--[[
	Engine/LedgerLayout.lua
	Pure layout maths for the Tavern Ledger book (Client/LedgerBook.lua). Every number comes from the measured art in
	Engine/LedgerBookGeometry.lua (page quads and the slightly sloped ruled lines of ledger_book_open), so text sits ON
	the book's own lines at the book's own angle. All positions are fractions of the book image unless a name says Px.
]]

local Geometry = require(script.Parent.LedgerBookGeometry)

local LedgerLayout = {}

LedgerLayout.GEOMETRY = Geometry
LedgerLayout.ASPECT = Geometry.aspect -- book image width / height; the drawn book keeps it
LedgerLayout.LINE_COUNT = 9
LedgerLayout.UP_PX = 3 -- the text baseline sits this far above its ruled line
LedgerLayout.INSET = 0.08 -- of the usable line length, each end
LedgerLayout.INK = { 40, 26, 14 } -- dark brown, full opacity
LedgerLayout.INK_DIM = { 70, 48, 28 } -- the softer ink, still 7:1 on the paper

-- ribbon tabs on the right edge of the book, level with the top of the pages (fractions of the book)
LedgerLayout.TABS = { x = 0.975, w = 0.085, h = 0.105, y = 0.154, step = 0.12 }

local function lerp(a, b, t) return a + (b - a) * t end

function LedgerLayout.lines(side)
	return Geometry[side].lines
end

function LedgerLayout.quad(side)
	return Geometry[side].quad
end

-- bounding box { x, y, w, h } of a page quad: the page frame in the book
function LedgerLayout.pageBox(side)
	local q = Geometry[side].quad
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(q) do
		x0, y0, x1, y1 = math.min(x0, p[1]), math.min(y0, p[2]), math.max(x1, p[1]), math.max(y1, p[2])
	end
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

-- the quad's left and right edge at height y (the edges are near vertical)
local function edgeAt(quad, y, leftEdge)
	local a, b
	if leftEdge then a, b = quad[1], quad[4] else a, b = quad[2], quad[3] end
	local t = (y - a[2]) / (b[2] - a[2])
	return lerp(a[1], b[1], math.max(0, math.min(1, t)))
end

-- is the point inside the page quad, shrunk by `inset` (fraction of the book width) from the left and right edges
function LedgerLayout.insideQuad(side, x, y, inset)
	local q = Geometry[side].quad
	inset = inset or 0
	return y >= q[1][2] and y <= q[4][2] and x >= edgeAt(q, y, true) + inset - 1e-9 and x <= edgeAt(q, y, false) - inset + 1e-9
end

-- Usable span of ruled line i on a page: the line clipped to the quad, then inset 8 percent at both ends.
-- Returns { x0, y0, x1, y1, angle } (book fractions) or nil.
function LedgerLayout.span(side, i)
	local g = Geometry[side]
	local ln = g.lines[i]
	if not ln then return nil end
	local slope = (ln.y1 - ln.y0) / (ln.x1 - ln.x0)
	local function yAt(x) return ln.y0 + slope * (x - ln.x0) end
	local xa = math.max(ln.x0, edgeAt(g.quad, ln.y0, true))
	local xb = math.min(ln.x1, edgeAt(g.quad, ln.y1, false))
	local inset = LedgerLayout.INSET * (xb - xa)
	xa, xb = xa + inset, xb - inset
	return { x0 = xa, y0 = yAt(xa), x1 = xb, y1 = yAt(xb), angle = ln.angle }
end

-- point at t (0..1) along the usable span of a line
function LedgerLayout.point(side, i, t)
	local s = LedgerLayout.span(side, i)
	return lerp(s.x0, s.x1, t), lerp(s.y0, s.y1, t)
end

-- mean ruled-line angle of a page (degrees): widgets that are not text rows tilt with the page
function LedgerLayout.pageAngle(side)
	local sum, n = 0, 0
	for _, ln in ipairs(Geometry[side].lines) do sum, n = sum + ln.angle, n + 1 end
	return n > 0 and sum / n or 0
end

