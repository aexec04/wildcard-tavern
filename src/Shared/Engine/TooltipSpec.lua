--[[
	Shared/Engine/TooltipSpec.lua
	The one shared tooltip's look and placement rules (pure, tested). Client/Tooltip.lua draws it.

	A tooltip has exactly ONE border (the outer UIStroke) and padding inside it, so no line can ever run
	through the text: the old tooltip used polishPanel, which adds a gold ring AND an inner rim frame, and that
	inner rim cut through the text lines.

	Spec fields: borders (outer strokes, must be 1), innerRim (must be false), stroke (px), padX, padY,
	maxWidth (text wraps beyond it), gap (to the target), margin (to the screen edge).

	place(pos, size, tip, screen, align) -> x, y
	    pos/size = the target's AbsolutePosition/AbsoluteSize ({X,Y} tables), tip = tooltip size, screen = screen size.
	    Above the target with `gap`, below when there is no room above, clamped inside the screen by `margin`.
	    align "left": the tooltip's right edge lines up with the target's right edge (buttons on the right side).
	textClear(spec) -> true when the padding is wider than the border plus a 4px breathing space on every side.
]]

local TooltipSpec = {}

TooltipSpec.Spec = {
	borders = 1,
	innerRim = false,
	stroke = 1.5,
	padX = 12,
	padY = 8,
	maxWidth = 280,
	gap = 8,
	margin = 6,
	textSize = 16,
}

function TooltipSpec.textClear(spec)
	spec = spec or TooltipSpec.Spec
	return spec.borders == 1 and spec.innerRim == false
		and spec.padX >= spec.stroke + 4 and spec.padY >= spec.stroke + 4
end

function TooltipSpec.place(pos, size, tip, screen, align, spec)
	spec = spec or TooltipSpec.Spec
	local x
	if align == "left" then
		x = pos.X + size.X - tip.X
	else
		x = pos.X + size.X / 2 - tip.X / 2
	end
	local y = pos.Y - tip.Y - spec.gap
	if y < spec.margin then
		y = pos.Y + size.Y + spec.gap
	end
	x = math.max(spec.margin, math.min(x, screen.X - tip.X - spec.margin))
	y = math.max(spec.margin, math.min(y, screen.Y - tip.Y - spec.margin))
	return x, y
end

return TooltipSpec
