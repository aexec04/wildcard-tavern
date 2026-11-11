--[[
	Shared/Engine/NewsBoardLayout.lua
	Tavern News drawn like the Notice Board on the menu wall: a cork board, each event a small paper note pinned to it with a
	brass pin and a fixed hand-hung tilt. Pure numbers (tested at 1920x1080, 1280x720 and 800x450); drawn by Client/NewsPanel.lua.

	  NewsBoardLayout.board(W, H)                     -> { x, y, w, h }   the cork board, centred on the screen
	  NewsBoardLayout.areas(board)                    -> { heading, subtitle, notes, close }   rects inside the board (board-relative)
	  NewsBoardLayout.layout(areaW, areaH, notes)     -> { scale, scroll, contentH, rects = { { id, x, y, w, h, tilt } } }
	      notes = { { id, claim = bool } }; claim notes are taller (they carry a Claim button). Notes keep 10 px from the board edge,
	      one grid (as many columns as fit), the last row centred, the whole block centred; FEW notes are drawn bigger (up to
	      MAX_SCALE) so the board never looks empty, MANY notes shrink down to MIN_SCALE and then the board scrolls.
	  NewsBoardLayout.tiltFor(id)                     -> degrees, at most 2, the same for the same id
	  NewsBoardLayout.iconPiece(row)                  -> the HudKit piece for a note's small icon, or nil (never an emoji)
]]

local M = {}

M.MARGIN = 10 -- from the board's edge to the notes
M.GAP = 12
M.NOTE_W, M.NOTE_H, M.NOTE_H_CLAIM = 180, 112, 146 -- three columns fit the smallest board (800x450)
M.MIN_SCALE, M.MAX_SCALE = 0.9, 1.3 -- below 0.9 the 14 px text would be unreadable: the board scrolls instead
M.HEADING_H, M.SUBTITLE_H, M.CLOSE_H = 40, 26, 44

function M.board(W, H)
	local w = math.max(480, math.min(760, math.floor(W * 0.74)))
	local h = math.max(340, math.min(600, math.floor(H * 0.92)))
	w, h = math.min(w, W), math.min(h, H)
	return { x = (W - w) / 2, y = (H - h) / 2, w = w, h = h }
end

-- Where things sit inside the board (board-relative pixels): the nameplate hangs over the top edge, the paper strip under it, the
-- Close button at the foot, the notes between.
function M.areas(board)
	local top = 16 + M.HEADING_H -- the plaque starts 16 px inside the board
	local subTop = top + 4
	local notesTop = subTop + M.SUBTITLE_H + 8
	local notesBottom = board.h - M.CLOSE_H - 20
	return {
		heading = { x = (board.w - 280) / 2, y = 16, w = 280, h = M.HEADING_H },
		subtitle = { x = M.MARGIN + 20, y = subTop, w = board.w - 2 * (M.MARGIN + 20), h = M.SUBTITLE_H },
		notes = { x = M.MARGIN, y = notesTop, w = board.w - 2 * M.MARGIN, h = notesBottom - notesTop },
		close = { x = (board.w - 140) / 2, y = board.h - M.CLOSE_H - 10, w = 140, h = M.CLOSE_H },
	}
end

function M.tiltFor(id)
	local h = 7
	for i = 1, #tostring(id) do h = (h * 31 + tostring(id):byte(i)) % 9973 end
	return (h % 5 - 2) * 0.8 -- -1.6, -0.8, 0, 0.8 or 1.6 degrees
end

local function gridAt(scale, areaW, notes)
	local w = M.NOTE_W * scale
	local gap = M.GAP * scale
	local cols = math.max(1, math.floor((areaW + gap) / (w + gap)))
	cols = math.min(cols, math.max(1, #notes))
	local rows, y = {}, 0
	local i = 1
	while i <= #notes do
		local row, rowH = {}, 0
		for c = 1, cols do
			local n = notes[i]
			if not n then break end
			local h = (n.claim and M.NOTE_H_CLAIM or M.NOTE_H) * scale
			row[#row + 1] = { note = n, h = h }
			rowH = math.max(rowH, h)
			i = i + 1
		end
		rows[#rows + 1] = { cells = row, h = rowH, y = y }
		y = y + rowH + gap
	end
	return rows, math.max(0, y - gap), w, gap
end

function M.layout(areaW, areaH, notes)
	notes = notes or {}
	if #notes == 0 then return { scale = 1, scroll = false, contentH = 0, rects = {} } end
	local usableW = areaW
	local chosen
	-- the biggest scale (few notes are drawn big) at which the whole grid fits the area; below MIN_SCALE the board scrolls
	local scale = M.MAX_SCALE
	while scale >= M.MIN_SCALE - 1e-9 do
		local rows, contentH, w = gridAt(scale, usableW, notes)
		local widest = 0
		for _, r in ipairs(rows) do widest = math.max(widest, #r.cells) end
		if contentH <= areaH and widest * w + (widest - 1) * M.GAP * scale <= usableW + 1e-6 then
			chosen = { scale = scale, scroll = false }
			break
		end
		scale = scale - 0.02
	end
	chosen = chosen or { scale = M.MIN_SCALE, scroll = true }
	local rows, contentH, w, gap = gridAt(chosen.scale, usableW, notes)
	local out = { scale = chosen.scale, scroll = chosen.scroll, contentH = contentH, rects = {} }
	local y0 = chosen.scroll and 0 or math.max(0, (areaH - contentH) / 2) -- centre the block when it fits
	for _, row in ipairs(rows) do
		local rowW = #row.cells * w + (#row.cells - 1) * gap
		local x0 = (areaW - rowW) / 2 -- the last row is centred too
		for c, cell in ipairs(row.cells) do
			out.rects[#out.rects + 1] = {
				id = cell.note.id, x = x0 + (c - 1) * (w + gap), y = y0 + row.y + (row.h - cell.h) / 2, w = w, h = cell.h,
				tilt = M.tiltFor(cell.note.id),
			}
		end
	end
	return out
end

-- The small kit icon on a note: coins for an event with rewards, a seat for the rest. nil = no icon (never an emoji).
function M.iconPiece(row)
	if type(row) ~= "table" then return nil end
	if row.rewards and #row.rewards > 0 then return "icon_tips" end
	return "icon_slot"
end

return M
