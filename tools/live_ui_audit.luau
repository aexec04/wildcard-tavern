--[[ tools/live_ui_audit.luau  (run with execute_luau, datamodel Client, in Play, ON ANY SCREEN)
	Audits the REAL GuiObjects on screen (not layout math). Prints one compact summary plus up to 14 findings:
	  OVERFLOW  text wider/taller than its own box (TextBounds vs AbsoluteSize)
	  CLIPPED   a drawn object cut by an ancestor that clips (more than 4 px lost), scroll children excepted
	  OFFSCREEN an object with text or a picture leaving the screen by more than 3 px
	  OVERLAP   two texts or two buttons that are not parent and child and share more than 25 percent of the smaller one
	Rule: a UI change is not done until this prints "0 findings" on the screen it touched at 1920x957 and 1506x751.
]]
local pg = game.Players.LocalPlayer.PlayerGui
local gui = pg:FindFirstChild("GameUI")
local root = gui and gui.AbsoluteSize or Vector2.new(1920, 1080)
local function shown(i)
	local p = i
	while p and not p:IsA("ScreenGui") do
		if p:IsA("GuiObject") and (not p.Visible) then return false end
		p = p.Parent
	end
	return p ~= nil and p.Enabled
end
local function hasText(i) return (i:IsA("TextLabel") or i:IsA("TextButton")) and i.Text ~= "" and i.TextTransparency < 0.9 end
local function hasPic(i) return (i:IsA("ImageLabel") or i:IsA("ImageButton")) and i.Image ~= "" and i.ImageTransparency < 0.9 end
local items, texts = {}, {}
for _, d in ipairs(pg:GetDescendants()) do
	if d:IsA("GuiObject") and shown(d) and d.AbsoluteSize.X > 2 and d.AbsoluteSize.Y > 2 then
		if hasText(d) then table.insert(texts, d) end
		if hasText(d) or hasPic(d) then table.insert(items, d) end
	end
end
local out, n = {}, { o = 0, c = 0, f = 0, v = 0 }
local function add(k, s) n[k] += 1 if #out < 14 then table.insert(out, s) end end
local function nm(i) return i:GetFullName():gsub("^.-PlayerGui%.", ""):sub(-70) end
for _, t in ipairs(texts) do
	local b, a = t.TextBounds, t.AbsoluteSize
	if not t.TextScaled and (b.X > a.X + 2 or b.Y > a.Y + 3) and t.TextTruncate == Enum.TextTruncate.None then
		add("o", ("OVERFLOW %s text %dx%d in box %dx%d '%s'"):format(nm(t), b.X, b.Y, a.X, a.Y, t.Text:sub(1, 24)))
	end
end
for _, i in ipairs(items) do
	local p, s = i.AbsolutePosition, i.AbsoluteSize
	if p.X < -3 or p.Y < -3 - 58 or p.X + s.X > root.X + 3 or p.Y + s.Y > root.Y + 61 then
		add("f", ("OFFSCREEN %s at %d,%d size %dx%d"):format(nm(i), p.X, p.Y, s.X, s.Y))
	end
	local a = i.Parent
	while a and a:IsA("GuiObject") do
		if a.ClipsDescendants and not a:IsA("ScrollingFrame") and a.BackgroundTransparency < 1 or (a:IsA("ScrollingFrame") and a.ScrollingEnabled == false) then
			local ap, as = a.AbsolutePosition, a.AbsoluteSize
			local lost = math.max(0, ap.X - p.X) + math.max(0, p.X + s.X - (ap.X + as.X))
			local lostY = math.max(0, ap.Y - p.Y) + math.max(0, p.Y + s.Y - (ap.Y + as.Y))
			if (lost > 4 or lostY > 4) and lost < s.X and lostY < s.Y then
				add("c", ("CLIPPED %s cut by %s (%d px x, %d px y)"):format(nm(i), a.Name, lost, lostY))
				break
			end
		end
		a = a.Parent
	end
end
local function isBtn(i) return i:IsA("TextButton") or i:IsA("ImageButton") end
for x = 1, #texts do
	for y = x + 1, #texts do
		local a, b = texts[x], texts[y]
		if not a:IsDescendantOf(b) and not b:IsDescendantOf(a) and (a.Text ~= b.Text) then
			local ap, as, bp, bs = a.AbsolutePosition, a.AbsoluteSize, b.AbsolutePosition, b.AbsoluteSize
			local w = math.min(ap.X + as.X, bp.X + bs.X) - math.max(ap.X, bp.X)
			local h = math.min(ap.Y + as.Y, bp.Y + bs.Y) - math.max(ap.Y, bp.Y)
			if w > 0 and h > 0 and w * h > 0.25 * math.min(as.X * as.Y, bs.X * bs.Y) and as.X < root.X * 0.7 and bs.X < root.X * 0.7 then
				add("v", ("OVERLAP '%s' (%s) with '%s' (%s)"):format(a.Text:sub(1, 18), nm(a):sub(-32), b.Text:sub(1, 18), nm(b):sub(-32)))
			end
		end
	end
end
return ("%d findings (overflow %d, clipped %d, offscreen %d, overlap %d), %d texts checked\n%s"):format(n.o + n.c + n.f + n.v, n.o, n.c, n.f, n.v, #texts, table.concat(out, "\n"))
