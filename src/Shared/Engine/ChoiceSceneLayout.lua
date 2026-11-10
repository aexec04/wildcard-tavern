--[[
	Shared/Engine/ChoiceSceneLayout.lua
	Pure numbers for the run-start Choice screens (Choose your first Patron, Choose a blessing, event cards),
	drawn by Client/ChoicePanel.lua as a painted scene: the tavern room painting under ONE smooth scrim, a
	brass-edged title plate, framed paper cards standing on the table, a round medallion per option, candle glow
	at both sides. Tested in EngineTests ("Choice scene").

	  ChoiceSceneLayout.PALETTE        colours as {r,g,b}
	  ChoiceSceneLayout.PLATES         every text-on-fill pair, so a test can check 4.5:1
	  ChoiceSceneLayout.cardSpots(w, h, count, cardW, cardH)   card centres standing on the table
]]

local ChoiceSceneLayout = {}

ChoiceSceneLayout.PALETTE = {
	paper = { 238, 222, 186 },
	paperDecline = { 214, 198, 160 },
	ink = { 48, 32, 18 },
	bless = { 34, 84, 40 },
	curse = { 130, 38, 30 },
	plate = { 44, 32, 22 },
	plateText = { 252, 240, 214 },
	brass = { 200, 160, 84 },
	buttonGreen = { 46, 98, 52 },
	buttonBrown = { 86, 58, 30 },
	buttonText = { 252, 244, 224 },
	scrim = { 14, 10, 6 },
}

-- { name, text colour key, fill colour key }
ChoiceSceneLayout.PLATES = {
	{ "title", "plateText", "plate" },
	{ "subtitle", "plateText", "plate" },
	{ "cardName", "ink", "paper" },
	{ "cardBlessing", "bless", "paper" },
	{ "cardCurse", "curse", "paper" },
	{ "cardInk", "ink", "paperDecline" },
	{ "choose", "buttonText", "buttonGreen" },
	{ "decline", "buttonText", "buttonBrown" },
}

-- Soft radial: many faint rings, never one disc with a visible edge.
-- Cards stand in one row on the table, centred, in the lower part of the screen.
function ChoiceSceneLayout.cardSpots(w, h, count, cardW, cardH)
	local gap = 22
	local total = count * cardW + (count - 1) * gap
	local x0 = (w - total) / 2 + cardW / 2
	local y = math.min(h - cardH / 2 - 24, h * 0.62)
	local spots = {}
	for i = 1, count do
		spots[i] = { x = x0 + (i - 1) * (cardW + gap), y = y }
	end
	return spots
end

return ChoiceSceneLayout
