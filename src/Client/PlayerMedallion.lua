--[[
	Client/PlayerMedallion.lua
	The player is shown as a headshot medallion at the top of the left panel (same gold-rimmed dark frame
	as the boss portrait, name beneath) instead of a standing avatar pasted into the scene
	(CharacterStage2D.USE_STAGE_AVATAR = false keeps that avatar off; flip it to bring it back).

	It sits in the top-right corner of the sidebar board's reserved top strip (the left 150px stay clear of
	Roblox's own top-bar buttons), parented to the board so it slides away with the panel on Round Select.
	The headshot comes from Players:GetUserThumbnailAsync (HeadShot, pcall, one retry); when it cannot load
	(Studio, offline) a plain initial on a warm disc stays. The ImageLabel is never gated on IsLoaded.

	install(root) -> medallion Frame or nil (nil if the board is not built)
]]

local Players = game:GetService("Players")

local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)
local SIZE = 42 -- 14 + 42 + 2 + 17 = 75: ends just above where the sidebar content starts (PaddingTop 76), so the name is never cut off

local PlayerMedallion = {}

function PlayerMedallion.install(root)
	local board = root:FindFirstChild("SidebarBoard")
	if not board then return nil end
	if board:FindFirstChild("PlayerMedallion") then return board.PlayerMedallion end
	local player = Players.LocalPlayer

	local holder = Instance.new("Frame")
	holder.Name = "PlayerMedallion"
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Position = UDim2.new(1, -12, 0, 14)
	holder.Size = UDim2.new(0, SIZE + 16, 0, SIZE + 22)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.ZIndex = 4
	holder.Parent = board

	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.Position = UDim2.new(0.5, 0, 0, 0)
	disc.Size = UDim2.fromOffset(SIZE, SIZE)
	disc.BackgroundColor3 = Color3.fromRGB(70, 48, 30)
	disc.BorderSizePixel = 0
	disc.Active = false
	disc.ZIndex = 4
	disc.Parent = holder
	local discCorner = Instance.new("UICorner")
	discCorner.CornerRadius = UDim.new(0.5, 0)
	discCorner.Parent = disc
	local rim = Instance.new("UIStroke")
	rim.Color = GOLD
	rim.Thickness = 3
	rim.Parent = disc

	local initial = Instance.new("TextLabel")
	initial.Size = UDim2.fromScale(1, 1)
	initial.BackgroundTransparency = 1
	initial.Font = Enum.Font.GothamBold
	initial.TextSize = 22
	initial.TextColor3 = CREAM
	initial.Text = string.upper(string.sub((player and (player.DisplayName ~= "" and player.DisplayName or player.Name)) or "?", 1, 1))
	initial.ZIndex = 5
	initial.Parent = disc

	local image = Instance.new("ImageLabel")
	image.Name = "Headshot"
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.ScaleType = Enum.ScaleType.Crop
	image.Visible = false
	image.Active = false
	image.ZIndex = 6
	image.Parent = disc
	local imageCorner = Instance.new("UICorner")
	imageCorner.CornerRadius = UDim.new(0.5, 0)
	imageCorner.Parent = image

	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0, SIZE + 2)
	name.Size = UDim2.new(1, 0, 0, 17)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 15
	name.TextColor3 = Color3.fromRGB(60, 40, 22) -- dark ink on the parchment board
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = player and (player.DisplayName ~= "" and player.DisplayName or player.Name) or ""
	name.ZIndex = 5
	name.Parent = holder

	task.spawn(function()
		if not player then return end
		for attempt = 1, 2 do
			local ok, content, ready = pcall(function()
				return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and type(content) == "string" and content ~= "" and ready ~= false then
				image.Image = content
				image.Visible = true
				initial.Visible = false
				return
			end
			task.wait(0.5)
		end
		print("[Stage] headshot unavailable (Studio or offline); keeping the initial")
	end)

	return holder
end

return PlayerMedallion
