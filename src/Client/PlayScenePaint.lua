--[[
	Client/PlayScenePaint.lua
	The painted play table (art key play_table_front_b): a bottom anchored, full width, never stretched foreground above the
	scene and below the hand and every other UI, with the hand row standing on its rail groove and the Actions row on the
	wooden front. Numbers come from Engine/PlayTableLayout (pure, tested). Gameplay logic, keys and hit areas are untouched:
	only the position of HandFrame and Actions changes, and only while the picture has loaded and the window is at least
	900 px wide. Anything else (no id, load failure, phone) leaves the old layout and the code-drawn hand tray as they are.

	install{ root, handFrame, actionFrame, SIDEBAR_WIDTH } -> { isPainted() }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PlayTableLayout = require(Engine:WaitForChild("PlayTableLayout"))
local R = require(Engine:WaitForChild("ResponsiveLayout"))
local ImagePreload = require(Engine:WaitForChild("ImagePreload"))
local Guard = require(script.Parent:WaitForChild("PlayPaintGuard"))

local PlayScenePaint = {}

function PlayScenePaint.install(deps)
	local root, handFrame, actionFrame = deps.root, deps.handFrame, deps.actionFrame
	local sidebarW = deps.SIDEBAR_WIDTH or R.SIDEBAR_W
	local okArt, art = pcall(function() return require(Engine:WaitForChild("PlaySceneArt")) end)
	local id = okArt and type(art) == "table" and art.play_table_front_b or nil
	if not id or id == "" then return { isPainted = function() return false end } end

	local image = Instance.new("ImageLabel")
	image.Name = "PlayTableFront"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Active = false
	image.Image = id
	image.ScaleType = Enum.ScaleType.Stretch -- the rect already has the picture's own aspect (PlayTableLayout.map)
	image.ZIndex = 0 -- created after the scene stack and TableLook, so it draws above them; hand and HUD are >= 1
	image.Visible = false
	image.Parent = root

	local loaded, painted = false, false
	local PlayMotion = require(Engine:WaitForChild("PlayMotion"))
	local shade = require(script.Parent.PlayFeltShade).install(root, art) -- corner darkening and felt grain, over the felt rect only
	local platesId = art.play_plates_b
	local PlayPlates = require(script.Parent.PlayPlates)
	local function plates(p)
		Guard.run("plates", PlayPlates.apply, actionFrame, p, platesId) -- a failure leaves the flat buttons (warned once)
	end

	local PlayDeckPaint = require(script.Parent.PlayDeckPaint)
	local function deck(rect) -- the deck widget inside the painted recess (step D2); nil puts it back
		if deps.deckWidget then Guard.run("deck", PlayDeckPaint.apply, deps.deckWidget, rect, platesId) end
	end

	-- the painted table has its own shading: the TableLook edge vignettes would show as a hard dark strip on it
	-- GameRoot.EdgeShadow (the old sidebar's right-edge shadow, Sidebar.lua) is the same kind of strip: bisected in Studio as the
	-- dark band over the felt at x 0 to 240 on the painted table, so it goes too and comes back with the old sidebar
	local function vignette(hidden)
		local edge = root:FindFirstChild("EdgeShadow")
		if edge then edge.Visible = not hidden end
		local layers = root:FindFirstChild("TableLookLayers")
		if not layers then return end
		for _, c in ipairs(layers:GetChildren()) do
			if c:IsA("GuiObject") and string.sub(c.Name, 1, 9) == "Vignette_" then c.Visible = not hidden end
		end
	end

	local PlayRailLip = require(script.Parent.PlayRailLip)
	local lip = PlayRailLip.install(root)
	local PlayRail = require(script.Parent.PlayRail)
	local rail = PlayRail.install(root, art) -- nil until both rail Image ids exist: the flat lip stays
	local function setLip(v) -- one place for lip visibility: the painted pieces replace the flat strip when present
		lip.Visible = v and not rail
		if rail then rail.back.Visible = v; rail.front.Visible = v end
	end
	-- the equipped or previewed Card Set may tint the table (felt on the picture, wood on the rail lip); HudTheme calls this on equip,
	-- Preview start and Preview stop, and a set without a tint puts the painted colours back exactly
	local CosmeticSets = require(Engine:WaitForChild("CosmeticSets"))
	local HudTheme = require(script.Parent.HudTheme)
	local function covered() -- any full-screen scene over the table (Counter, Round Select, Game Over)
		for _, name in ipairs(PlayRailLip.COVERS) do
			local c = root:FindFirstChild(name)
			if c and c:IsA("GuiObject") and c.Visible then return true end
		end
		return false
	end
	local function lipShown() return PlayRailLip.shouldShow(handFrame.Visible, covered()) end
	local watched = {}
	local function watchCovers()
		for _, name in ipairs(PlayRailLip.COVERS) do
			local c = root:FindFirstChild(name)
			if c and c:IsA("GuiObject") and not watched[c] then
				watched[c] = true
				c:GetPropertyChangedSignal("Visible"):Connect(function()
					if painted then setLip(lipShown()) end
				end)
			end
		end
	end
	local function c3(t) return Color3.fromRGB(t[1], t[2], t[3]) end
	local apply -- assigned below
	local setKey = nil -- the Card Set id whose own painted front is showing (PlayTableLayout.SETS), nil for the default front
	local lastReport = nil
	-- A set with its own painted table (Mountain Festival, Frosted Garden) swaps the front picture and its measured rects; the art already
	-- carries the colour, so no tint goes on top. Any other set keeps the default front plus its tint, exactly as before.
	local function tint(skin)
		local sid = skin and skin.id
		local artKey = PlayTableLayout.artKeyOf(sid)
		local setId = artKey and art[artKey] and sid or nil
		local t = (not setId) and CosmeticSets.tableTintOf(sid) or nil
		image.Image = setId and art[artKey] or id
		image.ImageColor3 = t and c3(t.felt) or Color3.new(1, 1, 1)
		lip.BackgroundColor3 = t and c3(t.wood):Lerp(PlayRailLip.WOOD, 0.5) or PlayRailLip.WOOD
		if setKey ~= setId then
			setKey = setId
			if apply then apply() end
		end
		if game:GetService("RunService"):IsStudio() and lastReport ~= tostring(sid) then
			lastReport = tostring(sid)
			print(string.format("[PlayTableSet] %s front=%s", tostring(sid or "default"), setId and "painted" or "default"))
		end
	end
	HudTheme.onSkin(tint)
	tint(HudTheme.skin())
	apply = function()
		local size = root.AbsoluteSize
		local p = loaded and PlayTableLayout.placement(size.X, size.Y, sidebarW + 20, R.PILE_RESERVE, setKey) or nil
		if p then
			painted = true
			vignette(true)
			local m = p.map.image
			image.Position = UDim2.fromOffset(m.x, m.y)
			image.Size = UDim2.fromOffset(m.w, m.h)
			image.Visible = handFrame.Visible
			local feltClip = handFrame.Visible and PlayMotion.clipFelt(p.map.felt, sidebarW + 20) or nil -- never under the left HUD
			shade.apply(feltClip, feltClip ~= nil and feltClip.x > p.map.felt.x)
			handFrame:SetAttribute("PaintedRail", true) -- CardFace hides its code-drawn tray
			handFrame.Position = UDim2.fromOffset(p.hand.x, p.hand.y)
			handFrame.Size = UDim2.fromOffset(p.hand.w, p.hand.h)
			actionFrame.Position = UDim2.fromOffset(p.actions.x, p.actions.y)
			actionFrame.Size = UDim2.fromOffset(p.actions.w, p.actions.h)
			plates(p)
			deck(p.map.deck)
			watchCovers()
			PlayRailLip.apply(lip, p, lipShown())
			PlayRail.apply(rail, p, lipShown())
			if rail then lip.Visible = false end
		elseif painted then
			deck(nil)
			-- leaving the painted layout: back to the flat one (a narrow window is then handled by CompactLayout)
			painted = false
			vignette(false)
			image.Visible = false
			shade.apply(nil)
			PlayRailLip.apply(lip, nil)
			PlayRail.apply(rail, nil)
			handFrame:SetAttribute("PaintedRail", nil)
			plates(nil)
			if size.X >= PlayTableLayout.MIN_W then
				handFrame.Position = UDim2.new(0, sidebarW + 20, 1, -272)
				handFrame.Size = UDim2.new(1, -(sidebarW + 40 + R.PILE_RESERVE), 0, 176)
				actionFrame.Position = UDim2.new(0, sidebarW + 20, 1, -80)
				actionFrame.Size = UDim2.new(1, -(sidebarW + 40 + R.PILE_RESERVE), 0, R.ACTION_H)
			end
		end
	end

	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	-- The game owns HandFrame, Actions and DeckWidget visibility; this module only follows it (never sets it)
	handFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if painted then image.Visible = handFrame.Visible; shade.frame.Visible = handFrame.Visible; setLip(lipShown()) end
	end)
	-- CompactLayout re-applies its own numbers on viewport changes; put the painted ones back right after
	handFrame:GetPropertyChangedSignal("Position"):Connect(apply)
	handFrame:GetPropertyChangedSignal("Size"):Connect(apply)
	actionFrame:GetPropertyChangedSignal("Position"):Connect(apply)

	task.spawn(function()
		-- IsLoaded reads false for a Visible = false label in Studio, so trust the PreloadAsync status instead
		loaded = ImagePreload.run(ContentProvider, image, Enum.AssetFetchStatus.Success)
		if loaded then apply() end
	end)

	return { isPainted = function() return painted end }
end

return PlayScenePaint
