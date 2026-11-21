--[[
	Shared/Engine/ButtonFeel.lua
	Pure rules for how the gameplay buttons feel (tested). Client/ActionButtonFX applies them with tweens.

	scaleFor(hover, pressed) -> number    1 at rest, 1.05 on hover, 0.94 pressed (a 6 percent squash)
	playReady(selectedCount) -> bool      Play Hand (and Discard) light up when at least 1 card is selected
	                                      (the rule allows 1 to 5; the server still validates)
	MIN_HIT                               every gameplay button keeps a hit area of at least this many px
]]

local ButtonFeel = {}

ButtonFeel.HOVER_SCALE = 1.05
ButtonFeel.PRESS_SCALE = 0.94
ButtonFeel.MIN_HIT = 44

function ButtonFeel.scaleFor(hover, pressed)
	if pressed then return ButtonFeel.PRESS_SCALE end
	if hover then return ButtonFeel.HOVER_SCALE end
	return 1
end

-- Rest position of a hovering button. The rest spot is read when the hover starts (never when the button is created),
-- so a row whose Position is set later by a layout rests where the layout put it. While a hover is active the stored
-- spot is kept. Returns the rest spot to use.
function ButtonFeel.restFor(hovering, storedRest, currentPos)
	if hovering and storedRest ~= nil then return storedRest end
	return currentPos
end

function ButtonFeel.playReady(selectedCount)
	return type(selectedCount) == "number" and selectedCount >= 1 and selectedCount <= 5
end

return ButtonFeel
