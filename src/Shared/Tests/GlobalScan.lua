--[[
	Shared/Tests/GlobalScan.lua
	Test helper: which global names a Lua file reads or writes, taken from the bytecode listing of luac (the compiler's own scoping,
	so a local, an upvalue or a parameter is never reported). A global that is not a real one is a nil global waiting to be called
	(Collection.lua called furnCols(), which was never defined, and the Collection would not open) or an accidental global (a local
	someone forgot to declare). Local runner only: it needs io.popen, os.tmpname and the luac that ships with Lua; everything here
	reports "not available" instead of failing when they are missing, and Studio has none of them.

	GlobalScan.available() -> bool
	GlobalScan.listLua(dir) -> { "dir/File.lua", ... }
	GlobalScan.scan(path) -> { { name, op = "GET" | "SET", line }, ... } | nil, reason
	    Luau's "x += y" lines are rewritten first (FakeGui.plainLua). A file that uses other Luau-only syntax cannot be compiled by
	    plain Lua: scan returns nil and the reason, so a caller can tell "skipped" from "clean".
	GlobalScan.KNOWN -> set of names that are real globals in Lua or Roblox, plus "_" (the project's "unused value" idiom: _ = x)
]]

local FakeGui = require(script.Parent.FakeGui)

local GlobalScan = {}

GlobalScan.KNOWN = {}
for name in ([[
assert collectgarbage dofile error getmetatable ipairs load loadfile next pairs pcall print rawequal rawget rawlen rawset require
select setmetatable tonumber tostring type xpcall _G _VERSION _ string table math os io debug coroutine utf8 bit32 unpack
game workspace script shared plugin Instance Enum UDim UDim2 Vector2 Vector3 Vector2int16 Vector3int16 Color3 CFrame Rect Region3
Ray Random Font ColorSequence ColorSequenceKeypoint NumberSequence NumberSequenceKeypoint NumberRange TweenInfo BrickColor
DateTime PhysicalProperties Faces Axes OverlapParams RaycastParams SharedTable task wait delay spawn tick time warn typeof
elapsedTime settings UserSettings stats version
]]):gmatch("%S+") do
	GlobalScan.KNOWN[name] = true
end

function GlobalScan.available()
	if not (io and io.popen and os.tmpname) then return false end
	local ok, pipe = pcall(io.popen, "luac -v 2>&1")
	if not ok or not pipe then return false end
	local out = pipe:read("*a") or ""
	pipe:close()
	return out:find("^Lua") ~= nil
end

function GlobalScan.listLua(dir)
	local files = {}
	local ok, pipe = pcall(io.popen, 'ls "' .. dir .. '" 2>/dev/null')
	if not ok or not pipe then return files end
	for name in pipe:lines() do
		if name:match("%.lua$") then files[#files + 1] = dir .. "/" .. name end
	end
	pipe:close()
	table.sort(files)
	return files
end

function GlobalScan.scan(path)
	local f = io.open(path, "r")
	if not f then return nil, "cannot open " .. path end
	local src = f:read("*a")
	f:close()
	local tmp = os.tmpname()
	local w = io.open(tmp, "w")
	if not w then return nil, "cannot write a temp file" end
	w:write(FakeGui.plainLua(src))
	w:close()
	local pipe = io.popen('luac -l -p "' .. tmp .. '" 2>&1')
	local out = pipe and pipe:read("*a") or ""
	if pipe then pipe:close() end
	os.remove(tmp)
	if not out:find("main <", 1, true) then return nil, out:match("[^\n]+") or "no listing" end
	local found = {}
	for line in out:gmatch("[^\n]+") do
		-- e.g.  "  12  [886]  GETTABUP   3 0 14  ; _ENV "furnCols""  (a read) or SETTABUP (a write)
		local op, name = line:match("(%u+)%s.-;%s*_ENV%s+\"([^\"]+)\"")
		if name then
			found[#found + 1] = { name = name, op = op == "SETTABUP" and "SET" or "GET", line = tonumber(line:match("%[(%d+)%]")) }
		end
	end
	return found
end

return GlobalScan
