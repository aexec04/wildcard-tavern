-- probe: Patron ids by rarity (temporary, delete after use)
local src = "src/Shared"
local cache = {}
local function proxy(path)
	return setmetatable({ __path = path }, {
		__index = function(_, key)
			if key == "WaitForChild" then return function(self, n) return self[n] end end
			if key == "Parent" then return proxy(path:match("(.*)/[^/]+$") or ".") end
			return proxy(path .. "/" .. key)
		end,
	})
end
local function load(path)
	if cache[path] then return cache[path] end
	local env = setmetatable({ script = proxy(path) }, { __index = _G })
	env.require = function(t) return load(t.__path) end
	local chunk = assert(loadfile(path .. ".lua", "t", env))
	cache[path] = chunk()
	return cache[path]
end
Color3 = Color3 or { fromRGB = function(r, g, b) return { r = r, g = g, b = b } end }
local CB = load(src .. "/Engine/CollectionBook")
local by = {}
for _, it in ipairs(CB.itemsFor("patrons")) do
	local r = CB.rarityOf(it)
	by[r] = by[r] or {}
	table.insert(by[r], it.id .. "|" .. tostring(it.def.name))
end
for r, l in pairs(by) do print(r, #l); print("  " .. table.concat(l, "; ")) end
