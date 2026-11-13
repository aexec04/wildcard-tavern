--[[
	Client/CornerToast.lua
	Small notices (an unlock, a finished quest, a rank, a chosen blessing) as a corner toast instead of the big OverlayQueue
	plate: up to three stacked, newest on top, one or two lines each, no button, about 4 seconds, a tap closes one. Rules, text and
	the slot are in Engine/CornerToastRules.lua (tested): the right edge, 8 px under the top-right corner buttons; on Round Select,
	where the cards start right under them, ONE compact line. OverlayQueue.enqueue sends every item here unless it says plate = true
	(the daily reward and Round Complete).

	It never blocks anything: the toasts are the only Active objects, there is no backdrop, nothing here is named "...Backdrop"
	(so PopupShield, InputGuard and the modal gate ignore it), and calm mode (or Fast speed) shows and hides them with no tween.

	CornerToast.init(screenGui)
	CornerToast.show(item) -> bool        item = { id?, text?, rows?, group?, icon?, artId?, title? } (the OverlayQueue item shape)
	CornerToast.setScreen(name)           "table" | "roundSelect" | "choice" | "shop", from ToastPlacement.screenOf(state)
	CornerToast.newRound()                the same notice may show again
	In Studio the first toast prints one [CornerToast] line with its AbsolutePosition and size.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("CornerToastRules"))
local OverlayRules = require(Engine:WaitForChild("OverlayQueueRules"))
local HudKit = require(Engine:WaitForChild("HudKit"))
local HudTheme = require(script.Parent.HudTheme)
local ClientSettings = require(script.Parent.ClientSettings)

local CornerToast = {}

-- parchment strip like the play hint toast: paper fill, dark ink, thin gold edge, soft shadow (numbers in ToastPlacement.STYLE)
local STYLE = require(Engine:WaitForChild("ToastPlacement")).STYLE
local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end
local PLATE = rgb(STYLE.paper)
local BRASS = rgb(STYLE.edge)
local CREAM = rgb(STYLE.ink) -- dark ink on paper (name kept from the old dark plate)
local Z = 140 -- over the Choice screen (60 to 66) and the HUD, under the OverlayQueue plates (150)

local stack = Rules.new()
local gui, holder
local screen = "table"
local rows = {} -- one row per slot: { frame, label, icon, order }
local looping = false
local reported = false

local function calm()
	return ClientSettings.get("animSpeed") == "fast" or ClientSettings.get("reduceShake") == true
end

local function newRow()
	local frame = Instance.new("TextButton") -- a tap closes it
	frame.Name = "Toast"
	frame.AutoButtonColor = false
	frame.Text = ""
	frame.BackgroundColor3 = PLATE
	frame.BackgroundTransparency = STYLE.paperTransparency
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = Z + 1
	frame.Parent = holder
	local shadow = Instance.new("Frame") -- soft shadow, a child so it moves and hides with the toast
	shadow.Name = "Shadow"
	shadow.Position = UDim2.fromOffset(0, STYLE.shadowOffset)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = STYLE.shadowTransparency
	shadow.BorderSizePixel = 0
	shadow.ZIndex = Z
	shadow.Parent = frame
	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 8)
	shadowCorner.Parent = shadow
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = BRASS
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	local icon = Instance.new("ImageLabel") -- a painted kit or blessing icon, or nothing (never an emoji)
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	icon.Size = UDim2.fromOffset(28, 28)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Visible = false
	icon.ZIndex = Z + 2
	icon.Parent = frame
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 15
	label.TextColor3 = CREAM
	label.TextTransparency = 0
	label.TextStrokeTransparency = 1
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = Z + 2
	label.Parent = frame
	local row = { frame = frame, label = label, icon = icon, shadow = shadow, order = nil }
	frame.MouseButton1Click:Connect(function()
		if row.order then
			stack:dismiss(row.order)
			CornerToast.refresh()
		end
	end)
	return row
end

local function iconFor(entry)
	if entry.artId and entry.artId ~= "" then return entry.artId end
	local setId = HudTheme.setId()
	local piece = OverlayRules.iconPiece(entry.icon)
	return (piece and setId) and HudKit.piece(setId, piece) or nil
end

