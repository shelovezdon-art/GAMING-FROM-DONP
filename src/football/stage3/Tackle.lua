-- ALLSTAR WORLD · Tackle: the geometry and rules of bringing a ball carrier down, shared by the server (which decides)
-- and every client (which draws the lunge and the debug overlay). Pure maths in metres and seconds: plain numbers only,
-- no Vector3, no CFrame, no Instances, so the whole thing runs in a unit test with no Roblox at all.
--
-- Nothing here is random. Every outcome carries a reason string you can read on screen, the same way Receive.judge does.
-- Where the design doc asks for a dice roll (P_break, P_fumble) this module reads the same terms as a SCORE and
-- compares it to a threshold, which is the doc's own `TACKLE_RESOLUTION = "threshold"` option. Two players who do
-- the same thing at the same moment always get the same result, and the reason says which term decided it.
--
-- Reach is NOT a constant. The caller measures the tackler's own arm (shoulder -> elbow -> palm) off the R15 rig the
-- same way Receive.rig does and passes it in as `armReachM`, so a long-armed avatar really does tackle from further
-- out and a small one doesn't. This module only adds the margins: the carrier's torso the arms have to get around,
-- the network allowance, and the extra stretch a dive buys.
--
-- Two kinds of tackle:
--   wrap   tap: short startup, must be facing the carrier, safe to miss (a slowed recovery), but loses to a
--          stiff-arm in front and to a spin
--   dive   a committed lunge: covers diveSpeed * diveTime of ground and a wider arc, beats a stiff-arm and a spin,
--          but a well-timed juke makes it miss and a miss leaves you on the floor
--
-- One carry's worth of carrier state, owned by the server, passed in as `carrier`:
--   { speed, vx, vz, spinUntil, jukeUntil, stiffAt, securingUntil, stumbleUntil, broken }
-- `broken` is the number of tackles already broken on this carry: per-play fatigue, so one runner cannot break
-- every tackle in a row.
local Tackle = {}

Tackle.WRAP = "wrap"
Tackle.DIVE = "dive"

-- outcome codes (the server switches on these; the names are carried over from AWFootball.Rules.resolveTackle so the
-- older 1v1 mode and this one talk about the same events)
Tackle.NOT_LIVE = "NOT_LIVE"       -- nobody is carrying the ball, or the carrier is you
Tackle.NO_CONTACT = "NO_CONTACT"   -- never got near: no commitment spent
Tackle.WHIFF = "WHIFF"             -- in range but missed (angle, or the carrier had just juked away)
Tackle.WRAPPED = "WRAP"            -- hands on him: he is dragged and has breakWindow to answer
Tackle.TACKLED = "TACKLED"         -- down, play over
Tackle.FUMBLE = "FUMBLE"           -- down, and the ball is out
Tackle.BROKEN = "BROKEN"           -- the carrier beat it outright; the tackler pays
Tackle.STUMBLE = "STUMBLE"         -- the carrier stays up but loses his feet for a moment
Tackle.INCOMPLETE = "INCOMPLETE"   -- hit before he ever secured the catch: not a tackle, an incompletion

-------------------------------------------------------------------------------------------------- reach
-- metres a tackler of this build can reach, measured from his own root part, flat.
-- armReachM: shoulder -> palm, from the rig (Receive.rig gives it in studs; divide by Config.S first).
function Tackle.reach(armReachM, kind, cfg)
	local r = armReachM + cfg.bodySlack + cfg.latencySlack
	if kind == Tackle.DIVE then r += cfg.diveExtra end
	return r
end

-- how far a dive travels, so the server can draw it and the client can predict it
function Tackle.diveTravel(cfg) return cfg.diveSpeed * cfg.diveTime end

