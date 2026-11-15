-- Combo counter: "COMBO x3" pops beside the score popup when hands keep scoring in a round. VISUAL ONLY: it never
-- changes a score (rules in Engine/ScoreFeel). One label is created once and reused for every hand, so scoring a
-- hand allocates nothing here. The combo resets when a round starts or a hand scores nothing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ScoreFeel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ScoreFeel"))
local ClientSettings = require(script.Parent.ClientSettings)

local ComboCounter = {}

local label, scale
local combo = 0
local token = 0
local activeTween
local place = nil -- { side = "left" | "right", edge, y, limit } in screen pixels: where the played cards are (stand)

function ComboCounter.init(screenGui)
	label = Instance.new("TextLabel")
	label.Name = "ComboCounter"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.3, 0)
	label.Size = UDim2.fromOffset(300, 48)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 32
	label.TextColor3 = Color3.fromRGB(255, 214, 90)
	label.TextStrokeColor3 = Color3.fromRGB(60, 36, 12)
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	label.Visible = false
	label.Active = false
	label.ZIndex = 110
	label.Parent = screenGui
	scale = Instance.new("UIScale")
	scale.Parent = label
end

-- The score popup says where the played cards are (Client/ScorePopup layoutPlayedRow). The shout stands on the felt
-- beside them, on the side the score readout did not take, level with the middle of the row.
function ComboCounter.stand(spec)
	place = spec
end

local function hide(mine)
	if mine ~= token or not label then
		return
	end
	label.TextTransparency, label.TextStrokeTransparency = 1, 1
	label.Visible = false
end

-- Call once per played hand, at its finale. `score` is the hand's score; `firstHandOfRound` is true for the first
-- hand of a round (roundScoreBefore == 0).
function ComboCounter.hand(score, firstHandOfRound)
	combo = ScoreFeel.nextCombo(combo, score, firstHandOfRound)
	local text = ScoreFeel.comboText(combo)
	if not label or not text then
		return
	end
	token += 1
	local mine = token
	if activeTween then
		activeTween:Cancel()
	end
	label.Text = text
	label.Visible = true
	label.TextTransparency, label.TextStrokeTransparency = 0, 0.3
	local target = ScoreFeel.comboScale(combo)
	if place then
		local left = place.side ~= "right"
		label.AnchorPoint = Vector2.new(left and 1 or 0, 0.5) -- it grows away from the cards, never over them
		label.TextXAlignment = left and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(place.edge + (left and -ScoreFeel.COMBO_AIR or ScoreFeel.COMBO_AIR), place.y)
		target = ScoreFeel.comboFit(place.edge, place.limit, target)
	end
	if ClientSettings.get("animSpeed") == "fast" or ClientSettings.get("reduceShake") == true then
		scale.Scale = target
	else
		scale.Scale = target * 0.6
		activeTween = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = target })
		activeTween:Play()
	end
	task.delay(1.3, function()
		if mine == token and label then
			TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.35, hide, mine)
		end
	end)
end

function ComboCounter.reset()
	combo = 0
	token += 1
	if label then
		label.Visible = false
	end
end

return ComboCounter
