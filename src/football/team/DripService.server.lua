-- MIRROR of game.ServerScriptService.DripService (Script), pulled 2026-11-02 (post wave-3, Gauntlet, DRIP, broadcast UI, stance poses, 2K camera).
-- Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1); this copy is the QA/design record.
-- ALLSTAR WORLD · DripService — DRIP STORE server (v1, 2026-11-02)
-- Owns: player cosmetic profiles (DataStore "AWDrip_v1" + in-memory fallback), the DRIP earn loop
-- (fed by ReplicatedStorage.AWFootball.MatchEvents, fired by TeamFootballService), buy/equip validation,
-- and the dormant Robux developer-product path (MarketplaceService.ProcessReceipt — grants only when
-- Catalog.products ids are nonzero). Equips publish as PLAYER ATTRIBUTES (AWTrail / AWTitle / AWTitleColor /
-- AWCelebration) so no other script needs editing to render them.
-- Fairness law: nothing here writes to or is read by any gameplay config (cosmetics.md F5).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")

local drip = RS:WaitForChild("AWDrip")
local Catalog = require(drip:WaitForChild("Catalog"))
local Store = drip:WaitForChild("Store")           -- RemoteEvent: server->client state/celebrate/toast; client->server buyPack
local StoreCall = drip:WaitForChild("StoreCall")   -- RemoteFunction: getState / buy / equip

-------------------------------------------------------------------------------------------------- persistence
local dsOk, ds = pcall(function() return DataStoreService:GetDataStore("AWDrip_v1") end)
if not dsOk then
	warn("[DripService] DataStore unavailable (Studio API access off?) — running on in-memory profiles; nothing will persist this session")
end
local saidLoadWarn = false -- say the fallback once, not per player

local profiles = {} -- [player] = { balance, owned = {id=true}, equipped = {trail=,title=,celebration=}, receipts = {receiptId=true} }

local function defaultProfile()
	return { balance = 0, owned = {}, equipped = {}, receipts = {} }
end

local function loadProfile(player)
	local prof = defaultProfile()
	if dsOk then
		local ok, data = pcall(function() return ds:GetAsync("u_" .. player.UserId) end)
		if ok and type(data) == "table" then
			prof.balance = tonumber(data.balance) or 0
			if type(data.owned) == "table" then for id in pairs(data.owned) do if Catalog.byId[id] then prof.owned[id] = true end end end
			if type(data.equipped) == "table" then
				for slot in pairs(Catalog.slots) do
					local id = data.equipped[slot]
					-- equipped item gone from the catalog -> fall back to default, keep owned (spec edge case 3)
					if id and Catalog.byId[id] and prof.owned[id] then prof.equipped[slot] = id end
				end
			end
			if type(data.receipts) == "table" then prof.receipts = data.receipts end
		elseif not ok and not saidLoadWarn then
			saidLoadWarn = true
			warn("[DripService] GetAsync failed — in-memory fallback for this session: " .. tostring(data))
		end
	end
	return prof
end

local function saveProfile(player, prof)
	if not (dsOk and prof) then return end
	local ok, err = pcall(function()
		ds:SetAsync("u_" .. player.UserId, {
			balance = prof.balance, owned = prof.owned, equipped = prof.equipped, receipts = prof.receipts,
		})
	end)
	if not ok then warn("[DripService] SetAsync failed for " .. player.Name .. ": " .. tostring(err)) end
end

-------------------------------------------------------------------------------------------------- equip rendering surface
local function applyAttributes(player)
	local prof = profiles[player]; if not prof then return end
	local trail = prof.equipped.trail and Catalog.byId[prof.equipped.trail]
	local title = prof.equipped.title and Catalog.byId[prof.equipped.title]
	local celebr = prof.equipped.celebration and Catalog.byId[prof.equipped.celebration]
	player:SetAttribute("AWTrail", trail and trail.color or nil)          -- "r,g,b" or "r,g,b;r,g,b"
	player:SetAttribute("AWTitle", title and title.name or nil)           -- style name ("GOLD")
	player:SetAttribute("AWTitleColor", title and title.color or nil)
	player:SetAttribute("AWCelebration", celebr and celebr.id or nil)
end

local function stateFor(player)
	local prof = profiles[player]; if not prof then return nil end
	local owned = {}
	for id in pairs(prof.owned) do table.insert(owned, id) end
	return { balance = prof.balance, owned = owned, equipped = prof.equipped }
end

local function pushState(player)
	local st = stateFor(player)
	if st then Store:FireClient(player, { ev = "state", state = st }) end
end

-------------------------------------------------------------------------------------------------- earn loop
local matchEarned = {} -- [player] = DRIP earned this match (cap bookkeeping)

local function grant(player, amount, why, capped)
	local prof = profiles[player]; if not prof or amount <= 0 then return end
	if capped then
		local used = matchEarned[player] or 0
		amount = math.min(amount, Catalog.earn.matchCap - used)
		if amount <= 0 then return end
		matchEarned[player] = used + amount
	end
	prof.balance += amount
	Store:FireClient(player, { ev = "earn", amount = amount, why = why, balance = prof.balance })
end

-- MatchEvents: DripService creates it; TeamFootballService fires it if present (safe either order)
local football = RS:WaitForChild("AWFootball")
local events = football:FindFirstChild("MatchEvents")
if not events then
	events = Instance.new("BindableEvent"); events.Name = "MatchEvents"; events.Parent = football
