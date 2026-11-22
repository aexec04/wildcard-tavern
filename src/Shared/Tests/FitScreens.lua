--[[
	Shared/Tests/FitScreens.lua
	The screens the fit audit (Tests/FitAudit.lua) covers: one adapter per layout module in Engine/ that turns the module's
	answer into a map of rects { x, y, w, h }. `E(name)` loads an Engine module. Lanes: "menu" = Settings, Store, Season, Quests, Daily
	Rewards, Loading, Menu; "table" = Table, Draft, Round Select, Map, Counter shop; "shared" = anything else.
]]

return function(E)
	local screens = {}
	local function add(s) screens[#screens + 1] = s end
	local function box(l, t, r, b) return { x = l, y = t, w = r - l, h = b - t } end

	add({
		name = "Menu", lane = "menu",
		rects = function(w, h)
			local L = E("MenuLayout")
			local out = {}
			for _, hs in ipairs(L.Hotspots) do
				local l, t, r, b = L.rect(hs, w, h)
				out[hs.id] = box(l, t, r, b)
			end
			local nl, nt, nr, nb = L.noticeRect(w, h)
			out.noticeBoard = box(nl, nt, nr, nb)
			return out
		end,
	})

	add({
		name = "Loading", lane = "menu",
		rects = function(w, h) return E("LoadingLayout").rects(w, h) end,
	})

	add({
		name = "Settings", lane = "menu",
		rects = function(w, h)
			local r = E("SettingsLayout").panelRects(w, h)
			return { panel = r.panel }
		end,
	})

	add({
		name = "Store", lane = "menu",
		rects = function(w, h)
			-- the 820x470 panel is drawn shrunk by one UIScale and centred, so scale its children the same way
			local L = E("StoreLayout")
			local s = L.scale(w, h)
			local ox, oy = (w - L.PANEL_W * s) / 2, (h - L.PANEL_H * s) / 2
			local function place(r) return { x = ox + r.x * s, y = oy + r.y * s, w = r.w * s, h = r.h * s } end
			local r = L.rects()
			return { panel = place({ x = 0, y = 0, w = L.PANEL_W, h = L.PANEL_H }), closeButton = place(r.close) }
		end,
	})

	add({
		name = "Table", lane = "table",
		rects = function(w, h) return E("Gameplay2Layout").rects(w, h) end,
		intended = { "stage|", "deck|", "tray", "patron", "round|", "target|" },
	})

	add({
		name = "Table (play board)", lane = "table",
		rects = function(w, h) return E("PlayBoardLayout").hud(w, h) end,
		-- hands, discards and handsDiscards are alternatives for the same strip, not neighbours
		intended = { "^hands$|^discards$", "^handsDiscards$|^hands$", "^handsDiscards$|^discards$" },
		skip = { touch = { ["^hands"] = true, ["^discards"] = true } }, -- readouts, not buttons
	})

	add({
		name = "Counter shop", lane = "table",
		rects = function(w, h) return E("ShopSceneLayout").rects(w, h, {}) end,
		-- the scene is layers: the counter, felt, table, light and Marlo stack by design, and the bubble sits beside Marlo
		intended = { "^counter$|^felt$", "^counter$|^marlo$", "^counter$|^table$", "^felt$|^light$", "^light$|^table$", "^bubble$|^marlo$" },
	})

	add({
		name = "Run Over", lane = "shared",
		rects = function(w, h)
			-- the content is drawn at r.scale and centred (what the screen does after computeTouch), so scale every rect the same way
			local r = E("RunOverLayout").computeTouch(w, h, { factsH = 330, patrons = 3, primary = 2, more = 5, pills = true, cardSeats = true })
			local s = r.scale or 1
			local ox, oy = (w - r.panel.w * s) / 2, (h - r.panel.h * s) / 2
			local out = {}
			local function place(v) return { x = ox + v.x * s, y = oy + v.y * s, w = v.w * s, h = v.h * s } end
			for k, v in pairs(r) do
				if type(v) == "table" and type(v.x) == "number" then
					out[k] = place(v)
				elseif type(v) == "table" and k ~= "columns" then
					local grp = {}
					for i, c in pairs(v) do
						if type(c) == "table" and type(c.x) == "number" then grp[i] = place(c) end
					end
					out[k] = grp
				end
			end
			return out
		end,
	})

	add({
		name = "Draft", lane = "table",
		rects = function(w, h)
			-- three 230x300 cards, shrunk by the panel's own scale (ChoicePanel: clamp(min(w / 790, h / 490), 0.5, 1.2))
			local s = math.max(0.5, math.min(1.2, math.min(w / (230 * 3 + 100), h / (300 + 190))))
			local spots = E("ChoiceSceneLayout").cardSpots(w, h, 3, 230 * s, 300 * s)
			local out = {}
			for i, p in ipairs(spots) do out["card" .. i] = { x = p.x - 115 * s, y = p.y - 150 * s, w = 230 * s, h = 300 * s } end
			return out
		end,
	})

	add({
		name = "Collection", lane = "menu",
		rects = function(w, h)
			local L = E("CollectionSceneLayout")
			local c = L.content(w, h)
			local out = { content = c }
			local g = L.grid(w, h, "frames", 4) -- the first row of tiles (the rest scroll)
			for i, cell in ipairs(g.cells) do
				if cell.y + cell.h <= c.y + c.h + 1 then out["tile" .. i] = cell end
			end
			return out
		end,
	})

	add({
		name = "Daily Rewards row", lane = "menu",
		rects = function(w, h)
			local r = E("RewardsLayout").row(math.floor(w * 0.7), 4)
			local out = { emblem = r.emblem, name = r.name, count = r.count }
			for i, c in ipairs(r.chips) do out["chip" .. i] = c end
			return out
		end,
	})

	return screens
end
