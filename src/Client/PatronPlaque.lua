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
		art.ImageColor3 = Color3.fromRGB(120, 110, 100)
		art.ImageTransparency = 0.35
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
	local emojiLabel = opts.emojiLabel
	task.defer(function()
		local waited = 0
		while art.Parent and not art.IsLoaded and waited < 12 do
			task.wait(0.25)
			waited += 0.25
		end
		if art.Parent and art.IsLoaded and emojiLabel then
			if art:IsDescendantOf(emojiLabel) then
				emojiLabel.TextTransparency = 1
				emojiLabel.TextStrokeTransparency = 1
			else
				emojiLabel.Visible = false
			end
		end
	end)
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
		-- Locked entries: still readable, just muted.
		art.ImageColor3 = Color3.fromRGB(120, 110, 100)
		art.ImageTransparency = 0.35
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

	local emojiLabel = opts.emojiLabel
	task.defer(function()
		local waited = 0
		while art.Parent and not art.IsLoaded and waited < 12 do
			task.wait(0.25)
			waited += 0.25
		end
		if art.Parent and art.IsLoaded and emojiLabel then
			if art:IsDescendantOf(emojiLabel) then
				-- The art lives inside the emoji label (Shop badge): hiding the
				-- label would hide the art too, so blank its text instead.
				emojiLabel.TextTransparency = 1
				emojiLabel.TextStrokeTransparency = 1
			else
				emojiLabel.Visible = false
			end
		end
	end)

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
			cornerRadius = 16,
		})
	end
end

return PatronPlaque
