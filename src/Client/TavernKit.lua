--[[
	Client/TavernKit.lua
	Shared UI pieces in the look of the main menu and the Night screen, drawn only with Frame, UICorner, UIStroke, UIGradient and
	text (no images, so nothing is stretched). Numbers and colors: Engine/TavernStyle, written up in claude/STYLE-TAVERN.md.

	TavernKit.plate(parent, size)            -> Frame      dark brown plate, thin gold trim
	TavernKit.primaryButton(parent, text)    -> TextButton green, one drawn rect that is also the click rect
	TavernKit.secondaryButton(parent, text)  -> TextButton brown
	TavernKit.pill(parent, text, color)      -> Frame      small rounded chip; color is a TavernStyle.PILLS name
	TavernKit.goldBox(parent, text)          -> Frame      the dark Target box with a gold number
	TavernKit.title(parent, text)            -> TextLabel  serif cream title with a dark outline
	TavernKit.skin(button, text, kind)       style an existing TextButton as primary or secondary (the real instance stays the click target)
	TavernKit.feel(button)                   hover lift and press squeeze, a no-op in Calm mode, Reduce motion and Fast speed

	Gradients are Color only, never Transparency. Position the returned instance yourself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TavernStyle"))
local ImagePreload = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ImagePreload"))

local TavernKit = {}

local function rgb(c) return Color3.fromRGB(c[1], c[2], c[3]) end
local function col(name) return rgb(Style.rgb(name)) end

-- Calm mode, Reduce motion (both end in reduceShake) or Fast speed: no motion at all.
local function still()
	local ok, ClientSettings = pcall(function() return require(script.Parent.ClientSettings) end)
	if not ok then return true end
	return ClientSettings.get("reduceShake") == true or ClientSettings.get("animSpeed") == "fast"
end
TavernKit.still = still

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function stroke(inst, colorName, thickness)
	local s = Instance.new("UIStroke")
	s.Color = col(colorName)
	s.Thickness = thickness
	s.Transparency = Style.STROKE.transparency
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function shade(inst, top, bottom)
	local g = Instance.new("UIGradient")
	g.Name = "Shade"
	g.Rotation = 90
	g.Color = ColorSequence.new(top, bottom) -- Color only, never Transparency
	g.Parent = inst
	return g
end

function TavernKit.plate(parent, size)
	local w, h = size and size.X.Offset or 0, size and size.Y.Offset or 0
	local f = Instance.new("Frame")
	f.Name = "TavernPlate"
	f.Size = size or UDim2.fromOffset(Style.plateSize(w, h))
	f.BackgroundColor3 = col("plateFill")
	f.BorderSizePixel = 0
	corner(f, Style.RADIUS.panel)
	stroke(f, "goldTrim", Style.STROKE.plate)
	shade(f, Color3.new(1, 1, 1), Color3.fromRGB(190, 185, 180))
	f.Parent = parent
	return f
end

function TavernKit.feel(button)
	if still() then return end
	local f = Style.feel(false)
	local scale = button:FindFirstChild("PressScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "PressScale"
		scale.Parent = button
	end
	local ButtonFeel = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ButtonFeel"))
	local TweenService = game:GetService("TweenService")
	local info = TweenInfo.new(f.seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local hovering, restPos, posTween = false, nil, nil
	local function settle() -- stop the hover tween and snap to the rest spot (hidden button, layout moved it)
		if posTween then posTween:Cancel() posTween = nil end
		if hovering and restPos then button.Position = restPos end
		hovering = false
	end
	button.MouseEnter:Connect(function()
		if still() then return end
		restPos = ButtonFeel.restFor(hovering, restPos, button.Position)
		hovering = true
		posTween = TweenService:Create(button, info, { Position = restPos - UDim2.fromOffset(0, f.lift) })
		posTween:Play()
	end)
	button.MouseLeave:Connect(function()
		if still() then return end
		if hovering and restPos then
			posTween = TweenService:Create(button, info, { Position = restPos })
			posTween:Play()
		end
		hovering = false
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end)
	button:GetPropertyChangedSignal("Visible"):Connect(function()
		if not button.Visible then settle() end
	end)
	button.MouseButton1Down:Connect(function()
		if still() then return end
		TweenService:Create(scale, info, { Scale = f.press }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		if still() then return end
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end)
end

-- Style a TextButton as a kit button. Used by button() for a new one and by Gameplay v2 for the real Play Hand and Discard
-- instances, so the drawn rect and the click rect are one object. Idempotent (a second call changes nothing visible).
function TavernKit.skin(b, text, kind)
	local k = Style.BUTTONS[kind]
	b:SetAttribute("TavernKind", kind)
	b.AutoButtonColor = false
	b.BackgroundTransparency = 0
	b.BackgroundColor3 = col(k.fill)
	b.BorderSizePixel = 0
	b.Font = Enum.Font[Style.FONTS.ui]
	b.TextSize = Style.TEXT.button
	b.TextColor3 = col(k.text)
	b.TextTransparency = 0
	b.TextStrokeTransparency = 0.3
	b.TextStrokeColor3 = col(kind == "primary" and "buttonStroke" or "outline")
	if text then b.Text = text end
	for _, c in ipairs(b:GetChildren()) do
		if c:IsA("GuiObject") then
			if c.Name ~= "KitLabel" then c.Visible = false end -- old art and labels on a reused button; the label above the plate stays
		elseif c:IsA("UICorner") or c:IsA("UIStroke") or c:IsA("UIGradient") then c:Destroy() end
	end
	corner(b, Style.RADIUS.button)
	stroke(b, k.stroke, Style.STROKE.button)
	local base = rgb(Style.rgb(k.fill))
	shade(b, base:Lerp(Color3.new(1, 1, 1), 0.06), base:Lerp(Color3.new(0, 0, 0), 0.15))
	return b
end

local function button(parent, text, kind)
	local k = Style.BUTTONS[kind]
	local b = Instance.new("TextButton")
	b.Name = kind == "primary" and "TavernPrimary" or "TavernSecondary"
	b.Size = UDim2.new(1, 0, 0, k.height)
	TavernKit.skin(b, text or "", kind)
	b.Parent = parent
	TavernKit.feel(b)
	return b
end

function TavernKit.primaryButton(parent, text) return button(parent, text, "primary") end
function TavernKit.secondaryButton(parent, text) return button(parent, text, "secondary") end

function TavernKit.pill(parent, text, color)
	local fill = Style.PILLS[color or "wood"] or Style.PILLS.wood
	local f = Instance.new("Frame")
	f.Name = "TavernPill"
	f.Size = UDim2.fromOffset(Style.SIZES.pillH * 4, Style.SIZES.pillH)
	f.BackgroundColor3 = rgb(fill)
	f.BorderSizePixel = 0
	corner(f, Style.SIZES.pillH // 2)
	stroke(f, "goldTrimPlate", Style.STROKE.button)
	local t = Instance.new("TextLabel")
	t.Name = "Word"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font[Style.FONTS.ui]
	t.TextSize = Style.TEXT.min
	t.TextColor3 = col("creamChip")
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0.3
	t.TextStrokeColor3 = col("outline")
	t.Text = text or ""
	t.Parent = f
	f.Parent = parent
	return f
end

function TavernKit.goldBox(parent, text)
	local f = Instance.new("Frame")
	f.Name = "TavernGoldBox"
	f.Size = UDim2.new(1, 0, 0, Style.SIZES.boxH)
	f.BackgroundColor3 = col("plateDark")
	f.BorderSizePixel = 0
	corner(f, Style.RADIUS.chip)
	stroke(f, "goldTrim", Style.STROKE.button)
	local t = Instance.new("TextLabel")
	t.Name = "Value"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font[Style.FONTS.ui]
	t.TextSize = Style.TEXT.box
	t.TextColor3 = col("gold")
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0.4
	t.TextStrokeColor3 = col("outline")
	t.Text = text or ""
	t.Parent = f
	f.Parent = parent
	return f
end

-- Painted frame (Engine/TavernStyle.PAINTED, art from Engine/PaintedKitArt): wraps any plate in its painted nine-slice picture.
-- The picture is a SIBLING drawn just under the plate (ZIndex - 1), so the plate's own words and children, `raise` and a Clone of the
-- plate are untouched; it follows the plate's Position, Size, AnchorPoint, Visible and ZIndex. The plate's flat fill and stroke go
-- transparent while the picture is up; if the picture has not loaded after PAINTED_LOAD_WAIT seconds, or there is no id, the flat look
-- stays or comes back. Words stay on the plate (a button keeps its KitLabel, its own text stays transparent). Returns the ImageLabel or nil.
local paintedArt
local plateSetId -- defined below: the Card Set whose plates are drawn now
local paintOf = setmetatable({}, { __mode = "k" }) -- host -> its picture: two sibling buttons both named "TextButton" must not share one "TextButtonPaint"
function TavernKit.painted(host, piece)
	if not host or not host.Parent or not Style.PAINTED[piece] then return nil end
	host:SetAttribute("BasePiece", piece)
	local sid = plateSetId()
	piece = Style.setPiece(piece, sid) -- the set's own plate when it has one (tabs, Tips and Next boss wear it with the buttons)
	local tint -- no own picture for this set: the classic one takes the set's hue
	if piece == host:GetAttribute("BasePiece") and sid and not Style.isSetPiece(piece) then
		pcall(function()
			local CS = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CosmeticSets"))
			tint = Style.setTint(sid, CS.accentOf(CS.getById(sid)))
		end)
	end
	local def = Style.PAINTED[piece]
	if paintedArt == nil then
		local ok, art = pcall(function() return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PaintedKitArt")) end)
		paintedArt = ok and art or false
		local bad = Style.plateAudit() -- one Studio line: any plate whose picture would be cropped
		print("[PlateSlices] " .. (#bad == 0 and ("ok, all plates fit at " .. #Style.AUDIT_SIZES .. " sizes") or table.concat(bad, "; ")))
	end
	local id = paintedArt and paintedArt[def.art]
	if not id or id == "" then return nil end
	local old = paintOf[host]
	if old and old.Parent and old:GetAttribute("PaintPiece") == piece and (old:GetAttribute("SetTint") == true) == (tint ~= nil) and old:GetAttribute("TintSet") == (tint and sid or nil) then return old end
	if old then old:Destroy() end
	local img = Instance.new("ImageLabel")
	img.Name = host.Name .. "Paint"
	img:SetAttribute("PaintPiece", piece)
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Active = false
	img.Image = id
	img.ImageTransparency = 0
	if tint then img.ImageColor3 = Color3.fromRGB(tint[1], tint[2], tint[3]); img:SetAttribute("SetTint", true); img:SetAttribute("TintSet", sid); img:SetAttribute("TintColor", img.ImageColor3) end
	local flatBg = host.BackgroundTransparency
	local strokes = {}
	local function fit()
		img.AnchorPoint = host.AnchorPoint
		img.Position = host.Position
		img.Size = host.Size
		img.Visible = host.Visible
		img.ZIndex = math.max(0, host.ZIndex - 1)
		-- a plate that names its own layout size (attributes PaintW and PaintH) slices by that, not by AbsoluteSize: under a scaled
		-- parent AbsoluteSize is in screen pixels while SliceScale is in local units, which can push the right corners off the plate
		local pw, ph = host:GetAttribute("PaintW"), host:GetAttribute("PaintH")
		local sl = Style.paintedTexSlice(piece, pw or host.AbsoluteSize.X, ph or host.AbsoluteSize.Y)
		if sl then
			img.ScaleType = Enum.ScaleType.Slice
			img.SliceCenter = Rect.new(sl.left, sl.top, sl.right, sl.bottom)
			img.SliceScale = sl.scale
		elseif def.whole then
			img.ScaleType = Enum.ScaleType.Stretch -- a finished picture at the plate's aspect: no slicing
		else
			img.ScaleType = Enum.ScaleType.Fit
		end
	end
	local function flatOff(on)
		for _, c in ipairs(host:GetChildren()) do
			if c:IsA("UIStroke") then
				if on and strokes[c] == nil then strokes[c] = c.Enabled end
				c.Enabled = (not on) and (strokes[c] ~= false)
			end
		end
	end
	img.Parent = host.Parent
	paintOf[host] = img
	fit()
	flatOff(true)
	host.BackgroundTransparency = 1
	for _, prop in ipairs({ "Position", "Size", "AnchorPoint", "Visible", "ZIndex", "AbsoluteSize" }) do
		host:GetPropertyChangedSignal(prop):Connect(fit)
	end
	-- a module that sets the plate opaque again (skin, an apply loop) does not bring the flat fill back over the picture
	host:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		if img.Parent and host.BackgroundTransparency ~= 1 then host.BackgroundTransparency = 1 end
	end)
	-- No picture, no change: the flat look returns. The verdict is the PreloadAsync status, never ImageLabel.IsLoaded: IsLoaded stays false
	-- for a label inside a hidden screen (the table HUD is built before the play screen shows), which used to destroy every picture built
	-- early and leave a flat grey plate. PAINTED_LOAD_WAIT is only the longest we wait for a verdict.
	task.spawn(function()
		local decided, loaded = false, false
		task.delay(Style.PAINTED_LOAD_WAIT * 4, function() decided = true end)
		task.spawn(function()
			loaded = ImagePreload.run(ContentProvider, img, Enum.AssetFetchStatus.Success)
			decided = true
		end)
		while not decided do task.wait(0.1) end
		if img.Parent and not loaded and not img.IsLoaded then
			warn("[PaintedKit] " .. piece .. " did not load (" .. tostring(def.art) .. "), flat look kept")
			img:Destroy()
			flatOff(false)
			host.BackgroundTransparency = (flatBg >= 1) and 0 or flatBg -- a plate that was see-through when wrapped still gets a flat fill, never bare text
		end
	end)
	host.Destroying:Connect(function() img:Destroy() end)
	return img
end

-- The ornate button for any screen: kind "primary" (green) or "secondary" (dark wood); the piece follows the plate's shape (Style.buttonPiece).
-- The Card Set whose plates are drawn now: the previewed set on the Card Sets screen, else the equipped one (Golden Gala has palace plates).
function plateSetId()
	local ok, sid = pcall(function()
		local TS = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ThemeScenes"))
		local skin = require(script.Parent.HudTheme).skin()
		local okV, view = pcall(function() return require(script.Parent.CosmeticSetsView) end)
		local previewId = okV and view and view.previewSetId and view.previewSetId() or nil
		return TS.effectiveSetId(skin and skin.id, previewId)
	end)
	return ok and sid or nil
end

function TavernKit.plateSetId() return plateSetId() end

-- A primary or secondary plate ONLY when the equipped Card Set has its own (Style.resultPlate); classic and plateless sets keep the caller's
-- flat look untouched. Returns true when the plate was drawn. The button must be parented and sized first.
function TavernKit.setPlateButton(host, kind)
	local sid = plateSetId()
	local piece = Style.resultPlate(kind, host.AbsoluteSize.X, host.AbsoluteSize.Y, sid)
	if not piece then return false end
	local ok, img = pcall(function() return TavernKit.painted(host, piece) end)
	return ok and img ~= nil
end

-- A tab plate (Collection and Leaderboards tabs): the equipped set's green plate while lit, its dark one otherwise; classic keeps the flat
-- browns the caller sets. The tab needs a fixed Size (a plate painted behind an AutomaticSize button would have no width). True when drawn.
function TavernKit.setPlateTab(host, active)
	local piece = Style.tabPlate(active, plateSetId())
	if not piece then return false end
	local ok, img = pcall(function() return TavernKit.painted(host, piece) end)
	if ok and img ~= nil then host.TextColor3 = Color3.fromRGB(250, 240, 220) end
	return ok and img ~= nil
end

local buttonsHooked = false
local function restyleButtons()
	local sid = plateSetId()
	for host in pairs(paintOf) do
		local kind = host.Parent and host:GetAttribute("ButtonKind")
		if kind then TavernKit.painted(host, Style.buttonPiece(kind, host.AbsoluteSize.X, host.AbsoluteSize.Y, sid))
		else
			local base = host.Parent and host:GetAttribute("BasePiece")
			if base then TavernKit.painted(host, base) end
		end
	end
end

function TavernKit.paintedButton(host, kind)
	if not host then return nil end
	host:SetAttribute("ButtonKind", kind)
	if not buttonsHooked then -- a skin change or a Card Set preview re-dresses every ornate button already on screen
		buttonsHooked = true
		pcall(function() require(script.Parent.HudTheme).onSkin(restyleButtons) end)
		pcall(function() require(script.Parent.CosmeticSetsView).onPreview(restyleButtons) end)
	end
	return TavernKit.painted(host, Style.buttonPiece(kind, host.AbsoluteSize.X, host.AbsoluteSize.Y, plateSetId()))
end

-- A small painted icon (speaker, pause, bulb, bars, spade, crown: Engine/PaintedKitArt pk_w_icon_<name>) drawn as a CHILD of the plate at its
-- left side, so it survives a Clone and follows the plate. `pad` pushes the plate's own text right by that fraction of the width (a UIPadding),
-- so the word never sits on the icon. Returns the ImageLabel, or nil (no id: the word stays centred and nothing changes).
function TavernKit.icon(host, name, pad)
	if not host or not host.Parent then return nil end
	local ok, art = pcall(function() return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PaintedKitArt")) end)
	local id = ok and art and art["pk_w_icon_" .. name]
	if not id or id == "" then return nil end
	local img = host:FindFirstChild("KitIcon")
	if not img then
		img = Instance.new("ImageLabel")
		img.Name = "KitIcon"
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Active = false
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = host
	end
	-- hooks go on every host that has none yet, also a Cloned plate that arrives with a KitIcon child but none of the connections
	TavernKit._wired = TavernKit._wired or setmetatable({}, { __mode = "k" })
	if not TavernKit._wired[host] then
		TavernKit._wired[host] = true
		-- group hung from the plate's CENTRE (scale 0.5 plus a small offset, IconLabelLayout.anchored), so a stale measured width cannot push it out
		-- icon 14 px in from the left, word 6 px right of it, both centred vertically (Engine/IconLabelLayout, tested). A square sized in
		-- pixels (a zero-width UDim2 with an aspect constraint collapsed to nothing). The word is the button's KitLabel when it has one (a
		-- child, so a UIPadding on the button never moved it: that put the word under the icon), else the host's own text via KitIconPad.
		local Layout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("IconLabelLayout"))
		local function size()
			local sc = 1 -- a UIScale on the plate or above it scales offsets too: measure the plate in its own units
			local anc = host
			while anc and anc:IsA("GuiObject") do
				local us = anc:FindFirstChildOfClass("UIScale")
				if us and us.Scale > 0 then sc = sc * us.Scale end
				anc = anc.Parent
			end
			local pw, ph = math.floor(host.AbsoluteSize.X / sc + 0.5), math.floor(host.AbsoluteSize.Y / sc + 0.5)
			if pw < 2 or ph < 2 then return end -- not laid out yet: the AbsoluteSize signal calls again
			local kl = host:FindFirstChild("KitLabel")
			local a
			if kl and (kl:IsA("TextLabel") or kl:IsA("TextButton")) and kl.Text ~= "" then -- icon, gap and word are one group, 14 px clear each side, the word shrinks to fit
				local base = kl:GetAttribute("KitBaseSize") or kl.TextSize
				kl:SetAttribute("KitBaseSize", base)
				local ok, bounds = pcall(function() return game:GetService("TextService"):GetTextSize(kl.Text, base, kl.Font, Vector2.new(10000, 10000)) end)
				if ok and bounds then
					a = Layout.anchored(pw, ph, bounds.X, base, host.Name:find("^Sort") and 10 or 14, host.Name:find("^Sort") and 4 or nil) -- the Rank and Suit plates are narrow at 800x450: the word may go down to 10 px and the side air to 4 px
					kl.TextSize = a.size
				end
			end
			if not a then
				local p = Layout.place(pw, ph) -- no word to measure: icon at the left
				img.Position = UDim2.fromOffset(p.icon.x, p.icon.y)
				img.Size = UDim2.fromOffset(p.icon.w, p.icon.h)
				local up = host:FindFirstChild("KitIconPad")
				if up then up.PaddingLeft = UDim.new(0, p.label.x) end
				if up then img.Position = UDim2.fromOffset(p.icon.x - up.PaddingLeft.Offset, p.icon.y) end -- a UIPadding moves every child, the icon too
				return
			end
			img.AnchorPoint = Vector2.new(0, 0)
			img.Position = UDim2.new(0.5, a.icon.dx, 0, a.icon.y)
			img.Size = UDim2.fromOffset(a.icon.w, a.icon.h)
			local up = host:FindFirstChild("KitIconPad")
			if up then up.PaddingLeft = UDim.new(0, 0) end -- the KitLabel draws the word; a left padding here shifted the icon and word right by half of it (Nov 19, 39.5 px)
			kl.AnchorPoint = Vector2.new(0, 0)
			kl.Position = UDim2.new(0.5, a.label.dx, 0, 0)
			kl.Size = UDim2.new(0, a.label.w + 4, 1, 0)
			kl.TextXAlignment = Enum.TextXAlignment.Left
			if game:GetService("RunService"):IsStudio() and host.Name:find("^Sort") then print(string.format("[PlateGroup] %s plate abs %d,%d size %dx%d icon abs %d,%d word abs %d,%d", host.Name, host.AbsolutePosition.X, host.AbsolutePosition.Y, host.AbsoluteSize.X, host.AbsoluteSize.Y, img.AbsolutePosition.X, img.AbsolutePosition.Y, kl.AbsolutePosition.X, kl.AbsolutePosition.Y)) end
			if game:GetService("RunService"):IsStudio() and not Layout.inside(pw, ph, Layout.resolve(pw, a)) then warn("[TavernKit.icon] label outside its plate: " .. host:GetFullName()) end
		end
		size()
		local kl0 = host:FindFirstChild("KitLabel")
		if kl0 then
			for _, prop in ipairs({ "Text", "TextSize", "TextXAlignment" }) do -- ButtonLabelTop mirrors the button's own text over the group
				kl0:GetPropertyChangedSignal(prop):Connect(function() task.defer(size) end)
			end
		end
		host:GetPropertyChangedSignal("AbsoluteSize"):Connect(size)
		host.ChildAdded:Connect(function(c) if c.Name == "KitLabel" then task.defer(size) end end)
	end
	img.Image = id
	img.ImageTransparency = 0
	img.ZIndex = host.ZIndex + 2
	if pad and pad > 0 and (host:IsA("TextLabel") or host:IsA("TextButton")) and not host:FindFirstChild("KitIconPad") then
		local up = Instance.new("UIPadding"); up.Name = "KitIconPad"; up.Parent = host
		local Layout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("IconLabelLayout"))
		up.PaddingLeft = UDim.new(0, Layout.place(host.AbsoluteSize.X, host.AbsoluteSize.Y).label.x) -- 6 px clear of the icon at any plate width
		host.TextXAlignment = Enum.TextXAlignment.Left -- the word starts at the padding, so a centred word cannot slide under the icon (its KitLabel mirrors this)
		local kl = host:FindFirstChild("KitLabel")
		if kl then kl.TextXAlignment = Enum.TextXAlignment.Left end
	end
	return img
end

function TavernKit.title(parent, text)
	local t = Instance.new("TextLabel")
	t.Name = "TavernTitle"
	t.Size = UDim2.new(1, 0, 0, Style.TEXT.title + 10)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font[Style.FONTS.title]
	t.TextSize = Style.TEXT.title
	t.TextColor3 = col("cream")
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0
	t.TextStrokeColor3 = col("outline")
	t.Text = text or ""
	t.Parent = parent
	return t
end

return TavernKit
