--[[ ALLSTAR WORLD · Practice Field ("Ball Lab") · Stage 3: a defender, tackling, and contested catches.

   Install: ServerScriptService/TackleService (Script), Disabled = true until reviewed.
   Needs:   ReplicatedStorage/AWPractice/{Config, BallState, Carry, Receive, Tackle, Contest}
            (Tackle and Contest are the two new modules in this folder; Config needs the two blocks from
             config-additions.lua)

   WHO OWNS WHAT
     PracticeService still owns the ball: its state, its revision, who holds it and every change to it.
     This script owns everything about CONTACT: tackle geometry, the counter matrix, broken tackles, per-play
     fatigue, fumbles, and the jump-ball contest. It never moves the ball itself and never edits PracticeService.
     Clients send intentions only (wrap / dive / juke / spin / stiffarm / contestJump), each one quoting the ball
     revision and the player's own clock reading. Every outcome is decided here and sent back with a reason.

   ---------------------------------------------------------------------------------------------------------------
   THE SEAM  (the one thing this script cannot do for itself)
   ---------------------------------------------------------------------------------------------------------------
   Changing ball possession is PracticeService's job, and it exposes no server-side way to ask for it. So this
   script looks for ONE optional BindableFunction and degrades gracefully when it is absent:

       ServerStorage.AWPracticeBall:Invoke(cmd, arg)
         ("down",   cause: string)                               -> whistle: HELD -> DEAD, cause shown to players
         ("fumble", { pos: Vector3, vel: Vector3, cause: string }) -> HELD -> LOOSE at pos with vel (studs)
         ("award",  { model: Model, cause: string })             -> HELD/IN_FLIGHT -> HELD by that body

   Adding it to PracticeService is twelve lines and touches none of its logic (it only calls functions that are
   already there). Paste at the end of PracticeService, next to the existing AWPracticeTest hook:

       local seam = SS:FindFirstChild("AWPracticeBall") or Instance.new("BindableFunction")
       seam.Name = "AWPracticeBall"; seam.Parent = SS
       seam.OnInvoke = function(cmd, arg)
           if cmd == "down" then goDead(tostring(arg)); return true
           elseif cmd == "fumble" then
               if ball.state ~= "HELD" then return false end
               ball.pos, ball.vel = arg.pos, arg.vel
               return setState("LOOSE", arg.cause or "FUMBLE")
           elseif cmd == "award" then
               local a = byModel[arg.model]
               if not a then return false end
               return giveTo(a, arg.cause or "CONTEST")
           end
           return nil
       end

   WITHOUT the seam this script still runs and is still useful: it decides and reports every tackle, applies every
   penalty it owns (the tackler's recovery, the carrier's drag and stumble, the stiff-arm stun, fatigue), and shows
   both players the reason. What it cannot do is blow the whistle, so the carrier simply stays up and the toast says
   so. One warning is printed, once. For a FUMBLE there is a zero-seam fallback: the carrier's own `drop` intent is
   replayed through PracticeService's existing AWPracticeTest hook, which is a legal HELD -> LOOSE transition.

   ---------------------------------------------------------------------------------------------------------------
   WHAT IT READS, WITHOUT A SEAM
   ---------------------------------------------------------------------------------------------------------------
     * ball state / revision:   ServerStorage.AWPracticeTest:Invoke("ball")   (already present, read-only)
     * why the ball changed:    ServerStorage.AWPracticeTest:Invoke("log")    (read-only; used only to learn that a
                                catch is still being secured, so a hit then is an incompletion, not a tackle)
     * who is carrying it:      geometrically. A held ball sits exactly on Carry.cframe(holder), so the body whose
                                hand frame matches the ball part is the carrier. No name matching, no guessing.
     * how fast a body is:      this script's own position history, same method as PracticeService's bodyVel.
     * how far a body reaches:  Receive.rig(model) — the real shoulder, upper arm, forearm and hand of that avatar.
     * movement plausibility:   Config.validate.speedSlack, read-only. PracticeService owns pulling people back;
                                this script only refuses a contact intent from a body that was moving impossibly.

   Remote contract  (ReplicatedStorage.AWPractice.Remotes — its own events, so it never competes with
                     PracticeService's Intent rate limiter)
     TackleIntent  client -> server  (action: string, data: { rev, at, dir? })
     TackleState   server -> client  { kind = "tackle",  ... }   an outcome, with its reason
                                     { kind = "contest", ... }   a jump ball, with every component score
                                     { kind = "role",    role }  you are now offence / defence
                                     { kind = "fb",      text, tone }
                                     { kind = "cd",      wrap, dive, juke, spin, stiff }  cooldown readiness 0..1
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local PKG = RS:WaitForChild("AWPractice", 30)
if not PKG then warn("[Tackle] AWPractice missing — Stage 3 not loaded"); return end

local CFG = require(PKG:WaitForChild("Config"))
local Carry = require(PKG:WaitForChild("Carry"))
local Receive = require(PKG:WaitForChild("Receive"))
local Tackle = require(PKG:WaitForChild("Tackle"))
local Contest = require(PKG:WaitForChild("Contest"))

if not (CFG.tackle and CFG.contest) then
	warn("[Tackle] Config has no `tackle` / `contest` block — apply config-additions.lua first. Stage 3 not loaded.")
	return
end

local S = CFG.S
local F, V, T, C = CFG.field, CFG.validate, CFG.tackle, CFG.contest
local YD = CFG.YARD * S
local SPRINT = CFG.move.sprint

-------------------------------------------------------------------------------------------------- field geometry (studs)
local G = {}
G.halfW = F.widthM / 2 * S
G.halfL = (F.playYards + F.endZoneYards) * YD / 2
G.north, G.south = F.cz - G.halfL, F.cz + G.halfL
G.floor = F.floorY
local function inZone(pos, marginM)
	local m = marginM * S
	return math.abs(pos.X - F.cx) <= G.halfW + m and pos.Z >= G.north - m and pos.Z <= G.south + m
end

-------------------------------------------------------------------------------------------------- remotes
local remotes = PKG:FindFirstChild("Remotes") or Instance.new("Folder")
remotes.Name = "Remotes"; remotes.Parent = PKG
local function remote(name)
	local r = remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
	r.Name = name; r.Parent = remotes
	return r
end
local Intent, State = remote("TackleIntent"), remote("TackleState")

-------------------------------------------------------------------------------------------------- the seam
local seam = SS:FindFirstChild("AWPracticeBall")
local testHook = SS:FindFirstChild("AWPracticeTest")
local warnedNoSeam = false
local function seamCall(cmd, arg)
	if seam and seam:IsA("BindableFunction") then
		local ok, res = pcall(function() return seam:Invoke(cmd, arg) end)
		if ok then return true, res end
		warn("[Tackle] seam " .. cmd .. " failed: " .. tostring(res))
	end
	if not warnedNoSeam then
		warnedNoSeam = true
		warn("[Tackle] ServerStorage.AWPracticeBall is not installed: outcomes are reported but the ball is left alone. " ..
			"See the seam note at the top of TackleService.")
	end
	return false, nil
end
local function hookCall(cmd, arg)
	if not (testHook and testHook:IsA("BindableFunction")) then return nil end
	local ok, res = pcall(function() return testHook:Invoke(cmd, arg) end)
	return ok and res or nil
end

-------------------------------------------------------------------------------------------------- the ball, read-only
local ballPart                                   -- found lazily: PracticeService builds it under the field's Runtime
local function findBallPart()
	if ballPart and ballPart.Parent then return ballPart end
	local world = workspace:FindFirstChild("AllstarWorld")
	local field = world and world:FindFirstChild("19_PracticeField")
	local rt = field and field:FindFirstChild("Runtime")
	ballPart = rt and rt:FindFirstChild("PracticeBall") or nil
	return ballPart
end

local ball = { state = "TEE", rev = -1, pos = Vector3.zero }
local function readBall()
	local b = hookCall("ball")
	local p = findBallPart()
	if p then ball.pos = p.Position end
	if typeof(b) == "table" then
		ball.state = tostring(b.state or "TEE")
		ball.rev = tonumber(b.rev) or ball.rev
		ball.holderName = b.holder
	end
	return ball
end

-------------------------------------------------------------------------------------------------- bodies
local bodies = {}      -- [Model] = body
local byPlayer = {}    -- [Player] = body

local function makeBody(model, player)
	local b = {
		model = model, player = player,
		name = player and player.DisplayName or model.Name,
		role = "offense",
		hist = {},
		bucket = CFG.net.maxIntentsPerSecond, bucketAt = os.clock(),
		nextWrap = 0, nextDive = 0, nextJuke = 0, nextSpin = 0, nextStiff = 0,
		recoverUntil = 0, groundedUntil = 0, stunUntil = 0,
		pending = nil, carry = nil, jumpAt = nil,
	}
	bodies[model] = b
	if player then byPlayer[player] = b end
	return b
end
local function forget(model)
	local b = bodies[model]
	if not b then return end
	if b.player then byPlayer[b.player] = nil end
	bodies[model] = nil
end

local function root(b) return b and b.model and b.model:FindFirstChild("HumanoidRootPart") end
local function rigOf(b)
	if not (b.rig and b.rig.model == b.model and b.rig.ut and b.rig.ut.Parent) then b.rig = Receive.rig(b.model) end
	return b.rig
end
-- metres, shoulder to palm, from this avatar's own joints. Falls back to a stock R15 arm if the rig is not readable.
local function armReachM(b)
	local r = rigOf(b)
	if not r then return 0.72 end
	local a = r.arms[1] or r.arms[-1]
	return a and (a.reach / S) or 0.72
end
-- metres: how high this avatar's fingertips are with both feet on the grass
local function standReachM(b)
	local r = rigOf(b)
	local rp = root(b)
	if not (r and rp) then return 2.1 end
	local body = Receive.body(r)
	local shoulderY = (body.sh[1] or body.sh[-1]).Y
	return ((shoulderY - G.floor) + (r.arms[1] or r.arms[-1]).reach) / S
end

-- position history, so every decision is made against where a body really was at the moment of the intent
local function trackBodies()
	local now = workspace:GetServerTimeNow()
	for model, b in pairs(bodies) do
		if not model.Parent then forget(model) else
			local rp = root(b)
			if rp then
				table.insert(b.hist, { t = now, p = rp.Position, look = rp.CFrame.LookVector })
				while #b.hist > 2 and now - b.hist[1].t > 0.4 do table.remove(b.hist, 1) end
			end
		end
	end
end
local function at(b, t)                      -- position + facing as the server saw them at time t
	local h = b.hist
	if not h or #h == 0 then
		local rp = root(b)
		return rp and rp.Position or Vector3.zero, rp and rp.CFrame.LookVector or Vector3.new(0, 0, -1)
	end
	local prev = h[1]
	for i = 1, #h do
		if h[i].t >= t then
			local cur = h[i]
			if i == 1 then return cur.p, cur.look end
			local span = cur.t - prev.t
			local f = span > 1e-5 and math.clamp((t - prev.t) / span, 0, 1) or 0
			return prev.p:Lerp(cur.p, f), prev.look:Lerp(cur.look, f)
		end
		prev = h[i]
	end
	return h[#h].p, h[#h].look
end
local function vel(b)                         -- m/s, flat
	local h = b.hist
	if not h or #h < 2 then return 0, 0, 0 end
	local last, first = h[#h], h[1]
	for i = #h - 1, 1, -1 do if last.t - h[i].t >= 0.1 then first = h[i]; break end end
	local dt = last.t - first.t
	if dt <= 0 then return 0, 0, 0 end
	local d = (last.p - first.p) / dt / S
	return d.X, d.Z, math.sqrt(d.X * d.X + d.Z * d.Z)
end

-------------------------------------------------------------------------------------------------- joining / leaving
local function hook(player, char)
	forget(char)
	local b = makeBody(char, player)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then hum.Died:Connect(function() forget(char) end) end
	char.AncestryChanged:Connect(function(_, parent) if parent == nil then forget(char) end end)
	State:FireClient(player, { kind = "role", role = b.role })
end
local function watch(player)
	player.CharacterAdded:Connect(function(char) task.spawn(hook, player, char) end)
	if player.Character then task.spawn(hook, player, player.Character) end
end
Players.PlayerAdded:Connect(watch)
for _, p in ipairs(Players:GetPlayers()) do watch(p) end
Players.PlayerRemoving:Connect(function(p)
	local b = byPlayer[p]
	if b then forget(b.model) end
end)

-- PracticeService's partner and its scripted test dummies are bodies too, so they can be tackled and can contest.
local function adoptLocals()
	local world = workspace:FindFirstChild("AllstarWorld")
	local field = world and world:FindFirstChild("19_PracticeField")
	local rt = field and field:FindFirstChild("Runtime")
	if not rt then return end
	for _, m in ipairs(rt:GetChildren()) do
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") and not bodies[m] then
			local b = makeBody(m, nil)
			b.local_ = true
			-- PracticeService names its scripted defender dummies, so honour that without needing a seam
			if m.Name:match("^TestDummy_") and m:GetAttribute("AWRole") == "defense" then b.role = "defense" end
		end
	end
end

-------------------------------------------------------------------------------------------------- the carrier
-- A held ball sits exactly where Carry.cframe puts it, so whichever body's hand frame matches the ball part is the
-- carrier. Geometric, not name-based, so two players with the same display name cannot confuse it.
local carrier, carryRev = nil, -1
local function findCarrier()
	if ball.state ~= "HELD" then return nil end
	local p = findBallPart()
	if not p then return nil end
	local best, bestD
	for _, b in pairs(bodies) do
		local cf = Carry.cframe(b.model)
		if cf then
			local d = (cf.Position - p.Position).Magnitude
			if not bestD or d < bestD then best, bestD = b, d end
		end
	end
	if best and bestD <= 0.35 then return best end
	return nil
end

-- A catch that has not been pulled in yet: a hit now is an incompletion, not a tackle. PracticeService knows this
-- privately, but it already writes the reason into its own read-only log, so we can learn it without a seam.
local function securingUntilFor()
	local lg = hookCall("log")
	if typeof(lg) ~= "table" then return 0 end
	local intent
	for i = #lg, math.max(1, #lg - 24), -1 do
		local e = lg[i]
		if typeof(e) == "table" and e.kind == "CATCH_TRY" and e.caught then intent = e.intent; break end
	end
	local I = Receive.INTENTS[intent or "secure"] or Receive.INTENTS.secure
	return I.secure
end

local function newCarry(b)
	local secure = securingUntilFor()
	b.carry = { playId = ball.rev, broken = 0, startedAt = os.clock(), securingUntil = os.clock() + secure,
		spinUntil = 0, jukeUntil = 0, jukeRecoveryUntil = 0, stiffAt = nil, stumbleUntil = 0, lastHitAt = 0 }
end

local function carrierState(b)
	local c = b.carry or {}
	local now = os.clock()
	local function left(t) return math.max(0, (t or 0) - now) end
	return {
		speed = select(3, vel(b)),
		broken = c.broken or 0,
		spinUntil = left(c.spinUntil),
		jukeUntil = left(c.jukeUntil),
		jukeRecoveryUntil = left(c.jukeRecoveryUntil),
		securingUntil = left(c.securingUntil),
		stumbleUntil = left(c.stumbleUntil),
		stiffAge = c.stiffAt and (now - c.stiffAt) or nil,
	}
end

-------------------------------------------------------------------------------------------------- messages
local function fb(b, text, tone)
	if b and b.player then State:FireClient(b.player, { kind = "fb", text = text, tone = tone or "warn" }) end
end
local stats = { attempts = 0, tackles = 0, wraps = 0, whiffs = 0, broken = 0, stumbles = 0, fumbles = 0,
	incomplete = 0, contests = 0, rateLimited = 0, stale = 0, implausible = 0, noSeam = 0, results = {}, contestLog = {} }
local function record(list, entry, cap)
	table.insert(list, entry)
	while #list > (cap or 200) do table.remove(list, 1) end
end

-------------------------------------------------------------------------------------------------- applying an outcome
local function announce(msg)
	State:FireAllClients(msg)
end

local function endPlay(cause, by)
	stats.tackles += 1
	local ok = seamCall("down", cause)
	if not ok then stats.noSeam += 1 end
	if carrier then carrier.carry = nil end
end

local function fumbleBall(b, cause)
	stats.fumbles += 1
	local rp = root(b)
	local cf = Carry.cframe(b.model)
	local pos = (cf and cf.Position) or (rp and rp.Position) or ball.pos
	local vx, vz = vel(b)
	-- the ball squirts forward off the hit, keeping a share of his run: the same shape as Config.ball.dropInherit
	local v = Vector3.new(vx, 0, vz) * CFG.ball.dropInherit * S + Vector3.new(0, CFG.ball.dropUp * S, 0)
	local ok = seamCall("fumble", { pos = pos, vel = v, cause = cause })
	if not ok and b.player then
		-- zero-seam fallback: replay the carrier's own legal `drop` through PracticeService's existing hook
		ok = hookCall("intent", { player = b.player, action = "drop", data = { rev = ball.rev } }) and true or false
	end
	if not ok then stats.noSeam += 1 end
	if carrier then carrier.carry = nil end
end

local function applyResult(tackler, target, kind, res, geo)
	local now = os.clock()
	local out = res.outcome

	-- the tackler's commitment cost, whatever happened
	local pen = Tackle.missPenalty(kind, out, T)
	if out == Tackle.WHIFF or out == Tackle.BROKEN then
		tackler.recoverUntil = now + pen.recover
		tackler.groundedUntil = now + pen.grounded
	elseif out == Tackle.NO_CONTACT then
		tackler.recoverUntil = math.max(tackler.recoverUntil, now + (kind == Tackle.DIVE and T.diveMiss or 0))
		tackler.groundedUntil = math.max(tackler.groundedUntil, now + (kind == Tackle.DIVE and T.grounded or 0))
	end
	if res.stunTackler then tackler.stunUntil = now + res.stunTackler end

	-- the carrier's cost
	local c = target.carry
	if c then
		if res.carrierStumble and res.carrierStumble > 0 then c.stumbleUntil = now + res.carrierStumble end
		if out == Tackle.BROKEN then c.broken = Tackle.fatigueAfter(c.broken) end
		c.lastHitAt = now
	end

	local msg = {
		kind = "tackle", outcome = out, reason = res.reason, tackleKind = kind,
		tackler = tackler.model, target = target.model,
		score = res.score and math.floor(res.score * 1000) / 1000 or nil,
		decidedBy = res.decidedBy,
		d = math.floor(geo.d * 100) / 100, closing = math.floor(geo.closing * 10) / 10,
		alphaCos = math.floor(geo.alphaCos * 100) / 100,
		recover = pen.recover, grounded = (out == Tackle.WHIFF or out == Tackle.BROKEN) and pen.grounded or 0,
		drag = res.drag, dragMul = T.wrapDragMul, breakWindow = res.breakWindow,
		stumble = res.carrierStumble, stun = res.stunTackler,
		broken = c and c.broken or 0,
	}
	announce(msg)
	record(stats.results, { who = tackler.name, on = target.name, kind = kind, outcome = out, reason = res.reason,
		score = msg.score, decidedBy = res.decidedBy, d = msg.d, closing = msg.closing, broken = msg.broken }, 300)

	if out == Tackle.WHIFF then
		stats.whiffs += 1
		fb(tackler, res.reason, "bad"); fb(target, "HE MISSED", "good")
	elseif out == Tackle.NO_CONTACT then
		fb(tackler, res.reason, "warn")
	elseif out == Tackle.BROKEN then
		stats.broken += 1
		fb(tackler, "BROKEN TACKLE · " .. res.reason, "bad"); fb(target, res.reason, "good")
	elseif out == Tackle.STUMBLE then
		stats.stumbles += 1
		fb(tackler, "KNOCKED HIM OFF BALANCE", "warn"); fb(target, res.reason, "warn")
	elseif out == Tackle.WRAPPED then
		stats.wraps += 1
		fb(tackler, "WRAPPED UP · HOLD ON", "good")
		fb(target, "WRAPPED · SPIN OR STIFF-ARM TO BREAK IT", "warn")
		-- he has breakWindow to answer; if he does not, the wrap brings him down at wrapDrag
		local playId = c and c.playId
		tackler.wrap = { target = target, at = now, endsAt = now + T.wrapDrag, breakUntil = now + T.breakWindow,
			score = res.score or 0, playId = playId }
		if c then c.wrappedBy = tackler end
	elseif out == Tackle.TACKLED then
		fb(tackler, res.reason, "good"); fb(target, "BROUGHT DOWN · " .. res.reason, "bad")
		endPlay("TACKLED · " .. res.reason, tackler)
	elseif out == Tackle.FUMBLE then
		fb(tackler, res.reason, "good"); fb(target, res.reason, "bad")
		fumbleBall(target, "FUMBLE · " .. res.reason)
	elseif out == Tackle.INCOMPLETE then
		stats.incomplete += 1
		fb(tackler, "BROKE IT UP · INCOMPLETE", "good"); fb(target, res.reason, "bad")
		local ok = seamCall("down", "INCOMPLETE · " .. res.reason)
		if not ok then stats.noSeam += 1 end
		if target.carry then target.carry = nil end
	end
end

-------------------------------------------------------------------------------------------------- one contact check
local function contactGeometry(tackler, target, t)
	local tp, look = at(tackler, t)
	local cp = at(target, t)
	local tvx, tvz = vel(tackler)
	local cvx, cvz = vel(target)
	local l = Vector3.new(look.X, 0, look.Z)
	l = (l.Magnitude > 1e-4) and l.Unit or Vector3.new(0, 0, -1)
	return Tackle.geometry({
		dx = (cp.X - tp.X) / S, dz = (cp.Z - tp.Z) / S,
		fx = l.X, fz = l.Z,
		tvx = tvx, tvz = tvz, cvx = cvx, cvz = cvz,
	})
end

local function tryContact(tackler, kind, startedAt)
	local target = carrier
	if not (target and target.carry) then return nil end
	if target == tackler then return nil end
	local geo = contactGeometry(tackler, target, workspace:GetServerTimeNow())
	local res = Tackle.resolve({
		kind = kind, geo = geo, reach = Tackle.reach(armReachM(tackler), kind, T),
		live = true, age = os.clock() - startedAt, carrier = carrierState(target), sprint = SPRINT,
	}, T)
	return res, geo, target
end

-------------------------------------------------------------------------------------------------- intents
local function takeToken(b)
	local now = os.clock()
	local rate = CFG.net.maxIntentsPerSecond
	b.bucket = math.min(rate, b.bucket + (now - b.bucketAt) * rate)
	b.bucketAt = now
	if b.bucket < 1 then return false end
	b.bucket -= 1
	return true
end

-- a client's own clock reading, believed only as far back as its connection allows (same rule as PracticeService)
local function clientTime(b, v)
	local now = workspace:GetServerTimeNow()
	local ping = 0
	if b.player then pcall(function() ping = b.player:GetNetworkPing() end) end
	local grace = math.min(CFG.pass.catch.lagMax, ping * 2 + 0.05)
	return math.clamp(tonumber(v) or now, now - grace, now)
end

-- read-only plausibility gate. PracticeService owns pulling people back; we just refuse contact from a body that
-- was moving faster than the limit, so a speed exploit cannot buy a tackle.
local function plausible(b)
	local _, _, sp = vel(b)
	if sp > SPRINT * V.speedSlack + 0.5 then
		stats.implausible += 1
		fb(b, "MOVEMENT CHECK · NOT WHILE YOU'RE MOVING LIKE THAT", "bad")
		return false
	end
	return true
end

local function busy(b)
	local now = os.clock()
	if now < b.groundedUntil then return "YOU'RE ON THE FLOOR" end
	if now < b.stunUntil then return "STILL SHAKING IT OFF" end
	if now < b.recoverUntil then return "GETTING YOUR FEET BACK" end
	return nil
end

local function startTackle(b, kind, data)
	if b.role ~= "defense" then fb(b, "YOU'RE ON OFFENCE · PRESS ROLE TO SWITCH", "warn"); return end
	local why = busy(b)
	if why then fb(b, why, "warn"); return end
	local nextAt = (kind == Tackle.DIVE) and b.nextDive or b.nextWrap
	if os.clock() < nextAt then fb(b, "NOT YET", "warn"); return end
	if not (carrier and carrier.carry) then fb(b, "NOBODY'S CARRYING IT", "warn"); return end
	if carrier == b then return end
	if not plausible(b) then return end
	stats.attempts += 1
	b.nextWrap = os.clock() + T.cooldown
	b.nextDive = b.nextWrap
	local startedAt = os.clock()
	-- a wrap resolves once its arms are closed; a dive stays open for its whole lunge and resolves on first contact
	b.pending = { kind = kind, startedAt = startedAt, rev = ball.rev,
		readyAt = startedAt + ((kind == Tackle.WRAP) and T.wrapStartup or 0),
		expireAt = startedAt + ((kind == Tackle.WRAP) and (T.wrapStartup + 0.08) or T.diveTime) }
	announce({ kind = "lunge", who = b.model, tackleKind = kind, time = (kind == Tackle.DIVE) and T.diveTime or T.wrapStartup,
		speed = (kind == Tackle.DIVE) and T.diveSpeed * S or 0 })
end

local function carrierMove(b, move)
	if not (carrier == b and b.carry) then fb(b, "YOU DON'T HAVE THE BALL", "bad"); return end
	local c = b.carry
	local now = os.clock()
	-- answering a wrap takes priority over starting a new move
	local w = c.wrappedBy and c.wrappedBy.wrap or nil
	if w and w.target == b and now <= w.breakUntil then
		local broke, why = Tackle.answerWrap(move, w.score, c.broken, T)
		c.wrappedBy.wrap = nil
		c.wrappedBy = nil
		if broke then
			stats.broken += 1
			c.broken = Tackle.fatigueAfter(c.broken)
			c.jukeUntil = now + T.jukeImmunity
			announce({ kind = "tackle", outcome = Tackle.BROKEN, reason = why, target = b.model, broken = c.broken })
			fb(b, why, "good")
			return
		end
		fb(b, why, "bad")
		return
	end

	if move == "juke" or move == "jukeL" or move == "jukeR" then
		if now < (b.nextJuke or 0) then fb(b, "JUKE NOT READY", "warn"); return end
		b.nextJuke = now + T.jukeCooldown
		c.jukeUntil = now + T.jukeImmunity
		c.jukeRecoveryUntil = now + T.jukeImmunity + T.jukeRecovery
		announce({ kind = "move", who = b.model, move = move, side = (move == "jukeL") and 1 or -1, time = T.jukeTime, speed = T.jukeSpeed * S })
	elseif move == "spin" then
		if now < (b.nextSpin or 0) then fb(b, "SPIN NOT READY", "warn"); return end
		b.nextSpin = now + T.spinCooldown
		c.spinUntil = now + T.spinTime
		announce({ kind = "move", who = b.model, move = "spin", time = T.spinTime, speed = T.spinSpeed * S })
	elseif move == "stiffarm" then
		if now < (b.nextStiff or 0) then fb(b, "ARM NOT READY", "warn"); return end
		b.nextStiff = now + T.stiffCooldown     -- a whiff pays the full cooldown, so spamming it is punished
		c.stiffAt = now
		announce({ kind = "move", who = b.model, move = "stiffarm", time = T.stiffWindow, retain = T.stiffSpeedRetain })
		fb(b, "ARM OUT", "warn")
	end
end

local function onIntent(player, action, data)
	if typeof(action) ~= "string" then return end
	if data ~= nil and typeof(data) ~= "table" then return end
	local b = byPlayer[player]
	if not b then return end
	local rp = root(b)
	if not rp or not inZone(rp.Position, F.zoneMarginM) then return end
	if not takeToken(b) then stats.rateLimited += 1; return end
	-- every contact intent quotes the ball revision it was aimed at: a tap that crossed a possession change is stale
	local rev = data and tonumber(data.rev) or -1
	local needsRev = (action == "wrap" or action == "dive" or action == "juke" or action == "jukeL" or action == "jukeR"
		or action == "spin" or action == "stiffarm")
	if needsRev and rev ~= ball.rev then stats.stale += 1; return end

	if action == "wrap" then startTackle(b, Tackle.WRAP, data)
	elseif action == "dive" then startTackle(b, Tackle.DIVE, data)
	elseif action == "juke" or action == "jukeL" or action == "jukeR" or action == "spin" or action == "stiffarm" then
		carrierMove(b, action)
	elseif action == "role" then
		b.role = (b.role == "defense") and "offense" or "defense"
		b.model:SetAttribute("AWRole", b.role)
		State:FireClient(player, { kind = "role", role = b.role })
		fb(b, b.role == "defense" and "YOU'RE ON DEFENCE" or "YOU'RE ON OFFENCE", "good")
	elseif action == "contestJump" then
		b.jumpAt = clientTime(b, data and data.at)
	end
end
Intent.OnServerEvent:Connect(function(player, action, data) onIntent(player, action, data) end)

-------------------------------------------------------------------------------------------------- jump balls
-- A contest is armed while the ball is in the air and bodies from both sides are inside Config.contest.radius of it.
-- It resolves at the closest approach (the moment the ball starts moving away again) plus resolveDelay, so every
-- late input has arrived. Nothing is predicted: the ball's real position is read each tick.
local contest = nil
local function handPoint(b)
	local r = rigOf(b)
	if not r then
		local rp = root(b)
		return rp and rp.Position or Vector3.zero
	end
	local body = Receive.body(r)
	return body.mid + body.look * 0.38 * S
end

local function contestant(b, bp)
	local hp = handPoint(b)
	local d = Vector3.new(hp.X - bp.X, 0, hp.Z - bp.Z).Magnitude / S
	local ang = math.atan2(hp.X - bp.X, hp.Z - bp.Z)
	local tau = b.jumpAt and (workspace:GetServerTimeNow() - b.jumpAt) or nil
	if tau and tau > 2 * Contest.apex(C) + 0.4 then tau = nil end
	return { name = b.name, side = (b.role == "defense") and "defense" or "offense", dist = d, ang = ang,
		tau = tau, standReach = standReachM(b), body = b }
end

local function stepContest()
	if ball.state ~= "IN_FLIGHT" then
		if contest then contest = nil end
		return
	end
	local bp = ball.pos
	local off, def = {}, {}
	for _, b in pairs(bodies) do
		local rp = root(b)
		if rp and inZone(rp.Position, F.zoneMarginM) then
			local cont = contestant(b, bp)
			if cont.dist <= C.radius then
				if cont.side == "defense" then table.insert(def, cont) else table.insert(off, cont) end
			end
		end
	end
	if #off == 0 or #def == 0 then
		if contest and not contest.armedAt then contest = nil end
		return
	end
	local closest = math.huge
	for _, c in ipairs(off) do closest = math.min(closest, c.dist) end
	for _, c in ipairs(def) do closest = math.min(closest, c.dist) end
	if not contest or contest.rev ~= ball.rev then
		contest = { rev = ball.rev, closest = closest, armedAt = nil }
		return
	end
	if closest <= contest.closest - 1e-4 then
		contest.closest = closest
		contest.off, contest.def, contest.height = off, def, (bp.Y - G.floor) / S
		return
	end
	-- the ball is moving away again: that tick was the closest approach
	if not contest.armedAt then
		contest.armedAt = os.clock()
		contest.off = contest.off or off
		contest.def = contest.def or def
		contest.height = contest.height or (bp.Y - G.floor) / S
	end
	if os.clock() - contest.armedAt < C.resolveDelay then return end

	local res = Contest.resolve(contest.off, contest.def, contest.height, C)
	stats.contests += 1
	local winner = res.winner and res.winner.body or nil
	announce({ kind = "contest", result = res.result, reason = res.reason, winner = winner and winner.model or nil,
		scores = res.scores, margin = math.floor(res.margin * 1000) / 1000, height = math.floor(contest.height * 100) / 100 })
	record(stats.contestLog, { result = res.result, reason = res.reason, winner = winner and winner.name, scores = res.scores }, 100)
	for _, side in ipairs({ contest.off, contest.def }) do
		for _, c in ipairs(side) do
			local s = res.scores[c.name]
			fb(c.body, ("%s · %s %.2f (jump %.2f, spot %.2f, height %.2f)"):format(res.result, res.reason,
				s and s.score or 0, s and s.timing or 0, s and s.position or 0, s and s.height or 0),
				(winner == c.body) and "good" or "bad")
		end
	end
	-- possession follows the contest only when the seam is installed; otherwise this is the readable ruling and
	-- PracticeService's own catch sweep stands (see the seam note at the top).
	if res.result == "CATCH" and winner then
		seamCall("award", { model = winner.model, cause = "WON THE JUMP BALL" })
	elseif res.result == "INT" and winner then
		seamCall("award", { model = winner.model, cause = "INTERCEPTED · " .. res.reason })
	elseif res.result == "BREAKUP" or res.result == "INCOMPLETE" then
		seamCall("down", "INCOMPLETE · " .. res.reason)
	end
	contest = { rev = ball.rev, closest = math.huge, done = true }
	for _, b in pairs(bodies) do b.jumpAt = nil end
end

-------------------------------------------------------------------------------------------------- main loop
local lastAdopt = 0
local hudAt = 0
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	if now - lastAdopt > 2 then lastAdopt = now; adoptLocals() end
	trackBodies()
	readBall()

	-- possession changes start a fresh carry (fatigue, immunities and the securing window are per carry)
	local c = findCarrier()
	if c ~= carrier or (c and ball.rev ~= carryRev) then
		if carrier and carrier ~= c then carrier.carry = nil end
		carrier, carryRev = c, ball.rev
		if c then newCarry(c) end
		for _, b in pairs(bodies) do b.pending = nil; b.wrap = nil end
	end

	-- open tackle attempts
	for _, b in pairs(bodies) do
		local p = b.pending
		if p then
			if p.rev ~= ball.rev then
				b.pending = nil
			elseif now >= p.readyAt then
				local res, geo, target = tryContact(b, p.kind, p.startedAt)
				if res and res.outcome ~= Tackle.NO_CONTACT then
					b.pending = nil
					applyResult(b, target, p.kind, res, geo)
				elseif now >= p.expireAt then
					b.pending = nil
					local miss = Tackle.missPenalty(p.kind, Tackle.WHIFF, T)
					b.recoverUntil = now + miss.recover
					b.groundedUntil = now + miss.grounded
					announce({ kind = "tackle", outcome = Tackle.WHIFF, reason = "WHIFFED · NOTHING THERE",
						tackleKind = p.kind, tackler = b.model, recover = miss.recover, grounded = miss.grounded })
					stats.whiffs += 1
					fb(b, "WHIFFED", "bad")
				end
			end
		end
		-- a wrap that was never answered brings him down
		local w = b.wrap
		if w then
			if not (carrier == w.target and w.target.carry) then
				b.wrap = nil
			elseif now >= w.endsAt then
				b.wrap = nil
				if w.target.carry then w.target.carry.wrappedBy = nil end
				announce({ kind = "tackle", outcome = Tackle.TACKLED, reason = "WRAPPED UP AND BROUGHT DOWN",
					tackleKind = Tackle.WRAP, tackler = b.model, target = w.target.model })
				fb(b, "WRAP TACKLE", "good"); fb(w.target, "TAKEN DOWN", "bad")
				endPlay("TACKLED · WRAPPED UP AND BROUGHT DOWN", b)
			end
		end
	end

	stepContest()

	if now - hudAt >= 0.1 then
		hudAt = now
		local function ready(nextAt, full) return math.clamp(1 - math.max(0, nextAt - now) / full, 0, 1) end
		for _, b in pairs(bodies) do
			if b.player then
				State:FireClient(b.player, { kind = "cd",
					wrap = ready(b.nextWrap, T.cooldown), dive = ready(b.nextDive, T.cooldown),
					juke = ready(b.nextJuke or 0, T.jukeCooldown), spin = ready(b.nextSpin or 0, T.spinCooldown),
					stiff = ready(b.nextStiff or 0, T.stiffCooldown),
					role = b.role, carrying = (carrier == b),
					down = math.max(0, math.max(b.groundedUntil, b.recoverUntil) - now),
					broken = (b.carry and b.carry.broken) or 0,
					wrapped = (b.carry and b.carry.wrappedBy) and math.max(0, b.carry.wrappedBy.wrap and b.carry.wrappedBy.wrap.breakUntil - now or 0) or 0,
				})
			end
		end
	end
end)

-------------------------------------------------------------------------------------------------- Studio test hook
local hook = SS:FindFirstChild("AWTackleTest") or Instance.new("BindableFunction")
hook.Name = "AWTackleTest"; hook.Parent = SS
hook.OnInvoke = function(cmd, arg)
	if cmd == "state" then
		local list = {}
		for _, b in pairs(bodies) do
			table.insert(list, { name = b.name, role = b.role, carrying = (carrier == b),
				broken = b.carry and b.carry.broken or 0, down = math.max(0, math.max(b.groundedUntil, b.recoverUntil) - os.clock()) })
		end
		return { ball = { state = ball.state, rev = ball.rev }, carrier = carrier and carrier.name or nil,
			seam = seam ~= nil, bodies = list, stats = stats }
	elseif cmd == "role" then                 -- arg: { name = display name or model name, role = "defense"|"offense" }
		for _, b in pairs(bodies) do
			if b.name == arg.name or b.model.Name == arg.name then
				b.role = arg.role; b.model:SetAttribute("AWRole", arg.role); return true
			end
		end
		return false
	elseif cmd == "tackle" then               -- arg: { by = name, kind = "wrap"|"dive" } — runs the real path
		for _, b in pairs(bodies) do
			if b.name == arg.by or b.model.Name == arg.by then
				startTackle(b, arg.kind == "dive" and Tackle.DIVE or Tackle.WRAP, {})
				return true
			end
		end
		return false
	elseif cmd == "move" then                 -- arg: { by = name, move = "jukeL"|"jukeR"|"spin"|"stiffarm" }
		for _, b in pairs(bodies) do
			if b.name == arg.by or b.model.Name == arg.by then carrierMove(b, arg.move); return true end
		end
		return false
	elseif cmd == "jump" then                 -- arg: { name, at = server time (nil = now) }
		for _, b in pairs(bodies) do
			if b.name == arg.name or b.model.Name == arg.name then
				b.jumpAt = arg.at or workspace:GetServerTimeNow(); return true
			end
		end
		return false
	elseif cmd == "results" then
		local out = {}
		for i = math.max(1, #stats.results - (arg or 10) + 1), #stats.results do table.insert(out, stats.results[i]) end
		return out
	elseif cmd == "contests" then
		return stats.contestLog
	elseif cmd == "resetStats" then
		for k, v in pairs(stats) do if type(v) == "number" then stats[k] = 0 end end
		stats.results = {}; stats.contestLog = {}
		return true
	end
	return nil
end

print("[Tackle] Stage 3 ready · seam " .. (seam and "installed" or "NOT installed (report-only)"))
