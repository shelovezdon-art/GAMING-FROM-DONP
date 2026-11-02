-- MIRROR of game.StarterPlayer.StarterPlayerScripts.Hoops3Client (LocalScript), pulled 2026-11-02 (post wave-3, Gauntlet, DRIP, broadcast UI, stance poses, 2K camera).
-- Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1); this copy is the QA/design record.
-- ALLSTAR WORLD · Hoops3Client (LocalScript): input, movement feel, HUD and feedback for the FULL-COURT 3v3 on Court 2.
-- The ball and the dribble are drawn by AWHoops/BallView on every screen (this script predicts your own dribble moves
-- there). Everything you press is a request; the server decides.
--   PC        WASD move · SHIFT sprint · F shoot (hold, let go on the line; near the rim it's a layup / dunk)
--             G pass (hold = bounce pass) · 1 / 2 pass straight to that teammate · T lob (alley-oop to a cutter)
--             Q / E crossover · Z between the legs · B behind the back · H hesitation · C spin (off the ball: set a
--             screen) · V step-back · R steal · SPACE contest / block / go up · F or SPACE: FINISH an alley-oop · X leave
--   Controller X shoot / layup / dunk · A pass (hold = bounce) · Y lob · B spin (hold = speed dribble; on an open
--             drive: the 360 dunk) · LB behind · RB step-back · RT sprint · D-pad ◀ ▶ pass to 1 / 2 · right stick moves ·
--             R3 camera
--   Camera     P (or R3, or CAM on screen) cycles 2K → BROADCAST → CLOSE → BASELINE → FREE (AWHoops/HoopsCamera).
--             2K is the default: behind the basket your team defends, looking at the one it attacks, so it swings ends
--             when possession changes. Your pick is remembered for the rest of the session.
--   Touch     the thumb cluster (TouchMoves): SHOOT / LAYUP / DUNK / FINISH, PASS (hold = bounce), LOB, 1 / 2,
--             moves, STEAL / BLOCK on defense, SCREEN off the ball, RUN on the left

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CAS = game:GetService("ContextActionService")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local folder = RS:WaitForChild("AWHoops")
local remotes = folder:WaitForChild("Remotes3")
local Intent = remotes:WaitForChild("Intent")
local State = remotes:WaitForChild("State")
local T = require(folder:WaitForChild("Tuning3"))
local Play = require(folder:WaitForChild("Play3"))
local BallView = require(folder:WaitForChild("BallView"))
local TouchMoves = require(folder:WaitForChild("TouchMoves"))
local Driver = require(folder:WaitForChild("Driver"))          -- steers your own body through a finish / a jump
local HoopsCamera = require(folder:WaitForChild("HoopsCamera"))
local S = 1 / 0.35

local GOLD, NAVY = Color3.fromRGB(255, 191, 58), Color3.fromRGB(7, 16, 28)
local BLUE = Color3.fromRGB(70, 150, 255)
local GREEN, RED, WHITE, ORANGE = Color3.fromRGB(80, 230, 120), Color3.fromRGB(255, 95, 70), Color3.new(1, 1, 1), Color3.fromRGB(255, 140, 40)
local TEAMCOLOR = { home = BLUE, away = GOLD }

local active, waiting, hud = false, false, nil
local sprintHeld, sprintOn = false, false   -- declared up here so the camera can ask whether you're running
local camMode = nil                         -- the camera view you last picked, remembered for this session
local ballState = { mode = "hidden" }
local lunge, meter, pressAt = nil, nil, nil
local lobInfo, incoming = nil, nil

---------------------------------------------------------------------------------------------------- HUD
local gui = Instance.new("ScreenGui"); gui.Name = "AWHoops3HUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
local function panel(parent, props)
	local f = Instance.new("Frame"); f.BackgroundColor3 = NAVY; f.BackgroundTransparency = 0.18; f.BorderSizePixel = 0
	for k, v in pairs(props) do f[k] = v end
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10); f.Parent = parent
	return f
end
local function label(parent, props)
	local t = Instance.new("TextLabel"); t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBlack; t.TextScaled = true; t.TextColor3 = WHITE
	for k, v in pairs(props) do t[k] = v end
	t.Parent = parent
	return t
