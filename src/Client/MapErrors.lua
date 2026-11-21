-- Counts Tavern Map script errors so DebugGoto map can say "ok" only when nothing failed since the jump.
local MapErrors = { total = 0 }

function MapErrors.report(label, err)
	MapErrors.total += 1
	warn("[TavernMap] " .. label .. " failed: " .. tostring(err))
end

return MapErrors
