--[[
	Client/CharacterStage2D.lua
	The default "stage" (CharacterStage.USE_3D_RIGS = false): the boss is the painted portrait card that
	BossFight.lua draws, and the player is their own avatar as a flat image (GetUserThumbnailAsync) standing
	on the left above the hand row. Same public API as the old 3D stage, so BossFight / RoundSelect / the hub
	keep working unchanged:

	  prewarm()                    menu time: fetch the avatar thumbnail (pcall, one retry)
	  update(state)                called from render(); shows / hides / lays out the avatar
	  playPlayerState(name)        "cheer" (hop) | "flinch" (shake) | "slump" (sink a little)
	  playBossState(...)           no-op (BossFight animates the portrait itself)
	  isReady(expectBoss)          true once the thumbnail attempt has finished (success or fallback)
	  isActive()                   false: the framed portrait is always the boss
	  reset(), failed()

	The image sways with one RenderStepped sine (Engine/StageMotion), connected only while it is visible.
	If the thumbnail cannot load (Studio often cannot) a blocky silhouette is shown and one [Stage] line is printed.
	It never blocks a round: readiness gives up after a few seconds.
	deps: root (ScreenGui frame), SIDEBAR_WIDTH.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local StageLayout = require(Engine:WaitForChild("StageLayout"))
local StageMotion = require(Engine:WaitForChild("StageMotion"))
local ClientSettings = require(script.Parent.ClientSettings)

local ROUNDS_PER_NIGHT = 3
local FADE_IN = 0.3
local GIVE_UP_AFTER = 4 -- seconds before a slow thumbnail counts as "done" for readiness

local function reduced()
	return ClientSettings.get("reduceShake") == true
end

local function fast()
	return ClientSettings.get("animSpeed") == "fast"
end

local function build(deps)
	local root = deps.root
	local sidebarWidth = deps.SIDEBAR_WIDTH or 240

	local M = {}
	local ok = true
	local holder, shadow, image, silhouette
	local conn = nil
	local mode = "none" -- "none" | "normal" | "boss"
	local started = os.clock()
	local thumbDone = false -- the thumbnail attempt finished (loaded or fell back)
	local thumbRequested = false
	local thumbContent = nil
	local shown = false
	local fadeToken = 0
	local eventKind, eventStart, eventStrength = nil, 0, 1
	local lastKey = nil
	local baseX, baseY = 0, 0 -- feet position in pixels (holder anchor is bottom centre)

	local function blockPart(parent, name, pos, size, color)
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0)
		f.Position = pos
		f.Size = size
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Active = false
		f.Parent = parent
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = f
		return f
	end

	local okBuild = pcall(function()
		holder = Instance.new("Frame")
		holder.Name = "PlayerStage"
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Active = false
		holder.ZIndex = 0
		holder.Visible = false
		holder.Parent = root

		shadow = Instance.new("Frame")
		shadow.Name = "AvatarShadow"
		shadow.AnchorPoint = Vector2.new(0.5, 0.5)
		shadow.BackgroundColor3 = Color3.new(0, 0, 0)
		shadow.BackgroundTransparency = 0.6
		shadow.BorderSizePixel = 0
		shadow.Active = false
		shadow.ZIndex = 0
		shadow.Visible = false
		shadow.Parent = root
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(0.5, 0)
		sc.Parent = shadow

		image = Instance.new("ImageLabel")
		image.Name = "AvatarImage"
		image.AnchorPoint = Vector2.new(0.5, 1)
		image.Position = UDim2.fromScale(0.5, 1)
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
		image.ImageTransparency = 1
		image.Active = false
		image.ZIndex = 0
		image.Visible = false
		image.Parent = holder

		-- blocky silhouette fallback (head, torso, arms, legs) in a warm dark tone
		silhouette = Instance.new("Frame")
		silhouette.Name = "AvatarSilhouette"
		silhouette.AnchorPoint = Vector2.new(0.5, 1)
		silhouette.Position = UDim2.fromScale(0.5, 1)
		silhouette.Size = UDim2.fromScale(0.5, 1)
		silhouette.BackgroundTransparency = 1
		silhouette.Active = false
		silhouette.ZIndex = 0
		silhouette.Visible = false
		silhouette.Parent = holder
		local tone = Color3.fromRGB(60, 44, 34)
		blockPart(silhouette, "Head", UDim2.fromScale(0.5, 0.02), UDim2.fromScale(0.34, 0.2), tone)
		blockPart(silhouette, "Torso", UDim2.fromScale(0.5, 0.24), UDim2.fromScale(0.5, 0.36), tone)
		blockPart(silhouette, "ArmL", UDim2.fromScale(0.14, 0.24), UDim2.fromScale(0.2, 0.34), tone)
		blockPart(silhouette, "ArmR", UDim2.fromScale(0.86, 0.24), UDim2.fromScale(0.2, 0.34), tone)
		blockPart(silhouette, "LegL", UDim2.fromScale(0.37, 0.62), UDim2.fromScale(0.23, 0.38), tone)
		blockPart(silhouette, "LegR", UDim2.fromScale(0.63, 0.62), UDim2.fromScale(0.23, 0.38), tone)
	end)
	if not okBuild or not holder then
		ok = false
	end

	local function showSilhouette()
		if silhouette then
			silhouette.Visible = true
		end
		if image then
			image.Visible = false
		end
	end

	-- Fetch the thumbnail once (retry once). Never yields the caller.
	local function requestThumbnail()
		if thumbRequested or not ok then return end
		thumbRequested = true
		task.spawn(function()
			local player = Players.LocalPlayer
			local content, ready
			for attempt = 1, 2 do
				local got, a, b = pcall(function()
					return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.AvatarThumbnail, Enum.ThumbnailSize.Size420x420)
				end)
				if got and type(a) == "string" and a ~= "" and b ~= false then
					content, ready = a, true
					break
				end
				task.wait(0.5)
			end
			if content and ready then
				thumbContent = content
				image.Image = content
				image.Visible = true
				if silhouette then silhouette.Visible = false end
				-- fade in once the image has really loaded (PreloadAsync status, never an IsLoaded gate)
				pcall(function()
					game:GetService("ContentProvider"):PreloadAsync({ image })
				end)
				fadeToken = fadeToken + 1
				if reduced() or fast() then
					image.ImageTransparency = 0
				else
					TweenService:Create(image, TweenInfo.new(FADE_IN), { ImageTransparency = 0 }):Play()
				end
			else
				print("[Stage] avatar thumbnail unavailable (Studio or offline); using the blocky silhouette")
				showSilhouette()
			end
			thumbDone = true
		end)
	end

	local function layout()
		local cam = workspace.CurrentCamera
		local size = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local floorFrac = StageLayout.floorFraction(size.Y)
		local playerPx = StageLayout.heights(size.Y, floorFrac, mode == "boss" and "boss" or "normal", false)
		playerPx = math.floor(playerPx)
		local tableLeft = sidebarWidth
		local tableWidth = math.max(1, size.X - sidebarWidth)
		baseX = tableLeft + tableWidth * 0.14
		baseY = floorFrac * size.Y
		holder.Size = UDim2.fromOffset(playerPx, playerPx)
		shadow.Size = UDim2.fromOffset(playerPx * 0.55, math.max(8, playerPx * 0.07))
		shadow.Position = UDim2.fromOffset(baseX, baseY - 2)
		holder.Position = UDim2.fromOffset(baseX, baseY)
	end

	local function stopLoop()
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end

	local function startLoop()
		if conn or not ok then return end
		conn = RunService.RenderStepped:Connect(function()
			if not holder.Visible then return end
			local t = os.clock()
			local dx, dy, rot = StageMotion.sway(t, 1.3, 2, reduced())
			local ex, erot, lift = 0, 0, 0
			local sink = 0
			if eventKind then
				local e = t - eventStart
				if eventKind == "cheer" then
					lift = StageMotion.hop(e, 14 * eventStrength)
				elseif eventKind == "flinch" then
					ex, erot = StageMotion.hitShake(e, eventStrength, 0.3)
				elseif eventKind == "slump" then
					sink = math.min(1, e / 0.4) * 8
				end
				if e > 0.6 and eventKind ~= "slump" then
					eventKind = nil
				end
			end
			if reduced() then
				lift, ex, erot = lift * 0.3, ex * 0.3, erot * 0.3
			end
			holder.Position = UDim2.fromOffset(baseX + dx + ex, baseY + dy - lift + sink)
			holder.Rotation = rot + erot
		end)
	end

	local function setShown(on)
		if not ok or on == shown then return end
		shown = on
		holder.Visible = on
		shadow.Visible = on
		if on then
			layout()
			startLoop()
		else
			stopLoop()
			eventKind = nil
		end
	end

	-- Menu time: start fetching so the avatar is ready before the first round.
	function M.prewarm()
		requestThumbnail()
	end

	function M.isReady(_expectBoss)
		if not ok then return true end
		return thumbDone or (os.clock() - started) > GIVE_UP_AFTER
	end

	function M.isActive()
		return false -- the framed portrait always stays the boss
	end

	function M.reset()
		setShown(false)
		mode = "none"
		lastKey = nil
	end

	function M.playBossState(_name, _strength) end

	function M.playPlayerState(name)
		if not (ok and shown) then return end
		if name == "cheer" or name == "flinch" or name == "slump" then
			eventKind = name
			eventStart = os.clock()
			eventStrength = name == "cheer" and 1 or 0.7
		end
	end

	function M.update(state)
		if not ok or type(state) ~= "table" then return end
		requestThumbnail()
		if state.phase ~= "playing" then
			if shown then
				-- keep the avatar through the boss-defeat / loss beat (BossFight runs for ~1.5s), then hide
				if mode == "boss" and (state.phase == "shop" or state.phase == "roundSelect" or state.phase == "gameover" or state.phase == "nightVictory") then
					mode = "ending"
					local mine = lastKey
					task.delay(1.7, function()
						if mode == "ending" and lastKey == mine then
							M.reset()
						end
					end)
					return
				end
				if mode ~= "ending" then
					M.reset()
				end
			end
			return
		end
		local isBoss = state.bossModifier ~= nil and (state.round or 1) >= ROUNDS_PER_NIGHT
		local newMode = isBoss and "boss" or "normal"
		local key = tostring(state.night or 1) .. "-" .. tostring(state.round or 1)
		if mode == "ending" then
			M.reset()
		end
		if newMode ~= mode or key ~= lastKey then
			mode = newMode
			lastKey = key
			layout()
		end
		setShown(true)
		if thumbDone and not thumbContent then
			showSilhouette()
		end
	end

	function M.failed()
		return not ok
	end

	return M
end

return {
	build = build,
}
