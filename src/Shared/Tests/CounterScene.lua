--[[
	Shared/Tests/CounterScene.lua
	Test helper: the rects of the Counter in screen space, built from the same functions the live Counter uses
	(Engine/ShopSceneLayout.rects/cardScales/rows and Engine/CardShape.shape), so a tooltip test works on the real layout
	instead of hand-made numbers. Reproduces the Play numbers of 2026-11-10 (frame 1257 x 750 at 260,-58: offers 226 x 313
	at x 764 and 1006, packs 96 x 148 at x 894 and 1006; the offer row bobs up to 5 px higher live).

	build(W, H, ox, oy, nOffers, nPacks) -> {
	  offers, packs   card SLOTS ({ X, Y, W, H }): the Body plus 16 px above and 4 below, as Client/ShopCards builds them
	  plates          the name plate (Banner) inside each offer
	  controls        Next Round, tabs, Next boss chip, Haggle and Reroll, each with the tag that hangs below it
	  blockers        offers + plates + controls
	}
	W, H = the Counter frame's size, ox, oy = its screen position.
]]

local Engine = script.Parent.Parent.Engine
local SL = require(Engine.ShopSceneLayout)
local CS = require(Engine.CardShape)

local CounterScene = {}

local HEAD, GAP = 16, 16 -- Client/ShopCards: headroom above a resting card; Client/ShopCards.row lists cards 16 px apart
CounterScene.HEAD, CounterScene.GAP = HEAD, GAP

function CounterScene.build(W, H, ox, oy, nOffers, nPacks)
	local r = SL.rects(W, H, { offers = nOffers, packs = nPacks })
	local sc = SL.cardScales(r)
	local oShape, pShape = CS.shape("patron", sc.patron), CS.shape("pack", sc.pack)
	local rows = SL.rows(r, oShape.h + HEAD + 12, pShape.h + HEAD + 12) -- 12 = ShopCards.rowHeight's 4 + 8

	local function slotsOf(row, shape, n)
		local total = n * shape.w + (n - 1) * GAP
		local x = ox + row.x + (row.w - total) / 2 -- the row centres its cards
		local out = {}
		for i = 1, n do
			out[i] = { X = x + (i - 1) * (shape.w + GAP), Y = oy + row.y, W = shape.w, H = shape.h + HEAD + 4 }
		end
		return out
	end
	local scene = { layout = r, scales = sc, plates = {}, controls = {}, blockers = {} }
	scene.offers, scene.packs = slotsOf(rows.patron, oShape, nOffers), slotsOf(rows.pack, pShape, nPacks)
	for i, o in ipairs(scene.offers) do
		scene.plates[i] = { X = o.X + 2, Y = o.Y + HEAD + oShape.bannerTop, W = oShape.w - 4, H = CS.BANNER_H }
	end
	local function abs(rc, padX, tag)
		return { X = ox + rc.x - (padX or 0), Y = oy + rc.y, W = rc.w + 2 * (padX or 0), H = rc.h + (tag or 0) }
	end
	-- the Haggle and Reroll tags are 24 px tall, 4 px under their button, up to 120 px wide
	scene.controls = { abs(r.leave), abs(r.tabs), abs(r.nextBoss), abs(r.props.ledger, 30, 28), abs(r.props.bell, 30, 28) }
	for _, list in ipairs({ scene.offers, scene.plates, scene.controls }) do
		for _, rc in ipairs(list) do scene.blockers[#scene.blockers + 1] = rc end
	end
	return scene
end

return CounterScene
