--[[
	Client/CardSetsRoom.lua
	The Card Sets & Backs room (Client/CosmeticSetsPanel.lua) over the shared Collection wall. One large hero preview on the left (about 40
	percent): for a Card Set a mini table in its felt and rail colours, 5 ivory cards fanned with its accent edge and corner pips, its back on a
	stand, its name plate and one Equip or Buy button; for a Card Back the back large with a tilt and soft shadow. On the right a shelf of tiles,
	5 per row, each standing on a drawn shelf board (a mini table picture or a tilted back, name below, gold ring on the equipped one, padlock
	on locked ones). Clicking a tile selects it into the hero. Rects come from the tested Engine/CardSetsSceneLayout.room.

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
local BODY_TEXT = 14
local BROWN = Color3.fromRGB(96, 66, 34)

function CardSetsRoom.new(ctx)
	local Layout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CardSetsSceneLayout"))
	local addTip = require(script.Parent.Tooltip).new(ctx.screenGui).attach
	local wall = Instance.new("Frame") -- the shared painted Collection wall under a calm scrim (Client/RoomWall.lua)
	wall.Name = "RoomWall"
	wall.BorderSizePixel = 0
	wall.Size = UDim2.fromScale(1, 1)
	wall.Active = false
	wall.Visible = false
	wall.ClipsDescendants = true
	wall.ZIndex = 41
	wall.Parent = ctx.panel
	require(script.Parent.RoomWall).fill(wall, 41)
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
		b.TextSize = 15
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

	local function entries()
		local out = {}
		if view.tab == "sets" then
			for _, set in ipairs(ctx.CosmeticSets.Definitions) do out[#out + 1] = { key = set.id, set = set } end
		else
			out[1] = { key = "match", match = true }
			for _, back in ipairs(ctx.CardBacks.Definitions) do out[#out + 1] = { key = back.id, back = back } end
		end
		return out
	end

	local function rgb(c) return Color3.fromRGB(c[1], c[2], c[3]) end
	local function solid(parent, color, r, z, corner)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.ZIndex = z
		f.Position, f.Size = rectProps(r)
		f.Parent = parent
		if corner then ctx.roundCorner(f, corner) end
		return f
	end
	local function stroke(parent, color, thickness)
		local st = Instance.new("UIStroke")
		st.Color = color
		st.Thickness = thickness
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = parent
		return st
	end

	-- a framed mini table in the set's own felt and rail colours
	local function miniTable(parent, r, set, owned, z)
		local tint = ctx.CosmeticSets.tableTintOf(set)
		local felt = tint and tint.felt or { 52, 110, 78 }
		local wood = tint and tint.wood or { 150, 104, 60 }
		local rail = solid(parent, rgb(wood), r, z, 6)
		rail.Name = "SetSwatch"
		local inner = solid(rail, rgb(felt), { x = 4, y = 4, w = r.w - 8, h = r.h - 8 }, z + 1, 4)
		if not owned then rail.BackgroundTransparency = 0.45; inner.BackgroundTransparency = 0.45 end
		return rail, inner
	end

	-- one new ivory card: thin accent edge, accent corner pips, rank in the set's ink (frost sets add a pale inner edge)
	local function ivoryCard(parent, r, look, rank, red, z, owned)
		local card = solid(parent, rgb(look.paper), r, z, 4)
		stroke(card, rgb(look.edge), 1.5)
		local pip = math.max(3, math.floor(r.w * 0.1))
		for _, pos in ipairs({ { 3, 3 }, { r.w - 3 - pip, 3 }, { 3, r.h - 3 - pip }, { r.w - 3 - pip, r.h - 3 - pip } }) do
			solid(card, rgb(look.edge), { x = pos[1], y = pos[2], w = pip, h = pip }, z + 1, 1)
		end
		if look.motif == "frost" then
			local fr = solid(card, Color3.fromRGB(235, 245, 255), { x = 3, y = 3, w = r.w - 6, h = r.h - 6 }, z, 3)
			fr.BackgroundTransparency = 1
			stroke(fr, Color3.fromRGB(205, 228, 245), 1)
		end
		ctx.label(card, { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = math.max(11, math.floor(r.h * 0.34)),
			TextColor3 = rgb(red and look.ink.red or look.ink.black), Text = rank, ZIndex = z + 2 })
		if not owned then card.BackgroundTransparency = 0.35 end
		return card
	end

	local function padlock(parent, x, y, z)
		local body = solid(parent, Color3.fromRGB(214, 176, 92), { x = x, y = y + 7, w = 16, h = 12 }, z, 3)
		local shackle = solid(parent, Color3.fromRGB(0, 0, 0), { x = x + 3, y = y, w = 10, h = 11 }, z - 1, 5)
		shackle.BackgroundTransparency = 1
		stroke(shackle, Color3.fromRGB(214, 176, 92), 2.5)
		body.Name = "Padlock"
		return body
	end

	local function shadowOf(parent, r, z)
		local sh = solid(parent, Color3.fromRGB(10, 6, 3), { x = r.x + 4, y = r.y + 5, w = r.w, h = r.h }, z, 6)
		sh.BackgroundTransparency = 0.6
		sh.Name = "BackShadow"
		return sh
	end

	-- what an entry is, owned, equipped, its action and tooltip
	local function describe(entry, cosmetics)
		local d = {}
		if entry.set then
			local set = entry.set
			local unlocked = {}
			for _, id in ipairs(cosmetics.unlockedSetIds or {}) do unlocked[id] = true end
			d.owned = unlocked[set.id] == true
			d.equipped = cosmetics.equippedSetId == set.id
			d.name = set.name
			d.desc = set.description or ""
			if d.equipped then d.action = "Equipped"
			elseif d.owned then d.action = "Equip"; d.run = function() ctx.actions.equipSet(set.id) end
			elseif set.unlock.kind == "tips" then d.action = string.format("Buy (%d)", math.floor(set.unlock.price)); d.run = function() ctx.actions.buySet(set.id) end
			else d.action = "Locked" end
			d.tip = set.name .. ": " .. d.desc .. (d.owned and "" or ("\n" .. ctx.CosmeticSets.unlockText(set)))
			if not d.owned then d.desc = ctx.CosmeticSets.unlockText(set) end
		else
			local back = entry.back
			local backsUnlocked = {}
			for _, id in ipairs(cosmetics.unlockedCardBackIds or { ctx.CardBacks.DefaultId }) do backsUnlocked[id] = true end
			d.owned = back == nil or backsUnlocked[back.id] == true
			if back == nil then d.equipped = cosmetics.pickedCardBackId == nil else d.equipped = cosmetics.pickedCardBackId == back.id end
			d.shown = back or ctx.CardBacks.getById(cosmetics.cardBackId or ctx.CardBacks.DefaultId)
			d.name = back == nil and "Match my set" or back.name
			d.desc = back == nil and "The card back follows your equipped Card Set." or (d.owned and "A card back for your deck." or ctx.backHint(back))
			if d.equipped then d.action = "Equipped"
			elseif d.owned then d.action = back == nil and "Use set's" or "Equip"; d.run = function() ctx.actions.equipBack(back and back.id or nil) end
			else d.action = "Locked" end
			d.tip = d.name .. (d.owned and "" or ("\n" .. ctx.backHint(back)))
		end
		return d
	end

	local function paintHero(entry, d, g)
		local hp, hero = g.parts, g.hero
		local z = 43
		local function rel(r) return { x = r.x - hero.x, y = r.y - hero.y, w = r.w, h = r.h } end
		local frame = solid(layer, Color3.fromRGB(70, 44, 24), hero, z, 10)
		frame.Name = "Hero"
		stroke(frame, Color3.fromRGB(214, 172, 88), 2)
		local plate = solid(frame, Color3.fromRGB(34, 22, 14), rel(hp.plate), z + 1, 6)
		local acc = entry.set and ctx.CosmeticSets.accentOf(entry.set) or { 214, 172, 88 }
		stroke(plate, rgb(acc), 1.5)
		ctx.label(plate, { Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = CREAM, Text = d.name, ZIndex = z + 2 })
		local tb = rel(hp.table)
		local owned = d.owned
		if entry.set then
			miniTable(frame, tb, entry.set, owned, z + 1)
			local look = ctx.CosmeticSets.cardLook(entry.set)
			local ranks = { { "A", false }, { "K", true }, { "Q", false }, { "J", true }, { "10", false } }
			for i, rk in ipairs(ranks) do
				local c = ivoryCard(frame, rel(hp.fan[i]), look, rk[1], rk[2], z + 3 + i * 2, owned)
				c.Rotation = (i - 3) * 5
			end
			local br = rel(hp.back)
			solid(frame, Color3.fromRGB(34, 22, 14), rel(hp.stand), z + 3, 3)
			shadowOf(frame, br, z + 3)
			local back = ctx.CardBacks.getById(entry.set.cardBackId)
			local th = ctx.CardBackView.thumb(frame, back, { size = Vector2.new(br.w, br.h), locked = not owned, shimmer = false, zIndex = z + 4 })
			th.Position = UDim2.fromOffset(br.x, br.y)
			th.Rotation = 4
		else
			local bg = solid(frame, Color3.fromRGB(40, 26, 36), tb, z + 1, 8)
			stroke(bg, Color3.fromRGB(214, 172, 88), 1.5)
			local br = rel(hp.big)
			solid(frame, Color3.fromRGB(34, 22, 14), { x = br.x - 8, y = br.y + br.h, w = br.w + 16, h = 7 }, z + 3, 3)
			shadowOf(frame, br, z + 3)
			local th = ctx.CardBackView.thumb(frame, d.shown, { size = Vector2.new(br.w, br.h), equipped = d.equipped, locked = not owned, zIndex = z + 4, isActive = ctx.isOpen })
			th.Position = UDim2.fromOffset(br.x, br.y)
			th.Rotation = -4
		end
		if not owned then padlock(frame, tb.x + tb.w - 24, tb.y + 6, z + 20) end
		if hp.desc.h >= 28 then
			ctx.label(frame, { Position = UDim2.fromOffset(hp.desc.x - hero.x, hp.desc.y - hero.y), Size = UDim2.fromOffset(hp.desc.w, hp.desc.h), Font = Enum.Font.Gotham,
				TextSize = BODY_TEXT, TextWrapped = true, TextColor3 = CREAM, Text = d.desc, ZIndex = z + 2 })
		end
		local locked = d.run == nil
		local btn = plateButton(layer, hp.button, d.action, { solid = locked and Color3.fromRGB(34, 22, 14) or GOLD, onClick = d.run })
		btn.Name = "HeroAction"
		btn.TextSize = 17
		btn.TextColor3 = locked and CREAM or INK
		btn.ZIndex = 46
		if not locked then btn.AutoButtonColor = true end
		local rim = solid(layer, Color3.fromRGB(214, 172, 88), { x = hp.button.x - 2, y = hp.button.y - 2, w = hp.button.w + 4, h = hp.button.h + 4 }, 45, 6) -- gold rim behind the button (a UIStroke on a button doubles its text)
		rim.Name = "HeroRim"
	end

	local function paintTile(i, entry, cell, d, selected)
		local holder = Instance.new("TextButton")
		holder.Name = "Slot" .. i
		holder.AutoButtonColor = false
		holder.Text = ""
		holder.BackgroundColor3 = Color3.fromRGB(70, 44, 24)
		holder.BorderSizePixel = 0
		holder.Position, holder.Size = rectProps(cell.tile)
		holder.ZIndex = 43
		holder.Parent = layer
		ctx.roundCorner(holder, 8)
		local restColor = d.equipped and GOLD or (selected and CREAM or Color3.fromRGB(150, 108, 58))
		local ring = stroke(holder, restColor, d.equipped and 3 or (selected and 2 or 1))
		local pic = { x = cell.pic.x - cell.tile.x, y = cell.pic.y - cell.tile.y, w = cell.pic.w, h = cell.pic.h }
		if entry.set then
			miniTable(holder, pic, entry.set, d.owned, 44)
			local look = ctx.CosmeticSets.cardLook(entry.set)
			local cw = math.floor(math.min(pic.w * 0.22, pic.h * 0.5 * 2 / 3))
			local ch = math.floor(cw * 3 / 2)
			for k = 1, 3 do
				local cx = pic.x + math.floor(pic.w / 2) - cw - math.floor(cw / 4) + (k - 1) * math.floor(cw * 0.75)
				local c = ivoryCard(holder, { x = cx, y = pic.y + pic.h - ch - 6, w = cw, h = ch }, look, ({ "A", "K", "Q" })[k], k == 2, 46 + k * 2, d.owned)
				c.Rotation = (k - 2) * 6
			end
		else
			solid(holder, Color3.fromRGB(40, 26, 36), pic, 44, 6)
			local ch = pic.h - 8
			local cw = math.floor(ch * 2 / 3)
			local r = { x = pic.x + math.floor((pic.w - cw) / 2), y = pic.y + 4, w = cw, h = ch }
			shadowOf(holder, r, 45)
			local th = ctx.CardBackView.thumb(holder, d.shown, { size = Vector2.new(cw, ch), equipped = d.equipped, locked = not d.owned, shimmer = false, zIndex = 46 })
			th.Position = UDim2.fromOffset(r.x, r.y)
			th.Rotation = -4
		end
		if not d.owned then padlock(holder, pic.x + pic.w - 20, pic.y + 4, 60) end
		ctx.label(holder, { Position = UDim2.fromOffset(cell.name.x - cell.tile.x, cell.name.y - cell.tile.y), Size = UDim2.fromOffset(cell.name.w, cell.name.h), Font = Enum.Font.GothamBold,
			TextSize = BODY_TEXT, TextWrapped = true, TextColor3 = d.owned and CREAM or Color3.fromRGB(190, 175, 150), Text = d.name, ZIndex = 47 })
		addTip(holder, d.tip)
		holder.MouseButton1Click:Connect(function()
			ctx.playClickSfx()
			view.selected = entry.key
			room.paint()
		end)
		do -- hover lifts the tile 6 px with a warm ring (set directly, no tween, so calm mode needs nothing extra)
			local base = holder.Position
			holder.MouseEnter:Connect(function() holder.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset - 6); ring.Color = GOLD end)
			holder.MouseLeave:Connect(function() holder.Position = base; ring.Color = restColor end)
		end
	end

	-- the plate row: two tabs, then "Page n of m" and the arrows (plates stay intact and empty when there is one page)
	local function paintPlates(pages)
		local pl = placed.plates
		local function tab(rect, text, key)
			plateButton(layer, rect, text, { solid = view.tab == key and BROWN or Color3.fromRGB(34, 22, 14), onClick = function() view.tab, view.page, view.selected = key, 1, nil; room.paint() end }).TextColor3 = CREAM
		end
		tab(pl.tabs[1], "Card Sets", "sets")
		tab(pl.tabs[2], "Card Backs", "backs")
		if pages > 1 then -- Prev and Next exist only with more than one page, and only in a direction that goes somewhere
			plateButton(layer, pl.page, "Page " .. view.page .. " of " .. pages, { cream = true })
			if view.page > 1 then plateButton(layer, pl.prev, "< Prev", { solid = BROWN, onClick = function() view.page = view.page - 1; room.paint() end }).TextColor3 = CREAM end
			if view.page < pages then plateButton(layer, pl.next, "Next >", { solid = BROWN, onClick = function() view.page = view.page + 1; room.paint() end }).TextColor3 = CREAM end
		end
	end

	function room.paint()
		for _, ch in ipairs(layer:GetChildren()) do ch:Destroy() end
		if not room.on or not placed then return end
		local state = ctx.getState()
		local cosmetics = state and state.cosmetics or { equippedSetId = ctx.CosmeticSets.DefaultId, unlockedSetIds = { ctx.CosmeticSets.DefaultId } }
		local list = entries()
		local g = Layout.room(placed.areaW, placed.areaH, #list, view.page)
		view.page = g.page
		local top = placed.top
		local function down(r) return { x = r.x, y = r.y + top, w = r.w, h = r.h } end
		local parts = {}
		for k, v in pairs(g.parts) do
			if k == "fan" then parts.fan = {}; for i, r in ipairs(v) do parts.fan[i] = down(r) end else parts[k] = down(v) end
		end
		local cells = {}
		for i, c in ipairs(g.cells) do cells[i] = { tile = down(c.tile), pic = down(c.pic), name = down(c.name), board = down(c.board) } end
		placed.plates = { tabs = { down(g.plates.tabs[1]), down(g.plates.tabs[2]) }, page = down(g.plates.page), prev = down(g.plates.prev), next = down(g.plates.next) }
		paintPlates(g.pages)
		-- the selected entry (default: the equipped one) shows large in the hero
		local selected
		for _, e in ipairs(list) do if e.key == view.selected then selected = e end end
		if not selected then
			local eq = view.tab == "sets" and cosmetics.equippedSetId or (cosmetics.pickedCardBackId or "match")
			for _, e in ipairs(list) do if e.key == eq then selected = e end end
			selected = selected or list[1]
		end
		paintHero(selected, describe(selected, cosmetics), { parts = parts, hero = down(g.hero) })
		local seenShelf = {}
		for i, cell in ipairs(cells) do
			local entry = list[(g.page - 1) * g.perPage + i]
			local bd = cell.board
			if not seenShelf[bd.y] then -- one carved wood shelf board under each row: shadow, plank, light top edge
				seenShelf[bd.y] = true
				solid(layer, Color3.fromRGB(20, 12, 6), { x = bd.x, y = bd.y + bd.h, w = bd.w, h = 6 }, 42, nil).BackgroundTransparency = 0.4
				solid(layer, Color3.fromRGB(126, 88, 48), bd, 42, nil)
				solid(layer, Color3.fromRGB(168, 122, 70), { x = bd.x, y = bd.y, w = bd.w, h = 2 }, 42, nil)
			end
			paintTile(i, entry, cell, describe(entry, cosmetics), entry.key == selected.key)
		end
	end

	function room.layout()
		local screen = ctx.screenGui.AbsoluteSize
		local pw, ph = Layout.roomPanel(screen.X, screen.Y)
		pw, ph = FullScreen.fit(ctx.panel, pw, ph, screen.X, screen.Y) -- a full screen panel: the real screen below the tab strip
		local area = { x = 0, y = Layout.TOP, w = pw, h = ph - Layout.TOP - Layout.BOTTOM }
		local p = Layout.room(area.w, area.h, 1, 1)
		room.on = p.ok and pw >= Layout.ROOM_MIN.w and ph >= Layout.ROOM_MIN.h
		placed = nil
		if room.on then
			placed = { areaW = area.w, areaH = area.h, top = Layout.TOP, plates = p.plates }
			FullScreen.setRect(ctx.panel, UDim2.fromOffset(pw, ph))
		else
			FullScreen.setRect(ctx.panel, UDim2.fromScale(0.64, 0.84))
		end
		wall.Visible = room.on
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
					room.on and p.perPage or 0, 0, room.on and p.cols or 0, room.on and p.rows or 0, pw, ph))
			end
		end
		return room.on
	end

	return room
end

return CardSetsRoom
