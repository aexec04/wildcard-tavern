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

	Returns:
		{
			showWarning = function(text),
			bossBanner = Frame,
			bossBannerLabel = TextLabel,
		}
]]

return function(deps)
	local SIDEBAR_WIDTH = deps.SIDEBAR_WIDTH
	local root = deps.root
	local polishPanel = deps.polishPanel

	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "Message"
	messageLabel.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 40), 0, 30)
	messageLabel.Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 0, 20)
	messageLabel.BackgroundTransparency = 1
	messageLabel.Font = Enum.Font.Gotham
	messageLabel.TextSize = 16
	messageLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	messageLabel.Text = ""
	messageLabel.Parent = root

	-- Every warning shown through this ("Not enough tips", "Select 1-5 cards...")
	-- used to just sit on screen forever once set. This clears it back to ""
	-- after a few seconds. The "MessageToken" attribute (not a top-level
	-- local) guards against a newer message getting wiped early by an older
	-- message's stale clear-timer.
	local function showWarning(text)
		messageLabel.Text = text
		local myToken = (messageLabel:GetAttribute("MessageToken") or 0) + 1
		messageLabel:SetAttribute("MessageToken", myToken)
		task.delay(3, function()
			if messageLabel:GetAttribute("MessageToken") == myToken then
				messageLabel.Text = ""
			end
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
