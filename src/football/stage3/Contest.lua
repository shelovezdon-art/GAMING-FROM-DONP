-- ALLSTAR WORLD · Contest: who comes down with a ball that two people can both get to (a jump ball / contested catch).
-- Pure maths in metres and seconds: plain numbers, no Vector3, no Instances, so it unit-tests with no Roblox at all.
--
-- There is no dice roll here, on purpose. Three things are measured, each 0..1, and added with fixed weights:
--   timing   0.45  when you pressed JUMP relative to the moment the ball arrives. Pure input skill, so it weighs most.
--   position 0.35  how close your hands are to where the ball actually is, plus a box-out bonus for being the one
--                  between your opponent and the ball. This is what route running and coverage earn you.
--   height   0.20  only bites when the ball is above the hands you got up there, so it punishes a bad jump rather
--                  than rewarding a tall avatar: standing reach comes from the player's own rig, same as Receive.
-- The weights live in Config.contest so they can be retuned without touching this file.
--
-- Ties go to the offence. That is the real rule (simultaneous possession is the receiver's ball) and it also means a
-- defender has to actually win the contest rather than merely match it.
--
-- Reach is measured, not assumed: the caller reads the shoulder height and arm length off the R15 rig exactly the way
-- Receive.rig does and passes `standReach` in metres (shoulder height + arm, i.e. how high the fingertips are with
-- both feet on the grass).
local Contest = {}

-------------------------------------------------------------------------------------------------- the jump
-- Time from the press to the top of the jump.
function Contest.apex(cfg) return cfg.jumpSpeed / cfg.gravity end

-- How high the jump itself is, at its peak.
function Contest.jumpPeak(cfg) return cfg.jumpSpeed * cfg.jumpSpeed / (2 * cfg.gravity) end

-- Where the fingertips are, `tau` seconds after the press (metres above the grass). tau = nil means never jumped.
-- A parabola that starts at the standing reach, peaks at the apex, and is back down two apexes later.
function Contest.handHeight(standReach, tau, cfg)
	if tau == nil or tau < 0 then return standReach end
	local ap = Contest.apex(cfg)
	if tau > 2 * ap then return standReach end
	local k = (tau - ap) / ap
	return standReach + Contest.jumpPeak(cfg) * math.max(0, 1 - k * k)
end

-------------------------------------------------------------------------------------------------- one contestant
-- p = { name, side = "offense" | "defense", tau = seconds since their JUMP press at ball arrival (nil = no jump),
--       dist = metres from their catch point to where the ball is, standReach = metres, boxout = bool }
-- ballHeight = metres above the grass at arrival
-- returns score, parts
function Contest.score(p, ballHeight, cfg)
	local timing = 0
	if p.tau ~= nil then
		local off = math.abs(p.tau - Contest.apex(cfg))
		timing = math.clamp(1 - math.max(0, off - cfg.perfectBand) / cfg.timingWindow, 0, 1)
	end
	local position = math.clamp(1 - p.dist / cfg.radius + (p.boxout and cfg.boxoutBonus or 0), 0, 1)
	local hand = Contest.handHeight(p.standReach, p.tau, cfg)
	local height = math.clamp(1 - math.max(0, ballHeight - hand) / cfg.heightTol, 0, 1)
	local parts = { timing = timing, position = position, height = height, hand = hand }
	local total = cfg.wTiming * timing + cfg.wPosition * position + cfg.wHeight * height
	return total, parts
end

-- Is `a` boxing `b` out? Closer to the ball AND standing between them: the angle from the ball to each of them is
-- small, so a is in b's way. aAng / bAng are the bearings (radians) of each player as seen from the ball.
function Contest.boxout(a, b, cfg)
	if not (a and b) then return false end
	if a.dist >= b.dist then return false end
	if a.ang == nil or b.ang == nil then return true end           -- no bearings given: closer is enough
	local d = math.abs(a.ang - b.ang) % (math.pi * 2)
	if d > math.pi then d = math.pi * 2 - d end
	return math.cos(d) >= cfg.boxoutCos
end

-------------------------------------------------------------------------------------------------- the contest
local function best(list, ballHeight, cfg)
	local bp, bs, bparts
	for _, p in ipairs(list) do
		local s, parts = Contest.score(p, ballHeight, cfg)
		if not bp or s > bs then bp, bs, bparts = p, s, parts end
	end
	return bp, bs, bparts
end

-- offense / defense: lists of contestants (usually one each). ballHeight in metres.
-- returns {
--   result   = "CATCH" | "INT" | "BREAKUP" | "INCOMPLETE"
--   winner   = the contestant table that won, or nil
--   reason   = readable
--   scores   = { [name] = { score, timing, position, height, hand } }
--   margin   = how much the winner won by
-- }
function Contest.resolve(offense, defense, ballHeight, cfg)
	offense = offense or {}
	defense = defense or {}
	-- box-out is decided pairwise between the two closest bodies, before scoring
	local o0 = best(offense, ballHeight, cfg)
	local d0 = best(defense, ballHeight, cfg)
	if o0 and d0 then
		o0.boxout = Contest.boxout(o0, d0, cfg)
		d0.boxout = Contest.boxout(d0, o0, cfg)
	end
	local scores = {}
	local function record(p)
		if not p then return nil end
		local s, parts = Contest.score(p, ballHeight, cfg)
		scores[p.name or tostring(p)] = { score = s, timing = parts.timing, position = parts.position,
			height = parts.height, hand = parts.hand, side = p.side, dist = p.dist, tau = p.tau }
		return s
	end
	local O, X = o0 and record(o0) or nil, d0 and record(d0) or nil
	for _, p in ipairs(offense) do if p ~= o0 then record(p) end end
	for _, p in ipairs(defense) do if p ~= d0 then record(p) end end

	if not O and not X then
		return { result = "INCOMPLETE", reason = "NOBODY WENT UP FOR IT", scores = scores, margin = 0 }
	end
	if not X then
		if O < cfg.minToCatch then
			return { result = "INCOMPLETE", winner = o0, reason = Contest.why(o0, scores, cfg, false), scores = scores, margin = 0 }
		end
		return { result = "CATCH", winner = o0, reason = Contest.why(o0, scores, cfg, true), scores = scores, margin = O }
	end
	if not O then
		if X < cfg.minToCatch then
			return { result = "BREAKUP", winner = d0, reason = "KNOCKED IT AWAY", scores = scores, margin = 0 }
		end
		return { result = (X >= cfg.intThreshold) and "INT" or "BREAKUP", winner = d0,
			reason = (X >= cfg.intThreshold) and "SKIED FOR THE PICK" or "SKIED AND BROKE IT UP", scores = scores, margin = X }
	end

	local gap = O - X
	if math.abs(gap) < cfg.tieMargin then
		if O >= cfg.minToCatch and X >= cfg.minToCatch then
			return { result = "CATCH", winner = o0, reason = "SIMULTANEOUS CATCH · BALL GOES TO THE OFFENCE",
				scores = scores, margin = math.abs(gap) }
		end
		return { result = "INCOMPLETE", reason = "BOTH GOT A HAND ON IT · BATTED DOWN", scores = scores, margin = math.abs(gap) }
	end
	if gap > 0 then
		if O < cfg.minToCatch then
			return { result = "INCOMPLETE", winner = o0, reason = Contest.why(o0, scores, cfg, false), scores = scores, margin = gap }
		end
		return { result = "CATCH", winner = o0, reason = Contest.why(o0, scores, cfg, true), scores = scores, margin = gap }
	end
	if X < cfg.minToCatch then
		return { result = "BREAKUP", winner = d0, reason = "GOT A FINGER ON IT", scores = scores, margin = -gap }
	end
	return { result = (X >= cfg.intThreshold) and "INT" or "BREAKUP", winner = d0,
		reason = (X >= cfg.intThreshold) and Contest.why(d0, scores, cfg, true) .. " · PICKED IT" or Contest.why(d0, scores, cfg, true) .. " · BROKE IT UP",
		scores = scores, margin = -gap }
end

-- the one sentence that explains a contestant's score: the component that carried it, or the one that sank it
local STRONG = { timing = "PERFECT LEAP", position = "BOXED HIM OUT", height = "HIGH-POINTED IT" }
local WEAK = { timing = "MISTIMED THE JUMP", position = "WASN'T IN POSITION", height = "BALL WAS OVER YOUR HANDS" }
function Contest.why(p, scores, cfg, won)
	local s = scores[p.name or tostring(p)]
	if not s then return won and "WON IT" or "LOST IT" end
	local keys = { "timing", "position", "height" }
	local pick, pickV = "timing", won and -math.huge or math.huge
	for _, k in ipairs(keys) do
		local v = s[k]
		if won then if v > pickV then pick, pickV = k, v end
		else if v < pickV then pick, pickV = k, v end end
	end
	return (won and STRONG[pick] or WEAK[pick])
end

return Contest
