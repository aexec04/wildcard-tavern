#!/usr/bin/env python3
"""One-off: add the sequence-limit and Collection Furn tests to EngineTests.lua."""
import pathlib
p = pathlib.Path(__file__).resolve().parents[1] / "src" / "Shared" / "Tests" / "EngineTests.lua"
s = p.read_text()
old = '''		local want = ((c[2] > 0) and 11 or 1) + ((c[3] > 0) and 11 or 1)
		expectEqual(want, #pts, "keypoint count")
	end
end })
'''
new = '''		local want = ((c[2] > 0) and 11 or 1) + ((c[3] > 0) and 11 or 1)
		if c[2] > 0 and c[3] > 0 then want = 20 end -- both sides faded: capped so the NumberSequence stays within Roblox's 20 keypoints
		expectEqual(want, #pts, "keypoint count")
	end
end })

table.insert(tests, { name = "RegionTiles.maskStops: never more than 20 keypoints for any width, fade or perSide, and a stub NumberSequence accepts every result", fn = function()
	local RegionTiles = require(script.Parent.Parent.Engine.RegionTiles)
	-- stub with Roblox's rule: NumberSequence.new(table) errors when the table has more than 20 keypoints
	local function stubSequence(kps)
		if #kps > 20 then error("NumberSequence.new(): table is too long") end
		return kps
	end
	for _, width in ipairs({ 1, 50, 100, 400, 800, 3000 }) do
		for _, fade in ipairs({ 0, 1, 40, 200, 500, 4000 }) do
			for _, perSide in ipairs({ 1, 8, 10, 15, 40, 200 }) do
				for _, sides in ipairs({ { fade, 0 }, { 0, fade }, { fade, fade } }) do
					local pts = RegionTiles.maskStops(width, sides[1], sides[2], perSide)
					expectTrue(#pts <= 20, "at most 20 keypoints")
					local kps = {}
					for _, p in ipairs(pts) do kps[#kps + 1] = { t = p.t, v = p.transparency } end
					local ok = pcall(stubSequence, kps)
					expectTrue(ok, "stub NumberSequence accepts width " .. width .. " fade " .. fade .. " perSide " .. perSide)
					expectEqual(0, pts[1].t, "starts at 0")
					expectEqual(1, pts[#pts].t, "ends at 1")
				end
			end
		end
	end
end })

table.insert(tests, { name = "Collection: Furn is defined before use and every tab has a furniture kind or an explicit plain entry", fn = function()
	local CollectionBook = require(script.Parent.Parent.Engine.CollectionBook)
	local F = require(script.Parent.Parent.Engine.CollectionFurnitureLayout)
	for _, tab in ipairs(CollectionBook.Tabs) do
		expectTrue(F.TAB_KIND[tab.id] ~= nil or F.PLAIN[tab.id] == true, tab.id .. " has a furniture kind or a plain entry")
		expectFalse(F.TAB_KIND[tab.id] ~= nil and F.PLAIN[tab.id] == true, tab.id .. " is not both")
	end
	local f = io and io.open and io.open("src/Client/Collection.lua", "r")
	if f then
		local code = f:read("*a")
		f:close()
		local decl = code:find("local Furn\\n", 1, true)
		local use = code:find("Furn.kind(", 1, true)
		expectTrue(decl ~= nil and use ~= nil and decl < use, "local Furn is declared before its first use")
		expectTrue(code:find("kind = function() return nil end", 1, true) ~= nil, "nil-safe fallback to plain cells")
	end
end })

table.insert(tests, { name = "Gradient sequences: map masks are clamped to 20 keypoints and the map viewport edge fade is one gradient per side", fn = function()
	local function read(path)
		local f = io and io.open and io.open(path, "r")
		if not f then return nil end
		local c = f:read("*a")
		f:close()
		return c
	end
	local sc = read("src/Client/JourneyMapScenery.lua")
	if sc then
		expectTrue(sc:find("maskSequence(RegionTiles.maskStops", 1, true) ~= nil, "map masks go through the clamping builder")
		expectTrue(sc:find("MAX_KEYPOINTS", 1, true) ~= nil, "the builder clamps to MAX_KEYPOINTS")
	end
	local VC = require(script.Parent.Parent.Engine.VignetteCurve)
	expectTrue(#VC.keypoints() <= 20, "vignette curve within 20 keypoints")
	local view = read("src/Client/JourneyMapView.lua")
	if view then
		expectTrue(view:find("FADE_STEPS", 1, true) == nil, "no stepped fade strips on the map viewport")
		expectTrue(view:find("SmoothVignette", 1, true) ~= nil, "the map viewport edge fade is one gradient per side")
	end
end })
'''
assert old in s
p.write_text(s.replace(old, new, 1))
print("ok")
