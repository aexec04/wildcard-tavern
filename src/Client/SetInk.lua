--[[
	Client/SetInk.lua
	The equipped Card Set's plate and accent colours for code-drawn frames (score pop-up, Patron seats, Patron Power panel).
	SetInk.get() -> { plate = Color3, accent = Color3, ratio = number } or nil for classic_tavern (classic keeps its own look).
	The numbers come from Engine/ThemeScenes.scoreStyle (accent on plate is 7:1 or more). A Studio Card Sets preview wins over the equipped set.
]]

local M = {}

function M.get()
	local ok, st = pcall(function()
		local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ThemeScenes"))
		local skin = require(script.Parent.HudTheme).skin()
		local previewId = nil
		local okV, view = pcall(function() return require(script.Parent.CosmeticSetsView) end)
		if okV and view and view.previewSetId then previewId = view.previewSetId() end
		return TS.scoreStyle(TS.effectiveSetId(skin and skin.id, previewId))
	end)
	if not (ok and st) then return nil end
	return {
		plate = Color3.fromRGB(st.plate[1], st.plate[2], st.plate[3]),
		accent = Color3.fromRGB(st.accent[1], st.accent[2], st.accent[3]),
		ratio = st.ratio,
	}
end

return M
