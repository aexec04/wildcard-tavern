--[[
	lint_sort_order.lua
	Every UIListLayout / UIGridLayout created in src/Client must set SortOrder
	within a few lines. The Roblox default is Name, which silently ignores
	LayoutOrder (the Run Setup sections landed in the wrong order because of it).
	A layout that really wants Name order can opt out with "-- sort: name" on
	the creation line or the lines right after it.

	Usage: lua tools/lint_sort_order.lua   (also run by run_tests_local.lua)
	Returns the number of offenders when loaded with dofile.
]]

local WINDOW = 12

local function listFiles()
	local files = {}
	local p = io.popen('ls src/Client/*.lua 2>/dev/null')
	if not p then
		return files
	end
	for l in p:lines() do
		files[#files + 1] = l
	end
	p:close()
	return files
end

local offenders = {}
for _, f in ipairs(listFiles()) do
	local lines = {}
	for l in io.lines(f) do
		lines[#lines + 1] = l
	end
	for i, l in ipairs(lines) do
		local name = l:match('local%s+([%w_]+)%s*=%s*Instance%.new%("UI[%a]*Layout"%)')
		if name and (l:find('"UIListLayout"') or l:find('"UIGridLayout"')) then
			local ok = false
			for j = i, math.min(i + WINDOW, #lines) do
				if lines[j]:find("SortOrder") or lines[j]:find("sort: name") then
					ok = true
					break
				end
			end
			if not ok then
				offenders[#offenders + 1] = f .. ":" .. i .. " " .. name
			end
		end
	end
end

for _, o in ipairs(offenders) do
	print("[lint] layout without SortOrder: " .. o)
end
if #offenders == 0 then
	print("[lint] all UIList/UIGrid layouts set SortOrder")
end
return #offenders