-------------------------------------------------------------------------------------------------- geometry
-- g = { dx, dz   carrier minus tackler, metres (flat)
--       fx, fz   where the tackler is facing (unit, flat)
--       tvx, tvz tackler velocity, m/s
--       cvx, cvz carrier velocity, m/s }
-- returns a table of the four numbers every rule below is written against.
function Tackle.geometry(g)
	local d = math.sqrt(g.dx * g.dx + g.dz * g.dz)
	local nx, nz = 0, 1
	if d > 1e-4 then nx, nz = g.dx / d, g.dz / d end
	local facingCos = math.clamp(g.fx * nx + g.fz * nz, -1, 1)          -- +1 = carrier straight ahead of the tackler
	local closing = (g.tvx - g.cvx) * nx + (g.tvz - g.cvz) * nz          -- m/s the gap is shrinking at
	local cs = math.sqrt(g.cvx * g.cvx + g.cvz * g.cvz)
	-- alphaCos: +1 = the tackler is straight in front of where the carrier is running (head-on),
	--           -1 = the tackler is directly behind him (blindside). cos(120 deg) = -0.5.
	local alphaCos = (cs > 0.5) and math.clamp(-((g.cvx * nx + g.cvz * nz) / cs), -1, 1) or 0
	return { d = d, nx = nx, nz = nz, facingCos = facingCos, closing = closing, carrierSpeed = cs, alphaCos = alphaCos }
end

-------------------------------------------------------------------------------------------------- the carrier's answers
-- A stiff-arm is live for stiffWindow seconds and is strongest in the middle of it (stiffPeak). Returns 0..1, or nil
-- if there is no live stiff-arm. `age` = seconds between the press and the contact.
function Tackle.stiffArmQuality(age, cfg)
	if age == nil or age < 0 or age > cfg.stiffWindow then return nil end
	return math.clamp(1 - math.abs(age - cfg.stiffPeak) / cfg.stiffPeak, 0, 1)
end

-- does the stiff-arm point at this tackler? Only the front arc counts (stiffCone is the cosine limit, e.g. -0.5 = 120 deg).
function Tackle.stiffArmReaches(geo, cfg)
	return geo.alphaCos >= cfg.stiffCone
end

-------------------------------------------------------------------------------------------------- the break score
-- Same terms as the design doc's P_break, read as a score. breakAt (0.5) is the line; anything at or above it breaks.
-- Returns score, parts, worst (the single biggest contributor, used for the reason text).
function Tackle.breakScore(kind, geo, carrier, saQ, spinning, cfg, sprint)
	local m = math.clamp((geo.carrierSpeed - math.max(geo.closing, 0)) / sprint, -1, 1)
	local parts = {
		base = (kind == Tackle.DIVE) and cfg.breakBaseDive or cfg.breakBaseWrap,
		momentum = cfg.momentumK * m,
		angle = cfg.angleK * (1 - geo.alphaCos) / 2,
		stiff = saQ and (cfg.saMin + cfg.saScale * saQ) or 0,
		spin = spinning and ((kind == Tackle.DIVE) and cfg.spinBonusDive or cfg.spinBonusWrap) or 0,
		fatigue = -cfg.fatigue * (carrier.broken or 0),
	}
	local total = 0
	local worst, worstV = "base", -math.huge
	for k, v in pairs(parts) do
		total += v
		if v > worstV then worst, worstV = k, v end
	end
	return math.clamp(total, cfg.breakMin, cfg.breakMax), parts, worst
end

local BREAK_TEXT = {
	base = "SHOOK HIM OFF",
	momentum = "RAN THROUGH IT",
	angle = "ARM TACKLE FROM BEHIND · BROKE IT",
	stiff = "STIFF-ARM · BROKE IT",
	spin = "SPUN OUT OF IT",
	fatigue = "BROKE IT",
}

-------------------------------------------------------------------------------------------------- fumbles
-- Rare by construction, never by a dice roll. Every one of these has to be true at the same instant, and each one is
-- something both players can see happen:
--   it was a dive (a wrap never strips the ball)
--   the carrier was spinning, or still recovering from a juke, so the ball was away from his body
--   the hit was a big one: closing speed at least fumbleClosing of a full sprint
--   it came from his blind side (more than 120 degrees off the way he was running)
-- Returns true plus the reason, or false plus nil.
function Tackle.fumbles(kind, geo, exposed, cfg, sprint)
	if kind ~= Tackle.DIVE then return false, nil end
	if not exposed then return false, nil end
	if geo.closing < cfg.fumbleClosing * sprint then return false, nil end
	if geo.alphaCos >= cfg.fumbleBlindCos then return false, nil end
	return true, "STRIPPED ON THE BLIND SIDE · BALL'S OUT"
end

