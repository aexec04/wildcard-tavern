--[[
	lint_shadow_calls.lua
	A `local function X` and a later `local X = ...` in the same Tavern Map file make calls to X hit the new value ("attempt to call a
	table value"). Fail when a map module declares both. Rename the data local.

	Usage: lua tools/lint_shadow_calls.lua   (also run by run_tests_local.lua)
	Returns the number of offenders when loaded with dofile.
]]

local files = {}
local p = io.popen("ls src/Client/JourneyMap*.lua src/Client/Map*.lua src/Client/Journey.lua 2>/dev/null")
if p then
	for l in p:lines() do files[#files + 1] = l end
	p:close()
end

local offenders = 0
for _, f in ipairs(files) do
	local funcs, lines = {}, {}
	for l in io.lines(f) do
		lines[#lines + 1] = l
		local name = l:match("^%s*local%s+function%s+([%a_][%w_]*)")
		if name then funcs[name] = true end
	end
	for n, l in ipairs(lines) do
		local list = l:match("^%s*local%s+([%a_][%w_,%s]*)=") or l:match("^%s*local%s+([%a_][%w_,%s]*)$")
		if list and not l:match("^%s*local%s+function") then
			for name in list:gmatch("[%a_][%w_]*") do
				if funcs[name] then
					offenders = offenders + 1
					print(string.format("[lint] %s:%d local '%s' shadows a local function of the same name", f, n, name))
				end
			end
		end
	end
end

if offenders == 0 then print("[lint] no map local shadows a local function") end
return offenders