local function fade(row, visible)
	local f = row.frame
	if calm() then
		f.Visible = visible
		f.BackgroundTransparency, row.label.TextTransparency = STYLE.paperTransparency, 0
		row.label.TextStrokeTransparency = 1
		row.shadow.BackgroundTransparency = STYLE.shadowTransparency
		return
	end
	local info = TweenInfo.new(Rules.FADE)
	if visible and not f.Visible then
		f.Visible = true
		f.BackgroundTransparency, row.label.TextTransparency, row.shadow.BackgroundTransparency = 1, 1, 1
		TweenService:Create(f, info, { BackgroundTransparency = STYLE.paperTransparency }):Play()
		TweenService:Create(row.label, info, { TextTransparency = 0 }):Play()
		TweenService:Create(row.shadow, info, { BackgroundTransparency = STYLE.shadowTransparency }):Play()
	elseif visible then
		-- already showing: once the fade-in is over, force the ink fully opaque (a fade-out still running from the last toast
		-- on this row must not leave dark-on-paper text invisible), and re-assert the ink colour
		if not row.shownAt or os.clock() - row.shownAt > Rules.FADE + 0.1 then
			for _, t in ipairs(row.outTweens or {}) do t:Cancel() end
			row.outTweens = nil
			row.shadow.BackgroundTransparency = STYLE.shadowTransparency
			row.label.TextTransparency, row.label.TextStrokeTransparency = 0, 1
			row.label.TextColor3 = CREAM
			f.BackgroundTransparency = STYLE.paperTransparency
		end
	elseif not visible and f.Visible then
		TweenService:Create(f, info, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(row.label, info, { TextTransparency = 1 }):Play()
		TweenService:Create(row.shadow, info, { BackgroundTransparency = 1 }):Play()
		task.delay(Rules.FADE, function()
			if not row.order then f.Visible = false end
		end)
	end
end

-- Tick the stack and draw it.
function CornerToast.refresh()
	if not holder then return end
	local plan = Rules.plan(screen)
	stack:tick(os.clock(), plan.maxVisible)
	local size = gui.AbsoluteSize
	local w, h = size.X, size.Y
	if w < 1 or h < 1 then
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		w, h = vp.X, vp.Y
	end
	if screen == "table" then -- the Mult panel beside the Patron display stands where the column starts: toasts go under it
		local okPanel, rect = pcall(function() return require(script.Parent.PatronRow).panelRect() end)
		if okPanel and rect then Rules.below(plan, w, rect) end
	end
	for i = 1, Rules.MAX_STACK do
		local row = rows[i]
		if not row then
			row = newRow()
			rows[i] = row
		end
		local entry = stack.visible[i]
		if entry then
			local slot = Rules.slot(w, h, plan, i)
			row.frame.Position = UDim2.fromOffset(slot.x, slot.y)
			row.frame.Size = UDim2.fromOffset(slot.w, slot.h)
			local iconId = iconFor(entry)
			row.icon.Visible = iconId ~= nil
			row.icon.Image = iconId or ""
			row.label.Position = UDim2.fromOffset(iconId and 44 or 12, 0)
			row.label.Size = UDim2.new(1, -(iconId and 52 or 20), 1, 0)
			row.label.Text = entry.text
			row.label.TextWrapped = plan.lines > 1
			row.order = entry.order
			fade(row, true)
		else
			row.order = nil
			fade(row, false)
		end
	end
	if not reported and stack.visible[1] and RunService:IsStudio() then
		reported = true
		task.defer(function()
			local f = rows[1].frame
			local slot = Rules.slot(w, h, plan, 1)
			local function n(v) return math.floor(v or 0) end
			local at, size = f.AbsolutePosition, f.AbsoluteSize
			warn(string.format("[CornerToast] first toast at %d,%d size %dx%d (slot %d,%d %dx%d) on a %dx%d screen (%s)", n(at and at.X), n(at and at.Y),
				n(size and size.X), n(size and size.Y), n(slot.x), n(slot.y), n(slot.w), n(slot.h), n(w), n(h), screen))
		end)
	end
	if not stack:isEmpty() and not looping then
		looping = true
		task.spawn(function()
			while not stack:isEmpty() do
				task.wait(0.25)
				CornerToast.refresh()
			end
			looping = false
		end)
	end
end

function CornerToast.init(screenGui)
	gui = screenGui
	if holder then return end
	holder = Instance.new("Frame")
	holder.Name = "CornerToasts" -- not a "...Backdrop": it shields nothing and the modal gate ignores it
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Active = false
	holder.ZIndex = Z
	holder.Parent = screenGui
end

function CornerToast.show(item)
	if not holder then return false end
	local taken = stack:push(item, os.clock())
	if taken then CornerToast.refresh() end
	return taken
end

function CornerToast.setScreen(name)
	if type(name) ~= "string" or name == screen then return end
	screen = name
	CornerToast.refresh()
end

function CornerToast.newRound()
	stack:newRound()
end

-- for the tests
function CornerToast.stack() return stack end
function CornerToast.rows() return rows end

return CornerToast
