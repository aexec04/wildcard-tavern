--[[
	tools/overlay_audit.luau
	Run with execute_luau in Studio Play (client side). Opens each screen through DebugGoto and, for every open page or popup
	(a visible GuiObject whose name ends in "Backdrop" directly under a ScreenGui), lists every visible GuiObject OUTSIDE it that
	would draw above it:
	  visible, not fully transparent, size above 0, every ancestor visible, overlapping the page on screen, and either in a
	  ScreenGui with a higher DisplayOrder, or in the same ScreenGui with a higher draw order (ZIndex in Global mode, the ZIndex of
	  the branch under the common ancestor in Sibling mode).
	Prints "PASS <screen>" or "FAIL <screen>" followed by the offending paths (first 15). Ends with a one line total.
	Layer rules live in src/Shared/Engine/Layers.lua; fix a FAIL by moving the offender to the right band (or hiding it through
	PopupLayers), never by raising the page's ZIndex by a bare number.
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer
assert(player, "run this in Play, on the client")
local playerGui = player:WaitForChild("PlayerGui")

local SETS = { "classic_tavern", "golden_gala", "harbor_lights" }
local SCREENS = { "menu", "map", "tome:collection", "tome:cardsets", "tome:badges", "news", "haggle", "haggle:good" }
for _, set in ipairs(SETS) do
	SCREENS[#SCREENS + 1] = "round1:" .. set
	SCREENS[#SCREENS + 1] = "boss1:" .. set
end
-- screens that may not exist in every build: asked for, but a missing one only warns
local OPTIONAL = { "store", "season", "dailyrewards", "quests" }
for _, s in ipairs(OPTIONAL) do SCREENS[#SCREENS + 1] = s end

local function gotoScreen(value, wait)
	local v = player:FindFirstChild("DebugGoto")
	if not v then
		v = Instance.new("StringValue")
		v.Name = "DebugGoto"
		v.Parent = player
	end
	v.Value = ""
	task.wait(0.2)
	v.Value = value
	task.wait(wait or 2.5)
end

local function shown(inst)
	-- every GuiObject ancestor up to the ScreenGui is Visible, and the ScreenGui is Enabled
	local p = inst
	while p and not p:IsA("ScreenGui") do
		if p:IsA("GuiObject") and not p.Visible then return false end
		p = p.Parent
	end
	return p ~= nil and p.Enabled
end

local function draws(inst)
	if not inst:IsA("GuiObject") or not shown(inst) then return false end
	if inst.AbsoluteSize.X <= 0 or inst.AbsoluteSize.Y <= 0 then return false end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") then
		if inst.Text ~= "" and inst.TextTransparency < 1 then return true end
	end
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		if inst.Image ~= "" and inst.ImageTransparency < 1 then return true end
	end
	if inst.BackgroundTransparency < 1 then return true end
	return inst:FindFirstChildOfClass("UIStroke") ~= nil
end

local function overlaps(a, b)
	local ap, as, bp, bs = a.AbsolutePosition, a.AbsoluteSize, b.AbsolutePosition, b.AbsoluteSize
	return ap.X < bp.X + bs.X and bp.X < ap.X + as.X and ap.Y < bp.Y + bs.Y and bp.Y < ap.Y + as.Y
end

local function chain(inst)
	local c = {}
	local p = inst
	while p and not p:IsA("ScreenGui") do
		table.insert(c, 1, p)
		p = p.Parent
	end
	return c, p
end

-- true when `other` draws above `page` (both in the same ScreenGui)
local function above(other, page, gui)
	if gui.ZIndexBehavior == Enum.ZIndexBehavior.Global then
		return other.ZIndex > page.ZIndex
	end
	local a, b = chain(other), chain(page)
	local i = 1
	while a[i] and b[i] and a[i] == b[i] do i += 1 end
	if not (a[i] and b[i]) then return false end -- one is inside the other
	if a[i].ZIndex ~= b[i].ZIndex then return a[i].ZIndex > b[i].ZIndex end
	return a[i].LayoutOrder > b[i].LayoutOrder
end

local function openPages()
	local pages = {}
	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("ScreenGui") and gui.Enabled then
			for _, c in ipairs(gui:GetChildren()) do
				if c:IsA("GuiObject") and c.Name:sub(-8) == "Backdrop" and shown(c) and c.AbsoluteSize.X > 0 then
					table.insert(pages, { page = c, gui = gui })
				end
			end
		end
	end
	return pages
end

local function auditPage(entry)
	local page, gui = entry.page, entry.gui
	local bad = {}
	for _, other in ipairs(gui:GetDescendants()) do
		if other ~= page and draws(other) and not other:IsDescendantOf(page) and not page:IsDescendantOf(other)
			and overlaps(other, page) and above(other, page, gui) then
			table.insert(bad, other:GetFullName() .. " (ZIndex " .. other.ZIndex .. ")")
		end
	end
	for _, otherGui in ipairs(playerGui:GetChildren()) do
		if otherGui:IsA("ScreenGui") and otherGui ~= gui and otherGui.Enabled and otherGui.DisplayOrder > gui.DisplayOrder then
			for _, other in ipairs(otherGui:GetDescendants()) do
				if draws(other) and overlaps(other, page) then
					table.insert(bad, other:GetFullName() .. " (DisplayOrder " .. otherGui.DisplayOrder .. ")")
				end
			end
		end
	end
	return bad
end

local passed, failed = 0, 0
for _, screen in ipairs(SCREENS) do
	gotoScreen(screen, screen:find("^round1") and 5 or (screen:find("^boss1") and 6 or 2.5))
	local pages = openPages()
	if #pages == 0 then
		print("PASS " .. screen .. " (no page or popup open, nothing to cover)")
		passed += 1
	else
		local all = {}
		for _, entry in ipairs(pages) do
			for _, path in ipairs(auditPage(entry)) do
				table.insert(all, entry.page.Name .. " is covered by " .. path)
			end
		end
		if #all == 0 then
			print("PASS " .. screen .. " (" .. #pages .. " page" .. (#pages == 1 and "" or "s") .. " open)")
			passed += 1
		else
			print("FAIL " .. screen)
			for i = 1, math.min(#all, 15) do print("    " .. all[i]) end
			if #all > 15 then print("    ... and " .. (#all - 15) .. " more") end
			failed += 1
		end
	end
end
print(("[overlay_audit] %d PASS, %d FAIL over %d screens"):format(passed, failed, #SCREENS))
