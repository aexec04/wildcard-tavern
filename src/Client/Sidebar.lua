--[[
	Client/Sidebar.lua
	LAYOUT FEATURE 1: the always-visible left-side column showing round/blind
	info, tips, hands/discards remaining, the Patron-slot row, and the live
	score preview. Replaces the old full-width top status bar, which had
	started colliding with the top-right corner icon buttons as more got
	added (a real bug -- the "Hands" label was getting cut off). Balatro
	keeps this info in a dedicated left-side column instead of a top bar, so
	this moves the same data there and leaves the whole top edge free for
	the corner icon buttons with no shared space to collide over.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. SIDEBAR_WIDTH is consumed as a dep by
	Client/MessageBanner.lua and Client/Shop.lua, so this module must be
	required BEFORE either of those. Every label here is live-updated
	elsewhere: nightRoundLabel/blindInfoLabel/scoreLabel/tipsLabel/
	handsDiscardsLabel/patronsCountLabel/the patronSlots array are all set
	inside render() (still inline in init.client.lua), and
	scorePreviewLabel/scorePreviewBox are driven by refreshScorePreview()
	(also still inline). All of those come back out of the require() call
	so the rest of the script can keep updating them.

	deps fields:
		root        -- Frame, the sidebar's parent
		polishPanel  -- function(instance, radius)
		roundCorner  -- function(instance, radius)
		Patrons      -- the Patrons engine module (needs #Patrons.Definitions)

	Returns:
		{
			SIDEBAR_WIDTH = 240,
			sidebar = Frame,
			nightRoundLabel = TextLabel,
			blindInfoLabel = TextLabel,
			scoreLabel = TextLabel,
			tipsLabel = TextLabel,
			handsDiscardsLabel = TextLabel,
			patronsCountLabel = TextLabel,
			patronSlots = { [i] = { frame = Frame, label = TextLabel } },
			MAX_SIDEBAR_PATRON_SLOTS = 14,
			scorePreviewBox = Frame,
			scorePreviewLabel = TextLabel,
		}
]]

return function(deps)
	local root = deps.root
	local polishPanel = deps.polishPanel
	local roundCorner = deps.roundCorner
	local Patrons = deps.Patrons

	local SIDEBAR_WIDTH = 240

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0)
	sidebar.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	sidebar.BorderSizePixel = 0
	sidebar.ZIndex = 2
	sidebar.Parent = root

	local sidebarPadding = Instance.new("UIPadding")
	-- 76px, not 16 -- Roblox's own top-left system UI (menu/chat/voice icons)
	-- lives in roughly that space and was overlapping the "Round" box's text.
	sidebarPadding.PaddingTop = UDim.new(0, 76)
	sidebarPadding.PaddingLeft = UDim.new(0, 12)
	sidebarPadding.PaddingRight = UDim.new(0, 12)
	sidebarPadding.Parent = sidebar

	local sidebarLayout = Instance.new("UIListLayout")
	sidebarLayout.FillDirection = Enum.FillDirection.Vertical
	sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sidebarLayout.Padding = UDim.new(0, 10)
	sidebarLayout.Parent = sidebar

	local function makeSidebarBox(height)
		local box = Instance.new("Frame")
		box.Size = UDim2.new(1, 0, 0, height or 46)
		box.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
		box.ZIndex = 2
		box.Parent = sidebar
		polishPanel(box, 10)
		return box
	end

	local function makeSidebarLabel(parent, textSize, color)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = textSize or 16
		label.TextColor3 = color or Color3.fromRGB(240, 220, 190)
		label.TextWrapped = true
		label.Text = ""
		label.ZIndex = 2
		label.Parent = parent
		return label
	end

	local nightRoundBox = makeSidebarBox(40)
	local nightRoundLabel = makeSidebarLabel(nightRoundBox, 16)

	-- LAYOUT FEATURE 2: blind/round name + ability (mirrors the existing
	-- bossBanner content, just always-visible in the sidebar instead of a
	-- banner that only appears mid-round) and the target score + tip reward
	-- for clearing it, computed the same way the server does (see RunState.lua
	-- playHand: tipsPerRoundWin, doubled on a Boss Round) so it never drifts
	-- out of sync with the actual payout.
	local blindInfoBox = makeSidebarBox(56)
	local blindInfoLabel = makeSidebarLabel(blindInfoBox, 13)
	blindInfoLabel.TextWrapped = true
	blindInfoLabel.TextYAlignment = Enum.TextYAlignment.Top

	local scoreBox = makeSidebarBox(66)
	local scoreLabel = makeSidebarLabel(scoreBox, 16, Color3.fromRGB(255, 214, 130))

	local tipsBox = makeSidebarBox(40)
	local tipsLabel = makeSidebarLabel(tipsBox, 16)

	local handsDiscardsBox = makeSidebarBox(40)
	local handsDiscardsLabel = makeSidebarLabel(handsDiscardsBox, 15)

	-- LAYOUT FEATURE 5: Patron slot icons, mirroring Balatro's persistent
	-- Joker-slot row -- shows how many Patrons you've picked up this run at a
	-- glance, without opening the Collection Gallery. This game has no hard
	-- cap on Patrons owned (unlike Balatro's Joker slots), so this shows
	-- owned-out-of-total-in-the-game rather than a hard capacity.
	local patronsBox = makeSidebarBox(58)

	local patronsHeader = Instance.new("TextLabel")
	patronsHeader.Size = UDim2.new(0.6, 0, 0, 16)
	patronsHeader.Position = UDim2.new(0, 0, 0, 4)
	patronsHeader.BackgroundTransparency = 1
	patronsHeader.Font = Enum.Font.GothamBold
	patronsHeader.TextSize = 12
	patronsHeader.TextColor3 = Color3.fromRGB(200, 185, 165)
	patronsHeader.TextXAlignment = Enum.TextXAlignment.Left
	patronsHeader.Text = "Patrons"
	patronsHeader.ZIndex = 2
	patronsHeader.Parent = patronsBox

	local patronsCountLabel = Instance.new("TextLabel")
	patronsCountLabel.Size = UDim2.new(0.4, 0, 0, 16)
	patronsCountLabel.Position = UDim2.new(0.6, 0, 0, 4)
	patronsCountLabel.BackgroundTransparency = 1
	patronsCountLabel.Font = Enum.Font.GothamBold
	patronsCountLabel.TextSize = 12
	patronsCountLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	patronsCountLabel.TextXAlignment = Enum.TextXAlignment.Right
	patronsCountLabel.Text = ""
	patronsCountLabel.ZIndex = 2
	patronsCountLabel.Parent = patronsBox

	local patronsSlotRow = Instance.new("Frame")
	patronsSlotRow.Size = UDim2.new(1, 0, 0, 30)
	patronsSlotRow.Position = UDim2.new(0, 0, 0, 24)
	patronsSlotRow.BackgroundTransparency = 1
	patronsSlotRow.ZIndex = 2
	patronsSlotRow.Parent = patronsBox

	local patronsSlotLayout = Instance.new("UIListLayout")
	patronsSlotLayout.FillDirection = Enum.FillDirection.Horizontal
	-- Was Left -- with only patronSlotLimit (5 by default) of the 14
	-- possible slots actually Visible at once (see LAYOUT FEATURE 5 in
	-- init.client.lua's render()), Left-aligned left the row looking
	-- lopsided, bunched against the left edge with a big empty gap on the
	-- right. Center keeps it looking balanced no matter how many slots
	-- are actually shown.
	patronsSlotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	patronsSlotLayout.Padding = UDim.new(0, 6)
	patronsSlotLayout.Parent = patronsSlotRow

	-- Built once, refreshed in render() below each time state.ownedPatrons
	-- changes. Capped at MAX_SIDEBAR_PATRON_SLOTS regardless of how big the
	-- Patron catalog grows -- this is a quick-glance strip, not the full
	-- browser (that's the Shop's "My Patrons" tab / Collection Gallery), and
	-- a catalog of 50+ would otherwise overflow the sidebar entirely. The
	-- exact "X / Y owned" count (patronsCountLabel above) is always accurate
	-- even when the icon row itself is truncated.
	local MAX_SIDEBAR_PATRON_SLOTS = 14
	local patronSlots = {}
	for i = 1, math.min(MAX_SIDEBAR_PATRON_SLOTS, #Patrons.Definitions) do
		local slot = Instance.new("Frame")
		slot.Size = UDim2.new(0, 30, 0, 30)
		slot.BackgroundColor3 = Color3.fromRGB(45, 40, 38)
		slot.LayoutOrder = i
		slot.ZIndex = 2
		slot.Parent = patronsSlotRow
		roundCorner(slot, 6)

		local slotLabel = Instance.new("TextLabel")
		slotLabel.Size = UDim2.fromScale(1, 1)
		slotLabel.BackgroundTransparency = 1
		slotLabel.Font = Enum.Font.GothamBold
		slotLabel.TextSize = 14
		slotLabel.TextColor3 = Color3.fromRGB(140, 135, 130)
		slotLabel.Text = "?"
		slotLabel.ZIndex = 2
		slotLabel.Parent = slot

		patronSlots[i] = { frame = slot, label = slotLabel }
	end

	-- LAYOUT FEATURE 6: live chips x mult preview for the currently-selected
	-- cards, mirroring Balatro's running score readout. Computed with the same
	-- HandEvaluator/Scoring modules the server uses, so the preview can't
	-- drift out of sync with the real payout -- see refreshScorePreview()
	-- back in init.client.lua, which wires this up once
	-- selected/latestState exist.
	local scorePreviewBox = makeSidebarBox(50)
	local scorePreviewLabel = makeSidebarLabel(scorePreviewBox, 15, Color3.fromRGB(190, 215, 255))

	return {
		SIDEBAR_WIDTH = SIDEBAR_WIDTH,
		sidebar = sidebar,
		nightRoundLabel = nightRoundLabel,
		blindInfoLabel = blindInfoLabel,
		scoreLabel = scoreLabel,
		tipsLabel = tipsLabel,
		handsDiscardsLabel = handsDiscardsLabel,
		patronsCountLabel = patronsCountLabel,
		patronSlots = patronSlots,
		MAX_SIDEBAR_PATRON_SLOTS = MAX_SIDEBAR_PATRON_SLOTS,
		scorePreviewBox = scorePreviewBox,
		scorePreviewLabel = scorePreviewLabel,
	}
end
