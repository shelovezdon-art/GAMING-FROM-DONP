-- MIRROR of game.StarterPlayer.StarterPlayerScripts.TeamFootballClient (LocalScript), pulled 2026-11-02 (post feature-wave-2 + ankle-breaker).
-- Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1); this copy is the QA/design record.
-- ALLSTAR WORLD · TeamFootballClient (LocalScript). Lobby (roster + READY), HUD, input and visuals for 2v2 / 5v5.
-- The server decides everything; this script sends intents and draws.
-- Controls (keyboard / gamepad / touch):
--   SPACE (A)      QB: SET, then HUT · receivers: release on the HUT, catch · defenders: get off, leap on a jump ball
--   1–5            QB before the snap: call a play · QB after the snap: throw to receiver 1–4 (hold = lob)
--   1–6            receiver before the snap: pick your own route
--   F (X)          aggressive catch · swat / intercept · QB: throw to the man you face (hold = lob)
--   R (B)          tackle (defense) · stiff-arm (ball carrier)
--   Q / E          juke left / right · C spin · SHIFT flip your hips (backpedal) · G call for the ball · X leave
--   1 / 2 (D-pad ◀ / ▶, or tap)  offense after a TD: declare the try (1 = from the 5, pass only · 2 = from the 10)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CAS = game:GetService("ContextActionService")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local folder = RS:WaitForChild("AWFootball")
local remotes = folder:WaitForChild("TeamRemotes")
local Intent = remotes:WaitForChild("Intent")
local State = remotes:WaitForChild("State")
local Motion = require(RS:WaitForChild("AWMotion"))   -- added 2026-11-02: carrier arm tuck (claimArms), same as PracticeClient

local GOLD, NAVY = Color3.fromRGB(255, 191, 58), Color3.fromRGB(7, 16, 28)
local BLUE = Color3.fromRGB(70, 150, 255)
local GOOD, BAD, WHITE = Color3.fromRGB(90, 220, 120), Color3.fromRGB(255, 95, 70), Color3.new(1, 1, 1)
local TEAMCOLOR = { home = BLUE, away = GOLD }
local ROUTE_KEYS = { "slant", "curl", "post", "fade", "cross", "free" }
local ROUTE_LABEL = { slant = "SLANT", curl = "CURL", post = "POST", fade = "FADE", cross = "CROSS", free = "FREE" }

local mode = "none"        -- none | lobby | queued | game
local hud, field, lobby = nil, nil, nil
local ballState = { mode = "hidden" }
local lunge, pedalFace = nil, nil
local visuals = {}
local holdStart = {}
local pumpMod = false -- FEATURE WAVE 2 (feel-upgrades #6): C/ButtonY held in the pocket turns a quick throw-key tap into a pump fake

local function send(t) Intent:FireServer(t) end

-------------------------------------------------------------------------------------------------- UI helpers
local gui = Instance.new("ScreenGui"); gui.Name = "AWTeamFootballHUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
local function label(parent, props)
	local t = Instance.new("TextLabel"); t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBlack; t.TextScaled = true; t.TextColor3 = WHITE
	for k, v in pairs(props) do t[k] = v end
	t.Parent = parent
	return t
end
local function panel(parent, props)
	local f = Instance.new("Frame"); f.BackgroundColor3 = NAVY; f.BackgroundTransparency = 0.18; f.BorderSizePixel = 0
	for k, v in pairs(props) do f[k] = v end
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 12); f.Parent = parent
	return f
end
local function button(parent, text, props, color)
	local b = Instance.new("TextButton"); b.Font = Enum.Font.GothamBlack; b.TextScaled = true; b.Text = text
	b.BackgroundColor3 = color or NAVY; b.TextColor3 = color and NAVY or WHITE; b.BackgroundTransparency = 0.1; b.AutoButtonColor = true
	for k, v in pairs(props) do b[k] = v end
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10); b.Parent = parent
	return b
end
local function fbColor(k) return k == "good" and GOOD or k == "bad" and BAD or k == "warn" and GOLD or WHITE end

-------------------------------------------------------------------------------------------------- lobby panel
local lobbyF = panel(gui, { Size = UDim2.fromOffset(380, 330), Position = UDim2.new(0, 16, 0.5, -165), Visible = false })
local lst = Instance.new("UIStroke", lobbyF); lst.Color = GOLD; lst.Thickness = 2; lst.Transparency = 0.3
local lobbyTitle = label(lobbyF, { Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 8), Text = "TEAM FOOTBALL" })
local lobbySub = label(lobbyF, { Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 36), Text = "", TextColor3 = GOLD, Font = Enum.Font.GothamBold })
local cols = {}
for i, team in ipairs({ "home", "away" }) do
	local c = Instance.new("Frame"); c.BackgroundTransparency = 1; c.Size = UDim2.new(0.5, -15, 0, 210); c.Position = UDim2.new((i - 1) * 0.5, 10, 0, 58); c.Parent = lobbyF
	label(c, { Size = UDim2.new(1, 0, 0, 20), Text = team == "home" and "HOME" or "AWAY", TextColor3 = TEAMCOLOR[team] })
	local list = Instance.new("Frame"); list.BackgroundTransparency = 1; list.Size = UDim2.new(1, 0, 1, -24); list.Position = UDim2.fromOffset(0, 24); list.Parent = c
	local ll = Instance.new("UIListLayout", list); ll.Padding = UDim.new(0, 4)
	cols[team] = { frame = list, buttons = {} }
end
local readyB = button(lobbyF, "READY", { Size = UDim2.new(0.5, -15, 0, 40), Position = UDim2.new(0, 10, 1, -50) }, GOOD)
local leaveLB = button(lobbyF, "LEAVE", { Size = UDim2.new(0.5, -15, 0, 40), Position = UDim2.new(0.5, 5, 1, -50) })
readyB.MouseButton1Click:Connect(function()
	if mode ~= "lobby" or not lobby then return end
	local me = lobby.myTeam and lobby[lobby.myTeam][lobby.mySlot]
	send({ action = "ready", on = not (me and me.ready) })
end)
leaveLB.MouseButton1Click:Connect(function() send({ action = "leave" }) end)

local function renderLobby(l)
	lobby = l
	lobbyTitle.Text = l.mode .. " · " .. l.field
	if l.state == "countdown" and l.countdown then lobbySub.Text = "KICKOFF IN " .. l.countdown .. "…"
	else lobbySub.Text = "Tap READY · AI fills empty spots" .. (l.autoStart and (" · auto-start " .. l.autoStart .. "s") or "") end
	for _, team in ipairs({ "home", "away" }) do
		local c = cols[team]
		for s, info in ipairs(l[team]) do
			local b = c.buttons[s]
			if not b then
				b = button(c.frame, "", { Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Left })
				local pad = Instance.new("UIPadding", b); pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6); pad.PaddingTop = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)
				b.MouseButton1Click:Connect(function() if lobby and not lobby[team][s].human then send({ action = "pick", team = team, slot = s }) end end)
				c.buttons[s] = b
			end
			local mine = l.myTeam == team and l.mySlot == s
			b.Text = info.role .. "  ·  " .. (info.human and info.name or "AI (tap to take)") .. (info.ready and "  ✓" or "")
			b.BackgroundColor3 = mine and TEAMCOLOR[team] or NAVY
			b.TextColor3 = mine and NAVY or (info.human and WHITE or Color3.fromRGB(160, 170, 185))
		end
		for s = #l[team] + 1, #c.buttons do c.buttons[s].Visible = false end
	end
	local me = l.myTeam and l[l.myTeam][l.mySlot]
	readyB.Text = (me and me.ready) and "NOT READY" or "READY"
	readyB.BackgroundColor3 = (me and me.ready) and GOLD or GOOD
end