end
local hudScale = Instance.new("UIScale"); hudScale.Parent = gui
-- compact scoreboard (the broadcast bug replaces it when it's showing)
local board = panel(gui, { Size = UDim2.fromOffset(330, 58), Position = UDim2.new(0.5, -165, 0, 10) })
board.Name = "Scoreboard"
local bst = Instance.new("UIStroke", board); bst.Color = GOLD; bst.Thickness = 2; bst.Transparency = 0.35
local homeN = label(board, { Size = UDim2.fromOffset(60, 16), Position = UDim2.fromOffset(10, 5), Text = "HOME", TextColor3 = BLUE, TextXAlignment = Enum.TextXAlignment.Left })
local homeS = label(board, { Size = UDim2.fromOffset(60, 32), Position = UDim2.fromOffset(10, 22), Text = "0", TextXAlignment = Enum.TextXAlignment.Left })
local awayN = label(board, { Size = UDim2.fromOffset(60, 16), Position = UDim2.new(1, -70, 0, 5), Text = "AWAY", TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right })
local awayS = label(board, { Size = UDim2.fromOffset(60, 32), Position = UDim2.new(1, -70, 0, 22), Text = "0", TextXAlignment = Enum.TextXAlignment.Right })
local gameL = label(board, { Size = UDim2.fromOffset(120, 26), Position = UDim2.new(0.5, -60, 0, 4), Text = "6:00" })
local possL = label(board, { Size = UDim2.fromOffset(170, 14), Position = UDim2.new(0.5, -85, 0, 34), Text = "", TextColor3 = GOLD, Font = Enum.Font.GothamBold })
local youL = label(board, { Size = UDim2.fromOffset(170, 10), Position = UDim2.new(0.5, -85, 0, 46), Text = "", Font = Enum.Font.GothamBold })
-- the possession clock: always visible, big and red when it's short
local clockF = panel(gui, { Size = UDim2.fromOffset(64, 46), Position = UDim2.new(0.5, 172, 0, 16), Name = "PossessionClock" })
local clockS = Instance.new("UIStroke", clockF); clockS.Color = WHITE; clockS.Thickness = 2; clockS.Transparency = 0.5
local clockL = label(clockF, { Size = UDim2.new(1, -8, 0, 30), Position = UDim2.fromOffset(4, 2), Text = "20" })
label(clockF, { Size = UDim2.new(1, -8, 0, 10), Position = UDim2.fromOffset(4, 33), Text = "SHOT", Font = Enum.Font.GothamBold, TextColor3 = GOLD })
local msgF = panel(gui, { Size = UDim2.fromOffset(560, 44), Position = UDim2.new(0.5, -280, 0.16, 0), Visible = false })
local msgL = label(msgF, { Size = UDim2.new(1, -24, 1, -12), Position = UDim2.fromOffset(12, 6) })
local fbL = label(gui, { Size = UDim2.fromOffset(560, 52), Position = UDim2.new(0.5, -280, 0.3, 0), Visible = false, TextStrokeTransparency = 0.3 })
local promptF = panel(gui, { Size = UDim2.fromOffset(720, 34), Position = UDim2.new(0.5, -360, 1, -112) })
local promptL = label(promptF, { Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), Font = Enum.Font.GothamBold })
local ballL = label(gui, { Size = UDim2.fromOffset(360, 24), Position = UDim2.new(0.5, -180, 0, 74), Text = "", TextStrokeTransparency = 0.4, Font = Enum.Font.GothamBold })
local stamF = panel(gui, { Size = UDim2.fromOffset(180, 10), Position = UDim2.new(0.5, -90, 1, -70), BackgroundTransparency = 0.35 })
local stamFill = Instance.new("Frame"); stamFill.BorderSizePixel = 0; stamFill.BackgroundColor3 = BLUE; stamFill.Size = UDim2.fromScale(1, 1); stamFill.Parent = stamF
Instance.new("UICorner", stamFill).CornerRadius = UDim.new(0, 8)
-- shot meter: fill, the good band, the perfect band and the release line
local meterF = panel(gui, { Size = UDim2.fromOffset(24, 210), Position = UDim2.new(0.5, 110, 0.5, -105), Visible = false, BackgroundTransparency = 0.25 })
local meterFill = Instance.new("Frame"); meterFill.BorderSizePixel = 0; meterFill.BackgroundColor3 = WHITE; meterFill.AnchorPoint = Vector2.new(0, 1)
meterFill.Position = UDim2.fromScale(0, 1); meterFill.Size = UDim2.fromScale(1, 0); meterFill.Parent = meterF
Instance.new("UICorner", meterFill).CornerRadius = UDim.new(0, 10)
local goodZ = Instance.new("Frame"); goodZ.BorderSizePixel = 0; goodZ.BackgroundColor3 = GOLD; goodZ.BackgroundTransparency = 0.45; goodZ.AnchorPoint = Vector2.new(0, 0.5); goodZ.Parent = meterF
local perfZ = Instance.new("Frame"); perfZ.BorderSizePixel = 0; perfZ.BackgroundColor3 = GREEN; perfZ.BackgroundTransparency = 0.1; perfZ.AnchorPoint = Vector2.new(0, 0.5); perfZ.Parent = meterF
local targetLine = Instance.new("Frame"); targetLine.BorderSizePixel = 0; targetLine.BackgroundColor3 = WHITE; targetLine.AnchorPoint = Vector2.new(0, 0.5)
targetLine.Size = UDim2.new(1.7, 0, 0, 2); targetLine.Parent = meterF
local gradeL = label(gui, { Size = UDim2.fromOffset(260, 34), Position = UDim2.new(0.5, 140, 0.5, -34), Visible = false, TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 0.3 })
local gradeD = label(gui, { Size = UDim2.fromOffset(260, 20), Position = UDim2.new(0.5, 140, 0.5, 2), Visible = false, TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 0.4, Font = Enum.Font.GothamBold })
-- alley-oop timing: a ring that closes on the arrival
local lobF = Instance.new("Frame"); lobF.Name = "LobTiming"; lobF.BackgroundTransparency = 1; lobF.AnchorPoint = Vector2.new(0.5, 0.5)
lobF.Position = UDim2.fromScale(0.5, 0.42); lobF.Size = UDim2.fromOffset(160, 160); lobF.Visible = false; lobF.Parent = gui
local lobRing = Instance.new("Frame"); lobRing.AnchorPoint = Vector2.new(0.5, 0.5); lobRing.Position = UDim2.fromScale(0.5, 0.5); lobRing.BackgroundTransparency = 1; lobRing.Parent = lobF
Instance.new("UICorner", lobRing).CornerRadius = UDim.new(1, 0)
local lobStroke = Instance.new("UIStroke", lobRing); lobStroke.Color = GREEN; lobStroke.Thickness = 4
local lobCore = Instance.new("Frame"); lobCore.AnchorPoint = Vector2.new(0.5, 0.5); lobCore.Position = UDim2.fromScale(0.5, 0.5); lobCore.Size = UDim2.fromOffset(46, 46)
lobCore.BackgroundTransparency = 1; lobCore.Parent = lobF
Instance.new("UICorner", lobCore).CornerRadius = UDim.new(1, 0)
local lobCoreS = Instance.new("UIStroke", lobCore); lobCoreS.Color = WHITE; lobCoreS.Thickness = 3
local lobText = label(lobF, { Size = UDim2.fromOffset(220, 26), Position = UDim2.new(0.5, -110, 1, 4), Text = "ALLEY-OOP · FINISH!", TextColor3 = GREEN, TextStrokeTransparency = 0.3 })
local touchF = Instance.new("Frame"); touchF.BackgroundTransparency = 1; touchF.Size = UDim2.fromScale(1, 1); touchF.Visible = UIS.TouchEnabled; touchF.Parent = gui
local function tbtn(text, pos, size, color)
	local b = Instance.new("TextButton"); b.Size = UDim2.fromOffset(size, size); b.Position = pos; b.Text = text
	b.Font = Enum.Font.GothamBlack; b.TextScaled = true; b.TextColor3 = NAVY; b.BackgroundColor3 = color or GOLD; b.BackgroundTransparency = 0.1
	Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0); b.Parent = touchF
	return b
