--[[
	Shared/Engine/PopupRules.lua
	Pure rules for "a popup blocks every click behind it" (tested; applied by Client/PopupShield.lua).

	  PopupRules.isPopupName(name)   a full-screen popup root: any "...Backdrop" plus the named extras
	  PopupRules.shouldShield(name)  popup roots that get Active = true (DeckTrackerBackdrop is skipped:
	                                 the deck pile toggles it)
	  PopupRules.MENU_AMBIENT_MAX_Z  highest ZIndex any Menu decoration uses (Notice Board pins and hit areas)
	  PopupRules.MENU_SCROLL_MIN_Z   lowest ZIndex of the Menu scroll popups, catcher and All actions list
	  PopupRules.MENU_POPUPS         the Menu scroll layers (Studio-checkable list)
	  PopupRules.STUDIO_CHECK        every popup to click through in Studio (rows that overlap the Notice Board)
]]

local PopupRules = {}

PopupRules.MENU_AMBIENT_MAX_Z = 44
PopupRules.MENU_SCROLL_MIN_Z = 48

PopupRules.EXTRA = { SpectateOverlay = true, ModalStage = true }
PopupRules.SKIP = { DeckTrackerBackdrop = true }

-- The Menu scroll layers, from Client/MenuHotspots.lua.
PopupRules.MENU_POPUPS = { "FanCatcher", "Scroll_<hotspot>", "AllActions" }

PopupRules.STUDIO_CHECK = {
	"Quest Scroll rows (Daily Challenge, Weekly Challenge, Seed Run, Daily Quests, Leaderboards)",
	"All actions list", "Seed Run dialog", "Run Setup", "Daily Quests", "Leaderboards", "Settings",
	"Collection", "Card Sets", "Stats", "Season", "Flair", "Badges", "News", "Store", "Peddler (Shop)",
	"Round Select", "Choice", "Road", "Win Card", "Run Summary", "Confirm dialogs",
}

function PopupRules.isPopupName(name)
	if type(name) ~= "string" then return false end
	return name:sub(-8) == "Backdrop" or PopupRules.EXTRA[name] == true
end

function PopupRules.shouldShield(name)
	return PopupRules.isPopupName(name) and not PopupRules.SKIP[name]
end

-- Popups that make a sound: every shielded popup root plus the Menu scroll layers (not the Fan catcher, which only catches clicks).
function PopupRules.makesSound(name)
	if type(name) ~= "string" then return false end
	return PopupRules.shouldShield(name) or name:sub(1, 7) == "Scroll_" or name == "AllActions"
end

-- One gate for every popup: gate(isOpen, now) returns the cue to play ("scroll_open" or "scroll_close") or nil. A change of state
-- inside `minGap` seconds of the last sound is silent, so rapid toggles never stack and an open and a close never both play at once.
PopupRules.CUE_GAP = 0.15
function PopupRules.newCueGate(minGap)
	local last = -math.huge
	return function(isOpen, now)
		if now - last < (minGap or PopupRules.CUE_GAP) then return nil end
		last = now
		return isOpen and "scroll_open" or "scroll_close"
	end
end

return PopupRules
