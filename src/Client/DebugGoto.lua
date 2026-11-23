--[[
	Client/DebugGoto.lua
	Studio-only jump hook. Set a StringValue named DebugGoto under the LocalPlayer (or the attribute DebugGoto)
	to one of: menu, tome:<collection|cardsets|badges|legend|flair|stats>[:subtab], news, round1, round1:<cardSetId>, round1:mod=<blessingId>[,tag=<tagId>]
	(the last starts round 1 with that Card Set previewed, e.g. round1:winter_evening).
	Every value below and above may end in :<cardSetId> (haggle:winter_evening, boss1:dune_market, menu:meadow_picnic, map:harbor_lights):
	that set is previewed over the equipped one through the Card Sets Preview path, and "[DebugGoto] screen set=<id> (<screen>)" is printed.
	Goes through the normal open paths (OverlayManager openers, NewsPanel.open, the StartSeedRun and Choice
	remotes). Prints "[DebugGoto] <value> ok" or the error. Does nothing outside Studio. spectate needs a second
	player, so it only warns. scale:<w>x<h> shrinks GameUI to that viewport, scale:off restores it. Parsing is in Engine/DebugGotoRules.lua.
	Screens that are hard to reach (each goes through round1 first, then shows a changed copy of the real state):
	  Admin jumps (Studio only, each prints "[DebugGoto] <key> ok"; list in Rules.ADMIN_KEYS):
	  freshsave                         resets the profile to a brand new one (server remote), then the menu
	  daily, daily:done, weekly         the Daily Rewards panel, the Daily leaderboard, the leaderboard (weekly)
	  seed                              the fixed seed run (same as round1)
	  store, store:<tab>, season        the Store and Season panels (the tab is noted, panels open on their first tab)
	  collection, collection:<tab>      the Tome Collection page
	  cardset:<id>                      the table with that Card Set previewed
	  settings, share                   Settings; the win Run Over screen that holds the Invite and Share lines
	  tavernmap:night=<n>               the Tavern Map (same as map:night=n)
	  haggle, haggle:good, haggle:bad   the Counter with a Wandering Stranger on offer (bad: the long curse picks the second scroll)
	  map, map:night=N                  opens the real Tavern Map overlay (the night part is only parsed)
	  road                              Choose your road with three sample stops
	  runover, runover:win              the merged Run Over screen with a loss or a win sample, every field filled
	  boss1, boss1:<bossId>             the play screen in a Boss Round: the first one, or the one with that id (boss1:hearts_are_out)
	  packroom                          5/5 Patrons, 20 Tips, an open Patron pack and its first Patron picked: the Make room step
	  rarity, rarity:2                  the first-Patron draft with one Patron per rarity tier that exists, three per page
	  wildcard, legendary               plays the True Wildcard or the Legendary banner and effect once on the play screen
	  loading, loading:<0..100>         the launch loading screen frozen at 60 percent (or that percent), for screenshots
	  night:<1..12>, bossN:<bossId> (N 2..12), boon, reward, shop:<tips>, tips:<n>, recipes:<id,id>, patrons:<id,id>, sellpatron, tag:<id>,
	  victory, endrun, endrun:win       real screens on the live run (round1 first), see Engine/DebugJump; prints "[DebugGoto] <key> ok"
	  patrons:<0..8>                    after round1 is up: seats n different Patrons on the live run (Studio-only server remote), HUD rebuilds
	  playhand:keep                     first sets the round target to 5000 (Studio-only server remote), then plays, so the round stays open and the beats can be watched
	  playhand                          plays the first 5 hand cards through the real PlayHand remote, so the Patron beats run once
	  beatslow:on|freeze|off            Patron scoring beats 2.0 s apart, each held 1.6 s; freeze keeps beat 2 (ring, hop, pill, dimmed others) until off
	  sfx:<cue>, sfx:ladder           plays a sound cue once, or an 8 step pitch ladder
	  sfx:roundwin                      fires the whole round win sound set (score ticks, stinger, coin run, greeting, wildcard stinger); the
	                                    Output logs "[SoundDirector] voices=N" each time a sound starts
	init({ menuFrame })
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Cue = require(script.Parent.Cue)

local DebugGoto = {}

-- the hub hands over its render function and a getter for the latest table state (Studio-only screens re-render a changed copy)
function DebugGoto.setRenderer(render, getState, tools)
	DebugGoto.render, DebugGoto.getState, DebugGoto.tools = render, getState, tools or {}
end

function DebugGoto.init(deps)
	if not RunService:IsStudio() then return end
	local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("DebugGotoRules"))
	local OverlayManager = require(script.Parent.OverlayManager)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local player = Players.LocalPlayer
	local pendingRound1 = false
	local round1Token = 0 -- bumped on every jump so an old watchdog never fires for a new one
	local lastStep = "start"
	local selectSent = false
	local synthWhich = nil -- shop/roundwin/gameover/boss1/roundselect: the screen to show once round1 has reached it
	local synthVariant, synthPage = nil, nil -- haggle:good|bad, runover:win, rarity:<page>
	local wantedMod, wantedTag = nil, nil -- round1:mod=<id>,tag=<id>: the blessing to pick and the Tag to make current
	local previewSet = nil -- round1:<setId>: the set to preview once the hand is dealt (a run start resets the look)

	local function showSynth(which, variant, page)
		if which == "roundselect" then return end -- the real Round Select state is already on screen
		if not (DebugGoto.render and DebugGoto.getState) then error("renderer not wired") end
		local base = DebugGoto.getState()
		if not base then error("no table state yet") end
		local Engine = ReplicatedStorage.Shared.Engine
		local patrons, packs = {}, {}
		for _, d in ipairs(require(Engine.Patrons).Definitions) do patrons[#patrons + 1] = d if #patrons >= 2 then break end end
		for _, d in ipairs(require(Engine.Packs).Definitions) do packs[#packs + 1] = d if #packs >= 2 then break end end
		local boss = require(Engine.BossRounds).Definitions[1]
		if which == "boss1" and variant then -- boss1:<bossId>: any Boss Round by id, to look at its plate, its rule line and the cards it switches off
			boss = require(Engine.BossRounds).getById(variant) or error("no Boss Round has the id " .. tostring(variant))
		end
		local data = { patrons = patrons, packs = packs, boss = boss, variant = variant, page = page }
		if which == "road" then
			-- three sample stops that exist on the map
			data.roads = {}
			for id in pairs(require(Engine.WorldMap).Stops) do
				data.roads[#data.roads + 1] = id
			end
			table.sort(data.roads)
			while #data.roads > 3 do table.remove(data.roads) end
		elseif which == "boss1" then
			data.allPatrons = require(Engine.Patrons).Definitions
		elseif which == "packroom" then
			data.allPatrons = require(Engine.Patrons).Definitions
		elseif which == "rarity" then
			-- one Patron of each rarity tier that exists, weakest tier first
			local CB = require(Engine.CollectionBook)
			local byTier, order = {}, {}
			for _, d in ipairs(require(Engine.Patrons).Definitions) do
				local tier = CB.rarityForId("patrons", d.id)
				if not byTier[tier] then byTier[tier] = d end
			end
			for _, tier in ipairs(CB.RarityOrder) do
				if byTier[tier] then order[#order + 1] = byTier[tier] end
			end
			data.tierPatrons = order
		end
		local synthState = Rules.synth(which, base, data)
		if which == "boss1" and data.boss then
			warn(string.format("[DebugGoto] boss1 hand=%d live=%d delta=%d", #(synthState.hand or {}), #(base.hand or {}), data.boss.handSizeDelta or 0))
		end
		DebugGoto.render(synthState)
		if which == "packroom" and DebugGoto.tools.packSelect then
			-- pick the first revealed Patron and press Confirm, so the Make room step shows
			task.delay(0.6, function()
				pcall(DebugGoto.tools.packSelect, 1)
				pcall(DebugGoto.tools.packConfirm)
			end)
		end
		print("[DebugGoto] " .. which .. (variant and (":" .. variant) or "") .. " ok")
	end

	local function hideMenu()
		if deps and deps.menuFrame then deps.menuFrame.Visible = false end
	end
	-- the Menu scene stays up behind Tome panels and the news board (like the real Menu), so no 3D world shows through them
	local function showMenu()
		if deps and deps.root then deps.root.Visible = false end
		if deps and deps.menuFrame then deps.menuFrame.Visible = true end
	end
	local function hideTutorialOverlay()
		local overlay = player.PlayerGui:FindFirstChild("TutorialOverlay", true)
		if overlay and overlay:IsA("GuiObject") then overlay.Visible = false end
	end

	-- scale:<w>x<h> / scale:off. Every full screen top-level GuiObject of GameUI gets a real pixel Size of w x h (centred), so
	-- AbsoluteSize is 1280x720 and every layout re-runs for that size, as on a real screen (a UIScale only shrank the picture of
	-- the full-size layout). The original size, anchor and position are kept in attributes and restored by scale:off.
	local function applyScale(target)
		local gui = player.PlayerGui:FindFirstChild("GameUI")
		if not gui then error("no GameUI") end
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(target.w or 1920, target.h or 1080)
		for _, child in ipairs(gui:GetChildren()) do
			if child:IsA("GuiObject") then
				local us = child:FindFirstChild("DebugScale") -- left over from the old UIScale harness
				if us then us:Destroy() end
				local keptSize = child:GetAttribute("DebugSize")
				if target.off then
					if keptSize then
						child.Size = keptSize
						child.AnchorPoint = child:GetAttribute("DebugAnchor") or child.AnchorPoint
						child.Position = child:GetAttribute("DebugPos") or child.Position
						child:SetAttribute("DebugSize", nil)
						child:SetAttribute("DebugAnchor", nil)
						child:SetAttribute("DebugPos", nil)
					end
				else
					local sz = keptSize or child.Size
					if keptSize or Rules.isFullScreenSize(sz.X.Scale, sz.X.Offset, sz.Y.Scale, sz.Y.Offset) then
						if not keptSize then
							child:SetAttribute("DebugSize", child.Size)
							child:SetAttribute("DebugAnchor", child.AnchorPoint)
							child:SetAttribute("DebugPos", child.Position)
						end
						local w, h = Rules.frameFor(target.w, target.h, vp.X, vp.Y)
						child.AnchorPoint = Vector2.new(0.5, 0.5)
						child.Position = UDim2.fromScale(0.5, 0.5)
						child.Size = UDim2.fromOffset(w, h)
					end
				end
			end
		end
		print(target.off and "[DebugGoto] scale off" or ("[DebugGoto] scale " .. target.w .. "x" .. target.h .. " as real pixel size"))
	end

	local sweepToken = 0
	local function go(value)
		local target, why = Rules.parse(value)
		if not target then
			warn("[DebugGoto] " .. tostring(value) .. " ignored: " .. tostring(why))
			return
		end
		if target.kind == "sweep" then
			-- Studio only: visit every capture screen in turn (Rules.SWEEP), logging "[DebugGoto] sweep <screen>"; sweep:stop ends it
			sweepToken = sweepToken + 1
			if target.stop then print("[DebugGoto] sweep stopped") return end
			local mineS = sweepToken
			task.spawn(function()
				for _, step in ipairs(Rules.SWEEP) do
					if sweepToken ~= mineS then return end
					print("[DebugGoto] sweep " .. step.label)
					go(step.value)
					task.wait(target.seconds)
				end
				if sweepToken == mineS then print("[DebugGoto] sweep done") end
			end)
			return
		end
		if target.kind == "perf" then
			-- Studio only: one [Perf] line with the instance counts of the GameUI, for before and after numbers (open a scene first)
			local okP, errP = pcall(function()
				local gui = Players.LocalPlayer.PlayerGui:FindFirstChild("GameUI") or Players.LocalPlayer.PlayerGui
				local total, visible, scripts = 0, 0, 0
				for _, d in ipairs(gui:GetDescendants()) do
					total += 1
					if d:IsA("GuiObject") and d.Visible then visible += 1 end
					if d:IsA("LocalScript") or d:IsA("ModuleScript") then scripts += 1 end
				end
				print(string.format("[Perf] gui=%s instances=%d visibleGuiObjects=%d scripts=%d", gui.Name, total, visible, scripts))
				-- who owns the weight: the ten biggest direct children by descendant count, then the commonest classes
				local owners, classes = {}, {}
				for _, c in ipairs(gui:GetChildren()) do
					owners[#owners + 1] = { name = c.Name, n = #c:GetDescendants() + 1 }
				end
				table.sort(owners, function(a, b) return a.n > b.n end)
				local parts = {}
				for i = 1, math.min(10, #owners) do parts[i] = owners[i].name .. "=" .. owners[i].n end
				print("[Perf] top children: " .. table.concat(parts, ", "))
				for _, d in ipairs(gui:GetDescendants()) do classes[d.ClassName] = (classes[d.ClassName] or 0) + 1 end
				local cl = {}
				for k, v in pairs(classes) do cl[#cl + 1] = { k = k, v = v } end
				table.sort(cl, function(a, b) return a.v > b.v end)
				local cp = {}
				for i = 1, math.min(6, #cl) do cp[i] = cl[i].k .. "=" .. cl[i].v end
				print("[Perf] top classes: " .. table.concat(cp, ", "))
			end)
			if not okP then warn("[DebugGoto] perf failed: " .. tostring(errP)) end
			return
		end
		if target.kind == "beatslow" then
			-- Patron scoring beats slowed for screenshots; freeze keeps beat 2 on screen until beatslow:off
			local okB, errB = pcall(function()
				require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PatronEvents")).setSlow(target.mode)
			end)
			if okB then print("[DebugGoto] beatslow " .. target.mode .. " ok") else warn("[DebugGoto] beatslow failed: " .. tostring(errB)) end
			return
		end
		if target.kind == "drawer" then
			-- the left board drawer, for screenshots (start a round first: round1)
			local okD, errD = pcall(function() require(script.Parent.BoardDrawer).setCollapsed(target.closed) end)
			if okD then print("[DebugGoto] drawer " .. (target.closed and "closed" or "open") .. " ok") else warn("[DebugGoto] drawer failed: " .. tostring(errD)) end
			return
		end
		if target.kind == "loading" then
			-- the launch loading screen frozen at a percent, for screenshots (the real one is ReplicatedFirst/LoadingScreen)
			local okL, errL = pcall(function()
				local old = Players.LocalPlayer.PlayerGui:FindFirstChild("LoadingScreen")
				if old then old:Destroy() end
				local module = game:GetService("ReplicatedFirst"):WaitForChild("LoadingScreenUI", 3)
				if not module then
					error("ReplicatedFirst.LoadingScreenUI is not in this Studio session: resync with the Rojo 7.4.4 plugin (default.project.json maps src/ReplicatedFirst), stop Play and press Play again")
				end
				local UI = require(module)
				UI.show(Players.LocalPlayer.PlayerGui, { shared = ReplicatedStorage:WaitForChild("Shared"), frozen = target.percent / 100 })
			end)
			if okL then print("[DebugGoto] loading " .. target.percent .. " ok (set DebugGoto to menu to clear)") else warn("[DebugGoto] loading failed: " .. tostring(errL)) end
			return
		end
		if target.kind == "jump" or (target.kind == "boon" and not target.setId) then
			-- a real screen on the live run (Engine/DebugJump): the server does the work, the table re-renders from the pushed state
			local state = DebugGoto.getState and DebugGoto.getState()
			if not state or state.night == nil then warn("[DebugGoto] " .. tostring(value) .. " needs a live run: round1 first") return end
			OverlayManager.closeAllExcept("")
			hideMenu()
			if deps and deps.root then deps.root.Visible = true end
			hideTutorialOverlay()
			local key = target.key or "boon"
			local okJ, errJ = pcall(function() remotes:WaitForChild("DebugJump"):FireServer(key) end)
			if okJ then print("[DebugGoto] " .. key .. " ok") else warn("[DebugGoto] " .. key .. " failed: " .. tostring(errJ)) end
			return
		end
		if target.kind == "patrons" then
			local okG, errG = pcall(function() remotes:WaitForChild("DebugGrantPatrons"):FireServer(target.count) end)
			if okG then print("[DebugGoto] patrons " .. target.count .. " sent (needs a live run: round1 first)") else warn("[DebugGoto] patrons failed: " .. tostring(errG)) end
			return
		end
		if target.kind == "playhand" then
			local state = DebugGoto.getState and DebugGoto.getState()
			local n = state and state.hand and math.min(5, #state.hand) or 0
			if n < 1 then warn("[DebugGoto] playhand needs a dealt hand: round1 first") return end
			if target.keep then remotes:WaitForChild("DebugSetTarget"):FireServer(5000) end -- same client, so it arrives before PlayHand
			-- the hub's real Play Hand handler (preview, score popup, Patron beats), not a bare remote: beats are client-side
			if not DebugGoto.playSelected then warn("[DebugGoto] playhand: hub play handler not wired, nothing sent") return end
			task.spawn(function()
				-- the Play Hand preview reads the client's state, so wait until the pushed 5000 target has arrived (else TARGET CLEARED flashes)
				if target.keep then
					local t0 = os.clock()
					while os.clock() - t0 < 3 do
						local st = DebugGoto.getState and DebugGoto.getState()
						if st and st.targetScore == 5000 then break end
						task.wait(0.05)
					end
				end
				DebugGoto.playSelected(n)
				print("[DebugGoto] playhand ran the real Play Hand flow with " .. n .. " cards" .. (target.keep and " (target 5000)" or ""))
			end)
			return
		end
		if target.kind == "sfx" then
			if not Cue.audition(target.cue) then warn("[DebugGoto] sfx:" .. target.cue .. " did not play") end
			return
		end
		if target.kind == "fx" then
			-- the True Wildcard banner and effect, or the Legendary banner and FlashFX, once, on the play screen (round1 first so the table is up)
			local tools = DebugGoto.tools or {}
			if not tools.showScorePopup then warn("[DebugGoto] " .. target.effect .. " ignored: no score popup wired") return end
			local preview = { name = "Straight Flush", score = 48000, chips = 800, mult = 60, breakdown = {}, roundScoreBefore = 0, targetScore = 3000,
				isLegendary = target.effect == "legendary" }
			if target.effect == "wildcard" then preview.wildcardResolution = { label = "8 of Hearts" } end
			local okF, errF = pcall(function()
				if deps and deps.root then deps.root.Visible = true end
				if deps and deps.menuFrame then deps.menuFrame.Visible = false end
				tools.showScorePopup(preview, nil)
			end)
			if okF then print("[DebugGoto] " .. target.effect .. " ok") else warn("[DebugGoto] " .. target.effect .. " failed: " .. tostring(errF)) end
			return
		end
		if target.kind == "audit" then
			local okA, errA = pcall(function() require(script.Parent.AuditV2).run() end)
			if not okA then warn("[DebugGoto] audit:v2 failed: " .. tostring(errA)) end
			return
		end
		if target.kind == "selfcheck" then
			local okC, errC = pcall(function() require(script.Parent.SelfCheck).run() end)
			if not okC then warn("[DebugGoto] selfcheck failed: " .. tostring(errC)) end
			return
		end
		if target.kind == "tablecheck" then
			local okT, errT = pcall(function() require(script.Parent.TableCheck).run() end)
			if not okT then warn("[DebugGoto] tablecheck failed: " .. tostring(errT)) end
			return
		end
		if target.kind == "decorcheck" then
			local okD, errD = pcall(function() require(script.Parent.DecorCheck).run() end)
			if not okD then warn("[DebugGoto] decorcheck failed: " .. tostring(errD)) end
			return
		end
		if target.kind == "screencheck" then
			local okK, errK = pcall(function() require(script.Parent.ScreenCheck).run() end)
			if not okK then warn("[DebugGoto] screencheck failed: " .. tostring(errK)) end
			return
		end
		if target.kind == "scale" then
			local okS, errS = pcall(applyScale, target)
			if not okS then warn("[DebugGoto] " .. tostring(value) .. " failed: " .. tostring(errS)) end
			return
		end
		local ok, err = pcall(function()
			pendingRound1 = false
			-- a loading preview never covers the next screen
			pcall(function()
				local ls = player.PlayerGui:FindFirstChild("LoadingScreen")
				if ls then ls:Destroy() end
			end)
			pcall(function() require(script.Parent.NewsPanel).hideNow() end) -- every jump starts with the News board closed
			pcall(function() require(script.Parent.LoginStreakUI).suppress(true) end) -- the daily reward plate would cover the view
			if target.kind == "menu" then
				OverlayManager.closeAllExcept("")
				showMenu()
			elseif target.kind == "tome" then
				OverlayManager.closeAllExcept("")
				showMenu()
				if not OverlayManager.open(target.page) then error("no opener for " .. target.page) end
				if target.sub then
					warn("[DebugGoto] sub-tab " .. target.sub .. " cannot be clicked from script; panel opened on its first tab")
				end
			elseif target.kind == "freshsave" then
				OverlayManager.closeAllExcept("")
				remotes:WaitForChild("DebugFreshSave"):FireServer()
				showMenu()
			elseif target.kind == "opener" then
				OverlayManager.closeAllExcept("")
				showMenu()
				if not OverlayManager.open(target.opener) then error("no opener for " .. target.opener) end
			elseif target.kind == "map" then
				-- the real Tavern Map: Client/Journey registers its opener (the corner button's path) on this module
				OverlayManager.closeAllExcept("")
				showMenu()
				if not DebugGoto.openMap then error("the Tavern Map opener is not registered yet") end
				local MapErrors = require(script.Parent.MapErrors)
				local before = MapErrors.total
				DebugGoto.openMap()
				task.delay(3, function() -- the panel opens a moment after the map; say ok only when no [TavernMap] error came since the jump
					if MapErrors.total == before then print("[DebugGoto] map ok") else warn("[DebugGoto] map had " .. (MapErrors.total - before) .. " [TavernMap] error(s)") end
				end)
				if target.night then
					warn("[DebugGoto] map:night=" .. target.night .. " is parsed but the map always opens on the live Night")
				end
			elseif target.kind == "news" then
				OverlayManager.closeAllExcept("")
				showMenu()
				require(script.Parent.NewsPanel).open()
			elseif target.kind == "boon" then -- boon or boon:<setId>: the Night boon picker with three sample boons, over the table
				OverlayManager.closeAllExcept("")
				hideMenu()
				local NB = require(ReplicatedStorage.Shared.Engine.NightBoons)
				local draft = NB.draft({ night = 3, rng = function() return 1 end }, true)
				require(script.Parent.ChoicePanel).update({ choice = draft })
			elseif target.kind == "equip" then
				if not require(ReplicatedStorage.Shared.Engine.CosmeticSets).getById(target.setId) then error("unknown card set " .. target.setId) end
				pcall(function() require(script.Parent.CosmeticSetsView).stopPreview() end)
				remotes:WaitForChild("DebugEquipSet"):FireServer(target.setId)
				print("[DebugGoto] equipped set=" .. target.setId .. " (server equip, no preview)")
			elseif target.kind == "round1" or target.kind == "synth" then
				synthWhich = (target.kind == "synth") and target.which or nil
				synthVariant, synthPage = target.variant, target.page
				OverlayManager.closeAllExcept("")
				hideMenu()
				if deps and deps.root then deps.root.Visible = true end -- the real launch shows the table too (Client/ChallengeStart.launch)
				hideTutorialOverlay()
				local CosmeticSets = require(ReplicatedStorage.Shared.Engine.CosmeticSets)
				previewSet = nil
				wantedMod, wantedTag = target.modId, target.tagId
				-- a preview left over from an earlier jump or the Card Sets panel would win over this jump's set: clear it first
				pcall(function() require(script.Parent.CosmeticSetsView).stopPreview() end)
				if target.setId then
					previewSet = CosmeticSets.getById(target.setId)
					if not previewSet then error("unknown card set " .. target.setId) end
				end
				pendingRound1 = true
				lastStep = "start"
				selectSent = false
				round1Token = round1Token + 1
				local mine = round1Token
				remotes:WaitForChild("StartSeedRun"):FireServer(Rules.SEED_CODE)
				task.delay(Rules.ROUND1_TIMEOUT, function()
					if pendingRound1 and round1Token == mine then
						pendingRound1 = false
						warn("[DebugGoto] round1 stuck at step '" .. lastStep .. "' after " .. Rules.ROUND1_TIMEOUT .. " s")
					end
				end)
			else
				error(target.kind .. " is not reachable from script (needs a second player)")
			end
			-- menu:<setId>, map:<setId>, tome:<page>:<setId>, news:<setId>: preview that set over whatever is equipped
			if target.setId and (target.kind == "menu" or target.kind == "tome" or target.kind == "map" or target.kind == "news" or target.kind == "boon") then
				local set = require(ReplicatedStorage.Shared.Engine.CosmeticSets).getById(target.setId)
				if not set then error("unknown card set " .. target.setId) end
				local View = require(script.Parent.CosmeticSetsView)
				pcall(View.stopPreview)
				View.preview(set.id, set.cardBackId)
				print("[DebugGoto] screen set=" .. set.id .. " (" .. target.kind .. ")")
			end
		end)
		if ok and target.kind == "synth" then
			-- "<name> ok" is printed once the screen is up
		elseif ok then
			print("[DebugGoto] " .. tostring(value) .. " ok")
		else
			warn("[DebugGoto] " .. tostring(value) .. " failed: " .. tostring(err))
		end
	end

	-- round1: answer the draft and blessing choices with the first option, then start the round
	remotes:WaitForChild("StateUpdated").OnClientEvent:Connect(function(state)
		if not pendingRound1 then return end
		lastStep = Rules.stepOf(state)
		local count = Rules.handCount(state)
		if synthWhich == "roundselect" and lastStep == "select" then
			pendingRound1 = false
			synthWhich = nil
			print("[DebugGoto] roundselect ok")
			return
		end
		if count then
			pendingRound1 = false
			if synthWhich then
				local which, variant, page = synthWhich, synthVariant, synthPage
				synthWhich, synthVariant, synthPage = nil, nil, nil
				-- the set preview first, so the room, keeper, plates and boss table are built for it (it used to be dropped on synth screens)
				if previewSet then
					local set = previewSet
					previewSet = nil
					local okP, errP = pcall(function() require(script.Parent.CosmeticSetsView).preview(set.id, set.cardBackId) end)
					print("[DebugGoto] screen set=" .. set.id .. " (" .. which .. ")" .. (okP and "" or (" preview failed: " .. tostring(errP))))
				end
				local okS, errS = pcall(showSynth, which, variant, page)
				if not okS then warn("[DebugGoto] " .. which .. " failed: " .. tostring(errS)) end
				return
			end
			print("[DebugGoto] round1 hand=" .. count)
			if wantedTag or wantedMod then
				local tagId, modId = wantedTag, wantedMod
				wantedTag, wantedMod = nil, nil
				if modId then pcall(function() remotes:WaitForChild("DebugSetMod"):FireServer(modId, true) end) end
				if tagId then pcall(function() remotes:WaitForChild("DebugSetTag"):FireServer(tagId) end) end
				task.delay(1, function() -- let the state update reach the board, then list what it shows
					local okB, board = pcall(function() return player.PlayerGui.GameUI.GameRoot.Sidebar end)
					if not okB or not board then warn("[DebugGoto] board text: Sidebar not found") return end
					local lines = {}
					for _, d in ipairs(board:GetDescendants()) do
						if d:IsA("TextLabel") and d.Text ~= "" and d.Visible then
							local shown = true
							local p = d.Parent
							while p and p ~= board do
								if p:IsA("GuiObject") and not p.Visible then shown = false break end
								p = p.Parent
							end
							if shown then lines[#lines + 1] = d.Text:gsub("<[^>]+>", "") end
						end
					end
					print("[DebugGoto] board text: " .. table.concat(lines, " | "))
				end)
			end
			if previewSet then
				local set = previewSet
				previewSet = nil
				-- same call the Card Sets Preview button makes; PlayScenePaint then prints [PlayTableSet] <set> front=<painted|default>
				local okP, errP = pcall(function() require(script.Parent.CosmeticSetsView).preview(set.id, set.cardBackId) end)
				print("[DebugGoto] screen set=" .. set.id .. " (round1)" .. (okP and "" or (" preview failed: " .. tostring(errP))))
			end
			return
		end
		hideTutorialOverlay()
		local step, optionId = Rules.round1Step(state, wantedMod)
		if step == "choice" then
			if wantedMod and state.choice and state.choice.kind == "modifier" and optionId ~= wantedMod then
				local ids = {}
				for _, o in ipairs(state.choice.options) do ids[#ids + 1] = o.id end
				-- not in the random draw: the server swaps it in, then the normal Choice remote picks it (same order on the wire)
				print("[DebugGoto] blessing '" .. wantedMod .. "' was not in the draw (" .. table.concat(ids, ", ") .. "); asking the server to offer it")
				remotes:WaitForChild("DebugSetMod"):FireServer(wantedMod)
				optionId = wantedMod
			end
			remotes:WaitForChild("Choice"):FireServer(optionId)
		elseif step == "select" and not selectSent then
			selectSent = true
			remotes:WaitForChild("SelectRound"):FireServer() -- stays pending until the hand is dealt
		end
	end)

	local function watch(inst)
		if inst:IsA("StringValue") and inst.Name == "DebugGoto" then
			inst.Changed:Connect(function() go(inst.Value) end)
			if inst.Value ~= "" then go(inst.Value) end
		end
	end
	player.ChildAdded:Connect(watch)
	for _, child in ipairs(player:GetChildren()) do watch(child) end
	player:GetAttributeChangedSignal("DebugGoto"):Connect(function() go(player:GetAttribute("DebugGoto")) end)
end

return DebugGoto
