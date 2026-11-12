--[[
	Client/DebugGoto.lua
	Studio-only jump hook. Set a StringValue named DebugGoto under the LocalPlayer (or the attribute DebugGoto)
	to one of: menu, tome:<collection|cardsets|badges|legend|flair|stats>[:subtab], news, round1, round1:<cardSetId>
	(the last starts round 1 with that Card Set previewed, e.g. round1:winter_evening).
	Goes through the normal open paths (OverlayManager openers, NewsPanel.open, the StartSeedRun and Choice
	remotes). Prints "[DebugGoto] <value> ok" or the error. Does nothing outside Studio. shop and spectate need a
	server hook or a second player, so they only warn. Parsing is in Engine/DebugGotoRules.lua.
	init({ menuFrame })
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DebugGoto = {}

function DebugGoto.init(deps)
	if not RunService:IsStudio() then return end
	local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("DebugGotoRules"))
	local OverlayManager = require(script.Parent.OverlayManager)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local player = Players.LocalPlayer
	local pendingRound1 = false
	local round1Token = 0 -- bumped on every jump so an old watchdog never fires for a new one
	local lastStep = "start"
	local selectSent = false
	local previewSet = nil -- round1:<setId>: the set to preview once the hand is dealt (a run start resets the look)

	local function hideMenu()
		if deps and deps.menuFrame then deps.menuFrame.Visible = false end
	end
	-- the Menu scene stays up behind Tome panels and the news board (like the real Menu), so no 3D world shows through them
	local function showMenu()
		if deps and deps.root then deps.root.Visible = false end
		if deps and deps.menuFrame then deps.menuFrame.Visible = true end
	end
	local function hideTutorialOverlay()
		local overlay = player.PlayerGui:FindFirstChild("TutorialOverlay", true)
		if overlay and overlay:IsA("GuiObject") then overlay.Visible = false end
	end

	local function go(value)
		local target, why = Rules.parse(value)
		if not target then
			warn("[DebugGoto] " .. tostring(value) .. " ignored: " .. tostring(why))
			return
		end
		local ok, err = pcall(function()
			pendingRound1 = false
			pcall(function() require(script.Parent.LoginStreakUI).suppress(true) end) -- the daily reward plate would cover the view
			if target.kind == "menu" then
				OverlayManager.closeAllExcept("")
				showMenu()
			elseif target.kind == "tome" then
				OverlayManager.closeAllExcept("")
				showMenu()
				if not OverlayManager.open(target.page) then error("no opener for " .. target.page) end
				if target.sub then
					warn("[DebugGoto] sub-tab " .. target.sub .. " cannot be clicked from script; panel opened on its first tab")
				end
			elseif target.kind == "news" then
				OverlayManager.closeAllExcept("")
				showMenu()
				require(script.Parent.NewsPanel).open()
			elseif target.kind == "round1" then
				OverlayManager.closeAllExcept("")
				hideMenu()
				if deps and deps.root then deps.root.Visible = true end -- the real launch shows the table too (Client/ChallengeStart.launch)
				hideTutorialOverlay()
				local CosmeticSets = require(ReplicatedStorage.Shared.Engine.CosmeticSets)
				previewSet = nil
				-- a preview left over from an earlier jump or the Card Sets panel would win over this jump's set: clear it first
				pcall(function() require(script.Parent.CosmeticSetsView).stopPreview() end)
				if target.setId then
					previewSet = CosmeticSets.getById(target.setId)
					if not previewSet then error("unknown card set " .. target.setId) end
				end
				pendingRound1 = true
				lastStep = "start"
				selectSent = false
				round1Token = round1Token + 1
				local mine = round1Token
				remotes:WaitForChild("StartSeedRun"):FireServer(Rules.SEED_CODE)
				task.delay(Rules.ROUND1_TIMEOUT, function()
					if pendingRound1 and round1Token == mine then
						pendingRound1 = false
						warn("[DebugGoto] round1 stuck at step '" .. lastStep .. "' after " .. Rules.ROUND1_TIMEOUT .. " s")
					end
				end)
			else
				error(target.kind .. " is not reachable from script (needs a server hook or a second player)")
			end
		end)
		if ok then
			print("[DebugGoto] " .. tostring(value) .. " ok")
		else
			warn("[DebugGoto] " .. tostring(value) .. " failed: " .. tostring(err))
		end
	end

	-- round1: answer the draft and blessing choices with the first option, then start the round
	remotes:WaitForChild("StateUpdated").OnClientEvent:Connect(function(state)
		if not pendingRound1 then return end
		lastStep = Rules.stepOf(state)
		local count = Rules.handCount(state)
		if count then
			pendingRound1 = false
			print("[DebugGoto] round1 hand=" .. count)
			if previewSet then
				local set = previewSet
				previewSet = nil
				-- same call the Card Sets Preview button makes; PlayScenePaint then prints [PlayTableSet] <set> front=<painted|default>
				local okP, errP = pcall(function() require(script.Parent.CosmeticSetsView).preview(set.id, set.cardBackId) end)
				print("[DebugGoto] round1 preview " .. set.id .. (okP and " ok" or (" failed: " .. tostring(errP))))
			end
			return
		end
		hideTutorialOverlay()
		local step, optionId = Rules.round1Step(state)
		if step == "choice" then
			remotes:WaitForChild("Choice"):FireServer(optionId)
		elseif step == "select" and not selectSent then
			selectSent = true
			remotes:WaitForChild("SelectRound"):FireServer() -- stays pending until the hand is dealt
		end
	end)

	local function watch(inst)
		if inst:IsA("StringValue") and inst.Name == "DebugGoto" then
			inst.Changed:Connect(function() go(inst.Value) end)
			if inst.Value ~= "" then go(inst.Value) end
		end
	end
	player.ChildAdded:Connect(watch)
	for _, child in ipairs(player:GetChildren()) do watch(child) end
	player:GetAttributeChangedSignal("DebugGoto"):Connect(function() go(player:GetAttribute("DebugGoto")) end)
end

return DebugGoto
