--[[
	Client/CollectionFurniture.lua
	Collection tab furniture drawn FROM THE CELLS (rule: furniture is derived from the cells, never the other way round).
	Every piece lives inside its own cell's tile, so rows scroll with their furniture and nothing can drift. All rects come
	from Engine/CollectionFurnitureLayout.lua (tested). Painted art is not stretched behind the grid any more.

	  Furniture.kind(tabId)                 "cork" | "trophy" | "key" | "plate" or nil (the plain tiles stay)
	  Furniture.cellSize(kind) / .gap(kind) UDim2 for the UIGridLayout
	  Furniture.padding(kind)               { top, side } px the grid needs so outer margins are not clipped
	  Furniture.style(kind, tile, opts)     content: card, pin, base, ticket, plate, icon well and name (once per tile)
	                                        opts = { found, iconWell, nameLabel, rarityColor, id, equipped }; a locked cell keeps its dim
	                                        silhouette (iconWell) and its name on the plate
	                                        returns { hang = {dy, tilt}, target = frame the hover acts on }
	  Furniture.furnish(tile, ctx)          board / plank / rail / hook / strings (rebuilt when the column count changes)
	ctx = { index, n, cols, tie = bool (Bonds: a string to the next card) }
]]

local TweenService = game:GetService("TweenService")

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local F = require(Engine:WaitForChild("CollectionFurnitureLayout"))
local Scene = require(Engine:WaitForChild("CollectionSceneLayout"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local CORK, CORK_EDGE = Color3.fromRGB(168, 124, 78), Color3.fromRGB(96, 64, 38)
local PLANK, PLANK_TOP = Color3.fromRGB(108, 72, 42), Color3.fromRGB(146, 104, 62)
local BRASS, BRASS_DULL = Color3.fromRGB(196, 156, 74), Color3.fromRGB(110, 90, 54)
local INK, CREAM = Color3.fromRGB(52, 32, 10), Color3.fromRGB(250, 240, 220)
local RAIL = Color3.fromRGB(70, 46, 28)
local SHADE = Color3.fromRGB(10, 6, 3)

local function calm() return ClientSettings.get("reduceShake") == true end

local function box(parent, name, props, radius, static)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Active = false
	for k, v in pairs(props) do f[k] = v end
	f.Parent = parent
	if radius then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, radius)
		c.Parent = f
	end
	if static then f:SetAttribute("Static", true) end
	return f
end

local function rect(r) return UDim2.fromOffset(r.x, r.y), UDim2.fromOffset(r.w, r.h) end
local function at(parent, name, r, props, radius, static)
	props.Position, props.Size = rect(r)
	return box(parent, name, props, radius, static)
end

M.layout = F

function M.kind(tabId) return F.TAB_KIND[tabId] end
function M.cellSize(kind) local c = F.CELL[kind]; return UDim2.fromOffset(c.w, c.h) end
function M.gap(kind) local g = F.GAP[kind]; return UDim2.fromOffset(g.x, g.y) end
function M.padding(kind)
	if kind == "cork" then return { top = F.MARGIN, side = F.MARGIN + 2 } end
	return { top = kind == "plate" and 8 or 4, side = 8 }
end

local function lift(tile, by) -- content built by the caller moves above the furniture layers
	for _, d in ipairs(tile:GetDescendants()) do
		if d:IsA("GuiObject") and not d:GetAttribute("Static") then d.ZIndex = d.ZIndex + by end
	end
end

local function clear(tile)
	for _, c in ipairs(tile:GetChildren()) do
		if c:GetAttribute("Furn") then c:Destroy() end
	end
end

-- ===== content (once per tile) =====
function M.style(kind, tile, o)
	local P = F.cell(kind, { index = 1, n = 1, cols = 1 })
	tile.BackgroundTransparency = 1
	tile.AutoButtonColor = false
	tile.ZIndex = 21
	for _, c in ipairs(tile:GetChildren()) do
		if c:IsA("UIStroke") or c:IsA("UICorner") then c:Destroy() end
	end
	lift(tile, 3)
	local found, iconWell, nameLabel = o.found, o.iconWell, o.nameLabel
	local result = { hang = nil, target = tile } -- only cork cards have a hover hang (the rest sit on fixed furniture)

	local function nameOn(r, topPad)
		if not nameLabel then return end
		nameLabel.Parent = tile
		nameLabel.AnchorPoint = Vector2.new(0, 0)
		nameLabel.Position = UDim2.fromOffset(r.x + 3, r.y + (topPad or 0))
		nameLabel.Size = UDim2.fromOffset(r.w - 6, r.h - (topPad or 0))
		nameLabel.TextColor3 = found and INK or CREAM
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center
		nameLabel.TextWrapped = true
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.ZIndex = 30
	end
	local function plateOn(name, r, color)
		local p = at(tile, name, r, { BackgroundColor3 = color, ZIndex = 28 }, 5, true)
		local s = Instance.new("UIStroke")
		s.Color = o.rarityColor or BRASS_DULL
		s.Thickness = 1.5
		s.Transparency = found and 0.35 or 0.7
		s.Parent = p
		return p
	end

	if kind == "cork" then
		-- a cream paper card (or a blank card when locked) with a fixed tiny tilt, a brass pin at its top centre
		local card = box(tile, "Card", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = found and Color3.fromRGB(238, 224, 186) or Color3.fromRGB(214, 200, 164),
			BackgroundTransparency = 0, ZIndex = 24 }, 4, true)
		if iconWell then iconWell.Parent = card end
		if nameLabel then nameLabel.Parent = card end
		local shade = box(card, "CardShadow", { Position = UDim2.fromOffset(2, 3), Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = SHADE, BackgroundTransparency = 0.7, ZIndex = 23 }, 4, true)
		local pin = at(card, "Pin", P.pin, { BackgroundColor3 = Color3.fromRGB(176, 52, 40), ZIndex = 40 }, 6, true)
		local rim = Instance.new("UIStroke")
		rim.Color = Color3.fromRGB(40, 26, 14)
		rim.Thickness = 1
		rim.Parent = pin
		box(card, "PinShadow", { Position = UDim2.fromOffset(P.pin.x + 2, P.pin.y + 3), Size = UDim2.fromOffset(P.pin.w, P.pin.h), BackgroundColor3 = SHADE, BackgroundTransparency = 0.6, ZIndex = 39 }, 6, true)
		-- a locked card stays on the board as a dim silhouette with its name in dimmer ink: no padlock chip, no ???, never a blank note
		if nameLabel and found then
			nameLabel.TextColor3 = INK
		elseif nameLabel then
			nameLabel.TextColor3 = Color3.fromRGB(96, 80, 56)
		end
		local tilt = math.max(-Scene.CARD_TILT, math.min(Scene.CARD_TILT, Scene.hang(o.id or "x").tilt))
		card.Rotation = tilt
		result.hang, result.target = { dy = 0, tilt = tilt }, card
	elseif kind == "trophy" then
		-- a round wooden base standing on the plank; the trophy on it when defeated, an empty base when not
		at(tile, "TrophyShadow", P.shadow, { BackgroundColor3 = SHADE, BackgroundTransparency = 0.45, ZIndex = 24 }, 4, true)
		local base = at(tile, "TrophyBase", P.base, { BackgroundColor3 = found and Color3.fromRGB(146, 104, 62) or Color3.fromRGB(90, 62, 38), ZIndex = 26 }, 7, true)
		local rim = Instance.new("UIStroke")
		rim.Color = found and BRASS or BRASS_DULL
		rim.Thickness = 1.5
		rim.Parent = base
		if iconWell then
			iconWell.Position, iconWell.Size = rect(P.icon)
			iconWell.Visible = true -- locked: the dim silhouette stands on the base
			if found then iconWell.BackgroundColor3 = Color3.fromRGB(255, 226, 150); iconWell.BackgroundTransparency = 0.8 end -- a slight shine
		end
		plateOn("BrassPlate", P.plate, found and BRASS or BRASS_DULL)
		nameOn(P.plate) -- locked: the name on a duller plate
	elseif kind == "key" then
		-- a hook on the rail with a short chain and a ticket (owned) or an empty hook with the faint outline of a tag (locked)
		local pivot = P.sway.pivotY
		local H = P.ticket.y + P.ticket.h - pivot
		local holder = box(tile, "TagSway", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(P.hookCentre.x, pivot),
			Size = UDim2.fromOffset(P.cell.w, 2 * H), BackgroundTransparency = 1, ZIndex = 25 })
		local function rel(r) return { x = r.x, y = r.y - pivot + H, w = r.w, h = r.h } end
		if found then
			at(holder, "Chain", rel(P.chain), { BackgroundColor3 = Color3.fromRGB(122, 98, 62), ZIndex = 26 })
			local t = at(holder, "Ticket", rel(P.ticket), { BackgroundColor3 = Color3.fromRGB(214, 184, 112), ZIndex = 26 }, 8)
			local s = Instance.new("UIStroke")
			s.Color = BRASS_DULL
			s.Thickness = 1.5
			s.Parent = t
			box(holder, "TicketShadow", { Position = UDim2.fromOffset(rel(P.ticket).x + 2, rel(P.ticket).y + 3), Size = UDim2.fromOffset(P.ticket.w, P.ticket.h), BackgroundColor3 = SHADE, BackgroundTransparency = 0.7, ZIndex = 25 }, 8)
		else
			local ghost = at(holder, "TagOutline", rel(P.ticket), { BackgroundTransparency = 1, ZIndex = 26 }, 8)
			local s = Instance.new("UIStroke")
			s.Color = BRASS_DULL
			s.Thickness = 1.5
			s.Transparency = 0.7
			s.Parent = ghost
		end
		if iconWell then
			iconWell.Parent = holder
			local r = rel(P.icon)
			iconWell.Position, iconWell.Size = rect(r)
			iconWell.Visible = true -- locked: the dim silhouette hangs on the empty hook's tag outline
		end
		plateOn("BrassPlate", P.plate, found and BRASS or BRASS_DULL)
		nameOn(P.plate) -- locked: the name on a duller plate
		local swaying = false
		tile.MouseEnter:Connect(function()
			if swaying or calm() or not found then return end
			swaying = true
			local d = P.sway.degrees
			local info = TweenInfo.new(0.16, Enum.EasingStyle.Sine)
			task.spawn(function()
				for _, r in ipairs({ d, -d, 0 }) do
					local tw = TweenService:Create(holder, info, { Rotation = r })
					tw:Play()
					tw.Completed:Wait()
				end
				swaying = false
			end)
		end)
	else -- plate: an engraved brass plate on the rail
		local plate = at(tile, "Plate", P.plate, { BackgroundColor3 = found and Color3.fromRGB(206, 164, 78) or Color3.fromRGB(122, 100, 62), ZIndex = 26 }, 4, true)
		local s = Instance.new("UIStroke")
		s.Color = found and Color3.fromRGB(240, 206, 120) or BRASS_DULL
		s.Thickness = 1.5
		s.Parent = plate
		for i, r in ipairs(P.screws) do
			at(plate, "Screw" .. i, r, { BackgroundColor3 = found and Color3.fromRGB(120, 88, 34) or Color3.fromRGB(80, 64, 40), ZIndex = 27 }, 2, true)
		end
		if o.equipped and not calm() then
			local clip = box(plate, "Sweep", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 28 }, 4, true)
			local strip = box(clip, "SweepStrip", { Position = UDim2.fromScale(-0.3, 0), Size = UDim2.fromScale(0.2, 1), BackgroundColor3 = Color3.fromRGB(255, 248, 214), BackgroundTransparency = 0.7, ZIndex = 29 }, nil, true)
			TweenService:Create(strip, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 5.1), { Position = UDim2.fromScale(1.1, 0) }):Play()
		end
		if o.equipped then
			local chk = box(tile, "EquippedCheck", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(18, 18),
				BackgroundColor3 = Color3.fromRGB(60, 110, 50), ZIndex = 32 }, 9, true)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1, 1)
			t.Font = Enum.Font.GothamBold
			t.TextSize = 14
			t.Text = "\226\156\147"
			t.TextColor3 = CREAM
			t.TextTransparency = 0
			t.TextStrokeTransparency = 1
			t.ZIndex = 33
			t.Parent = chk
		end
		if iconWell then iconWell.Visible = false end
		nameOn(P.plate)
		if nameLabel then
			nameLabel.Position = UDim2.fromOffset(24, 0)
			nameLabel.Size = UDim2.fromOffset(P.plate.w - 48, P.plate.h) -- locked: the name on a duller plate
		end
	end
	return result
