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
