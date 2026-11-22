import re
p = 'src/Server/init.server.lua'
L = open(p).read().split('\n')
start = 117
end = 229  # slice [117:229] -> lines 118..229
region = L[start:end]
mapping = {}
for ln in region:
    m = re.match(r'local (\w+) = newRemote\("(\w+)"\)', ln)
    if m:
        mapping[m.group(1)] = m.group(2)
    m = re.match(r'local (\w+) = Instance\.new\("RemoteFunction"\)', ln)
    if m:
        mapping[m.group(1)] = None
for ln in region:
    m = re.match(r'(\w+)\.Name = "(\w+)"', ln)
    if m and m.group(1) in mapping:
        mapping[m.group(1)] = m.group(2)
out = []
for ln in region:
    if ln.startswith('local remotes = '):
        out.append('local ReplicatedStorage = game:GetService("ReplicatedStorage")\n\n' + ln)
        continue
    if ln.startswith('local Rem = {}'):
        out.append('local Rem = {} -- every remote, keyed by its remote name')
        continue
    m = re.match(r'local (\w+) = newRemote\(', ln)
    if m:
        out.append(ln.replace('local ' + m.group(1), 'Rem.' + mapping[m.group(1)], 1))
        continue
    out.append(ln)
mod = '\n'.join(out)
for ident, name in mapping.items():
    if ('local %s = Instance.new("RemoteFunction")' % ident) in mod:
        mod = mod.replace('%s.Parent = remotes' % ident, '%s.Parent = remotes\nRem.%s = %s' % (ident, name, ident))
mod = "-- All server RemoteEvents/RemoteFunctions, created once. Split out of init.server.lua to keep its main chunk under Lua's 200 local limit.\n" + mod + '\n\nreturn Rem\n'
open('src/Server/Remotes.lua', 'w').write(mod)
rest = L[:start] + ['local Rem = require(script:WaitForChild("Remotes")) -- all remotes, keyed by remote name (see Remotes.lua)'] + L[end:]
txt = '\n'.join(rest)
for ident, name in mapping.items():
    txt = re.sub(r'\b%s\b' % ident, 'Rem.' + name, txt)
open(p, 'w').write(txt)
print(len(mapping), 'mapped')
