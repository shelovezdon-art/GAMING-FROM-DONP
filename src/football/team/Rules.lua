-- MIRROR of game.ReplicatedStorage.AWFootball.Rules (ModuleScript), pulled 2026-11-02 (post wave-3, Gauntlet, DRIP, broadcast UI, stance poses, 2K camera).
-- Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1); this copy is the QA/design record.
-- ALLSTAR WORLD · Football rules core (pure functions). Luau port of football-rules.js. Units: metres, seconds.
local Rules = {}
function Rules.clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local Rng = {}
Rng.__index = Rng
function Rules.newRng(seed) return setmetatable({ s = (seed or 1) % 4294967296 }, Rng) end
function Rng:next() self.s = (self.s * 1664525 + 1013904223) % 4294967296; return self.s / 4294967296 end
function Rng:range(a, b) return a + (b - a) * self:next() end
Rules.ROUTES = {
	slant = { label = "Slant", pts = { { 0, 3 }, { 5, 8 }, { 9, 13 } } },
	curl = { label = "Curl", pts = { { 0, 10 }, { 0.6, 8.2 } } },
	post = { label = "Post", pts = { { 0, 10 }, { 5, 18 }, { 9, 27 } } },
	fade = { label = "Fade", pts = { { -1, 8 }, { -2.2, 18 }, { -2.8, 30 } } },
	cross = { label = "Cross", pts = { { 0, 5 }, { 12, 9 }, { 22, 12 } } },
	-- moved up from TeamFootballService 2026-11-02 so the client play-call dashboard can draw every route
	-- (the service re-adds identical copies locally; harmless overwrite)
	flat = { label = "Flat", pts = { { -2, 1 }, { -7, 2.5 }, { -9, 3 } } },
	wheel = { label = "Wheel", pts = { { -3, 1 }, { -6, 4 }, { -6.5, 20 } } },
	seam = { label = "Seam", pts = { { 0, 10 }, { 0.5, 26 } } },
	-- FEATURE WAVE 2 (football-playbook.md §3.3, 2026-11-02): 4 new routes. The GDD writes laterals positive toward
	-- the SIDELINE; this table is positive toward the MIDDLE (routeWorld: x = startX - side * lat), so signs are negated.
	out = { label = "Out", pts = { { 0, 7 }, { -6, 7 } } },                       -- speed out at 7 m to the sideline
	dig = { label = "Dig", pts = { { 0, 10 }, { 8, 10 } } },                      -- square-in at 10 m to the middle
	comeback = { label = "Comeback", pts = { { 0, 12 }, { -2, 10 } }, settle = true }, -- drive 12, back down to 10 (settle: the AI holds at the break instead of extending backward)
	sluggo = { label = "Sluggo", pts = { { 2, 4 }, { 2.5, 6 }, { -0.5, 26 } }, doubleMove = true, fakeBreakIdx = 2 }, -- slant-and-go: the double move (feel-upgrades §3.3.2)
	free = { label = "Free run", pts = {} },
}
Rules.ROUTE_ORDER = { "slant", "curl", "post", "fade", "cross" }
function Rules.routeWorld(routeId, startX, startZ, dir, side)
	local out = {}
	for _, p in ipairs(Rules.ROUTES[routeId].pts) do table.insert(out, { x = startX - side * p[1], z = startZ + dir * p[2] }) end
	return out
end
function Rules.solveThrow(from, to, t, g)
	return { x = (to.x - from.x) / t, y = (to.y - from.y) / t + 0.5 * g * t, z = (to.z - from.z) / t }
end
function Rules.flightTime(dist, cfg)
	local speed = Rules.clamp(dist / 1.0, cfg.qb.throwSpeedMin, cfg.qb.throwSpeedMax)
	return Rules.clamp(dist / speed, cfg.ball.minFlight, cfg.ball.maxFlight)
