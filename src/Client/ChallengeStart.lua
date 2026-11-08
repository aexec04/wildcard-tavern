--[[
	Client/ChallengeStart.lua
	Starting a Daily, Weekly or Seed Run from the main menu. The tiles used to fire the remote and nothing
	else: the menu stayed on top of the new run and a blocked state failed silently. Now:
	  * Engine/ChallengeStart decides: start, ask first (a run is in progress), or blocked with one short line;
	  * a blocked tile shows that line on its own label for a moment;
	  * a run in progress asks with the same hold-to-confirm popup as Restart Run;
	  * starting hides the menu and shows the table, like the Play button does.

	init{ root, menuFrame, remotes = { daily, weekly, seed }, getState, music?, isTutorialActive? }
	start(kind, button?, code?)   kind = "daily" | "weekly" | "seed"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ChallengeStart"))

local ChallengeStart = {}
local deps = nil

function ChallengeStart.init(d)
	deps = d
end

function ChallengeStart.ready()
	return deps ~= nil
end

local function traveling()
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	return pg ~= nil and pg:FindFirstChild("TravelTransition") ~= nil
end

-- Show a short line on the tile itself for a moment (its first TextLabel that holds the tile name).
local function flashTile(button, line)
	if not button or not line then return end
	local target
	for _, d in ipairs(button:GetDescendants()) do
		if d:IsA("TextLabel") and d.Text ~= "" and #d.Text < 24 and d.Visible then
			target = d
		end
	end
	if not target then return end
	local original = target.Text
	target.Text = line
	task.delay(2.2, function()
		if target.Parent and target.Text == line then target.Text = original end
	end)
end

local function launch(kind, code)
	local remote = deps.remotes[kind]
	if not remote then return end
	if kind == "seed" then
		remote:FireServer(code)
	else
		remote:FireServer()
	end
	deps.menuFrame.Visible = false
	deps.root.Visible = true
	local music = deps.music
	if music and music.SoundId ~= "rbxassetid://0" and music.Volume > 0 and not music.IsPlaying then
		music:Play()
	end
end

local NAMES = { daily = "Daily Challenge", weekly = "Weekly Challenge", seed = "Seed Run" }

function ChallengeStart.start(kind, button, code)
	if not deps then return end
	local state = deps.getState()
	local verdict, line = Rules.check({
		hasState = state ~= nil,
		phase = state and state.phase, night = state and state.night, round = state and state.round,
		tutorialActive = deps.isTutorialActive and deps.isTutorialActive() or false,
		traveling = traveling(),
	})
	if verdict == "blocked" then
		flashTile(button, line)
		if deps.warn then deps.warn(line) end
		return
	end
	if verdict == "confirm" then
		local restart = require(script.Parent.RestartRun).get()
		if restart then
			restart.ask({
				title = "Start a " .. (NAMES[kind] or "new run") .. "?",
				message = "Your current run will end and its progress is lost. Your Collection, Keys and badges are kept.",
				holdText = "Hold to Start",
				onConfirm = function()
					local abandon = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("AbandonRun")
					if abandon then abandon:FireServer() end
					launch(kind, code)
				end,
			})
			return
		end
	end
	launch(kind, code)
end

return ChallengeStart