end
local sprintB = tbtn("RUN", UDim2.new(0, 30, 1, -260), 70, WHITE)
local leaveB = Instance.new("TextButton"); leaveB.Size = UDim2.fromOffset(110, 30); leaveB.Position = UDim2.new(1, -124, 0, 14)
leaveB.BackgroundColor3 = NAVY; leaveB.BackgroundTransparency = 0.2; leaveB.Font = Enum.Font.GothamBold; leaveB.TextScaled = true
leaveB.TextColor3 = WHITE; leaveB.Text = "X  LEAVE"; leaveB.Parent = gui
Instance.new("UICorner", leaveB).CornerRadius = UDim.new(0, 10)
local cycleCam                                                  -- (defined with the bindings, below)
local camB = Instance.new("TextButton"); camB.Name = "Cam"; camB.Size = UDim2.fromOffset(110, 30); camB.Position = UDim2.new(1, -244, 0, 14)
camB.BackgroundColor3 = NAVY; camB.BackgroundTransparency = 0.2; camB.Font = Enum.Font.GothamBold; camB.TextScaled = true
camB.TextColor3 = WHITE; camB.Text = "CAM · 2K"; camB.Parent = gui   -- was "CAM · BROADCAST" (2026-11-02)
Instance.new("UICorner", camB).CornerRadius = UDim.new(0, 10)
camB.MouseButton1Click:Connect(function() if cycleCam then cycleCam() end end)

-- the camera follows the play on the 3v3 court (the court model is the AWCourt tagged Mode3v3)
local function court3()
	for _, m in ipairs(game:GetService("CollectionService"):GetTagged("AWCourt")) do
		if m:GetAttribute("Mode3v3") and m:IsDescendantOf(workspace) then return m end
	end
	return nil
end
local function ballDrawn()
	local b = workspace:FindFirstChild("AWBasketball3v3")
	local info = b and BallView.last[b]
	return info and info.pos or nil
end
local function startCamera()
	local c = court3()
	-- the 2K view's orientation: the rim YOUR team attacks, straight off the HUD message (studs). When possession
	-- changes the server sends the other rim and the camera swings to the other end on its own.
	local opts = {
		court = c, ball = ballDrawn,
		modes = HoopsCamera.MODES_FULLCOURT, mode = camMode or "2K",
		attackRim = function() return hud and hud.attack or nil end,
		sprinting = function() return sprintHeld or sprintOn end,
	}
	if c and HoopsCamera.start(opts) then
		camMode = HoopsCamera.mode()
		camB.Text = "CAM · " .. (camMode or "")
	end
end

local function rescaleHud()
	local vp = workspace.CurrentCamera.ViewportSize
	hudScale.Scale = math.clamp(math.min(vp.X / 1100, vp.Y / 620), 0.62, 1)
end
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescaleHud)
rescaleHud()

---------------------------------------------------------------------------------------------------- hints (per device)
-- hints follow whatever the player last touched (a controller plugged into a PC shows controller hints)
local function device()
	local t = UIS:GetLastInputType()
	if t == Enum.UserInputType.Touch then return "touch" end
	if string.find(tostring(t), "Gamepad") then return "pad" end
	if UIS.TouchEnabled and not UIS.KeyboardEnabled then return "touch" end
	return "pc"
end
local HINTS = {
	pc = {
		handler = "F shoot · G pass (hold = bounce) · 1/2 pass to · T lob · Q/E cross · Z legs · B behind · H hesi · C spin · V step-back",
		inbounder = "INBOUND · G pass in (hold = bounce) · 1/2 pick who",
		offball = "G call for it · C set a screen · SHIFT sprint · SPACE go up",
		defense = "Guard %s · R steal · SPACE contest / block · SHIFT sprint",
		loose = "LOOSE BALL · get to it · SPACE go up for it",
		lob = "ALLEY-OOP · press F (or SPACE) as it arrives!",
		shooting = "LET GO on the line",
		waiting = "Waiting for the next dead ball…",
	},
	touch = {
		handler = "SHOOT · PASS (hold = bounce) · 1/2 · LOB · moves around SHOOT · RUN",
		inbounder = "INBOUND · PASS it in (hold = bounce) · 1/2 pick who",
		offball = "CALL for it · SCREEN · BLOCK to go up · RUN",
		defense = "Guard %s · STEAL · BLOCK · RUN",
		loose = "LOOSE BALL · get to it · BLOCK to go up",
		lob = "ALLEY-OOP · tap FINISH as it arrives!",
		shooting = "LET GO on the line",
		waiting = "Waiting for the next dead ball…",
	},
	pad = {
		handler = "X shoot · A pass (hold = bounce) · D-pad ◀ ▶ pass to 1 / 2 · Y lob · R-stick moves · B spin · LB behind · RB step-back · RT sprint",
		inbounder = "INBOUND · A pass in (hold = bounce) · D-pad ◀ ▶ pick who",
		offball = "A call for it · B or D-pad ▼ set a screen · Y go up · RT sprint",
		defense = "Guard %s · X / B steal · A / Y contest / block · RT sprint",
		loose = "LOOSE BALL · A go up for it · RT sprint",
		lob = "ALLEY-OOP · press X or A as it arrives!",
		shooting = "LET GO on the line",
		waiting = "Waiting for the next dead ball…",
	},
}

