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
local Tip = require(Engine:WaitForChild("Gameplay2Tip"))
local TierStyle = require(Engine:WaitForChild("PatronTierStyle"))
local CutCards = require(Engine:WaitForChild("ConceptTPatronArt"))

local M = {}

local CREAM = Color3.fromRGB(245, 232, 200)
local GOLD = Color3.fromRGB(246, 196, 70)
local PLATE = Color3.fromRGB(40, 30, 22) -- TavernStyle plateFill
local plate, highlights = nil, {}
local token = 0 -- a newer show or a hide cancels a plate that is still waiting its delay

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
	token = token + 1
	if plate then plate:Destroy(); plate = nil end
	for _, h in ipairs(highlights) do h:Destroy() end
	highlights = {}
end

local render

-- Gameplay v2: the plate shows 0.25 s after the pointer arrives (Engine/Gameplay2Tip.DELAY); leaving hides it at once
function M.show(root, cards, index, info, calm)
	M.hide()
	if not root or not info or not info.id then return end
	local v2 = false
	pcall(function() v2 = require(script.Parent.Gameplay2).isActive() end)
	if not v2 then return render(root, cards, index, info, calm, false) end
	local mine = token
	task.delay(Tip.DELAY, function()
		if mine == token and root.Parent then
			render(root, cards, index, info, calm, true)
			pcall(function() require(script.Parent.Cue).play("hover") end) -- the soft hover tick, behind the cue cooldown
		end
	end)
end

function render(root, cards, index, info, calm, v2)
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
	local w = v2 and Tip.width(rs.X) or math.floor(math.max(190, math.min(280, rs.X * 0.3)))
	local padX, padY = 12, 8
	local portrait = v2 and Tip.portrait(w) or nil
	local inner = v2 and Tip.textWidth(w) or (w - padX * 2)
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
	if v2 then h = Tip.height(w, rows) end
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
	st.Color = Color3.fromRGB(200, 165, 90) -- TavernStyle goldTrim; rarity is the word on the pill, not the border
	st.Thickness = 2
	st.Parent = frame
	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, -padX * 2, 1, -padY * 2)
	body.Position = UDim2.fromOffset(padX, padY)
	body.ZIndex = 61
	body.Parent = frame
	if v2 then -- the cut card grown large on the left, with its power disc, the text on the right
		local pad = Tip.PAD
		body.Size = UDim2.fromOffset(inner, h - pad * 2)
		body.Position = UDim2.fromOffset(pad * 2 + portrait.w, pad)
		local pic = Instance.new("ImageLabel")
		pic.Name = "TipCard"
		pic.BackgroundTransparency = 1
		pic.BorderSizePixel = 0
		pic.Active = false
		pic.ScaleType = Enum.ScaleType.Fit
		pic.Image = CutCards["ctp_" .. info.id] or ""
		pic.Size = UDim2.fromOffset(portrait.w, portrait.h)
		pic.Position = UDim2.fromOffset(pad, pad)
		pic.ZIndex = 61
		pic.Parent = frame
		local numeral = TierStyle.numeral(info.value or "")
		if numeral ~= "" then
			local D = math.max(30, math.floor(portrait.w * 0.4))
			local disc = Instance.new("Frame")
			disc.Name = "TipDisc"
			disc.Size = UDim2.fromOffset(D, D)
			disc.Position = UDim2.fromOffset(pad + portrait.w - math.floor(D * 0.6), pad + portrait.h - math.floor(D * 0.6))
			disc.BackgroundColor3 = Color3.fromRGB(table.unpack(TierStyle.DISC.fill))
			disc.BorderSizePixel = 0
			disc.Active = false
			disc.ZIndex = 63
			local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = disc
			local ds = Instance.new("UIStroke"); ds.Color = Color3.fromRGB(table.unpack(TierStyle.DISC.ring)); ds.Thickness = 2; ds.Parent = disc
			local num = Instance.new("TextLabel")
			num.BackgroundTransparency = 1
			num.Size = UDim2.fromScale(1, 1)
			num.Font = Enum.Font.Merriweather
			num.TextSize = 16
			num.Text = numeral
			num.TextColor3 = Color3.fromRGB(table.unpack(TierStyle.DISC.text))
			num.TextStrokeTransparency = 0.4
			num.ZIndex = 64
			num.Active = false
			num.Parent = disc
			disc.Parent = frame
		end
	end
	local y = 0
	label(body, content.name, 20, Enum.Font.Merriweather, v2 and GOLD or CREAM, y, nameH)
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
	local okV2, v2 = pcall(function() return require(script.Parent.Gameplay2).isActive() end)
	if okV2 and v2 then -- Gameplay v2: keep clear of its round bar, hand, buttons, sort control and deck instead
		local g = require(Engine:WaitForChild("Gameplay2Layout")).rects(rs.X, rs.Y)
		avoid = { g.bar, g.hand, g.play, g.discard, g.sortRank, g.sortSuit, g.deck, g.deckCount }
	end
	local slot = cards[index] and cards[index].slot
	local rp, rsz = root.AbsolutePosition, rs
	local card = { x = 0, y = 0, w = 0, h = 0 }
	if slot then
		card = { x = slot.AbsolutePosition.X - rp.X, y = slot.AbsolutePosition.Y - rp.Y, w = slot.AbsoluteSize.X, h = slot.AbsoluteSize.Y }
	end
	local x, py = PatronTips.place(card, { X = w, Y = h }, avoid, { X = rsz.X, Y = rsz.Y })
	if v2 and index >= 1 and index <= 5 then
		x, py = Tip.place(require(Engine:WaitForChild("Gameplay2Layout")).rects(rs.X, rs.Y), rs.X, rs.Y, index, w, h)
	end
	frame.Position = UDim2.fromOffset(math.floor(x), math.floor(py))
	frame.Parent = root
	plate = frame
end

return M
