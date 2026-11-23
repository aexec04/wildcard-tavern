-- usage: lua tools/_splice_block.lua <block file> <marker prefix> [<first line of an older copy of the block>]
-- Inserts the block before the marker line; when an older copy starts at the third argument, that copy is replaced.
local blockPath, marker, oldStart = arg[1], arg[2], arg[3]
local f = assert(io.open(blockPath, "rb")); local block = f:read("a"); f:close()
local t = assert(io.open("src/Shared/Tests/EngineTests.lua", "rb")); local text = t:read("a"); t:close()
local at = text:find(marker, 1, true)
assert(at, "marker not found")
assert(not text:find(marker, at + 1, true), "marker not unique")
local from = at
if oldStart then
	local o = text:find(oldStart, 1, true)
	assert(o and o < at, "old block not found")
	from = o
end
text = text:sub(1, from - 1) .. block .. text:sub(at)
local o = assert(io.open("src/Shared/Tests/EngineTests.lua", "wb")); o:write(text); o:close()
print("spliced")
