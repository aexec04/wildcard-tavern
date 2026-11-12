--[[
	Client/StatsRoom.lua
	The painted ledger desk (stats_room_a) behind the Stats panel (Client/StatsPanel.lua), used when the window is big enough; the old open
	leather ledger book (Client/LedgerBook.lua) stays for small windows and a missing Image id. Slots and the text for them come from the
	tested Engine/StatsSceneLayout.lua: three brass plaques hold the headline numbers (Runs won, Best Night, Best hand), the left page holds
	the lifetime ledger lines, the right page the newest runs (ink on paper, rows that do not fit are left out, never cut), and the six
	recessed shelf slots hold the login streak, the three best runs, the favourite Patron and the Quick Run best.

	StatsRoom.new(ctx) -> room
	  ctx = { panel, screenGui, hide = { gui, ... } (the book layer), getState = fn, plainRect = fn() -> { x, y, w, h }, roundCorner }
	room.layout() -> true when the painted room is on (sizes and draws the picture), false restores the plain panel rect
	room.paint()  rebuilds the texts from the latest state
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StatsRoom = {}

local INK = Color3.fromRGB(58, 36, 18)
local INK_DIM = Color3.fromRGB(104, 76, 46)
local WIN_INK = Color3.fromRGB(150, 40, 34)
local LOSS_INK = Color3.fromRGB(58, 82, 132)
local CREAM = Color3.fromRGB(250, 236, 204)
local GOLD = Color3.fromRGB(236, 196, 112)

function StatsRoom.new(ctx)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local Layout = require(Engine:WaitForChild("StatsSceneLayout"))
	local Patrons = require(Engine:WaitForChild("Patrons"))
	local Achievements = require(Engine:WaitForChild("Achievements"))
	local PanelScene = require(script.Parent.PanelScene)
	local scene = PanelScene.new(ctx.panel, { artKey = Layout.ART_KEY, def = Layout.DEF, z = 41 })
	local layer = Instance.new("Frame")
	layer.Name = "RoomLayer"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.Active = false
	layer.Visible = false
	layer.ZIndex = 42
	layer.Parent = ctx.panel

	local room = { on = false }
	local placed = nil
	local lastKey = nil

	local function text(parent, rect, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextSize = 14
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.ZIndex = 44
		l.Position, l.Size = UDim2.fromOffset(rect.x, rect.y), UDim2.fromOffset(rect.w, rect.h)
		for k, v in pairs(props or {}) do l[k] = v end
		l.Parent = parent
		return l
	end

	function room.paint()
		for _, ch in ipairs(layer:GetChildren()) do ch:Destroy() end
		if not room.on or not placed then return end
		local state = ctx.getState()
		local stats = state and state.runStats
		if not stats then return end
		local titleDef = state.equippedTitleId and Achievements.getById(state.equippedTitleId)
		local fav = stats.favoritePatron
		local patron = fav and Patrons.getById(fav.id)
		local c = Layout.content(stats, state.login, titleDef and titleDef.title or nil, patron and patron.name or nil)

		-- brass plaques: the number big, its caption under it (ink on brass)
		for i, h in ipairs(c.headline) do
			local pl = placed.plaques[i]
			if pl then
				local numH = math.max(28, math.floor(pl.h * 0.5))
				text(layer, { x = pl.x + 8, y = pl.y + math.floor(pl.h * 0.14), w = pl.w - 16, h = numH }, { Text = h.value, TextSize = math.clamp(math.floor(numH * 0.9), 22, 44), TextWrapped = false })
				text(layer, { x = pl.x + 8, y = pl.y + math.floor(pl.h * 0.14) + numH, w = pl.w - 16, h = 20 }, { Text = h.caption, Font = Enum.Font.GothamMedium, TextWrapped = false })
			end
		end

		-- left page: lifetime ledger lines, label left and value right, a row each
		local lp = placed.pages[1]
		if lp then
			local fit = Layout.rowsFit(lp.h - 30, Layout.ROW_H)
			text(layer, { x = lp.x + 8, y = lp.y + 4, w = lp.w - 16, h = 24 }, { Text = "The Ledger", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false })
			for i = 1, math.min(fit, #c.rows) do
				local y = lp.y + 30 + (i - 1) * Layout.ROW_H
				text(layer, { x = lp.x + 8, y = y, w = math.floor(lp.w * 0.55), h = Layout.ROW_H }, { Text = c.rows[i].label, Font = Enum.Font.GothamMedium, TextColor3 = INK_DIM, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false })
				text(layer, { x = lp.x + 8 + math.floor(lp.w * 0.45), y = y, w = lp.w - 16 - math.floor(lp.w * 0.45), h = Layout.ROW_H }, { Text = c.rows[i].value, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
			end
		end

		-- right page: the newest runs, won in red ink and lost in blue (as in the book)
		local rp = placed.pages[2]
		if rp then
			local fit = Layout.rowsFit(rp.h - 30, Layout.ROW_H)
			text(layer, { x = rp.x + 8, y = rp.y + 4, w = rp.w - 16, h = 24 }, { Text = "Recent Runs", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false })
			if #c.runs == 0 then
				text(layer, { x = rp.x + 8, y = rp.y + 34, w = rp.w - 16, h = 48 }, { Text = "Nothing written yet. Go lose gracefully.", Font = Enum.Font.GothamMedium, TextColor3 = INK_DIM, TextXAlignment = Enum.TextXAlignment.Left })
			end
			for i = 1, math.min(fit, #c.runs) do
				text(layer, { x = rp.x + 8, y = rp.y + 30 + (i - 1) * Layout.ROW_H, w = rp.w - 16, h = Layout.ROW_H },
					{ Text = c.runs[i].text, TextColor3 = c.runs[i].won and WIN_INK or LOSS_INK, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false })
			end
		end

		-- shelves: a gold title and the value in cream, wrapping on up to two lines each (whole text, no dots)
		for i, sh in ipairs(c.shelves) do
			local r = placed.shelves[i]
			if r then
				local titleH = 18 -- titles are one short line; the value takes up to three
				text(layer, { x = r.x + 6, y = r.y + 6, w = r.w - 12, h = titleH }, { Text = sh.title, TextColor3 = GOLD, TextWrapped = false, TextYAlignment = Enum.TextYAlignment.Top })
				text(layer, { x = r.x + 6, y = r.y + 8 + titleH, w = r.w - 12, h = math.max(52, r.h - titleH - 12) }, { Text = sh.value, Font = Enum.Font.GothamMedium, TextColor3 = CREAM, TextYAlignment = Enum.TextYAlignment.Top })
			end
		end
	end

	function room.layout()
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
		local rect = Layout.panel(vp.X, vp.Y)
		local area = { x = 0, y = Layout.TOP, w = rect.w, h = rect.h - Layout.TOP - Layout.BOTTOM }
		local p = scene.id and Layout.place(area.w, area.h) or nil
		room.on = p ~= nil and p.ok
		placed = nil
		if room.on then
			placed = p
			for _, group in ipairs({ p.plaques, p.pages, p.shelves }) do
				for _, r in ipairs(group) do r.y = r.y + Layout.TOP end
			end
			ctx.panel.Size = UDim2.new(0, rect.w, 0, rect.h)
			ctx.panel.Position = UDim2.new(0, rect.x, 0.5, 0)
			scene.show(area, p)
		else
			local r = ctx.plainRect()
			ctx.panel.Size = UDim2.new(0, r.w, 0, r.h)
			ctx.panel.Position = UDim2.new(0, r.x, 0.5, 0)
			scene.hide()
		end
		layer.Visible = room.on
		for _, g in ipairs(ctx.hide) do g.Visible = not room.on end
		if RunService:IsStudio() then
			local key = rect.w .. "x" .. rect.h .. (room.on and "on" or "off")
			if key ~= lastKey then
				lastKey = key
				print(string.format("[StatsRoom] %s slots=%d (plaques %d, pages %d, shelves %d) panel %dx%d", room.on and "painted" or "plain",
					room.on and (#p.plaques + #p.pages + #p.shelves) or 0, room.on and #p.plaques or 0, room.on and #p.pages or 0, room.on and #p.shelves or 0, rect.w, rect.h))
			end
		end
		return room.on
	end

	return room
end

return StatsRoom
