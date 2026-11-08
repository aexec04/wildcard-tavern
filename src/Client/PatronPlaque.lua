--[[
	Client/PatronPlaque.lua
	Overlay a patron's uploaded art image on any frame that shows patron icons.
	Falls back silently to the existing emoji label when no art id exists for
	the patron, or when the image hasn't loaded -- same contract as SkinArt.

	PatronPlaque.apply(frame, id, opts) -> ImageLabel | nil
			opts.category     -- "patrons" (default), "bosses", "recipes", "housePasses" or
			                  -- "titles": picks the generated id map (PatronArt, BossRoundArt,
			                  -- RecipeArt, HousePassArt, TitleArt). Same fallback everywhere.
			opts.dim          -- bool: muted look for locked Collection entries
		opts.emojiLabel   -- TextLabel to hide once the image loads (optional)
		opts.zIndex       -- default: frame.ZIndex + 1
		opts.cornerRadius -- pixel radius for UICorner, default 4; 0 = none
		opts.ring         -- bool: add a gold UIStroke ring (default false)
		opts.size         -- UDim2 (default UDim2.fromScale(1, 1))
		opts.position     -- UDim2 (default top-left)
		opts.anchor       -- Vector2 (default 0,0)

	PatronPlaque.updateSlot(slot, patronId)
		slot: { frame = Frame, label = TextLabel }
		Tracks the last-applied patron id on slot._ppLastId. Only swaps the
		art when the id actually changes, so render()-per-frame calls are cheap.
		Pass nil to clear art and restore the label.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local ART_MAPS = {
	patrons = require(Engine:WaitForChild("PatronArt")),
	bosses = require(Engine:WaitForChild("BossRoundArt")),
	recipes = require(Engine:WaitForChild("RecipeArt")),
	housePasses = require(Engine:WaitForChild("HousePassArt")),
	titles = require(Engine:WaitForChild("TitleArt")),
}

local GOLD = Color3.fromRGB(222, 182, 104)
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local LOAD_TIMEOUT = 8

-- Reveal `art` without a placeholder flash. Already loaded (cached/preloaded):
-- hide the emoji synchronously. Otherwise keep the art invisible AND the emoji
-- hidden until IsLoaded flips, then fade the art in. If the image has not
-- loaded after LOAD_TIMEOUT seconds or fails, restore the emoji so a broken id
-- never leaves a blank tile (a late load still swaps the art back in).
local function revealArt(art, emojiLabel)
	if not emojiLabel then
		if not art.IsLoaded then
			local target = art.ImageTransparency
			art.ImageTransparency = 1
			local conn
			conn = art:GetPropertyChangedSignal("IsLoaded"):Connect(function()
				if art.IsLoaded then
					conn:Disconnect()
					TweenService:Create(art, TweenInfo.new(0.12), { ImageTransparency = target }):Play()
				end
			end)
		end
		return
	end
	-- The art lives inside the emoji label (Shop badge): hiding the label would
	-- hide the art too, so blank its text instead.
	local inside = art:IsDescendantOf(emojiLabel)
	local origVisible = emojiLabel.Visible
	local origText, origStroke = emojiLabel.TextTransparency, emojiLabel.TextStrokeTransparency
	local function hideEmoji()
		if inside then
			emojiLabel.TextTransparency = 1
			emojiLabel.TextStrokeTransparency = 1
		else
			emojiLabel.Visible = false
		end
	end
	local function restoreEmoji()
		if inside then
			emojiLabel.TextTransparency = origText
			emojiLabel.TextStrokeTransparency = origStroke
		else
			emojiLabel.Visible = origVisible
		end
	end

	if art.IsLoaded then
		hideEmoji()
		return
	end

	local target = art.ImageTransparency
	art.ImageTransparency = 1
	hideEmoji()
	local shown = false
	local function onLoaded()
		if shown or not art.Parent then return end
		shown = true
		hideEmoji()
		art.Visible = true
		TweenService:Create(art, TweenInfo.new(0.12), { ImageTransparency = target }):Play()
	end
	art:GetPropertyChangedSignal("IsLoaded"):Connect(function()
		if art.IsLoaded then onLoaded() end
	end)
	-- giveUp must NOT hide the art: an invisible ImageLabel never loads, so a
	-- late load could never swap in. Keep it Visible (transparent), show emoji.
	local function giveUp()
		if shown or not art.Parent then return end
		restoreEmoji()
	end
	local preloadOk = false
	task.delay(LOAD_TIMEOUT, function()
		if not art.IsLoaded and not preloadOk then giveUp() end
	end)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ art }, function(_, status)
				if status == Enum.AssetFetchStatus.Success then
					preloadOk = true
					onLoaded()
				elseif status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
					giveUp()
				end
			end)
		end)
		if preloadOk or (art.Parent and art.IsLoaded) then onLoaded() end
	end)
