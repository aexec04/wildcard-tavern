--[[
	Engine/CollectionLoadJob.lua
	The cancellable tile build of the Collection (Client/Collection), pure so it is tested without Roblox.

	local job = Job.new()
	job:cancel()                            a refresh starts by cancelling whatever was building (a tab switch)
	local rest = job:begin(count, build)    cut `count` tiles into chunks (CollectionTileCache.CHUNK, 12 tiles), build chunk 1 NOW (the visible
	                                        rows) and return a function that builds the others one per frame; nil when chunk 1 held everything
	rest(wait)                              builds chunks 2..n in order, calling wait() (a task.wait) before each one; stops quietly when the job was
	                                        cancelled meanwhile; returns true only when every chunk was built
	job:cancel()                            a newer build or a tab switch: the running `rest` builds nothing more
	job:close() / job:reopen()              the Collection closed / opened: nothing is built while it is closed
	job:alive(mine)                         true while the build that took token `mine` (job.token at begin) may still work: same build, panel open
	build(from, to)                         builds tiles from..to (inclusive)
]]

local Engine = script.Parent
local TileCache = require(Engine:WaitForChild("CollectionTileCache"))

local Job = {}
Job.__index = Job

function Job.new()
	return setmetatable({ token = 0, open = true }, Job)
end

function Job:alive(mine)
	return self.open and self.token == mine
end

function Job:cancel()
	self.token = self.token + 1
end

function Job:close()
	self.open = false
	self.token = self.token + 1
end

function Job:reopen()
	self.open = true
end

function Job:begin(count, build)
	local mine = self.token -- the caller cancels the build before it (a refresh), so this build owns the current token
	if not self.open then return nil end
	local chunks = TileCache.chunks(count, TileCache.CHUNK)
	if chunks[1] then build(chunks[1].from, chunks[1].to) end
	if #chunks < 2 then return nil end
	return function(wait)
		for i = 2, #chunks do
			if wait then wait() end
			if not self:alive(mine) then return false end
			build(chunks[i].from, chunks[i].to)
		end
		return self:alive(mine)
	end, mine
end

return Job
