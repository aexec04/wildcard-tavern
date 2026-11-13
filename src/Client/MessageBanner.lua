--[[
	Client/MessageBanner.lua
	A small always-on-screen message strip, parented directly to root (not
	inside any overlay), for transient warnings ("Not enough tips",
	"Select 1-5 cards...").

	FEATURE 9's persistent Boss Round banner used to live here too, but it
	just restated the sidebar's blindInfoLabel (same boss name + description,
	shown at the same time) for the whole round -- removed. The sidebar box
	is the always-on readout now, and PhaseA.lua's one-shot Boss Intro is
	the spectacle.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. showWarning is a widely-used
	dependency -- it's passed into several other overlay modules (Shop.lua,
	Collection.lua) that need to report "not enough tips" -- so it comes back
	out of the require() call.

	deps fields:
		SIDEBAR_WIDTH -- number, for the sidebar-aware horizontal layout
		root          -- Frame, the message strip's parent
		polishPanel    -- function(instance, radius)
		tweenTo        -- function(instance, properties, duration, style?, direction?)

	Returns:
		{
			showWarning = function(text),
		}

	POLISH PASS: showWarning used to just snap `messageLabel.Text` on and
	back off with zero animation -- a bare floating line of text with no
	background, appearing/disappearing on a hard cut. It's one of the most
	frequently-seen pieces of feedback in the whole game (fires on nearly
	every invalid action -- not enough tips, wrong card count, no discards
	left), so it's a high-value, low-risk target for real animation: it now
	sits on its own small toast-style panel (`messageBar`) that slides down
	a few pixels and fades in on show, then fades back out (not an instant
	clear) when its timer or a newer warning replaces it.
]]

local ToastPlacement = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ToastPlacement"))
local STYLE = ToastPlacement.STYLE
local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end

