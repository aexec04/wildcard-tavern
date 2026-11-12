--[[
	Shared/Tests/FakeGui.lua
	Test helper: a tiny fake of the Roblox GUI API, enough to run a Client module's REAL builder in the plain Lua runner (no
	Roblox, no Rojo) and then inspect the instances it made. Used by the Tavern Map layer tests (Tests/MapScene.lua).

	FakeGui.new(class) -> instance      a fake Instance: parent tree, property-changed signals, event signals, attributes. GuiObject
	                                    classes start with ZIndex 1 and Visible true, like the real ones.
	FakeGui.env(opts) -> env, state     the globals for a Client chunk: Instance, UDim, UDim2, Vector2, Color3, ColorSequence,
	                                    NumberSequence (more than 20 keypoints, a first time other than 0 or a last other than 1
	                                    errors, like Roblox), TweenInfo, Enum, math.clamp, typeof, task, warn, print, game:GetService
	                                    and require/script.Parent.<Name> backed by opts.stubs[<Name>].
	                                    opts.studio is what RunService:IsStudio() answers; state.warns / state.prints collect output
	                                    and state.studio can be flipped later.
	FakeGui.folder(map) -> object       a stand-in for the Engine folder: folder:WaitForChild(name) is require()-able to map[name]
	FakeGui.load(path, env) -> result   runs a Client file under env and returns what it returns. The Luau-only "x += y" lines are
	                                    rewritten to "x = x + y" first, because plain Lua 5.3 cannot parse them.
	FakeGui.drawOrder(root) -> list, rank
	                                    every GuiObject under root, bottom to top, the way a ScreenGui with ZIndexBehavior.Global
	                                    draws them: by ABSOLUTE ZIndex (a child never inherits its parent's), ties by tree order
	                                    (a descendant and a later sibling draw on top). rank[instance] is its place in the list.
]]

local FakeGui = {}

local GUI = {
	Frame = true, ImageLabel = true, ImageButton = true, TextLabel = true, TextButton = true,
	ScrollingFrame = true, ViewportFrame = true, CanvasGroup = true, VideoFrame = true,
}
FakeGui.GUI_CLASSES = GUI

local EVENTS = {
	MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, MouseButton2Click = true, MouseEnter = true,
	MouseLeave = true, MouseMoved = true, InputBegan = true, InputEnded = true, InputChanged = true, Activated = true,
	TouchTap = true, ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true,
	AncestryChanged = true, Changed = true, Destroying = true, FocusLost = true, Focused = true,
	MouseWheelForward = true, MouseWheelBackward = true,
}

