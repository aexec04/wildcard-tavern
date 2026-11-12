--[[
	Shared/Engine/ConfirmCopy.lua
	The words of the Yes / No dialog (Client/ConfirmDialog), one entry per action, so no action can ever inherit another action's label
	(the old dialog said "Yes, discard it" for using a recipe). Pure Lua, tested in EngineTests ("ConfirmCopy").

	ConfirmCopy.DEFAULT                  { yes = "Yes", no = "Cancel", danger = false }
	ConfirmCopy.use(name, description)   { message, yesText = "Use it", noText = "Not now", danger = false }
	ConfirmCopy.sell(name, refund)       { message, yesText = "Sell it", noText = "Keep it", danger = true }
	ConfirmCopy.discard(count)           { message, yesText = "Discard", noText = "Cancel", danger = true }
	ConfirmCopy.options(opts)            the opts a dialog uses: missing labels become "Yes" / "Cancel", never a destructive word
	ConfirmCopy.split(message)           title line, body text (the first line of the message is the title, the rest the body)
	ConfirmCopy.bodyLines(body, width, size)   estimated wrapped lines of the body
	ConfirmCopy.MAX_WIDTH                520
]]

local ConfirmCopy = {}

ConfirmCopy.DEFAULT = { yes = "Yes", no = "Cancel", danger = false }
ConfirmCopy.MAX_WIDTH = 520
ConfirmCopy.TEXT_SIZE = 16

function ConfirmCopy.use(name, description)
	local body = tostring(description or "")
	return {
		message = string.format("Use %s?", tostring(name)) .. (body ~= "" and ("\n\n" .. body) or ""),
		yesText = "Use it", noText = "Not now", danger = false,
	}
end

function ConfirmCopy.sell(name, refund)
	return {
		message = string.format("Sell %s?\n\nYou'll get %d tips back. This can't be undone.", tostring(name), math.floor(tonumber(refund) or 0)),
		yesText = "Sell it", noText = "Keep it", danger = true,
	}
end

function ConfirmCopy.discard(count)
	count = math.floor(tonumber(count) or 0)
	return {
		message = string.format("Discard %d card%s?", count, count == 1 and "" or "s"),
		yesText = "Discard", noText = "Cancel", danger = true,
	}
end

function ConfirmCopy.options(opts)
	opts = opts or {}
	local yes = (type(opts.yesText) == "string" and opts.yesText ~= "") and opts.yesText or ConfirmCopy.DEFAULT.yes
	local no = (type(opts.noText) == "string" and opts.noText ~= "") and opts.noText or ConfirmCopy.DEFAULT.no
	return { yesText = yes, noText = no, danger = opts.danger == true }
end

function ConfirmCopy.split(message)
	message = tostring(message or "")
	local title, body = message:match("^(.-)\n\n(.*)$")
	if not title then title, body = message, "" end
	return title, body
end

function ConfirmCopy.bodyLines(body, width, size)
	body = tostring(body or "")
	if body == "" then return 0 end
	local per = math.max(1, math.floor(width / ((size or ConfirmCopy.TEXT_SIZE) * 0.55)))
	local lines = 0
	for part in (body .. "\n"):gmatch("(.-)\n") do
		lines = lines + math.max(1, math.ceil(#part / per))
	end
	return lines
end

return ConfirmCopy
