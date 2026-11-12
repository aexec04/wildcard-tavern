--[[
	Client/CardSetsRoom.lua
	The painted Card Sets shelf wall (cardsets_room_a) behind the Card Sets & Backs panel (Client/CosmeticSetsPanel.lua). Slots and paging
	come from the tested Engine/CardSetsSceneLayout.lua: the top plate row holds the two tabs (Card Sets, Card Backs) and the page
	controls, each of the ten framed velvet slots holds one set (a sample face and its back) or one card back, with its name, a Preview
	plate, and the action on the brass plaque under the frame (Equip, Equipped, Buy (n), Locked). Details of a locked entry are in its
	tooltip. The picture is cover-fitted with a soft vignette over uncovered edges (Client/PanelScene.lua), never stretched.

	CardSetsRoom.new(ctx) -> room
	  ctx = { panel, screenGui, roundCorner, playClickSfx, label, isOpen = fn, hide = { gui, ... } (plain widgets to hide),
	          CosmeticSets, CardBacks, CardBackView, SetSkin, getState = fn,
	          actions = { equipSet(id), buySet(id), equipBack(idOrNil), preview(name, setId, backId) }, backHint = fn(back) }
	room.layout() -> true when the painted room is on (sizes the panel and draws the picture, or restores the plain panel)
	room.paint()  rebuilds the tiles from the latest state
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FullScreen = require(script.Parent.PanelFullScreen)

local CardSetsRoom = {}

local CREAM = Color3.fromRGB(250, 240, 220)
local GOLD = Color3.fromRGB(255, 214, 130)
local INK = Color3.fromRGB(44, 26, 12)
local DIM_INK = Color3.fromRGB(88, 64, 40)
local BROWN = Color3.fromRGB(96, 66, 34)

function CardSetsRoom.new(ctx)
	local Layout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CardSetsSceneLayout"))
	local PanelScene = require(script.Parent.PanelScene)
	local addTip = require(script.Parent.Tooltip).new(ctx.screenGui).attach
	local scene = PanelScene.new(ctx.panel, { artKey = Layout.ART_KEY, def = Layout.DEF, z = 41 })
	local layer = Instance.new("Frame") -- tiles, plate texts and plaque buttons, over the picture
	layer.Name = "RoomLayer"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.Active = false
	layer.Visible = false
	layer.ZIndex = 42
	layer.Parent = ctx.panel

	local room = { on = false }
	local placed = nil
	local view = { tab = "sets", page = 1 }
	local lastKey = nil

	local function rectProps(r) return UDim2.fromOffset(r.x, r.y), UDim2.fromOffset(r.w, r.h) end

	-- a transparent button over a painted plate or plaque; ink text, a faint gold wash on hover
	local function plateButton(parent, rect, text, opts)
		opts = opts or {}
		local b = Instance.new("TextButton")
		b.AutoButtonColor = false
		b.BackgroundColor3 = opts.solid or GOLD
		b.BackgroundTransparency = opts.solid and 0 or (opts.active and 0.7 or 1)
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold
		b.TextSize = 14
		b.TextColor3 = opts.dim and DIM_INK or INK
		if opts.pill then -- cream on a small dark pill: readable on the brass plaque (cream straight on brass is only about 3.8:1)
			local pc, cc = Layout.COLORS.pill, Layout.COLORS.cream
			b.BackgroundColor3 = Color3.fromRGB(pc[1], pc[2], pc[3])
			b.BackgroundTransparency = 0.08
			b.TextColor3 = Color3.fromRGB(cc[1], cc[2], cc[3])
		end
		b.TextTransparency = 0
		b.TextStrokeTransparency = 1
		if opts.cream then -- plate labels on the dark painted plates: cream with a soft dark shadow (light text stroke)
			b.TextColor3 = CREAM
			b.TextStrokeColor3 = Color3.fromRGB(20, 12, 6)
			b.TextStrokeTransparency = 0.7
		end
		b.Text = text
		b.TextWrapped = true
		b.ZIndex = 44
		b.Position, b.Size = rectProps(rect)
		b.Parent = parent
		ctx.roundCorner(b, 4)
		if opts.onClick then
			if not opts.solid and not opts.pill then
				b.MouseEnter:Connect(function() if not opts.active then b.BackgroundTransparency = 0.82 end end)
				b.MouseLeave:Connect(function() b.BackgroundTransparency = opts.active and 0.7 or 1 end)
			end
			b.MouseButton1Click:Connect(function()
				ctx.playClickSfx()
				opts.onClick()
			end)
		end
		return b
	end

	local function entries(state)
		local out = {}
		if view.tab == "sets" then
			for _, set in ipairs(ctx.CosmeticSets.Definitions) do out[#out + 1] = { set = set } end
		else
			out[1] = { match = true }
			for _, back in ipairs(ctx.CardBacks.Definitions) do out[#out + 1] = { back = back } end
		end
		return out
	end

	-- a sample face tinted by the set (as in the old row preview) and the set's back
	local function setPreview(frame, parts, set, back, owned)
		local face = Instance.new("Frame")
		face.BackgroundColor3 = owned and Color3.fromRGB(246, 236, 214) or Color3.fromRGB(130, 130, 130)
		face.ZIndex = 44
		face.Position, face.Size = rectProps(parts.face)
		face.Parent = frame
		ctx.roundCorner(face, 5)
		local fs = Instance.new("UIStroke")
		fs.Thickness = 2
		local trim = back and back.colors.trim or { 205, 170, 95 }
		fs.Color = Color3.fromRGB(trim[1], trim[2], trim[3])
		fs.Parent = face
		local theme = ctx.CosmeticSets.themeOf(set)
		if owned and not theme.face.neutral then
			local p, b = theme.face.paper, theme.face.border
			face.BackgroundColor3 = Color3.fromRGB(p[1], p[2], p[3])
			fs.Color = Color3.fromRGB(b[1], b[2], b[3])
		end
		pcall(ctx.SetSkin.cardLayers, face, 44, "K", theme.skin)
		ctx.label(face, { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = Color3.fromRGB(60, 40, 22), Text = "K", ZIndex = 46 })
		local thumb = ctx.CardBackView.thumb(frame, back, { size = Vector2.new(parts.back.w, parts.back.h), locked = not owned, shimmer = false, zIndex = 44 })
		thumb.Position = UDim2.fromOffset(parts.back.x, parts.back.y)
	end

	local function paintTile(i, entry, frame, plaque, state)
		local cosmetics = state and state.cosmetics or { equippedSetId = ctx.CosmeticSets.DefaultId, unlockedSetIds = { ctx.CosmeticSets.DefaultId } }
		local parts = Layout.tileParts(frame)
		local holder = Instance.new("Frame")
		holder.Name = "Slot" .. i
		holder.BackgroundTransparency = 1
		holder.Position, holder.Size = rectProps(frame)
		holder.Active = true -- so its tooltip sees the pointer
		holder.ZIndex = 43
		holder.Parent = layer

		local name, owned, equipped, action, actionText, tipText, onPreview, onAction
		if entry.set then
			local set = entry.set
			local unlocked = {}
			for _, id in ipairs(cosmetics.unlockedSetIds or {}) do unlocked[id] = true end
			owned = unlocked[set.id] == true
			equipped = cosmetics.equippedSetId == set.id
			name = set.name
			setPreview(holder, parts, set, ctx.CardBacks.getById(set.cardBackId), owned)
			if equipped then
				actionText = "Equipped"
			elseif owned then
				actionText = "Equip"
				onAction = function() ctx.actions.equipSet(set.id) end
			elseif set.unlock.kind == "tips" then
				actionText = string.format("Buy (%d)", math.floor(set.unlock.price))
				onAction = function() ctx.actions.buySet(set.id) end
			else
				actionText = "Locked"
			end
			tipText = set.name .. ": " .. set.description .. (owned and "" or ("\n" .. ctx.CosmeticSets.unlockText(set)))
			onPreview = function() ctx.actions.preview(set.name, set.id, set.cardBackId) end
		else
			local back = entry.back
			local backsUnlocked = {}
			for _, id in ipairs(cosmetics.unlockedCardBackIds or { ctx.CardBacks.DefaultId }) do backsUnlocked[id] = true end
			owned = back == nil or backsUnlocked[back.id] == true
			if back == nil then equipped = cosmetics.pickedCardBackId == nil else equipped = cosmetics.pickedCardBackId == back.id end
			local shown = back or ctx.CardBacks.getById(cosmetics.cardBackId or ctx.CardBacks.DefaultId)
			name = back == nil and "Match my set" or back.name
			local thumb = ctx.CardBackView.thumb(holder, shown, { size = Vector2.new(parts.single.w, parts.single.h), equipped = equipped, locked = not owned, zIndex = 44,
				isActive = ctx.isOpen })
			thumb.Position = UDim2.fromOffset(parts.single.x, parts.single.y)
			if equipped then
				actionText = "Equipped"
			elseif owned then
				actionText = back == nil and "Use set's" or "Equip"
				onAction = function() ctx.actions.equipBack(back and back.id or nil) end
			else
				actionText = "Locked"
			end
			tipText = name .. (owned and "" or ("\n" .. ctx.backHint(back)))
			if back ~= nil then
				onPreview = function() ctx.actions.preview(back.name, cosmetics.equippedSetId or ctx.CosmeticSets.DefaultId, back.id) end
			end
		end

		-- name on two lines in the velvet, whole (a 38 px box fits two 14 px lines), no dots
		ctx.label(holder, { Position = UDim2.fromOffset(parts.name.x, parts.name.y), Size = UDim2.fromOffset(parts.name.w, parts.name.h), Font = Enum.Font.GothamBold, TextSize = 14,
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = owned and GOLD or Color3.fromRGB(215, 200, 178), Text = name, ZIndex = 45 })
		if onPreview then
			local pb = plateButton(holder, parts.preview, "Preview", { onClick = onPreview, solid = BROWN })
			pb.AutoButtonColor = true
			pb.TextColor3 = CREAM -- clean cream text on the brown plate: no stroke (a UIStroke on a button strokes its text and doubles it)
			pb.TextStrokeTransparency = 1
		end
		addTip(holder, tipText)
		-- the action lives on the brass plaque under the frame
		local pr = { x = plaque.x - 0, y = plaque.y, w = plaque.w, h = plaque.h }
		local pill = actionText == "Locked" or string.sub(actionText, 1, 3) == "Buy" -- cream on a dark pill; Equip and Equipped stay ink on the brass
		plateButton(layer, pr, actionText, { onClick = onAction, pill = pill, active = equipped })
	end

	-- the plate row: two tabs, then "Page n of m" and the arrows (plates stay intact and empty when there is one page)
	local function paintPlates(pages)
		local pl = placed.plates
		plateButton(layer, pl[1], "Card Sets", { cream = true, active = view.tab == "sets", onClick = function() view.tab, view.page = "sets", 1; room.paint() end })
		plateButton(layer, pl[2], "Card Backs", { cream = true, active = view.tab == "backs", onClick = function() view.tab, view.page = "backs", 1; room.paint() end })
		if pages > 1 then
			plateButton(layer, pl[3], "Page " .. view.page .. " of " .. pages, { cream = true })
			-- a disabled arrow draws nothing: its plate stays an intact, empty painted plate
			if view.page > 1 then plateButton(layer, pl[4], "< Prev", { cream = true, onClick = function() view.page = view.page - 1; room.paint() end }) end
			if view.page < pages then plateButton(layer, pl[5], "Next >", { cream = true, onClick = function() view.page = view.page + 1; room.paint() end }) end
		end
	end

	function room.paint()
		for _, ch in ipairs(layer:GetChildren()) do ch:Destroy() end
		if not room.on or not placed then return end
		local state = ctx.getState()
		local list = entries(state)
		local pageList, page, pages = Layout.pageSlice(list, view.page)
		view.page = page
		paintPlates(pages)
		for i, entry in ipairs(pageList) do
			if placed.frames[i] and placed.plaques[i] then paintTile(i, entry, placed.frames[i], placed.plaques[i], state) end
		end
	end

	function room.layout()
		local screen = ctx.screenGui.AbsoluteSize
		local pw, ph = Layout.panel(screen.X, screen.Y)
		pw, ph = FullScreen.fit(ctx.panel, pw, ph, screen.X, screen.Y) -- a full screen panel: the real screen below the tab strip
		local area = { x = 0, y = Layout.TOP, w = pw, h = ph - Layout.TOP - Layout.BOTTOM }
		local p = scene.id and Layout.place(area.w, area.h) or nil
		room.on = p ~= nil and p.ok and pw >= 640 and ph >= 520
		placed = nil
		if room.on then
			placed = p
			for _, group in ipairs({ p.plates, p.frames, p.plaques }) do
				for _, r in ipairs(group) do r.y = r.y + Layout.TOP end
			end
			FullScreen.setRect(ctx.panel, UDim2.fromOffset(pw, ph))
			scene.show(area, p)
		else
			FullScreen.setRect(ctx.panel, UDim2.fromScale(0.64, 0.84))
			scene.hide()
		end
		layer.Visible = room.on
		do local sh = ctx.panel.Parent and ctx.panel.Parent:FindFirstChild("Shadow"); if sh then sh.Visible = not room.on end -- the sibling drop shadow keeps the plain size and showed as a stray lighter rectangle behind the room
		end
		for _, g in ipairs(ctx.hide) do g.Visible = not room.on end
		if RunService:IsStudio() then
			local key = pw .. "x" .. ph .. (room.on and "on" or "off")
			if key ~= lastKey then
				lastKey = key
				local shownH = room.on and ph or math.floor(screen.Y * 0.84) -- the plain panel is 84 percent of the height
				local fit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PanelLayout")).fit(screen.Y, shownH)
				print(string.format("[PanelFit] cardsets screen=%dx%d panel=%dx%d top=%d bottom=%d fits=%s", screen.X, screen.Y, room.on and pw or math.floor(screen.X * 0.64), shownH, fit.top, fit.bottom, tostring(fit.fits)))
				print(string.format("[CardSetsRoom] %s slots=%d (plates %d, frames %d, plaques %d) panel %dx%d", room.on and "painted" or "plain",
					room.on and (#p.plates + #p.frames + #p.plaques) or 0, room.on and #p.plates or 0, room.on and #p.frames or 0, room.on and #p.plaques or 0, pw, ph))
			end
		end
		return room.on
	end

	return room
end

return CardSetsRoom
