--[[
	Client/Table3D/Veil.lua
	With the 3D table on, the painted 2D table and its backdrop layers must not draw: the world is behind them. They
	are owned by a dozen modules that keep setting their Visible, so each named layer is simply held invisible here.
	So are the dark edges a Boss Round lays over the painted scene (inside BossFightHost): on the 3D table they were a
	hard-edged shade over the felt. The Boss's medallion, name plate and speech stay.
	The Counter, Round Select and the Menu have backgrounds of their own and are not touched.

	install(root)
]]

local Veil = {}

local NAMES = {
	GameBackgroundArt = true, GameSceneStack = true, GameSceneShade = true, TableLookLayers = true,
	PlayTableBg = true, PlayTableFront = true, PlayFeltShade = true, PlayFloorShade = true, PlayRailBack = true,
	PlayRailFront = true, PlayGrooveLip = true, HandRailLip = true, HandTray = true, PlayLightPool = true,
}

local IN_BOSS_HOST = { "BossVignette" }

-- (the mark is an attribute on the layer itself: a table keyed by instances can forget one that is still there, and
-- the layer would then be given a second listener on every sweep)
local function hold(inst)
	if not inst:IsA("GuiObject") or inst:GetAttribute("Table3DHeld") then return end
	inst:SetAttribute("Table3DHeld", true)
	inst.Visible = false
	inst:GetPropertyChangedSignal("Visible"):Connect(function()
		if inst.Visible then inst.Visible = false end
	end)
end

function Veil.install(root)
	local function sweep()
		for _, child in ipairs(root:GetChildren()) do
			if NAMES[child.Name] then hold(child) end
		end
		local row = root:FindFirstChild("PatronRow") -- the Patron row's painted alcove: the Patrons stand on the table now
		local nook = row and row:FindFirstChild("Nook")
		if nook then hold(nook) end
		local host = root:FindFirstChild("BossFightHost")
		if host then
			for _, name in ipairs(IN_BOSS_HOST) do
				local piece = host:FindFirstChild(name, true)
				if piece then hold(piece) end
			end
		end
	end
	sweep()
	root.ChildAdded:Connect(function(child)
		task.defer(function()
			if child.Parent == root and NAMES[child.Name] then hold(child) end
		end)
	end)
	task.spawn(function() -- a layer that is named after it is parented is caught here
		while root.Parent do
			task.wait(1)
			sweep()
		end
	end)
end

return Veil
