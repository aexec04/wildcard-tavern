--[[
	ToastPlacement.lua
	Where the message strip ("Sharp Eyes: ...", "X joins your table") sits so it never covers a screen title.
	Table screens: a small toast centred on the felt at about 35 percent of the height, above the hand row, gone after 2 s. Round Select, Choice and Shop: just below the title block.
	Pure Lua; Client/MessageBanner.lua applies the result.
]]

local ToastPlacement = {}

ToastPlacement.TITLE_BLOCK = 96 -- Round Select / Choice / Shop title plus subtitle end by this y
ToastPlacement.TRAY_CLEARANCE = 270 -- hand tray, action buttons and a margin, measured from the screen foot
ToastPlacement.HEIGHT = 34
ToastPlacement.TABLE_Y = 0.35 -- table toast: a fraction of the screen height (about y 380 at 1080), on the felt above the hand
ToastPlacement.TABLE_W = 360 -- a small parchment toast, never a wide bar across the cards
ToastPlacement.TABLE_SECONDS = 2
ToastPlacement.SECONDS = 3

-- screen: "table" | "roundSelect" | "choice" | "shop". Returns { anchor = "top" | "bottom", y = offset }.
function ToastPlacement.plan(screen)
	if screen == "roundSelect" or screen == "choice" or screen == "shop" then
		return { anchor = "top", y = ToastPlacement.TITLE_BLOCK }
	end
	return { anchor = "top", yScale = ToastPlacement.TABLE_Y, y = 0, width = ToastPlacement.TABLE_W, centred = true, seconds = ToastPlacement.TABLE_SECONDS }
end

-- Rect of the table toast for a screen size and sidebar width: centred on the area right of the sidebar, never over the hand row.
function ToastPlacement.tableRect(screenW, screenH, sidebarW, handTop)
	local w = math.min(ToastPlacement.TABLE_W, math.max(160, screenW - sidebarW - 40))
	local x = sidebarW + (screenW - sidebarW - w) / 2
	local y = math.floor(screenH * ToastPlacement.TABLE_Y)
	if handTop and y + 44 > handTop - 8 then y = math.max(0, handTop - 8 - 44) end
	return x, y, w, 44
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
