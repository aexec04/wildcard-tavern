--[[
	Client/Table3D/Rig.lua
	The fixed camera of the 3D play table, and the one place that turns a spot on the 2D screen into a point on the
	felt. The numbers and the maths are Engine/TableScene (pure, tested); this module only feeds it the live viewport.

	The camera is Scriptable and is put back every frame, so a respawn or the default camera scripts cannot take it.
	A 2D screen shake (VisualHelpers.screenShake moves the game root by a few pixels) also shakes this camera, and the
	root's own offset is taken out of every lookup: cards stay where they lie on the table while the view shakes.

	start()                              bind the camera
	pointUnder(guiX, guiY, height) -> Vector3 | nil, tablePoint   GUI space pixel (AbsolutePosition space) -> world
	world(tablePoint) -> Vector3;  feltY() -> number
	studsPerPixel(tablePoint) -> number
	shake(intensity, duration);  kick(amount)   a wobble, and a dip that springs back
	watchRoot(root)                      whose shake offset to take out
]]

local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local TS = require(Engine:WaitForChild("TableScene"))

local Rig = {}

local origin = Vector3.new(TS.ORIGIN[1], TS.ORIGIN[2], TS.ORIGIN[3])
local C = TS.CAMERA
local base = CFrame.new(origin + Vector3.new(C.x, C.height, C.z)) * CFrame.Angles(-math.rad(C.pitch), 0, 0)
local shakes = {}
local dip = { x = 0, v = 0 }
local root, rootRest = nil, nil
local bound = false

function Rig.world(p)
	return origin + Vector3.new(p[1], p[2], p[3])
end

function Rig.feltY()
	return origin.Y
end

function Rig.base()
	return base
end

function Rig.watchRoot(guiRoot)
	root = guiRoot
	rootRest = guiRoot and guiRoot.Position or nil
end

-- how far the 2D shake has pushed the game root right now, in pixels
local function rootOffset()
	if not root or not rootRest then return 0, 0 end
	local p = root.Position
	return p.X.Offset - rootRest.X.Offset, p.Y.Offset - rootRest.Y.Offset
end

function Rig.pointUnder(guiX, guiY, height)
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local size = cam.ViewportSize
	if size.X < 2 or size.Y < 2 then return nil end
	local inset = GuiService:GetGuiInset()
	local ox, oy = rootOffset()
	local nx = (guiX - ox + inset.X) / size.X * 2 - 1
	local ny = (guiY - oy + inset.Y) / size.Y * 2 - 1
	local p = TS.groundPoint(nx, ny, size.X / size.Y, height or 0)
	if not p then return nil end
	return Rig.world(p), p
end

-- the same for any plane in table space (p0, n as Engine/TableScene.planePoint takes them)
function Rig.pointOnPlane(guiX, guiY, p0, n)
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local size = cam.ViewportSize
	if size.X < 2 or size.Y < 2 then return nil end
	local inset = GuiService:GetGuiInset()
	local ox, oy = rootOffset()
	local nx = (guiX - ox + inset.X) / size.X * 2 - 1
	local ny = (guiY - oy + inset.Y) / size.Y * 2 - 1
	local p = TS.planePoint(nx, ny, size.X / size.Y, p0, n)
	if not p then return nil end
	return Rig.world(p), p
end

function Rig.studsPerPixel(tablePoint)
	local cam = workspace.CurrentCamera
	return TS.studsPerPixel(TS.depthOf(tablePoint), cam and cam.ViewportSize.Y or 751)
end

function Rig.shake(intensity, duration)
	if #shakes > 6 then table.remove(shakes, 1) end
	shakes[#shakes + 1] = { t0 = os.clock(), intensity = intensity or 2, duration = duration or 0.2 }
end

function Rig.kick(amount)
	dip.v = dip.v - (amount or 0.1) * 10
end

function Rig.start()
	if bound then return end
	bound = true
	RunService:BindToRenderStep("Table3DCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local cam = workspace.CurrentCamera
		if not cam then return end
		if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
		if cam.FieldOfView ~= C.fov then cam.FieldOfView = C.fov end
		local now = os.clock()
		local dx, dy = 0, 0
		for i = #shakes, 1, -1 do
			local s = shakes[i]
			local t = now - s.t0
			if t >= s.duration then
				table.remove(shakes, i)
			else
				local x, y = TS.shakeAt(t, s.intensity, s.duration)
				dx, dy = dx + x, dy + y
			end
		end
		dip.x, dip.v = TS.spring(dip.x, dip.v, 0, dt)
		cam.CFrame = base * CFrame.new(dx, dy + dip.x, 0)
	end)
end

return Rig
