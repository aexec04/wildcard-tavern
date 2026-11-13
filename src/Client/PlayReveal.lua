--[[
	Client/PlayReveal.lua
	Holds a played hand's score reveal for the server's play report, then plays the report (Engine/PlayReport.lua).

	Play is pressed: the hub builds the card ghosts and its local preview as before, but instead of starting the reveal
	it calls PlayReveal.begin. When the next state arrives with a newer state.lastPlay, the reveal starts with the
	server's numbers and entries. If no report comes within PlayReport.TIMEOUT (a refused play, a very slow link), the
	reveal starts with the local preview, which never contains a luck roll, so nothing shown was invented.

	  PlayReveal.begin{ preview, played, held, seqBefore, show = fn(finalPreview, fromServer) }
	  PlayReveal.onState(state)     call for every state the server sends, before it is drawn
	  PlayReveal.waiting() -> bool  a reveal is still held (tests and debugging)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PlayReport = require(Engine:WaitForChild("PlayReport"))
local Patrons = require(Engine:WaitForChild("Patrons"))

local RunService = game:GetService("RunService")

local M = {}

local pending

-- Studio only: one line per hand, so a playtest can see the reveal took the server's numbers (and how the preview compared)
local function note(text)
	if RunService:IsStudio() then print("[PlayReveal] " .. text) end
end

function M.begin(args)
	local mine = { preview = args.preview, played = args.played, held = args.held, seqBefore = args.seqBefore, show = args.show }
	pending = mine
	task.delay(PlayReport.TIMEOUT, function()
		if pending == mine then
			pending = nil
			note(string.format("no report within %.1f s, showing the local preview (%s %d)", PlayReport.TIMEOUT, tostring(mine.preview.name), math.floor((mine.preview.score or 0) + 0.5)))
			mine.show(mine.preview, false)
		end
	end)
end

function M.onState(state)
	local mine = pending
	if not mine then return end
	local report = state and state.lastPlay
	if not PlayReport.isNew(report, mine.seqBefore) then return end
	pending = nil
	local ok, merged = pcall(PlayReport.apply, mine.preview, report, mine.played, mine.held, Patrons.getById)
	if not ok then
		warn("[PlayReveal] report could not be applied, showing the local preview: " .. tostring(merged))
	end
	if ok then
		note(string.format("hand %d from the server: %s %d (the preview said %d), %d entries", report.seq, tostring(report.handName),
			math.floor((report.score or 0) + 0.5), math.floor((mine.preview.score or 0) + 0.5), #(report.entries or {})))
	end
	mine.show(ok and merged or mine.preview, ok)
end

function M.waiting()
	return pending ~= nil
end

return M