-------------------------------------------------------------------------------------------------- the decision
-- input = {
--   kind      = Tackle.WRAP | Tackle.DIVE
--   geo       = Tackle.geometry(...)
--   reach     = Tackle.reach(...)        metres, already includes the margins
--   live      = true if the carrier has the ball and is a legal target
--   age       = seconds since the lunge / wrap started (a wrap cannot connect before cfg.wrapStartup)
--   carrier   = { speed, spinUntil, jukeUntil, stiffAge, securingUntil, stumbleUntil, broken }  (times as ages/remaining)
--   sprint    = Config.move.sprint, for normalising the momentum term
-- }
-- The counter matrix is checked first, in order, because the design doc states those cells as rules rather than odds.
-- Anything the matrix does not decide falls through to the break score.
--
-- returns res = { outcome, reason, score, parts, decidedBy, fumble }
function Tackle.resolve(input, cfg)
	local geo, c, kind = input.geo, input.carrier or {}, input.kind
	local sprint = input.sprint or 7.8

	if not input.live then
		return { outcome = Tackle.NOT_LIVE, reason = "NOBODY'S CARRYING IT", decidedBy = "live" }
	end
	-- out of range entirely: the attempt costs the cooldown but no commitment penalty
	if geo.d > input.reach + cfg.missMargin then
		return { outcome = Tackle.NO_CONTACT, reason = "NOTHING THERE · TOO FAR", decidedBy = "range" }
	end
	if geo.d > input.reach then
		return { outcome = Tackle.WHIFF, reason = ("JUST SHORT · %.1f m OUT OF REACH"):format(geo.d - input.reach), decidedBy = "range" }
	end
	local cos = (kind == Tackle.DIVE) and cfg.diveCos or cfg.wrapCos
	if geo.facingCos < cos then
		return { outcome = Tackle.WHIFF, reason = "WRONG ANGLE · HE WENT PAST YOU", decidedBy = "angle" }
	end
	if kind == Tackle.WRAP and (input.age or 1) < cfg.wrapStartup then
		return { outcome = Tackle.NO_CONTACT, reason = "ARMS WEREN'T CLOSED YET", decidedBy = "startup" }
	end

	-- a hit on someone who has not pulled the catch in yet is an incompletion, not a tackle
	if (c.securingUntil or 0) > 0 then
		return { outcome = Tackle.INCOMPLETE, reason = "HIT BEFORE HE SECURED IT · INCOMPLETE", decidedBy = "securing" }
	end
	-- gang tackle / already off his feet: any contact finishes it
	if (c.stumbleUntil or 0) > 0 then
		local fum, why = Tackle.fumbles(kind, geo, true, cfg, sprint)
		return { outcome = fum and Tackle.FUMBLE or Tackle.TACKLED, reason = fum and why or "HE WAS ALREADY STUMBLING · BROUGHT DOWN",
			decidedBy = "stumbling", fumble = fum }
	end
	-- a juke that landed moves him out from under the tackle: the geometry usually misses, and when it doesn't, this does
	if (c.jukeUntil or 0) > 0 then
		return { outcome = Tackle.WHIFF, reason = "JUKED YOU OUT OF YOUR BOOTS", decidedBy = "juke" }
	end

	local spinning = (c.spinUntil or 0) > 0
	local saQ = Tackle.stiffArmQuality(c.stiffAge, cfg)
	if saQ and not Tackle.stiffArmReaches(geo, cfg) then saQ = nil end   -- you cannot stiff-arm someone behind you
	if kind == Tackle.DIVE then saQ = nil end                            -- a dive goes in under the arm: it ignores it

	-- Per-play fatigue, the hard half. The counter-matrix cells below hand the carrier a free win, so without this a
	-- runner with a stiff-arm off cooldown would break every tackle on one carry. Past maxBreaks he is gassed and
	-- the matrix stops rescuing him; the score path (which carries the softer `fatigue` term) still applies.
	local gassed = (c.broken or 0) >= cfg.maxBreaks

	-- counter matrix, from the design doc's table
	if kind == Tackle.WRAP and saQ and not gassed then
		return { outcome = Tackle.BROKEN, reason = ("STIFF-ARM · PUT HIM ON THE FLOOR (%.0f%%)"):format(saQ * 100),
			decidedBy = "matrix:stiffArmVsWrap", stunTackler = cfg.stiffStun, score = 1, parts = nil }
	end
	if kind == Tackle.WRAP and spinning and not gassed then
		return { outcome = Tackle.BROKEN, reason = "SPUN OUT OF THE WRAP", decidedBy = "matrix:spinVsWrap",
			carrierStumble = cfg.stumble, score = 1 }
	end
	if gassed and (saQ or spinning) and kind == Tackle.WRAP then
		return { outcome = Tackle.WRAPPED, reason = ("GASSED · %d BROKEN ALREADY, NOTHING LEFT"):format(c.broken or 0),
			decidedBy = "fatigue:gassed", drag = cfg.wrapDrag, breakWindow = cfg.breakWindow }
	end
	if kind == Tackle.DIVE and spinning then
		local fum, why = Tackle.fumbles(kind, geo, true, cfg, sprint)
		return { outcome = fum and Tackle.FUMBLE or Tackle.TACKLED,
			reason = fum and why or "DOVE THROUGH THE SPIN · BROUGHT HIM DOWN", decidedBy = "matrix:diveVsSpin", fumble = fum }
	end
	-- momentum break: a wrap from behind by someone the carrier is pulling away from only knocks him off balance
	if kind == Tackle.WRAP and geo.alphaCos < cfg.fumbleBlindCos
		and (geo.carrierSpeed - math.max(geo.closing, 0)) > cfg.breakSpeedDelta then
		return { outcome = Tackle.STUMBLE, reason = ("RAN OUT OF THE ARM TACKLE · %.1f m/s FASTER"):format(geo.carrierSpeed - math.max(geo.closing, 0)),
			decidedBy = "matrix:momentumBreak", carrierStumble = cfg.stumble }
	end

	-- everything else: the score decides, and the reason names the term that decided it
	local score, parts, worst = Tackle.breakScore(kind, geo, c, saQ, spinning, cfg, sprint)
	if score >= cfg.breakAt then
		return { outcome = Tackle.BROKEN, reason = BREAK_TEXT[worst] or "BROKE THE TACKLE", score = score, parts = parts,
			decidedBy = "score:" .. worst, carrierStumble = (worst == "momentum") and 0 or cfg.stumble * 0.5 }
	end
	-- it held. A wrap drags him down over wrapDrag seconds (he gets breakWindow to answer); a dive finishes it now.
	if kind == Tackle.WRAP then
		return { outcome = Tackle.WRAPPED, reason = "WRAPPED UP", score = score, parts = parts, decidedBy = "score:held",
			drag = cfg.wrapDrag, breakWindow = cfg.breakWindow }
	end
	local exposed = spinning or ((c.jukeRecoveryUntil or 0) > 0)
	local fum, why = Tackle.fumbles(kind, geo, exposed, cfg, sprint)
	return { outcome = fum and Tackle.FUMBLE or Tackle.TACKLED, reason = fum and why or
		((geo.closing >= cfg.fumbleClosing * sprint) and "BIG HIT · DOWN HE GOES" or "WRAPPED AND DOWN"),
		score = score, parts = parts, decidedBy = "score:held", fumble = fum }
