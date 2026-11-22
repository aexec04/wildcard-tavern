--[[
	remote_args_audit.lua
	Static check of src/Server/init.server.lua: for every `Rem.X.OnServerEvent:Connect(function(player, a, b)` handler, every
	argument must be checked (type(), typeof(), math.type, tostring, tonumber, PayloadGuard, a Registry lookup or `== true`)
	before it is used. Prints one line per handler that has an argument with no check in its body.

		lua tools/remote_args_audit.lua
]]
local f = assert(io.open((arg[0]:match("(.*)/remote_args_audit%.lua$") or ".") .. "/../src/Server/init.server.lua", "r"))
local lines = {}
for l in f:lines() do lines[#lines + 1] = l end
f:close()

local function audit()
	local bad = {}
	for i, l in ipairs(lines) do
		local name, params = l:match("^%s*Rem%.([%w_]+)%.OnServerEvent:Connect%(function%(player,?%s*([^)]*)%)")
		if name and not name:find("^Debug") then
			local body = {}
			for j = i + 1, #lines do
				if lines[j]:match("^end%)") or lines[j]:match("^\tend%)") then break end
				body[#body + 1] = lines[j]
			end
			local text = table.concat(body, "\n")
			for arg_ in params:gmatch("[%w_]+") do
				local checked = text:find("type%(" .. arg_ .. "%)") or text:find("typeof%(" .. arg_ .. "%)")
					or text:find("tonumber%(" .. arg_ .. "%)") or text:find("tostring%(" .. arg_ .. "%)")
					or text:find("math%.type%(" .. arg_ .. "%)") or text:find("Guard%.[%w]+%(" .. arg_)
					or text:find("[%w%.]+%(" .. arg_ .. "%)") or text:find("[%w%.]+%(" .. arg_ .. ",")
					or text:find(arg_ .. "%s*==") or text:find("==%s*" .. arg_) or text:find("%[" .. arg_ .. "%]")
				if not checked then
					bad[#bad + 1] = string.format("%s (line %d): argument '%s' has no check", name, i, arg_)
				end
			end
		end
	end
	return bad
end

if arg and arg[0] and arg[0]:find("remote_args_audit") then
	local bad = audit()
	for _, b in ipairs(bad) do print(b) end
	print(#bad .. " unchecked arguments")
end
return audit
