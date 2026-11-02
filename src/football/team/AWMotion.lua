-- MIRROR of game.ReplicatedStorage.AWMotion (ModuleScript), pulled 2026-11-02 (post feature-wave-2 + ankle-breaker).
-- Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1); this copy is the QA/design record.
-- ALLSTAR WORLD · AWMotion (ModuleScript in ReplicatedStorage). Shared between client scripts on one machine:
-- a sport script that poses a character's arms itself (a dribble, a shot) "claims" the arms each frame, and the
-- athlete motion layer (AthleteMotion) leaves them alone. A football carrier claims "tuckR" so the ball arm tucks
-- high and tight while the other arm drives. Claims expire on their own 0.15 s after the last one.
local Motion = { claims = setmetatable({}, { __mode = "k" }) }

function Motion.claimArms(model, mode)
	if model then Motion.claims[model] = { mode = mode or "busy", t = os.clock() } end
end

function Motion.armMode(model)
	local c = Motion.claims[model]
	if c and os.clock() - c.t < 0.15 then return c.mode end
	return nil
end

-- Extra procedural layers (a basketball dribble, say). AthleteMotion calls every layer for every body it poses, after
-- the animation, the sport pose and the lean, as fn(model, joints, dt): joints are the R15 joints by short name
-- (root, waist, neck, rsh, lsh, rel, lel, rhip, lhip, rkn, lkn, rank, lank). A layer changes their Transform.
Motion.layers = {}
function Motion.addLayer(name, fn)
	for i, l in ipairs(Motion.layers) do if l.name == name then Motion.layers[i] = { name = name, fn = fn }; return end end
	table.insert(Motion.layers, { name = name, fn = fn })
end

