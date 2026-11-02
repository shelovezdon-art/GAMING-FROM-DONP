-- MIRROR of ReplicatedStorage.AWFootball.Config (ModuleScript), pulled 2026-11-02.
-- Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1); this copy is the QA/design record.
-- ALLSTAR WORLD · Football 1v1 tunables (Roblox port of the browser build's AW.FOOTBALL_CFG, Milestone 01).
-- Units are METRES and SECONDS, exactly as in the browser prototype; the services convert to studs with STUD (0.35 m).
local Config = {
	STUD = 0.35,
	-- LEGACY 1v1 block. Still read by FootballService (possessionsEach/startYard/otPossessionsEach/maxOtRounds) and by
	-- TeamFootballService (downs). Kept key-for-key; the IFAF ruleset below supersedes it for TeamFootballService.
	-- td: was 7 (browser prototype's TD+auto-extra-point). IFAF/NFL FLAG: a touchdown is 6 and the try is separate.
	rules = { possessionsEach = 5, downs = 4, td = 6, startYard = 20, otPossessionsEach = 1, maxOtRounds = 3 },
	rulesLegacy = { td = 7 },   -- shim: the pre-ruleset combined TD value, if any caller still wants the old scoreline

	-- ======================================================================================================
	-- IFAF FLAG FOOTBALL 5-ON-5 RULESET (ADR-0001). Research + sources: design/gdd/football-ruleset.md.
	-- One labelled deviation from IFAF: contact replaces IFAF's no-contact chapter. Everything else is the book.
	-- Metres throughout. YARD below is the only conversion the rules layer needs.
	-- ======================================================================================================
	YARD = 0.9144,                        -- [VERIFIED] metres per yard, exact

	-- Field. [VERIFIED IFAF] 50 x 25 yd field of play, 10 yd end zones, 70 yd overall.
	field = {
		lengthM = 45.72,                  -- goal line to goal line (50 yd)
		widthM = 22.86,                   -- sideline to sideline (25 yd)
		endZoneM = 9.14,                  -- one end zone (10 yd)
		totalM = 64.01,                   -- 45.72 + 2 x 9.14 (70 yd)
		noRunZoneM = 4.57,                -- [VERIFIED] 5 yd before each goal line: no designed run
		safetyAreaM = 2.74,               -- [VERIFIED] 3 yd outside each sideline
		hashMarks = false,                -- [VERIFIED] IFAF defines only a middle line. Do not add hash marks.
		-- [VERIFIED] legal national variation 40-60 yd x 20-30 yd. This is what makes a 1v1/2v2 arena rules-legal.
		minLengthM = 35.6, maxLengthM = 54.9, minWidthM = 18.3, maxWidthM = 27.4,
	},

	-- Downs. [VERIFIED IFAF] A series is 4 downs; the line to gain is the MIDDLE LINE and nothing else.
	-- Player-facing: four plays to cross midfield, then four plays to score. No chains, no measurement.
	series = {
		downsPerSeries = 4,
		firstDownOnlyAtMiddle = true,     -- crossing the middle line is the only earned first down in a possession
		snapOwnM = 4.57,                  -- [VERIFIED] own 5 yd: every change of possession, touchback, safety, TD
		kickoffs = false, punts = false, fieldGoals = false,   -- [VERIFIED] none exist in this format at all
		interceptionReturnsLive = true,   -- [VERIFIED] the one spot-of-dead-ball exception to the own-5 rule
	},

	-- Scoring. [VERIFIED IFAF] TD 6; try from the 5 = 1 and is pass-only; try from the 10 = 2, run or pass;
	-- defensive TD on a try = 2; safety = 2 to the opponent; a safety on a try = 1 to the opponent.
	-- The offence declares 1 or 2 BEFORE the snap. That declaration is the whole risk/reward decision.
	scoring = {
		touchdown = 6,
		try1 = 1, try1SpotM = 4.57,  try1PassOnly = true,
		try2 = 2, try2SpotM = 9.14,  try2PassOnly = false,
		defensiveTryTouchdown = 2,
		safety = 2, safetyOnTry = 1,
	},

	-- Penalties: exactly five. [VERIFIED] enforcement is from the LINE OF SCRIMMAGE unless spot = true, and
	-- yardage HALVES if it exceeds half the distance to the goal. There are NO 15-yard penalties in this format.
	penalty = {
		halfTheDistance = true,
		fouls = {
			defensivePI        = { yards =  10, firstDown = true,  lossOfDown = false, spot = false, label = "DEFENSIVE PASS INTERFERENCE" },
			offensivePI        = { yards = -10, firstDown = false, lossOfDown = true,  spot = false, label = "OFFENSIVE PASS INTERFERENCE" },
			defensiveHolding   = { yards =   0, firstDown = true,  lossOfDown = false, spot = false, label = "DEFENSIVE HOLDING" },
			offside            = { yards =  -5, firstDown = false, lossOfDown = false, spot = false, label = "OFFSIDE" },
			falseStart         = { yards =  -5, firstDown = false, lossOfDown = false, spot = false, label = "FALSE START" },
			unnecessaryRoughness = { yards = 10, firstDown = true, lossOfDown = false, spot = false, label = "UNNECESSARY ROUGHNESS" },
		},
		-- NOTE: offside and falseStart are the same -5 foul in the research table, split here only so the HUD can
		-- name which side moved. That is 5 distinct penalties as specified, not 6.
	},

	-- Overtime. [VERIFIED IFAF] two-series shootout from the MIDDLE LINE, no first down available at midfield;
	-- if the defence scores in the first series the period ends. [VERIFIED NFL FLAG] period 2+ collapses to a
	-- one-play try from the 5. No charged timeouts in overtime.
	overtime = {
		fromMiddleLine = true,
		seriesPerPeriod = 2,
		firstDownAvailable = false,
		defensiveScoreEndsPeriod = true,
		collapseAfterPeriod = 1,          -- from period 2 on: a single try play
		collapseSpotM = 4.57,             -- ...from the 5
		timeouts = 0,
	},

	-- Clock. [VERIFIED IFAF] two halves; the clock stops for first downs, penalties, out of bounds, incomplete
	-- passes, scores and timeouts only inside the final window of each half.
	clock = {
		-- OWNER DECISION, NOT SOURCED. IFAF's own halves are 20 real minutes, which no Roblox round can carry.
		-- [ASSUMPTION] recommended 4-6 real minutes a half (240-360 s) so a match fits the 6-10 min window a
		-- player gives a round. Left as a knob on purpose -- do not treat this value as researched.
		halfSeconds = 300,                -- 5 min: the midpoint of the recommendation
		halves = 2,
		intermissionSeconds = 120,        -- [VERIFIED] IFAF 2-minute intermission
		stopClockWindowSeconds = 60,      -- [ASSUMPTION] IFAF's window is 120 s of a 20 min half; scaled to 60 s here
		playClockSeconds = 22,            -- [ASSUMPTION] research recommends 20-25 s
		timeoutsPerHalf = 2,              -- [VERIFIED] two charged, non-carrying
		timeoutSeconds = 90,              -- [VERIFIED] up to 90 s
		stopOn = { firstDown = true, penalty = true, outOfBounds = true, incomplete = true, score = true, timeout = true },
	},

	-- ======================================================================================================
	-- BALL PHYSICS CONSTANTS. All [VERIFIED] with provenance except where marked. See football-ruleset.md s4.
	-- These describe the real ball; `Config.ball` above stays as-is because the live flight code reads it.
	-- ======================================================================================================
	ballPhysics = {
		massKg = 0.411,                   -- [VERIFIED] flight-literature model mass; official range 0.397-0.425 kg
		longAxisMinM = 0.279, longAxisMaxM = 0.286,      -- [VERIFIED] NFL Football Operations, 11 - 11.25 in
		semiMajorM = 0.141, semiMinorM = 0.086,          -- [VERIFIED] a/b = 1.618
		axisRatio = 1.618,                -- [VERIFIED]
		inertiaTransverse = 3.21e-3, inertiaLongitudinal = 1.94e-3,   -- [VERIFIED] kg m^2, ratio 0.604

		-- Release speed band. Throw TYPES vary launch angle, not speed (see throwAngle below).
		releaseTypicalMps = 20.0,         -- [VERIFIED]
		releaseEliteMps = 25.0,           -- [VERIFIED]
		releaseCeilingMps = 26.8,         -- [VERIFIED]
		releaseDeepCaseMps = 27.4,        -- [VERIFIED] the 27.4 m/s at 30 deg deep-ball case used for calibration

		spinRadS = 62.8,                  -- [VERIFIED] 600 rpm = 10 rev/s
		nutationRadS = 38.0,              -- [VERIFIED] aerodynamic-torque nutation of a WELL-thrown pass, period ~0.19 s
		precessionRadS = 2.52,            -- [VERIFIED] nose-tracking precession rate
		velocityRotationRadS = 0.37,      -- [VERIFIED] rotation rate of the velocity vector over a pass
		yawOffsetDeg = 9.0,               -- [VERIFIED] the nose's tracking error is centred here, not at zero
		precessionRadius = 0.15,          -- [VERIFIED] ...growing to 0.22 for a 10 deg initial pitch error
		precessionRadiusPitched = 0.22,   -- [VERIFIED]

		-- Drag reference area. This ~60% swing is WHY spiral quality matters: a wobbling ball presents more area,
		-- so it drags more and lands measurably shorter. It is the honest feedback channel for a bad throw.
		areaNoseOnM2 = 0.023,             -- [VERIFIED] pi * b^2
		areaBroadsideM2 = 0.038,          -- [VERIFIED] pi * a * b
		airDensity = 1.21,                -- [VERIFIED] kg/m^3, the wind-tunnel condition

		-- THE ONE TUNED CONSTANT. The wind-tunnel source publishes C_D only as figures with +/-0.094 uncertainty
		-- (13-55% of the observed values) and the flight paper publishes none, so ANY single C_D is invented.
		-- This is therefore a tuning dial, not a measurement. CALIBRATION TARGET: a 27.4 m/s throw released at
		-- 30 deg must land MEASURABLY SHORT of the drag-free range of 66.4 m in 2.80 s. Tune against that, and
		-- never cite this number as sourced.
		dragCoefficientTUNED = 0.17,      -- [TUNED, NOT SOURCED]
		dragFreeRangeM = 66.4, dragFreeTimeS = 2.80,     -- [VERIFIED] the calibration benchmark itself
		magnusOverM = 0.8, magnusOmit = true,            -- [VERIFIED] ~0.8 m over 50 m: below notice, so omitted

		-- Launch angle per throw type. [ASSUMPTION - DESIGN INFERENCE] No study splits bullet/touch/lob release
		-- speed, so the sourced 20-27 m/s band is held and the ANGLE is what varies. Optimal range angle is 45.
		throwAngleDeg = {
			BULLET = { min =  5, max = 15 },
			TOUCH  = { min = 20, max = 30 },
			LOB    = { min = 35, max = 45 },
		},
		groundIsDead = true,              -- [VERIFIED IFAF] a pass or fumble touching the ground is dead.
		                                  -- Deliberate: real prolate bounce is chaotic and would decide turnovers
		                                  -- with no player input. Contest the fumble IN THE AIR instead.
	},

	-- ======================================================================================================
	-- COVERAGE. [VERIFIED] coaching-standard distances; the three-state footwork machine is the skill ceiling.
	-- ======================================================================================================
	coverage = {
		alignMinM = 4.6, alignMaxM = 6.4,      -- [VERIFIED] off-coverage alignment depth
		cushionMinM = 1.8, cushionMaxM = 2.7,  -- [VERIFIED] the cushion a DB defends
		pressAlignM = 1.4,                     -- [VERIFIED] press alignment
		controlPedalFraction = 0.75,           -- [VERIFIED] a control pedal runs at 75% of top speed
		-- Three states with stated transitions: control -> speed once the cushion is threatened -> man turn once
		-- the cushion is broken. No roll decides which: the distance does.
		states = { "controlPedal", "speedPedal", "manTurn" },
		threatenedAtM = 2.7,                   -- cushion at/under its max and closing: go to the speed pedal
		brokenAtM = 1.8,                       -- cushion under its min: flip the hips
		-- Leverage is set by whether deep help exists. [VERIFIED]
		leverageWithHelp = "outsideEye", leverageWithoutHelp = "insideEye",
	},

	qb = { dropbackDepth = 3.0, dropbackTime = 0.8, minReadTime = 1.1, deadline = 3.4, windup = 0.35,
		throwSpeedMin = 14, throwSpeedMax = 27, accuracy = 0.82, rushedPenalty = 0.9, leadFactor = 0.85 }, -- throwSpeedMax was 24; 27 ≈ the sourced 26.8 m/s elite ceiling (football-ruleset.md §4)
	ball = { gravity = 13.5, catchHeight = 1.25, minFlight = 0.55, maxFlight = 2.15 }, -- maxFlight was 1.6: owner wants deep balls rewarded (live-tuned + approved 2026-11-02)
	jump = { highCatchHeight = 2.05, needHeight = 0.55, tightCoverage = 2.2, jumpSpeed = 6.2, gravity = 22,
		flightScale = 1.35, maxFlight = 2.5, cpuReaction = 0.12, aggressiveMargin = 0.05 }, -- maxFlight was 1.95: longer jump-ball hang (owner, 2026-11-02)
	catch = { secureReach = 1.5, aggressiveReach = 2.3, autoReach = 0.9, autoChance = 0.5, windowEarly = 0.5, -- reaches were 1.3/2.1, windowEarly 0.4 (owner catch-feel pass, 2026-11-02)
		windowLate = 0.22, cpuBase = 0.86, cpuContestedPenalty = 0.4, contestRadius = 1.1, -- windowLate was 0.15
		-- Which catch model Rules.resolveCatch uses. "roll" is the shipped quality-roll (0.97/0.80/0.50/0.35,
		-- untouched above); "deterministic" routes to Rules.judgeCatchDeterministic, which never rolls a die.
		-- Default stays "roll" until parity is proven in a playtest. Flip this key, nothing else.
		model = "roll",
		-- Deterministic model. Difficulty is a sum of three readable terms against `threshold`.
		-- Basis [VERIFIED technique]: above the waist the fingers point up and the thumbs touch; below the waist
		-- the hands turn down and the pinkies meet. That switch at the waist is the real, teachable, binary rule.
		-- [ASSUMPTION] that the switch is the right basis for a DIFFICULTY curve, and the over-the-shoulder and
		-- contested penalties below, are coaching lore that could NOT be sourced: treat them as tuning.
		det = {
			waistM = 1.05,                -- height of the waist above the feet: the thumbs-up / pinkies-down line
			comfortBandM = 0.45,          -- within this much of chest height the catch is free
			heightK = 0.55,               -- difficulty per metre outside the comfort band
			belowWaistK = 1.35,           -- a scoop below the waist costs more than the same error above it
			comfortSpeedMps = 14.0,       -- relative arrival speed that starts to hurt (= AWPractice pass.catch)
			speedScale = 12.0,           -- difficulty per (speed - comfort) / this
			facingFreeDeg = 35,           -- ball-velocity vs receiver-facing angle that is free
			facingK = 0.9,                -- difficulty per 90 deg beyond that
			overShoulderAdd = 0.22,      -- [ASSUMPTION/tuning]
			contestedAdd = 0.30,         -- [ASSUMPTION/tuning] a defender inside catch.contestRadius
			oneHandMul = 1.30,           -- [ASSUMPTION/tuning]
			threshold = 1.0,              -- at or above this it is not caught
			dropBandM = 0.35,            -- how far past the threshold still reads as a DROP rather than out of reach
		},
	},
	defend = { swatReach = 1.7, intReach = 0.95, cpuAttemptChance = 0.55, reaction = 0.22 },
	tackle = { reach = 1.35, lungeReach = 1.7, lungeTime = 0.3, lungeSpeed = 12.5, whiffRecovery = 0.65, cooldown = 0.9,
		facingCos = 0.15, jukeImmunity = 0.28, cleanClosingSpeed = 4.0, cleanAngleCos = -0.2, wrapDrag = 0.45,
		breakWindow = 0.35, cpuBreakChance = 0.35 },
	move = { wrSpeed = 9.6, dbSpeed = 9.3, cpuWrSpeed = 9.1, cpuDbSpeed = 9.25, carrySpeed = 9.0, jukeSpeed = 12.5,
		jukeTime = 0.22, jukeCooldown = 1.1, spinTime = 0.42, spinCooldown = 1.6, spinSpeed = 6.5, stiffArmReach = 1.6,
		stiffArmStun = 0.7, stiffArmCooldown = 1.4 },
	ai = { cpuJukeChance = 0.5, cpuTackleAngleError = 0.5 },
	-- Stance, snap and release: both sides get the same timing windows off the same HUT. Moving early is a penalty.
	stance = { cadenceMin = 0.9, cadenceMax = 2.2, perfect = 0.15, good = 0.35, autoRelease = 0.6,
		perfectBurst = 1.18, goodBurst = 1.08, burstTime = 0.7, falseStartYards = 5, earlyFreeze = 0.5,
		cpuReactMin = 0.08, cpuReactMax = 0.42, setGrace = 0.45 },
	-- DB backpedal: pedal facing the line (slower) until you flip your hips; beaten deep = forced flip with a stumble.
	pedal = { speed = 6.6, flipTime = 0.18, beatenMargin = 0.6, beatenStumble = 0.3, cpuFlipReaction = 0.2, cpuCushion = 1.4 },
	flow = { downOverTime = 2.4, finalTime = 6, cpuSnapDelay = 1.8, presnapAutoSnap = 12, leaveDistance = 40 },
	seed = 1337,
}
return Config