-------------------------------------------------------------------------------------------------- game HUD
local hudF = Instance.new("Frame"); hudF.BackgroundTransparency = 1; hudF.Size = UDim2.fromScale(1, 1); hudF.Visible = false; hudF.Parent = gui
local board = panel(hudF, { Size = UDim2.fromOffset(440, 80), Position = UDim2.new(0.5, -220, 0, 14) })
board.Name = "Scoreboard"
local bst = Instance.new("UIStroke", board); bst.Color = GOLD; bst.Thickness = 2; bst.Transparency = 0.3
label(board, { Size = UDim2.fromOffset(90, 20), Position = UDim2.fromOffset(14, 8), Text = "HOME", TextColor3 = BLUE, TextXAlignment = Enum.TextXAlignment.Left })
local homeS = label(board, { Size = UDim2.fromOffset(70, 40), Position = UDim2.fromOffset(14, 30), Text = "0", TextXAlignment = Enum.TextXAlignment.Left })
label(board, { Size = UDim2.fromOffset(90, 20), Position = UDim2.new(1, -104, 0, 8), Text = "AWAY", TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right })
local awayS = label(board, { Size = UDim2.fromOffset(70, 40), Position = UDim2.new(1, -84, 0, 30), Text = "0", TextXAlignment = Enum.TextXAlignment.Right })
local downL = label(board, { Size = UDim2.new(1, -220, 0, 22), Position = UDim2.fromOffset(110, 10), Text = "", Font = Enum.Font.GothamBold })
local possL = label(board, { Size = UDim2.new(1, -220, 0, 16), Position = UDim2.fromOffset(110, 36), Text = "", TextColor3 = GOLD, Font = Enum.Font.GothamBold })
local roleL = label(board, { Size = UDim2.new(1, -220, 0, 16), Position = UDim2.fromOffset(110, 56), Text = "", Font = Enum.Font.GothamBold })
local msgF = panel(hudF, { Size = UDim2.fromOffset(640, 52), Position = UDim2.new(0.5, -320, 0.2, 0), Visible = false })
local msgL = label(msgF, { Size = UDim2.new(1, -24, 1, -12), Position = UDim2.fromOffset(12, 6) })
local bigL = label(hudF, { Size = UDim2.fromOffset(700, 120), Position = UDim2.new(0.5, -350, 0.38, 0), Visible = false, TextStrokeTransparency = 0.2, TextColor3 = GOLD })
local fbL = label(hudF, { Size = UDim2.fromOffset(600, 56), Position = UDim2.new(0.5, -300, 0.33, 0), Visible = false, TextStrokeTransparency = 0.3 })
local promptF = panel(hudF, { Size = UDim2.fromOffset(700, 38), Position = UDim2.new(0.5, -350, 1, -150) })
local promptL = label(promptF, { Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), Font = Enum.Font.GothamBold })
local timingF = panel(hudF, { Size = UDim2.fromOffset(360, 20), Position = UDim2.new(0.5, -180, 1, -190), Visible = false, BackgroundTransparency = 0.3 })
local timingFill = Instance.new("Frame"); timingFill.BorderSizePixel = 0; timingFill.BackgroundColor3 = WHITE; timingFill.Size = UDim2.fromScale(0, 1); timingFill.Parent = timingF
Instance.new("UICorner", timingFill).CornerRadius = UDim.new(0, 10)
local windowF = Instance.new("Frame"); windowF.BorderSizePixel = 0; windowF.BackgroundColor3 = GOLD; windowF.BackgroundTransparency = 0.35; windowF.Parent = timingF
local chipsF = Instance.new("Frame"); chipsF.BackgroundTransparency = 1; chipsF.Size = UDim2.fromOffset(720, 40); chipsF.Position = UDim2.new(0.5, -360, 1, -104); chipsF.Parent = hudF
local cl = Instance.new("UIListLayout", chipsF); cl.FillDirection = Enum.FillDirection.Horizontal; cl.Padding = UDim.new(0, 6); cl.HorizontalAlignment = Enum.HorizontalAlignment.Center
local chips = {}
local function chip(i)
	if chips[i] then return chips[i] end
	local b = button(chipsF, "", { Size = UDim2.fromOffset(112, 38) })
	b.MouseButton1Click:Connect(function()
		if not hud then return end
		if hud.isQB then send({ action = "play", index = i })
		elseif i <= #ROUTE_KEYS then send({ action = "route", route = ROUTE_KEYS[i] })
		else send({ action = "route", route = "play" }) end
	end)
	chips[i] = b
	return b
end
local cdF = Instance.new("Frame"); cdF.BackgroundTransparency = 1; cdF.Size = UDim2.fromOffset(260, 30); cdF.Position = UDim2.new(1, -280, 1, -60); cdF.Parent = hudF
local cdl = Instance.new("UIListLayout", cdF); cdl.FillDirection = Enum.FillDirection.Horizontal; cdl.Padding = UDim.new(0, 6); cdl.HorizontalAlignment = Enum.HorizontalAlignment.Right

