--[[
	Client/TableCheck.lua
	Studio only (DebugGoto "tablecheck"). Reads every ornate table piece's live rect, converts it to the 1672 x 941 reference scale and
	prints it next to the reference target, warning when one is more than 25 px off. Reads only. Open the play screen first
	(DebugGoto round1 then patrons:5). Rules and targets: Engine/TableCheck.
]]
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TableCheck"))

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

local function rectOf(g) return { x = g.AbsolutePosition.X, y = g.AbsolutePosition.Y, w = g.AbsoluteSize.X, h = g.AbsoluteSize.Y } end

local function union(list)
	local x0, y0, x1, y1
	for _, g in ipairs(list) do
		local r = rectOf(g)
		x0 = x0 and math.min(x0, r.x) or r.x
		y0 = y0 and math.min(y0, r.y) or r.y
		x1 = x1 and math.max(x1, r.x + r.w) or r.x + r.w
		y1 = y1 and math.max(y1, r.y + r.h) or r.y + r.h
	end
	if not x0 then return nil end
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

function M.run()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = pg:FindFirstChild("GameUI") or pg:FindFirstChildOfClass("ScreenGui")
	if not gui then warn("[TableCheck] no GameUI found") return 0 end
	local guiW = gui.AbsoluteSize.X
	-- AbsolutePosition leaves out the top GuiInset, the layout is drawn in the full viewport height: add the inset back to y, scale y by that height.
	local cam = workspace.CurrentCamera
	local root = gui:FindFirstChild("GameRoot")
	local inset = Rules.insetFrom(GuiService:GetGuiInset().Y, cam and cam.ViewportSize.Y, gui.AbsoluteSize.Y, root and root.AbsolutePosition.Y)
	local guiH = gui.AbsoluteSize.Y + inset
	local live = {}
	local function byName(name)
		for _, d in ipairs(pg:GetDescendants()) do
			if d.Name == name and d:IsA("GuiObject") and d.AbsoluteSize.X > 0 and visible(d) then return d end
		end
	end
	local function byWord(word) -- a TextButton whose drawn word (KitLabel or its own text) is `word`
		for _, d in ipairs(pg:GetDescendants()) do
			if d:IsA("TextButton") and visible(d) and d.AbsoluteSize.X > 0 then
				local kl = d:FindFirstChild("KitLabel")
				if (kl and kl.Text == word) or d.Text == word then return d end
			end
		end
	end
	for _, key in ipairs({ "TargetBox", "RoundName", "TipsPill", "ScorePlate", "RoundHint", "SortRank", "SortSuit", "DeckCountPill" }) do
		local g = byName(key)
		if g then live[key] = rectOf(g) end
	end
	local play, discard = byWord("Play Hand"), byWord("Discard")
	if play then live.PlayHand = rectOf(play) end
	if discard then live.Discard = rectOf(discard) end
	local seats = {}
	local row = byName("PatronRow")
	if row then
		for _, d in ipairs(row:GetDescendants()) do
			if d:IsA("ImageLabel") and d.Name == "PatronArt" and visible(d) then seats[#seats + 1] = d end
		end
	end
	if #seats > 0 then live.PatronSlots = union(seats) end
	local lines, warns = Rules.compare(live, guiW, guiH, inset)
	local kx, ky = Rules.scales(guiW, guiH)
	print(string.format("[TableCheck] GUI %d x %d, inset %d, reference %d x %d (scale x %.3f, y %.3f)", guiW, guiH, inset, Rules.REF_W, Rules.REF_H, kx, ky))
	for _, l in ipairs(lines) do print("[TableCheck] " .. l) end
	for _, w in ipairs(warns) do warn("[TableCheck] " .. w) end
	print(string.format("[TableCheck] %d of %d pieces within %d px", #Rules.TARGETS - #warns, #Rules.TARGETS, Rules.TOLERANCE))
	return #warns
end

return M
