--[[
	Client/PanelArt.lua
	Painted background for a panel, with the flat look as the fallback: when the
	ContentArt id is missing (rbxassetid://0 or not recorded yet) nothing is added.

	PanelArt.add(panel, {
		key = "collection_bg",          -- ContentArt key (in `category`)
		category = "backgrounds",        -- optional ContentArt category, default "backgrounds"
		fallbackId = "rbxassetid://...", -- optional older art to use when the key has none
		zIndex = panel.ZIndex,           -- default: the panel's own (children draw after the panel)
		scrim = { position = UDim2, size = UDim2 }, -- optional dark scrim behind the content
		scrimTransparency = 0.35,
	}) -> ImageLabel | nil

	Call it right after polishPanel so the panel's UICorner exists; the art copies it
	(Crop, Active = false, lowest ZIndex of the panel's content, created first).
	PanelArt.vignette(parent, zIndex) adds smooth dark edges (one gradient frame per edge).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentArt = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))

local PanelArt = {}

local function matchCorner(inst, panel)
	local src = panel:FindFirstChildOfClass("UICorner")
	local corner = Instance.new("UICorner")
	corner.CornerRadius = src and src.CornerRadius or UDim.new(0, 6)
	corner.Parent = inst
end

function PanelArt.add(panel, opts)
	local category = opts.category or "backgrounds"
	local id = ContentArt.getImageId(category, opts.key) or opts.fallbackId
	if type(id) ~= "string" or id == "" or id == "rbxassetid://0" then
		return nil
	end
	local z = opts.zIndex or panel.ZIndex
	local art = Instance.new("ImageLabel")
	art.Name = "PanelArt_" .. opts.key
	art.Size = UDim2.fromScale(1, 1)
	art.BackgroundTransparency = 1
	art.BorderSizePixel = 0
	art.ScaleType = Enum.ScaleType.Crop
	art.Image = id
	art.Active = false
	art.ZIndex = z
	art.Parent = panel
	matchCorner(art, panel)
	if opts.scrim and ContentArt.getImageId(category, opts.key) then
		local scrim = Instance.new("Frame")
		scrim.Name = "PanelScrim"
		scrim.Position = opts.scrim.position
		scrim.Size = opts.scrim.size
		scrim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		scrim.BackgroundTransparency = opts.scrimTransparency or 0.35
		scrim.BorderSizePixel = 0
		scrim.Active = false
		scrim.ZIndex = z
		scrim.Parent = panel
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = scrim
	end
	return art
end

-- Dark edges on all four sides: one smooth gradient frame per edge (Client/SmoothVignette), no stacked steps.
function PanelArt.vignette(parent, zIndex)
	local edge = { strength = 0.6, extent = 0.13 }
	return require(script.Parent.SmoothVignette).build(parent, {
		name = "EdgeVignette", zIndex = zIndex, color = Color3.new(0, 0, 0),
		top = edge, bottom = edge, left = edge, right = edge,
	}).holder
end

return PanelArt
