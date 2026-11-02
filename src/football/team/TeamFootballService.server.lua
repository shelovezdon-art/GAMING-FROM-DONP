-- MIRROR of ServerScriptService.TeamFootballService (Script), pulled 2026-11-02 after the try-flow,
-- clock and config-unification passes. Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1).
-- ALLSTAR WORLD · TeamFootballService (Milestone 06): 2v2 and 5v5 football on the Football Park team fields.
-- HOME vs AWAY. Friends take slots by pressing E on a team's JOIN pad; the lobby shows the roster, everyone taps READY,
-- and every empty slot is played by the same team AI on both sides (fair). Late joiners queue and take an AI slot at
-- the next dead ball; leavers are replaced by the AI on the spot.
-- Slot 1 is the QB on offense and the RUSHER on defense; slot N covers slot N (man coverage). A human QB calls the
-- play, controls the snap count and throws to a receiver (tap = on the line, hold = lob / jump ball). Human receivers
-- release on the HUT, run their route and time the catch; human defenders get off the line, backpedal, swat and tackle.
-- Same rules core as the 1v1 (catch / jump ball / tackle evaluator), same speeds and windows for humans and AI.
-- Server-authoritative; clients send intents. Units: METRES in logic, S converts to studs.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local folder = RS:WaitForChild("AWFootball")
local CFG = require(folder:WaitForChild("Config"))
local Rules = require(folder:WaitForChild("Rules"))
local S = 1 / CFG.STUD

local TC = {
	modes = {
		["2v2"] = { size = 2, possessionsEach = 4, rushCount = 3.0 },
		["5v5"] = { size = 5, possessionsEach = 4, rushCount = 3.2 },
	},
	tryDeclareTime = 8, -- startYard=20, td=7, safety=2, otPossessionsEach=1, maxOtRounds=2 moved to AWFootball.Config (rules/scoring) 2026-11-02
	rushDepth = 6, cushion = 5,
	readyCountdown = 4, lobbyAutoStart = 40, leaveDistance = 45, humanSnapAuto = 15, humanSetToSnap = 4,
	qbPocketSpeed = 7.2, lobHold = 0.35, pressureRadius = 2.6, onRunSpeed = 3.5, onRunPenalty = 0.6,
	blockReach = 1.2, blockDrag = 0.55, blockCooldown = 1.3, engagedScale = 0.4,
	openSeparation = 2.4, finalTime = 7, downOverTime = 2.4,
}

local remotes = folder:FindFirstChild("TeamRemotes") or Instance.new("Folder")
remotes.Name = "TeamRemotes"; remotes.Parent = folder
local function remote(name)
	local r = remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
	r.Name = name; r.Parent = remotes
	return r
end
local Intent = remote("Intent")
local State = remote("State")

local GROUP = "AWFootball"
pcall(function() PhysicsService:RegisterCollisionGroup(GROUP) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false) end)

local function dist2(ax, az, bx, bz) local dx, dz = ax - bx, az - bz; return math.sqrt(dx * dx + dz * dz) end
local function other(team) return team == "home" and "away" or "home" end
local TEAMNAME = { home = "HOME", away = "AWAY" }
local TEAMCOLOR = { home = Color3.fromRGB(70, 150, 255), away = Color3.fromRGB(255, 191, 58) }
local clamp = Rules.clamp

-------------------------------------------------------------------------------------------------- routes + plays
-- lateral + is toward the middle of the field, downfield + is toward the end zone being attacked
local ROUTES = {}
for k, v in pairs(Rules.ROUTES) do ROUTES[k] = v end
ROUTES.flat = { label = "Flat", pts = { { -2, 1 }, { -7, 2.5 }, { -9, 3 } } }
ROUTES.wheel = { label = "Wheel", pts = { { -3, 1 }, { -6, 4 }, { -6.5, 20 } } }
ROUTES.seam = { label = "Seam", pts = { { 0, 10 }, { 0.5, 26 } } }

local function routeWorld(id, startX, startZ, dir, side)
	local out = {}
	for _, p in ipairs((ROUTES[id] or ROUTES.free).pts) do table.insert(out, { x = startX - side * p[1], z = startZ + dir * p[2] }) end
	return out
end

