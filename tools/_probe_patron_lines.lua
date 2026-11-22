package.path = "src/Shared/Engine/?.lua;" .. package.path
local P = require("Patrons")
local seen = {}
for _, d in ipairs(P.Definitions) do
	local s = d.description or ""
	local flag = ""
	if #s == 0 or #s >= 70 then flag = flag .. " LEN" end
	if seen[s] then flag = flag .. " DUP" end
	seen[s] = true
	if flag ~= "" or #s > 55 then print(d.id, #s, s, flag) end
end
print(#P.Definitions)