end
function Rules.resolveTackle(attacker, carrier, now, cfg)
	local T = cfg.tackle
	if not carrier.live or not carrier.hasBall then return "NOT_LIVE" end
	local dx, dz = carrier.x - attacker.x, carrier.z - attacker.z
	local d = math.sqrt(dx * dx + dz * dz)
	local reach = attacker.lunging and T.lungeReach or T.reach
	if d > reach + 1.2 then return "NO_CONTACT" end
	if d > reach then return "WHIFF" end
	local fx, fz = math.sin(attacker.heading), math.cos(attacker.heading)
	local cos = d > 1e-4 and (fx * dx + fz * dz) / d or 1
	if cos < T.facingCos then return "WHIFF" end
	if carrier.immuneUntil and now < carrier.immuneUntil then return "EVADED" end
	local avx, avz, cvx, cvz = attacker.vx or 0, attacker.vz or 0, carrier.vx or 0, carrier.vz or 0
	local nx, nz = 0, 1
	if d > 1e-4 then nx, nz = dx / d, dz / d end
	local closing = (avx - cvx) * nx + (avz - cvz) * nz
	local cs = math.sqrt(cvx * cvx + cvz * cvz)
	local angleCos = cs > 0.5 and -((cvx * nx + cvz * nz) / cs) or 0
	if closing < T.cleanClosingSpeed or angleCos < T.cleanAngleCos then return "WRAP" end
	return "CLEAN_TACKLE"
end
function Rules.catchGrade(timing, cfg)
	local K = cfg.catch
	if timing == nil then return "NONE" end
	if timing < -K.windowEarly then return "EARLY" end
	if timing > K.windowLate then return "LATE" end
	return math.abs(timing + 0.1) < 0.12 and "PERFECT" or "GOOD"
end
function Rules.jumpHeight(t, cfg)
	local J = cfg.jump
	if t == nil or t < 0 then return 0 end
	local h = J.jumpSpeed * t - 0.5 * J.gravity * t * t
	return h > 0 and h or 0
end
function Rules.jumpApexTime(cfg) return cfg.jump.jumpSpeed / cfg.jump.gravity end
function Rules.jumpReaches(timing, cfg)
	if timing == nil then return false end
	return Rules.jumpHeight(-timing, cfg) >= cfg.jump.needHeight
end
local function inWindow(t, K) return t ~= nil and t >= -K.windowEarly and t <= K.windowLate end
function Rules.resolveJumpBall(wr, db, cfg, rng)
	local K, D, J = cfg.catch, cfg.defend, cfg.jump
	local apex = Rules.jumpApexTime(cfg)
	local function err(a) if a.jumped and Rules.jumpReaches(a.timing, cfg) then return math.abs(-a.timing - apex) end return nil end
	local wrErr = err(wr)
	local dbErr = db and err(db) or nil
	local wrIn = wrErr ~= nil and wr.dist <= K.aggressiveReach
	local dbIn = dbErr ~= nil and db.dist <= D.swatReach
	if not wrIn and not dbIn then
		return { result = "INCOMPLETE", detail = (wr.jumped or (db and db.jumped)) and "mistimed the jump" or "nobody went up for it" }
	end
	if wrIn and dbIn then
		local margin = wr.pressed == "aggressive" and J.aggressiveMargin or 0
		if dbErr + margin < wrErr then
			return { result = db.dist <= D.intReach and "INT" or "SWAT", detail = db.dist <= D.intReach and "out-jumped and picked" or "out-jumped, swatted away" }
		end
		return { result = "CATCH", detail = "won the jump ball" }
	end
	if dbIn then return { result = db.dist <= D.intReach and "INT" or "SWAT", detail = db.dist <= D.intReach and "skied for the pick" or "skied and swatted it" } end
	local quality = wr.human and 0.95 or K.cpuBase
	if rng:next() > quality then return { result = "DROP", detail = "came down without it" } end
	return { result = "CATCH", detail = "skied for it" }
