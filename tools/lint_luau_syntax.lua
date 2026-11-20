--[[
	lint_luau_syntax.lua
	Lua 5.3 runs the tests locally, Luau runs the game. Lua 5.3 syntax that Luau rejects makes a whole
	script fail to load in Studio ("Incomplete statement: expected assignment or a function call"),
	while the local run stays green. This lint fails on `goto` and `::label::` in src (use an if block
	or a helper function instead). It skips comments and string literals on a line.

	Usage: lua tools/lint_luau_syntax.lua   (also run by run_tests_local.lua)
	Returns the number of offenders when loaded with dofile.
]]

local function code(line)
	line = line:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
	return (line:gsub("%-%-.*$", ""))
end

local offenders = 0
local p = io.popen("find src -name '*.lua' 2>/dev/null")
if p then
	for f in p:lines() do
		local n, inBlock = 0, false
		for l in io.lines(f) do
			n = n + 1
			if inBlock then
				if l:find("]]", 1, true) then inBlock = false end
			elseif l:find("%-%-%[=*%[") and not l:find("]]", 1, true) then
				inBlock = true
			else
				local c = code(l)
				if c:find("%f[%w_]goto%s+[%a_]") or c:find("::[%a_][%w_]*::") then
					offenders = offenders + 1
					print(string.format("[lint] %s:%d goto or label is not valid Luau", f, n))
				elseif c:find("<<") or c:find(">>") then
					offenders = offenders + 1
					print(string.format("[lint] %s:%d bit shift operator is not valid Luau (use bit32 or arithmetic)", f, n))
				end
			end
		end
	end
	p:close()
end

if offenders == 0 then
	print("[lint] no goto, labels or bit shifts in src (Luau safe)")
end
return offenders
