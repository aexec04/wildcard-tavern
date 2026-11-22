p = "src/Client/ChoicePanel.lua"
s = open(p).read()
a = s.index("\t\t-- Patron art is a full card with its name baked in at the bottom: show it enlarged")
b = s.index("\telseif choice.kind == \"modifier\" then")
new = '''\t\t-- The ring shows the portrait window of the cut card (Engine/DraftPortrait): no frame, no baked name, clipped to the ring
\t\tlocal crop = Instance.new("Frame")
\t\tcrop.Name = "PortraitCrop"
\t\tcrop.Size = UDim2.fromScale(1, 1)
\t\tcrop.BackgroundTransparency = 1
\t\tcrop.BorderSizePixel = 0
\t\tcrop.ClipsDescendants = true
\t\tcrop.ZIndex = 64
\t\tcrop.Parent = well
\t\tui.roundCorner(crop, 8)
\t\tlocal spec = DraftPortrait.spec(option.id)
\t\tif spec then
\t\t\tlocal pic = Instance.new("ImageLabel")
\t\t\tpic.Name = "PatronArt"
\t\t\tpic.BackgroundTransparency = 1
\t\t\tpic.BorderSizePixel = 0
\t\t\tpic.Active = false
\t\t\tpic.Image = spec.image
\t\t\tpic.ScaleType = spec.kind == "card" and Enum.ScaleType.Crop or Enum.ScaleType.Fit
\t\t\tif spec.rect then
\t\t\t\tpic.ImageRectOffset = Vector2.new(spec.rect.x, spec.rect.y)
\t\t\t\tpic.ImageRectSize = Vector2.new(spec.rect.w, spec.rect.h)
\t\t\tend
\t\t\tpic.Size = UDim2.fromScale(1, 1)
\t\t\tpic.Position = UDim2.fromScale(0, 0)
\t\t\tpic.ZIndex = 64
\t\t\tpic.Parent = crop
\t\t\tif game:GetService("RunService"):IsStudio() then
\t\t\t\ttask.defer(function()
\t\t\t\t\tif not crop.Parent then return end
\t\t\t\t\tlocal w = DraftPortrait.overflow(pic.AbsolutePosition.X, pic.AbsolutePosition.Y, pic.AbsoluteSize.X, pic.AbsoluteSize.Y,
\t\t\t\t\t\tcrop.AbsolutePosition.X, crop.AbsolutePosition.Y, crop.AbsoluteSize.X, crop.AbsoluteSize.Y)
\t\t\t\t\tif w then warn("[PortraitCrop] " .. tostring(option.id) .. " " .. w) end
\t\t\t\tend)
\t\t\tend
\t\tend
'''
s = s[:a] + new + s[b:]
s = s.replace('local PORTRAIT_SCALE = 1.5 -- Patron portraits in the draft rings: enlarged and top anchored so the baked in name is clipped away\n', 'local DraftPortrait = require(Engine:WaitForChild("DraftPortrait")) -- what the Patron rings draw (cut card portrait window)\n')
open(p, "w").write(s)
