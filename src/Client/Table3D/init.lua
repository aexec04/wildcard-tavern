--[[
	Client/Table3D (init.lua)
	The 3D play table: one scene, a fixed perspective camera, the hand and the played cards lying on the felt, real
	light, and a score that throws chips. The game underneath is untouched: rules, layout, input and the 2D HUD are
	the hub's, and this module only draws. The Counter, the menu and the map never see it.

	  Scene   builds the table, props and lights from a theme           Rig    the camera and screen-to-felt lookup
	  Cards   the cards on the felt, following their 2D twins           Chips  the pot
	  React   the table's answer to a thump                             Veil   holds the painted 2D table invisible

	A theme is a folder of four data modules, Shared/TableThemes/<Name>/{Materials,Lighting,Props,Felt}; which one is
	used is Engine/TableTheme.default(). A second theme is a second folder.

	Table3D.start{ root, handFrame, deckWidget, scoreBox }  -> true when the 3D table is on
	    If anything fails the painted 2D table simply stays (and a warning says why). Touch-only devices keep the 2D
	    table for now: the 3D one has not been tried on them.
	Table3D.active()
	Table3D.syncHand(handFrame, handData, backId)     the hub, after it rebuilt the hand
	Table3D.adoptGhosts(entries)                      the hub, when a play's score ghosts exist
	Table3D.beat(kind, sourcePos, amount)             the score reveal, one scoring beat (sourcePos: UDim2 offset or nil)
	Table3D.payout(magnitude)                         the score reveal, the payout landing
	Table3D.settle()                                  a reveal ended early: the pot is cleared
	Table3D.shake(target, intensity, duration)        VisualHelpers.screenShake, every 2D shake
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Engine = Shared:WaitForChild("Engine")
local TS = require(Engine:WaitForChild("TableScene"))
local TableTheme = require(Engine:WaitForChild("TableTheme"))

local M = {}

local active = false
local tried = false
local deps = nil
local Rig, Cards, Chips, React, Stand
local pot = { at = nil, since = 0, last = 0 }

local function calm()
	local ok, value = pcall(function() return require(script.Parent.ClientSettings).get("reduceShake") end)
	return ok and value == true
end

local function loadTheme(name)
	local folder = Shared:WaitForChild("TableThemes"):FindFirstChild(name)
	if not folder then error("there is no theme folder named " .. tostring(name)) end
	local theme = { name = name }
	for _, part in ipairs(TableTheme.PARTS) do
		local module = folder:FindFirstChild(part)
		if not module then error("the theme " .. name .. " has no " .. part .. " module") end
		theme[part] = require(module)
	end
	local ok, problems = TableTheme.check(theme)
	if not ok then error("the theme " .. name .. " is not complete: " .. table.concat(problems, "; ")) end
	return theme
end

function M.start(d)
	if tried then return active end
	tried = true
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then return false end
	local scene
	local ok, err = pcall(function()
		local theme = loadTheme(TableTheme.default())
		local Scene = require(script.Scene)
		Rig, Cards, Chips, React = require(script.Rig), require(script.Cards), require(script.Chips), require(script.React)
		scene = Scene.build(theme)
		Scene.light(theme)
		Rig.watchRoot(d.root)
		Cards.start({ scene = scene, theme = theme, deck = d.deckWidget, calm = calm })
		Chips.start({ scene = scene, calm = calm })
		React.start({ scene = scene, theme = theme, calm = calm })
		Stand = require(script.Stand)
		Stand.start({ scene = scene, theme = theme })
		Rig.start()
		require(script.Veil).install(d.root)
		d.root:SetAttribute("Table3D", true) -- Client/PlayMotion reads it: its painted light pool stays off
	end)
	if not ok then
		warn("[Table3D] the 3D table did not start and the painted table stays: " .. tostring(err))
		pcall(function() if scene then scene.model:Destroy() end end)
		return false
	end
	deps = d
	active = true
	task.spawn(function() -- the HUD's pieces come and go with the screens: look for new ones twice a second
		while d.root.Parent do
			local ok, err = pcall(M.furnish)
			if not ok and not M.furnishWarned then
				M.furnishWarned = true
				warn("[Table3D] a HUD piece could not be stood on the table: " .. tostring(err))
			end
			task.wait(0.5)
		end
	end)
	return true
end

-- The HUD's pieces become things on the table (Table3D/Stand): the Patrons and the Multiplier panel stand at the far
-- side, Play Hand, Discard and the sort toggle are signs at the near side (their painted plates on real boards), the
-- deck is a pile of cards.
function M.furnish()
	local root = deps.root
	local row = root:FindFirstChild("PatronRow")
	if row then
		local drop = math.floor(root.AbsoluteSize.Y * TS.LAYOUT.patronDrop + 0.5)
		if row.Position.Y.Offset ~= drop then row.Position = UDim2.new(0, 0, 0, drop) end -- the row stands lower: on the table, not over the room
		for _, slot in ipairs(row:GetChildren()) do
			if slot:IsA("GuiObject") and slot.Name:match("^PatronCard%d+$") then
				local float = slot:FindFirstChild("Float")
				local body = float and float:FindFirstChild("Body")
				local plaque = float and float:FindFirstChild("Plaque")
				if body then Stand.adopt(body, { lean = TS.STAND.patron, anchor = slot, foot = true }) end
				if plaque then Stand.adopt(plaque, { lean = TS.STAND.plaque, clear = true }) end
				local shadow = slot:FindFirstChild("Shadow")
				if shadow and shadow.Visible then shadow.Visible = false end -- the board casts a real one
			end
		end
		local boost = row:FindFirstChild("PatronBoostPanel")
		if boost then Stand.adopt(boost, { lean = TS.STAND.patron, foot = true }) end
	end
	local actions = root:FindFirstChild("Actions")
	if actions then
		for _, child in ipairs(actions:GetChildren()) do
			-- (backers: the hub restyles these by name, so their painted plates stay theirs and a board stands behind)
			if child:IsA("GuiButton") or (child:IsA("Frame") and child:FindFirstChild("SortToggle")) then
				Stand.adopt(child, { lean = TS.STAND.sign, foot = true, backer = true, thick = 0.3 })
			end
		end
	end
	Stand.pile(root:FindFirstChild("DeckWidget"))
end

function M.active()
	return active
end

function M.syncHand(handFrame, handData, backId)
	if active then Cards.syncHand(handFrame, handData, backId) end
end

function M.adoptGhosts(entries)
	if not active then return end
	Cards.adoptGhosts(entries)
	pot.at = nil -- a new play: the pot finds its place again
end

-- the pot stands on the felt left of a full played row, level with it
local function potPlace()
	local now = os.clock()
	if pot.at and now - pot.last < 12 then return pot.at end
	local at = nil
	local ghosts = Cards.played()
	local root = deps.root
	if #ghosts > 0 and root then
		local y, w = 0, 0
		for _, g in ipairs(ghosts) do
			y = y + g.AbsolutePosition.Y + g.AbsoluteSize.Y / 2
			w = math.max(w, g.AbsoluteSize.X)
		end
		local mid = root.AbsolutePosition.X + root.AbsoluteSize.X / 2
		local rowLeft = mid - (w * 5 + 12 * 4) / 2
		at = Rig.pointUnder(rowLeft - w * 0.95, y / #ghosts, 0)
	end
	if at then
		local p = { at.X - TS.ORIGIN[1], 0, at.Z - TS.ORIGIN[3] }
		if not TS.onFelt(p, 3.2) then at = nil end -- it would stand on the rail or off the table
	end
	pot.at = at or Rig.world(TS.POT)
	return pot.at
end

function M.beat(kind, sourcePos, amount)
	if not active then return end
	local from = nil
	if typeof(sourcePos) == "UDim2" then
		from = Rig.pointUnder(sourcePos.X.Offset, sourcePos.Y.Offset, 0.5)
	end
	local place = potPlace()
	pot.last = os.clock()
	local id = pot.last
	Chips.toss(kind, from, TS.chipsFor(kind, amount), place)
	React.thump(0.1) -- every beat rattles the table a little; the big hits come through shake()
	task.delay(12, function() -- a reveal that never paid out (an error, a skipped round): the pot does not stay
		if pot.last == id and active then Chips.payout(nil, true) end
	end)
end

local function boardPoint()
	local box = deps.scoreBox and deps.scoreBox()
	if box and box.Parent and box.AbsoluteSize.X > 0 then
		local p = Rig.pointUnder(box.AbsolutePosition.X + box.AbsoluteSize.X / 2, box.AbsolutePosition.Y + box.AbsoluteSize.Y / 2, 2.4)
		if p then return p end
	end
	return Rig.world({ -18, 2.4, -1 })
end

function M.payout(magnitude)
	if not active then return end
	pot.last = os.clock()
	local sent = Chips.payout(boardPoint(), false)
	pot.at = nil
	if sent > 0 then React.flare(math.clamp(0.35 + (magnitude or 0) / 14, 0, 1)) end
end

function M.settle()
	if not active then return end
	pot.last = os.clock()
	Chips.payout(boardPoint(), true)
	pot.at = nil
end

function M.shake(target, intensity, duration)
	if not active or target ~= deps.root then return end
	Rig.shake(intensity, duration)
	React.thump(math.clamp((intensity or 0) / 10, 0, 1))
end

-- The played cards' lane starts under the Patron row in the 2D layout. On the 3D table the Patrons stand at the far
-- side and the played cards lie on the felt in front of them, so the lane may start level with the Patrons' knees.
function M.laneTop(nookBottom)
	if not active or type(nookBottom) ~= "number" then return nookBottom end
	local h = deps.root.AbsoluteSize.Y
	return nookBottom - math.floor(h * (TS.LAYOUT.patronDrop + TS.LAYOUT.laneRise) + 0.5)
end

-- for a look in Studio: what is on the table right now
function M.report()
	if not active then return "off" end
	local hand, all = Cards.count()
	local inPot, inAir = Chips.count()
	return string.format("hand=%d cards=%d pot=%d flying=%d", hand, all, inPot, inAir)
end

return M
