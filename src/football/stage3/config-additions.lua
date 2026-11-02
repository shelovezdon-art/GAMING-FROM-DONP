--[[ PATCH · ReplicatedStorage.AWPractice.Config  (Stage 3: defender, tackling, jump balls)

   This is NOT a replacement Config. Paste the two blocks below into the existing module, between
   `Config.pass = { ... }` and `Config.net = { ... }`, keeping the file's own comment style.
   Nothing already in Config changes. Units are metres and seconds, like every other block; `Config.S`
   converts to studs at the Instance boundary.

   Where a value was carried over from the older 1v1 mode, the comment says so:
     [AWF] = taken unchanged from ReplicatedStorage.AWFootball.Config (already tuned and played)
     [GDD] = the design doc's starting value, converted from studs to metres where it was in studs
     [NEW] = chosen here, with the reason on the line
]]

-- Tackling (Stage 3). A tackler's reach is measured off his own R15 rig (shoulder + upper arm + forearm + hand), the
-- same way Receive does it, so a long-armed athlete really does tackle from further out. These are only the margins
-- added on top of that measurement, plus the timings.
Config.tackle = {
	-- reach
	bodySlack = 0.19,                     -- the carrier's torso the arms have to get around (= Receive.TORSO_R, same body)
	latencySlack = 0.35,                  -- the server sees characters slightly late (same allowance as Config.possession)
	diveExtra = 0.35,                     -- [NEW] extra stretch a full-length dive buys over a standing wrap
	missMargin = 1.2,                     -- [AWF] further out than reach + this and the attempt costs nothing: you were never close
	wrapCos = 0.5,                        -- [GDD] a wrap needs him inside 60 deg of where you face (WRAP_CONE_HALF)
	diveCos = 0.15,                       -- [AWF] a dive is aimed and committed, so it connects over a wider ~81 deg arc

	-- the two tackles
	wrapStartup = 0.10,                   -- [GDD] seconds before a wrap can connect: you have to close your arms
	wrapMiss = 0.40,                      -- [GDD] seconds of slowed recovery after a wrap that touched nothing
	diveTime = 0.30,                      -- [AWF] seconds the dive lunge lasts (lungeTime)
	diveSpeed = 12.5,                     -- [AWF] m/s along the dive (lungeSpeed) — covers 3.75 m, faster than a sprint
	diveMiss = 1.00,                      -- [GDD] seconds out of the play after a whiffed dive
	grounded = 1.00,                      -- [GDD] ...of which this long is spent actually on the floor
	cooldown = 0.90,                      -- [AWF] seconds between tackle attempts
	wrapDrag = 0.45,                      -- [AWF] seconds a wrap drags him before he goes down
	wrapDragMul = 0.35,                   -- [AWF] his top speed while being dragged
	breakWindow = 0.35,                   -- [AWF] seconds he has to answer a wrap with a move
	stumble = 0.35,                       -- [GDD] seconds off his feet after a stumble (any contact then finishes it)

	-- the carrier's moves (ported from AWFootball.Config.move, which already plays well)
	jukeTime = 0.22, jukeCooldown = 1.10, jukeSpeed = 12.5,   -- [AWF]
	jukeImmunity = 0.28,                  -- [AWF] seconds after a juke in which a tackle cannot land
	jukeRecovery = 0.25,                  -- [NEW] ...and then this long in which the ball is still away from his body
	spinTime = 0.42, spinCooldown = 1.60, spinSpeed = 6.5,    -- [AWF]
	stiffWindow = 0.30,                   -- [GDD] the stiff-arm is live this long after the press
	stiffPeak = 0.15,                     -- [GDD] and is strongest halfway through it
	stiffCooldown = 2.50,                 -- [GDD] a whiff pays the full cooldown, so spamming it is punished
	stiffStun = 0.70,                     -- [AWF] seconds the stiff-armed tackler is stunned
	stiffSpeedRetain = 0.90,              -- [GDD] small speed cost while the arm is out
	stiffCone = -0.5,                     -- [GDD] only works on a tackler inside the front 120 deg

	-- break score (the design doc's P_break terms, read as a score; >= breakAt breaks the tackle).
	-- Deterministic on purpose: this mode's whole point is that an outcome has a reason, not odds.
	breakBaseWrap = 0.10, breakBaseDive = 0.25,              -- [GDD] a dive trades reach for being easier to break
	momentumK = 0.15,                     -- [GDD] speed wins collisions
	angleK = 0.15,                        -- [GDD] chasing arm tackles are weak
	saMin = 0.15, saScale = 0.30,         -- [GDD] a peak stiff-arm is worth +0.45: the carrier's biggest lever
	spinBonusWrap = 0.20, spinBonusDive = 0.10,              -- [GDD] spin beats wraps, dives beat spins
	fatigue = 0.10,                       -- [GDD] per tackle already broken on this carry: no unstoppable runners
	maxBreaks = 2,                        -- [NEW] and a hard stop: past this many breaks on one carry the counter
	                                      --       matrix stops handing him free wins ("GASSED"). Without it a carrier
	                                      --       with a stiff-arm off cooldown breaks every tackle on a long run.
	breakAt = 0.50,                       -- [GDD] TACKLE_RESOLUTION = "threshold": at or above this, he breaks it
	breakMin = 0.02, breakMax = 0.75,     -- [GDD] clamp, kept so the score still reads like the doc's probability
	breakSpeedDelta = 2.0,                -- [GDD] a wrap from behind by someone this much slower only stumbles him
	jukeAnswer = 0.12,                    -- [NEW] how close to breakAt a wrap has to be for a juke to wriggle out of it

	-- fumbles. Deterministic and rare: a dive, on an exposed ball, at full closing speed, from the blind side.
	fumbleClosing = 0.80,                 -- [GDD] fraction of sprint speed that counts as a big hit (FUMBLE_BIGHIT)
	fumbleBlindCos = -0.5,                -- [GDD] more than 120 deg off the way he was running (FUMBLE_BLINDSIDE)
	recoverRadius = 1.3,                  -- [GDD] metres: who can scoop the loose ball (= Config.possession.grabReach)
	gangWindow = 0.50,                    -- [GDD] a second tackler arriving inside this counts as a gang tackle
}

-- Jump balls / contested catches (Stage 3). A fixed calculation, never a roll: timing, position and reach height.
-- Standing reach is read off each athlete's own rig, so height is earned by jumping well, not bought with an avatar.
Config.contest = {
	radius = 1.1,                         -- [AWF] metres: both sides inside this of the ball at arrival = a contest
	resolveDelay = 0.20,                  -- [GDD] wait this long after arrival so every late input has landed
	jumpSpeed = 6.2, gravity = 22,        -- [AWF] the leap: apex at 0.28 s, 0.87 m off the ground
	perfectBand = 0.06,                   -- [NEW] inside this much of the apex counts as a perfect leap
	timingWindow = 0.22,                  -- [GDD] and the timing score fades to zero this far outside the band
	heightTol = 0.55,                     -- [AWF] metres the ball can be above your hands before height scores zero
	boxoutBonus = 0.15,                   -- [GDD] for being the body between him and the ball
	boxoutCos = 0.5,                      -- [GDD] ...which means inside 60 deg of him, as seen from the ball
	wTiming = 0.45, wPosition = 0.35, wHeight = 0.20,        -- [GDD] must sum to 1
	tieMargin = 0.04,                     -- [GDD] closer than this is a tie, and a tie goes to the offence
	minToCatch = 0.35,                    -- [NEW] under this nobody had enough of it: incomplete rather than a gift
	intThreshold = 0.62,                  -- [GDD] a defender needs this much to come down with it, not just bat it
}
