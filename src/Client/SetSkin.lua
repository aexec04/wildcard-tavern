--[[
	Client/SetSkin.lua
	One place where the equipped Card Set reskins the UI (slots in CosmeticSets.skinOf, art in Engine/SetSkinArt.lua).

	  SetSkin.set(skin)                    stores the equipped skin and restyles everything registered (live on equip)
	  SetSkin.register(inst, kind)         kind = "panel" | "button" | "tab"; called by VisualHelpers.polishPanel and
	                                       polishButton, PanelTabs and the HUD hookup in CosmeticSetsView
	  SetSkin.sample(inst, kind, skin)     styles a preview element with any set's skin (Card Sets panel)
	  SetSkin.cardLayers(face, z, rank)    paper texture, frame overlay and court ornament for a card FRONT

	With art: panels and buttons get an ImageLabel overlay (panelFrame / buttonPlate), tabs get tabPlate, card faces get
	facePaper (tiled under the pips), faceFrame (border overlay) and faceCourt (J, Q, K centrepiece); indexInfo gives the ink, stroke and inner-window layout so ranks sit inside the frame without any box. Art is cropped to its measured box (Engine/SetSkinMetrics) and 9-sliced (Engine/SkinSlice), never stretched. Without art the set's
	colours do the work: panel and button rings take the set's border colour, tabs a tinted wash, and card faces keep
	CardFace's own paper wash and border. The default set keeps today's look. Overlays are children of the element itself
	(so Clone() keeps them) and are skipped for ScrollingFrames and anything holding a UIListLayout or UIGridLayout.
]]

local PanelBand = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PanelBand"))

local CosmeticSets = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CosmeticSets"))
local CardFaceArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CardFaceArt"))
local PlaySceneArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PlaySceneArt"))
local SkinSlice = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SkinSlice"))

local PanelBorder = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PanelBorder"))

local SetSkin = {}

local current = { images = {}, colors = nil, neutral = true }
local registry = setmetatable({}, { __mode = "k" }) -- [instance] = kind

local OVERLAY = "SetSkinPlate"
local BORDER = "SetSkinBorder"
local WASH = "SetSkinWash"

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function hasLayout(inst)
	return inst:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
end

local function ring(inst)
	return inst:FindFirstChildOfClass("UIStroke")
end

local function plate(inst, name, image, z, transparency)
	local label = inst:FindFirstChild(name)
	if not image then
		if label then label:Destroy() end
		return nil
	end
	if not label then
		label = Instance.new("ImageLabel")
		label.Name = name
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Active = false
		label.ScaleType = Enum.ScaleType.Stretch
		label.Parent = inst
	end
	label.Image = image
	label.ImageTransparency = transparency or 0
	label.ZIndex = z
	return label
end

-- True when an ancestor is itself a registered panel (nested sub-frames get no plate of their own).
local function nestedPanel(inst)
	local p = inst.Parent
	while p do
		if registry[p] == "panel" then return true end
		p = p.Parent
	end
	return false
end

-- AbsoluteSize includes every ancestor UIScale (a Round Select card's fit/breathe/hover scale), but offsets inside the
-- element are scaled again on screen. Border geometry must use the unscaled local size or it is off whenever the scale is
-- not 1 (the idle card), so divide the ancestor scales back out.
local function localSize(inst)
	local size = inst.AbsoluteSize
	local k = 1
	local node = inst.Parent
	while node do
		local us = node:FindFirstChildOfClass("UIScale")
		if us and us.Scale > 0 then k = k * us.Scale end
		node = node.Parent
	end
	local own = inst:FindFirstChildOfClass("UIScale")
	if own and own.Scale > 0 then k = k * own.Scale end
	return Vector2.new(size.X / k, size.Y / k)
end

local SLOT_KEY = { panel = "panel_frame", button = "button_plate", tab = "tab_plate" }

-- Crop the plate to its measured art box and 9-slice it for the element's size (see Engine/SkinSlice). Panels get a band
-- of at most PanelBand.MAX_BAND px; buttons and tabs scale uniformly to their height. Too small for its caps: the plate
-- is hidden and the flat set colours (ring, wash) show instead.
local function fitArt(inst, kind, label, m)
	local crop = SkinSlice.crop(m)
	label.ImageRectOffset = Vector2.new(crop.x, crop.y)
	label.ImageRectSize = Vector2.new(crop.w, crop.h)
	label.ScaleType = Enum.ScaleType.Slice
	local function apply()
		local size = localSize(inst)
		local sl
		if size.X > 0 and size.Y > 0 then
			if kind == "panel" then
				sl = SkinSlice.panelSlice(m, PanelBand.band(size.X, size.Y))
			else
				sl = SkinSlice.plateSlice(m, size.X, size.Y)
			end
		end
		label.Visible = sl ~= nil
		if sl then
			local c = sl.crop or crop -- wide plates show only the plain rails
			label.ImageRectOffset = Vector2.new(c.x, c.y)
			label.ImageRectSize = Vector2.new(c.w, c.h)
			if sl.wide and not label:FindFirstChildOfClass("UICorner") then
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 8)
				corner.Parent = label
			end
			label.SliceCenter = Rect.new(sl.center.l, sl.center.t, sl.center.r, sl.center.b)
			label.SliceScale = sl.scale
		end
	end
	apply()
	if not label:GetAttribute("BandHooked") then
		label:SetAttribute("BandHooked", true)
		inst:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	end
