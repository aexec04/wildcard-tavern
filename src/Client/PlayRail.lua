--[[
	Client/PlayRail.lua
	Painted wooden hand tray: a back strip BEHIND the cards (tray interior with groove) and a front strip ABOVE the lowest part of the
	cards (carved lip with brass studs), so the hand sits seated in the table. Both are optional art (play_rail_back_a, play_rail_front_b
	in Engine/PlaySceneArt); until both Image ids exist the flat wood strip (Client/PlayRailLip) stays and this module draws nothing.
	  rects(p)            pure: { back = rect, front = rect } from PlayTableLayout.placement, nil without a placement
	  ready(art)          true when both ids are present
	  install(root, art)  creates PlayRailBack (ZIndex 0, above the table picture, below every card) and PlayRailFront (above cards)
	  apply(pieces, p, shown)   place and show or hide both
]]

local PlayRailLip = nil
local ok, mod = pcall(function() return require(script.Parent.PlayRailLip) end)
if ok then PlayRailLip = mod else PlayRailLip = dofile("src/Client/PlayRailLip.lua") end

local PlayRail = {}

PlayRail.BACK_KEY = "play_rail_back_a"
PlayRail.FRONT_KEY = "play_rail_front_b"
-- opaque pixels of each 1536x1024 picture (alpha > 40), so the transparent padding is cropped away
PlayRail.CROP = {
	back = { x = 11, y = 514, w = 1522, h = 243 },
	front = { x = 17, y = 456, w = 1502, h = 218 },
}
PlayRail.BACK_Z = 0 -- same level as the table picture; created after it, so it draws on top; cards are >= 1
PlayRail.FRONT_Z = PlayRailLip.Z + 2 -- above the flat lip's own pieces
PlayRail.BACK_H = 0.11 -- tray height as a share of its width
PlayRail.SIDE = 0.03 -- both strips overhang the rail by this share of its width per side

local function r0(v) return math.floor(v + 0.5) end

function PlayRail.rects(p)
	local lip = PlayRailLip.lipRect(p)
	if not lip then return nil end
	local over = PlayRail.SIDE * lip.w
	local x, w = r0(lip.x - over), r0(lip.w + 2 * over)
	local bh = r0(w * PlayRail.BACK_H)
	local bottom = lip.y + lip.h
	return {
		back = { x = x, y = bottom - bh, w = w, h = bh },
		front = { x = x, y = lip.y, w = w, h = lip.h },
	}
end

function PlayRail.ready(art)
	return type(art) == "table" and (art[PlayRail.BACK_KEY] or "") ~= "" and (art[PlayRail.FRONT_KEY] or "") ~= ""
end

local function piece(root, name, id, crop, z)
	local img = root:FindFirstChild(name)
	if img then return img end
	img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Active = false
	img.Image = id
	img.ImageRectOffset = Vector2.new(crop.x, crop.y)
	img.ImageRectSize = Vector2.new(crop.w, crop.h)
	img.ScaleType = Enum.ScaleType.Stretch
	img.ZIndex = z
	img.Visible = false
	img.Parent = root
	return img
end

-- returns nil when the art is missing, so the caller keeps the flat lip
function PlayRail.install(root, art)
	if not PlayRail.ready(art) then return nil end
	return {
		back = piece(root, "PlayRailBack", art[PlayRail.BACK_KEY], PlayRail.CROP.back, PlayRail.BACK_Z),
		front = piece(root, "PlayRailFront", art[PlayRail.FRONT_KEY], PlayRail.CROP.front, PlayRail.FRONT_Z),
	}
end

function PlayRail.apply(pieces, p, shown)
	if not pieces then return end
	local r = PlayRail.rects(p)
	if not r then
		pieces.back.Visible = false
		pieces.front.Visible = false
		return
	end
	for _, k in ipairs({ "back", "front" }) do
		local g, o = r[k], pieces[k]
		o.Position = UDim2.fromOffset(g.x, g.y)
		o.Size = UDim2.fromOffset(g.w, g.h)
		o.Visible = shown ~= false
	end
end

return PlayRail
