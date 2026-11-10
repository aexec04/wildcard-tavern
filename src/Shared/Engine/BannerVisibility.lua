--[[
	Engine/BannerVisibility.lua
	Pure rule for the round rules banner (the boss name and rule text drawn by Client/BossFight): it belongs to the table, so
	it must not draw over the tab row of any non-run screen. Same overlay rule as Client/InputGuard: any visible GUI frame
	whose name ends in "Backdrop" (Collection, Card Sets, Badges, Legend, Flair, Stats, Ledger ...) counts, except the deck
	tracker, which is opened from the table itself.

	  BannerVisibility.isScreenOpen(visibleNames)   true when one of the names is a non-run screen backdrop
	  BannerVisibility.shouldShow(inFight, visibleNames)
]]

local BannerVisibility = {}

BannerVisibility.SKIP = { DeckTrackerBackdrop = true }

function BannerVisibility.isScreenOpen(visibleNames)
	for _, name in ipairs(visibleNames or {}) do
		if type(name) == "string" and name:sub(-8) == "Backdrop" and not BannerVisibility.SKIP[name] then
			return true
		end
	end
	return false
end

function BannerVisibility.shouldShow(inFight, visibleNames)
	return inFight == true and not BannerVisibility.isScreenOpen(visibleNames)
end

return BannerVisibility
