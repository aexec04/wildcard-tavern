-- Turns an art map value (bare number or "rbxassetid://123", even repeated prefixes) into one clean content string.
local AssetId = {}

local PREFIX = "rbxassetid://"

function AssetId.normalize(value)
	if value == nil then return nil end
	local s = tostring(value)
	while s:sub(1, #PREFIX) == PREFIX do
		s = s:sub(#PREFIX + 1)
	end
	if s == "" then return nil end
	return PREFIX .. s
end

return AssetId
