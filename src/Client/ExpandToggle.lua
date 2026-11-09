--[[
	Client/ExpandToggle.lua
	A small corner button that swaps an overlay panel between its normal
	size and a near-fullscreen one -- for panels with a lot to browse
	(Collection's 40+ Patrons) that feel cramped at their default size but
	shouldn't be huge ALL the time.

	Generic on purpose: only Collection.lua uses it today, but Settings or
	DailyLeaderboard can opt in later with the same one call. Only ever
	tweens the panel's Size, so it doesn't fight popIn/popOut (those
	animate a UIScale, see VisualHelpers.lua). The panel should be
	center-anchored (AnchorPoint 0.5, 0.5) so it grows/shrinks in place
	around its middle instead of off its top-left corner.

	Usage:
		local toggle = require(script.Parent.ExpandToggle)(panel, {
			collapsedSize       = UDim2,               -- the panel's normal size
			expandedSize        = UDim2?,              -- default 0.95 x 0.92 of the screen
			zIndex              = number?,             -- default panel.ZIndex
			polishButton        = function(instance, radius)?,
			addButtonHoverScale = function(button, opts?)?,
			playClickSfx        = function(volume?)?,
		})

	Returns:
		{
			button = TextButton,
			isExpanded = function() -> boolean,
			setExpanded = function(expanded, instant?),
		}
]]

local TweenService = game:GetService("TweenService")

local PanelLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PanelLayout"))
-- tall enough to fill the screen but always clear of the PanelTabs strip (top 37px) once nudged down
local DEFAULT_EXPANDED_SIZE = UDim2.new(0.95, 0, 1, -PanelLayout.EXPANDED_MARGIN)
local TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Glyphs read as "grow" / "shrink" -- plain arrows from the basic Arrows
-- block, which every Roblox font's fallback covers.
local EXPAND_GLYPH = "↗"
local COLLAPSE_GLYPH = "↙"

return function(panel, opts)
	opts = opts or {}
	local collapsedSize = opts.collapsedSize or panel.Size
	local expandedSize = opts.expandedSize or DEFAULT_EXPANDED_SIZE
	local expanded = false
	local activeTween = nil

	local button = Instance.new("TextButton")
	button.Name = "ExpandToggle"
	button.Size = UDim2.new(0, 30, 0, 30)
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -8, 0, PanelLayout.TOGGLE_INSET)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.Text = EXPAND_GLYPH
	button.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	button.TextColor3 = Color3.fromRGB(250, 240, 220)
	button.ZIndex = opts.zIndex or math.max(panel.ZIndex, 70) -- above the PanelTabs strip (60) so clicks always reach it
	button.Parent = panel
	if opts.polishButton then
		opts.polishButton(button, 8)
	end
	if opts.addButtonHoverScale then
		opts.addButtonHoverScale(button)
	end

	local function setExpanded(value, instant)
		expanded = value
		button.Text = expanded and COLLAPSE_GLYPH or EXPAND_GLYPH
		local targetSize = expanded and expandedSize or collapsedSize
		if activeTween then
			activeTween:Cancel()
			activeTween = nil
		end
		if instant then
			panel.Size = targetSize
		else
			activeTween = TweenService:Create(panel, TWEEN_INFO, { Size = targetSize })
			activeTween:Play()
		end
	end

	button.MouseButton1Click:Connect(function()
		if opts.playClickSfx then
			opts.playClickSfx()
		end
		setExpanded(not expanded)
	end)

	return {
		button = button,
		isExpanded = function()
			return expanded
		end,
		setExpanded = setExpanded,
	}
end
