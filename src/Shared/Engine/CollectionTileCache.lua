--[[
	Engine/CollectionTileCache.lua
	Pure helpers for the Collection tab builds (Client/Collection):
	  chunks(n, size)     -> list of { from, to } ranges that cut n tiles into builds of `size` (one chunk per frame)
	  key(parts)          -> a string that changes when anything a tab's tiles show changes; an unchanged key means the tiles on screen
	                         are still right, so a click on the same tab does not tear them down and rebuild them
	  shouldWarm(done, n) -> true once per name: a warm up or a tab preload that already ran or is running is never started twice
	parts = { tab, width, hidden = { rarityId = true }, items = { { id, found } }, equipped, fresh = count, extra }
]]

local M = {}

M.CHUNK = 12 -- tiles built per frame

function M.chunks(n, size)
	size = math.max(1, math.floor(tonumber(size) or M.CHUNK))
	local out = {}
	n = math.max(0, math.floor(tonumber(n) or 0))
	local i = 1
	while i <= n do
		out[#out + 1] = { from = i, to = math.min(n, i + size - 1) }
		i = i + size
	end
	return out
end

function M.key(parts)
	parts = parts or {}
	local hidden = {}
	for id, on in pairs(parts.hidden or {}) do if on then hidden[#hidden + 1] = tostring(id) end end
	table.sort(hidden)
	local items = {}
	for i, it in ipairs(parts.items or {}) do items[i] = tostring(it.id) .. (it.found and "+" or "-") end
	return table.concat({
		tostring(parts.tab), tostring(math.floor(tonumber(parts.width) or 0)), table.concat(hidden, ","),
		tostring(parts.equipped), tostring(parts.fresh or 0), tostring(parts.extra or ""), table.concat(items, ","),
	}, "|")
end

function M.shouldWarm(done, name)
	if done[name] then return false end
	done[name] = true
	return true
end

return M
