--[[
	Client/PlayBoardPaint.lua
	Step C1 of the painted play screen: play_board_a (the hanging wooden board) as one picture behind the left HUD rows.
	The rows are placed on the slots by Client/PlayBoardHud (C2 to C4). The picture is made
	right after SidebarBoard (so every later sibling, the hand included, draws above it at the same ZIndex 1) with the
	rect from Engine/PlayBoardLayout.placement (2:3, width at most 24 percent of the screen, never stretched).
	Painted state comes from the PreloadAsync status (Engine/ImagePreload), not IsLoaded. Missing id, failed load or a window under
	900 px wide: the flat parchment board stays exactly as it was.

	install{ root, board, boardArt, width, fill }   board = SidebarBoard frame, boardArt = its old painted art label (or nil),
	width = SIDEBAR_WIDTH, fill = the flat parchment colour
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PlayBoardLayout = require(Engine:WaitForChild("PlayBoardLayout"))
local ImagePreload = require(Engine:WaitForChild("ImagePreload"))
local SidebarMetrics = require(Engine:WaitForChild("SidebarMetrics"))
local PlayBoardHud = require(script.Parent:WaitForChild("PlayBoardHud"))
local Guard = require(script.Parent:WaitForChild("PlayPaintGuard"))

local PlayBoardPaint = {}

function PlayBoardPaint.install(deps)
	local root, board = deps.root, deps.board
	local okArt, art = pcall(function() return require(Engine:WaitForChild("PlaySceneArt")) end)
	local id = okArt and type(art) == "table" and art.play_board_a or nil
	if not id or id == "" then return { isPainted = function() return false end } end

	-- flat parchment under the part of the left column the board does not reach (the rows still sit there)
	local filler = Instance.new("Frame")
	filler.Name = "PlayBoardFiller"
	filler.BackgroundColor3 = deps.fill or Color3.fromRGB(226, 202, 156)
	filler.BorderSizePixel = 0
	filler.Active = false
	filler.ZIndex = 1
	filler.Visible = false
	filler.Parent = root

	local image = Instance.new("ImageLabel") -- made after the filler, so it draws above it
	image.Name = "PlayBoardPaint"
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Active = false
	image.Image = id
	image.ScaleType = Enum.ScaleType.Stretch -- the rect already has the picture's 2:3 (PlayBoardLayout.size)
	image.ZIndex = 1
	image.Visible = false
	image.Parent = root

	local function tinted() return root:GetAttribute("RoomTint") or Color3.new(1, 1, 1) end
	image.ImageColor3 = tinted()
	root:GetAttributeChangedSignal("RoomTint"):Connect(function() image.ImageColor3 = tinted() end) -- the equipped Card Set's room (PlayScenePaint)
	local loaded, painted = false, false
	local function apply()
		local size = root.AbsoluteSize
		local p = loaded and PlayBoardLayout.placement(size.X, size.Y) or nil
		if p then
			painted = true
			SidebarMetrics.setPainted(true)
			image.Position = UDim2.fromOffset(p.x, p.y)
			image.Size = UDim2.fromOffset(p.w, p.h)
			image.Visible = true
			filler.Position = UDim2.fromOffset(0, p.h)
			filler.Size = UDim2.fromOffset(deps.width or 240, math.max(0, size.Y - p.h))
			filler.Visible = false -- the table shows below the board; the leftover rows sit on their own plates
			board.BackgroundTransparency = 1
			if deps.boardArt then deps.boardArt.Visible = false end
			Guard.run("board HUD", PlayBoardHud.apply, root, p) -- C2 to C4: the HUD rows onto the board's slots (the old column returns on nil)
		elseif painted then
			painted = false
			SidebarMetrics.setPainted(false)
			image.Visible, filler.Visible = false, false
			board.BackgroundTransparency = 0
			if deps.boardArt then deps.boardArt.Visible = true end
			Guard.run("board HUD", PlayBoardHud.apply, root, nil)
		end
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)

	task.spawn(function()
		loaded = ImagePreload.run(ContentProvider, image, Enum.AssetFetchStatus.Success)
		if loaded then apply() end
	end)
	return { isPainted = function() return painted end }
end

return PlayBoardPaint