end
function Rules.resolveCatch(wr, db, cfg, rng, high)
	local K, D = cfg.catch, cfg.defend
	-- Config flag, not a rewrite: "deterministic" routes to the no-dice model at the bottom of this file; the
	-- quality-roll model below is untouched and stays the default until parity is proven.
	-- Jump balls stay a timing DUEL even in deterministic mode: who met the ball at its apex is the whole contest,
	-- and the deterministic model has no concept of two bodies in the air (reordered 2026-11-02).
	if high then return Rules.resolveJumpBall(wr, db, cfg, rng) end
	if K.model == "deterministic" then return Rules.resolveCatchDeterministic(wr, db, cfg, high) end
	local dbPlay = false
	if db then
		if db.human then dbPlay = db.pressed and inWindow(db.timing, K) and db.dist <= D.swatReach
		else dbPlay = db.dist <= D.swatReach and rng:next() < D.cpuAttemptChance end
	end
	local wrReach, wrQuality = 0, 0
	if wr.human then
		if wr.pressed and inWindow(wr.timing, K) then
			wrReach = wr.pressed == "aggressive" and K.aggressiveReach or K.secureReach
			wrQuality = wr.pressed == "aggressive" and 0.8 or 0.97
		elseif not wr.pressed then wrReach, wrQuality = K.autoReach, K.autoChance
		else wrReach, wrQuality = K.secureReach * 0.6, 0.35 end
	else
		wrReach, wrQuality = K.secureReach, K.cpuBase
		if db and db.dist <= K.contestRadius then wrQuality -= K.cpuContestedPenalty end
	end
	local wrCan = wr.dist <= wrReach
	if dbPlay and (not wrCan or db.dist < wr.dist) then
		local int = db.dist <= D.intReach
		return { result = int and "INT" or "SWAT", detail = int and "defender intercepted" or "defender swatted" }
	end
	if not wrCan then return { result = "INCOMPLETE", detail = wr.dist > wrReach + 1.5 and "ball out of reach" or "just out of reach" } end
	if rng:next() > wrQuality then return { result = "DROP", detail = wr.pressed == "aggressive" and "aggressive catch dropped" or "dropped" } end
	return { result = "CATCH", detail = wr.pressed == "aggressive" and "aggressive catch" or wr.pressed == "secure" and "secure catch" or "caught" }
end
function Rules.yardsBetween(fromZ, toZ, dir, metresPerYard) return math.floor(((toZ - fromZ) * dir) / metresPerYard + 0.5) end

-- ==========================================================================================================
-- IFAF FLAG FOOTBALL 5-ON-5 RULES (ADR-0001). Pure functions: no Instances, no RNG, no os.clock, no yields.
-- Research and sources: design/gdd/football-ruleset.md. One labelled deviation from IFAF: contact.
--
-- SPOT CONVENTION for everything below. A spot is a number of METRES measured from the CURRENT OFFENCE'S OWN
-- GOAL LINE: 0 = its own goal line, cfg.field.lengthM (45.72) = the goal line it is attacking, and
-- cfg.field.lengthM / 2 (22.86) = the middle line. The service converts its world z to this and back; doing
-- the flip in one place is what keeps these functions testable.
--
-- Every function returns a readable reason. Nothing here is decided by a dice roll.
-- ==========================================================================================================

function Rules.middleLine(cfg) return cfg.field.lengthM * 0.5 end
function Rules.goalLine(cfg) return cfg.field.lengthM end

-- The line to gain. [VERIFIED IFAF] There is exactly ONE in a possession, and it is the middle line. Once a
-- series has started beyond the middle there is no line to gain left: the target is the goal line.
function Rules.lineToGain(cfg, seriesStartedBeyondMiddle)
	if seriesStartedBeyondMiddle then
		return Rules.goalLine(cfg), "no line to gain left - four downs to score"
	end
	return Rules.middleLine(cfg), "four downs to cross the middle line"
end

-- Did this dead-ball spot earn a first down? Crossing the middle line is the ONLY earned first down in a
-- possession (an accepted penalty can still mandate one - see Rules.enforcePenalty).
function Rules.isFirstDown(spotM, seriesStartedBeyondMiddle, cfg)
	if seriesStartedBeyondMiddle then
		return false, "already past the middle - no second first down in this possession"
	end
	local mid = Rules.middleLine(cfg)
	if spotM > mid then return true, "crossed the middle line - first down" end
	if spotM == mid then return false, "on the middle line, not beyond it - no first down" end
	return false, ("short of the middle line by %.2f m"):format(mid - spotM)
end

