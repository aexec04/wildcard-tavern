--[[
	Client/PanelFullScreen.lua
	Collection, Card Sets, Badges, Legend, Flair and Stats open as full-screen scenes like the Tavern Map (Engine/PanelLayout.FULL_SCREEN).
	PanelTabs.attach calls apply(backdrop, panel) for them: the panel fills the screen below the tab strip, its outer border, corner
	radius and shadow are gone, the backdrop is opaque, and a panel that sets its own Size or Position (a painted room, the Expand toggle)
	is put back at once. The corner dock is hidden by PanelTabs while the page is open. Painted scenes are cover-fitted into the panel,
	so they fill the screen without stretching.

	apply(backdrop, panel)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PanelLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PanelLayout"))

local PanelFullScreen = {}

local DECOR = { Shadow = true, SetSkinBorder = true, InnerRim = true, CornerStud = true, Brackets = true, BracketH = true, BracketV = true }

local function hideDecor(c)
	c.Visible = false
	if not c:GetAttribute("FullScreenGuard") then
		c:SetAttribute("FullScreenGuard", true)
		-- popIn, popOut and SetSkin may switch the old windowed decoration back on: keep it off for the life of the panel
		c:GetPropertyChangedSignal("Visible"):Connect(function()
			if c.Visible then c.Visible = false end
		end)
	end
end

local function flatten(panel)
	for _, c in ipairs(panel:GetChildren()) do
		if c:IsA("UIStroke") then
			c.Enabled = false
		elseif c:IsA("UICorner") then
			c.CornerRadius = UDim.new(0, 0)
		elseif c:IsA("UISizeConstraint") then
			c.MaxSize = Vector2.new(math.huge, math.huge)
			c.MinSize = Vector2.new(0, 0)
		elseif DECOR[c.Name] then
			hideDecor(c)
		end
	end
end

-- True once apply() has taken the panel: from then on its size and position are the screen's, not the module's own.
function PanelFullScreen.owns(panel)
	return panel ~= nil and panel:GetAttribute("FullScreenPanel") == true
end

-- A panel's own layout computes its windowed size (w, h) from the screen; a full screen panel uses the real screen below the tab strip.
function PanelFullScreen.fit(panel, w, h, screenW, screenH)
	if PanelFullScreen.owns(panel) and (screenW or 0) > 0 and (screenH or 0) > 0 then
		local r = PanelLayout.fullScreenRect(screenW, screenH)
		return r.w, r.h
	end
	return w, h
end

-- The size a full screen page lays out for: its backdrop (the frame that fills the screen, which Studio's scale:WxH shrinks to a real
-- pixel size), not the whole window. Falls back to `fallback` (a Vector2 with X and Y) when the backdrop has no size yet.
function PanelFullScreen.screenSize(panel, fallback)
	local backdrop = panel and panel.Parent
	local size = backdrop and backdrop.AbsoluteSize
	if size and (size.X or 0) > 0 and (size.Y or 0) > 0 then return { X = size.X, Y = size.Y } end
	return fallback
end

-- Every windowed Size/Position write goes through here: a full screen panel keeps the rect apply() gave it (writing the windowed size and
-- letting force() undo it later made layouts measure a transient size and paint at about 66 percent of the screen).
function PanelFullScreen.setRect(panel, size, position)
	if PanelFullScreen.owns(panel) then return false end
	if size then panel.Size = size end
	if position then panel.Position = position end
	return true
end

-- Studio only: one frame after a full screen panel opens, its size and its direct art children must match the screen below the tab strip.
local ART = { "PanelArt", "Wall", "Scrim", "Room", "Scene" }
local function audit(name, backdrop, panel)
	local okRs, RunService = pcall(function() return game:GetService("RunService") end)
	if not okRs or not RunService:IsStudio() then return end
	task.defer(function()
		task.wait(); task.wait() -- after heal() has measured and added its gap
		if not backdrop.Visible then return end
		local top = PanelLayout.fullScreenRect(0, 0).y
		local extra = panel:GetAttribute("FullScreenExtra") or 0 -- height heal() added so the bottom reaches the ScreenGui
		local want = Vector2.new(backdrop.AbsoluteSize.X, backdrop.AbsoluteSize.Y - top + extra)
		local function off(a, b) return math.abs(a.X - b.X) > 2 or math.abs(a.Y - b.Y) > 2 end
		local function report(child, got, expect)
			warn(string.format("[FullScreen] mismatch %s %s %dx%d vs %dx%d", name, child, got.X, got.Y, expect.X, expect.Y))
		end
		if off(panel.AbsoluteSize, want) then report("panel", panel.AbsoluteSize, want) end
		local gui = backdrop:FindFirstAncestorOfClass("ScreenGui")
		if gui then -- the measured rectangle of every full screen page, so Collection, Flair, Badges and the rest report like Card Sets
			local H = gui.AbsoluteSize.Y
			local topY = panel.AbsolutePosition.Y - gui.AbsolutePosition.Y
			local bottom = topY + panel.AbsoluteSize.Y
			print(string.format("[PanelFit] %s screen=%dx%d panel=%dx%d top=%d bottom=%d fits=%s", name, math.floor(gui.AbsoluteSize.X), math.floor(H),
				math.floor(panel.AbsoluteSize.X), math.floor(panel.AbsoluteSize.Y), math.floor(topY), math.floor(bottom), tostring(bottom <= H + 1 and topY >= PanelLayout.STRIP_BOTTOM)))
		end
		for _, c in ipairs(panel:GetChildren()) do
			if c:IsA("GuiObject") then
				if DECOR[c.Name] and c.Visible then warn("[FullScreen] decor visible " .. name .. " " .. c.Name) end
				for _, key in ipairs(ART) do
					if string.find(c.Name, key, 1, true) == 1 and c.Visible and c.AbsoluteSize.X > 0 and off(c.AbsoluteSize, panel.AbsoluteSize) then
						report(c.Name, c.AbsoluteSize, panel.AbsoluteSize)
					end
				end
			end
		end
	end)
end

function PanelFullScreen.apply(backdrop, panel, name)
	if panel:GetAttribute("FullScreenPanel") then return end
	panel:SetAttribute("FullScreenPanel", true)
	panel.ChildAdded:Connect(function(c) -- a Shadow added after the panel opened for the first time
		if DECOR[c.Name] and c:IsA("GuiObject") then hideDecor(c) end
	end)
	local top = PanelLayout.fullScreenRect(0, 0).y
	local forcing = false
	local extra = 0 -- pixels added to the height so the bottom edge reaches the bottom of the ScreenGui (see heal)
	local function force()
		if forcing then return end
		forcing = true
		backdrop.BackgroundTransparency = 0
		backdrop.BackgroundColor3 = Color3.fromRGB(26, 20, 14)
		panel.AnchorPoint = Vector2.new(0, 0)
		panel.Position = UDim2.fromOffset(0, top)
		panel.Size = UDim2.new(1, 0, 1, -top + extra)
		panel:SetAttribute("FullScreenExtra", extra)
		flatten(panel)
		forcing = false
	end
	force()
	-- The panel is (screen height - top) tall, but in Studio the backdrop's absolute top can sit above the GUI origin, leaving a dark band
	-- under the painting. One frame after opening, measure the panel's bottom against the ScreenGui and add the missing height.
	local function heal()
		local gui = backdrop:FindFirstAncestorOfClass("ScreenGui")
		if not gui or not backdrop.Visible then return end
		local gap = PanelLayout.fullScreenGap(gui.AbsoluteSize.Y, panel.AbsolutePosition.Y, panel.AbsoluteSize.Y)
		if gap > 0 then
			extra = extra + gap
			force()
		end
	end
	for _, prop in ipairs({ "Size", "Position", "AnchorPoint" }) do
		panel:GetPropertyChangedSignal(prop):Connect(function()
			if forcing then return end
			if panel.Size ~= UDim2.new(1, 0, 1, -top + extra) or panel.Position ~= UDim2.fromOffset(0, top) or panel.AnchorPoint ~= Vector2.new(0, 0) then
				task.defer(force)
			end
		end)
	end
	-- the ScreenGui counts the full screen pages that are open (attribute FullScreenOpen); DailyStrip hides while the count is above 0
	local counted = false
	local function count()
		local gui = backdrop.Parent
		while gui and gui.ClassName ~= "ScreenGui" do gui = gui.Parent end
		if not gui then return end
		local on = backdrop.Visible == true
		if on == counted then return end
		counted = on
		local cur = gui:GetAttribute("FullScreenOpen")
		gui:SetAttribute("FullScreenOpen", math.max(0, (type(cur) == "number" and cur or 0) + (on and 1 or -1))) -- the Tavern Map sets true: never add to a boolean
	end
	count()
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		count()
		if backdrop.Visible then
			force()
			task.defer(function() task.wait(); pcall(heal) end)
			audit(name or panel.Name, backdrop, panel)
		end
	end)
end

return PanelFullScreen
