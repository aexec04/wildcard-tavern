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

-- R15 body part -> the part its Motor6D (a child of that part) hangs from.
RigWalk.R15_ANCHOR = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm", LeftHand = "LeftLowerArm",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm", RightHand = "RightLowerArm",
	LeftUpperLeg = "LowerTorso", LeftLowerLeg = "LeftUpperLeg", LeftFoot = "LeftLowerLeg",
	RightUpperLeg = "LowerTorso", RightLowerLeg = "RightUpperLeg", RightFoot = "RightLowerLeg",
}

-- Fills a joint's missing Part0 / Part1 from the standard R15 layout (Part1 = the joint's parent part,
-- Part0 = its named anchor). partByName(name) returns the part or nil; getParentName(joint) returns the
-- name of the part holding the joint. Returns how many joints were healed. Joints already set are untouched.
function RigWalk.heal(joints, partByName, getParentName)
	local healed = 0
	for _, j in ipairs(joints) do
		if not (j.Part0 and j.Part1) then
			local childName = getParentName(j)
			local anchorName = childName and RigWalk.R15_ANCHOR[childName]
			if anchorName then
				local p0, p1 = partByName(anchorName), partByName(childName)
				if p0 and p1 then
					j.Part0, j.Part1 = p0, p1
					healed = healed + 1
				end
			end
		end
	end
	return healed
end

-- Modern avatars join their body with AnimationConstraints (no Motor6D). One behaves like a Motor6D whose
-- C0 / C1 are its two attachments' CFrames and whose parts are the attachments' parents:
-- child.CFrame = parent.CFrame * att0.CFrame * Transform * att1.CFrame:Inverse().
-- Returns a joint table { Part0, Part1, C0, C1, Name, animated = true, source = constraint }, or nil while
-- the constraint is not assembled yet (missing attachment or parent).
function RigWalk.fromConstraint(c)
	local a0, a1 = c.Attachment0, c.Attachment1
	if not (a0 and a1 and a0.Parent and a1.Parent) then
		return nil
	end
	return { Part0 = a0.Parent, Part1 = a1.Parent, C0 = a0.CFrame, C1 = a1.CFrame, Name = c.Name,
		animated = true, source = c }
end

-- True for the wrapper tables made by fromConstraint. Real Instances (Weld, Motor6D) are userdata and error
-- on unknown field reads, so never index `.animated` on a joint without this check first.
function RigWalk.isWrapper(j)
	return type(j) == "table" and rawget(j, "animated") == true
end

-- True when the joint takes a pose rotation: a wrapped AnimationConstraint or a real Motor6D.
-- isMotor(j) is called only for non-wrappers (CharacterStage passes j:IsA("Motor6D")).
function RigWalk.hasTransform(j, isMotor)
	if RigWalk.isWrapper(j) then
		return true
	end
	return isMotor(j) == true
end

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
