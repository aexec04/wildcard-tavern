--[[
	Client/ShopTrace.lua
	Studio-only trace of the Counter's Reroll and Haggle path (click, what the client checked, what it sent, what the server
	said back), so "it does nothing" can be answered from the Output window. Silent in a published game.

	ShopTrace.log(format, ...)   prints "[Shop] ..." in Studio, nothing elsewhere; never throws
]]

local RunService = game:GetService("RunService")

local ShopTrace = {}

function ShopTrace.log(format, ...)
	if not RunService:IsStudio() then return end
	local ok, line = pcall(string.format, format, ...)
	print("[Shop] " .. (ok and line or tostring(format)))
end

return ShopTrace
