--[[
	Client/LazyPanel.lua
	Builds an account panel on its first open instead of at startup (the Menu carried every panel's instances). wrap(id, init)
	returns a function with the panel's own signature: it registers the opener under `id` at once (PanelTabs and OverlayManager.open
	work as before), and the first click on the panel's open button, or the first OverlayManager.open(id), runs the real init with
	a stand-in open button, then calls the open handler the panel registered. A second open never rebuilds. The built panel
	re-registers its own opener and close function, which replace the stand-in.
	  wrap(id, init)  init(deps) is the panel's constructor (deps.openButton is the button that opens it)
]]

local OverlayManager = require(script.Parent.OverlayManager)

local LazyPanel = {}

function LazyPanel.wrap(id, init)
	return function(deps)
		local built, handler = false, nil
		local standIn = { MouseButton1Click = { Connect = function(_, fn) handler = fn end } }
		local proxy = setmetatable({ openButton = standIn }, { __index = deps })
		local function build()
			if built then return end
			built = true
			init(proxy)
		end
		local function open()
			build()
			if handler then handler() end
		end
		OverlayManager.registerOpener(id, open)
		deps.openButton.MouseButton1Click:Connect(open)
		return { build = build, id = id }
	end
end

return LazyPanel
