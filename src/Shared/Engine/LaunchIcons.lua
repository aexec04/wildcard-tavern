--[[
	Shared/Engine/LaunchIcons.lua
	Hand edited. Image ids of the pass and product icons from claude/launch-art, keyed by Store item id.
	Paste an `rbxassetid://<number>` (the Image id, not the Decal id) after you upload an icon.
	Nothing recorded means the Store tile keeps the generated bundle art, and then the emoji.
]]

local LaunchIcons = {}

-- Store item id -> "rbxassetid://..." (empty until the icons are uploaded)
LaunchIcons.Ids = {
	-- vip = "rbxassetid://0",
}

local function wellFormed(id)
	return type(id) == "string" and id:match("^rbxassetid://%d+$") ~= nil and id ~= "rbxassetid://0"
end
LaunchIcons.wellFormed = wellFormed

-- The image for a Store tile: the launch icon if one is recorded, else the bundle art, else nil (emoji).
function LaunchIcons.imageFor(itemId, bundleArt)
	local id = LaunchIcons.Ids[itemId]
	if wellFormed(id) then return id end
	local art = bundleArt and bundleArt[itemId]
	if wellFormed(art) then return art end
	return nil
end

return LaunchIcons
