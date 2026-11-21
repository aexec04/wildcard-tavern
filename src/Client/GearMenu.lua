--[[
	Client/GearMenu.lua
	The one Settings icon at the top right of the table, the Counter and the Night map, and the toggle menu it drops down (numbers and
	rules in Engine/GearMenu, tested). Toggles write the real settings through ClientSettings; Pause, How to play and Quit to Tavern
	open the existing overlays through OverlayManager, so no backend is duplicated. Built from TavernKit helpers, so the painted UI
	kit can restyle it later. Calm mode and Reduce motion: the menu appears at once, no tween.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local G = require(Engine:WaitForChild("GearMenu"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local Art = require(Engine:WaitForChild("ConceptTArt"))
local Kit = require(script.Parent.TavernKit)
local ClientSettings = require(script.Parent.ClientSettings)
local OverlayManager = require(script.Parent.OverlayManager)
local ButtonLabelTop = require(script.Parent.ButtonLabelTop)

local M = {}

local Z = 900 -- above the table, the Counter and the Night map, under every popup (popups start at 5000)

local function rgb(name) local c = Style.rgb(name); return Color3.fromRGB(c[1], c[2], c[3]) end

local function settingsNow()
	local out = {}
	for _, k in ipairs({ "muted", "sfxVolume", "musicVolume", "reduceMotion", "reduceFlashing", "reduceShake", "roundHints" }) do out[k] = ClientSettings.getRaw(k) end
	return out
end

local function calm()
	return Kit.still()
end

function M.install(deps)
	local root = deps.root
	local existing = root:FindFirstChild("GearMenu")
	if existing then return existing end
	local host = Instance.new("Frame")
	host.Name = "GearMenu"
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Size = UDim2.fromScale(1, 1)
	host.ZIndex = Z
	host.Active = false
	host.Parent = root

	-- tap outside: a see-through catcher behind the menu, only while it is open
	local catcher = Instance.new("TextButton")
	catcher.Name = "OutsideCatcher"
	catcher.BackgroundTransparency = 1
	catcher.BorderSizePixel = 0
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.ZIndex = Z
	catcher.Visible = false
	catcher.Parent = host

	local gear = Instance.new("TextButton")
	gear.Name = "GearButton"
	gear.AutoButtonColor = false
	gear.Text = ""
	gear.BackgroundColor3 = rgb("brown")
	gear.BorderSizePixel = 0
	gear.ZIndex = Z + 1
	gear.Parent = host
	local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0.5, 0); gc.Parent = gear
	local gs = Instance.new("UIStroke"); gs.Color = rgb("goldTrim"); gs.Thickness = 2; gs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; gs.Parent = gear
	pcall(function() Kit.painted(gear, "icon_round") end) -- the painted round frame (the flat gold ringed disc stays if it is missing)
	local icon = Instance.new("ImageLabel")
	icon.Name = "GearIcon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(0.72, 0.72)
	icon.Position = UDim2.fromScale(0.14, 0.14)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = Art.ct_hud_gear or ""
	icon.ZIndex = Z + 2
	icon.Parent = gear
	if icon.Image == "" then -- no art id: the word stands in (ASCII only)
		local word = ButtonLabelTop.own(gear, "Menu", 14, Z + 2, rgb("cream"))
		word.Size = UDim2.fromScale(1, 1)
	end

	-- speaker (Sound toggle) and Settings round buttons left of the gear: the same actions as the menu rows
	local PaintedArt = require(Engine:WaitForChild("PaintedKitArt"))
	local quick = {}
	for _, q in ipairs({ { "speaker", "pk_w_icon_speaker", "Sound" }, { "pause", "ct_hud_gear", "Settings" } }) do
		local b = Instance.new("TextButton")
		b.Name = "Quick_" .. q[1]
		b.AutoButtonColor = false
		b.Text = ""
		b.BackgroundColor3 = rgb("brown")
		b.BorderSizePixel = 0
		b.ZIndex = Z + 1
		b.Parent = host
		local qc = Instance.new("UICorner"); qc.CornerRadius = UDim.new(0.5, 0); qc.Parent = b
		local qs = Instance.new("UIStroke"); qs.Color = rgb("goldTrim"); qs.Thickness = 2; qs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; qs.Parent = b
		pcall(function() Kit.painted(b, "icon_round") end)
		local qi = Instance.new("ImageLabel")
		qi.Name = "Icon"
		qi.BackgroundTransparency = 1
		qi.Size = UDim2.fromScale(0.62, 0.62)
		qi.Position = UDim2.fromScale(0.19, 0.19)
		qi.ScaleType = Enum.ScaleType.Fit
		qi.Image = PaintedArt[q[2]] or Art[q[2]] or ""
		qi.ZIndex = Z + 2
		qi.Parent = b
		if qi.Image == "" then -- no art id: the word stands in (ASCII only)
			local word = ButtonLabelTop.own(b, q[3], 12, Z + 2, rgb("cream"))
			word.Size = UDim2.fromScale(1, 1)
		end
		quick[q[1]] = b
	end

	local menu = Instance.new("Frame")
	menu.Name = "Menu"
	menu.BackgroundColor3 = rgb("plateDark")
	menu.BorderSizePixel = 0
	menu.ZIndex = Z + 1
	menu.Visible = false
	menu.Active = true
	menu.ClipsDescendants = true
	menu.Parent = host
	local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0, 10); mc.Parent = menu
	local ms = Instance.new("UIStroke"); ms.Color = rgb("goldTrim"); ms.Thickness = 2; ms.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ms.Parent = menu
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollBarThickness = 4
	scroll.ZIndex = Z + 1
	scroll.CanvasSize = UDim2.fromOffset(0, G.contentHeight())
	scroll.Parent = menu

	local rows = {}
	for _, def in ipairs(G.ROWS) do
		local b = Kit.secondaryButton(scroll, def.label)
		b.Name = "Row_" .. def.id
		b.ZIndex = Z + 2
		pcall(Kit.paintedButton, b, "secondary") -- same ornate dark plate as every other screen (flat brown if the picture does not load)
		local label = ButtonLabelTop.own(b, def.label, Style.TEXT.button, Z + 4, rgb("cream"))
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Size = UDim2.new(1, -78, 1, 0)
		label.Position = UDim2.fromOffset(12, 0)
		local pill
		if def.kind == "toggle" then
			pill = Instance.new("Frame")
			pill.Name = "StatePill"
			pill.AnchorPoint = Vector2.new(1, 0.5)
			pill.Position = UDim2.new(1, -8, 0.5, 0)
			pill.Size = UDim2.fromOffset(56, 26)
			pill.BorderSizePixel = 0
			pill.ZIndex = Z + 3
			local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 13); pc.Parent = pill
			local word = Instance.new("TextLabel")
			word.Name = "Word"
			word.BackgroundTransparency = 1
			word.Size = UDim2.fromScale(1, 1)
			word.Font = Enum.Font[Style.FONTS.ui]
			word.TextSize = Style.TEXT.min
			word.TextColor3 = Color3.new(1, 1, 1)
			word.TextTransparency = 0
			word.TextStrokeTransparency = 0.3
			word.ZIndex = Z + 5
			word.Parent = pill
			pill.Parent = b
		end
		rows[def.id] = { button = b, label = label, pill = pill, def = def }
	end

	local isOpen = false
	local size = Vector2.new(1280, 720)

	local function paint()
		local v = G.view(settingsNow())
		for id, r in pairs(rows) do
			local s = v[id]
			if r.pill and s then
				r.pill.BackgroundColor3 = s.on and Color3.fromRGB(46, 112, 56) or Color3.fromRGB(58, 44, 34) -- green On, dark Off; the word is the real signal
				r.pill.Word.Text = s.state
			end
		end
	end

	local function layout()
		size = host.AbsoluteSize
		local gr = G.gearRect(size.X, size.Y)
		gear.Position = UDim2.fromOffset(gr.x, gr.y)
		gear.Size = UDim2.fromOffset(gr.w, gr.h)
		local qr = G.quickRects(size.X, size.Y)
		for k, b in pairs(quick) do
			b.Position = UDim2.fromOffset(qr[k].x, qr[k].y)
			b.Size = UDim2.fromOffset(qr[k].w, qr[k].h)
		end
		local mr = G.menuRect(size.X, size.Y)
		menu.Position = UDim2.fromOffset(mr.x, mr.y)
		menu.Size = UDim2.fromOffset(mr.w, mr.h)
		scroll.ScrollingEnabled = mr.scroll
		scroll.CanvasSize = UDim2.fromOffset(0, mr.contentH)
		for i, rr in ipairs(G.rowRects(mr)) do
			local r = rows[rr.id]
			r.button.Position = UDim2.fromOffset(rr.x, rr.y)
			r.button.Size = UDim2.fromOffset(rr.w - (mr.scroll and 6 or 0), rr.h)
		end
	end

	local slideToken = 0
	local function setOpen(open)
		if open == isOpen then return end
		isOpen = open
		slideToken = slideToken + 1
		catcher.Visible = open
		if open then
			layout(); paint()
			menu.Visible = true
			local mr = G.menuRect(size.X, size.Y)
			local d = G.duration(calm())
			if d > 0 then
				menu.Size = UDim2.fromOffset(mr.w, 0)
				local token = slideToken
				TweenService:Create(menu, TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(mr.w, mr.h) }):Play()
				task.delay(d + 0.05, function() if token == slideToken and isOpen then menu.Size = UDim2.fromOffset(mr.w, mr.h) end end)
			end
		else
			menu.Visible = false
		end
	end
	M.setOpen = setOpen

	gear.MouseButton1Click:Connect(function()
		pcall(function() require(script.Parent.Cue).play("button_click") end)
		OverlayManager.closeAllExcept("gear-menu")
		setOpen(not isOpen)
	end)
	catcher.MouseButton1Click:Connect(function() setOpen(false) end)
	OverlayManager.register("gear-menu", function() setOpen(false) end) -- one menu at a time: any other overlay closes it
	-- Escape and the click outside both go through PopupDismiss (the one place that handles Escape); the catcher is the dark area
	pcall(function() require(script.Parent.PopupDismiss).attach(catcher, { id = "gear-menu", panel = menu, close = function() setOpen(false) end, button = false }) end)

	quick.speaker.MouseButton1Click:Connect(function()
		pcall(function() require(script.Parent.Cue).play("button_click") end)
		for k, val in pairs(G.writes("sound", settingsNow())) do ClientSettings.set(k, val) end
		if isOpen then paint() end
	end)
	quick.pause.MouseButton1Click:Connect(function()
		pcall(function() require(script.Parent.Cue).play("button_click") end)
		setOpen(false)
		OverlayManager.open("settings") -- the same call as the menu's Settings row
	end)

	local function act(id)
		pcall(function() require(script.Parent.Cue).play("button_click") end)
		if rows[id].def.kind == "toggle" then
			for k, val in pairs(G.writes(id, settingsNow())) do ClientSettings.set(k, val) end
			paint()
			return
		end
		setOpen(false)
		if id == "settings" then OverlayManager.open("settings")
		elseif id == "howTo" then OverlayManager.open("howToPlay")
		elseif id == "quit" then OverlayManager.open("quitToTavern") end
	end
	for id, r in pairs(rows) do
		r.button.MouseButton1Click:Connect(function() act(id) end)
	end
	ClientSettings.onChanged(function() if isOpen then pcall(paint) end end)

	-- shown on the table, the Counter and the Night map only; a popup above it hides it (and closes the menu)
	local function visibleNow()
		local function shown(n) local f = root:FindFirstChild(n); return f ~= nil and f:IsA("GuiObject") and f.Visible end
		local table2 = false
		local gp = root:FindFirstChild("Gameplay2")
		if gp and gp.Visible then table2 = true end
		return G.visibleOn({ root = root.Visible, table = table2, counter = shown("Shop"), map = shown("RoundSelect") })
	end
	host:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if isOpen then layout() end end)
	layout()
	task.spawn(function()
		while host.Parent do
			local want = visibleNow()
			if gear.Visible ~= want then gear.Visible = want; for _, b in pairs(quick) do b.Visible = want end end
			if not want and isOpen then setOpen(false) end
			if want then
				local abs = host.AbsoluteSize
				if abs ~= size then layout() end
			end
			task.wait(0.25)
		end
	end)
	gear.Visible = false
	for _, b in pairs(quick) do b.Visible = false end
	return host
end

return M
