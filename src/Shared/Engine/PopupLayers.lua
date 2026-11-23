--[[
	Shared/Engine/PopupLayers.lua
	Pure rules for "nothing from the table shows through or sits above an open popup" (applied by Client/PopupLayers.lua).

	  PopupLayers.shouldHide(name)        true for the boss card, boss banners, boss tooltips, HUD plates, gear and sort buttons
	  PopupLayers.hiddenFor(open, names)  the names that must be hidden while `open` popups are up (none when open == 0)
	  PopupLayers.violations(layers, popupZ, openCount)
	                                      layers = { { name=, z=, visible= } }; the table layers that would still draw above a popup
	  PopupLayers.SCROLL_BOTTOM_PAD       room under the last Deck tracker row so it is never clipped
]]

local PopupLayers = {}

PopupLayers.SCROLL_BOTTOM_PAD = 24

PopupLayers.NAMES = {
	BossCard = true, BossSeatCard = true, BossHealth = true, BossPresencePlate = true, BossBanner = true,
	BossScoutBanner = true, BossEnrageBanner = true, BossBubble = true, BossAttackBand = true,
	TargetBox = true, TipsPill = true, GearMenu = true, SortToggle = true,
	BossRuleHit = true, BossRuleTip = true, -- the rule chip tap target and its line
}

-- Full screen pages (the Tome pages, the Store, the Season and the reward boards) draw their own room. While one is open the WHOLE
-- table (GameRoot) is hidden by one switch, so no table layer can ever leak through, whatever it is called or how high its ZIndex is.
-- A new full screen page only has to be listed here; the name lists above stay for partial popups (confirms, Deck tracker).
PopupLayers.FULL_SCREEN = {
	CollectionBackdrop = true, StoreBackdrop = true, SeasonBackdrop = true, DailyRewardsBackdrop = true, QuestsBackdrop = true,
}
-- Every other Backdrop the Client creates is a partial popup: the table stays alive behind it and only the NAMES layers above hide.
-- A test scans src/Client for every `Name = "...Backdrop"` and fails when one is in neither list, so a new page cannot be forgotten.
PopupLayers.PARTIAL = {
	Backdrop = true, -- FlairDressingRoom inner dimmer
	RoadChoiceBackdrop = true, ReplayConfirmBackdrop = true, DeckTrackerBackdrop = true, QuitConfirmBackdrop = true,
	SeedRunBackdrop = true, ConfirmBackdrop = true, FlairBackdrop = true, HowToPlayBackdrop = true, VictoryBackdrop = true,
	NightVictoryBackdrop = true, HandRefBackdrop = true, MusicBackdrop = true, OverlayQueueBackdrop = true,
	JourneyBackdrop = true, ShopBackdrop = true, DailyLeaderboardBackdrop = true, BoonsPageBackdrop = true,
	ChoiceBackdrop = true, SeasonPreviewBackdrop = true, CosmeticSetsBackdrop = true, VolumeBackdrop = true,
	TwistPopupBackdrop = true, LegendBackdrop = true, CollectionRewardsBackdrop = true, SettingsBackdrop = true,
	StatsBackdrop = true, RunSetupBackdrop = true, WinCardBackdrop = true, RestartConfirmBackdrop = true,
	BadgesBackdrop = true, NewsBackdrop = true,
}
function PopupLayers.isClassified(name)
	return PopupLayers.FULL_SCREEN[name] == true or PopupLayers.PARTIAL[name] == true
end

function PopupLayers.coversTable(name)
	return type(name) == "string" and PopupLayers.FULL_SCREEN[name] == true
end

function PopupLayers.shouldHide(name)
	if type(name) ~= "string" then return false end
	if PopupLayers.NAMES[name] then return true end
	return name:sub(1, 4) == "Boss" and name:sub(-7) == "Tooltip"
end

function PopupLayers.hiddenFor(open, names)
	local out = {}
	if (open or 0) <= 0 then return out end
	for _, n in ipairs(names or {}) do
		if PopupLayers.shouldHide(n) then out[#out + 1] = n end
	end
	return out
end

function PopupLayers.violations(layers, popupZ, openCount)
	local out = {}
	local popupUp = (openCount or 0) > 0
	for _, l in ipairs(layers or {}) do
		local table_layer = PopupLayers.shouldHide(l.name)
		-- a table layer above the popup is only fine when it is hidden while the popup is open
		if table_layer and l.visible ~= false and (l.z or 0) > popupZ and not popupUp then
			out[#out + 1] = l.name
		end
	end
	return out
end

return PopupLayers
