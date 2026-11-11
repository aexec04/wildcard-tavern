--[[
	Engine/ImagePreload.lua
	Decides whether an image loaded from the ContentProvider:PreloadAsync callback status, not from ImageLabel.IsLoaded
	(which reads false in Studio for a label that is Visible = false).

	ImagePreload.run(provider, image, successValue) -> true only when the callback reported successValue for the label
	and nothing else. provider:PreloadAsync({ image }, callback) calls callback(contentId, status).
]]

local ImagePreload = {}

function ImagePreload.run(provider, image, successValue)
	local sawSuccess, sawOther = false, false
	local ok = pcall(function()
		provider:PreloadAsync({ image }, function(_, status)
			if status == successValue then sawSuccess = true else sawOther = true end
		end)
	end)
	return ok and sawSuccess and not sawOther
end

return ImagePreload
