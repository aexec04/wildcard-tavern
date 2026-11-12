--[[
	Client/Announcer.lua
	One queue for the centre of the screen. Every transient message goes through it (Round Complete, True Wildcard lock in, the flavor line
	merged into Round Complete) so only ONE shows at a time, 0.25 s apart; the rules are the pure, tested Engine/Announcer. A presenter
	supplies show(done, msg) (draw it; call done() when it is gone) and hide(msg) (remove it now).

	Announcer.submit{ id, kind, priority, duration, stateKey, text, show, hide, onDrop }
	Announcer.addFlavor(text, apply)   merge a flavor line into the Round Complete that is up or queued; apply(text) is called when that plate
	                                   is already on screen. Returns false when there is none (then say it some other way, or drop it).
	Announcer.request(kind, priority, duration)   -> ticket { wait(timeout) -> bool, release() } for a presenter that draws itself (the
	                                   True Wildcard banner): wait() yields until it is this message's turn, release() frees the slot
	Announcer.setState(key)            the round state key (messages made for another state are dropped)
	Announcer.isIdle()                 nothing up and nothing waiting (the quiet "Night begins next" strip shows only then)
	Announcer.onChange(fn)             fn() whenever a message appears or disappears
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Announcer"))

local Announcer = {}

local core = Rules.new()
local presenters = {} -- id -> { show, hide, onDrop, text }
local listeners = {}
local connection

local function changed()
	for _, fn in ipairs(listeners) do pcall(fn) end
end

local function step()
	local now = os.clock()
	local ops = core:tick(now)
	for _, op in ipairs(ops) do
		local p = presenters[op.msg.id]
		if op.op == "show" and p and p.show then
			local id = op.msg.id
			pcall(p.show, function() core:done(id, os.clock()) end, op.msg)
		elseif op.op == "hide" then
			if p and p.hide then pcall(p.hide, op.msg) end
			presenters[op.msg.id] = nil
		elseif op.op == "drop" then
			if p and p.onDrop then pcall(p.onDrop, op.msg, op.reason) end
			presenters[op.msg.id] = nil
		end
	end
	if #ops > 0 then changed() end
	if core:isIdle() and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function ensureRunning()
	if not connection then connection = RunService.Heartbeat:Connect(step) end
end

function Announcer.submit(args)
	local id = args.id or (tostring(args.kind) .. tostring(os.clock()))
	presenters[id] = { show = args.show, hide = args.hide, onDrop = args.onDrop }
	core:submit({ id = id, kind = args.kind, priority = args.priority or 0, duration = args.duration or 2.6, stateKey = args.stateKey, text = args.text }, os.clock())
	ensureRunning()
	step() -- an idle centre shows it in the same frame
	return id
end

function Announcer.addFlavor(text, apply)
	local msg, onScreen = core:addFlavor(text)
	if not msg then return false end
	if onScreen and apply then pcall(apply, text) end
	return true
end

-- A ticket for a presenter that draws itself and cannot be wrapped in a callback (the True Wildcard banner inside the scoring sequence).
function Announcer.request(kind, priority, duration)
	local ticket = { started = false, id = "ticket_" .. tostring(kind) .. tostring(os.clock()) }
	Announcer.submit({
		id = ticket.id, kind = kind, priority = priority, duration = duration,
		show = function() ticket.started = true end,
		onDrop = function() ticket.dropped = true end,
	})
	function ticket.wait(timeout)
		local t0 = os.clock()
		while not ticket.started and not ticket.dropped and os.clock() - t0 < (timeout or 1.5) do
			task.wait(0.05)
		end
		if not ticket.started then
			core:cancel(ticket.id, os.clock()) -- stop waiting: show it now rather than never, without holding the slot
			presenters[ticket.id] = nil
			return false
		end
		return true
	end
	function ticket.release()
		core:done(ticket.id, os.clock())
	end
	return ticket
end

function Announcer.setState(key)
	core:setState(key)
end

function Announcer.isIdle()
	return core:isIdle()
end

function Announcer.onChange(fn)
	listeners[#listeners + 1] = fn
end

-- test hook: the pure queue behind it
Announcer._core = core

return Announcer