local function fbColor(k) return k == "good" and GREEN or k == "bad" and RED or k == "warn" and GOLD or WHITE end
local function fmtClock(s) s = math.max(0, math.ceil(s)); return string.format("%d:%02d", s // 60, s % 60) end

local mateTags = {}      -- [model] = BillboardGui
local handlerTag
local function clearTags()
	for m, b in pairs(mateTags) do b:Destroy(); mateTags[m] = nil end
	if handlerTag then handlerTag:Destroy(); handlerTag = nil end
end
local function render(h)
	homeS.Text = tostring(h.home); awayS.Text = tostring(h.away)
	gameL.Text = (h.gameTime and h.gameTime > 0) and (h.suddenDeath and "NEXT WINS" or fmtClock(h.gameClock)) or ("TO " .. tostring(h.target))
	local running = h.state == "possessed" or h.state == "passing" or h.state == "lob" or h.state == "shooting" or h.state == "loose"
	clockL.Text = tostring(math.max(0, math.ceil(h.shotClock)))
	clockL.TextColor3 = (running and h.shotClock < 5) and RED or WHITE
	clockS.Color = (running and h.shotClock < 5) and RED or WHITE
	possL.Text = h.offense and ((h.offense == "home" and "◀ HOME BALL" or "AWAY BALL ▶")) or ""
	youL.Text = "YOU: " .. (h.myTeam == "home" and "HOME" or "AWAY"); youL.TextColor3 = TEAMCOLOR[h.myTeam] or WHITE
	msgF.Visible = h.message ~= nil; msgL.Text = h.message or ""
	if h.feedback then fbL.Visible = true; fbL.Text = h.feedback.text; fbL.TextColor3 = fbColor(h.feedback.kind) else fbL.Visible = false end
	local hints = HINTS[device()]
	local p = hints[h.ctx or "waiting"]
	if p and h.ctx == "defense" then p = string.format(p, h.manName or "your man") end
	if p and h.ctx == "inbounder" and h.inboundLeft then p = p .. string.format(" · %.0fs", h.inboundLeft) end
	promptF.Visible = p ~= nil; promptL.Text = p or ""
	if h.iHaveBall then ballL.Text = "YOUR BALL"; ballL.TextColor3 = GREEN
	elseif h.holderName then ballL.Text = "BALL: " .. h.holderName; ballL.TextColor3 = WHITE
	else ballL.Text = "" end
	stamFill.Size = UDim2.fromScale(math.clamp(h.stamina or 1, 0, 1), 1)
	stamFill.BackgroundColor3 = (h.stamina or 1) < 0.2 and RED or BLUE
	-- teammate tags: the number is the pass key
	local seen = {}
	for _, m in ipairs(h.mates or {}) do
		local model = m.model
		if model and model.Parent then
			seen[model] = true
			local head = model:FindFirstChild("Head")
			local b = mateTags[model]
			if not b and head then
				b = Instance.new("BillboardGui"); b.Name = "AW3Mate"; b.Size = UDim2.fromOffset(110, 22); b.StudsOffset = Vector3.new(0, 3.6, 0)
				b.AlwaysOnTop = true; b.MaxDistance = 200; b.Adornee = head
				local t = label(b, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.25, BackgroundColor3 = NAVY, TextColor3 = TEAMCOLOR[h.myTeam] or WHITE })
				t.Name = "L"; Instance.new("UICorner", t).CornerRadius = UDim.new(0, 6)
				b.Parent = gui
				mateTags[model] = b
			end
			if b then b.L.Text = m.n .. " · " .. m.name end
		end
	end
	for model, b in pairs(mateTags) do if not seen[model] then b:Destroy(); mateTags[model] = nil end end
	-- a dot over whoever has the ball
	local holder = h.holder
	local head = holder and holder.Parent and holder:FindFirstChild("Head")
	if head then
		if not handlerTag then
			handlerTag = Instance.new("BillboardGui"); handlerTag.Name = "AW3Ball"; handlerTag.Size = UDim2.fromOffset(16, 16); handlerTag.AlwaysOnTop = true
			handlerTag.StudsOffset = Vector3.new(0, 4.6, 0); handlerTag.MaxDistance = 250
			local f = Instance.new("Frame"); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = ORANGE; f.Parent = handlerTag
			Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
			handlerTag.Parent = gui
		end
		handlerTag.Adornee = head; handlerTag.Enabled = holder ~= player.Character
	elseif handlerTag then handlerTag.Enabled = false end
end

---------------------------------------------------------------------------------------------------- world markers
local manRing, catchMark, losLine
local function buildVisuals()
	if manRing then manRing:Destroy() end
	manRing = Instance.new("Part"); manRing.Name = "AWManRing"; manRing.Shape = Enum.PartType.Cylinder; manRing.Anchored = true
	manRing.CanCollide = false; manRing.CanQuery = false; manRing.CanTouch = false; manRing.Material = Enum.Material.Neon
	manRing.Color = RED; manRing.Transparency = 1; manRing.Size = Vector3.new(0.08, 3.4, 3.4); manRing.Parent = workspace
	if catchMark then catchMark:Destroy() end
	catchMark = Instance.new("Part"); catchMark.Name = "AWCatchMark"; catchMark.Shape = Enum.PartType.Cylinder; catchMark.Anchored = true
	catchMark.CanCollide = false; catchMark.CanQuery = false; catchMark.CanTouch = false; catchMark.Material = Enum.Material.Neon
	catchMark.Color = GREEN; catchMark.Transparency = 1; catchMark.Size = Vector3.new(0.08, 2.6, 2.6); catchMark.Parent = workspace
	-- defence: a faint line on the floor from your feet to the ball -- the line you are the one denying. Same spirit
	-- as the man ring above, kept dim so live play doesn't get cluttered.
	if losLine then losLine:Destroy() end
	losLine = Instance.new("Part"); losLine.Name = "AWLosLine"; losLine.Anchored = true
	losLine.CanCollide = false; losLine.CanQuery = false; losLine.CanTouch = false; losLine.Material = Enum.Material.Neon
	losLine.Color = RED; losLine.Transparency = 1; losLine.Size = Vector3.new(0.35, 0.06, 1); losLine.Parent = workspace
end
local function humanoid()
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end
local function leap(power)
	local hum = humanoid()
	if not hum then return end
	hum.UseJumpPower = true; hum.JumpPower = power or 26
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
	task.delay(0.15, function() if hum.Parent then hum.JumpPower = 0 end end)
end

