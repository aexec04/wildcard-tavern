-- News: a slim banner at the top of the main menu for the running live event (one line, art first, emoji until the
-- news art exists) and the Tavern News board: a cork board like the Notice Board on the menu wall, each event a small paper
-- note pinned to it (brass pin, a fixed hand-hung tilt per event), a wooden nameplate on top, a paper strip under it and Close
-- below. Display only: the data and the rewards come from the server (Engine/LiveEvents.lua -> state.news); Claim fires
-- `ClaimLiveEvent`. Events never change a fair board, and the board says so. The grid is Engine/NewsBoardLayout (tested at
-- 1920x1080, 1280x720 and 800x450: every note inside the board with 10 px margins, none overlapping, few notes drawn bigger so
-- the cork never looks empty, many notes scrolling). Escape and a click on the dark area close it (Client/PopupDismiss).
--
-- attach(parent, layoutOrder)  called by Menu.lua once, builds the banner
-- init(deps)                   { screenGui, polishPanel, polishButton, roundCorner, playClickSfx, popIn, popOut, claimRemote }
-- update(state)                called from render in a pcall
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NewsPanel = {}

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("NewsBoardLayout"))
local HudKit = require(Engine:WaitForChild("HudKit"))
local MenuSceneArt = require(Engine:WaitForChild("MenuSceneArt"))
-- the painted notice board (Engine/NewsSceneLayout + the shared Client/PanelScene); nil keeps the plain cork board
local okScene, SceneLayout = pcall(function() return require(Engine:WaitForChild("NewsSceneLayout")) end)
if not okScene or type(SceneLayout) ~= "table" then SceneLayout = nil end

local INK = Color3.fromRGB(60, 40, 22)
local INK_SOFT = Color3.fromRGB(110, 78, 40) -- on the paper about 5.6:1
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local PAPER = Color3.fromRGB(238, 222, 186)
local PAPER_SOON = Color3.fromRGB(226, 208, 170)
local GOLD = Color3.fromRGB(222, 182, 104)
local BRASS = Color3.fromRGB(190, 150, 62)
local CREAM = Color3.fromRGB(250, 235, 200)
local WOOD = Color3.fromRGB(86, 58, 34)
local CORK = Color3.fromRGB(168, 124, 78)
local CORK_EDGE = Color3.fromRGB(96, 64, 38)
local GREEN = Color3.fromRGB(70, 110, 65)

local banner
local ui
local lastNews

-- "2 days left", "Last day", "Starts tomorrow", "Starts in 5 days"
function NewsPanel.timeText(row)
	if row.daysLeft then
		return row.daysLeft <= 1 and "Last day" or (tostring(row.daysLeft) .. " days left")
	end
	local n = row.startsIn or 0
	return n <= 1 and "Starts tomorrow" or ("Starts in " .. tostring(n) .. " days")
end

-- The line on a pinned note: "Ends in 3 days" / "Last day" for what is on now, "Starts in 5 days" for what is coming.
function NewsPanel.noteTime(row)
	if row.daysLeft then
		return row.daysLeft <= 1 and "Last day" or ("Ends in " .. tostring(row.daysLeft) .. " days")
	end
	return NewsPanel.timeText(row)
end

