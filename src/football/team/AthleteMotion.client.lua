-- MIRROR of game.StarterPlayer.StarterPlayerScripts.AthleteMotion (LocalScript), pulled 2026-11-02 (post wave-3, Gauntlet, DRIP, broadcast UI, stance poses, 2K camera).
-- Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1); this copy is the QA/design record.
-- ALLSTAR WORLD · AthleteMotion (LocalScript). A procedural layer on top of the running animation, for every R15
-- character on screen (players and CPU athletes), so a sprint looks like a sprint and not a faster jog:
--   · forward lean that grows with speed, plus a push-forward when accelerating and a lean-back plant when braking
--   · banking into cuts (lean scales with speed × turn rate), head kept level
--   · longer stride and higher knees at sprint speed (the animation's own leg swing, amplified)
--   · arm drive: elbows bent, arms pumping opposite the legs in time with the stride
--   · football carrier: the ball arm tucks high and tight while the other arm drives (blended, not snapped)
--   · landing: knees, ankles and hips absorb a touchdown, scaled by how long and how fast the body fell
--   · hard cut: a plant that punches in and decays out, so a cut has a snap instead of a smooth ramp
--   · follow-through: a throw, a shot or a kick releases slowly instead of snapping back to neutral
-- Runs after the animation each frame (PreSimulation) and only changes how bodies look on this screen; it never moves
-- anyone -- every line below writes a joint's .Transform or nothing at all, never a character's position, velocity or
-- any Humanoid property -- so it can't affect gameplay or fairness. Keep that invariant: a layer that moved a body
-- would make this client-side cosmetic code authoritative over the match.
-- It adds NO animation tracks. Everything here is arithmetic on the joints the animator already wrote, so it fits any
-- track budget, including the 8-track-per-Animator ceiling of Roblox's Server Authority. Sport scripts that pose the arms themselves claim them via AWMotion.
--   · basketball clips (AWClip, see AWHoops/Clips): layups, dunks, the 360, rebounds, the spin move — the whole body is
--     posed from the clip at the server's clock (blended in and out), then the ball layer (BallView) puts the hands on
--     the ball. While a clip plays, the run lean / arm pump stay out of its way.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Motion = require(RS:WaitForChild("AWMotion"))
local Clips = nil
task.spawn(function()
	local f = RS:WaitForChild("AWHoops", 30)
	local m = f and f:WaitForChild("Clips", 30)
	if m then Clips = require(m) end
end)

local rad, clamp, exp = math.rad, math.clamp, math.exp
local S = 1 / 0.35                        -- studs per metre
local JOG, SPRINT = 18.0, 21.5            -- studs/s: sprint pose blends in between these (≈ 6.3 → 7.5 m/s)
local MAX_DIST = 260                      -- studs from the camera: further bodies aren't worth posing
local FOLLOW_T = 0.42                     -- s: release time for a throw / shot / kick (their own AWPoseT is ~0.15)
local FOLLOW = { ["football:throw"] = true, ["hoops:shoot"] = true, ["soccer:kick"] = true, ["hoops:layup"] = true }

local JOINTS = {
	root = { "LowerTorso", "Root" }, waist = { "UpperTorso", "Waist" }, neck = { "Head", "Neck" },
	rsh = { "RightUpperArm", "RightShoulder" }, lsh = { "LeftUpperArm", "LeftShoulder" },
	rel = { "RightLowerArm", "RightElbow" }, lel = { "LeftLowerArm", "LeftElbow" },
	rhip = { "RightUpperLeg", "RightHip" }, lhip = { "LeftUpperLeg", "LeftHip" },
	rkn = { "RightLowerLeg", "RightKnee" }, lkn = { "LeftLowerLeg", "LeftKnee" },
	rank = { "RightFoot", "RightAnkle" }, lank = { "LeftFoot", "LeftAnkle" },
}
-- sport pose joint names (AWMotion.POSES) -> our keys
local POSE_KEY = { Root = "root", Waist = "waist", Neck = "neck", RightShoulder = "rsh", LeftShoulder = "lsh", RightElbow = "rel",
	LeftElbow = "lel", RightHip = "rhip", LeftHip = "lhip", RightKnee = "rkn", LeftKnee = "lkn", RightAnkle = "rank", LeftAnkle = "lank" }
local IDENT = CFrame.new()

local tracked = {}   -- [Humanoid] = state
local function track(h)
	if h:IsA("Humanoid") and not tracked[h] then tracked[h] = {} end
end
for _, d in ipairs(workspace:GetDescendants()) do if d:IsA("Humanoid") then track(d) end end
workspace.DescendantAdded:Connect(function(d) if d:IsA("Humanoid") then task.defer(track, d) end end)
workspace.DescendantRemoving:Connect(function(d) if d:IsA("Humanoid") then tracked[d] = nil end end)

local function resolve(model, st)
	local j = st.j
	if not j and st.retryAt and os.clock() < st.retryAt then return nil end   -- not an R15 body (yet)
	if j then
		local ok = true
		for _, m in pairs(j) do if not m.Parent then ok = false; break end end
		if ok then return j end
	end
	j = {}
	local missing
	for key, path in pairs(JOINTS) do
		local part = model:FindFirstChild(path[1])
		local m = part and part:FindFirstChild(path[2])
		if not (m and (m:IsA("AnimationConstraint") or m:IsA("Motor6D"))) then
			missing = missing or {}
			missing[#missing + 1] = path[1] .. "." .. path[2]
		else
			j[key] = m
		end
	end
	if missing then
		-- Degrade to plain stock animation (unchanged). But say so: a non-conforming imported rig used to go stiff with
		-- NOTHING in the log, which is indistinguishable from this script being broken. Once per body, never per frame,
		-- and never again once the body conforms -- a retargeted Mixamo rig missing one joint is now findable.
		if not st.jointWarned then
			st.jointWarned = true
			warn(("[AthleteMotion] %s not posed: %d/13 R15 joints missing (%s). Falling back to stock animation.")
				:format(model:GetFullName(), #missing, table.concat(missing, ", ", 1, math.min(#missing, 4))))
		end
		st.j = nil; st.retryAt = os.clock() + 2; return nil
	end
	st.j = j
	st.hipK = nil
	return j
end

-- the animation's own rotation of a joint, scaled (keeps its offset)
local function amplify(m, k)
	local cf = m.Transform
	local axis, ang = cf:ToAxisAngle()
	if ang ~= ang or axis.Magnitude < 1e-4 then return end
	m.Transform = CFrame.new(cf.Position) * CFrame.fromAxisAngle(axis, ang * k)
end
local function pitchOf(m) local x = m.Transform:ToEulerAnglesXYZ(); return x end
local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
local function approach(cur, target, rate, dt) return cur + (target - cur) * (1 - exp(-rate * dt)) end

local function pose(h, st, dt, camPos)
	local model = h.Parent
	local root = h.RootPart
	if not (model and root) or h.Health <= 0 then st.last = nil; return end
	local pos = root.Position
	if (pos - camPos).Magnitude > MAX_DIST then st.last = nil; return end
	local j = resolve(model, st)
	if not j then return end
	st.posed = j                                   -- the extra layers (AWMotion.layers) run on this body afterwards
	-- how this body's leg length compares with the default R15 one the poses were authored against (1 = default)
	local hipK = st.hipK
	if not hipK then
		hipK = (h.HipHeight > 0.1) and (h.HipHeight / Motion.POSE_HIP_REF) or 1
		st.hipK = hipK
	end

	-- the sport pose the server published for this body (stance, shot, block...), blended in and layered onto the animation
	local poseKey = model:GetAttribute("AWPose")
	local target = Motion.pose(poseKey)
	if target then
		-- stud offsets were authored for a default R15 body; scale them to this one (rotations pass through untouched,
		-- and AWMotion caches one scaled copy per pose per body size, so this is a table lookup after the first frame)
		target = Motion.scaled(target, h.HipHeight)
		st.lastPose = poseKey
	end
	-- PRE-SNAP WAVE (2026-11-02): a STANCE loses weight as the body picks up speed; an ACTION pose never does.
	-- MEASURED FIRST: the pose is layered MULTIPLICATIVELY onto the animation below (`cur * j[key].Transform`), so a
	-- pose has never frozen the legs -- the walk/run cycle keeps playing underneath and the pose is an offset on top of
	-- it. What it did do is apply a full-depth crouch to a body already sprinting, which reads as a man running in a
	-- squat; the deeper dbCrouch / snap poses of this wave would have made that much worse. Which poses fade, how fast,
	-- and the floor they keep are data in AWMotion.STANCE_FADE -- nothing fades unless it is listed there, so throw,
	-- collapse and reach still land at full weight at any speed.
	-- Speed is last frame's smoothed st.vel (computed further down, after the clip layer): one frame of latency, which
	-- is invisible against the pose's own 0.15 s blend.
	local poseW = target and Motion.stanceWeight(poseKey, st.vel and st.vel.Magnitude or 0) or 1
	if target or st.poseCur then
		st.poseCur = st.poseCur or {}
		local blendT = math.max(0.05, tonumber(model:GetAttribute("AWPoseT")) or 0.15)
		-- follow-through: a throw, a shot or a kick doesn't snap back to neutral, the body carries past and settles. When
		-- one of those poses clears, its residue decays over FOLLOW_T instead of the pose's own (much shorter) blend time.
		if not target and FOLLOW[st.lastPose or ""] then blendT = FOLLOW_T end   -- was: always the AWPoseT blend, ~0.15 s
		local k = 1 - exp(-dt * 3 / blendT)
		local any = false
		for name, key in pairs(POSE_KEY) do
			local want = target and target[name] or IDENT
			if poseW < 0.999 then want = IDENT:Lerp(want, poseW) end   -- was: always the pose's full depth
			local cur = st.poseCur[key] or IDENT
			cur = cur:Lerp(want, k)
			if not target and (cur.Position.Magnitude < 1e-3 and cur.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.99999 and cur.UpVector.Y > 0.99999) then cur = nil end
			st.poseCur[key] = cur
			if cur then any = true; j[key].Transform = cur * j[key].Transform end
		end
		if not any then st.poseCur = nil end
	end

	-- a basketball clip (finish, rebound, spin): absolute joint targets, blended over whatever the animation did
	local clipStr = model:GetAttribute("AWClip")
	if clipStr ~= st.clipStr then
		st.clipStr = clipStr
		st.clip = (clipStr and Clips) and Clips.decode(clipStr) or nil
	end
	if st.clip then
		local pose, w, yaw = Clips.sample(st.clip, workspace:GetServerTimeNow() - st.clip.t0)
		if pose and w > 0.001 then
			for key, m in pairs(j) do
				local want = pose[key] or IDENT
				m.Transform = m.Transform:Lerp(want, w)
			end
			if yaw ~= 0 then j.root.Transform = CFrame.Angles(0, yaw, 0) * j.root.Transform end
			Motion.claimArms(model, "busy")
			-- was: st.last = nil -- which zeroed vel/pitch/roll/run/spr, so lean and stride rebuilt from flat over
			-- 100-170 ms exactly as a dunk or layup landed and the camera was on it. Re-seat the position instead and
			-- keep the lean state, so the run layer resumes from where the body actually is.
			st.last = pos
			return
		elseif not pose then
			st.clip = nil
		end
	end

	-- motion from the root's own path (works for players, CPU athletes and anything else moving a body)
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 1e-3 then return end
	flatLook = flatLook.Unit
	local yaw = math.atan2(-flatLook.X, -flatLook.Z)
	if not st.last then
		st.last, st.yaw, st.vel, st.yawRate, st.acc = pos, yaw, Vector3.zero, 0, 0
		st.pitch, st.roll, st.spr, st.run = 0, 0, 0, 0
		return
	end
	local raw = (pos - st.last) / dt
	st.last = pos
	raw = Vector3.new(raw.X, 0, raw.Z)
	if raw.Magnitude > 120 then st.vel = Vector3.zero; st.yaw = yaw; return end   -- a teleport / respawn
	local prevFwd = st.vel:Dot(flatLook)
	st.vel = st.vel:Lerp(raw, 1 - exp(-14 * dt))
	local speed = st.vel.Magnitude
	local fwd = st.vel:Dot(flatLook)
	st.yawRate = approach(st.yawRate, wrap(yaw - st.yaw) / dt, 10, dt)
	st.yaw = yaw
	st.acc = approach(st.acc, (fwd - prevFwd) / dt / S, 8, dt)          -- m/s² along facing

	local grounded = h.FloorMaterial ~= Enum.Material.Air
	-- landing: remember how long and how fast the body fell, and arm an absorb for the frame it touches down
	if not grounded then
		st.air = (st.air or 0) + dt
		st.vyMin = math.min(st.vyMin or 0, root.AssemblyLinearVelocity.Y)
	elseif st.air then
		if st.air > 0.12 then                                        -- a real fall, not a kerb or a step
			st.land = clamp(-(st.vyMin or 0) / 55, 0, 1) * clamp(st.air / 0.45, 0.35, 1)
		end
		st.air, st.vyMin = nil, nil
	end
	local run = grounded and clamp((speed - 3) / 12, 0, 1) or 0
	local spr = grounded and clamp((speed - JOG) / (SPRINT - JOG), 0, 1) or 0
	st.run = approach(st.run, run, 8, dt)
	st.spr = approach(st.spr, spr, 6, dt)
	run, spr = st.run, st.spr

	-- lean: forward with speed, more while accelerating, back when braking hard; bank into cuts
	local accLean = 0
	if run > 0.2 then accLean = clamp(st.acc * 0.9, -8, 7) end
	local tPitch = -(4 * run + 9 * spr) - math.max(0, accLean) + math.max(0, -accLean) * 1.2
	local tRoll = clamp(st.yawRate * speed / S * 0.9, -13, 13) * run
	st.pitch = approach(st.pitch, tPitch, 10, dt)
	st.roll = approach(st.roll, tRoll, 10, dt)
	local pitch, roll = st.pitch, st.roll
	if math.abs(pitch) + math.abs(roll) > 0.05 then
		j.root.Transform = j.root.Transform * CFrame.Angles(rad(pitch * 0.3), 0, rad(roll))
		j.waist.Transform = j.waist.Transform * CFrame.Angles(rad(pitch * 0.7), 0, rad(roll * 0.25))
		j.neck.Transform = j.neck.Transform * CFrame.Angles(rad(-pitch * 0.8), 0, rad(-roll * 0.6))
	end

	-- a hard cut: arm a plant that punches straight in and decays out, so the cut has a snap the smooth roll ramp lacks
	local cutMag = math.abs(st.yawRate) * speed / S
	if cutMag > 9 and run > 0.5 then
		local want = clamp((cutMag - 9) / 14, 0, 1)
		if want > (st.cut or 0) then st.cut = want; st.cutSide = (st.yawRate > 0) and 1 or -1 end
	end

	local mode = Motion.armMode(model)
	-- was: an absolute assignment with no blend at all, so the ball arm appeared and vanished in one frame, and a single
	-- frame without a claim (they expire 0.15 s after the last one) flicked it back to the pump. Blend it.
	st.tuck = approach(st.tuck or 0, (mode == "tuckR") and 1 or 0, 14, dt)
	if st.tuck > 0.01 then
		-- ball arm high and tight: elbow folded, forearm across the chest (standing or running)
		j.rsh.Transform = j.rsh.Transform:Lerp(CFrame.Angles(rad(28), 0, rad(-14)), st.tuck)
		j.rel.Transform = j.rel.Transform:Lerp(CFrame.Angles(rad(98), 0, 0), st.tuck)
	end
	-- legs: longer stride, higher knee drive at sprint. Runs before the absorb and the plant so amplify() -- which
	-- rescales a joint's whole rotation -- can't rescale them too.
	if run >= 0.02 and spr > 0.02 then
		local k = 1 + 0.32 * spr
		amplify(j.rhip, k); amplify(j.lhip, k)
		amplify(j.rkn, 1 + 0.4 * spr); amplify(j.lkn, 1 + 0.4 * spr)
	end
	-- The arm pump swings off the OPPOSITE hip's own animated pitch, so read both hips here -- before the absorb and the
	-- plant below bend them -- or a landing and a cut would feed themselves back into the arms.
	local hipPitchR, hipPitchL = pitchOf(j.rhip), pitchOf(j.lhip)

	-- the settle after a landing: full on the touchdown frame, under a tenth by 0.25 s, clear by 0.5 s. Knees and ankles give, the thighs
	-- come forward and the hips drop. Deliberately above the run gate below: most jumps land from a standstill.
	if st.land then
		local a = st.land
		st.land = a * exp(-dt / 0.11)
		if st.land < 0.01 then st.land = nil end
		local fold = rad(-30 * a)
		j.rkn.Transform = j.rkn.Transform * CFrame.Angles(fold, 0, 0)
		j.lkn.Transform = j.lkn.Transform * CFrame.Angles(fold, 0, 0)
		j.rhip.Transform = j.rhip.Transform * CFrame.Angles(rad(16 * a), 0, 0)
		j.lhip.Transform = j.lhip.Transform * CFrame.Angles(rad(16 * a), 0, 0)
		j.rank.Transform = j.rank.Transform * CFrame.Angles(rad(14 * a), 0, 0)
		j.lank.Transform = j.lank.Transform * CFrame.Angles(rad(14 * a), 0, 0)
		j.waist.Transform = j.waist.Transform * CFrame.Angles(rad(-10 * a), 0, 0)
		j.root.Transform = CFrame.new(0, -0.35 * a * hipK, 0) * j.root.Transform
	end

	-- the plant on a cut: the outside leg braces and the torso counters over it
	if st.cut then
		local c = st.cut
		st.cut = c * exp(-dt / 0.13)
		if st.cut < 0.01 then st.cut = nil end
		local sideSign = st.cutSide or 1
		local hipJ = (sideSign > 0) and j.rhip or j.lhip
		local knJ = (sideSign > 0) and j.rkn or j.lkn
		local ankJ = (sideSign > 0) and j.rank or j.lank
		hipJ.Transform = hipJ.Transform * CFrame.Angles(rad(-9 * c), 0, rad(14 * c * sideSign))   -- +Z splays the leg out (AWMotion header)
		knJ.Transform = knJ.Transform * CFrame.Angles(rad(-20 * c), 0, 0)
		ankJ.Transform = ankJ.Transform * CFrame.Angles(rad(12 * c), 0, 0)
		j.waist.Transform = j.waist.Transform * CFrame.Angles(0, 0, rad(-5 * c * sideSign))
	end

	if run < 0.02 then return end

	-- arms: pump opposite the legs (right arm with the left leg), elbows bent
	if mode == "busy" then return end
	local w = clamp(0.35 * run + 0.65 * spr, 0, 1)
	local function drive(sh, el, oppHipPitch, side, wm)
		local ww = w * (wm or 1)
		if ww < 0.01 then return end
		local swing = clamp(oppHipPitch * (1.25 + 0.35 * spr), rad(-60), rad(70))
		local tSh = CFrame.Angles(swing, 0, side * rad(6))
		local tEl = CFrame.Angles(rad(50 + 35 * spr) + math.max(0, swing) * 0.35, 0, 0)
		sh.Transform = sh.Transform:Lerp(tSh, ww)
		el.Transform = el.Transform:Lerp(tEl, ww)
	end
	-- was: a hard `if mode ~= "tuckR"` skip, which popped between pump and tuck. Hand the right arm over gradually.
	drive(j.rsh, j.rel, hipPitchL, 1, 1 - (st.tuck or 0))
	drive(j.lsh, j.lel, hipPitchR, -1)
end

RunService.PreSimulation:Connect(function(dt)
	if dt <= 0 then return end
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for h, st in pairs(tracked) do
		if h.Parent then
			st.posed = nil
			local ok, err = pcall(pose, h, st, dt, camPos)
			if not ok and not st.warned then st.warned = true; warn("[AthleteMotion] " .. tostring(err)) end
			if st.posed and #Motion.layers > 0 then
				for _, layer in ipairs(Motion.layers) do
					local ok2, err2 = pcall(layer.fn, h.Parent, st.posed, dt)
					if not ok2 and not st.layerWarned then st.layerWarned = true; warn("[AthleteMotion] layer " .. layer.name .. ": " .. tostring(err2)) end
				end
			end
		else
			tracked[h] = nil
		end
	end
end)