end

-- Code-drawn panel border (Engine/PanelBorder): dark outer line, accent inner line, tiny corner brackets. Always fits at
-- the panel's true size; children of the panel so Clone() keeps them. Created once, recoloured on every call.
local function codeBorder(inst, accent)
	local holder = inst:FindFirstChild(BORDER)
	if not accent then
		if holder then holder:Destroy() end
		return nil
	end
	if not holder then
		holder = Instance.new("Frame")
		holder.Name = BORDER
		holder.Size = UDim2.fromScale(1, 1)
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Active = false
		local outer = Instance.new("UIStroke")
		outer.Name = "Outer"
		outer.Thickness = PanelBorder.OUTER_LINE
		outer.Color = Color3.fromRGB(20, 12, 6)
		outer.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		outer.Parent = holder
		local innerLine = Instance.new("Frame")
		innerLine.Name = "Inner"
		innerLine.BackgroundTransparency = 1
		innerLine.BorderSizePixel = 0
		innerLine.Active = false
		local innerStroke = Instance.new("UIStroke")
		innerStroke.Thickness = PanelBorder.INNER_LINE
		innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		innerStroke.Parent = innerLine
		innerLine.Parent = holder
		for i = 1, 8 do
			local b = Instance.new("Frame")
			b.Name = "Bracket" .. i
			b.BorderSizePixel = 0
			b.Active = false
			b.Parent = holder
		end
		holder.Parent = inst
		local function layout()
			local size = localSize(inst)
			if size.X <= 0 or size.Y <= 0 then return end
			local l = PanelBorder.layout(size.X, size.Y)
			innerLine.Position = UDim2.fromOffset(l.inner.x, l.inner.y)
			innerLine.Size = UDim2.fromOffset(l.inner.w, l.inner.h)
			for i, r in ipairs(l.brackets) do
				local b = holder:FindFirstChild("Bracket" .. i)
				if b then
					b.Position = UDim2.fromOffset(r.x, r.y)
					b.Size = UDim2.fromOffset(r.w, r.h)
				end
			end
		end
		layout()
		inst:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	end
	holder.ZIndex = inst.ZIndex
	local inner = holder:FindFirstChild("Inner")
	inner.ZIndex = inst.ZIndex
	inner:FindFirstChildOfClass("UIStroke").Color = accent
	for _, c in ipairs(holder:GetChildren()) do
		if c.Name:sub(1, 7) == "Bracket" then
			c.BackgroundColor3 = accent
			c.ZIndex = inst.ZIndex
		end
	end
	return holder
end