end
events.Event:Connect(function(m)
	if type(m) ~= "table" then return end
	local E = Catalog.earn
	if m.ev == "td" and m.player then
		grant(m.player, E.td, "TOUCHDOWN", true)
		local prof = profiles[m.player]
		if prof and prof.equipped.celebration then Store:FireClient(m.player, { ev = "celebrate", id = prof.equipped.celebration }) end
	elseif m.ev == "perfectCatch" and m.player then
		grant(m.player, E.perfectCatch, "PERFECT CATCH", true)
	elseif m.ev == "ankleBreaker" and m.player then
		grant(m.player, E.ankleBreaker, "ANKLE BREAKER", true)
	elseif m.ev == "final" then
		for _, p in ipairs(m.winners or {}) do
			grant(p, E.matchComplete, "MATCH COMPLETE", true)
			grant(p, E.win, "WIN BONUS", true)
		end
		for _, p in ipairs(m.losers or {}) do
			grant(p, E.matchComplete, "MATCH COMPLETE", true)
		end
		for _, p in ipairs(m.winners or {}) do matchEarned[p] = nil end
		for _, p in ipairs(m.losers or {}) do matchEarned[p] = nil end
	end
end)

-------------------------------------------------------------------------------------------------- store calls
local lastCall = {} -- [player] = { t, n } crude rate limit: 12 calls per rolling second
local function allowed(player)
	local now = os.clock()
	local b = lastCall[player]
	if not b or now - b.t > 1 then lastCall[player] = { t = now, n = 1 }; return true end
	b.n += 1
	return b.n <= 12
end

StoreCall.OnServerInvoke = function(player, req)
	if type(req) ~= "table" or not allowed(player) then return { ok = false, err = "SLOW DOWN" } end
	local prof = profiles[player]
	if not prof then return { ok = false, err = "PROFILE NOT READY" } end
	if req.action == "getState" then
		return { ok = true, state = stateFor(player) }
	elseif req.action == "buy" then
		local it = type(req.id) == "string" and Catalog.byId[req.id]
		if not it then return { ok = false, err = "UNKNOWN ITEM" } end
		if prof.owned[it.id] then return { ok = false, err = "ALREADY OWNED" } end
		if prof.balance < it.price then return { ok = false, err = "NOT ENOUGH DRIP" } end
		prof.balance -= it.price
		prof.owned[it.id] = true
		task.spawn(saveProfile, player, prof)
		return { ok = true, state = stateFor(player) }
	elseif req.action == "equip" then
		local slot = req.slot
		if not (type(slot) == "string" and Catalog.slots[slot]) then return { ok = false, err = "BAD SLOT" } end
		if req.id == nil then -- unequip
			prof.equipped[slot] = nil
		else
			local it = type(req.id) == "string" and Catalog.byId[req.id]
			if not it then return { ok = false, err = "UNKNOWN ITEM" } end
			if not prof.owned[it.id] then return { ok = false, err = "NOT OWNED" } end
			if it.kind ~= Catalog.slots[slot] then return { ok = false, err = "WRONG SLOT" } end
			prof.equipped[slot] = it.id
		end
		applyAttributes(player)
		task.spawn(saveProfile, player, prof)
		return { ok = true, state = stateFor(player) }
	end
	return { ok = false, err = "UNKNOWN ACTION" }
end

-------------------------------------------------------------------------------------------------- Robux packs (dormant until ids are set)
Store.OnServerEvent:Connect(function(player, m)
	if type(m) ~= "table" or m.ev ~= "buyPack" or not allowed(player) then return end
	local pack = type(m.pack) == "string" and Catalog.products[m.pack]
	if not pack then return end
	if pack.devProductId == 0 then
		Store:FireClient(player, { ev = "toast", text = "DRIP PACKS · COMING SOON" })
		return
	end
	local ok, err = pcall(function() MarketplaceService:PromptProductPurchase(player, pack.devProductId) end)
	if not ok then warn("[DripService] PromptProductPurchase failed: " .. tostring(err)) end
end)

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local prof = profiles[player]
	if not prof then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local key = tostring(receipt.PurchaseId)
	if prof.receipts[key] then return Enum.ProductPurchaseDecision.PurchaseGranted end -- idempotent replay (spec edge case 2)
	local pack
	for _, name in ipairs(Catalog.packOrder) do
		local p = Catalog.products[name]
		if p.devProductId ~= 0 and p.devProductId == receipt.ProductId then pack = p break end
	end
	if not pack then return Enum.ProductPurchaseDecision.NotProcessedYet end -- not ours / dormant
	prof.balance += pack.drip -- purchased DRIP is NOT match-capped
	prof.receipts[key] = true
	saveProfile(player, prof) -- synchronous best effort before granting the receipt
	pushState(player)
	Store:FireClient(player, { ev = "toast", text = "+" .. pack.drip .. " DRIP · THANK YOU" })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-------------------------------------------------------------------------------------------------- lifecycle
local function onPlayer(player)
	profiles[player] = loadProfile(player)
	applyAttributes(player)
	pushState(player)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayer, p) end

Players.PlayerRemoving:Connect(function(player)
	local prof = profiles[player]
	if prof then saveProfile(player, prof) end
	profiles[player] = nil; matchEarned[player] = nil; lastCall[player] = nil
end)

game:BindToClose(function()
	for player, prof in pairs(profiles) do saveProfile(player, prof) end
end)

print("[DripService] up · " .. #Catalog.items .. " items · packs dormant=" .. tostring(Catalog.products.drip500.devProductId == 0))
