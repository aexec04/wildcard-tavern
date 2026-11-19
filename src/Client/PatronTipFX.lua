--[[
	Client/PatronTipFX.lua
	The Patron hover or long press tooltip plate of the play screen (Concept T look): serif name, rarity word on a tinted pill,
	one plain effect sentence and up to two synergy tags. Other seated Patrons that share a tag get a soft gold outline
	(0.4 alpha). Numbers and placement are the tested Engine/PatronTips. Display only; nothing is sent to the server.
	No tween anywhere: the plate and the outlines appear and vanish, so Calm mode and Reduce motion are the same.

	PatronTipFX.show(root, cards, index, info, calm)   info = { id, name, description, rarity }; cards[i].slot are the card slots
	PatronTipFX.hide()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PatronTips = require(Engine:WaitForChild("PatronTips"))
local CTLayout = require(Engine:WaitForChild("ConceptTLayout"))
local CollectionBook = require(Engine:WaitForChild("CollectionBook"))

local M = {}

local CREAM = Color3.fromRGB(245, 232, 200)
local GOLD = Color3.fromRGB(246, 196, 70)
local PLATE = Color3.fromRGB(46, 30, 17)
local plate, highlights = nil, {}

local function label(parent, text, size, font, color, y, h, order)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, h)
	t.Position = UDim2.fromOffset(0, y)
	t.Font = font
	t.TextSize = size
	t.TextColor3 = color
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0.4
	t.TextStrokeColor3 = Color3.fromRGB(20, 12, 6)
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Text = text
	t.ZIndex = 61
	t.Active = false
	t.LayoutOrder = order or 0
	t.Parent = parent
	return t
end

function M.hide()
	if plate then plate:Destroy(); plate = nil end
	for _, h in ipairs(highlights) do h:Destroy() end
	highlights = {}
end

function M.show(root, cards, index, info, calm)
	M.hide()
	if not root or not info or not info.id then return end
	local tier = tostring(info.rarity or "common"):lower()
	local content = PatronTips.content(info.id, info.name, info.description, tier)
	local color = Color3.fromRGB(table.unpack((CollectionBook.Rarities[tier] or CollectionBook.Rarities.common).color))
	local rs = root.AbsoluteSize
	local ownedIds = {}
	for i, c in ipairs(cards) do ownedIds[i] = c.id end
	-- soft gold outline on the other Patrons that share a shown tag (a transparent frame with a stroke: never a filled block)
	for i in pairs(PatronTips.sharing(ownedIds, index)) do
		local slot = cards[i] and cards[i].slot
		if slot and slot.Visible then
			local hl = Instance.new("Frame")
			hl.Name = "SynergyHighlight"
			hl.BackgroundTransparency = 1
			hl.BorderSizePixel = 0
			hl.Size = UDim2.new(1, 6, 1, 6)
			hl.Position = UDim2.fromOffset(-3, -3)
			hl.ZIndex = 40
			hl.Active = false
			local cr = Instance.new("UICorner")
			cr.CornerRadius = UDim.new(0, 10)
			cr.Parent = hl
			local st = Instance.new("UIStroke")
			st.Color = GOLD
			st.Thickness = 2
			st.Transparency = 1 - PatronTips.HIGHLIGHT_ALPHA
			st.Parent = hl
			hl.Parent = slot
			highlights[#highlights + 1] = hl
		end
	end
	-- the plate: text sizes 15 or more, width follows the screen (never wider than 280)
	local w = math.floor(math.max(190, math.min(280, rs.X * 0.3)))
	local padX, padY = 12, 8
	local inner = w - padX * 2
	local TextService = game:GetService("TextService")
	local function height(text, size, font)
		local ok, b = pcall(function() return TextService:GetTextSize(text, size, font, Vector2.new(inner, 1000)) end)
		return ok and b.Y or size * 2
	end
	local nameH = height(content.name, 20, Enum.Font.Merriweather) + 2
	local effH = height(content.effect, 16, Enum.Font.GothamMedium) + 2
	local tagText = ""
	for i, t in ipairs(content.tags) do tagText = tagText .. (i > 1 and "   " or "") .. t.icon .. " " .. t.word end
	local rows = nameH + 22 + effH + (tagText ~= "" and 22 or 0)
	local h = math.floor(rows + padY * 2 + 8)
	local frame = Instance.new("Frame")
	frame.Name = "PatronTipPlate"
	frame.Size = UDim2.fromOffset(w, h)
	frame.BackgroundColor3 = PLATE
	frame.BackgroundTransparency = 0.04
	frame.BorderSizePixel = 0
	frame.ZIndex = 60
	frame.Active = false
	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(0, 8)
	cr.Parent = frame
	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = 2
	st.Parent = frame
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, -padX * 2, 1, -padY * 2)
	body.Position = UDim2.fromOffset(padX, padY)
	body.ZIndex = 61
	body.Parent = frame
	local y = 0
	label(body, content.name, 20, Enum.Font.Merriweather, CREAM, y, nameH)
	y = y + nameH + 2
	-- rarity as a word on a tinted pill, never colour alone
	local pill = Instance.new("TextLabel")
	pill.BackgroundColor3 = color
	pill.BackgroundTransparency = 0.15
	pill.BorderSizePixel = 0
	pill.Size = UDim2.fromOffset(#content.rarity * 9 + 20, 20)
	pill.Position = UDim2.fromOffset(0, y)
	pill.Font = Enum.Font.GothamBold
	pill.TextSize = 15
	pill.TextColor3 = Color3.fromRGB(20, 12, 6)
	pill.TextTransparency = 0
	pill.TextStrokeTransparency = 1
	pill.Text = content.rarity
	pill.ZIndex = 62
	pill.Active = false
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 10)
	pc.Parent = pill
	pill.Parent = body
	y = y + 24
	label(body, content.effect, 16, Enum.Font.GothamMedium, CREAM, y, effH)
	y = y + effH
	if tagText ~= "" then
		label(body, tagText, 15, Enum.Font.GothamBold, GOLD, y + 2, 20)
	end
	-- position: from the same rects the layout uses, clear of the HUD pills, banner, gear and hand
	local r = CTLayout.rects(rs.X, rs.Y)
	local avoid = { r.coins, r.hands, r.round, r.gear, r.hand }
	local slot = cards[index] and cards[index].slot
	local rp, rsz = root.AbsolutePosition, rs
	local card = { x = 0, y = 0, w = 0, h = 0 }
	if slot then
		card = { x = slot.AbsolutePosition.X - rp.X, y = slot.AbsolutePosition.Y - rp.Y, w = slot.AbsoluteSize.X, h = slot.AbsoluteSize.Y }
	end
	local x, py = PatronTips.place(card, { X = w, Y = h }, avoid, { X = rsz.X, Y = rsz.Y })
	frame.Position = UDim2.fromOffset(math.floor(x), math.floor(py))
	frame.Parent = root
	plate = frame
end

return M
