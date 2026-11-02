--[[ ALLSTAR WORLD · Practice Field ("Ball Lab") client · Stage 3: tackling and jump balls.

   Install: StarterPlayer/StarterPlayerScripts/TackleClient (LocalScript), Disabled = true until reviewed.

   It sits ALONGSIDE PracticeClient and does not touch it. Its keys, its gamepad buttons, its touch buttons, its
   ContextActionService action names and its RemoteEvents are all its own, so nothing is stolen from Stage 1 or 2.
   PracticeClient keeps E / T / O / Q / R / F / G / SHIFT and SPACE; this script uses the keys below and nothing else.

   Controls
     keyboard   Z juke left · X juke right · C spin · V stiff-arm      (while you are carrying)
                B wrap · N dive                                        (while you are on defence)
                K switch between offence and defence
     gamepad    L1 = wrap on defence / juke toward the stick (or spin with the stick centred) on offence
                L2 = dive on defence / stiff-arm on offence
                D-pad right switches sides
     touch      the buttons that appear on the left of the screen change with your side

   Optimistic, then corrected
     The moment you press, this script moves your own body (a dive really lunges, a juke really cuts) and shows the
     label, because waiting a round trip for a 0.3 s lunge feels broken. It never claims an outcome. The server
     decides what the contact was and sends back the reason; if it disagrees — the tap was stale, you were still
     recovering, the angle was wrong, or it simply never arrived inside 0.4 s — the local lunge is cancelled on the
     spot and the body goes back to whatever PracticeClient's momentum says. Penalties (on the floor, stunned,
     dragged) are only ever applied from the server's message, never guessed.

     The lunge is applied on Heartbeat, which runs after PracticeClient's own movement step, so for those few frames
     ours is the last word on WalkSpeed and Humanoid:Move. Nothing is patched or monkeyed with to make that happen.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CAS = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PKG = RS:WaitForChild("AWPractice")
local CFG = require(PKG:WaitForChild("Config"))
local Tackle = require(PKG:WaitForChild("Tackle"))
if not CFG.tackle then warn("[TackleClient] Config has no `tackle` block — Stage 3 client not loaded"); return end

local remotes = PKG:WaitForChild("Remotes")
local Intent = remotes:WaitForChild("TackleIntent")
local State = remotes:WaitForChild("TackleState")

local S = CFG.S
local F, T = CFG.field, CFG.tackle
local YD = CFG.YARD * S
local G = {}
G.halfW = F.widthM / 2 * S
G.halfL = (F.playYards + F.endZoneYards) * YD / 2
G.north, G.south = F.cz - G.halfL, F.cz + G.halfL
local function inZone(pos, marginM)
	local m = marginM * S
	return math.abs(pos.X - F.cx) <= G.halfW + m and pos.Z >= G.north - m and pos.Z <= G.south + m
end

local NAVY = Color3.fromRGB(10, 20, 38)
local GOLD = Color3.fromRGB(255, 191, 58)
local WHITE = Color3.fromRGB(245, 246, 248)
local GOOD = Color3.fromRGB(70, 210, 120)
local BAD = Color3.fromRGB(240, 80, 80)
local TONE = { good = GOOD, bad = BAD, warn = GOLD }

-------------------------------------------------------------------------------------------------- state
local active = false
local role = "offense"
local cd = { wrap = 1, dive = 1, juke = 1, spin = 1, stiff = 1 }
local carrying = false
local wrappedLeft = 0
local brokenCount = 0
local lunge = nil          -- { dir, speed, untilT, kind, awaitingUntil }
local penalty = { downUntil = 0, capMul = 1, capUntil = 0 }
local lastReason = nil

local function character()
	local c = player.Character
	return c, c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end

-------------------------------------------------------------------------------------------------- UI
local gui = Instance.new("ScreenGui")
gui.Name = "AWTackleHUD"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 21; gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(o, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o end
local function text(parent, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold; t.TextColor3 = WHITE; t.TextScaled = true
	for k, v in pairs(props) do t[k] = v end
	t.Parent = parent
	return t
end

local panel = Instance.new("Frame")
panel.Name = "ContactPanel"; panel.AnchorPoint = Vector2.new(0, 0); panel.Position = UDim2.new(0, 12, 0, 64)
panel.Size = UDim2.fromOffset(224, 112); panel.BackgroundColor3 = NAVY; panel.BackgroundTransparency = 0.2; panel.Parent = gui
corner(panel, 10)
local stroke = Instance.new("UIStroke"); stroke.Color = GOLD; stroke.Transparency = 0.5; stroke.Parent = panel
local title = text(panel, { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(10, 8), Text = "CONTACT · OFFENCE",
	TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
local rows = {}
for i = 1, 4 do
	rows[i] = text(panel, { Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(10, 12 + i * 20), Text = "",
		Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left })
end

local toast = text(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.58, 0), Size = UDim2.new(0.7, 0, 0, 34),
	Text = "", TextTransparency = 1, TextStrokeTransparency = 0.4, TextStrokeColor3 = Color3.new(0, 0, 0) })
local toastToken = 0
local function showToast(msg, tone)
	toastToken += 1
	local my = toastToken
	toast.Text = msg; toast.TextColor3 = TONE[tone] or WHITE; toast.TextTransparency = 0; toast.TextStrokeTransparency = 0.4
	task.delay(1.4, function()
		if toastToken == my then
			TweenService:Create(toast, TweenInfo.new(0.25), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

-- touch buttons, on the LEFT of the screen (PracticeClient's are all on the right)
local touchFrame = Instance.new("Frame")
touchFrame.Name = "TouchContact"; touchFrame.BackgroundTransparency = 1; touchFrame.Size = UDim2.fromScale(1, 1)
touchFrame.Visible = false; touchFrame.Parent = gui
local function touchButton(label, size, x, y)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(size, size); b.AnchorPoint = Vector2.new(0.5, 0.5); b.Position = UDim2.new(0, x, 1, y)
	b.BackgroundColor3 = NAVY; b.BackgroundTransparency = 0.15; b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBlack; b.Text = label; b.TextColor3 = WHITE; b.TextScaled = true
	local pad = Instance.new("UIPadding"); pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6); pad.Parent = b
	local st = Instance.new("UIStroke"); st.Color = GOLD; st.Thickness = 2; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = b
	corner(b, size); b.Parent = touchFrame
	return b
end
local wrapB = touchButton("WRAP", 84, 120, -210)
local diveB = touchButton("DIVE", 84, 215, -150)
local jukeLB = touchButton("\u{25C0}", 72, 100, -220)
local jukeRB = touchButton("\u{25B6}", 72, 196, -220)
local spinB = touchButton("SPIN", 64, 136, -140)
local armB = touchButton("ARM", 64, 226, -258)
local roleB = touchButton("SIDE", 48, 60, -118)

-------------------------------------------------------------------------------------------------- sending
local ballRev = 0
-- the ball revision is published by PracticeService on its own State event; we listen read-only so our intents can
-- quote it, exactly the way PracticeClient does. (Listening to a RemoteEvent does not consume it: every client
-- handler of the same event still runs.)
local PracticeState = remotes:WaitForChild("State", 10)
if PracticeState then
	PracticeState.OnClientEvent:Connect(function(msg)
		if typeof(msg) == "table" and msg.kind == "ball" and tonumber(msg.rev) then ballRev = tonumber(msg.rev) end
	end)
end

local function send(action, extra)
	local data = extra or {}
	data.rev = ballRev
	data.at = workspace:GetServerTimeNow()
	Intent:FireServer(action, data)
end

-------------------------------------------------------------------------------------------------- optimistic lunge
local function flatLook()
	local _, _, hrp = character()
	if not hrp then return Vector3.new(0, 0, -1) end
	local l = hrp.CFrame.LookVector
	l = Vector3.new(l.X, 0, l.Z)
	return (l.Magnitude > 1e-4) and l.Unit or Vector3.new(0, 0, -1)
end
local function rightOf(dir) return Vector3.new(-dir.Z, 0, dir.X) end

local function beginLunge(kind, dir, speedStuds, time)
	lunge = { kind = kind, dir = dir, speed = speedStuds, untilT = os.clock() + time, awaitingUntil = os.clock() + 0.4 }
end
local function cancelLunge(why)
	if not lunge then return end
	lunge = nil
	if why then showToast(why, "bad") end
end

-- Runs on Heartbeat, which is after PracticeClient's movement step, so during a lunge ours is the last word.
RunService.Heartbeat:Connect(function()
	local _, hum = character()
	if not hum then return end
	local now = os.clock()
	if lunge then
		if now >= lunge.untilT then
			lunge = nil
		else
			hum.WalkSpeed = lunge.speed
			hum:Move(lunge.dir, false)
			return
		end
	end
	if now < penalty.downUntil then
		hum.WalkSpeed = 0
		hum:Move(Vector3.zero, false)
	elseif now < penalty.capUntil then
		local cap = CFG.move.sprint * penalty.capMul * S
		if hum.WalkSpeed > cap then hum.WalkSpeed = cap end
	end
end)

-------------------------------------------------------------------------------------------------- actions
local function doWrap()
	if role ~= "defense" then showToast("YOU'RE ON OFFENCE · K TO SWITCH", "warn"); return end
	if cd.wrap < 1 then return end
	send("wrap")
	beginLunge("wrap", flatLook(), CFG.move.jog * S, T.wrapStartup)
	showToast("WRAP", "warn")
end
local function doDive()
	if role ~= "defense" then showToast("YOU'RE ON OFFENCE · K TO SWITCH", "warn"); return end
	if cd.dive < 1 then return end
	send("dive")
	beginLunge("dive", flatLook(), T.diveSpeed * S, T.diveTime)
	showToast("DIVE", "warn")
end
local function doJuke(side)
	if not carrying then return end
	if cd.juke < 1 and wrappedLeft <= 0 then return end
	send(side > 0 and "jukeL" or "jukeR")
	local dir = (rightOf(flatLook()) * -side + flatLook() * 0.3)
	beginLunge("juke", dir.Unit, T.jukeSpeed * S, T.jukeTime)
end
local function doSpin()
	if not carrying then return end
	if cd.spin < 1 and wrappedLeft <= 0 then return end
	send("spin")
	beginLunge("spin", flatLook(), T.spinSpeed * S, T.spinTime)
	showToast("SPIN", "warn")
end
local function doStiffArm()
	if not carrying then return end
	if cd.stiff < 1 and wrappedLeft <= 0 then return end
	send("stiffarm")
	penalty.capMul = T.stiffSpeedRetain
	penalty.capUntil = os.clock() + T.stiffWindow
	showToast("STIFF-ARM", "warn")
end
local function doRole() send("role") end

-- the gamepad has no spare face buttons left after Stages 1 and 2, so its two shoulder triggers do the job of four:
-- what they mean depends on which side you are on, and on offence L1 reads the stick (left / right = juke that way,
-- centred = spin). The HUD always says which, so nothing is hidden.
local function padPrimary()
	if role == "defense" then doWrap(); return end
	local v = UIS:GetGamepadState(Enum.UserInputType.Gamepad1)
	local x = 0
	for _, s in ipairs(v) do if s.KeyCode == Enum.KeyCode.Thumbstick1 then x = s.Position.X end end
	if math.abs(x) < 0.35 then doSpin() else doJuke(x < 0 and 1 or -1) end
end
local function padSecondary()
	if role == "defense" then doDive() else doStiffArm() end
end

local bound = false
local function bindActions()
	if bound then return end
	bound = true
	local P = 3090      -- below PracticeClient's 3100, and on keys it does not use, so nothing of Stage 1-2 is sunk
	local function bind(name, keys, fn)
		CAS:BindActionAtPriority(name, function(_, st)
			if st == Enum.UserInputState.Begin then fn() end
			return Enum.ContextActionResult.Sink
		end, false, P, table.unpack(keys))
	end
	bind("AWTackleJukeL", { Enum.KeyCode.Z }, function() doJuke(1) end)
	bind("AWTackleJukeR", { Enum.KeyCode.X }, function() doJuke(-1) end)
	bind("AWTackleSpin", { Enum.KeyCode.C }, doSpin)
	bind("AWTackleArm", { Enum.KeyCode.V }, doStiffArm)
	bind("AWTackleWrap", { Enum.KeyCode.B }, doWrap)
	bind("AWTackleDive", { Enum.KeyCode.N }, doDive)
	bind("AWTackleRole", { Enum.KeyCode.K, Enum.KeyCode.DPadRight }, doRole)
	bind("AWTacklePadA", { Enum.KeyCode.ButtonL1 }, padPrimary)
	bind("AWTacklePadB", { Enum.KeyCode.ButtonL2 }, padSecondary)
end
local NAMES = { "AWTackleJukeL", "AWTackleJukeR", "AWTackleSpin", "AWTackleArm", "AWTackleWrap", "AWTackleDive",
	"AWTackleRole", "AWTacklePadA", "AWTacklePadB" }
local function unbindActions()
	if not bound then return end
	bound = false
	for _, n in ipairs(NAMES) do CAS:UnbindAction(n) end
	lunge = nil
end

wrapB.Activated:Connect(doWrap)
diveB.Activated:Connect(doDive)
jukeLB.Activated:Connect(function() doJuke(1) end)
jukeRB.Activated:Connect(function() doJuke(-1) end)
spinB.Activated:Connect(doSpin)
armB.Activated:Connect(doStiffArm)
roleB.Activated:Connect(doRole)

-------------------------------------------------------------------------------------------------- per-frame readout
RunService.PreRender:Connect(function(dt)
	if not active then return end
	if wrappedLeft > 0 then wrappedLeft = math.max(0, wrappedLeft - dt) end
	local def = (role == "defense")
	title.Text = def and "CONTACT · DEFENCE" or (carrying and "CONTACT · CARRYING" or "CONTACT · OFFENCE")
	title.TextColor3 = def and Color3.fromRGB(255, 130, 90) or GOLD
	local function bar(v) local n = math.floor(math.clamp(v, 0, 1) * 8 + 0.5); return string.rep("\u{2588}", n) .. string.rep("\u{00B7}", 8 - n) end
	if def then
		rows[1].Text = "B / L1  WRAP  " .. bar(cd.wrap)
		rows[2].Text = "N / L2  DIVE  " .. bar(cd.dive)
		rows[3].Text = (os.clock() < penalty.downUntil) and "ON THE FLOOR" or "TAKE AN ANGLE · DON'T DIVE EARLY"
		rows[4].Text = lastReason or ""
	else
		rows[1].Text = "Z/X JUKE " .. bar(cd.juke) .. "   C SPIN " .. bar(cd.spin)
		rows[2].Text = "V STIFF-ARM " .. bar(cd.stiff)
		rows[3].Text = wrappedLeft > 0 and ("WRAPPED · %.2fs TO BREAK IT"):format(wrappedLeft)
			or (carrying and (brokenCount > 0 and ("BROKEN: " .. brokenCount .. " (each one gets harder)") or "RUN IT") or "K SWITCH TO DEFENCE")
		rows[4].Text = lastReason or ""
	end
	rows[3].TextColor3 = wrappedLeft > 0 and GOLD or WHITE
	if touchFrame.Visible then
		wrapB.Visible = def; diveB.Visible = def
		jukeLB.Visible = not def; jukeRB.Visible = not def; spinB.Visible = not def; armB.Visible = not def
	end
end)

-------------------------------------------------------------------------------------------------- activation
local function activate()
	if active then return end
	active = true
	bindActions()
	gui.Enabled = true
	touchFrame.Visible = UIS.TouchEnabled
	showToast(role == "defense" and "DEFENCE · B WRAP · N DIVE" or "OFFENCE · Z/X JUKE · C SPIN · V ARM · K SWITCH", "warn")
end
local function deactivate()
	if not active then return end
	active = false
	unbindActions()
	gui.Enabled = false
	penalty.downUntil = 0; penalty.capUntil = 0
end

RunService.PostSimulation:Connect(function()
	local _, hum, hrp = character()
	local here = hum and hrp and hum.Health > 0 and inZone(hrp.Position, F.zoneMarginM)
	if here then activate() else deactivate() end
	-- the server never confirmed this attempt: cancel the optimistic lunge rather than keep running on a guess
	if lunge and lunge.awaitingUntil and os.clock() > lunge.awaitingUntil and not lunge.confirmed then
		cancelLunge("NO ANSWER FROM THE SERVER · ATTEMPT DROPPED")
	end
end)

player.CharacterAdded:Connect(function()
	lunge = nil
	penalty.downUntil = 0; penalty.capUntil = 0
	if active then deactivate() end
end)

-------------------------------------------------------------------------------------------------- server messages
local function isMe(model) return model ~= nil and model == player.Character end

State.OnClientEvent:Connect(function(msg)
	if typeof(msg) ~= "table" then return end

	if msg.kind == "role" then
		role = tostring(msg.role or "offense")
		if active then showToast(role == "defense" and "ON DEFENCE" or "ON OFFENCE", "good") end

	elseif msg.kind == "cd" then
		cd.wrap = msg.wrap or 1; cd.dive = msg.dive or 1
		cd.juke = msg.juke or 1; cd.spin = msg.spin or 1; cd.stiff = msg.stiff or 1
		role = msg.role or role
		carrying = msg.carrying == true
		wrappedLeft = tonumber(msg.wrapped) or 0
		brokenCount = tonumber(msg.broken) or 0
		-- the server's own view of being out of the play wins over the local guess
		if (tonumber(msg.down) or 0) > 0 then penalty.downUntil = os.clock() + msg.down end

	elseif msg.kind == "lunge" then
		if isMe(msg.who) then
			if lunge then lunge.confirmed = true end
		end

	elseif msg.kind == "move" then
		if isMe(msg.who) then
			if lunge then lunge.confirmed = true end
		end

	elseif msg.kind == "fb" then
		if active then showToast(tostring(msg.text), msg.tone) end

	elseif msg.kind == "tackle" then
		lastReason = tostring(msg.reason or "")
		local mine = isMe(msg.tackler)
		local onMe = isMe(msg.target)
		if mine then
			if lunge then lunge.confirmed = true end
			-- the server disagreed with the optimistic lunge: stop lunging now, and take the penalty it set
			if msg.outcome == Tackle.WHIFF or msg.outcome == Tackle.NO_CONTACT or msg.outcome == Tackle.BROKEN then
				cancelLunge(nil)
				if (tonumber(msg.grounded) or 0) > 0 then
					penalty.downUntil = os.clock() + msg.grounded
					local _, hum = character()
					if hum then hum:ChangeState(Enum.HumanoidStateType.FallingDown) end
				elseif (tonumber(msg.recover) or 0) > 0 then
					penalty.capMul = 0.25; penalty.capUntil = os.clock() + msg.recover
				end
				if (tonumber(msg.stun) or 0) > 0 then penalty.downUntil = os.clock() + msg.stun end
			else
				cancelLunge(nil)
			end
		end
		if onMe then
			cancelLunge(nil)
			if (tonumber(msg.stumble) or 0) > 0 then
				local _, hum = character()
				if hum then hum:ChangeState(Enum.HumanoidStateType.FallingDown) end
				penalty.downUntil = os.clock() + msg.stumble
			elseif (tonumber(msg.drag) or 0) > 0 then
				penalty.capMul = tonumber(msg.dragMul) or T.wrapDragMul
				penalty.capUntil = os.clock() + msg.drag
				wrappedLeft = tonumber(msg.breakWindow) or T.breakWindow
			end
			if msg.outcome == Tackle.TACKLED or msg.outcome == Tackle.FUMBLE then
				local _, hum = character()
				if hum then hum:ChangeState(Enum.HumanoidStateType.FallingDown) end
				penalty.downUntil = os.clock() + 0.9
			end
		end
		if active and (mine or onMe) then showToast(lastReason, (mine and msg.outcome == Tackle.TACKLED) and "good" or
			(onMe and msg.outcome == Tackle.BROKEN) and "good" or "bad") end

	elseif msg.kind == "contest" then
		lastReason = tostring(msg.reason or "")
		if active then
			local mineWon = isMe(msg.winner)
			showToast(("%s · %s"):format(tostring(msg.result), lastReason), mineWon and "good" or "warn")
		end
	end
end)

print("[TackleClient] Stage 3 contact client ready")