end

local PatronPlaque = {}

-- Apply art given an explicit rbxassetid string. Used by callers that already
-- have the art id from ContentArt (not restricted to patron ids).
function PatronPlaque.applyById(frame, artId, opts)
	if type(artId) ~= "string" or artId == "" or artId == "rbxassetid://0" then return nil end
	opts = opts or {}
	local art = Instance.new("ImageLabel")
	art.Name = "ContentArt"
	art.BackgroundTransparency = 1
	art.BorderSizePixel = 0
	art.Active = false
	art.Image = artId
	art.ScaleType = Enum.ScaleType.Fit
	art.Size = opts.size or UDim2.fromScale(1, 1)
	art.Position = opts.position or UDim2.new(0, 0, 0, 0)
	art.AnchorPoint = opts.anchor or Vector2.new(0, 0)
	art.ZIndex = opts.zIndex or (frame.ZIndex + 1)
	art.ImageTransparency = 0
	if opts.dim then
		-- Locked: dimmed, never a black silhouette (colour multiply, no transparency).
		art.ImageColor3 = Color3.fromRGB(90, 90, 90)
	end
	local r = opts.cornerRadius
	if r == nil then r = 4 end
	if r > 0 then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, r)
		corner.Parent = art
	end
	if opts.ring then
		local ring = Instance.new("UIStroke")
		ring.Color = GOLD
		ring.Thickness = 2
		ring.Transparency = 0.15
		ring.Parent = art
	end
	art.Parent = frame
	revealArt(art, opts.emojiLabel)
	return art
end

function PatronPlaque.apply(frame, patronId, opts)
	opts = opts or {}
	if type(patronId) ~= "string" or patronId == "" then return nil end
	local category = opts.category or "patrons"
	local map = ART_MAPS[category]
	local artId = map and map[patronId]
	if type(artId) ~= "string" or artId == "" or artId == "rbxassetid://0" then return nil end

	local art = Instance.new("ImageLabel")
	art.Name = category == "patrons" and "PatronArt" or "EntryArt"
	art.BackgroundTransparency = 1
	art.BorderSizePixel = 0
	art.Active = false
	art.Image = artId
	art.ScaleType = Enum.ScaleType.Fit
	art.Size = opts.size or UDim2.fromScale(1, 1)
	art.Position = opts.position or UDim2.new(0, 0, 0, 0)
	art.AnchorPoint = opts.anchor or Vector2.new(0, 0)
	art.ZIndex = opts.zIndex or (frame.ZIndex + 1)
	art.ImageTransparency = 0
	if opts.dim then
		-- Locked: dimmed, never a black silhouette (colour multiply, no transparency).
		art.ImageColor3 = Color3.fromRGB(90, 90, 90)
	end

	local r = opts.cornerRadius
	if r == nil then r = 4 end
	if r > 0 then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, r)
		corner.Parent = art
	end

	if opts.ring then
		local ring = Instance.new("UIStroke")
		ring.Color = GOLD
		ring.Thickness = 2
		ring.Transparency = 0.15
		ring.Parent = art
	end

	art.Parent = frame

	revealArt(art, opts.emojiLabel)

	return art
end

-- Manage art for a sidebar-style patron slot across render()-per-frame calls.
-- slot must have .frame (the round seat frame) and .label (the emoji/letter label).
-- Only tears down and recreates the ImageLabel when patronId actually changes.
function PatronPlaque.updateSlot(slot, patronId)
	if slot._ppLastId == patronId then return end
	slot._ppLastId = patronId
	local existing = slot.frame:FindFirstChild("PatronArt")
	if existing then existing:Destroy() end
	slot.label.Visible = true
	if patronId then
		PatronPlaque.apply(slot.frame, patronId, {
			emojiLabel = slot.label,
			zIndex = slot.frame.ZIndex + 1,
			cornerRadius = math.floor(slot.frame.Size.X.Offset / 2) > 0 and math.floor(slot.frame.Size.X.Offset / 2) or 16,
		})
	end
end

return PatronPlaque
