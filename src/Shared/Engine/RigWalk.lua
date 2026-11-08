--[[
	Shared/Engine/RigWalk.lua
	Pure joint-graph walk used by Client/CharacterStage. Joints are plain tables { Part0 = x, Part1 = y }
	(Roblox JointInstances work as-is). Starting from the root, each joint is ordered so its anchor part is
	placed before the part it moves. Accessory welds are built the other way round (Part0 = the accessory
	handle), so when only Part1 is placed the joint is walked backwards (reversed[joint] = true).
	Returns ordered, reversed, placed (set of parts reached) and the number of parts reached.
]]

local RigWalk = {}

RigWalk.MIN_AVATAR_PARTS = 10 -- an R15 avatar reaches 16+ body parts; fewer means it was not assembled

function RigWalk.walk(joints, root)
	local all = {}
	for _, j in ipairs(joints) do
		if j.Part0 and j.Part1 then
			table.insert(all, j)
		end
	end
	local placed = { [root] = true }
	local count = 1
	local ordered, reversed = {}, {}
	local progress = true
	while progress do
		progress = false
		for _, j in ipairs(all) do
			if not placed[j.Part1] and placed[j.Part0] then
				placed[j.Part1] = true
				count = count + 1
				table.insert(ordered, j)
				progress = true
			elseif not placed[j.Part0] and placed[j.Part1] then
				placed[j.Part0] = true
				count = count + 1
				reversed[j] = true
				table.insert(ordered, j)
				progress = true
			end
		end
	end
	return ordered, reversed, placed, count
end

return RigWalk
