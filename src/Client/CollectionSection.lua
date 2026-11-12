--[[
	Client/CollectionSection.lua
	A Collection section as a painted scene. Opening Patrons, Recipes, Boss Rounds, House Passes, Titles or Bonds from the gallery room
	shows that section's own painted close-up (art `collection_scene` coll_sec_<section>_a) as ONE cover-fitted picture, and every entry
	sits INSIDE a painted slot: a portrait in its gilded frame with the name on the brass plate, a boss standing on its pedestal, ink on a
	parchment card, a paper tag or a brass nameplate. The section pages (12 entries a page, Bonds 8) with brass arrow plates and a
	"Page 2 of 7" plate that live in the panel's bottom strip (a `SectionPager` host, rect from CollectionRoomLayout.panel, never over the
	scene), and with the Left and Right keys. Slot geometry is Engine/CollectionSectionLayout.lua (tested). The scene has its own region:
	the picture is contained with 8 px of margin, the rest of the region is the dimmed Collection wall, and the picture's edges are
	feathered into it (SmoothVignette, the one sanctioned Transparency gradient).

	A locked entry stays on its slot, painted plate lit, with its name in text that reads at 4.5:1 (CollectionSectionLayout.inkOn); a
	click calls onPick(item) (the Collection's detail card). No tween anywhere, so calm mode needs no special case. Collection.lua keeps the
	old scrolling grid when canShow(tabId) is false (no Image id, or a window too small for readable slots).

	CollectionSection.new({ parent, zIndex, isActive = function() -> bool, addTooltip }) -> {
		frame, canShow(tabId), show(tabId, items, describe, onPick), hide(), layout(w, h), setPager(rect), page(), pages(), turn(delta)
	}
	describe(item) -> { found, name, line, artId, icon, rarityColor, equipped, fresh, tip }
]]

