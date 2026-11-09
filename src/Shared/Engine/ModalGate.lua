--[[
	Shared/Engine/ModalGate.lua
	Pure model of "while a modal popup is open, nothing behind it may react" (tested).

	  local gate = ModalGate.new()
	  gate:open(owner)            a modal opened; `owner` is any opaque value (the client passes its backdrop frame)
	  gate:close(owner)           it closed; the count never goes below 0 and a repeated close is ignored
	  gate:count()                modals currently open
	  gate:isModalOpen()          count() > 0
	  gate:blocks(target, inside) true when a modal is open and `target` is not inside any open modal.
	                              inside(target, owner) -> bool tells whether target lives under that owner.
	                              Hover handlers call this first and return early when it is true.

	ModalGate.STAGES: one themed stage per modal kind (blessing, draft, pack, event, road, detail), read by
	Client/ModalStage.lua. stageFor(kind) maps a ChoicePanel / popup kind to a stage id and never returns nil.
]]

local ModalGate = {}
ModalGate.__index = ModalGate

function ModalGate.new()
	return setmetatable({ owners = {}, n = 0 }, ModalGate)
end

function ModalGate:open(owner)
	if owner == nil or self.owners[owner] then return end
	self.owners[owner] = true
	self.n = self.n + 1
end

function ModalGate:close(owner)
	if owner == nil or not self.owners[owner] then return end
	self.owners[owner] = nil
	self.n = math.max(0, self.n - 1)
end

function ModalGate:count()
	return self.n
end

function ModalGate:isModalOpen()
	return self.n > 0
end

function ModalGate:blocks(target, inside)
	if self.n == 0 then return false end
	if target ~= nil and inside then
		for owner in pairs(self.owners) do
			if inside(target, owner) then return false end
		end
	end
	return true
end

-- Colours are {r, g, b}. top/bottom paint the stage gradient, accent tints the frame and the decor.
ModalGate.STAGES = {
	blessing = { title = "Candlelit Altar", top = { 52, 34, 40 }, bottom = { 20, 12, 18 }, accent = { 255, 214, 140 }, decor = "rays", ease = 6 },
	draft = { title = "Card Table", top = { 30, 74, 58 }, bottom = { 12, 34, 28 }, accent = { 222, 182, 104 }, decor = "chairs", ease = 6 },
	pack = { title = "Card Table", top = { 30, 74, 58 }, bottom = { 12, 34, 28 }, accent = { 222, 182, 104 }, decor = "chairs", ease = 6 },
	event = { title = "Map Desk", top = { 96, 74, 46 }, bottom = { 44, 30, 18 }, accent = { 235, 205, 150 }, decor = "map", ease = 6 },
	road = { title = "Map Desk", top = { 96, 74, 46 }, bottom = { 44, 30, 18 }, accent = { 235, 205, 150 }, decor = "map", ease = 6 },
	detail = { title = "Cork Wall", top = { 128, 92, 58 }, bottom = { 74, 50, 30 }, accent = { 200, 60, 50 }, decor = "pins", ease = 6 },
}

local KIND_TO_STAGE = {
	modifier = "blessing", blessing = "blessing",
	patron = "draft", rushPatron = "draft", draft = "draft",
	pack = "pack", event = "event", road = "road", detail = "detail",
}

function ModalGate.stageFor(kind)
	return KIND_TO_STAGE[kind] or "event"
end

return ModalGate
