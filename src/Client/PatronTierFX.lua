--[[
	Client/PatronTierFX.lua
	Gameplay v2 Patron tier look, native UI over the cut card (Engine/PatronTierStyle holds every number): a tier frame whose SHAPE
	differs (plain wood, silver trim, studded steel, crown notch, full gold), taller or wider for Epic and Legendary (it grows
	upward, the slot never moves), a halo, light rays and sparks for the top tiers, and a big power numeral on a gold disc at the
	bottom centre. Everything is a Frame, UICorner, UIStroke or text, parented to the card's slot so it survives a clone.
	Motion (Rare pulse 3 s, Epic sparks, Legendary rays and a shimmer sweep every 5 s) runs on the shared FxLoop heartbeat, never a
	per tick tween, and is static in Calm mode, Reduce motion and Fast speed.

	set(slot, tier, valueText)   build or update the deco for the slot's current size
	clear(slot)                  hide it (an empty seat)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PatronTierStyle"))
local FxLoop = require(script.Parent.FxLoop)
local Kit = require(script.Parent.TavernKit)

local M = {}

local Z_BEHIND, Z_FRAME, Z_DISC = 2, 14, 16

local function c3(t) return Color3.fromRGB(t[1], t[2], t[3]) end

local function frame(parent, name, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function corner(f, r)
	local u = Instance.new("UICorner")
	u.CornerRadius = r
	u.Parent = f
end

local function ring(parent, name, color, thickness, trans, z, radius)
	local f = frame(parent, name, z)
	f.Size = UDim2.fromScale(1, 1)
	corner(f, UDim.new(0, radius or 12))
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = trans
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	return f, s
end

local function dot(parent, name, size, color, z)
	local f = frame(parent, name, z)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0
	corner(f, UDim.new(1, 0))
	return f
end

local running = setmetatable({}, { __mode = "k" }) -- deco -> loop handle

local function stopLoop(deco)
	local h = running[deco]
	if h then h.cancel(); running[deco] = nil end
end

local function build(deco, tier, w)
	for _, ch in ipairs(deco:GetChildren()) do ch:Destroy() end
	stopLoop(deco)
	local s = Style.style(tier)
	local frameColor = c3(s.rgb)
	-- outer glow ring (soft, rounded, never a filled block)
	local glowStroke
	if s.glow > 0 then
		local glow
		glow, glowStroke = ring(deco, "Glow", frameColor, 6, 1 - s.glow * 0.5, Z_BEHIND + 1, 16)
		glow.Position = UDim2.fromOffset(-3, -3)
		glow.Size = UDim2.new(1, 6, 1, 6)
	end
	-- the frame itself: its thickness and colour are the tier's
	ring(deco, "Frame", frameColor, s.thickness, 0, Z_FRAME, 12)
	if s.trimRgb then
		local trim = ring(deco, "Trim", c3(s.trimRgb), 1, 0.15, Z_FRAME, 10)
		trim.Position = UDim2.fromOffset(s.thickness + 1, s.thickness + 1)
		trim.Size = UDim2.new(1, -2 * (s.thickness + 1), 1, -2 * (s.thickness + 1))
	end
	-- rare: corner studs
	if s.studs > 0 then
		local corners = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }
		for i = 1, math.min(s.studs, 4) do
			local d = dot(deco, "Stud" .. i, 9, c3(s.trimRgb), Z_FRAME + 1)
			d.Position = UDim2.new(corners[i][1], corners[i][1] == 0 and 4 or -4, corners[i][2], corners[i][2] == 0 and 4 or -4)
		end
	end
	-- epic: a crown notch on top (a gold diamond) and a halo behind the portrait
	if s.crown then
		local n = frame(deco, "CrownNotch", Z_FRAME + 1)
		n.AnchorPoint = Vector2.new(0.5, 0.5)
		n.Position = UDim2.new(0.5, 0, 0, 0)
		n.Size = UDim2.fromOffset(16, 16)
		n.Rotation = 45
		n.BackgroundTransparency = 0
		n.BackgroundColor3 = c3(s.trimRgb)
		local ns = Instance.new("UIStroke")
		ns.Color = c3(s.rgb)
		ns.Thickness = 2
		ns.Parent = n
	end
	if s.halo then
		local hr = ring(deco, "Halo", c3(s.trimRgb or s.rgb), 8, 0.78, Z_BEHIND, 40)
		hr.AnchorPoint = Vector2.new(0.5, 0.5)
		hr.Position = UDim2.fromScale(0.5, 0.45)
		hr.Size = UDim2.new(1.18, 0, 1.12, 0)
	end
	-- legendary: light rays behind the card and a shimmer lane inside it
	for i = 1, s.rays do
		local r = frame(deco, "Ray" .. i, Z_BEHIND)
		r.AnchorPoint = Vector2.new(0.5, 1)
		r.Position = UDim2.fromScale(0.5, 0.5)
		r.Size = UDim2.new(0, 3, 0.72, 0)
		r.Rotation = -70 + (140 / math.max(1, s.rays - 1)) * (i - 1)
		r.BackgroundTransparency = 0.72
		r.BackgroundColor3 = c3(s.trimRgb)
	end
	local shimmerBar
	if s.shimmer > 0 then
		local clip = frame(deco, "ShimmerClip", Z_FRAME + 1)
		clip.Size = UDim2.fromScale(1, 1)
		clip.ClipsDescendants = true
		corner(clip, UDim.new(0, 12))
		shimmerBar = frame(clip, "Shimmer", Z_FRAME + 1)
		shimmerBar.AnchorPoint = Vector2.new(0.5, 0.5)
		shimmerBar.Size = UDim2.new(0, 12, 1.6, 0)
		shimmerBar.Rotation = 20
		shimmerBar.BackgroundColor3 = c3(s.trimRgb)
		shimmerBar.BackgroundTransparency = 1
		shimmerBar.Position = UDim2.new(-0.2, 0, 0.5, 0)
	end
	-- sparks drift up in Epic and Legendary
	local sparks = {}
	for i = 1, s.sparks do
		local d = dot(deco, "Spark" .. i, 4, c3(s.trimRgb), Z_FRAME + 1)
		d.BackgroundTransparency = 0.3
		sparks[i] = d
		d.Position = UDim2.new((i - 0.5) / s.sparks, 0, 0.6, 0)
	end
	-- uncommon: a small green gem on the top edge; common: a dark wood cap hides the cut card's gold gem
	if s.gem then
		local g = frame(deco, "Gem", Z_FRAME + 1)
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.new(0.5, 0, 0, 0)
		g.Size = UDim2.fromOffset(14, 14)
		g.Rotation = 45
		g.BackgroundTransparency = 0
		g.BackgroundColor3 = c3(s.gem)
		local gs = Instance.new("UIStroke")
		gs.Color = c3(s.trimRgb or s.rgb)
		gs.Thickness = 2
		gs.Parent = g
	end
	if s.coverGem then
		local cap = frame(deco, "GemCover", Z_FRAME + 1)
		cap.AnchorPoint = Vector2.new(0.5, 0)
		cap.Position = UDim2.new(0.5, 0, 0, 0)
		cap.Size = UDim2.fromOffset(math.max(20, math.floor(w * 0.16)), math.max(10, math.floor(w * 0.08)))
		cap.BackgroundTransparency = 0
		cap.BackgroundColor3 = c3(s.rgb)
		corner(cap, UDim.new(0, 4))
	end
	-- the power disc sits in the card's bottom right corner, 40 percent over the frame; only the numeral is inside it
	local D = Style.discDiameter(w)
	local disc = frame(deco, "PowerDisc", Z_DISC)
	local dr = Style.discRect(w, 0)
	disc.AnchorPoint = Vector2.new(0, 0)
	disc.Position = UDim2.new(1, dr.x - w, 1, dr.y) -- bottom right corner, 40 percent outside the frame
	disc.Size = UDim2.fromOffset(D, D)
	disc.BackgroundTransparency = 0
	disc.ClipsDescendants = true -- whatever the text does, it never leaves the disc
	disc.BackgroundColor3 = c3(Style.DISC.fill)
	corner(disc, UDim.new(1, 0))
	local ds = Instance.new("UIStroke")
	ds.Color = c3(Style.DISC.ring)
	ds.Thickness = 2.5
	ds.Parent = disc
	local num = Instance.new("TextLabel")
	num.Name = "Numeral"
	num.BackgroundTransparency = 1
	num.Size = UDim2.fromScale(1, 1)
	num.Font = Enum.Font.Merriweather -- the numeral is serif, the unit word lives only in the pill below
	num.TextSize = D >= 40 and 20 or 16 -- fixed, never scaled: the figure is at most 5 characters (Style.numeral) and always fits
	num.TextTruncate = Enum.TextTruncate.None
	num.TextWrapped = false
	num.TextColor3 = c3(Style.DISC.text)
	num.TextTransparency = 0
	num.TextStrokeColor3 = c3(Style.DISC.outline)
	num.TextStrokeTransparency = 0.2
	num.TextScaled = false
	num.ZIndex = Z_DISC + 1
	num.Parent = disc

	-- motion on the shared heartbeat, none when still
	local moves = s.pulse > 0 or #sparks > 0 or shimmerBar ~= nil
	if moves and not Kit.still() then
		local t0 = os.clock()
		running[deco] = FxLoop.add(function(_, now)
			if not deco.Parent or Kit.still() then return true end -- Calm mode switched on: the loop ends
			local t = now - t0
			if s.pulse > 0 and glowStroke then -- Rare: period 3 s, alpha 0.15 to 0.35
				glowStroke.Transparency = 1 - (0.25 + 0.10 * math.sin(t * 2 * math.pi / s.pulse))
			end
			for i, d in ipairs(sparks) do -- Epic and Legendary: drift up, loop every 3 s, staggered
				local p = ((t / 3) + i / #sparks) % 1
				d.Position = UDim2.new((i - 0.5) / #sparks + 0.05 * math.sin(t + i), 0, 0.85 - 0.7 * p, 0)
				d.BackgroundTransparency = 0.3 + 0.7 * p
			end
			if shimmerBar then -- Legendary: one sweep every 5 s, 0.5 s long
				local p = (t % s.shimmer) / 0.5
				if p <= 1 then
					shimmerBar.Position = UDim2.new(-0.2 + 1.4 * p, 0, 0.5, 0)
					shimmerBar.BackgroundTransparency = 0.7
				else
					shimmerBar.BackgroundTransparency = 1
				end
			end
			return false
		end, 1 / 30)
	elseif glowStroke and s.pulse > 0 then
		glowStroke.Transparency = 1 - 0.25 -- still: the mid value
	end
end

function M.set(slot, tier, valueText)
	local key = tostring(tier or "common"):lower()
	local w, h = slot.AbsoluteSize.X, slot.AbsoluteSize.Y
	if w <= 0 or h <= 0 then return end
	local deco = slot:FindFirstChild("TierDeco")
	if not deco then
		deco = Instance.new("Frame")
		deco.Name = "TierDeco"
		deco.BackgroundTransparency = 1
		deco.BorderSizePixel = 0
		deco.Active = false
		deco.ZIndex = Z_BEHIND
		deco.ClipsDescendants = false
		deco.Parent = slot
	end
	deco.Visible = true
	local r = Style.frameRect(key, w, h)
	deco.Position = UDim2.fromOffset(r.x, r.y)
	deco.Size = UDim2.fromOffset(r.w, r.h)
	local sig = key .. ":" .. w .. ":" .. h
	if deco:GetAttribute("Sig") ~= sig then
		deco:SetAttribute("Sig", sig)
		build(deco, key, w)
	end
	local disc = deco:FindFirstChild("PowerDisc")
	local text = Style.numeral(valueText)
	if disc then
		disc.Visible = text ~= ""
		local num = disc:FindFirstChild("Numeral")
		if num then
			num.Text = text
			-- Studio only: the measured text must fit the disc (a wider string would be cut by the clip)
			if text ~= "" and game:GetService("RunService"):IsStudio() then
				task.defer(function()
					if num.Parent and num.TextBounds.X > disc.AbsoluteSize.X + 1 then
						warn(string.format("[PatronTierFX] disc text '%s' is %d px wide in a %d px disc", text, math.floor(num.TextBounds.X), math.floor(disc.AbsoluteSize.X)))
					end
				end)
			end
		end
	end
	-- Common reads slightly muted: the portrait is tinted a touch grey
	local art = slot:FindFirstChild("PatronArt", true)
	if art and art:IsA("ImageLabel") then art.ImageColor3 = c3(Style.style(key).tint) end
end

function M.clear(slot)
	local deco = slot:FindFirstChild("TierDeco")
	if deco then
		stopLoop(deco)
		deco.Visible = false
		deco:SetAttribute("Sig", nil)
	end
end

return M
