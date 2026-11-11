--[[
	Client/CollectionSection.lua
	A Collection section as a painted scene. Opening Patrons, Recipes, Boss Rounds, House Passes, Titles or Bonds from the gallery room
	shows that section's own painted close-up (art `collection_scene` coll_sec_<section>_a) as ONE cover-fitted picture, and every entry
	sits INSIDE a painted slot: a portrait in its gilded frame with the name on the brass plate, a boss standing on its pedestal, ink on a
	parchment card, a paper tag or a brass nameplate. The section pages (12 entries a page, Bonds 8) with brass arrow plates and a
	"Page 2 of 7" plate under the scene, and with the Left and Right keys. Slot geometry is Engine/CollectionSectionLayout.lua (tested).

	A locked entry stays on its slot dim, with its name; a click calls onPick(item) (the Collection's detail card). No tween anywhere, so
	calm mode needs no special case. Collection.lua keeps the old scrolling grid when canShow(tabId) is false (no Image id, or a window
	too small for readable slots).

	CollectionSection.new({ parent, zIndex, isActive = function() -> bool, addTooltip }) -> {
		frame, canShow(tabId), show(tabId, items, describe, onPick), hide(), layout(w, h), page(), pages(), turn(delta)
	}
	describe(item) -> { found, name, line, artId, icon, rarityColor, equipped, fresh, tip }
]]

local UserInputService = game:GetService("UserInputService")

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("CollectionSectionLayout"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))

local CollectionSection = {}

local INK = Color3.fromRGB(58, 38, 18)
local INK_BRASS = Color3.fromRGB(52, 34, 14)
local CREAM = Color3.fromRGB(240, 226, 190)
local BRASS = Color3.fromRGB(176, 136, 58)
local BRASS_DULL = Color3.fromRGB(118, 94, 50)
local WALL = Color3.fromRGB(24, 17, 11)
local ZSTEP = 1

local function make(class, parent, props)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function rect(o, r)
	o.Position = UDim2.fromOffset(r.x, r.y)
	o.Size = UDim2.fromOffset(r.w, r.h)
end

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
end

-- one label that shrinks to fit its box and never goes under 14 px
local function fitText(parent, r, text, z, props)
	local t = make("TextLabel", parent, {
		BackgroundTransparency = 1, Text = text, TextWrapped = true, TextScaled = true, TextSize = 18, ZIndex = z,
		Font = Enum.Font.GothamBold, TextColor3 = INK, TextStrokeTransparency = 1, TextTransparency = 0,
	})
	rect(t, r)
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = 14
	c.MaxTextSize = props and props.max or 20
	c.Parent = t
	if props then
		for k, v in pairs(props) do
			if k ~= "max" then t[k] = v end
		end
	end
	return t
end