-- Where the next snap happens. [VERIFIED IFAF] Own 5 yd (4.57 m) after every change of possession, touchback,
-- safety and touchdown. No kickoffs, punts or field goals exist, so there is nothing else to resolve.
-- The one exception: an interception return is live, so it is spotted where the ball was declared dead.
-- outcome: "TOUCHDOWN" | "TRY_OVER" | "SAFETY" | "TOUCHBACK" | "TURNOVER_ON_DOWNS" | "INTERCEPTION"
--          | "FUMBLE_LOST" | "START_OF_HALF" | "PUNT" | "FIELD_GOAL" | "KICKOFF"
-- opts.deadSpotOwnM: for INTERCEPTION / FUMBLE_LOST, the dead-ball spot already expressed from the NEW
--                    offence's own goal line.
-- Returns { spotM, possession = "same" | "opponent", reason, firstSeriesBeyondMiddle }
function Rules.nextSnapSpot(outcome, cfg, opts)
	opts = opts or {}
	local own = cfg.series.snapOwnM
	local function at(spot, who, why)
		return { spotM = spot, possession = who, reason = why,
			firstSeriesBeyondMiddle = spot > Rules.middleLine(cfg) }
	end
	if outcome == "KICKOFF" or outcome == "PUNT" or outcome == "FIELD_GOAL" then
		return nil, "this format has no kickoffs, punts or field goals"
	end
	if outcome == "TOUCHDOWN" or outcome == "TRY_OVER" then
		return at(own, "opponent", "after a score: the other team snaps from its own 5")
	end
	if outcome == "SAFETY" then
		return at(own, "opponent", "safety: the scoring team snaps from its own 5")
	end
	if outcome == "TOUCHBACK" then
		return at(own, "same", "touchback: snap from the own 5")
	end
	if outcome == "TURNOVER_ON_DOWNS" then
		return at(own, "opponent", "turnover on downs: the defence takes over at its own 5")
	end
	if outcome == "START_OF_HALF" then
		return at(own, "same", "start of a half: snap from the own 5")
	end
	if outcome == "INTERCEPTION" or outcome == "FUMBLE_LOST" then
		local spot = opts.deadSpotOwnM
		if spot == nil then
			return at(own, "opponent", "no dead-ball spot supplied: falling back to the own 5")
		end
		spot = Rules.clamp(spot, 0, Rules.goalLine(cfg))
		return at(spot, "opponent", "the return was live: spotted where the ball was declared dead")
	end
	return nil, ("unknown outcome '%s'"):format(tostring(outcome))
end

-- Points for one scoring event. [VERIFIED IFAF]
-- event: "TOUCHDOWN" | "TRY_1" | "TRY_2" | "DEFENSIVE_TRY_TOUCHDOWN" | "SAFETY" | "SAFETY_ON_TRY"
function Rules.scoreFor(event, cfg)
	local S = cfg.scoring
	if event == "TOUCHDOWN" then return S.touchdown, "touchdown" end
	if event == "TRY_1" then return S.try1, "try from the 5 (pass only)" end
	if event == "TRY_2" then return S.try2, "try from the 10 (run or pass)" end
	if event == "DEFENSIVE_TRY_TOUCHDOWN" then return S.defensiveTryTouchdown, "defence scored on the try" end
	if event == "SAFETY" then return S.safety, "safety" end
	if event == "SAFETY_ON_TRY" then return S.safetyOnTry, "safety on a try" end
	return 0, ("unknown scoring event '%s'"):format(tostring(event))
end

-- Where a declared try is snapped from. The offence DECLARES 1 or 2 before the snap: that declaration is the
-- decision, and it sets both the spot and whether running is legal.
function Rules.trySpot(declared, cfg)
	local S = cfg.scoring
	if declared == 2 then return S.try2SpotM, "two-point try from the 10 - run or pass" end
	return S.try1SpotM, "one-point try from the 5 - pass only"
end

-- Resolve a try. [VERIFIED IFAF] The 1-pointer from the 5 is PASS ONLY; the 2-pointer from the 10 may be run
-- or pass; a defensive touchdown on a try is worth 2; a safety on a try is 1 to the opponent.
-- declared: 1 | 2. playType: "pass" | "run". result: "SCORED" | "FAILED" | "DEFENSIVE_TOUCHDOWN" | "SAFETY"
-- Returns { points, to = "offence" | "defence", legal, reason }
function Rules.resolveTry(declared, playType, result, cfg)
	local S = cfg.scoring
	local two = (declared == 2)
	-- written long on purpose: `two and S.try2PassOnly or S.try1PassOnly` silently reads the 1-pt flag whenever
	-- try2PassOnly is false, which is exactly its real value
	local passOnly = if two then S.try2PassOnly == true else S.try1PassOnly == true
	if result == "DEFENSIVE_TOUCHDOWN" then
		return { points = S.defensiveTryTouchdown, to = "defence", legal = true,
			reason = "defence returned the try - 2 points" }
	end
	if result == "SAFETY" then
		return { points = S.safetyOnTry, to = "defence", legal = true,
			reason = "safety on a try - 1 point to the defence" }
	end
	if passOnly and playType == "run" then
		return { points = 0, to = "offence", legal = false,
			reason = "declared the 1-point try from the 5, which is pass only - a run cannot score it" }
	end
	if result ~= "SCORED" then
		return { points = 0, to = "offence", legal = true,
			reason = two and "two-point try failed" or "one-point try failed" }
	end
	return { points = two and S.try2 or S.try1, to = "offence", legal = true,
		reason = two and ("two-point try good on a " .. tostring(playType)) or "one-point try good on a pass" }