-- Sport poses (stances, shots, blocks...). Since Roblox's avatar joint upgrade, R15 joints are AnimationConstraints whose
-- C0 can't be written, so a server no longer bends bodies itself: it sets the model attributes AWPose ("sport:name") and
-- AWPoseT (blend seconds), and every client layers the pose onto whatever animation is playing (AthleteMotion).
-- Angles: +X on a hip/shoulder swings the limb forward, -X on a knee folds the shin back, -X on the waist leans forward.
local rad = math.rad
local HOOPS = {
	handle = { Root = CFrame.new(0, -0.22, 0), Waist = CFrame.Angles(rad(-14), 0, 0),
		LeftHip = CFrame.Angles(rad(22), 0, rad(-6)), LeftKnee = CFrame.Angles(rad(-34), 0, 0),
		RightHip = CFrame.Angles(rad(22), 0, rad(6)), RightKnee = CFrame.Angles(rad(-34), 0, 0) },
	defend = { Root = CFrame.new(0, -0.4, 0), Waist = CFrame.Angles(rad(-18), 0, 0),
		LeftHip = CFrame.Angles(rad(36), 0, rad(-14)), LeftKnee = CFrame.Angles(rad(-62), 0, 0),
		RightHip = CFrame.Angles(rad(36), 0, rad(14)), RightKnee = CFrame.Angles(rad(-62), 0, 0),
		LeftShoulder = CFrame.Angles(rad(30), 0, rad(-55)), RightShoulder = CFrame.Angles(rad(30), 0, rad(55)) },
	shoot = { Waist = CFrame.Angles(rad(6), 0, 0), LeftShoulder = CFrame.Angles(rad(155), 0, rad(-10)),
		RightShoulder = CFrame.Angles(rad(165), 0, rad(8)), LeftElbow = CFrame.Angles(rad(30), 0, 0), RightElbow = CFrame.Angles(rad(20), 0, 0) },
	block = { LeftShoulder = CFrame.Angles(rad(170), 0, rad(-8)), RightShoulder = CFrame.Angles(rad(170), 0, rad(8)) },
	call = { RightShoulder = CFrame.Angles(rad(160), 0, rad(10)) },
	-- 3v3 full court
	catch = { Waist = CFrame.Angles(rad(-6), 0, 0), LeftShoulder = CFrame.Angles(rad(80), 0, rad(-12)), RightShoulder = CFrame.Angles(rad(80), 0, rad(12)),
		LeftElbow = CFrame.Angles(rad(30), 0, 0), RightElbow = CFrame.Angles(rad(30), 0, 0) },
	pass = { Waist = CFrame.Angles(rad(-8), 0, 0), LeftShoulder = CFrame.Angles(rad(88), 0, rad(-6)), RightShoulder = CFrame.Angles(rad(88), 0, rad(6)),
		LeftElbow = CFrame.Angles(rad(4), 0, 0), RightElbow = CFrame.Angles(rad(4), 0, 0) },
	reach = { Root = CFrame.new(0, -0.25, 0), Waist = CFrame.Angles(rad(-16), 0, 0), RightShoulder = CFrame.Angles(rad(72), 0, rad(-8)),
		LeftShoulder = CFrame.Angles(rad(25), 0, rad(-30)), LeftHip = CFrame.Angles(rad(30), 0, 0), LeftKnee = CFrame.Angles(rad(-45), 0, 0),
		RightHip = CFrame.Angles(rad(15), 0, 0), RightKnee = CFrame.Angles(rad(-30), 0, 0) },
	screen = { Root = CFrame.new(0, -0.25, 0), LeftHip = CFrame.Angles(rad(14), 0, rad(-10)), RightHip = CFrame.Angles(rad(14), 0, rad(10)),
		LeftKnee = CFrame.Angles(rad(-26), 0, 0), RightKnee = CFrame.Angles(rad(-26), 0, 0),
		LeftShoulder = CFrame.Angles(rad(40), 0, rad(25)), RightShoulder = CFrame.Angles(rad(40), 0, rad(-25)),
		LeftElbow = CFrame.Angles(rad(95), 0, 0), RightElbow = CFrame.Angles(rad(95), 0, 0) },
	layup = { Waist = CFrame.Angles(rad(4), 0, 0), RightShoulder = CFrame.Angles(rad(165), 0, rad(6)), LeftShoulder = CFrame.Angles(rad(70), 0, rad(-14)),
		LeftHip = CFrame.Angles(rad(75), 0, 0), LeftKnee = CFrame.Angles(rad(-85), 0, 0), RightHip = CFrame.Angles(rad(-5), 0, 0) },
	dunk1 = { RightShoulder = CFrame.Angles(rad(176), 0, rad(4)), LeftShoulder = CFrame.Angles(rad(45), 0, rad(-25)),
		LeftHip = CFrame.Angles(rad(35), 0, 0), LeftKnee = CFrame.Angles(rad(-60), 0, 0), RightHip = CFrame.Angles(rad(20), 0, 0), RightKnee = CFrame.Angles(rad(-40), 0, 0) },
	dunk2 = { Waist = CFrame.Angles(rad(6), 0, 0), RightShoulder = CFrame.Angles(rad(172), 0, rad(6)), LeftShoulder = CFrame.Angles(rad(172), 0, rad(-6)),
		LeftHip = CFrame.Angles(rad(35), 0, 0), LeftKnee = CFrame.Angles(rad(-65), 0, 0), RightHip = CFrame.Angles(rad(35), 0, 0), RightKnee = CFrame.Angles(rad(-65), 0, 0) },
	hang = { RightShoulder = CFrame.Angles(rad(178), 0, rad(4)), LeftShoulder = CFrame.Angles(rad(178), 0, rad(-4)),
		LeftHip = CFrame.Angles(rad(10), 0, 0), LeftKnee = CFrame.Angles(rad(-18), 0, 0), RightHip = CFrame.Angles(rad(10), 0, 0), RightKnee = CFrame.Angles(rad(-18), 0, 0) },
}
local FOOTBALL = {
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
	-- hands-up reach as the ball arrives (owner: "put the hands up", 2026-11-02) — thumbs-together high reach,
	-- set by the server on the target + the contesting DB in the final windowEarly of flight
	reach = { Waist = CFrame.Angles(rad(6), 0, 0), LeftShoulder = CFrame.Angles(rad(165), 0, rad(-8)), RightShoulder = CFrame.Angles(rad(165), 0, rad(8)),
		LeftElbow = CFrame.Angles(rad(12), 0, 0), RightElbow = CFrame.Angles(rad(12), 0, 0) },
	qbSet = { Waist = CFrame.Angles(rad(-8), 0, 0), LeftHip = CFrame.Angles(rad(12), 0, 0), LeftKnee = CFrame.Angles(rad(-20), 0, 0),
		RightHip = CFrame.Angles(rad(12), 0, 0), RightKnee = CFrame.Angles(rad(-20), 0, 0),
		LeftShoulder = CFrame.Angles(rad(30), 0, 0), RightShoulder = CFrame.Angles(rad(35), 0, 0), LeftElbow = CFrame.Angles(rad(60), 0, 0), RightElbow = CFrame.Angles(rad(60), 0, 0) },
	throw = { Waist = CFrame.Angles(0, rad(-25), 0), RightShoulder = CFrame.Angles(rad(160), 0, rad(20)), RightElbow = CFrame.Angles(rad(40), 0, 0),
		LeftShoulder = CFrame.Angles(rad(40), 0, rad(-10)) },
	rush = { Root = CFrame.new(0, -0.35, 0), Waist = CFrame.Angles(rad(-30), 0, 0), LeftHip = CFrame.Angles(rad(30), 0, 0), LeftKnee = CFrame.Angles(rad(-55), 0, 0),
		RightHip = CFrame.Angles(rad(30), 0, 0), RightKnee = CFrame.Angles(rad(-55), 0, 0), LeftShoulder = CFrame.Angles(rad(20), 0, 0), RightShoulder = CFrame.Angles(rad(20), 0, 0) },
}
local SOCCER = {
	kick = { RightHip = CFrame.Angles(rad(70), 0, 0), RightKnee = CFrame.Angles(rad(-10), 0, 0), Waist = CFrame.Angles(rad(-10), 0, 0),
		LeftShoulder = CFrame.Angles(rad(30), 0, rad(-40)), RightShoulder = CFrame.Angles(rad(-30), 0, rad(40)) },
	slide = { Root = CFrame.new(0, -1.4, 0) * CFrame.Angles(rad(60), 0, 0), RightHip = CFrame.Angles(rad(80), 0, 0), LeftKnee = CFrame.Angles(rad(-80), 0, 0) },
	keeper = { Root = CFrame.new(0, -0.3, 0), Waist = CFrame.Angles(rad(-15), 0, 0), LeftHip = CFrame.Angles(rad(25), 0, rad(-12)),
		RightHip = CFrame.Angles(rad(25), 0, rad(12)), LeftKnee = CFrame.Angles(rad(-40), 0, 0), RightKnee = CFrame.Angles(rad(-40), 0, 0),
		LeftShoulder = CFrame.Angles(rad(40), 0, rad(-40)), RightShoulder = CFrame.Angles(rad(40), 0, rad(40)) },
	dive = { Root = CFrame.new(0, -0.8, 0), LeftShoulder = CFrame.Angles(rad(170), 0, rad(-10)), RightShoulder = CFrame.Angles(rad(170), 0, rad(10)) },
	cheer = { LeftShoulder = CFrame.Angles(rad(170), 0, rad(-20)), RightShoulder = CFrame.Angles(rad(170), 0, rad(20)) },
}
Motion.POSES = { hoops = HOOPS, football = FOOTBALL, soccer = SOCCER }