local function newSignal()
	local s = { handlers = {} }
	function s:Connect(fn)
		local h = { fn = fn, on = true }
		self.handlers[#self.handlers + 1] = h
		return { Connected = true, Disconnect = function() h.on = false end }
	end
	function s:Once(fn)
		local conn
		conn = self:Connect(function(...)
			conn.Disconnect()
			fn(...)
		end)
		return conn
	end
	function s:Fire(...)
		for _, h in ipairs(self.handlers) do
			if h.on then h.fn(...) end
		end
	end
	return s
end
FakeGui.signal = newSignal

-- ===== Instances =====
local Methods = {}
local meta = {}

local function signalOf(inst, key)
	local signals = rawget(inst, "_signals")
	if not signals[key] then signals[key] = newSignal() end
	return signals[key]
end

meta.__index = function(inst, key)
	local v = rawget(inst, "_props")[key]
	if v ~= nil then return v end
	if key == "ClassName" then return rawget(inst, "_class") end
	if key == "Parent" then return rawget(inst, "_parent") end
	if Methods[key] then return Methods[key] end
	if EVENTS[key] then return signalOf(inst, "event:" .. key) end
	return nil
end

local NO_ENABLED = { UIListLayout = true, UIGridLayout = true, UIPageLayout = true, UITableLayout = true }

meta.__newindex = function(inst, key, value)
	if key == "Parent" then
		local old = rawget(inst, "_parent")
		if old == value then return end
		if old then
			local kids = rawget(old, "_kids")
			for i, kid in ipairs(kids) do
				if kid == inst then table.remove(kids, i) break end
			end
		end
		rawset(inst, "_parent", value)
		if value then table.insert(rawget(value, "_kids"), inst) end
		return
	end
	local props = rawget(inst, "_props")
	-- like Roblox: list, grid and page layouts have no Enabled (only UIStroke, UIGradient and the like do)
	if key == "Enabled" and NO_ENABLED[rawget(inst, "_class")] then
		error("Enabled is not a valid member of " .. rawget(inst, "_class"), 2)
	end
	if props[key] == value then return end
	props[key] = value
	local signal = rawget(inst, "_signals")["prop:" .. key]
	if signal then signal:Fire() end
end

function Methods.GetChildren(inst)
	local out = {}
	for i, kid in ipairs(rawget(inst, "_kids")) do out[i] = kid end
	return out
end

function Methods.GetDescendants(inst)
	local out = {}
	local function walk(node)
		for _, kid in ipairs(rawget(node, "_kids")) do
			out[#out + 1] = kid
			walk(kid)
		end
	end
	walk(inst)
	return out
end

function Methods.Destroy(inst)
	Methods.ClearAllChildren(inst)
	inst.Parent = nil
	rawset(inst, "_destroyed", true)
end

function Methods.ClearAllChildren(inst)
	for _, kid in ipairs(Methods.GetChildren(inst)) do Methods.Destroy(kid) end
end

function Methods.FindFirstChild(inst, name, recursive)
	for _, kid in ipairs(rawget(inst, "_kids")) do
		if kid.Name == name then return kid end
	end
	if recursive then
		for _, kid in ipairs(rawget(inst, "_kids")) do
			local found = Methods.FindFirstChild(kid, name, true)
			if found then return found end
		end
	end
	return nil
end

function Methods.WaitForChild(inst, name) return Methods.FindFirstChild(inst, name) end

function Methods.FindFirstChildOfClass(inst, class)
	for _, kid in ipairs(rawget(inst, "_kids")) do
		if rawget(kid, "_class") == class then return kid end
	end
	return nil
end

function Methods.IsA(inst, class)
	local own = rawget(inst, "_class")
	return own == class or class == "Instance" or (class == "GuiObject" and GUI[own] == true)
end

function Methods.IsAncestorOf(inst, other)
	local p = other and rawget(other, "_parent")
	while p do
		if p == inst then return true end
		p = rawget(p, "_parent")
	end
	return false
end

function Methods.IsDescendantOf(inst, other) return Methods.IsAncestorOf(other, inst) end

function Methods.GetPropertyChangedSignal(inst, name) return signalOf(inst, "prop:" .. name) end
function Methods.SetAttribute(inst, key, value)
	local attrs = rawget(inst, "_attrs")
	local changed = attrs[key] ~= value
	attrs[key] = value
	if changed then signalOf(inst, "attr:" .. key):Fire() end
end
function Methods.GetAttributeChangedSignal(inst, name) return signalOf(inst, "attr:" .. name) end
function Methods.GetAttribute(inst, key) return rawget(inst, "_attrs")[key] end

function FakeGui.new(class)
	local inst = setmetatable({ _class = class, _kids = {}, _props = { Name = class }, _signals = {}, _attrs = {} }, meta)
	local props = rawget(inst, "_props")
	if GUI[class] then
		props.ZIndex, props.Visible = 1, true
		-- like Roblox, a GuiObject that has not been laid out yet reports zero (never nil): FakeGui.layout or a test sets real numbers
		props.AbsoluteSize, props.AbsolutePosition = { X = 0, Y = 0 }, { X = 0, Y = 0 }
		if class == "ScrollingFrame" then
			props.AbsoluteWindowSize, props.CanvasPosition = { X = 0, Y = 0 }, { X = 0, Y = 0 }
		elseif class == "TextLabel" or class == "TextButton" then
			props.TextBounds = { X = 0, Y = 0 }
		end
	elseif class == "UIListLayout" or class == "UIGridLayout" then
		props.AbsoluteContentSize = { X = 0, Y = 0 }
	end
	return inst
end

-- ===== Value types and services =====
local function udim(s, o) return { Scale = s or 0, Offset = o or 0 } end
local UDim2 = {}
local udim2Meta = {} -- UDim2 + UDim2 and UDim2 - UDim2 work in Roblox ("pos + UDim2.fromOffset(0, 3)")
function UDim2.new(xs, xo, ys, yo)
	if type(xs) == "table" then return setmetatable({ X = xs, Y = xo }, udim2Meta) end
	return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo) }, udim2Meta)
