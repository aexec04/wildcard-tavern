--[[
	lint_stacked_strips.lua
	A fade made of stacked Frames with stepped BackgroundTransparency shows as hard dark bands. Fail when a `for i = 1, N do` loop in
	src/Client (N above 4 or not a literal) sets BackgroundTransparency from its loop variable. Use ONE Frame with a UIGradient
	(Engine/ScrimGradient). A line may opt out with "-- strips: <reason>" (animated pulses that are not stacked).

	Usage: lua tools/lint_stacked_strips.lua   (also run by run_tests_local.lua)
	Returns the number of offenders when loaded with dofile.
]]

local files = {}
local p = io.popen("ls src/Client/*.lua 2>/dev/null")
if p then
	for l in p:lines() do files[#files + 1] = l end
	p:close()
end

local offenders = 0
for _, f in ipairs(files) do
	local lines = {}
	for l in io.lines(f) do lines[#lines + 1] = l end
	for n, l in ipairs(lines) do
		local var, hi = l:match("^%s*for%s+([%a_][%w_]*)%s*=%s*1%s*,%s*([%w_%.#%(%)]+)%s+do")
		if var then
			local limit = tonumber(hi)
			if not limit or limit > 4 then
				local indent = l:match("^(%s*)")
				local graded = false
				for m = n + 1, #lines do
					local b = lines[m]
					if b:match("^" .. indent .. "end") then break end
					if b:find("BackgroundTransparency", 1, true) and b:find("%f[%w_]" .. var .. "%f[^%w_]") and not b:find("-- strips:", 1, true) then
						graded = true
					end
				end
				if graded then
					offenders = offenders + 1
					print(string.format("[lint] %s:%d loop builds stacked graded-transparency Frames; use one UIGradient Frame", f, n))
				end
			end
		end
	end
end

if offenders == 0 then
	print("[lint] no stacked graded-transparency strips")
end
return offenders
