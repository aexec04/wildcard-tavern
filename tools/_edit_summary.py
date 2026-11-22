def sub(path, a, b):
    s = open(path, encoding='utf-8').read()
    assert a in s, (path, a)
    open(path, 'w', encoding='utf-8').write(s.replace(a, b, 1))

sub('src/Shared/Engine/TavernStyle.lua', '\torn_btn_dark = {', '\torn_target = { art = "pk_w_target", full = true, src = { 1470, 348 }, inset = { l = 200, t = 130, r = 200, b = 130 } }, -- the table Target plate cut as a nine-slice: all four corners alike, nothing hangs outside\n\torn_btn_dark = {')
sub('src/Shared/Engine/ShopPaintRules.lua', 'return "orn_score"', 'return "orn_target"')
sub('src/Client/ShopSummaryPlate.lua', '"orn_score"', '"orn_target"')
T = 'src/Shared/Tests/EngineTests.lua'
sub(T, 'painted(plate, "orn_score")', 'painted(plate, "orn_target")')
sub(T, 'expectEqual(PR.pieceFor("summary"), "orn_score", "summary plate is the ornate score frame")', 'expectEqual(PR.pieceFor("summary"), "orn_target", "summary plate is the symmetric ornate Target frame")\n\texpectEqual(PR.TAB_Z, 8, "tab pictures sit above the Counter dim layer (Z 5)")\n\tlocal sl = require(script.Parent.Parent.Engine.TavernStyle).paintedSlice("orn_target", 300, 124)\n\texpectTrue(sl and sl.left == 200 and sl.right == 1470 - 200 and sl.top == 130 and sl.bottom == 348 - 130, "summary slice keeps all four corners alike")\n\texpectTrue(sl.scale * 200 * 2 <= 300 * 0.9 + 1e-9, "both corner columns fit inside the 300 px summary plate")')
sub('src/Shared/Engine/ShopPaintRules.lua', 'function M.tabSlot', 'M.TAB_Z = 8 -- a tab and its picture (one below) must clear the Counter dim and plate layers at Z 5\n\nfunction M.tabSlot')
sub('src/Client/ShopPaint.lua', '\t\tb.Size = UDim2.new(s.ws, s.wo, 1, 0)\n', '\t\tb.Size = UDim2.new(s.ws, s.wo, 1, 0)\n\t\tif b.ZIndex < Rules.TAB_Z then b.ZIndex = Rules.TAB_Z end\n')
sub(T, '"orn_square", "orn_score", "orn_btn_dark"', '"orn_square", "orn_score", "orn_target", "orn_btn_dark"')
