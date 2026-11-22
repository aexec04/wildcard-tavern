--[[
	Shared/Engine/SkipPlate.lua
	What the Skip plate on Round Select says before you tap it: the Tag you would get and one kind line, both from the Tags registry.
	Pure and tested. Client/RoundSelect draws it.

	text(tag)         -> rich text, "Skip for <Tag name>" over the Tag's short line (a plain "Skip" when there is no Tag yet)
	needsConfirm(tag) -> true only for a rare Tag (Tags.rare), so a common skip stays one tap
	confirmCopy(tag)  -> the ConfirmCopy.skip options for the dialog
	HEIGHT            44 px plate, INK on FILL keeps SkipPlate.MIN_CONTRAST (7:1)
]]

local Tags = require(script.Parent.Tags)
local ConfirmCopy = require(script.Parent.ConfirmCopy)

local M = {}

M.HEIGHT = 44
M.FILL = { 90, 60, 30 }
M.INK = { 250, 240, 220 }
M.MIN_CONTRAST = 7
M.NAME_SIZE, M.LINE_SIZE = 16, 13
M.MAX_LINE = 40

local function def(tag)
	if type(tag) ~= "table" then return nil end
	return Tags.getById(tag.id) or tag
end

local function escape(s)
	return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function M.line(tag)
	local d = def(tag)
	if not d then return "" end
	local s = d.short
	if type(s) ~= "string" or s == "" then s = tostring(d.description or "") end
	if #s > M.MAX_LINE then s = s:sub(1, M.MAX_LINE - 3) .. "..." end
	return s
end

function M.text(tag)
	local d = def(tag)
	if not d or not d.name then return "Skip" end
	local line = M.line(tag)
	local top = "Skip for " .. escape(d.name)
	if line == "" then return top end
	return top .. '\n<font size="' .. M.LINE_SIZE .. '">' .. escape(line) .. "</font>"
end

function M.needsConfirm(tag)
	local d = def(tag)
	return d ~= nil and d.rare == true
end

function M.confirmCopy(tag)
	local d = def(tag) or {}
	return ConfirmCopy.skip(d.name or "this Tag", M.line(tag))
end

return M