---------------------------------------------------------------------------------------------------- sending (with an optional test latency)
local function lag() return tonumber(player:GetAttribute("AWSimLag")) or 0 end
local function send(t)
	if not active then return end
	-- shoot / spin decide finish-or-jumper from where he is: say where this screen has him (the server checks it)
	if t.action == "shootStart" or t.action == "spin" then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then t.pos = root.Position; t.vel = root.AssemblyLinearVelocity; t.at = workspace:GetServerTimeNow() end
	end
	local l = lag()
	if l > 0 then task.delay(l, function() Intent:FireServer(t) end) else Intent:FireServer(t) end
end
local function ctx() return hud and hud.ctx or "waiting" end
local function iHandle() return ballState.mode == "held" and ballState.holder ~= nil and ballState.holder == player.Character end

local function finish() send({ action = "finish", at = workspace:GetServerTimeNow() }) end
local function shootDown()
	if not active then return end
	if ctx() == "lob" then finish(); return end
	if pressAt then return end
	pressAt = os.clock(); send({ action = "shootStart" })
end
local function shootUp()
	if not pressAt then return end
	local held = os.clock() - pressAt
	pressAt = nil
	send({ action = "shootRelease", held = held, id = meter and meter.id })
	if meter then meter.releasedAt = held end
end
local function aimDir()
	local hum = humanoid()
	local md = hum and hum.MoveDirection
	if md and md.Magnitude > 0.2 then return md end
	return workspace.CurrentCamera.CFrame.LookVector
end
local passDownAt
local function passDown() passDownAt = os.clock() end
local function passUp(targetIdx)
	local held = passDownAt and (os.clock() - passDownAt) or 0
	passDownAt = nil
	send({ action = "pass", aim = aimDir(), target = targetIdx, bounce = held >= T.pass.holdForBounce })
