--[[
	Client/Gameplay2.lua
	Gameplay v2, the rebuilt table screen (flag GAMEPLAY_V2, default on; the Concept T table is GAMEPLAY_V1, archived and still
	openable). New pieces are drawn with Client/TavernKit (plates, pills, gold box) over the candlelit table scene
	(Engine/TableSceneArt). Rects come from ONE pure function, Engine/Gameplay2Layout.rects, so layout and tests share it.

	No separate hit frames anywhere: Play Hand and Discard are the real buttons from the hub, restyled by TavernKit.skin and
	moved onto their rect, the Rank | Suit control and the deck click catcher are the real instances moved the same way. Server logic,
	scoring and remotes are untouched, as are PopupShield and InputGuard (the buttons keep every handler).
	Active only in phase "playing" on screens of at least 640 x 360.

	install{ root, handFrame, actionFrame, playButton, discardButton, deckWidget, selectedCount, firstCard, cards } -> { update(state), isActive() }
	Studio only: [ClickCheck] lines compare each control's real rect with its layout rect and warn above 4 px.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("Gameplay2Layout"))
local Moments = require(Engine:WaitForChild("Gameplay2Moments"))
local PreviewRules = require(Engine:WaitForChild("Gameplay2Preview"))
local ClientSettings = require(script.Parent.ClientSettings)
local CTLayout = require(Engine:WaitForChild("ConceptTLayout"))
local Flags = require(Engine:WaitForChild("FeatureFlags"))
local TableArt = require(Engine:WaitForChild("TableSceneArt"))
local Art = require(Engine:WaitForChild("ConceptTArt"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local DeckCountText = require(Engine:WaitForChild("DeckCountText"))
local PlayMotion = require(Engine:WaitForChild("PlayMotion"))
local Kit = require(script.Parent.TavernKit)
local LayoutSwitch = require(script.Parent.LayoutSwitch)

local M = {}
local current = nil

-- the old play screen pieces this screen hides while it is up (same list the Concept T screen hid)
local HIDE = { "Sidebar", "SidebarBoard", "EdgeShadow", "PlayBoardPaint", "PlayBoardPaintBand", "PlayBoardPaintCap", "PlayBoardFiller", "BlessingChip", "PlayFeltShade", "PlayTableFront", "PlayTableBg", "PlayFloorShade", "HandRailLip", "PlayGrooveLip", "PlayRailBack", "PlayRailFront" }

local function place(g, r)
	g.Position = UDim2.fromOffset(r.x, r.y)
	g.Size = UDim2.fromOffset(r.w, r.h)
end

-- Under ZIndexBehavior.Global a child at the default ZIndex 1 is painted UNDER its parent's plate (that hid every pill and box
-- label). Put the piece and everything inside it at z, text one higher.
local function raise(inst, z)
	inst.ZIndex = z
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("GuiObject") then d.ZIndex = z + 1 end
	end
end

local function setText(box, text)
	local t = box:FindFirstChild("Value") or box:FindFirstChild("Word")
	if t and t.Text ~= text then t.Text = text end
	return t
end

function M.install(deps)
	local root = deps.root
	local layer = Instance.new("Frame")
	layer.Name = "Gameplay2"
	layer.BackgroundColor3 = Color3.fromRGB(Style.rgb("plateDark")[1], Style.rgb("plateDark")[2], Style.rgb("plateDark")[3]) -- plain dark brown until the scene loads
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 1
	layer.Visible = false
	layer.Active = false
	layer.Parent = root

	local scene = Instance.new("ImageLabel")
	scene.Name = "Scene"
	scene.BackgroundTransparency = 1
	scene.BorderSizePixel = 0
	scene.Active = false
	scene.Size = UDim2.fromScale(1, 1)
	scene.ScaleType = Enum.ScaleType.Crop
	scene.ZIndex = 1
	scene.Image = TableArt.table_play_ref or TableArt.table_play or "" -- the reference tavern (four banners, shelves, fireplace); the older scene is the fallback
	scene.Parent = layer
	scene.ImageColor3 = Color3.fromRGB(217, 217, 217) -- about 15 percent darker, so the shelves and banners stop competing with the Patron seats
	do -- soft dark vignette: stepped nested edge bands (no UIGradient.Transparency), darkest at the rim, nothing in the middle, static so Calm mode is the same
		local vig = Instance.new("Frame"); vig.Name = "SceneVignette"; vig.BackgroundTransparency = 1; vig.BorderSizePixel = 0; vig.Active = false
		vig.Size = UDim2.fromScale(1, 1); vig.ZIndex = 2; vig.Parent = layer
		local STEPS, DEPTH = 8, 0.22 -- eight bands, together 22 percent of the width and of the height per side
		for i = 1, STEPS do
			local tr = 0.92 -- the bands are nested and stack: the rim gets all eight (about 0.5 transparent), the inner edge one (0.92), the middle none
			for _, side in ipairs({ "T", "B", "L", "R" }) do
				local f = Instance.new("Frame"); f.Name = "VigBand" .. side .. i; f.BorderSizePixel = 0; f.Active = false
				f.BackgroundColor3 = Color3.fromRGB(10, 6, 14); f.BackgroundTransparency = tr; f.ZIndex = 2
				local w = DEPTH * (STEPS - i + 1) / STEPS
				if side == "T" then f.Size = UDim2.fromScale(1, w); f.Position = UDim2.fromScale(0, 0)
				elseif side == "B" then f.Size = UDim2.fromScale(1, w); f.Position = UDim2.fromScale(0, 1 - w)
				elseif side == "L" then f.Size = UDim2.fromScale(w, 1); f.Position = UDim2.fromScale(0, 0)
				else f.Size = UDim2.fromScale(w, 1); f.Position = UDim2.fromScale(1 - w, 0) end
				f.Parent = vig
			end
		end
	end

	-- every drawn piece sits above the scene; the real buttons are lifted to Z_BTN
	local Z_UI, Z_BTN = 3, 6
	local bar = Kit.plate(layer, UDim2.fromOffset(100, 40)); bar.Name = "RoundBar"; bar.ZIndex = Z_UI
	local roundLabel = Instance.new("TextLabel")
	roundLabel.Name = "RoundName"
	roundLabel.BackgroundTransparency = 1
	roundLabel.Font = Enum.Font[Style.FONTS.title]
	roundLabel.TextSize = Style.TEXT.subtitle
	roundLabel.TextColor3 = Color3.fromRGB(Style.rgb("cream")[1], Style.rgb("cream")[2], Style.rgb("cream")[3])
	roundLabel.TextTransparency = 0
	roundLabel.TextStrokeTransparency = 0.2
	roundLabel.TextStrokeColor3 = Color3.fromRGB(Style.rgb("outline")[1], Style.rgb("outline")[2], Style.rgb("outline")[3])
	roundLabel.TextXAlignment = Enum.TextXAlignment.Center
	roundLabel.TextTruncate = Enum.TextTruncate.AtEnd
	roundLabel.ZIndex = Z_UI + 1
	roundLabel.Parent = layer
	local target = Kit.goldBox(layer, "Target: 0"); target.Name = "TargetBox"; target.ZIndex = Z_UI + 1
	local tips = Kit.pill(layer, "Tips: 0", "wood"); tips.Name = "TipsPill"; tips.ZIndex = Z_UI + 1
	local handsPill = Kit.pill(layer, "Hands: 0", "green"); handsPill.Name = "HandsPill"; handsPill.ZIndex = Z_UI
	local discardsPill = Kit.pill(layer, "Discards: 0", "wood"); discardsPill.Name = "DiscardsPill"; discardsPill.ZIndex = Z_UI
	local deckImg = Instance.new("ImageLabel")
	deckImg.Name = "DeckBook"
	deckImg.BackgroundTransparency = 1
	deckImg.BorderSizePixel = 0
	deckImg.Active = false
	deckImg.Image = Art.ct_deck_a or ""
	deckImg.ScaleType = Enum.ScaleType.Fit
	deckImg.ZIndex = Z_UI
	deckImg.Parent = layer
	local deckPill = Kit.pill(layer, "0 / 52", "wood"); deckPill.Name = "DeckCountPill"; deckPill.ZIndex = Z_UI
	-- table furniture under the deck and under the bottom row (rects from ConceptTLayout.decorFor), over the felt, under every plate and button
	local furniture = {}
		-- soft contact shadow under the deck on the felt (solid black, stacked rounded frames from faint to dark, no gradient)
		local shadows = {}
		for _, name in ipairs({ "DeckShadow" }) do
			local sh = Instance.new("Frame"); sh.Name = name; sh.BackgroundTransparency = 1; sh.BorderSizePixel = 0; sh.Active = false; sh.ZIndex = 2; sh.Visible = false; sh.Parent = layer
			for i, tr in ipairs({ 0.88, 0.8, 0.7 }) do
				local ring = Instance.new("Frame"); ring.Name = "Ring" .. i; ring.BorderSizePixel = 0; ring.Active = false
			ring.BackgroundColor3 = Color3.new(0, 0, 0); ring.BackgroundTransparency = tr; ring.ZIndex = 2
			ring.AnchorPoint = Vector2.new(0.5, 0.5); ring.Position = UDim2.fromScale(0.5, 0.5)
			ring.Size = UDim2.new(1, -2 * (i - 1) * 5, 1, -2 * (i - 1) * 5)
			ring.Parent = sh
			local uc = Instance.new("UICorner"); uc.CornerRadius = UDim.new(0, 14); uc.Parent = ring
			end
			shadows[name] = sh
		end
		for _, spec in ipairs({ { "inlay", "FeltInlay", "ct_felt_inlay" }, { "rail", "BottomRail", "ct_rail_strip" }, { "rim", "TableRim", "ct_table_rim" } }) do
		local img = Instance.new("ImageLabel")
		img.Name = spec[2]; img.BackgroundTransparency = 1; img.BorderSizePixel = 0; img.Active = false
		img.Image = Art[spec[3]] or ""; img.ScaleType = Enum.ScaleType.Stretch; img.ZIndex = 2; img.Visible = false; img.Parent = layer
		if spec[1] == "rim" then -- the wide wood rim lies slightly wider than the root at the sides: same clip frame as the rail, drawn above the flat rail
			local clip = layer:FindFirstChild("RailClip")
			if clip then img.Parent = clip end
			local rail = furniture.rail
			if rail and img.Image ~= "" then rail.ImageTransparency = 1 end -- the curved rim replaces the flat rail strip (kept in the tree: its rect and the deck shadow follow it)
		end
		if spec[1] == "rail" then -- the rail picture is drawn wider than the root (its carved end caps lie outside), so a clip frame the size of the root keeps it inside a scaled or letterboxed root
			local clip = Instance.new("Frame"); clip.Name = "RailClip"; clip.BackgroundTransparency = 1; clip.BorderSizePixel = 0; clip.Active = false
			clip.ClipsDescendants = true; clip.Size = UDim2.fromScale(1, 1); clip.ZIndex = 2; clip.Parent = layer
			img.Parent = clip
		end
		if spec[1] == "inlay" then img.ImageTransparency = 0.5; img.ImageColor3 = Color3.fromRGB(190, 150, 70); img.ClipsDescendants = true end -- thin warm gold, not cream
		furniture[spec[1]] = img
	end
	-- wall banners: still pictures on the wall (no tween, so Calm mode and Reduce motion are unchanged), drawn under every plate
	local wallBanners = {}
	do
		local PK = require(Engine:WaitForChild("PaintedKitArt"))
		for side, key in pairs({ left = "pk_banner_l", right = "pk_banner_r" }) do
			local img = Instance.new("ImageLabel")
			img.Name = side == "left" and "WallBannerLeft" or "WallBannerRight"
			img.BackgroundTransparency = 1
			img.BorderSizePixel = 0
			img.Active = false
			img.Image = PK[key] or ""
			img.ScaleType = Enum.ScaleType.Fit
			img.ZIndex = 2
			img.Visible = false
			img.Parent = layer
			wallBanners[side] = img
		end
	end
	-- centre of the felt: the round score and a thin gold underline, quiet so the cards stand out
	local scoreBox = Instance.new("Frame")
	scoreBox.Name = "CenterScore"
	scoreBox.BackgroundTransparency = 1
	scoreBox.BorderSizePixel = 0
	scoreBox.Active = false
	scoreBox.Parent = layer
	local function scoreText(name, font, color, strokeT)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Font = font
		t.TextColor3 = color
		t.TextTransparency = 0.3
		t.TextStrokeTransparency = strokeT
		t.TextStrokeColor3 = Color3.fromRGB(Style.rgb("outline")[1], Style.rgb("outline")[2], Style.rgb("outline")[3])
		t.TextScaled = false
		t.Parent = scoreBox
		return t
	end
	local cream = Color3.fromRGB(Style.rgb("cream")[1], Style.rgb("cream")[2], Style.rgb("cream")[3])
	local scoreNum = scoreText("ScoreNumeral", Enum.Font[Style.FONTS.title], Color3.fromRGB(Style.rgb("gold")[1], Style.rgb("gold")[2], Style.rgb("gold")[3]), 0.5)
	scoreNum.TextTransparency = 0
	local scorePlate = Instance.new("Frame") -- ornate plate behind the caption, numeral and gold line (the progress line stays under it)
	scorePlate.Name = "ScorePlate"; scorePlate.BackgroundTransparency = 1; scorePlate.BorderSizePixel = 0; scorePlate.Active = false
	scorePlate.ZIndex = 3; scorePlate.Parent = layer
	local scoreCaption = scoreText("ScoreCaption", Enum.Font.Merriweather, cream, 0.6) -- cream serif with a soft dark shadow (reference)
	scoreCaption.Text = "Score"
	local scoreProgress = scoreText("ScoreProgress", Enum.Font[Style.FONTS.ui], Color3.fromRGB(Style.rgb("cream")[1], Style.rgb("cream")[2], Style.rgb("cream")[3]), 0.5)
	scoreProgress.TextTransparency = 0.1
	scoreNum.TextTransparency = 0; scoreNum.TextStrokeTransparency = 0.1 -- bold white digits (a thin serif 0 read as an O) with a gold outline
	scoreNum.Font = Enum.Font.GothamBold
	scoreNum.TextColor3 = Color3.fromRGB(255, 244, 222) -- cream white until the Target is reached, then gold (below)
	scoreNum.TextStrokeColor3 = Color3.fromRGB(Style.rgb("outline")[1], Style.rgb("outline")[2], Style.rgb("outline")[3]) -- 1 px dark outline
	scoreCaption.TextTransparency = 0.1
	local scoreLine = Instance.new("Frame")
	scoreLine.Name = "ScoreUnderline"
	scoreLine.BorderSizePixel = 0
	scoreLine.BackgroundColor3 = Color3.fromRGB(Style.rgb("gold")[1], Style.rgb("gold")[2], Style.rgb("gold")[3])
	scoreLine.BackgroundTransparency = 0.45
	scoreLine.Active = false
	scoreLine.Parent = scoreBox
	-- the hand preview: "Flush Lv 2  |  50 Chips x 6 Mult" over the centre score while cards are selected (Engine/Gameplay2Preview)
	-- the one Settings gear at the top right (and its drop down toggle menu) lives in Client/GearMenu, shared with the Counter and the Night map
	pcall(function() require(script.Parent.GearMenu).install({ root = root }) end)
	local tray = nil
	pcall(function() tray = require(script.Parent.Gameplay2Tray).install(layer, { selectedIndices = deps.selectedIndices }, Z_BTN) end)
	local previewPill = Kit.pill(layer, "", "wood"); previewPill.Name = "PreviewPill"; previewPill.ZIndex = Z_UI + 1; previewPill.Visible = false
	for _, p in ipairs({ tips, handsPill, discardsPill, deckPill, previewPill }) do -- a pill's word fills the whole pill and may be longer than 4 chars
		local w = p:FindFirstChild("Word")
		if w then w.TextSize = Style.TEXT.chip; w.TextScaled = false end
	end

	-- painted frames for the table HUD (Engine/TavernStyle.PAINTED): the top bar, the Hands, Discards and deck count tabs
	local painted = {}
	-- ornate set (dark wood, carved gold trim, scrolled corners): three separate top pieces (Target, the parchment rule scroll holding the Night and
	-- Round name, Tips), the three count plates and the score plate; the old one piece bar stays as an invisible layout host
	pcall(function()
		bar.BackgroundTransparency = 1
		for _, c in ipairs(bar:GetChildren()) do if c:IsA("UIStroke") then c.Enabled = false end end
		Kit.painted(target, "wh_target"); Kit.painted(tips, "wh_target")
		Kit.painted(deckPill, "wh_count")
		for _, p in ipairs({ handsPill, discardsPill }) do -- plain dark rounded pill, 1 px gold line, cream text (the concept), no ornate frame
			p.BackgroundColor3 = Color3.fromRGB(38, 24, 14)
			local ps = p:FindFirstChildOfClass("UIStroke")
			if ps then ps.Thickness = 1; ps.Color = Color3.fromRGB(214, 168, 76) end
			local pw = p:FindFirstChild("Word")
			if pw then pw.TextColor3 = Color3.fromRGB(245, 232, 200); pw.TextStrokeTransparency = 1 end
		end
		do -- the lightbulb icon on Tips, its word moved right of it
			local bulb = Kit.icon(tips, "bulb")
			local tw = tips:FindFirstChild("Word")
			if bulb and tw and not tw:FindFirstChild("KitIconPad") then local up = Instance.new("UIPadding"); up.Name = "KitIconPad"; up.PaddingLeft = UDim.new(0.18, 0); up.Parent = tw end
		end
		local scroll = Kit.painted(roundLabel, "wh_scroll")
		if scroll and not roundLabel:FindFirstChild("KitIconPad") then local up = Instance.new("UIPadding"); up.Name = "KitIconPad"; up.PaddingLeft = UDim.new(0.15, 0); up.PaddingRight = UDim.new(0.04, 0); up.Parent = roundLabel end -- the wax seal sits at the left
		if scroll then -- dark ink on the cream scroll; cream again if the picture never loads
			roundLabel.TextColor3 = Color3.fromRGB(58, 36, 20); roundLabel.TextStrokeTransparency = 1
			task.delay(Style.PAINTED_LOAD_WAIT * 4 + 0.5, function()
				if not scroll.Parent then
					roundLabel.TextColor3 = Color3.fromRGB(Style.rgb("cream")[1], Style.rgb("cream")[2], Style.rgb("cream")[3]); roundLabel.TextStrokeTransparency = 0.2
				end
			end)
		end
	end)

	local function sortChrome(toggle, on)
		on = Layout.sortChromeShown(on)
		for _, nm in ipairs({ "SortRank", "SortSuit" }) do
			local b = toggle and toggle:FindFirstChild(nm)
			if b then
				for _, kn in ipairs({ "KitIcon", "KitLabel", "GoldFrame", "GoldInner" }) do local kc = b:FindFirstChild(kn); if kc then kc.Visible = on end end
			end
		end
	end

	-- the real Rank and Suit buttons live inside the hub's SortToggle; Gameplay v2 draws each as its own brown plate
	local function splitSort(toggle, r)
		toggle:SetAttribute("Split", true)
		toggle.Size = UDim2.fromOffset(r.sortSuit.x + r.sortSuit.w - r.sortRank.x, r.sortRank.h)
		toggle.Position = UDim2.fromOffset(0, 0)
		for _, nm in ipairs({ "SortRank", "SortSuit" }) do
			local b = toggle:FindFirstChild(nm)
			local want = nm == "SortRank" and r.sortRank or r.sortSuit
			if b then
				b.Size = UDim2.fromOffset(want.w, want.h)
				b.Position = UDim2.fromOffset(want.x - r.sortRank.x, 0)
				b.ZIndex = Z_BTN
				if not painted[nm] then -- dark wood face (reference: carved brown like Discard, cream text, gold icon and edge): a flat plate, no picture
					painted[nm] = true
					pcall(function()
						if not b:FindFirstChildOfClass("UICorner") then local uc = Instance.new("UICorner"); uc.CornerRadius = UDim.new(0, 8); uc.Parent = b end
						local ic = Kit.icon(b, nm == "SortRank" and "bars" or "spade", 0.2)
						local ink = Color3.fromRGB(240, 196, 92) -- gold glyph on the dark wood
						if ic and ic:IsA("ImageLabel") then -- the painted icon sits on a dark disc: keep its box (the layout moves it) and draw a bare dark glyph in it
							ic.ImageTransparency = 1
							if nm == "SortRank" then
								for i, wf in ipairs({ 1, 0.7, 0.45 }) do
									local bar = Instance.new("Frame"); bar.Name = "GlyphBar"; bar.BorderSizePixel = 0; bar.Active = false; bar.BackgroundColor3 = ink
									bar.Size = UDim2.fromScale(0.8 * wf, 0.16); bar.Position = UDim2.fromScale(0.1, 0.16 + (i - 1) * 0.27); bar.ZIndex = Z_BTN + 1; bar.Parent = ic
								end
							else
								local g = Instance.new("TextLabel"); g.Name = "GlyphSpade"; g.BackgroundTransparency = 1; g.Size = UDim2.fromScale(1, 1); g.Text = utf8.char(0x2660)
								g.Font = Enum.Font.GothamBold; g.TextScaled = true; g.TextColor3 = ink; g.TextStrokeTransparency = 1; g.ZIndex = Z_BTN + 1; g.Active = false; g.Parent = ic
							end
						end
						-- the ornate gold edge (same family as Target and Tips) drawn ABOVE the wood face: outer gold ring, thin dark gold inner line, four corner diamonds
						local gf = Instance.new("Frame"); gf.Name = "GoldFrame"; gf.BackgroundTransparency = 1; gf.BorderSizePixel = 0; gf.Active = false
						gf.Size = UDim2.fromScale(1, 1); gf.ZIndex = Z_BTN + 2; gf.Parent = b
						local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0, 8); gc.Parent = gf
						local gs = Instance.new("UIStroke"); gs.Thickness = 2; gs.Color = Color3.fromRGB(176, 134, 56); gs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; gs.Parent = gf
						local gi = Instance.new("Frame"); gi.Name = "GoldInner"; gi.BackgroundTransparency = 1; gi.BorderSizePixel = 0; gi.Active = false
						gi.Size = UDim2.new(1, -10, 1, -10); gi.Position = UDim2.fromOffset(5, 5); gi.ZIndex = Z_BTN + 2; gi.Parent = gf
						local gic = Instance.new("UICorner"); gic.CornerRadius = UDim.new(0, 5); gic.Parent = gi
						local gis = Instance.new("UIStroke"); gis.Thickness = 1; gis.Color = Color3.fromRGB(120, 88, 40); gis.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; gis.Parent = gi
						for _, cx in ipairs({ 0, 1 }) do for _, cy in ipairs({ 0, 1 }) do
							local d = Instance.new("Frame"); d.Name = "GoldDiamond"; d.BorderSizePixel = 0; d.Active = false; d.Rotation = 45; d.AnchorPoint = Vector2.new(0.5, 0.5)
							d.Size = UDim2.fromOffset(7, 7); d.Position = UDim2.new(cx, cx == 0 and 4 or -4, cy, cy == 0 and 4 or -4); d.BackgroundColor3 = Color3.fromRGB(240, 196, 92); d.ZIndex = Z_BTN + 3; d.Parent = gf
						end end
					end)
				end
			end
		end
		sortChrome(toggle, true)
	end

	local active, lastState = false, nil
	local life = nil -- candles, fire and dust motes over the scene (Client/Gameplay2Life), built on first use
	local function lifeAttach()
		if not life then pcall(function() life = require(script.Parent.Gameplay2Life).attach(layer, function() return active end) end) end
		return life
	end
	local hiddenDeck, sortHost, actionHeld = {}, nil, nil
	local savedFan, savedFanOn = PlayMotion.FAN, PlayMotion.HAND_FAN_ENABLED
	local self = {}

	local function fanHand(on, h)
		if on then
			PlayMotion.FAN = CTLayout.fanProfile(h)
			PlayMotion.HAND_FAN_ENABLED = true
		else
			PlayMotion.FAN = savedFan
			PlayMotion.HAND_FAN_ENABLED = savedFanOn
		end
	end

	-- the label is its own TextLabel above the button's plate: the button's own Text is blanked so the word is drawn once, on top
	local function buttonLabel(b, text)
		local cream = Style.rgb("cream")
		local l = require(script.Parent.ButtonLabelTop).own(b, text, math.max(Style.TEXT.button, math.min(24, math.floor(b.AbsoluteSize.Y * 0.4))), Z_BTN + 1, Color3.fromRGB(cream[1], cream[2], cream[3]))
		l.Font = Enum.Font[Style.FONTS.ui]
		l.TextStrokeColor3 = Color3.fromRGB(Style.rgb("outline")[1], Style.rgb("outline")[2], Style.rgb("outline")[3])
	end

	local function restoreOld()
		for _, b in ipairs({ deps.playButton, deps.discardButton }) do
			local l = b:FindFirstChild("KitLabel")
			if l then l.Visible = false end
		end
		if deps.playButton.Text == "" then deps.playButton.Text = "Play Hand" end
		if deps.discardButton.Text == "" then deps.discardButton.Text = "Discard" end
		if actionHeld then
			local held = actionHeld
			actionHeld = nil
			LayoutSwitch.on(deps.actionFrame)
			deps.playButton.Size = UDim2.new(0, 200, 1, 0)
			deps.discardButton.Size = UDim2.new(0, 200, 1, 0)
			local cs = deps.actionFrame:FindFirstChild("CompactScale")
			if cs and held.scale then cs.Scale = held.scale end
			deps.actionFrame.Position = UDim2.new(deps.actionFrame.Position.X.Scale, deps.actionFrame.Position.X.Offset + 1, deps.actionFrame.Position.Y.Scale, deps.actionFrame.Position.Y.Offset)
		end
		for c in pairs(hiddenDeck) do c.Visible = true end
		hiddenDeck = {}
		if sortHost and sortHost.Parent then
			local sf = sortHost
			sortHost = nil
			LayoutSwitch.on(sf)
			sf.Size = UDim2.new(0, 214, 1, 0)
			sf.Position = UDim2.new()
			for _, k in ipairs(sf:GetChildren()) do
				if k.Name == "PlatePaint" and k:IsA("GuiObject") then k.Visible = true
				elseif k:IsA("TextLabel") then k.Visible = true
				elseif k.Name == "SortToggle" then
					k:SetAttribute("Flat", false)
					k:SetAttribute("Split", false)
					sortChrome(k, false) -- gold frames, icons and words stay on the table (Counter, Nov 20)
					k.Size = UDim2.fromOffset(132, 28)
					for _, nm in ipairs({ "SortRank", "SortSuit" }) do -- back to the two halves of the shared track
						local half = k:FindFirstChild(nm)
						if half then
							-- the icon and word belong to the table plate: out of the table phase they would float as stray chips (Counter, Nov 19)
							half.Size = UDim2.new(0.5, -5, 1, -6)
							half.Position = UDim2.new(nm == "SortRank" and 0 or 0.5, nm == "SortRank" and 3 or 2, 0, 3)
						end
					end
				end
			end
		end
	end

	local function sceneKey(state)
		local boss = state and state.bossModifier ~= nil and (state.round or 0) >= 3
		return boss and "table_boss" or "table_play"
	end

	local function apply()
		local size = root.AbsoluteSize
		local r = Layout.rects(size.X, size.Y)
		fanHand(true, size.Y)
		-- the real controls are the drawn controls: same instance, moved onto the layout rect
		local cs = deps.actionFrame:FindFirstChild("CompactScale")
		if not actionHeld then actionHeld = { scale = cs and cs.Scale or nil } end
		LayoutSwitch.off(deps.actionFrame)
		deps.actionFrame.ClipsDescendants = false -- the painted Discard frame is a sibling inside this frame: never cut it at the frame edge
		if cs then cs.Scale = 1 end
		deps.actionFrame.Position = UDim2.fromOffset(r.play.x, r.play.y)
		deps.actionFrame.Size = UDim2.fromOffset(r.discard.x + r.discard.w - r.play.x, r.play.h)
		deps.playButton.Position = UDim2.fromOffset(0, 0)
		deps.playButton.Size = UDim2.fromOffset(r.play.w, r.play.h)
		deps.discardButton.Position = UDim2.fromOffset(r.discard.x - r.play.x, 0)
		deps.discardButton.Size = UDim2.fromOffset(r.discard.w, r.discard.h)
		deps.playButton.ZIndex = Z_BTN; deps.discardButton.ZIndex = Z_BTN
		if deps.playButton:GetAttribute("TavernKind") ~= "primary" then Kit.skin(deps.playButton, "Play Hand", "primary") end
		if deps.discardButton:GetAttribute("TavernKind") ~= "secondary" then Kit.skin(deps.discardButton, "Discard", "secondary") end
		-- the button IS the plate: never see-through, whatever another module did to it since the skin was applied
		if not painted.buttons then -- the painted frames (Engine/TavernStyle.PAINTED); the flat plate stays if a picture is missing
			painted.buttons = true
			pcall(function() Kit.painted(deps.playButton, "wh_btn_green"); Kit.painted(deps.discardButton, "wh_btn_dark") end)
		end
		local function flatOpaque(b) if not (b.Parent and b.Parent:FindFirstChild(b.Name .. "Paint")) then b.BackgroundTransparency = 0 end end
		flatOpaque(deps.playButton); flatOpaque(deps.discardButton)
		deps.playButton.AnchorPoint = Vector2.new(0, 0); deps.discardButton.AnchorPoint = Vector2.new(0, 0); deps.actionFrame.AnchorPoint = Vector2.new(0, 0)
		buttonLabel(deps.playButton, "Play Hand"); buttonLabel(deps.discardButton, "Discard")
		pcall(function() -- feel: label press and the ready ring (Client/Gameplay2FeelFX); the buttons themselves never move
			local FX = require(script.Parent.Gameplay2FeelFX)
			FX.wirePress(deps.playButton); FX.wirePress(deps.discardButton)
			local n = deps.selectedCount and deps.selectedCount() or 0
			local legal = lastState ~= nil and lastState.phase == "playing" and require(Engine:WaitForChild("Gameplay2Feel")).legalPlay(n, 1, 5)
				and require(Engine:WaitForChild("PlayRules")).allows(lastState, n) ~= false
			FX.setLegal(deps.playButton, legal)
		end)
		do
			local n = lastState and lastState.hand and #lastState.hand or 0
			place(deps.handFrame, require(Engine:WaitForChild("HandSizing")).frameFor(size.X, CTLayout.handFor(r.hand, size.X, n), math.max(n, 8)))
		end
		place(bar, r.bar)
		place(roundLabel, r.round)
		place(target, r.target); place(tips, r.tips)
		do -- Target: and Tips: words grow with the plate (Layout.barTextSize), the Tips bulb with them
			local ts = Layout.barTextSize(r.target.h)
			for _, pl in ipairs({ target, tips }) do
				local tw = pl:FindFirstChild("Value") or pl:FindFirstChild("Word")
				if tw then tw.TextScaled = false; tw.TextSize = ts end
			end
		end
		place(handsPill, r.playCount); place(discardsPill, r.discardCount)
		for _, pr in ipairs({ { handsPill, r.playCount }, { discardsPill, r.discardCount } }) do -- cream 18 px words, smaller only when the pill is too short for them
			local pw = pr[1]:FindFirstChild("Word")
			if pw then pw.TextScaled = false; pw.TextSize = math.max(10, math.min(18, math.floor(pr[2].h * 0.6))) end
		end
		place(deckImg, CTLayout.deckPicture(r.deck)); place(deckPill, r.deckCount)
		do
			local dc = CTLayout.decorFor(r, size.X, size.Y)
			for key, img in pairs(furniture) do
				img.Visible = img.Image ~= ""
				place(img, dc[key])
			end
			deckImg.Rotation = CTLayout.DECK_TILT
			do
				local sh = shadows.DeckShadow
				sh.Visible = furniture.rail.Visible
				sh.Rotation = CTLayout.DECK_TILT
				place(sh, CTLayout.deckShadow(r.deck))
			end
			if game:GetService("RunService"):IsStudio() and self.decorKey ~= size.X .. "x" .. size.Y then
				self.decorKey = size.X .. "x" .. size.Y
				local fl2 = CTLayout.feltFor(size.X, size.Y).rim
				local hull = CTLayout.hullOf(r.deck, CTLayout.DECK_TILT)
				print(("[TableDecor] %dx%d deck=%d,%d,%d,%d hull=%d,%d,%d,%d felt=%d,%d,%d,%d inside=%s rail=%d,%d,%d,%d capClear=%d,%d"):format(size.X, size.Y, r.deck.x, r.deck.y, r.deck.w, r.deck.h, hull.x, hull.y, hull.w, hull.h, fl2.x, fl2.y, fl2.w, fl2.h, tostring(CTLayout.insideFelt(r.deck, CTLayout.DECK_TILT, size.X, size.Y, 0)), dc.rail.box.x, dc.rail.box.y, dc.rail.box.w, dc.rail.box.h, CTLayout.railCapClear(dc.rail, size.X).left, CTLayout.railCapClear(dc.rail, size.X).right))
			end
		end
		do
			-- the reference tavern paints its own four banners, so the HUD pair only hangs on scenes without them (Boss rounds)
				local wb = ((TableArt.table_play_ref and scene.Image == TableArt.table_play_ref) or (TableArt.table_boss_ref and scene.Image == TableArt.table_boss_ref)) and nil or Layout.banners(size.X, size.Y)
			for side, img in pairs(wallBanners) do
				local rc = wb and wb[side]
				img.Visible = rc ~= nil and img.Image ~= ""
				if rc then place(img, rc) end
			end
		end
		raise(target, Z_UI + 1); raise(tips, Z_UI + 1); raise(handsPill, Z_BTN + 2); raise(discardsPill, Z_BTN + 2); raise(deckPill, Z_UI)
		-- the quiet score in the middle of the felt (inside the stage rect, under any scoring popup)
		local SPlate = require(Engine:WaitForChild("Gameplay2ScorePlate"))
		local capH, progH = SPlate.capFor(root.AbsoluteSize.X), 22 -- the caption row (SPlate.MIN_H counts CAP_H); the strip stands above the plate, so it no longer shares this row
		local HSz = require(Engine:WaitForChild("HandSizing"))
		local nHand = lastState and lastState.hand and #lastState.hand or 0
		local idleHand = HSz.frameFor(size.X, CTLayout.handFor(r.hand, size.X, nHand), math.max(nHand, 8))
		local stageUse = self.playing == true and r.stage or SPlate.idleStage(r.stage, idleHand.y, root.AbsoluteSize.X) -- idle: plate and line end 12 px above the tallest card
		local stripShown = false -- the hand strip stands above the Score plate (never over its caption) when the idle stage has room for both
		if self.previewText and self.playing ~= true then
			local ps, ok = PreviewRules.plateStage(stageUse, SPlate.MIN_H)
			if ok then -- only when the shifted plate still holds the whole stack (caption, normal numeral, "o of N" line)
				local t = SPlate.live(ps, root.AbsoluteSize.X, capH, progH, false).N
				if t.roomy and not t.noProgress then stageUse, stripShown = ps, true end
			end
		end
		local nameInCaption = self.previewText ~= nil and self.playing ~= true and not stripShown -- no room for the strip: the hand name takes the caption row instead
		local live = SPlate.live(stageUse, root.AbsoluteSize.X, capH, progH, self.playing == true)
		if game:GetService("RunService"):IsStudio() and self.tableRectsKey ~= size.X .. "x" .. size.Y then
			self.tableRectsKey = size.X .. "x" .. size.Y
			print(("[TableRects] %dx%d plate y=%d bottom=%d handTop=%d stage=%d..%d caption=%s progress=%s"):format(size.X, size.Y, live.plate.y, live.plate.y + live.plate.h, idleHand.y, stageUse.y, stageUse.y + stageUse.h, tostring(live.N.roomy), tostring(live.N.roomy and not live.N.noProgress)))
			local function rc(b) return ("%d,%d,%d,%d"):format(b.x, b.y, b.w, b.h) end
			print(("[ScorePlateSize] plate=%dx%d numeral=%dx%d textSize=%d"):format(live.plate.w, live.plate.h, live.N.numH and live.inner.w or 0, live.N.numH or 0, live.N.textSize or 0))
			print(("[ActionRects] play=%s discard=%s hands=%s discards=%s"):format(rc(r.play), rc(r.discard), rc(r.playCount), rc(r.discardCount)))
		end -- the stack stands 8 px inside the carved border
		local N = live.N
		scoreBox.Position = UDim2.fromOffset(live.box.x, live.box.y)
		scoreBox.Size = UDim2.fromOffset(live.box.w, live.box.h)
		scoreBox.ZIndex = 3
		self.scoreFit = { size = N.textSize, w = live.inner.w }
		scoreNum.Size = UDim2.new(1, 0, 0, N.numH); scoreNum.Position = UDim2.fromOffset(0, N.numTop)
		scoreNum.TextSize = SPlate.fitSize(N.textSize, #tostring(scoreNum.Text), live.inner.w); scoreNum.ZIndex = 4
		scoreLine.Size = UDim2.new(0.4, 0, 0, 2); scoreLine.AnchorPoint = Vector2.new(0.5, 0)
		scoreLine.Position = UDim2.new(0.5, 0, 0, N.lineY); scoreLine.ZIndex = 4
		scoreCaption.Size = UDim2.new(1, 0, 0, capH); scoreCaption.TextSize = capH -- 30 px at 1920, scaled with the width (SPlate.capFor)
		scoreCaption.Position = UDim2.fromOffset(0, 0); scoreCaption.ZIndex = 4
		local nudge = SPlate.NAME_NUDGE
		if nameInCaption and N.numH and N.numH - nudge >= SPlate.IDLE_MIN_FONT then -- the hand name in the caption row clears the carved top border: it drops nudge px and the numeral gives them up
			scoreCaption.Position = UDim2.fromOffset(0, nudge)
			scoreNum.Size = UDim2.new(1, 0, 0, N.numH - nudge); scoreNum.Position = UDim2.fromOffset(0, N.numTop + nudge)
			scoreNum.TextSize = SPlate.fitSize(N.textSize - nudge, #tostring(scoreNum.Text), live.inner.w)
		end
		scoreProgress.Size = UDim2.new(1, 0, 0, progH); scoreProgress.TextSize = 24
		scoreProgress.Position = UDim2.fromOffset(0, N.below and N.progressY or (N.lineY + 4)); scoreProgress.ZIndex = 4 -- idle: the line stands 12 px under the plate
		do -- the plate: centred in the stage, as wide as the numeral needs, from the stage top to just under the gold line
			scorePlate.Position = UDim2.fromOffset(live.plate.x, live.plate.y)
			scorePlate.Size = UDim2.fromOffset(live.plate.w, live.plate.h)
			if not painted.score then painted.score = true; pcall(function() Kit.painted(scorePlate, "wh_score") end) end
		end
		scoreCaption.Visible = N.roomy and N.numTop >= capH
		scoreCaption.Text = nameInCaption and (self.previewText:match("^(.-)%s*|") or self.previewText) or (self.playing == true and self.scoringText) or "Score" -- "Flush Lv 2": the plate is too narrow for the Chips x Mult part
		scoreLine.Visible = false; scoreProgress.Visible = N.roomy and not N.noProgress -- the ornate plate has its own trim
		local inl -- set when the compact plate carries the progress inside; the ornament arrows are then hidden
		do -- compact table: the progress sits inside the plate beside the numeral ("0 / 65", 11 px) instead of dropping out
			inl = self.playing ~= true and SPlate.inline(live, #tostring(scoreNum.Text)) or nil
			scoreProgress.TextXAlignment = Enum.TextXAlignment.Center
			scoreProgress.TextYAlignment = Enum.TextYAlignment.Center
			if inl then
				scoreProgress.Size = UDim2.fromOffset(inl.w, inl.h); scoreProgress.Position = UDim2.fromOffset(inl.x, inl.y)
				scoreProgress.TextSize = inl.size; scoreProgress.Visible = true
				scoreProgress.Text = tostring(scoreProgress.Text):gsub(" of ", " / ")
			else
				scoreProgress.Text = tostring(scoreProgress.Text):gsub(" / ", " of ")
			end
		end
		for _, side in ipairs({ -1, 1 }) do -- small gold arrow flourishes flanking the "o of N" line: a thin line ending in a diamond
			local arrow = scoreBox:FindFirstChild(side < 0 and "ArrowL" or "ArrowR")
			if not arrow then
				arrow = Instance.new("Frame"); arrow.Name = side < 0 and "ArrowL" or "ArrowR"
				arrow.BorderSizePixel = 0; arrow.Active = false; arrow.AnchorPoint = Vector2.new(0.5, 0.5)
				arrow.BackgroundColor3 = Color3.fromRGB(Style.rgb("gold")[1], Style.rgb("gold")[2], Style.rgb("gold")[3]); arrow.Size = UDim2.fromOffset(52, 2)
				local dia = Instance.new("Frame"); dia.Name = "Tip"; dia.BorderSizePixel = 0; dia.Active = false; dia.Rotation = 45; dia.ZIndex = 4
				dia.AnchorPoint = Vector2.new(0.5, 0.5); dia.Size = UDim2.fromOffset(7, 7); dia.Position = UDim2.new(side < 0 and 1 or 0, 0, 0.5, 0)
				dia.BackgroundColor3 = arrow.BackgroundColor3; dia.Parent = arrow
				arrow.Parent = scoreBox
			end
			arrow.ZIndex = 4
			local half = math.floor(math.max(24, math.min(scoreProgress.TextBounds.X, 160)) / 2) -- snug: 12 px gap from the "o of N" text, arrow 52 wide
			arrow.Position = UDim2.new(0.5, side * (half + 12 + 26), 0, (N.below and N.progressY or (N.lineY + 4)) + math.floor(progH / 2))
			arrow.Visible = scoreProgress.Visible and not inl and (half + 12 + 52) * 2 <= (N.below and live.box.w or live.inner.w) -- a flourish that would cross the carved border is dropped
		end
		if self.previewText and not self.playing and stripShown then -- while a hand scores the centre name flair is the only hand label
			place(previewPill, PreviewRules.rect(r.stage, self.previewText))
			raise(previewPill, Z_UI + 1)
			if not painted.preview then painted.preview = true; pcall(function() Kit.painted(previewPill, "wh_target") end) end -- the Target and Tips plate family
			local pw = setText(previewPill, self.previewText)
			if pw then
				pw.RichText = true; pw.Text = self.previewRich or self.previewText
				pw.TextScaled = false; pw.TextSize = math.max(Style.TEXT.chip, 16)
				pw.TextTruncate = Enum.TextTruncate.AtEnd
				local pad = pw:FindFirstChild("PreviewPad") or Instance.new("UIPadding")
				pad.Name = "PreviewPad"; pad.PaddingLeft = UDim.new(0, 28); pad.PaddingRight = UDim.new(0, 28); pad.Parent = pw -- clear of the carved gold ends
			end
			previewPill.Visible = true
			if game:GetService("RunService"):IsStudio() and self.previewRectKey ~= self.previewText then
				self.previewRectKey = self.previewText
				local pr = PreviewRules.rect(r.stage, self.previewText)
				print(("[PreviewStrip] strip=%d,%d,%d,%d plate=%d,%d,%d,%d shifted=%s"):format(pr.x, pr.y, pr.w, pr.h, live.plate.x, live.plate.y, live.plate.w, live.plate.h, tostring(stripShown)))
			end
			if game:GetService("RunService"):IsStudio() then -- only one preview may show: the older box must stay hidden
				local old = deps.root and deps.root:FindFirstChild("CTPreviewPill", true)
				if old and old.Visible then warn("[Gameplay2] a second preview box (CTPreviewPill) is visible over the centre score") end
			end
		else
			previewPill.Visible = false
		end
		-- Rank | Suit: one frame covering the two layout halves
		for _, c in ipairs(deps.actionFrame:GetChildren()) do
			if c:IsA("Frame") and c.LayoutOrder == 0 then
				LayoutSwitch.off(c)
				c.Size = UDim2.fromOffset(r.sortSuit.x + r.sortSuit.w - r.sortRank.x, r.sortRank.h)
				c.Position = UDim2.fromOffset(r.sortRank.x - r.play.x, r.sortRank.y - r.play.y)
				sortHost = c
				for _, k in ipairs(c:GetChildren()) do
					if k.Name == "PlatePaint" and k:IsA("GuiObject") then k.Visible = false
					elseif k:IsA("TextLabel") then k.Visible = false
					elseif k.Name == "SortToggle" then
						k:SetAttribute("Flat", true)
						k.BackgroundTransparency = 0
						splitSort(k, r) -- each half takes its layout rect (44 px tall), so the hit box is the painted plate
					end
				end
			end
		end
		local dw = deps.deckWidget
		if dw then
			place(dw, r.deck)
			dw.AnchorPoint = Vector2.new(0, 0)
			local hit = Layout.deckHit(r) -- the click catcher also covers the count plate, so either opens the deck viewer
			local cc = dw:FindFirstChild("ClickCatcher")
			if cc then cc.Size = UDim2.fromOffset(hit.w, hit.h); cc.Position = UDim2.fromOffset(hit.x - r.deck.x, hit.y - r.deck.y) end
			dw.ClipsDescendants = false
			dw.BackgroundTransparency = 1
			for _, c in ipairs(dw:GetChildren()) do
				if c.Name ~= "ClickCatcher" then
					if c:IsA("GuiObject") then
						if c.Visible then hiddenDeck[c] = true end
						c.Visible = false
					elseif c:IsA("UIStroke") then c.Enabled = false end
				end
			end
		end
		if tray then pcall(tray.update, r, lastState) end -- the consumables tray (Client/Gameplay2Tray)
	end

	local function shell(on)
		if on then
			for _, name in ipairs(HIDE) do
				local g = root:FindFirstChild(name)
				if g and g:IsA("GuiObject") then g.Visible = false end
			end
		end
		layer.Visible = on
	end

	function self.isActive() return active end

	-- the hand name flair above the centre score (Client/Gameplay2FlairFX); the stage and the Patron row's last row set where it may sit
	function self.flair(preview)
		if not active or not preview or not preview.name then return end
		local r = self.rects()
		local avoid = 0
		for _, s in ipairs(r.slots) do avoid = math.max(avoid, s.pill.y + s.pill.h, s.label.y + s.label.h) end
		local over = require(Engine:WaitForChild("Gameplay2Flair")).overkill(preview.score, preview.targetScore)
		local ch, mu = require(Engine:WaitForChild("PlayReport")).baseOf(preview.breakdown or {})
		local row = Layout.scoringRows(r, math.max(20, PreviewRules.H)).name -- under the Score plate, above the played cards, 12 px each side
		self.scoringText = ("%d x %d"):format(math.floor((ch or 0) + 0.5), math.floor((mu or 0) + 0.5)) -- Chips x Mult live in the Score plate caption, not in side pills next to the one trigger line
		local sw = root.AbsoluteSize.X
		local sp = require(Engine:WaitForChild("Gameplay2ScorePlate")).live(r.stage, sw, math.max(20, PreviewRules.H), 22).plate
		local pill = over and require(Engine:WaitForChild("Gameplay2Flair")).overkillPill(sp, sw) or nil
		require(script.Parent.Gameplay2FlairFX).show(layer, r.stage, avoid, preview.name, over, nil, nil, row, pill)
	end

	function self.rects()
		local size = root.AbsoluteSize
		return Layout.rects(size.X, size.Y)
	end

	function self.rootW() return root.AbsoluteSize.X end

	function self.size() return root.AbsoluteSize end
	function self.refresh() apply() end
	-- while a hand scores the played row may reach into the hand rect: the unplayed hand cards step aside (hidden, then given back exactly
	-- as they were), so nothing stands under or over the played cards; the played cards are ghost copies on the root, not these
	local hiddenHand = {}
	function self.hideHand(on)
		if on then
			for _, c in ipairs(deps.handFrame:GetChildren()) do
				if c:IsA("GuiObject") and c.Visible and not c:IsA("ScrollingFrame") then hiddenHand[c] = true; c.Visible = false end
			end
		else
			for c in pairs(hiddenHand) do if c.Parent then c.Visible = true end end
			hiddenHand = {}
		end
	end

	function self.shake(which)
		pcall(function() require(script.Parent.Gameplay2FeelFX).shake(which == "discard" and deps.discardButton or deps.playButton) end)
	end

	-- Studio only: the real controls against their layout rects
	function self.selfCheck()
		local size = root.AbsoluteSize
		local r = Layout.rects(size.X, size.Y)
		local origin = root.AbsolutePosition
		local sortToggle
		if sortHost then sortToggle = sortHost:FindFirstChild("SortToggle") end
		local list = {
			{ "PlayHand", deps.playButton, r.play }, { "Discard", deps.discardButton, r.discard },
			{ "Deck", deps.deckWidget and deps.deckWidget:FindFirstChild("ClickCatcher"), Layout.deckHit(r) },
			{ "SortRank", sortToggle and sortToggle:FindFirstChild("SortRank", true), r.sortRank },
			{ "SortSuit", sortToggle and sortToggle:FindFirstChild("SortSuit", true), r.sortSuit },
		}
		for _, p in ipairs(list) do
			local b, want = p[2], p[3]
			if b and b.Parent then
				local cx = b.AbsolutePosition.X - origin.X + b.AbsoluteSize.X / 2
				local cy = b.AbsolutePosition.Y - origin.Y + b.AbsoluteSize.Y / 2
				local dx, dy = cx - (want.x + want.w / 2), cy - (want.y + want.h / 2)
				local line = string.format("[ClickCheck v2] %s abs=%d,%d size=%dx%d layout=%d,%d,%dx%d off=%d,%d", p[1], math.floor(b.AbsolutePosition.X), math.floor(b.AbsolutePosition.Y),
					math.floor(b.AbsoluteSize.X), math.floor(b.AbsoluteSize.Y), math.floor(want.x), math.floor(want.y), math.floor(want.w), math.floor(want.h), math.floor(dx), math.floor(dy))
				if math.abs(dx) > 4 or math.abs(dy) > 4 then warn(line) else print(line) end
				-- real hit test at the painted centre in screen space: the control must be the top object there
				pcall(function()
					local gs = game:GetService("GuiService")
					local gui = root:FindFirstAncestorWhichIsA("ScreenGui")
					local inset = (gui and gui.IgnoreGuiInset) and Vector2.zero or gs:GetGuiInset()
					-- GetGuiObjectsAtPosition takes GUI space, which is AbsolutePosition space plus the inset a non ignoring ScreenGui hides
					local at = Vector2.new(origin.X + want.x + want.w / 2, origin.Y + want.y + want.h / 2) + inset
					local top = gs:GetGuiObjectsAtPosition(at.X, at.Y)[1]
					if top and top ~= b and not top:IsDescendantOf(b) then
						warn(string.format("[ClickCheck v2] %s: top object at its painted centre is %s, not the control", p[1], top:GetFullName()))
					end
				end)
			end
		end
		pcall(function() -- the 14 pieces against the reference mockup: a warn lists every piece off by more than 12 px or 12 percent
			local RC = require(Engine:WaitForChild("Gameplay2RefCheck"))
			local plate = require(Engine:WaitForChild("Gameplay2ScorePlate")).plate(size.X, size.Y)
			local rows = RC.compare(RC.liveFrom(r, require(Engine:WaitForChild("GearMenu")).quickRects(size.X, size.Y), plate), size.X, size.Y)
			local bad = {}
			for _, row in ipairs(rows) do
				if row.bad then bad[#bad + 1] = string.format("%s dx=%d dy=%d size=%d%%", row.name, math.floor(row.dx + 0.5), math.floor(row.dy + 0.5), math.floor(row.sizePct + 0.5)) end
			end
			local line = string.format("[RefCheck] %dx%d %d of %d pieces off the reference", size.X, size.Y, #bad, #rows)
			if #bad > 0 then warn(line .. ": " .. table.concat(bad, "; ")) else print(line) end
		end)
	end

	-- a rising round score counts up and slams in (Client/Gameplay2ScoreFX); anything else just shows the number.
	-- Also called when the round has ended (phase not playing): the total that arrives then must still be written.
	function self.writeNumeral(score, phase)
		local nowScore = math.floor(score or lastState.roundScore or 0)
		phase = phase or lastState.phase
		local function put(n)
			scoreNum.Text = string.format("%d", math.floor(n))
			local fit = self.scoreFit
			if fit then -- a long total shrinks to stay inside the plate's border
				pcall(function() scoreNum.TextSize = require(Engine:WaitForChild("Gameplay2ScorePlate")).fitSize(fit.size, #scoreNum.Text, fit.w) end)
			end
		end
		local SN = require(Engine:WaitForChild("ScoreNumeral"))
		local act = SN.action(self.lastScore, nowScore, phase)
		if act == "count" then
			local ok = pcall(function() require(script.Parent.Gameplay2ScoreFX).play(scoreNum, scoreBox, self.lastScore, nowScore, put, lastState.targetScore) end)
			if not ok then put(nowScore); act = "count failed, set" end
		elseif act == "set" then
			put(nowScore)
		end
		local gold = SN.cleared(nowScore, lastState.targetScore)
		if gold ~= self.numeralGold then
			self.numeralGold = gold
			local c = gold and Style.rgb("gold") or { 255, 244, 222 } -- cream white (reference) until the Target is reached, then gold
			scoreNum.TextColor3 = Color3.fromRGB(c[1], c[2], c[3])
		end
		if game:GetService("RunService"):IsStudio() and act ~= "keep" then
			print(("[ScoreNumeral] phase=%s %s last=%s now=%d text=%s gold=%s"):format(tostring(phase), act, tostring(self.lastScore), nowScore, scoreNum.Text, tostring(gold)))
		end
		self.lastScore = nowScore
	end

	-- the hand's payout landed (ScoreLand.land) while the round-ending state is still held back by the reveal: count the numeral up
	-- now and keep it, so a later refresh with the old state (roundScore 0) cannot write 0 over it
	function self.landScore(score)
		if not lastState or type(score) ~= "number" then return end
		local copy = {}
		for k, v in pairs(lastState) do copy[k] = v end
		copy.roundScore = score
		lastState = copy
		self.writeNumeral(score, "playing")
	end

	-- the round-ending state is on screen (the shop opens): the numeral must read the final total, even if a count was still running
	function self.handOff()
		local final = self.lastScore
		if type(final) ~= "number" then return end
		if scoreNum.Text ~= string.format("%d", final) then
			pcall(function() require(script.Parent.Gameplay2ScoreFX).cancel() end)
			scoreNum.Text = string.format("%d", final)
			local fit = self.scoreFit
			if fit then pcall(function() scoreNum.TextSize = require(Engine:WaitForChild("Gameplay2ScorePlate")).fitSize(fit.size, #scoreNum.Text, fit.w) end) end
		end
		if game:GetService("RunService"):IsStudio() then print(("[ScoreNumeral] hand-off to shop: text=%s final=%d"):format(scoreNum.Text, final)) end
	end

	-- the Night and Round scroll text: sized from the layout's scroll rect, so it can be run again when the root is rescaled
	local function fitBanner()
		if not lastState then return end
			roundLabel.Text = string.format("Night %d, Round %d", math.floor(lastState.night or 1), math.floor(lastState.round or 1))
			do -- a Boss round adds its rule as a second line in the scroll (two lines at most, one line when the bar is too short for two)
				local bname, brule = Moments.bossText(lastState)
				if bname ~= nil then -- the BossCardFX name, health bar and Night line sit in the scroll: no second text here
					roundLabel:SetAttribute("RuleInScroll", false)
					roundLabel.RichText = false
					roundLabel.Text = ""
					return
				end
				local baseSize = Style.TEXT.subtitle
				local ih = roundLabel.AbsoluteSize.Y
				pcall(function() ih = Layout.rects(root.AbsoluteSize.X, root.AbsoluteSize.Y).round.h end) -- ask the layout, not the label: after a root rescale the label still holds its old size
				local inScroll = bname ~= nil and brule ~= "" and ih >= 2 * 15 + 6
				local compactRule = false -- a short scroll with a compact chip: the rule is the second line at 9 px or more, the chip holds "Boss: Name"
				if bname ~= nil and brule ~= "" and not inScroll and ih >= 28 then
					local okc, ch = pcall(function() local rr = Layout.rects(root.AbsoluteSize.X, root.AbsoluteSize.Y); return Moments.ruleChip(rr, root.AbsoluteSize.X, root.AbsoluteSize.Y, bname, brule) end)
					compactRule = okc and ch ~= nil and ch.compact
				end
				if compactRule then
					local pw = roundLabel.AbsoluteSize.X
					pcall(function() pw = Layout.rects(root.AbsoluteSize.X, root.AbsoluteSize.Y).round.w end)
					local sub = Moments.ruleSubtitle(brule, pw)
					roundLabel:SetAttribute("RuleInScroll", false)
					roundLabel.RichText = false
					roundLabel.TextWrapped = true
					roundLabel.TextTruncate = Enum.TextTruncate.None
					roundLabel.TextSize = math.max(9, math.min(13, math.floor((ih - 4) / 2.5), Moments.subtitleSize(sub, pw)))
					roundLabel.Text = roundLabel.Text .. "\n" .. sub
				else
					roundLabel:SetAttribute("RuleInScroll", inScroll) -- the scroll is then the one rule element: Gameplay2MomentsFX hides the separate rule plate
					roundLabel.RichText = false
					if inScroll then
					roundLabel.TextWrapped = true
					roundLabel.TextSize = math.max(14, math.min(baseSize, math.floor((ih - 6) / 2)))
					roundLabel.Text = roundLabel.Text .. "\n" .. Moments.plateLine(bname, brule)
					roundLabel.TextTruncate = Enum.TextTruncate.AtEnd
				elseif bname == nil and ih >= Layout.roundTwoLineMin() then -- a normal round: bold title line plus the goal line (two lines, never cut)
					roundLabel:SetAttribute("RuleInScroll", false)
					roundLabel.TextWrapped = true
					roundLabel.RichText = ih >= 62
					roundLabel.TextTruncate = Enum.TextTruncate.None
					local goal = string.format("Score %d to clear", math.floor(lastState.targetScore or 0))
					if roundLabel.RichText then -- reference: 30 px title over a 20 px goal line
						local avail = ih - 12 -- 6 px margin top and bottom: a 60 px scroll gets 28 and 17, both lines inside it
						local titleSz, goalSz = math.min(30, math.floor(avail * 0.55)), math.min(20, math.floor(avail * 0.35))
						local pw = roundLabel.AbsoluteSize.X
						pcall(function() pw = Layout.rects(root.AbsoluteSize.X, root.AbsoluteSize.Y).round.w end)
						titleSz = Layout.fitRoundText(roundLabel.Text, titleSz, pw / 1.1) -- bold words run wider than plain ones
						goalSz = Layout.fitRoundText(goal, goalSz, pw)
						roundLabel.TextSize = goalSz
						roundLabel.TextYAlignment = Enum.TextYAlignment.Center
						roundLabel.Text = string.format('<font size="%d"><b>%s</b></font>\n<font size="%d">%s</font>', titleSz, roundLabel.Text, goalSz, goal)
					else
						local pw = roundLabel.AbsoluteSize.X
						pcall(function() pw = Layout.rects(root.AbsoluteSize.X, root.AbsoluteSize.Y).round.w end)
						roundLabel.TextTruncate = Enum.TextTruncate.None -- the text is fitted to the scroll, never cut with an ellipsis
						roundLabel.TextSize = Layout.fitRoundText(goal, math.max(Layout.ROUND_TEXT_MIN, math.min(Layout.barTextSize(ih * 2), Layout.roundLineSize(ih, 2))), pw)
						roundLabel.Text = roundLabel.Text .. "\n" .. goal
					end
				else
					roundLabel.RichText = false
					roundLabel.TextTruncate = Enum.TextTruncate.None
					local pw = roundLabel.AbsoluteSize.X
					pcall(function() pw = Layout.rects(root.AbsoluteSize.X, root.AbsoluteSize.Y).round.w end)
					roundLabel.TextSize = Layout.fitRoundText(roundLabel.Text, math.min(baseSize, math.max(Layout.ROUND_TEXT_MIN, Layout.roundLineSize(ih, 1))), pw) -- one line: fits the scroll in width and height
				end
				end
			end
	end

	function self.update(state)
		lastState = state or lastState
		local size = root.AbsoluteSize
		local on = Flags.gameplay() == 2 and lastState ~= nil and lastState.phase == "playing" and deps.handFrame.Visible and Layout.fits(size.X, size.Y)
		active = on
		if deps.deckWidget then deps.deckWidget.Visible = Layout.deckWidgetShown(lastState and lastState.phase) end
		shell(on)
		if not on then
			pcall(function() require(script.Parent.BossCardFX).hide() end)
			if lastState and lastState.roundScore ~= nil and lastState.phase ~= "playing" then pcall(self.writeNumeral); self.handOff() end
			if self.prev and lastState and lastState.phase ~= "playing" then -- the round just ended: a cleared target gets its plate
				local lines = Moments.clearLines(self.prev, lastState)
				self.prev = nil
				if lines then
					pcall(function() require(script.Parent.ShopSummaryPlate).remember(lines) end) -- stays on the Counter
					-- one popup: an ordinary clear is the Round Complete plate (RoundRewardBanner, it takes the Score line from here); only the Night plate stays
					pcall(function() require(script.Parent.RoundRewardBanner).rememberScore(lines.score) end)
					if lines.night then pcall(function() require(script.Parent.Gameplay2MomentsFX).clear(root, lines) end) end
				end
			end
			pcall(function() require(script.Parent.NightIntroFX).reset(layer) end) -- the next round shows its intro again
			fanHand(false, size.Y); restoreOld()
			if game:GetService("RunService"):IsStudio() and lastState and lastState.phase ~= "playing" then -- Studio only: no gold frame may stay lit off the table
				for _, d in ipairs(deps.actionFrame:GetDescendants()) do
					if (d.Name == "GoldFrame" or d.Name == "GoldInner") and d.Visible then warn("[SortChrome] visible off the table: " .. d:GetFullName()) end
				end
			end
			-- the "TARGET CLEARED!" shout of the last hand must not hang over the Counter
			local jb = root:FindFirstChild("ScoreJuiceBanner")
			if jb and jb:IsA("TextLabel") and lastState and lastState.phase ~= "playing" then jb.TextTransparency = 1; jb.TextStrokeTransparency = 1 end
			return
		end
		local key = sceneKey(lastState)
		local bossRef = key == "table_boss" and TableArt.table_boss_ref or nil -- the Boss round draws the painted red-lit reference tavern; the old scene is the fallback
		local img = bossRef or (key == "table_play" and (TableArt.table_play_ref or TableArt.table_play)) or TableArt[key] or "" -- normal rounds keep the reference tavern
		if scene.Image ~= img then
			scene.Image = img
			if game:GetService("RunService"):IsStudio() then print(string.format("[PlayTableBg] bg=%s %s", key == "table_play" and "table_play_ref" or (bossRef and "table_boss_ref" or key), img)) end
		end
		if lifeAttach() then life.scene(bossRef and "table_play" or key); life.place(size.X, size.Y) end -- the boss reference tavern has the reference layout, so it uses its candle spots
		fitBanner()
		self.writeNumeral()
		scoreProgress.Text = string.format("%d of %d", math.floor(lastState.roundScore or 0), math.floor(lastState.targetScore or 0))
		setText(target, string.format("Target: %d", math.floor(lastState.targetScore or 0)))
		setText(tips, string.format("Tips: %d", math.floor(lastState.tips or 0)))
		do -- the Hands and Discards pills tick (pop) when their count changes
			local function ticked(pill, text)
				local w = pill:FindFirstChild("Word") or pill:FindFirstChild("Value")
				local old = w and w.Text or nil
				setText(pill, text)
				if old and old ~= text and old ~= "" then
					pcall(function() require(script.Parent.Gameplay2FeelFX).tick(pill, old, text) end)
				end
			end
			ticked(handsPill, string.format("Hands: %d", math.floor(lastState.handsRemaining or 0)))
			ticked(discardsPill, string.format("Discards: %d", math.floor(lastState.discardsRemaining or 0)))
		end
		local remaining = 0
		for _, suit in pairs(lastState.deckCounts or {}) do
			for _, n in pairs(suit) do remaining = remaining + (tonumber(n) or 0) end
		end
		setText(deckPill, DeckCountText.spaced(remaining, lastState.deckView))
		apply()
		self.prev = { phase = "playing", targetScore = lastState.targetScore, roundScore = lastState.roundScore, tips = lastState.tips,
			round = lastState.round, night = lastState.night, nightCap = lastState.nightCap, endless = lastState.endless, bossModifier = lastState.bossModifier }
		pcall(function() -- a thin gold thread between neighbouring Patrons that share a theme (Client/Gameplay2SynergyFX)
			local ids = {}
			for i, o in ipairs(lastState.ownedPatrons or {}) do ids[i] = o.id end
			require(script.Parent.Gameplay2SynergyFX).update(layer, Layout.rects(size.X, size.Y), ids)
		end)
		pcall(function() require(script.Parent.Gameplay2MomentsFX).boss(layer, Layout.rects(size.X, size.Y), lastState, size.X, size.Y) end)
		pcall(function() require(script.Parent.NightIntroFX).update(layer, lastState, size.X, size.Y) end) -- Night N, the room and the rule, 1.2 s, tap to skip, none in Calm
		if not self.checked and game:GetService("RunService"):IsStudio() then
			self.checked = true
			task.delay(1.5, function() pcall(self.selfCheck) end)
		end
		if deps.selectedCount then -- the guided first hand hint (Engine/GuidedHand), display only
			pcall(function()
				require(script.Parent.GuidedHint).update(layer, lastState, deps.selectedCount(), deps.firstCard and deps.firstCard(), deps.playButton, Layout.rects(size.X, size.Y), deps.cards and deps.cards())
			end)
			pcall(function() -- the Patron Power panel at the left of the table (Engine/PatronPowerPanel)
				require(script.Parent.PatronPowerPanelFX).update(layer, lastState, Layout.rects(size.X, size.Y), size.X, size.Y)
			end)
			pcall(function() -- boss round: the Boss card, health bar and glow (Engine/BossCard)
				require(script.Parent.BossCardFX).update(layer, lastState, Layout.rects(size.X, size.Y), size.X, size.Y)
			end)
			pcall(function() -- the three hint plates of the first rounds (Engine/RoundHints), beside the score stage
				require(script.Parent.RoundHintsFX).update(layer, lastState, deps.selectedCount(), Layout.rects(size.X, size.Y), size.X, size.Y)
			end)
		end
	end

	-- the hint plate keeps its old spot when the root is rescaled (DebugGoto scale, a resized window): place it again from the new size
	local function replaceHint()
		if not (active and lastState and deps.selectedCount) then return end
		local size = root.AbsoluteSize
		pcall(fitBanner) -- the Night and Round text follows the new scroll size
		pcall(function() require(script.Parent.PatronPowerPanelFX).update(layer, lastState, Layout.rects(size.X, size.Y), size.X, size.Y) end) -- the Patron Power panel is re-placed (or hidden when nothing fits) at the new size
		pcall(function() require(script.Parent.BossCardFX).update(layer, lastState, Layout.rects(size.X, size.Y), size.X, size.Y) end)
		pcall(function() require(script.Parent.RoundHintsFX).update(layer, lastState, deps.selectedCount(), Layout.rects(size.X, size.Y), size.X, size.Y) end)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if active then apply(); replaceHint() end end)
	for _, inst in ipairs({ deps.actionFrame, deps.playButton, deps.discardButton }) do -- another module moved the real controls off their rects: put them back at once
		inst:GetPropertyChangedSignal("Position"):Connect(function()
			if active and not self.applying then
				self.applying = true
				pcall(apply)
				self.applying = false
			end
		end)
	end
	-- other modules rewrite their own Position now and then; this keeps the v2 layout the last word (no per frame work)
	task.spawn(function()
		while layer.Parent do
			task.wait(0.25)
			if active then
				replaceHint()
				pcall(shell, true)
				local ok, err = pcall(apply)
				if not ok and not self.warned then self.warned = true; warn("[Gameplay2] apply stopped on an error: " .. tostring(err)) end
			end
		end
	end)
	current = self
	return self
end

function M.isActive()
	return current ~= nil and current.isActive()
end

-- a hand was played (ScorePopup): the name flair, nothing when the v2 table is not up or the flair has no room
function M.flair(preview)
	if not current then return end
	pcall(current.flair, preview)
end

-- the hub passes its live hand preview (Engine/HandPreview) whenever the selection changes, nil when nothing is selected
function M.setPreview(preview, handLevels)
	if not current then return end
	local lv = preview and PreviewRules.levelOf(handLevels, preview.name)
	local text = preview and PreviewRules.line(preview, lv) or nil
	if current.previewText == text then return end
	current.previewText = text
	current.previewRich = preview and PreviewRules.rich(preview, lv) or nil
	if current.isActive() then pcall(current.refresh) end
end

-- where the played cards land (root-relative { top, bottom }), nil when the v2 table is not up: below the centre score block
-- ScorePopup: true while a hand is being scored (the score block is compact so the played cards stand clear under it)
function M.setPlaying(on)
	if not current then return end
	local v = on == true
	if current.playing == v then return end
	current.playing = v
	if not v then current.scoringText = nil end
	if current.hideHand and (current.isActive() or not v) then pcall(current.hideHand, v) end
	if current.isActive() then pcall(current.refresh) end
end

-- the scoring moment's reserved rects in root pixels (plate, hand name banner row, played band, stage), nil when the v2 table is not up
function M.scoringRects()
	if not (current and current.isActive()) then return nil end
	local r = current.rects()
	local L = require(Engine:WaitForChild("Gameplay2Layout"))
	local capH = math.max(20, PreviewRules.H)
	local rows = L.scoringRows(r, capH)
	local live = require(Engine:WaitForChild("Gameplay2ScorePlate")).live(r.stage, current.rootW and current.rootW() or r.stage.w * 1.5, capH, 22, true)
	return { stage = r.stage, plate = live.plate, name = rows.name, band = rows.band }
end

-- the lift for a picked hand card on the v2 table (28 px, less when the Score plate sits close above the hand), nil when v2 is not up
function M.selectedLift(want, restTop)
	if not (current and current.isActive()) then return nil end
	local L = require(Engine:WaitForChild("Gameplay2Layout"))
	local lift = L.selectedLift(current.rects(), want, math.max(20, PreviewRules.H))
	local progBottom
	pcall(function()
		local gui = game:GetService("Players").LocalPlayer.PlayerGui
		local row = gui:FindFirstChild("ScoreProgress", true)
		if row and row.Visible then progBottom = row.AbsolutePosition.Y + row.AbsoluteSize.Y end
	end)
	return L.capLift(lift, restTop, progBottom)
end

function M.playedBand()
	if not (current and current.isActive()) then return nil end
	current.playing = true
	if current.hideHand then pcall(current.hideHand, true) end
	pcall(current.refresh)
	local r = current.rects()
	return require(Engine:WaitForChild("Gameplay2Layout")).playedBand(r, math.max(20, PreviewRules.H), 22)
end

-- where discarded cards fly (root pixels), nil when the v2 table is not up: the bottom right, under the deck count
function M.discardPoint()
	if not (current and current.isActive()) then return nil end
	local r = current.rects()
	local size = current.size()
	local x, y = require(Engine:WaitForChild("Gameplay2Feel")).discardPoint(r, size.X, size.Y)
	return x, y
end

-- the Play Hand or Discard press with nothing selected: a short shake, no popup (the hub still shows its hint)
function M.shakeFor(which)
	if not (current and current.isActive()) then return end
	current.shake(which)
end

function M.update(state)
	if current then current.update(state) end
end

-- the payout landed: the Score plate's numeral shows the new round total even while the round-ending state is held back
function M.landScore(score)
	if current and current.landScore then current.landScore(score) end
end

return M