-- ============================ play-call dashboard (owner: "3 plays, showing what each player does") 2026-11-02
local playbook = nil
local pbPage = 1
local pbF = panel(hudF, { Size = UDim2.fromOffset(660, 212), Position = UDim2.new(0.5, -330, 1, -336) })
pbF.Visible = false
label(pbF, { Size = UDim2.fromOffset(260, 22), Position = UDim2.fromOffset(12, 5), Text = "CALL THE PLAY", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
local pbPrev = button(pbF, "◀", { Size = UDim2.fromOffset(34, 28), Position = UDim2.new(1, -84, 0, 3) })
local pbNext = button(pbF, "▶", { Size = UDim2.fromOffset(34, 28), Position = UDim2.new(1, -44, 0, 3) })
local pbCards = {}
local PB_COLOR = { Color3.fromRGB(70, 150, 255), GOLD, WHITE, Color3.fromRGB(255, 110, 90) } -- X, Z, SLOT, RB
local PB_X = { 0.14, 0.86, 0.34, 0.58 }    -- card-space start x per receiver slot
local PB_SIDE = { -1, 1, -1, 1 }           -- which sideline each aligns to (lateral + = toward the middle)
local function pbSeg(parent, x0, y0, x1, y1, color)
	local dx, dy = x1 - x0, y1 - y0
	local f = Instance.new("Frame")
	f.Name = "Seg"; f.BorderSizePixel = 0; f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
	f.Size = UDim2.fromOffset(math.max(3, math.sqrt(dx * dx + dy * dy)), 3)
	f.Rotation = math.deg(math.atan2(dy, dx))
	f.Parent = parent
end
local function pbCard(i)
	if pbCards[i] then return pbCards[i] end
	local card = Instance.new("TextButton")
	card.Name = "Card" .. i; card.Text = ""; card.AutoButtonColor = true
	card.BackgroundColor3 = Color3.fromRGB(10, 22, 40); card.BorderSizePixel = 0
	card.Size = UDim2.fromOffset(204, 170); card.Position = UDim2.fromOffset(12 + (i - 1) * 216, 34)
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)
	local st = Instance.new("UIStroke"); st.Thickness = 2; st.Color = NAVY; st.Parent = card
	local nameL = label(card, { Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(6, 2), Text = "" })
	nameL.Name = "PlayName"
	local mini = Instance.new("Frame"); mini.Name = "Mini"; mini.BorderSizePixel = 0
	mini.BackgroundColor3 = Color3.fromRGB(28, 70, 36); mini.Size = UDim2.fromOffset(192, 134); mini.Position = UDim2.fromOffset(6, 30)
	mini.ClipsDescendants = true
	Instance.new("UICorner", mini).CornerRadius = UDim.new(0, 8)
	local los = Instance.new("Frame"); los.Name = "LOS"; los.BorderSizePixel = 0; los.BackgroundColor3 = WHITE; los.BackgroundTransparency = 0.55
	los.Size = UDim2.fromOffset(192, 2); los.Position = UDim2.fromOffset(0, 108); los.Parent = mini
	mini.Parent = card
	card.MouseButton1Click:Connect(function()
		local idx = card:GetAttribute("PlayIndex")
		if idx and hud and hud.isQB then send({ action = "play", index = idx }) end
	end)
	pbCards[i] = card; card.Parent = pbF
	return card
end
local function pbDraw(card, idx, play, selected)
	card:SetAttribute("PlayIndex", idx)
	card.PlayName.Text = idx .. " · " .. play.name
	card.PlayName.TextColor3 = selected and GOLD or WHITE
	card.UIStroke.Color = selected and GOLD or NAVY
	local mini = card.Mini
	for _, ch in ipairs(mini:GetChildren()) do if ch.Name == "Seg" or ch.Name == "Dot" then ch:Destroy() end end
	local W, losY, H = 192, 108, 134
	local K = (losY - 8) / 27          -- px per metre of route depth (deepest standard route ~27 m)
	local LK = 4.2                     -- px per metre of lateral break
	for r = 1, #play.routes do -- was: 1, 4 — 2v2 plays carry one route; drawing curl for the missing three lied about the play (FEATURE WAVE 2)
		local pts = (Rules.ROUTES[play.routes[r]] or Rules.ROUTES.curl).pts
		local x0, y0 = PB_X[r] * W, losY
		local dot = Instance.new("Frame"); dot.Name = "Dot"; dot.BorderSizePixel = 0; dot.BackgroundColor3 = PB_COLOR[r]
		dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.Size = UDim2.fromOffset(7, 7); dot.Position = UDim2.fromOffset(x0, y0)
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		dot.Parent = mini
		local px, py = x0, y0
		for _, p in ipairs(pts) do
			local nx = math.clamp(x0 - PB_SIDE[r] * p[1] * LK, 4, W - 4)
			local ny = math.clamp(losY - p[2] * K, 4, H - 4)
			pbSeg(mini, px, py, nx, ny, PB_COLOR[r])
			px, py = nx, ny
		end
	end
	local qb = Instance.new("Frame"); qb.Name = "Dot"; qb.BorderSizePixel = 0; qb.BackgroundColor3 = GOOD
	qb.AnchorPoint = Vector2.new(0.5, 0.5); qb.Size = UDim2.fromOffset(9, 9); qb.Position = UDim2.fromOffset(W / 2, losY + 16)
	Instance.new("UICorner", qb).CornerRadius = UDim.new(1, 0)
	qb.Parent = mini
end
local function renderPlaybook(h)
	local show = playbook ~= nil and h ~= nil and h.isQB and h.state == "preSnap" and h.pre == "lineup"
	pbF.Visible = show
	if not show then return end
	local pages = math.max(1, math.ceil(#playbook / 3))
	if pbPage > pages then pbPage = 1 end
	for i = 1, 3 do
		local idx = (pbPage - 1) * 3 + i
		local card = pbCard(i)
		if playbook[idx] then card.Visible = true; pbDraw(card, idx, playbook[idx], h.play == idx)
		else card.Visible = false end
	end
	pbPrev.Visible = pages > 1; pbNext.Visible = pages > 1
end
pbPrev.MouseButton1Click:Connect(function() pbPage = math.max(1, pbPage - 1); renderPlaybook(hud) end)
pbNext.MouseButton1Click:Connect(function() pbPage = pbPage + 1; renderPlaybook(hud) end)
-- ============================ end play-call dashboard
local cdPips = {}
local leaveB = button(hudF, "X  LEAVE", { Size = UDim2.fromOffset(120, 34), Position = UDim2.new(1, -134, 0, 20) })
leaveB.MouseButton1Click:Connect(function() send({ action = "leave" }) end)

-------------------------------------------------------------------------------------------------- rules HUD: series, clock, try, flags, reasons
-- PRESENTATION ONLY. Every rule number is read from AWFootball.Config; every down, score, spot and penalty is what the
-- server's hud message says. Structured fields (h.series, h.clock, h.try, h.flag, h.feedback.reason) are preferred;
-- until the server sends them, the series line falls back to parsing h.down and the other elements stay hidden.
local CFG = require(folder:WaitForChild("Config"))
local Rules = require(folder:WaitForChild("Rules")) -- route shapes for the play-call dashboard (2026-11-02)
local TweenService = game:GetService("TweenService")
local MUTED = Color3.fromRGB(170, 182, 200)
local TEAMNAME = { home = "HOME", away = "AWAY" }
local ORD = { "1st", "2nd", "3rd", "4th" }
local function ord(n) return n and (ORD[n] or (tostring(n) .. "th")) or "" end
local function yardsOf(m) return (m and CFG.YARD) and math.floor(m / CFG.YARD + 0.5) or nil end
local function viewK()
	local vp = workspace.CurrentCamera.ViewportSize
	return math.clamp(math.min(vp.X / 1100, vp.Y / 640), 0.55, 1)   -- same phone scaling as BroadcastHUD
end
local rulesScales = {}
local function uiScale(f) local s = Instance.new("UIScale"); s.Parent = f; table.insert(rulesScales, s); return s end

-- series strip: sits directly under BroadcastHUD's score bug (or our own board when the bug is down)
local seriesF = panel(hudF, { Name = "SeriesStrip", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(520, 56), Position = UDim2.new(0.5, 0, 0, 100) })
local sst = Instance.new("UIStroke", seriesF); sst.Color = GOLD; sst.Thickness = 2; sst.Transparency = 0.3
uiScale(seriesF)
local seriesL = label(seriesF, { Size = UDim2.new(1, -176, 0, 28), Position = UDim2.fromOffset(12, 5), Text = "", TextXAlignment = Enum.TextXAlignment.Left })
local seriesTag = label(seriesF, { Size = UDim2.new(1, -176, 0, 16), Position = UDim2.fromOffset(12, 35), Text = "", TextColor3 = GOLD, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left })
local sdiv = Instance.new("Frame"); sdiv.BorderSizePixel = 0; sdiv.BackgroundColor3 = GOLD; sdiv.BackgroundTransparency = 0.5; sdiv.Size = UDim2.new(0, 2, 1, -14); sdiv.Position = UDim2.new(1, -160, 0, 7); sdiv.Parent = seriesF
local halfL = label(seriesF, { Size = UDim2.fromOffset(144, 16), Position = UDim2.new(1, -152, 0, 6), Text = "", TextColor3 = MUTED, Font = Enum.Font.GothamBold })
local clockL = label(seriesF, { Size = UDim2.fromOffset(144, 28), Position = UDim2.new(1, -152, 0, 23), Text = "" })
-- final-window bar: which events stop the clock, straight from CFG.clock.stopOn
local stopF = panel(seriesF, { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.new(0, 0, 1, 4), BackgroundColor3 = GOLD, BackgroundTransparency = 0.05, Visible = false })
local stopHead = label(stopF, { Size = UDim2.new(1, -16, 0, 14), Position = UDim2.fromOffset(8, 3), Text = "", TextColor3 = NAVY })
local stopList = label(stopF, { Size = UDim2.new(1, -16, 0, 13), Position = UDim2.fromOffset(8, 18), Text = "", TextColor3 = NAVY, Font = Enum.Font.GothamBold })
do
	local C = CFG.clock or {}
	local NAMES = { incomplete = "INCOMPLETE", outOfBounds = "OUT OF BOUNDS", firstDown = "FIRST DOWN", score = "SCORE", penalty = "PENALTY", timeout = "TIMEOUT" }
	local ORDER = { "incomplete", "outOfBounds", "firstDown", "score", "penalty", "timeout" }
	local parts = {}
	for _, k in ipairs(ORDER) do if C.stopOn and C.stopOn[k] then table.insert(parts, NAMES[k]) end end
	for k, v in pairs(C.stopOn or {}) do if v and not NAMES[k] then table.insert(parts, string.upper(k)) end end
	stopHead.Text = "FINAL " .. tostring(C.stopClockWindowSeconds or "") .. "s · THE CLOCK NOW STOPS ON"
	stopList.Text = table.concat(parts, " · ")
end

-- penalty flag card: top-left, clear of the score bug and of BroadcastHUD's lower-left result card
local flagF = panel(hudF, { Name = "FlagCard", Size = UDim2.fromOffset(250, 104), Position = UDim2.fromOffset(16, 14), Visible = false })
local fst = Instance.new("UIStroke", flagF); fst.Color = GOLD; fst.Thickness = 2; fst.Transparency = 0.2
uiScale(flagF)
local flagBar = Instance.new("Frame"); flagBar.BorderSizePixel = 0; flagBar.BackgroundColor3 = GOLD; flagBar.Size = UDim2.new(0, 8, 1, -14); flagBar.Position = UDim2.fromOffset(8, 7); flagBar.Parent = flagF
local flagHead = label(flagF, { Size = UDim2.new(1, -34, 0, 18), Position = UDim2.fromOffset(24, 6), Text = "FLAG", TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
local flagFoul = label(flagF, { Size = UDim2.new(1, -34, 0, 28), Position = UDim2.fromOffset(24, 25), Text = "", TextXAlignment = Enum.TextXAlignment.Left })
local flagTeam = label(flagF, { Size = UDim2.new(1, -34, 0, 16), Position = UDim2.fromOffset(24, 56), Text = "", Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left })
local flagCons = label(flagF, { Size = UDim2.new(1, -34, 0, 20), Position = UDim2.fromOffset(24, 76), Text = "", TextXAlignment = Enum.TextXAlignment.Left })
local lastFlagId = nil

-- try declaration: bottom-centre, above the play chips and prompt, between the touch clusters
local tryF = Instance.new("Frame"); tryF.Name = "TryDeclare"; tryF.BackgroundTransparency = 1; tryF.AnchorPoint = Vector2.new(0.5, 1)
tryF.Size = UDim2.new(0.44, 0, 0, 96); tryF.Position = UDim2.new(0.5, 0, 1, -160); tryF.Visible = false; tryF.Parent = hudF
local tsc = Instance.new("UISizeConstraint", tryF); tsc.MaxSize = Vector2.new(560, 96)
local tryTitle = label(tryF, { Size = UDim2.new(1, 0, 0, 22), Text = "DECLARE THE TRY", TextColor3 = GOLD, TextStrokeTransparency = 0.3 })
local tryBtns = {}
local tryChoice = nil   -- what I pressed, highlighted until the server's h.try answers
local function canDeclare(h) return h ~= nil and type(h.try) == "table" and h.try.phase == "declare" and h.offense == h.myTeam and h.try.canDeclare ~= false end
local function inputHint()
	local t = UIS:GetLastInputType()
	if string.find(t.Name, "Gamepad") then return "gamepad" end
	if t == Enum.UserInputType.Touch then return "touch" end
	return "keyboard"
end
local renderTry
local function declareTry(n)
	if not canDeclare(hud) then return end
	tryChoice = n
	send({ action = "declareTry", declared = n })
	renderTry(hud)
end
do
	local S = CFG.scoring or {}
	for n = 1, 2 do
		local pts = n == 2 and S.try2 or S.try1
		local spot = yardsOf(n == 2 and S.try2SpotM or S.try1SpotM)
		local passOnly = if n == 2 then S.try2PassOnly == true else S.try1PassOnly == true
		local b = button(tryF, "", { Size = UDim2.new(0.5, -4, 0, 70), Position = UDim2.new((n - 1) * 0.5, n == 2 and 4 or 0, 0, 26) })
		local st = Instance.new("UIStroke", b); st.Color = GOLD; st.Thickness = 2; st.Transparency = 0.3; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local head = label(b, { Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 4), Text = "+" .. tostring(pts) .. (pts == 1 and " PT" or " PTS") .. " · FROM THE " .. tostring(spot) })
		local sub = label(b, { Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(6, 31), Font = Enum.Font.GothamBold,
			Text = passOnly and "PASS ONLY · A RUN SCORES 0" or "RUN OR PASS", TextColor3 = passOnly and GOLD or MUTED })
		local key = label(b, { Size = UDim2.new(1, -12, 0, 13), Position = UDim2.fromOffset(6, 52), Font = Enum.Font.GothamBold, Text = "", TextColor3 = MUTED })
		b.Activated:Connect(function() declareTry(n) end)
		tryBtns[n] = { b = b, head = head, sub = sub, key = key, passOnly = passOnly }
	end
end
renderTry = function(h)
	local declaring = h ~= nil and type(h.try) == "table" and h.try.phase == "declare"
	if not declaring then tryChoice = nil end
	local show = canDeclare(h)
	tryF.Visible = show
	if not show then return end
	local hint = inputHint()
	for n, t in pairs(tryBtns) do
		local on = tryChoice == n or h.try.declared == n
		t.b.BackgroundColor3 = on and GOLD or NAVY
		t.head.TextColor3 = on and NAVY or WHITE
		t.sub.TextColor3 = on and NAVY or (t.passOnly and GOLD or MUTED)
		t.key.TextColor3 = on and NAVY or MUTED
		t.key.Text = hint == "gamepad" and (n == 1 and "◀ D-PAD" or "D-PAD ▶") or hint == "keyboard" and ("PRESS " .. n) or "TAP"
	end
	tryTitle.Text = "DECLARE THE TRY" .. (h.try.timeLeft and (" · " .. math.ceil(h.try.timeLeft)) or "")
end

-- outcome reason: one line under the feedback headline, to whoever the server addressed it
local fbReasonL = label(hudF, { Size = UDim2.fromOffset(600, 26), Position = UDim2.new(0.5, -300, 0.33, 58), Visible = false, TextStrokeTransparency = 0.3, Font = Enum.Font.GothamBold })

-- the series as the ruleset reads: "2nd & TO MIDFIELD" behind the middle line, "2nd & GOAL" after it
local function seriesInfo(h)
	if type(h.series) == "table" then return h.series.down, h.series.toGain == "goal" end
	local txt = tostring(h.down or "")
	return tonumber(string.match(txt, "^(%d)")), string.find(string.upper(txt), "GOAL", 1, true) ~= nil
end
local function tryText(t)
	local S = CFG.scoring or {}
	if t.phase == "declare" then
		return "TRY · " .. (TEAMNAME[t.team] or "OFFENSE") .. " DECLARES " .. tostring(S.try1) .. " OR " .. tostring(S.try2),
			"+" .. tostring(S.try1) .. " FROM THE " .. tostring(yardsOf(S.try1SpotM)) .. ": " .. (S.try1PassOnly and "PASS ONLY" or "RUN OR PASS")
			.. "  ·  +" .. tostring(S.try2) .. " FROM THE " .. tostring(yardsOf(S.try2SpotM)) .. ": " .. (S.try2PassOnly and "PASS ONLY" or "RUN OR PASS")
	end
	local two = t.declared == 2
	local passOnly = if two then S.try2PassOnly == true else S.try1PassOnly == true
	return "TRY FOR " .. tostring(two and S.try2 or S.try1) .. " · FROM THE " .. tostring(yardsOf(two and S.try2SpotM or S.try1SpotM)) .. " · " .. (passOnly and "PASS ONLY" or "RUN OR PASS"),
		passOnly and "A RUN CANNOT SCORE THIS TRY" or "ONE PLAY · RUN OR PASS IT IN"
end
local function seriesText(h)
	if h.state == "final" then return "FINAL", "" end
	if type(h.try) == "table" then return tryText(h.try) end
	local d, goal = seriesInfo(h)
	if not d then return tostring(h.down or ""), "" end
	local main = ord(d) .. " & " .. (goal and "GOAL" or "TO MIDFIELD")
	local SR = CFG.series or {}
	local tag = ""
	if SR.firstDownOnlyAtMiddle then
		if not goal then tag = "CROSS MIDFIELD FOR YOUR ONE FIRST DOWN"
		elseif SR.downsPerSeries and d >= SR.downsPerSeries then tag = "NO MORE FIRST DOWNS · LAST DOWN TO SCORE"
		elseif SR.downsPerSeries then tag = "NO MORE FIRST DOWNS · " .. (SR.downsPerSeries - d + 1) .. " DOWNS TO SCORE"
		else tag = "NO MORE FIRST DOWNS · SCORE OR TURN IT OVER" end
	end
	return main, tag
end

local clockBase = nil
local function renderClock(h)
	local c, C = h.clock, CFG.clock or {}
	if type(c) ~= "table" or c.remaining == nil then clockBase = nil; halfL.Text = ""; clockL.Text = ""; stopF.Visible = false; return end
	clockBase = { remaining = c.remaining, at = os.clock(), running = c.running == true }
	local ot = C.halves and c.half and c.half > C.halves
	halfL.Text = (ot and "OVERTIME" or (c.half and (string.upper(ord(c.half)) .. " HALF") or "")) .. (c.play and (" · PLAY " .. math.ceil(c.play)) or "")
	local inWindow = c.stopWindow
	if inWindow == nil then inWindow = C.stopClockWindowSeconds ~= nil and c.remaining <= C.stopClockWindowSeconds and not ot end
	stopF.Visible = inWindow == true and h.state ~= "final"
end
local function tickClock()
	if not clockBase then return end
	local r = math.max(0, clockBase.remaining - (clockBase.running and (os.clock() - clockBase.at) or 0))
	clockL.Text = string.format("%d:%02d", r // 60, math.floor(r % 60))
	clockL.TextColor3 = clockBase.running and WHITE or GOLD   -- gold = clock stopped
end

local function renderFlag(h)
	local fl = h.flag
	local F = type(fl) == "table" and CFG.penalty and CFG.penalty.fouls and CFG.penalty.fouls[fl.foul]
	if type(fl) ~= "table" or not (F or fl.label) then flagF.Visible = false; lastFlagId = nil; return end
	F = F or {}
	flagFoul.Text = fl.label or F.label or ""
	flagTeam.Text = fl.team and ((TEAMNAME[fl.team] or "") .. (fl.team == h.offense and " · OFFENSE" or " · DEFENSE")) or ""
	flagTeam.TextColor3 = TEAMCOLOR[fl.team] or WHITE
	local yds = fl.yards; if yds == nil then yds = F.yards end
	local fd = fl.firstDown; if fd == nil then fd = F.firstDown end
	local lod = fl.lossOfDown; if lod == nil then lod = F.lossOfDown end
	local parts = {}
	if yds and yds ~= 0 then table.insert(parts, (yds > 0 and "+" or "−") .. math.floor(math.abs(yds) + 0.5)) end
	if fl.halved then table.insert(parts, "HALF THE DISTANCE") end
	if fd then table.insert(parts, "AUTOMATIC FIRST DOWN") end
	if lod then table.insert(parts, "LOSS OF DOWN") end
	if fl.replayDown then table.insert(parts, "REPLAY THE DOWN") end
	flagCons.Text = table.concat(parts, " · ")
	flagCons.TextColor3 = fl.team == h.myTeam and BAD or GOOD
	if not flagF.Visible or fl.id ~= lastFlagId then
		lastFlagId = fl.id
		flagF.Position = UDim2.fromOffset(-300, 14)
		TweenService:Create(flagF, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(16, 14) }):Play()
	end
	flagF.Visible = true
end

local function placeRules()
	local k = viewK()
	for _, s in ipairs(rulesScales) do s.Scale = k end
	local bc = player.PlayerGui:FindFirstChild("AWBroadcast")
	local bug = bc and bc:FindFirstChild("ScoreBug")
	local top = (bc and bc.Enabled and bug and bug.Visible) and (12 + 88 * k + 4) or (board.Visible and 100 or 14)
	seriesF.Position = UDim2.new(0.5, 0, 0, top)
end

local function renderRules(h)
	local main, tag = seriesText(h)
	seriesL.Text = main; seriesTag.Text = tag
	downL.Text = main
	renderClock(h); tickClock()
	renderFlag(h)
	renderTry(h)
	local reason = h.feedback and h.feedback.reason
	fbReasonL.Visible = reason ~= nil and reason ~= ""
	fbReasonL.Text = reason and string.upper(tostring(reason)) or ""
	fbReasonL.TextColor3 = h.feedback and fbColor(h.feedback.kind) or WHITE
	placeRules()
end

-- touch buttons (phones / tablets)
local touchF = Instance.new("Frame"); touchF.BackgroundTransparency = 1; touchF.Size = UDim2.fromScale(1, 1); touchF.Visible = UIS.TouchEnabled; touchF.Parent = hudF
local function tbtn(text, pos, size, color)
	local b = button(touchF, text, { Size = UDim2.fromOffset(size, size), Position = pos }, color or WHITE)
	b:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
	return b
end
local goB = tbtn("GO", UDim2.new(1, -124, 1, -250), 100, GOLD)
local fB = tbtn("CATCH", UDim2.new(1, -230, 1, -320), 70, GOOD)
local rB = tbtn("HIT", UDim2.new(1, -230, 1, -130), 70, BAD)
local jlB = tbtn("◀", UDim2.new(1, -310, 1, -200), 60)
local jrB = tbtn("▶", UDim2.new(1, -120, 1, -130), 60)
local spinB = tbtn("SPIN", UDim2.new(1, -310, 1, -280), 60)
local flipB = tbtn("FLIP", UDim2.new(0, 30, 1, -260), 70)
local callB = tbtn("CALL", UDim2.new(0, 30, 1, -350), 70, GOOD)
local throwBs = {}
for i = 1, 4 do
	local b = tbtn(tostring(i), UDim2.new(1, -90 - (i - 1) * 76, 0, 120), 66, GOLD)
	b.Visible = false
	throwBs[i] = b
end

local function airTime() if ballState.mode == "flight" then return workspace:GetServerTimeNow() - ballState.t0 end return nil end
local function humanoid()
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end
local function leap()
	local hum = humanoid()
	if not hum then return end
	hum.UseJumpPower = true; hum.JumpPower = 42
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
	task.delay(0.15, function() if hum.Parent then hum.JumpPower = 0 end end)
end
local function primary()
	send({ action = "primary", airTime = airTime() })
	if ballState.mode == "flight" and ballState.high then leap() end
end
local function aggressive(lob)
	local off = hud and hud.offense == hud.myTeam
	if hud and hud.isQB and hud.phase == "pocket" then send({ action = "throwAim", aim = workspace.CurrentCamera.CFrame.LookVector, lob = lob }); return end
	send({ action = off and "catchAggressive" or "swat", airTime = airTime() })
	if ballState.mode == "flight" and ballState.high then leap() end
end
local function hit() local off = hud and hud.offense == hud.myTeam; send({ action = off and "stiffarm" or "tackle" }) end
goB.MouseButton1Down:Connect(primary)
fB.MouseButton1Down:Connect(function() holdStart.F = os.clock(); if not (hud and hud.isQB) then aggressive(false) end end)
fB.MouseButton1Up:Connect(function() if hud and hud.isQB and holdStart.F then aggressive(os.clock() - holdStart.F >= 0.35) end; holdStart.F = nil end)
rB.MouseButton1Down:Connect(hit)
jlB.MouseButton1Down:Connect(function() send({ action = "jukeL" }) end)
jrB.MouseButton1Down:Connect(function() send({ action = "jukeR" }) end)
spinB.MouseButton1Down:Connect(function() send({ action = "spin" }) end)
flipB.MouseButton1Down:Connect(function() send({ action = "flip" }) end)
callB.MouseButton1Down:Connect(function() send({ action = "call" }) end)
for i, b in ipairs(throwBs) do
	b.MouseButton1Down:Connect(function() holdStart[i] = os.clock() end)
	b.MouseButton1Up:Connect(function()
		if holdStart[i] then send({ action = "throw", target = i, lob = os.clock() - holdStart[i] >= 0.35 }) end
		holdStart[i] = nil
	end)
end

local function renderHud(h)
	homeS.Text = tostring(h.home); awayS.Text = tostring(h.away)
	downL.Text = h.down or ""
	possL.Text = h.mode .. " · POSSESSION " .. (h.possession or "")
	local onO = h.offense == h.myTeam
	roleL.Text = "YOU: " .. (h.role or "") .. " · " .. (h.myTeam == "home" and "HOME" or "AWAY") .. (onO and " (offense)" or " (defense)")
	roleL.TextColor3 = TEAMCOLOR[h.myTeam] or WHITE
	local call = h.message == "SET…" or h.message == "HUT!"
	bigL.Visible = call; bigL.Text = h.message or ""; bigL.TextColor3 = h.message == "HUT!" and GOOD or GOLD
	msgF.Visible = h.message ~= nil and not call; msgL.Text = h.message or ""
	if h.feedback then fbL.Visible = true; fbL.Text = h.feedback.text; fbL.TextColor3 = fbColor(h.feedback.kind) else fbL.Visible = false end
	promptF.Visible = h.prompt ~= nil; promptL.Text = h.prompt or ""
	-- chips: QB calls plays, receivers pick routes (pre-snap only)
	local n = 0
	if h.state == "preSnap" and onO then
		if h.isQB and h.plays and not playbook then -- was: not (playbook and h.pre == "lineup") — 15 plays overflow the chip row, so the dashboard owns QB play calls whenever it has data; chips stay as the legacy fallback (FEATURE WAVE 2)
			for i, name in ipairs(h.plays) do
				local b = chip(i); b.Visible = true; b.Text = i .. " " .. name
				b.BackgroundColor3 = i == h.play and GOLD or NAVY; b.TextColor3 = i == h.play and NAVY or WHITE
				n = i
			end
		elseif not h.isQB then
			for i, id in ipairs(ROUTE_KEYS) do
				local b = chip(i); b.Visible = true; b.Text = i .. " " .. ROUTE_LABEL[id]
				b.BackgroundColor3 = id == h.route and GOLD or NAVY; b.TextColor3 = id == h.route and NAVY or WHITE
				n = i
			end
		end
	end
	for i, b in pairs(chips) do if i > n then b.Visible = false end end
	chipsF.Visible = n > 0
	-- touch layout by role
	local pocketQB = h.isQB and h.phase == "pocket" and h.state == "live"
	for i, b in ipairs(throwBs) do
		local r = h.receivers and h.receivers[i]
		b.Visible = pocketQB and r ~= nil
		if r then b.Text = tostring(i); b.BackgroundColor3 = r.open and GOOD or GOLD end
	end
	fB.Text = h.isQB and "THROW" or (onO and "CATCH" or "SWAT")
	rB.Text = onO and "ARM" or "HIT"
	callB.Visible = onO and not h.isQB
	flipB.Visible = not onO
	goB.Text = (h.isQB and h.state == "preSnap") and (h.pre == "lineup" and "SET" or "HUT") or (h.phase == "flight" and "CATCH" or "GO")
	for _, c in ipairs(h.cooldowns or {}) do
		local pip = cdPips[c[1]]
		if not pip then
			pip = panel(cdF, { Size = UDim2.fromOffset(80, 28) })
			local fill = Instance.new("Frame"); fill.Name = "Fill"; fill.BorderSizePixel = 0; fill.BackgroundColor3 = GOLD; fill.BackgroundTransparency = 0.4; fill.Parent = pip
			Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 12)
			label(pip, { Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), Text = c[1], Font = Enum.Font.GothamBold, ZIndex = 2 })
			cdPips[c[1]] = pip
		end
		pip.Visible = true; pip.Fill.Size = UDim2.fromScale(c[2], 1)
	end
	-- sprint stamina rides the same pip row (2026-11-02): green while sprinting, gold while recovering
	if h.sprint and h.state == "live" then
		local pip = cdPips.SPRINT
		if not pip then
			pip = panel(cdF, { Size = UDim2.fromOffset(80, 28) })
			local fill = Instance.new("Frame"); fill.Name = "Fill"; fill.BorderSizePixel = 0; fill.BackgroundColor3 = GOLD; fill.BackgroundTransparency = 0.4; fill.Parent = pip
			Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 12)
			label(pip, { Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), Text = "SPRINT", Font = Enum.Font.GothamBold, ZIndex = 2 })
			cdPips.SPRINT = pip
		end
		pip.Visible = true
		pip.Fill.Size = UDim2.fromScale(math.clamp(h.sprint.stamina / math.max(h.sprint.max, 0.01), 0, 1), 1)
		pip.Fill.BackgroundColor3 = h.sprint.on and GOOD or GOLD
	end
	local keep = { SPRINT = h.sprint ~= nil and h.state == "live" }
	for _, c in ipairs(h.cooldowns or {}) do keep[c[1]] = true end
	for k, pip in pairs(cdPips) do if not keep[k] then pip.Visible = false end end
	renderRules(h)
