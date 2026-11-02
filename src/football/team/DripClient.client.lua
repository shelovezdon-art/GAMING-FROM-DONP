-- MIRROR of game.StarterPlayer.StarterPlayerScripts.DripClient (LocalScript), pulled 2026-11-02 (post wave-3, Gauntlet, DRIP, broadcast UI, stance poses, 2K camera).
-- Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1); this copy is the QA/design record.
-- ALLSTAR WORLD · DripClient — DRIP STORE client (v1, 2026-11-02)
-- Store UI (own ScreenGui "AWDripStore", opened from the lobby kiosk ProximityPrompt), buy/equip through
-- AWDrip.StoreCall, DRIP PACKS tab (COMING SOON while product ids are 0), the ball-trail recolor and the
-- TD celebration playback. Reads TeamFootballClient's visuals folder by NAME ONLY — never edits that script.
-- V1 SIMPLIFICATION (honest): the flight comet recolors to the LOCAL player's own equipped trail in his own
-- view at all times (the spec's thrower/carrier ownership rule needs a carrier feed the client doesn't have yet).
-- Celebration is likewise own-view in v1: a client-set pose attribute does not replicate to other players.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local drip = RS:WaitForChild("AWDrip")
local Catalog = require(drip:WaitForChild("Catalog"))
local Store = drip:WaitForChild("Store")
local StoreCall = drip:WaitForChild("StoreCall")
local AWMotion = require(RS:WaitForChild("AWMotion"))

local NAVY = Color3.fromRGB(7, 16, 28)
local NAVY2 = Color3.fromRGB(14, 28, 46)
local GOLD = Color3.fromRGB(255, 191, 58)
local WHITE = Color3.fromRGB(235, 240, 248)
local MUTED = Color3.fromRGB(140, 155, 175)
local GOOD = Color3.fromRGB(88, 214, 141)

local state = { balance = 0, owned = {}, equipped = {} } -- owned as set
local function setState(s)
	if not s then return end
	state.balance = s.balance or 0
	state.equipped = s.equipped or {}
	state.owned = {}
	for _, id in ipairs(s.owned or {}) do state.owned[id] = true end
end

-------------------------------------------------------------------------------------------------- UI
local gui = Instance.new("ScreenGui")
gui.Name = "AWDripStore"; gui.ResetOnSpawn = false; gui.Enabled = false
gui.IgnoreGuiInset = true; gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromScale(0.62, 0.72); panel.Position = UDim2.fromScale(0.5, 0.5); panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = NAVY; panel.BorderSizePixel = 0; panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local stroke = Instance.new("UIStroke", panel); stroke.Color = GOLD; stroke.Thickness = 2; stroke.Transparency = 0.25
local ratio = Instance.new("UISizeConstraint", panel); ratio.MinSize = Vector2.new(520, 360) -- phones: never below touch-usable

local titleL = Instance.new("TextLabel")
titleL.Size = UDim2.new(0.5, 0, 0, 44); titleL.Position = UDim2.fromOffset(18, 8); titleL.BackgroundTransparency = 1
titleL.Font = Enum.Font.GothamBlack; titleL.TextScaled = true; titleL.TextXAlignment = Enum.TextXAlignment.Left
titleL.Text = "DRIP STORE"; titleL.TextColor3 = GOLD; titleL.Parent = panel

local balanceL = Instance.new("TextLabel")
balanceL.Size = UDim2.new(0.3, 0, 0, 34); balanceL.Position = UDim2.new(1, -18, 0, 13); balanceL.AnchorPoint = Vector2.new(1, 0)
balanceL.BackgroundColor3 = NAVY2; balanceL.Font = Enum.Font.GothamBold; balanceL.TextScaled = true
balanceL.TextColor3 = WHITE; balanceL.Text = "0 DRIP"; balanceL.Parent = panel
Instance.new("UICorner", balanceL).CornerRadius = UDim.new(0, 8)
local bstroke = Instance.new("UIStroke", balanceL); bstroke.Color = GOLD; bstroke.Transparency = 0.5