function CollectionSection.new(opts)
	local self = {}
	local z0 = opts.zIndex or 22
	local frame = make("Frame", opts.parent, {
		Name = "SectionScene", BackgroundColor3 = WALL, BorderSizePixel = 0, ClipsDescendants = true, Visible = false, ZIndex = z0,
	})
	self.frame = frame
	local area = { w = 0, h = 0 }
	local st = { tabId = nil, items = {}, describe = nil, onPick = nil, page = 1 }

	local function artId(tabId)
		return ContentArt.getImageId("collection_scene", Layout.artKey(tabId))
	end

	local function placement(tabId, n)
		local pages = Layout.pageCount(n, tabId)
		return Layout.place(tabId, area.w, area.h, pages), pages
	end

	function self.canShow(tabId, n)
		if not Layout.has(tabId) or not artId(tabId) or area.w <= 0 or area.h <= 0 then return false end
		local p = placement(tabId, n or st.tabId == tabId and #st.items or 0)
		return p ~= nil and p.ok
	end

	local function clear()
		for _, child in ipairs(frame:GetChildren()) do child:Destroy() end
	end

	local function pick(item)
		if st.onPick then st.onPick(item) end
	end

	-- a transparent button over a slot: the click, the hover wash and the tooltip
	local function hitArea(parent, r, item, info, z)
		local hit = make("TextButton", parent, {
			Name = "Slot", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(255, 240, 200),
			BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = z,
		})
		rect(hit, r)
		hit.MouseEnter:Connect(function() hit.BackgroundTransparency = 0.88 end)
		hit.MouseLeave:Connect(function() hit.BackgroundTransparency = 1 end)
		hit.MouseButton1Click:Connect(function() pick(item) end)
		if opts.addTooltip and info.tip then opts.addTooltip(hit, function() return info.tip end) end
		return hit
	end

	local function newTag(parent, r, z)
		local tag = make("TextLabel", parent, {
			Name = "NewTag", Text = "NEW", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = INK_BRASS, BackgroundColor3 = BRASS,
			BorderSizePixel = 0, ZIndex = z, TextStrokeTransparency = 1,
		})
		tag.Position = UDim2.fromOffset(r.x + 2, r.y + 2)
		tag.Size = UDim2.fromOffset(40, 18)
		corner(tag, 4)
		return tag
	end

	local function dimOver(parent, r, z, radius)
		local d = make("Frame", parent, { Name = "Dim", BackgroundColor3 = Color3.fromRGB(10, 6, 3), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = z })
		rect(d, r)
		if radius then corner(d, radius) end
		return d
	end

	-- the portrait kinds: Patrons (the portrait fills the frame's dark canvas) and Boss Rounds (it stands on the pedestal)
	local function portraitSlot(tabId, slot, item, info, z)
		local standing = tabId == "bosses"
		local well = make("Frame", frame, { Name = "Portrait", BackgroundTransparency = standing and 1 or 0, BorderSizePixel = 0, ZIndex = z })
		well.BackgroundColor3 = info.found and Color3.fromRGB(46, 36, 26) or Color3.fromRGB(26, 20, 15)
		rect(well, slot)
		local art = info.artId and make("ImageLabel", well, {
			Name = "ContentArt", BackgroundTransparency = 1, Image = info.artId, ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1), ZIndex = z + ZSTEP,
			ImageColor3 = info.found and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(78, 72, 66),
		}) or nil
		if not art then
			make("TextLabel", well, {
				Text = info.icon or "?", Font = Enum.Font.GothamBold, TextSize = 28, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
				TextColor3 = CREAM, TextTransparency = info.found and 0 or 0.55, TextStrokeTransparency = 1, ZIndex = z + ZSTEP,
			})
		end
		if not info.found and not standing then dimOver(frame, slot, z + 2, nil) end
		if slot.plate then
			local plate = make("TextButton", frame, {
				Name = "Plate", AutoButtonColor = false, BackgroundColor3 = info.found and BRASS or BRASS_DULL, BorderSizePixel = 0,
				Text = tostring(info.name), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = INK_BRASS, TextTruncate = Enum.TextTruncate.AtEnd,
				TextTransparency = info.found and 0 or 0.35, TextStrokeTransparency = 1, ZIndex = z + 3,
			})
			rect(plate, slot.plate)
			corner(plate, 4)
			plate.MouseButton1Click:Connect(function() pick(item) end)
		end
	end

	-- the text kinds: ink on a card, a tag or a nameplate, shrink-to-fit
	local function textSlot(tabId, slot, item, info, z)
		local kind = Layout.kind(tabId)
		local inner = slot.inner
		local ink = (kind == "plate") and INK_BRASS or INK
		local transparency = info.found and 0 or 0.35
		if kind == "tag" or kind == "plate" then
			local name = fitText(frame, inner, tostring(info.name), z + 1, { TextColor3 = ink, TextTransparency = transparency, max = 20 })
			if info.line and kind == "plate" then
				name.Size = UDim2.fromOffset(inner.w, math.floor(inner.h * 0.68))
				local sub = fitText(frame, { x = inner.x, y = inner.y + math.floor(inner.h * 0.7), w = inner.w, h = math.floor(inner.h * 0.3) }, info.line, z + 1,
					{ TextColor3 = ink, TextTransparency = transparency, max = 16 })
				sub.Name = "Line"
			end
		else
			local nameH = math.floor(inner.h * (info.line and 0.36 or 1))
			fitText(frame, { x = inner.x, y = inner.y, w = inner.w, h = nameH }, tostring(info.name), z + 1, { TextColor3 = ink, TextTransparency = transparency, max = 20 })
			if info.line then
				local line = fitText(frame, { x = inner.x, y = inner.y + nameH + 2, w = inner.w, h = inner.h - nameH - 2 }, info.line, z + 1,
					{ TextColor3 = ink, TextTransparency = transparency, Font = Enum.Font.Gotham, max = 16 })
				line.Name = "Line"
			end
		end
		if not info.found then dimOver(frame, slot, z + 2, nil) end
	end

	local function brassButton(r, text, onClick)
		local b = make("TextButton", frame, {
			AutoButtonColor = true, BackgroundColor3 = BRASS, BorderSizePixel = 0, Text = text, Font = Enum.Font.GothamBold, TextSize = 20,
			TextColor3 = INK_BRASS, TextStrokeTransparency = 1, ZIndex = z0 + 6,
		})
		rect(b, r)
		corner(b, 6)
		if onClick then b.MouseButton1Click:Connect(onClick) end
		return b
	end

	local function render()
		clear()
		if not st.tabId then return end
		local tabId = st.tabId
		local pages = Layout.pageCount(#st.items, tabId)
		st.page = Layout.clampPage(st.page, #st.items, tabId)
		local p = Layout.place(tabId, area.w, area.h, pages)
		if not p then return end
		local img = artId(tabId)
		if img then
			local im = make("ImageLabel", frame, { Name = "Scene", BackgroundTransparency = 1, Image = img, ScaleType = Enum.ScaleType.Stretch, ZIndex = z0 })
			im.Position = UDim2.fromOffset(math.floor(p.image.x), math.floor(p.image.y))
			im.Size = UDim2.fromOffset(math.ceil(p.image.w), math.ceil(p.image.h))
		end
		local z = z0 + 1 -- every piece stays under the detail card (30) and the toast
		for i, item in ipairs(Layout.pageItems(st.items, tabId, st.page)) do
			local slot = p.slots[i]
			local info = st.describe(item)
			if Layout.scene(tabId).plate then portraitSlot(tabId, slot, item, info, z) else textSlot(tabId, slot, item, info, z) end
			local hit = hitArea(frame, slot, item, info, z + 5)
			hit.Name = "Slot_" .. tostring(item.id)
			if info.fresh and info.found then newTag(frame, slot, z + 6) end
		end
		if p.pager then
			brassButton(p.pager.prev, "<", function() self.turn(-1) end).Name = "PagePrev"
			brassButton(p.pager.next, ">", function() self.turn(1) end).Name = "PageNext"
			local plate = brassButton(p.pager.label, Layout.pageText(st.page, pages), nil)
			plate.AutoButtonColor = false
			plate.TextSize = 16
			plate.Name = "PagePlate"
		end
	end

	function self.page() return st.page end
	function self.pages() return Layout.pageCount(#st.items, st.tabId) end
	function self.turn(delta)
		local to = Layout.clampPage(st.page + delta, #st.items, st.tabId)
		if to ~= st.page then
			st.page = to
			render()
		end
	end

	-- tabId = the section; items = its entries in order (already filtered); describe(item) -> info; onPick(item) opens the detail card
	function self.show(tabId, items, describe, onPick, keepPage)
		if st.tabId ~= tabId then st.page = 1 end
		st.tabId, st.items, st.describe, st.onPick = tabId, items, describe, onPick
		if keepPage == false then st.page = 1 end
		frame.Visible = true
		render()
	end

	function self.hide()
		frame.Visible = false
		clear()
	end

	function self.layout(w, h)
		area.w, area.h = w, h
		if frame.Visible and st.tabId then render() end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not frame.Visible or not st.tabId then return end
		if opts.isActive and not opts.isActive() then return end
		if input.KeyCode == Enum.KeyCode.Left then self.turn(-1) elseif input.KeyCode == Enum.KeyCode.Right then self.turn(1) end
	end)

	return self
end

return CollectionSection
