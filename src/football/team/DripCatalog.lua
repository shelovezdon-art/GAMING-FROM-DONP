-- MIRROR of game.ReplicatedStorage.AWDrip.Catalog (ModuleScript), pulled 2026-11-02 (post wave-3, Gauntlet, DRIP, broadcast UI, stance poses, 2K camera).
-- Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1); this copy is the QA/design record.
-- ALLSTAR WORLD · AWDrip.Catalog — DRIP STORE v1 catalog + economy numbers (2026-11-02)
-- DATA ONLY. Fairness law (design/gdd/cosmetics.md, carried from football-core.md): cosmetics are visual only.
-- No gameplay config (AWFootball.*, AWPractice.*) may ever require or read this module (acceptance F5).
-- Prices and earn rates are [ASSUMPTION] starting points from the spec §3.2 / owner brief until the owner tunes them.

local Catalog = {}

-- color: "r,g,b" = solid; "r,g,b;r,g,b" = two-stop gradient (ColorSequence — epic trails only)
Catalog.items = {
	-- ball trails: recolor the flight comet ONLY. The white catch-window flip is a reserved signal (spec §3.4).
	{ id = "trail_ice_white",    name = "ICE WHITE",    kind = "trail", rarity = "common", price = 150,  color = "200,225,255" }, -- icy pale blue, NOT white: all-white is the catch-window signal (F4)
	{ id = "trail_classic_gold", name = "CLASSIC GOLD", kind = "trail", rarity = "common", price = 150,  color = "255,191,58" },
	{ id = "trail_miami_teal",   name = "MIAMI TEAL",   kind = "trail", rarity = "rare",   price = 500,  color = "64,199,195" },
	{ id = "trail_flamingo",     name = "FLAMINGO",     kind = "trail", rarity = "rare",   price = 500,  color = "255,112,160" },
	{ id = "trail_sunset_fade",  name = "SUNSET FADE",  kind = "trail", rarity = "epic",   price = 1200, color = "255,112,160;255,191,58" },
	{ id = "trail_royal_blue",   name = "ROYAL BLUE",   kind = "trail", rarity = "epic",   price = 1200, color = "40,80,255;140,185,255" },
	-- badge-banner title styles: accent color on the client badge/lower-third chrome
	{ id = "title_gold",     name = "GOLD",     kind = "title", rarity = "rare", price = 400, color = "255,191,58" },
	{ id = "title_teal",     name = "TEAL",     kind = "title", rarity = "rare", price = 400, color = "64,199,195" },
	{ id = "title_flamingo", name = "FLAMINGO", kind = "title", rarity = "rare", price = 400, color = "255,112,160" },
	-- celebrations: pose-based, TD dead-ball beat only, hard-capped length (spec §3.5)
	{ id = "celebr_the_point", name = "THE POINT", kind = "celebration", rarity = "epic", price = 800, color = "255,191,58", pose = "soccer:cheer", poseLen = 1.5 },
}

Catalog.byId = {}
for _, it in ipairs(Catalog.items) do
	assert(Catalog.byId[it.id] == nil, "AWDrip.Catalog: duplicate id " .. it.id)
	Catalog.byId[it.id] = it
end

-- reserved-white law (spec F4): reject any trail color stop with every channel >= whiteFloor
Catalog.whiteFloor = 230 -- safe range 210–245 (spec §7)
for _, it in ipairs(Catalog.items) do
	if it.kind == "trail" then
		for seg in string.gmatch(it.color, "[^;]+") do
			local r, g, b = string.match(seg, "^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
			assert(r and g and b, "AWDrip.Catalog: bad color on " .. it.id)
			assert(not (tonumber(r) >= Catalog.whiteFloor and tonumber(g) >= Catalog.whiteFloor and tonumber(b) >= Catalog.whiteFloor),
				"AWDrip.Catalog: " .. it.id .. " reads as reserved white (catch-window signal, F4)")
		end
	end
end

-- equip slots: slot name -> required item kind
Catalog.slots = { trail = "trail", title = "title", celebration = "celebration" }

-- earn rules, server-side only (owner brief 2026-11-02; all [ASSUMPTION] until tuned)
Catalog.earn = {
	matchComplete = 25,  -- present at the final whistle
	win = 50,
	td = 10,
	perfectCatch = 5,    -- PERFECT CATCH badge
	ankleBreaker = 15,   -- ANKLE BREAKER badge
	matchCap = 250,      -- hard cap per player per match, all sources (anti-farm)
}

-- Robux developer products — DORMANT until the owner creates them in Creator Hub
-- (Monetization → Developer Products) and pastes the numeric ids below. 0 = not created = "COMING SOON".
Catalog.products = {
	drip500  = { devProductId = 0, drip = 500,  name = "500 DRIP",   blurb = "STARTER PACK" },
	drip1200 = { devProductId = 0, drip = 1200, name = "1,200 DRIP", blurb = "EPIC PACK" },
	drip3000 = { devProductId = 0, drip = 3000, name = "3,000 DRIP", blurb = "LEGEND PACK" },
}
Catalog.packOrder = { "drip500", "drip1200", "drip3000" }

-- rarity chrome (spec §3.2 palette; frame/label color only, text tier always shown beside it)
Catalog.rarityColor = {
	common = Color3.fromRGB(150, 160, 175),
	rare = Color3.fromRGB(64, 199, 195),
	epic = Color3.fromRGB(255, 112, 160),
	legendary = Color3.fromRGB(255, 191, 58),
}
Catalog.rarityOrder = { common = 1, rare = 2, epic = 3, legendary = 4 }

-- "r,g,b" -> Color3 · "r,g,b;r,g,b" -> ColorSequence · nil/garbage -> nil
function Catalog.parseColor(s)
	local stops = {}
	for seg in string.gmatch(s or "", "[^;]+") do
		local r, g, b = string.match(seg, "^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
		if r then table.insert(stops, Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b))) end
	end
	if #stops == 0 then return nil end
	if #stops == 1 then return stops[1] end
	return ColorSequence.new(stops[1], stops[2])
end

return Catalog
