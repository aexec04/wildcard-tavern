--[[
	Client/MenuPlayButton.lua
	The Menu's Deal Me In sign in the Concept T green button style: the wood plate and studs are hidden, the painted
	ct_btn_blank art sits behind the label, and a gentle UIScale pulse is added to `loops` (the hotspot loop list that
	startLoops plays and stopLoops cancels; startLoops plays nothing in Calm mode or Reduce Motion, so nothing tweens then).
	Click handling is untouched: the real button stays the click surface.
]]
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Art = require(Engine:WaitForChild("ConceptTArt"))

local MenuPlayButton = {}
MenuPlayButton.PULSE_SCALE = 1.05
MenuPlayButton.PULSE_SECONDS = 1.1

function MenuPlayButton.style(plaque, loops, TweenService)
	if plaque:FindFirstChild("ConceptTArt") then return end
	local id = Art.ct_btn_blank -- the text-free plate; ct_btn_play_a has "Play Hand" baked in
	if not id or id == "" then return end -- no art recorded: keep the wood plate
	plaque.BackgroundTransparency = 1
	local rim = plaque:FindFirstChild("Rim")
	if rim then rim.Enabled = false end
	for _, child in ipairs(plaque:GetChildren()) do
		if child.Name == "Stud" then child.Visible = false end
	end
	local art = Instance.new("ImageLabel")
	art.Name = "ConceptTArt"
	art.BackgroundTransparency = 1
	art.Size = UDim2.fromScale(1, 1)
	art.Image = id
	art.ScaleType = Enum.ScaleType.Stretch
	art.Active = false
	art.ZIndex = plaque.ZIndex
	art.Parent = plaque
	local title = plaque:FindFirstChild("Title")
	if title then
		title.ZIndex = plaque.ZIndex + 1
		title.TextColor3 = Color3.fromRGB(255, 248, 225)
		title.TextStrokeColor3 = Color3.fromRGB(30, 60, 20)
		title.TextStrokeTransparency = 0.2
		title.TextTransparency = 0
	end
	local scale = Instance.new("UIScale")
	scale.Name = "PulseScale"
	scale.Parent = plaque
	if loops and TweenService then
		table.insert(loops, TweenService:Create(scale, TweenInfo.new(MenuPlayButton.PULSE_SECONDS, Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut, -1, true), { Scale = MenuPlayButton.PULSE_SCALE }))
	end
end

return MenuPlayButton
