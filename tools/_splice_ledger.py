p = "src/Client/LedgerBook.lua"
s = open(p).read()
block = open("art-wip/_checks/ledger_turn_block.lua").read()
block = block.replace("\tfunction crossfade(state)", "\tcrossfade = function(state)")
block = "\tlocal crossfade -- set below (calm mode)\n" + block

# 1. the old flip and calm crossfade become the new turn block
a = s.index("\t-- A real page flip:")
b = s.index("\tlocal function countUp()")
s = s[:a] + block + s[b:]

# 2. the old go() and the tab loop become tabs that turn one sheet
a = s.index("\tlocal function go(i, animate)")
b = s.index("\tlocal api = {}")
tabs = '''\tfor i, name in ipairs(Pages.PAGES) do
\t\tlocal tab = Instance.new("TextButton")
\t\ttab.Name = "Tab_" .. i
\t\ttab.Font = Enum.Font.GothamBold
\t\ttab.TextSize = 14
\t\ttab.TextWrapped = true
\t\ttab.Text = name
\t\ttab.BorderSizePixel = 0
\t\ttab.AutoButtonColor = true
\t\ttab.ZIndex = Z + 3
\t\ttab.Parent = book
\t\tdeps.roundCorner(tab, 6)
\t\ttab.MouseButton1Click:Connect(function()
\t\t\tif i == pageIndex then return end
\t\t\tdeps.playClickSfx()
\t\t\tquickTurn(i) -- one sheet to that section, never a whole-book motion
\t\tend)
\t\ttabButtons[i] = tab
\tend

\t-- the page content is sized from the book's real pixels: repaint once the book has been laid out or resized
\tdo
\t\tlocal repaintToken = 0
\t\tbook:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
\t\t\trepaintToken = repaintToken + 1
\t\t\tlocal mine = repaintToken
\t\t\ttask.delay(0.15, function()
\t\t\t\tif mine ~= repaintToken or turn or drag or not showing() then return end
\t\t\t\tlocal state = latest()
\t\t\t\tif state and state.runStats then paint(state) end
\t\t\tend)
\t\tend)
\tend
'''
s = s[:a] + tabs + s[b:]

# 3. grab hotspots on the outer edge and bottom corner of each page, created before the page frames
a = s.index("\tlocal function pageFrame(name, side)")
hot = '''\t-- Drag-to-turn hotspots: the outer edge strip (12 percent of the page width, full height) and the bottom corner of each page.
\t-- They sit under the page content, so rows and buttons on the page keep their clicks; Active ones above always win.
\tlocal onGrab -- set below
\tfor _, side in ipairs({ "left", "right" }) do
\t\tlocal box = Layout.pageBox(side)
\t\tfor kind, r in pairs(Layout.hotspots(side)) do
\t\t\tlocal hit = Instance.new("TextButton")
\t\t\thit.Name = "Grab_" .. side .. "_" .. kind
\t\t\thit.Text = ""
\t\t\thit.AutoButtonColor = false
\t\t\thit.BackgroundTransparency = 1
\t\t\thit.BorderSizePixel = 0
\t\t\thit.Position = UDim2.fromScale(box.x + r.x * box.w, box.y + r.y * box.h)
\t\t\thit.Size = UDim2.fromScale(r.w * box.w, r.h * box.h)
\t\t\thit.ZIndex = Z + 1
\t\t\thit.Parent = book
\t\t\thit.InputBegan:Connect(function(input)
\t\t\t\tif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
\t\t\t\t\tif onGrab then onGrab(side, input) end
\t\t\t\tend
\t\t\tend)
\t\tend
\tend

'''
s = s[:a] + hot + s[a:]

# 4. requires
s = s.replace('local TweenService = game:GetService("TweenService")\n',
              'local TweenService = game:GetService("TweenService")\nlocal UserInputService = game:GetService("UserInputService")\n', 1)
s = s.replace('\tlocal Layout = require(Engine:WaitForChild("LedgerLayout"))\n',
              '\tlocal Layout = require(Engine:WaitForChild("LedgerLayout"))\n\tlocal PopupRules = require(Engine:WaitForChild("PopupRules"))\n', 1)

# 5. scroll bar: thin, low contrast brown, only when the page really scrolls (the canvas is automatic)
s = s.replace("scroll.ScrollBarThickness = 6", "scroll.ScrollBarThickness = 4")
s = s.replace("scroll.ScrollBarImageColor3 = BRASS", "scroll.ScrollBarImageColor3 = Color3.fromRGB(112, 80, 56)")
s = s.replace("scroll.ScrollBarImageTransparency = 0\n", "scroll.ScrollBarImageTransparency = 0.5\n")
open(p, "w").write(s)
print("ok")
