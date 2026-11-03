--[[
	Client/SkinArt.lua
	REFERENCE-MATCH PASS, art round (Nov 1 2026): lays an uploaded UI art
	image (wood plaque, deck holder, hand tray, button) over an existing
	code-drawn element.

	The code-drawn look stays in place until the image has ACTUALLY
	loaded (ImageLabel.IsLoaded). Only then does
	the art fade in and `onLoaded` hide the old code chrome. So a
	placeholder id ("rbxassetid://0"), a typo, or an image stuck in
	moderation all leave the element looking exactly as it did before --
	never blank.

	SkinArt.apply(target, imageId, opts) -> ImageLabel | nil
		opts.parent       -- where the art goes (default: target)
		opts.zIndex       -- default target.ZIndex
		opts.sliceCenter  -- Rect in IMAGE pixels: 9-slice (corners stay
		                     crisp, middle stretches)
		opts.sliceScale   -- shrinks/grows the 9-slice border (default 1)
		opts.scaleType    -- used when there's no sliceCenter (default Stretch)
		opts.size / opts.position / opts.anchor
		opts.onLoaded(art) -- hide the code-drawn chrome here

	IMPORTANT for callers: create the art BEFORE the element's text/labels.
	This game's ScreenGui uses Global ZIndex layering; at equal ZIndex,
	whatever comes first in the tree draws first (underneath).
]]

local SkinArt = {}

function SkinArt.apply(target, imageId, opts)
	opts = opts or {}
	if type(imageId) ~= "string" or imageId == "" or imageId == "rbxassetid://0" then
		return nil
	end

	local art = Instance.new("ImageLabel")
	art.Name = "SkinArt"
	art.BackgroundTransparency = 1
	art.BorderSizePixel = 0
	art.Active = false
	art.Image = imageId
	art.ImageColor3 = opts.tint or Color3.fromRGB(255, 255, 255)
	art.Size = opts.size or UDim2.fromScale(1, 1)
	art.Position = opts.position or UDim2.new(0, 0, 0, 0)
	art.AnchorPoint = opts.anchor or Vector2.new(0, 0)
	if opts.sliceCenter then
		art.ScaleType = Enum.ScaleType.Slice
		art.SliceCenter = opts.sliceCenter
		art.SliceScale = opts.sliceScale or 1
	else
		art.ScaleType = opts.scaleType or Enum.ScaleType.Stretch
	end
	art.ZIndex = opts.zIndex or target.ZIndex
	art.Parent = opts.parent or target

	-- BUGFIX (Nov 1 2026): this used to gate on ContentProvider:PreloadAsync
	-- reporting Success. Tested live in Studio: PreloadAsync reports
	-- Failure even for images that load and render fine (including the
	-- working tavern background), so it was hiding good art. Now the art
	-- is shown right away, and the code chrome underneath is only hidden
	-- once ImageLabel.IsLoaded confirms the pixels actually arrived. An
	-- image that never loads just draws nothing, so the code look shows
	-- through unchanged.
	art.ImageTransparency = 0
	-- No time limit: Roblox only downloads images for UI that's actually
	-- on screen, and the game screen stays hidden while the player sits on
	-- the main menu -- a timeout here was expiring before the art was ever
	-- visible. The art simply waits; until it loads it draws nothing, so
	-- the code-drawn look shows through.
	local function finish()
		if art.Parent and art.IsLoaded and opts.onLoaded then
			opts.onLoaded(art)
		end
	end
	-- Polled, not GetPropertyChangedSignal("IsLoaded"): that signal didn't
	-- fire in testing (the deck holder art loaded but onLoaded never ran,
	-- so the old outline stayed on top of it). A 0.25s check is cheap.
	-- task.defer, not spawn: an already-cached image would otherwise call
	-- onLoaded before the caller has finished building what it touches.
	task.defer(function()
		while art.Parent and not art.IsLoaded do
			task.wait(0.25)
		end
		finish()
	end)

	return art
end

-- Hides the code-drawn chrome the reference-match pass added (strokes,
-- gradients, inner rims, corner brackets/gems) and makes the element's own
-- fill see-through, so only the art shows. Never touches text or content.
local CHROME_NAMES = {
	InnerRim = true, CornerGem = true, BracketH = true, BracketV = true, CornerStud = true,
}
function SkinArt.hideCodeChrome(frame)
	frame.BackgroundTransparency = 1
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("UIStroke") or child:IsA("UIGradient") then
			child.Enabled = false
		elseif CHROME_NAMES[child.Name] and child:IsA("GuiObject") then
			child.Visible = false
		end
	end
end

-- 9-slice settings, measured from the cleaned images in art-wip/ (all
-- pixel values are in the uploaded image's own pixels).
SkinArt.Slices = {
	plaque = { center = Rect.new(125, 125, 899, 875), scale = 0.17 },   -- ui-plaque.png 1024x1000
	handTray = { center = Rect.new(95, 95, 929, 257), scale = 0.3 },     -- ui-hand-tray.png 1024x352
	button = { center = Rect.new(130, 60, 894, 291), scale = 0.28 },     -- ui-button.png 1024x351
	sidebarColumn = { center = Rect.new(20, 70, 372, 954), scale = 0.575 }, -- ui-sidebar-column.png 417x1024
}

-- Color tints (ImageColor3 multiplies the art) that pull each piece back
-- to the reference mockup's dark, low-saturation wood. Measured, not
-- eyeballed: each is reference color / art color, per channel, sampled
-- from the same spot in both (Nov 2 2026). The column was the big one --
-- the art came out about 2x brighter and much more orange than the
-- reference's near-black wood. Raise a value toward 255 to brighten.
SkinArt.Tints = {
	sidebarColumn = Color3.fromRGB(107, 122, 190),
	plaque = Color3.fromRGB(232, 228, 215),
	button = Color3.fromRGB(225, 222, 212),
	buttonDimmed = Color3.fromRGB(150, 138, 125), -- inactive Rank/Suit sort button
	handTray = Color3.fromRGB(215, 210, 200),
	deckHolder = Color3.fromRGB(205, 195, 185),
	deckBoard = Color3.fromRGB(176, 189, 191), -- column planks, tinted to the reference board
}

-- ui-deck-holder.png (651x1024): the see-through window where the card
-- sits, as a fraction of the image.
SkinArt.DeckHolderWindow = { left = 62 / 651, top = 129 / 1024, right = 588 / 651, bottom = 959 / 1024 }

return SkinArt