end

-- Enforce one of the five penalties. [VERIFIED IFAF] Two conventions, both encoded here:
--   1. enforcement is FROM THE LINE OF SCRIMMAGE unless the foul is marked a spot foul;
--   2. yardage HALVES if it exceeds half the distance to the goal.
-- There are no 15-yard penalties in this format, so nothing here can move the ball further than 10 yd.
-- foul: a key of cfg.penalty.fouls, or the foul table itself.
-- spotOfFoulM / lineOfScrimmageM: metres from the offence's own goal line.
-- distanceToGoalM: optional override; by default it is measured from the enforcement basis.
-- Returns { newSpotM, yardsApplied, firstDown, lossOfDown, halved, basis, label, reason }
function Rules.enforcePenalty(foul, spotOfFoulM, lineOfScrimmageM, distanceToGoalM, cfg)
	local P = cfg.penalty
	local F = type(foul) == "table" and foul or P.fouls[foul]
	if F == nil then
		return nil, ("unknown foul '%s' - this format has exactly five"):format(tostring(foul))
	end
	local basis = F.spot and spotOfFoulM or lineOfScrimmageM
	local goal = Rules.goalLine(cfg)
	local wanted = F.yards * cfg.YARD                      -- metres, signed: + toward the goal attacked
	local applied, halved = wanted, false
	if wanted > 0 then
		local toGoal = distanceToGoalM or (goal - basis)
		local cap = toGoal * 0.5
		if P.halfTheDistance and wanted > cap then applied, halved = cap, true end
	elseif wanted < 0 then
		local toOwnGoal = basis                            -- the offence's own goal line is spot 0
		local cap = toOwnGoal * 0.5
		if P.halfTheDistance and -wanted > cap then applied, halved = -cap, true end
	end
	local newSpot = Rules.clamp(basis + applied, 0, goal)
	local reason = ("%s: %s%.0f yd from the %s"):format(F.label, F.yards > 0 and "+" or "", F.yards,
		F.spot and "spot of the foul" or "line of scrimmage")
	if halved then reason = reason .. ", halved to half the distance to the goal" end
	if F.firstDown then reason = reason .. ", automatic first down" end
	if F.lossOfDown then reason = reason .. ", loss of down" end
	return { newSpotM = newSpot, yardsApplied = applied / cfg.YARD, firstDown = F.firstDown == true,
		lossOfDown = F.lossOfDown == true, halved = halved, basis = basis, label = F.label, reason = reason }
end

-- Overtime. [VERIFIED IFAF] A period is a two-series shootout from the MIDDLE LINE with no first down
-- available at midfield; if the defence scores in the first series the period ends immediately.
-- [VERIFIED NFL FLAG] From period 2 on it collapses to a single try play from the 5.
-- No charged timeouts in overtime.
-- st: { period = 1.., seriesPlayed = 0.., defenceScoredInFirstSeries = bool, score = { a, b } }
-- Returns { spotM, seriesRemaining, firstDownAvailable, onePlayTry, periodOver, timeouts, reason }
function Rules.overtimeState(st, cfg)
	local O = cfg.overtime
	local period = math.max(1, st.period or 1)
	local played = st.seriesPlayed or 0
	if period > O.collapseAfterPeriod then
		local over = played >= O.seriesPerPeriod
		return { spotM = O.collapseSpotM, seriesRemaining = math.max(0, O.seriesPerPeriod - played),
			firstDownAvailable = false, onePlayTry = true, periodOver = over, timeouts = O.timeouts,
			reason = ("overtime period %d: one try play from the 5, no first downs, no timeouts"):format(period) }
	end
	if st.defenceScoredInFirstSeries and played >= 1 then
		return { spotM = Rules.middleLine(cfg), seriesRemaining = 0, firstDownAvailable = false,
			onePlayTry = false, periodOver = true, timeouts = O.timeouts,
			reason = "the defence scored in the first series - the period ends there" }
	end
	local remaining = math.max(0, O.seriesPerPeriod - played)
	return { spotM = Rules.middleLine(cfg), seriesRemaining = remaining,
		firstDownAvailable = O.firstDownAvailable == true, onePlayTry = false,
		periodOver = remaining <= 0, timeouts = O.timeouts,
		reason = ("overtime period %d, series %d of %d from the middle line - no first down available at midfield")
			:format(period, math.min(played + 1, O.seriesPerPeriod), O.seriesPerPeriod) }
