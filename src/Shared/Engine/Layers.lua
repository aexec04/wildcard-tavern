--[[
	Shared/Engine/Layers.lua
	The one place that decides how high anything draws. Every Client file takes its ZIndex from here as a band base plus a small
	offset (`Layers.confirm + 2`), never a bare number of 100 or more. A test fails with the file and line if one slips in.

	Bands, lowest to highest:
	  table      1 to 99      cards, plates, the table scene
	  effect     100 to 999   table effects, banners, tooltips, hints, celebration, previews
	  gear       1000         the gear menu and quick icons
	  screen     2000 to 2999 screens and pages (offset 0 to 999)
	  popup      5000         popups and panels over a screen
	  confirm    6000         "Are you sure?" plates, always clickable
	  toast      7000         toasts, the last thing drawn

	Layers.bandOf(z)        "table" | "effect" | "gear" | "screen" | "popup" | "confirm" | "toast"
	Layers.isAtLeast(z, band)  true when z sits in `band` or any band above it
	Layers.ORDER            band names, lowest first
]]

local Layers = {}

Layers.table = 1
Layers.effect = 100
Layers.gear = 1000
Layers.screen = 2000
Layers.popup = 5000
Layers.confirm = 6000
Layers.toast = 7000

Layers.TABLE_MAX = 99
Layers.EFFECT_MAX = 999

Layers.ORDER = { "table", "effect", "gear", "screen", "popup", "confirm", "toast" }

-- first ZIndex of each band; a band runs until the next one starts
local STARTS = { table = 1, effect = 100, gear = 1000, screen = 2000, popup = 5000, confirm = 6000, toast = 7000 }

function Layers.bandOf(z)
	if type(z) ~= "number" or z < 1 then return nil end
	local found
	for _, name in ipairs(Layers.ORDER) do
		if z >= STARTS[name] then found = name end
	end
	return found
end

local RANK = {}
for i, name in ipairs(Layers.ORDER) do RANK[name] = i end

function Layers.isAtLeast(z, band)
	local b = Layers.bandOf(z)
	return b ~= nil and RANK[band] ~= nil and RANK[b] >= RANK[band]
end

return Layers
