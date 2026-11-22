def sub(path, old, new, count=1):
    s = open(path).read()
    assert old in s, (path, old[:60])
    s = s.replace(old, new, count)
    open(path, 'w').write(s)

# (21) guided hint pulse on FxLoop instead of its own infinite tween
p = 'src/Client/GuidedHint.lua'
s = open(p).read()
i = s.index("		if hint.pulse and outlineOn ~= target then")
j = s.index("		elseif not hint.pulse then")
s = s[:i] + '''		if hint.pulse and outlineOn ~= target then
			outlineOn = target
			outline.Transparency = 0
			if pulseLoop then pulseLoop.cancel() end
			local t0 = os.clock()
			pulseLoop = FxLoop.add(function()
				if not outline or outline.Parent == nil or not outline.Enabled then pulseLoop = nil; return true end
				outline.Transparency = 0.3 + 0.3 * math.sin((os.clock() - t0) * math.pi / 0.7) -- 0 to 0.6 over 1.4 s, on the one loop
			end, 0.05)
''' + s[j:]
s = s.replace("local skipped = false", "local pulseLoop\nlocal skipped = false", 1)
s = s.replace("local ClientSettings = require(script.Parent.ClientSettings)", "local ClientSettings = require(script.Parent.ClientSettings)\nlocal FxLoop = require(script.Parent.FxLoop)", 1)
s = s.replace("		elseif not hint.pulse then\n			outlineOn = nil", "		elseif not hint.pulse then\n			outlineOn = nil\n			if pulseLoop then pulseLoop.cancel(); pulseLoop = nil end", 1)
s = s.replace("	if outline then outline.Enabled = false; outline.Parent = nil end", "	if pulseLoop then pulseLoop.cancel(); pulseLoop = nil end\n	outlineOn = nil\n	if outline then outline.Enabled = false; outline.Parent = nil end", 1)
open(p, 'w').write(s)

# (21) AuditV2 prints the live GuiObject count
p = 'src/Client/AuditV2.lua'
sub(p, '''	print(string.format("[AuditV2] %d warning(s) across %d sizes", total, #sizes))''', '''	pcall(function() -- live GuiObject count under the limit (Engine/Gameplay2Perf); run it at round start and again during scoring
		local Perf = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Gameplay2Perf"))
		local pg = game:GetService("Players").LocalPlayer.PlayerGui
		local all, shown = Perf.count(pg, false), Perf.count(pg, true)
		local v = Perf.verdict(shown)
		local line = string.format("[AuditV2] GuiObjects: %d in the tree, %d on screen (limit %d, %s)", all, shown, Perf.LIMIT, v)
		if v == "ok" then print(line) else warn(line) end
	end)
	print(string.format("[AuditV2] %d warning(s) across %d sizes", total, #sizes))''')

# (23) sound: boss entrance cue (silent while boss_intro has no id) and the tooltip hover cue
p = 'src/Client/Gameplay2MomentsFX.lua'
sub(p, '''		banner:SetAttribute("EntranceKey", key)
''', '''		banner:SetAttribute("EntranceKey", key)
		pcall(function() require(script.Parent.Cue).play("boss_intro") end) -- silent until the cue has an id
''')
p = 'src/Client/PatronTipFX.lua'
sub(p, '''	local mine = token
	task.delay(Tip.DELAY, function()
		if mine == token and root.Parent then render(root, cards, index, info, calm, true) end''', '''	local mine = token
	task.delay(Tip.DELAY, function()
		if mine == token and root.Parent then
			render(root, cards, index, info, calm, true)
			pcall(function() require(script.Parent.Cue).play("hover") end) -- the soft hover tick, behind the cue cooldown
		end''')
p = 'src/Shared/Engine/Gameplay2Sound.lua'
sub(p, '''	{ moment = "nothing selected",''', '''	{ moment = "Patron tooltip", cue = "hover", file = "src/Client/PatronTipFX.lua", marker = '"hover"' },
	{ moment = "shop buy", cue = "shop_buy", file = "src/Client/ShopScene.lua", marker = '"shop_buy"' },
	{ moment = "nothing selected",''')
sub(p, '''M.SLIDER_STEPS''', '''-- cues that may stay silent until an id is pasted in (SoundFX.EMPTY_OK); the call site must still exist
M.SILENT_OK = {
	{ moment = "boss entrance", cue = "boss_intro", file = "src/Client/Gameplay2MomentsFX.lua", marker = '"boss_intro"' },
}

M.SLIDER_STEPS''')

# tests
p = 'src/Shared/Tests/EngineTests.lua'
s = open(p).read()
marker = 'table.insert(tests, { name = "Gameplay v2 quick controls:'
assert marker in s
test = '''table.insert(tests, { name = "Gameplay v2 pass 21 to 23: GuiObject count under 1,500, every table effect on FxLoop, text 12 px or more, silent cues keep their call site", fn = function()
	local P = require(script.Parent.Parent.Engine.Gameplay2Perf)
	local G = require(script.Parent.Parent.Engine.Gameplay2Sound)
	local S = require(script.Parent.Parent.Engine.SoundIds)
	local FX = require(script.Parent.Parent.Engine.SoundFX)
	assert(P.LIMIT == 1500 and P.verdict(100) == "ok" and P.verdict(1200) == "warn" and P.verdict(1500) == "over")
	local tree = { Children = { { ClassName = "Frame", Visible = true, Children = { { ClassName = "TextLabel", Visible = true, Children = {} }, { ClassName = "UICorner", Children = {} } } },
		{ ClassName = "Frame", Visible = false, Children = { { ClassName = "TextLabel", Visible = true, Children = {} } } } } }
	assert(P.count(tree, false) == 4 and P.count(tree, true) == 3, "invisible branches are not counted on screen")
	for _, m in ipairs(G.SILENT_OK) do
		assert(S.Cues[m.cue] and FX.EMPTY_OK[m.cue], m.moment .. ": a real cue that is allowed to stay silent")
	end
	if not io then return end
	local function read(path) local f = assert(io.open(path, "r")); local c = f:read("a"); f:close(); return c end
	for _, m in ipairs(G.SILENT_OK) do assert(read(m.file):find(m.marker, 1, true), m.moment .. ": call site") end
	for _, path in ipairs(P.LOOP_FILES) do
		local src = read(path)
		local bad = P.forbiddenLoop(src)
		assert(not bad, path .. " starts a repeating effect outside FxLoop: " .. tostring(bad))
		for size in src:gmatch("TextSize = (%d+)") do assert(tonumber(size) >= P.MIN_TEXT, path .. ": text under 12 px") end
	end
	assert(read("src/Client/GuidedHint.lua"):find("FxLoop.add", 1, true), "the guide pulse runs on FxLoop")
	assert(read("src/Client/AuditV2.lua"):find("Gameplay2Perf", 1, true), "AuditV2 prints the GuiObject count")
end })

'''
s = s.replace(marker, test + marker, 1)
open(p, 'w').write(s)
print("ok")
