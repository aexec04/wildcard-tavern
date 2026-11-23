--[[
	Engine/Layers.lua
	The shared ZIndex bands (the ScreenGui uses ZIndexBehavior Global, so a bigger number draws on top of a smaller one, whatever the parent).
	Pages and panels (Store, Collection, Card Sets, Season, Settings) live below PAGE_TOP; every purchase or quit confirmation sits in the
	confirm band so it always draws above the page it was opened from. Pure numbers, no Roblox calls.
]]
local M = {}

M.PAGE_TOP = 1000 -- nothing a page draws goes above this
M.tooltip = 100
M.confirm = 6000 -- ConfirmDialog, QuitConfirm, ReplayConfirm: backdrop at confirm, panel at confirm + 1, text and plates at confirm + 2

return M
