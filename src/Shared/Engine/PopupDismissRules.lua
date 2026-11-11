--[[
	Shared/Engine/PopupDismissRules.lua
	Pure rules for "every screen can be exited" (tested; applied by Client/PopupDismiss.lua). Nothing may trap the player.

	A popup registers with one POLICY, which says what its three exits do:

	  policy    Escape            click on the dark area   a visible button
	  dismiss   closes it         closes it                Back or Close (every panel has one)
	  cancel    closes it         closes it                Cancel (a confirm dialog: both exits mean Cancel, NEVER Confirm)
	  button    presses its one   nothing                  its only button (result screens, the notice plates)
	            button
	  locked    opens Settings    nothing                  not abandonable (a mid-run choice): Escape still opens the
	                                                       Settings panel, lifted above it, so the player is never stuck

	PopupDismissRules.action(policy, trigger)  -> "close" | "press" | "pause" | "none"   (trigger "escape" | "outside")
	PopupDismissRules.topmost(entries)         -> the entry Escape and an outside click belong to
	PopupDismissRules.isDimLayer(w, h, bw, bh) -> true when a child covers (nearly) the whole backdrop
	PopupDismissRules.canAbandonChoice(kind)   -> true for the start-of-run draft, false for a between-Nights event
	PopupDismissRules.exits(policy, hasButton) -> { button, escape, outside } for the Studio report
	PopupDismissRules.EXCEPTIONS               names that end in "Backdrop" but are not popups a player can be stuck in
]]

local M = {}

M.POLICIES = {
	dismiss = { escape = "close", outside = "close" },
	cancel = { escape = "close", outside = "close" },
	button = { escape = "press", outside = "none" },
	locked = { escape = "pause", outside = "none" },
}

function M.isPolicy(name)
	return type(name) == "string" and M.POLICIES[name] ~= nil
end

-- An unknown policy does nothing: a typo must never close a screen the player is in the middle of.
function M.action(policy, trigger)
	local row = M.POLICIES[policy]
	return row and row[trigger] or "none"
end

-- The topmost visible popup: highest ZIndex, and among equal ZIndex the one opened last (a confirm dialog opened over its parent
-- panel wins even when both share a ZIndex). entries = { { id, z, order, visible } }.
function M.topmost(entries)
	local best
	for _, e in ipairs(entries or {}) do
		if e.visible then
			if not best or e.z > best.z or (e.z == best.z and (e.order or 0) > (best.order or 0)) then
				best = e
			end
		end
	end
	return best
end

-- A child of the backdrop that covers (nearly) all of it is part of the dark area (a scene, a stage, a vignette): a click that
-- lands on it is a click outside the panel. A shadow, a tab strip or a panel is smaller than that. 85 percent in both axes.
M.DIM_FRACTION = 0.85
function M.isDimLayer(w, h, bw, bh)
	if not (w and h and bw and bh) or bw <= 0 or bh <= 0 then return false end
	return w >= bw * M.DIM_FRACTION and h >= bh * M.DIM_FRACTION
end

-- The start-of-run draft (first Patron, blessing, Boss Rush Patrons) can be left; a between-Nights event card cannot (it already
-- has a "No, thanks" card, and the run is under way).
M.ABANDONABLE_CHOICES = { patron = true, modifier = true, rushPatron = true }
function M.canAbandonChoice(kind)
	return M.ABANDONABLE_CHOICES[kind] == true
end

-- Which exits a popup has, for the Studio startup report. hasButton = it shows a Back, Close, Cancel or Continue button.
function M.exits(policy, hasButton)
	local row = M.POLICIES[policy]
	return {
		button = hasButton == true,
		escape = row ~= nil and row.escape ~= "none",
		outside = row ~= nil and row.outside ~= "none",
	}
end

-- Roots whose name ends in "Backdrop" but that are not popups: a scene behind the Counter, not a panel over the game.
M.EXCEPTIONS = {
	ShopBackdrop = "the painted Counter scene (Client/ShopBackdrop.lua), a layer of the Shop screen, not a popup",
}

return M
