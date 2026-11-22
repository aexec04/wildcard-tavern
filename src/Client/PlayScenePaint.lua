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
local PlayRoomArt = require(Engine:WaitForChild("PlayRoomArt"))
local TableSceneArt = require(Engine:WaitForChild("TableSceneArt"))
local ImageSpace = require(Engine:WaitForChild("ImageSpace"))
local Guard = require(script.Parent:WaitForChild("PlayPaintGuard"))

local PlayScenePaint = {}

function PlayScenePaint.install(deps)
	local root, handFrame, actionFrame = deps.root, deps.handFrame, deps.actionFrame
	local sidebarW = deps.SIDEBAR_WIDTH or R.SIDEBAR_W
	local okArt, art = pcall(function() return require(Engine:WaitForChild("PlaySceneArt")) end)
	local id = okArt and type(art) == "table" and art.play_table_front_b or nil
	if not id or id == "" then return { isPainted = function() return false end } end

	-- the painted tavern room behind the table (play_table_bg_b, an oval table in a candlelit room): cover-cropped over the whole screen,
	-- never stretched, directly under the table front (created first, same ZIndex, so it draws below it). No id: the old scene shows.
	local bgId = art.play_table_bg_b
	local bg = nil
	if bgId and bgId ~= "" then
		bg = Instance.new("ImageLabel")
		bg.Name = "PlayTableBg"
		bg.BackgroundTransparency = 1
		bg.BorderSizePixel = 0
		bg.Active = false
		bg.Image = bgId
		bg.ScaleType = Enum.ScaleType.Crop
		bg.Size = UDim2.fromScale(1, 1)
		bg.ZIndex = 0
		bg.Visible = false
		bg.Parent = root
	end

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
	local setKey = nil -- the Card Set id whose own painted front is showing (PlayTableLayout.SETS), nil for the default front
	local ovalArt = art[PlayTableLayout.SETS[PlayTableLayout.OVAL_KEY].art]
	-- the oval front's own groove rim, cut from the same picture and drawn above the cards so the rim overlaps their bottoms; it replaces
	-- the flat lip and the old PlayRailBack / PlayRailFront pieces, which are hidden while the oval front shows
	local groove = Instance.new("ImageLabel")
	groove.Name = "PlayGrooveLip"
	groove.BackgroundTransparency = 1
	groove.BorderSizePixel = 0
	groove.Active = false
	groove.Image = ovalArt or ""
	groove.ScaleType = Enum.ScaleType.Stretch
	groove.ZIndex = PlayRailLip.Z
	groove.Visible = false
	groove.Parent = root
	local function hasRim() -- the front has a rim crop to draw over the card bottoms (the oval front and every per-set room front)
		local def = setKey and PlayTableLayout.SETS[setKey]
		return def ~= nil and def.lip ~= nil
	end
	-- a per-Card-Set room is its painting alone: no wood front (the flat tan band), no groove rim, no deck recess box; a soft floor shadow
	-- under the hand keeps it legible (Engine/PlayTableLayout.showsFront, Client/PlayFloorShade)
	local floorShade = require(script.Parent.PlayFloorShade).install(root)
	local function frontShown() return PlayTableLayout.showsFront(setKey) end
	local function setLip(v) -- one place for lip visibility: the painted pieces replace the flat strip when present
		local oval = hasRim()
		lip.Visible = v and not rail and not oval
		if rail then rail.back.Visible = v and not oval; rail.front.Visible = v and not oval end
		groove.Visible = v and oval and frontShown()
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
	local lastReport = nil
	local lastFeltLine, lastHandLine = nil, nil
	-- A set with its own painted table (Mountain Festival, Frosted Garden) swaps the front picture and its measured rects; the art already
	-- carries the colour, so no tint goes on top. Any other set keeps the default front plus its tint, exactly as before.
	local function tint(skin)
		local sid = skin and skin.id
		local artKey = PlayTableLayout.artKeyOf(sid)
		local setId = artKey and art[artKey] and sid or nil
		-- the equipped or previewed Card Set's own room (Engine/PlayRoomArt): a complete recorded pair wins over any older painted front, and
		-- swaps live with the skin (this runs on equip, Preview start and Preview stop); anything else keeps the classic backdrop and front
		local room = PlayRoomArt.roomArt(sid, art)
		if room.layout and PlayTableLayout.SETS[room.layout] then
			setId, artKey = room.layout, room.front
		end
		if bg then
			local key, bid = PlayRoomArt.backdrop(sid, art, TableSceneArt)
			bg.Image = bid or bgId
			if root:GetAttribute("BossRound") then -- the set's own boss table picture (ThemeScenes); other sets keep the room they have
				local okB, bossId = pcall(function() return require(Engine:WaitForChild("ThemeScenes")).themeImageId(sid, "bossTableBackground") end)
				if okB and bossId then bg.Image = bossId end
			end
			if game:GetService("RunService"):IsStudio() then print(string.format("[PlayTableBg] key=%s id=%s", tostring(key), tostring(bg.Image))) end
		end
		-- default look: the wood-only oval front (play_table_front_c) when recorded and the tavern backdrop is there; else the old front
		local oval = (not setId) and bg and art[PlayTableLayout.SETS[PlayTableLayout.OVAL_KEY].art] or nil
		if oval then setId = PlayTableLayout.OVAL_KEY; artKey = PlayTableLayout.SETS[setId].art end
		local t = (not setId) and CosmeticSets.tableTintOf(sid) or nil
		image.Image = setId and art[artKey] or id
		groove.Image = setId and art[artKey] or ""
		-- a low contrast hint of the set's accent on the left board, the bottom plates and the Counter (never darker than TINT_FLOOR, so
		-- ink and cream text keep 4.5:1); the pieces read this attribute and follow it live
		local mult = PlayRoomArt.tint(CosmeticSets.accentOf(CosmeticSets.getById(sid)))
		root:SetAttribute("RoomTint", Color3.fromRGB(mult[1], mult[2], mult[3]))
		actionFrame:SetAttribute("RoomTint", Color3.fromRGB(mult[1], mult[2], mult[3]))
		image.ImageColor3 = t and c3(t.felt) or Color3.new(1, 1, 1)
		lip.BackgroundColor3 = t and c3(t.wood):Lerp(PlayRailLip.WOOD, 0.5) or PlayRailLip.WOOD
		if setKey ~= setId then
			setKey = setId
			if apply then apply() end
		end
		if game:GetService("RunService"):IsStudio() and lastReport ~= tostring(sid) then
			lastReport = tostring(sid)
			print(string.format("[PlayTableSet] %s front=%s art=%s bg=%s", tostring(sid or "default"), setId and "painted" or "default",
				tostring(setId and PlayTableLayout.SETS[setId] and PlayTableLayout.SETS[setId].art or "play_table_front_a"), tostring(room.bg)))
		end
	end
	HudTheme.onSkin(tint)
	tint(HudTheme.skin())
	root:GetAttributeChangedSignal("BossRound"):Connect(function() tint(HudTheme.skin()) end) -- boss rounds draw the set's boss table
	apply = function()
		local size = root.AbsoluteSize
		-- a per-Card-Set room keeps the hand 24 px right of the painted left board (the board is wider than the sidebar)
		local leftEdge = sidebarW + 20
		local roomSet = setKey and PlayTableLayout.SETS[setKey]
		if roomSet and (roomSet.room or setKey == PlayTableLayout.OVAL_KEY) then
			local bp = require(Engine:WaitForChild("PlayBoardLayout")).placement(size.X, size.Y)
			if bp then leftEdge = math.max(leftEdge, bp.x + bp.w + 24) end
		end
		if root:GetAttribute("BoardCollapsed") then leftEdge = 60 end -- the left board is slid away (Client/BoardDrawer): the hand uses the free width
		local p = loaded and PlayTableLayout.placement(size.X, size.Y, leftEdge, R.PILE_RESERVE, setKey) or nil
		if p then
			painted = true
			vignette(true)
			local m = p.map.image
			image.Position = UDim2.fromOffset(m.x, m.y)
			image.Size = UDim2.fromOffset(m.w, m.h)
			image.Visible = handFrame.Visible and frontShown()
			floorShade.setVisible(handFrame.Visible and not frontShown())
			if bg then bg.Visible = handFrame.Visible end
			local rim = p.map.lip -- the front's own rim, cropped from the same picture and drawn above the cards so it overlaps their bottoms
			local def = setKey and PlayTableLayout.SETS[setKey]
			if rim and def and def.lip then
				groove.Position = UDim2.fromOffset(rim.x, rim.y)
				groove.Size = UDim2.fromOffset(rim.w, rim.h)
				local rx, ry, rw, rh = ImageSpace.rect(def.lip.x, def.lip.y, def.lip.w, def.lip.h, PlayTableLayout.IMG_W, PlayTableLayout.IMG_H)
				groove.ImageRectOffset = Vector2.new(rx, ry)
				groove.ImageRectSize = Vector2.new(rw, rh)
			end
			local feltClip = handFrame.Visible and PlayMotion.clipFelt(p.map.felt, sidebarW + 20) or nil -- never under the left HUD
			-- the 14 per-Card-Set rooms carry their own painted lighting: the felt shade (a green grain, edge and corner glows clipped to the
			-- felt RECT) showed as a hard-edged band where that rect leaves the room's oval (golden_gala, y 325 to 335 at 1920x957), so it is
			-- off in every room; only the classic backdrop keeps it
			local roomDef = setKey and PlayTableLayout.SETS[setKey]
			if roomDef and roomDef.room then feltClip = nil end
			shade.apply(feltClip, feltClip ~= nil and feltClip.x > p.map.felt.x)
			shade.setFill(PlayTableLayout.fillOf(setKey))
			if game:GetService("RunService"):IsStudio() and setKey then
				local f = p.map.felt
				print(string.format("[PlayTableSet] felt=%d,%d,%d,%d visible=%s", math.floor(f.x), math.floor(f.y), math.floor(f.w), math.floor(f.h), tostring(feltClip ~= nil)))
			end
			handFrame:SetAttribute("PaintedRail", true) -- CardFace hides its code-drawn tray
			-- the Concept T screen owns the hand and the Actions row while it is up: two writers made the click targets drift off the art
			local ctOwns = false
			pcall(function() ctOwns = require(script.Parent.ConceptTPlay).isActive() end)
			if not ctOwns then
			handFrame.Position = UDim2.fromOffset(p.hand.x, p.hand.y)
			handFrame.Size = UDim2.fromOffset(p.hand.w, p.hand.h)
			end
			do
				local HS = require(Engine:WaitForChild("HandSizing"))
				handFrame:SetAttribute("MaxCardWidth", HS.maxCardWidth(size.X))
				if game:GetService("RunService"):IsStudio() then
					local cw, ch = HS.cardSize(size.X, p.hand.w, p.hand.h, 8)
					warn(string.format("[HandSize] screen %d, card %d x %d, step %d, overlap %d%%, fan %d (%d%% of width), frame %d x %d", size.X, cw, ch, cw + HS.gap(size.X, cw, 8), math.floor(HS.overlapFor(8) * 100), HS.fanSpan(size.X, cw, 8), math.floor(100 * HS.fanSpan(size.X, cw, 8) / size.X), p.hand.w, p.hand.h))
				end
			end
			if not ctOwns then
			actionFrame.Position = UDim2.fromOffset(p.actions.x, p.actions.y)
			actionFrame.Size = UDim2.fromOffset(p.actions.w, p.actions.h)
			end
			plates(p)
			if game:GetService("RunService"):IsStudio() then
				task.delay(1.2, function() pcall(function() require(script.Parent.PlayBoardHud).reportOverlaps(root) end) end) -- [PlateOverlap] in the Output
			end
			deck(frontShown() and p.map.deck or nil) -- no painted recess box in a room: the deck pile sits directly on the painting
			watchCovers()
			PlayRailLip.apply(lip, p, lipShown())
			PlayRail.apply(rail, p, lipShown())
			if rail then lip.Visible = false end
			setLip(lipShown()) -- the groove rim follows the current room (it kept the previous table's visibility before)
			if not frontShown() then -- a room has no rail in its painting: no flat tan strip, no groove strip, no painted tray pieces
				lip.Visible = false
				groove.Visible = false
				if rail then rail.back.Visible = false; rail.front.Visible = false end
			end
		elseif painted then
			deck(nil)
			-- leaving the painted layout: back to the flat one (a narrow window is then handled by CompactLayout)
			painted = false
			vignette(false)
			image.Visible = false
			floorShade.setVisible(false)
			if bg then bg.Visible = false end
			shade.apply(nil)
			groove.Visible = false
			PlayRailLip.apply(lip, nil)
			PlayRail.apply(rail, nil)
			handFrame:SetAttribute("PaintedRail", nil)
			plates(nil)
			if size.X >= PlayTableLayout.MIN_W then
				handFrame.Position = UDim2.new(0, sidebarW + 20, 1, -272)
				handFrame.Size = UDim2.new(1, -(sidebarW + 40 + R.PILE_RESERVE), 0, 176) -- flat layout keeps its own height
				actionFrame.Position = UDim2.new(0, sidebarW + 20, 1, -80)
				actionFrame.Size = UDim2.new(1, -(sidebarW + 40 + R.PILE_RESERVE), 0, R.ACTION_H)
			end
		end
	end

	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	root:GetAttributeChangedSignal("BoardCollapsed"):Connect(function() if apply then apply() end end)
	-- The game owns HandFrame, Actions and DeckWidget visibility; this module only follows it (never sets it)
	handFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if painted then
			image.Visible = handFrame.Visible and frontShown()
			floorShade.setVisible(handFrame.Visible and not frontShown())
			if bg then bg.Visible = handFrame.Visible end
			shade.frame.Visible = handFrame.Visible
			setLip(lipShown())
		end
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
