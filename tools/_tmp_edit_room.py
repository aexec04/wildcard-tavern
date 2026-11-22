import os
os.chdir("/Users/ahmedahmed/Desktop/wildcard-tavern")
p = "src/Client/CardSetsRoom.lua"
s = open(p).read()
s = s.replace('''		b.BackgroundColor3 = GOLD
		b.BackgroundTransparency = opts.active and 0.7 or 1''', '''		b.BackgroundColor3 = opts.solid or GOLD
		b.BackgroundTransparency = opts.solid and 0 or (opts.active and 0.7 or 1)''')
s = s.replace('''		if opts.onClick then
			b.MouseEnter:Connect(function() if not opts.active then b.BackgroundTransparency = 0.82 end end)
			b.MouseLeave:Connect(function() b.BackgroundTransparency = opts.active and 0.7 or 1 end)''', '''		if opts.onClick then
			if not opts.solid then
				b.MouseEnter:Connect(function() if not opts.active then b.BackgroundTransparency = 0.82 end end)
				b.MouseLeave:Connect(function() b.BackgroundTransparency = opts.active and 0.7 or 1 end)
			end''')
s = s.replace('''			local pb = plateButton(holder, parts.preview, "Preview", { onClick = onPreview })
			pb.BackgroundTransparency = 0
			pb.BackgroundColor3 = BROWN
			pb.TextColor3 = CREAM''', '''			local pb = plateButton(holder, parts.preview, "Preview", { onClick = onPreview, solid = BROWN })
			pb.AutoButtonColor = true
			pb.TextColor3 = CREAM''')
s = s.replace('''		holder.Active = false
		holder.ZIndex = 43''', '''		holder.Active = true -- so its tooltip sees the pointer
		holder.ZIndex = 43''')
s = s.replace("			ctx.panelLimit(Layout.PANEL_MAX[1], Layout.PANEL_MAX[2])\n", "")
s = s.replace("			ctx.panelLimit(nil)\n", "")
s = s.replace("ctx = { panel, screenGui, roundCorner, playClickSfx, label, isOpen = fn, panelLimit, hide", "ctx = { panel, screenGui, roundCorner, playClickSfx, label, isOpen = fn, hide")
open(p, "w").write(s)

p = "src/Client/CosmeticSetsPanel.lua"
s = open(p).read()
old = '''	refresh = function()
		for _, child in ipairs(scroll:GetChildren()) do'''
assert old in s
s = s.replace(old, '''	-- the painted shelf wall (cardsets_room_a): a paged grid of framed slots; the plain scrolling list stays for small windows and a missing id
	local room = require(script.Parent.CardSetsRoom).new({
		panel = panel, screenGui = deps.screenGui, roundCorner = roundCorner, playClickSfx = playClickSfx, label = label,
		isOpen = function() return backdrop.Visible end, hide = { scroll },
		CosmeticSets = CosmeticSets, CardBacks = CardBacks, CardBackView = CardBackView, SetSkin = SetSkin,
		getState = deps.getLatestState, backHint = backUnlockHint,
		actions = {
			equipSet = function(id) EquipRemote:FireServer(id) end,
			buySet = function(id) BuyRemote:FireServer(id) end,
			equipBack = function(id) EquipBackRemote:FireServer(id) end,
			preview = function(name, setId, backId) startPreview(name, setId, backId) end,
		},
	})
	deps.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if backdrop.Visible and not previewActive then refresh() end
	end)

	refresh = function()
		if room.layout() then
			room.paint()
			return
		end
		for _, child in ipairs(scroll:GetChildren()) do''', 1)
open(p, "w").write(s)
print("ok")