local closeB = Instance.new("TextButton")
closeB.Size = UDim2.fromOffset(40, 40); closeB.Position = UDim2.new(1, -6, 0, 6); closeB.AnchorPoint = Vector2.new(1, 0)
closeB.BackgroundTransparency = 1; closeB.Font = Enum.Font.GothamBlack; closeB.TextSize = 26
closeB.Text = "✕"; closeB.TextColor3 = MUTED; closeB.Parent = panel
balanceL.Position = UDim2.new(1, -54, 0, 13) -- make room for the close button

local toastL = Instance.new("TextLabel")
toastL.Size = UDim2.new(0.6, 0, 0, 26); toastL.Position = UDim2.new(0.5, 0, 1, -8); toastL.AnchorPoint = Vector2.new(0.5, 1)
toastL.BackgroundTransparency = 1; toastL.Font = Enum.Font.GothamBold; toastL.TextScaled = true
toastL.Text = ""; toastL.TextColor3 = GOLD; toastL.Parent = panel
local toastTok = 0
local function toast(text, color)
	toastTok += 1; local tok = toastTok
	toastL.Text = text; toastL.TextColor3 = color or GOLD
	task.delay(2.2, function() if toastTok == tok then toastL.Text = "" end end)
end

local TABS = { "TRAILS", "TITLES", "CELEBRATIONS", "DRIP PACKS" }
local TAB_KIND = { TRAILS = "trail", TITLES = "title", CELEBRATIONS = "celebration" }
local KIND_SLOT = { trail = "trail", title = "title", celebration = "celebration" }
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -36, 0, 34); tabBar.Position = UDim2.fromOffset(18, 56); tabBar.BackgroundTransparency = 1; tabBar.Parent = panel
local tabLayout = Instance.new("UIListLayout", tabBar); tabLayout.FillDirection = Enum.FillDirection.Horizontal; tabLayout.Padding = UDim.new(0, 8)

local grid = Instance.new("ScrollingFrame")
grid.Size = UDim2.new(1, -36, 1, -148); grid.Position = UDim2.fromOffset(18, 100)
grid.BackgroundTransparency = 1; grid.BorderSizePixel = 0; grid.ScrollBarThickness = 6
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y; grid.CanvasSize = UDim2.new(); grid.Parent = panel
local gl = Instance.new("UIGridLayout", grid)
gl.CellSize = UDim2.fromOffset(190, 120); gl.CellPadding = UDim2.fromOffset(10, 10)

local currentTab = "TRAILS"
local armedBuy = nil -- item id armed for the two-step confirm
local rebuild -- fwd

local function tabButtons()
	for _, name in ipairs(TABS) do
		local b = Instance.new("TextButton")
		b.Name = name; b.Size = UDim2.new(0, 130, 1, 0); b.AutoButtonColor = true
		b.BackgroundColor3 = NAVY2; b.Font = Enum.Font.GothamBold; b.TextScaled = true
		b.TextColor3 = MUTED; b.Text = name; b.Parent = tabBar
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
		b.MouseButton1Click:Connect(function()
			currentTab = name; armedBuy = nil; rebuild()
		end)
	end
end

local function card(parent)
	local c = Instance.new("Frame"); c.BackgroundColor3 = NAVY2; c.BorderSizePixel = 0; c.Parent = parent
	Instance.new("UICorner", c).CornerRadius = UDim.new(0, 10)
	local st = Instance.new("UIStroke", c); st.Thickness = 2
	return c, st
end

