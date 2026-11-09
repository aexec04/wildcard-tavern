--[[
	lint_text_size.lua
	Player-facing text in src/Client must be at least 14px (phones). A line may opt out with
	"-- small: <reason>" (decorative glyphs, Studio-only tools, permanently hidden UI).

	Usage: lua tools/lint_text_size.lua   (also run by run_tests_local.lua)
	Returns the number of offenders when loaded with dofile.
]]

local MIN = 14

local files = {}
local p = io.popen("ls src/Client/*.lua 2>/dev/null")
if p then
	for l in p:lines() do
		files[#files + 1] = l
	end
	p:close()
end

local offenders = 0
for _, f in ipairs(files) do
	local n = 0
	for l in io.lines(f) do
		n = n + 1
		local size = l:match("TextSize%s*=%s*(%d+)")
		if size and tonumber(size) < MIN and not l:find("-- small:", 1, true) then
			offenders = offenders + 1
			print(string.format("[lint] %s:%d TextSize %s is under %d", f, n, size, MIN))
		end
	end
end

if offenders == 0 then
	print("[lint] all TextSize values are 14 or more")
end
return offenders
