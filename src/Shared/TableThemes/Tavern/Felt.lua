--[[
	TableThemes/Tavern/Felt.lua
	The playing surface of the Tavern table: which materials the felt, the rail, the table's body and the floor wear,
	the brass studs along the rail and the stitched line on the felt. Names are keys of Materials.lua; sizes are studs.
]]

return {
	surface = "felt",
	body = "body",
	floor = "floor",
	rail = {
		top = "rail",
		inner = "railEdge",
		trim = "brass",
		studs = { material = "brass", spacing = 2.4, size = 0.3 },
	},
	line = { material = "feltLine", inset = 1.0, width = 0.07 },
}
