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
	local rail = pg:FindFirstChild("BottomRail", true)
	if not rail or not visible(rail) then
		warn("[DecorCheck] the live table is not open (no visible BottomRail): open a round first")
		return 1
	end
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
		if not g or not g.Visible or g.AbsoluteSize.X <= 0 then warn("[DecorCheck] " .. nm .. " is missing, hidden or 0 wide"); bad = bad + 1 end
	end
	local plates = {}
	for _, k in ipairs({ "sortRank", "sortSuit", "play", "discard", "deckCount" }) do plates[#plates + 1] = { label = k, rect = r[k] } end
	local lines, warns = Rules.check({
		w = w, h = h,
		felt = live("FeltRimShadow") or CT.feltFor(w, h).rim,
		inlay = live("FeltInlay") or CT.feltFor(w, h).inlay,
		deck = r.deck, tilt = CT.DECK_TILT,
		rail = { x = railPic.x, w = railPic.w, box = railBox },
		plates = plates,
	})
	print(string.format("[DecorCheck] %dx%d %s", w, h, table.concat(lines, "; ")))
	for _, msg in ipairs(warns) do warn("[DecorCheck] " .. msg) end
	print(string.format("[DecorCheck] %d warnings", #warns + bad))
	return #warns + bad
end

return M