-- The one line on the banner for the news view, or nil when there is nothing to show.
function NewsPanel.bannerLine(news)
	if type(news) ~= "table" then
		return nil
	end
	local row = news.banner
	if row then
		return row.icon, row.name .. ": " .. row.blurb, NewsPanel.timeText(row)
	end
	local soon = news.upcoming and news.upcoming[1]
	if soon then
		return soon.icon, "Soon: " .. soon.name, NewsPanel.timeText(soon)
	end
	return nil
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.ZIndex = 33
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function NewsPanel.attach(parent, layoutOrder)
	local frame = Instance.new("TextButton")
	frame.Name = "NewsBanner"
	frame.Size = UDim2.fromOffset(460, 42)
	frame.LayoutOrder = layoutOrder
	frame.BackgroundColor3 = WOOD
	frame.AutoButtonColor = true
	frame.Text = ""
	frame.ZIndex = 10
	frame.Visible = false
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	local icon = label(frame, { Name = "Icon", Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(4, 1), Text = "📰", TextSize = 26, TextColor3 = CREAM, ZIndex = 11 })
	-- Painted news scroll (menu_icons "news") covers the emoji once loaded; the emoji stays if the id is missing.
	require(script.Parent.ArtIcon).apply(icon, "menu_icons", "news", icon, { size = UDim2.fromOffset(34, 34), position = UDim2.fromOffset(3, 3), zIndex = 12, cornerRadius = 6 })
	local text = label(frame, {
		Name = "Text", Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(46, 0), Text = "", TextSize = 15, TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11,
	})
	local time = label(frame, {
		Name = "Time", Size = UDim2.fromOffset(100, 42), Position = UDim2.new(1, -104, 0, 0), Text = "", TextSize = 14, TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 11,
	})
	banner = { frame = frame, icon = icon, text = text, time = time }
	frame.MouseButton1Click:Connect(function()
		if ui then
			ui.playClickSfx()
			NewsPanel.open()
		end
	end)
	return frame
end

-- ===== the board =====
local function screenSize()
	local s = ui.screenGui.AbsoluteSize
	if s.X < 1 or s.Y < 1 then
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		return vp.X, vp.Y
	end
	return s.X, s.Y
end

local function place(obj, r)
	obj.Position = UDim2.fromOffset(r.x, r.y)
	obj.Size = UDim2.fromOffset(r.w, r.h)
end

-- the small kit icon on a note (coins for rewards, a seat otherwise); nothing when the equipped set has no kit
local function noteIcon(row)
	local piece = Layout.iconPiece(row)
	local setId = require(script.Parent.HudTheme).setId()
	return (piece and setId) and HudKit.piece(setId, piece) or nil
end