-- mean distance between ruled lines as a fraction of the book height
function LedgerLayout.spacing()
	local ln = Geometry.left.lines
	return (ln[#ln].y0 - ln[1].y0) / (#ln - 1)
end

-- Text sizes in px for a book bookH px tall: body at least 20 px at 1920x1080, never below 14.
function LedgerLayout.sizes(bookH)
	local sp = LedgerLayout.spacing() * bookH
	local function clamp(v, lo, hi) return math.max(lo, math.min(hi, math.floor(v + 0.5))) end
	return { spacing = sp, body = clamp(sp * 0.58, 14, 22), head = clamp(sp * 0.74, 18, 26), big = clamp(sp * 1.0, 24, 40) }
end

-- A text row on line i from t0 to t1 of its usable span. The label is anchored at its bottom-left corner, rotated by the
-- line's angle, and lifted UP_PX perpendicular to the line. Positions are in the PAGE frame (the page box) as scale plus a
-- pixel offset, so they follow the book's size. Returns { xs, xo, ys, yo, ws, angle, lenFrac } .
function LedgerLayout.place(side, i, t0, t1)
	local s = LedgerLayout.span(side, i)
	local box = LedgerLayout.pageBox(side)
	local x, y = LedgerLayout.point(side, i, t0)
	local xe = LedgerLayout.point(side, i, t1)
	local a = math.rad(s.angle)
	return {
		xs = (x - box.x) / box.w, xo = math.sin(a) * LedgerLayout.UP_PX,
		ys = (y - box.y) / box.h, yo = -math.cos(a) * LedgerLayout.UP_PX,
		ws = (xe - x) / box.w, angle = s.angle,
	}
end

-- pixel position (in the book) of a placed row's anchor and the line point under it, for a book bookW x bookH px
function LedgerLayout.anchorPx(side, i, t0, bookW, bookH)
	local p = LedgerLayout.place(side, i, t0, t0)
	local box = LedgerLayout.pageBox(side)
	local ax = (box.x + p.xs * box.w) * bookW + p.xo
	local ay = (box.y + p.ys * box.h) * bookH + p.yo
	local lx, ly = LedgerLayout.point(side, i, t0)
	return ax, ay, lx * bookW, ly * bookH
end

-- distance in px from a row's anchor to its ruled line (the perpendicular lift)
function LedgerLayout.liftPx(side, i, t0, bookW, bookH)
	local ax, ay, lx, ly = LedgerLayout.anchorPx(side, i, t0, bookW, bookH)
	local a = math.rad(LedgerLayout.span(side, i).angle)
	local dx, dy = ax - lx, ay - ly
	return dx * math.sin(a) - dy * math.cos(a) -- component along the upward normal
end

-- ===== turning one sheet (Ledger v6) =====
LedgerLayout.LIFT_PX = 6 -- the free edge lifts this far at the middle of a turn
LedgerLayout.GRAB = { edge = 0.12, corner = 0.22 } -- the outer edge strip (of the page width) and the bottom corner square
LedgerLayout.DRAG_START_PX = 8 -- the sheet leaves the page after this much travel, or at once on a click
LedgerLayout.COMPLETE_AT = 0.4 -- let go past this and the turn completes
LedgerLayout.FAST_PX_PER_S = 700 -- a quick flick completes the turn whatever the progress
LedgerLayout.TURN_TIME = 0.25 -- completing or springing back, seconds
LedgerLayout.END_LIFT = 0.12 -- first and last page: the sheet only lifts this far (progress) and falls back

-- The sheet at progress p (0 to 1). It is hinged on the spine: its width follows |cos(p * pi)|, it starts on the page being
-- turned (front face), crosses the spine at p = 0.5 and ends on the other page (back face). forward = right page to left page.
function LedgerLayout.sheetState(p, forward)
	p = math.max(0, math.min(1, p))
	local second = p >= 0.5
	local s = math.sin(math.pi * p)
	return {
		side = (forward == second) and "left" or "right", -- forward: right then left; backward: left then right
		width = math.abs(math.cos(math.pi * p)),
		face = second and "back" or "front",
		lift = LedgerLayout.LIFT_PX * s,
		shade = 0.35 * s, -- how dark the spine side of the sheet gets
		shadow = 0.3 * s, -- opacity of the shadow cast on the page underneath
	}
end

-- progress from the pointer's travel toward the spine (px, positive = toward it) and the page width in px
function LedgerLayout.dragProgress(dx, pageW)
	if pageW <= 0 then return 0 end
	return math.max(0, math.min(1, dx / pageW))
end

-- what letting go does: "complete" past COMPLETE_AT or on a fast flick, otherwise "back"
function LedgerLayout.release(p, velocity)
	if p > LedgerLayout.COMPLETE_AT or (velocity or 0) > LedgerLayout.FAST_PX_PER_S then return "complete" end
	return "back"
end

-- can the book turn from section `index` in direction dir (+1 forward, -1 back) among `count` sections
function LedgerLayout.canTurn(index, dir, count)
	local target = index + dir
	return target >= 1 and target <= count, target
end

-- the largest progress a drag may reach: the whole turn, or only a small lift at the first and last page
function LedgerLayout.maxProgress(canTurn)
	return canTurn and 1 or LedgerLayout.END_LIFT
end

-- grab hotspots of a page as fractions of its page box: the outer edge strip and the bottom corner square
function LedgerLayout.hotspots(side)
	local G = LedgerLayout.GRAB
	local outerLeft = side == "left"
	return {
		edge = { x = outerLeft and 0 or (1 - G.edge), y = 0, w = G.edge, h = 1 },
		corner = { x = outerLeft and 0 or (1 - G.corner), y = 1 - G.corner, w = G.corner, h = G.corner },
	}
end

-- WCAG contrast ratio between two { r, g, b } colours (0..255)
function LedgerLayout.contrast(c1, c2)
	local function lum(c)
		local function ch(v)
			v = v / 255
			return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
		end
		return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
	end
	local a, b = lum(c1), lum(c2)
	if a < b then a, b = b, a end
	return (a + 0.05) / (b + 0.05)
end

function LedgerLayout.paperRgb(side)
	local hex = Geometry[side].paper
	return { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) }
end

return LedgerLayout
