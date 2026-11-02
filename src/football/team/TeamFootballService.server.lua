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
			plays = self:playNames(), playbook = self:playBook() })
	end
	self.offense = "home"
	self:newPossession(self.mode .. " KICKOFF · " .. self.field.label .. " · HOME ball first")
	self:updateBoard()
end

function G:playNames() local t = {}; for i, p in ipairs(self.plays) do t[i] = p.name end; return t end
-- names + route assignments, for the client play-call dashboard (owner: "show what each player does", 2026-11-02)
function G:playBook() local t = {}; for i, p in ipairs(self.plays) do t[i] = { name = p.name, routes = p.routes, cat = p.cat or "PASS", run = p.run } end; return t end -- cat/run added for the PASS|RUN tabs (FEEDBACK WAVE 3)

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
							northGoal = self.field.northGoal * S, southGoal = self.field.southGoal * S }, plays = self:playNames(), playbook = self:playBook() })
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
	self.pumpUsed = nil; self.aiPumpRolled = nil; self.aiPumpAt = nil; self.breakawayFired = nil -- FEATURE WAVE 2 per-play flags
	self.handoffAt = nil -- FEEDBACK WAVE 3: run-play handoff timer
	local faceDown = dir < 0 and math.pi or 0
	local faceUp = dir < 0 and 0 or math.pi
	local latSign = dir < 0 and 1 or -1      -- offense's right in world x
	local off, def = self.offense, other(self.offense)
	local qb = self.slots[off][1]
	if qb.kind == "ai" then self.play = math.floor(self.rng:next() * #self.plays) + 1 else self.play = (self.humanPlay and self.humanPlay[off]) or 1 end
	-- the man over the ball. Only in the 5-man formation: in 1v1 / 2v2 the offense is the QB plus at most one receiver,
	-- and putting the lone receiver on the ball would be worse presentation than leaving it alone.
	local snapS = (self.size >= 5) and snapperSlot(self.mode, self.size, f.halfW) or nil
	self.snapper = nil
	for s = 1, self.size do
		local a = self.slots[off][s]
		a.st = newPlayState()
		local lat, depth = formation(self.mode, s, f.halfW)
		local x, z = f.cx + lat * latSign, self.los + dir * depth
		-- PRESENTATION ONLY: the snapper is placed over the ball instead of on his formation spot, but a.spot below
		-- stays the FORMATION spot, so his route (assignRoutes reads a.spot), his side, and every gameplay value are
		-- untouched -- at the snap he simply releases off the ball into the route he was always running.
		if s == snapS then self:place(a, f.cx, self.los, faceDown); self.snapper = a else self:place(a, x, z, faceDown) end
		a.spot = { x = x, z = z }
		a.side = (x - f.cx) >= 0 and 1 or -1
		if math.abs(x - f.cx) < 0.5 then a.side = latSign end
		-- was: setPose(a.model, s == 1 and "qbSet" or nil) -- nobody was over the ball, so nothing read as a snap
		setPose(a.model, s == 1 and "qbSet" or (s == snapS and "snap" or nil))
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
	-- was: self.ball = { holder = qb, air = false } -- the ball floated in the QB's hand pre-snap and the snap was invisible.
	-- Now it is SPOTTED on the ground at the middle of the line of scrimmage until G:snap hands it to him.
	self.ball = { spotted = true, air = false, at = { x = f.cx, z = self.los } }
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
		-- FEATURE WAVE 2 (feel-upgrades §3.3.2): double-move routes register their fake-break point in world space
		local R = ROUTES[a.route]
		if R and R.doubleMove then
			local p = R.pts[R.fakeBreakIdx or math.max(#R.pts - 1, 1)]
			local bx = a.spot.x - a.side * p[1]
			a.st.fakeBreak = { x = bx, z = a.spot.z + self.dir * p[2], dirx = (bx - a.spot.x) >= 0 and 1 or -1 }
		else a.st.fakeBreak = nil end
	end
end

function G:getSet()
	self.pre = "set"; self.setAt = self.now
	local qb = self:qb()
	if qb.kind == "ai" then self.snapTimer = self.rng:range(CFG.stance.cadenceMin, CFG.stance.cadenceMax)
	else self.snapTimer = TC.humanSetToSnap end
	-- was: every slot 2..size went to wrStance -- which wiped the snapper's `snap` pose at SET and stood him up again
	for s = 2, self.size do
		local a = self.slots[self.offense][s]
		if a ~= self.snapper then setPose(a.model, "wrStance") end
	end
	self:msg("SET…", 3)
end

function G:snap()
	self.clockStarted = true; self.clockStopped = false -- the game clock runs from the first snap, restarts on every snap
	self.state = "live"; self.phase = "pocket"; self.playClock = 0
	self.snapAt = self.now
	self.rushAt = self.now + TC.modes[self.mode].rushCount
	-- FEEDBACK WAVE 3: on a RUN play, queue the handoff (QB keeper tucks it almost immediately)
	local runSlot = self.plays[self.play].run
	self.handoffAt = runSlot and (self.now + (runSlot == 1 and 0.1 or 0.45)) or nil
	local K = CFG.stance
	for _, a in ipairs(self:athletes()) do
		local isQB = a.team == self.offense and a.slot == 1
		local isRush = a.team ~= self.offense and a.slot == 1
		if isQB or isRush then
			a.st.released = true
			-- was: setPose(a.model, nil, 0.15) -- the QB was left with no pose at all, so the ball hung off one hand
			if isQB then setPose(a.model, "qbCarry", 0.15) end
		elseif a.kind == "ai" then
			a.st.reactAt = self.now + self.rng:range(K.cpuReactMin, K.cpuReactMax)
		end
		if a.st.jumped then a.st.frozenUntil = self.now + K.earlyFreeze end
	end
	-- THE SNAP: the ball leaves the ground and goes into the QB's hands. This transition IS the snap -- before this wave
	-- it already sat in his hand from setupDown, so there was nothing to see.
	local qb = self:qb()
	self.ball = { holder = qb, air = false }
	self:sendBall()
	-- the snapper releases off the ball into his route / block, exactly as he did before
	if self.snapper and self.snapper.model and self.snapper.model.Parent then setPose(self.snapper.model, nil, 0.15) end
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
	-- was: setPose(a.model, nil, 0.12) -- THE DB-STANCE HOLE. From the hip flip onward a covering defender had NO pose
	-- at all and ran the stock animation, which is the "standing around" the owner saw. Give him a ready stance; it
	-- fades out on its own as he opens up and runs (AWMotion.STANCE_FADE["football:cover"]).
	setPose(a.model, "cover", 0.12)
	a.st.coverPose = true
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
	if n < (st.biteUntil or 0) then m *= (CFG.defend.biteSlowMult or 0.8) end -- bit on a fake (feel-upgrades §3.3.2)
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
		if self.now < (self.rushAt or 0) then return a.kind == "ai" and 4 or 0 end -- was 0 for both: the AI rusher now roams the line pre-count (FEEDBACK WAVE 3); humans stay held until the count
		return a.kind == "ai" and M.cpuDbSpeed or M.dbSpeed
	end
	if not a.st.released then return 0 end
	if a.st.pedal then return CFG.pedal.speed end
	return a.kind == "ai" and M.cpuDbSpeed or M.dbSpeed
end

-- Ankle-breaker (owner: "jukes should give some type of space", 2026-11-02): when the carrier jukes or spins,
-- any defender inside jukeBreakRadius who was CLOSING at >= jukeBreakClosingMps bites the move and freezes —
-- that freeze plus the juke burst is the separation. A defender sitting in position never bites: patience beats
-- juke-spam. Same rule for AI carriers breaking human defenders. Both sides hear why.
function G:ankleBreak(a, freezeS)
	local M = CFG.move
	if not freezeS or freezeS <= 0 then return end
	local x, z = self:pos(a)
	local sentBadge = false -- one ANKLE BREAKER badge per move, however many defenders bit (FEEDBACK WAVE 3)
	for _, d in ipairs(self:defenders()) do
		local dx, dz = self:pos(d)
		if dist2(x, z, dx, dz) <= (M.jukeBreakRadius or 0) then
			local vx, vz = self:vel(d)
			local toX, toZ = x - dx, z - dz
			local l = math.max(math.sqrt(toX * toX + toZ * toZ), 0.01)
			if (vx * toX + vz * toZ) / l >= (M.jukeBreakClosingMps or 2) then
				d.st.frozenUntil = math.max(d.st.frozenUntil or 0, self.now + freezeS)
				d.st.lunge = nil
				-- FEEDBACK WAVE 3: the bitten defender buckles (AWMotion football:collapse) for the freeze, then clears
				setPose(d.model, "collapse", 0.08)
				task.delay(freezeS, function() if d.model and d.model.Parent then setPose(d.model, nil, 0.2) end end)
				self:fb(d, "ANKLES · HE CUT BACK", "bad", 1.1, "bit on the move and froze")
				self:fb(a, "BROKE HIM OFF", "good", 1.0)
				if not sentBadge then
					sentBadge = true; self:sendTo(a, { kind = "badge", text = "ANKLE BREAKER", tone = "gold" })
					if a.kind == "human" then awDripFire({ ev = "ankleBreaker", player = a.player }) end -- AW DRIP (2026-11-02)
				end
				self:log("ANKLE_BREAK", { by = a.team .. a.slot, on = d.team .. d.slot })
			end
		end
	end
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
function G:coverOf(r) for _, d in ipairs(self:defenders()) do if d.man == r then return d end end return nil end

-- FEATURE WAVE 2 (feel-upgrades §3.3.2): the bite cost — beaten stumble + ×biteSlowMult for biteSlowS.
-- biteUntil is its own field (not dragUntil/recoverUntil) because breakWrap zeroes dragUntil and tackles own
-- recoverUntil: reusing either would let an unrelated event erase or inflate the price.
function G:biteCost(d, text)
	if d.st.pedal then self:flip(d, true)
	else d.st.flipUntil = math.max(d.st.flipUntil or 0, self.now + CFG.pedal.beatenStumble) end
	d.st.biteUntil = self.now + (CFG.defend.biteSlowS or 1.0)
	self:fb(d, text, "bad", 1.4, "committed to the fake")
end

-- FEATURE WAVE 2 (feel-upgrades §3.3.2): double-move bite detection. When a receiver on a doubleMove route
-- passes his fake-break point going vertical, a DB moving laterally the fake way within cushion range inside a
-- 0.6 s window is "beaten by bite". Geometric, so it works identically for human and AI on both sides.
function G:updateDoubleMoves()
	if not (self.phase == "pocket" or self.phase == "flight") then return end
	for _, a in ipairs(self:receivers()) do
		local st = a.st
		if st.fakeBreak and not st.biteDone then
			local x, z = self:pos(a)
			if (z - st.fakeBreak.z) * self.dir > 0.3 then
				st.biteWindowUntil = st.biteWindowUntil or (self.now + 0.6)
				if self.now > st.biteWindowUntil then st.biteDone = true
				else
					local d = self:coverOf(a)
					if d then
						local dvx = (self:vel(d))
						local dx, dz = self:pos(d)
						if dvx * st.fakeBreak.dirx >= 2 and dist2(x, z, dx, dz) <= TC.cushion + 2 then
							st.biteDone = true
							self:biteCost(d, "BIT ON THE SLANT · SLUGGO!")
							self:fb(a, "YOU SOLD IT — HE BIT", "good", 1.2)
							local qb = self:qb()
							if qb and qb ~= a then self:fb(qb, "HE BIT — THROW IT DEEP", "good", 1.2, "double move won") end
							self:log("BITE", { db = d.team .. d.slot, on = a.team .. a.slot, route = a.route })
						end
					end
				end
			end
		end
	end
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
	self:updateDoubleMoves() -- FEATURE WAVE 2: sluggo bite detection (guards its own phases)
	-- FEEDBACK WAVE 3 (owner: "keep it pass and keep it run"): run plays — the QB hands off once the timer is up.
	-- passCaught stays nil, so Rules.resolveTry still reads this play as a "run" on a try (a 1-pt try run scores 0).
	if self.handoffAt and self.phase == "pocket" and self.now >= self.handoffAt then
		self.handoffAt = nil
		local qb = self:qb()
		local slot = self.plays[self.play].run
		local back = slot and self.slots[self.offense][slot]
		if back and self.ball and self.ball.holder == qb and not self.ball.air then
			self.carrier = back; self.phase = "run"
			-- the two-hand pocket cradle ends at the handoff: he is a runner (keeper) or empty-handed (handoff) now
			setPose(qb.model, nil, 0.15)
			if back ~= qb then
				self.ball = { holder = back, air = false }
				if back.kind == "ai" then back.faceHeading = nil end
			end
			self:msg(back == qb and "QB KEEPER!" or "HANDOFF!", 1.0)
			self:fb(back, (back == qb and "KEEP IT" or "YOUR BALL") .. " · Q/E juke · C spin · R stiff-arm", "warn", 1.2)
			self:sendBall()
			self:log("HANDOFF", { to = self.offense .. tostring(slot), keeper = back == qb or nil })
		end
	end
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
