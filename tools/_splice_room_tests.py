p = 'src/Shared/Tests/EngineTests.lua'
s = open(p).read()
a = s.index('table.insert(tests, { name = "MenuRoomLayout: every action is on a prop')
b = s.index('table.insert(tests, { name = "HandLedger: every hand once weakest first')
s = s[:a] + open('tools/_tmp_room_tests.lua.txt').read() + s[b:]
open(p, 'w').write(s)
