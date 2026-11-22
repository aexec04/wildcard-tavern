p = 'src/Client/Settings.lua'
s = open(p).read()

# 1. choice row: painted switch for On/Off rows, optional custom getter/setter (Calm mode)
s = s.replace('local function makeChoiceRow(key, labelText, description, choices)',
              'local function makeChoiceRow(key, labelText, description, choices, custom)')
s = s.replace('''		button.Size = UDim2.new(0, 110, 0, 34)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -4, 0.5, 0)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 14
		button.TextColor3 = TEXT
		button.ZIndex = 21
		button.Parent = row''', '''		local isSwitch = #choices == 2 and choices[1][1] == false
		button.Size = isSwitch and UDim2.new(0, SW.w, 0, SW.h) or UDim2.new(0, 110, 0, 44)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -4, 0.5, 0)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 16
		button.TextColor3 = TEXT
		button.ZIndex = 21
		button.Parent = row''')
s = s.replace('''		local function refresh()
			local current = ClientSettings.getRaw(key)
			for i, choice in ipairs(choices) do
				if choice[1] == current then
					button.Text = choice[2]
					button.BackgroundColor3 = (i == 1) and BUTTON or ON
					return
				end
			end
		end

		button.MouseButton1Click:Connect(function()
			playClickSfx()
			local current = ClientSettings.getRaw(key)
			local nextIndex = 1
			for i, choice in ipairs(choices) do
				if choice[1] == current then
					nextIndex = (i % #choices) + 1
				end
			end
			ClientSettings.set(key, choices[nextIndex][1])
		end)

		ClientSettings.onChanged(function(changedKey)
			if changedKey == key then
				refresh()
			end
		end)
		refresh()''', '''		local function getVal()
			if custom then return custom.get() end
			return ClientSettings.getRaw(key)
		end
		local function refresh()
			local current = getVal()
			for i, choice in ipairs(choices) do
				if choice[1] == current then
					button.Text = choice[2]
					if isSwitch then -- clear On and Off: fill plus the word
						local f = (i == 1) and SW.offFill or SW.onFill
						local t = (i == 1) and SW.offText or SW.onText
						button.BackgroundColor3 = Color3.fromRGB(f[1], f[2], f[3])
						button.TextColor3 = Color3.fromRGB(t[1], t[2], t[3])
					else
						button.BackgroundColor3 = (i == 1) and BUTTON or ON
					end
					return
				end
			end
		end

		button.MouseButton1Click:Connect(function()
			playClickSfx()
			local current = getVal()
			local nextIndex = 1
			for i, choice in ipairs(choices) do
				if choice[1] == current then
					nextIndex = (i % #choices) + 1
				end
			end
			if custom then
				custom.set(choices[nextIndex][1])
			else
				ClientSettings.set(key, choices[nextIndex][1])
			end
			refresh()
		end)

		ClientSettings.onChanged(function(changedKey)
			if changedKey == key or (custom and custom.keys[changedKey]) then
				refresh()
			end
		end)
		refresh()''')

# 2. reorder: Comfort, Sound, Help (replay rows), Display, Gameplay, Account
a = s.index('	-- ===== Display =====')
g = s.index('	-- ===== Gameplay =====')
r = s.index('	-- Replay Tutorial: the 24 step walkthrough again')
acc = s.index('	-- ===== Account =====')
display_block = s[a:g]
gameplay_block = s[g:r]
replay_block = s[r:acc]

# Display block: pull the comfort rows out, leave Animation Speed
comfort_keys = ['reduceShake', 'colorblindSuits', 'reduceFlashing', 'reduceMotion', 'largerText']
lines = display_block.split('\n')
keep, comfort = [], {}
i = 0
while i < len(lines):
    ln = lines[i]
    hit = [k for k in comfort_keys if ln.startswith('\tmakeChoiceRow("%s"' % k)]
    if hit:
        comfort[hit[0]] = ln
    else:
        keep.append(ln)
    i += 1
display_new = '\n'.join(keep)

comfort_block = '''	-- ===== Comfort (Calm mode and Reduce Motion are always the first two rows, Engine/SettingsLayout) =====
	makeHeader("Comfort")
	makeChoiceRow("calmMode", "Calm Mode", "Turns on Reduce Motion, Reduce Flashing and Reduce Screen Shake together.", OFF_ON, {
		keys = { reduceMotion = true, reduceFlashing = true, reduceShake = true },
		get = function()
			return SettingsLayout.calmValue({ reduceMotion = ClientSettings.getRaw("reduceMotion"), reduceFlashing = ClientSettings.getRaw("reduceFlashing"), reduceShake = ClientSettings.getRaw("reduceShake") })
		end,
		set = function(on)
			for k, v in pairs(SettingsLayout.calmWrites(on)) do ClientSettings.set(k, v) end
		end,
	})
''' + '\n'.join(comfort[k] for k in ['reduceMotion', 'reduceFlashing', 'reduceShake', 'largerText', 'colorblindSuits']) + '''

	-- ===== Sound =====
	makeHeader("Sound")
	do
		local row = Instance.new("Frame")
		row.Name = "VolumeRow"
		row.Size = UDim2.new(1, 0, 0, 62)
		row.LayoutOrder = order()
		row.BackgroundTransparency = 1
		row.ZIndex = 21
		row.Parent = scroll
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -130, 0, 22)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBold
		t.TextSize = 16
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextColor3 = TEXT
		t.Text = "Music and Sound Effects"
		t.ZIndex = 21
		t.Parent = row
		local b = Instance.new("TextLabel")
		b.Size = UDim2.new(1, -130, 0, 36)
		b.Position = UDim2.new(0, 0, 0, 22)
		b.BackgroundTransparency = 1
		b.Font = Enum.Font.Gotham
		b.TextSize = 14
		b.TextWrapped = true
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.TextYAlignment = Enum.TextYAlignment.Top
		b.TextColor3 = SUBTLE
		b.Text = "Sliders for music and effects, and Mute."
		b.ZIndex = 21
		b.Parent = row
		local go = Instance.new("TextButton")
		go.Name = "OpenVolume"
		go.Size = UDim2.new(0, 110, 0, 44)
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.new(1, -4, 0.5, 0)
		go.Font = Enum.Font.GothamBold
		go.TextSize = 16
		go.TextColor3 = TEXT
		go.BackgroundColor3 = BUTTON
		go.Text = "Volume"
		go.ZIndex = 21
		go.Parent = row
		polishButton(go, 8)
		addButtonHoverScale(go)
		go.MouseButton1Click:Connect(function()
			playClickSfx()
			settingsBackdrop.Visible = false
			pcall(OverlayManager.open, "volume")
		end)
	end

	-- ===== Help =====
	makeHeader("Help")
'''
s = s[:a] + comfort_block + '\n' + replay_block + '\n' + display_new + gameplay_block + s[acc:]

# 3. header names and constants
s = s.replace('local OFF_ON = { { false, "Off" }, { true, "On" } }\n', 'local OFF_ON = { { false, "Off" }, { true, "On" } }\n')
open(p, 'w').write(s)
print('ok')