end

-- Does the clock stop for this event? [VERIFIED IFAF] Only inside the final window of each half.
-- event: a key of cfg.clock.stopOn. secondsLeftInHalf: seconds.
function Rules.clockStops(event, secondsLeftInHalf, cfg)
	local C = cfg.clock
	if not C.stopOn[event] then return false, ("'%s' never stops the clock"):format(tostring(event)) end
	if secondsLeftInHalf > C.stopClockWindowSeconds then
		return false, ("running clock: %.0f s left, stop rules start at %d s"):format(secondsLeftInHalf, C.stopClockWindowSeconds)
	end
	return true, ("inside the final %d s: the clock stops for %s"):format(C.stopClockWindowSeconds, tostring(event))
end

-- Which of the three coverage states a cushion puts a defender in. [VERIFIED] control pedal at 75% speed ->
-- speed pedal once the cushion is threatened -> man turn once the cushion is broken. The distance decides it.
function Rules.pedalState(cushionM, cfg)
	local V = cfg.coverage
	if cushionM <= V.brokenAtM then
		return "manTurn", ("cushion broken at %.2f m - flip the hips"):format(cushionM)
	end
	if cushionM <= V.threatenedAtM then
		return "speedPedal", ("cushion threatened at %.2f m - speed pedal"):format(cushionM)
	end
	return "controlPedal", ("cushion safe at %.2f m - control pedal at %d%% speed")
		:format(cushionM, math.floor(V.controlPedalFraction * 100 + 0.5))
end

-- Leverage. [VERIFIED] Deep help means you take the outside eye; no help means the inside eye.
function Rules.leverage(hasDeepHelp, cfg)
	if hasDeepHelp then return cfg.coverage.leverageWithHelp, "deep help behind you - take his outside eye" end
	return cfg.coverage.leverageWithoutHelp, "no help behind you - take his inside eye and protect the deep ball"
end

