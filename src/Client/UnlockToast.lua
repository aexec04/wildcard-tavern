-- Toasts: a small parchment banner that slides in at the top for good news, one at a time (a queue):
--   * "Unlocked: Nest Egg"           state.unlockNotice   = { seq, items = { { kind, id, hint } } }   (Engine/Unlocks)
--   * "Quest done: Pair Up  +40 XP"  state.progressNotice = { seq, rankUps, quests, rewards }         (Engine/AccountProgress)
--   * "Rank 5!  Title: Table Regular"
-- Art first: the painted portrait when there is one (emoji fallback) in a gold ring, one line of text, then it
-- slides away. Display only. Self-contained: the hub calls init(screenGui) once and update(state) from render
-- in a pcall.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Patrons = require(Engine:WaitForChild("Patrons"))
local Recipes = require(Engine:WaitForChild("Recipes"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local PatronPlaque = require(script.Parent.PatronPlaque)
local ClientSettings = require(script.Parent.ClientSettings)

local UnlockToast = {}

local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local GOLD = Color3.fromRGB(222, 182, 104)

local SHOW_SECONDS = 4
local MAX_NAMES = 2

local gui -- the ScreenGui
local toast -- the built frame, created on first use
local lastUnlockSeq = 0
local lastProgressSeq = 0
local token = 0
local queue = {} -- entries waiting: { icon, text, tab, id }
local busy = false

local function defOf(item)
	if item.kind == "patron" then
		return Patrons.getById(item.id), "patrons"
	end
	return Recipes.getHouseRecipeById(item.id) or Recipes.getSecretRecipeById(item.id), "recipes"
end

local function build()
	local frame = Instance.new("Frame")
	frame.Name = "UnlockToast"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Size = UDim2.fromOffset(440, 76)
	frame.Position = UDim2.new(0.5, 0, 0, -100)
	frame.BackgroundColor3 = PARCHMENT
	frame.Visible = false
	frame.ZIndex = 130
	frame.Active = false
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2.5
	stroke.Parent = frame

	local well = Instance.new("Frame")
	well.Name = "Well"
	well.Size = UDim2.fromOffset(56, 56)
	well.Position = UDim2.fromOffset(10, 10)
	well.BackgroundColor3 = Color3.fromRGB(86, 58, 34)
	well.ZIndex = 131
	well.Parent = frame
	local wellCorner = Instance.new("UICorner")
	wellCorner.CornerRadius = UDim.new(0, 28)
	wellCorner.Parent = well
	local wellStroke = Instance.new("UIStroke")
	wellStroke.Color = GOLD
	wellStroke.Thickness = 2
	wellStroke.Parent = well

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 30
	icon.TextColor3 = Color3.fromRGB(250, 235, 200)
	icon.ZIndex = 132
	icon.Parent = well

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.new(1, -86, 1, -12)
	text.Position = UDim2.fromOffset(76, 6)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 17
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = INK
	text.TextTransparency = 0
	text.TextStrokeTransparency = 1
	text.ZIndex = 131
	text.Parent = frame
	return frame
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

local function showNext()
	if busy or #queue == 0 then
		return
	end
	local entry = table.remove(queue, 1)
	busy = true
	toast = toast or build()
	toast.Text.Text = entry.text
	toast.Well.Icon.Text = entry.icon or "✨"
	for _, child in ipairs(toast.Well:GetChildren()) do
		if child.Name == "ContentArt" then
			child:Destroy()
		end
	end
	local artId = entry.tab and ContentArt.getImageId(entry.tab, entry.id)
	if artId then
		PatronPlaque.applyById(toast.Well, artId, { emojiLabel = toast.Well.Icon, zIndex = 133, cornerRadius = 28 })
	end

	token += 1
	local mine = token
	local shownPos = UDim2.new(0.5, 0, 0, 70) -- clear of Roblox's top bar
	local hiddenPos = UDim2.new(0.5, 0, 0, -100)
	toast.Visible = true
	if ClientSettings.get("animSpeed") == "fast" or ClientSettings.get("reduceShake") == true then
		toast.Position = shownPos
	else
		toast.Position = hiddenPos
		TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = shownPos }):Play()
	end
	task.delay(SHOW_SECONDS, function()
		if mine ~= token or not toast then
			return
		end
		local tween = TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = hiddenPos })
		tween.Completed:Connect(function()
			if mine == token and toast then
				toast.Visible = false
				busy = false
				showNext()
			end
		end)
		tween:Play()
	end)
end

local function push(entry)
	queue[#queue + 1] = entry
	showNext()
end

local function pushUnlocks(items)
	local names, first = {}, nil
	for _, item in ipairs(items) do
		local def, tab = defOf(item)
		if def then
			names[#names + 1] = def.name
			first = first or { def = def, tab = tab, id = item.id }
		end
	end
	if first then
		push({ icon = first.def.icon, text = UnlockToast.textFor(names), tab = first.tab, id = first.id })
	end
end

local function pushProgress(notice)
	for _, q in ipairs(notice.quests or {}) do
		push({ icon = q.icon or "✔", text = string.format("Quest done: %s   +%d XP", q.name, q.xp or 0) })
	end
	local ups = notice.rankUps or {}
	if #ups > 0 then
		local line = "Rank " .. ups[#ups] .. "!"
		local rewards = notice.rewards or {}
		if #rewards > 0 then
			line = line .. "  " .. rewards[#rewards]:gsub("^Rank %d+: ", "")
		end
		push({ icon = "🏅", text = line })
	end
end

function UnlockToast.init(screenGui)
	gui = screenGui
end

-- Called from render(): shows each new notice (by seq) once.
function UnlockToast.update(state)
	if not gui or type(state) ~= "table" then
		return
	end
	local unlock = state.unlockNotice
	if unlock and type(unlock.seq) == "number" and unlock.seq > lastUnlockSeq then
		lastUnlockSeq = unlock.seq
		pushUnlocks(unlock.items or {})
	end
	local progress = state.progressNotice
	if progress and type(progress.seq) == "number" and progress.seq > lastProgressSeq then
		lastProgressSeq = progress.seq
		pushProgress(progress)
	end
end

return UnlockToast
