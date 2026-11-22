-- one-off: plain replacements of emoji in Tavern Map UI sources
local function slurp(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
local function spit(p, s) local f = assert(io.open(p, "w")); f:write(s); f:close() end
local C = "src/Client/"
local R = {
	{ "JourneyMapView.lua", 'Text = "👣"', 'Text = ""' },
	{ "JourneyMapView.lua", 'isEndless and "∞"', 'isEndless and "oo"' },
	{ "JourneyMapView.lua", 'Text = "✓", BackgroundTransparency', 'Text = "OK", BackgroundTransparency' },
	{ "JourneyMapView.lua", 'closeCard.Text = "✕"', 'closeCard.Text = "X"' },
	{ "JourneyMapView.lua", '"Boss ★★★ and beyond"', '"Boss III and beyond"' },
	{ "JourneyMapView.lua", 'cardBoss.Text = JourneyMap.BossTiers[JourneyMap.bossTierFor(data.night)].icon .. " "', 'cardBoss.Text = ""' },
	{ "JourneyMapView.lua", '"🔒 Clear Night 8', '"Locked: clear Night 8' },
	{ "JourneyMapView.lua", '(isEarned and "✓ Earned: " or "🎁 Reward: ")', '(isEarned and "Earned: " or "Reward: ")' },
	{ "JourneyMapView.lua", '"Equipped ✓"', '"Equipped"' },
	{ "JourneyMapView.lua", '"🛠 Nudge: off"', '"Nudge: off"' },
	{ "JourneyMapView.lua", '"🛠 Nudge: ON" or "🛠 Nudge: off"', '"Nudge: ON" or "Nudge: off"' },
	{ "JourneyMapView.lua", '"📍 Find me"', '"Find me"' },
	{ "JourneyMapView.lua", 'showToast("🎁 " ..', 'showToast(' },
	{ "JourneyMapView.lua", '"♾ " .. JourneyMap.Endless.name .. " ♾"', 'JourneyMap.Endless.name' },
	{ "JourneyMapView.lua", 'return kind.icon .. " " .. (def', 'return kind.noun .. ": " .. (def' },
	{ "JourneyMapGraph.lua", '"  ★ Master"', '"  Master"' },
	{ "JourneyMapGraph.lua", '"  ✓ cleared"', '"  cleared"' },
	{ "JourneyMapGraph.lua", 'textLabel("🎁 " .. text', 'textLabel(text' },
	{ "JourneyMapGraph.lua", '"🔒 Unlock with a Key" or "🔒 Locked"', '"Unlock with a Key" or "Locked"' },
	{ "JourneyMapGraph.lua", 'textLabel("🔒", ', 'textLabel("Lock", ' },
	{ "JourneyMapCompass.lua", '"🗝 0"', '"Keys 0"' },
	{ "JourneyMapCompass.lua", '"🗝 " .. RoadLock.keys(state)', '"Keys " .. RoadLock.keys(state)' },
	{ "JourneyMapCompass.lua", 'icon.Text = "🧭"', 'icon.Text = "N"' },
	{ "JourneyMapCompass.lua", 'button("◀",', 'button("<",' },
	{ "JourneyMapCompass.lua", 'button("▶",', 'button(">",' },
	{ "JourneyMapHero.lua", 'emoji.Text = "🙂"', 'emoji.Text = ""' },
	{ "JourneyMapDiscoveries.lua", '{ chest = "🧰", merchant = "🛒", secret_patron = "🔓" }', '{ chest = "C", merchant = "$", secret_patron = "S" }' },
	{ "JourneyMapDiscoveries.lua", 'claimed and "✔" or', 'claimed and "OK" or' },
	{ "JourneyMapDiscoveries.lua", '"🧭 Use a charge', '"Use a charge' },
	{ "MapHover.lua", '(info.done and "✔ Cleared. " or "")', '(info.done and "Cleared. " or "")' },
	{ "CompassWheel.lua", 'string.rep("◆", n) .. string.rep("◇", math.max(0, 3 - n))) or "◇◇◇"', 'string.rep("#", n) .. string.rep("-", math.max(0, 3 - n))) or "---"' },
	{ "RoadChoice.lua", '"🧭 Choose your road"', '"Choose your road"' },
	{ "RoadChoice.lua", '"🧭 Use compass: reveal rewards"', '"Use compass: reveal rewards"' },
	{ "RoadChoice.lua", 'stop.icon or "🧭"', 'stop.icon or "?"' },
	{ "RoadChoice.lua", 'Text = "🔒", TextSize = 30', 'Text = "Lock", TextSize = 20' },
	{ "RoadChoice.lua", '"🔒 Unlock with a Key" or "🔒 Locked: needs a Key"', '"Unlock with a Key" or "Locked: needs a Key"' },
}
local cache = {}
for _, r in ipairs(R) do
	local p = C .. r[1]
	cache[p] = cache[p] or slurp(p)
	local i, j = cache[p]:find(r[2], 1, true)
	if i then cache[p] = cache[p]:sub(1, i - 1) .. r[3] .. cache[p]:sub(j + 1) else print("MISSING", r[1], r[2]) end
end
for p, s in pairs(cache) do spit(p, s) end
