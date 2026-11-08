--[[
	Client/JourneyMapFog.lua
	Fog of war for the Journey map. One drifting cloud band covers everything
	past the reveal limit. It is built in code from overlapping soft round
	Frames in warm-white (Color stops and stepped BackgroundTransparency only,
	never a gradient): a slow back layer and a nearer front layer, with
	feathered leading columns so the edge dissolves. It is never black.

	The band is one Frame; moving the fog back one stop is a tween of its
	Position. A "Something stirs in the fog..." tag rides on the band. The
	"teaser" node is a dim "???" lantern glow that sits half inside the fog,
	under it.

	Drift tweens run only between startDrift and stopDrift (map shown) and
	are skipped when `calm()` (Reduce Shake) is on.

	deps: canvas, TweenService, roundCorner, calm() -> bool, pace() -> number

	Returns:
		layout(canvasW, canvasH)  rebuilds the puffs for the canvas size
		update({ edgeX, teaser = {x, y, size} | nil, hintX, hintY, animate })
		    edgeX = canvas x where the fog begins (nil = no fog at all)
		startDrift(), stopDrift()
		getEdge() -> current target edgeX (nil when no fog)
]]

return function(deps)
	local TweenService = deps.TweenService
	local canvas = deps.canvas

	local FOG = Color3.fromRGB(244, 232, 208)
	local FOG_CORE = Color3.fromRGB(250, 240, 220)
	local GLOW = Color3.fromRGB(255, 200, 110)
	local GLOW_CORE = Color3.fromRGB(255, 228, 165)
	local INK = Color3.fromRGB(60, 40, 22)
	local STROKE = Color3.fromRGB(240, 222, 180)
	local Z_FOG = 35

	local band = Instance.new("Frame")
	band.Name = "FogBand"
	band.BackgroundTransparency = 1
	band.Position = UDim2.fromOffset(100000, 0)
	band.Size = UDim2.fromOffset(100, 100)
	band.ZIndex = Z_FOG
	band.Parent = canvas

	local puffHolder = Instance.new("Frame")
	puffHolder.Name = "Puffs"
	puffHolder.Size = UDim2.fromScale(1, 1)
	puffHolder.BackgroundTransparency = 1
	puffHolder.ZIndex = Z_FOG
	puffHolder.Parent = band

	-- Hint tag, rides on the band so it moves with the fog edge.
	local hint = Instance.new("TextLabel")
	hint.Name = "FogHint"
	hint.AnchorPoint = Vector2.new(0.5, 0.5)
	hint.Size = UDim2.fromOffset(0, 28)
	hint.AutomaticSize = Enum.AutomaticSize.X
	hint.BackgroundColor3 = Color3.fromRGB(236, 216, 172)
	hint.BackgroundTransparency = 0.1
	hint.BorderSizePixel = 0
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 14
	hint.TextWrapped = false
	hint.TextColor3 = INK
	hint.TextTransparency = 0
	hint.TextStrokeColor3 = STROKE
	hint.TextStrokeTransparency = 0.5
	hint.Text = "Something stirs in the fog..."
	hint.ZIndex = Z_FOG + 2
	hint.Parent = band
	deps.roundCorner(hint, 6)
	local hintPad = Instance.new("UIPadding")
	hintPad.PaddingLeft = UDim.new(0, 10)
	hintPad.PaddingRight = UDim.new(0, 10)
	hintPad.Parent = hint
	local hintStroke = Instance.new("UIStroke")
	hintStroke.Color = Color3.fromRGB(110, 80, 45)
	hintStroke.Thickness = 1.5
	hintStroke.Parent = hint

	-- Teaser: dim "???" lantern glow, drawn UNDER the fog so it sits half inside.
	local teaser = Instance.new("Frame")
	teaser.Name = "TeaserGlow"
	teaser.AnchorPoint = Vector2.new(0.5, 0.5)
	teaser.Size = UDim2.fromOffset(120, 120)
	teaser.BackgroundTransparency = 1
	teaser.Visible = false
	teaser.ZIndex = Z_FOG - 2
	teaser.Parent = canvas
	local function disc(parent, scale, color, transparency)
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromScale(0.5, 0.5)
		d.Size = UDim2.fromScale(scale, scale)
		d.BackgroundColor3 = color
		d.BackgroundTransparency = transparency
		d.BorderSizePixel = 0
		d.ZIndex = parent.ZIndex
		d.Parent = parent
		deps.roundCorner(d, 200)
		return d
	end
	local teaserOuter = disc(teaser, 1, GLOW, 0.84)
	disc(teaser, 0.68, GLOW, 0.7)
	disc(teaser, 0.38, GLOW_CORE, 0.5)
	local teaserText = Instance.new("TextLabel")
	teaserText.Size = UDim2.fromScale(1, 1)
	teaserText.BackgroundTransparency = 1
	teaserText.Font = Enum.Font.GothamBold
	teaserText.TextSize = 22
	teaserText.Text = "???"
	teaserText.TextWrapped = false
	teaserText.TextColor3 = Color3.fromRGB(120, 88, 48)
	teaserText.TextTransparency = 0.15
	teaserText.TextStrokeColor3 = STROKE
	teaserText.TextStrokeTransparency = 0.6
	teaserText.ZIndex = Z_FOG - 1
	teaserText.Parent = teaser

	local drifting = false
	local driftTweens = {}
	local glowTween = TweenService:Create(teaserOuter,
		TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.92 })
	local puffs = {}
	local lastW, lastH = 0, 0
	local edgeTarget = nil
	local edgeTween = nil

	local function puff(layerIndex, cx, cy, diameter, outerTr, innerTr)
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromOffset(cx, cy)
		holder.Size = UDim2.fromOffset(diameter, diameter)
		holder.BackgroundTransparency = 1
		holder.ZIndex = Z_FOG
		holder.Parent = puffHolder
		disc(holder, 1, FOG, math.min(outerTr, 0.98))
		disc(holder, 0.62, FOG_CORE, math.min(innerTr, 0.98))
		table.insert(puffs, { frame = holder, cx = cx, cy = cy, layer = layerIndex })
	end

	local function stopDrift()
		drifting = false
		for _, t in ipairs(driftTweens) do
			t:Cancel()
		end
		driftTweens = {}
		glowTween:Cancel()
	end

	local function startDrift()
		stopDrift()
		drifting = true
		if deps.calm() then
			return
		end
		glowTween:Play()
		for i, p in ipairs(puffs) do
			local amp = (p.layer == 1 and 26 or 46) * (0.6 + ((i * 53) % 40) / 50)
			local dur = (p.layer == 1 and 12 or 8) + ((i * 29) % 50) / 10
			local dir = (p.layer == 1) and -1 or 1
			local t = TweenService:Create(p.frame,
				TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = UDim2.fromOffset(p.cx + dir * amp, p.cy + ((i % 3) - 1) * 8) })
			t:Play()
			table.insert(driftTweens, t)
		end
	end

	local function layout(canvasW, canvasH)
		lastW, lastH = canvasW, canvasH
		local wasDrifting = drifting
		stopDrift()
		puffHolder:ClearAllChildren()
		puffs = {}
		local bandW = canvasW + 700
		band.Size = UDim2.fromOffset(bandW, canvasH)
		-- Back layer: big, faint, sparse.
		local backStep, backD = 340, math.max(440, canvasH * 0.7)
		local rows = math.max(2, math.ceil(canvasH / 330))
		local col = 0
		local x = -320
		while x < bandW do
			col += 1
			local feather = col == 1 and 0.2 or (col == 2 and 0.08 or 0)
			for r = 1, rows do
				local cy = (r - 0.5) * canvasH / rows + (((col + r) % 2) * 2 - 1) * 24
				puff(1, x + ((r % 2) * 90), cy, backD, 0.8 + feather, 0.7 + feather)
			end
			x += backStep
		end
		-- Front layer: nearer, denser.
		local frontStep, frontD = 230, math.max(340, canvasH * 0.5)
		rows = math.max(3, math.ceil(canvasH / 250))
		col = 0
		x = -260
		while x < bandW do
			col += 1
			local feather = col == 1 and 0.26 or (col == 2 and 0.12 or 0)
			for r = 1, rows do
				local cy = (r - 0.5) * canvasH / rows + (((col * 3 + r) % 3) - 1) * 30
				puff(2, x + ((r % 2) * 60), cy, frontD, 0.7 + feather, 0.5 + feather)
			end
			x += frontStep
		end
		if wasDrifting then
			startDrift()
		end
	end

	-- edgeX nil = nothing left to hide. update() with animate rolls the band back.
	local function update(info)
		local edgeX = info.edgeX
		local show = edgeX ~= nil
		band.Visible = show
		hint.Visible = show
		local t = info.teaser
		teaser.Visible = t ~= nil
		if t then
			teaser.Position = UDim2.fromOffset(t.x, t.y)
			teaser.Size = UDim2.fromOffset(t.size * 1.5, t.size * 1.5)
		end
		if not show then
			edgeTarget = nil
			return
		end
		hint.Position = UDim2.fromOffset((info.hintX or edgeX) - edgeX + 40, info.hintY or lastH * 0.5)
		if edgeTween then
			edgeTween:Cancel()
			edgeTween = nil
		end
		local goal = UDim2.fromOffset(edgeX, 0)
		if info.animate and edgeTarget ~= nil then
			-- teaser faded in again after the band rolls back
			hint.TextTransparency = 1
			hint.BackgroundTransparency = 1
			hintStroke.Transparency = 1
			hint.TextStrokeTransparency = 1
			local d = 1.2 / math.max(deps.pace(), 0.1)
			edgeTween = TweenService:Create(band, TweenInfo.new(d, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = goal })
			edgeTween:Play()
			local fadeIn = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, d * 0.7)
			TweenService:Create(hint, fadeIn, { TextTransparency = 0, BackgroundTransparency = 0.1, TextStrokeTransparency = 0.5 }):Play()
			TweenService:Create(hintStroke, fadeIn, { Transparency = 0 }):Play()
		else
			band.Position = goal
			hint.TextTransparency = 0
			hint.BackgroundTransparency = 0.1
			hint.TextStrokeTransparency = 0.5
			hintStroke.Transparency = 0
		end
		edgeTarget = edgeX
	end

	return {
		layout = layout,
		update = update,
		startDrift = startDrift,
		stopDrift = stopDrift,
		getEdge = function()
			return edgeTarget
		end,
	}
end
