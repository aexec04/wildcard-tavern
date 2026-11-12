--[[
	Client/PlayFeltShade.lua
	Shading over the felt only (never the rail, deck or plates): four dark corner glows (far corners about 10 percent darker)
	and a tiled seamless grain image at 8 to 12 percent once `play_felt_grain` has an Image id in PlaySceneArt. Everything sits in
	one clipped frame that PlayScenePaint sizes to the measured felt rect, above the painted table and below the cards.
	Numbers: Engine/PlayMotion FELT and cornerGlows (tested). No motion, so calm mode keeps it as is.

	install(root, art) -> { frame, apply(rect or nil) }   rect = { x, y, w, h } in root pixels
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PM = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PlayMotion"))
local SoftGlow = require(script.Parent.SoftGlow)

local M = {}

function M.install(root, art)
	local frame = Instance.new("Frame")
	frame.Name = "PlayFeltShade"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.ClipsDescendants = true
	frame.ZIndex = 0
	frame.Visible = false
	frame.Parent = root

	local grainId = type(art) == "table" and art.play_felt_grain or nil
	if grainId and grainId ~= "" then
		local grain = Instance.new("ImageLabel")
		grain.Name = "Grain"
		grain.BackgroundTransparency = 1
		grain.BorderSizePixel = 0
		grain.Active = false
		grain.Size = UDim2.fromScale(1, 1)
		grain.Image = grainId
		grain.ScaleType = Enum.ScaleType.Tile
		grain.TileSize = UDim2.fromOffset(PM.FELT.grainTile, PM.FELT.grainTile)
		grain.ImageTransparency = 1 - PM.FELT.grainOpacity
		grain.ZIndex = 0
		grain.Parent = frame
	end

	local corners = {}
	for i = 1, 4 do
		corners[i] = SoftGlow.build(frame, {
			name = "Corner" .. i, color = Color3.fromRGB(8, 14, 8), position = UDim2.fromOffset(0, 0),
			size = UDim2.fromOffset(10, 10), peak = PM.FELT.cornerPeak, zIndex = 0,
		})
	end

	local api = { frame = frame }
	function api.apply(rect)
		if not rect then frame.Visible = false return end
		frame.Position = UDim2.fromOffset(rect.x, rect.y)
		frame.Size = UDim2.fromOffset(rect.w, rect.h)
		frame.Visible = true
		for i, g in ipairs(PM.cornerGlows(0, 0, rect.w, rect.h)) do
			corners[i].root.Position = UDim2.fromOffset(g[1], g[2])
			corners[i].root.Size = UDim2.fromOffset(g[3], g[3])
		end
	end
	return api
end

return M
