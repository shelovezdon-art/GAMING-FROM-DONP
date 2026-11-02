-- MIRROR of game.ReplicatedStorage.AWHoops.HoopsCamera (ModuleScript), pulled 2026-11-02 (post wave-3, Gauntlet, DRIP, broadcast UI, stance poses, 2K camera).
-- Studio is the source of truth (docs/practice/ROBLOX-PRACTICE.md §1); this copy is the QA/design record.
--!nonstrict
-- ALLSTAR WORLD · HoopsCamera (client): basketball cameras that keep the play readable — dribble, shot, iron, rebound,
-- outlet — instead of Roblox's over-the-shoulder follow cam that loses the ball and parks behind scenery.
--   2K (the full-court default): behind the basket your team DEFENDS, looking down the floor at the basket it
--     ATTACKS. On offence you play into the rim you shoot on; when possession flips the camera swings around the
--     near sideline to the other end, so on defence the attack comes at you with your own basket behind the view.
--     Needs opts.attackRim; without it the view holds whichever end it was already on.
--   BROADCAST: high on the near sideline, panning along the floor with the play (the classic side view). The
--     whole width of the court is in frame; the camera leads toward the ball, not just your player.
--   CLOSE: the same angle, lower and tighter, weighted toward your own player.
--   BASELINE: behind the play, looking down the floor toward the basket the ball is going at.
--   FREE: Roblox's own camera (its usual zoom-in occlusion; a LocalScript can't change the occlusion mode).
-- Nothing on the court ever blocks the shot: scenery between the camera and the action (stands, light towers, fences,
-- trees, the arch) fades out on this screen only, and comes back when the view clears. Players and the ball never fade.
-- Movement stays camera-relative (Roblox's controls read workspace.CurrentCamera), so "up" is up-court on screen.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local Cam = {}
local player = Players.LocalPlayer
local MODES = { "BROADCAST", "CLOSE", "BASELINE", "FREE" }   -- the default cycle (the 1v1 keeps this one unchanged)
Cam.MODES = MODES
Cam.MODES_FULLCOURT = { "2K", "BROADCAST", "CLOSE", "BASELINE", "FREE" }   -- pass as opts.modes for the 3v3

-- tuning (studs; the court is ~98 x 52 studs): height, distance back from the near sideline, field of view
local VIEW = {
	BROADCAST = { h = 30, back = 24, fov = 50, lead = 0.62, follow = 3.2 },
	CLOSE = { h = 21, back = 13, fov = 56, lead = 0.4, follow = 4.0 },
	BASELINE = { h = 17, back = 30, fov = 60, lead = 0.55, follow = 3.0 },
}

-------------------------------------------------------------------------------------------------- 2K view: CONFIG
-- Every number the 2K broadcast view is tuned with lives here. Studs and seconds unless the name says otherwise.
-- Measured live on Court_bb-2 (2026-11-02): floor top 0.50, rim 9.214, BACKBOARD TOP 12.50, surface 98.23 x 52.25 studs.
local CFG2K = {
	back = 25,            -- studs the camera trails the play by, along the court's long axis
	up = 14,              -- studs above the floor (the board tops out at 12.50 -- lower and you look through your own glass)
	minUp = 13.2,         -- never drop below this: your own backboard and stanchion would cut the view
	pitchDeg = 20,        -- how far below horizontal the camera looks (sets the aim point, so the far rim stays in frame)
	fov = 52,
	playerWeight = 0.65,  -- the framed point is 0.65 * you + 0.35 * the ball
	follow = 4.2,         -- critical-damping rate for that framed point
	posFollow = 5.0,      -- ... and for the camera position
	flipSeconds = 0.6,    -- a possession change swings the view to the other end over this long (never a snap)
	leadToRim = 0.18,     -- aim this fraction of the way on from the framed point toward the rim you attack
	leadMax = 9,          -- ... but never more than this many studs of lead
	sideSweep = 0.85,     -- the end-to-end swing passes out over the near sideline instead of through the floor
	zDrift = 0.3,         -- how much the camera slides across with the play
	sprintBack = 0.1,     -- + this fraction of `back` while sprinting / on a fast break
	sprintFov = 4,        -- + this many degrees of FOV while sprinting
	sprintEase = 2.5,
	occludePull = 1.2,    -- when scenery blocks the view, stop the camera this far short of it
	minBack = 10,         -- ... but never pull closer in than this
	behindMax = 34,       -- never drift further than this behind your own baseline
}
Cam.CFG2K = CFG2K
VIEW["2K"] = { h = CFG2K.up, back = CFG2K.back, fov = CFG2K.fov, lead = 1 - CFG2K.playerWeight, follow = CFG2K.follow }

local state = nil

local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function damp(cur, target, rate, dt) return cur:Lerp(target, 1 - math.exp(-rate * dt)) end

-- the floor box of a court model (studs): centre, half sizes, floor top
local function courtBox(model)
	local surf = model:FindFirstChild("CourtSurface")
	if not surf then return nil end
	local long = math.max(surf.Size.X, surf.Size.Z)
	local short = math.min(surf.Size.X, surf.Size.Z)
	return { cx = surf.Position.X, cz = surf.Position.Z, top = surf.Position.Y + surf.Size.Y / 2, hl = long / 2, hw = short / 2 }
end

-------------------------------------------------------------------------------------------------- occluders fade
local faded = {}          -- [part] = current fade
local function isPerson(inst)
	local m = inst:FindFirstAncestorOfClass("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then return true end
		if m.Name == "AWBallView" then return true end
		m = m.Parent and m.Parent:FindFirstAncestorOfClass("Model")
	end
	return false
end
local function fadeOccluders(camPos, targets, dt, court)
	local want = {}
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignore, p.Character) end end
	if court then table.insert(ignore, court) end
	params.FilterDescendantsInstances = ignore
	for _, target in ipairs(targets) do
		local dir = camPos - target
		local from = target
		for _ = 1, 6 do
			local hit = workspace:Raycast(from, camPos - from, params)
			if not hit then break end
			local part = hit.Instance
			if part:IsA("BasePart") and not isPerson(part) then want[part] = true end
			table.insert(ignore, part)
			params.FilterDescendantsInstances = ignore
			from = hit.Position + dir.Unit * 0.05
		end
	end
	for part in pairs(want) do faded[part] = faded[part] or 0 end
	for part, f in pairs(faded) do
		if not part.Parent then faded[part] = nil
		else
			local goal = want[part] and 0.8 or 0
			f = f + (goal - f) * (1 - math.exp(-12 * dt))
			if goal == 0 and f < 0.01 then part.LocalTransparencyModifier = 0; faded[part] = nil
			else part.LocalTransparencyModifier = f; faded[part] = f end
		end
	end
end
local function clearFades()
	for part in pairs(faded) do if part.Parent then part.LocalTransparencyModifier = 0 end end
	faded = {}
end

-------------------------------------------------------------------------------------------------- 2K view: the maths
-- Where the camera goes for the 2K view, and what it aims at. `f` is the framed point (between you and the ball, on
-- the floor), `z` the mouse-wheel zoom. Returns pos, aim.
--
-- The orientation rule: the rim this player's team ATTACKS decides the end. `d` is +1 when that rim is at +X, -1 when
-- it is at -X, and the camera goes to the OTHER end -- behind the basket the team DEFENDS -- so the attacked rim is
-- always the far end of the shot. The swing is an eased angle `theta` around the framed point: theta = 0 puts the
-- camera at the +X end, theta = -pi at the -X end, and easing between them travels through -pi/2, which is out over
-- the near sideline. So a possession change pans end to end across the floor instead of cutting, and the camera is
-- never degenerately on top of the play mid-swing (the distance back is constant the whole way round).
local function twoK(st, f, z, dt)
	local C = CFG2K
	local box = st.box
	local rim = st.opts.attackRim and st.opts.attackRim() or nil
	local want = st.theta
	if rim then
		local d = (rim.X >= box.cx) and 1 or -1
		want = (d > 0) and -math.pi or 0
	end
	st.theta = st.theta or want or 0
	if want and not st.seated then
		st.theta, st.seated = want, true          -- the first rim we hear about seats the view at once (no opening pan)
	elseif want then
		st.theta = st.theta + (want - st.theta) * (1 - math.exp(-(3 / C.flipSeconds) * dt))
	end
	-- sprint / fast break: a touch further back and a touch wider, eased in and out
	local spWant = (st.opts.sprinting and st.opts.sprinting()) and 1 or 0
	st.sprint = (st.sprint or 0) + (spWant - (st.sprint or 0)) * (1 - math.exp(-C.sprintEase * dt))
	local back = C.back * (1 + C.sprintBack * st.sprint) * z
	local up = math.max(C.up * z, C.minUp)
	local camX = f.X + math.cos(st.theta) * back
	local camZ = box.cz + (f.Z - box.cz) * C.zDrift + math.sin(st.theta) * back * C.sideSweep
	camX = clamp(camX, box.cx - box.hl - C.behindMax, box.cx + box.hl + C.behindMax)
	local pos = Vector3.new(camX, box.top + up, camZ)
	-- a gentle lead on toward the rim being attacked, so cuts into the frame read before they arrive
	local aim = f
	if rim then
		local lead = Vector3.new(rim.X - f.X, 0, rim.Z - f.Z) * C.leadToRim
		if lead.Magnitude > C.leadMax then lead = lead.Unit * C.leadMax end
		aim = aim + lead
	end
	-- hold the pitch at pitchDeg by lifting the aim point, rather than letting the distance decide how steep it looks
	local flat = Vector3.new(pos.X - aim.X, 0, pos.Z - aim.Z).Magnitude
	local lift = (pos.Y - aim.Y) - flat * math.tan(math.rad(C.pitchDeg))
	if lift > 0 then aim = aim + Vector3.new(0, lift, 0) end
	return pos, aim
end

-- never shoot through the floor or the backboard: if anything solid sits between the aim point and the camera, pull
-- the camera in to just short of it, and keep it above the board either way.
local function pullIn(st, pos, aim)
	local C = CFG2K
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignore, p.Character) end end
	local bv = workspace:FindFirstChild("AWBallView")
	if bv then table.insert(ignore, bv) end
	params.FilterDescendantsInstances = ignore
	local dir = pos - aim
	local dist = dir.Magnitude
	if dist > 1e-3 then
		local hit = workspace:Raycast(aim, dir, params)
		if hit then
			local keep = math.max((hit.Position - aim).Magnitude - C.occludePull, C.minBack)
			if keep < dist then pos = aim + dir.Unit * keep end
		end
	end
	return Vector3.new(pos.X, math.max(pos.Y, st.box.top + C.minUp), pos.Z)
