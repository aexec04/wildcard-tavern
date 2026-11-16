--[[
	Client/Table3D/Chips.lua
	The chips of a scoring hand. Every beat of the reveal throws a few from the card or Patron that scored into the
	pot beside the played cards: blue for Chips, red for Mult, gold for Tips, in three piles of neat stacks. At the
	payout the whole pot flies to the score board. How many, where they stack and the arc are Engine/TableScene.

	Chips.start{ scene, calm }
	Chips.toss(kind, from, count, potAt)   from: world point or nil (the house throws from the far rail)
	Chips.payout(to, quick) -> number of chips sent
	Chips.count() -> chips on the table
]]

local RunService = game:GetService("RunService")
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local TS = require(Engine:WaitForChild("TableScene"))
local Rig = require(script.Parent.Rig)

local Chips = {}

local C = TS.CHIP
local PILE = {
	chips = { mat = "chipChips", x = -1.5, z = 0, mirror = -1 },
	mult = { mat = "chipMult", x = 1.5, z = 0, mirror = 1 },
	tips = { mat = "chipTips", x = 0, z = 2.1, mirror = 1 },
}

local deps, folder = nil, nil
local flying = {} -- chips in the air
local piles = { chips = {}, mult = {}, tips = {} } -- chips that have a place in the pot (landed or on their way)
local seed = 0

local function rnd() -- the same throw every time: no surprises in a screenshot test
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local function calm()
	return deps and deps.calm and deps.calm() == true
end

local UP = CFrame.Angles(0, 0, math.rad(90)) -- a Roblox cylinder lies along X: this stands it on the felt

local function newChip(mat, n)
	local part = Instance.new("Part")
	part.Name = "Chip"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(C.height, C.diameter, C.diameter)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	deps.scene.paint(part, mat)
	if n % 3 == 0 then part.Color = part.Color:Lerp(Color3.new(1, 1, 1), 0.16) end -- every third chip is paler: a stack reads as chips
	return part
end

function Chips.toss(kind, from, count, potAt)
	if not deps or not potAt then return 0 end
	local key = kind == "chips" and "chips" or kind == "tips" and "tips" or "mult"
	local spec, pile = PILE[key], piles[key]
	local T = TS.TABLE
	local house = Rig.world({ T.centreX + 3, T.railHeight + 0.4, -(T.halfWidth + T.railWidth * 0.5) })
	local sent = 0
	for i = 1, count do
		if #pile >= C.perPile then break end
		local n = #pile + 1
		local dx, dz, level = TS.potSlot(n)
		local rest = CFrame.new(potAt + Vector3.new(spec.x + dx * spec.mirror, C.height * (level + 0.5) + 0.01, spec.z + dz))
			* CFrame.Angles(0, rnd() * math.pi, 0) * UP
		local part = newChip(spec.mat, n)
		pile[n] = part
		sent = sent + 1
		if calm() then
			part.CFrame = rest
			part.Parent = folder
		else
			local start = (from or house) + Vector3.new((rnd() - 0.5) * 0.7, 0.25, (rnd() - 0.5) * 0.7)
			flying[#flying + 1] = {
				part = part, from = start, rest = rest, t = -(i - 1) * 0.045, dur = C.flight * (0.9 + rnd() * 0.25),
				apex = C.apex * (0.8 + rnd() * 0.4), turns = 1 + math.floor(rnd() * 2), lean = rnd() * math.pi,
			}
		end
	end
	return sent
end

-- every chip in the pot goes to `to` (a world point: the score board) and is gone when it gets there
function Chips.payout(to, quick)
	if not deps then return 0 end
	local sent = 0
	for _, key in ipairs({ "tips", "mult", "chips" }) do
		local pile = piles[key]
		for n = #pile, 1, -1 do
			local part = pile[n]
			pile[n] = nil
			if part.Parent == nil or calm() or not to then
				part:Destroy()
			else
				sent = sent + 1
				for i = #flying, 1, -1 do -- a chip still on its way in turns round where it is
					if flying[i].part == part then table.remove(flying, i) end
				end
				flying[#flying + 1] = {
					part = part, from = part.Position, out = to + Vector3.new((rnd() - 0.5) * 1.2, (rnd() - 0.5) * 0.6, (rnd() - 0.5) * 1.2),
					t = -sent * (quick and 0.004 or 0.012), dur = (quick and 0.22 or 0.4) * (0.9 + rnd() * 0.25),
					apex = 2.2 + rnd() * 1.6, turns = 2, lean = rnd() * math.pi, spin = part.CFrame.Rotation,
				}
			end
		end
	end
	return sent
end

function Chips.count()
	return #piles.chips + #piles.mult + #piles.tips, #flying
end

local function step(dt)
	for i = #flying, 1, -1 do
		local f = flying[i]
		f.t = f.t + dt
		if f.t >= 0 then
			local part = f.part
			if part.Parent == nil then
				if f.out then table.remove(flying, i) part:Destroy() continue end
				part.Parent = folder
			end
			local u = math.min(1, f.t / f.dur)
			if f.out then
				local e = u * u -- it gathers speed toward the board
				local p = TS.arcPoint({ f.from.X, f.from.Y, f.from.Z }, { f.out.X, f.out.Y, f.out.Z }, f.apex, e)
				part.CFrame = CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(e * f.turns * math.pi * 2, f.lean, 0) * f.spin
				if u >= 1 then
					table.remove(flying, i)
					part:Destroy()
				end
			else
				local to = f.rest.Position
				if u >= 1 then
					part.CFrame = f.rest
					table.remove(flying, i)
				else
					local e = 1 - (1 - u) ^ 2 -- thrown fast, lands soft
					local p = TS.arcPoint({ f.from.X, f.from.Y, f.from.Z }, { to.X, to.Y, to.Z }, f.apex, e)
					local tumble = (1 - e) * f.turns * math.pi * 2
					part.CFrame = CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(0, f.lean, 0) * CFrame.Angles(tumble, 0, 0) * f.rest.Rotation
				end
			end
		end
	end
end

function Chips.start(d)
	deps = d
	folder = Instance.new("Folder")
	folder.Name = "Chips"
	folder.Parent = d.scene.model
	RunService:BindToRenderStep("Table3DChips", Enum.RenderPriority.Camera.Value + 3, step)
end

return Chips
