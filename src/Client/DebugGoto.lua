--[[
	Client/DebugGoto.lua
	Studio-only jump hook. Set a StringValue named DebugGoto under the LocalPlayer (or the attribute DebugGoto)
	to one of: menu, tome:<collection|cardsets|badges|legend|flair|stats>[:subtab], news, round1.
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

	local function hideMenu()
		if deps and deps.menuFrame then deps.menuFrame.Visible = false end
	end

	local function go(value)
		local target, why = Rules.parse(value)
		if not target then
			warn("[DebugGoto] " .. tostring(value) .. " ignored: " .. tostring(why))
			return
		end
		local ok, err = pcall(function()
			pendingRound1 = false
			if target.kind == "menu" then
				OverlayManager.closeAllExcept("")
				if deps and deps.menuFrame then deps.menuFrame.Visible = true end
			elseif target.kind == "tome" then
				hideMenu()
				if not OverlayManager.open(target.page) then error("no opener for " .. target.page) end
				if target.sub then
					warn("[DebugGoto] sub-tab " .. target.sub .. " cannot be clicked from script; panel opened on its first tab")
				end
			elseif target.kind == "news" then
				OverlayManager.closeAllExcept("")
				require(script.Parent.NewsPanel).open()
			elseif target.kind == "round1" then
				OverlayManager.closeAllExcept("")
				hideMenu()
				pendingRound1 = true
				remotes:WaitForChild("StartSeedRun"):FireServer(Rules.SEED_CODE)
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
		local step, optionId = Rules.round1Step(state)
		if step == "choice" then
			remotes:WaitForChild("Choice"):FireServer(optionId)
		elseif step == "select" then
			pendingRound1 = false
			remotes:WaitForChild("SelectRound"):FireServer()
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
