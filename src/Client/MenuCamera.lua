--[[
	Client/MenuCamera.lua
	Points the camera at the tavern scene (table, chandelier, and the 4
	seated Patron NPCs -- Viking/Wizard/Rogue/Goblin -- built server-side in
	Server/TavernScene.server.lua as part of the Visual Life Pass) while the
	main menu is showing, instead of leaving the camera wherever the
	player's character happened to spawn behind a flat opaque menu panel.

	Deliberately isolated to this one file rather than touching
	TavernScene.server.lua: that file has a standing rule (see its own
	header) that it never touches the camera/character, since it's a
	server script and camera control is inherently a client-side concept
	in Roblox anyway. This keeps that rule intact -- all camera control
	here is client-only, only active while the menu is actually visible,
	and handed back to the player's normal follow-camera the instant it's
	not (see init.client.lua's `menuFrame:GetPropertyChangedSignal
	("Visible")` wiring, which calls showMenuView()/restorePlayerView()
	off that single signal so it stays correct no matter how many
	different places in the codebase toggle menuFrame.Visible).

	deps fields:
		tableCenter -- Vector3, world position of the tavern table's
		               center. MUST match Server/TavernScene.server.lua's
		               own TABLE_CENTER constant, or this shot frames on
		               empty air instead of the actual table -- if that
		               file ever repositions the room, update this too.

	Returns:
		{
			showMenuView = function(),      -- switches to the scripted showcase shot
			restorePlayerView = function(), -- hands the camera back to normal play
		}
]]

return function(deps)
	local tableCenter = deps.tableCenter

	local RunService = game:GetService("RunService")

	-- A slow, lazy drift around the table rather than a fast spin -- this
	-- is meant to read as "atmospheric showcase," not a spinning
	-- turntable. One full orbit takes roughly 100 seconds.
	local ORBIT_RADIUS = 14
	local ORBIT_HEIGHT = 9
	local ORBIT_SPEED = 0.063 -- radians/sec
	-- Aimed slightly above the table surface so the frame catches both
	-- the cards/chips on the table AND the lit chandelier hanging above
	-- it, not just a flat top-down view of the tabletop.
	local LOOK_TARGET_OFFSET = Vector3.new(0, 4.5, 0)

	local connection = nil
	local elapsed = 0

	local function showMenuView()
		if connection then
			return
		end

		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		camera.CameraType = Enum.CameraType.Scriptable
		elapsed = 0
		connection = RunService.RenderStepped:Connect(function(deltaTime)
			elapsed = elapsed + deltaTime
			local angle = elapsed * ORBIT_SPEED
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * ORBIT_RADIUS
			local position = tableCenter + offset + Vector3.new(0, ORBIT_HEIGHT, 0)
			camera.CFrame = CFrame.new(position, tableCenter + LOOK_TARGET_OFFSET)
		end)
	end

	local function restorePlayerView()
		if connection then
			connection:Disconnect()
			connection = nil
		end

		local camera = workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end

	return {
		showMenuView = showMenuView,
		restorePlayerView = restorePlayerView,
	}
end
