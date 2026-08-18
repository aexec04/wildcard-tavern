--[[
	TestRunner.lua
	A tiny, dependency-free test harness. Works both from plain Lua (via
	tools/run_tests_local.lua) and pasted/required inside Roblox Studio --
	it only uses core Lua, nothing Roblox-specific.
]]

local TestRunner = {}

-- tests: array of { name = string, fn = function }
-- Each fn should call TestRunner.expect* and simply error() (or let an
-- expect* call error for it) to signal failure.
function TestRunner.run(tests)
	local passed, failed = 0, 0
	local failures = {}

	for _, t in ipairs(tests) do
		local ok, err = pcall(t.fn)
		if ok then
			passed = passed + 1
			print("  [PASS] " .. t.name)
		else
			failed = failed + 1
			table.insert(failures, { name = t.name, err = err })
			print("  [FAIL] " .. t.name .. " -- " .. tostring(err))
		end
	end

	print(string.format("\n%d passed, %d failed (%d total)", passed, failed, passed + failed))
	return { passed = passed, failed = failed, failures = failures }
end

function TestRunner.expectEqual(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", message or "expectEqual", tostring(expected), tostring(actual)), 3)
	end
end

function TestRunner.expectTrue(value, message)
	if not value then
		error(message or "expected true, got false", 3)
	end
end

function TestRunner.expectFalse(value, message)
	if value then
		error(message or "expected false, got true", 3)
	end
end

return TestRunner