-- offense roles by slot, formation spots {lateral (offense's right = +), depth (behind the line = −)}
local ROLES = {
	["2v2"] = { off = { "QB", "WR" }, def = { "RUSH", "CB" } },
	["5v5"] = { off = { "QB", "X", "Z", "SLOT", "RB" }, def = { "RUSH", "CB", "CB", "NICKEL", "LB" } },
}
local PLAYS = {
	["2v2"] = {
		{ name = "SLANT", routes = { "slant" } }, { name = "CURL", routes = { "curl" } }, { name = "POST", routes = { "post" } },
		{ name = "FADE", routes = { "fade" } }, { name = "CROSS", routes = { "cross" } },
	},
	["5v5"] = {
		{ name = "SPREAD SLANTS", routes = { "slant", "slant", "curl", "flat" } },
		{ name = "FOUR VERTS", routes = { "fade", "fade", "seam", "curl" } },
		{ name = "MESH", routes = { "cross", "slant", "curl", "flat" } },
		{ name = "DEEP SHOT", routes = { "post", "curl", "seam", "wheel" } },
		{ name = "QUICK", routes = { "curl", "curl", "slant", "flat" } },
	},
}
local function formation(mode, slot, halfW)
	if mode == "2v2" then
		if slot == 1 then return 0, -4 end
		return math.min(7, halfW - 3), 0
	end
	local wide = halfW - 3
	local spot = ({ { 0, -4.5 }, { -wide, 0 }, { wide, 0 }, { -wide * 0.5, -0.8 }, { 2.4, -4.5 } })[slot]
	return spot[1], spot[2]
end

-------------------------------------------------------------------------------------------------- poses
local rad = math.rad
local POSES = {
	wrStance = { Root = CFrame.new(0, -0.32, 0), Waist = CFrame.Angles(rad(-34), 0, 0),
		LeftHip = CFrame.Angles(rad(40), 0, 0), LeftKnee = CFrame.Angles(rad(-60), 0, 0), LeftAnkle = CFrame.Angles(rad(20), 0, 0),
		RightHip = CFrame.Angles(rad(8), 0, 0), RightKnee = CFrame.Angles(rad(-45), 0, 0), RightAnkle = CFrame.Angles(rad(35), 0, 0),
		LeftShoulder = CFrame.Angles(rad(-25), 0, 0), RightShoulder = CFrame.Angles(rad(40), 0, 0),
		LeftElbow = CFrame.Angles(rad(40), 0, 0), RightElbow = CFrame.Angles(rad(55), 0, 0) },
	dbCrouch = { Root = CFrame.new(0, -0.45, 0), Waist = CFrame.Angles(rad(-22), 0, 0),
		LeftHip = CFrame.Angles(rad(40), 0, rad(-8)), LeftKnee = CFrame.Angles(rad(-70), 0, 0), LeftAnkle = CFrame.Angles(rad(30), 0, 0),
		RightHip = CFrame.Angles(rad(40), 0, rad(8)), RightKnee = CFrame.Angles(rad(-70), 0, 0), RightAnkle = CFrame.Angles(rad(30), 0, 0),
		LeftShoulder = CFrame.Angles(rad(25), 0, rad(-22)), RightShoulder = CFrame.Angles(rad(25), 0, rad(22)),
		LeftElbow = CFrame.Angles(rad(45), 0, 0), RightElbow = CFrame.Angles(rad(45), 0, 0) },
	pedal = { Root = CFrame.new(0, -0.3, 0), Waist = CFrame.Angles(rad(-16), 0, 0),
		LeftHip = CFrame.Angles(rad(22), 0, 0), LeftKnee = CFrame.Angles(rad(-35), 0, 0),
		RightHip = CFrame.Angles(rad(22), 0, 0), RightKnee = CFrame.Angles(rad(-35), 0, 0),
		LeftShoulder = CFrame.Angles(rad(20), 0, rad(-15)), RightShoulder = CFrame.Angles(rad(20), 0, rad(15)) },
	qbSet = { Waist = CFrame.Angles(rad(-8), 0, 0), LeftHip = CFrame.Angles(rad(12), 0, 0), LeftKnee = CFrame.Angles(rad(-20), 0, 0),
		RightHip = CFrame.Angles(rad(12), 0, 0), RightKnee = CFrame.Angles(rad(-20), 0, 0),
		LeftShoulder = CFrame.Angles(rad(30), 0, 0), RightShoulder = CFrame.Angles(rad(35), 0, 0), LeftElbow = CFrame.Angles(rad(60), 0, 0), RightElbow = CFrame.Angles(rad(60), 0, 0) },
	throw = { Waist = CFrame.Angles(0, rad(-25), 0), RightShoulder = CFrame.Angles(rad(160), 0, rad(20)), RightElbow = CFrame.Angles(rad(40), 0, 0),
		LeftShoulder = CFrame.Angles(rad(40), 0, rad(-10)) },
	rush = { Root = CFrame.new(0, -0.35, 0), Waist = CFrame.Angles(rad(-30), 0, 0), LeftHip = CFrame.Angles(rad(30), 0, 0), LeftKnee = CFrame.Angles(rad(-55), 0, 0),
		RightHip = CFrame.Angles(rad(30), 0, 0), RightKnee = CFrame.Angles(rad(-55), 0, 0), LeftShoulder = CFrame.Angles(rad(20), 0, 0), RightShoulder = CFrame.Angles(rad(20), 0, 0) },
}
local JOINTS = {}
for _, p in pairs(POSES) do for k in pairs(p) do JOINTS[k] = true end end
local ORIG = setmetatable({}, { __mode = "k" })
local AWMotion = require(game:GetService("ReplicatedStorage"):WaitForChild("AWMotion"))
local function setPose(model, name, t)
	-- R15 joints are AnimationConstraints now (their C0 can't be written): publish the pose, every client draws it
	AWMotion.setPose(model, "football", name, t)
end
local function setGroup(model, g) for _, p in ipairs(model:GetDescendants()) do if p:IsA("BasePart") then p.CollisionGroup = g end end end

-------------------------------------------------------------------------------------------------- AI bodies
-- was: local ANIM = { run = "rbxassetid://913376220", idle = "rbxassetid://507766388" } (ids + walk from AWMotion.ANIM, 2026-11-02)
local ANIM = {}
for k, id in pairs(AWMotion.ANIM.r15) do ANIM[k] = "rbxassetid://" .. id end
local SKINS = { Color3.fromRGB(141, 90, 59), Color3.fromRGB(198, 134, 66), Color3.fromRGB(90, 59, 42), Color3.fromRGB(224, 172, 105), Color3.fromRGB(110, 70, 45), Color3.fromRGB(241, 194, 125) }
local function tagFor(model, text, color)
	local head = model:FindFirstChild("Head")
	if not head then return end
	local bb = head:FindFirstChild("AWTeamTag") or Instance.new("BillboardGui")
	bb.Name = "AWTeamTag"; bb.Size = UDim2.fromOffset(130, 30); bb.StudsOffset = Vector3.new(0, 2.6, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 160
	local t = bb:FindFirstChild("L") or Instance.new("TextLabel")
	t.Name = "L"; t.Size = UDim2.fromScale(1, 1); t.BackgroundColor3 = Color3.fromRGB(7, 16, 28); t.BackgroundTransparency = 0.25
	t.Font = Enum.Font.GothamBlack; t.TextScaled = true; t.TextColor3 = color; t.Text = text; t.Parent = bb
	if not t:FindFirstChildOfClass("UICorner") then Instance.new("UICorner", t).CornerRadius = UDim.new(0, 8) end
	bb.Parent = head
end
local function buildAIBody(fieldId, team, slot)
	local desc = Instance.new("HumanoidDescription")
	local skin = SKINS[(slot * 7 + (team == "away" and 3 or 0)) % #SKINS + 1]
	desc.HeadColor = skin; desc.LeftArmColor = skin; desc.RightArmColor = skin
	desc.TorsoColor = team == "home" and Color3.fromRGB(31, 79, 143) or Color3.fromRGB(240, 240, 236)
	desc.LeftLegColor = Color3.fromRGB(16, 20, 24); desc.RightLegColor = Color3.fromRGB(16, 20, 24)
	local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15) end)
	if not ok or not model then warn("[TeamFootball] AI build failed: " .. tostring(model)); return nil end
	model.Name = "TF_" .. fieldId .. "_" .. TEAMNAME[team] .. "_" .. slot
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.MaxHealth = 1e9; hum.Health = 1e9; hum.BreakJointsOnDeath = false   -- large and finite: math.huge leaks nan into ratios
	-- An AI athlete only ever stands, runs and jumps. Every other Humanoid state costs a per-frame floor raycast
	-- and state transition on the server, for every athlete on every field. Hoops3Modules.Roster already does this.
	for _, st in ipairs({ Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.GettingUp, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Swimming,
		Enum.HumanoidStateType.PlatformStanding, Enum.HumanoidStateType.Flying, Enum.HumanoidStateType.Seated }) do
		pcall(function() hum:SetStateEnabled(st, false) end)
	end
	hum.UseJumpPower = true; hum.JumpPower = 42
	local torso = model:FindFirstChild("UpperTorso")
	if torso then
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local g = Instance.new("SurfaceGui"); g.Face = face; g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud; g.PixelsPerStud = 40
			local l = Instance.new("TextLabel"); l.BackgroundTransparency = 1; l.Size = UDim2.fromScale(1, 1); l.Font = Enum.Font.GothamBlack; l.TextScaled = true
			l.TextColor3 = team == "home" and Color3.new(1, 1, 1) or Color3.fromRGB(31, 79, 143)
			l.Text = tostring(({ 12, 81, 88, 17, 24 })[slot] + (team == "away" and 1 or 0)); l.Parent = g
			g.Parent = torso
		end
	end
	tagFor(model, "AI · " .. TEAMNAME[team], TEAMCOLOR[team])
	setGroup(model, GROUP)
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local tracks = {}
	for k, id in pairs(ANIM) do
		local an = Instance.new("Animation"); an.AnimationId = id
		local ok2, tr = pcall(function() return animator:LoadAnimation(an) end)
		if ok2 then tr.Looped = true; tracks[k] = tr end
	end
	return { model = model, hum = hum, hrp = model:FindFirstChild("HumanoidRootPart"), tracks = tracks }
end

-------------------------------------------------------------------------------------------------- fields
local function fieldFrom(id, label, model, north, south, pad)
	local nz0 = (north.Position.Z - north.Size.Z / 2) / S
	local nz1 = (north.Position.Z + north.Size.Z / 2) / S
	local sz0 = (south.Position.Z - south.Size.Z / 2) / S
	local sz1 = (south.Position.Z + south.Size.Z / 2) / S
	local f = { id = id, label = label, model = model, pad = pad,
		cx = north.Position.X / S, halfW = north.Size.X / S / 2,
		northGoal = nz1, southGoal = sz0, cz = (nz0 + sz1) / 2, halfL = (sz1 - nz0) / 2,
		floorY = (north.Position.Y + north.Size.Y / 2) / S }
	f.metresPerYard = (f.southGoal - f.northGoal) / 100
	f.mid = (f.northGoal + f.southGoal) / 2
	return f
end

-------------------------------------------------------------------------------------------------- the game (one per field)
local G = {}
G.__index = G
local GAMES = {}          -- field id -> game
local PLAYER_GAME = {}    -- player -> game (lobby, pending or seated)

local function newPlayState()
	return { released = false, burst = 1, burstUntil = 0, pedal = false, flipUntil = 0, recoverUntil = 0, dragUntil = 0,
		frozenUntil = 0, stunUntil = 0, engagedUntil = 0, tackleCd = 0, jukeCd = 0, spinCd = 0, stiffCd = 0, blockCd = 0,
		immuneUntil = 0, lunge = nil, trail = {}, routePts = {}, routeIdx = 1, jumpAt = nil, catchPress = nil, swatPress = nil,
		jumped = false, reactAt = nil, flipAt = nil, calledAt = nil, placedAt = 0 }
end

function G.new(model, mode, f)
	local self = setmetatable({}, G)
	self.id = f.id; self.field = f; self.mode = mode; self.size = TC.modes[mode].size; self.model = model
	self.roles = ROLES[mode]; self.plays = PLAYS[mode]
	self.state = "lobby"
	self.roster = { home = {}, away = {} }   -- slot -> { player, ready }
	self.slots = { home = {}, away = {} }    -- slot -> athlete (in game)
	self.bodies = { home = {}, away = {} }   -- cached AI bodies
	self.pending = {}
	self.feedbackFor = {}
	self.now = 0
	self.play = 1
	self.events = {}
	self.score = { home = 0, away = 0 }
	self:buildPads()
	return self
end

function G:log(t, d) d = d or {}; d.t = t; d.down = self.down; table.insert(self.events, d); if #self.events > 400 then table.remove(self.events, 1) end end
function G:msg(text, t) self.message = text; self.messageTimer = t or 2 end
function G:fb(a, text, kind, t, reason) if a and a.kind == "human" then self.feedbackFor[a.player] = { text = text, kind = kind or "good", t = t or 1.2, reason = reason } end end
function G:fbTeam(team, text, kind, t) for _, a in ipairs(self:athletes()) do if a.team == team then self:fb(a, text, kind, t) end end end
function G:sendTo(a, m) if a and a.kind == "human" then State:FireClient(a.player, m) end end

-- everyone who should hear about this game: lobby roster, pending, seated
function G:audience()
	local list, seen = {}, {}
	local function add(p) if p and not seen[p] then seen[p] = true; table.insert(list, p) end end
	for _, team in ipairs({ "home", "away" }) do for s = 1, self.size do local r = self.roster[team][s]; if r then add(r.player) end end end
	for _, p in ipairs(self.pending) do add(p.player) end
	return list
end
function G:sendAll(m) for _, p in ipairs(self:audience()) do State:FireClient(p, m) end end

function G:athletes()
	local list = {}
	for _, team in ipairs({ "home", "away" }) do for s = 1, self.size do local a = self.slots[team][s]; if a then table.insert(list, a) end end end
	return list
end
function G:athleteOf(player)
	for _, a in ipairs(self:athletes()) do if a.player == player then return a end end
	return nil
end
function G:rosterOf(player)
	for _, team in ipairs({ "home", "away" }) do for s = 1, self.size do local r = self.roster[team][s]; if r and r.player == player then return team, s end end end
	return nil
end
function G:humanCount()
	local n = #self.pending
	for _, team in ipairs({ "home", "away" }) do for s = 1, self.size do if self.roster[team][s] then n += 1 end end end
	return n
end
function G:roleOf(a)
	if not a then return "" end
	return a.team == self.offense and self.roles.off[a.slot] or self.roles.def[a.slot]
end
function G:qb() return self.slots[self.offense][1] end
function G:rusher() return self.slots[other(self.offense)][1] end

-------------------------------------------------------------------------------------------------- join pads + field signage
function G:buildPads()
	local f = self.field
	local old = f.pad
	local folderP = self.model:FindFirstChild("JoinPads") or Instance.new("Folder")
	folderP.Name = "JoinPads"; folderP.Parent = self.model
	folderP:ClearAllChildren()
	if old then old.Transparency = 1; old.CanQuery = false end
	local base = old and old.Position or Vector3.new(f.cx * S, f.floorY * S, (f.southGoal + 8) * S)
	for i, team in ipairs({ "home", "away" }) do
		local pad = Instance.new("Part")
		pad.Name = "Join_" .. TEAMNAME[team]; pad.Anchored = true; pad.CanCollide = false; pad.CanTouch = false
		pad.Shape = Enum.PartType.Cylinder; pad.Size = Vector3.new(0.08, 7, 7)
		pad.CFrame = CFrame.new(base + Vector3.new((i == 1 and -4.5 or 4.5), 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90))
		pad.Color = TEAMCOLOR[team]; pad.Material = Enum.Material.Neon; pad.Transparency = 0.2
		pad.Parent = folderP
		local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(170, 52); bb.StudsOffset = Vector3.new(0, 4.5, 0); bb.MaxDistance = 110
		local t = Instance.new("TextLabel"); t.Size = UDim2.fromScale(1, 1); t.BackgroundColor3 = Color3.fromRGB(7, 16, 28); t.BackgroundTransparency = 0.2
		t.Font = Enum.Font.GothamBlack; t.TextScaled = true; t.TextColor3 = TEAMCOLOR[team]; t.Text = self.mode .. " · JOIN " .. TEAMNAME[team]; t.Parent = bb
		Instance.new("UICorner", t).CornerRadius = UDim.new(0, 10)
		bb.Parent = pad
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "AWJoinTeam"; pp.ActionText = "Join " .. TEAMNAME[team]; pp.ObjectText = f.label .. " · friends + AI"
		pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0; pp.MaxActivationDistance = 12; pp.RequiresLineOfSight = false
		pp.Parent = pad
		pp.Triggered:Connect(function(player) self:join(player, team) end)
	end
	self.model:SetAttribute("Playable", true)
	-- the walk-on sign promised Milestone 06 — it's here now
	for _, d in ipairs(self.model:GetDescendants()) do
		if d:IsA("TextLabel") and (d.Text == "OPENS IN MILESTONE 06") then d.Text = "JOIN HOME OR AWAY · FRIENDS + AI" end
		if d:IsA("TextLabel") and d.Text:find("COMING IN MILESTONE 06") then self.boardLabel = d end
	end
	self:updateBoard()
end

function G:updateBoard()
	local l = self.boardLabel
	if not l then return end
	if self.state == "lobby" or self.state == "countdown" then
		l.Text = self.mode:upper() .. " · OPEN · JOIN A TEAM"
	else
		l.Text = "HOME " .. self.score.home .. "  –  " .. self.score.away .. " AWAY" .. (self.state == "final" and " · FINAL" or "")
	end
end

-------------------------------------------------------------------------------------------------- lobby: join / pick / ready / leave
function G:firstOpen(team)
	-- the first human on a team gets slot 1 (QB on offense, RUSHER on defense); friends fill 2..n
	for s = 1, self.size do if not self.roster[team][s] then return s end end
	return nil
end

function G:join(player, team)
	local g = PLAYER_GAME[player]
	if g and g ~= self then State:FireClient(player, { kind = "toast", text = "You're already in a game on " .. g.field.label .. " · press X to leave it" }); return end
	if self:rosterOf(player) then
		-- already here: switch team if there's room
		local t0 = self:rosterOf(player)
		if t0 ~= team and (self.state == "lobby" or self.state == "countdown") then
			local s = self:firstOpen(team)
			if s then
				local _, s0 = self:rosterOf(player)
				local r = self.roster[t0][s0]; self.roster[t0][s0] = nil
				r.ready = false; self.roster[team][s] = r
				self:sendLobby()
			end
		end
		return
	end
	for _, p in ipairs(self.pending) do if p.player == player then return end end
	if self.state == "lobby" or self.state == "countdown" then
		local s = self:firstOpen(team)
		if not s then State:FireClient(player, { kind = "toast", text = TEAMNAME[team] .. " is full of players — try " .. TEAMNAME[other(team)] }); return end
		self.roster[team][s] = { player = player, ready = false }
		PLAYER_GAME[player] = self
		self.lobbySince = self.lobbySince or self.now
		self:sendLobby()
		if self.state == "countdown" then self.state = "lobby" end   -- someone new: wait for their READY
	else
		-- game running: queue for the next dead ball
		local humans = 0
		for s = 1, self.size do if self.roster[team][s] then humans += 1 end end
		for _, p in ipairs(self.pending) do if p.team == team then humans += 1 end end
		if humans >= self.size then State:FireClient(player, { kind = "toast", text = TEAMNAME[team] .. " is full of players — try " .. TEAMNAME[other(team)] }); return end
		table.insert(self.pending, { player = player, team = team })
		PLAYER_GAME[player] = self
		State:FireClient(player, { kind = "queued", team = team, field = self.field.label })
		State:FireClient(player, { kind = "toast", text = "You're in the queue · you take an AI spot on " .. TEAMNAME[team] .. " at the next dead ball" })
	end
end

function G:pick(player, team, slot)
	if not (self.state == "lobby" or self.state == "countdown") then return end
	if not (team == "home" or team == "away") or type(slot) ~= "number" or slot < 1 or slot > self.size then return end
	slot = math.floor(slot)
	local t0, s0 = self:rosterOf(player)
	if not t0 or self.roster[team][slot] then return end
	local r = self.roster[t0][s0]; self.roster[t0][s0] = nil
	r.ready = false; self.roster[team][slot] = r
	if self.state == "countdown" then self.state = "lobby" end
	self:sendLobby()
end

function G:setReady(player, on)
	local t, s = self:rosterOf(player)
	if not t then return end
	self.roster[t][s].ready = on and true or false
	local all = true
	for _, team in ipairs({ "home", "away" }) do for i = 1, self.size do local r = self.roster[team][i]; if r and not r.ready then all = false end end end
	if self.state == "lobby" and all and self:humanCount() > 0 then
		self.state = "countdown"; self.countdown = TC.readyCountdown
	elseif self.state == "countdown" and not all then
		self.state = "lobby"
	end
	self:sendLobby()
end

function G:sendLobby()
	local function slotsOf(team)
		local out = {}
		for s = 1, self.size do
			local r = self.roster[team][s]
			out[s] = { name = r and r.player.DisplayName or "AI", human = r ~= nil, ready = r and r.ready or false,
				role = self.roles.off[s] .. " / " .. self.roles.def[s], me = false }
		end
		return out
	end
	local auto = self.lobbySince and math.max(0, TC.lobbyAutoStart - (self.now - self.lobbySince)) or nil
	for _, p in ipairs(self:audience()) do
		local t, s = self:rosterOf(p)
		State:FireClient(p, { kind = "lobby", field = self.field.label, fieldId = self.id, mode = self.mode,
			home = slotsOf("home"), away = slotsOf("away"), myTeam = t, mySlot = s, state = self.state,
			countdown = self.state == "countdown" and math.ceil(self.countdown) or nil, autoStart = auto and math.ceil(auto) or nil })
	end
end

function G:leave(player)
	if PLAYER_GAME[player] == self then PLAYER_GAME[player] = nil end
	for i, p in ipairs(self.pending) do if p.player == player then table.remove(self.pending, i); State:FireClient(player, { kind = "end" }); return end end
	local t, s = self:rosterOf(player)
	if t then self.roster[t][s] = nil end
	local a = self:athleteOf(player)
	if a then
		local x, z = self:pos(a)
		self:releaseHuman(a, true)
		local ai = self:fillAI(a.team, a.slot)
		if ai then
			ai.st = a.st; ai.spot = a.spot; ai.man = a.man; ai.route = a.route; ai.side = a.side
			for _, o in ipairs(self:athletes()) do if o.man == a then o.man = ai end end
			self:place(ai, x, z, self:headingOf(a))
			if self.ball and self.ball.holder == a then self.ball.holder = ai end
			if self.carrier == a then self.carrier = ai end
			if self.ball and self.ball.target == a then self.ball.target = ai end
			if self.wrap and self.wrap.by == a then self.wrap.by = ai end
			if self.wrap and self.wrap.carrier == a then self.wrap.carrier = ai end
		end
	else
		State:FireClient(player, { kind = "end" })
	end
	if self:humanCount() == 0 then self:reset() elseif self.state == "lobby" or self.state == "countdown" then self:setReadyCheck() end
end
function G:setReadyCheck()
	local all, any = true, false
	for _, team in ipairs({ "home", "away" }) do for i = 1, self.size do local r = self.roster[team][i]; if r then any = true; if not r.ready then all = false end end end end
	if self.state == "countdown" and not (all and any) then self.state = "lobby" end
	if self.state == "lobby" and all and any then self.state = "countdown"; self.countdown = TC.readyCountdown end
	self:sendLobby()
end

-------------------------------------------------------------------------------------------------- athletes (humans + AI share one interface)
function G:pos(a) local p = a.hrp.Position / S; return p.X, p.Z end
function G:vel(a) local v = a.hrp.AssemblyLinearVelocity / S; return v.X, v.Z end
function G:speedOf(a) local vx, vz = self:vel(a); return math.sqrt(vx * vx + vz * vz) end
function G:headingOf(a)
	local vx, vz = self:vel(a)
	if math.sqrt(vx * vx + vz * vz) > 1 then return math.atan2(vx, vz) end
	local l = a.hrp.CFrame.LookVector; return math.atan2(l.X, l.Z)
end
function G:place(a, x, z, heading)
	local y = self.field.floorY * S + a.hum.HipHeight + a.hrp.Size.Y / 2 + 0.15
	local p = Vector3.new(x * S, y, z * S)
	a.model:PivotTo(CFrame.lookAt(p, p + Vector3.new(math.sin(heading), 0, math.cos(heading))))
	a.hrp.AssemblyLinearVelocity = Vector3.zero
	a.st.placedAt = self.now
	if a.kind == "ai" then a.hum:Move(Vector3.zero); a.wantX = nil end
end

function G:fillAI(team, slot)
	local body = self.bodies[team][slot]
	if not body or body.model.Parent == nil then
		body = buildAIBody(self.id, team, slot)
		self.bodies[team][slot] = body
	end
	if not body then return nil end
	local holder = workspace:FindFirstChild("AWTeamFootballActors") or Instance.new("Folder")
	holder.Name = "AWTeamFootballActors"; holder.Parent = workspace
	body.model.Parent = holder
	pcall(function() body.hrp:SetNetworkOwner(nil) end)
	local a = { team = team, slot = slot, kind = "ai", model = body.model, hum = body.hum, hrp = body.hrp, tracks = body.tracks, name = "AI", st = newPlayState() }
	self.slots[team][slot] = a
	return a
end

function G:humanAthlete(player, team, slot)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) or hum.Health <= 0 then return nil end
	local a = { team = team, slot = slot, kind = "human", player = player, model = char, hum = hum, hrp = hrp, name = player.DisplayName, st = newPlayState() }
	a.saved = { walk = hum.WalkSpeed, jumpPower = hum.JumpPower, jumpHeight = hum.JumpHeight, useJP = hum.UseJumpPower }
	hum.UseJumpPower = true; hum.JumpPower = 0
	setGroup(char, GROUP)
	a.conn = char.DescendantAdded:Connect(function(d) if d:IsA("BasePart") then d.CollisionGroup = GROUP end end)
	a.died = hum.Died:Connect(function() self:leave(player) end)
	local hl = Instance.new("Highlight"); hl.Name = "AWTeamHighlight"; hl.FillTransparency = 1; hl.OutlineColor = TEAMCOLOR[team]; hl.Parent = char
	tagFor(char, player.DisplayName .. " · " .. TEAMNAME[team], TEAMCOLOR[team])
	return a
end

function G:releaseHuman(a, sendEnd)
	if a.conn then a.conn:Disconnect() end
	if a.died then a.died:Disconnect() end
	if a.model and a.model.Parent then
		setGroup(a.model, "Default"); setPose(a.model, nil)
		local hl = a.model:FindFirstChild("AWTeamHighlight"); if hl then hl:Destroy() end
		local head = a.model:FindFirstChild("Head"); local tg = head and head:FindFirstChild("AWTeamTag"); if tg then tg:Destroy() end
		a.hum.WalkSpeed = a.saved.walk; a.hum.JumpPower = a.saved.jumpPower; a.hum.JumpHeight = a.saved.jumpHeight; a.hum.UseJumpPower = a.saved.useJP
		a.hum.AutoRotate = true
	end
	self.slots[a.team][a.slot] = nil
	if sendEnd then State:FireClient(a.player, { kind = "end", score = self.score, team = a.team }) end
end

function G:parkAI(a)
	a.hum:Move(Vector3.zero); setPose(a.model, nil)
	a.model.Parent = SS
	self.slots[a.team][a.slot] = nil
end

-------------------------------------------------------------------------------------------------- game flow
function G:startGame()
	self.rng = Rules.newRng(CFG.seed + math.floor(os.clock() * 1000) % 100000)
	self.score = { home = 0, away = 0 }
	self.events = {}
	self.stats = {}
	self.possession = 1; self.totalPossessions = TC.modes[self.mode].possessionsEach * 2; self.otRound = 0
	-- IFAF game clock: two halves, running clock, stop events only inside the final window (CFG.clock)
	self.half = 1; self.halfClock = CFG.clock.halfSeconds; self.clockStarted = false; self.clockStopped = true
	self.halfOpeningOffense = "home"
	self.lobbySince = nil
	for _, team in ipairs({ "home", "away" }) do
		for s = 1, self.size do
			local r = self.roster[team][s]
			local a = r and self:humanAthlete(r.player, team, s) or nil
			if a then self.slots[team][s] = a
			else
				if r then self.roster[team][s] = nil; PLAYER_GAME[r.player] = nil end
				self:fillAI(team, s)
			end
		end
	end
	for _, a in ipairs(self:athletes()) do
		self:sendTo(a, { kind = "start", mode = self.mode, team = a.team, slot = a.slot, fieldId = self.id,
			field = { label = self.field.label, cx = self.field.cx * S, halfW = self.field.halfW * S, floorY = self.field.floorY * S,
				northGoal = self.field.northGoal * S, southGoal = self.field.southGoal * S },
			plays = self:playNames() })
	end
	self.offense = "home"
	self:newPossession(self.mode .. " KICKOFF · " .. self.field.label .. " · HOME ball first")
	self:updateBoard()
end

function G:playNames() local t = {}; for i, p in ipairs(self.plays) do t[i] = p.name end; return t end

function G:reset()
	for _, a in ipairs(self:athletes()) do
		if a.kind == "human" then self:releaseHuman(a, true) else self:parkAI(a) end
	end
	for _, team in ipairs({ "home", "away" }) do for s = 1, self.size do local r = self.roster[team][s]; if r then PLAYER_GAME[r.player] = nil end end end
	for _, p in ipairs(self.pending) do PLAYER_GAME[p.player] = nil; State:FireClient(p.player, { kind = "end" }) end
	self.roster = { home = {}, away = {} }; self.slots = { home = {}, away = {} }; self.pending = {}
	self.state = "lobby"; self.lobbySince = nil; self.ball = nil; self.carrier = nil; self.wrap = nil
	self.score = { home = 0, away = 0 }
	self:updateBoard()
end

-- after a final: everyone goes back to the lobby with the same roster (rematch with one tap)
function G:backToLobby()
	for _, a in ipairs(self:athletes()) do
		if a.kind == "human" then
			self:releaseHuman(a, false)
			local pad = self.model:FindFirstChild("JoinPads") and self.model.JoinPads:FindFirstChild("Join_" .. TEAMNAME[a.team])
			if pad and a.hum.Health > 0 then a.model:PivotTo(CFrame.new(pad.Position + Vector3.new(0, a.hum.HipHeight + a.hrp.Size.Y / 2 + 0.5, 0))) end
		else self:parkAI(a) end
	end
	for _, p in ipairs(self.pending) do
		local s = self:firstOpen(p.team)
		if s then self.roster[p.team][s] = { player = p.player, ready = false } else PLAYER_GAME[p.player] = nil end
	end
	self.pending = {}
	for _, team in ipairs({ "home", "away" }) do for s = 1, self.size do local r = self.roster[team][s]; if r then r.ready = false end end end
	self.state = "lobby"; self.lobbySince = self.now; self.ball = nil; self.carrier = nil; self.wrap = nil
	for _, p in ipairs(self:audience()) do State:FireClient(p, { kind = "backToLobby", score = self.score }) end
	if self:humanCount() == 0 then self:reset() else self:sendLobby() end
	self:updateBoard()
end

function G:yards(n) return n * self.field.metresPerYard end
function G:goalZ() return self.dir < 0 and self.field.northGoal or self.field.southGoal end
function G:ownGoalZ() return self.dir < 0 and self.field.southGoal or self.field.northGoal end
function G:scoredAt(z) return (z - self:goalZ()) * self.dir >= 0 end
function G:inOwnEndZone(z) return (z - self:ownGoalZ()) * self.dir < 0 end

function G:newPossession(text)
	self.dir = self.offense == "home" and -1 or 1
	self.down = 1
	self.try = nil; self.tryActive = nil
	self.los = self:ownGoalZ() + self.dir * self:yards(CFG.rules.startYard) -- was TC.startYard
	self.toGain = self.field.mid
	self:setupDown(text)
end

function G:downText()
	if self.tryActive then return "TRY FOR " .. tostring(self.try and self.try.declared or 1) .. " · " .. TEAMNAME[self.offense] end
	local ord = ({ "1st", "2nd", "3rd", "4th" })[self.down] or "4th"
	local goalNext = math.abs(self.toGain - self:goalZ()) < 0.01
	-- IFAF 5v5: one line to gain (midfield), then goal — was "& <yds>", which implied first downs that don't exist (2026-11-02)
	return ord .. " & " .. (goalNext and "GOAL" or "TO MIDFIELD") .. " · " .. TEAMNAME[self.offense] .. " BALL"
end

-- seat queued players in AI slots (dead ball only)
function G:seatPending()
	local still = {}
	for _, p in ipairs(self.pending) do
		local seated = false
		local order = { 1, 2, 3, 4, 5 }
		for _, s in ipairs(order) do
			if s <= self.size and not self.roster[p.team][s] then
				local prev = self.slots[p.team][s]
				local a = self:humanAthlete(p.player, p.team, s)
				if a then
					if prev and prev.kind == "ai" then self:parkAI(prev) end
					self.slots[p.team][s] = a
					self.roster[p.team][s] = { player = p.player, ready = true }
					self:sendTo(a, { kind = "start", mode = self.mode, team = p.team, slot = s, fieldId = self.id,
						field = { label = self.field.label, cx = self.field.cx * S, halfW = self.field.halfW * S, floorY = self.field.floorY * S,
							northGoal = self.field.northGoal * S, southGoal = self.field.southGoal * S }, plays = self:playNames() })
					self:fb(a, "YOU'RE IN · " .. TEAMNAME[p.team] .. " · " .. self.roles.off[s] .. " / " .. self.roles.def[s], "good", 2)
					seated = true
				end
				break
			end
		end
		if not seated then table.insert(still, p) end
	end
	self.pending = still
end

function G:setupDown(text)
	self:seatPending()
	local f, dir = self.field, self.dir
	self.state = "preSnap"; self.phase = "pre"; self.playClock = 0
	self.carrier = nil; self.wrap = nil; self.highBall = false; self.snapAt = nil; self.rushAt = nil; self.passCaught = nil
	local faceDown = dir < 0 and math.pi or 0
	local faceUp = dir < 0 and 0 or math.pi
	local latSign = dir < 0 and 1 or -1      -- offense's right in world x
	local off, def = self.offense, other(self.offense)
	local qb = self.slots[off][1]
	if qb.kind == "ai" then self.play = math.floor(self.rng:next() * #self.plays) + 1 else self.play = (self.humanPlay and self.humanPlay[off]) or 1 end
	for s = 1, self.size do
		local a = self.slots[off][s]
		a.st = newPlayState()
		local lat, depth = formation(self.mode, s, f.halfW)
		local x, z = f.cx + lat * latSign, self.los + dir * depth
		self:place(a, x, z, faceDown)
		a.spot = { x = x, z = z }
		a.side = (x - f.cx) >= 0 and 1 or -1
		if math.abs(x - f.cx) < 0.5 then a.side = latSign end
		setPose(a.model, s == 1 and "qbSet" or nil)
		if a.kind == "ai" then a.faceHeading = faceDown end
	end
	for s = 1, self.size do
		local d = self.slots[def][s]
		d.st = newPlayState()
		local man = self.slots[off][s]
		local x, z
		if s == 1 then x, z = f.cx, self.los + dir * TC.rushDepth
		elseif self.roles.def[s] == "LB" then x, z = man.spot.x, self.los + dir * 4
		else x, z = man.spot.x, self.los + dir * TC.cushion end
		self:place(d, x, z, faceUp)
		d.man = s == 1 and qb or man
		setPose(d.model, s == 1 and "rush" or "dbCrouch")
		if d.kind == "ai" then d.faceHeading = faceUp end
		self:sendTo(d, { kind = "pedal", on = false })
	end
	self:assignRoutes()
	-- snap count: AI QB runs its own random cadence; a human QB calls SET and HUT himself (auto if he stalls)
	if qb.kind == "ai" then
		self.pre = "lineup"; self.snapTimer = CFG.flow.cpuSnapDelay
	else
		self.pre = "lineup"; self.snapTimer = TC.humanSnapAuto
	end
	self.ball = { holder = qb, air = false }
	self:msg(text or self:downText(), text and 3.2 or 1.8)
	self:sendBall()
	for _, a in ipairs(self:athletes()) do self:sendTo(a, { kind = "camera", yawHeading = a.team == off and faceDown or faceUp }) end
	self:log("SETUP", { offense = off, los = math.floor(self.los * 10) / 10, play = self.plays[self.play].name })
end

function G:assignRoutes()
	local off = self.offense
	local play = self.plays[self.play]
	for s = 2, self.size do
		local a = self.slots[off][s]
		a.route = a.routeOverride or play.routes[s - 1] or "curl"
		a.st.routePts = routeWorld(a.route, a.spot.x, a.spot.z, self.dir, a.side)
		a.st.routeIdx = 1
	end
end

function G:getSet()
	self.pre = "set"; self.setAt = self.now
	local qb = self:qb()
	if qb.kind == "ai" then self.snapTimer = self.rng:range(CFG.stance.cadenceMin, CFG.stance.cadenceMax)
	else self.snapTimer = TC.humanSetToSnap end
	for s = 2, self.size do setPose(self.slots[self.offense][s].model, "wrStance") end
	self:msg("SET…", 3)
end

function G:snap()
	self.clockStarted = true; self.clockStopped = false -- the game clock runs from the first snap, restarts on every snap
	self.state = "live"; self.phase = "pocket"; self.playClock = 0
	self.snapAt = self.now
	self.rushAt = self.now + TC.modes[self.mode].rushCount
	local K = CFG.stance
	for _, a in ipairs(self:athletes()) do
		local isQB = a.team == self.offense and a.slot == 1
		local isRush = a.team ~= self.offense and a.slot == 1
		if isQB or isRush then
			a.st.released = true
			if isQB then setPose(a.model, nil, 0.15) end
		elseif a.kind == "ai" then
			a.st.reactAt = self.now + self.rng:range(K.cpuReactMin, K.cpuReactMax)
		end
		if a.st.jumped then a.st.frozenUntil = self.now + K.earlyFreeze end
	end
	self.stats.snaps = (self.stats.snaps or 0) + 1
	self:msg("HUT!", 0.8)
	self:log("SNAP", { play = self.plays[self.play].name })
end

function G:grade(r)
	local K = CFG.stance
	if r <= K.perfect then return "PERFECT", K.perfectBurst elseif r <= K.good then return "GOOD", K.goodBurst end
	return "LATE", 1
end

function G:release(a, auto)
	if a.st.released then return end
	a.st.released = true
	local g, burst = self:grade(self.now - (self.snapAt or self.now))
	if auto then g, burst = "LATE", 1 end
	if a.st.jumped then g, burst = "SLOW", 1 end
	a.st.burst = burst; a.st.burstUntil = self.now + CFG.stance.burstTime
	local defense = a.team ~= self.offense
	if defense then
		a.st.pedal = true
		local face = self.dir < 0 and 0 or math.pi
		setPose(a.model, "pedal", 0.15)
		if a.kind == "human" then self:sendTo(a, { kind = "pedal", on = true, face = face }) else a.faceHeading = face end
	else
		setPose(a.model, nil, 0.15)
		if a.kind == "ai" then a.faceHeading = nil end
	end
	if a.kind == "human" then
		local label = defense and "GET-OFF" or "RELEASE"
		if g == "PERFECT" then self:fb(a, "PERFECT " .. label .. "!", "good", 1.0)
		elseif g == "GOOD" then self:fb(a, "GOOD " .. label, "good", 0.8)
		elseif g == "SLOW" then self:fb(a, "JUMPED THE SNAP · SLOW START", "bad", 1.0)
		else self:fb(a, "LATE " .. label, "neutral", 0.7) end
	end
	self:log("RELEASE", { who = a.team .. a.slot, grade = g })
end

function G:flip(a, beaten)
	if not a.st.pedal then return end
	a.st.pedal = false
	a.st.flipUntil = self.now + (beaten and CFG.pedal.beatenStumble or CFG.pedal.flipTime)
	setPose(a.model, nil, 0.12)
	if a.kind == "human" then
		self:sendTo(a, { kind = "pedal", on = false })
		if beaten then self:fb(a, "BEATEN · FLIP YOUR HIPS EARLIER", "bad", 1.0) end
	else
		a.faceHeading = nil
		if beaten and a.man then self:fb(a.man, "YOU BEAT HIM DEEP!", "good", 1.0) end
	end
end

function G:falseStart(a)
	local f = self.field
	self.los = clamp(self.los - self.dir * self:yards(CFG.stance.falseStartYards), f.northGoal + 1, f.southGoal - 1)
	self:log("FALSE_START", { who = a.team .. a.slot })
	if (Rules.clockStops("penalty", self.halfClock or 1e9, CFG)) then self.clockStopped = true end
	self:setupDown("FALSE START · " .. (a.kind == "human" and a.name or "AI") .. " · −" .. CFG.stance.falseStartYards .. " yds · replay the down")
end

-------------------------------------------------------------------------------------------------- movement
function G:mult(a)
	local st, n = a.st, self.now
	if n < st.frozenUntil or n < st.stunUntil then return 0 end
	local m = 1
	if n < st.recoverUntil then m *= 0.25 end
	if n < st.burstUntil then m *= st.burst end
	if n < st.flipUntil then m *= 0.45 end
	if n < st.dragUntil then m *= 0.35 end
	if n < st.engagedUntil then m *= TC.engagedScale end
	return m
end

function G:baseSpeed(a)
	local M = CFG.move
	if self.state ~= "live" then return 0 end
	if a.team == self.offense then
		if self.carrier == a then return a.kind == "ai" and M.carrySpeed * 0.97 or M.carrySpeed end
		if a.slot == 1 and self.ball and self.ball.holder == a and self.phase == "pocket" then return TC.qbPocketSpeed end
		if not a.st.released then return 0 end
		return a.kind == "ai" and M.cpuWrSpeed or M.wrSpeed
	end
	if a.slot == 1 then
		if self.now < (self.rushAt or 0) then return 0 end
		return a.kind == "ai" and M.cpuDbSpeed or M.dbSpeed
	end
	if not a.st.released then return 0 end
	if a.st.pedal then return CFG.pedal.speed end
	return a.kind == "ai" and M.cpuDbSpeed or M.dbSpeed
end

-- Sprint (2026-11-02): +CFG.sprint.mult while held, draining a small stamina tank; empty locks out until
-- minToStart recovers. Humans toggle via the "sprint" intent (burst key); AI sprints in the same situations a
-- player would — carrying the ball, or pursuing the carrier — so the fairness pillar holds.
function G:sprintStep(a, dt)
	local K = CFG.sprint
	if not K then return 1 end
	a.stamina = a.stamina or K.staminaMax
	local on
	if a.kind == "ai" then
		on = self.state == "live" and (self.carrier == a or (self.phase == "run" and a.team ~= self.offense))
	else
		on = a.st.sprintOn == true and self.state == "live"
	end
	if a.sprintLock and a.stamina >= K.minToStart then a.sprintLock = nil end
	if on and not a.sprintLock and a.stamina > 0 then
		a.stamina = math.max(0, a.stamina - dt * K.drainRate)
		if a.stamina <= 0 then a.sprintLock = true end
		return K.mult
	end
	a.stamina = math.min(K.staminaMax, a.stamina + dt * K.recoverRate)
	return 1
end

function G:steer(a, x, z, speed) a.wantX, a.wantZ, a.wantSpeed = x, z, speed end
function G:hold(a) a.wantX = nil end

function G:aiStep(a, dt)
	local st = a.st
	local dir, speed = Vector3.zero, 0
	if st.lunge and self.now < st.lunge.untilT then
		dir, speed = st.lunge.dir, st.lunge.speed
	elseif st.lunge then
		if st.lunge.kind == "tackle" and self.state == "live" then st.recoverUntil = math.max(st.recoverUntil, self.now + CFG.tackle.whiffRecovery) end
		st.lunge = nil
	elseif a.wantX and self.state == "live" then
		local x, z = self:pos(a)
		local dx, dz = a.wantX - x, a.wantZ - z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 0.3 then dir = Vector3.new(dx / d, 0, dz / d); speed = math.min(a.wantSpeed, self:baseSpeed(a) > 0 and a.wantSpeed or 0) * self:mult(a) * self:sprintStep(a, dt) end -- * sprintStep added 2026-11-02
	end
	a.hum.WalkSpeed = math.max(speed * S, 0.01)
	a.hum:Move(dir)
	if a.faceHeading and not (st.lunge) then
		a.hum.AutoRotate = false
		local p = a.hrp.Position
		a.hrp.CFrame = CFrame.lookAt(p, p + Vector3.new(math.sin(a.faceHeading), 0, math.cos(a.faceHeading)))
	else
		a.hum.AutoRotate = true
	end
	local v = a.hrp.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local sp = flat.Magnitude / S
	if a.tracks then
		-- was: binary idle<->run at sp>1.0 m/s with run:AdjustSpeed(math.clamp(sp * S / 16, 0.8, 2.2) * (backpedal and -0.8 or 1)) (2026-11-02)
		local backward = flat.Magnitude > 1e-4 and flat.Unit:Dot(a.hrp.CFrame.LookVector) < -0.3
		AWMotion.locomote(a.tracks, flat.Magnitude, backward, st)
	end
end

function G:lungeAI(a, dirX, dirZ, speed, time, kind)
	a.st.lunge = { dir = Vector3.new(dirX, 0, dirZ).Unit, speed = speed, untilT = self.now + time, kind = kind }
	a.faceHeading = nil
	local p = a.hrp.Position
	a.hrp.CFrame = CFrame.lookAt(p, p + Vector3.new(dirX, 0, dirZ))
end

-------------------------------------------------------------------------------------------------- helpers
function G:defenders() local t = {}; for s = 1, self.size do local d = self.slots[other(self.offense)][s]; if d then table.insert(t, d) end end; return t end
function G:receivers() local t = {}; for s = 2, self.size do local r = self.slots[self.offense][s]; if r then table.insert(t, r) end end; return t end
function G:nearestDefender(x, z, except)
	local best, bd
	for _, d in ipairs(self:defenders()) do
		if d ~= except then
			local dx, dz = self:pos(d)
			local dd = dist2(x, z, dx, dz)
			if not bd or dd < bd then best, bd = d, dd end
		end
	end
	return best, bd or math.huge
end
function G:separation(r)
	local x, z = self:pos(r)
	local _, d = self:nearestDefender(x, z, self:rusher())
	return d
end

-------------------------------------------------------------------------------------------------- per tick
function G:update(dt)
	self.now += dt
	if self.messageTimer then self.messageTimer -= dt; if self.messageTimer <= 0 and self.state ~= "final" then self.message = nil; self.messageTimer = nil end end
	for p, f in pairs(self.feedbackFor) do f.t -= dt; if f.t <= 0 then self.feedbackFor[p] = nil end end
	if self.state == "lobby" or self.state == "countdown" then
		if self.state == "countdown" then
			self.countdown -= dt
			if self.countdown <= 0 then self:startGame(); return end
		elseif self.lobbySince and self:humanCount() > 0 and self.now - self.lobbySince >= TC.lobbyAutoStart then
			self:startGame(); return
		end
		self.lobbyTimer = (self.lobbyTimer or 0) - dt
		if self.lobbyTimer <= 0 then
			self.lobbyTimer = 0.5
			-- players who wandered off leave the lobby
			for _, team in ipairs({ "home", "away" }) do
				for s = 1, self.size do
					local r = self.roster[team][s]
					local hrp = r and r.player.Character and r.player.Character:FindFirstChild("HumanoidRootPart")
					if r and (not hrp or dist2(hrp.Position.X / S, hrp.Position.Z / S, self.field.cx, self.field.cz) > self.field.halfL + TC.leaveDistance) then
						self:leave(r.player); return
					end
				end
			end
			if self:humanCount() > 0 then self:sendLobby() end
		end
		return
	end
	-- humans who walked away
	for _, a in ipairs(self:athletes()) do
		if a.kind == "human" then
			local x, z = self:pos(a)
			if self.now - a.st.placedAt > 2 and dist2(x, z, self.field.cx, self.field.cz) > self.field.halfL + TC.leaveDistance then self:leave(a.player); return end
		end
	end
	-- game clock: paused in OT (untimed shootout), during the try (untimed down) and after a window stop
	if self.clockStarted and (self.otRound or 0) == 0 and not self.tryActive and self.state ~= "tryDeclare" and self.state ~= "final" then
		if not self.clockStopped then self.halfClock = math.max(0, (self.halfClock or 0) - dt) end
	end
	if self.state == "preSnap" then
		self.snapTimer -= dt
		if self.snapTimer <= 0 then
			if self.pre == "lineup" then self:getSet() else self:snap() end
		end
	elseif self.state == "live" then
		self.playClock += dt
		self:updateLive(dt)
	elseif self.state == "tryDeclare" then
		self.timer -= dt
		if self.try then self.try.timeLeft = math.max(0, self.timer) end
		if self.timer <= 0 then self:declareTry(1); return end
	elseif self.state == "downOver" then
		self.timer -= dt
		if self.timer <= 0 then self:advance(); return end
	elseif self.state == "final" then
		self.timer -= dt
		if self.timer <= 0 then self:backToLobby(); return end
	end
	for _, a in ipairs(self:athletes()) do
		if a.kind == "ai" then self:aiStep(a, dt)
		else a.hum.WalkSpeed = self:baseSpeed(a) * self:mult(a) * self:sprintStep(a, dt) * S end -- * sprintStep added 2026-11-02
	end
	self.hudTimer = (self.hudTimer or 0) - dt
	if self.hudTimer <= 0 then self.hudTimer = 0.1; self:sendHud() end
end

function G:updateLive(dt)
	-- releases off the HUT
	for _, a in ipairs(self:athletes()) do
		if not a.st.released then
			if a.kind == "human" and self.now - self.snapAt >= CFG.stance.autoRelease then self:release(a, true)
			elseif a.kind == "ai" and a.st.reactAt and self.now >= a.st.reactAt then self:release(a, false) end
		end
	end
	self:updatePedals()
	if self.phase == "pocket" then self:updatePocket(dt) end
	if self.ball and self.ball.air then self:updateFlight(dt) end
	if self.state ~= "live" then return end
	if self.phase == "run" then self:updateRun(dt) end
	if self.state ~= "live" then return end
	if self.wrap then
		local w = self.wrap
		if w.by.kind == "human" and w.carrier.kind == "ai" and not w.rolled then
			w.rolled = true
			if self.rng:next() < CFG.tackle.cpuBreakChance then w.aiBreaksAt = self.now + 0.15 end
		end
		if w.aiBreaksAt and self.now >= w.aiBreaksAt then self:breakWrap("juke")
		elseif self.now > w.endsAt then self:finishWrap() end
	end
	if self.state ~= "live" then return end
	self:updateBlocks()
	for _, a in ipairs(self:athletes()) do if a.kind == "ai" then self:aiThink(a, dt) end end
end

-- defenders pedal off the line facing the offense until they flip; beaten deep = forced flip with a stumble
function G:updatePedals()
	local P = CFG.pedal
	for _, d in ipairs(self:defenders()) do
		if d.st.pedal then
			local man = d.man
			if self.ball and self.ball.air then self:flip(d, false)
			elseif man then
				local mx, mz = self:pos(man); local x, z = self:pos(d)
				local gap = (z - mz) * self.dir
				if gap < -P.beatenMargin then self:flip(d, true)
				elseif d.kind == "ai" then
					local mvx = select(1, self:vel(man))
					if gap < P.cpuCushion or math.abs(mvx) > 5 then
						d.st.flipAt = d.st.flipAt or (self.now + P.cpuFlipReaction)
						if self.now >= d.st.flipAt then self:flip(d, false) end
					end
				end
			end
		end
	end
end

function G:updatePocket(dt)
	local qb = self:qb()
	if not (self.ball and self.ball.holder == qb) then return end
	local x, z = self:pos(qb)
	local f = self.field
	if math.abs(x - f.cx) > f.halfW then self:endPlay("OOB", z, "QB stepped out"); return end
	if self:inOwnEndZone(z) and self.now - self.snapAt > 0.5 then
		-- only a safety if he's brought down there; walking back into the end zone is allowed but risky
	end
	if (z - self.los) * self.dir > 0.4 then
		self.phase = "run"; self.carrier = qb
		self:msg("QB SCRAMBLE!", 1.0)
		self:fb(qb, "SCRAMBLE · Q/E juke · C spin · R stiff-arm", "warn", 1.2)
		self:sendBall()
		self:log("SCRAMBLE", {})
	end
end

-------------------------------------------------------------------------------------------------- throwing (human and AI QB share one solver)
function G:throwTo(qb, r, lob, rushed)
	if not (self.ball and self.ball.holder == qb and self.phase == "pocket") or not r then return end
	local Q, f = CFG.qb, self.field
	local qx, qz = self:pos(qb)
	if (qz - self.los) * self.dir > 0 then self:fb(qb, "PAST THE LINE · RUN IT", "bad", 0.8); return end
	local rx, rz = self:pos(r); local rvx, rvz = self:vel(r)
	self.highBall = lob and true or false
	local from = { x = qx, y = f.floorY + 1.75, z = qz }
	local dist0 = dist2(rx, rz, from.x, from.z)
	local t = Rules.flightTime(dist0, CFG)
	if self.highBall then t = clamp(t * CFG.jump.flightScale, CFG.ball.minFlight, CFG.jump.maxFlight) end
	local catchY = f.floorY + (self.highBall and CFG.jump.highCatchHeight or CFG.ball.catchHeight)
	local lead = { x = rx + rvx * t * Q.leadFactor, y = catchY, z = rz + rvz * t * Q.leadFactor }
	-- accuracy: same formula for everyone; pressure and throwing on the run widen the miss
	local rusher = self:rusher()
	local pressured = false
	if rusher and self.now >= (self.rushAt or 0) then
		local px, pz = self:pos(rusher)
		pressured = dist2(px, pz, qx, qz) < TC.pressureRadius
	end
	local onRun = self:speedOf(qb) > TC.onRunSpeed
	local err = (1 - Q.accuracy) * 3.2 + ((rushed or pressured) and Q.rushedPenalty or 0) + (onRun and TC.onRunPenalty or 0)
	local ang, rr = self.rng:next() * math.pi * 2, self.rng:next() * err
	lead.x += math.cos(ang) * rr; lead.z += math.sin(ang) * rr
	lead.x = clamp(lead.x, f.cx - f.halfW - 2, f.cx + f.halfW + 2)
	local d3 = math.sqrt((lead.x - from.x) ^ 2 + (lead.y - from.y) ^ 2 + (lead.z - from.z) ^ 2)
	t = Rules.flightTime(d3, CFG)
	if self.highBall then t = clamp(t * CFG.jump.flightScale, CFG.ball.minFlight, CFG.jump.maxFlight) end
	local v = Rules.solveThrow(from, lead, t, CFG.ball.gravity)
	self.ball = { air = true, holder = nil, target = r, thrower = qb, from = from, vel = v, flight = t, airTime = 0, aim = lead, t0 = workspace:GetServerTimeNow() }
	self.phase = "flight"
	setPose(qb.model, "throw", 0.08)
	if qb.kind == "ai" then qb.faceHeading = nil end
	task.delay(0.35, function() if qb.model.Parent then setPose(qb.model, nil, 0.2) end end)
	-- AI athletes near the landing spot time a leap for a jump ball (same reaction error for both sides)
	for _, a in ipairs(self:athletes()) do a.st.catchPress = nil; a.st.swatPress = nil; a.st.jumpAt = nil; a.st.jumpPlanned = nil end
	if self.highBall then
		local apex = Rules.jumpApexTime(CFG)
		local nd = self:nearestDefender(lead.x, lead.z)
		for _, a in ipairs({ r, nd }) do
			if a and a.kind == "ai" then a.st.jumpPlanned = t - apex + (self.rng:next() - 0.5) * 2 * CFG.jump.cpuReaction end
		end
		self:fb(r, "JUMP BALL · SPACE AT THE PEAK", "warn", math.min(1.1, t - 0.2))
	end
	self:fb(r, self.highBall and "JUMP BALL · SPACE AT THE PEAK" or "BALL'S COMING · SPACE / F TO CATCH", "warn", math.min(1.1, t - 0.1))
	self.stats.throws = (self.stats.throws or 0) + 1
	self:log("THROW", { to = r.team .. r.slot, flight = math.floor(t * 100) / 100, err = math.floor(rr * 100) / 100, high = self.highBall, pressured = pressured, onRun = onRun, human = qb.kind == "human" })
	self:sendBall()
end

function G:updateFlight(dt)
	local b, f = self.ball, self.field
	b.airTime += dt
	local t = math.min(b.airTime, b.flight)
	local bx = b.from.x + b.vel.x * t
	for _, a in ipairs(self:athletes()) do
		if a.kind == "ai" and a.st.jumpPlanned and b.airTime >= a.st.jumpPlanned and not a.st.jumpAt then
			local x, z = self:pos(a)
			if dist2(x, z, b.aim.x, b.aim.z) < 2.6 then a.hum.Jump = true; a.st.jumpAt = b.airTime else a.st.jumpPlanned = nil end
		end
	end
	if math.abs(bx - f.cx) > f.halfW + 0.5 then self:resolveArrival("OUT_OF_BOUNDS"); return end
	if b.airTime >= b.flight then self:resolveArrival(nil) end
end

function G:resolveArrival(forced)
	local b = self.ball
	local t = math.min(b.airTime, b.flight)
	local g = CFG.ball.gravity
	local bx, bz = b.from.x + b.vel.x * t, b.from.z + b.vel.z * t
	local wr = b.target
	local wx, wz = self:pos(wr)
	local db, dDB = self:nearestDefender(bx, bz)
	local dWR = dist2(wx, wz, bx, bz)
	local res
	if forced == "OUT_OF_BOUNDS" then res = { result = "INCOMPLETE", detail = "thrown out of bounds" }
	else
		local wrIn = { dist = dWR, human = wr.kind == "human", pressed = wr.st.catchPress and wr.st.catchPress.kind or nil,
			timing = wr.st.catchPress and (wr.st.catchPress.at - b.airTime) or nil }
		local dbIn = db and { dist = dDB, human = db.kind == "human", pressed = db.st.swatPress ~= nil,
			timing = db.st.swatPress and (db.st.swatPress.at - b.airTime) or nil } or nil
		if self.highBall then
			if wr.kind == "ai" then wrIn.jumped = wr.st.jumpAt ~= nil; wrIn.timing = wr.st.jumpAt and (wr.st.jumpAt - b.airTime) or nil
			else wrIn.jumped = wr.st.catchPress ~= nil end
			if dbIn then
				if db.kind == "ai" then dbIn.jumped = db.st.jumpAt ~= nil; dbIn.timing = db.st.jumpAt and (db.st.jumpAt - b.airTime) or nil
				else dbIn.jumped = db.st.swatPress ~= nil end
			end
		end
		res = Rules.resolveCatch(wrIn, dbIn, CFG, self.rng, self.highBall)
	end
	b.air = false
	-- feedback: receiver, defender, thrower
	local grade = Rules.catchGrade(wr.st.catchPress and (wr.st.catchPress.at - b.airTime) or nil, CFG)
	if res.result == "CATCH" then
		self:fb(wr, (self.highBall and "SKIED FOR IT!") or ((grade == "PERFECT" and "PERFECT " or grade == "GOOD" and "CLEAN " or "") .. "CATCH"), "good", 1.2, res.detail)
		self:fb(db, "COMPLETE · GO MAKE THE TACKLE", "bad", 1.0)
		self:fb(b.thrower, "COMPLETE!", "good", 1.0)
	elseif res.result == "INT" then
		self:fb(db, self.highBall and "SKIED FOR THE PICK!" or "INTERCEPTION!", "good", 1.4)
		self:fb(wr, "PICKED OFF", "bad", 1.2); self:fb(b.thrower, "INTERCEPTED", "bad", 1.2)
	elseif res.result == "SWAT" then
		self:fb(db, self.highBall and "SKIED AND SWATTED!" or "SWAT!", "good", 1.2)
		self:fb(wr, "SWATTED", "bad", 1.0); self:fb(b.thrower, "BROKEN UP", "bad", 1.0)
	elseif res.result == "DROP" then
		self:fb(wr, "DROPPED" .. (grade == "EARLY" and " · TOO EARLY" or grade == "LATE" and " · TOO LATE" or ""), "bad", 1.2)
	else
		self:fb(wr, grade == "EARLY" and "TOO EARLY" or grade == "LATE" and "TOO LATE" or (res.detail == "thrown out of bounds" and "OVERTHROWN" or "INCOMPLETE"), "bad", 1.0)
	end
	self:log("ARRIVAL", { result = res.result, detail = res.detail, dWR = math.floor(dWR * 100) / 100, dDB = math.floor(dDB * 100) / 100, high = self.highBall })
	if res.result == "CATCH" then
		self.ball = { holder = wr, air = false }
		self.passCaught = true -- a completed forward pass: makes this play a "pass" for try legality (Rules.resolveTry)
		self.carrier = wr; self.phase = "run"
		wr.st.immuneUntil = self.now + (CFG.catch.runAfterCatch or 0) -- was 0: the catcher was wrapped at the catch point before he could move (owner, 2026-11-02)
		if wr.kind == "ai" then wr.faceHeading = nil end
		self.stats.catches = (self.stats.catches or 0) + 1
		self:sendBall()
		if self:scoredAt(wz) then self:endPlay("TD", wz, "caught in the end zone") end
		return
	end
	if res.result == "INT" then
		self.ball = { holder = db, air = false }; self:sendBall()
		self:endPlay("INT", bz, res.detail); return
	end
	self.ball = { air = false, landed = { x = bx, z = bz } }
	self:sendBall()
	self:endPlay("INCOMPLETE", nil, res.detail)
end

-------------------------------------------------------------------------------------------------- AI brains
function G:aiQB(a, dt)
	local Q = CFG.qb
	local x, z = self:pos(a)
	a.faceHeading = self.dir < 0 and math.pi or 0
	if self.playClock < Q.dropbackTime then
		self:steer(a, a.spot.x, a.spot.z - self.dir * 1.5, Q.dropbackDepth / Q.dropbackTime + 1.5); return
	end
	self:hold(a)
	if self.qbWindupUntil then
		if self.now >= self.qbWindupUntil then
			local r, lob, rushed = self.qbTarget, self.qbLob, self.qbRushed
			self.qbWindupUntil = nil; self.qbTarget = nil
			self:throwTo(a, r, lob, rushed)
		end
		return
	end
	-- read: a teammate calling for it (human) gets it if he has a step; otherwise the most open man
	local best, bestSep, called
	for _, r in ipairs(self:receivers()) do
		local sep = self:separation(r)
		local rx, rz = self:pos(r)
		local downfield = (rz - self.los) * self.dir
		if r.kind == "human" and r.st.calledAt and self.now - r.st.calledAt < 1.2 and sep >= 1.5 then called = r end
		local score = sep + (downfield > 2 and 0.6 or 0) + math.min(downfield, 15) * 0.05
		if not bestSep or score > bestSep then best, bestSep = r, score end
	end
	local rusher = self:rusher()
	local pressure = false
	if rusher and self.now >= (self.rushAt or 0) then local px, pz = self:pos(rusher); pressure = dist2(px, pz, x, z) < TC.pressureRadius + 0.6 end
	local target
	if called then target = called
	elseif best and self.playClock >= Q.minReadTime and self:separation(best) >= TC.openSeparation then target = best
	elseif pressure or self.playClock >= Q.deadline then target = best end
	if target then
		self.qbTarget = target
		local sep = self:separation(target)
		self.qbLob = sep < CFG.jump.tightCoverage * 0.8 or target.route == "fade" or target.route == "seam"
		self.qbRushed = pressure or self:separation(target) < TC.openSeparation
		self.qbWindupUntil = self.now + Q.windup
		local tx, tz = self:pos(target)
		a.faceHeading = math.atan2(tx - x, tz - z)
		self:log("READ", { to = target.team .. target.slot, sep = math.floor(sep * 10) / 10, rushed = self.qbRushed, called = called ~= nil })
	end
end

function G:aiReceiver(a)
	local M = CFG.move
	local pts = a.st.routePts
	local x, z = self:pos(a)
	if #pts == 0 then self:steer(a, x, z + self.dir * 6, M.cpuWrSpeed); return end
	local i = a.st.routeIdx
	local tgt = pts[math.min(i, #pts)]
	if dist2(x, z, tgt.x, tgt.z) < 0.8 then
		if i < #pts then a.st.routeIdx += 1; tgt = pts[a.st.routeIdx]
		elseif a.route == "curl" then self:hold(a); return
		else
			local p0 = pts[#pts - 1] or a.spot
			local dx, dz = tgt.x - p0.x, tgt.z - p0.z
			local l = math.max(math.sqrt(dx * dx + dz * dz), 0.01)
			tgt = { x = clamp(tgt.x + dx / l * 15, self.field.cx - self.field.halfW + 1, self.field.cx + self.field.halfW - 1), z = tgt.z + dz / l * 15 }
			a.st.routePts = { tgt }; a.st.routeIdx = 1
		end
	end
	self:steer(a, tgt.x, tgt.z, M.cpuWrSpeed)
end

function G:aiCarrier(a)
	local M = CFG.move
	local x, z = self:pos(a)
	local d, dd = self:nearestDefender(x, z)
	local dx, dz = 0, self.dir
	if d then
		local ox, oz = self:pos(d)
		local rx, rz = ox - x, oz - z
		if rz * self.dir > -1 and dd < 12 then dx = (rx > 0 and -1 or 1) * clamp((12 - dd) / 9, 0.2, 0.95) end
		if dd < 2.6 and self.now >= a.st.jukeCd and self.rng:next() < CFG.ai.cpuJukeChance then
			a.st.jukeCd = self.now + M.jukeCooldown
			a.st.immuneUntil = self.now + CFG.tackle.jukeImmunity
			self:lungeAI(a, -(rx >= 0 and 1 or -1), 0.3 * self.dir, M.jukeSpeed, M.jukeTime, "juke")
			self:log("AI_JUKE", { who = a.team .. a.slot })
			return
		end
	end
	local f = self.field
	if x > f.cx + f.halfW - 2 then dx = math.min(dx, -0.5) end
	if x < f.cx - f.halfW + 2 then dx = math.max(dx, 0.5) end
	local l = math.sqrt(dx * dx + dz * dz)
	self:steer(a, x + dx / l * 5, z + dz / l * 5, M.carrySpeed)
end

function G:aiDefender(a)
	local M, D = CFG.move, CFG.defend
	local x, z = self:pos(a)
	local holder = self.ball and self.ball.holder
	-- ball carrier (or QB in the pocket for the rusher): pursue with an angle and tackle in reach
	local chase = nil
	if self.phase == "run" then chase = self.carrier
	elseif self.phase == "pocket" and a.slot == 1 and self.now >= (self.rushAt or 0) then chase = holder end
	if chase then
		local cx, cz = self:pos(chase)
		local vx, vz = self:vel(chase)
		self:steer(a, cx + vx * 0.35, cz + vz * 0.35, M.cpuDbSpeed)
		a.faceHeading = nil
		if dist2(x, z, cx, cz) < CFG.tackle.reach + 0.3 and self.now >= a.st.tackleCd and self.now >= a.st.recoverUntil and not a.st.lunge then
			local ang = math.atan2(cx - x, cz - z) + (self.rng:next() - 0.5) * CFG.ai.cpuTackleAngleError
			a.st.tackleCd = self.now + CFG.tackle.cooldown
			self:lungeAI(a, math.sin(ang), math.cos(ang), CFG.tackle.lungeSpeed, CFG.tackle.lungeTime, "tackle")
			self:attemptTackle(a, chase, { x = x, z = z, heading = ang, vx = math.sin(ang) * CFG.tackle.lungeSpeed, vz = math.cos(ang) * CFG.tackle.lungeSpeed })
		end
		return
	end
	if a.slot == 1 then self:hold(a); return end
	if not a.st.released then self:hold(a); return end
	local man = a.man
	if not man then self:hold(a); return end
	local mx, mz = self:pos(man)
	if self.phase == "flight" and self.ball.airTime >= D.reaction + 0.2 then
		self:steer(a, self.ball.aim.x, self.ball.aim.z, M.cpuDbSpeed); a.faceHeading = nil; return
	end
	if a.st.pedal then
		self:steer(a, mx, z + self.dir * 3, CFG.pedal.speed); return
	end
	-- man coverage with human-like lag: chase where the man WAS `reaction` seconds ago, a step downfield
	table.insert(a.st.trail, { x = mx, z = mz, t = self.now })
	while #a.st.trail > 2 and self.now - a.st.trail[1].t > D.reaction do table.remove(a.st.trail, 1) end
	local past = a.st.trail[1]
	self:steer(a, past.x, past.z + self.dir * 1.2, M.cpuDbSpeed)
end

function G:aiThink(a, dt)
	if a.st.lunge then return end
	if a.team == self.offense then
		if a.slot == 1 and self.ball and self.ball.holder == a and self.phase == "pocket" then self:aiQB(a, dt); return end
		if self.carrier == a then self:aiCarrier(a); return end
		if self.phase == "pocket" then
			if a.slot == 1 then self:hold(a) elseif a.st.released then self:aiReceiver(a) else self:hold(a) end
		elseif self.phase == "flight" then
			if self.ball.target == a then self:steer(a, self.ball.aim.x, self.ball.aim.z, CFG.move.cpuWrSpeed)
			else self:hold(a) end
		elseif self.phase == "run" then
			-- block for the carrier: get between him and the closest free defender
			local c = self.carrier
			local cx, cz = self:pos(c)
			local best, bd
			for _, d in ipairs(self:defenders()) do
				if self.now >= d.st.engagedUntil then
					local dx, dz = self:pos(d)
					local dd = dist2(dx, dz, cx, cz)
					if not bd or dd < bd then best, bd = d, dd end
				end
			end
			if best then local dx, dz = self:pos(best); self:steer(a, (dx + cx) / 2, (dz + cz) / 2, CFG.move.cpuWrSpeed)
			else self:hold(a) end
		end
	else
		self:aiDefender(a)
	end
end

-- blocks: an offensive player who gets a body on a defender slows him down for a moment (humans block by contact too)
function G:updateBlocks()
	if self.phase ~= "run" then return end
	for _, o in ipairs(self:athletes()) do
		if o.team == self.offense and o ~= self.carrier and self.now >= o.st.blockCd then
			local ox, oz = self:pos(o)
			for _, d in ipairs(self:defenders()) do
				if self.now >= d.st.engagedUntil then
					local dx, dz = self:pos(d)
					if dist2(ox, oz, dx, dz) < TC.blockReach then
						d.st.engagedUntil = self.now + TC.blockDrag; o.st.blockCd = self.now + TC.blockCooldown
						self:fb(o, "BLOCK!", "good", 0.6); self:fb(d, "BLOCKED", "bad", 0.6)
						self:log("BLOCK", { by = o.team .. o.slot, on = d.team .. d.slot })
						break
					end
				end
			end
		end
	end
end

function G:updateRun(dt)
	local c = self.carrier
	if not c then return end
	local x, z = self:pos(c)
	local f = self.field
	if self:scoredAt(z) then self:endPlay("TD", z, (c.kind == "human" and c.name or "AI") .. " ran it in"); return end
	if math.abs(x - f.cx) > f.halfW then self:endPlay("OOB", z, "stepped out of bounds"); return end
end

-------------------------------------------------------------------------------------------------- tackling
-- attacker info {x, z, heading, vx, vz}
function G:attemptTackle(d, c, info)
	if self.state ~= "live" then return end
	local cx, cz = self:pos(c)
	if self.wrap then
		if self.wrap.carrier == c and self.wrap.by ~= d and dist2(info.x, info.z, cx, cz) <= CFG.tackle.lungeReach + 0.3 then
			self:fb(d, "GANG TACKLE", "good", 1.0)
			self:finishWrap(); return
		end
		return
	end
	local cvx, cvz = self:vel(c)
	info.lunging = true
	local res = Rules.resolveTackle(info, { x = cx, z = cz, vx = cvx, vz = cvz, hasBall = true, live = true, immuneUntil = c.st.immuneUntil }, self.now, CFG)
	self:log("TACKLE", { by = d.team .. d.slot, on = c.team .. c.slot, result = res })
	local sack = self.phase == "pocket"
	if res == "CLEAN_TACKLE" then
		self:fb(d, sack and "SACK!" or "BIG HIT", "good", 1.2)
		self:fb(c, sack and "SACKED" or "TACKLED", "bad", 1.2)
		if c.kind == "ai" then c.hum:ChangeState(Enum.HumanoidStateType.FallingDown) else self:sendTo(c, { kind = "fall" }) end
		if d.kind == "human" then self:sendTo(d, { kind = "lunge", stop = true }) else d.st.lunge = nil; d.st.recoverUntil = self.now + 0.2 end
		self.stats.tackles = (self.stats.tackles or 0) + 1
		if self:inOwnEndZone(cz) then self:endPlay("SAFETY", cz, "tackled in the end zone"); return end
		self:endPlay(sack and "SACK" or "TACKLE", cz, (d.kind == "human" and d.name or "AI") .. (sack and " got to the QB" or " made the hit"))
	elseif res == "WRAP" then
		local T = CFG.tackle
		self.wrap = { by = d, carrier = c, breakUntil = self.now + T.breakWindow, endsAt = self.now + T.wrapDrag, rolled = false, sack = sack }
		c.st.dragUntil = self.now + T.wrapDrag
		if d.kind == "human" then self:sendTo(d, { kind = "lunge", stop = true }) else d.st.lunge = nil end
		self:fb(d, "WRAPPED UP", "warn", 0.9)
		self:fb(c, "WRAPPED · Q/E/C/R TO BREAK", "warn", T.breakWindow)
	else
		self:fb(d, res == "EVADED" and "JUKED" or "WHIFF", "bad", 1.0)
		self:fb(c, res == "EVADED" and "SHOOK HIM" or "HE MISSED", "good", 1.0)
	end
end

function G:breakWrap(move)
	local w = self.wrap
	if not w then return end
	self.wrap = nil
	w.carrier.st.dragUntil = 0
	w.carrier.st.immuneUntil = self.now + 0.35
	w.by.st.stunUntil = self.now + 0.6
	self:fb(w.carrier, "BROKE THE TACKLE", "good", 1.0); self:fb(w.by, "BROKEN TACKLE", "bad", 1.0)
	self:log("BROKEN_TACKLE", { by = w.carrier.team .. w.carrier.slot, move = move })
end

function G:finishWrap()
	local w = self.wrap
	if not w then return end
	self.wrap = nil
	local c = w.carrier
	local _, z = self:pos(c)
	self:fb(w.by, w.sack and "SACK!" or "WRAP TACKLE", "good", 1.2); self:fb(c, w.sack and "SACKED" or "TAKEN DOWN", "bad", 1.2)
	if c.kind == "ai" then c.hum:ChangeState(Enum.HumanoidStateType.FallingDown) else self:sendTo(c, { kind = "fall" }) end
	self.stats.tackles = (self.stats.tackles or 0) + 1
	if self:inOwnEndZone(z) then self:endPlay("SAFETY", z, "wrapped up in the end zone"); return end
	self:endPlay(w.sack and "SACK" or "TACKLE", z, "wrapped up")
end

-------------------------------------------------------------------------------------------------- play end / flow
function G:endPlay(kind, spotZ, detail)
	if self.state ~= "live" then return end
	detail = detail or kind -- a nil detail must never crash the play-end path (seen via the test hook 2026-11-02)
	self.state = "downOver"; self.phase = "dead"; self.timer = TC.downOverTime
	self.wrap = nil; self.qbWindupUntil = nil; self.qbTarget = nil
	for _, a in ipairs(self:athletes()) do
		if a.kind == "ai" then self:hold(a); a.st.lunge = nil else self:sendTo(a, { kind = "lunge", stop = true }); self:sendTo(a, { kind = "pedal", on = false }) end
	end
	if self.ball then self.ball.air = false end
	self:log("PLAY_END", { kind = kind, spotZ = spotZ and math.floor(spotZ * 10) / 10 or nil, detail = detail })
	local off = self.offense
	-- clock stop events (only bite inside the final window — Rules.clockStops decides)
	local stopEvent = kind == "INCOMPLETE" and "incomplete" or kind == "OOB" and "outOfBounds"
		or (kind == "TD" or kind == "SAFETY") and "score" or nil
	if stopEvent and (Rules.clockStops(stopEvent, self.halfClock or 1e9, CFG)) then self.clockStopped = true end
	if self.tryActive then
		-- a try play just ended: resolve with the IFAF rules (pass-only 1-pt from the 5, run-or-pass 2-pt from the 10)
		local playType = self.passCaught and "pass" or "run"
		local result = kind == "TD" and "SCORED" or kind == "SAFETY" and "SAFETY" or "FAILED"
		local r = Rules.resolveTry(self.try and self.try.declared or 1, playType, result, CFG)
		local good = r.points > 0 and r.to ~= "defence"
		if r.points > 0 then self.score[r.to == "defence" and other(off) or off] += r.points end
		self:log("TRY_RESULT", { declared = self.try and self.try.declared, playType = playType, result = result, points = r.points, to = r.to })
		self:msg("TRY · " .. string.upper(r.reason) .. " · HOME " .. self.score.home .. " – " .. self.score.away .. " AWAY", 2.6)
		self:fbTeam(off, good and "TRY GOOD!" or "TRY FAILED", good and "good" or "bad", 1.4, r.reason)
		self.tryActive = nil; self.try = nil
		self.nextStep = "possession"; self:updateBoard(); self:sendHud(); return
	end
	if kind == "TD" then
		self.score[off] += (Rules.scoreFor("TOUCHDOWN", CFG)) -- 6 + a declared try; was TC.td = 7 flat (2026-11-02)
		self:msg("TOUCHDOWN " .. TEAMNAME[off] .. "! · " .. detail .. " · HOME " .. self.score.home .. " – " .. self.score.away .. " AWAY", 2.6)
		self:fbTeam(off, "TOUCHDOWN!", "good", 1.6)
		self.nextStep = "try"; self:updateBoard(); self:sendHud(); return
	end
	if kind == "SAFETY" then
		self.score[other(off)] += (Rules.scoreFor("SAFETY", CFG)) -- was TC.safety
		self:msg("SAFETY · +" .. CFG.scoring.safety .. " " .. TEAMNAME[other(off)] .. " · HOME " .. self.score.home .. " – " .. self.score.away .. " AWAY", 2.6)
		self.nextStep = "possession"; self:updateBoard(); self:sendHud(); return
	end
	if kind == "INT" then
		self:msg("INTERCEPTION · " .. TEAMNAME[other(off)] .. " ball", 2.4)
		self.nextStep = "possession"; self:sendHud(); return
	end
	local gained = 0
	if (kind == "TACKLE" or kind == "OOB" or kind == "SACK") and spotZ then
		gained = Rules.yardsBetween(self.los, spotZ, self.dir, self.field.metresPerYard)
		self.los = clamp(spotZ, self.field.northGoal + 0.5, self.field.southGoal - 0.5)
	end
	local label = kind == "INCOMPLETE" and "INCOMPLETE" or kind == "OOB" and "OUT OF BOUNDS" or kind == "SACK" and "SACK" or "TACKLED"
	local yds = kind == "INCOMPLETE" and "" or (" · " .. (gained >= 0 and "+" or "") .. gained .. " yds")
	if (self.los - self.toGain) * self.dir >= 0 and kind ~= "INCOMPLETE" then
		self.down = 1; self.toGain = self:goalZ()
		self:msg(label .. yds .. " · FIRST DOWN!", 2.0); self.nextStep = "down"
		self:fbTeam(off, "FIRST DOWN!", "good", 1.2)
		if (Rules.clockStops("firstDown", self.halfClock or 1e9, CFG)) then self.clockStopped = true end
	elseif self.down >= CFG.rules.downs then
		self:msg(label .. yds .. " · TURNOVER ON DOWNS", 2.4); self.nextStep = "possession"
	else
		self.down += 1; self:msg(label .. yds .. " · " .. detail, 1.8); self.nextStep = "down"
	end
	self:sendHud()
end

function G:declareTry(n)
	if not self.try or self.try.phase ~= "declare" then return end
	n = n == 2 and 2 or 1
	local spotM, label = Rules.trySpot(n, CFG)
	self.try.declared = n; self.try.phase = "declared"; self.try.timeLeft = nil
	self.tryActive = true
	self.los = self:goalZ() - self.dir * spotM
	self.toGain = self:goalZ()
	self:log("TRY_DECLARED", { declared = n })
	self:setupDown("TRY FOR " .. n .. " · " .. string.upper(label))
end

function G:advance()
	if self.nextStep == "try" then
		self.nextStep = nil
		self.state = "tryDeclare"; self.phase = "dead"; self.timer = TC.tryDeclareTime
		self.try = { team = self.offense, phase = "declare", declared = nil, timeLeft = TC.tryDeclareTime }
		local qb = self.slots[self.offense][1]
		if qb.kind == "ai" then
			-- AI declares: go for 2 when trailing, else take the 1
			self:declareTry(self.score[self.offense] < self.score[other(self.offense)] and 2 or 1)
		else
			self:msg("CHOOSE YOUR TRY · +1 FROM THE 5 (PASS ONLY) · +2 FROM THE 10 (RUN OR PASS)", TC.tryDeclareTime)
			self:sendHud()
		end
		return
	end
	-- half and game end on the clock (regulation only; OT is the untimed shootout below)
	if (self.halfClock or 1) <= 0 and (self.otRound or 0) == 0 then
		if (self.half or 1) < CFG.clock.halves then
			self.half += 1; self.halfClock = CFG.clock.halfSeconds
			self.clockStarted = false; self.clockStopped = true
			self.offense = other(self.halfOpeningOffense or "home")
			self:newPossession("HALFTIME · HALF " .. self.half .. " · " .. TEAMNAME[self.offense] .. " BALL")
			return
		end
		-- regulation over at this dead ball: close the possession gate so the step below finishes or goes to OT
		self.nextStep = "possession"
		self.totalPossessions = math.min(self.totalPossessions, self.possession)
	end
	if self.nextStep == "possession" then
		self.possession += 1
		if self.possession > self.totalPossessions then
			if self.score.home == self.score.away and self.otRound < CFG.rules.maxOtRounds then -- was TC.maxOtRounds = 2
				self.otRound += 1; self.totalPossessions += CFG.rules.otPossessionsEach * 2 -- was TC.otPossessionsEach
				self.offense = other(self.offense)
				self:newPossession("OVERTIME " .. self.otRound .. " · one possession each · " .. TEAMNAME[self.offense] .. " ball")
				return
			end
			self:finish(); return
		end
		self.offense = other(self.offense)
		self:newPossession(TEAMNAME[self.offense] .. " BALL · possession " .. self.possession .. " of " .. self.totalPossessions)
	else
		self:setupDown(nil)
	end
end

function G:finish()
	self.state = "final"; self.timer = TC.finalTime
	local s = self.score
	local w = s.home > s.away and "home" or s.away > s.home and "away" or nil
	self:msg((w and (TEAMNAME[w] .. " WINS") or "DRAW") .. " · FINAL HOME " .. s.home .. " – " .. s.away .. " AWAY", TC.finalTime)
	if w then self:fbTeam(w, "YOU WIN!", "good", 4); self:fbTeam(other(w), "GOOD GAME", "neutral", 4) end
	self:log("FINAL", { home = s.home, away = s.away })
	self:updateBoard()
	self:sendHud()
end

-------------------------------------------------------------------------------------------------- client sync
function G:sendBall()
	local b = self.ball
	local m = { kind = "ball" }
	if not b then m.mode = "hidden"
	elseif b.air then
		m.mode = "flight"; m.high = self.highBall
		m.from = Vector3.new(b.from.x, b.from.y, b.from.z) * S
		m.vel = Vector3.new(b.vel.x, b.vel.y, b.vel.z) * S
		m.g = CFG.ball.gravity * S; m.t0 = b.t0; m.flight = b.flight
		m.target = Vector3.new(b.aim.x, self.field.floorY, b.aim.z) * S
		m.targetModel = b.target and b.target.model
	elseif b.holder then m.mode = "held"; m.holder = b.holder.model
	elseif b.landed then m.mode = "ground"; m.at = Vector3.new(b.landed.x, self.field.floorY + 0.12, b.landed.z) * S
	else m.mode = "hidden" end
	for _, a in ipairs(self:athletes()) do self:sendTo(a, m) end
end

function G:prompt(a)
	local off = a.team == self.offense
	local role = self:roleOf(a)
	if self.state == "preSnap" then
		if off and a.slot == 1 and a.kind == "human" then
			if self.pre == "lineup" then return "1–" .. #self.plays .. " call a play (" .. self.plays[self.play].name .. ") · SPACE: SET" end
			return "SPACE: HUT! (snap it when you're ready)"
		end
		if off then return self.pre == "set" and "SET… release with SPACE on the HUT · moving early = false start" or ("1–6 pick your route (" .. (ROUTES[a.route or "curl"] or ROUTES.curl).label .. ") · wait for SET") end
		if a.slot == 1 then return "RUSHER · you can go after the QB " .. TC.modes[self.mode].rushCount .. "s after the snap" end
		return "Crouch · SPACE on the HUT to get off the line · don't jump the snap"
	elseif self.state == "live" then
		if off then
			if a.slot == 1 and self.ball and self.ball.holder == a and self.phase == "pocket" then
				return "THROW: tap 1–" .. (self.size - 1) .. " (hold = lob) · F = man you face · run past the line to scramble"
			end
			if self.carrier == a then return "RUN! Q/E juke · C spin · R stiff-arm" end
			if not a.st.released then return "HUT! SPACE to release!" end
			if self.phase == "flight" and self.ball.target == a then return self.highBall and "JUMP BALL · SPACE at the peak" or "SPACE secure catch · F aggressive catch" end
			if self.phase == "run" then return "BLOCK! run into a defender to slow him down" end
			return "Run your route · G call for the ball"
		else
			if a.slot == 1 then
				local left = (self.rushAt or 0) - self.now
				if left > 0 then return string.format("RUSH IN %.1f…", left) end
				return "GET THE QB! R to tackle"
			end
			if not a.st.released then return "HUT! SPACE to get off!" end
			if self.phase == "flight" then return self.highBall and "JUMP BALL · SPACE to leap" or "F to swat / intercept" end
			if self.phase == "run" then return "R to tackle · take an angle" end
			if a.st.pedal then return "Backpedal · SHIFT to flip your hips and run" end
			return "Stay with your man (red ring)"
		end
	end
	return nil
end

function G:sendHud()
	local M, T = CFG.move, CFG.tackle
	local off = self.offense
	for _, a in ipairs(self:athletes()) do
		if a.kind == "human" then
			local mine = a.team == off
			local isQB = mine and a.slot == 1
			local pts = {}
			local showRoutes = self.state == "preSnap" or (self.state == "live" and self.phase == "pocket")
			local recv = nil
			if mine and showRoutes then
				local list = isQB and self:receivers() or { a }
				for _, r in ipairs(list) do
					if r.slot >= 2 and r.st.routePts then
						local line = { Vector3.new(r.spot.x, self.field.floorY, r.spot.z) * S }
						for _, p in ipairs(r.st.routePts) do table.insert(line, Vector3.new(p.x, self.field.floorY, p.z) * S) end
						table.insert(pts, line)
					end
				end
			end
			if isQB then
				recv = {}
				for _, r in ipairs(self:receivers()) do
					table.insert(recv, { n = r.slot - 1, model = r.model, open = self.state == "live" and self:separation(r) >= TC.openSeparation, role = self.roles.off[r.slot],
						called = r.st.calledAt ~= nil and self.now - r.st.calledAt < 1.2 })
				end
			end
			local function ready(cd) return 1 - clamp((cd - self.now) / 1.2, 0, 1) end
			local b = self.ball
			local seesTiming = b and b.air and (b.target == a or (not mine))
			State:FireClient(a.player, { kind = "hud", mode = self.mode,
				home = self.score.home, away = self.score.away, myTeam = a.team, slot = a.slot, role = self:roleOf(a),
				offense = off, state = self.state, phase = self.phase,
				down = self.state == "final" and "FINAL" or self:downText(),
				series = { down = self.down, toGain = (self.tryActive or math.abs(self.toGain - self:goalZ()) < 0.01) and "goal" or "mid" },
				clock = self.half and { half = self.half, remaining = math.max(0, self.halfClock or 0),
					running = (self.clockStarted and not self.clockStopped and (self.otRound or 0) == 0
						and not self.tryActive and self.state ~= "tryDeclare") or false,
					play = self.state == "preSnap" and math.max(0, self.snapTimer or 0) or nil,
					stopWindow = (self.halfClock or 1e9) <= CFG.clock.stopClockWindowSeconds } or nil,
				try = self.try and { phase = self.try.phase, team = self.try.team, declared = self.try.declared,
					canDeclare = (a.team == self.try.team and self.try.phase == "declare") or nil, timeLeft = self.try.timeLeft } or nil,
				possession = (self.possession or 1) .. "/" .. (self.totalPossessions or 1) .. ((self.otRound or 0) > 0 and " OT" or ""),
				message = self.message, prompt = self:prompt(a), feedback = self.feedbackFor[a.player],
				plays = (isQB and self.state == "preSnap") and self:playNames() or nil, play = self.play,
				route = a.route, routeLines = pts, pre = self.pre, released = a.st.released, pedal = a.st.pedal,
				losZ = self.los * S, toGainZ = self.toGain * S, dir = self.dir,
				receivers = recv, isQB = isQB,
				man = (not mine and a.slot >= 2 and a.man) and a.man.model or nil,
				carrier = self.carrier and self.carrier.model or nil,
				timing = seesTiming and { remaining = b.flight - b.airTime, flight = b.flight, high = self.highBall,
					pressed = (mine and a.st.catchPress ~= nil) or ((not mine) and a.st.swatPress ~= nil) } or nil,
				wrap = (self.wrap and (self.wrap.carrier == a or self.wrap.by == a)) and { mine = self.wrap.carrier == a, left = math.max(0, self.wrap.breakUntil - self.now) } or nil,
				cooldowns = (self.carrier == a) and { { "JUKE", ready(a.st.jukeCd) }, { "SPIN", ready(a.st.spinCd) }, { "ARM", ready(a.st.stiffCd) } }
					or ((not mine) and { { "TACKLE", 1 - clamp((a.st.tackleCd - self.now) / T.cooldown, 0, 1) } } or {}),
				rushIn = (not mine and a.slot == 1 and self.state == "live") and math.max(0, (self.rushAt or 0) - self.now) or nil,
				sprint = CFG.sprint and { on = a.st.sprintOn == true and not a.sprintLock, stamina = a.stamina or CFG.sprint.staminaMax, max = CFG.sprint.staminaMax } or nil,
			})
		end
	end
end

-------------------------------------------------------------------------------------------------- intents
function G:intent(player, d)
	local act = d.action
	if act == "leave" then self:leave(player); return end
	if self.state == "lobby" or self.state == "countdown" then
		if act == "ready" then self:setReady(player, d.on ~= false)
		elseif act == "pick" then self:pick(player, d.team, tonumber(d.slot))
		elseif act == "team" and (d.team == "home" or d.team == "away") then self:join(player, d.team) end
		return
	end
	local a = self:athleteOf(player)
	if not a then return end
	local off = a.team == self.offense
	local isQB = off and a.slot == 1
	if act == "declareTry" and self.try and self.try.phase == "declare" and a.team == self.try.team then
		self:declareTry(tonumber(d.declared) == 2 and 2 or 1); return
	end
	if act == "sprint" then a.st.sprintOn = d.on == true; return end -- burst key held/released (2026-11-02)
	if self.state == "preSnap" then
		if act == "play" and isQB then
			local i = tonumber(d.index)
			if i and self.plays[i] then self.play = math.floor(i); self.humanPlay = self.humanPlay or {}; self.humanPlay[a.team] = self.play; self:assignRoutes(); self:sendHud() end
		elseif act == "route" and off and not isQB and (ROUTES[d.route] or d.route == "play") then
			a.routeOverride = d.route ~= "play" and d.route or nil
			self:assignRoutes(); self:sendHud()
		elseif act == "primary" then
			if isQB then
				if self.pre == "lineup" then self:getSet()
				elseif self.pre == "set" and self.now - (self.setAt or 0) > 0.3 then self:snap() end
			elseif off then
				if self.pre == "set" and self.now - (self.setAt or 0) > CFG.stance.setGrace then self:falseStart(a) end
			elseif not a.st.jumped and self.pre == "set" then
				a.st.jumped = true
				self:fb(a, "JUMPED THE SNAP", "bad", 0.9)
			end
		end
		return
	end
	if self.state ~= "live" then return end
	if act == "primary" and not a.st.released then self:release(a, false); return end
	if act == "flip" and not off then self:flip(a, false); return end
	if act == "call" and off and not isQB then a.st.calledAt = self.now; setPose(a.model, nil); self:fb(a, "CALLING FOR IT", "neutral", 0.6); return end
	-- QB throws
	if isQB and self.ball and self.ball.holder == a and self.phase == "pocket" then
		if act == "throw" then
			local n = tonumber(d.target)
			local r = n and self.slots[a.team][math.floor(n) + 1]
			if r then self:throwTo(a, r, d.lob == true, false) end
			return
		elseif act == "throwAim" or act == "catchAggressive" then
			local aim = typeof(d.aim) == "Vector3" and d.aim or a.hrp.CFrame.LookVector
			local x, z = self:pos(a)
			local best, bs
			for _, r in ipairs(self:receivers()) do
				local rx, rz = self:pos(r)
				local vx, vz = rx - x, rz - z
				local l = math.max(math.sqrt(vx * vx + vz * vz), 0.01)
				local sc = (vx * aim.X + vz * aim.Z) / l
				if not bs or sc > bs then best, bs = r, sc end
			end
			if best then self:throwTo(a, best, d.lob == true, false) end
			return
		end
	end
	if act == "primary" then act = "catch" end
	local function pressTime()
		local est = tonumber(d.airTime)
		local bt = self.ball.airTime
		if est then return clamp(est, bt - 0.25, bt) end
		return bt
	end
	if self.ball and self.ball.air then
		if off and (act == "catch" or act == "catchAggressive") and not a.st.catchPress then
			a.st.catchPress = { kind = act == "catchAggressive" and "aggressive" or "secure", at = pressTime() }
			return
		end
		if (not off) and (act == "swat" or act == "catchAggressive" or (act == "catch" and self.highBall)) and not a.st.swatPress then
			a.st.swatPress = { at = pressTime() }
			return
		end
	end
	local M, T = CFG.move, CFG.tackle
	-- ball carrier moves (also the QB scrambling)
	if self.carrier == a and self.phase == "run" or (isQB and self.ball and self.ball.holder == a and self.wrap and self.wrap.carrier == a) then
		local moveKey = (act == "jukeL" or act == "jukeR") and "juke" or act == "spin" and "spin" or (act == "stiffarm" or act == "tackle") and "stiffarm" or nil
		if not moveKey then return end
		if self.wrap and self.wrap.carrier == a and self.now <= self.wrap.breakUntil then self:breakWrap(moveKey); return end
		local h = self:headingOf(a)
		if moveKey == "juke" and self.now >= a.st.jukeCd then
			local sgn = act == "jukeL" and 1 or -1
			a.st.jukeCd = self.now + M.jukeCooldown; a.st.immuneUntil = self.now + T.jukeImmunity
			self:sendTo(a, { kind = "lunge", dir = Vector3.new(math.cos(h) * sgn, 0, -math.sin(h) * sgn), speed = M.jukeSpeed * S, time = M.jukeTime })
		elseif moveKey == "spin" and self.now >= a.st.spinCd then
			a.st.spinCd = self.now + M.spinCooldown; a.st.immuneUntil = self.now + M.spinTime
			self:sendTo(a, { kind = "lunge", dir = Vector3.new(math.sin(h), 0, math.cos(h)), speed = M.spinSpeed * S, time = M.spinTime, spin = true })
		elseif moveKey == "stiffarm" and self.now >= a.st.stiffCd then
			a.st.stiffCd = self.now + M.stiffArmCooldown
			local x, z = self:pos(a)
			local nd, dd = self:nearestDefender(x, z)
			if nd and dd <= M.stiffArmReach then
				local nx, nz = self:pos(nd)
				local cosA = ((nx - x) * math.sin(h) + (nz - z) * math.cos(h)) / math.max(dd, 0.01)
				if cosA > -0.2 then
					nd.st.stunUntil = self.now + M.stiffArmStun; nd.st.lunge = nil; a.st.immuneUntil = self.now + 0.3
					self:fb(a, "STIFF-ARM", "good", 1.2); self:fb(nd, "STIFF-ARMED", "bad", 1.0)
				end
			end
		end
		return
	end
	-- defender tackle (QB in the pocket for the rusher once the count is up, otherwise the ball carrier)
	if (not off) and act == "tackle" and self.now >= a.st.tackleCd and self.now >= a.st.recoverUntil and a.st.released then
		local target = self.carrier
		if not target and self.phase == "pocket" and self.ball and self.ball.holder then
			if a.slot ~= 1 or self.now >= (self.rushAt or 0) then target = self.ball.holder end
		end
		if a.st.pedal then self:flip(a, false) end
		local x, z = self:pos(a)
		local h = self:headingOf(a)
		local fx, fz = math.sin(h), math.cos(h)
		local lx, lz = fx, fz
		if target then
			local cx, cz = self:pos(target)
			local dx, dz = cx - x, cz - z
			local dd = math.max(math.sqrt(dx * dx + dz * dz), 0.01)
			local assist = 0.35
			lx, lz = fx * (1 - assist) + dx / dd * assist, fz * (1 - assist) + dz / dd * assist
			local ll = math.max(math.sqrt(lx * lx + lz * lz), 0.01); lx, lz = lx / ll, lz / ll
		end
		a.st.tackleCd = self.now + T.cooldown
		a.st.recoverUntil = self.now + T.lungeTime + T.whiffRecovery
		self:sendTo(a, { kind = "lunge", dir = Vector3.new(lx, 0, lz), speed = T.lungeSpeed * S, time = T.lungeTime, dive = true })
		if target then
			self:attemptTackle(a, target, { x = x, z = z, heading = math.atan2(lx, lz), vx = lx * T.lungeSpeed, vz = lz * T.lungeSpeed })
			if self.state ~= "live" or self.wrap then a.st.recoverUntil = 0 end
		end
	end
end

-------------------------------------------------------------------------------------------------- wiring
local function discover()
	local world = workspace:WaitForChild("AllstarWorld", 30)
	local park = world and world:FindFirstChild("06_FootballPark")
	if not park then warn("[TeamFootball] no football park"); return end
	for _, m in ipairs(park:GetChildren()) do
		local mode = m:IsA("Model") and m:GetAttribute("Mode")
		if mode == "2v2" or mode == "5v5" then
			local n, s, pad = m:FindFirstChild("EndZoneNorth", true), m:FindFirstChild("EndZoneSouth", true), m:FindFirstChild("Pad", true)
			if n and s then
				local id = m:GetAttribute("FieldId") or m.Name
				local f = fieldFrom(id, m:GetAttribute("Label") or id, m, n, s, pad)
				GAMES[id] = G.new(m, mode, f)
			end
		end
	end
	local ids = {}
	for id in pairs(GAMES) do table.insert(ids, id) end
	table.sort(ids)
	print("[TeamFootball] team fields ready: " .. table.concat(ids, ", "))
end

Intent.OnServerEvent:Connect(function(player, d)
	if typeof(d) ~= "table" or typeof(d.action) ~= "string" then return end
	local g = PLAYER_GAME[player]
	if g then g:intent(player, d) end
end)
Players.PlayerRemoving:Connect(function(p) local g = PLAYER_GAME[p]; if g then g:leave(p) end end)
RunService.Heartbeat:Connect(function(dt)
	for _, g in pairs(GAMES) do
		local ok, err = pcall(g.update, g, math.min(dt, 0.1))
		if not ok then warn("[TeamFootball] " .. g.id .. ": " .. tostring(err)); pcall(g.reset, g) end
	end
end)

local hook = folder:FindFirstChild("TestHookTeam") or Instance.new("BindableFunction")
hook.Name = "TestHookTeam"; hook.Parent = folder
hook.OnInvoke = function(cmd, player, arg, arg2, arg3)
	if cmd == "fields" then local t = {}; for id, g in pairs(GAMES) do t[id] = { mode = g.mode, state = g.state } end; return t end

	-- Driving commands, copied from Hoops3Service.TestHook3 so the football test plan can force a state instead of only
	-- watching one (production/qa/football-test-plan.md, hook H1: converts 48 tests from blocked to runnable).
	-- Form: Invoke(cmd, fieldId, ...). "@home1" / "@away3" name an athlete by team and slot.
	-- call(fieldId, "methodName", {args...})          -> runs g:methodName(args...)
	-- set (fieldId, "@home1" | nil, "a.b.c", value)   -> sets a field on an athlete, or on the game when nil
	-- snap(fieldId)                                   -> every scalar on the game, plus athletes and the carrier
	-- call and set can change anything, so they only run inside Studio: a live server never exposes a backdoor.
	if cmd == "call" or cmd == "set" or cmd == "snap" then
		local g = type(player) == "string" and GAMES[player] or nil
		if not g then return nil, "unknown field id " .. tostring(player) end
		if cmd ~= "snap" and not game:GetService("RunService"):IsStudio() then
			return nil, "call/set are Studio-only"
		end
		local function athlete(tag)
			local team, slot = string.match(tag, "^@(%a+)(%d+)$")
			if not team then return nil end
			for _, a in ipairs(g:athletes()) do
				if a.team == team and tostring(a.slot) == slot then return a end
			end
			return nil
		end
		local function resolve(v)
			if type(v) == "string" and v:sub(1, 1) == "@" then return athlete(v) or v end
			if type(v) == "table" then local t = {}; for k, x in pairs(v) do t[k] = resolve(x) end; return t end
			return v
		end
		if cmd == "call" then
			local fn = g[arg]
			if type(fn) ~= "function" then return nil, "no method " .. tostring(arg) end
			local args = resolve(arg2 or {})
			return fn(g, table.unpack(args, 1, #args))
		end
		if cmd == "set" then
			local obj = arg and resolve(arg) or g
			if type(obj) ~= "table" then return nil, "no target " .. tostring(arg) end
			local keys = {}
			for k in string.gmatch(arg2 or "", "[^%.]+") do table.insert(keys, k) end
			if #keys == 0 then return nil, "empty path" end
			for i = 1, #keys - 1 do
				obj = obj[keys[i]]
				if type(obj) ~= "table" then return nil, "path breaks at " .. keys[i] end
			end
			obj[keys[#keys]] = arg3
			return true
		end
		-- snap: read-only, so it also runs on a live server
		local s = {}
		for k, v in pairs(g) do
			local tv = type(v)
			if tv == "number" or tv == "string" or tv == "boolean" then s[k] = v end
		end
		if type(g.score) == "table" then s.score = { home = g.score.home, away = g.score.away } end
		s.carrier = g.carrier and (g.carrier.team .. g.carrier.slot .. ":" .. g.carrier.kind) or nil
		s.events = g.events
		local list = {}
		for _, a in ipairs(g:athletes()) do
			local x, z = g:pos(a)
			table.insert(list, { id = a.team .. a.slot, kind = a.kind, role = g:roleOf(a), x = x, z = z })
		end
		s.athletes = list
		return s
	end
	local g = (type(arg) == "string" and GAMES[arg]) or (player and PLAYER_GAME[player])
	if cmd == "join" then g = GAMES[arg]; if g then g:join(player, arg2 or "home") end; return g ~= nil end
	if not g then return nil end
	if cmd == "intent" then g:intent(player, arg2 or arg); return true end
	if cmd == "state" then
		return { state = g.state, phase = g.phase, offense = g.offense, down = g.down, possession = g.possession, score = g.score,
			los = g.los, toGain = g.toGain, play = g.play and g.plays[g.play].name, events = g.events,
			carrier = g.carrier and (g.carrier.team .. g.carrier.slot .. ":" .. g.carrier.kind) or nil,
			pending = #g.pending, humans = g:humanCount() }
	end
	if cmd == "athletes" then
		local t = {}
		for _, a in ipairs(g:athletes()) do local x, z = g:pos(a); table.insert(t, { id = a.team .. a.slot, kind = a.kind, role = g:roleOf(a), x = math.floor(x * 10) / 10, z = math.floor(z * 10) / 10 }) end
		return t
	end
	return nil
end

discover()

-------------------------------------------------------------------------------------------------- sessions (M07): publish this service's games for Quick Match / Live Games / Watch
local REG = RS:FindFirstChild("AWSessions") or Instance.new("Folder"); REG.Name = "AWSessions"; REG.Parent = RS
local JOIN = SS:FindFirstChild("AWSessionJoin") or Instance.new("Folder"); JOIN.Name = "AWSessionJoin"; JOIN.Parent = SS
local HAS = SS:FindFirstChild("AWSessionHas") or Instance.new("Folder"); HAS.Name = "AWSessionHas"; HAS.Parent = SS
local function sessEntry(id, attrs)
	local c = REG:FindFirstChild(id) or Instance.new("Configuration")
	c.Name = id
	for k, v in pairs(attrs) do c:SetAttribute(k, v) end
	c.Parent = REG
end
local function sessBind(folderX, id, fn)
	local b = folderX:FindFirstChild(id) or Instance.new("BindableFunction")
	b.Name = id; b.OnInvoke = fn; b.Parent = folderX
end
local function sessWatch(cxS, czS, floorS, lenS)   -- studs: a high sideline camera over the playing area
	return Vector3.new(cxS + lenS * 0.62, floorS + lenS * 0.42, czS), Vector3.new(cxS, floorS, czS)
end
local function sessTeleport(player, pos)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then char:PivotTo(CFrame.new(pos + Vector3.new(0, 4, 0))) end
end
sessBind(HAS, "teamfootball", function(player) return PLAYER_GAME[player] ~= nil end)
for id, g in pairs(GAMES) do
	local function teamCounts()
		local n = { home = 0, away = 0 }
		for _, team in ipairs({ "home", "away" }) do for s = 1, g.size do if g.roster[team][s] then n[team] += 1 end end end
		for _, p in ipairs(g.pending) do n[p.team] += 1 end
		return n
	end
	sessBind(JOIN, "tf-" .. id, function(player, team)
		if PLAYER_GAME[player] and PLAYER_GAME[player] ~= g then return false, "You're already in another game" end
		local n = teamCounts()
		team = (team == "home" or team == "away") and team or (n.home <= n.away and "home" or "away")
		local pads = g.model:FindFirstChild("JoinPads")
		local pad = pads and pads:FindFirstChild("Join_" .. (team == "home" and "HOME" or "AWAY"))
		if pad then sessTeleport(player, pad.Position) end
		g:join(player, team)
		return PLAYER_GAME[player] == g, g.field.label .. " · " .. (team == "home" and "HOME" or "AWAY")
	end)
end
task.spawn(function()
	while true do
		for id, g in pairs(GAMES) do
			local f = g.field
			local n = g:humanCount()
			local st = (g.state == "lobby" and (n > 0 and "lobby" or "open")) or (g.state == "countdown" and "countdown") or "playing"
			local pads = g.model:FindFirstChild("JoinPads")
			local pad = pads and pads:FindFirstChild("Join_HOME")
			local wp, wl = sessWatch(f.cx * S, f.cz * S, f.floorY * S, f.halfL * 2 * S)
			sessEntry("tf-" .. id, { Mode = "football" .. g.mode, Sport = "football", Label = f.label .. " · " .. g.mode .. " friends + AI", State = st,
				Humans = n, Capacity = g.size * 2, Score = (g.state ~= "lobby" and g.state ~= "countdown") and ("HOME " .. g.score.home .. " – " .. g.score.away .. " AWAY") or "",
				PadPos = pad and pad.Position or Vector3.new(f.cx * S, f.floorY * S, f.southGoal * S), WatchPos = wp, WatchLook = wl, Order = g.mode == "5v5" and 1 or 5, DropIn = true })
		end
		task.wait(0.5)
	end
end)
