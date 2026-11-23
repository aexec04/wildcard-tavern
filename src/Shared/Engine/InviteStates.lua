--[[
	Engine/InviteStates.lua
	Every state of the friend invite and spectate flow has one kind line (60 characters or less) and a plate that fits the screen.
	Pure and tested. The Invite button toast (Client/InvitePrompt) and the Spectate end messages (server, Spectate canWatch reasons)
	both read from here, so no player ever sees a raw engine word like "Unknown player."

	Invite:   sent, joined, declined, unavailable, failed
	Spectate: full, private, blocked, notInRun, already, self, stopped, removed, unknown
	line(state)            -> the kind line
	spectateLine(reason)   -> the kind line for an engine reason string (Spectate.canWatch), unknown reasons get the `unknown` line
	plate(w, h)            -> toast rect { x, y, w, h } (bottom centre, 52 px tall, inside the screen with a 12 px margin)
]]

local InviteStates = {}

InviteStates.MAX_LINE = 60
InviteStates.Lines = {
	sent = "Invite sent! Your friend can join from the invite.",
	joined = "Your friend joined! You get Tips on your next run.",
	declined = "No problem. You can invite a friend any time.",
	unavailable = "Invites are not available right now.",
	failed = "Could not open invites. Try again in a moment.",
	full = "That table is full right now. Try again soon.",
	private = "That player is keeping their table private.",
	blocked = "That table is not open to you right now.",
	notInRun = "That player is not in a run right now.",
	already = "You are already watching that table.",
	self = "You are the star of your own table!",
	stopped = "Stopped watching.",
	removed = "You were moved away from this table.",
	unknown = "That table is not open right now.",
}

-- Spectate.canWatch and server reason strings -> state key
InviteStates.Reasons = {
	["That table is full."] = "full",
	["That player is not allowing spectators."] = "private",
	["You cannot watch that player."] = "blocked",
	["That player is not in a run."] = "notInRun",
	["Already watching."] = "already",
	["You cannot watch yourself."] = "self",
	["Unknown player."] = "unknown",
	["Stopped watching."] = "stopped",
	["You were removed from this table."] = "removed",
}

function InviteStates.line(state)
	return InviteStates.Lines[state] or InviteStates.Lines.unknown
end

function InviteStates.spectateLine(reason)
	local key = type(reason) == "string" and InviteStates.Reasons[reason] or nil
	return InviteStates.line(key or "unknown")
end

InviteStates.TOAST_H = 52
InviteStates.MARGIN = 12
function InviteStates.plate(w, h)
	local pw = math.max(240, math.min(520, w - 2 * InviteStates.MARGIN))
	local ph = InviteStates.TOAST_H
	return { x = math.floor((w - pw) / 2), y = math.max(0, h - ph - 24), w = pw, h = ph }
end

return InviteStates
