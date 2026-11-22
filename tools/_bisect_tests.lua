local f = io.open("src/Shared/Tests/EngineTests.lua"):read("a")
local lines = {}
for l in (f .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
local starts = {}
for i, l in ipairs(lines) do
	if l:match("^table%.insert%(tests") then starts[#starts + 1] = i end
end
for k, s in ipairs(starts) do
	local e = (starts[k + 1] or #lines + 1) - 1
	local ok, err = load(table.concat(lines, "\n", s, e), "t")
	if not ok then print(s, e, err) end
end
