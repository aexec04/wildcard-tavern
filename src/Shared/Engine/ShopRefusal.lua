--[[
	Shared/Engine/ShopRefusal.lua
	One line of text for every way the Counter can say no to Reroll or Haggle, so a click is never met with silence, and the
	words on the two controls. Pure (tested); the server turns a refusal into a notice the client shows on the Counter.

	  ShopRefusal.reroll(phaseOk, pendingPack, tips, cost) -> nil when allowed, else the reason
	  ShopRefusal.haggle(code)                             -> the reason for a Haggle.canStart / Haggle.start code
	  ShopRefusal.rerollLabel(cost)                        -> "Reroll 3"
	  ShopRefusal.haggleLabel(view)                        -> "Haggle" or "Haggled" (view = Haggle.view)
	  ShopRefusal.haggleDenied(view)                       -> why a click on Haggle does nothing right now, or nil
	  ShopRefusal.hiddenCodes                              codes after which the Haggle control is not shown at all
]]

local ShopRefusal = {}

ShopRefusal.REASONS = {
	wrong_phase = "The Counter is closed right now.",
	ranked = "No haggling on a ranked board.",
	tutorial = "No haggling in the tutorial.",
	pack_open = "Finish opening your pack first.",
	used = "You already haggled this visit.",
	bad_item = "That item is no longer on offer.",
	not_open = "The haggle bar is not open.",
	tips = "Not enough tips to reroll.",
	slow = "One moment, the Counter is busy.",
}

-- The Haggle control does not exist on these boards or in the tutorial, so it is not drawn there.
ShopRefusal.hiddenCodes = { ranked = true, tutorial = true, wrong_phase = true }

function ShopRefusal.reroll(phaseOk, pendingPack, tips, cost)
	if not phaseOk then return ShopRefusal.REASONS.wrong_phase end
	if pendingPack then return ShopRefusal.REASONS.pack_open end
	if (tips or 0) < (cost or 0) then return ShopRefusal.REASONS.tips end
	return nil
end

function ShopRefusal.haggle(code)
	return ShopRefusal.REASONS[code] or "Marlo shakes his head."
end

function ShopRefusal.rerollLabel(cost)
	return string.format("Reroll %d", math.floor(cost or 0))
end

function ShopRefusal.haggleLabel(view)
	if view and view.used then return "Haggled" end
	return "Haggle"
end

-- nil when a click on Haggle should open the chooser; otherwise the one line to show.
function ShopRefusal.haggleDenied(view)
	if not view then return ShopRefusal.REASONS.wrong_phase end
	if view.available then return nil end
	if view.open then return nil end -- the bar is already up
	return ShopRefusal.haggle(view.reason or (view.used and "used") or "wrong_phase")
end

return ShopRefusal
