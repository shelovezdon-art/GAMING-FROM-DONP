-- !! TRUNCATED MIRROR — DO NOT TRUST OR RESTORE FROM THIS FILE !!
-- Two mirror runs collided on 2026-11-02 (orchestrator error: a second run was launched while the first was
-- still writing). This file holds only ~34,610 of the live script's 123,205 bytes (~28%). The live Studio
-- script is correct and is the source of truth; this copy is incomplete and ends mid-file.
-- Re-mirror required. Status tracked in docs/handoffs/2026-11-02-mirror-status.md.
-- MIRROR of game.ServerScriptService.TeamFootballService (Script), pulled 2026-11-02 (post wave-3, Gauntlet, DRIP, broadcast UI, stance poses, 2K camera).
-- Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1); this copy is the QA/design record.
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
		["1v1"] = { size = 1, possessionsEach = 4, rushCount = 0 }, -- THE GAUNTLET: runner vs tackler, tackler free at the snap (2026-11-02)
		["2v2"] = { size = 2, possessionsEach = 4, rushCount = 3.0 },
		["5v5"] = { size = 5, possessionsEach = 4, rushCount = 3.2 },
	},
	tryDeclareTime = 8, -- startYard=20, td=7, safety=2, otPossessionsEach=1, maxOtRounds=2 moved to AWFootball.Config (rules/scoring) 2026-11-02
	rushDepth = 6, cushion = 5,
	readyCountdown = 4, lobbyAutoStart = 40, leaveDistance = 45, humanSnapAuto = 15, humanSetToSnap = 4,
	qbPocketSpeed = 7.2, lobHold = 0.35, pressureRadius = 2.6, onRunSpeed = 3.5, onRunPenalty = 0.6,
	blockReach = 1.2, blockDrag = 0.55, blockCooldown = 1.3, engagedScale = 0.4,
	blockDragSprint = 0.8, pancakeSpeed = 8, -- FEATURE WAVE 2 (feel-upgrades #9): a blocker at ≥ 8 m/s at contact pancakes (drag 0.8 vs 0.55)
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

-- AW DRIP hooks (2026-11-02, DRIP STORE v1): cosmetics earn events for DripService. -- was: no cosmetics events
-- The BindableEvent RS.AWFootball.MatchEvents is created by DripService; this service only fires it if present.
-- Cosmetics never feed back into gameplay: these are one-way notifications (cosmetics.md F5).
local function awDripFire(payload)
	local ev = folder:FindFirstChild("MatchEvents")
	if ev then pcall(function() ev:Fire(payload) end) end
end

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
	["1v1"] = { off = { "RB" }, def = { "TACKLER" } }, -- THE GAUNTLET (2026-11-02)
	["2v2"] = { off = { "QB", "WR" }, def = { "RUSH", "CB" } },
	["5v5"] = { off = { "QB", "X", "Z", "SLOT", "RB" }, def = { "RUSH", "CB", "CB", "NICKEL", "LB" } },
}
-- FEATURE WAVE 2 (football-playbook.md §3.4–3.5, 2026-11-02): 15-play 5v5 book + 6-play 2v2 book. Route order is
-- X / Z / SLOT / RB (slots 2..5). The GDD's crossL/crossR mesh pair ships as plain "cross" (mirrored by each
-- player's side) until mirrored route variants exist. Categories/formations/tryOnly stay design-only for now:
-- the service's play shape is unchanged ({ name, routes }) and so is the wire format { action = "play", index }.
-- was: 5 plays per mode — 2v2 SLANT/CURL/POST/FADE/CROSS; 5v5 SPREAD SLANTS { slant,slant,curl,flat },
-- FOUR VERTS { fade,fade,seam,curl }, MESH { cross,slant,curl,flat }, DEEP SHOT { post,curl,seam,wheel },
-- QUICK { curl,curl,slant,flat } (2026-11-02)
local PLAYS = {
	-- FEEDBACK WAVE 3 (owner: "keep it pass and keep it run, so you can have a running back", 2026-11-02):
	-- every play carries cat = "PASS" | "RUN"; a RUN play carries run = the offensive slot that takes the handoff
	-- (1 = QB keeper). The wire format { action = "play", index } is unchanged; cat rides along in G:playBook().
	["1v1"] = { -- THE GAUNTLET: one play — take the ball and survive (2026-11-02)
		{ name = "GAUNTLET", routes = {}, cat = "RUN", run = 1 },
	},
	["2v2"] = {
		{ name = "SLANT", routes = { "slant" }, cat = "PASS" }, { name = "CURL", routes = { "curl" }, cat = "PASS" },
		{ name = "COMEBACK", routes = { "comeback" }, cat = "PASS" }, { name = "POST", routes = { "post" }, cat = "PASS" },
		{ name = "SLUGGO", routes = { "sluggo" }, cat = "PASS" }, { name = "GO", routes = { "fade" }, cat = "PASS" },
		{ name = "DRAW", routes = { "free" }, cat = "RUN", run = 2 },
	},
	["5v5"] = {
		-- QUICK
		{ name = "DOUBLE SLANT", routes = { "slant", "fade", "slant", "flat" }, cat = "PASS" },
		{ name = "CURL FLAT", routes = { "curl", "curl", "seam", "flat" }, cat = "PASS" },
		{ name = "QUICK OUTS", routes = { "out", "out", "slant", "flat" }, cat = "PASS" },
		-- CROSSERS
		{ name = "MESH RAIL", routes = { "cross", "post", "cross", "wheel" }, cat = "PASS" },
		{ name = "SHALLOW DIG", routes = { "dig", "fade", "cross", "flat" }, cat = "PASS" },
		-- VERTS
		{ name = "FOUR VERTS", routes = { "fade", "fade", "seam", "seam" }, cat = "PASS" },
		{ name = "SLUGGO SHOT", routes = { "sluggo", "comeback", "dig", "flat" }, cat = "PASS" },
		{ name = "POST WHEEL", routes = { "curl", "post", "cross", "wheel" }, cat = "PASS" },
		-- MISDIRECTION
		{ name = "SWITCH VERTS", routes = { "post", "dig", "wheel", "flat" }, cat = "PASS" },
		{ name = "JET WHEEL", routes = { "dig", "slant", "wheel", "flat" }, cat = "PASS" },
		-- GOALLINE
		{ name = "GOAL FADE", routes = { "fade", "fade", "out", "flat" }, cat = "PASS" },
		{ name = "UNDER", routes = { "slant", "curl", "slant", "flat" }, cat = "PASS" },
		-- SPECIALS (try plays by design; callable on any down until tryOnly filtering ships)
		{ name = "MONEY OUT", routes = { "slant", "fade", "out", "flat" }, cat = "PASS" },
		{ name = "TEN SHOT", routes = { "dig", "comeback", "seam", "wheel" }, cat = "PASS" },
		{ name = "RAIL SWING", routes = { "comeback", "post", "cross", "wheel" }, cat = "PASS" },
		-- RUN (FEEDBACK WAVE 3): decoy routes pull coverage; non-carriers block once phase == "run" (updateBlocks/aiThink)
		{ name = "INSIDE DRAW", routes = { "fade", "fade", "seam", "free" }, cat = "RUN", run = 5 },
		{ name = "SWEEP RIGHT", routes = { "dig", "slant", "cross", "free" }, cat = "RUN", run = 5 },
		{ name = "SWEEP LEFT", routes = { "slant", "dig", "cross", "free" }, cat = "RUN", run = 5 },
		{ name = "QB KEEP", routes = { "fade", "fade", "out", "wheel" }, cat = "RUN", run = 1 },
	},
}
local function formation(mode, slot, halfW)
	if mode == "1v1" then return 0, -2 end -- the runner lines up alone behind the ball (2026-11-02)
	if mode == "2v2" then
		if slot == 1 then return 0, -4 end
		return math.min(7, halfW - 3), 0
	end
	local wide = halfW - 3
	local spot = ({ { 0, -4.5 }, { -wide, 0 }, { wide, 0 }, { -wide * 0.5, -0.8 }, { 2.4, -4.5 } })[slot]
	return spot[1], spot[2]
