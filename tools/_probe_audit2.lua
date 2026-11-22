local src = "src/Shared"
local cache = {}
local function proxy(path)
	return setmetatable({ __path = path }, { __index = function(_, key)
		if key == "WaitForChild" then return function(self, n) return self[n] end end
		if key == "Parent" then return proxy(path:match("(.*)/[^/]+$") or ".") end
		return proxy(path .. "/" .. key) end })
end
local function load(path)
	if cache[path] then return cache[path] end
	local env = setmetatable({ script = proxy(path) }, { __index = _G })
	env.require = function(t) return load(t.__path) end
	cache[path] = assert(loadfile(path .. ".lua", "t", env))()
	return cache[path]
end
Color3 = Color3 or { fromRGB = function(r, g, b) return { r = r, g = g, b = b } end }
local A = load(src .. "/Engine/Gameplay2Audit")
for _, s in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 1024, 600 }, { 800, 400 }, { 390, 844 }, { 844, 390 }, { 640, 360 } }) do
	local lines = A.report(s[1], s[2])
	for _, l in ipairs(lines) do if not l:find("^  %a+ +%d") then print(l) end end
end
