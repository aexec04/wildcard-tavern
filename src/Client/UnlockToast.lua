-- Good-news notices, shown as corner toasts (Client/CornerToast, via OverlayQueue: one or two lines, no button, never over a card):
--   * "Unlocked: Nest Egg"           state.unlockNotice   = { seq, items = { { kind, id, hint } } }   (Engine/Unlocks)
--   * "Quest done: Pair Up  +40 XP"  state.progressNotice = { seq, rankUps, quests, rewards }         (Engine/AccountProgress)
--   * "Rank 5!  Title: Table Regular"
--   * "Blessing: Generous House"     state.rewardNotice with blessingId (the effect lives in the left HUD blessing chip)
--   * "Tutorial complete! ..." / "First win! ..."   state.rewardNotice = { seq, icon, text } (Engine/FirstRewards)
-- Display only. Self-contained: the hub calls init(screenGui) once and update(state) from render
-- in a pcall.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Patrons = require(Engine:WaitForChild("Patrons"))
local Recipes = require(Engine:WaitForChild("Recipes"))
local HousePasses = require(Engine:WaitForChild("HousePasses"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local OverlayQueue = require(script.Parent.OverlayQueue)
local ClientSettings = require(script.Parent.ClientSettings)

local UnlockToast = {}

local MAX_NAMES = 2
local PRI = OverlayQueue.rules.PRIORITY

local gui -- the ScreenGui
local lastUnlockSeq = 0
local lastProgressSeq = 0
local lastRewardSeq = 0
local levelUpSound -- set by the hub: function() that plays the existing level up sound (Engine/HandLevelMoment.SOUND)

local function defOf(item)
	if item.kind == "patron" then
		return Patrons.getById(item.id)
	end
	if item.kind == "housePass" then
		return HousePasses.getById(item.id)
	end
	return Recipes.getHouseRecipeById(item.id) or Recipes.getSecretRecipeById(item.id)
end

-- "Unlocked: Nest Egg", "Unlocked: Nest Egg and Lucky Ticket", "Unlocked: A, B and 3 more"
function UnlockToast.textFor(names)
	if #names == 0 then
		return ""
	end
	if #names == 1 then
		return "Unlocked: " .. names[1]
	end
	if #names <= MAX_NAMES then
		return "Unlocked: " .. table.concat(names, " and ")
	end
	return string.format("Unlocked: %s, %s and %d more", names[1], names[2], #names - 2)
end

-- names of the unlocked items (Run Over lists them: Engine/ProgressionFeel.unlockLine)
function UnlockToast.namesOf(items)
	local names = {}
	for _, item in ipairs(items or {}) do
		local def = defOf(item)
		if def then names[#names + 1] = def.name end
	end
	return names
end

local pushed = 0
local function push(entry)
	pushed += 1
	entry.id = entry.id or ("toast:" .. tostring(pushed))
	entry.priority = entry.priority or PRI.other
	OverlayQueue.enqueue(entry)
end

local function pushUnlocks(items, seq)
	local rows = {}
	for _, item in ipairs(items) do
		local def = defOf(item)
		if def then rows[#rows + 1] = def.name end -- names only: the effect text is in the Collection
	end
	if #rows > 0 then
		push({ id = "unlock:" .. tostring(seq), priority = PRI.unlock, group = "unlock", title = "Unlocked!", rows = rows })
	end
end

local function pushProgress(notice)
	for _, q in ipairs(notice.quests or {}) do
		push({ text = string.format("Quest done: %s   +%d XP", q.name, q.xp or 0) })
	end
	local ups = notice.rankUps or {}
	if #ups > 0 then
		local line = "Rank " .. ups[#ups] .. "!"
		local rewards = notice.rewards or {}
		if #rewards > 0 then
			line = line .. "  " .. rewards[#rewards]:gsub("^Rank %d+: ", "")
		end
		local feel = require(Engine:WaitForChild("ProgressionFeel")).toast("rank", ClientSettings.get("reduceShake") == true)
		push({ id = "rank:" .. tostring(ups[#ups]), priority = PRI.rank, text = line, hold = feel.hold, rise = feel.rise })
		pcall(function() require(script.Parent.Cue).play(feel.cue) end) -- a short reward cue
	end
end

function UnlockToast.init(screenGui)
	gui = screenGui
	OverlayQueue.init(screenGui)
end

-- The hub hands over the sound player once (a closure over SoundModule), so this module never needs the hub's locals.
function UnlockToast.setLevelUpSound(fn)
	levelUpSound = fn
end

-- Called from render(): shows each new notice (by seq) once.
function UnlockToast.update(state)
	if not gui or type(state) ~= "table" then
		return
	end
	-- the toast slot follows the screen: one compact line on Round Select (its cards start right under the corner buttons)
	pcall(function()
		require(script.Parent.CornerToast).setScreen(require(Engine:WaitForChild("ToastPlacement")).screenOf(state))
	end)
	local unlock = state.unlockNotice
	if unlock and type(unlock.seq) == "number" and unlock.seq > lastUnlockSeq then
		lastUnlockSeq = unlock.seq
		pushUnlocks(unlock.items or {}, unlock.seq)
	end
	local reward = state.rewardNotice
	if reward and type(reward.seq) == "number" and reward.seq > lastRewardSeq then
		lastRewardSeq = reward.seq
		local artId = reward.blessingId and ContentArt.getImageId("blessing_icons", reward.blessingId) or nil
		local text = reward.text
		if reward.blessingId and type(text) == "string" then
			text = "Blessing: " .. (text:match("^(.-):") or text) -- "Generous House: Rounds pay +2 Tips, ..." becomes "Blessing: Generous House"
		end
		if reward.levelUp and levelUpSound then pcall(levelUpSound) end -- a hand levelled up: the existing chime, the toast is a still line
		push({ icon = reward.icon, text = text, artId = artId })
	end
	local progress = state.progressNotice
	if progress and type(progress.seq) == "number" and progress.seq > lastProgressSeq then
		lastProgressSeq = progress.seq
		pushProgress(progress)
	end
end

return UnlockToast