end

-------------------------------------------------------------------------------------------------- world visuals
local vfolder
local function vpart(name, size, color, mat)
	local p = Instance.new("Part")
	p.Name = name; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Size = size; p.Color = color; p.Material = mat or Enum.Material.Neon; p.Parent = vfolder
	return p
end
local function buildVisuals()
	if vfolder then vfolder:Destroy() end
	vfolder = Instance.new("Folder"); vfolder.Name = "AWTeamFootballVisuals"; vfolder.Parent = workspace
	visuals = {}
	-- was 0.8 x 0.5 x 0.5 SmoothPlastic (110,58,30): true-to-life but reads tiny; owner approved 1.75x leather in the 2026-11-02 playtest
	local ball = vpart("Football", Vector3.new(1.4, 0.85, 0.85), Color3.fromRGB(146, 76, 36), Enum.Material.Leather)
	local mesh = Instance.new("SpecialMesh"); mesh.MeshType = Enum.MeshType.Sphere; mesh.Parent = ball
	visuals.ball = ball
	-- catch sense: a comet trail in flight and an outline that flips white when the catch window opens
	local ta0 = Instance.new("Attachment"); ta0.Position = Vector3.new(-0.6, 0, 0); ta0.Parent = ball
	local ta1 = Instance.new("Attachment"); ta1.Position = Vector3.new(0.6, 0, 0); ta1.Parent = ball
	local tr = Instance.new("Trail"); tr.Attachment0 = ta0; tr.Attachment1 = ta1
	tr.Color = ColorSequence.new(GOLD)
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	tr.Lifetime = 0.35; tr.Enabled = false; tr.Parent = ball
	visuals.trail = tr
	local hl = Instance.new("Highlight"); hl.FillTransparency = 1; hl.OutlineColor = GOLD; hl.OutlineTransparency = 1; hl.Parent = ball
	visuals.glow = hl
	visuals.lace = vpart("Lace", Vector3.new(0.5, 0.08, 0.1), WHITE, Enum.Material.SmoothPlastic) -- was 0.3 x 0.05 x 0.06
	local ret = vpart("Reticle", Vector3.new(0.1, 4, 4), GOLD); ret.Shape = Enum.PartType.Cylinder; ret.Transparency = 1
	visuals.reticle = ret
	visuals.los = vpart("LOS", Vector3.new(1, 0.06, 0.5), Color3.fromRGB(58, 160, 255)); visuals.los.Transparency = 0.2
	visuals.gain = vpart("ToGain", Vector3.new(1, 0.06, 0.5), Color3.fromRGB(255, 220, 60)); visuals.gain.Transparency = 0.25
	-- line-to-gain pylons on both sidelines, each labelled MIDFIELD or GOAL LINE
	visuals.gainPylons = {}
	for i = 1, 2 do
		local py = vpart("ToGainPylon", Vector3.new(0.7, 3.2, 0.7), Color3.fromRGB(255, 220, 60))
		local bb = Instance.new("BillboardGui"); bb.Name = "GainTag"; bb.Size = UDim2.fromOffset(190, 30); bb.StudsOffset = Vector3.new(0, 3, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 260
		local t = Instance.new("TextLabel"); t.Name = "T"; t.Size = UDim2.fromScale(1, 1); t.BackgroundColor3 = NAVY; t.BackgroundTransparency = 0.18
		t.Font = Enum.Font.GothamBlack; t.TextScaled = true; t.TextColor3 = GOLD; t.Text = ""; t.Parent = bb
		Instance.new("UICorner", t).CornerRadius = UDim.new(0, 8)
		local pad = Instance.new("UIPadding", t); pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6); pad.PaddingTop = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)
		bb.Adornee = py; bb.Parent = py
		visuals.gainPylons[i] = py
	end
	local ring = vpart("ManRing", Vector3.new(0.08, 3.4, 3.4), BAD); ring.Shape = Enum.PartType.Cylinder; ring.Transparency = 1
	visuals.ring = ring
	visuals.route = {}
	visuals.tags = {}
