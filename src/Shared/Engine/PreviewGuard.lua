--[[
	Engine/PreviewGuard.lua
	Card Set Preview mode is look-only. Pure rules, no Roblox types.

	blocked(remoteName, previewing)  -> true when a run remote must be rejected (the server calls it with the player's PreviewMode attribute)
	sampleState(real)                -> the table the play screen shows while previewing: a fixed sample hand (one card of each suit, face
	                                    cards, an Ace) and sample numbers (Night 1 Round 1, 0 / 300), so a real run is never shown or changed;
	                                    anything that is not a playing round is returned as is
	barText(name)                    -> the preview bar line
]]

local PreviewGuard = {}

-- every remote that acts on a run (a new run or leaving one clears the preview instead, see Server)
PreviewGuard.BLOCKED = {
	["Rem.PlayHand"] = true, ["Rem.Discard"] = true, ["Rem.BuyPatron"] = true, ["Rem.SellPatron"] = true, ["Rem.MovePatron"] = true, ["Rem.UseRuleBan"] = true,
	["Rem.Choice"] = true, ["Rem.ChooseRoad"] = true, ["Rem.Minigame"] = true, ["Rem.SideStop"] = true, ["Rem.BuyRecipe"] = true,
	["Rem.UseRecipe"] = true, ["Rem.SellRecipe"] = true, ["Rem.RerollShop"] = true, ["Rem.Haggle"] = true, ["Rem.Stranger"] = true, ["Rem.BuyPack"] = true,
	["Rem.ResolvePack"] = true, ["Rem.BuyHousePass"] = true, ["Rem.BuyMark"] = true, ["Rem.AdvanceRound"] = true, ["Rem.SelectRound"] = true, ["Rem.SkipRound"] = true,
	["UseRuleBanRemote"] = true, ["Rem.UnlockRoad"] = true, ["Rem.UseCompass"] = true, ["Rem.RequestContinue"] = true,
}
-- remotes that end a preview on the server (a new run, a restart, leaving a run)
PreviewGuard.ENDS = { ["Rem.StartRun"] = true, ["Rem.RestartRun"] = true, ["Rem.AbandonRun"] = true, ["Rem.StartTutorial"] = true }

PreviewGuard.DIM = 0.4 -- Play Hand and Discard are dimmed by this much while previewing
PreviewGuard.PLATE_TIP = "Preview only"

function PreviewGuard.blocked(remoteName, previewing)
	return previewing == true and PreviewGuard.BLOCKED[remoteName] == true
end

local SAMPLE = {
	{ 14, "Spades" }, { 13, "Hearts" }, { 12, "Diamonds" }, { 11, "Clubs" },
	{ 10, "Spades" }, { 7, "Hearts" }, { 5, "Diamonds" }, { 2, "Clubs" },
}

function PreviewGuard.sampleHand()
	local hand = {}
	for i, c in ipairs(SAMPLE) do hand[i] = { rank = c[1], suit = c[2] } end
	return hand
end

function PreviewGuard.sampleState(real)
	if type(real) ~= "table" or real.phase ~= "playing" then return real end
	local s = {}
	for k, v in pairs(real) do s[k] = v end
	s.hand = PreviewGuard.sampleHand()
	s.night, s.round = 1, 1
	s.roundScore, s.targetScore = 0, 300
	s.handsRemaining, s.discardsRemaining = 4, 3
	s.tips = 4
	s.ownedPatrons = {}
	s.isBossRound, s.bossModifier = false, nil
	return s
end

function PreviewGuard.barText(name)
	return "Preview mode: " .. tostring(name) .. "  (look only, X to end)"
end

return PreviewGuard
