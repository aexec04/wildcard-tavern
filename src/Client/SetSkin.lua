--[[
	Client/SetSkin.lua
	One place where the equipped Card Set reskins the UI (slots in CosmeticSets.skinOf, art in Engine/SetSkinArt.lua).

	  SetSkin.set(skin)                    stores the equipped skin and restyles everything registered (live on equip)
	  SetSkin.register(inst, kind)         kind = "panel" | "button" | "tab"; called by VisualHelpers.polishPanel and
	                                       polishButton, PanelTabs and the HUD hookup in CosmeticSetsView
	  SetSkin.sample(inst, kind, skin)     styles a preview element with any set's skin (Card Sets panel)
	  SetSkin.cardLayers(face, z, rank)    paper texture, frame overlay and court ornament for a card FRONT

	With art: panels and buttons get an ImageLabel overlay (panelFrame / buttonPlate), tabs get tabPlate, card faces get
	facePaper (tiled under the pips), faceFrame (border overlay) and faceCourt (J, Q, K centrepiece); indexLayers adds light plates so ranks stay readable. Without art the set's
	colours do the work: panel and button rings take the set's border colour, tabs a tinted wash, and card faces keep
	CardFace's own paper wash and border. The default set keeps today's look. Overlays are children of the element itself
	(so Clone() keeps them) and are skipped for ScrollingFrames and anything holding a UIListLayout or UIGridLayout.
]]

local SetSkin = {}

local current = { images = {}, colors = nil, neutral = true }
local registry = setmetatable({}, { __mode = "k" }) -- [instance] = kind

local OVERLAY = "SetSkinPlate"
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

-- Restyle one registered element for the current skin. Safe to call repeatedly.
local function style(inst, kind, skin)
	if not inst.Parent or inst:IsA("ScrollingFrame") or hasLayout(inst) then return end
	skin = skin or current
	local images, colors = skin.images, skin.colors
	local image = (kind == "panel" and images.panelFrame) or (kind == "button" and images.buttonPlate) or (kind == "tab" and images.tabPlate) or nil
	-- Borders frame, they do not dominate: lighter plates, and the older gold frame pieces (inner rim, brackets, carved
	-- holder art) step aside while a set plate is drawn so there is one frame, not two.
	local label = plate(inst, OVERLAY, image, inst.ZIndex + 1, kind == "panel" and 0.35 or 0.25)
	local hide = label ~= nil
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
		plate(face, "SetSkinFrame", images.faceFrame, zIndex, 0.15)
	end
end

local function indexPlate(face, name, z, color, pos, size)
	local p = Instance.new("Frame")
	p.Name = name
	p.BackgroundColor3 = color
	p.BackgroundTransparency = 0.12
	p.BorderSizePixel = 0
	p.Active = false
	p.Position = pos
	p.Size = size
	p.ZIndex = z
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = p
	p.Parent = face
end

-- Light plates behind the top-left and mirrored bottom-right index. Returns the ink Color3 to use (nil when the set has
-- no index style, i.e. the default set) and the ZIndex the index labels must use.
function SetSkin.indexLayers(face, zIndex, isRed, skin)
	skin = skin or current
	local style = skin.index and (isRed and skin.index.red or skin.index.black)
	if not style then return nil, zIndex end
	local color = rgb(style.plate)
	indexPlate(face, "IndexPlate", zIndex + 1, color, UDim2.fromScale(0.1, 0.08), UDim2.fromScale(0.3, 0.3))
	indexPlate(face, "IndexPlateBottom", zIndex + 1, color, UDim2.fromScale(0.62, 0.74), UDim2.fromScale(0.24, 0.17))
	return rgb(style.ink), zIndex + 2
end

-- Targets in the table HUD that wear the panel treatment (found by name, once the instance exists).
SetSkin.HUD_PANELS = { "SidebarBoard", "HandTray", "DeckWidget" }

return SetSkin