end
local function clearVisuals()
	if vfolder then vfolder:Destroy() end
	for _, t in pairs(visuals.tags or {}) do t:Destroy() end
	vfolder = nil; visuals = {}
end
local function drawRoutes(lines)
	for _, p in ipairs(visuals.route or {}) do p:Destroy() end
	visuals.route = {}
	for _, pts in ipairs(lines or {}) do
		for i = 1, #pts - 1 do
			local a, b = pts[i] + Vector3.new(0, 0.12, 0), pts[i + 1] + Vector3.new(0, 0.12, 0)
			local n = math.max(1, math.floor((b - a).Magnitude / 2.4))
			for k = 0, n - 1 do
				if k % 2 == 0 then
					local p0 = a:Lerp(b, k / n); local p1 = a:Lerp(b, math.min(1, (k + 1) / n))
					local seg = vpart("RouteDash", Vector3.new(0.45, 0.05, (p1 - p0).Magnitude), BLUE)
					seg.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
					table.insert(visuals.route, seg)
				end
			end
		end
		if #pts >= 2 then
			local cap = vpart("RouteEnd", Vector3.new(1.4, 0.06, 1.4), BLUE); cap.CFrame = CFrame.new(pts[#pts] + Vector3.new(0, 0.12, 0))
			table.insert(visuals.route, cap)
		end
	end
end
-- QB sees receiver numbers over their heads (green = open)
local function updateTags(h)
	local want = {}
	for _, r in ipairs((h.isQB and h.receivers) or {}) do
		local head = r.model and r.model:FindFirstChild("Head")
		if head then
			want[r.model] = true
			local bb = visuals.tags[r.model]
			if not bb then
				bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(46, 46); bb.StudsOffset = Vector3.new(0, 4.6, 0); bb.AlwaysOnTop = true
				local t = Instance.new("TextLabel"); t.Name = "N"; t.Size = UDim2.fromScale(1, 1); t.Font = Enum.Font.GothamBlack; t.TextScaled = true; t.TextColor3 = NAVY; t.Parent = bb
				Instance.new("UICorner", t).CornerRadius = UDim.new(1, 0)
				bb.Adornee = head; bb.Parent = player.PlayerGui
				visuals.tags[r.model] = bb
			end
			bb.N.Text = tostring(r.n); bb.N.BackgroundColor3 = r.called and BLUE or (r.open and GOOD or GOLD)
		end
	end
	for m, bb in pairs(visuals.tags) do if not want[m] then bb:Destroy(); visuals.tags[m] = nil end end
end

-------------------------------------------------------------------------------------------------- keyboard / gamepad
local function onAction(name, inputState, input)
	if mode ~= "game" then return Enum.ContextActionResult.Pass end
	local began = inputState == Enum.UserInputState.Begin
	local ended = inputState == Enum.UserInputState.End
	if name == "AWTTry1" or name == "AWTTry2" then
		if not canDeclare(hud) then return Enum.ContextActionResult.Pass end
		if began then declareTry(name == "AWTTry2" and 2 or 1) end
		return Enum.ContextActionResult.Sink
	end
	local num = tonumber(name:match("^AWT(%d)$"))
	if num and canDeclare(hud) then
		if began and (num == 1 or num == 2) then declareTry(num) end
		return Enum.ContextActionResult.Sink
	end
	if num then
		if hud and hud.state == "preSnap" then
			if began then
				if hud.isQB then send({ action = "play", index = num })
				elseif hud.offense == hud.myTeam and ROUTE_KEYS[num] then send({ action = "route", route = ROUTE_KEYS[num] }) end
			end
		elseif hud and hud.isQB and hud.phase == "pocket" then
			if began then holdStart[num] = os.clock()
			elseif ended and holdStart[num] then
				local held = os.clock() - holdStart[num]
				-- pump fake (FEATURE WAVE 2): modifier held + a tap under 0.25 s = pump, not a throw; plain taps throw exactly as before
				if pumpMod and held < 0.25 then send({ action = "pump", target = num })
				else send({ action = "throw", target = num, lob = held >= 0.35 }) end -- was: send throw with lob = held >= 0.35 (unchanged path)
				holdStart[num] = nil
			end
		end
		return Enum.ContextActionResult.Sink
	end
	if name == "AWTF" then
		if hud and hud.isQB and hud.phase == "pocket" then
			if began then holdStart.F = os.clock() elseif ended and holdStart.F then aggressive(os.clock() - holdStart.F >= 0.35); holdStart.F = nil end
		elseif began then aggressive(false) end
		return Enum.ContextActionResult.Sink
	end
	if name == "AWTFlip" then
		-- Shift/L3 is the burst key (2026-11-02): tapping still flips a pedaling DB; HOLDING it sprints (both sides)
		if began then send({ action = "flip" }); send({ action = "sprint", on = true })
		elseif ended then send({ action = "sprint", on = false }) end
		return Enum.ContextActionResult.Sink
	end
	if name == "AWTSpin" and hud and hud.isQB and hud.phase == "pocket" then
		-- in the pocket C/ButtonY is the pump-fake modifier (spin is a carrier move and does nothing here anyway)
		pumpMod = began
		return Enum.ContextActionResult.Sink
	end
	if not began then return Enum.ContextActionResult.Sink end
	if name == "AWTPrimary" then primary()
	elseif name == "AWTHit" then hit()
	elseif name == "AWTJukeL" then send({ action = "jukeL" })
	elseif name == "AWTJukeR" then send({ action = "jukeR" })
	elseif name == "AWTSpin" then send({ action = "spin" })
	elseif name == "AWTCall" then send({ action = "call" })
	elseif name == "AWTLeave" then send({ action = "leave" }) end
	return Enum.ContextActionResult.Sink
end
local ACTIONS = { "AWTPrimary", "AWTF", "AWTHit", "AWTJukeL", "AWTJukeR", "AWTSpin", "AWTFlip", "AWTCall", "AWTLeave", "AWT1", "AWT2", "AWT3", "AWT4", "AWT5", "AWT6", "AWTTry1", "AWTTry2" }
local function bindAll()
	local P = 3001
	CAS:BindActionAtPriority("AWTPrimary", onAction, false, P, Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.PlayerActions.CharacterJump)
	CAS:BindActionAtPriority("AWTF", onAction, false, P, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
	CAS:BindActionAtPriority("AWTHit", onAction, false, P, Enum.KeyCode.R, Enum.KeyCode.ButtonB)
	CAS:BindActionAtPriority("AWTJukeL", onAction, false, P, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	CAS:BindActionAtPriority("AWTJukeR", onAction, false, P, Enum.KeyCode.E, Enum.KeyCode.ButtonR1)
	CAS:BindActionAtPriority("AWTSpin", onAction, false, P, Enum.KeyCode.C, Enum.KeyCode.ButtonY)
	CAS:BindActionAtPriority("AWTFlip", onAction, false, P, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	CAS:BindActionAtPriority("AWTCall", onAction, false, P, Enum.KeyCode.G, Enum.KeyCode.ButtonR2)
	CAS:BindActionAtPriority("AWTLeave", onAction, false, P, Enum.KeyCode.X)
	-- try declaration on gamepad (keyboard uses 1 / 2, touch taps the buttons); passes through when no try is pending
	CAS:BindActionAtPriority("AWTTry1", onAction, false, P, Enum.KeyCode.DPadLeft)
	CAS:BindActionAtPriority("AWTTry2", onAction, false, P, Enum.KeyCode.DPadRight)
	local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six }
	for i, k in ipairs(keys) do CAS:BindActionAtPriority("AWT" .. i, onAction, false, P, k) end
end
local function unbindAll() for _, n in ipairs(ACTIONS) do CAS:UnbindAction(n) end end

-------------------------------------------------------------------------------------------------- server messages
local function toast(text)
	local g2 = Instance.new("ScreenGui"); g2.Name = "AWTeamToast"; g2.ResetOnSpawn = false; g2.Parent = player.PlayerGui
	local f = panel(g2, { Size = UDim2.fromOffset(560, 50), Position = UDim2.new(0.5, -280, 0.3, 0) })
	label(f, { Size = UDim2.new(1, -20, 1, -12), Position = UDim2.fromOffset(10, 6), Text = text, TextColor3 = GOLD })
	task.delay(2.8, function() g2:Destroy() end)
end
local function stopGame()
	unbindAll(); clearVisuals()
	hud = nil; lunge = nil; pedalFace = nil; ballState = { mode = "hidden" }; pumpMod = false
	clockBase = nil; lastFlagId = nil; tryChoice = nil; flagF.Visible = false; tryF.Visible = false
	local hum = humanoid(); if hum then hum.AutoRotate = true end
	hudF.Visible = false
end

State.OnClientEvent:Connect(function(m)
	if m.kind == "lobby" then
		if mode ~= "game" then mode = "lobby"; gui.Enabled = true; lobbyF.Visible = true; hudF.Visible = false end
		renderLobby(m)
	elseif m.kind == "queued" then
		mode = "queued"; gui.Enabled = true; lobbyF.Visible = false
		toast("Queued for " .. (m.team == "home" and "HOME" or "AWAY") .. " on " .. m.field)
	elseif m.kind == "start" then
		mode = "game"; field = m.field; gui.Enabled = true; lobbyF.Visible = false; hudF.Visible = true
		playbook = m.playbook; pbPage = 1 -- play-call dashboard data (2026-11-02)
		buildVisuals(); bindAll()
	elseif m.kind == "hud" then
		if mode ~= "game" then return end
		hud = m
		renderHud(m)
		renderPlaybook(m)
		if visuals.los and field then
			visuals.los.Size = Vector3.new(field.halfW * 2, 0.06, 0.5)
			visuals.los.CFrame = CFrame.new(field.cx, field.floorY + 0.1, m.losZ)
			visuals.gain.Size = Vector3.new(field.halfW * 2, 0.06, 0.6)
			visuals.gain.CFrame = CFrame.new(field.cx, field.floorY + 0.11, m.toGainZ)
			-- the line to gain stays on the field all game (midfield until crossed, then the goal line)
			local showGain = m.state ~= "final"
			visuals.gain.Transparency = showGain and 0.2 or 1
			local _, goal = seriesInfo(m)
			local tagText = type(m.try) == "table" and "TRY · GOAL LINE" or (goal and "LINE TO GAIN · GOAL" or "LINE TO GAIN · MIDFIELD")
			for i, py in ipairs(visuals.gainPylons or {}) do
				py.CFrame = CFrame.new(field.cx + (i == 1 and -1 or 1) * (field.halfW + 0.5), field.floorY + 1.6, m.toGainZ)
				py.Transparency = showGain and 0 or 1
				py.GainTag.Enabled = showGain; py.GainTag.T.Text = tagText
			end
		end
		local key = ""
		for _, line in ipairs(m.routeLines or {}) do for _, p in ipairs(line) do key ..= string.format("%.0f,%.0f;", p.X, p.Z) end end
		if key ~= visuals.routeKey then visuals.routeKey = key; drawRoutes(m.routeLines) end
		updateTags(m)
	elseif m.kind == "ball" then
		ballState = m
	elseif m.kind == "lunge" then
		if m.stop then lunge = nil else lunge = { dir = m.dir, speed = m.speed, untilT = os.clock() + m.time, spin = m.spin } end
	elseif m.kind == "fall" then
		local hum = humanoid(); if hum then hum:ChangeState(Enum.HumanoidStateType.FallingDown) end
	elseif m.kind == "pedal" then
		pedalFace = m.on and m.face or nil
		local hum = humanoid(); if hum then hum.AutoRotate = not m.on end
	elseif m.kind == "camera" then
		local _, hrp = humanoid()
		local cam = workspace.CurrentCamera
		if hrp and cam then
			local fwd = Vector3.new(math.sin(m.yawHeading), 0, math.cos(m.yawHeading))
			cam.CFrame = CFrame.lookAt(hrp.Position - fwd * 22 + Vector3.new(0, 9, 0), hrp.Position + fwd * 20)
		end
	elseif m.kind == "toast" then
		toast(m.text)
	elseif m.kind == "backToLobby" then
		stopGame()
		mode = "lobby"; lobbyF.Visible = true; gui.Enabled = true
		if m.score then toast("FINAL · HOME " .. m.score.home .. " – " .. m.score.away .. " AWAY · tap READY for a rematch") end
	elseif m.kind == "end" then
		stopGame()
		mode = "none"; lobbyF.Visible = false; gui.Enabled = false
		if m.score and m.team then toast("Left the game · HOME " .. m.score.home .. " – " .. m.score.away .. " AWAY") end
	end
end)

-------------------------------------------------------------------------------------------------- per frame
RunService.RenderStepped:Connect(function()
	if mode ~= "game" then return end
	tickClock()
	local _, hrp = humanoid()
	if lunge and hrp then
		if os.clock() < lunge.untilT then
			local v = lunge.dir * lunge.speed
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, hrp.AssemblyLinearVelocity.Y, v.Z)
			if lunge.spin then hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(25), 0) end
		else lunge = nil end
	end
	if pedalFace and hrp then
		local p = hrp.Position
		hrp.CFrame = CFrame.lookAt(p, p + Vector3.new(math.sin(pedalFace), 0, math.cos(pedalFace)))
	end
	-- red ring under the man you cover
	local ring = visuals.ring
	if ring then
		local man = hud and hud.man
		local root = man and man.Parent and man:FindFirstChild("HumanoidRootPart")
		if root and field and hud and (hud.state == "live" or hud.state == "preSnap") then
			ring.Transparency = 0.35
			ring.CFrame = CFrame.new(root.Position.X, field.floorY + 0.12, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		else ring.Transparency = 1 end
	end
	local ball, lace, ret = visuals.ball, visuals.lace, visuals.reticle
	if not ball then return end
	local bm = ballState.mode
	if bm == "flight" then
		local t = math.clamp(workspace:GetServerTimeNow() - ballState.t0, 0, ballState.flight)
		local pos = ballState.from + ballState.vel * t + Vector3.new(0, -0.5 * ballState.g * t * t, 0)
		local vel = ballState.vel + Vector3.new(0, -ballState.g * t, 0)
		local cf = CFrame.lookAt(pos, pos + vel) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(os.clock() * 25, 0, 0)
		ball.CFrame = cf; ball.Transparency = 0
		lace.CFrame = cf * CFrame.new(0, 0.24, 0); lace.Transparency = 0
		local k = math.clamp((ballState.flight - t) / ballState.flight, 0, 1)
		ret.Transparency = 0.3; ret.Color = ballState.high and BAD or GOLD
		ret.Size = Vector3.new(0.08, 2.6 + 5 * k, 2.6 + 5 * k)
		ret.CFrame = CFrame.new(ballState.target + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
		-- catch sense (2026-11-02): trail on in flight; outline + landing ring flip white and pulse while the catch window is open
		local winEarly = (CFG.catch and CFG.catch.windowEarly) or 0.5
		local inWin = (ballState.flight - t) <= winEarly
		if visuals.trail then visuals.trail.Enabled = true end
		if visuals.glow then
			visuals.glow.OutlineColor = inWin and WHITE or GOLD
			visuals.glow.OutlineTransparency = inWin and (0.05 + 0.3 * math.abs(math.sin(os.clock() * 12))) or 0.5
		end
		if inWin then ret.Color = WHITE end
		local showTiming = hud and hud.timing ~= nil
		timingF.Visible = showTiming
		if showTiming then
			timingFill.Size = UDim2.fromScale(math.clamp(t / ballState.flight, 0, 1), 1)
			local early, late = (CFG.catch and CFG.catch.windowEarly) or 0.5, (CFG.catch and CFG.catch.windowLate) or 0.22 -- was hardcoded 0.4, 0.15: drifted from Config
			local a = math.clamp((ballState.flight - early) / ballState.flight, 0, 1)
			windowF.Position = UDim2.fromScale(a, 0); windowF.Size = UDim2.fromScale(math.clamp((early + late) / ballState.flight, 0, 1 - a), 1)
			timingFill.BackgroundColor3 = hud.timing.pressed and GOLD or WHITE
		end
	else
		timingF.Visible = false
		ret.Transparency = 1
		if visuals.trail then visuals.trail.Enabled = false end
		if visuals.glow then visuals.glow.OutlineTransparency = 1 end
		if bm == "held" and ballState.holder and ballState.holder.Parent then
			Motion.claimArms(ballState.holder, "tuckR")   -- ball arm high and tight; AthleteMotion blends it (was: carrier arm kept pumping through the ball, 2026-11-02)
			local hand = ballState.holder:FindFirstChild("RightHand") or ballState.holder:FindFirstChild("HumanoidRootPart")
			if hand then
				local cf = hand.CFrame * CFrame.new(0, -0.35, -0.25)
				ball.CFrame = cf; ball.Transparency = 0
				lace.CFrame = cf * CFrame.new(0, 0.24, 0); lace.Transparency = 0
			end
		elseif bm == "ground" and ballState.at then
			ball.CFrame = CFrame.new(ballState.at + Vector3.new(0, 0.2, 0)); ball.Transparency = 0; lace.Transparency = 1
		else
			ball.Transparency = 1; lace.Transparency = 1
		end
	end
end)