-- Animation ids in one place. Read today by FootballService:85, HoopsService:96 and Hoops3Modules.Roster
-- (2026-11-02: was "nothing reads this table yet"). TeamFootballService:134, SoccerService and PracticeService:250
-- still hold string literals; TeamFootballService's move to this table is drafted in the animation QA report.
-- r15 = Roblox stock. rthro = the set AWSoccer.Athlete already applies to its slim Rthro bodies -- a football athlete
-- moved onto that body should move to this row too, or it will run a blocky R15 cycle on a slim rig.
Motion.ANIM = {
	r15 = { run = 913376220, idle = 507766388, walk = 913402848 },
	rthro = { run = 2510238627, walk = 2510242378, idle = 2510235063, jump = 2510236649, fall = 2510233257 },
	-- The five sites above all call run:AdjustSpeed(math.clamp(sp * S / 16, 0.8, 2.2)). With S = 1/0.35 that is sp/5.6,
	-- so the 2.2 cap is reached at 12.3 studs/s: every speed from a fast jog to the 21.5 studs/s sprint plays the SAME
	-- leg tempo. That is the main reason a sprint reads as a faster jog, and no client-side layer can fix it -- only the
	-- clip's playback rate can. max = 3.6 moves the cap out to 20 studs/s.
	speedClamp = { min = 0.8, max = 3.6 },
	-- FootballService:208-236 and HoopsService (~790-810) blend idle -> walk -> run across this band now.
	-- TeamFootballService:843-848, SoccerService:1262 and Hoops3Modules.Body:195 are still the old binary
	-- idle <-> run crossfade (2026-11-02). Motion.locomote below is the shared form of that blend.
	-- The third track costs 1 of the 8 tracks per Animator.
	walkBand = { lo = 4, hi = 11 },
}