return function(deps)
	local SIDEBAR_WIDTH = deps.SIDEBAR_WIDTH
	local root = deps.root
	local polishPanel = deps.polishPanel
	local tweenTo = deps.tweenTo

	local RESTING_Y = 20
	local START_Y = RESTING_Y - 10 -- slides down 10px into place on show

	local messageBar = Instance.new("Frame")
	messageBar.Name = "MessageBar"
	messageBar.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 40), 0, 34)
	messageBar.Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 0, RESTING_Y)
	messageBar.BackgroundColor3 = rgb(STYLE.paper)
	messageBar.BackgroundTransparency = 1
	messageBar.Visible = false
	messageBar.ZIndex = 4
	messageBar.Parent = root
	polishPanel(messageBar, 8)
	-- Thin gold edge (Border mode) and a soft shadow; both are children of the bar so they fade and hide with it.
	local edge = Instance.new("UIStroke")
	edge.Color = rgb(STYLE.edge)
	edge.Thickness = STYLE.edgeThickness
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Transparency = 1
	edge.Parent = messageBar
	local shadow = Instance.new("Frame") -- ZIndex below the bar, so it draws beneath it (the GUI uses Global draw order)
	shadow.Name = "Shadow"
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(0, STYLE.shadowOffset)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 1
	shadow.BorderSizePixel = 0
	shadow.Active = false
	shadow.ZIndex = 3
	shadow.Parent = messageBar
	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 8)
	shadowCorner.Parent = shadow
	-- Deliberately no addSoftShadow here -- that helper parents its shadow
	-- to messageBar.Parent (root), which never toggles Visible/transparency
	-- alongside messageBar itself, so a shadow attached to something this
	-- frequently shown/hidden would just sit there permanently instead of
	-- fading with it. Fine to revisit once addSoftShadow itself supports a
	-- toggle-along-with-its-panel mode.

	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "Message"
	messageLabel.Size = UDim2.fromScale(1, 1)
	messageLabel.BackgroundTransparency = 1
	messageLabel.Font = Enum.Font.Gotham
	messageLabel.TextSize = 16
	messageLabel.TextWrapped = true
	messageLabel.TextColor3 = rgb(STYLE.ink)
	messageLabel.TextStrokeTransparency = 1
	messageLabel.TextTransparency = 1
	messageLabel.Text = ""
	messageLabel.ZIndex = 4
	messageLabel.Parent = messageBar

	local BAR_TRANSPARENCY = STYLE.paperTransparency

	-- Every warning shown through this ("Not enough tips", "Select 1-5 cards...")
	-- used to just sit on screen forever once set. This clears it back to ""
	-- after a few seconds. The "MessageToken" attribute (not a top-level
	-- local) guards against a newer message getting wiped early by an older
	-- message's stale clear-timer.
	-- A full screen (Run Over, a Backdrop popup) owns the view: no toast or bracket border is drawn over it.
	local function blocked()
		for _, c in ipairs(root:GetChildren()) do
			if c:IsA("GuiObject") and c.Visible and (c.Name == "GameOver" or (c.Name:sub(-8) == "Backdrop" and c.Name ~= "DeckTrackerBackdrop")) then
				return true
			end
		end
		return false
	end
	-- Where the bar goes on the screen that is showing NOW (it also sizes the bar): a wide strip under the title on
	-- Round Select, Choice and Shop, a small toast on the felt on the table.
	local function currentPlace()
		return ToastPlacement.plan(root:GetAttribute("ToastScreen") or (root:GetAttribute("BannerAtBottom") and "roundSelect") or "table")
	end
	local function barPosition(place, y)
		messageBar.AnchorPoint = Vector2.new(0, 0)
		local drift = y - RESTING_Y
		if place.centred then
			local size = root.AbsoluteSize
			local hand = root:FindFirstChild("HandFrame")
			local handTop = hand and hand.Visible and (hand.AbsolutePosition.Y - root.AbsolutePosition.Y) or nil
			local x, ty, w, h = ToastPlacement.tableRect(size.X, size.Y, SIDEBAR_WIDTH, handTop)
			messageBar.Size = UDim2.fromOffset(w, h)
			return UDim2.fromOffset(x, ty + drift)
		end
		messageBar.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 40), 0, 34)
		return UDim2.new(0, SIDEBAR_WIDTH + 20, 0, place.y + drift)
	end
	-- A message can outlive the screen it was shown on (said on Round Select, still up when the table appears): it used
	-- to stay a wide strip across the Patron cards. It now moves to the new screen's place the moment the screen changes.
	root:GetAttributeChangedSignal("ToastScreen"):Connect(function()
		if messageBar.Visible then
			messageBar.Position = barPosition(currentPlace(), RESTING_Y)
		end
	end)
	local function showWarning(text)
		if blocked() then
			messageBar.Visible = false
			return
		end
		messageLabel.Text = text
		local myToken = (messageBar:GetAttribute("MessageToken") or 0) + 1
		messageBar:SetAttribute("MessageToken", myToken)

		messageBar.Visible = true
		-- Never over a title: Round Select, Choice and Shop sit under the title block. Table screens: a small toast on the felt
		-- above the hand (Engine/ToastPlacement.lua; render() sets the ToastScreen attribute), never across the cards.
		local place = currentPlace()
		local function pos(y) return barPosition(place, y) end
		messageBar.Position = pos(START_Y)
		tweenTo(messageBar, { BackgroundTransparency = BAR_TRANSPARENCY, Position = pos(RESTING_Y) }, 0.18)
		tweenTo(messageLabel, { TextTransparency = 0 }, 0.18)
		tweenTo(edge, { Transparency = 0 }, 0.18)
		tweenTo(shadow, { BackgroundTransparency = STYLE.shadowTransparency }, 0.18)

		task.delay(place.seconds or ToastPlacement.SECONDS, function()
			if messageBar:GetAttribute("MessageToken") ~= myToken then
				return -- a newer warning has already replaced this one
			end
			tweenTo(messageBar, { BackgroundTransparency = 1 }, 0.3)
			tweenTo(edge, { Transparency = 1 }, 0.3)
			tweenTo(shadow, { BackgroundTransparency = 1 }, 0.3)
			local fadeOut = tweenTo(messageLabel, { TextTransparency = 1 }, 0.3)
			fadeOut.Completed:Connect(function(playbackState)
				if playbackState == Enum.PlaybackState.Completed and messageBar:GetAttribute("MessageToken") == myToken then
					messageBar.Visible = false
					messageLabel.Text = ""
				end
			end)
		end)
	end

	return {
		showWarning = showWarning,
	}
end
