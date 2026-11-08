--[[
	Client/PanelArt.lua
	Painted background for a panel, with the flat look as the fallback: when the
	ContentArt id is missing (rbxassetid://0 or not recorded yet) nothing is added.

	PanelArt.add(panel, {
		key = "collection_bg",          -- ContentArt "backgrounds" key
		fallbackId = "rbxassetid://...", -- optional older art to use when the key has none
		zIndex = panel.ZIndex,           -- default: the panel's own (children draw after the panel)
		scrim = { position = UDim2, size = UDim2 }, -- optional dark scrim behind the content
		scrimTransparency = 0.35,
	}) -> ImageLabel | nil

	Call it right after polishPanel so the panel's UICorner exists; the art copies it
	(Crop, Active = false, lowest ZIndex of the panel's content, created first).
	PanelArt.vignette(parent, zIndex) adds stepped dark edges (Color stops only).
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
	local id = ContentArt.getImageId("backgrounds", opts.key) or opts.fallbackId
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
	if opts.scrim and ContentArt.getImageId("backgrounds", opts.key) then
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

-- Dark edges on all four sides, stepped transparency (never a gradient).
local STEPS = { 0.45, 0.62, 0.76, 0.87, 0.94, 0.98 }
function PanelArt.vignette(parent, zIndex)
	local holder = Instance.new("Frame")
	holder.Name = "EdgeVignette"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Active = false
	holder.ZIndex = zIndex
	holder.Parent = parent
	local step = 0.025
	for i, tr in ipairs(STEPS) do
		local o = (i - 1) * step
		for side = 1, 4 do
			local f = Instance.new("Frame")
			f.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			f.BackgroundTransparency = tr
			f.BorderSizePixel = 0
			f.Active = false
			f.ZIndex = zIndex
			if side == 1 then
				f.Size, f.Position = UDim2.fromScale(step, 1), UDim2.fromScale(o, 0)
			elseif side == 2 then
				f.Size, f.Position = UDim2.fromScale(step, 1), UDim2.fromScale(1 - o - step, 0)
			elseif side == 3 then
				f.Size, f.Position = UDim2.fromScale(1, step), UDim2.fromScale(0, o)
			else
				f.Size, f.Position = UDim2.fromScale(1, step), UDim2.fromScale(0, 1 - o - step)
			end
			f.Parent = holder
		end
	end
	return holder
end

return PanelArt