end

-- PRE-SNAP WAVE (owner: "them lining up for the ball", 2026-11-02): which offensive slot snaps it. In 5v5 flag somebody
-- has to be over the ball, so the athlete whose FORMATION SPOT is nearest the ball (which sits at lat 0, depth 0 -- the
-- middle of the line of scrimmage) is placed over it in the `snap` pose for the pre-snap only. Slot 1 is excluded: he
-- is the QB and takes the snap.
-- MEASURED, NOT ASSUMED. halfW is in metres and comes from the built EndZoneNorth part (fieldFrom below), so `wide`
-- changes per field and the nearest slot changes with it. Read live 2026-11-02, distance from the ball in metres:
--   Field_5v5      halfW 18.375  wide 15.375 -> slot2/3 15.38, slot4 7.73,  slot5 5.10  => slot 5 (the RB)
--   Field_Yard     halfW 28.000  wide 25.000 -> slot2/3 25.00, slot4 12.53, slot5 5.10  => slot 5 (the RB)
--   Field_Youth2v2 halfW 12.250  wide  9.250 -> slot4 4.69, slot5 5.10                  => slot 4
--   Field_Youth1v1 halfW  8.750  wide  5.750 -> slot4 2.98, slot5 5.10                  => slot 4
-- So on both real 5v5 fields the SLOT receiver is NOT the nearest man -- the RB is. That is why this measures the table
-- every setupDown instead of hardcoding a slot.
local function snapperSlot(mode, size, halfW)
	local best, bd
	for s = 2, size do
		local lat, depth = formation(mode, s, halfW)
		local d = lat * lat + depth * depth
		if not bd or d < bd then best, bd = s, d end
	end
	return best
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
	return { released = false, burst = 1, burstUntil = 0, pedal = false, flipUntil = 0, recoverUntil = 0, dragUntil = 0, biteUntil = 0,
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
			if self.snapper == a then self.snapper = ai end   -- or getSet/snap would hold a parked athlete (PRE-SNAP WAVE)
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
