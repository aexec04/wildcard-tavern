--[[
	Client/PatronPlaque.lua
	Overlay a patron's uploaded art image on any frame that shows patron icons.
	Falls back silently to the existing emoji label when no art id exists for
	the patron, or when the image hasn't loaded -- same contract as SkinArt.

	PatronPlaque.apply(frame, patronId, opts) -> ImageLabel | nil
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
local PatronArt = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PatronArt"))

local GOLD = Color3.fromRGB(222, 182, 104)

local PatronPlaque = {}

function PatronPlaque.apply(frame, patronId, opts)
	opts = opts or {}
	if type(patronId) ~= "string" or patronId == "" then return nil end
	local artId = PatronArt[patronId]
	if type(artId) ~= "string" or artId == "" or artId == "rbxassetid://0" then return nil end

	local art = Instance.new("ImageLabel")
	art.Name = "PatronArt"
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
		while art.Parent and not art.IsLoaded do
			task.wait(0.25)
		end
		if art.Parent and art.IsLoaded and emojiLabel then
			emojiLabel.Visible = false
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
