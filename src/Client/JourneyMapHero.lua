--[[
	Client/JourneyMapHero.lua
	The player's mini avatar on the Journey map. Three steps, each in a pcall,
	so the map never lacks a hero:
	  1. a clone of LocalPlayer.Character (scripts, tools and sounds stripped)
	     in a ViewportFrame/WorldModel with a small camera, walk/idle
	     animations through its Animator;
	  2. Players:GetUserThumbnailAsync(AvatarBust) as an ImageLabel;
	  3. ContentArt map_nodes/hero_token (or the emoji) in a round plaque.
	The plaque (3) is shown at once; 1 or 2 replace it when they work.

	Facing: the viewport clone is turned (yaw) to face the travel direction;
	image heroes are mirrored with a negative width. Idle looks 3/4 toward
	the camera. The image/token hero gets a gentle bob while walking.

	deps: parent (Frame the hero fills), Players, TweenService, ContentArt,
	PatronPlaque, roundCorner, calm() -> bool (Reduce Shake)

	Returns:
		build()            create the hero if there is none (safe to call often)
		destroy()          stop animations, destroy the clone and every hero frame
		setWalking(bool)   walk vs idle animation / bob
		face(dir)          1 = right, -1 = left
		getKind()          "viewport" | "bust" | "token" | nil
]]