-- Restyle one registered element for the current skin. Safe to call repeatedly.
local function style(inst, kind, skin)
	if kind == "button" and inst:GetAttribute("HudThemed") then return end -- code-drawn by Client/HudTheme
	if not inst.Parent or inst:IsA("ScrollingFrame") or hasLayout(inst) then return end
	skin = skin or current
	local images, colors = skin.images, skin.colors
	-- Panels never use the illustrated panelFrame art (its asymmetric corners cannot be sliced): they get the code border,
	-- or slice-friendly panelFrame9 art when a set has it.
	local image = (kind == "panel" and nil) or (kind == "button" and images.buttonPlate) or (kind == "tab" and images.tabPlate) or nil
	-- Borders frame, they do not dominate: lighter plates, and the older gold frame pieces (inner rim, brackets, carved
	-- holder art) step aside while a set plate is drawn so there is one frame, not two.
	if kind == "panel" and nestedPanel(inst) then image = nil end -- only top-level panels get a frame
	-- Plates sit at the element's own ZIndex (behind its content), never above text, buttons or maps.
	local m = image and kind ~= "panel" and SkinSlice.metrics(skin.id, SLOT_KEY[kind]) or nil
	if kind ~= "panel" and not m then image = nil end -- no measured box: never draw unmeasured (stretched) art
	if kind == "button" and inst:GetAttribute("FlatFace") then image = nil end -- plate art has a baked mark (classic_tavern lantern bracket): flat face
	-- Tome tabs and every Close button are one clean plate: the plate crops showed small garbled shapes at the left and a thin bar at the
	-- right of the label, so they keep their own wood and gold look (tabs also get the faint set wash below).
	if kind == "tab" or (kind == "button" and inst:IsA("TextButton") and (inst.Name == "Close" or inst.Text == "Close")) then image = nil end
	local label = plate(inst, OVERLAY, image, inst.ZIndex, kind == "panel" and 0.35 or 0.25)
	local border = nil
	if kind == "panel" then
		if label then
			-- slice-friendly art: fixed 6 percent edge on a 3:2 canvas (1536x1024), band-thick on screen
			label.ScaleType = Enum.ScaleType.Slice
			label.SliceCenter = Rect.new(92, 61, 1444, 963)
			local function fit() label.SliceScale = PanelBorder.thickness(localSize(inst).X, localSize(inst).Y) / 61 end
			fit()
			if not label:GetAttribute("BandHooked") then
				label:SetAttribute("BandHooked", true)
				inst:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
			end
			codeBorder(inst, nil)
		else
			local accent = colors and rgb(colors.border) or (skin.images.panelFrame and Color3.fromRGB(200, 160, 70)) or nil
			border = codeBorder(inst, accent)
		end
	elseif label then
		fitArt(inst, kind, label, m)
	end
	local hide = (label ~= nil and label.Visible) or border ~= nil
	for _, child in ipairs(inst:GetChildren()) do
		local n = child.Name
		if n == "InnerRim" or n == "BracketH" or n == "BracketV" or n == "SkinArt" then
			if hide and child:GetAttribute("SkinWasVisible") == nil then
				child:SetAttribute("SkinWasVisible", child:IsA("GuiObject") and child.Visible or true)
			end
			if child:IsA("GuiObject") then
				if hide then child.Visible = false
				elseif child:GetAttribute("SkinWasVisible") ~= nil then
					child.Visible = child:GetAttribute("SkinWasVisible")
					child:SetAttribute("SkinWasVisible", nil)
				end
			end
		end
	end

	if kind == "tab" then
		-- Tabs keep PanelTabs' own wood and gold states; the set adds a faint wash when it has no plate art.
		local wash = inst:FindFirstChild(WASH)
		if colors and not image then
			if not wash then
				wash = Instance.new("Frame")
				wash.Name = WASH
				wash.Size = UDim2.fromScale(1, 1)
				wash.BorderSizePixel = 0
				wash.Active = false
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 8)
				corner.Parent = wash
				wash.Parent = inst
			end
			wash.BackgroundColor3 = rgb(colors.tab)
			wash.BackgroundTransparency = 0.72
			wash.ZIndex = inst.ZIndex
		elseif wash then
			wash:Destroy()
		end
		return
	end

	if kind == "button" and colors and inst:IsA("TextButton") and image then
		-- readable on the plate: cream or ink by contrast with the set's button colour, plus a thin dark stroke
		local t = CosmeticSets.buttonTextColor(colors.button)
		inst.TextColor3 = rgb(t)
		inst.TextTransparency = 0
		inst.TextStrokeColor3 = Color3.fromRGB(20, 12, 6)
		inst.TextStrokeTransparency = t[1] > 128 and 0.6 or 1
	end

	local stroke = ring(inst)
	if stroke then
		local original = stroke:GetAttribute("SkinOriginalColor")
		if not original then
			original = stroke.Color
			stroke:SetAttribute("SkinOriginalColor", original)
		end
		stroke.Color = colors and rgb(colors.border) or original
	end
end

function SetSkin.register(inst, kind)
	if not inst or registry[inst] then return end
	registry[inst] = kind
	-- one frame later, once the caller has finished setting ZIndex, children and layouts (same as addOrnateFrame)
	task.defer(style, inst, kind)
end