end

-- ===== furniture (rebuilt when the column count changes) =====
function M.furnish(kind, tile, ctx)
	clear(tile)
	local P = F.cell(kind, ctx)
	local function add(name, r, props, radius)
		local f = at(tile, name, r, props, radius, true)
		f:SetAttribute("Furn", true)
		return f
	end
	if kind == "cork" then
		add("Board", P.segment, { BackgroundColor3 = CORK, ZIndex = 21 })
		for i, e in ipairs(P.edges) do add("BoardEdge" .. i, e, { BackgroundColor3 = CORK_EDGE, ZIndex = 22 }) end
		if ctx.tie and ctx.cols then
			-- a sagging red string from this pin to the next card's pin
			local ax, ay = P.pinCentre.x, P.pinCentre.y
			local bx, by = F.pinOffset(ctx.index, ctx.index + 1, ctx.cols)
			local pts = F.string(ax, ay, bx, by, 10, 10)
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
				add("String" .. i, { x = (a.x + b.x) / 2 - len / 2, y = (a.y + b.y) / 2 - 1, w = len + 1, h = 2 },
					{ BackgroundColor3 = Color3.fromRGB(188, 44, 44), ZIndex = 38, Rotation = math.deg((math.atan2 or math.atan)(b.y - a.y, b.x - a.x)) })
			end
		end
	elseif kind == "trophy" then
		local plank = add("Plank", P.plank, { BackgroundColor3 = PLANK, ZIndex = 22 })
		box(plank, "PlankTop", { Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = PLANK_TOP, ZIndex = 23 }, nil, true)
		add("BrassRail", P.rail, { BackgroundColor3 = BRASS, ZIndex = 23 })
		if P.bracket then add("Bracket", P.bracket, { BackgroundColor3 = RAIL, ZIndex = 22 }, 3) end
	elseif kind == "key" then
		add("Rail", P.rail, { BackgroundColor3 = RAIL, ZIndex = 22 }, 3)
		add("Hook", P.hook, { BackgroundColor3 = BRASS, ZIndex = 27 }, 6)
	else
		local rail = add("Rail", P.rail, { BackgroundColor3 = RAIL, ZIndex = 22 }, 4)
		box(rail, "RailTop", { Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.fromRGB(104, 72, 44), ZIndex = 23 }, nil, true)
	end
end

return M
