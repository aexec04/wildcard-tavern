--[[
	Client/LazyPanel.lua
	Builds an account panel on its first open instead of at startup (the Menu carried every panel's instances). wrap(id, init)
	returns a function with the panel's own signature: it registers the opener under `id` at once (PanelTabs and OverlayManager.open
	work as before), and the first click on the panel's open button, or the first OverlayManager.open(id), runs the real init with
	a stand-in open button, then calls the open handler the panel registered. A second open never rebuilds. The built panel
	re-registers its own opener and close function, which replace the stand-in.
	  wrap(id, init, buttons, alsoIds)
	    init(deps)  the panel's constructor
	    buttons     the deps field (or a list of fields) holding the open button(s); default "openButton". Each gets the stand-in while
	                building, and a click on the real one builds first.
	    alsoIds     other OverlayManager ids that the built init registers (a group such as the Collection registers several): until
	                built, opening one of them builds the group and then opens that id for real.
]]

local OverlayManager = require(script.Parent.OverlayManager)

local LazyPanel = {}

function LazyPanel.wrap(id, init, buttons, alsoIds)
	local keys = type(buttons) == "table" and buttons or { buttons or "openButton" }
	return function(deps)
		local built, handler, api = false, nil, nil
		local standIn = { MouseButton1Click = { Connect = function(_, fn) handler = fn end } }
		local over = {}
		for _, key in ipairs(keys) do
			if deps[key] ~= nil then over[key] = standIn end
		end
		local proxy = setmetatable(over, { __index = deps })
		local function build()
			if built then return end
			built = true
			api = init(proxy)
		end
		local function open()
			build()
			if handler then handler() end
		end
		OverlayManager.registerOpener(id, open)
		for key in pairs(over) do
			deps[key].MouseButton1Click:Connect(open)
		end
		for _, other in ipairs(alsoIds or {}) do
			local busy = false
			OverlayManager.registerOpener(other, function()
				if busy then return end -- the group did not register this id itself: do nothing rather than loop
				busy = true
				build()
				pcall(OverlayManager.open, other)
				busy = false
			end)
		end
		return { build = build, id = id, api = function() return api end }
	end
end

return LazyPanel
