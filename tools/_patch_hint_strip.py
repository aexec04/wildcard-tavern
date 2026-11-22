p = 'src/Shared/Engine/RoundHints.lua'
s = open(p).read()
a = 'function M.place(r, viewW, viewH, avoid)\n'
assert a in s
new = '''-- The slim strip: one 60 px plate centred above the hand fan with the Got it plate inside it on the right (the concept shows nothing at the
-- left of the table). 520 wide at 1920 and scaled with the screen (never under 360); it ends STRIP_GAP above the hand rect and may stand
-- over the idle stage's progress line, but never over a Patron seat or the avoid rects. nil when it does not fit.
M.STRIP_W, M.STRIP_H, M.STRIP_MIN_W, M.STRIP_GAP, M.STRIP_PAD = 520, 60, 360, 6, 8
M.STRIP_TITLE, M.STRIP_BODY = 22, 16
function M.strip(r, viewW, viewH, avoid)
	if type(r) ~= "table" or not r.hand or not r.slots or not r.slots[1] then return nil end
	local w = math.min(M.STRIP_W, math.max(M.STRIP_MIN_W, math.floor(M.STRIP_W / 1920 * viewW + 0.5)))
	local plate = { x = math.floor((viewW - w) / 2), y = r.hand.y - M.STRIP_GAP - M.STRIP_H, w = w, h = M.STRIP_H }
	local bh = M.BUTTON_H
	local button = { x = plate.x + w - M.STRIP_PAD - M.BUTTON_W, y = plate.y + math.floor((M.STRIP_H - bh) / 2), w = M.BUTTON_W, h = bh }
	if plate.x < 0 or plate.y < 0 or plate.x + w > viewW or plate.y + plate.h > viewH then return nil end
	for _, s in ipairs(r.slots) do
		for _, part in ipairs({ s.card, s.label, s.pill }) do
			if part and hit(plate, part) then return nil end
		end
	end
	for _, a in ipairs(avoid or {}) do
		if hit(plate, a) then return nil end
	end
	return { plate = plate, button = button, kind = "strip", textW = w - 3 * M.STRIP_PAD - M.BUTTON_W }
end

function M.place(r, viewW, viewH, avoid)
	local strip = M.strip(r, viewW, viewH, avoid)
	if strip then return strip end
'''
s = s.replace(a, new, 1)
open(p, 'w').write(s)

p = 'src/Client/RoundHintsFX.lua'
s = open(p).read()
a = '\ttitle.Text, body.Text = entry.title, entry.body\n\tplate.Visible = true\n'
assert a in s
s = s.replace(a, '''	title.Text, body.Text = entry.title, entry.body
	local strip = spot.kind == "strip"
	local paint = layer:FindFirstChild(plate.Name .. "Paint")
	if strip then -- the slim strip is a flat plate: the crown picture is the wrong shape for it
		if paint then paint:Destroy() end
		plate.BackgroundTransparency = 0.05
		for _, d in ipairs(plate:GetChildren()) do if d:IsA("UIStroke") then d.Enabled = true end end
		title.Position = UDim2.fromOffset(Rules.STRIP_PAD + 4, 6); title.Size = UDim2.fromOffset(spot.textW, 26); title.TextSize = Rules.STRIP_TITLE
		body.Position = UDim2.fromOffset(Rules.STRIP_PAD + 4, 33); body.Size = UDim2.fromOffset(spot.textW, 22); body.TextSize = Rules.STRIP_BODY
		body.TextWrapped = false; title.TextWrapped = false
	else
		if not paint then pcall(function() require(script.Parent.TavernKit).painted(plate, "wh_hint") end) end
		title.Position = UDim2.new(0.31, 0, 0, 14); title.Size = UDim2.new(0.62, 0, 0, 22); title.TextSize = 18
		body.Position = UDim2.new(0.31, 0, 0, 38); body.Size = UDim2.new(0.62, 0, 0, 36); body.TextSize = 15
		body.TextWrapped = true; title.TextWrapped = true
	end
	plate.Visible = true
''')
a = '\tbutton.Position = UDim2.fromOffset(spot.button.x, spot.button.y)\nend'
assert a in s
s = s.replace(a, '''	button.Position = UDim2.fromOffset(spot.button.x, spot.button.y)
	if game:GetService("RunService"):IsStudio() and M.lastKey ~= viewW .. "x" .. viewH .. spot.kind then
		M.lastKey = viewW .. "x" .. viewH .. spot.kind
		print(("[HintRects] %s plate=%d,%d,%d,%d button=%d,%d,%d,%d"):format(spot.kind, spot.plate.x, spot.plate.y, spot.plate.w, spot.plate.h, spot.button.x, spot.button.y, spot.button.w, spot.button.h))
	end
end''')
open(p, 'w').write(s)
