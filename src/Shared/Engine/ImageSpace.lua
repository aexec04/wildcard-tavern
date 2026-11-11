--[[
	Engine/ImageSpace.lua
	Roblox stores an uploaded image at most 1024 px on its long side, and ImageRectOffset / ImageRectSize are read in the STORED
	texture. A rect measured on a 1536x1024 source must be multiplied by 2/3, or only a strip of the sheet draws.

	ImageSpace.rectScale(srcW, srcH)          min(1, 1024 / max(srcW, srcH))
	ImageSpace.rect(x, y, w, h, srcW, srcH)   the four numbers scaled into stored pixels
]]

local ImageSpace = {}

ImageSpace.MAX = 1024

function ImageSpace.rectScale(srcW, srcH)
	local long = math.max(srcW or 0, srcH or 0)
	if long <= ImageSpace.MAX then return 1 end
	return ImageSpace.MAX / long
end

function ImageSpace.rect(x, y, w, h, srcW, srcH)
	local s = ImageSpace.rectScale(srcW, srcH)
	return x * s, y * s, w * s, h * s
end

return ImageSpace