-- Pose translations are in studs, and all 24 poses were authored against a default R15 body (HipHeight 2.0). Rotations
-- are proportion-free -- a 60 degree knee bend is 60 degrees on any rig -- but a fixed -0.32 stud root drop is a
-- different DEPTH of crouch on the longer-legged Rthro body in AWSoccer.Athlete. Clients scale the translation part by
-- the body's own HipHeight and leave every rotation alone. Rotations that are over-cranked for a slim rig still have to
-- be retuned by hand; this only makes the stud offsets proportion-robust.
Motion.POSE_HIP_REF = 2.0
local scaleCache = setmetatable({}, { __mode = "k" })
function Motion.scaled(pose, hipHeight)
	if not pose then return nil end
	local k = (type(hipHeight) == "number" and hipHeight > 0.1) and (hipHeight / Motion.POSE_HIP_REF) or 1
	if math.abs(k - 1) < 0.02 then return pose end
	k = math.floor(k * 50 + 0.5) / 50                 -- quantised, so one cached copy serves every body of a size
	local byK = scaleCache[pose]
	if not byK then byK = {}; scaleCache[pose] = byK end
	if byK[k] then return byK[k] end
	local out = {}
	for name, cf in pairs(pose) do
		local p = cf.Position
		out[name] = (p.Magnitude > 1e-4) and (CFrame.new(p * k) * (cf - p)) or cf
	end
	byK[k] = out
	return out
end

-- Locomotion: one shared idle -> walk -> run blend for every script that owns an Animator's tracks (server AI
-- bodies today; a client could drive its own the same way). Pure arithmetic on the given tracks - no instances,
-- no state of its own beyond what the caller passes in `st`.
--   tracks   { idle = AnimationTrack, run = AnimationTrack, walk = AnimationTrack? } (walk optional: without it,
--            this is the old binary crossfade with the better rate clamp)
--   spStuds  planar speed in studs/s (pass studs, not m/s - callers that hold m/s multiply by their studs-per-metre S)
--   backward true plays the legs in reverse at 0.8x (backpedal), same convention as the five old inline sites
--   st       optional per-body table; used only for `st.awMoving`, the idle hysteresis latch
-- Rate: the stock r15 run/walk clips are authored around a 16 studs/s stride at rate 1 (the basis of the existing
-- `/16` at all five inline sites), so rate = spStuds/16 keeps feet matched to the ground across the whole band.
Motion.RUN_CYCLE_STUDS = 16
-- idle hysteresis: the old sites flipped idle<->run across a single 1.0 m/s (2.86 studs/s) line, so a body
-- hovering at that speed twitched between tracks every few frames. Start moving above hi, sit down below lo.
Motion.IDLE_BAND = { lo = 2.0, hi = 3.2 } -- studs/s (was one threshold: 1.0 m/s = 2.857 studs/s)
function Motion.locomote(tracks, spStuds, backward, st)
	local run, idle, walk = tracks.run, tracks.idle, tracks.walk
	if not (run and idle) then return end
	local moving
	if st then
		moving = st.awMoving and (spStuds > Motion.IDLE_BAND.lo) or (spStuds > Motion.IDLE_BAND.hi)
		st.awMoving = moving
	else
		moving = spStuds > Motion.IDLE_BAND.hi
	end
	if moving then
		if idle.IsPlaying then idle:Stop(0.15) end
		local c = Motion.ANIM.speedClamp
		local rate = math.clamp(spStuds / Motion.RUN_CYCLE_STUDS, c.min, c.max) * (backward and -0.8 or 1)
		local b = Motion.ANIM.walkBand
		local w = walk and math.clamp((spStuds - b.lo) / (b.hi - b.lo), 0, 1) or 1
		if walk then
			if w < 1 then
				if not walk.IsPlaying then walk:Play(0.15) end
				walk:AdjustWeight(1 - w, 0.1); walk:AdjustSpeed(rate)
			elseif walk.IsPlaying then walk:Stop(0.2) end
		end
		if w > 0 then
			if not run.IsPlaying then run:Play(0.15) end
			run:AdjustWeight(w, 0.1); run:AdjustSpeed(rate)
		elseif run.IsPlaying then run:Stop(0.2) end
	else
		if not idle.IsPlaying then idle:Play(0.2) end
		if run.IsPlaying then run:Stop(0.2) end
		if walk and walk.IsPlaying then walk:Stop(0.2) end
	end
end

-- "sport:name" -> pose table (or nil)
function Motion.pose(key)
	if type(key) ~= "string" then return nil end
	local sport, name = string.match(key, "^(%w+):(%w+)$")
	local t = sport and Motion.POSES[sport]
	return t and t[name] or nil
end

-- the server side: publish a pose for every client to draw (nil clears it)
function Motion.setPose(model, sport, name, t)
	if not model then return end
	model:SetAttribute("AWPoseT", t or 0.15)
	model:SetAttribute("AWPose", name and (sport .. ":" .. name) or nil)
end

return Motion
