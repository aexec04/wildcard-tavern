--[[
	Client/CharacterStage.lua
	PROTOTYPE: live characters in the scene. One transparent ViewportFrame over the table area
	(between the scene background and the hand/UI, click-through) holds:
	  - the player's own avatar (HumanoidDescription R15 rig, blocky fallback rig on any failure),
	  - during a Boss Round, a blocky boss rig (Client/BossRigs.lua) facing the player.
	Normal rounds show only the player, small, lower left. Boss rounds show both, the portrait
	frame of BossFight is hidden while the stage works (and stays as the fallback if it fails).

	No animation assets: every rig is anchored Parts and each frame the stage recomputes the part
	CFrames itself from the rig's Motor6D/Weld joints (forward kinematics), so poses are just
	target angles that ease in. Idle breathing and weight shift run on top.

	Public API (singleton): init(deps), get() ->
	  update(state)                 called from render(); shows/hides/lays out the stage
	  playBossState(name, strength) "taunt" "attack" "hit" "stagger" "enrage" "defeat" "victory"
	  playPlayerState(name)         "flinch" "cheer" "slump"
	  reset()                       destroy the boss rig, hide the stage (player rig is cached)
	  isActive()                    true while the stage is drawing the boss (BossFight hides the portrait)
	deps: root (ScreenGui frame), SIDEBAR_WIDTH.

	Respects Fast (no slide-in) and Reduce shake (idles nearly still, events are small and short).
	Rigs, connections and delayed callbacks are all dropped on reset(); one rig pair at a time.
	Floors: Engine/SceneKeys.FloorFractions (per scene key, default 0.66 of the screen height).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local SceneKeys = require(Engine:WaitForChild("SceneKeys"))
local BossLines = require(Engine:WaitForChild("BossLines"))
local JourneyMap = require(Engine:WaitForChild("JourneyMap"))
local ClientSettings = require(script.Parent.ClientSettings)
local BossRigs = require(script.Parent.BossRigs)

local FOV = 35
local DIST = 22
local ROUNDS_PER_NIGHT = 3
local PLAYER_YAW = -120 -- faces the boss (+X) turned a little toward the camera
local BOSS_YAW = 120
local ZERO = Vector3.new(0, 0, 0)

-- Joint key -> candidate Motor6D names (R15 avatar first, blocky rig second).
local JOINT_NAMES = {
	waist = { "Waist", "RootJoint" },
	neck = { "Neck" },
	rShoulder = { "RightShoulder" },
	lShoulder = { "LeftShoulder" },
	rHip = { "RightHip" },
	lHip = { "LeftHip" },
}
local JOINT_KEYS = { "waist", "neck", "rShoulder", "lShoulder", "rHip", "lHip" }

local function reduced()
	return ClientSettings.get("reduceShake") == true
end

local function fast()
	return ClientSettings.get("animSpeed") == "fast"
end

-- ===== Rig =====
local Rig = {}
Rig.__index = Rig

local function collectJoints(model, root)
	local all = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("JointInstance") and d.Part0 and d.Part1 then
			table.insert(all, d)
		end
	end
	local placed = { [root] = true }
	local ordered = {}
	local progress = true
	while progress do
		progress = false
		for _, j in ipairs(all) do
			if not placed[j.Part1] and placed[j.Part0] then
				placed[j.Part1] = true
				table.insert(ordered, j)
				progress = true
			end
		end
	end
	return ordered
end

local function newRig(model, kind)
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	assert(root, "rig has no root part")
	local self = setmetatable({}, Rig)
	self.model = model
	self.kind = kind
	self.root = root
	self.joints = collectJoints(model, root)
	self.byKey = {}
	for key, names in pairs(JOINT_NAMES) do
		for _, joint in ipairs(self.joints) do
			if table.find(names, joint.Name) and joint:IsA("Motor6D") and not self.byKey[key] then
				self.byKey[key] = joint
			end
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		elseif d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy() -- nothing simulates in a viewport; avoids name tags and state machines
	end
	self.cur, self.tgt = {}, {}
	for _, key in ipairs(JOINT_KEYS) do
		self.cur[key] = ZERO
		self.tgt[key] = ZERO
	end
	self.off = { x = 0, y = 0, roll = 0, yaw = 0 }
	self.offTgt = { x = 0, y = 0, roll = 0, yaw = 0 }
	self.base = {} -- resting pose (enrage lean etc.)
	self.rate = 12
	self.seq = 0
	self.pos = ZERO
	self.yaw = 0
	self.side = 1
	self.localRoot = CFrame.new()
	self.height = 5
	self.scale1Height = 5
	self.phase = math.random() * 6
	self:remeasure()
	return self
end

-- Forward kinematics with the given root CFrame and joint transforms.
function Rig:fk(rootCF, transformFor)
	self.root.CFrame = rootCF
	for _, j in ipairs(self.joints) do
		local tr = transformFor and transformFor(j) or CFrame.new()
		local c0, c1 = j.C0, j.C1
		if j:IsA("Motor6D") then
			j.Part1.CFrame = j.Part0.CFrame * c0 * tr * c1:Inverse()
		else
			j.Part1.CFrame = j.Part0.CFrame * c0 * c1:Inverse()
		end
	end
end

-- Measure the rest pose: how tall it is and where the feet are relative to the root.
function Rig:remeasure()
	self:fk(CFrame.new(), nil)
	local minY, maxY = math.huge, -math.huge
	for _, d in ipairs(self.model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local half = d.Size / 2
			local cf = d.CFrame
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local y = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)).Y
						minY = math.min(minY, y)
						maxY = math.max(maxY, y)
					end
				end
			end
		end
	end
	if minY == math.huge then
		minY, maxY = -3, 2
	end
	self.localRoot = CFrame.new(0, -minY, 0)
	self.height = maxY - minY
	local scale = self.model:GetScale()
	self.scale1Height = self.height / math.max(scale, 0.001)
end

function Rig:fitHeight(worldHeight)
	self.model:ScaleTo(math.max(0.05, worldHeight / self.scale1Height))
	self:remeasure()
end

local function rest(self)
	return self.base
end

-- pose = { waist = {x,y,z} (degrees), ..., off = { x, y, roll, yaw } }; unlisted joints go to rest.
function Rig:setPose(pose, rate)
	pose = pose or rest(self)
	for _, key in ipairs(JOINT_KEYS) do
		local v = pose[key] or self.base[key]
		self.tgt[key] = v and Vector3.new(v[1] or v.x or 0, v[2] or v.y or 0, v[3] or v.z or 0) or ZERO
	end
	local o = pose.off or self.base.off or {}
	self.offTgt = { x = o.x or 0, y = o.y or 0, roll = o.roll or 0, yaw = o.yaw or 0 }
	if rate then
		self.rate = rate
	end
end

-- Runs timed steps { t = seconds, pose = pose, rate = number? }; a new play() cancels the old one.
-- The last step should be the rest pose (setPose(nil)).
function Rig:play(steps)
	self.seq = self.seq + 1
	local mine = self.seq
	for _, step in ipairs(steps) do
		local function apply()
			if self.seq == mine and self.model.Parent then
				self:setPose(step.pose, step.rate or 12)
			end
		end
		if step.t <= 0 then
			apply()
		else
			task.delay(step.t, apply)
		end
	end
end

function Rig:step(dt, idleAmp)
	local alpha = 1 - math.exp(-self.rate * dt)
	for _, key in ipairs(JOINT_KEYS) do
		self.cur[key] = self.cur[key]:Lerp(self.tgt[key], alpha)
	end
	for k, v in pairs(self.offTgt) do
		self.off[k] = self.off[k] + (v - self.off[k]) * alpha
	end
	local t = os.clock() + self.phase
	local breath = math.sin(t * 2 * math.pi / 3.2)
	local shift = math.sin(t * 2 * math.pi / 7)
	local function rot(key, extra)
		local v = self.cur[key]
		if extra then
			v = v + extra
		end
		return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
	end
	local transforms = {}
	local function put(key, extra)
		local joint = self.byKey[key]
		if joint then
			transforms[joint] = rot(key, extra)
		end
	end
	put("waist", Vector3.new(breath * 1.6 * idleAmp, shift * 2 * idleAmp, 0))
	put("neck", Vector3.new(-breath * 1.2 * idleAmp, -shift * 3 * idleAmp, 0))
	put("rShoulder", Vector3.new(0, 0, 3 + breath * 2 * idleAmp))
	put("lShoulder", Vector3.new(0, 0, -3 - breath * 2 * idleAmp))
	put("rHip", Vector3.new(0, 0, shift * 1.5 * idleAmp))
	put("lHip", Vector3.new(0, 0, shift * 1.5 * idleAmp))
	local roll = self.off.roll + shift * 0.8 * idleAmp
	local origin = CFrame.new(self.pos + Vector3.new(self.off.x, self.off.y, 0))
		* CFrame.Angles(0, 0, math.rad(roll))
		* CFrame.Angles(0, math.rad(self.yaw + self.off.yaw), 0)
	self:fk(origin * self.localRoot, function(j)
		return transforms[j]
	end)
end

function Rig:destroy()
	self.seq = self.seq + 1
	self.model:Destroy()
end

-- ===== Pose library =====
-- Angles are degrees: shoulder z raises the arm sideways and up (+z right arm, -z left arm), shoulder
-- x swings it forward (+x); waist x negative leans forward. off.x is world X: the player stands left
-- (-X), the boss right (+X), so "toward the opponent" is +x for the player and -x for the boss.
local function arms(rz, lz, rx)
	return { rShoulder = { rx or 0, 0, rz }, lShoulder = { 0, 0, lz } }
end

local function merge(a, b)
	local out = {}
	for k, v in pairs(a) do out[k] = v end
	for k, v in pairs(b) do out[k] = v end
	return out
end

local function scaled(pose, k)
	-- Reduce shake: shrink every angle and offset instead of skipping the pose.
	local out = {}
	for key, v in pairs(pose) do
		if key == "off" then
			out.off = { x = (v.x or 0) * k, y = (v.y or 0) * k, roll = (v.roll or 0) * k, yaw = (v.yaw or 0) * k }
		else
			out[key] = { (v[1] or 0) * k, (v[2] or 0) * k, (v[3] or 0) * k }
		end
	end
	return out
end

-- dir = +1 when the rig stands on the right (boss), -1 on the left (player): "away" is +dir in X.
local function bossSteps(name, strength, dir)
	local s = math.max(0.2, math.min(strength or 0.5, 1))
	if name == "taunt" then
		local up = merge(arms(155, -4), { neck = { -8, 0, 0 } })
		local up2 = merge(arms(120, -4), { neck = { -8, 0, 0 } })
		return {
			{ t = 0, pose = up, rate = 14 },
			{ t = 0.3, pose = up2, rate = 14 },
			{ t = 0.6, pose = up, rate = 14 },
			{ t = 0.9, pose = up2, rate = 14 },
			{ t = 1.3, pose = nil, rate = 8 },
		}
	elseif name == "attack" then
		local wind = merge(arms(25, -8, -60), { waist = { 14, 0, 0 }, off = { x = dir * 0.35 } })
		local lunge = merge(arms(8, -8, 150), { waist = { -26, 0, 0 }, off = { x = -dir * (0.9 + 0.7 * s) } })
		return {
			{ t = 0, pose = wind, rate = 16 },
			{ t = 0.16, pose = lunge, rate = 28 },
			{ t = 0.5, pose = nil, rate = 9 },
		}
	elseif name == "hit" then
		return {
			{ t = 0, pose = { waist = { 10 + 14 * s, 0, 0 }, neck = { 12 * s, 0, 0 }, off = { x = dir * (0.3 + 0.8 * s) } }, rate = 26 },
			{ t = 0.28, pose = nil, rate = 9 },
		}
	elseif name == "stagger" then
		return {
			{ t = 0, pose = merge(arms(40, -40), { waist = { 30, 0, 12 }, neck = { 20, 0, 0 }, off = { x = dir * 1.2, roll = -dir * 8 } }), rate = 22 },
			{ t = 0.9, pose = merge(arms(25, -25), { waist = { 14, 0, 6 }, off = { x = dir * 0.5, roll = -dir * 3 } }), rate = 5 },
			{ t = 1.4, pose = nil, rate = 7 },
		}
	elseif name == "enrage" then
		local steps = {}
		for i = 0, 7 do
			steps[#steps + 1] = {
				t = i * 0.09,
				pose = merge(arms(28, -28), { waist = { -14, 0, 0 }, off = { x = (i % 2 == 0 and 1 or -1) * 0.14 } }),
				rate = 40,
			}
		end
		steps[#steps + 1] = { t = 0.8, pose = { waist = { -9, 0, 0 }, rShoulder = { 0, 0, 18 }, lShoulder = { 0, 0, -18 } }, rate = 8 }
		return steps
	elseif name == "defeat" then
		return {
			{ t = 0, pose = merge(arms(45, -45), { waist = { 28, 0, 0 }, off = { x = dir * 0.6 } }), rate = 20 },
			{ t = 0.45, pose = merge(arms(75, -75), { waist = { 20, 0, 0 }, off = { x = dir * 1.4, y = 0.15, roll = -dir * 84 } }), rate = 6 },
		}
	elseif name == "victory" then
		local steps = {}
		for i = 0, 5 do
			steps[#steps + 1] = {
				t = i * 0.22,
				pose = merge(arms(168, -168), { off = { y = (i % 2 == 0) and 0.5 or 0 } }),
				rate = 18,
			}
		end
		steps[#steps + 1] = { t = 1.4, pose = nil, rate = 8 }
		return steps
	end
	return nil
end

local function playerSteps(name, dir)
	if name == "flinch" then
		return {
			{ t = 0, pose = merge(arms(35, -35), { waist = { 10, 0, 0 }, neck = { 10, 0, 0 }, off = { x = dir * 0.45 } }), rate = 26 },
			{ t = 0.3, pose = nil, rate = 9 },
		}
	elseif name == "cheer" then
		local steps = {}
		for i = 0, 3 do
			steps[#steps + 1] = {
				t = i * 0.25,
				pose = merge(arms(170, -170), { off = { y = (i % 2 == 0) and 0.45 or 0 } }),
				rate = 18,
			}
		end
		steps[#steps + 1] = { t = 1.2, pose = nil, rate = 8 }
		return steps
	elseif name == "slump" then
		return {
			{ t = 0, pose = merge(arms(-2, 2), { waist = { -26, 0, 0 }, neck = { -24, 0, 0 }, rShoulder = { 10, 0, 4 }, lShoulder = { 10, 0, -4 }, off = { y = -0.1 } }), rate = 5 },
		}
	end
	return nil
end

-- ===== Stage =====
local function build(deps)
	local root = deps.root
	local sidebarWidth = deps.SIDEBAR_WIDTH or 240

	local M = {}
	local ok = true -- turns false if the stage cannot be built; BossFight keeps its portrait then
	local viewport, cam
	local playerRig, bossRig
	local playerFallback = false
	local playerRequested = false
	local connection = nil
	local mode = "none" -- "none" | "normal" | "boss"
	local bossKey, grandBoss = nil, false
	local sceneKey = "default"
	local lastSize = Vector2.new(0, 0)
	local lastLayoutKey = nil
	local slideStart = nil
	local token = 0

	local okBuild = pcall(function()
		viewport = Instance.new("ViewportFrame")
		viewport.Name = "CharacterStage"
		viewport.BackgroundTransparency = 1
		viewport.BorderSizePixel = 0
		viewport.Active = false
		viewport.ZIndex = 0
		viewport.Ambient = Color3.fromRGB(120, 100, 84)
		viewport.LightColor = Color3.fromRGB(255, 218, 160)
		viewport.LightDirection = Vector3.new(-0.6, -0.8, -0.55)
		viewport.Visible = false
		viewport.Position = UDim2.new(0, sidebarWidth, 0, 0)
		viewport.Size = UDim2.new(1, -sidebarWidth, 1, 0)
		viewport.Parent = root
		cam = Instance.new("Camera")
		cam.FieldOfView = FOV
		cam.Parent = viewport
		viewport.CurrentCamera = cam
	end)
	if not okBuild then
		ok = false
	end

	local function bossHeightFrac()
		return grandBoss and 0.40 or 0.35
	end

	local function layout()
		if not ok then return end
		local size = viewport.AbsoluteSize
		if size.X < 10 or size.Y < 10 then
			size = Vector2.new(1040, 720)
		end
		local aspect = size.X / size.Y
		local H = 2 * DIST * math.tan(math.rad(FOV / 2))
		local W = H * aspect
		local floorFrac = SceneKeys.floorFraction(sceneKey)
		local cy = (floorFrac - 0.5) * H
		cam.CFrame = CFrame.lookAt(Vector3.new(0, cy, DIST), Vector3.new(0, cy, 0))
		if playerRig then
			local frac = (mode == "boss") and 0.32 or 0.22
			playerRig:fitHeight(frac * H)
			playerRig.pos = Vector3.new((mode == "boss") and -0.2 * W or -0.34 * W, 0, 0)
			playerRig.yaw = PLAYER_YAW
			playerRig.side = -1
		end
		if bossRig then
			bossRig:fitHeight(bossHeightFrac() * H)
			bossRig.pos = Vector3.new(0.2 * W, 0, 0)
			bossRig.yaw = BOSS_YAW
			bossRig.side = 1
			bossRig.slideW = W
		end
		lastSize = size
	end

	local function ensureLoop()
		if connection or not ok then return end
		connection = RunService.RenderStepped:Connect(function(dt)
			if not viewport.Visible then return end
			local size = viewport.AbsoluteSize
			if size ~= lastSize and size.X > 10 then
				layout()
			end
			local idleAmp = reduced() and 0.15 or 1
			dt = math.min(dt, 0.1)
			if playerRig then
				playerRig:step(dt, idleAmp)
			end
			if bossRig then
				-- entrance: slide in from the right until the interior scene has settled
				if slideStart then
					local t = (os.clock() - slideStart) / 0.55
					if t >= 1 then
						slideStart = nil
						bossRig.slide = 0
					else
						local e = 1 - (1 - math.max(t, 0)) ^ 3
						bossRig.slide = (1 - e) * (bossRig.slideW or 14) * 0.6
					end
				end
				local keep = bossRig.pos
				bossRig.pos = keep + Vector3.new(bossRig.slide or 0, 0, 0)
				bossRig:step(dt, idleAmp)
				bossRig.pos = keep
			end
		end)
	end

	local function stopLoop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local function mount(rig)
		rig.model.Parent = viewport
	end

	-- The player's own avatar, built once per session (cached); a blocky rig stands in until it is ready.
	local function ensurePlayer()
		if playerRig or playerRequested or not ok then return end
		playerRequested = true
		local function fallback()
			local color = Color3.fromRGB(90, 130, 190)
			local model = BossRigs.buildBlocky({
				skin = Color3.fromRGB(226, 184, 140), shirt = color, pants = Color3.fromRGB(55, 60, 80),
			}, "PlayerRig")
			local rig = newRig(model, "blocky")
			playerFallback = true
			return rig
		end
		task.spawn(function()
			local rig = nil
			local built, model = pcall(function()
				local lp = Players.LocalPlayer
				local description = Players:GetHumanoidDescriptionFromUserId(lp.UserId)
				return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
			end)
			if built and model then
				local okRig, result = pcall(newRig, model, "avatar")
				if okRig then
					rig = result
				else
					pcall(function() model:Destroy() end)
				end
			end
			if not rig then
				local okFb, fb = pcall(fallback)
				if not okFb then
					playerRequested = false
					return
				end
				rig = fb
			end
			playerRig = rig
			mount(rig)
			layout()
		end)
	end

	local function destroyBoss()
		if bossRig then
			bossRig:destroy()
			bossRig = nil
		end
		slideStart = nil
		bossKey = nil
	end

	function M.isActive()
		return ok and viewport ~= nil and viewport.Visible and bossRig ~= nil
	end

	function M.reset()
		token = token + 1
		destroyBoss()
		mode = "none"
		lastLayoutKey = nil
		if viewport then
			viewport.Visible = false
		end
		if playerRig then
			playerRig:setPose(nil, 12)
			playerRig.seq = playerRig.seq + 1
		end
		stopLoop()
	end

	function M.playBossState(name, strength)
		if not (ok and bossRig) then return end
		local steps = bossSteps(name, strength, 1)
		if not steps then return end
		if reduced() then
			steps = { { t = 0, pose = scaled(steps[1].pose or {}, 0.3), rate = 12 }, { t = 0.25, pose = nil, rate = 8 } }
		end
		if name == "enrage" then
			-- the enraged boss keeps leaning in until the round ends
			bossRig.base = { waist = { -9, 0, 0 } }
		elseif name == "defeat" then
			bossRig.base = {}
			if reduced() then
				steps = { { t = 0, pose = { off = { roll = -84, y = 0.15 } }, rate = 10 } }
			end
		end
		bossRig:play(steps)
	end

	function M.playPlayerState(name)
		if not (ok and playerRig) then return end
		local steps = playerSteps(name, -1)
		if not steps then return end
		if reduced() then
			steps = { { t = 0, pose = scaled(steps[1].pose or {}, 0.3), rate = 12 }, { t = 0.25, pose = name == "slump" and steps[1].pose or nil, rate = 8 } }
		end
		playerRig:play(steps)
	end

	-- Called from render() with the latest server state; cheap when nothing changed.
	function M.update(state)
		if not ok or type(state) ~= "table" then return end
		if state.phase ~= "playing" then
			if mode ~= "none" then
				-- a boss fight ending lets BossFight run its defeat / loss beat first; the rig is
				-- only removed when the stage hides, which happens a moment later via reset()
				if mode == "boss" and (state.phase == "shop" or state.phase == "roundSelect" or state.phase == "gameover" or state.phase == "nightVictory") then
					local mine = token
					task.delay(state.phase == "gameover" and 1.9 or 1.7, function()
						if token == mine then
							M.reset()
						end
					end)
					mode = "ending"
					return
				end
				if mode ~= "ending" then
					M.reset()
				end
			end
			return
		end

		local round = state.round or 1
		local boss = state.bossModifier
		local isBoss = boss ~= nil and round >= ROUNDS_PER_NIGHT
		local night = state.night or 1
		sceneKey = SceneKeys.keyFor(night, SceneKeys.roundKind(round, ROUNDS_PER_NIGHT))

		local newMode = isBoss and "boss" or "normal"
		local key = isBoss and (tostring(night) .. "-" .. tostring(round) .. "-" .. tostring(boss.id)) or nil

		if mode == "ending" then
			-- a new round started before the ending timer fired
			M.reset()
		end

		ensurePlayer()
		if not isBoss then
			destroyBoss()
		elseif key ~= bossKey then
			destroyBoss()
			bossKey = key
			grandBoss = BossLines.isGrand(night, state.nightCap or 8, JourneyMap.EndlessMilestones)
			local built, model = pcall(function()
				return BossRigs.build(boss.id, { grand = grandBoss })
			end)
			if built and model then
				local okRig, rig = pcall(newRig, model, "boss")
				if okRig then
					bossRig = rig
					bossRig.slide = 0
					mount(bossRig)
					lastLayoutKey = nil -- the new rig needs sizing and placing
					-- slide in from the side once the walk-in has settled (skipped on Fast / Reduce shake)
					if not fast() and not reduced() then
						bossRig.slide = 99
						local mine = token
						task.delay(0.8, function()
							if token == mine and bossRig then
								slideStart = os.clock()
							end
						end)
					end
				else
					pcall(function() model:Destroy() end)
				end
			end
		end

		if newMode ~= mode or lastLayoutKey ~= sceneKey then
			mode = newMode
			lastLayoutKey = sceneKey
			layout()
		end
		if viewport then
			viewport.Visible = playerRig ~= nil or bossRig ~= nil
			if viewport.Visible then
				ensureLoop()
			end
		end
	end

	function M.failed()
		return not ok
	end

	return M
end

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
