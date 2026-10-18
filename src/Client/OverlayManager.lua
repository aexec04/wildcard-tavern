--[[
	Client/OverlayManager.lua
	BUGFIX (Ahmed's report: opening a different overlay -- e.g. clicking
	Themes while Journey, or Collection, or any other corner-button panel
	was already open -- left the new panel drawn directly on top of the
	old one, both still fully visible and overlapping, instead of the old
	one closing first). Every one of the always-reachable corner-button/
	deck-widget overlays (Collection, Themes, Journey, Settings,
	HowToPlay, PokerHandsReference, DailyLeaderboard, DeckTracker) now
	registers its own "close myself" function here, and calls
	closeAllExcept(itsOwnName) right before it opens itself -- so opening
	any one of them always closes whichever other one happened to be
	open, no matter which pair.

	Deliberately NOT used for nested confirmation dialogs (ConfirmDialog,
	and RunSetup/SeedRunDialog's own confirm steps) -- those are meant to
	layer ON TOP of whatever opened them (e.g. a "are you sure?" dialog
	shown over the Run Setup panel itself), so they never register here
	and never call closeAllExcept. Registering them would make opening a
	nested confirm immediately close its own parent panel -- the opposite
	of what a confirmation dialog is for.

	A standalone, dependency-free module (NOT threaded through deps from
	init.client.lua, unlike every other Client module's usual
	`return function(deps) ... end` shape) specifically so requiring it
	costs NOTHING against init.client.lua's own top-level-local budget --
	that file is already right up against Lua's 200-local ceiling (see
	ArtAssets.lua's and Collection.lua's own BUGFIX comments for the
	first two times that limit bit this exact file). Each overlay module
	requires this directly off its own `script.Parent` -- every overlay
	module is a sibling ModuleScript under the same parent Script
	init.client.lua runs as (same place ArtAssets.lua/DeckWidget.lua/etc.
	already live, per default.project.json mapping the whole src/Client
	folder onto that one Script) -- so init.client.lua itself never has
	to require or even know about this file.

	Roblox's require() caches a ModuleScript's result per-instance, so
	every overlay module that requires this gets back the exact same
	`closeFns` table below -- registrations from all of them really do
	end up in one shared place.

	Returns:
		{
			register = function(name, closeFn), -- closeFn takes no args
			closeAllExcept = function(exceptName),
		}
]]

local closeFns = {} -- name -> function() -- closes that overlay if it's open; safe to call even if already closed

local function register(name, closeFn)
	closeFns[name] = closeFn
end

local function closeAllExcept(exceptName)
	for name, closeFn in pairs(closeFns) do
		if name ~= exceptName then
			closeFn()
		end
	end
end

return {
	register = register,
	closeAllExcept = closeAllExcept,
}
