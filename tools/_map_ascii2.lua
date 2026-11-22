local function slurp(p) local f = assert(io.open(p)); local s = f:read("a"); f:close(); return s end
local function spit(p, s) local f = assert(io.open(p, "w")); f:write(s); f:close() end
local R = {
 { "src/Client/Journey.lua", '	journeySubtitle.BackgroundTransparency = 1\n	journeySubtitle.Font = Enum.Font.Gotham\n	journeySubtitle.TextSize = 14\n	journeySubtitle.TextColor3 = Color3.fromRGB(220, 205, 185)',
   '	journeySubtitle.BackgroundColor3 = Color3.fromRGB(34, 24, 16) -- dark plate: readable over any map art\n	journeySubtitle.BackgroundTransparency = 0.12\n	journeySubtitle.Font = Enum.Font.Gotham\n	journeySubtitle.TextSize = 15\n	journeySubtitle.TextColor3 = Color3.fromRGB(240, 228, 205)' },
 { "src/Client/Journey.lua", 'Your table walks the road one Round at a time. 👑 = Boss Round.', 'Your table walks the road one Round at a time.' },
 { "src/Client/JourneyMapView.lua", 'string.format("Journey %d%% (%d/%d)", percent, done, total)', 'string.format("Journey %d of %d cleared", done, total)' },
 { "src/Client/JourneyMapView.lua", '". Discovered %d of %d"', '"   |   Discovered %d of %d"' },
 { "src/Client/JourneyMapView.lua", '". Places seen: %d of %d"', '"   |   Places seen %d of %d"' },
 { "src/Client/JourneyMapView.lua", 'deps.subtitleLabel.Text = progress .. ". " .. hint', 'deps.subtitleLabel.Text = progress .. "   |   " .. hint' },
}
local cache = {}
for _, r in ipairs(R) do
 cache[r[1]] = cache[r[1]] or slurp(r[1])
 local i, j = cache[r[1]]:find(r[2], 1, true)
 if i then cache[r[1]] = cache[r[1]]:sub(1, i-1)..r[3]..cache[r[1]]:sub(j+1) else print("MISSING", r[2]:sub(1,40)) end
end
for p, s in pairs(cache) do spit(p, s) end
