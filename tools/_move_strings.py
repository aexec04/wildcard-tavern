import re
p = 'src/Client/Settings.lua'
s = open(p).read()
src = open('src/Shared/Engine/Strings.lua').read()
pairs = re.findall(r'\["([^"]+)"\] = "([^"]+)"', src)
assert len(pairs) == 16
for key, text in pairs:
    q = '"' + text + '"'
    assert s.count(q) == 1, (text, s.count(q))
    s = s.replace(q, 'S("' + key + '")')
anchor = 'local ON = Color3.fromRGB(70, 110, 60)\n'
assert anchor in s
s = s.replace(anchor, anchor + 'local S = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Strings")).get -- player facing text by id\n', 1)
open(p, 'w').write(s)
print("ok", len(pairs))