local function label(parent, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold; t.TextScaled = true; t.TextColor3 = WHITE
	for k, v in pairs(props) do t[k] = v end
	t.Parent = parent
	return t
end

function rebuild()
	for _, c in ipairs(grid:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	for _, b in ipairs(tabBar:GetChildren()) do
		if b:IsA("TextButton") then
			b.TextColor3 = (b.Name == currentTab) and GOLD or MUTED
			b.BackgroundColor3 = (b.Name == currentTab) and Color3.fromRGB(22, 40, 62) or NAVY2
		end
	end
	balanceL.Text = state.balance .. " DRIP"
	if currentTab == "DRIP PACKS" then
		for _, packName in ipairs(Catalog.packOrder) do
			local pack = Catalog.products[packName]
			local c, st = card(grid)
			st.Color = GOLD; st.Transparency = 0.35
			label(c, { Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 8), Text = pack.name, TextColor3 = GOLD })
			label(c, { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 40), Text = pack.blurb, TextColor3 = MUTED })
			local dormant = pack.devProductId == 0
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(1, -16, 0, 34); b.Position = UDim2.new(0, 8, 1, -42)
			b.BackgroundColor3 = dormant and Color3.fromRGB(30, 42, 58) or GOLD
			b.Font = Enum.Font.GothamBlack; b.TextScaled = true
			b.TextColor3 = dormant and MUTED or NAVY
			b.Text = dormant and "COMING SOON" or "BUY · ROBUX"
			b.Parent = c
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
			b.MouseButton1Click:Connect(function()
				if dormant then toast("DRIP PACKS · COMING SOON", MUTED)
				else Store:FireServer({ ev = "buyPack", pack = packName }) end
			end)
		end
		return
	end
	local kind = TAB_KIND[currentTab]
	for _, it in ipairs(Catalog.items) do
		if it.kind == kind then
			local owned = state.owned[it.id] == true
			local slot = KIND_SLOT[it.kind]
			local equipped = state.equipped[slot] == it.id
			local c, st = card(grid)
			st.Color = Catalog.rarityColor[it.rarity] or MUTED
			st.Transparency = 0.15
			-- color swatch
			local sw = Instance.new("Frame"); sw.Size = UDim2.fromOffset(28, 28); sw.Position = UDim2.fromOffset(8, 8); sw.BorderSizePixel = 0; sw.Parent = c
			Instance.new("UICorner", sw).CornerRadius = UDim.new(0, 6)
			local col = Catalog.parseColor(it.color)
			if typeof(col) == "ColorSequence" then
				sw.BackgroundColor3 = Color3.new(1, 1, 1)
				local g = Instance.new("UIGradient", sw); g.Color = col
			else
				sw.BackgroundColor3 = col or GOLD
			end
			label(c, { Size = UDim2.new(1, -48, 0, 20), Position = UDim2.fromOffset(42, 8), Text = it.name, TextXAlignment = Enum.TextXAlignment.Left })
			label(c, { Size = UDim2.new(1, -48, 0, 14), Position = UDim2.fromOffset(42, 28), Text = string.upper(it.rarity), TextColor3 = Catalog.rarityColor[it.rarity] or MUTED, TextXAlignment = Enum.TextXAlignment.Left })
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(1, -16, 0, 34); b.Position = UDim2.new(0, 8, 1, -42)
			b.Font = Enum.Font.GothamBlack; b.TextScaled = true
			b.Parent = c
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
			if equipped then
				b.BackgroundColor3 = GOOD; b.TextColor3 = NAVY; b.Text = "EQUIPPED"
			elseif owned then
				b.BackgroundColor3 = NAVY; b.TextColor3 = GOOD; b.Text = "EQUIP"
				local s2 = Instance.new("UIStroke", b); s2.Color = GOOD; s2.Transparency = 0.4
			elseif armedBuy == it.id then
				b.BackgroundColor3 = GOLD; b.TextColor3 = NAVY; b.Text = "CONFIRM · " .. it.price
			else
				b.BackgroundColor3 = NAVY; b.TextColor3 = GOLD; b.Text = "BUY · " .. it.price .. " DRIP"
				local s2 = Instance.new("UIStroke", b); s2.Color = GOLD; s2.Transparency = 0.4
			end
			b.MouseButton1Click:Connect(function()
				if equipped then
					local r = StoreCall:InvokeServer({ action = "equip", slot = slot, id = nil })
					if r and r.ok then setState(r.state) else toast(r and r.err or "ERROR", MUTED) end
					armedBuy = nil; rebuild()
				elseif owned then
					local r = StoreCall:InvokeServer({ action = "equip", slot = slot, id = it.id })
					if r and r.ok then setState(r.state) else toast(r and r.err or "ERROR", MUTED) end
					armedBuy = nil; rebuild()
				elseif armedBuy == it.id then -- two-step confirm (kid-safety gate, spec §3.3)
					armedBuy = nil
					local r = StoreCall:InvokeServer({ action = "buy", id = it.id })
					if r and r.ok then setState(r.state); toast(it.name .. " · YOURS", GOOD) else toast(r and r.err or "ERROR", MUTED) end
					rebuild()
				else
					armedBuy = it.id; rebuild()
				end
			end)
		end
	end
