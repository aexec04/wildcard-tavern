p='src/Client/Gameplay2.lua'
s=open(p).read()
T='\t'
a=T*1+'local furniture = {}\n'+T*1+'for _, spec in ipairs('
b=T*1+'''local furniture = {}
\t\t-- soft contact shadows (solid black, stacked rounded frames from faint to dark, no gradient): one under the tray, a smaller one under the deck on it
\t\tlocal shadows = {}
\t\tfor _, name in ipairs({ "TrayShadow", "DeckShadow" }) do
\t\t\tlocal sh = Instance.new("Frame"); sh.Name = name; sh.BackgroundTransparency = 1; sh.BorderSizePixel = 0; sh.Active = false; sh.ZIndex = 2; sh.Visible = false; sh.Parent = layer
\t\t\tfor i, tr in ipairs({ 0.88, 0.8, 0.7 }) do
\t\t\t\tlocal ring = Instance.new("Frame"); ring.Name = "Ring" .. i; ring.BorderSizePixel = 0; ring.Active = false
\t\t\tring.BackgroundColor3 = Color3.new(0, 0, 0); ring.BackgroundTransparency = tr; ring.ZIndex = 2
\t\t\tring.AnchorPoint = Vector2.new(0.5, 0.5); ring.Position = UDim2.fromScale(0.5, 0.5)
\t\t\tring.Size = UDim2.new(1, -2 * (i - 1) * 5, 1, -2 * (i - 1) * 5)
\t\t\tring.Parent = sh
\t\t\tlocal uc = Instance.new("UICorner"); uc.CornerRadius = UDim.new(0, 14); uc.Parent = ring
\t\t\tend
\t\t\tshadows[name] = sh
\t\tend
\t\tfor _, spec in ipairs('''
assert a in s
s=s.replace(a,b,1)
a=T*4+'place(img, dc[key])\n'+T*3+'end\n'
b=a+T*3+'''furniture.tray.Rotation = CTLayout.TRAY_TILT
\t\t\tlocal sp = CTLayout.shadowFor(dc.tray, r.deck)
\t\t\tfor name, sh in pairs(shadows) do
\t\t\t\tsh.Visible = furniture.tray.Visible
\t\t\t\tsh.Rotation = CTLayout.TRAY_TILT
\t\t\t\tplace(sh, name == "TrayShadow" and sp.tray or sp.deck)
\t\t\tend
'''
assert a in s
s=s.replace(a,b,1)
open(p,'w').write(s)

p='src/Shared/Engine/ConceptTLayout.lua'
s=open(p).read()
a='-- The tray art is drawn leaning'
b='''-- Contact shadows for the tray and the deck: the tray's visible box grown SHADOW_GROW per side and moved SHADOW_DROP down, and the deck rect
-- grown 4 px per side and moved 4 px down, so each peeks out under its object.
M.SHADOW_GROW, M.SHADOW_DROP = 20, 6
function M.shadowFor(tray, deck)
	local g, d = M.SHADOW_GROW, M.SHADOW_DROP
	local b = tray.box
	return {
		tray = { x = b.x - g, y = b.y - g + d, w = b.w + 2 * g, h = b.h + 2 * g },
		deck = { x = deck.x - 4, y = deck.y, w = deck.w + 8, h = deck.h + 8 },
	}
end

'''
assert a in s
s=s.replace(a,b+a,1)
open(p,'w').write(s)

p='src/Shared/Tests/EngineTests.lua'
s=open(p).read()
a='table.insert(tests, { name = "Gameplay2 bottom rail: carved end caps'
b='''table.insert(tests, { name = "Gameplay2 deck tray: contact shadow is 20 px bigger, 6 px lower, and the live tray is turned", fn = function()
	local L = require(script.Parent.Parent.Engine.ConceptTLayout)
	local G = require(script.Parent.Parent.Engine.Gameplay2Layout)
	for _, sz in ipairs({ { 1920, 1080 }, { 1920, 957 }, { 1506, 751 }, { 1280, 720 } }) do
		local w, h = sz[1], sz[2]
		local r = G.rects(w, h)
		local d = L.decorFor(r, w, h)
		local sh = L.shadowFor(d.tray, r.deck)
		assert(sh.tray.w == d.tray.box.w + 40 and sh.tray.h == d.tray.box.h + 40, w .. "x" .. h .. " shadow 20 px bigger per side")
		assert(sh.tray.y == d.tray.box.y - 20 + 6, w .. "x" .. h .. " shadow dropped 6 px")
		assert(sh.deck.x < r.deck.x and sh.deck.x + sh.deck.w > r.deck.x + r.deck.w, w .. "x" .. h .. " deck shadow wraps the deck")
	end
	local src = io and io.open("src/Client/Gameplay2.lua")
	if src then
		local t = src:read("*a"); src:close()
		assert(t:find("furniture.tray.Rotation = CTLayout.TRAY_TILT", 1, true), "Gameplay2 applies the tray tilt")
	end
end })
'''
assert a in s
s=s.replace(a,b+a,1)
open(p,'w').write(s)
