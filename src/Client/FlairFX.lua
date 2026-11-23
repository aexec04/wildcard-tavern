--[[
	Client/FlairFX.lua
	Draws the equipped Flair (Engine/Flair.lua). Visual only: it never reads or changes scoring, targets or timing.
	  scoreColor()                the color of the final score numbers (nil for the classic look)
	  playTrail(burst, pos)       a few particles as cards are played
	  finisher(burst, pos, preview, cleared)  a flourish on any hand that clears the target, stronger on big hands (Flush or better, Legendary)
  scoreGlow(), aura(), canAnimate()  equipped Score Numbers glow, Name Aura (color, crest) and the calm mode check
	  preview(burst, slotId, optionId, pos)  plays one effect once, for the Flair panel
	Rules: no loops and no allocations outside a burst, at most MAX_PARTICLES per call, each burst frees itself (the shared
	ParticleBurst tweens and destroys its dots). Nothing plays under Reduce Flashing, Reduce Motion or Reduce Shake (calm mode)
	or on the Fast animation speed; the preview from the panel plays unless calm mode is on.
	Fed by setState(state) from render; reads state.flair (Flair.view).
]]

local Layers = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Layers"))
local ClientSettings = require(script.Parent.ClientSettings)

local FlairFX = {}

local MAX_PARTICLES = 24
local PREVIEW_COUNT, PREVIEW_SIZE = 24, 11 -- previews are bigger and fuller than in-run effects
FlairFX.PANEL_Z = Layers.effect + 100 -- previews draw above every panel (FlairPanel uses 40 to 46, Spectate less)
local BIG_HANDS = { ["Flush"] = true, ["Full House"] = true, ["Four of a Kind"] = true, ["Straight Flush"] = true }

local current -- state.flair

function FlairFX.setState(state)
	current = state and state.flair or nil
end

local function equippedOption(slotId)
	if not current then
		return nil
	end
	for _, slot in ipairs(current.slots or {}) do
		if slot.id == slotId then
			for _, option in ipairs(slot.options or {}) do
				if option.equipped then
					return option
				end
			end
		end
	end
	return nil
end

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- the classic look returns nil so the popup keeps its own color
function FlairFX.scoreColor()
	local option = equippedOption("scoreNumbers")
	if option and option.id ~= "classic_numbers" and option.color then
		return rgb(option.color)
	end
	return nil
end

local TRAIL = {
	sparkle = { { 255, 245, 200 }, { 255, 214, 130 } }, ember = { { 255, 150, 70 }, { 255, 200, 90 } },
	star = { { 255, 240, 130 }, { 255, 255, 200 } }, petal = { { 255, 190, 210 }, { 255, 225, 235 } },
	ribbon = { { 200, 150, 255 }, { 255, 170, 220 } },
}
local FINISH = {
	pop = { colors = { { 255, 214, 130 } }, bursts = 1, count = 10, spread = 110 },
	firework = { colors = { { 255, 120, 120 }, { 120, 200, 255 }, { 255, 230, 120 } }, bursts = 3, count = 8, spread = 150 },
	confetti = { colors = { { 255, 120, 160 }, { 120, 220, 255 }, { 255, 230, 100 }, { 150, 255, 160 } }, bursts = 2, count = 12, spread = 170 },
	lantern = { colors = { { 255, 170, 80 }, { 255, 210, 130 } }, bursts = 2, count = 6, spread = 90 },
	goldrain = { colors = { { 255, 214, 100 } }, bursts = 2, count = 12, spread = 130 },
	crown = { colors = { { 255, 230, 150 }, { 255, 255, 220 } }, bursts = 2, count = 6, spread = 120 },
}

local function allowed(isPreview)
	if ClientSettings.get("reduceShake") == true then
		return false -- calm mode: Reduce Flashing, Reduce Motion or Reduce Shake
	end
	if not isPreview and ClientSettings.getRaw("animSpeed") == "fast" then
		return false -- the Fast setting skips cosmetic flourishes
	end
	return true
end

local function trailBurst(burst, pos, option, isPreview, zIndex)
	if not allowed(isPreview) or not option or option.style == nil or option.style == "none" then
		return
	end
	local colors = TRAIL[option.style]
	if not colors then
		return
	end
	local color = rgb(colors[math.random(#colors)])
	local count, size = 6, 6
	if isPreview then count, size = PREVIEW_COUNT, PREVIEW_SIZE end -- the Flair panel preview must read on the Stage
	pcall(burst, pos, color, count, { size = size, spread = 70, duration = 0.5, zIndex = zIndex })
end

local function finisherBurst(burst, pos, option, isPreview, zIndex, strong)
	if not allowed(isPreview) or not option or not option.style then
		return
	end
	local spec = FINISH[option.style]
	if not spec then
		return
	end
	local bursts = strong == false and 1 or spec.bursts -- a plain round clear is a single smaller pop
	local total = 0
	for i = 1, bursts do
		local count = math.min(spec.count, MAX_PARTICLES - total)
		if isPreview then count = PREVIEW_COUNT end
		if count <= 0 then break end
		total = total + count
		local color = rgb(spec.colors[((i - 1) % #spec.colors) + 1])
		local offset = UDim2.fromOffset((i - 2) * 46, ((i % 2 == 0) and -22 or 12))
		pcall(burst, UDim2.new(pos.X.Scale, pos.X.Offset + offset.X.Offset, pos.Y.Scale, pos.Y.Offset + offset.Y.Offset), color, count,
			{ size = isPreview and PREVIEW_SIZE or 8, spread = spec.spread, duration = 0.65, zIndex = zIndex })
	end
end

function FlairFX.playTrail(burst, pos)
	trailBurst(burst, pos, equippedOption("playTrail"), false)
end

-- Any hand that clears the round target plays the equipped Finisher; big hands play the stronger version.
function FlairFX.finisher(burst, pos, preview, clearedTarget)
	if type(preview) ~= "table" then
		return
	end
	local big = preview.isLegendary == true or BIG_HANDS[preview.name] == true
	if big then
		finisherBurst(burst, pos, equippedOption("finisher"), false, nil, true)
	elseif clearedTarget == true then
		finisherBurst(burst, pos, equippedOption("finisher"), false, nil, false)
	end
end

-- Score Numbers glow: stroke thickness for the equipped style (0 for the classic look). Visual only.
function FlairFX.scoreGlow()
	local option = equippedOption("scoreNumbers")
	if option and option.id ~= "classic_numbers" and option.glow then
		return option.glow
	end
	return 0
end

-- The equipped Name Aura as {color = Color3, crest = string}; nil for no aura. Visual only.
function FlairFX.aura()
	local option = equippedOption("nameAura")
	if option and option.color then
		return { color = rgb(option.color), crest = option.crest or "" }
	end
	return nil
end

-- Calm mode check for panels that animate their own preview (pop, glow ring).
function FlairFX.canAnimate()
	return ClientSettings.get("reduceShake") ~= true
end

-- Plays one option once (the Flair panel's Preview button). `option` is a Flair.view option row.
function FlairFX.preview(burst, slotId, option, pos)
	local z = FlairFX.PANEL_Z
	if slotId == "playTrail" then
		for _ = 1, 3 do trailBurst(burst, pos, option, true, z) end
	elseif slotId == "finisher" then
		finisherBurst(burst, pos, option, true, z, true)
	end
end

return FlairFX
