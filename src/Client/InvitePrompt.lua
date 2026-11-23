--[[
	Client/InvitePrompt.lua
	The Invite button (main menu tile and Run Summary): asks Roblox to open its game-invite sheet.
	  InvitePrompt.bind(button)   makes `button` invite on click

	Checks SocialService:CanSendGameInviteAsync first and shows a short message when invites are unavailable
	(Studio, a private server, or the player's settings). The invite carries LaunchData "inv:<my userId>"
	(Engine/Invites.launchData); the server reads it when the friend joins and pays both sides once.
	Every call is wrapped in pcall and runs in its own thread, so a social service error never touches gameplay.
]]

local Layers = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Layers"))
local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Invites = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Invites"))

local InviteStates = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("InviteStates"))

local GameName = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("GameName"))

local InvitePrompt = {}

local busy = false
local lastAnchor
local closedHooked = false

local function toast(anchor, text)
	local gui = anchor and anchor:FindFirstAncestorOfClass("ScreenGui")
	if not gui then
		return
	end
	local old = gui:FindFirstChild("InviteToast")
	if old then
		old:Destroy()
	end
	local label = Instance.new("TextLabel")
	label.Name = "InviteToast"
	local size = gui.AbsoluteSize
	local r = InviteStates.plate(size.X, size.Y) -- tested rect: inside the screen, 52 px tall, room for two lines
	label.Position = UDim2.fromOffset(r.x, r.y)
	label.Size = UDim2.fromOffset(r.w, r.h)
	label.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(250, 235, 200)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 1
	label.TextWrapped = true
	label.Text = text
	label.ZIndex = Layers.effect + 100
	label.Active = false
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	task.delay(3, function()
		if label.Parent then
			if require(script.Parent.ClientSettings).motionAllowed() then
				TweenService:Create(label, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			else
				label.BackgroundTransparency, label.TextTransparency, label.TextStrokeTransparency = 1, 1, 1 -- Calm: no fade
			end
			task.delay(0.45, function()
				if label.Parent then label:Destroy() end
			end)
		end
	end)
end

-- The invite sheet closed: friends were picked (sent) or it was closed with nobody (declined, said kindly).
local function hookClosed()
	if closedHooked then return end
	closedHooked = true
	pcall(function()
		SocialService.GameInvitePromptClosed:Connect(function(_, recipientIds)
			toast(lastAnchor, InviteStates.line(type(recipientIds) == "table" and #recipientIds > 0 and "sent" or "declined"))
		end)
	end)
end

function InvitePrompt.prompt(anchor)
	if busy then
		return
	end
	busy = true
	lastAnchor = anchor
	hookClosed()
	task.spawn(function()
		local player = Players.LocalPlayer
		local okCan, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not (okCan and can) then
			toast(anchor, InviteStates.line("unavailable"))
			busy = false
			return
		end
		local okSend, err = pcall(function()
			local options = Instance.new("ExperienceInviteOptions")
			options.PromptMessage = "Come play " .. GameName.NAME .. " with me!"
			options.LaunchData = Invites.launchData(player.UserId)
			SocialService:PromptGameInvite(player, options)
		end)
		if not okSend then
			warn("[Invite] prompt failed: " .. tostring(err))
			toast(anchor, InviteStates.line("failed"))
		end
		busy = false
	end)
end

function InvitePrompt.bind(button)
	button.MouseButton1Click:Connect(function()
		InvitePrompt.prompt(button)
	end)
end

return InvitePrompt
