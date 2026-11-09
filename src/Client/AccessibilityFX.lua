--[[
	Client/AccessibilityFX.lua
	Larger Text (Settings): every TextLabel, TextButton and TextBox under the main ScreenGui is drawn at
	Accessibility.TEXT_SCALE (1.15) times the size its own module gave it, but never taller than its label can hold
	(Engine/Accessibility.scaledTextSize), so nothing clips and a tight label simply stays as it was.
	  * the original size is remembered in the "BaseTextSize" attribute; if some module changes TextSize later the
	    new value becomes the base, so dynamic labels keep working;
	  * new labels are scaled as they appear (DescendantAdded, deferred one frame so the layout has run);
	  * turning the option off restores every label; the player-facing 14px floor is unaffected.
	init(screenGui) once from the hub.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Accessibility = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Accessibility"))
local ClientSettings = require(script.Parent.ClientSettings)

local AccessibilityFX = {}

local function isText(obj)
	return obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")
end

-- Sets one label to the scaled (or restored) size.
local function apply(obj, scale)
	if not obj.Parent then
		return
	end
	local base = obj:GetAttribute("BaseTextSize")
	local last = obj:GetAttribute("ScaledTextSize")
	if base == nil or (last ~= nil and obj.TextSize ~= last) then
		base = obj.TextSize -- first sight, or a module changed the size itself
		obj:SetAttribute("BaseTextSize", base)
	end
	local fit = obj.AutomaticSize == Enum.AutomaticSize.None and obj.AbsoluteSize.Y or 0
	local target = Accessibility.scaledTextSize(base, scale, fit)
	obj:SetAttribute("ScaledTextSize", target)
	if obj.TextSize ~= target then
		obj.TextSize = target
	end
end

function AccessibilityFX.init(screenGui)
	local connection = nil

	local function sweep()
		local scale = Accessibility.textScale({ largerText = ClientSettings.getRaw("largerText") })
		for _, obj in ipairs(screenGui:GetDescendants()) do
			if isText(obj) and (scale > 1 or obj:GetAttribute("BaseTextSize") ~= nil) then
				pcall(apply, obj, scale)
			end
		end
	end

	local function watch(on)
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if on then
			connection = screenGui.DescendantAdded:Connect(function(obj)
				if isText(obj) then
					task.defer(function()
						pcall(apply, obj, Accessibility.TEXT_SCALE)
					end)
				end
			end)
		end
	end

	ClientSettings.onChanged(function(key)
		if key == "largerText" then
			watch(ClientSettings.getRaw("largerText") == true)
			sweep()
		end
	end)
	if ClientSettings.getRaw("largerText") == true then
		watch(true)
		sweep()
	end
end

return AccessibilityFX
