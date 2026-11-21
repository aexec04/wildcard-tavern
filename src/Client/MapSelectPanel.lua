--[[
	Client/MapSelectPanel.lua
	The selected-location panel at the lower left of the Tavern Map (dark wood and gold): the location picture on the left, its name, its type
	with an icon, one line of description, the Target score when it is a fight, and a green Continue. Rules and rects: Engine/MapSelectRules.

	MapSelectPanel.new{ parent, PatronPlaque, onContinue } -> { show(desc, artId, icon), hide(), layout(frame size), setMode(mode), mode(), panel }
	  show(desc, ...)   desc from MapSelectRules.describe; the panel updates in place
	  layout(w, h)      places the panel in the lower left zone (MapHeaderRules.panelZone) in its current mode
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("MapSelectRules"))
local HeaderRules = require(Engine:WaitForChild("MapHeaderRules"))
local NodeRules = require(Engine:WaitForChild("MapNodeRules"))
local TavernKit = require(script.Parent.TavernKit)
local ButtonLabelTop = require(script.Parent.ButtonLabelTop)

local MapSelectPanel = {}

local CREAM = Color3.fromRGB(250, 240, 220)
local GOLD_TXT = Color3.fromRGB(255, 205, 90)

local function put(inst, r)
	inst.Position = UDim2.fromOffset(r.x, r.y)
	inst.Size = UDim2.fromOffset(r.w, r.h)
end

local function label(parent, name, size, font)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = CREAM
	l.TextTransparency = 0
	l.TextStrokeTransparency = 0.8
	l.TextStrokeColor3 = Color3.fromRGB(20, 12, 6)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextWrapped = false
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.RichText = true
	l.Active = false
	l.ZIndex = 49
	l.Parent = parent
	return l
end

function MapSelectPanel.new(deps)
	local panel = TavernKit.plate(deps.parent, UDim2.fromOffset(320, 130))
	panel.Name = "SelectPanel"
	panel.ZIndex = 47 -- above every map layer (decor 40, compass 44 to 47), under the hover card (60)
	panel.Visible = false
	panel.Active = true -- a click on the panel never falls through to the map
	-- A plain carved wood panel: the 9-sliced ornate art put its swirl on one end and the text over it, so the trim is a 3 px gold line
	-- plus four small gold corner studs, and every part sits inside a clear padded inner rect (MapSelectRules.PAD)
	for i, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		local stud = Instance.new("Frame")
		stud.Name = "Stud" .. i
		stud.AnchorPoint = Vector2.new(0.5, 0.5)
		stud.Position = UDim2.new(c[1], c[1] == 0 and 7 or -7, c[2], c[2] == 0 and 7 or -7)
		stud.Size = UDim2.fromOffset(9, 9)
		stud.Rotation = 45
		stud.BackgroundColor3 = Color3.fromRGB(226, 182, 88)
		stud.BorderSizePixel = 0
		stud.Active = false
		stud.ZIndex = 48
		stud.Parent = panel
	end
	-- dark carved wood with gold trim, like the header (a lighter wood band across the top, Color only gradient)
	panel.BackgroundColor3 = Color3.fromRGB(150, 104, 62) -- the lighter wood outer frame, 10 px wide round the dark inset
	panel.BackgroundTransparency = 0
	do
		local shade = panel:FindFirstChild("Shade")
		if shade then shade.Color = ColorSequence.new(Color3.fromRGB(172, 124, 76), Color3.fromRGB(128, 88, 52)) end
		local trimStroke = panel:FindFirstChildOfClass("UIStroke")
		if trimStroke then
			trimStroke.Color = Color3.fromRGB(52, 34, 20)
			trimStroke.Thickness = 2
			trimStroke.Transparency = 0
		end
	end

	-- the painted carved wood frame (map_paint frame_panel), 9-sliced behind everything; the drawn studs and line step aside when it loads
	do
		local id = deps.frameArt and deps.frameArt()
		if id then
			local fr = Instance.new("ImageLabel")
			fr.Name = "PanelFrame"
			fr.BackgroundTransparency = 1
			fr.Image = id
			fr.ScaleType = Enum.ScaleType.Slice
			fr.SliceCenter = Rect.new(170, 170, 854, 854)
			fr.SliceScale = 0.09 -- 15 px of carved border, inside the 16 px clear padding the content keeps
			fr.Size = UDim2.fromScale(1, 1)
			fr.Active = false
			fr.ZIndex = 47
			fr.Parent = panel
		end
	end
	-- dark brown wood fill (never black) inside the 10 px lighter frame, with a 3 px warm gold inner line; the corner studs stay on top
	do
		local inset = Instance.new("Frame")
		inset.Name = "Inset"
		inset.Position = UDim2.fromOffset(10, 10)
		inset.Size = UDim2.new(1, -20, 1, -20)
		inset.BackgroundColor3 = Color3.fromRGB(88, 58, 34)
		inset.BorderSizePixel = 0
		inset.Active = false
		inset.ZIndex = 47
		inset.Parent = panel
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(226, 182, 88)
		s.Thickness = 3
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = inset
	end

	local art = Instance.new("Frame")
	art.Name = "Art"
	art.BackgroundColor3 = Color3.fromRGB(70, 52, 34)
	art.BorderSizePixel = 0
	art.Active = false
	art.ZIndex = 48
	art.Parent = panel
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = art
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(176, 138, 66)
		s.Thickness = 2
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = art
	end
	local icon = label(art, "Icon", 30, Enum.Font.GothamBold)
	icon.Size = UDim2.fromScale(1, 1)
	icon.TextXAlignment = Enum.TextXAlignment.Center
	icon.RichText = false

	local name = label(panel, "Name", 18, Enum.Font.GothamBlack)
	local typeRow = label(panel, "Type", 15)
	local line = label(panel, "Line", 14, Enum.Font.Gotham)
	line.TextColor3 = Color3.fromRGB(236, 224, 200)
	line.TextWrapped = true -- the description shows two full lines, never a cut word
	line.TextYAlignment = Enum.TextYAlignment.Top
	local target = label(panel, "Target", 16)
	local go = TavernKit.primaryButton(panel, "Continue")
	go.Name = "Continue"
	go.ZIndex = 49
	go.Activated:Connect(function()
		if go:GetAttribute("Enabled") and deps.onContinue then deps.onContinue() end
	end)
	local tabToggle = Instance.new("TextButton") -- in tab mode a click opens the panel again
	tabToggle.Name = "TabToggle"
	tabToggle.BackgroundTransparency = 1
	tabToggle.Text = ""
	tabToggle.Size = UDim2.fromScale(1, 1)
	tabToggle.ZIndex = 50
	tabToggle.Visible = false
	tabToggle.Parent = panel

	local self = { panel = panel }
	local current = nil -- { desc, artId, iconText }
	local mode = "full"
	local zone = { x = 12, y = 300, w = 320, h = 130 }
	local artImage

	local function apply()
		if not current then return end
		local r = Rules.rects(zone, mode)
		local pr = Rules.panelRect(zone, mode)
		panel.Position = UDim2.fromOffset(pr.x, pr.y)
		panel.Size = UDim2.fromOffset(pr.w, pr.h)
		local d = current.desc
		local tag = NodeRules.tagFor(d.typeId)
		local tc = Color3.fromRGB(tag.color[1], tag.color[2], tag.color[3])
		art.Visible = mode == "full"
		typeRow.Visible, line.Visible = mode == "full", mode == "full"
		target.Visible = mode == "full" and d.target ~= nil
		tabToggle.Visible = mode == "tab"
		go.Visible = mode ~= "tab" and d.button.visible
		go.Active = d.button.enabled
		go:SetAttribute("Enabled", d.button.enabled)
		go.Text = d.button.text
		go.AutoButtonColor = false
		-- bright green when the node can be entered, a muted brown when it cannot
		local cc = Rules.CONTINUE
		local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end
		local base = d.button.enabled and rgb(cc.fill) or rgb(cc.offFill)
		go.BackgroundColor3 = base
		local goShade = go:FindFirstChild("Shade")
		if goShade then goShade.Color = ColorSequence.new(base:Lerp(Color3.new(1, 1, 1), 0.12), base:Lerp(Color3.new(0, 0, 0), 0.12)) end
		-- cream 24 px bold word on the plate, gold trim; the same green family as the table Play Hand button, grey when it cannot be entered
		go.Font = Enum.Font.GothamBold
		local ts = r.button and math.min(24, r.button.h - 8) or 24
		go.TextSize = ts
		go.TextColor3 = d.button.enabled and rgb(cc.text) or rgb(cc.offText)
		go.TextTransparency = 0
		go.TextStrokeTransparency = 0 -- dark outline so the cream word reads on the green plate
		go.TextStrokeColor3 = rgb(cc.stroke)
		local goStroke = go:FindFirstChildOfClass("UIStroke")
		if goStroke then goStroke.Thickness = 2 end
		if goStroke then goStroke.Color = d.button.enabled and rgb(cc.edge) or Color3.fromRGB(130, 120, 100) end
		-- The kit's Shade UIGradient sits on the button and MULTIPLIES the button's own text colour, so a cream word drawn by the button
		-- itself reads dark green while its TextColor3 still says cream (Nov 21 live check). A child label is not tinted by its parent's
		-- gradient, so the word is always drawn by an owned KitLabel, created here when the sweep never made one.
		local kl = go:FindFirstChild("KitLabel")
		if not (kl and kl:IsA("TextLabel")) then
			kl = ButtonLabelTop.own(go, d.button.text, ts, go.ZIndex + 3, go.TextColor3)
			go.Text = d.button.text -- own() blanks the button text; the hit box keeps the word for code that reads it
		end
		if kl and kl:IsA("TextLabel") then
			-- the Continue word is OWNED by this label: the kit's mirror (button properties copied onto the label after every write)
			-- can no longer repaint it, so the cream colour and the solid dark outline are what is drawn
			kl:SetAttribute("OwnLabel", true)
			kl.Text = d.button.text
			kl.TextColor3, kl.TextSize, kl.Font = go.TextColor3, ts, Enum.Font.GothamBold
			kl.TextTransparency, kl.TextStrokeTransparency = 0, 0
			kl.TextStrokeColor3 = rgb(cc.stroke)
			kl.Visible = true
			go.TextTransparency, go.TextStrokeTransparency = 1, 1 -- the button keeps its Text as the hit box; the label draws the word once
		end
		name.Text = d.name
		if mode == "tab" then
			name.Text = d.name .. "  (tap)"
		end
		put(name, r.name)
		name.TextSize = mode == "tab" and 14 or 18
		if mode == "full" then
			put(art, r.art)
			put(typeRow, r.type)
			put(line, r.line)
			put(target, r.target)
			typeRow.TextColor3 = tc
			typeRow.Text = d.typeIcon .. " " .. (d.status and (d.typeText .. "  |  " .. d.status) or d.typeText)
			line.Text = d.line
			if d.target then
				target.Text = string.format('Target: <font color="#ffcd5a">%d</font>', math.floor(d.target))
			end
			icon.Text = current.iconText or ""
			icon.Visible = artImage == nil
		end
		if mode ~= "tab" and d.button.visible then put(go, r.button) end
	end

	function self.show(desc, artId, iconText)
		current = { desc = desc, artId = artId, iconText = iconText }
		if artImage then artImage:Destroy() artImage = nil end
		if deps.PatronPlaque and artId then
			artImage = deps.PatronPlaque.applyById(art, artId, { emojiLabel = icon, zIndex = 49, cornerRadius = 8 })
		end
		panel.Visible = true
		apply()
	end

	function self.hide()
		panel.Visible = false
		current = nil
	end

	function self.layout(sw, sh)
		zone = HeaderRules.layout(sw, sh).panelZone
		apply()
	end

	function self.zone() return zone end
	function self.mode() return mode end
	function self.setMode(m)
		if m == mode then return end
		mode = m
		apply()
	end
	function self.rect() return Rules.panelRect(zone, mode) end
	tabToggle.Activated:Connect(function() self.setMode("full") end)

	return self
end

return MapSelectPanel