-- ==========================================================================================================
-- DETERMINISTIC CATCH (behind Config.catch.model == "deterministic"). Same shape as AWPractice.Receive.judge:
-- a sum of readable terms, a stated limit, and an outcome that always carries the reason it happened.
-- No RNG. Nothing here is pay-affected: every term is geometry or input.
--
-- Basis [VERIFIED technique]: above the waist the fingers point up and the thumbs touch; below the waist the
-- hands turn down and the pinkies meet. That switch at the waist is the real, teachable, binary rule, so a
-- ball arriving near chest height is free and one arriving at or below the waist costs more.
-- [ASSUMPTION] Using that switch as a DIFFICULTY curve, and the over-the-shoulder / contested / one-handed
-- multipliers, is coaching lore that could not be sourced. Tuning, not fact.
--
-- c = { arrivalYM  = ball height above the receiver's feet at arrival (metres),
--       chestYM    = his chest height (optional; defaults to catch.det.waistM + comfortBandM),
--       relSpeed   = ball speed relative to his hands (m/s),
--       facingDeg  = angle between ball velocity and his facing (degrees, 0 = coming straight at him),
--       hands      = "two" | 1 | -1 | nil (nil = body only),
--       stretch    = 0..1 fraction of full reach used (optional),
--       overShoulder = bool, contested = bool }
-- Returns { result = "CATCH" | "DROP" | "INCOMPLETE", detail, difficulty, threshold, terms }
function Rules.judgeCatchDeterministic(c, cfg)
	local K = cfg.catch
	local T = K.det
	local terms = {}
	local chest = c.chestYM or (T.waistM + T.comfortBandM)

	-- height: free inside the comfort band around the chest; a scoop at or below the waist costs more.
	local dy = math.abs((c.arrivalYM or chest) - chest)
	local outside = math.max(0, dy - T.comfortBandM)
	local belowWaist = (c.arrivalYM or chest) < T.waistM
	terms.height = outside * T.heightK * (belowWaist and T.belowWaistK or 1)

	-- arrival speed: free up to the comfort speed, then linear.
	terms.speed = math.max(0, (c.relSpeed or 0) - T.comfortSpeedMps) / T.speedScale

	-- facing: a ball across the body is harder than one coming straight at you.
	terms.facing = math.max(0, (math.abs(c.facingDeg or 0) - T.facingFreeDeg)) / 90 * T.facingK

	terms.overShoulder = c.overShoulder and T.overShoulderAdd or 0
	terms.contested = c.contested and T.contestedAdd or 0

	local difficulty = terms.height + terms.speed + terms.facing + terms.overShoulder + terms.contested
	if c.hands ~= "two" then
		difficulty *= T.oneHandMul
		terms.oneHandMul = T.oneHandMul
	end
	if c.stretch and c.stretch > 0.85 then
		terms.stretch = (c.stretch - 0.85) * 2.2
		difficulty += terms.stretch
	end

	local function out(result, detail)
		return { result = result, detail = detail, difficulty = difficulty, threshold = T.threshold, terms = terms }
	end
	if difficulty < T.threshold then
		if c.hands == nil then return out("CATCH", "body catch - trapped it against the chest") end
		if c.hands ~= "two" then return out("CATCH", "one-handed grab") end
		if belowWaist then return out("CATCH", "pinkies down - scooped it off the grass") end
		if c.overShoulder then return out("CATCH", "over the shoulder") end
		return out("CATCH", "thumbs together - caught it clean")
	end
	-- past the threshold: close is a drop you can feel, far is a ball nobody was catching.
	if difficulty <= T.threshold + T.dropBandM then
		local worst, worstName = 0, "it"
		for name, v in pairs(terms) do
			if name ~= "oneHandMul" and type(v) == "number" and v > worst then worst, worstName = v, name end
		end
		local why = ({ height = "it was out of his frame", speed = "it arrived too hot",
			facing = "it came across his body", overShoulder = "he had to find it late",
			contested = "the defender was all over him", stretch = "fingertips" })[worstName] or "he lost it"
		return out("DROP", ("dropped - %s"):format(why))
	end
	return out("INCOMPLETE", "never a catch - the ball was past what anyone could hold")
end

-- Adapter so the existing single call site keeps working when the flag is flipped. Maps the roll model's
-- receiver/defender tables onto the deterministic model's inputs and returns the same { result, detail } shape
-- the services already branch on, with difficulty attached for the debug overlay.
function Rules.resolveCatchDeterministic(wr, db, cfg, high)
	local K, D = cfg.catch, cfg.defend
	local reach = (wr.pressed == "aggressive") and K.aggressiveReach or (wr.pressed and K.secureReach or K.autoReach)
	-- a defender close enough to play the ball and closer to it than the receiver takes it away first
	if db and db.dist and db.dist <= D.swatReach and (wr.dist > reach or db.dist < wr.dist) then
		local int = db.dist <= D.intReach
		return { result = int and "INT" or "SWAT", detail = int and "defender got there first and picked it" or "defender got there first and swatted it" }
	end
	if wr.dist and wr.dist > reach then
		return { result = "INCOMPLETE",
			detail = wr.dist > reach + 1.5 and "ball out of reach" or "just out of reach" }
	end
	local j = Rules.judgeCatchDeterministic({
		arrivalYM = wr.arrivalYM or (high and cfg.jump.highCatchHeight or cfg.ball.catchHeight),
		chestYM = wr.chestYM,
		relSpeed = wr.relSpeed or 0,
		facingDeg = wr.facingDeg or 0,
		hands = wr.hands or (wr.pressed and "two" or nil),
		stretch = wr.stretch or (wr.dist and reach > 0 and wr.dist / reach or nil),
		overShoulder = wr.overShoulder,
		contested = wr.contested or (db ~= nil and db.dist ~= nil and db.dist <= K.contestRadius),
	}, cfg)
	return { result = j.result == "CATCH" and "CATCH" or j.result, detail = j.detail,
		difficulty = j.difficulty, threshold = j.threshold, terms = j.terms }
end

return Rules