end

-------------------------------------------------------------------------------------------------- the camera
-- opts = { court = court model, ball = () -> Vector3? (where the ball is drawn), attackDir = () -> +1/-1 (which way along
-- X the play is going; nil = toward the ball), attackRim = () -> Vector3? (the rim THIS player's team attacks, studs --
-- the 2K view's orientation comes from this, and flipping it flips the view), sprinting = () -> boolean (widens the 2K
-- view a little), modes = { names } (the cycle this game uses; defaults to MODES), mode = initial mode name }
function Cam.start(opts)
	Cam.stop()
	local box = opts.court and courtBox(opts.court)
	if not box then return false end
	local cam = workspace.CurrentCamera
	state = {
		opts = opts, box = box, modes = opts.modes or MODES, mode = opts.mode or (opts.modes and opts.modes[1]) or "BROADCAST", zoom = 1,
		focus = nil, pos = nil, look = nil,
		saved = { fov = cam.FieldOfView },
	}
	-- the near sideline: the side of the court away from the JOIN pads / scorer's table (south, -Z, for courts along X)
	state.side = -1
	RunService:BindToRenderStep("AWHoopsCamera", Enum.RenderPriority.Camera.Value + 1, function(dt) Cam.update(dt) end)
	state.wheel = UIS.InputChanged:Connect(function(input, gp)
		if gp or not state or input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
		state.zoom = clamp(state.zoom - input.Position.Z * 0.08, 0.7, 1.35)
	end)
	Cam.setMode(state.mode)
	return true
