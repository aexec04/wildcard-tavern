--[[
	Client/MenuTitleHider.lua
	Hides the dark main-menu title, shadow and ribbon while a menu overlay
	(Run Setup, Daily, Weekly, Seed, Settings, Volume) is open, because they
	bleed through above the panel. How to Play does the same inline.

	MenuTitleHider.bind(screenGui, backdrop)
]]
local NAMES = { "MenuTitle", "MenuTitleShadow", "MenuRibbon" }

local MenuTitleHider = {}

function MenuTitleHider.bind(screenGui, backdrop)
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		local menuRoot = screenGui:FindFirstChild("MenuRoot", true)
		if not menuRoot then
			return
		end
		for _, n in ipairs(NAMES) do
			local o = menuRoot:FindFirstChild(n)
			if o then
				o.Visible = not backdrop.Visible
			end
		end
	end)
end

return MenuTitleHider
