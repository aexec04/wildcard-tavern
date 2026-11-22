--[[
	Client/DealFlip.lua
	Cosmetic deal flip: a newly dealt card briefly shows the equipped card back, then flips to its face.
	The overlay is a non-interactive child of the card button (Active=false, destroyed after the flip).
	It never changes the button's own properties, input, selection or hand state.
	Skipped when Animation Speed is Fast.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local CardBacks = require(Engine:WaitForChild("CardBacks"))
local ClientSettings = require(script.Parent.ClientSettings)
local CardBackView = require(script.Parent.CardBackView)

local FLIP_TIME = 0.15-- seconds to close the back
local STAGGER = 0.04 -- extra delay per card
local FLY_TIME = 0.24 -- the existing deal tween; the flip starts once the card has landed

local M = {}

-- button: the freshly built card TextButton; order: 1-based position among dealt cards.
function M.play(button, order, backId)
	if ClientSettings.get("animSpeed") == "fast" then
		return
	end
	backId = backId or CardBacks.DefaultId
	if (order or 1) == 1 then require(script.Parent.Cue).play("card_deal") end -- once per batch
	local back = CardBacks.getById(backId) or CardBacks.getById(CardBacks.DefaultId)
	local base = back and back.colors and back.colors.base or { 50, 70, 110 }

	local overlay = Instance.new("Frame")
	overlay.Name = "DealBack"
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 50
	overlay.Active = false
	overlay.BorderSizePixel = 0
	overlay.BackgroundColor3 = Color3.fromRGB(base[1], base[2], base[3])
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = overlay

	local image = CardBackView.imageFor(backId)
	if image then
		local art = Instance.new("ImageLabel")
		art.Size = UDim2.fromScale(1, 1)
		art.BackgroundTransparency = 1
		art.Image = image
		art.ScaleType = Enum.ScaleType.Crop
		art.Active = false
		art.ZIndex = 51
		local artCorner = Instance.new("UICorner")
		artCorner.CornerRadius = UDim.new(0, 8)
		artCorner.Parent = art
		art.Parent = overlay
	end
	overlay.Parent = button

	task.delay(FLY_TIME + (order - 1) * STAGGER, function()
		if not overlay.Parent then
			return
		end
		if (order or 1) == 1 then require(script.Parent.Cue).play("card_flip") end -- once per batch
		local tween = TweenService:Create(overlay, TweenInfo.new(FLIP_TIME, Enum.EasingStyle.Sine), { Size = UDim2.fromScale(0, 1) })
		tween.Completed:Once(function()
			overlay:Destroy()
		end)
		tween:Play()
	end)
end

return M
