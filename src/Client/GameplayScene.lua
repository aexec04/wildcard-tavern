--[[
	Client/GameplayScene.lua
	Owns the gameplay table background so it matches where the player is on the Tavern Map.
	Small round -> "<art>_a", Big round -> "<art>_b", Boss round -> "<art>_in" (see Engine/SceneKeys).
	Scenes come from ContentArt "scenes"; while an id is missing nothing is shown and the old
	GameBackgroundArt (ArtAssets.gameplayBackground or the equipped set's backdrop) stays visible.

	Layers (all under root, below the UI): GameBackgroundArt (hub, untouched) < GameSceneStack
	(two stacked ImageLabels that crossfade, with a slow push-in UIScale) < GameSceneShade (stepped
	dark strips over the bottom half so cards stay readable on any scene).

	Boss walk-in: on entering a Boss round the outside scene zooms toward the door, a gold flash
	cuts to the inside scene, which settles back to 1.0, with a short whoosh and a vignette pulse.
	Total about 1.1s, never blocks input (nothing here is Active), skipped on Fast and Reduce shake.
	Once it ends, afterWalkIn's callback runs so the existing Boss Intro plays after it.

	Round Select shows the scene of the round that is up, except the Boss round, which shows its
	outside "_b" (the door) so the walk-in has somewhere to come from. The Shop keeps the last scene.

	deps: root, gameBackgroundArt, playSfx(id, volume, maxLength), soundId (whoosh)
	module: init(deps) once, then get() -> { update(state), walkInActive() -> bool, afterWalkIn(fn(lastState)), reset() }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local SceneKeys = require(Engine:WaitForChild("SceneKeys"))
local ClientSettings = require(script.Parent.ClientSettings)

local ROUNDS_PER_NIGHT = 3 -- same client-side assumption RoundSelect.lua makes
local CROSSFADE = 0.7
local PUSH_IN_TO = 1.06
local PUSH_IN_SECONDS = 90
local DIM = Color3.fromRGB(215, 205, 195) -- same dimming the hub gives the default backdrop
local SHADE_STEPS = 10

local function tween(inst, props, time, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function build(deps)
	local root = deps.root
	local gameBackgroundArt = deps.gameBackgroundArt
	local playSfx = deps.playSfx
	local soundId = deps.soundId

	local stack = Instance.new("Frame")
	stack.Name = "GameSceneStack"
	stack.AnchorPoint = Vector2.new(0.5, 0.5)
	stack.Position = UDim2.fromScale(0.5, 0.5)
	stack.Size = UDim2.fromScale(1, 1)
	stack.BackgroundTransparency = 1
	stack.BorderSizePixel = 0
	stack.Active = false
	stack.ZIndex = 0
	stack.Parent = root
	local push = Instance.new("UIScale")
	push.Parent = stack

	local labels = {}
	for i = 1, 2 do
		local label = Instance.new("ImageLabel")
		label.Name = "Scene" .. i
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.ScaleType = Enum.ScaleType.Crop
		label.ImageColor3 = DIM
		label.ImageTransparency = 1
		label.Active = false
		label.ZIndex = 0
		label.Parent = stack
		labels[i] = label
	end

	-- Soft dark gradient over the bottom half (stepped strips, Frame transparency only).
	local shade = Instance.new("Frame")
	shade.Name = "GameSceneShade"
	shade.AnchorPoint = Vector2.new(0, 1)
	shade.Position = UDim2.fromScale(0, 1)
	shade.Size = UDim2.fromScale(1, 0.55)
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.Active = false
	shade.ZIndex = 0
	shade.Visible = false
	shade.Parent = root
	for i = 1, SHADE_STEPS do
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(1, 0, 1 / SHADE_STEPS, 1)
		strip.Position = UDim2.new(0, 0, (i - 1) / SHADE_STEPS, 0)
		strip.BackgroundColor3 = Color3.fromRGB(10, 6, 4)
		strip.BackgroundTransparency = 1 - 0.55 * (i / SHADE_STEPS) ^ 1.3
		strip.BorderSizePixel = 0
		strip.Active = false
		strip.ZIndex = 0
		strip.Parent = shade
	end

	-- Walk-in effect frames (above the table, below the Boss Intro overlay at 36).
	local flash = Instance.new("Frame")
	flash.Name = "SceneWalkInFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.fromRGB(255, 232, 170)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Active = false
	flash.ZIndex = 34
	flash.Parent = root
	local vignette = Instance.new("Frame")
	vignette.Name = "SceneWalkInVignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = Color3.new(0, 0, 0)
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel = 0
	vignette.Active = false
	vignette.ZIndex = 33
	vignette.Parent = root

	local M = {}
	local front = 1 -- index of the label currently showing
	local currentKey = nil -- key shown (or wanted) right now
	local lastBossKey = nil
	local lastState = nil
	local fadeToken = 0
	local pushTween = nil
	local walkToken = 0
	local walking = false
	local afterFn = nil

	local function fast()
		return ClientSettings.get("animSpeed") == "fast"
	end
	local function reduced()
		return ClientSettings.get("reduceShake") == true
	end

	local function startPush(from)
		if pushTween then pushTween:Cancel() pushTween = nil end
		push.Scale = from or 1
		if reduced() then
			push.Scale = 1
			return
		end
		pushTween = tween(push, { Scale = PUSH_IN_TO }, PUSH_IN_SECONDS, Enum.EasingStyle.Linear)
	end

	-- Publish the shown image so CosmeticSetsView does not fight it (it keeps its own backdrop swap).
	local function show(key, instant)
		local image = key and ContentArt.getImageId("scenes", key) or nil
		fadeToken = fadeToken + 1
		local mine = fadeToken
		local duration = (instant or fast()) and 0 or CROSSFADE
		if not image then
			-- No art yet: fade the scenes out, the old backdrop shows.
			for _, l in ipairs(labels) do
				tween(l, { ImageTransparency = 1 }, duration)
			end
			shade.Visible = false
			return
		end
		local old = labels[front]
		local new = labels[3 - front]
		new.Image = image
		new.ImageTransparency = 1
		new.ZIndex = 0
		-- Draw the incoming label above the outgoing one.
		old.ZIndex = 0
		new.Parent = nil
		new.Parent = stack
		shade.Visible = true
		if duration > 0 then
			tween(new, { ImageTransparency = 0 }, duration)
			task.delay(duration, function()
				if fadeToken == mine then old.ImageTransparency = 1 end
			end)
		else
			new.ImageTransparency = 0
			old.ImageTransparency = 1
		end
		front = 3 - front
		startPush(1)
	end

	local function wantedKey(state)
		local night, round = state.night or 1, state.round or 1
		local kind = SceneKeys.roundKind(round, ROUNDS_PER_NIGHT)
		if state.phase == "roundSelect" and kind == "boss" then
			kind = "big" -- the approach; the walk-in plays when the round actually starts
		end
		return SceneKeys.keyFor(night, kind)
	end

	local function finishWalkIn()
		walking = false
		local fn = afterFn
		afterFn = nil
		if fn then
			local ok, err = pcall(fn, lastState)
			if not ok then warn("GameplayScene afterWalkIn failed: " .. tostring(err)) end
		end
	end

	local function walkIn(insideKey)
		walkToken = walkToken + 1
		local mine = walkToken
		walking = true
		if pushTween then pushTween:Cancel() pushTween = nil end
		if playSfx and soundId then pcall(playSfx, soundId, 0.35, 0.6) end
		-- 1) zoom toward the door
		tween(push, { Scale = 1.25 }, 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(vignette, { BackgroundTransparency = 0.55 }, 0.5)
		task.delay(0.6, function()
			if walkToken ~= mine then return end
			-- 2) gold flash, cut to the inside scene (settles from 1.15 to 1.0)
			flash.BackgroundTransparency = 0.25
			show(insideKey, true)
			push.Scale = 1.15
			tween(push, { Scale = 1 }, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			tween(flash, { BackgroundTransparency = 1 }, 0.3)
			tween(vignette, { BackgroundTransparency = 1 }, 0.45)
			task.delay(0.45, function()
				if walkToken ~= mine then return end
				startPush(1)
				finishWalkIn()
			end)
		end)
	end

	function M.walkInActive()
		return walking
	end

	-- Run fn(latestState) when the current walk-in finishes (one pending callback).
	function M.afterWalkIn(fn)
		afterFn = fn
	end

	function M.reset()
		walkToken = walkToken + 1
		walking = false
		afterFn = nil
		lastBossKey = nil
		currentKey = nil
		flash.BackgroundTransparency = 1
		vignette.BackgroundTransparency = 1
	end

	function M.update(state)
		if type(state) ~= "table" or not state.night or not state.round then return end
		lastState = state
		local phase = state.phase
		if phase ~= "roundSelect" and phase ~= "playing" then
			return -- shop and game over keep whatever is showing (no flicker)
		end
		local key = wantedKey(state)
		local isBossPlay = phase == "playing" and state.bossModifier ~= nil
			and SceneKeys.roundKind(state.round, ROUNDS_PER_NIGHT) == "boss"
		local bossKey = tostring(state.night) .. "-" .. tostring(state.round)

		if isBossPlay and bossKey ~= lastBossKey then
			local firstSight = (lastBossKey == nil and currentKey == nil)
			lastBossKey = bossKey
			-- Walk in only when the player was just outside this Boss round's door.
			local outside = SceneKeys.keyFor(state.night, "big")
			if not firstSight and currentKey == outside and not fast() and not reduced()
				and ContentArt.getImageId("scenes", key) and ContentArt.getImageId("scenes", outside) then
				currentKey = key
				walkIn(key)
				return
			end
		end
		if key ~= currentKey and not walking then
			currentKey = key
			show(key)
		end
	end

	startPush(1)
	return M
end

-- Singleton: the hub calls init() once (a do-block, it has no spare locals) and get() from render().
local instance = nil
return {
	init = function(deps)
		instance = build(deps)
		return instance
	end,
	get = function()
		return instance
	end,
}
