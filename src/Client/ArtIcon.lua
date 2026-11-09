--[[
	Client/ArtIcon.lua
	One call for "painted icon with an emoji fallback": looks the key up in ContentArt and, when an id exists,
	puts the art over `frame` through PatronPlaque.applyById (which hides the emoji only once the image loads).
	No id, a failed lookup or a failed load leaves the emoji label untouched. Never throws.

	  ArtIcon.apply(frame, "quests", row.id, emojiLabel, { cornerRadius = 30 })  -> the ImageLabel or nil
]]

local ArtIcon = {}

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")

-- True when a painted id exists for (category, key); lets a layout drop its emoji prefix and reserve room for art.
function ArtIcon.has(category, key)
	local ok, id = pcall(function()
		return require(Engine:WaitForChild("ContentArt")).getImageId(category, key)
	end)
	return ok and id ~= nil
end

function ArtIcon.apply(frame, category, key, emojiLabel, opts)
	local art
	pcall(function()
		local ContentArt = require(Engine:WaitForChild("ContentArt"))
		local artId = ContentArt.getImageId(category, key)
		if not artId then return end
		opts = opts or {}
		art = require(script.Parent.PatronPlaque).applyById(frame, artId, {
			emojiLabel = emojiLabel,
			zIndex = opts.zIndex or (frame.ZIndex + 1),
			cornerRadius = opts.cornerRadius,
			size = opts.size,
			position = opts.position,
			anchor = opts.anchor,
			dim = opts.dim,
		})
	end)
	return art
end

return ArtIcon
