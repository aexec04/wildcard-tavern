--[[
	Client/MessageBanner.lua
	Two small always-on-screen banners, both parented directly to root (not
	inside any overlay): a message strip for transient warnings ("Not enough
	tips", "Select 1-5 cards..."), and FEATURE 9's Boss Round banner.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. showWarning is a widely-used
	dependency -- it's passed into several other overlay modules (Shop.lua,
	Themes.lua) that need to report "not enough tips" -- and
	bossBanner/bossBannerLabel are driven every render() call, so all three
	come back out of the require() call.

	deps fields:
		SIDEBAR_WIDTH -- number, for the sidebar-aware horizontal layout
		root          -- Frame, both banners' parent
		polishPanel    -- function(instance, radius)
		tweenTo        -- function(instance, properties, duration, style?, direction?)

	Returns:
		{
			showWarning = function(text),
			bossBanner = Frame,
			bossBannerLabel = TextLabel,
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
	messageBar.BackgroundColor3 = Color3.fromRGB(50, 38, 28)
	messageBar.BackgroundTransparency = 1
	messageBar.Visible = false
	messageBar.ZIndex = 4
	messageBar.Parent = root
	polishPanel(messageBar, 8)
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
	messageLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	messageLabel.TextTransparency = 1
	messageLabel.Text = ""
	messageLabel.ZIndex = 4
	messageLabel.Parent = messageBar

	local BAR_TRANSPARENCY = 0.12

	-- Every warning shown through this ("Not enough tips", "Select 1-5 cards...")
	-- used to just sit on screen forever once set. This clears it back to ""
	-- after a few seconds. The "MessageToken" attribute (not a top-level
	-- local) guards against a newer message getting wiped early by an older
	-- message's stale clear-timer.
	local function showWarning(text)
		messageLabel.Text = text
		local myToken = (messageBar:GetAttribute("MessageToken") or 0) + 1
		messageBar:SetAttribute("MessageToken", myToken)

		messageBar.Visible = true
		messageBar.Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 0, START_Y)
		tweenTo(messageBar, { BackgroundTransparency = BAR_TRANSPARENCY, Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 0, RESTING_Y) }, 0.18)
		tweenTo(messageLabel, { TextTransparency = 0 }, 0.18)

		task.delay(3, function()
			if messageBar:GetAttribute("MessageToken") ~= myToken then
				return -- a newer warning has already replaced this one
			end
			tweenTo(messageBar, { BackgroundTransparency = 1 }, 0.3)
			local fadeOut = tweenTo(messageLabel, { TextTransparency = 1 }, 0.3)
			fadeOut.Completed:Connect(function(playbackState)
				if playbackState == Enum.PlaybackState.Completed and messageBar:GetAttribute("MessageToken") == myToken then
					messageBar.Visible = false
					messageLabel.Text = ""
				end
			end)
		end)
	end

	-- FEATURE 9: a banner announcing this round's Boss modifier, if any.
	local bossBanner = Instance.new("Frame")
	bossBanner.Name = "BossBanner"
	bossBanner.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 40), 0, 40)
	bossBanner.Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 0, 56)
	bossBanner.BackgroundColor3 = Color3.fromRGB(90, 40, 40)
	bossBanner.Visible = false
	bossBanner.ZIndex = 3
	bossBanner.Parent = root
	polishPanel(bossBanner, 10)

	local bossBannerLabel = Instance.new("TextLabel")
	bossBannerLabel.Size = UDim2.fromScale(1, 1)
	bossBannerLabel.BackgroundTransparency = 1
	bossBannerLabel.Font = Enum.Font.GothamBold
	bossBannerLabel.TextSize = 15
	bossBannerLabel.TextColor3 = Color3.fromRGB(255, 225, 210)
	bossBannerLabel.Text = ""
	bossBannerLabel.ZIndex = 3
	bossBannerLabel.Parent = bossBanner

	return {
		showWarning = showWarning,
		bossBanner = bossBanner,
		bossBannerLabel = bossBannerLabel,
	}
end
