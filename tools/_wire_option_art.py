"""One-off: wires OptionArt into ContentArt, RunEvents, RunChoice, ChoicePanel and adds the test."""


def sub(p, a, b):
    s = open(p).read()
    assert a in s, (p, a)
    open(p, "w").write(s.replace(a, b, 1))


sub("src/Shared/Engine/ContentArt.lua",
    '	blessing_icons = require(Engine:WaitForChild("BlessingIconArt")),',
    '	option_icons = require(Engine:WaitForChild("OptionArt")),         -- keyed by event option kind (RunEvents.OPTION_KINDS)\n'
    '	blessing_icons = require(Engine:WaitForChild("BlessingIconArt")),')

sub("src/Shared/Engine/RunEvents.lua", "function RunEvents.getById(id)",
    '''-- one painted icon per option KIND (OptionArt), not per event; the event's art and then its emoji are the fallbacks
RunEvents.OPTION_KINDS = {
	decline = "decline", bet = "bet", trade = "recipe", swap = "swap", accept = "gain",
	buy = "hand", buy_hand = "hand", trade_hand = "hand",
	sell_discard = "discard", mend = "discard", shoo = "discard", share = "supper",
}

function RunEvents.getById(id)''')

sub("src/Shared/Engine/RunChoice.lua",
    'icon = o.id == "decline" and "✋" or event.icon, line1',
    'icon = o.id == "decline" and "✋" or event.icon, kind = RunEvents.OPTION_KINDS[o.id], line1')

sub("src/Client/ChoicePanel.lua",
    '''	elseif choice.kind == "event" and not isDecline then
		local artId = ContentArt.getImageId("events", choice.eventId)
		if artId then
			PatronPlaque.applyById(well, artId, { emojiLabel = icon, zIndex = 65, cornerRadius = 42 })
		end
	end''',
    '''	elseif choice.kind == "event" then
		-- one painted icon per option kind (decline included), else the event's own art; the emoji is only the last fallback
		local artId = (option.kind and ContentArt.getImageId("option_icons", option.kind)) or (not isDecline and ContentArt.getImageId("events", choice.eventId)) or nil
		if artId then
			PatronPlaque.applyById(well, artId, { emojiLabel = icon, zIndex = 65, cornerRadius = 42 })
		elseif game:GetService("RunService"):IsStudio() then
			print(("[EmojiLeft] event %s option %s is drawn from the emoji %s"):format(tostring(choice.eventId), tostring(option.id), tostring(option.icon)))
		end
	end''')

test = '''table.insert(tests, { name = "Event art: every event and every event option shown in a normal run has a painted id, the emoji is only a fallback", fn = function()
	local RunEvents = require(script.Parent.Parent.Engine.RunEvents)
	local EventArt = require(script.Parent.Parent.Engine.EventArt)
	local OptionArt = require(script.Parent.Parent.Engine.OptionArt)
	local RunChoice = require(script.Parent.Parent.Engine.RunChoice)
	for _, ev in ipairs(RunEvents.Definitions) do
		expectTrue(EventArt[ev.id] ~= nil, "event " .. ev.id .. " has a painted id")
		for _, o in ipairs(ev.options) do
			local kind = RunEvents.OPTION_KINDS[o.id]
			expectTrue(kind ~= nil and OptionArt[kind] ~= nil, "option " .. o.id .. " of " .. ev.id .. " has a painted option icon")
		end
		local choice = RunChoice.forceEvent(ev.id)
		for _, o in ipairs(choice.options) do expectTrue(o.kind ~= nil, "choice option " .. o.id .. " carries its kind") end
	end
	if not io then return end
	local f = io.open("src/Client/ChoicePanel.lua", "r"); local src = f and f:read("*a") or ""; if f then f:close() end
	expectTrue(src:find("[EmojiLeft]", 1, true) ~= nil and src:find('"option_icons"', 1, true) ~= nil, "the panel draws option icons and prints [EmojiLeft] for any emoji fallback in Studio")
end })

'''
p = "src/Shared/Tests/EngineTests.lua"
s = open(p).read()
i = s.rindex("return tests")
open(p, "w").write(s[:i] + test + s[i:])
print("ok")
