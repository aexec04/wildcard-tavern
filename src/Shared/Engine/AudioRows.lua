--[[
	Shared/Engine/AudioRows.lua
	The Volume popup (Client/VolumePanel.lua): one kind line under each of the Music, SFX and Mute rows, and the panel layout (tested).

	AudioRows.LINES              { music, sfx, mute }   each 60 characters or less, plain words
	AudioRows.layout(vpW, vpH)   -> row rects inside the panel (panel pixels), the panel size and the knob touch size
]]
local M = {}

M.LINES = {
	music = "The tavern tunes. Turn them down any time.",
	sfx = "Card clicks, coins and cheers.",
	mute = "Mute silences everything. Reset restores both.",
}

M.TITLE_H = 44
M.SIDE = 20
M.SLIDER_H = 46
M.LINE_H = 18
M.BUTTON_H = 44
M.GAP = 6
M.KNOB_HIT = 44
M.PANEL_W = 380

function M.layout(vpW, vpH)
	local w = math.min(M.PANEL_W, vpW - 16)
	local y = M.TITLE_H
	local function row(h)
		local r = { x = M.SIDE, y = y, w = w - 2 * M.SIDE, h = h }
		y = y + h + M.GAP
		return r
	end
	local music, musicLine = row(M.SLIDER_H), row(M.LINE_H)
	local sfx, sfxLine = row(M.SLIDER_H), row(M.LINE_H)
	local buttons, muteLine = row(M.BUTTON_H), row(M.LINE_H)
	local wanted = y + 10
	return {
		panel = { w = w, h = math.min(wanted, vpH - 16) }, wanted = wanted, contentH = y - M.TITLE_H,
		music = music, musicLine = musicLine, sfx = sfx, sfxLine = sfxLine, buttons = buttons, muteLine = muteLine,
		titleH = M.TITLE_H, knobHit = M.KNOB_HIT,
	}
end

return M
