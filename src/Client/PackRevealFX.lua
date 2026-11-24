--[[
	Client/PackRevealFX.lua
	The pack opening moment (numbers and state in Engine/PackReveal): every pick card starts face down on a painted back, a "Tap to open"
	plate sits over the panel, a tap shakes the cards 0.4 s and flashes gold, then the cards flip one at a time (0.25 s each, card_flip;
	Rare and above add a sparkle ring and patron_trigger). A Seat or Keep pill under each face-up card picks it, Take all opens everything.
	Calm mode and Reduce motion (reduceShake): nothing is face down, no overlay, no tween, no delayed cue.

	PackRevealFX.attach(panel, row, cards, items, rarities, opts) -> controller
	    cards[i] is a ShopCards card (slot, hit); opts.onPick(i) toggles the pick, opts.isPicked(i) reads it, opts.z is the base ZIndex.
	    controller.refresh() updates the pill words, controller.destroy() removes the overlay (call before a rebuild or when the panel closes).
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PackReveal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PackReveal"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local GOLD = Color3.fromRGB(246, 196, 70)
local CREAM = Color3.fromRGB(255, 240, 205)
local DARK = Color3.fromRGB(28, 18, 12)
local BACK = Color3.fromRGB(70, 40, 110)

local function setEdge(setId, rarity, isCalm)
	local look = PackReveal.look(setId, rarity, isCalm)
	return Color3.fromRGB(look.edge[1], look.edge[2], look.edge[3]), look.glow
end

local function calm() return ClientSettings.get("reduceShake") == true end

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
end

local function stroke(o, color, th)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = th
	s.Parent = o
	return s
end

local function cue(name)
	pcall(function() require(script.Parent.Cue).play(name) end)
end

local function pill(parent, name, text, size, pos, z, edge)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = pos
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.BackgroundColor3 = Color3.fromRGB(40, 94, 52)
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = CREAM
	b.TextStrokeColor3 = DARK
	b.TextStrokeTransparency = 0.4
	b.Text = text
	b.ZIndex = z
	b.Parent = parent
	corner(b, 8)
	stroke(b, edge or GOLD, 1)
	return b
end

function M.attach(panel, row, cards, items, rarities, opts)
	pcall(function() require(script.Parent.Cue).play("pack_open") end) -- the pack opens: its cards are laid out face down
	local isCalm = calm()
	local state = PackReveal.new(#items, isCalm)
	local plan = PackReveal.plan(rarities, isCalm)
	local z = opts.z or (panel.ZIndex + 20)
	local setId = nil
	pcall(function() setId = require(script.Parent.TavernKit).plateSetId() end)
	local edge = setEdge(setId, nil, isCalm)
	local ctl = {}
	local covers, pills, marks = {}, {}, {}
	local backImage = ""
	pcall(function()
		local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
		local ContentArt = require(Engine:WaitForChild("ContentArt"))
		backImage = ContentArt.getImageId("card_backs", opts.cardBackId or "classic") or ContentArt.getImageId("card_backs", "classic") or ""
	end)
	local overlay

	local function faceUp(i)
		local c = covers[i]
		if c and c.Parent then c:Destroy() end
		covers[i] = nil
		state.reveal(i)
		if pills[i] then pills[i].Visible = true end
		if marks[i] then marks[i].Visible = true end
	end

	function ctl.refresh()
		for i, p in pairs(pills) do
			if p.Parent then
				p.Text = PackReveal.keepWord(items[i].category, opts.isPicked(i))
			end
		end
	end

	function ctl.destroy()
		if overlay and overlay.Parent then overlay:Destroy() end
		overlay = nil
	end

	local function revealAllNow()
		state.revealAll() -- also marks the pack opened: canKeep needs it, so the Keep pill works after Skip all
		for i = 1, #items do faceUp(i) end
		ctl.destroy()
		ctl.refresh()
	end

	for i, card in ipairs(cards) do
		-- the Seat or Keep pill: a second, clear way to pick the card, shown once it is face up
		local p = pill(card.slot, "KeepPill", "", UDim2.fromOffset(110, 34), UDim2.new(0.5, 0, 1, 4), z + 2, edge)
		p.Visible = state.isRevealed(i)
		p.MouseButton1Click:Connect(function()
			if state.canKeep(i) then opts.onPick(i) end
		end)
		pills[i] = p
		-- the Owned or New mark: a small plate on the card's top corner, shown once it is face up
		local owned = opts.isOwned and opts.isOwned(i) == true
		local m = Instance.new("TextLabel")
		m.Name = "OwnedMark"
		m.AnchorPoint = Vector2.new(0, 0)
		m.Position = UDim2.fromOffset(4, 4)
		m.Size = UDim2.fromOffset(64, 24)
		m.BackgroundColor3 = owned and Color3.fromRGB(70, 60, 55) or Color3.fromRGB(40, 94, 52)
		m.BorderSizePixel = 0
		m.Font = Enum.Font.GothamBold
		m.TextSize = 16
		m.TextColor3 = CREAM
		m.Text = PackReveal.markWord(owned)
		m.ZIndex = z + 2
		m.Visible = state.isRevealed(i)
		m.Parent = card.slot
		corner(m, 6)
		marks[i] = m
		if not state.isRevealed(i) then
			local cover = Instance.new("TextButton") -- a button, so a click on a hidden card is swallowed
			cover.Name = "PackBack"
			cover.Size = UDim2.fromScale(1, 1)
			cover.BackgroundColor3 = BACK
			cover.BorderSizePixel = 0
			cover.AutoButtonColor = false
			cover.Text = ""
			cover.ZIndex = z
			cover.Parent = card.slot
			corner(cover, 10)
			stroke(cover, GOLD, 3)
			-- the painted card back (the equipped one, else the classic back), under the crest
			local art = Instance.new("ImageLabel")
			art.Name = "BackArt"
			art.Size = UDim2.fromScale(1, 1)
			art.BackgroundTransparency = 1
			art.BorderSizePixel = 0
			art.ScaleType = Enum.ScaleType.Crop
			art.Image = backImage
			art.ZIndex = z
			art.Parent = cover
			corner(art, 10)
			local crest = Instance.new("TextLabel")
			crest.Name = "Crest"
			crest.AnchorPoint = Vector2.new(0.5, 0.5)
			crest.Position = UDim2.fromScale(0.5, 0.5)
			crest.Size = UDim2.new(1, -12, 0, 28)
			crest.BackgroundTransparency = 1
			crest.Font = Enum.Font.Fondamento -- the serif face of the Counter titles
			crest.TextSize = 20
			crest.TextColor3 = GOLD
			crest.TextStrokeColor3 = DARK
			crest.TextStrokeTransparency = 0.2
			crest.TextTransparency = 0
			crest.Text = "Patron"
			crest.ZIndex = z + 1
			crest.Parent = cover
			cover.MouseButton1Click:Connect(function() if overlay then overlay:SetAttribute("Tap", true) end end)
			covers[i] = cover
		end
	end
	ctl.refresh()
	if isCalm or state.allRevealed() then return ctl end

	-- the overlay: a painted wood plate (Tap to open) and Skip all
	overlay = Instance.new("Frame")
	overlay.Name = "PackRevealOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex = z + 5
	overlay.Parent = panel
	local tap = Instance.new("TextButton")
	tap.Name = "TapToOpen"
	tap.AnchorPoint = Vector2.new(0.5, 0.5)
	tap.Position = UDim2.fromScale(0.5, 0.5)
	tap.Size = UDim2.fromOffset(260, 64)
	tap.BackgroundColor3 = DARK
	tap.BackgroundTransparency = 0.08
	tap.BorderSizePixel = 0
	tap.AutoButtonColor = true
	tap.Font = Enum.Font.GothamBold
	tap.TextSize = 24
	tap.TextColor3 = CREAM
	tap.TextStrokeColor3 = DARK
	tap.TextStrokeTransparency = 0.3
	tap.Text = PackReveal.TAP_WORD
	tap.ZIndex = z + 6
	tap.Parent = overlay
	corner(tap, 12)
	stroke(tap, edge, 2)
	local takeWord = PackReveal.takeAllWord(opts.pickCount, #items)
	local skip = pill(overlay, "TakeAll", takeWord, UDim2.fromOffset(160, PackReveal.TAKE_ALL_HEIGHT), UDim2.new(0.5, 0, 0.5, 48), z + 6, edge)

	local started = false
	local function open()
		if started then return end
		started = true
		state.open()
		tap.Visible = false
		skip.Visible = false
		cue("shuffle")
		-- the shake: the cards row jitters 0.4 s, then a gold flash, then the flips in order
		local home = row.Position
		local n = 6
		for k = 1, n do
			task.delay((k - 1) * plan.shake / n, function()
				if row.Parent then
					local dx = (k % 2 == 0 and 1 or -1) * PackReveal.SHAKE_PIXELS * (1 - k / (n + 1))
					row.Position = UDim2.new(home.X.Scale, home.X.Offset + dx, home.Y.Scale, home.Y.Offset)
				end
			end)
		end
		task.delay(plan.shake, function() if row.Parent then row.Position = home end end)
		local flash = Instance.new("Frame")
		flash.Name = "PackFlash"
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = GOLD
		flash.BackgroundTransparency = 1
		flash.BorderSizePixel = 0
		flash.Active = false
		flash.ZIndex = z + 7
		flash.Parent = overlay
		task.delay(plan.shake, function()
			if not flash.Parent then return end
			flash.BackgroundTransparency = 1 - PackReveal.FLASH_ALPHA
			TweenService:Create(flash, TweenInfo.new(plan.flash, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		end)
		for _, f in ipairs(plan.flips) do
			task.delay(f.at, function()
				if state.isRevealed(f.index) then return end -- Skip all got there first
				local cover = covers[f.index]
				if not (cover and cover.Parent) then return end
				cue(f.cue)
				local half = f.dur / 2
				local tw = TweenService:Create(cover, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Size = UDim2.new(0, 0, 1, 0), Position = UDim2.fromScale(0.5, 0) })
				tw:Play()
				task.delay(half, function()
					faceUp(f.index)
					ctl.refresh()
					if f.ring and cards[f.index] and cards[f.index].slot.Parent then
						local ring = Instance.new("Frame")
						ring.Name = "SparkleRing"
						ring.AnchorPoint = Vector2.new(0.5, 0.5)
						ring.Position = UDim2.fromScale(0.5, 0.45)
						ring.Size = UDim2.fromScale(0.9, 0.9)
						ring.BackgroundTransparency = 1
						ring.Active = false
						ring.ZIndex = z + 3
						ring.Parent = cards[f.index].slot
						corner(ring, 40)
						local st = stroke(ring, GOLD, 3)
						TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1.4, 1.4) }):Play()
						TweenService:Create(st, TweenInfo.new(0.5), { Transparency = 1 }):Play()
						task.delay(0.55, function() if ring.Parent then ring:Destroy() end end)
					end
				end)
			end)
		end
		task.delay(plan.flips[#plan.flips] and (plan.flips[#plan.flips].at + plan.flips[#plan.flips].dur) or plan.shake, function()
			ctl.destroy()
		end)
	end
	tap.MouseButton1Click:Connect(open)
	overlay:GetAttributeChangedSignal("Tap"):Connect(open) -- a tap on any face-down card opens the pack too
	skip.MouseButton1Click:Connect(function()
		started = true
		revealAllNow()
		if takeWord == PackReveal.SKIP_WORD then -- the pack keeps every card: Take all also picks them
			for i = 1, #items do if not opts.isPicked(i) then opts.onPick(i) end end
			ctl.refresh()
		end
	end)
	return ctl
end

return M
