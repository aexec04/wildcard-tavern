--[[
	ToastPlacement.lua
	Where the message strip ("Sharp Eyes: ...", "X joins your table") sits so it never covers a screen title.
	Table screens: bottom centre, above the hand tray. Round Select, Choice and Shop: just below the title block.
	Pure Lua; Client/MessageBanner.lua applies the result.
]]

local ToastPlacement = {}

ToastPlacement.TITLE_BLOCK = 96 -- Round Select / Choice / Shop title plus subtitle end by this y
ToastPlacement.TRAY_CLEARANCE = 270 -- hand tray, action buttons and a margin, measured from the screen foot
ToastPlacement.HEIGHT = 34

-- screen: "table" | "roundSelect" | "choice" | "shop". Returns { anchor = "top" | "bottom", y = offset }.
function ToastPlacement.plan(screen)
	if screen == "roundSelect" or screen == "choice" or screen == "shop" then
		return { anchor = "top", y = ToastPlacement.TITLE_BLOCK }
	end
	return { anchor = "bottom", y = -ToastPlacement.TRAY_CLEARANCE }
end

-- Which placement screen the render state is on.
function ToastPlacement.screenOf(state)
	if type(state) ~= "table" then
		return "table"
	end
	if state.choice then
		return "choice"
	end
	if state.phase == "roundSelect" or state.phase == "shop" then
		return state.phase
	end
	return "table"
end

return ToastPlacement
