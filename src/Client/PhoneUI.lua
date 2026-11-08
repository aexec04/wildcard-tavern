--[[
	PhoneUI: touch/phone pass (rules in Engine/PhoneLayout, tested).
	On touch devices only:
	  - the ScreenGui respects the device safe area (notch / rounded corners),
	  - text below 14px is raised to 14px,
	  - fixed-pixel buttons smaller than 44px are grown to 44px around their center
	    (skipped inside grid layouts and for auto-sized or scale-sized buttons).
	Desktop is untouched. Hover stays a bonus: every hover effect in the game
	sits on a button that also works on tap.
]]

local UserInputService = game:GetService("UserInputService")

local PhoneLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PhoneLayout"))

local PhoneUI = {}

function PhoneUI.isTouch()
	return UserInputService.TouchEnabled
end

local function fixText(obj)
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		if not obj.TextScaled then
			local want = PhoneLayout.textSize(obj.TextSize, true)
			if want ~= obj.TextSize then
				obj.TextSize = want
			end
		end
	end
end

local function fixTap(obj)
	if not (obj:IsA("TextButton") or obj:IsA("ImageButton")) then
		return
	end
	if obj.AutomaticSize ~= Enum.AutomaticSize.None then
		return
	end
	local parent = obj.Parent
	if parent and parent:FindFirstChildWhichIsA("UIGridLayout") then
		return
	end
	local size = obj.Size
	if size.X.Scale ~= 0 or size.Y.Scale ~= 0 then
		return
	end
	local w, h = size.X.Offset, size.Y.Offset
	if w < 8 or h < 8 then
		return -- decorative or hidden hit areas
	end
	local nw, nh = PhoneLayout.tapSize(w, h, true)
	if nw == w and nh == h then
		return
	end
	obj.Size = UDim2.new(0, nw, 0, nh)
	local inList = parent and parent:FindFirstChildWhichIsA("UIListLayout")
	if not inList then
		local dx, dy = PhoneLayout.growShift(w, h, nw, nh, obj.AnchorPoint.X, obj.AnchorPoint.Y)
		local p = obj.Position
		obj.Position = UDim2.new(p.X.Scale, p.X.Offset + dx, p.Y.Scale, p.Y.Offset + dy)
	end
end

local function fix(obj)
	fixText(obj)
	fixTap(obj)
end

-- Call once with the main ScreenGui. Returns true when the touch pass is active.
function PhoneUI.install(gui)
	if not PhoneUI.isTouch() then
		return false
	end
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	for _, d in ipairs(gui:GetDescendants()) do
		pcall(fix, d)
	end
	gui.DescendantAdded:Connect(function(d)
		-- Wait a frame so the creator has finished setting Size and TextSize.
		task.defer(function()
			if d.Parent then
				pcall(fix, d)
			end
		end)
	end)
	return true
end

return PhoneUI
