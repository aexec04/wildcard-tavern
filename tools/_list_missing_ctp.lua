-- lists Patrons without a ctp_<id> key: rarity|id|name|description (run: lua tools/_list_missing_ctp.lua), temporary
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
local Art = load(src .. "/Engine/ConceptTPatronArt")
local order = { common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5, mythical = 6 }
local list = {}
for _, it in ipairs(CB.itemsFor("patrons")) do
	if not Art["ctp_" .. it.id] then
		list[#list + 1] = { r = CB.rarityOf(it), id = it.id, name = it.def.name, d = it.def.description }
	end
end
table.sort(list, function(a, b)
	if (order[a.r] or 9) ~= (order[b.r] or 9) then return (order[a.r] or 9) < (order[b.r] or 9) end
	return a.id < b.id
end)
for i, p in ipairs(list) do print(i .. "|" .. p.r .. "|" .. p.id .. "|" .. tostring(p.name) .. "|" .. tostring(p.d)) end
