--[[
	Client/DecorCheck.lua
	Studio only (DebugGoto "decorcheck"). Open the table first (DebugGoto boss1 or the idle table). Prints the felt, inlay, rail and
	deck rects of the live Gameplay2 table and warns when the inlay or the deck leaves the felt or the rail covers a plate
	(rules in Engine/DecorCheck). Run it after scale:1920x957 and scale:1280x720. Reads only.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("DecorCheck"))
local CT = require(Engine:WaitForChild("ConceptTLayout"))
local Layout = require(Engine:WaitForChild("Gameplay2Layout"))

local M = {}

local function visible(g)
	local o = g
	while o and not o:IsA("PlayerGui") do
		if o:IsA("GuiObject") and not o.Visible then return false end
		if o:IsA("ScreenGui") and not o.Enabled then return false end
		o = o.Parent
	end
	return true
end

function M.run()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local rail
	for _, d in ipairs(pg:GetDescendants()) do
		if d.Name == "BottomRail" and d:IsA("GuiObject") then
			if visible(d) then rail = d; break end
			rail = rail or d
		end
	end
	if not rail then
		warn("[DecorCheck] the live table is not open (no BottomRail found): open a round first")
		return 1
	end
	if not visible(rail) then warn("[DecorCheck] BottomRail found but hidden (Image empty or table closed); measuring anyway") end
	local layer = rail.Parent
	local ox, oy = layer.AbsolutePosition.X, layer.AbsolutePosition.Y
	local w, h = layer.AbsoluteSize.X, layer.AbsoluteSize.Y
	local function live(name)
		local g = layer:FindFirstChild(name)
		if not g or not g:IsA("GuiObject") then return nil end
		return { x = g.AbsolutePosition.X - ox, y = g.AbsolutePosition.Y - oy, w = g.AbsoluteSize.X, h = g.AbsoluteSize.Y }
	end
	local r = Layout.rects(w, h)
	local dc = CT.decorFor(r, w, h)
	local railPic = live("BottomRail") or dc.rail
	local railBox = { x = 0, y = dc.rail.box.y, w = w, h = dc.rail.box.h }
	local bad = 0
	for _, nm in ipairs({ "FeltInlay", "FeltRimShadow" }) do
		local g = layer:FindFirstChild(nm)
		if g and (not g.Visible or g.AbsoluteSize.X <= 0) then warn("[DecorCheck] " .. nm .. " exists but is hidden or 0 wide"); bad = bad + 1 end
	end
	local plates = {}
	for _, k in ipairs({ "sortRank", "sortSuit", "play", "discard", "deckCount" }) do plates[#plates + 1] = { label = k, rect = r[k] } end
	local lines, warns = Rules.check({
		w = w, h = h,
		felt = CT.feltFor(w, h).rim,
		inlay = layer:FindFirstChild("FeltInlay") and layer.FeltInlay.Visible and dc.inlay.box or nil, -- the ring's visible line, nil while the picture is hidden
		deck = r.deck, tilt = CT.DECK_TILT,
		rail = { x = railPic.x, w = railPic.w, box = railBox },
		plates = plates,
	})
	print(string.format("[DecorCheck] %dx%d %s", w, h, table.concat(lines, "; ")))
	do -- [FeltInlay]: the ring picture's visible line against the felt rect
		local ring, fe = live("FeltInlay") and dc.inlay.box or nil, CT.feltFor(w, h).rim
		if ring then
			local gap = math.min(ring.x - fe.x, ring.y - fe.y, fe.x + fe.w - ring.x - ring.w, fe.y + fe.h - ring.y - ring.h)
			print(string.format("[FeltInlay] ring x%d y%d w%d h%d, felt x%d y%d w%d h%d, gap %d, inside %s", math.floor(ring.x + 0.5), math.floor(ring.y + 0.5), math.floor(ring.w + 0.5), math.floor(ring.h + 0.5), fe.x, fe.y, fe.w, fe.h, math.floor(gap + 0.5), tostring(gap >= CT.INLAY_MARGIN)))
		end
	end
	for _, msg in ipairs(warns) do warn("[DecorCheck] " .. msg) end
	print(string.format("[DecorCheck] %d warnings", #warns + bad))
	return #warns + bad
end

return M
