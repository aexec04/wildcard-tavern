local L = dofile("src/Shared/Engine/RunOverLayout.lua")
local P = { "One More (Free)", "Play Again", "Back to Tavern" }
local M = { "Share", "Challenge", "Invite", "Save Badge", "Win Card", "" }
local S = L.SCROLLS.a
local scale = math.min((1280 - 24) / S.art.w, (720 - 16) / S.art.h)
local safe = { w = S.safe.w * scale, h = S.safe.h * scale }
local inner = L.compute(safe.w + 32, 100000, { factsH = 330, patrons = 3, primary = 3, more = 6, primaryLabels = P, moreLabels = M })
print(scale, safe.w, safe.h, inner.panel.w, inner.panel.h, inner.morePerRow, #inner.primary)
for i, c in ipairs(inner.primary) do print("p", i, c.x, c.y, c.w) end