end

-- what the carrier's re-answer to a wrap does. move = "juke" | "spin" | "stiffarm", within res.breakWindow.
-- Deterministic: a spin or a stiff-arm beats a wrap outright (the matrix says so), a juke only shakes it loose if the
-- score was close. Returns broke (bool), reason.
function Tackle.answerWrap(move, score, broken, cfg)
	if (broken or 0) >= cfg.maxBreaks then
		return false, ("GASSED · %d BROKEN ALREADY, NOTHING LEFT"):format(broken or 0)
	end
	if move == "spin" then return true, "SPUN FREE" end
	if move == "stiffarm" then return true, "STIFF-ARMED HIM OFF" end
	if move == "juke" then
		if score >= cfg.breakAt - cfg.jukeAnswer then return true, "WRIGGLED OUT OF IT" end
		return false, "COULDN'T SHAKE HIM"
	end
	return false, "NO ANSWER · TAKEN DOWN"
end

-- the miss penalty a tackler pays, in seconds. `grounded` > 0 means a whiffed dive: on the floor, out of the play.
function Tackle.missPenalty(kind, outcome, cfg)
	if outcome == Tackle.NO_CONTACT then return { recover = 0, grounded = 0 } end
	if kind == Tackle.DIVE then return { recover = cfg.diveMiss, grounded = cfg.grounded } end
	return { recover = cfg.wrapMiss, grounded = 0 }
end

-- per-play fatigue: the number to store back on the carrier after a break
function Tackle.fatigueAfter(broken) return (broken or 0) + 1 end

return Tackle
