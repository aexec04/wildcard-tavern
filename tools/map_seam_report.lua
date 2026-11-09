-- Studio-free report for the Tavern Map backdrop joins: run with `lua tools/map_seam_report.lua`.
-- For each region strip in order it prints the art key, whether an Image id is recorded, the generated image size and
-- aspect, the width the strip gets on the 4072x734 canvas, how many tiles it needs, and where each join falls with the
-- overlap each painting gets. Regions with no recorded art are flagged (those would be flat areas without the fallback).
-- The zone is sized from the NARROWER neighbour (18 percent of it on each side), so the wider painting overlaps by less in percent.
-- Region strips mirror Client/JourneyMapScenery.lua REGIONS; node x positions are assumed evenly spread because the
-- real ones come from Studio layout, so treat the pixel numbers as a model of the layout, not a measurement.
package.path = "./src/Shared/Engine/?.lua;" .. package.path

local function loadEngine(name)
	local f = assert(loadfile("src/Shared/Engine/" .. name .. ".lua"))
	return f()
end

local MapSeams = loadEngine("MapSeams")

-- art ids come from the generated map (parsed as text so no Roblox services are needed)
local recorded = {}
for key in io.open("src/Shared/Engine/MapRegionArt.lua"):read("*a"):gmatch('%["([%w_]+)"%]%s*=%s*"rbxassetid://%d+"') do
	recorded[key] = true
end

local REGIONS = {
	{ key = "region_road", name = "The Dusty Road", tint = { 222, 200, 150 }, lastNode = 1 },
	{ key = "region_meadow", name = "Wildflower Meadow", tint = { 190, 200, 142 }, lastNode = 3 },
	{ key = "region_river", name = "Willow River", tint = { 168, 196, 176 }, lastNode = 4 },
	{ key = "region_peaks", name = "Mountain Peaks", tint = { 186, 190, 172 }, lastNode = 5 },
	{ key = "region_tavern", name = "The Tavern", tint = { 226, 190, 128 }, lastNode = 8, single = true },
	{ key = "region_road", name = "The Road Beyond", tint = { 214, 192, 146 }, lastNode = math.huge },
}

local CANVAS_W, CANVAS_H, NODES = 4072, 734, 12
local nodeXs = {}
for i = 1, NODES do nodeXs[i] = math.floor((i - 0.5) * CANVAS_W / NODES) end

local plan = MapSeams.plan(REGIONS, CANVAS_W, CANVAS_H, nodeXs, function(i) return recorded[REGIONS[i].key] == true end)

print(string.format("Canvas %dx%d, art generated at 1536x1024 (aspect %.2f), %d nodes assumed evenly spaced", CANVAS_W, CANVAS_H, MapSeams.ART_ASPECT, NODES))
print("")
print("REGION STRIPS")
local missing = 0
for i, r in ipairs(plan.regions) do
	if not r.hasArt then missing = missing + 1 end
	print(string.format("  %d %-16s art=%-14s recorded=%-3s x %5d..%5d width %5d tiles %d%s", i, REGIONS[i].name, r.key,
		r.hasArt and "yes" or "NO", r.x0, r.x1, r.width, r.tiles,
		r.hasArt and "" or ("  <- flat area; falls back to a tinted copy of region " .. tostring(r.fallbackFrom))))
end
print("")
print("JOINS (cross-fade zone centred on the join; both paintings overlap by the percentages shown)")
local badJoins = 0
for i = 2, #REGIONS do
	local j = plan.joins[i]
	local ok = math.max(j.overlapLeftPct, j.overlapRightPct) >= 17.5 or j.width >= MapSeams.JOIN_MAX or j.width >= math.min(plan.regions[i - 1].width, plan.regions[i].width)
	if not ok then badJoins = badJoins + 1 end
	local a, b = REGIONS[i - 1].tint, REGIONS[i].tint
	local dist = math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
	print(string.format("  join %d|%d at x=%5d  zone %4d..%4d (%4d px)  overlap left %.0f%% right %.0f%%  tint distance %3.0f%s",
		i - 1, i, j.x, j.from, j.to, j.width, j.overlapLeftPct, j.overlapRightPct, dist, ok and "" or "  <- overlap under 18%"))
end
print("")
print(string.format("Missing art: %d. Joins under 18%% overlap: %d.", missing, badJoins))
