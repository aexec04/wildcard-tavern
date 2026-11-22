--[[
	Client/TableDress.lua
	Dresses the table furniture that is one painted picture for all Card Sets (DeckBook, WallBannerLeft/Right, SeatFacePicture) in the colours
	of the set shown right now: ThemeScenes.effectiveSetId(HudTheme skin, previewed set), so an equipped or previewed set always dresses
	the pile, banners and seats together.

	TableDress.install()              once; tints new instances as they appear and re-tints on a skin change or a Preview
	TableDress.refresh()              re-tint every live instance now
	TableDress.applyTo(root, setId)   tint the named instances under root (tests and refresh use it)
	TableDress.audit()                { { name, color, expected, setId } ... } for every live instance (Studio check)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Pure = require(Engine:WaitForChild("TableDress"))

local TableDress = {}
local installed = false

local function shownSetId()
	local skinId, previewId = nil, nil
	pcall(function() local s = require(script.Parent.HudTheme).skin(); skinId = s and s.id end)
	pcall(function() previewId = require(script.Parent.CosmeticSetsView).previewSetId() end)
	return require(Engine:WaitForChild("ThemeScenes")).effectiveSetId(skinId, previewId)
end

local function expected(setId, part)
	local t = Pure.tintFor(setId, part)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local CREAM = Color3.fromRGB(250, 240, 220)
local function paint(inst, setId)
	local part = Pure.partOf(inst.Name)
	if part and Pure.BACK_PARTS[part] and inst:IsA("ImageLabel") then
		-- the pile and banners draw the set's own painted card back; classic (or a set with no painted back) keeps the shared picture
		if inst:GetAttribute("ClassicImage") == nil then
			inst:SetAttribute("ClassicImage", inst.Image)
			inst:SetAttribute("ClassicScale", inst.ScaleType.Name)
		end
		local back = Pure.backImage(setId)
		if back then
			inst.Image = back
			inst.ScaleType = Enum.ScaleType[Pure.BACK_SCALE[part]]
			inst.ImageColor3 = Color3.new(1, 1, 1)
		else
			inst.Image = inst:GetAttribute("ClassicImage")
			inst.ScaleType = Enum.ScaleType[inst:GetAttribute("ClassicScale")]
			inst.ImageColor3 = expected(setId, part)
		end
	elseif part and inst:IsA("ImageLabel") then
		inst.ImageColor3 = expected(setId, part)
	end
	if (inst.Name == "ScoreCaption" or inst.Name == "ScoreProgress") and inst:IsA("TextLabel") then -- Score plate words wear the set accent (7:1 on its plate), classic keeps cream
		local ink = nil
		pcall(function() ink = require(script.Parent.SetInk).get() end)
		inst.TextColor3 = ink and ink.accent or CREAM
	end
end

function TableDress.applyTo(root, setId)
	for _, d in ipairs(root:GetDescendants()) do paint(d, setId) end
end

local function gui()
	local p = Players.LocalPlayer
	return p and p:FindFirstChildOfClass("PlayerGui")
end

function TableDress.refresh()
	local g = gui()
	if g then TableDress.applyTo(g, shownSetId()) end
end

function TableDress.audit()
	local out, g = {}, gui()
	if not g then return out end
	local setId = shownSetId()
	for _, d in ipairs(g:GetDescendants()) do
		local part = Pure.partOf(d.Name)
		if part and d:IsA("ImageLabel") then out[#out + 1] = { name = d.Name, color = d.ImageColor3, expected = expected(setId, part), setId = setId } end
	end
	return out
end

function TableDress.install()
	if installed then return end
	installed = true
	local g = gui()
	if g then
		g.DescendantAdded:Connect(function(d)
			if Pure.partOf(d.Name) or d.Name == "ScoreCaption" or d.Name == "ScoreProgress" then task.defer(function() if d.Parent then paint(d, shownSetId()) end end) end
		end)
	end
	pcall(function() require(script.Parent.HudTheme).onSkin(TableDress.refresh) end)
	pcall(function() require(script.Parent.CosmeticSetsView).onPreview(TableDress.refresh) end)
	TableDress.refresh()
end

return TableDress
