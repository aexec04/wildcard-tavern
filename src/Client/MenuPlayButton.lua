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
local Life = require(Engine:WaitForChild("MenuLife"))
MenuPlayButton.PULSE_SCALE = Life.PULSE_SCALE -- 1.0 to 1.03 and back every 2.5 s
MenuPlayButton.PULSE_SECONDS = Life.PULSE_PERIOD / 2

function MenuPlayButton.style(plaque, loops, TweenService)
	if plaque:FindFirstChild("ConceptTArt") then return end
	local id = Art.ct_btn_blank -- the text-free plate; ct_btn_play_a has "Play Hand" baked in
	-- first choice: the lit ornate green button every other screen uses (sibling picture, so it gets its own pulse scale below)
	-- the equipped Card Set's own green plate first (same family as the table buttons); classic and plateless sets keep the ornate green below
	local Kit = require(script.Parent.TavernKit)
	local okSet, drawn = pcall(function() return Kit.setPlateButton(plaque, "primary") end)
	local setDrawn = okSet and drawn == true
	local okKit, ornate = false, nil
	if not setDrawn then okKit, ornate = pcall(function() return Kit.paintedButton(plaque, "primary") end) end
	if not okKit or not ornate then ornate = nil end
	if not ornate and not setDrawn and (not id or id == "") then return end -- no art at all: keep the wood plate
	plaque.BackgroundTransparency = 1
	local rim = plaque:FindFirstChild("Rim")
	if rim then rim.Enabled = false end
	for _, child in ipairs(plaque:GetChildren()) do
		if child.Name == "Stud" then child.Visible = false end
	end
	local art = Instance.new("ImageLabel")
	art.Name = "ConceptTArt"
	if ornate or setDrawn then art.Visible = false end -- marker only; the ornate picture is the plate
	art.BackgroundTransparency = 1
	art.Size = UDim2.fromScale(1, 1)
	art.Image = id or ""
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
	if ornate then
		local s2 = Instance.new("UIScale"); s2.Name = "PulseScale"; s2.Parent = ornate
		if loops and TweenService then
			table.insert(loops, TweenService:Create(s2, TweenInfo.new(MenuPlayButton.PULSE_SECONDS, Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut, -1, true), { Scale = MenuPlayButton.PULSE_SCALE }))
		end
	end
	if loops and TweenService then
		table.insert(loops, TweenService:Create(scale, TweenInfo.new(MenuPlayButton.PULSE_SECONDS, Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut, -1, true), { Scale = MenuPlayButton.PULSE_SCALE }))
	end
end

return MenuPlayButton
