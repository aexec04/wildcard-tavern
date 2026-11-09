-- Guards Lua's 200-locals-per-function limit on the two hub scripts by counting
-- top level `local` declarations (column 0 only). Run by tools/run_tests_local.lua.
-- Server must stay at or under 150. The client hub is already above that, so its
-- limit is a ratchet: lower CLIENT_LIMIT whenever locals are moved out, never raise it.
local LIMITS = {
	{ path = "src/Server/init.server.lua", limit = 150 },
	{ path = "src/Client/init.client.lua", limit = 131 },
}

local function countLocals(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local n = 0
	for line in f:lines() do
		if line:match("^local%s+function%s") then
			n = n + 1
		else
			local names = line:match("^local%s+([%w_,%s]-)%s*=") or line:match("^local%s+([%w_,%s]+)%s*$")
			if names then
				for _ in names:gmatch("[%w_]+") do n = n + 1 end
			end
		end
	end
	f:close()
	return n
end

local fails = 0
for _, entry in ipairs(LIMITS) do
	local n = countLocals(entry.path)
	if n == nil then
		print("[locals] skipped (cannot open) " .. entry.path)
	else
		print(string.format("[locals] %s: %d of %d allowed (Lua hard limit 200)", entry.path, n, entry.limit))
		if n > entry.limit then
			print("FAILED: too many top level locals in " .. entry.path)
			fails = fails + 1
		end
	end
end
return fails