return function(deps)
	local Players = deps.Players
	local TweenService = deps.TweenService

	local ANIM = {
		R15 = { walk = "rbxassetid://507777826", idle = "rbxassetid://507766388" },
		R6 = { walk = "rbxassetid://180426354", idle = "rbxassetid://180435571" },
	}
	local PARCHMENT = Color3.fromRGB(226, 202, 156)

	local built = nil -- { kind, root, ... }
	local facing = 1
	local walking = false
	local buildToken = 0

	local function yawFor()
		-- Camera looks down -Z; facing right shows the character's side.
		local side = walking and math.pi / 2 or math.pi * 0.75
		return -side * facing
	end

	local function applyPose()
		if not built then
			return
		end
		if built.kind == "viewport" then
			pcall(function()
				built.clone:PivotTo(CFrame.Angles(0, yawFor(), 0))
			end)
			pcall(function()
				if walking then
					if built.idle then built.idle:Stop(0.15) end
					if built.walk and not built.walk.IsPlaying then built.walk:Play(0.15) end
				else
					if built.walk then built.walk:Stop(0.15) end
					if built.idle and not built.idle.IsPlaying then built.idle:Play(0.15) end
				end
			end)
		elseif built.kind == "bust" or built.kind == "token" then
			local label = built.flip
			if label then
				if facing < 0 then
					label.Size = UDim2.fromScale(-1, 1)
					label.Position = UDim2.fromScale(1, 0)
				else
					label.Size = UDim2.fromScale(1, 1)
					label.Position = UDim2.fromScale(0, 0)
				end
			end
			if built.bob then
				if walking and not deps.calm() then
					built.bob:Play()
				else
					built.bob:Cancel()
					built.inner.Position = UDim2.fromOffset(0, 0)
				end
			end
		end
	end

	local function destroy()
		buildToken += 1
		if built then
			local b = built
			built = nil
			pcall(function()
				if b.walk then b.walk:Stop(0) end
				if b.idle then b.idle:Stop(0) end
				if b.bob then b.bob:Cancel() end
			end)
			pcall(function()
				if b.clone then b.clone:Destroy() end
				b.root:Destroy()
			end)
		end
	end

	-- ===== Step 3: token / emoji plaque (always works) =====
	local function makeToken()
		local root = Instance.new("Frame")
		root.Name = "HeroToken"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundTransparency = 1
		root.ZIndex = 34
		root.Parent = deps.parent
		local inner = Instance.new("Frame")
		inner.AnchorPoint = Vector2.new(0.5, 1)
		inner.Position = UDim2.fromScale(0.5, 1)
		inner.Size = UDim2.fromOffset(46, 46)
		inner.BackgroundColor3 = PARCHMENT
		inner.ZIndex = 34
		inner.Parent = root
		deps.roundCorner(inner, 23)
		local emoji = Instance.new("TextLabel")
		emoji.Size = UDim2.fromScale(1, 1)
		emoji.BackgroundTransparency = 1
		emoji.Font = Enum.Font.Gotham
		emoji.TextSize = 28
		emoji.Text = "🙂"
		emoji.TextTransparency = 0
		emoji.TextStrokeTransparency = 1
		emoji.ZIndex = 35
		emoji.Parent = inner
		pcall(function()
			local id = deps.ContentArt.getImageId("map_nodes", "hero_token")
			if id then
				deps.PatronPlaque.applyById(inner, id, { emojiLabel = emoji, zIndex = 35, cornerRadius = 23, ring = true })
			end
		end)
		local bob = TweenService:Create(inner, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.new(0.5, 0, 1, -5) })
		built = { kind = "token", root = root, inner = inner, bob = bob }
		applyPose()
	end

	-- ===== Step 1: live clone of the character =====
	local function tryViewport()
		local char = Players.LocalPlayer and Players.LocalPlayer.Character
		if not char then
			return false
		end
		char.Archivable = true
		local clone = char:Clone()
		if not clone then
			return false
		end
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("Tool") or d:IsA("Sound")
				or d:IsA("ForceField") or d:IsA("BillboardGui") then
				d:Destroy()
			end
		end
		local hum = clone:FindFirstChildOfClass("Humanoid")
		local hrp = clone:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then
			clone:Destroy()
			return false
		end
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hrp.Anchored = true
		clone.PrimaryPart = hrp

		local root = Instance.new("ViewportFrame")
		root.Name = "HeroViewport"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundTransparency = 1
		root.Ambient = Color3.fromRGB(190, 175, 150)
		root.LightColor = Color3.fromRGB(255, 240, 215)
		root.LightDirection = Vector3.new(-0.4, -0.6, -0.7)
		root.ZIndex = 34
		local world = Instance.new("WorldModel")
		world.Parent = root
		clone.Parent = world
		clone:PivotTo(CFrame.new(0, 0, 0))
		local cam = Instance.new("Camera")
		cam.FieldOfView = 28
		cam.CFrame = CFrame.lookAt(Vector3.new(0, -0.1, 13.5), Vector3.new(0, -0.1, 0))
		cam.Parent = root
		root.CurrentCamera = cam
		root.Parent = deps.parent

		local rig = hum.RigType == Enum.HumanoidRigType.R6 and "R6" or "R15"
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = hum
		end
		local function load(id)
			local ok, track = pcall(function()
				local a = Instance.new("Animation")
				a.AnimationId = id
				local t = animator:LoadAnimation(a)
				t.Looped = true
				return t
			end)
			return ok and track or nil
		end
		built = { kind = "viewport", root = root, clone = clone, walk = load(ANIM[rig].walk), idle = load(ANIM[rig].idle) }
		return true
	end

	-- ===== Step 2: avatar bust thumbnail =====
	local function tryBust(token)
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(Players.LocalPlayer.UserId, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size150x150)
		end)
		if not ok or type(content) ~= "string" or content == "" or token ~= buildToken then
			return false
		end
		local root = Instance.new("Frame")
		root.Name = "HeroBust"
		root.Size = UDim2.fromScale(1, 1)
		root.BackgroundTransparency = 1
		root.ZIndex = 34
		local inner = Instance.new("Frame")
		inner.Size = UDim2.fromScale(1, 1)
		inner.BackgroundTransparency = 1
		inner.ZIndex = 34
		inner.Parent = root
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.Image = content
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = 34
		img.Parent = inner
		root.Parent = deps.parent
		local bob = TweenService:Create(inner, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.fromOffset(0, -5) })
		return { kind = "bust", root = root, inner = inner, flip = img, bob = bob }
	end

	local function build()
		if built then
			return
		end
		buildToken += 1
		local token = buildToken
		local okView = pcall(function()
			if not tryViewport() then
				error("no character")
			end
		end)
		if okView and built then
			applyPose()
			return
		end
		built = nil
		-- Step 3 now (never without a hero), then upgrade to the bust when it loads.
		makeToken()
		task.spawn(function()
			local bust = tryBust(token)
			if bust and token == buildToken and built then
				local old = built
				built = bust
				pcall(function()
					old.root:Destroy()
				end)
				applyPose()
			elseif bust then
				bust.root:Destroy()
			end
		end)
	end

	return {
		build = build,
		destroy = destroy,
		setWalking = function(on)
			walking = on == true
			applyPose()
		end,
		face = function(dir)
			facing = dir >= 0 and 1 or -1
			applyPose()
		end,
		getKind = function()
			return built and built.kind or nil
		end,
	}
end
