--[[
	Client/SeasonPreviewView.lua
	The small popup for one Season tier (words and sizes in Engine/SeasonPreview, tested): the reward art and name, one status line, a Claim
	plate when the tier is ready, and Close. It wears the equipped Card Set (paper fill, edge and 7:1 ink from CosmeticSets.popupStyleOf,
	plates from TavernKit); classic keeps dark wood and cream. Escape and a tap on the dark area close it. No tween, so Calm mode and
	Reduce motion need nothing extra. Claiming goes through the same ClaimSeason remote the tile used to call; the server owns the rules.

	SeasonPreviewView.init(deps) -> { show(row, view), hide(), isOpen() }
	deps: screenGui, polishPanel, polishButton, playClickSfx, rewardArt(reward) -> category, key, emoji, onClaim(tier)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Words = require(Engine:WaitForChild("SeasonPreview"))

local CREAM = Color3.fromRGB(250, 240, 220)
local GOLD = Color3.fromRGB(222, 182, 104)
local WOOD = Color3.fromRGB(86, 58, 34)

local SeasonPreviewView = {}

local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

function SeasonPreviewView.init(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local ArtIcon = require(script.Parent.ArtIcon)

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "SeasonPreviewBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 70
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.Name = "SeasonPreviewPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.Active = true -- a tap on the panel is not a tap on the dark area
	panel.ZIndex = 71
	panel.Parent = backdrop
	deps.polishPanel(panel, 14, "wood")

	local function text(name, size, font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Font = font or Enum.Font.Merriweather
		l.TextSize = size
		l.TextColor3 = CREAM
		l.TextWrapped = true
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.ZIndex = 73
		l.Parent = panel
		return l
	end
	local heading = text("Heading", 18)
	local well = Instance.new("Frame")
	well.Name = "Art"
	well.BackgroundColor3 = WOOD
	well.BorderSizePixel = 0
	well.ZIndex = 72
	well.Parent = panel
	deps.polishPanel(well, 10, "wood")
	local glyph = Instance.new("TextLabel")
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.BackgroundTransparency = 1
	glyph.Font = Enum.Font.GothamBold
	glyph.TextSize = 40
	glyph.TextColor3 = CREAM
	glyph.ZIndex = 73
	glyph.Parent = well
	local title = text("RewardName", 18)
	local status = text("Status", 16, Enum.Font.Merriweather)
	title.TextYAlignment = Enum.TextYAlignment.Top
	status.TextYAlignment = Enum.TextYAlignment.Top

	local function plate(name, label, kind)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Font = Enum.Font.Merriweather
		b.TextSize = 18
		b.Text = label
		b.TextColor3 = CREAM
		b.BackgroundColor3 = kind == "primary" and Color3.fromRGB(86, 140, 80) or Color3.fromRGB(110, 70, 40)
		b.ZIndex = 73
		b.Parent = panel
		deps.polishButton(b, 10)
		pcall(function() require(script.Parent.TavernKit).setPlateButton(b, kind) end) -- the set plate; classic keeps the flat colour
		return b
	end
	local claim = plate("Claim", Words.CLAIM, "primary")
	local close = plate("Close", Words.CLOSE, "secondary")

	local current -- the tier being shown
	local function skin()
		local paper, edge
		pcall(function()
			local CS = require(Engine:WaitForChild("CosmeticSets"))
			local s = CS.popupStyleOf(require(script.Parent.TavernKit).plateSetId())
			if s and s.paper then paper, edge = s.paper, s.edge or s.paper.edge end
		end)
		local stroke = panel:FindFirstChildOfClass("UIStroke")
		if paper then
			-- dark ink (7:1) on the set's paper, the same pair the Season tiles use
			panel.BackgroundColor3 = rgb(paper.top)
			if stroke and paper.edge then stroke.Color = rgb(paper.edge) end
			local ink = rgb(paper.ink)
			heading.TextColor3, title.TextColor3, status.TextColor3 = ink, ink, ink
		else
			panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
			if stroke then stroke.Color = GOLD end
			heading.TextColor3, title.TextColor3, status.TextColor3 = GOLD, CREAM, CREAM
		end
	end

	local function place(r, inst)
		inst.Position = UDim2.fromOffset(r.x, r.y)
		inst.Size = UDim2.fromOffset(r.w, r.h)
	end

	local api = {}
	local open = false

	function api.hide()
		if not open then return end
		open = false
		current = nil
		backdrop.Visible = false
	end
	function api.isOpen() return open end

	function api.show(row, view)
		local words = Words.of(row, view)
		local size = deps.screenGui.AbsoluteSize
		local L = Words.layout(math.max(1, size.X), math.max(1, size.Y))
		panel.Size = UDim2.fromOffset(L.panel.w, L.panel.h)
		place(L.heading, heading); place(L.art, well); place(L.title, title); place(L.status, status)
		place(L.claim, claim); place(L.close, close)
		heading.Text, title.Text, status.Text = words.heading, words.title, words.status
		heading.TextXAlignment, title.TextXAlignment, status.TextXAlignment = Enum.TextXAlignment.Center, Enum.TextXAlignment.Center, Enum.TextXAlignment.Center
		claim.Visible = words.canClaim
		-- the reward art, with the emoji when no picture is registered
		for _, child in ipairs(well:GetChildren()) do
			if child:IsA("ImageLabel") then child:Destroy() end
		end
		local category, key, emoji = deps.rewardArt(row and row.reward)
		glyph.Text = emoji or ""
		glyph.TextTransparency = 0
		if category then
			pcall(ArtIcon.apply, well, category, key, glyph, { cornerRadius = 10, zIndex = 74 })
		end
		skin()
		current = words.tier
		open = true
		backdrop.Visible = true
	end

	claim.MouseButton1Click:Connect(function()
		if not open or not current then return end
		local tier = current
		api.hide()
		if deps.onClaim then deps.onClaim(tier) end
	end)
	close.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		api.hide()
	end)
	OverlayManager.register("season-preview", api.hide)
	pcall(function()
		require(script.Parent.PopupDismiss).attach(backdrop, { id = "season-preview", panel = panel, button = true })
	end)
	return api
end

return SeasonPreviewView