end

function Cam.stop()
	if not state then return end
	pcall(function() RunService:UnbindFromRenderStep("AWHoopsCamera") end)
	if state.wheel then state.wheel:Disconnect() end
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = state.saved.fov or 70
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
	clearFades()
	state = nil
end

function Cam.setMode(name)
	if not state then return end
	state.mode = name
	local cam = workspace.CurrentCamera
	if name == "FREE" then
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then cam.CameraSubject = hum end
		clearFades()
	else
		cam.CameraType = Enum.CameraType.Scriptable
		state.pos = nil                                        -- re-seat smoothly from where it is
	end
end

function Cam.cycle()
	if not state then return nil end
	local list = state.modes or MODES   -- was MODES (2026-11-02: per-game cycle, so the 1v1's list is unchanged)
	local i = table.find(list, state.mode) or 1
	local nextMode = list[i % #list + 1]
	Cam.setMode(nextMode)
	return nextMode
end
function Cam.mode() return state and state.mode or nil end
function Cam.active() return state ~= nil end

function Cam.update(dt)
	if not state then return end
	dt = math.clamp(dt, 0, 0.1)
	local cam = workspace.CurrentCamera
	if state.mode == "FREE" then return end
	if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
	local box = state.box
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local me = root and root.Position or Vector3.new(box.cx, box.top, box.cz)
	local ball = state.opts.ball and state.opts.ball() or nil
	local V = VIEW[state.mode] or VIEW.BROADCAST
	-- what to look at: between you and the ball (leaning toward the ball), kept on the floor
	local target = ball and me:Lerp(ball, V.lead) or me
	local fx = clamp(target.X, box.cx - box.hl - 4, box.cx + box.hl + 4)
	local fz = clamp(target.Z, box.cz - box.hw - 4, box.cz + box.hw + 4)
	local fy = box.top + 3 + (ball and clamp(ball.Y - box.top - 3, 0, 8) * 0.35 or 0)
	local focus = Vector3.new(fx, fy, fz)
	state.focus = state.focus and damp(state.focus, focus, V.follow, dt) or focus
	local f = state.focus
	local z = state.zoom
	local pos, aimAt
	if state.mode == "2K" then
		pos, aimAt = twoK(state, f, z, dt)
	elseif state.mode == "BASELINE" then
		local dir = state.opts.attackDir and state.opts.attackDir() or nil
		if not dir then dir = (ball and ball.X >= me.X) and 1 or -1 end
		state.dir = state.dir and (state.dir + (dir - state.dir) * (1 - math.exp(-2.5 * dt))) or dir
		local d = state.dir
		pos = Vector3.new(f.X - d * V.back * z, box.top + V.h * z, f.Z + (box.cz - f.Z) * 0.35)
	else
		-- sideline: x follows the play, z fixed off the near sideline, a little dolly toward the far side of the floor
		local back = box.hw + V.back * z
		local zOff = (f.Z - box.cz) * 0.25
		pos = Vector3.new(f.X, box.top + V.h * z, box.cz + state.side * back + zOff)
	end
	local posRate = (state.mode == "2K") and CFG2K.posFollow or V.follow * 1.2
	state.pos = state.pos and damp(state.pos, pos, posRate, dt) or pos
	local fovWant = V.fov
	if state.mode == "2K" then
		fovWant = CFG2K.fov + CFG2K.sprintFov * (state.sprint or 0)
		state.pos = pullIn(state, state.pos, aimAt or f)
	end
	cam.FieldOfView = cam.FieldOfView + (fovWant - cam.FieldOfView) * (1 - math.exp(-6 * dt))
	cam.CFrame = CFrame.lookAt(state.pos, aimAt or f)
	-- keep the play visible: fade anything between the camera and you / the ball
	state.fadeT = (state.fadeT or 0) + dt
	if state.fadeT > 0.05 then
		local targets = { me + Vector3.new(0, 1.5, 0) }
		if ball then table.insert(targets, ball) end
		fadeOccluders(state.pos, targets, state.fadeT, state.opts.court)
		state.fadeT = 0
	end
end

return Cam
