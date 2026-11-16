--[[
	Client/Table3D/Stand.lua
	The play screen's flat HUD pieces, stood on the table as things. The same bargain as the cards (Table3D/Cards):
	the 2D piece stays where the hub's layout puts it and keeps every click, tooltip, tutorial rectangle and tween,
	but it no longer draws. A wooden board stands on the felt where the piece's lower edge is on screen, leaning back
	toward the camera, and the piece's own pictures and labels are moved onto the board's face. So a button is still
	the hub's button, pressed in the same place, and it is a sign on the table.

	Stand.start{ scene, theme }
	Stand.adopt(proxy, opts)   proxy: the 2D GuiObject. opts:
	    lean      degrees back from upright (Engine/TableScene.STAND)
	    anchor    the GuiObject whose lower edge is the foot (default: the proxy). A proxy that rises above its anchor
	              (a Patron's hop) rises off the table.
	    material  the theme material of the board (default "board")
	    foot      true: a wooden foot under the board
	    forward   studs toward the camera (a small plate on a bigger board)
	    keep      { [child name] = true }: children that stay in 2D (they hold click targets of their own)
	    clear     true: no board is seen, only the piece's own picture (a plate on a board that is already there)
	    backer    true: the piece keeps drawing in 2D and the board only stands behind it, a little larger, with its
	              foot and its shadow. For pieces the hub restyles by looking their parts up by name (Play Hand,
	              Discard, the sort toggle): moving those parts away made the hub paint them twice.
	Stand.pile(widget)         the deck: a real pile of cards under the 2D deck widget, as tall as the deck is full
	Stand.count() -> boards
]]

local RunService = game:GetService("RunService")
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local TS = require(Engine:WaitForChild("TableScene"))
local Rig = require(script.Parent.Rig)

local Stand = {}

local K = 2
local FACE = CFrame.Angles(0, -math.pi / 2, 0) -- see Table3D/Cards: a top face draws its picture a quarter turn round
local CLONED = { UICorner = true, UIListLayout = true, UIPadding = true, UIGridLayout = true }
local MOVED = { UIStroke = true, UIGradient = true }

local deps, folder = nil, nil
local stands = {}
local pile = nil

local function still(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function seen(gui)
	local node = gui
	while node and not node:IsA("LayerCollector") do
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	return node ~= nil and node.Enabled
end

local function newFace(part, w, h)
	local look = deps.theme.Lighting.cards or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(w * K, h * K)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.LightInfluence = look.lightInfluence or 1
	gui.Brightness = look.brightness or 1
	gui.Parent = part
	local paper = Instance.new("Frame")
	paper.Name = "Paper"
	paper.BorderSizePixel = 0
	paper.BackgroundTransparency = 1
	paper.Size = UDim2.fromOffset(w, h)
	paper.ZIndex = 0
	paper.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = K
	scale.Parent = paper
	return gui, paper
end

local function rehome(st, child)
	if st.dead or not child or child.Parent ~= st.proxy then return end
	if st.keep and st.keep[child.Name] then return end
	if child:IsA("GuiObject") or MOVED[child.ClassName] then
		-- the hub's painters look a piece up by name on the button and, not finding the one that was moved here, make
		-- it again: the newest one replaces the one on the board
		if child.Name ~= child.ClassName then
			local old = st.paper:FindFirstChild(child.Name)
			if old and old ~= child then old:Destroy() end
		end
		child.Parent = st.paper
	elseif CLONED[child.ClassName] and not st.paper:FindFirstChildOfClass(child.ClassName) then
		child:Clone().Parent = st.paper
	end
end

local function drop(st)
	st.dead = true
	for _, c in ipairs(st.conns) do c:Disconnect() end
	st.part:Destroy()
	if st.footPart then st.footPart:Destroy() end
end

function Stand.adopt(proxy, opts)
	if not deps or not proxy or not proxy:IsA("GuiObject") or proxy:GetAttribute("Table3DStand") then return end
	proxy:SetAttribute("Table3DStand", true)
	opts = opts or {}
	local part = still(Instance.new("Part"))
	part.Name = "Board_" .. proxy.Name
	part.Size = Vector3.new(2, 0.14, 2)
	deps.scene.paint(part, opts.material or "board")
	if opts.clear then
		part.Transparency = 1
		part.CastShadow = false
	end
	local size = proxy.AbsoluteSize
	local w, h = math.max(8, math.floor(size.X + 0.5)), math.max(8, math.floor(size.Y + 0.5))
	local gui, paper = newFace(part, w, h)
	local st = {
		proxy = proxy, anchor = opts.anchor, lean = opts.lean or TS.STAND.sign, forward = opts.forward or 0,
		keep = opts.keep, part = part, gui = gui, paper = paper, basisW = w, basisH = h, conns = {}, thick = opts.thick or 0.14,
	}
	if opts.foot then
		local foot = still(Instance.new("Part"))
		foot.Name = "Foot"
		deps.scene.paint(foot, opts.material or "board")
		st.footPart = foot
	end
	if opts.backer then
		st.backer = true
		gui.Enabled = false
		stands[#stands + 1] = st
		return st
	end
	-- a button that writes its own caption (no label child) gets it copied onto the board
	local labelled = proxy:FindFirstChildWhichIsA("TextLabel") ~= nil -- its caption is a label of its own: that is moved, not copied
	if (proxy:IsA("TextButton") or proxy:IsA("TextLabel")) and proxy.Text ~= "" and proxy.TextTransparency < 1 and not labelled then
		local label = Instance.new("TextLabel")
		label.Name = "Caption"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.ZIndex = proxy.ZIndex + 1
		label.TextTransparency = proxy.TextTransparency
		label.Parent = paper
		st.caption = label
		proxy.TextTransparency = 1
	elseif proxy:IsA("TextButton") then
		proxy.TextTransparency = 1
	end
	for _, child in ipairs(proxy:GetChildren()) do rehome(st, child) end
	st.conns[1] = proxy.ChildAdded:Connect(function(child) task.defer(rehome, st, child) end)
	stands[#stands + 1] = st
	return st
end

local function show(st, on)
	if st.shown == on then return end
	st.shown = on
	st.part.Parent = on and folder or nil
	if st.footPart then st.footPart.Parent = on and folder or nil end
end

local function place(st)
	local proxy = st.proxy
	local ps = proxy.AbsoluteSize
	if not seen(proxy) or ps.X < 4 or ps.Y < 4 then show(st, false) return end
	local anchor = st.anchor and st.anchor.Parent and st.anchor or proxy
	local ap, as = anchor.AbsolutePosition, anchor.AbsoluteSize
	local pp = proxy.AbsolutePosition
	local footX, footY = ap.X + as.X / 2, ap.Y + as.Y
	local at, tp = Rig.pointUnder(footX, footY, 0)
	if not at or not TS.onFelt(tp, -4) then show(st, false) return end
	local spp = Rig.studsPerPixel(tp)
	local w, h = ps.X * spp, ps.Y * spp
	if st.backer then w, h = w + 0.5, h + 0.3 end
	local rise = math.max(-0.5, (footY - (pp.Y + ps.Y)) * spp)
	local side = (pp.X + ps.X / 2 - footX) * spp
	local a = math.rad(st.lean)
	local up = Vector3.new(0, math.cos(a), -math.sin(a))
	local normal = Vector3.new(0, math.sin(a), math.cos(a))
	local centre = at + Vector3.new(side, 0, 0) + up * (h / 2 + rise) + normal * (st.thick / 2 + st.forward)
	st.part.Size = Vector3.new(h, st.thick, w)
	st.part.CFrame = CFrame.new(centre) * CFrame.Angles(math.pi / 2 - a, 0, 0) * FACE
	if st.footPart then
		st.footPart.Size = Vector3.new(w * 0.86, 0.16, math.max(0.5, h * 0.2))
		st.footPart.CFrame = CFrame.new(at + Vector3.new(side, 0.08, -h * 0.05))
	end

	if st.backer then show(st, true) return end
	-- the board's face keeps up with the piece: its size, its backing color and its caption
	local bw, bh = math.floor(ps.X + 0.5), math.floor(ps.Y + 0.5)
	if math.abs(bw - st.basisW) > 1 or math.abs(bh - st.basisH) > 1 then
		st.basisW, st.basisH = bw, bh
		st.gui.CanvasSize = Vector2.new(bw * K, bh * K)
		st.paper.Size = UDim2.fromOffset(bw, bh)
	end
	if proxy.BackgroundTransparency < 1 then -- the hub drew its backing again: the board takes it, the piece stays unseen
		st.backing = proxy.BackgroundTransparency
		proxy.BackgroundTransparency = 1
	end
	st.paper.BackgroundTransparency = st.backing or 1
	st.paper.BackgroundColor3 = proxy.BackgroundColor3
	if st.caption then
		local c = st.caption
		c.Text, c.FontFace, c.TextSize, c.TextColor3, c.TextScaled = proxy.Text, proxy.FontFace, proxy.TextSize, proxy.TextColor3, proxy.TextScaled
		if proxy.TextTransparency < 1 then proxy.TextTransparency = 1 end
	end
	show(st, true)
end

-- the deck
local KEEP_IN_DECK = { ClickCatcher = true, DeckCount = true }
function Stand.pile(widget)
	if not deps or pile or not widget then return end
	local part = still(Instance.new("Part"))
	part.Name = "DeckPile"
	deps.scene.paint(part, "cardEdge")
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(200, 280)
	local look = deps.theme.Lighting.cards or {}
	gui.LightInfluence = look.lightInfluence or 1
	gui.Brightness = look.brightness or 1
	gui.Parent = part
	local back = Instance.new("ImageLabel")
	back.Size = UDim2.fromScale(1, 1)
	back.BorderSizePixel = 0
	back.ScaleType = Enum.ScaleType.Crop
	back.Parent = gui
	pile = { widget = widget, part = part, back = back, tick = 0 }
end

local function placePile(dt)
	local widget = pile.widget
	if not widget.Parent then pile.part.Parent = nil return end
	pile.tick = pile.tick - dt
	if pile.tick <= 0 then -- now and then: the painted pile stays unseen (card sets repaint it), the count is read
		pile.tick = 0.4
		if widget.BackgroundTransparency < 1 then widget.BackgroundTransparency = 1 end
		for _, child in ipairs(widget:GetChildren()) do
			if child:IsA("GuiObject") then
				if not KEEP_IN_DECK[child.Name] and child.Visible then child.Visible = false end
			elseif child:IsA("UIStroke") and child.Enabled then
				child.Enabled = false
			end
		end
		local art = widget:FindFirstChild("CardBackArt", true)
		local frame = widget:FindFirstChild("DeckCardBack")
		if art and art.Image ~= "" then pile.back.Image = art.Image end
		if frame then pile.back.BackgroundColor3 = frame.BackgroundColor3 end
		local count = widget:FindFirstChild("DeckCount")
		local left, all = string.match(count and count.Text or "", "(%d+)%s*/%s*(%d+)")
		pile.full = (tonumber(left) or 40) / math.max(1, tonumber(all) or 52)
	end
	if not seen(widget) then pile.part.Parent = nil return end
	local pos, size = widget.AbsolutePosition, widget.AbsoluteSize
	local at, tp = Rig.pointUnder(pos.X + size.X / 2, pos.Y + size.Y * 0.62, 0)
	if not at then pile.part.Parent = nil return end
	local spp = Rig.studsPerPixel(tp)
	local w = size.X * 0.8 * spp
	local tall = math.max(0.06, 1.5 * (pile.full or 0.8))
	pile.part.Size = Vector3.new(w * TS.CARD.aspect, tall, w)
	pile.part.CFrame = CFrame.new(at + Vector3.new(0, tall / 2, 0)) * CFrame.Angles(0, math.rad(-7), 0) * FACE
	if pile.part.Parent ~= folder then pile.part.Parent = folder end
end

local function step(dt)
	for i = #stands, 1, -1 do
		local st = stands[i]
		if not st.proxy.Parent then
			drop(st)
			table.remove(stands, i)
		else
			local ok, err = pcall(place, st)
			if not ok and not st.warned then
				st.warned = true
				warn("[Table3D] the board for " .. st.proxy.Name .. " could not be placed: " .. tostring(err))
			end
		end
	end
	if pile then pcall(placePile, dt) end
end

function Stand.count()
	return #stands
end

function Stand.start(d)
	deps = d
	folder = Instance.new("Folder")
	folder.Name = "Stands"
	folder.Parent = d.scene.model
	RunService:BindToRenderStep("Table3DStands", Enum.RenderPriority.Camera.Value + 2, step)
end

return Stand