local UserInputService = game:GetService("UserInputService")

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("CollectionSectionLayout"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local SmoothVignette = require(script.Parent.SmoothVignette)
local TweenService = game:GetService("TweenService")
local ClientSettings = require(script.Parent.ClientSettings)

local CollectionSection = {}

local INK = Color3.fromRGB(58, 38, 18)
local INK_BRASS = Color3.fromRGB(52, 34, 14)
local CREAM = Color3.fromRGB(240, 226, 190)
local BRASS_RGB = { 176, 136, 58 }
local BRASS = Color3.fromRGB(BRASS_RGB[1], BRASS_RGB[2], BRASS_RGB[3])
local WALL = Color3.fromRGB(24, 17, 11)
local ZSTEP = 1
local FEATHER = 40 -- px of the picture's edge that melts into the wall
local WALL_DIM = 0.35 -- the side wall is dimmed by this much

local function inkOf(bg, locked)
	local r = Layout.inkOn(bg, locked)
	return Color3.fromRGB(r.color[1], r.color[2], r.color[3]), r.transparency
end

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
		Name = "SectionScene", BackgroundColor3 = WALL, BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
		Visible = false, ZIndex = z0,
	})
	self.frame = frame
	-- the page arrows and plate: a host in the panel's bottom strip (outside the scene frame), shown with the scene
	local pagerHost = make("Frame", opts.parent, { Name = "SectionPager", BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, ZIndex = z0 + 6 })
	local pagerRect = nil
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
		for _, child in ipairs(pagerHost:GetChildren()) do child:Destroy() end
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
		tag.Position = UDim2.fromOffset(r.x + 30, r.y + 2) -- the rarity gem sits at the slot corner
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

	-- the portrait kinds: Patrons (the portrait sits INSET in the frame's dark canvas) and Boss Rounds (it stands on the pedestal)
	-- name plate text: fixed plate height, scaled to fit between PLATE_MIN and PLATE_MAX, truncated at the end, never clipped
	local function plateText(plate)
		plate.TextScaled = true
		plate.TextWrapped = true
		plate.TextTruncate = Enum.TextTruncate.AtEnd
		plate.TextYAlignment = Enum.TextYAlignment.Center
		local c = Instance.new("UITextSizeConstraint")
		c.MinTextSize, c.MaxTextSize = Layout.PLATE_MIN, Layout.PLATE_MAX
		c.Parent = plate
		make("UIPadding", plate, { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) })
	end
	local PATRON_INSET = 0.06 -- of the frame, per side, so the art never touches the gilded edge
	local function portraitSlot(tabId, slot, item, info, z)
		local standing = tabId == "bosses"
		local well = { x = slot.x, y = slot.y, w = slot.w, h = slot.h }
		if not standing then
			local ix, iy = math.floor(slot.w * PATRON_INSET), math.floor(slot.h * PATRON_INSET)
			well = { x = slot.x + ix, y = slot.y + iy, w = slot.w - 2 * ix, h = slot.h - 2 * iy }
		end
		local holder = make("Frame", frame, { Name = "Portrait", BackgroundTransparency = standing and 1 or 0, BorderSizePixel = 0, ZIndex = z })
		holder.BackgroundColor3 = info.found and Color3.fromRGB(46, 36, 26) or Color3.fromRGB(26, 20, 15)
		rect(holder, well)
		if standing then corner(holder, 8) end -- lightly rounded on the pedestal, never a hard dark rectangle
		local art = info.artId and make("ImageLabel", holder, {
			Name = "ContentArt", BackgroundTransparency = 1, Image = info.artId, ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1), ZIndex = z + ZSTEP,
			ImageColor3 = info.found and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(78, 72, 66),
		}) or nil
		if art and standing then corner(art, 8) end
		if not art then
			make("TextLabel", holder, {
				Text = info.icon or "?", Font = Enum.Font.GothamBold, TextSize = 28, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
				TextColor3 = CREAM, TextTransparency = info.found and 0 or 0.55, TextStrokeTransparency = 1, ZIndex = z + ZSTEP,
			})
		end
		-- a locked Patron dims only its portrait, the painted frame stays lit
		if not info.found and not standing then dimOver(frame, well, z + 2, nil) end
		if slot.plate then
			local ink, transparency = inkOf(BRASS_RGB, not info.found)
			local plate = make("TextButton", frame, {
				Name = "Plate", AutoButtonColor = false, BackgroundColor3 = BRASS, BorderSizePixel = 0,
				Text = tostring(info.name), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = ink, TextWrapped = true,
				TextTransparency = transparency, TextStrokeTransparency = 1, ZIndex = z + 3,
			})
			rect(plate, (Layout.plateFit(info.name, slot.plate)))
			plateText(plate)
			corner(plate, 4)
			plate.MouseButton1Click:Connect(function() pick(item) end)
		end
	end

	-- the text kinds: ink on a card, a tag or a nameplate, shrink-to-fit. The painted slot stays lit (no dark wash over the text); a
	-- locked entry is told apart by softer text that still reads at 4.5:1 against the slot's own paper
	-- a key-rack tag (House Passes): the pass icon on the paper tag, the name on the brass plate under it (shared with portraitSlot)
	local function tagSlot(tabId, slot, item, info, z)
		local inner = slot.inner
		local holder = make("Frame", frame, { Name = "TagIcon", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = z })
		rect(holder, inner)
		if info.artId then
			make("ImageLabel", holder, {
				Name = "ContentArt", BackgroundTransparency = 1, Image = info.artId, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(1, 1),
				ZIndex = z + ZSTEP, ImageColor3 = info.found and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(110, 96, 78),
			})
		else
			local ink, transparency = inkOf(Layout.paperOf(tabId) or BRASS_RGB, not info.found)
			make("TextLabel", holder, {
				Text = info.icon or "?", Font = Enum.Font.GothamBold, TextSize = 28, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
				TextColor3 = ink, TextTransparency = transparency, TextStrokeTransparency = 1, ZIndex = z + ZSTEP,
			})
		end
		if slot.plate then
			local ink, transparency = inkOf(BRASS_RGB, not info.found)
			local plate = make("TextButton", frame, {
				Name = "Plate", AutoButtonColor = false, BackgroundColor3 = BRASS, BorderSizePixel = 0,
				Text = tostring(info.name), Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = ink, TextWrapped = true,
				TextTransparency = transparency, TextStrokeTransparency = 1, ZIndex = z + 3,
			})
			rect(plate, (Layout.plateFit(info.name, slot.plate)))
			plateText(plate)
			corner(plate, 4)
			plate.MouseButton1Click:Connect(function() pick(item) end)
		end
	end

	local function textSlot(tabId, slot, item, info, z)
		local kind = Layout.kind(tabId)
		local inner = slot.inner
		local ink, transparency = inkOf(Layout.paperOf(tabId) or BRASS_RGB, not info.found)
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
	end

	-- Rarity on a slot: a muted rim in the tier colour around the slot, a thin underline of it on the name plate, a small gem at the top
	-- left, a very faint inner glow from Epic up and (not in calm mode) a slow shimmer on Mythical. Locked entries keep the tint, dimmed.
	local function rarityMarks(slot, info, z)
		local c = info.rarityColor
		if not c then return end
		local calm = false
		pcall(function() calm = ClientSettings.get("reduceShake") == true end)
		local k = 0.2 -- locked entries get the same full tier colour as found ones
		local tint = c:Lerp(Color3.fromRGB(60, 44, 28), k * 0.5)
		local common = info.rarity == "common"
		local rim = make("Frame", frame, { Name = "RarityRim", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = z + 4 })
		rect(rim, slot)
		corner(rim, 6)
		local stroke = make("UIStroke", rim, { Color = tint, Thickness = common and 2 or 5, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
		local tier = info.rarity
		if info.found and (tier == "epic" or tier == "legendary" or tier == "mythical") then
			local glow = make("Frame", frame, { Name = "RarityGlow", BackgroundColor3 = c, BackgroundTransparency = 0.93, BorderSizePixel = 0, ZIndex = z + 4 })
			rect(glow, slot)
			corner(glow, 6)
			if tier == "mythical" and not calm then
				task.spawn(function()
					while glow.Parent do
						TweenService:Create(glow, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 0.85 }):Play()
						task.wait(1.6)
						if not glow.Parent then break end
						TweenService:Create(glow, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 0.95 }):Play()
						task.wait(1.6 + 3)
					end
				end)
			end
		end
		local gem = make("Frame", frame, { Name = "RarityGem", BackgroundColor3 = c, BorderSizePixel = 0, Rotation = 45, ZIndex = z + 5 })
		gem.Position = UDim2.fromOffset(slot.x + 10, slot.y + 10)
		gem.Size = UDim2.fromOffset(16, 16)
		gem.BackgroundTransparency = 0
		make("UIStroke", gem, { Color = Color3.fromRGB(30, 20, 10), Thickness = 2 })
		local plate = slot.plate
		if plate then
			local pr = Layout.plateFit(info.name, plate)
			if not common then -- very dark version of the rarity colour behind the name
				local fill = make("Frame", frame, { Name = "RarityPlateFill", BackgroundColor3 = c:Lerp(Color3.fromRGB(12, 8, 6), 0.78), BorderSizePixel = 0, ZIndex = z, BackgroundTransparency = 0.2 })
				rect(fill, pr)
				corner(fill, 4)
			end
			local line = make("Frame", frame, { Name = "RarityUnderline", BackgroundColor3 = tint, BorderSizePixel = 0, ZIndex = z + 4 })
			line.Position = UDim2.fromOffset(pr.x + 3, pr.y + pr.h - 3)
			line.Size = UDim2.fromOffset(math.max(1, pr.w - 6), 2)
			line.BackgroundTransparency = 0
		end
	end

	local function brassButton(r, text, onClick)
		local b = make("TextButton", pagerHost, {
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
		-- the side areas: the dimmed Collection wall (cover-cropped), never flat black
		local wallId = ContentArt.getImageId("collection_scene", "collection_wall")
		if wallId then
			make("ImageLabel", frame, { Name = "SideWall", BackgroundTransparency = 1, Image = wallId, ScaleType = Enum.ScaleType.Crop, Size = UDim2.fromScale(1, 1), ZIndex = z0 })
			make("Frame", frame, { Name = "SideWallDim", BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 1 - WALL_DIM, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z0 })
		else
			make("Frame", frame, { Name = "SideWall", BackgroundColor3 = WALL, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = z0 })
		end
		local img = artId(tabId)
		if img then
			local im = make("ImageLabel", frame, { Name = "Scene", BackgroundTransparency = 1, Image = img, ScaleType = Enum.ScaleType.Stretch, ZIndex = z0 })
			im.Position = UDim2.fromOffset(math.floor(p.image.x), math.floor(p.image.y))
			im.Size = UDim2.fromOffset(math.ceil(p.image.w), math.ceil(p.image.h))
			-- feather: a 40 px fade on every picture edge that lies inside the region, into the dimmed wall
			local f = Layout.feather(p, FEATHER)
			if f then
				local holder = make("Frame", frame, { Name = "Feather", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = z0 })
				rect(holder, f.rect)
				local spec = { zIndex = z0, color = Color3.fromRGB(22, 15, 10), name = "SceneFeather" }
				for edge, extent in pairs(f.edges) do spec[edge] = { strength = 0.9, extent = extent } end
				SmoothVignette.build(holder, spec)
			end
		end
		local z = z0 + 1 -- every piece stays under the detail card (30) and the toast
		for i, item in ipairs(Layout.pageItems(st.items, tabId, st.page)) do
			local slot = p.slots[i]
			local info = st.describe(item)
			if Layout.kind(tabId) == "tag" then tagSlot(tabId, slot, item, info, z)
			elseif Layout.scene(tabId).plate then portraitSlot(tabId, slot, item, info, z)
			else textSlot(tabId, slot, item, info, z) end
			rarityMarks(slot, info, z)
			local hit = hitArea(frame, slot, item, info, z + 5)
			hit.Name = "Slot_" .. tostring(item.id)
			if info.fresh and info.found then newTag(frame, slot, z + 6) end
		end
		if pagerRect and pages > 1 then
			pagerHost.Visible = true
			local pg = Layout.pager(pagerRect.w)
			brassButton(pg.prev, "<", function() self.turn(-1) end).Name = "PagePrev"
			brassButton(pg.next, ">", function() self.turn(1) end).Name = "PageNext"
			local plate = brassButton(pg.label, Layout.pageText(st.page, pages), nil)
			plate.AutoButtonColor = false
			plate.TextSize = 16
			plate.Name = "PagePlate"
		else
			pagerHost.Visible = false
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
		pagerHost.Visible = false
		clear()
	end

	-- the strip rect (panel pixels) for the page arrows and plate; nil = no room for them (a narrow panel)
	function self.setPager(r)
		pagerRect = r
		if r then rect(pagerHost, r) end
		if frame.Visible and st.tabId then render() end
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