end
udim2Meta.__add = function(a, b)
	return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
udim2Meta.__sub = function(a, b)
	return UDim2.new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
function UDim2.fromOffset(x, y) return UDim2.new(0, x, 0, y) end
function UDim2.fromScale(x, y) return UDim2.new(x, 0, y, 0) end

local function sequence(what)
	return {
		new = function(a, b)
			if type(a) ~= "table" then
				return { Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = b == nil and a or b } } }
			end
			if #a > 20 then error(what .. ": too many keypoints (" .. #a .. ", the limit is 20)", 2) end
			if #a < 2 then error(what .. ": needs at least 2 keypoints", 2) end
			if a[1].Time ~= 0 then error(what .. ": the first keypoint must be at time 0", 2) end
			if a[#a].Time ~= 1 then error(what .. ": the last keypoint must be at time 1", 2) end
			for i = 2, #a do
				if a[i].Time < a[i - 1].Time then error(what .. ": keypoint times must not decrease", 2) end
			end
			return { Keypoints = a }
		end,
	}
end

function FakeGui.env(opts)
	opts = opts or {}
	local stubs = opts.stubs or {}
	if stubs.CloseX == nil then -- the shared round X: a 44 px "CloseX" button in the panel's top right, like Client/CloseX
		stubs.CloseX = {
			retire = function(old) if old then old.Visible = false end end,
			attach = function(panel, onClose, o)
				o = o or {}
				local inset = o.inset or 8
				local b = FakeGui.new("TextButton")
				b.Name = "CloseX"
				b.Size = UDim2.new(0, 44, 0, 44)
				b.AnchorPoint = { X = 1, Y = 0 }
				b.Position = UDim2.new(1, -inset, 0, o.top or inset)
				b.Parent = panel
				b.MouseButton1Click:Connect(onClose)
				return b
			end,
		}
	end
	local state = { warns = {}, prints = {}, studio = opts.studio == true, services = {}, delays = {}, parked = {} }
	-- resume every thread parked at a task.wait once
	function state.runWaiting()
		local list = state.parked
		state.parked = {}
		for _, co in ipairs(list) do
			local ok, err = coroutine.resume(co)
			if not ok then error(err, 0) end
			if coroutine.status(co) == "suspended" then state.parked[#state.parked + 1] = co end
		end
		return #list
	end
	-- run (and clear) the task.delay callbacks queued so far; callbacks they queue wait for the next call
	function state.runDelays()
		local list = state.delays
		state.delays = {}
		for _, d in ipairs(list) do d.fn(table.unpack(d.args)) end
		return #list
	end
	local services = state.services
	services.TweenService = {
		Create = function(_, inst, info, goal)
			return { Play = function() end, Cancel = function() end, Pause = function() end, Completed = newSignal(), instance = inst, goal = goal }
		end,
	}
	services.RunService = {
		IsStudio = function() return state.studio end,
		RenderStepped = newSignal(), Heartbeat = newSignal(), Stepped = newSignal(),
	}
	services.UserInputService = { InputBegan = newSignal(), InputChanged = newSignal(), InputEnded = newSignal() }
	services.ReplicatedStorage = FakeGui.new("Folder")
	services.Players = {}

	local function vec(x, y) return { X = x or 0, Y = y or 0 } end
	local env = {
		Instance = { new = FakeGui.new },
		UDim = { new = udim },
		UDim2 = UDim2,
		Vector2 = { new = vec, zero = vec(0, 0) },
		Color3 = {
			fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end,
			new = function(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end,
		},
		ColorSequence = (function()
			local seq = sequence("ColorSequence")
			local build = seq.new
			seq.new = function(a, b)
				if type(a) == "table" and a.R ~= nil then -- a single Color3: two equal keypoints
					return { Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = a } } }
				end
				return build(a, b)
			end
			return seq
		end)(),
		ColorSequenceKeypoint = { new = function(t, c) return { Time = t, Value = c } end },
		NumberSequence = sequence("NumberSequence"),
		NumberSequenceKeypoint = { new = function(t, v, envelope) return { Time = t, Value = v, Envelope = envelope } end },
		TweenInfo = { new = function(...) return { ... } end },
		Enum = setmetatable({}, { __index = function(_, a)
			return setmetatable({}, { __index = function(_, b) return "Enum." .. a .. "." .. b end })
		end }),
		math = setmetatable({ clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end }, { __index = math }),
		typeof = function(v)
			if type(v) == "table" and rawget(v, "_class") ~= nil then return "Instance" end
			return type(v)
		end,
		task = {
			defer = function(fn, ...) fn(...) end,
			-- spawn runs at once until the first task.wait, where the thread parks (like Roblox) until a test calls state.runWaiting()
			spawn = function(fn, ...)
				local co = coroutine.create(fn)
				local ok, err = coroutine.resume(co, ...)
				if not ok then error(err, 0) end
				if coroutine.status(co) == "suspended" then state.parked[#state.parked + 1] = co end
			end,
			-- delayed calls wait in state.delays until a test runs them with state.runDelays()
			delay = function(t, fn, ...)
				state.delays[#state.delays + 1] = { t = t, fn = fn, args = { ... } }
			end,
			wait = function(t)
				if coroutine.isyieldable() then coroutine.yield() end
				return t or 0
			end,
		},
		warn = function(...)
			local parts = {}
			for i, v in ipairs({ ... }) do parts[i] = tostring(v) end
			state.warns[#state.warns + 1] = table.concat(parts, " ")
		end,
		print = function(...)
			local parts = {}
			for i, v in ipairs({ ... }) do parts[i] = tostring(v) end
			state.prints[#state.prints + 1] = table.concat(parts, " ")
		end,
		game = { GetService = function(_, name) return services[name] or {} end },
		script = { Parent = setmetatable({}, { __index = function(_, name) return { __module = stubs[name], __name = name } end }) },
		require = function(m)
			if type(m) == "table" and m.__name ~= nil then
				if m.__module == nil then error("FakeGui: no stub for script.Parent." .. m.__name, 2) end
				return m.__module
			end
			error("FakeGui: unsupported require() target", 2)
		end,
	}
	return setmetatable(env, { __index = _G }), state
end

-- folder:WaitForChild(name) -> something require() accepts, backed by map[name]
function FakeGui.folder(map)
	return {
		WaitForChild = function(_, name) return { __module = map[name], __name = name } end,
		FindFirstChild = function(_, name) return { __module = map[name], __name = name } end,
	}
end

-- Plain Lua 5.3 cannot parse Luau's compound assignment. Only whole-line "name += expr" statements exist in the Client files
-- this is used on, so rewrite exactly those.
local function plainLua(src)
	local out = {}
	for raw in (src .. "\n"):gmatch("(.-)\n") do
		local line = raw
		local indent, target, op, rest = line:match("^(%s*)([%w_%.]+)%s*([%+%-%*/])=%s*(.-)%s*$")
		if indent then
			line = indent .. target .. " = " .. target .. " " .. op .. " (" .. rest .. ")"
		end
		out[#out + 1] = line
	end
	return table.concat(out, "\n")
end

FakeGui.plainLua = plainLua

function FakeGui.load(path, env)
	assert(io and io.open, "FakeGui.load needs io.open (local runner only), missing for " .. tostring(path) .. "; guard the test with 'if not (io and io.open) then return end'")
	local f = assert(io.open(path, "r"))
	local src = f:read("*a")
	f:close()
	local chunk, err = load(plainLua(src), "@" .. path, "t", env)
	if not chunk then error("FakeGui.load " .. path .. ": " .. tostring(err), 2) end
	return chunk()
end

-- ===== A tiny layout: AbsolutePosition and AbsoluteSize from Position, Size and AnchorPoint (no UI constraints, no lists) =====
function FakeGui.layout(root, width, height)
	local function same(a, b) return a ~= nil and a.X == b.X and a.Y == b.Y end
	local function go(node, px, py, pw, ph)
		for _, kid in ipairs(rawget(node, "_kids")) do
			if GUI[rawget(kid, "_class")] then
				local size = kid.Size or { X = udim(0, 0), Y = udim(0, 0) }
				local pos = kid.Position or { X = udim(0, 0), Y = udim(0, 0) }
				local anchor = kid.AnchorPoint or { X = 0, Y = 0 }
				local w = size.X.Scale * pw + size.X.Offset
				local h = size.Y.Scale * ph + size.Y.Offset
				local x = px + pos.X.Scale * pw + pos.X.Offset - anchor.X * w
				local y = py + pos.Y.Scale * ph + pos.Y.Offset - anchor.Y * h
				if not same(kid.AbsolutePosition, { X = x, Y = y }) then kid.AbsolutePosition = { X = x, Y = y } end
				if not same(kid.AbsoluteSize, { X = w, Y = h }) then kid.AbsoluteSize = { X = w, Y = h } end
				go(kid, x, y, w, h)
			else
				go(kid, px, py, pw, ph)
			end
		end
	end
	go(root, 0, 0, width, height)
end

-- ===== What a click at (x, y) reaches, the way Roblox hit-tests it =====
-- The topmost visible GuiObject under the point that sinks input receives it: a button always does, a ScrollingFrame does unless
-- Active = false, a Frame or label only with Active = true. A transparent object sinks just the same. nil = nothing.
function FakeGui.hit(root, x, y)
	local order = FakeGui.drawOrder(root)
	for i = #order, 1, -1 do
		local o = order[i]
		local pos, size = o.AbsolutePosition, o.AbsoluteSize
		if pos and size and x >= pos.X and x <= pos.X + size.X and y >= pos.Y and y <= pos.Y + size.Y then
			local visible, p = true, o
			while p and GUI[rawget(p, "_class")] do
				if p.Visible == false then visible = false break end
				p = rawget(p, "_parent")
			end
			if visible then
				local class, active = rawget(o, "_class"), o.Active
				if active == nil then active = class == "TextButton" or class == "ImageButton" or class == "ScrollingFrame" end
				if active then return o end
			end
		end
	end
	return nil
end

-- ===== The Global draw order =====
function FakeGui.drawOrder(root)
	local list, n = {}, 0
	local function walk(node)
		for _, kid in ipairs(rawget(node, "_kids")) do
			if GUI[rawget(kid, "_class")] then
				n = n + 1
				list[#list + 1] = { inst = kid, z = kid.ZIndex, n = n }
			end
			walk(kid)
		end
	end
	walk(root)
	table.sort(list, function(a, b)
		if a.z ~= b.z then return a.z < b.z end
		return a.n < b.n
	end)
	local out, rank = {}, {}
	for i, entry in ipairs(list) do
		out[i] = entry.inst
		rank[entry.inst] = i
	end
	return out, rank
end

return FakeGui
