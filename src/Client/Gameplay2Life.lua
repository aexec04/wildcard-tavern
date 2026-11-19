--[[
	Client/Gameplay2Life.lua
	Ambient life on the Gameplay v2 table: candle flicker, lantern and fireplace breathing and a few dust motes over the painted
	table scene (table_play, or table_boss on a Boss round). The lights are Engine/RoomLights spots (rooms table_play and
	table_boss, at most 12 animated objects each) driven by the one shared FxLoop. Calm mode and Reduce motion keep static glows and
	no motes (Client/RoomLights). A scene's lights are built the first time that scene shows.

	attach(layer, isActive) -> { scene(key), place(w, h), destroy() }
	  key = "table_play" or "table_boss"; place gets the layer size (the scene is cover-cropped at 3:2, like the picture)
	coverRect(w, h) -> the picture's rect inside a w x h layer
]]

local M = {}

function M.coverRect(w, h)
	local pw = math.max(w, h * 1.5)
	local ph = pw / 1.5
	return { x = (w - pw) / 2, y = (h - ph) / 2, w = pw, h = ph }
end

function M.attach(layer, isActive)
	local self = {}
	local lights, current, size = {}, "table_play", nil

	local function build(key)
		if not lights[key] then
			lights[key] = require(script.Parent.RoomLights).attach(layer, {
				room = key, zIndex = 2, visible = function() return current == key and isActive() end,
			})
		end
		return lights[key]
	end

	local function refresh()
		for key, l in pairs(lights) do
			l.place(size and key == current and M.coverRect(size.w, size.h) or nil)
		end
	end

	function self.scene(key)
		key = key == "table_boss" and "table_boss" or "table_play"
		if key == current and lights[key] then return end
		current = key
		build(key)
		refresh()
	end

	function self.place(w, h)
		size = { w = w, h = h }
		build(current)
		refresh()
	end

	function self.destroy()
		for _, l in pairs(lights) do l.destroy() end
		lights = {}
	end
	return self
end

return M