function SetSkin.set(skin)
	if skin == current then return end
	current = skin or { images = {}, colors = nil, neutral = true }
	-- Play/Discard, Sort toggle, round icons, draw pile, left panel: applied once the set's kit images are loaded (old look until then)
	local mine = current
	pcall(function()
		require(script.Parent.HudKitPreload).whenReady(mine.id, function()
			if current ~= mine then return end -- another set was picked while loading
			pcall(function() require(script.Parent.HudTheme).setSkin(mine) end)
		end)
	end)
	for inst, kind in pairs(registry) do
		if inst.Parent then style(inst, kind) else registry[inst] = nil end
	end
end

-- Style a sample element (Card Sets preview) with a given set's skin instead of the equipped one. Not registered.
function SetSkin.sample(inst, kind, skin)
	style(inst, kind, skin)
end

function SetSkin.get()
	return current
end

local COURT = { J = true, Q = true, K = true }

-- Card FRONT layers, drawn under the corner and centre labels. `skin` defaults to the equipped one.
-- Explicit order: paper < court < frame < index plates (z + 1); CardFace puts the rank text at z + 2.
-- Paper and court are calmed so the pips and index read; the frame is a thin accent.
function SetSkin.cardLayers(face, zIndex, rankText, skin)
	skin = skin or current
	local images = skin.images
	local ivory = CardFaceArt.ivoryAlone(skin, CardFaceArt.resolve(PlaySceneArt))
	if not SetSkin._warned then
		SetSkin._warned = true
		warn(("[SetSkin] cardLayers set=%s ivoryAlone=%s SetSkinFrame=%s SetSkinPaper=%s"):format(tostring(skin.id), tostring(ivory), tostring(not ivory and skin.images.faceFrame ~= nil), tostring(not ivory and skin.images.facePaper ~= nil)))
	end
	if ivory then images = {} end -- the painted ivory face stands alone: no paper tile, court ornament or orange frame
	if skin.neutral and not images.faceFrame then
		pcall(function() require(script.Parent.ClassicCardFrame).draw(face, zIndex) end) -- the default set's real border
	end
	if images.facePaper then
		local paper = plate(face, "SetSkinPaper", images.facePaper, zIndex, 0.7)
		if paper then
			paper.ScaleType = Enum.ScaleType.Tile
			paper.TileSize = UDim2.fromScale(0.5, 0.5)
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = paper
		end
	end
	if images.faceCourt and COURT[rankText] then
		local court = plate(face, "SetSkinCourt", images.faceCourt, zIndex, 0.7)
		if court then
			court.AnchorPoint = Vector2.new(0.5, 0.5)
			court.Position = UDim2.fromScale(0.5, 0.53)
			court.Size = UDim2.fromScale(0.5, 0.36)
			court.ScaleType = Enum.ScaleType.Fit
		end
	end
	if images.faceFrame then
		local m = SkinSlice.metrics(skin.id, "face_frame")
		local frame = plate(face, "SetSkinFrame", images.faceFrame, zIndex, 0.15)
		if frame then
			if m then
				-- cropped to the visible art so the painted border sits on the card edge (no padding band)
				frame.ImageRectOffset = Vector2.new(m.x, m.y)
				frame.ImageRectSize = Vector2.new(m.cw, m.ch)
				local shrink = SkinSlice.indexWindow(m).shrink
				frame.Position = UDim2.fromScale(shrink, shrink)
				frame.Size = UDim2.fromScale(1 - 2 * shrink, 1 - 2 * shrink)
			end
			frame.ScaleType = Enum.ScaleType.Stretch
		end
	end
end

-- Index (corner rank and suit) styling. No box: the ink (4.5:1 against the paper) gets a soft paper-coloured stroke.
-- Returns nil for the default set; otherwise { ink = Color3, stroke = Color3, layout = SkinSlice.indexLayout } where the
-- layout sits inside the frame's measured inner window.
function SetSkin.indexInfo(isRed, skin)
	skin = skin or current
	local style = skin.index and (isRed and skin.index.red or skin.index.black)
	if not style then return nil end
	local win = SkinSlice.indexWindow(skin.images.faceFrame and SkinSlice.metrics(skin.id, "face_frame") or nil)
	return { ink = rgb(style.ink), stroke = rgb(style.plate), layout = SkinSlice.indexLayout(win) }
end

-- Targets in the table HUD that wear the panel treatment (found by name, once the instance exists).
SetSkin.HUD_PANELS = { "SidebarBoard", "HandTray", "DeckWidget" }

return SetSkin
