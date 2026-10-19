--[[
	Client/PhaseA.lua
	PHASE A (Spectacle pass, Oct 2026 -- see claude/mind-blowing-plan.md):
	the 2 standalone "extra beat" systems from that pass that aren't part
	of ScorePopup.lua's own per-hand reveal (that file's own "Legendary
	Hand" freeze-frame lives inside IT, driven by preview.isLegendary --
	see its header), bundled into ONE module instead of 2.

	Merged into a single file/require on purpose: init.client.lua is
	already right at Lua's 200-local-per-chunk ceiling (see its own
	comments elsewhere, e.g. the Fast Forward hasFastForwardPass
	inlining), and each separate top-level `local XModule = require(...)`
	costs one of those 200 slots -- 2 new modules would have tipped it
	over (confirmed: it did, during this pass). One merged module costs
	exactly one. Nothing below shares any state between the two halves;
	this is purely a top-level-local budget optimization, not a real
	coupling between "boss intro" and "run recap."

	== Boss Intro ==
	A short "arrival" beat the first time a NEW Boss Round's state shows
	up -- a hard screen flash + shake, a slammed-in banner naming the
	boss, and a low stinger sound, instead of the Boss Round just quietly
	appearing in the sidebar/top banner the way it always has (see
	init.client.lua's blindInfoLabel/bossBanner, unchanged by this file --
	this is a ONE-TIME extra beat layered on top of those). Same
	"only fire on a genuinely NEW state" pattern as GameOver.lua's
	lastGameOverKey -- keyed by night+round+bossModifier id. Reuses
	existing sound/tween/particle primitives only -- no new asset ids.

	== Run Recap ==
	Tracks the single biggest hand played so far THIS RUN, purely
	client-side (deliberately NOT wired into PlayerProfile.lua/
	DataStoreService -- a per-run bragging stat, not a lifetime one), so
	GameOver.lua's recap can show something more interesting than just
	the final score. resetRun() is called from 2 places in
	init.client.lua -- see that call site's own comment for why.

	deps fields:
		root            -- Frame, the full-screen gameplay root (flash + banner parent)
		tweenTo         -- function(instance, props, duration, easingStyle?, easingDirection?)
		screenShake     -- function(target, intensity, duration?)
		playPitched     -- function(sound, pitch?, volume?)
		payoutThudSound -- Sound instance, reused here pitched way down for a "slam" boom

	Returns:
		{
			announceBossIfNew = function(state), -- state: the full server state passed to render()
			recordHand = function(preview),       -- preview: { name, score, ... } from computeHandPreview
			resetRun = function(),
			getBest = function() -> { name = string, score = number } | nil,
		}
]]

return function(deps)
	local root = deps.root
	local tweenTo = deps.tweenTo
	local screenShake = deps.screenShake
	local playPitched = deps.playPitched
	local payoutThudSound = deps.payoutThudSound

	-- ===== Boss Intro =====

	local flashOverlay = Instance.new("Frame")
	flashOverlay.Name = "BossFlashOverlay"
	flashOverlay.Size = UDim2.fromScale(1, 1)
	flashOverlay.BackgroundColor3 = Color3.fromRGB(10, 6, 8)
	flashOverlay.BackgroundTransparency = 1
	flashOverlay.BorderSizePixel = 0
	flashOverlay.ZIndex = 36
	flashOverlay.Parent = root

	local banner = Instance.new("TextLabel")
	banner.Name = "BossIntroBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.38)
	banner.Size = UDim2.new(0, 560, 0, 70)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.GothamBlack
	banner.TextSize = 30
	banner.TextWrapped = true
	banner.TextColor3 = Color3.fromRGB(255, 210, 120)
	banner.TextStrokeTransparency = 0.1
	banner.TextStrokeColor3 = Color3.fromRGB(40, 10, 10)
	banner.TextTransparency = 1
	banner.Text = ""
	banner.ZIndex = 37
	banner.Parent = root

	local bannerScale = Instance.new("UIScale")
	bannerScale.Scale = 1
	bannerScale.Parent = banner

	local lastBossKey = nil
	local bossToken = 0

	local function announceBossIfNew(state)
		if not state or not state.bossModifier then
			return
		end
		local key = tostring(state.night) .. "-" .. tostring(state.round) .. "-" .. tostring(state.bossModifier.id)
		if key == lastBossKey then
			return
		end
		lastBossKey = key
		bossToken = bossToken + 1
		local myToken = bossToken

		banner.Text = string.format("👑 BOSS ROUND\n%s", state.bossModifier.name)
		banner.TextTransparency = 1
		bannerScale.Scale = 2.2

		playPitched(payoutThudSound, 0.55, 0.8)
		screenShake(root, 7, 0.3)

		flashOverlay.BackgroundTransparency = 1
		tweenTo(flashOverlay, { BackgroundTransparency = 0.35 }, 0.08)
		task.delay(0.08, function()
			if bossToken == myToken then
				tweenTo(flashOverlay, { BackgroundTransparency = 1 }, 0.5)
			end
		end)

		tweenTo(banner, { TextTransparency = 0 }, 0.12)
		tweenTo(bannerScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		task.delay(1.3, function()
			if bossToken == myToken then
				tweenTo(banner, { TextTransparency = 1 }, 0.4)
			end
		end)
	end

	-- ===== Run Recap =====

	local bestHand = nil -- { name = string, score = number } | nil

	-- Guards against a nil/odd preview the same way computeHandPreview's
	-- OTHER callers already do -- a bad preview here should just mean this
	-- one hand doesn't get recorded, never an error that takes down the
	-- Play Hand click handler.
	local function recordHand(preview)
		if not preview or type(preview.score) ~= "number" or preview.score <= 0 then
			return
		end
		if not bestHand or preview.score > bestHand.score then
			bestHand = { name = preview.name, score = preview.score }
		end
	end

	local function resetRun()
		bestHand = nil
	end

	local function getBest()
		return bestHand
	end

	return {
		announceBossIfNew = announceBossIfNew,
		recordHand = recordHand,
		resetRun = resetRun,
		getBest = getBest,
	}
end