end
local function passTo(i) send({ action = "pass", aim = aimDir(), target = i }) end
local function lob() send({ action = "lob", aim = aimDir() }) end
local function block() send({ action = "block" }) end
-- a dribble move: starts on this screen right away (BallView predicts it with the 3v3's rules); the server decides
local function move(action)
	BallView.predict(action, iHandle() and hud ~= nil and hud.state == "possessed")
	send({ action = action })
end
local function primary()
	local c = ctx()
	if c == "lob" then finish() elseif c ~= "handler" and c ~= "inbounder" then block() end
end

local stickReady = true
local function stickFlick(input)
	if not iHandle() then stickReady = true; return Enum.ContextActionResult.Pass end
	local p = input.Position
	local m = math.sqrt(p.X * p.X + p.Y * p.Y)
	if m < 0.35 then stickReady = true
	elseif m > 0.8 and stickReady then
		stickReady = false
		if math.abs(p.X) > math.abs(p.Y) then move(p.X < 0 and "crossL" or "crossR")
		elseif p.Y > 0 then move("hesi")
		elseif math.abs(p.X) > 0.45 * m then move("behind")
		else move("legs") end
	end
	return Enum.ContextActionResult.Sink
end
local bDownAt, bSprinting = nil, false
local function padB(state)
	if state == Enum.UserInputState.Begin then
		if not iHandle() then send({ action = "steal" }); return end
		bDownAt = os.clock(); bSprinting = false
		local mine = bDownAt
		task.delay(0.22, function()
			if bDownAt == mine and iHandle() then bSprinting = true; send({ action = "sprint", on = true }) end
		end)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		if bDownAt then
			if bSprinting then send({ action = "sprint", on = false }) elseif iHandle() then move("spin") end
		end
		bDownAt = nil; bSprinting = false
	end
end
-- (sprintHeld is declared at the top: the camera reads it)
-- the controller, 2K-style: every face button does the obvious thing for the situation you're in
local function padAction(name, state)
	local c = ctx()
	local began = state == Enum.UserInputState.Begin
	local ended = state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel
	if name == "AW3PadX" then                                   -- shoot / finish / steal
		if c == "lob" then if began then finish() end
		elseif c == "defense" then if began then send({ action = "steal" }) end
		elseif began then shootDown() elseif ended then shootUp() end
	elseif name == "AW3PadA" then                               -- pass / call / go up / finish
		if c == "handler" or c == "inbounder" then
			if began then passDown() elseif ended and passDownAt then passUp(nil) end
		elseif began then
			if c == "lob" then finish() elseif c == "offball" then passTo(nil) else block() end
		end
	elseif name == "AW3PadY" then                               -- lob / go up
		if began then if c == "handler" then lob() elseif c == "lob" then finish() else block() end end
	elseif name == "AW3PadB" then                               -- spin (hold = speed dribble) / screen / steal
		if c == "handler" or (bDownAt and ended) then padB(state)
		elseif began and c == "offball" then send({ action = "screen" })
		elseif began and c == "defense" then send({ action = "steal" }) end
	elseif name == "AW3PadRT" then                              -- sprint / speed dribble while held
		if began then sprintHeld = true; send({ action = "sprint", on = true })
		elseif ended then sprintHeld = false; send({ action = "sprint", on = false }) end
	elseif began then
		if name == "AW3PadLB" then move("behind")
		elseif name == "AW3PadRB" then move("stepback")
		elseif name == "AW3PadLeft" then passTo(1)
		elseif name == "AW3PadRight" then passTo(2)
		elseif name == "AW3PadDown" then send({ action = "screen" })
		elseif name == "AW3PadUp" then passTo(nil) end
	end
	return Enum.ContextActionResult.Sink
end
function cycleCam()
	local mode = HoopsCamera.cycle()
	if mode then camMode = mode; camB.Text = "CAM · " .. mode end   -- remembered, so a rejoin keeps your pick
end
local function onAction(name, state, input)
	if not active then return Enum.ContextActionResult.Pass end
	if name == "AW3Stick" then return stickFlick(input) end
	if string.sub(name, 1, 6) == "AW3Pad" then return padAction(name, state) end
	if name == "AW3Shoot" then
		if state == Enum.UserInputState.Begin then shootDown() elseif state == Enum.UserInputState.End then shootUp() end
		return Enum.ContextActionResult.Sink
	elseif name == "AW3Sprint" then
		if state == Enum.UserInputState.Begin then sprintHeld = true; send({ action = "sprint", on = true })
		elseif state == Enum.UserInputState.End then sprintHeld = false; send({ action = "sprint", on = false }) end
		return Enum.ContextActionResult.Sink
	elseif name == "AW3Pass" then
		if state == Enum.UserInputState.Begin then passDown() elseif state == Enum.UserInputState.End then passUp(nil) end
		return Enum.ContextActionResult.Sink
	end
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	if name == "AW3Primary" then primary()
	elseif name == "AW3Pass1" then passTo(1)
	elseif name == "AW3Pass2" then passTo(2)
	elseif name == "AW3Lob" then lob()
	elseif name == "AW3CrossL" then move("crossL")
	elseif name == "AW3CrossR" then move("crossR")
	elseif name == "AW3Spin" then if iHandle() then move("spin") else send({ action = "screen" }) end
	elseif name == "AW3Legs" then move("legs")
	elseif name == "AW3Behind" then move("behind")
	elseif name == "AW3Hesi" then move("hesi")
	elseif name == "AW3Step" then move("stepback")
	elseif name == "AW3Steal" then send({ action = "steal" })
	elseif name == "AW3Leave" then send({ action = "leave" })
	elseif name == "AW3Cam" then cycleCam() end
	return Enum.ContextActionResult.Sink
end
local ACTIONS = { "AW3Shoot", "AW3Sprint", "AW3Primary", "AW3Pass", "AW3Pass1", "AW3Pass2", "AW3Lob", "AW3CrossL", "AW3CrossR", "AW3Spin",
	"AW3Step", "AW3Steal", "AW3Leave", "AW3Legs", "AW3Behind", "AW3Hesi", "AW3Stick",
	"AW3PadX", "AW3PadA", "AW3PadY", "AW3PadB", "AW3PadRT", "AW3PadLB", "AW3PadRB", "AW3PadLeft", "AW3PadRight", "AW3PadDown", "AW3PadUp", "AW3Cam" }
local function bind()
	local P = 3002
	-- keyboard
	CAS:BindActionAtPriority("AW3Shoot", onAction, false, P, Enum.KeyCode.F)
	CAS:BindActionAtPriority("AW3Sprint", onAction, false, P, Enum.KeyCode.LeftShift)
	CAS:BindActionAtPriority("AW3Primary", onAction, false, P, Enum.KeyCode.Space)
	CAS:BindActionAtPriority("AW3Pass", onAction, false, P, Enum.KeyCode.G)
	CAS:BindActionAtPriority("AW3Pass1", onAction, false, P, Enum.KeyCode.One)
	CAS:BindActionAtPriority("AW3Pass2", onAction, false, P, Enum.KeyCode.Two)
	CAS:BindActionAtPriority("AW3Lob", onAction, false, P, Enum.KeyCode.T)
	CAS:BindActionAtPriority("AW3CrossL", onAction, false, P, Enum.KeyCode.Q)
	CAS:BindActionAtPriority("AW3CrossR", onAction, false, P, Enum.KeyCode.E)
	-- controller
	CAS:BindActionAtPriority("AW3PadX", onAction, false, P, Enum.KeyCode.ButtonX)
	CAS:BindActionAtPriority("AW3PadA", onAction, false, P, Enum.KeyCode.ButtonA)
	CAS:BindActionAtPriority("AW3PadY", onAction, false, P, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonL2)
	CAS:BindActionAtPriority("AW3PadB", onAction, false, P, Enum.KeyCode.ButtonB)
	CAS:BindActionAtPriority("AW3PadRT", onAction, false, P, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL3)
	CAS:BindActionAtPriority("AW3PadLB", onAction, false, P, Enum.KeyCode.ButtonL1)
	CAS:BindActionAtPriority("AW3PadRB", onAction, false, P, Enum.KeyCode.ButtonR1)
	CAS:BindActionAtPriority("AW3PadLeft", onAction, false, P, Enum.KeyCode.DPadLeft)
	CAS:BindActionAtPriority("AW3PadRight", onAction, false, P, Enum.KeyCode.DPadRight)
	CAS:BindActionAtPriority("AW3PadDown", onAction, false, P, Enum.KeyCode.DPadDown)
	CAS:BindActionAtPriority("AW3PadUp", onAction, false, P, Enum.KeyCode.DPadUp)
	CAS:BindActionAtPriority("AW3Spin", onAction, false, P, Enum.KeyCode.C)
	CAS:BindActionAtPriority("AW3Step", onAction, false, P, Enum.KeyCode.V)
	CAS:BindActionAtPriority("AW3Steal", onAction, false, P, Enum.KeyCode.R)
	CAS:BindActionAtPriority("AW3Legs", onAction, false, P, Enum.KeyCode.Z)
	CAS:BindActionAtPriority("AW3Behind", onAction, false, P, Enum.KeyCode.B)
	CAS:BindActionAtPriority("AW3Hesi", onAction, false, P, Enum.KeyCode.H)
	CAS:BindActionAtPriority("AW3Stick", onAction, false, P, Enum.KeyCode.Thumbstick2)
	CAS:BindActionAtPriority("AW3Leave", onAction, false, P, Enum.KeyCode.X)
	CAS:BindActionAtPriority("AW3Cam", onAction, false, P, Enum.KeyCode.P, Enum.KeyCode.ButtonR3)
end
local function unbind() for _, n in ipairs(ACTIONS) do CAS:UnbindAction(n) end end

TouchMoves.build(touchF, {
	shootDown = shootDown, shootUp = shootUp, move = move, steal = function() send({ action = "steal" }) end,
	spinDown = function() padB(Enum.UserInputState.Begin) end, spinUp = function() padB(Enum.UserInputState.End) end,
	pass = function() passTo(nil) end, passDown = passDown, passUp = function() passUp(nil) end,
	passLabel = function() return (hud and hud.iHaveBall) and "PASS" or "CALL" end,
	lob = lob, passTo = passTo, block = block, screen = function() send({ action = "screen" }) end, finish = finish,
	mateLabel = function(i) local m = hud and hud.mates and hud.mates[i]; return m and (tostring(i) .. (m.human and "★" or "")) or nil end,
	shootLabel = function() return hud and hud.shootLabel or "SHOOT" end,
	ctx = function() return active and ctx() or "waiting" end,
	isHandler = function() return active and iHandle() end, hand = function() return BallView.currentHand() end,
})
-- client-side test hook: drives the very same handlers the keys and buttons use (Studio tests can't press keys)
local TESTCALLS = { shootDown = shootDown, shootUp = shootUp, passDown = passDown, passUp = function() passUp(nil) end,
	pass1 = function() passTo(1) end, pass2 = function() passTo(2) end, lob = lob, block = block, finish = finish, primary = primary,
	steal = function() send({ action = "steal" }) end, screen = function() send({ action = "screen" }) end,
	sprintOn = function() sprintHeld = true; send({ action = "sprint", on = true }) end, sprintOff = function() sprintHeld = false; send({ action = "sprint", on = false }) end }
local testIn = Instance.new("BindableEvent"); testIn.Name = "AW3TestInput"; testIn.Parent = gui
testIn.Event:Connect(function(name, arg)
	if not active then return end
	if name == "move" then move(arg) elseif TESTCALLS[name] then TESTCALLS[name]() end
end)
-- (sprintOn is declared at the top: the camera reads it)
sprintB.MouseButton1Down:Connect(function() sprintOn = not sprintOn; sprintB.BackgroundColor3 = sprintOn and GOLD or WHITE; send({ action = "sprint", on = sprintOn }) end)
leaveB.MouseButton1Click:Connect(function() if active or waiting then Intent:FireServer({ action = "leave" }) end end)

local function toast(text)
	local g = Instance.new("ScreenGui"); g.ResetOnSpawn = false; g.Parent = player.PlayerGui
	local f = panel(g, { Size = UDim2.fromOffset(540, 46), Position = UDim2.new(0.5, -270, 0.26, 0) })
	label(f, { Size = UDim2.new(1, -20, 1, -12), Position = UDim2.fromOffset(10, 6), Text = text, TextColor3 = GOLD })
	task.delay(2.6, function() g:Destroy() end)
end

local function stop()
	active = false; waiting = false; hud = nil; meter = nil; pressAt = nil; lunge = nil; lobInfo = nil; incoming = nil
	ballState = { mode = "hidden" }
	unbind(); gui.Enabled = false; meterF.Visible = false; lobF.Visible = false
	HoopsCamera.stop()
	if player.Character then Driver.stop(player.Character) end
	clearTags()
	BallView.moveRules = nil; BallView.simLag = 0
	if manRing then manRing:Destroy(); manRing = nil end
	if catchMark then catchMark:Destroy(); catchMark = nil end
	if losLine then losLine:Destroy(); losLine = nil end
	local hum = humanoid(); if hum then hum.AutoRotate = true end
end

State.OnClientEvent:Connect(function(m)
	if m.kind == "joined" then
		waiting = true; gui.Enabled = true
		toast("Joined " .. (m.team == "home" and "HOME" or "AWAY") .. " · full court 3v3 starting soon")
	elseif m.kind == "start" then
		active = true; waiting = false; gui.Enabled = true
		BallView.moveRules = T.moves
		buildVisuals(); bind()
		startCamera()
	elseif m.kind == "hud" then
		hud = m; render(m)
	elseif m.kind == "ball" then
		ballState = m
		if m.mode ~= "flight" then incoming = nil end
	elseif m.kind == "meter" then
		meter = { id = m.id, fill = m.fill, w = m.w, p = m.perfect, target = m.target }
		meterF.Visible = true; gradeL.Visible = false; gradeD.Visible = false
		goodZ.Size = UDim2.new(1, 0, math.min(m.w * 2, 1), 0); goodZ.Position = UDim2.fromScale(0, 1 - m.target)
		perfZ.Size = UDim2.new(1, 0, math.max(m.perfect * 2, 0.012), 0); perfZ.Position = UDim2.fromScale(0, 1 - m.target)
		targetLine.Position = UDim2.new(-0.35, 0, 1 - m.target, 0)
	elseif m.kind == "release" then
		gradeL.Visible = true; gradeL.Text = m.grade
		gradeL.TextColor3 = (m.grade == "PERFECT" or m.grade == "DUNK") and GREEN or (m.grade == "GOOD" or m.grade == "LAYUP") and GOLD or RED
		gradeD.Visible = (m.detail or "") ~= ""; gradeD.Text = m.detail or ""
		task.delay(1.1, function() meterF.Visible = false; gradeL.Visible = false; gradeD.Visible = false; meter = nil end)
	elseif m.kind == "lunge" then
		lunge = { dir = m.dir, speed = m.speed, untilT = os.clock() + m.time, spin = m.spin }
	elseif m.kind == "leap" then leap(m.power)
	elseif m.kind == "drive" then
		-- a finish or a jump: your body follows the server's plan (the same arc everyone else sees)
		if player.Character and m.spec then Driver.start(player.Character, m.spec) end
	elseif m.kind == "driveStop" then
		if player.Character then Driver.stop(player.Character) end
	elseif m.kind == "incoming" then incoming = { at = m.at, untilT = os.clock() + m.t + 0.2 }
	elseif m.kind == "lob" then
		lobInfo = { at = m.at, arriveAt = m.arriveAt, total = m.t }
		lobF.Visible = true
	elseif m.kind == "toast" then toast(m.text)
	elseif m.kind == "end" then
		stop()
		if m.score and m.team then toast("3v3 FINAL · HOME " .. m.score.home .. " – " .. m.score.away .. " AWAY") end
	end
end)

-- the body drive runs just before physics, every frame (your own character only)
RunService.PreSimulation:Connect(function() Driver.stepAll() end)

---------------------------------------------------------------------------------------------------- movement feel (your own character)
local movingFor, lastDir, plantUntil = 0, nil, 0
local SPACE = T.move.personalSpace * S
RunService.RenderStepped:Connect(function(dt)
	if not active then return end
	local hum, hrp = humanoid()
	if not (hum and hrp) then return end
	BallView.simLag = lag()
	-- server-sent lunges (moves, finishes)
	if lunge then
		if os.clock() < lunge.untilT then
			local v = lunge.dir * lunge.speed
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, hrp.AssemblyLinearVelocity.Y, v.Z)
		else lunge = nil end
	end
	-- in a finish the plan moves you (Driver); the rest of this is for your own running
	if Driver.isActive(player.Character) and (Driver.spec(player.Character) or {}).kind == "finish" then
		hum.WalkSpeed = 0
		return
	end
	-- speed: ramp up from a standstill, a short plant on a hard reversal at speed, back-pedal slower in a stance
	local cap = tonumber(player.Character:GetAttribute("AWSpeedCap")) or hum.WalkSpeed
	local md = hum.MoveDirection
	if md.Magnitude > 0.1 then
		local flat = Vector3.new(md.X, 0, md.Z).Unit
		if lastDir and flat:Dot(lastDir) < -0.3 and sprintHeld and hrp.AssemblyLinearVelocity.Magnitude > cap * 0.7 then plantUntil = os.clock() + T.move.plantTime end
		lastDir = flat
		movingFor += dt
	else movingFor = 0 end
	local speed = Play.speedCap(cap, movingFor, os.clock() < plantUntil, T)
	local c = ctx()
	local face
	if c == "defense" and not sprintHeld and hud then
		-- guard stance: square up to the ball (or your man) and slide
		local target = (hud.holder and hud.holder.Parent and hud.holder:FindFirstChild("HumanoidRootPart")) or (hud.man and hud.man.Parent and hud.man:FindFirstChild("HumanoidRootPart"))
		if target and (target.Position - hrp.Position).Magnitude < 9 * S then face = target.Position end
	end
	if face then
		hum.AutoRotate = false
		local p = hrp.Position
		local f = Vector3.new(face.X, p.Y, face.Z)
		if (f - p).Magnitude > 0.2 then hrp.CFrame = CFrame.lookAt(p, f) end
		if md.Magnitude > 0.1 and md:Dot(hrp.CFrame.LookVector) < -0.4 then speed *= T.move.slideBackFactor end
	else
		hum.AutoRotate = true
	end
	-- soft contact: never inside another player; driving into a set body slows you
	local myRoot = hrp.Position
	for _, other in ipairs(hud and hud.bodies or {}) do
		if other and other.Parent and other ~= player.Character then
			local r = other:FindFirstChild("HumanoidRootPart")
			if r then
				local d = Vector3.new(myRoot.X - r.Position.X, 0, myRoot.Z - r.Position.Z)
				local dist = d.Magnitude
				if dist < SPACE and dist > 1e-3 then
					hrp.CFrame = hrp.CFrame + d.Unit * (SPACE - dist) * 0.5
				end
				if iHandle() and dist < SPACE * 1.5 and md.Magnitude > 0.1 and md:Dot(-d.Unit) > 0.6 then speed *= T.move.contactSlow end
			end
		end
	end
	hum.WalkSpeed = speed
	-- shot meter
	if meter then
		local held = meter.releasedAt or (pressAt and (os.clock() - pressAt)) or 0
		local f = math.clamp(held / meter.fill, 0, 1.3)
		meterFill.Size = UDim2.fromScale(1, math.min(f, 1))
		local d = math.abs(f - meter.target)
		meterFill.BackgroundColor3 = d <= meter.p and GREEN or d <= meter.w and GOLD or WHITE
	end
	-- alley-oop ring: closes on the arrival (the best press is a beat before it lands)
	if lobInfo then
		local left = lobInfo.arriveAt - workspace:GetServerTimeNow()
		if left < -0.4 or c ~= "lob" then lobInfo = nil; lobF.Visible = false
		else
			local k = math.clamp(left / math.max(lobInfo.total, 0.1), 0, 1)
			local size = 46 + 110 * k
			lobRing.Size = UDim2.fromOffset(size, size)
			lobStroke.Color = (math.abs(left - 0.18) <= T.lob.perfectBand) and GREEN or WHITE
		end
	end
	-- floor markers: your man (defense), the line to the ball you're denying, where a pass / lob to you is going
	if losLine then
		local ball = ballDrawn()
		if c == "defense" and ball then
			local floorY = hrp.Position.Y - hum.HipHeight - hrp.Size.Y / 2
			local a = Vector3.new(hrp.Position.X, floorY + 0.05, hrp.Position.Z)
			local b = Vector3.new(ball.X, floorY + 0.05, ball.Z)
			local span = (b - a).Magnitude
			if span > 1.5 then
				losLine.Transparency = 0.78
				losLine.Size = Vector3.new(0.35, 0.06, span)
				losLine.CFrame = CFrame.lookAt((a + b) / 2, b)
			else losLine.Transparency = 1 end
		else losLine.Transparency = 1 end
	end
	if manRing then
		local man = hud and hud.man
		local root = man and man.Parent and man:FindFirstChild("HumanoidRootPart")
		if root and c == "defense" then
			manRing.Transparency = 0.35
			local floorY = hrp.Position.Y - hum.HipHeight - hrp.Size.Y / 2
			manRing.CFrame = CFrame.new(root.Position.X, floorY + 0.06, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		else manRing.Transparency = 1 end
	end
	if catchMark then
		local at = (lobInfo and lobInfo.at) or (incoming and os.clock() < incoming.untilT and incoming.at)
		if at then
			local floorY = hrp.Position.Y - hum.HipHeight - hrp.Size.Y / 2
			catchMark.Transparency = 0.3; catchMark.Color = lobInfo and GREEN or WHITE
			catchMark.CFrame = CFrame.new(at.X, floorY + 0.07, at.Z) * CFrame.Angles(0, 0, math.rad(90))
		else catchMark.Transparency = 1 end
	end
end)