end

tabButtons()

local function openStore()
	local r = StoreCall:InvokeServer({ action = "getState" })
	if r and r.ok then setState(r.state) end
	armedBuy = nil; currentTab = currentTab or "TRAILS"
	rebuild()
	gui.Enabled = true
end
closeB.MouseButton1Click:Connect(function() gui.Enabled = false end)

-------------------------------------------------------------------------------------------------- kiosk prompt
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local m = prompt:FindFirstAncestor("AW_DripKiosk_2026-11-02")
	if m then openStore() end
end)

-------------------------------------------------------------------------------------------------- server pushes
Store.OnClientEvent:Connect(function(m)
	if type(m) ~= "table" then return end
	if m.ev == "state" then
		setState(m.state)
		if gui.Enabled then rebuild() else balanceL.Text = state.balance .. " DRIP" end
	elseif m.ev == "earn" then
		state.balance = m.balance or state.balance
		balanceL.Text = state.balance .. " DRIP"
		if gui.Enabled then toast("+" .. m.amount .. " DRIP · " .. (m.why or ""), GOOD); rebuild() end
	elseif m.ev == "toast" then
		toast(m.text or "", GOLD)
	elseif m.ev == "celebrate" then
		-- TD dead-ball beat: own-view pose celebration (v1). Skipped silently if anything is missing (spec §3.5).
		local it = m.id and Catalog.byId[m.id]
		local char = player.Character
		if it and it.pose and char then
			local sport, pose = string.match(it.pose, "^(%w+):(%w+)$")
			if sport and pose then
				AWMotion.setPose(char, sport, pose, 0.15)
				task.delay(it.poseLen or 1.5, function()
					if player.Character == char then AWMotion.setPose(char, nil) end
				end)
			end
		end
	end
end)

-------------------------------------------------------------------------------------------------- ball trail recolor
-- V1 rule (stated in the header): the LOCAL player's equipped trail colors the comet in his own view.
local DEFAULT_TRAIL = ColorSequence.new(GOLD) -- TeamFootballClient's own default (read 2026-11-02, line 731)
local watchedTrail = nil

local function applyTrailColor()
	if not (watchedTrail and watchedTrail.Parent) then return end
	local col = Catalog.parseColor(player:GetAttribute("AWTrail"))
	if typeof(col) == "Color3" then watchedTrail.Color = ColorSequence.new(col)
	elseif typeof(col) == "ColorSequence" then watchedTrail.Color = col
	else watchedTrail.Color = DEFAULT_TRAIL end
end

local function hookBall(ball)
	local function tryTrail(ch)
		if ch:IsA("Trail") then watchedTrail = ch; applyTrailColor() end
	end
	local tr = ball:FindFirstChildOfClass("Trail")
	if tr then tryTrail(tr) end
	ball.ChildAdded:Connect(tryTrail)
end

local function hookVisuals(folder)
	local ball = folder:FindFirstChild("Football")
	if ball then hookBall(ball) end
	folder.ChildAdded:Connect(function(ch) if ch.Name == "Football" then hookBall(ch) end end)
end

local vf = workspace:FindFirstChild("AWTeamFootballVisuals")
if vf then hookVisuals(vf) end
workspace.ChildAdded:Connect(function(ch) if ch.Name == "AWTeamFootballVisuals" then hookVisuals(ch) end end)
player:GetAttributeChangedSignal("AWTrail"):Connect(applyTrailColor)