-- One paper note pinned to the cork. The rect is the final (scaled) rect inside the notes area; the note is built at its natural
-- size and scaled about its centre, tilted by its fixed per-event angle.
local function buildNote(rect, entry, scale, painted)
	local row = entry.row
	local y0 = painted and 30 or 0 -- painted: the picture's own pin sits on the paper's top edge, keep the text clear of it
	-- The root sits in the board's ScrollingFrame, where Roblox ignores Rotation on a direct child: it only places and scales the note.
	-- The paper is its inner Tilt frame, and the tilt is on that.
	local root = Instance.new("Frame")
	root.Name = "Note_" .. tostring(entry.id)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromOffset(rect.x + rect.w / 2, rect.y + rect.h / 2)
	root.Size = UDim2.fromOffset(rect.w / scale, rect.h / scale)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ZIndex = 32
	root.Parent = ui.list
	local note = Instance.new("Frame")
	note.Name = "Tilt"
	note.Size = UDim2.fromScale(1, 1)
	note.Rotation = rect.tilt
	note.BackgroundColor3 = entry.kind == "soon" and PAPER_SOON or PAPER
	note.BackgroundTransparency = painted and 1 or 0 -- painted: the paper and its pin are in the picture
	note.BorderSizePixel = 0
	note.ZIndex = 32
	note.Parent = root
	if scale ~= 1 then
		local s = Instance.new("UIScale")
		s.Scale = scale
		s.Parent = root
	end
	if not painted then
		ui.roundCorner(note, 4)
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(150, 118, 72)
		edge.Thickness = 1
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = note
		local pin = Instance.new("Frame") -- the pin holds the note to the cork, on its top edge, clear of the text
		pin.Name = "Pin"
		pin.AnchorPoint = Vector2.new(0.5, 0.5)
		pin.Position = UDim2.new(0.5, 0, 0, -3)
		pin.Size = UDim2.fromOffset(11, 11)
		pin.BackgroundColor3 = BRASS
		pin.BorderSizePixel = 0
		pin.Active = false
		pin.ZIndex = 36
		pin.Parent = note
		ui.roundCorner(pin, 6)
	end

	if entry.kind == "empty" then
		label(note, { Name = "Text", Size = UDim2.new(1, -24, 1, -16 - y0), Position = UDim2.fromOffset(12, 8 + y0), Text = row.text, TextSize = 17, TextWrapped = true })
		return note
	end

	local iconId = noteIcon(row)
	local textX = 12
	if iconId then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Image = iconId
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Size = UDim2.fromOffset(28, 28)
		icon.Position = UDim2.fromOffset(10, 10)
		icon.Active = false
		icon.ZIndex = 34
		icon.Parent = note
		textX = 40 -- the icon has its own 24 px column (10 to 34)
	end
	label(note, {
		Name = "Title", Size = UDim2.new(1, -(textX + 10), 0, 48), Position = UDim2.fromOffset(textX, 8 + y0), Text = row.name, TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	label(note, {
		Name = "Time", Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 58 + y0), Text = NewsPanel.noteTime(row), TextSize = 14,
		Font = Enum.Font.GothamMedium, TextColor3 = INK_SOFT, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local claimRow = (entry.kind == "active" and entry.claim) and 46 or 12
	label(note, {
		Name = "Blurb", Size = UDim2.new(1, -24, 0, painted and math.max(50, rect.h / scale - (80 + y0) - claimRow) or 50), Position = UDim2.fromOffset(12, 80 + y0), Text = row.blurb or "", TextSize = 14,
		Font = Enum.Font.GothamMedium, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if entry.kind == "active" then
		if entry.claim then
			local button = Instance.new("TextButton")
			button.Name = "Claim"
			button.Size = UDim2.fromOffset(rect.w / scale - 24, 34)
			button.Position = UDim2.fromOffset(12, rect.h / scale - 46)
			button.Font = Enum.Font.GothamBold
			button.TextSize = 16
			button.TextColor3 = CREAM
			button.ZIndex = 34
			button.Parent = note
			ui.polishButton(button, 8)
			if row.claimed then
				button.Text = "Claimed"
				button.BackgroundColor3 = Color3.fromRGB(110, 120, 90)
				button.Active = false
			else
				button.Text = (#row.rewards > 0) and ("Claim: " .. table.concat(row.rewards, ", ")) or "Claim"
				button.TextTruncate = Enum.TextTruncate.AtEnd
				button.BackgroundColor3 = GREEN
				button.MouseButton1Click:Connect(function()
					ui.playClickSfx()
					ui.claimRemote:FireServer(row.id)
				end)
			end
		end
	end
	return note
end

-- Painted notice board on/off: the plain cork dressing (fill, grain, wood edge, nameplate and strip fills, Close button look) goes away
-- when the picture is the board, and comes back for small screens, a missing Image id and more events than painted notes.
function NewsPanel.setPainted(on)
	if not ui or ui.painted == on then return end
	ui.painted = on
	ui.panel.BackgroundTransparency = on and 1 or 0
	ui.shade.Enabled = not on
	ui.woodEdge.Enabled = not on
	ui.speck.Parent = (not on) and ui.panel or nil
	ui.inner.Visible = not on
	for _, f in ipairs({ ui.heading, ui.strip }) do
		f.BackgroundTransparency = on and 1 or 0
	end
	ui.headEdge.Enabled = not on
	ui.stripEdge.Enabled = not on
	ui.close.BackgroundTransparency = on and 1 or 0
	for _, ch in ipairs(ui.close:GetChildren()) do -- the polish gloss, stroke and gradient of the button (the garbled little icon)
		if ch.ClassName == "UIStroke" or ch.ClassName == "UIGradient" then
			ch.Enabled = not on
		elseif ch.ClassName == "Frame" or ch.ClassName == "ImageLabel" or ch.ClassName == "TextLabel" then
			ch.Visible = not on
		end
	end
	ui.close.TextStrokeColor3 = Color3.fromRGB(30, 18, 8)
	ui.close.TextStrokeTransparency = on and 0.35 or 1
	ui.close.TextTransparency = 0
	local ink = on and SceneLayout.COLORS.ink or { 250, 235, 200 }
	ui.headingLabel.TextColor3 = Color3.fromRGB(ink[1], ink[2], ink[3])
	ui.stripLabel.TextColor3 = Color3.fromRGB(ink[1], ink[2], ink[3])
	ui.headingLabel.TextSize = on and 30 or 24
	ui.stripLabel.TextWrapped = on
	ui.stripLabel.TextTruncate = on and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
	if not on and ui.scene then ui.scene.hide() end
end

-- Lays the board out as the painted notice board; false when it cannot (plain board then)
function NewsPanel.refreshPainted(entries, W, H)
	if not (SceneLayout and ui.scene and ui.scene.id and SceneLayout.canShow(#entries)) then
		return false
	end
	local rect = SceneLayout.panel(W, H)
	local p = SceneLayout.place(rect.w)
	if not p then
		return false
	end
	NewsPanel.setPainted(true)
	ui.panel.Size = UDim2.fromOffset(rect.w, rect.h)
	ui.scene.show({ x = 0, y = 0, w = rect.w, h = rect.h }, p)
	place(ui.heading, p.banner)
	place(ui.strip, p.strip)
	place(ui.close, p.close)
	place(ui.list, { x = 0, y = 0, w = rect.w, h = rect.h })
	ui.list.CanvasSize = UDim2.fromOffset(0, 0)
	ui.list.ScrollingEnabled = false
	ui.list.ScrollBarThickness = 0
	ui.list.CanvasPosition = Vector2.new(0, 0)
	for i, entry in ipairs(entries) do
		local slot = p.notes[i]
		buildNote({ x = slot.x, y = slot.y, w = slot.w, h = slot.h, tilt = 0 }, entry, 1, true)
	end
	if entries[1].kind ~= "empty" then -- the blank papers left over say so, in the same ink
		for i = #entries + 1, #p.notes do
			local slot = p.notes[i]
			label(ui.list, { Name = "Soon_" .. i, Position = UDim2.fromOffset(slot.x + 12, slot.y + 30), Size = UDim2.fromOffset(slot.w - 24, 40),
				Text = "More news soon", TextSize = 16, TextWrapped = true, TextColor3 = INK_SOFT, Font = Enum.Font.GothamMedium })
		end
	end
	if game:GetService("RunService"):IsStudio() and ui.lastLog ~= #entries .. "x" .. rect.w then
		ui.lastLog = #entries .. "x" .. rect.w
		print(string.format("[NewsRoom] painted board=%dx%d notes=%d of %d slots, banner %dx%d, close %dx%d", rect.w, rect.h, #entries, #p.notes, p.banner.w, p.banner.h, p.close.w, p.close.h))
	end
	return true
end

function NewsPanel.refresh()
	if not ui or not lastNews then
		return
	end
	for _, child in ipairs(ui.list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local entries = {}
	for _, row in ipairs(lastNews.active or {}) do
		entries[#entries + 1] = { id = row.id, kind = "active", claim = row.hasRewards == true, row = row }
	end
	for _, row in ipairs(lastNews.upcoming or {}) do
		entries[#entries + 1] = { id = row.id, kind = "soon", claim = false, row = row }
	end
	if #entries == 0 then -- an empty cork is still a board: one note says so
		entries[1] = { id = "empty", kind = "empty", claim = false, row = { text = "Nothing is on right now. Check back soon!" } }
	end
	local W, H = screenSize()
	if NewsPanel.refreshPainted(entries, W, H) then
		return
	end
	NewsPanel.setPainted(false)
	local board = Layout.board(W, H)
	local areas = Layout.areas(board)
	ui.panel.Size = UDim2.fromOffset(board.w, board.h)
	place(ui.heading, areas.heading)
	place(ui.strip, areas.subtitle)
	place(ui.list, areas.notes)
	place(ui.close, areas.close)
	local plan = Layout.layout(areas.notes.w, areas.notes.h, entries)
	ui.list.CanvasSize = UDim2.fromOffset(0, plan.scroll and (plan.contentH + 24) or 0)
	ui.list.ScrollingEnabled = plan.scroll
	ui.list.ScrollBarThickness = plan.scroll and 6 or 0
	ui.list.CanvasPosition = Vector2.new(0, 0)
	for i, rect in ipairs(plan.rects) do
		-- in the scrolling case the rects are already top-down from 0; a 10 px gutter keeps the first pin inside the list
		local r = plan.scroll and { x = rect.x, y = rect.y + 12, w = rect.w, h = rect.h, tilt = rect.tilt } or rect
		buildNote(r, entries[i], plan.scale)
	end
end

-- Hide the board at once, no animation (DebugGoto jumps and other full-screen switches).
function NewsPanel.hideNow()
	if ui then ui.backdrop.Visible = false end
end

function NewsPanel.open()
	if not ui then
		return
	end
	NewsPanel.refresh()
	ui.popIn(ui.backdrop, ui.panel)
end

function NewsPanel.init(deps)
	local backdrop = Instance.new("Frame")
	backdrop.Name = "NewsBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 30
	backdrop.Parent = deps.screenGui
	require(script.Parent.MenuTitleHider).bind(deps.screenGui, backdrop)

	-- the Menu's painted tavern room behind the board (nothing when its Image id is missing), under one dim layer
	local art = MenuSceneArt["menu_scene_a"]
	if type(art) == "string" and art ~= "" then
		local painting = Instance.new("ImageLabel")
		painting.Name = "Painting"
		painting.Size = UDim2.fromScale(1, 1)
		painting.BackgroundTransparency = 1
		painting.Image = art
		painting.ScaleType = Enum.ScaleType.Crop
		painting.ZIndex = 30
		painting.Parent = backdrop
		local scrim = Instance.new("Frame")
		scrim.Name = "Scrim"
		scrim.Size = UDim2.fromScale(1, 1)
		scrim.BackgroundColor3 = Color3.fromRGB(14, 9, 5)
		scrim.BackgroundTransparency = 0.45
		scrim.BorderSizePixel = 0
		scrim.ZIndex = 30
		scrim.Parent = backdrop
	end

	-- the cork board: a warm cork fill (colour stops only) in a dark wooden frame
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(600, 440)
	panel.BackgroundColor3 = CORK
	panel.BorderSizePixel = 0
	panel.ZIndex = 31
	panel.Parent = backdrop
	deps.roundCorner(panel, 12)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.fromRGB(186, 142, 94), Color3.fromRGB(150, 108, 66))
	shade.Parent = panel
	local woodEdge = Instance.new("UIStroke")
	woodEdge.Color = CORK_EDGE
	woodEdge.Thickness = 6
	woodEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	woodEdge.Parent = panel
	-- cork grain: speckles (low contrast, stronger than before) at fixed spots (deterministic, no animation) and a thin inner shadow under the frame
	local speck = Instance.new("Folder")
	speck.Name = "Speckle"
	speck.Parent = panel
	local seed = 17
	for i = 1, 120 do
		seed = (seed * 1103515245 + 12345) % 2147483648
		local fx = (seed % 1000) / 1000
		seed = (seed * 1103515245 + 12345) % 2147483648
		local fy = (seed % 1000) / 1000
		local d = Instance.new("Frame")
		d.Name = "Dot" .. i
		d.Size = UDim2.fromOffset(2 + i % 3, 2 + i % 3)
		d.Position = UDim2.new(0.02 + fx * 0.96, 0, 0.02 + fy * 0.96, 0)
		d.BackgroundColor3 = (i % 2 == 0) and Color3.fromRGB(104, 70, 40) or Color3.fromRGB(214, 174, 126)
		d.BackgroundTransparency = 0.62
		d.BorderSizePixel = 0
		d.Active = false
		d.ZIndex = 31
		d.Parent = speck
		deps.roundCorner(d, 3)
	end
	local inner = Instance.new("Frame")
	inner.Name = "InnerShadow"
	inner.Size = UDim2.new(1, -4, 1, -4)
	inner.Position = UDim2.fromOffset(2, 2)
	inner.BackgroundTransparency = 1
	inner.BorderSizePixel = 0
	inner.Active = false
	inner.ZIndex = 31
	inner.Parent = panel
	deps.roundCorner(inner, 10)
	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = Color3.fromRGB(70, 46, 26)
	innerStroke.Thickness = 3
	innerStroke.Transparency = 0.65
	innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	innerStroke.Parent = inner

	-- "Tavern News" on a small wooden nameplate hung on the top of the board
	local heading = Instance.new("Frame")
	heading.Name = "Heading"
	heading.BackgroundColor3 = WOOD
	heading.BorderSizePixel = 0
	heading.ZIndex = 33
	heading.Parent = panel
	deps.roundCorner(heading, 8)
	local headEdge = Instance.new("UIStroke")
	headEdge.Color = GOLD
	headEdge.Thickness = 2
	headEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	headEdge.Parent = heading
	local headingLabel = label(heading, { Size = UDim2.fromScale(1, 1), Text = "Tavern News", TextSize = 24, TextColor3 = CREAM, ZIndex = 34 })

	-- the subtitle on a strip of paper
	local strip = Instance.new("Frame")
	strip.Name = "Subtitle"
	strip.BackgroundColor3 = WOOD
	strip.BorderSizePixel = 0
	strip.ZIndex = 33
	strip.Parent = panel
	deps.roundCorner(strip, 6)
	local stripEdge = Instance.new("UIStroke")
	stripEdge.Color = BRASS
	stripEdge.Thickness = 1
	stripEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stripEdge.Parent = strip
	local stripLabel = label(strip, {
		Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), Text = "Events never change the Daily, Weekly or Seed boards.",
		TextSize = 14, Font = Enum.Font.GothamMedium, TextColor3 = CREAM, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 34,
	})

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 0
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.ZIndex = 32
	list.Parent = panel

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Font = Enum.Font.GothamBold
	close.TextSize = 17
	close.Text = "Close"
	close.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	close.TextColor3 = CREAM
	close.ZIndex = 34
	close.Parent = panel
	deps.polishButton(close, 10)

	-- the painted notice board under the notes (nothing when the module or the Image id is missing: the cork board above stays)
	local scene
	if SceneLayout then
		local okPS, PanelScene = pcall(function() return require(script.Parent.PanelScene) end)
		if okPS and type(PanelScene) == "table" then
			local okNew, made = pcall(PanelScene.new, panel, { artKey = SceneLayout.ART_KEY, def = SceneLayout.DEF, z = 31, edgeFade = true })
			if okNew then scene = made end
		end
	end

	ui = {
		backdrop = backdrop, panel = panel, heading = heading, strip = strip, list = list, close = close, screenGui = deps.screenGui,
		scene = scene, shade = shade, woodEdge = woodEdge, speck = speck, inner = inner, headEdge = headEdge, stripEdge = stripEdge,
		headingLabel = headingLabel, stripLabel = stripLabel,
		roundCorner = deps.roundCorner, polishButton = deps.polishButton, playClickSfx = deps.playClickSfx, popIn = deps.popIn,
		popOut = deps.popOut, claimRemote = deps.claimRemote,
	}
	close.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		deps.popOut(backdrop, panel)
	end)
	-- Escape and a click on the dark area close it like Close (Client/PopupDismiss).
	require(script.Parent.PopupDismiss).attach(backdrop, { panel = panel, close = function() deps.popOut(backdrop, panel) end, button = true })
end

function NewsPanel.update(state)
	if type(state) ~= "table" or type(state.news) ~= "table" then
		return
	end
	lastNews = state.news
	if banner then
		local icon, line, time = NewsPanel.bannerLine(lastNews)
		banner.frame.Visible = icon ~= nil
		if icon then
			banner.icon.Text = icon
			banner.text.Text = line
			banner.time.Text = time
		end
	end
	if ui and ui.backdrop.Visible then
		NewsPanel.refresh()
	end
end

return NewsPanel
