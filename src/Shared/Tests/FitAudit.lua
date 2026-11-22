--[[
	Shared/Tests/FitAudit.lua
	Test helper: the screen fit audit. For every screen that has a layout module in Engine/, it builds the screen's rects at
	800x450, 1024x768, 1366x768 and 1920x1080 and checks:
	  on screen   every rect lies inside the view
	  text size   the text sizes a layout module publishes are at least 11 px (14 px for body text)
	  touch       button rects (named like a button) are at least 44 px on their short side
	  overlap     no two sibling rects overlap unless the pair is listed as intended (a rect that holds another one is nesting, not overlap)

	FitAudit.run(Engine) -> { failures = { { screen, size, rule, detail, lane } ... }, checked = n }
	Engine is a table of the loaded engine modules by name (the caller loads them, so this runs under plain Lua and in Studio).
	A screen is { name, lane, rects = function(w, h) -> map name -> {x,y,w,h} (nested maps allowed), texts = function(w, h)? -> map name -> {size, body},
	intended = { "a|b", ... } pair patterns, skip = { rule -> set of names } }.
	Pure data in, strings out: tools/fit_audit.lua prints the report into claude/FIT-AUDIT.md.
]]

local M = {}

M.SIZES = { { 800, 450 }, { 1024, 768 }, { 1366, 768 }, { 1920, 1080 } }
M.MIN_TEXT, M.MIN_BODY, M.MIN_TOUCH = 11, 14, 44
M.BUTTON_WORDS = { "button", "btn", "play", "discard", "sort", "buy", "close", "skip", "next", "reroll", "continue", "again", "tab", "sell", "use" }
local TOL = 1.5 -- px of slack for rounding

local function n0(x) return math.floor(x + 0.5) end

local function isRect(t)
	return type(t) == "table" and type(t.x) == "number" and type(t.y) == "number" and type(t.w) == "number" and type(t.h) == "number"
end

-- flatten a nested map into { { name, x, y, w, h, group } } (group = the table the rect came from, so siblings are known)
function M.flatten(map, prefix, out, group)
	out = out or {}
	prefix = prefix or ""
	group = group or "root"
	local keys = {}
	for k in pairs(map) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(keys) do
		local v = map[k]
		local name = prefix .. tostring(k)
		if isRect(v) then
			out[#out + 1] = { name = name, x = v.x, y = v.y, w = v.w, h = v.h, group = group }
		elseif type(v) == "table" then
			M.flatten(v, name .. ".", out, group .. "/" .. tostring(k))
		end
	end
	return out
end

local function looksLikeButton(name)
	local low = name:lower()
	for _, w in ipairs({ "count", "label", "text", "title", "scale" }) do
		if low:find(w, 1, true) then return false end -- a readout or caption, not a control
	end
	for _, w in ipairs(M.BUTTON_WORDS) do
		if low:find(w, 1, true) then return true end
	end
	return false
end

local function contains(a, b) -- a holds b
	return a.x <= b.x + TOL and a.y <= b.y + TOL and a.x + a.w >= b.x + b.w - TOL and a.y + a.h >= b.y + b.h - TOL
end

local function overlapArea(a, b)
	local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if w <= TOL or h <= TOL then return 0 end
	return w * h
end

local function listed(list, a, b)
	for _, pat in ipairs(list or {}) do
		local p, q = pat:match("^(.-)|(.-)$")
		if p and ((a:find(p) and b:find(q)) or (a:find(q) and b:find(p))) then return true end
	end
	return false
end

local function skipped(screen, rule, name)
	local set = screen.skip and screen.skip[rule]
	if not set then return false end
	for pat in pairs(set) do
		if name:find(pat) then return true end
	end
	return false
end

function M.checkScreen(screen, w, h)
	local fails = {}
	local function fail(rule, detail)
		fails[#fails + 1] = { screen = screen.name, size = w .. "x" .. h, rule = rule, detail = detail, lane = screen.lane }
	end
	local okBuild, map = pcall(screen.rects, w, h)
	if not okBuild or type(map) ~= "table" then
		fail("build", "layout call failed: " .. tostring(map))
		return fails
	end
	local rects = M.flatten(map)
	for _, r in ipairs(rects) do
		if not skipped(screen, "screen", r.name) and (r.x < -TOL or r.y < -TOL or r.x + r.w > w + TOL or r.y + r.h > h + TOL) then
			fail("screen", ("%s is off screen (x %d y %d w %d h %d)"):format(r.name, n0(r.x), n0(r.y), n0(r.w), n0(r.h)))
		end
		if looksLikeButton(r.name) and not skipped(screen, "touch", r.name) and r.w > 0 and r.h > 0 and math.min(r.w, r.h) < M.MIN_TOUCH - TOL then
			fail("touch", ("%s is %dx%d (needs %d)"):format(r.name, n0(r.w), n0(r.h), M.MIN_TOUCH))
		end
	end
	for i = 1, #rects do
		for j = i + 1, #rects do
			local a, b = rects[i], rects[j]
			if a.group == b.group and not contains(a, b) and not contains(b, a) and overlapArea(a, b) > 0
				and not listed(screen.intended, a.name, b.name) and not skipped(screen, "overlap", a.name) and not skipped(screen, "overlap", b.name) then
				fail("overlap", ("%s and %s overlap by about %d px"):format(a.name, b.name, n0(overlapArea(a, b) ^ 0.5)))
			end
		end
	end
	if screen.texts then
		local okT, texts = pcall(screen.texts, w, h)
		if okT and type(texts) == "table" then
			for name, t in pairs(texts) do
				local floor = t.body and M.MIN_BODY or M.MIN_TEXT
				if type(t.size) == "number" and t.size < floor then
					fail("text", ("%s is %d px (needs %d)"):format(name, n0(t.size), floor))
				end
			end
		end
	end
	return fails
end

function M.run(screens)
	local all, checked = {}, 0
	for _, screen in ipairs(screens) do
		for _, sz in ipairs(M.SIZES) do
			checked = checked + 1
			for _, f in ipairs(M.checkScreen(screen, sz[1], sz[2])) do all[#all + 1] = f end
		end
	end
	return { failures = all, checked = checked }
end

return M
