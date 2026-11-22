import re

p = "src/Shared/Engine/Patrons.lua"
s = open(p).read()
s = re.sub(r', artStandIn = "[a-z_]+"', '', s)
s = s.replace("\t-- Roster additions. artStandIn: borrows another Patron's painted portrait until its own art lands (see Patrons.artKey).\n", "\t-- Roster additions.\n")
a = s.index("-- The art key to draw for a Patron")
b = s.index("function Patrons.getById")
s = s[:a] + s[b:]
open(p, "w").write(s)

p = "src/Shared/Tests/EngineTests.lua"
s = open(p).read()
s = s.replace('''		expectTrue(Patrons.artKey(p.id) ~= p.id and art[Patrons.artKey(p.id)], p.id .. " borrows a portrait that exists")
	end
	expectEqual(Patrons.artKey("twin_spoons"), "twin_spoons", "a Patron with its own art keeps its id")
''', '''		expectTrue(art[p.id] and art[p.id] ~= "rbxassetid://0", p.id .. " has its own portrait")
		expectTrue(cards["ctp_" .. p.id], p.id .. " has its own cut card")
		expectTrue(crops[p.id], p.id .. " has a card crop")
	end
''')
s = s.replace('''	local art = require(script.Parent.Parent.Engine.PatronArt)
	for _, p in ipairs({ lone, even, odd, good }) do''', '''	local art = require(script.Parent.Parent.Engine.PatronArt)
	local cards = require(script.Parent.Parent.Engine.ConceptTPatronArt)
	local crops = require(script.Parent.Parent.Engine.PatronCardCrop)
	for _, p in ipairs({ lone, even, odd, good }) do''')
s = s.replace("score as written, read short and safe, and borrow a real portrait", "score as written, read short and safe, and have their own art")
open(p, "w").write(s)

p = "claude/STATUS.md"
s = open(p).read()
s = s.replace("**Four new Patrons (Nov 22, art pending):**", "**Four new Patrons (Nov 22):**")
s = s.replace(" They borrow a portrait through `artStandIn` in the registry (`Patrons.artKey`); remove the field when their own art lands. Roster is 85 Patrons.", " Each has its own portrait and cut card. Roster is 85 Patrons.")
open(p, "w").write(s)
