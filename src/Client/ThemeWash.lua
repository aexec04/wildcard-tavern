--[[
	Client/ThemeWash.lua
	Dresses one screen backdrop in the equipped Card Set (Engine/ThemeScenes): a tint overlay, a frost vignette for cold sets and the
	set's ambient particles, drawn by Client/BackdropStyles as a child frame of the host. Nothing is resized or moved, so layouts and hit
	targets are identical for every set. Follows equip, Preview start and Preview stop live; Calm mode ("Reduce screen shake") keeps the
	static tint and drops the moving particles (BackdropStyles). A failure leaves the plain backdrop.

	ThemeWash.attach(host, slot) -> { setId(), refresh() }    slot is a ThemeScenes slot ("menuBackdrop", "shopBackdrop", "mapBackdrop", ...)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local ThemeScenes = require(Engine:WaitForChild("ThemeScenes"))

local ThemeWash = {}

function ThemeWash.attach(host, slot)
	local out = { current = ThemeScenes.DEFAULT }
	local ok, controller = pcall(function()
		return require(script.Parent.BackdropStyles).attach(host, { defaultTint = host:IsA("ImageLabel") and host.ImageColor3 or nil })
	end)
	if not ok then return out end
	local HudTheme = require(script.Parent.HudTheme)
	function out.refresh()
		if host.Parent == nil then return end -- a screen rebuilt per show (Victory): the old host is gone
		local skin = HudTheme.skin()
		local t = ThemeScenes.of(skin and skin.id)
		out.current = t.setId
		pcall(controller.setStyle, ThemeScenes.washStyle(t.setId, slot))
		if game:GetService("RunService"):IsStudio() then
			print(string.format("[Theme] %s set=%s art=%s wash=%s", tostring(slot), t.setId, tostring(t.art[slot]), tostring(ThemeScenes.washed(t.setId, slot))))
		end
	end
	function out.setId() return out.current end
	HudTheme.onSkin(function() out.refresh() end)
	out.refresh()
	return out
end

return ThemeWash
