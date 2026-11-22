-- Pure rule for the result plates (Run Summary, Night Victory): while one is up, account panels
-- (the Store and its tab strip) must stay hidden, even if something re-shows them.
local ResultGuard = {}

ResultGuard.RESULTS = { "RunSummaryBackdrop", "NightVictoryBackdrop", "VictoryBackdrop" }
ResultGuard.HIDDEN = { "StoreBackdrop" }

-- visible: map of backdrop name -> bool. Returns true when an account panel must be forced hidden.
function ResultGuard.mustHide(visible)
	for _, name in ipairs(ResultGuard.RESULTS) do
		if visible and visible[name] == true then return true end
	end
	return false
end

return ResultGuard
