--[[
	Client/Table3D/Cards.lua
	The cards on the felt. The 2D hand (the hub's slots and buttons) and the score reveal's ghosts keep doing what they
	always did: layout, input, tooltips, the tutorial's rectangles, every tween. They only stop drawing. Each of them
	gets a card on the table instead, a thin part with the card's face on top, and that card stands, every frame, where
	its 2D twin is on screen (Rig.pointUnder), so nothing about the game's rules or timing lives here.

	  the 2D twin moves up a few pixels (hover, selected)   -> the card rises off the felt and leans to the camera
	  the 2D twin pops to 1.22 times its size (a scoring beat) -> the card jumps
	  the 2D twin travels fast (a deal, a play)              -> the card is carried a little above the table
	  the 2D deal overlay closes (Client/DealFlip)           -> the card turns over
	  the 2D twin is gone from the new hand                  -> the card flies to the deck, face down

	The face itself is the hub's own: the button's picture, rank and suit, badges and marks are moved onto the part's
	face (and anything a module adds to the button later follows), so a card can never show something else in 3D.

	Cards.start{ scene, theme, deck, calm }
	Cards.syncHand(handFrame, handData, backId)   after the hub rebuilt the hand
	Cards.adoptGhosts(entries)                    the reveal's ghosts take over the played cards
	Cards.count() -> hand, all
]]

local RunService = game:GetService("RunService")
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local TS = require(Engine:WaitForChild("TableScene"))
local Rig = require(script.Parent.Rig)

local Cards = {}

local K = 2 -- canvas pixels per screen pixel: a card that is lifted toward the camera stays sharp
-- A part's top face draws its picture with the picture's width along the part's Z axis and its top toward -X. So the
-- part lies with X as the card's height, turned a quarter so the picture's top points away from the player.
local FACE = CFrame.Angles(0, -math.pi / 2, 0)
local UNIQUE = { CardFace = true, CardArt = true, FocusDim = true, ScoreHighlight = true }
local MIRRORED = { OutMark = true } -- looked up by name on the button (Client/CardOutMark): the button keeps it, hidden

local deps = nil
local folder = nil
local avatars = {} -- every card on the table
local byProxy = {} -- GuiObject -> avatar
local handNow = {} -- the hand's avatars, left to right
local back = { image = nil, color = Color3.fromRGB(50, 70, 110) }

local function calm()
	return deps and deps.calm and deps.calm() == true
end

-- the equipped card back, for the underside (the same lookup Client/DealFlip makes)
local function readBack(backId)
	pcall(function()
		local CardBacks = require(Engine:WaitForChild("CardBacks"))
		local id = backId or CardBacks.DefaultId
		local entry = CardBacks.getById(id) or CardBacks.getById(CardBacks.DefaultId)
		local base = entry and entry.colors and entry.colors.base
		if base then back.color = Color3.fromRGB(base[1], base[2], base[3]) end
		back.image = require(script.Parent.Parent.CardBackView).imageFor(id)
	end)
end

local function newAvatar()
	local part = Instance.new("Part")
	part.Name = "Card"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(3.77, TS.CARD.thickness, 2.6)
	part.CastShadow = true
	deps.scene.paint(part, "cardEdge")

	-- the gold of a hovered or selected card: a glowing edge all round it, a hair wider than the card
	local halo = Instance.new("Part")
	halo.Name = "Halo"
	halo.Anchored = true
	halo.CanCollide = false
	halo.CanQuery = false
	halo.CanTouch = false
	halo.CastShadow = false
	halo.Material = Enum.Material.Neon
	halo.Transparency = 1
	halo.Size = Vector3.new(3.9, TS.CARD.thickness * 0.5, 2.7)

	local look = deps.theme.Lighting.cards or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(228, 330)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.LightInfluence = look.lightInfluence or 1
	gui.Brightness = look.brightness or 1
	gui.Parent = part

	local face = Instance.new("Frame")
	face.Name = "Paper"
	face.BorderSizePixel = 0
	face.Size = UDim2.fromOffset(114, 165)
	face.ZIndex = 0
	face.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = K
	scale.Parent = face

	local under = Instance.new("SurfaceGui")
	under.Name = "Back"
	under.Face = Enum.NormalId.Bottom
	under.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	under.CanvasSize = Vector2.new(228, 330)
	under.LightInfluence = look.lightInfluence or 1
	under.Brightness = look.brightness or 1
	under.Parent = part
	local backFill = Instance.new("Frame")
	backFill.Size = UDim2.fromScale(1, 1)
	backFill.BorderSizePixel = 0
	backFill.BackgroundColor3 = back.color
	backFill.Parent = under
	if back.image then
		local art = Instance.new("ImageLabel")
		art.Size = UDim2.fromScale(1, 1)
		art.BackgroundTransparency = 1
		art.Image = back.image
		art.ScaleType = Enum.ScaleType.Crop
		art.Parent = backFill
	end

	local av = {
		part = part, gui = gui, under = under, face = face, halo = halo,
		h = TS.CARD.rest, hv = 0, flip = 0, roll = 0, blend = 0, age = 0,
		basisW = 114, basisH = 165, mirrors = {}, conns = {}, mode = "hand", order = 0,
	}
	avatars[#avatars + 1] = av
	return av
end

local function drop(av)
	for _, c in ipairs(av.conns) do c:Disconnect() end
	av.conns = {}
	if av.proxy and byProxy[av.proxy] == av then byProxy[av.proxy] = nil end
	av.proxy = nil
end

local function remove(av)
	drop(av)
	for i, other in ipairs(avatars) do
		if other == av then table.remove(avatars, i) break end
	end
	for i, other in ipairs(handNow) do
		if other == av then table.remove(handNow, i) break end
	end
	av.part:Destroy()
	av.halo:Destroy()
	av.dead = true
end

-- one child of a 2D twin goes onto the card's face
local function rehome(av, child)
	if av.dead or not child or not child.Parent or child.Parent ~= av.proxy then return end
	if not child:IsA("GuiObject") then
		if child:IsA("UIStroke") then child.Enabled = false end -- the hub keeps tweening it; the card's own rim copies it
		return
	end
	local name = child.Name
	if name == "DealBack" then -- Client/DealFlip's overlay: it stays, unseen, and its closing turns the card over
		child.Visible = false
		if av.mode == "hand" then
			av.dealBack = child
			av.flip = 1
		end
		return
	end
	if MIRRORED[name] then
		if av.mirrors[child] then return end
		local stale = av.face:FindFirstChild(name)
		if stale then stale:Destroy() end
		local twin = child:Clone()
		twin.Visible = true
		twin.Parent = av.face
		av.mirrors[child] = twin
		child.Visible = false
		child.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				twin:Destroy()
				av.mirrors[child] = nil
			end
		end)
		return
	end
	if UNIQUE[name] then
		local old = av.face:FindFirstChild(name)
		if old and old ~= child then old:Destroy() end
	end
	child.Parent = av.face
end

local function attach(av, proxy, fresh)
	drop(av)
	av.proxy = proxy
	byProxy[proxy] = av
	av.scale = proxy:FindFirstChildOfClass("UIScale")
	av.proxyStroke = proxy:FindFirstChild("SelectionStroke")
	av.dealBack = nil
	if fresh then
		-- a rebuilt hand button carries the newest face: the old pieces go
		for _, piece in ipairs(av.face:GetChildren()) do
			if piece:IsA("GuiObject") then piece:Destroy() end
		end
		av.mirrors = {}
		if proxy:IsA("GuiObject") then
			av.face.BackgroundColor3 = proxy.BackgroundColor3
			proxy.BackgroundTransparency = 1
		end
		local corner = proxy:FindFirstChildOfClass("UICorner")
		if corner and not av.face:FindFirstChildOfClass("UICorner") then corner:Clone().Parent = av.face end
	end
	for _, child in ipairs(proxy:GetChildren()) do rehome(av, child) end
	av.conns[#av.conns + 1] = proxy.ChildAdded:Connect(function(child)
		task.defer(rehome, av, child) -- builders parent first and fill in after: wait for them to finish
	end)
end

local function seen(gui)
	local node = gui
	while node and not node:IsA("LayerCollector") do
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	return node ~= nil and node.Enabled
end

local function setShown(av, shown)
	if av.shown == shown then return end
	av.shown = shown
	av.part.Parent = shown and folder or nil
	if not shown then av.halo.Parent = nil end
end

-- an unmatched card leaves the table: to the deck, turning face down on the way
local function leave(av)
	if av.mode == "leaving" then return end
	drop(av)
	for i, other in ipairs(handNow) do
		if other == av then table.remove(handNow, i) break end
	end
	if not av.shown or calm() then remove(av) return end
	av.mode = "leaving"
	av.halo.Parent = nil
	local to = nil
	local deck = deps.deck
	if deck and deck.Parent and seen(deck) then
		to = Rig.pointUnder(deck.AbsolutePosition.X + deck.AbsoluteSize.X / 2, deck.AbsolutePosition.Y + deck.AbsoluteSize.Y / 2, 0.2)
	end
	to = to or (av.part.Position + Vector3.new(26, 0.4, -3))
	av.leaving = { t = 0, dur = 0.3 + (av.order % 5) * 0.03, from = av.part.CFrame, to = to }
end

local function stepLeaving(av, dt)
	local l = av.leaving
	l.t = l.t + dt / l.dur
	if l.t >= 1 then remove(av) return end
	local e = l.t * l.t * (3 - 2 * l.t)
	local p = TS.arcPoint({ l.from.X, l.from.Y, l.from.Z }, { l.to.X, l.to.Y, l.to.Z }, 1.3, e)
	av.part.CFrame = CFrame.new(p[1], p[2], p[3]) * l.from.Rotation * CFrame.Angles(math.pi * e, 0, 0) -- (the part's X is the card's long axis)
end

local function follow(av, proxy, dt, quiet)
	local pos, size = proxy.AbsolutePosition, proxy.AbsoluteSize
	if size.X < 2 or size.Y < 2 then setShown(av, av.mode == "ghost" and av.shown or false) return end
	local cx, cy = pos.X + size.X / 2, pos.Y + size.Y / 2
	-- A hand card is held up to the player: it stands in a plane that leans back from where the hand row's lower edge
	-- meets the felt. A played card (a ghost) lies on the felt.
	local slot = av.mode == "hand" and proxy.Parent or nil
	local footZ = nil
	if slot and slot:IsA("GuiObject") then
		local _, foot = Rig.pointUnder(cx, slot.AbsolutePosition.Y + slot.AbsoluteSize.Y, 0)
		footZ = foot and foot[3] or nil
	end
	local feltAt, feltPoint
	if footZ then
		local p0, n = TS.leanPlane(footZ, TS.STAND.hand, 0)
		feltAt, feltPoint = Rig.pointOnPlane(cx, cy, p0, n)
	else
		feltAt, feltPoint = Rig.pointUnder(cx, cy, 0)
	end
	if not feltAt then return end
	local spp = Rig.studsPerPixel(feltPoint)
	local s = av.scale and av.scale.Scale or 1
	local grow = math.max(1, s)
	local wPx, hPx = size.X / grow, size.Y / grow

	-- how far above its resting place the 2D twin stands (hover, selected)
	local liftPx = 0
	if slot and slot:IsA("GuiObject") and not slot:GetAttribute("Dealing") then
		local sp, ss = slot.AbsolutePosition, slot.AbsoluteSize
		local restX = sp.X + ss.X / 2 + (slot:GetAttribute("FanX") or 0)
		local restY = sp.Y + ss.Y / 2 + (slot:GetAttribute("FanY") or 0)
		if math.abs(cx - restX) < ss.X * 0.6 then liftPx = math.clamp(restY - cy, 0, 40) end
		local shadow = slot:FindFirstChild("ContactShadow") -- the 2D hand's painted shadow: the table casts a real one
		if shadow and shadow.Visible then shadow.Visible = false end
	end
	local pop = s
	if av.extraScale and av.extraGhost and av.extraGhost.Parent and av.extraGhost.Visible then
		pop = math.max(pop, av.extraScale.Scale)
	end
	local speed = 0
	if av.lastC and dt > 0 then speed = (Vector2.new(cx, cy) - av.lastC).Magnitude / dt end
	av.lastC = Vector2.new(cx, cy)
	local carried = TS.LIFT.travel * math.clamp(speed / 1400, 0, 1)

	local rest = TS.CARD.rest + av.order * TS.CARD.stackStep
	local target = rest + TS.liftFor(liftPx, pop, spp) + carried
	if quiet then
		av.h, av.hv = target, 0
	else
		av.h, av.hv = TS.spring(av.h, av.hv, target, dt)
		if av.h < rest then av.h, av.hv = rest, math.abs(av.hv) * 0.25 end -- it lands on the felt, it does not sink in
	end

	-- the deal overlay closes: the card turns over
	local flipTo = 0
	local db = av.dealBack
	if db then
		if db.Parent then flipTo = math.clamp(db.Size.X.Scale, 0, 1) else av.dealBack = nil end
	end
	if quiet then av.flip = flipTo else av.flip = av.flip + (flipTo - av.flip) * math.min(1, dt * 16) end
	if av.flip < 0.004 then av.flip = 0 end

	local w, h = math.max(0.05, wPx * spp), math.max(0.05, hPx * spp)
	local height = av.h + TS.CARD.thickness / 2 + math.sin(av.flip * math.pi) * w * 0.5
	if av.blend > 0 and av.blendFrom then -- the further a kept card has to go, the higher it is carried
		if not av.blendAmp then
			local gap = Vector3.new(feltAt.X - av.blendFrom.X, 0, feltAt.Z - av.blendFrom.Z).Magnitude
			av.blendAmp = math.min(0.45, gap * 0.2)
		end
		height = height + math.sin(av.blend * math.pi) * av.blendAmp
	end
	local at
	if footZ then
		local p0, n = TS.leanPlane(footZ, TS.STAND.hand, height)
		at = Rig.pointOnPlane(cx, cy, p0, n)
	else
		at = Rig.pointUnder(cx, cy, height)
	end
	if not at then return end
	local standTo = footZ and math.rad(90 - TS.STAND.hand) or 0 -- how far the card is raised from lying flat
	av.stand = quiet and standTo or (av.stand or standTo) + (standTo - (av.stand or standTo)) * math.min(1, dt * 14)
	if av.blend > 0 and av.blendFrom then -- a kept card glides to its new slot
		av.blend = quiet and 0 or math.max(0, av.blend - dt / 0.2)
		local e = av.blend * av.blend
		at = at:Lerp(av.blendFrom, e)
	end

	local rollTo = 0
	if av.lastAt and dt > 0 and not quiet then rollTo = math.clamp((at.X - av.lastAt.X) / dt * 0.012, -0.3, 0.3) end
	av.lastAt = at
	av.roll = av.roll + (rollTo - av.roll) * math.min(1, dt * 10)

	local lifted = math.clamp((av.h - rest) / TS.LIFT.tiltAt, 0, 1)
	av.part.Size = Vector3.new(h, TS.CARD.thickness, w)
	av.part.CFrame = CFrame.new(at)
		* CFrame.Angles(av.stand, 0, 0)
		* CFrame.Angles(0, -math.rad(proxy.AbsoluteRotation), 0)
		* CFrame.Angles(math.rad(TS.LIFT.tilt) * lifted, 0, av.roll)
		* CFrame.Angles(0, 0, math.pi * av.flip)
		* FACE

	-- the face's canvas follows the hand's card size (a resized window, a longer hand)
	if av.mode == "hand" and s >= 0.99 and wPx > 20 then
		local bw, bh = math.floor(wPx + 0.5), math.floor(hPx + 0.5)
		if math.abs(bw - av.basisW) > 1 or math.abs(bh - av.basisH) > 1 then
			av.basisW, av.basisH = bw, bh
			av.gui.CanvasSize = Vector2.new(bw * K, bh * K)
			av.under.CanvasSize = Vector2.new(bw * K, bh * K)
			av.face.Size = UDim2.fromOffset(bw, bh)
		end
	end

	if proxy.BackgroundTransparency ~= 1 then proxy.BackgroundTransparency = 1 end -- the 2D twin never draws
	setShown(av, true)
	-- the hub still drives its (unseen) selection stroke; the card's glowing edge copies it
	local ps = av.proxyStroke
	local halo = av.halo
	if ps and ps.Parent and ps.Transparency < 0.97 and av.flip < 0.5 then
		local margin = math.max(1.5, ps.Thickness) * spp * 1.1
		halo.Size = Vector3.new(h + margin * 2, TS.CARD.thickness * 0.5, w + margin * 2)
		halo.CFrame = av.part.CFrame * CFrame.new(0, -TS.CARD.thickness * 0.3, 0)
		halo.Color = ps.Color
		halo.Transparency = math.max(0.12, ps.Transparency)
		if halo.Parent ~= folder then halo.Parent = folder end
	elseif halo.Parent then
		halo.Parent = nil
	end
end

local function step(dt)
	local quiet = calm()
	for i = #avatars, 1, -1 do
		local av = avatars[i]
		if av.mode == "leaving" then
			stepLeaving(av, dt)
		else
			local proxy = av.proxy
			if not proxy or not proxy.Parent then
				if av.mode == "ghost" then
					remove(av) -- the reveal put its ghost away
				else
					av.orphan = (av.orphan or 0) + dt
					if av.orphan > 0.5 then leave(av) end -- the hand went without a new one being built
				end
			else
				av.orphan = nil
				av.age = av.age + 1
				if av.age < 2 or not seen(proxy) then
					if av.age >= 2 then setShown(av, false) end
				else
					local ok, err = pcall(follow, av, proxy, dt, quiet)
					if not ok and not av.warned then
						av.warned = true
						warn("[Table3D] a card could not be placed: " .. tostring(err))
					end
				end
			end
		end
	end
end

function Cards.start(d)
	deps = d
	folder = Instance.new("Folder")
	folder.Name = "Cards"
	folder.Parent = d.scene.model
	RunService:BindToRenderStep("Table3DCards", Enum.RenderPriority.Camera.Value + 2, step)
end

function Cards.syncHand(handFrame, handData, backId)
	if not deps then return end
	readBack(backId)
	local slots = {}
	for _, child in ipairs(handFrame:GetChildren()) do
		if child:IsA("Frame") and child:GetAttribute("HandIndex") then slots[#slots + 1] = child end
	end
	table.sort(slots, function(a, b) return a.LayoutOrder < b.LayoutOrder end)

	local oldSigs, newSigs, buttons = {}, {}, {}
	for i, av in ipairs(handNow) do oldSigs[i] = av.sig end
	for i, slot in ipairs(slots) do
		local card = handData and handData[slot:GetAttribute("HandIndex")]
		newSigs[i] = TS.signature(card)
		buttons[i] = slot:FindFirstChildWhichIsA("GuiButton")
	end
	local match = TS.matchHands(oldSigs, newSigs)

	local kept, nextHand = {}, {}
	for i = 1, #slots do
		local button = buttons[i]
		if button then
			local av = match[i] and handNow[match[i]] or nil
			if av and av.mode == "hand" and not av.dead then
				kept[av] = true
				if av.shown then
					av.blend, av.blendFrom, av.blendAmp = 1, av.part.Position, nil
				end
			else
				av = newAvatar()
			end
			av.sig, av.order, av.mode = newSigs[i], i, "hand"
			-- (a held card keeps the ghost that lends it its scoring pop: the reveal may still be running)
			av.age = 0 -- the new slot has no place on screen until the next layout pass: one frame is skipped
			attach(av, button, true)
			nextHand[#nextHand + 1] = av
		end
	end
	local old = handNow
	handNow = nextHand
	for _, av in ipairs(old) do
		if not kept[av] and av.mode == "hand" and not av.dead then leave(av) end
	end
end

-- entries: the hub's score ghosts, each { ghost, scale, isPlayed, source = the hand button it was cloned from }
function Cards.adoptGhosts(entries)
	if not deps then return end
	for _, entry in ipairs(entries or {}) do
		local av = entry.source and byProxy[entry.source]
		local ghost = entry.ghost
		if av and ghost and not av.dead then
			local fresh = ghost:FindFirstChild("CardFace")
			if entry.isPlayed then
				-- the card on the table follows the ghost from here: to the played row, through its beats, to the deck
				for i, other in ipairs(handNow) do
					if other == av then table.remove(handNow, i) break end
				end
				drop(av)
				av.mode = "ghost"
				av.proxy = ghost
				byProxy[ghost] = av
				av.scale = entry.scale
				av.proxyStroke = ghost:FindFirstChild("SelectionStroke")
				for _, child in ipairs(ghost:GetChildren()) do rehome(av, child) end -- its newly built face (a True Wildcard shows what it became)
				av.conns[#av.conns + 1] = ghost.ChildAdded:Connect(function(child)
					task.defer(rehome, av, child) -- the reveal's dim and flash overlays
				end)
			else
				-- a held card stays in the hand; its hidden ghost only lends the pop of its own beat
				if fresh then fresh:Destroy() end
				av.extraScale, av.extraGhost = entry.scale, ghost
				ghost.ChildAdded:Connect(function(child)
					task.defer(function()
						if child.Parent == ghost and child:IsA("GuiObject") and not av.dead then
							if UNIQUE[child.Name] then
								local old = av.face:FindFirstChild(child.Name)
								if old and old ~= child then old:Destroy() end
							end
							child.Parent = av.face
						end
					end)
				end)
			end
		end
	end
end

function Cards.count()
	return #handNow, #avatars
end

-- the played cards on the table right now (the pot stands beside them)
function Cards.played()
	local out = {}
	for _, av in ipairs(avatars) do
		if av.mode == "ghost" and av.proxy and av.proxy.Parent and av.shown then out[#out + 1] = av.proxy end
	end
	return out
end

return Cards
