--[[
	PhoneLayout: pure rules for the touch/phone UI pass (no Roblox APIs, tested).
	Client/PhoneUI.lua applies them to live instances.

	- Touch devices get a minimum tap target (44px) and minimum text (14px).
	- "Compact" means a short viewport (phone landscape, e.g. 800x400).
]]

local PhoneLayout = {}

PhoneLayout.MinTap = 44
PhoneLayout.MinText = 14
PhoneLayout.CompactHeight = 500

function PhoneLayout.isCompact(viewportHeight)
	return (viewportHeight or 720) < PhoneLayout.CompactHeight
end

-- Text size to use for `size` on this device.
function PhoneLayout.textSize(size, touch)
	if touch and size < PhoneLayout.MinText then
		return PhoneLayout.MinText
	end
	return size
end

-- New (width, height) for a button of pixel size w x h.
function PhoneLayout.tapSize(w, h, touch)
	if not touch then
		return w, h
	end
	return math.max(w, PhoneLayout.MinTap), math.max(h, PhoneLayout.MinTap)
end

-- Offset to add to Position so a button grown from (w,h) to (nw,nh) grows
-- around its center whatever its AnchorPoint is.
function PhoneLayout.growShift(w, h, nw, nh, anchorX, anchorY)
	return ((anchorX or 0) - 0.5) * (nw - w), ((anchorY or 0) - 0.5) * (nh - h)
end

return PhoneLayout
