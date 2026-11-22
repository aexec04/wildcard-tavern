p = "src/Shared/Tests/EngineTests.lua"
s = open(p).read()
a = s.index('table.insert(tests, { name = "Patron pick card: one name, plain portrait fills the frame (no cut card, no dark slab)"')
b = s.index('table.insert(tests, { name = "RunChoice events: wrong option, double resolve')
new = '''table.insert(tests, { name = "Patron pick card: one name, the cut card portrait window fills a clipped ring for every Patron (no scene, no overflow)", fn = function()
	local DP = require(script.Parent.Parent.Engine.DraftPortrait)
	local PP = require(script.Parent.Parent.Engine.PatronParchment)
	local Crop = require(script.Parent.Parent.Engine.PatronCardCrop)
	for _, def in ipairs(Patrons.Definitions) do
		local spec = DP.spec(def.id)
		expectTrue(spec ~= nil, def.id .. " resolves a portrait (no blank ring)")
		if spec then
			expectEqual(spec.kind, "card", def.id .. " uses the cut card window, not a full scene")
			expectEqual(spec.scaleType, "Crop", def.id .. " crops to fill")
			local r = spec.rect
			expectTrue(r.x >= 0 and r.y >= 0 and r.x + r.w <= 683.4 and r.y + r.h <= 1024.1, def.id .. " window inside the stored texture")
			expectTrue(Crop[def.id].y + Crop[def.id].h <= 1536 * 0.82, def.id .. " window ends above the baked name")
			expectTrue(r.w > 0 and r.h > 0, def.id .. " window has size")
		end
	end
	expectTrue(DP.spec("no_such_patron") == nil, "unknown Patron: no art, the ring keeps its emoji")
	local fr = DP.rect(126, 84)
	expectTrue(fr.x == 0 and fr.y == 0 and fr.w == 126 and fr.h == 84, "the picture is exactly the ring")
	expectTrue(DP.overflow(10, 10, 126, 84, 10, 10, 126, 84) == nil, "a picture on its frame does not warn")
	expectTrue(DP.overflow(0, 0, 200, 150, 10, 10, 126, 84) ~= nil, "a picture bigger than its frame warns")
	if not (io and io.open) then return end
	local function read(path) local f = io.open(path, "r"); if not f then return nil end local t = f:read("*a"); f:close(); return t end
	local panel = read("src/Client/ChoicePanel.lua")
	if not panel then return end
	expectTrue(panel:find("DraftPortrait.spec(option.id)", 1, true) ~= nil, "the pick card draws from DraftPortrait")
	expectTrue(panel:find("crop.ClipsDescendants = true", 1, true) ~= nil, "the portrait is clipped by the ring")
	expectTrue(panel:find("PORTRAIT_SCALE", 1, true) == nil, "no oversized scene scale left")
	-- the name is drawn once per card: one Name label in the plate branch, one in the plain branch
	local n = 0
	for _ in panel:gmatch('Name = "Name",') do n = n + 1 end
	expectEqual(n, 2)
end })

'''
s = s[:a] + new + s[b:]
open(p, "w").write(s)
