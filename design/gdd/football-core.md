# Football Core — ALLSTAR WORLD

> **Status: AUDITED AGAINST THE BUILD — 2026-11-02.** This document describes
> **what exists in the Roblox place**, verified by reading the scripts. It is no
> longer a greenfield spec.
>
> Engine: Roblox (Luau). **Units: METRES, SECONDS, DEGREES.** `Config.S = 1/0.35`
> converts metres to studs (1 stud = 0.35 m). Studs appear only where the code
> genuinely works in studs: field placement, rig measurements, part sizes.
>
> **Every rule below is tagged.** `BUILT` = verified in the code, with the file and
> line. `PARTIAL` = some of it is there. `NOT BUILT` = no code exists. Anything the
> earlier draft invented and the code does not have has been moved into a
> clearly-labelled **Proposed, not built** block at the end of its section — those
> blocks are design intent, not description.
>
> **Nothing is described as built unless it was verified in the code.** The audit
> trail, including real bugs found in passing, is `/home/claude/audit/findings.md`.
> Cached sources: `/home/claude/extracted/`.
>
> Monetization: cosmetic only. Verified — no value in any of the four config
> tables is purchase-linked.

---

## 1. Overview

**Status: BUILT (Practice Field) + BUILT-ELSEWHERE (1v1 / team modes).**

Football Core is the server-authoritative ball, possession and catching layer for
ALLSTAR WORLD football. It exists today as **two codebases**, and this document
covers both honestly rather than pretending there is one.

**The Practice Field "Ball Lab"** — `ReplicatedStorage.AWPractice` (6 modules),
`ServerScriptService.PracticeService` (1107 lines),
`StarterPlayer.StarterPlayerScripts.PracticeClient` (892 lines). This is the
current, better-engineered core: momentum movement, a 5-state ball machine with a
revision counter, possession claims, three pass types on a deterministic analytic
arc, and a rig-measured deterministic catch model with tips and deflections. It
has **no defender, no tackling, no play cycle, no downs and no score.**

**The older 1v1 and team modes** — `ReplicatedStorage.AWFootball`
(`Config`, `Rules`), `ServerScriptService.FootballService` (1198 lines),
`ServerScriptService.TeamFootballService`, plus their clients. These have what the
Practice Field lacks: tackling, wrap-and-break, juke/spin/stiff-arm, a snap
cadence with false starts, 5 routes, jump balls, downs, possessions, overtime and
an AI quarterback. They use a **different, partly random catch model** and a
different gravity.

Every outcome is decided on the server. The ball is never a physics object and no
client ever owns it. Clients send *intents*; they predict visuals only.

**The single most important open question in this document is which catch model
wins.** See OPEN-DECISIONS A1.

---

## 2. Player Fantasy

**Status: BUILT in spirit — the build pursues this harder than the draft did.**

**"I beat him clean, and I know exactly how."** The receiver should feel like a
playmaker: a sharp cut opens a window, the ball arrives in stride, and a late
high-point catch feels earned. The defender should feel like a hunter: reading the
route, closing ground, timing the hit. Every win and loss has a readable cause.
That serves **Challenge** first, then **Sensation** and **Expression**.

SDT targets: **Competence** from deterministic resolution and reason tags.
**Autonomy** from real route and move choices. **Relatedness** from 1v1 rivalry
and QB-receiver chemistry.

**How the build delivers this, verified:** every catch attempt produces a
human-readable `reason` string — `"OVER THE SHOULDER"`, `"HANDS LATE · TIPPED IT"`,
`"TOO HOT · 24 m/s OFF YOUR HANDS"`, `"NO FOOT IN BOUNDS · INCOMPLETE"`,
`"FINGERTIPS · COULDN'T HANG ON"` — which is sent to **both** the receiver and the
thrower, shown over the player's head, and written to a 400-entry result log
(`PracticeService:579-608`, `Receive.judge` in `Receive.lua:171`). The Practice
Field catch model contains **no randomness at all**. That is a stronger delivery of
"I know exactly why" than the draft's drop-probability formula would have been.

Where the fantasy is *not* yet delivered: there is nobody to beat on the Practice
Field. Separation, contest and the defender's whole half of the fantasy live only
in `AWFootball`.

---

## 3. Detailed Design

### 3.1 Authority model — BUILT

`PracticeService:1-16, 80-89`.

- The server owns ball state, who holds it, where it is, and every change.
- The ball part is `Anchored`, `CanCollide = false`, `CanQuery = false`,
  `CanTouch = false`, parented to `19_PracticeField.Runtime`, and is moved **only**
  by `PracticeService` (`placeBallPart`, line 899). No physics, no network
  ownership, no client-owned ball. There is also a purely local visual ball on each
  client (`PracticeClient:178`) which is hidden whenever the server ball is visible.
- Each player's own device moves their character (Roblox default). The server does
  not trust it and checks it (3.9).
- Clients send intents only. The remote surface is **two RemoteEvents**:
  `AWPractice.Remotes.Intent` (client to server) and `.State` (server to client)
  (`PracticeService:70-77`).
- Intents: `grab`, `handoff`, `drop`, `reset`, `throw`, `catchDown`, `catchUp`,
  `catchIntent`, `qb`, `partner` (`onIntent`, line 745).
- State messages: `{kind="ball", state, rev, holder, holderName, cause, flight}`,
  `{kind="fb", text, tone}`, `{kind="contact", who, p, result}`,
  `{kind="caught", ...}`, `{kind="stats", rejects}`.
- State changes are coalesced to **one broadcast per server step**
  (`queueBroadcast`/`flushBroadcast`, lines 113-117), so a burst cannot queue up on
  clients.

### 3.2 The revision counter — BUILT, and the key safety rule

`BallState.lua:2-3`, `PracticeService:128`.

Every state transition increments `ball.rev`. Every client intent carries the
`rev` the client last saw (`PracticeClient:266-270`). The server refuses any
request quoting a stale `rev` and counts it (`stats.stale`; see lines 293, 311,
426, 780).

**This one rule replaces a whole category of machinery.** It kills duplicate
button taps, "two people grabbed it" races, and actions queued against a ball that
has already moved on — without a `playId`, a `seq`, or a sequence-ordering
protocol. It is the pattern the earlier draft of this document missed entirely, and
it should be carried into every future mode.

### 3.3 Movement — BUILT

`AWPractice.Momentum` (pure maths, no Roblox objects — unit-testable as the repo's
standards require), driven by `PracticeClient:528` (`moveStep`).

Movement is **client-simulated** for instant response; the server only checks the
limits. The client replaces `ControlModule.moveFunction` with its own capture
(`takeOverMovement`, line 435) and drives `Humanoid:Move` plus `WalkSpeed` from the
model's output. It binds to `RunService:BindToSimulation(…, Hz60)` when the engine
offers it, else `PreSimulation` (lines 551-572). Movement is taken over **only
inside the practice zone** and released on leaving (line 567).

State is three numbers: `{ speed (m/s), hx, hz (unit ground heading) }`.
`Momentum.step(st, wantX, wantZ, sprint, carrying, grounded, dt, cfg)`.

| Rule | Behaviour | Where |
|---|---|---|
| Top speed | `(sprint and 7.8 or 6.0) * (carrying and 0.96 or 1)` m/s | Momentum:25 |
| Acceleration | linear, `sprint/accelTime` = **13 m/s^2** | Momentum:26 |
| Braking | linear, `sprint/brakeTime` = **26 m/s^2**; `* 0.6` when easing to a lower target | Momentum:27, 53 |
| No input | brake toward 0 along the current heading | Momentum:30-33 |
| From a standstill | below 0.05 m/s you may face anywhere instantly | Momentum:36 |
| Turn rate | `720 deg/s` at rest, falling **linearly** to `260 deg/s` at full sprint | Momentum:46 |
| Turn speed cost | target speed `* (1 - 0.45 * left/180)`, where `left` is the angle the turn could **not** cover this frame | Momentum:48 |
| Still-turning cap | if `left > 60 deg`, target speed is capped at pivot speed (4.29 m/s) | Momentum:49 |
| Hard cut (plant) | if the requested change `> 75 deg` **and** speed `> 4.29 m/s`: brake at full rate toward pivot speed, turn at only `130 deg/s`, and **do not accelerate this frame** | Momentum:40-45 |
| In the air | accel, brake and turn rate all `* 0.35` | Momentum:28 |
| Jump | `UseJumpPower = false`, `JumpHeight = 0.75 m` | PracticeClient:499 |

**Naming warning.** `turnFast = 720` is the turn rate **at a standstill**;
`turnSlow = 260` is the rate **at full sprint**. The names describe the turn, not
the runner. Read them backwards and every movement conclusion inverts.

Two extra caps the model does not know about, applied after it
(`PracticeClient:537-540`):

- Holding CATCH with `secure` intent caps you at `jog * 0.92` = **5.52 m/s**.
- For `recoverTime` after a catch, you are capped at `sprint * recoverMul` (3.9 m/s
  after an aggressive catch, 5.85 after a secure one, uncapped after catch-and-run).

And one correctness guard (line 544): if the body is physically slower than the
model — a wall, a teammate — momentum is clamped to `actual + 1.5`. You never run
ahead of your own body.

**Why continuous, not threshold-based.** The cost of a direction change is
proportional to how much of it is still owed at the end of the frame, so there is
no cliff at a magic angle: a 70-degree cut at sprint and a 76-degree cut at sprint
feel one notch apart rather than like two different mechanics. Only the plant
(> 75 deg at speed) is a discrete state, and it is discrete because it is a
*physical* event — a foot in the ground.

#### Proposed, not built (movement)

- **Stamina.** The earlier draft specified a 100-point sprint meter with drain,
  two regen rates, a delay, an exhaustion lockout and per-move costs. **None of it
  exists, and nothing in the code suggests it was ever planned.** It is a real
  design option — it would stop sprint-everywhere play — but it would be a new
  system, not a correction. Carried forward as a proposal only; see
  OPEN-DECISIONS D1.
- **Stumble and Grounded states** as first-class movement states with input
  lockout. `AWFootball` has effects that resemble them (`pedal.beatenStumble 0.3`,
  `recoverUntil`, `stun`) but there is no shared state machine.
- **Evade cooldown chaining** (each evade in a play stretching later cooldowns).
  `AWFootball` has flat per-move cooldowns only.

### 3.4 Ball states — BUILT

`AWPractice.BallState`. Five states; the transition table (lines 22-28) is the
whole specification.

| State | Meaning | Legal exits |
|---|---|---|
| `TEE` | Dead ball on the tee, ready to pick up | `HELD`, `DEAD` |
| `HELD` | One athlete has it, in the hand | `HELD` (hand-off), `LOOSE`, `DEAD`, `IN_FLIGHT` |
| `IN_FLIGHT` | Thrown; flying a fixed arc decided at release | `HELD` (caught), `DEAD`, `IN_FLIGHT` (tipped) |
| `LOOSE` | On the ground or bouncing; anyone close can scoop it | `HELD`, `DEAD` |
| `DEAD` | Whistle; untouchable | `TEE` |

Three things here are better than the earlier draft and are deliberate:

- **`HELD -> HELD` is a hand-off.** The draft had no hand-off at all.
- **`IN_FLIGHT -> IN_FLIGHT` is a tip.** A ball that touches hands or a body and
  is not caught **stays live on a new arc** rather than dying
  (`PracticeService:609-612`, `Receive.deflect`). A forward pass that then hits the
  ground is still incomplete. This is real football and the draft missed it.
- **There is no `CONTESTED` state.** Contests are resolved inside the flight sweep
  (3.7), not by parking the ball in a state and opening a window.

An illegal transition is refused, warned and counted (`setState`, line 121;
`stats.illegal`). `DEAD` returns to `TEE` after `ball.deadDelay = 0.6 s`, or
`0.25 s` for the four `QUICK_RESET` causes (line 137).

**NOT BUILT:** `SNAPPED`. There is no snap on the Practice Field.

### 3.5 Possession and claims — BUILT

`PracticeService:256-331, 771-809`.

- **Reach to grab** (`reachInfo`, line 265): flat distance `<= grabReach 1.3 m +
  latencySlack 0.35 m`, and vertical offset within `[-grabBelow 1.35,
  +grabAbove 0.9]` m. You can scoop a ball at your feet; you cannot grab one over
  your head.
- **Claims are batched and settled together once per server step**
  (`resolveClaims`, line 771). The **closest valid body wins**; an exact tie
  (within `tieMetres 0.02 m`) goes to whoever's request reached the server first.
  **One winner, always.** Losers are told `"BEATEN TO IT"` and counted
  (`stats.beaten`).
- `grabCooldown 0.25 s` per player. `net.maxIntentsPerSecond 12` token bucket
  (`takeToken`, line 277).
- **Hand-off** (`doHandoff`, line 291): you must hold the ball, be off
  `receiveLock 0.3 s` since receiving it (`"SECURE IT FIRST"`), and be within
  `handoffReach 1.7 m + latencySlack`. The target must be in the zone and not
  locked out.
- **Drop** (`doDrop`, line 309): the ball takes `dropInherit 0.6` of your running
  velocity plus `dropForward 1.0` m/s along your facing and `dropUp 1.4` m/s up.
  **Dropping during the securing window is an incompletion, not a loose ball**
  (line 312) — "never secured it".
- **Reset** (`doReset`, line 324): returns the ball to the tee,
  `resetCooldown 2.0 s`. *See OPEN-DECISIONS B1 — this currently has a griefing
  hole.*
- A carrier who walks further than `leaveMarginM 9 m` outside the field loses the
  ball (`"WALKED OFF THE FIELD"`, line 866). A carrier who dies, leaves or whose
  character is removed drops it dead (`dropActor`, line 190).

### 3.6 Passing — BUILT

`AWPractice.Flight`, `PracticeService:424-461`.

**Type is chosen by how long you hold THROW** (`Flight.kindForHold`):

| Type | Hold | Flight model | Speed / time |
|---|---|---|---|
| `BULLET` | `< 0.2 s` | fixed arm speed, **low-angle** ballistic root | `bulletSpeed 21 m/s` |
| `TOUCH` | `0.2`-`0.55 s` | flight time grows with distance | `T = 0.55 + 0.04*d` (20 m -> 1.35 s) |
| `LOB` | `> 0.55 s` | same, higher arc | `T = 1.3 + 0.045*d` (20 m -> 2.2 s) |

Hold is clamped to `maxHold 1.5 s`. The client draws an 18-dot arc preview and a
three-zone hold meter live while you hold (`PracticeClient:798-814`), using the
*same* `Flight.solve`, so the arc you are shown is the arc the server flies.

**Two failure modes, both readable:**

- A BULLET whose discriminant goes negative physically cannot reach the target at
  21 m/s, so the kind **silently degrades to TOUCH** (`Flight.lua:33`).
- A TOUCH or LOB needing more than `maxSpeed 26 m/s` has its velocity scaled down
  and returns `short = true`, surfaced as `"OUT OF RANGE · FELL SHORT"`
  (`describeMiss`, line 477).

**Gates on a throw** (`doThrow`): you must hold the ball with the current `rev`;
`throwCooldown 0.35 s` since receiving it (`"SET YOUR FEET FIRST"`); a valid target
in the zone; distance within `[2.5, maxRange 55] m` (closer than 2.5 m tells you to
hand it off); and the throw direction within `maxOffFacing 120 deg` of your facing
(`"CAN'T THROW BEHIND YOU"`).

**Target selection** is client-side and camera-based (`pickReceiver`,
`PracticeClient:272`): the candidate closest in angle to the camera's flat look
vector, within `targetCone 40 deg` and the distance band. The server re-validates
the target instance. There is no ground reticle and no placement offset.

**Aim and error.** The aim point is the receiver's root plus `catchUp 0.25 m`
(chest). The release point is the thrower's root plus `releaseUp 0.55 m` (ear).
The landing point is displaced from the aim by a **uniform sample inside a disc**
of radius `errorRadius` (`PracticeService:446`: `r = errR * sqrt(rand)`, uniform
angle) — not a Gaussian. Once released nothing steers it.

    errorRadius = base[kind] + perM[kind]*d + moving*speedFrac^2
                  + facingK*(offFacing - facingFree)/90   [if offFacing > 30]
                  + pressure

See 4.3 for the values. **`pressure` is plumbed through and always passed 0**
(`PracticeService:445`) — the parameter waits for a defender that does not exist.

**Ball does not inherit thrower velocity.** Running is penalised through the
`moving * speedFrac^2` error term instead.

**The stand-in partner as a thrower — PARTIAL.** `doQB` (line 726) /
`partnerThrow` (line 671) make an anchored dummy throw you TOUCH, BULLET and LOB in
rotation after a 0.9 s beat. It aims at your hands (chest + `0.38 m` along your
facing), and runs **four fixed-point iterations** of solve-then-re-lead
(lines 688-692) to converge on where you will be when the ball arrives — a real
lead calculation, done numerically. Its error radius is the standard one `* 0.6`.
It can be placed at `partnerYards {8, 15, 25, 35}`. **It has no decision-making
whatsoever**: it throws when you ask it to.

#### Proposed, not built (passing)

- **Mouse/gamepad/touch aim parity** — a ground reticle with `AIM_ASSIST_RADIUS`,
  a capped placement offset, right-stick receiver selection and tappable receiver
  icons. The build has one mechanism (camera cone) for all three input types. The
  draft's fairness concern (touch players cannot fine-tune placement) **does not
  currently apply, because nobody can**.
- **Pressure error.** The term exists at `pass.err.pressure = 1.0 m` and is never
  applied. Wiring it up is Stage 3 work.
- **A closed-form intercept solve.** The draft's quadratic is mathematically
  equivalent to what `partnerThrow` converges on numerically. The numerical
  version is already correct and handles the speed clamp; no reason to change it.

### 3.7 Catching — BUILT, and this is the strongest part of the build

`AWPractice.Receive` (253 lines) decides; `PracticeService:505-614` sweeps;
`PracticeClient:574-672` poses the arms.

**Reach is measured, not configured.** `Receive.rig` (line 43) reads the
character's own R15 joints — `Shoulder`, `Elbow`, `Wrist` — and measures the upper
arm (shoulder to elbow) and forearm (elbow to palm) **in each part's own space**,
because avatar arms are not always aligned with the part's Y axis. Reach is their
sum, per side. A taller avatar with longer arms genuinely reaches further; a
smaller one genuinely does not. There is no catch radius knob anywhere.

**Hands go up on a hold, and take time.** `Receive.RAISE = 0.12 s` from pressing
CATCH to hands fully up. `handsAt` (`PracticeService:343`) returns the raised
fraction at a given server time.

**Intent is chosen by what you are doing, never from a menu**
(`Receive.INTENTS`, line 28; selected client-side by `currentIntent`,
`PracticeClient:312`):

| intent | chosen when | reach mul | speed allowance | securing | after the catch |
|---|---|---|---|---|---|
| `secure` | hands up, jogging or standing | 0.97 | 26 m/s | 0.30 s | speed x0.75 for 0.25 s |
| `run` | hands up while sprinting | 0.94 | 22 m/s | 0.16 s | no penalty |
| `aggressive` | JUMP with hands up | 1.00 | 24 m/s | 0.36 s | speed x0.50 for 0.45 s |

**Contact detection is a true sweep, not a sample** (`sweepReceiver`, line 505):

- The ball's real path is stepped at `SUB = 1/240 s` — about 11 cm at the fastest
  throw.
- The body is a **capsule**, tested segment-against-segment
  (`Receive.hitsBody` / `segSeg`). A fast ball cannot tunnel through anyone.
- Hands count only while raised, and the contact point is where the ball comes
  **closest to the hands' sweet spot** (`mid + look*0.38 m - 0.12 m` vertical), not
  the first point of overlap: the loop keeps improving `rec.inside` while the ball
  closes and commits when it starts receding (lines 534-547).
- A ball that passed through reach while hands were down sets `rec.wentBy`, which
  becomes the message `"NO HANDS UP · IT WENT RIGHT BY"`.
- `Receive.reachable` (line 126) also models **crouching** for a low ball
  (shoulders drop up to `CROUCH 0.45 m`), `BACK_SLACK 0.12 m` behind the shoulder
  line at chest height, and `OVERHEAD_BACK 0.38 m` behind it over your head — which
  is what makes the over-the-shoulder catch possible.

**The decision is fully deterministic — there is no drop roll anywhere**
(`Receive.judge`, line 171):

1. `raised <= 0` -> `OFF_BODY`, `"NO HANDS · IT HIT YOU"`.
2. `raised < 1` -> `TIPPED`, `"HANDS LATE · TIPPED IT"`.
3. Otherwise compute a speed limit and compare it to `rel`, the ball's speed
   **relative to your body** (`bodyVel` from the server's own position history, so
   a client cannot claim a speed):

| Modifier | Multiplier |
|---|---|
| start | the intent's allowance (22-26 m/s) |
| body trap, no hands | x0.8 (and x0.85 again if `aggressive`) |
| one hand only | x0.72 |
| fingertips (`stretch > 0.85`) | x`(1 - (stretch - 0.85) * 2.2)` |
| over the shoulder | x0.85 |
| airborne but not `aggressive` | x0.9 |

   `rel > limit` -> `OFF_HANDS`. Fingertips at an otherwise catchable speed gets
   its own message, `"FINGERTIPS · COULDN'T HANG ON"`.
4. A ball behind you is `OFF_BODY`, `"HIT YOU IN THE BACK · TURN AROUND"`
   (`PracticeService:571`).
5. **A catch needs a foot in bounds** (`insideLines`, line 396 — the body footprint
   plus 0.15 m, the college rule). Outside -> `"NO FOOT IN BOUNDS · INCOMPLETE"`.

**Catch classification** (`Receive.classify`, line 152) names the catch for poses
and messages: `overShoulder`, `jump`, `high`, `low`, `reachR`/`reachL`, `chest`,
`body` — mapping to `"HIGH-POINTED IT"`, `"SCOOPED IT"`, `"REACHED OUT"` and so on.
A ball travelling the way you face counts as over-the-shoulder.

**Deflections are deterministic** (`Receive.deflect`, line 199) and keep the ball
live on a new arc:

| outcome | new velocity (m/s) |
|---|---|
| `TIPPED` | `flat * 0.18 + (0, 4.2, 0)` — pops up |
| `OFF_HANDS` | `-flat * 0.28 + look * 0.4 + (0, 1.8, 0)` — rebounds off the hands |
| `OFF_BODY` | `-flat * 0.12 + (0, 1.2, 0)` — drops |

The deflector gets a `0.45 s` grace before they can touch it again
(`startFor`, line 611).

**Arms are posed by IK, not animation** (`Receive.solveArm`, line 222;
`PracticeClient:607-672`). There are no catch animations in the game. Every frame,
after the running animation runs, a two-bone IK solver writes the shoulder and
elbow `Transform` so the palms sit where the ball will meet you — found by sampling
the arc for its closest approach (`meetPoint`, `PracticeClient:581`). The arm never
stretches: an unreachable target gets a fully-extended arm pointing at it. The
chest turns up to 35 degrees toward the ball and the head tracks it. It blends in
over `RAISE` and out again.

**Whose catch is it — BUILT** (`stepFlight`, line 616). This is the lag-fair part:

- Every eligible receiver is swept **only up to the moment their own screen is
  showing**: `now - receiverLag(c) - f.t0`, where
  `receiverLag = clamp(ping*0.5 + 0.02, 0, catch.lagMax 0.15)`.
- The **earliest contact wins — but the result is held until no one else could
  still have got there first** (`minCursor` gate, line 644). A low-ping player
  cannot win a ball simply by being resolved sooner.
- Exact tie -> the intended receiver; then the offense (line 640).
- The thrower cannot catch their own forward pass unless it was deflected
  (`eligible`, line 495).

This solves contested catches without a position-history ring buffer, because the
thing that has to be rewound is the **ball**, and the ball's path is analytic.

#### Proposed, not built (catching)

- **Box-out scoring.** The build has no notion of body position between an
  opponent and the ball. This remains the single best idea the earlier draft
  contributed that the code lacks, and it becomes necessary the moment a defender
  exists. The draft's `BOXOUT_BONUS / BOXOUT_ANGLE` and its
  timing/position/height weighted score are the starting point.
- **A height component.** Jump timing matters in `AWFootball` but not on the
  Practice Field, where a jump only changes your intent and your shoulder height.
- **Interceptions.** `a.defense` exists as a flag on test dummies
  (`PracticeService:1056`) and is read in exactly one tie-break. Nothing else
  distinguishes a defender, and there is no interception outcome.
- **The additive drop-probability model** (`DROP_BASE`, `DROP_OVER_SHOULDER`,
  `DROP_REACH_BACK`, `DROP_HOT_BALL`, `DROP_DIVE`, `DROP_HIT`, `DROP_SECURE`,
  `DROP_MAX`, `INT_DROP_BASE`) is **withdrawn, not deferred.** The built model
  already expresses every one of those factors deterministically, through the speed
  limit and its multipliers, and the built model is more readable. Reintroducing a
  probability roll would move the design away from its own pillar.
- **Diving catches.** No dive exists on the Practice Field.

### 3.8 Loose-ball physics — BUILT

`stepLoose` (`PracticeService:876`), substepped at `ball.substep = 1/120 s`,
server-only, custom (not Roblox physics):

- Gravity `9.81 m/s^2`.
- On ground contact: if downward speed exceeds `1 m/s`, keep `bounce 0.35` of it
  upward; otherwise stop vertical motion.
- Horizontal: `groundFriction 5.0 m/s^2`, stopping below `settleSpeed 0.15 m/s`.
- Visual spin and yaw are derived from horizontal speed (lines 895-896).
- An untouched loose ball goes dead after `looseTimeout 12 s`
  (`"LEFT TOO LONG"`), or immediately if it leaves `leaveMarginM 9 m`.

### 3.9 Anti-cheat and movement validation — BUILT

`checkMovement` (`PracticeService:831`), running at **10 Hz** (line 939).

- **Distance budget**, not a strike counter: the budget refills at
  `sprint * speedSlack = 9.36 m/s` and is capped at `burstM 3.5 m`, then each step's
  distance is subtracted. Late or bunched network updates cannot trip it, but
  sustained over-speed drains it within about a second (lines 854-859).
- **Teleport check**: any single step over `teleportM 6 m` is rejected outright.
- On rejection (`reject`, line 814): `stats.rejects`, a `lockout 1.0 s` ban on all
  ball actions, `AssemblyLinearVelocity` zeroed, character pivoted back to
  `lastGood`, and **the ball goes dead if they were carrying it**. The player is
  told `"MOVEMENT CHECK FAILED · PULLED BACK"` and their reject count is shown in
  their own HUD.
- `placedGrace 1.5 s` skips checks after the game itself moves you (join, respawn,
  entry pad).
- **Rate limiting**: token bucket, `maxIntentsPerSecond 12` (`takeToken`,
  line 277). *One path bypasses it — see OPEN-DECISIONS B2.*
- **Payload validation**: `typeof` checks on action and data (line 746),
  `typeof(target) == "Instance"` before any model lookup, `tonumber` coercion with
  defaults, `math.clamp` on hold time.
- **Claimed timestamps** (`clientTime`, line 337) are clamped to
  `[now - min(catch.lagMax 0.15, ping*2 + 0.05), now]`. No claims from the future;
  nothing older than the grace.
- The partner and test dummies are exempt (`isPartner`, `dummy`, line 833).

### 3.10 Tackling and ball-carrier moves — NOT BUILT on the Practice Field; BUILT in `AWFootball`

There is **no tackling, no defender, no sack, no juke, no spin and no stiff-arm on
the Practice Field.** What follows is what exists in the older 1v1 and team modes,
recorded here because it is real, working code that any Practice Field
implementation should either reuse or consciously replace.

`Rules.resolveTackle` (`AWFootball.Rules:30`) — **fully deterministic, no dice.**
Returns one of six outcomes, gated in this order:

| Gate | Rule | Result if failed |
|---|---|---|
| Live | carrier must be live and have the ball | `NOT_LIVE` |
| Range | `d <= reach` (`tackle.reach 1.35 m`, or `lungeReach 1.7 m` while lunging) | `NO_CONTACT` beyond `reach + 1.2 m`, else `WHIFF` |
| Facing | `cos(angle to carrier) >= facingCos 0.15` | `WHIFF` |
| Immunity | carrier's `immuneUntil` not yet expired | `EVADED` |
| Clean | closing speed `>= cleanClosingSpeed 4.0 m/s` **and** approach angle `>= cleanAngleCos -0.2` | `WRAP` |
| — | both satisfied | `CLEAN_TACKLE` |

So a hit taken square and at speed is a `CLEAN_TACKLE` (immediate down); a weak or
badly-angled hit is a `WRAP`.

**A wrap is a contest, not a result** (`FootballService:814-856`): the carrier gets
`breakWindow 0.35 s` to press juke, spin or stiff-arm and escape (`breakWrap`,
line 830); otherwise `wrapDrag 0.45 s` later they are down (`finishWrap`,
line 845). Breaking out costs the tackler a 0.6 s stun and grants the carrier
`0.35 s` of immunity. The CPU's break is a `cpuBreakChance 0.35` roll (line 786) —
the only randomness in the tackle path.

**Carrier moves** (`FootballService:1052-1078`):

| Move | Effect | Cooldown | Immunity granted |
|---|---|---|---|
| Juke (L/R) | `jukeSpeed 12.5 m/s` lateral for `jukeTime 0.22 s` | 1.1 s | `jukeImmunity 0.28 s` |
| Spin | `spinSpeed 6.5 m/s` for `spinTime 0.42 s` | 1.6 s | the spin duration |
| Stiff-arm | within `stiffArmReach 1.6 m` and front arc (`cosA > -0.2`): stuns the defender `stiffArmStun 0.7 s` | 1.4 s | 0.3 s |

**There are no fumbles anywhere in the codebase.** `script_grep "fumble"` returns
nothing. The `LOOSE` state on the Practice Field is reached only by a voluntary
drop or the partner setting the ball down.

#### Proposed, not built (tackling)

The earlier draft's **counter matrix** (wrap loses to stiff-arm and spin; dive
beats both but loses to a juke and is costly on a miss) is a genuinely better
*design* than what is built, because the build has only one tackle type and
therefore no rock-paper-scissors at all. Keep it as the target shape.

Also proposed and unbuilt: **dive tackling**, **momentum-break** (a wrap from
behind against a faster carrier becoming a stumble), **gang tackle**, the
**probabilistic `P_break`** model, and **fumbles** in any form. Note that the
built `resolveTackle` is deterministic and the draft's `P_break` is a dice roll;
if the project keeps its "I know exactly why" pillar, the built approach is the
one to extend.

### 3.11 Play cycle, downs and scoring — NOT BUILT on the Practice Field; BUILT in `AWFootball`

The Practice Field has **no play cycle at all**: no Ready, no pre-snap, no snap, no
whistle, no spot, no clock. The ball always returns to the same tee.

`AWFootball.Config.rules` **answers the scoring questions the earlier draft left
blank**:

    rules = { possessionsEach = 5, downs = 4, td = 7,
              startYard = 20, otPossessionsEach = 1, maxOtRounds = 3 }

What `FootballService` actually does with them (lines 342, 860-909):

- Each side gets **5 possessions**, each starting **20 yards** from its own goal.
- **4 downs, then turnover on downs.** **There are no first downs.** Yards gained
  are computed and displayed (`Rules.yardsBetween`) but never reset the down
  counter. A possession is "four plays, then it is the other player's turn."
  `script_grep "firstDown"` finds nothing engine-wide.
- **Touchdown = 7.** No kicking, no extra point, **no safety in 1v1**
  (`safety = 2` exists only in `TeamFootballService`'s own local table).
- Tie after regulation -> up to **3 overtime rounds** of one possession each.
- **False start is a real penalty**: -5 yards and replay the down
  (`stance.falseStartYards`, line 499).
- A snap cadence with `perfect 0.15 s` / `good 0.35 s` release windows and a
  `perfectBurst 1.18` / `goodBurst 1.08` speed bonus for `burstTime 0.7 s`
  (`AWFootball.Config.stance`).
- DB backpedal with a hip flip: `pedal.speed 6.6`, `flipTime 0.18 s`,
  `beatenMargin 0.6 m`, `beatenStumble 0.3 s`.

**Routes — PARTIAL.** Five exist (`Rules.ROUTES`): `slant`, `curl`, `post`, `fade`,
`cross`, plus `free` (free run), selected pre-snap with keys 1-6. The draft's
8-route tree is aspirational: **Out, In/Dig, Go and Comeback do not exist.**

**Jump balls — BUILT in `AWFootball`** (`Rules.resolveJumpBall`, line 70). Each
contestant's jump-timing error against apex (`jumpApexTime = jumpSpeed/gravity =
6.2/22 = 0.282 s`) is compared; nearest wins. The defender needs `swatReach 1.7 m`
to swat and `intReach 0.95 m` to intercept. An `aggressive` receiver gets an
`aggressiveMargin 0.05 s` tiebreak. Nobody jumping in time -> incomplete,
`"mistimed the jump"` or `"nobody went up for it"`.

**The `AWFootball` normal-catch model is substantially random** and is the main
reason this document asks for a decision: `Rules.resolveCatch` (line 93) sets a
reach and a *quality*, then rolls against it — human secure 0.97, aggressive 0.80,
no press `autoChance 0.50`, mistimed press 0.35, CPU `cpuBase 0.86` minus
`cpuContestedPenalty 0.4` when contested. Seeded LCG, `seed = 1337`.

#### Proposed, not built (play cycle)

Everything in the draft's play cycle that `AWFootball` does not have: an
**invisible LOS wall** preventing offside rather than penalising it; **forward
progress** spotting; **first downs**; **safeties** in 1v1; `PLAY_MAX_DURATION` as
a stall-breaker; `LOOSE_BALL_MAX_TIME`; and an explicit **Ready/huddle** phase with
a play-selection timeout.

### 3.12 AI quarterback — NOT BUILT on the Practice Field; BUILT in `AWFootball`

The Practice Field's "partner" is an anchored R15 dummy with an idle animation
(`buildPartner`, `PracticeService:222`). **It has no AI.** It throws only when a
player presses THROW ME, and it cycles TOUCH -> BULLET -> LOB regardless of
anything on the field. None of the draft's throw triggers (separation reached, call
for ball, defender crosses the LOS, max hold) exist here.

`AWFootball.Config.qb` is a real AI QB used by `FootballService`:
`dropbackDepth 3.0 m` over `dropbackTime 0.8 s`, `minReadTime 1.1 s`, forced throw
at `deadline 3.4 s`, `windup 0.35 s`, throw speed `14`-`24 m/s`,
`accuracy 0.82`, `rushedPenalty 0.9`, `leadFactor 0.85`. `TeamFootballService`
adds `openSeparation 2.4 m`.

#### Proposed, not built (AI QB)

The draft's explicit four-trigger model (separation threshold decaying over time,
call-for-ball, blitz response, hard deadline) with per-snap timing jitter is
clearer and more auditable than `accuracy 0.82` plus a deadline, and it is the
right target. Its `SEP_START / SEP_DECAY / SEP_MIN` curve has no counterpart in the
code.

### 3.13 Route practice mode — NOT BUILT

No route selection, no ghost route line, no per-rep feedback (break timing,
separation proxy, YAC), no session stats, no instant reset loop. The Practice Field
is a ball lab, not a route drill. The draft's §3.11 is entirely a proposal.

### 3.14 Controls — BUILT (Practice Field)

`PracticeClient:6-10` and the binding block. Context-sensitive: the same button
changes meaning by what you can currently do.

| Action | KB/M | Gamepad | Touch |
|---|---|---|---|
| Move | WASD | Left stick | Left virtual stick |
| Sprint (hold) | Shift | RT | SPRINT |
| Hands up / grab / hand off (hold) | E | X / Square | CATCH / GRAB / HAND OFF |
| Jump catch (`aggressive`) | Space while hands up | A | Roblox jump button |
| Throw (hold to pick type) | F | RB | THROW |
| Drop | Q | B | DROP |
| Ball back to the tee | R | Y | TEE |
| Partner throws me a pass | T | D-pad down | THROW ME |
| Move the partner downfield | — | — | PARTNER |
| Debug overlay | O | D-pad left | DBG |

**One button, three catches.** CATCH is held, and the *intent* is read from what
you are doing when the ball arrives: standing or jogging gives `secure`, sprinting
gives `run`, jumping gives `aggressive` (`currentIntent`, line 312). Changing what
you are doing mid-hold re-sends the intent (line 742). There is no catch-type menu
and no extra button — this is a better control design than the draft's separate
dive-catch button and it should be preserved.

**Touch shows 8 buttons, re-laid out for phone vs tablet** (`layout`, line 151).
This breaks the draft's own "at most 4 context buttons" rule. See OPEN-DECISIONS D4.

### 3.15 Debug and feedback overlay — BUILT

`PracticeClient:191-203, 746-785`. Toggled with O / D-pad left / DBG. Shows: a
ForceField sphere per shoulder sized to **that avatar's actual reach** times the
current intent's multiplier; the hands' sweet spot; the ball's predicted arc as 18
dots coloured by pass type; the last contact point coloured by caught/not; a
billboard over your head reading `HANDS UP · GO GET IT / raising 64%`,
`TRACKING · HANDS DOWN`, `SECURING`, or `CAUGHT`/`NO CATCH` with the reason; and a
panel with live speed, measured 0-to-full-sprint time, ball state, ball `rev`,
ping, and failed movement checks.

This is a real diagnostic tool and it is why the catch model can be tuned by feel
without guessing.

---

## 4. Formulas

All in **metres and seconds**. Degrees where marked. Every formula below is in the
code at the cited line.

### 4.1 Movement

#### 4.1.1 Acceleration and braking — BUILT (`Momentum.step`, lines 26-27, 50-54)

    accel = sprint / accelTime = 7.8 / 0.6 = 13.0 m/s^2
    brake = sprint / brakeTime = 7.8 / 0.3 = 26.0 m/s^2

    if speed < target:  speed = min(target, speed + accel * control * dt)
    else:               speed = max(target, speed - brake * 0.6 * control * dt)
    no input:           speed = max(0,      speed - brake * control * dt)

| Symbol | Type | Range | Meaning |
|---|---|---|---|
| `speed` | float | 0-7.8 | current speed, m/s |
| `target` | float | 0-7.8 | speed being steered toward |
| `control` | float | {0.35, 1} | 1 on the ground, `airControl` in the air |
| `dt` | float | 0.008-0.05 | frame delta, clamped to 0.05 by the caller |

**This is linear, not exponential.** Output is bounded in `[0, target]` because
both branches clamp to `target`.

**Worked example.** Standstill to full sprint on the ground: `7.8 / 13.0 =
0.60 s`, matching `accelTime` exactly by construction. Full sprint to a dead stop
with no input: `7.8 / 26.0 = 0.30 s`, covering `7.8^2/(2*26) = 1.17 m`. Easing from
sprint down to jog (input still held): rate is `26 * 0.6 = 15.6 m/s^2`, so
`(7.8 - 6.0)/15.6 = 0.115 s`. The client measures the real 0-to-sprint time live
and shows it (`measure`, `PracticeClient:835`), so this is verifiable in-game
rather than asserted.

#### 4.1.2 Turn rate versus speed — BUILT (`Momentum.step`, line 46)

    frac      = clamp(speed / sprint, 0, 1)
    rate(deg) = turnFast + (turnSlow - turnFast) * frac
              = 720 + (260 - 720) * frac
              = 720 - 460 * frac
    maxStep(rad per frame) = radians(rate) * control * dt

| Symbol | Range | Meaning |
|---|---|---|
| `turnFast` | 720 deg/s | turn rate **at a standstill** |
| `turnSlow` | 260 deg/s | turn rate **at full sprint** |
| `rate` | 260-720 deg/s | allowed heading change |

**Output range:** `[260, 720]` deg/s — minimum at sprint, maximum at rest.
**Linear in speed**, with no curve exponent.

**Worked example.** Turning radius `= speed / radians(rate)`. At jog (6.0 m/s,
`frac = 0.769`): `rate = 720 - 460*0.769 = 366 deg/s = 6.39 rad/s`, radius
`6.0/6.39 = 0.94 m`. At full sprint (7.8, `frac = 1`): `rate = 260 deg/s =
4.54 rad/s`, radius `7.8/4.54 = 1.72 m`. So a sprinting athlete needs about
1.7 m of lateral room to round a turn — roughly two body widths, which is what
makes routes have to be run rather than cornered.

#### 4.1.3 Turn speed cost — BUILT (`Momentum.step`, lines 47-49)

`rotateToward` returns `left`, the part of the requested angle it could **not**
cover this frame (0 if it covered all of it).

    target = top * mag * (1 - turnCost * (left / 180))
    if left > sharpTurn (60 deg):  target = min(target, pivot)
    pivot  = pivotFraction * sprint = 0.55 * 7.8 = 4.29 m/s

| Symbol | Range | Meaning |
|---|---|---|
| `top` | {6.0, 7.8} x `carryFactor` | jog or sprint top speed |
| `mag` | 0-1 | stick magnitude (analog sticks give less than 1) |
| `left` | 0-180 deg | residual turn owed after this frame |
| `turnCost` | 0.45 | speed fraction lost for a full 180 deg ask |
| `target` | 0-7.8 | this frame's target speed |

**Output range:** `[top * mag * 0.55, top * mag]`, further capped at 4.29 m/s
whenever more than 60 degrees of turn is still owed.

**Worked example.** A 90-degree ask at full sprint. Frame 1 at 60 fps: `rate` is
260 deg/s, so the turn covers `260/60 = 4.33 deg` and `left = 85.7 deg`. Since
`left > 60`, `target = min(7.8 * (1 - 0.45*85.7/180), 4.29) = min(5.93, 4.29) =
4.29 m/s`, and braking at 15.6 m/s^2 pulls speed down. Over the next frames `left`
shrinks, the pivot cap lifts at `left < 60`, and the penalty term relaxes toward 1.
The net effect is a decisive slow-down into the turn and an acceleration out of it,
with no discontinuity.

**Why this is better than a threshold penalty.** The cost is continuous in the
angle still owed, so there is no single frame where a cut "triggers". A 59-degree
and a 61-degree situation differ by one notch of cap, not by a different mechanic.

#### 4.1.4 Hard cut / plant — BUILT (`Momentum.step`, lines 40-45)

    if ang > cutAngle (75 deg) and speed > pivot (4.29):
        speed = max(pivot, speed - brake * control * dt)      -- full brake, 26 m/s^2
        rotateToward(dir, radians(turnSlow) * 0.5 * control * dt)   -- 130 deg/s only
        return                                               -- no acceleration this frame

| Symbol | Range | Meaning |
|---|---|---|
| `ang` | 0-180 deg | angle between current heading and the requested direction |
| `cutAngle` | 75 deg | above this, at speed, you plant a foot |
| `pivot` | 4.29 m/s | the floor the plant brakes down to |

**Output:** speed falls toward 4.29 m/s at 26 m/s^2 while heading changes at only
130 deg/s. Below `pivot`, or for asks under 75 degrees, the normal path (4.1.3)
runs instead.

**Worked example.** A 120-degree break at full sprint: the plant branch runs for
`(7.8 - 4.29)/26 = 0.135 s`, during which the heading turns `130 * 0.135 =
17.6 deg`. The remaining ~102 degrees are then turned at 4.29 m/s, where
`rate = 720 - 460*0.55 = 467 deg/s`, taking a further `0.22 s`. Total break time
about **0.36 s**, ending at pivot speed facing the new direction. A 180-degree
reversal costs about 0.5 s the same way — slow enough to be a real commitment,
fast enough not to feel stuck.

#### 4.1.5 Carrying and air control — BUILT

    top     = (sprint and 7.8 or 6.0) * (carrying and 0.96 or 1)
    control = grounded and 1 or 0.35

Carrying the ball costs 4% of top speed: sprint 7.49 m/s, jog 5.76 m/s. In the air
accel, brake and turn rate are all at 35%, so a jump commits you to your heading.

### 4.2 Pass flight

#### 4.2.1 BULLET — fixed arm speed, low-angle root — BUILT (`Flight.solve`, lines 25-33)

    disc  = v^4 - g * (g*d^2 + 2*dh*v^2)
    theta = atan( (v^2 - sqrt(disc)) / (g*d) )          -- the FLAT solution
    vh    = v*cos(theta);  vy = v*sin(theta);  T = d/vh
    disc < 0  ->  degrade to TOUCH

| Symbol | Range | Meaning |
|---|---|---|
| `v` | `bulletSpeed` 21 m/s | fixed arm speed |
| `g` | 9.81 m/s^2 | `pass.gravity` |
| `d` | 2.5-55 m | flat distance |
| `dh` | about -0.3 m | target height minus release height |
| `theta` | 0-45 deg | launch angle |

**Output range:** `theta` rises with distance; `disc < 0` at roughly `d > v^2/g =
45 m` for a level throw, which is where BULLET silently becomes TOUCH.

**Worked example, 15 m bullet.** `dh = 0.25 - 0.55 = -0.30`. `disc = 21^4 - 9.81*
(9.81*225 + 2*(-0.30)*441) = 194481 - 9.81*(2207 - 265) = 194481 - 19051 =
175430`, `sqrt = 418.8`. `theta = atan((441 - 418.8)/(9.81*15)) = atan(0.1509) =
8.58 deg`. `vh = 20.76`, `vy = 3.13`, `T = 15/20.76 = 0.72 s`. Apex above release
`= vy^2/(2g) = 0.50 m`. A flat, fast ball that arrives in under three quarters of a
second — exactly the slant-and-comeback tool it is meant to be.

#### 4.2.2 TOUCH and LOB — chosen flight time — BUILT (`Flight.solve`, lines 35-48)

    T  = t0 + tk * d                 TOUCH: 0.55 + 0.04*d     LOB: 1.3 + 0.045*d
    vh = d / T
    vy = (dh + 0.5*g*T^2) / T
    if sqrt(vh^2 + vy^2) > maxSpeed (26):
        scale both by maxSpeed/speed;  short = true
        T = (vy + sqrt(vy^2 - 2*g*dh)) / g           -- time back down to target height

**Output range:** TOUCH `T` runs 0.65 s at 2.5 m to 2.75 s at 55 m; LOB 1.41 s to
3.78 s. Apex above release is `vy^2/(2g)`.

**Worked example, 20 m TOUCH.** `T = 0.55 + 0.8 = 1.35 s`. `vh = 14.81 m/s`.
`vy = (-0.30 + 0.5*9.81*1.8225)/1.35 = (−0.30 + 8.94)/1.35 = 6.40 m/s`. Total
speed `sqrt(14.81^2 + 6.40^2) = 16.13 m/s` — under `maxSpeed`, so no clamp. Apex
`6.40^2/(2*9.81) = 2.09 m` above the ear, i.e. about 2.6 m off the ground: over a
standing defender's hands, catchable in stride.

**Worked example, 20 m LOB.** `T = 1.3 + 0.9 = 2.2 s`. `vh = 9.09`,
`vy = (−0.30 + 23.74)/2.2 = 10.65`. Speed 14.0 m/s. Apex `5.78 m` — a genuine
jump ball with over two seconds of hang time.

**Worked example of the short clamp, 50 m LOB.** `T = 1.3 + 2.25 = 3.55 s`,
`vh = 14.08`, `vy = (−0.30 + 61.8)/3.55 = 17.32`, speed `22.3` — still under 26.
A 50 m TOUCH, though: `T = 2.55`, `vh = 19.6`, `vy = 12.4`, speed `23.2` — also
under. The clamp bites hardest at **short LOBs and long BULLETs**: a 55 m TOUCH
gives speed 24.6, and anything past `maxRange 55 m` is refused outright before the
solve.

#### 4.2.3 Position — BUILT (`Flight.pos`, line 51)

    x(t) = fx + vx*t
    y(t) = fy + vy*t - 0.5*g*t^2
    z(t) = fz + vz*t

Evaluated identically on the server (`flightPos`, `PracticeService:494`) and every
client (`PracticeClient:702`, `flightAt` line 580) from the single broadcast packet
`{from, vel, g, t0, kind, target, thrower, T, deflected}`. **There is no jitter and
no interpolation, because there is nothing to interpolate** — the arc is a closed
form of server time.

Ground time is solved analytically at launch (`launchFlight`, line 406):

    groundT = (vy + sqrt(vy^2 + 2*g*h)) / g,     h = max(from.Y - floorY, 0)

#### 4.2.4 Throw error — BUILT (`Flight.errorRadius`, line 56)

    r = base[kind] + perM[kind]*d
        + moving * speedFrac^2
        + facingK * (offFacing - facingFree)/90      [only if offFacing > 30]
        + pressure
    landing = aim + disc_sample(r)         -- UNIFORM in the disc: rho = r*sqrt(U), theta = U(0,2pi)

| Symbol | Value / range | Meaning |
|---|---|---|
| `base` | BULLET 0.35, TOUCH 0.45, LOB 0.70 m | floor error by type |
| `perM` | BULLET 0.02, TOUCH 0.024, LOB 0.03 m/m | error growth with distance |
| `moving` | 0.9 m | added at full sprint, **quadratic** in speed fraction |
| `facingFree` | 30 deg | free across-body angle |
| `facingK` | 1.2 m | added per 90 deg beyond `facingFree` |
| `pressure` | 1.0 m | **defined but always passed 0** |
| `speedFrac` | 0-1 | thrower speed / sprint |

**Output range.** Best case, a set thrower at 5 m throwing square: TOUCH
`0.45 + 0.12 = 0.57 m`. Worst realistic case, a full-sprint LOB at 40 m thrown
110 degrees across the body: `0.70 + 1.20 + 0.90 + 1.2*(80/90) = 3.87 m`. With
`pressure` wired up, add up to 1.0 m.

**Worked example, 20 m TOUCH, set thrower, square.** `r = 0.45 + 0.48 + 0 + 0 =
0.93 m`. Mean sampled miss is `(2/3)*0.93 = 0.62 m`. The receiver's measured reach
is about 0.8-0.9 m from the shoulder, so a set 20 m touch pass is inside the hands
nearly every time — which is the intended feel.

**Worked example, same throw at full sprint.** `r = 0.45 + 0.48 + 0.9 = 1.83 m`.
Mean miss 1.22 m — now routinely outside comfortable reach, forcing a stretch
(`stretch > 0.85` cuts the speed limit) or a body catch. Throwing on the run costs
real accuracy, and because the term is `speedFrac^2` it costs little at a jog
(`(6/7.8)^2 = 0.59`, so 0.53 m) and a lot at a sprint.

### 4.3 Catch resolution

#### 4.3.1 Reach, from the rig — BUILT (`Receive.rig`, `Receive.reachable`)

    boneU = elbow.C0.Position - shoulder.C1.Position                 -- in the upper arm's space
    palmL = wrist.C0.Position - wrist.C1.Position - (0, hand.Size.Y*0.15, 0)
    boneL = palmL - elbow.C1.Position                                -- in the forearm's space
    reach[side] = |boneU| + |boneL|                                  -- STUDS

    dip        = clamp(-y - 0.4, 0, CROUCH 0.45) * S                 -- crouch for a low ball
    lim[side]  = reach[side] * reachMul + BALL_R*0.6*S
    fr[side]   = |p - (shoulder[side] - (0,dip,0))| / lim[side]
    stretch    = min over sides, or max of the two when both hands reach
    hands      = "two" if both fr <= 1, else the reaching side, else nil

    behind cutoff: z < -(y above head ? OVERHEAD_BACK 0.38 : BACK_SLACK 0.12)  ->  nil, "behind"

| Symbol | Range | Meaning |
|---|---|---|
| `reachMul` | 0.94-1.00 | the intent's reach multiplier |
| `stretch` | 0-1+ | fraction of full reach used; `> 1` means unreachable |
| `x, y, z` | metres | point in shoulder-local space: x right, y up, z forward |

**Output range:** `stretch` in `[0, 1]` means catchable; above 1 the ball is out of
reach. A default R15 rig measures roughly 0.8-0.9 m of arm, so the effective catch
envelope is a pair of overlapping spheres of about that radius centred on the
shoulders — **not** a single sphere on the root part.

#### 4.3.2 The catch limit — BUILT (`Receive.judge`, line 171)

    if raised <= 0:  OFF_BODY      ("NO HANDS · IT HIT YOU")
    if raised <  1:  TIPPED        ("HANDS LATE · TIPPED IT")

    limit = INTENTS[intent].speed                           -- 22, 24 or 26 m/s
    if body and not hands:   limit *= 0.8  (and *= 0.85 again if aggressive)
    elseif hands ~= "two":   limit *= 0.72
    if stretch > 0.85:       limit *= 1 - (stretch - 0.85) * 2.2
    if kind == overShoulder: limit *= 0.85
    if airborne and intent ~= aggressive: limit *= 0.9

    caught  <=>  rel <= limit        where rel = |v_ball(t) - bodyVel| in m/s

| Symbol | Range | Meaning |
|---|---|---|
| `raised` | 0-1 | `clamp((t - press) / RAISE 0.12, 0, 1)` at contact |
| `rel` | 0-30 m/s | ball speed **relative to the body** |
| `stretch` | 0-1 | from 4.3.1 |
| `limit` | ~6-26 m/s | the computed allowance |

**Output range.** Best case, two hands, square, grounded, `secure`, not stretched:
**26 m/s** — more than any throw in the game produces, so a well-set secure catch
of a clean ball is automatic. Worst case, a one-handed fingertip over-the-shoulder
grab while airborne on `run` intent: `22 * 0.72 * (1 - 0.15*2.2) * 0.85 * 0.9 =
22 * 0.72 * 0.67 * 0.85 * 0.9 = 8.1 m/s` — only a floated LOB will stick.

**Worked example, 20 m TOUCH into a sprinting receiver.** At arrival the ball's
speed is `sqrt(14.81^2 + (6.40 - 9.81*1.35)^2) = sqrt(219.3 + 45.4) = 16.3 m/s`.
The receiver is running away at 7.8 m/s roughly along the ball's path, so
`rel` is about `16.3 - 7.0 = 9.3 m/s` (the vertical component does not cancel).
Against a `run` limit of `22 * 1.0 = 22`, that is caught comfortably — and it is
caught comfortably **because he is running with it**, which is the in-stride reward
the design wants, falling out of the physics rather than from a bonus.

**Worked example, the same ball to a receiver standing still and facing away.**
`rel` is the full 16.3 m/s, `kind` is `overShoulder` (x0.85) and reach is likely
one-handed (x0.72): `limit = 26 * 0.72 * 0.85 = 15.9 m/s`. `16.3 > 15.9` -> it
goes **off the hands** and stays live on a new arc. The margin is thin, which is
why this catch feels like a coin toss to a player even though no coin is tossed.

**Worked example, a point-blank BULLET.** A 6 m bullet: `theta = atan((441 -
sqrt(194481 - 9.81*(353 - 265)))/(9.81*6)) = atan((441 - 440.0)/58.9) = 0.97 deg`,
`vh = 21.0`, `T = 0.286 s`, arrival speed about 21.1 m/s. Standing, two hands,
square: `limit = 26`, caught. One-handed: `limit = 18.7`, **off the hands**. So a
hot ball punishes bad hand position without any "hot ball" knob existing.

#### 4.3.3 Deflection velocities — BUILT (`Receive.deflect`, line 199)

    flat = (vIn.X, 0, vIn.Z)                 -- m/s in
    TIPPED:    flat*0.18 + (0, 4.2, 0)
    OFF_HANDS: -flat*0.28 + look*0.4 + (0, 1.8, 0)
    OFF_BODY:  -flat*0.12 + (0, 1.2, 0)

**Output range.** A tip of a 16 m/s ball leaves at `sqrt((16*0.18)^2 + 4.2^2) =
5.1 m/s`, mostly upward, hanging for `2*4.2/9.81 = 0.86 s` and travelling 2.5 m —
a genuinely live, scrappable ball. An off-hands rebound of the same comes back
toward the thrower at 4.5 m/s. Fully deterministic: the same hit always produces
the same bounce.

### 4.4 Lag handling — BUILT

    -- claimed press times (PracticeService:337)
    t_press = clamp(t_claimed, now - min(catch.lagMax 0.15, ping*2 + 0.05), now)

    -- per-receiver sweep cursor (PracticeService:629, 487)
    lag(c)   = clamp(ping*0.5 + 0.02, 0, 0.15)
    cursor(c)= clamp(now - lag(c) - t0, 0, groundT)

    -- resolution gate (PracticeService:644)
    resolve the earliest contact only when  min(cursor over all pending) >= contact.t

    -- spatial allowance (Config.possession.latencySlack)
    grab/handoff reach += 0.35 m        -- FIXED, not per-ping

| Symbol | Range | Meaning |
|---|---|---|
| `catch.lagMax` | 0.15 s | furthest back a press may be claimed |
| `lag(c)` | 0-0.15 s | estimated one-way lag, from `GetNetworkPing` |
| `latencySlack` | 0.35 m | flat spatial allowance on possession reach |

**Output range:** `t_press` in `[now - 0.15, now]`. A player above ~300 ms RTT gets
partial compensation only; the cap bounds how much history a spoofed timestamp can
rewrite.

**How this differs from the earlier draft, honestly.** The draft proposed a
`PositionHistory` ring buffer with per-ping rewind of every player's position and a
velocity-scaled spatial pad. The build has **neither**: possession reach gets a
flat 0.35 m and presses get a flat 0.15 s. There *is* a 0.3 s position history
(`a.hist`, `PracticeService:375`) but it is used only to compute `bodyVel` for the
relative-speed test — never to rewind geometry.

The build's approach is simpler and is probably sufficient, for a specific
structural reason: **the object whose position has to be rewound is the ball, and
the ball's position is a closed form of server time.** `Flight.pos` is exact at any
`t`, so there is nothing to look up. Players' positions matter only through the
per-receiver sweep cursor, which already shifts each receiver's evaluation back to
their own screen time. A ring buffer would add precision on the *player* side of
the comparison; whether that precision is worth the complexity is a real open
question and is recorded as such (OPEN-DECISIONS A3), not resolved by assertion.

The known cost of the simplification: a 0.35 m flat slack is generous for a 20 ms
player and tight for a 200 ms one, and 4.3.2 shows catch margins can be thin enough
for that to matter.

### 4.5 Movement validation — BUILT (`checkMovement`, line 831)

    every 0.1 s:
      step   = flatDist(last, pos) / S                 -- metres since last check
      if step > teleportM (6):  reject("teleport")
      limit  = sprint * speedSlack = 7.8 * 1.2 = 9.36 m/s
      budget = min(burstM 3.5, budget + limit*dt) - step
      if budget < 0: reject("sustained over-speed")
      if budget > burstM*0.5: lastGood = pos

| Symbol | Value | Meaning |
|---|---|---|
| `limit` | 9.36 m/s | tolerated sustained speed |
| `burstM` | 3.5 m | budget cap, absorbing bunched updates |
| `teleportM` | 6 m | single-step hard limit |
| `lockout` | 1.0 s | ban on ball actions after a failure |

**Output range:** a cheater at `2 x` sprint (15.6 m/s) drains the full 3.5 m budget
in `3.5/(15.6 - 9.36) = 0.56 s`. At `1.5 x` (11.7 m/s) it takes 1.5 s. At
`1.2 x` or below they are never caught by the budget — which is the deliberate
trade: `speedSlack 1.2` buys immunity from false positives at the price of
tolerating a 20% speed hack.

### 4.6 `AWFootball` jump-ball timing — BUILT (`Rules.jumpHeight`, `resolveJumpBall`)

    h(t)    = jumpSpeed*t - 0.5*jumpGravity*t^2 = 6.2t - 11t^2
    apex    = jumpSpeed / jumpGravity = 6.2/22 = 0.282 s,  h = 0.874 m
    reaches = h(-timing) >= needHeight 0.55
    err(a)  = |(-a.timing) - apex|           -- how far from the peak you were at arrival
    nearest err wins; aggressive receiver gets a 0.05 s margin

**Output range:** `h(t) >= 0.55` for `t` in `[0.106, 0.458]` s, a **0.35 s window**
in which you are high enough to contest at all. `err` is 0 for a perfect jump and
up to 0.18 s at the window's edges.

**Worked example.** Receiver jumps 0.30 s before arrival: `err = |0.30 - 0.282| =
0.018`. Defender jumps 0.40 s before: `err = 0.118`. Receiver wins by 0.10 s and
catches. Flip it — receiver at 0.15 s (`err = 0.132`), defender at 0.26 s
(`err = 0.022`): the defender wins, and it is an interception if within
`intReach 0.95 m`, otherwise a swat. Entirely input-determined.

### 4.7 Present but NOT WIRED: the timing-grade model

`AWPractice.Flight` lines 66-92 define a complete alternative catch model —
`timingGrade` (a `PERFECT/GOOD/LATE/EARLY/NONE` ladder) and `catchDifficulty`
(a sum of speed, reach, timing and run terms, caught under `threshold 1.0`) — and
`Config.pass.catch` carries all of its knobs (`perfectBefore 0.15`,
`perfectAfter 0.04`, `goodBefore 0.45`, `earlyLimit 0.8`, `lateAfter 0.12`,
`timing{PERFECT 0, GOOD 0.15, LATE 0.35, EARLY 0.45, NONE 0.4}`, `threshold 1.0`,
`reach 0.95`, `reachK 0.6`, `runK 0.1`, `comfortSpeed 14`, `speedScale 12`).

**Neither function is called anywhere in the place.** The Practice Field decides
catches entirely through `Receive.judge` (4.3.2), which uses a different model and
a different set of numbers — `Receive.INTENTS` hardcodes its own reach and speed
values rather than reading `pass.catch`.

This is documented here rather than quietly dropped because the dead code is
well-commented and reads as authoritative, and a future reader will otherwise
believe it is the catch model. Two further problems if it is ever wired up:

- `EARLY 0.45` penalises pressing too soon **harder than `NONE 0.4` penalises not
  pressing at all**, so the model rewards not trying.
- `catchDifficulty` finds its `worst` contributor by iterating with `pairs()`,
  whose order is not deterministic in Luau, so the reported *cause* varies on a tie
  (the total does not).

See OPEN-DECISIONS A2.

---

## 5. Edge Cases

Each case below states what the code actually does, with the line, or says plainly
that nothing handles it.

**BUILT:**

1. **Two players claim a loose ball in the same step** — batched and settled
   together; closest valid body wins; a tie within `0.02 m` goes to the earlier
   request. Exactly one winner. Losers get `"BEATEN TO IT"`. (`resolveClaims`:771)
2. **A stale claim** (quoting an old `rev`) — dropped, counted in `stats.stale`,
   and if someone else now has the ball the claimant is told
   `"TOO LATE · <name> HAS IT"`. (:780-782)
3. **Two receivers could both reach the ball** — the earliest *contact time* wins,
   held until no other receiver's sweep cursor could still produce an earlier one.
   Exact tie goes to the intended receiver, then the offense. (`stepFlight`:636-648)
4. **Ball touches hands but is not caught** — it stays **live** on a new
   deterministic arc (tip, off-hands rebound or body drop), and the deflector has a
   0.45 s grace before touching it again. (:609-612)
5. **Ball hits a receiver's body with hands down** — `OFF_BODY`,
   `"NO HANDS · IT HIT YOU"`, ball stays live. (`Receive.judge`:173)
6. **Hands still coming up at contact** — `raised < 1` is a `TIPPED` outcome, not a
   catch. The 0.12 s raise time is load-bearing. (`Receive.judge`:176)
7. **Ball arrives behind the receiver** — `"HIT YOU IN THE BACK · TURN AROUND"`.
   Over-the-head balls get more slack behind (`OVERHEAD_BACK 0.38` vs
   `BACK_SLACK 0.12`), which is what makes over-the-shoulder catches possible.
   (:571, `Receive.reachable`:128)
8. **Catch made with no foot in bounds** — incomplete, whatever the ball did.
   (`insideLines`:396, used at :578)
9. **A fast ball passing through a thin body** — impossible: the body test is a
   segment-vs-capsule sweep at 1/240 s steps. (`Receive.hitsBody`, `SUB`:486)
10. **Thrower tries to catch their own pass** — refused unless the ball was
    deflected. (`eligible`:496)
11. **Pass target out of range** — over `maxRange 55 m` is refused before release
    (`"TOO FAR FOR YOUR ARM"`); a reachable-but-too-strong throw is clamped and
    flagged `short`, reported as `"OUT OF RANGE · FELL SHORT"`. (:438, `Flight`:40)
12. **Pass target too close** — under 2.5 m is refused with
    `"TOO CLOSE · HAND IT OFF (E)"`. (:439)
13. **Throwing backwards** — refused beyond `maxOffFacing 120 deg`. (:442)
14. **Throwing immediately after catching** — refused for `throwCooldown 0.35 s`
    (`"SET YOUR FEET FIRST"`); handing off is refused for `receiveLock 0.3 s`
    (`"SECURE IT FIRST"`). (:427, :294)
15. **Dropping the ball during the securing window** — counts as an
    **incompletion**, not a loose ball. (`doDrop`:312)
16. **Carrier disconnects, dies or is removed** — ball goes `DEAD` at once and
    returns to the tee after the short 0.25 s `QUICK_RESET` delay.
    (`dropActor`:190, `hookCharacter`:198, `QUICK_RESET`:137)
17. **Carrier walks off the field** — beyond `leaveMarginM 9 m` the ball is dead:
    `"THE BALL STAYS ON THE PRACTICE FIELD"`. (:866)
18. **A ball in flight leaves the area** — dead out of bounds beyond
    `leaveMarginM + 6 m`. (:657)
19. **A flight that never resolves** — hard timeout `groundT + 1.5 s` forces it
    dead. (:661)
20. **A loose ball nobody picks up** — `looseTimeout 12 s`, then
    `"LEFT TOO LONG"`. (:929)
21. **A loose ball stuck outside the area** — dead immediately
    (`"OUT OF THE PRACTICE AREA"`). (:928)
22. **A player teleports or speed-hacks** — distance-budget and teleport checks,
    snap-back, 1 s action lockout, and the ball dies if they held it. (4.5)
23. **The game itself moves a player** (join, respawn, entry pad) — checks are
    skipped for `placedGrace 1.5 s`, so legitimate teleports are not punished.
    (:840)
24. **Remote spam** — token bucket at 12/s. (`takeToken`:277) *One path escapes it;
    see OPEN-DECISIONS B2.*
25. **A claimed timestamp from the future, or from long ago** — clamped to
    `[now - 0.15, now]`. (`clientTime`:337)
26. **An illegal ball transition is requested** — refused, warned and counted in
    `stats.illegal`. The transition table is the only authority. (`setState`:123)
27. **A player leaves the practice zone mid-session** — client movement override is
    released and the HUD hidden, so movement is never left hijacked. (:564-568)
28. **The player's body is blocked by a wall or a teammate** — momentum is clamped
    to actual speed + 1.5, so you cannot accumulate phantom speed against an
    obstacle. (:544)
29. **A late joiner** — gets a `SYNC` ball-state message one second after joining.
    (:946)
30. **The practice field model is missing from the place** — a flat fallback turf is
    generated and a warning logged, so the script still runs. (:52-60)
31. **The avatar is not an R15 rig** — `Receive.rig` returns `nil`, the receiver is
    skipped by the sweep, and `Carry.cframe` falls back to an R6 arm offset and then
    to the root part. (`Receive.rig`:46, `Carry`:13-17)
32. **A hand-off to someone off the field or locked out** — refused with a reason
    (`"THEY'RE OFF THE FIELD"`, `"THEY CAN'T TAKE IT RIGHT NOW"`). (:297-298)

**BUILT in `AWFootball` only:**

33. **A carrier is hit while juking or spinning** — `EVADED`; immunity windows are
    `jukeImmunity 0.28 s` and the full `spinTime 0.42 s`. (`Rules.resolveTackle`:41)
34. **A weak or badly-angled tackle** — becomes a `WRAP` with a 0.35 s break window
    rather than a down. (`Rules.resolveTackle`:48, `FootballService`:814)
35. **Moving before the snap** — false start, -5 yards, replay the down.
    (`FootballService`:499)
36. **Nobody goes up for a jump ball** — incomplete, `"nobody went up for it"`.
    (`Rules.resolveJumpBall`:79)
37. **Regulation ends tied** — up to 3 OT rounds of one possession each.
    (`FootballService`:896)

**NOT HANDLED — no code exists:**

38. **A fumble.** Nothing in the codebase can cause one.
39. **An interception on the Practice Field.** No defender, no INT outcome.
40. **A contested catch between opposing players** on the Practice Field. The
    earliest-contact rule is a race, not a contest: no box-out, no height, no
    timing score.
41. **A hit during the securing window.** `c.securing` is set and is only consulted
    on a voluntary drop. No defender can disturb a catch.
42. **A simultaneous tackle by two defenders.**
43. **A goal-line or forward-progress spot**, a safety in 1v1, a touchback, or a
    fumble out of bounds or out of the end zone. There is no spotting on the
    Practice Field at all.
44. **A first down.** Not implemented anywhere (3.11).
45. **A player who stalls behind the line forever.** No `PLAY_MAX_DURATION` on the
    Practice Field — but also no play to end.
46. **Rejoin after a disconnect mid-match.** No grace, no forfeit rule, no bot fill.

---

## 6. Dependencies

### 6.1 Systems this one touches — BUILT as described

| System | Direction | Actual contract |
|---|---|---|
| Roblox character movement (`PlayerModule` / `ControlModule`) | **This system overrides it** | `PracticeClient` replaces `ControlModule.moveFunction` inside the practice zone and restores it on leaving (:435, :567). This is an invasive integration and the single most fragile dependency in the build: a Roblox `PlayerModule` change can break movement. It is defended by three fallbacks (`ControlModule`, legacy `GetControls`, new `MoveAction`) at :448-468. |
| `ReplicatedStorage.AWMotion` | This system calls it | `Motion.claimArms(model, "busy" / "tuckR")` arbitrates who owns the arms, so the catch IK and the ball-tuck pose do not fight the running animation. (:667, :697) |
| Roblox `Humanoid` | Bidirectional | Driven via `Move` + `WalkSpeed`; `JumpHeight` set to 0.75 m with `UseJumpPower = false`; `FloorMaterial` read for grounded state. |
| R15 avatar rig | **This system depends on it structurally** | Reach, catch geometry and arm IK all read `Shoulder`/`Elbow`/`Wrist` joints and part sizes. **An R6 avatar cannot catch** — `Receive.rig` returns `nil` and the receiver is skipped. Joints may be `AnimationConstraint` or `Motor6D`; both are handled (`isJoint`, `Receive`:39). |
| `ReplicatedStorage.AWSessions` / `ServerStorage.AWSessionJoin` | Bidirectional | The field publishes a `practice` `Configuration` with `Mode`, `Humans`, `Capacity 16`, `PadPos`, `WatchPos`, `Order 95`, `DropIn` every second, and exposes a `practice` join `BindableFunction` that teleports the player to the entry pad. Listed with JOIN, never chosen by Quick Match. (:949-981) |
| `ServerStorage.AWPracticeTest` | Consumes | The scripted-test hook (6.3). |
| HUD | Consumes | Built into `PracticeClient`; reads only its own local state and `State` messages. |
| DRIP STORE cosmetics | — | **No integration exists.** Nothing in any config is purchase-linked, so the cosmetic-only promise currently holds by absence rather than by a guard. |

**Bidirectionality note, per the repo's design-doc rules:** `AWMotion` and the
session registry are both referenced by this system and neither has a GDD. When one
is written it must mention Football Core. `systems-index.md` is updated.

### 6.2 Module layout — BUILT (and nothing like the earlier draft)

    ReplicatedStorage/AWPractice/
      Config      -- all tunables (metres/seconds), field placement, validation limits
      BallState   -- the 5 states and the transition table; the ONLY authority on legality
      Momentum    -- pure movement maths (no Roblox objects)
      Carry       -- where a carried ball sits on a body (hand bone)
      Flight      -- pass solve, position, error radius  (+ an unwired catch model, 4.7)
      Receive     -- rig measurement, reach, body sweep, the catch decision, deflection, arm IK
      Remotes/    -- Intent (c->s), State (s->c)          [created at runtime by the server]

    ServerScriptService/
      PracticeService        -- authority: ball, possession, flight sweep, validation, test hook
      FootballService        -- the older 1v1 mode (own authority, own catch model)
      TeamFootballService    -- 2v2 / 5v5

    StarterPlayer/StarterPlayerScripts/
      PracticeClient         -- movement override, input, HUD, local ball, catch IK, overlay
      FootballClient / TeamFootballClient

    ReplicatedStorage/AWFootball/
      Config  -- 1v1 / team tunables, INCLUDING the match rules (3.11)
      Rules   -- pure: routes, throw solve, tackle resolution, catch + jump-ball resolution

**The earlier draft's proposed layout does not exist.** There is no `NetConfig`,
`BallArc`, `BallStates`, `Schema`, `PositionHistory`, `CatchResolver`,
`TackleResolver`, `MovementSanity`, `RemoteGuard`, `PlayController`,
`AIQuarterback`, `BallView`, `IntentSender` or `ContestFeedback`. The functions
those modules were to perform are either done inline in the two big scripts or not
done at all. The real split — **pure maths in `ReplicatedStorage`, authority in one
server script, presentation in one client script** — is defensible and keeps the
shared maths genuinely shared.

### 6.3 Test and diagnostic hooks — BUILT, and the earlier draft did not know they existed

`ServerStorage.AWPracticeTest` (`BindableFunction`, `PracticeService`:984-1104) —
20 commands, enough to script most of §8 without a human in the loop:

| Command | Purpose |
|---|---|
| `dummy {key, pos, face, defense}` | spawn an anchored R15 test receiver or defender |
| `dummyHands {key, down, up, intent}` | script a hands-up press at a chosen time (negative = already up) |
| `drive {key, vel, time}` | move a dummy at an exact velocity, so leads can be tested deterministically |
| `setLag {key, lag}` | force a fake lag value for that actor, overriding `GetNetworkPing` |
| `place` / `movePartner` / `partnerTo` | position actors precisely |
| `qbTo {to, kind, err, offset, lead, aimUp}` | partner throw with a **forced** error offset — removes the RNG from a test |
| `throwFrom {from, to, hold}` | run a throw through the real `doThrow` path |
| `claim {list}` | submit several simultaneous grab claims, to test 5.1 |
| `placeLoose pos` | put a loose ball anywhere, using only legal transitions |
| `give key` / `intent {...}` | force possession / replay a real intent through the real handler |
| `state` / `ball` / `flight` / `results n` / `log` / `geometry` | read everything |
| `resetStats` / `removeDummy` | clean up between reps |

Client side (`gui.Debug`, `PracticeClient`:675): `trace` (the last ~900 movement
frames: time, actual speed, model speed, heading, input, sprint, position),
`hands`, `raise`, `lower`, `pose`, `input`.

`stats` counters maintained live: `transitions`, `illegal`, `stale`, `cooldown`,
`rateLimited`, `tooFar`, `grabs`, `handoffs`, `drops`, `resets`, `rejects`,
`beaten`, `doubleOwner`, `throws`, `catches`, `dropped`, `incomplete`,
`catchPresses`, plus `dead[cause]` and the last 400 catch `results`.

**`doubleOwner` counts a state the code believes impossible** (`HELD` with no
holder, :130). It should be 0 in any session; if it is not, there is a real bug.

### 6.4 Networking and authority — BUILT

- **The server is the only writer** of ball state, holder, position and every
  outcome. There is no remote that lets a client set possession or ball position.
- **Clients send intents with the `rev` they saw** (3.2). Stale or
  illegal-for-state requests are dropped and counted.
- **One reliable broadcast per state change**, coalesced to one per server step,
  carrying the full flight packet so every client can draw the exact arc.
- **No `UnreliableRemoteEvent`, no attribute-based state replication, no `seq`.**
  Two attributes are used for presentation only: `AWHands` on the character (so
  other clients can pose raised hands) and `AWPracticeIn` on the player.
- **Bandwidth** is low by construction: one packet per throw and per state change,
  nothing per frame. No measurement has been taken.

The earlier draft's reasoning for *why* an analytic arc beats both a
client-owned and a server-owned physics ball was correct and is preserved:

> Giving a client network ownership of the ball lets that client move it anywhere —
> an exploit by design. A server-owned physics ball is safe but arrives on clients
> late and jittery, so each client sees it somewhere different, which is exactly
> what makes contested catches feel unfair. A fixed arc is evaluated *identically*
> by everyone for any given server time, costs one packet per throw, keeps working
> through a server hitch, and can be rewound exactly.

#### Proposed, not built (networking)

`PositionHistory` with per-ping rewind and a velocity-scaled spatial pad; a
`RemoteGuard` wrapper with per-action rate limits and NaN/bounds checks (the build
has a single global token bucket and inline `typeof` checks); `JOIN_SETTLE_TIME`
before trusting a new client's clock; `HICCUP_SKIP` to avoid false speed strikes
across a server stall; and a ping indicator in the HUD (ping *is* displayed, but
nothing is gated on it).

### 6.5 Roblox API behaviours the build already relies on — RESOLVED

The earlier draft listed four API questions to verify in Studio. Three are
answered by the fact that the build works:

- **`Workspace:GetServerTimeNow()` on a client** is used for every timestamp and
  for drawing the arc (`PracticeClient`:701). Claims are clamped server-side
  anyway, so a bad clock right after joining costs accuracy, not correctness.
- **Server writes to a client-owned `HumanoidRootPart`** do take effect: `reject`
  zeroes velocity and pivots the character back, and this is the anti-cheat
  snap-back (:819-822).
- **`RunService:BindToSimulation`** exists only on newer engines; the build feature-
  detects it and falls back to `PreSimulation` (:552-556).
- **`UnreliableRemoteEvent` payload limits** remain unverified and unneeded — the
  build does not use one.

---

## 7. Tuning Knobs

**All values are the real ones in the code.** Units are metres and seconds.
"Safe range" is a judgement about what can be changed without breaking an
assumption elsewhere; it is not in the code.

### 7.1 Movement — `AWPractice.Config.move` (BUILT)

| Knob | Value | Safe range | What it affects |
|---|---|---|---|
| `jog` | 6.0 m/s | 5.0-6.5 | Base run speed. |
| `sprint` | 7.8 m/s | 7.0-9.0 | Top speed. 1.3x jog — a narrower gap than most arcade football. Raising it also raises the anti-cheat ceiling (4.5) and every derived value below. |
| `carryFactor` | 0.96 | 0.90-1.00 | Cost of carrying. Deliberately small. |
| `accelTime` | 0.6 s | 0.4-0.9 | Standstill to full sprint. Sets `accel = sprint/accelTime`. |
| `brakeTime` | 0.3 s | 0.2-0.5 | Full sprint to a stop. Half of `accelTime`: stopping should beat starting or it feels like lag. |
| `turnFast` | 720 deg/s | 540-900 | Turn rate **at a standstill**. Near-instant facing when set. |
| `turnSlow` | 260 deg/s | 180-350 | Turn rate **at full sprint**. The main momentum lever: 260 gives a 1.72 m turn radius. |
| `cutAngle` | 75 deg | 60-100 | Above this, at speed, you plant. Lower = far more plants = heavier, more frustrating. |
| `pivotFraction` | 0.55 | 0.4-0.7 | Fraction of sprint speed a plant brakes down to (4.29 m/s). |
| `sharpTurn` | 60 deg | 45-80 | Residual-turn angle above which you cannot accelerate past pivot speed. |
| `turnCost` | 0.45 | 0.3-0.6 | Speed fraction lost for a full 180 deg ask. Continuous, not threshold-based. |
| `airControl` | 0.35 | 0.2-0.5 | Accel/brake/turn retained in the air. Low, so a jump is a commitment. |

Set in `PracticeClient`, not in `Config` — candidates for moving into config:
`JumpHeight 0.75 m` (:499), the `secure`-hold speed cap `jog * 0.92` (:538), and the
blocked-body clamp `actual + 1.5` (:544).

### 7.2 Ball and loose ball — `AWPractice.Config.ball` (BUILT)

| Knob | Value | Safe range | What it affects |
|---|---|---|---|
| `gravity` | 9.81 m/s^2 | fixed | **Real gravity.** Keep it. See 7.7. |
| `radius` | 0.09 m | fixed | Ground contact height and the reach bonus. |
| `bounce` | 0.35 | 0.2-0.5 | Vertical speed kept per bounce. Only applied above 1 m/s impact. |
| `groundFriction` | 5.0 m/s^2 | 3-8 | How fast a loose ball stops rolling. |
| `settleSpeed` | 0.15 m/s | 0.1-0.3 | Below this it stops dead. |
| `dropForward` / `dropUp` | 1.0 / 1.4 m/s | 0.5-2 / 1-2 | Where a dropped ball goes. |
| `dropInherit` | 0.6 | 0.4-0.8 | Share of your running speed a dropped ball keeps. |
| `looseTimeout` | 12 s | 8-20 | Before an untouched loose ball resets. |
| `deadDelay` | 0.6 s | 0.4-1.0 | Dead ball back to the tee (0.25 s for quick causes). |
| `substep` | 1/120 s | fixed | Loose-ball integration step. |

### 7.3 Possession — `AWPractice.Config.possession` (BUILT)

| Knob | Value | Safe range | What it affects |
|---|---|---|---|
| `grabReach` | 1.3 m | 1.0-1.6 | Flat distance to claim a ball. |
| `grabAbove` / `grabBelow` | 0.9 / 1.35 m | — | Vertical window: scoop at your feet, not over your head. |
| `latencySlack` | 0.35 m | 0.2-0.6 | **Flat** lag allowance on possession reach. Not per-ping — see 4.4. |
| `tieMetres` | 0.02 m | 0.01-0.05 | Below this two claims are a tie and the earlier request wins. |
| `grabCooldown` | 0.25 s | 0.15-0.5 | One claim per player per quarter second. |
| `handoffReach` | 1.7 m | 1.4-2.2 | Hand-off distance. |
| `receiveLock` | 0.3 s | 0.2-0.5 | You cannot hand it straight back. |
| `partnerHold` | 1.5 s | 1-3 | How long the stand-in holds a hand-off. |
| `resetCooldown` | 2.0 s | 1-4 | Between tee resets. |

### 7.4 Passing — `AWPractice.Config.pass` (BUILT)

| Knob | Value | Safe range | What it affects |
|---|---|---|---|
| `gravity` | 9.81 m/s^2 | fixed | Pass arc gravity. Real, because flight time is chosen directly. |
| `holdTouch` / `holdLob` | 0.2 / 0.55 s | 0.15-0.3 / 0.45-0.7 | Hold thresholds BULLET -> TOUCH -> LOB. |
| `maxHold` | 1.5 s | 1.0-2.0 | Hold is clamped here. |
| `bulletSpeed` | 21 m/s | 18-25 | Fixed bullet arm speed. Also sets the ~45 m distance where BULLET degrades to TOUCH. |
| `touchT0` / `touchTk` | 0.55 s / 0.04 s/m | 0.45-0.7 / 0.03-0.05 | TOUCH flight time. Raising `Tk` floats it more. |
| `lobT0` / `lobTk` | 1.3 s / 0.045 s/m | 1.1-1.6 / 0.04-0.06 | LOB hang time. **Must stay well above TOUCH** or the three types stop reading as different. |
| `maxSpeed` | 26 m/s | 22-30 | Strongest arm. Beyond it the throw is clamped and `short`. |
| `maxRange` | 55 m | 40-70 | No target beyond this is offered. |
| `releaseUp` / `catchUp` | 0.55 / 0.25 m | — | Release height (ear) and aim height (chest) above the root. |
| `targetCone` | 40 deg | 25-55 | Camera cone for picking a receiver. Wider = easier aim, more mis-picks. |
| `maxOffFacing` | 120 deg | 90-150 | Cannot throw behind yourself. |
| `throwCooldown` | 0.35 s | 0.25-0.6 | After receiving, before you may throw. |
| `err.base` | B 0.35 / T 0.45 / L 0.70 m | — | Floor error by type. Bullets are the most accurate. |
| `err.perM` | B 0.02 / T 0.024 / L 0.03 m/m | — | Error growth per metre. |
| `err.moving` | 0.9 m | 0.5-1.5 | Added at full sprint. **Quadratic** in speed, so jogging is cheap. |
| `err.facingFree` / `facingK` | 30 deg / 1.2 m | 20-45 / 0.8-1.8 | Free across-body angle, then cost per 90 deg. |
| `err.pressure` | 1.0 m | 0.5-2.0 | **Defined, always passed 0.** Waiting on a defender. |
| `partnerYards` | {8, 15, 25, 35} | — | Stand-in partner distances. |
| `partnerReturn` | 1.2 s | 1-3 | After the partner catches, the ball returns to the tee. |

### 7.5 Catching — `AWPractice.Receive` constants (BUILT)

**These are hardcoded in `Receive.lua`, not in `Config`.** That violates the
repo's "gameplay values must be data-driven" standard and should be moved.

| Knob | Value | Safe range | What it affects |
|---|---|---|---|
| `RAISE` | 0.12 s | 0.08-0.2 | Hands-up time. **The single most important catch knob.** Longer = must anticipate; shorter = reactive catching. Also the size of the timestamp-backdating exploit (OPEN-DECISIONS B3). |
| `BALL_R` | 0.09 m | fixed | Ball radius in reach and body tests. |
| `TORSO_R` | 0.19 m | 0.15-0.25 | Body capsule a ball can hit. |
| `BACK_SLACK` | 0.12 m | 0.05-0.2 | Reach behind the shoulder line at chest height. |
| `OVERHEAD_BACK` | 0.38 m | 0.25-0.5 | Reach behind, over the head. **This is what makes the over-the-shoulder catch exist.** |
| `CROUCH` | 0.45 m | 0.3-0.6 | How far shoulders drop to scoop a low ball. |
| `INTENTS.secure` | reach 0.97, speed 26, secure 0.30, recover x0.75 / 0.25 s | — | Standing/jogging. The most forgiving. |
| `INTENTS.run` | reach 0.94, speed 22, secure 0.16, no recovery | — | Sprinting. Less reach and allowance, but you keep your speed. |
| `INTENTS.aggressive` | reach 1.00, speed 24, secure 0.36, recover x0.50 / 0.45 s | — | Jump. Full extension, long commitment, slow landing. |
| one-hand multiplier | x0.72 | 0.6-0.85 | Inline at `Receive`:184. Reward for squaring up. |
| body-trap multiplier | x0.8 (x0.85 again if aggressive) | — | Inline at :181. |
| fingertip falloff | `1 - (stretch - 0.85)*2.2` | — | Inline at :186. Zero allowance at `stretch = 1.0`. |
| over-shoulder multiplier | x0.85 | 0.8-0.95 | Inline at :187. |
| airborne non-aggressive | x0.9 | — | Inline at :188. Rewards committing to the jump. |
| deflect: TIPPED | `flat*0.18 + 4.2 up` | — | How scrappable a tip is. |
| deflect: OFF_HANDS | `-flat*0.28 + look*0.4 + 1.8 up` | — | |
| deflect: OFF_BODY | `-flat*0.12 + 1.2 up` | — | |

### 7.6 Network and validation (BUILT)

| Knob | Value | Safe range | What it affects |
|---|---|---|---|
| `net.maxIntentsPerSecond` | 12 | 8-20 | Token bucket per player. |
| `pass.catch.lagMax` | 0.15 s | 0.1-0.25 | Furthest a press may be backdated **and** the cap on the per-receiver sweep lag. One knob, two jobs. |
| `validate.speedSlack` | 1.2 | 1.1-1.35 | Anti-cheat ceiling = `sprint * this` = 9.36 m/s. Lower catches more cheats and more false positives. |
| `validate.burstM` | 3.5 m | 2-6 | Budget absorbing bunched updates. Sets how long over-speed survives (4.5). |
| `validate.teleportM` | 6 m | 4-10 | Single-step hard limit at a 0.1 s cadence. |
| `validate.lockout` | 1.0 s | 0.5-3 | Ball-action ban after a failed check. |
| `validate.placedGrace` | 1.5 s | 1-3 | Checks skipped after a legitimate teleport. |
| movement check cadence | 0.1 s | — | Hardcoded at `PracticeService`:939. |
| flight sweep step `SUB` | 1/240 s | — | Hardcoded at :486. 11 cm at the fastest throw. |

### 7.7 `AWFootball` knobs (BUILT, different mode)

Full tables are in `/home/claude/extracted/AWFootball.Config.lua`. The values that
matter to this document:

**Match rules** — `possessionsEach 5`, `downs 4`, `td 7`, `startYard 20`,
`otPossessionsEach 1`, `maxOtRounds 3`. No first downs, no safety, no kicking.

**Tackling** — `reach 1.35`, `lungeReach 1.7`, `lungeTime 0.3`, `lungeSpeed 12.5`,
`whiffRecovery 0.65`, `cooldown 0.9`, `facingCos 0.15`, `jukeImmunity 0.28`,
`cleanClosingSpeed 4.0`, `cleanAngleCos -0.2`, `wrapDrag 0.45`,
`breakWindow 0.35`, `cpuBreakChance 0.35`.

**Carrier moves** — `jukeSpeed 12.5`, `jukeTime 0.22`, `jukeCooldown 1.1`,
`spinTime 0.42`, `spinCooldown 1.6`, `spinSpeed 6.5`, `stiffArmReach 1.6`,
`stiffArmStun 0.7`, `stiffArmCooldown 1.4`.

**Speeds** — `wrSpeed 9.6`, `dbSpeed 9.3`, `carrySpeed 9.0`. **Note these are
20-23% faster than the Practice Field's `sprint 7.8`.** Two modes, two speed
scales; reconciling them is OPEN-DECISIONS A4.

**The three gravities.** `AWPractice` uses real `9.81` for both ball and pass.
`AWFootball` uses `ball.gravity 13.5` and `jump.gravity 22`. They are not an
inconsistency to fix blindly — each follows from how its mode derives flight time:

- **`AWPractice` can afford real gravity because it chooses flight time directly.**
  `Flight.solve` picks `T = t0 + tk*d` and *derives* velocity. The arc shape comes
  from choosing `T`, so gravity never has to be faked.
- **`AWFootball` derives flight time from a speed clamp** (`Rules.flightTime`:
  `throwSpeedMin 14`-`throwSpeedMax 24`, clamped to `minFlight 0.55`-
  `maxFlight 1.6`). With flights capped at 1.6 s, real gravity makes every pass a
  flat line drive; `13.5` buys back visible arc height inside a short flight. A
  presentation fix, and legacy from the browser prototype.
- **`jump.gravity 22` is deliberately not ball gravity.** With `jumpSpeed 6.2`,
  apex is at `0.282 s` and `0.874 m`. At 9.81 the same launch gives 0.63 s of hang
  and 1.96 m — a moon-jump, and a 0.63 s apex window makes jump-ball timing far too
  forgiving. High gravity keeps the jump snappy and the timing window tight, which
  is exactly what `resolveJumpBall` measures.

**The Practice Field's 9.81 is the convention to carry forward.** The earlier
draft's `G_BALL = 80 studs/s^2` (28 m/s^2) matches none of the three and is dropped.

### 7.8 Knobs the earlier draft invented that do not exist

Recorded so nobody searches the code for them: all `STAMINA_*`; all `DROP_*` and
`INT_DROP_BASE`; `CATCH_RADIUS`, `DIVE_CATCH_RADIUS`, `REACH_STAND`,
`CONTEST_RADIUS`, `HEIGHT_TOL`, `BOXOUT_BONUS`, `BOXOUT_ANGLE`,
`W_TIMING`/`W_POSITION`/`W_HEIGHT`, `TIE_MARGIN`, `INT_THRESHOLD`,
`JUMPBALL_TIMING_WINDOW`, `JUMPBALL_PERFECT_BAND`; all `FUMBLE_*`; all `BREAK_*`
and `SA_BONUS_*`; `TACKLE_RESOLUTION`; `DIVE_*`; `WRAP_CONE_HALF`;
`G_BALL`, `H_RELEASE`, `LOB_TARGET_HEIGHT`, `BALL_INHERIT_QB_VEL`,
`THROW_CHARGE_TIME`, `THROW_WINDUP`, `LEAD_BIAS`, `RECEIVER_VEL_SMOOTH`,
`SPREAD_*`, `PRESSURE_RADIUS`, `SACK_RADIUS`; all `AI_*` and `SEP_*`;
`LATENCY_GRACE`, `INTERP_DELAY`, `CATCH_PAD_MAX`, `TACKLE_PAD_MAX`,
`CONTEST_RESOLVE_DELAY`, `POSITION_HISTORY_LEN`, `SPEED_TOLERANCE`,
`STRIKE_LIMIT`, `HISTORY_SECONDS`, `JOIN_SETTLE_TIME`, `HICCUP_SKIP`;
`FIRST_DOWN_DISTANCE`, `SAFETY_POINTS`, `WIN_SCORE`, `MATCH_TIME`, `OT_DISTANCE`,
`DRIVE_START_DISTANCE`, `DOWNS_PER_SERIES`; every play-cycle timing
(`SNAP_TIME`, `READY_TIMEOUT`, `AUTO_SNAP_TIME`, `BETWEEN_PLAY_TIME`,
`PLAY_MAX_DURATION`, `LOOSE_BALL_MAX_TIME`, `CATCH_SECURE_TIME`); and the
practice/QA knobs (`PRACTICE_YAC_TIME`, `REJOIN_GRACE`, `FAIRNESS_BAND`).

The nearest real equivalents, where one exists, are named in 7.1-7.7.

---

## 8. Acceptance Criteria

Rewritten as **verification of what is built** plus honest gates for what is not.
The in-Studio test hooks (6.3) make most of the BUILT criteria scriptable today.

### 8.1 BUILT — verify against the current place

Movement:

- [ ] 0 to full sprint measures `0.60 s (+/- 10%)`. The client already measures and
      displays this (`PracticeClient`:835); read it off the panel.
- [ ] Full sprint to a stop measures `0.30 s (+/- 10%)` and covers about 1.17 m.
- [ ] Top speeds read 6.0 m/s jogging and 7.8 m/s sprinting; **7.49 while carrying**
      (`carryFactor 0.96`).
- [ ] A direction change over 75 deg above 4.29 m/s brakes toward 4.29 m/s and turns
      at a visibly slower rate (the plant). Below that speed it does not.
- [ ] Sprint turning radius is about 1.7 m; standstill facing is near-instant.
- [ ] Holding CATCH with `secure` intent caps speed at 5.52 m/s; the cap lifts on
      release.
- [ ] Running into a wall does not accumulate phantom speed (`:544`).
- [ ] Leaving the practice zone restores Roblox's normal movement, and re-entering
      takes it over again. Check `Debug("input").hooked` flips.
- [ ] Identical behaviour on KB/M, gamepad and a phone-sized touch screen.

Ball state and possession:

- [ ] `AWPracticeTest("state")` shows `stats.illegal == 0` and
      **`stats.doubleOwner == 0`** after a long session.
- [ ] Every state change increments `rev` by exactly 1; a client intent quoting an
      old `rev` is refused and increments `stats.stale`.
- [ ] `AWPracticeTest("claim", {...})` with several simultaneous claims yields
      **exactly one** `HELD`; the closest body wins; a sub-0.02 m tie goes to the
      earlier request; losers see `"BEATEN TO IT"`.
- [ ] A ball at your feet is grabbable; one held over your head is not
      (`grabAbove 0.9` / `grabBelow 1.35`).
- [ ] Hand-off is refused within `receiveLock 0.3 s` of receiving, and beyond
      `handoffReach 1.7 + 0.35 m`.
- [ ] Dropping during the securing window logs `stats.incomplete`, not `stats.drops`.
- [ ] A carrier who leaves, dies or walks 9 m off the field leaves the ball dead,
      back on the tee within 0.25 s.

Passing:

- [ ] BULLET, TOUCH and LOB produce visibly distinct arcs, and the dotted preview
      matches the flown arc on every client.
- [ ] Measured flight times match 4.2: 20 m TOUCH about 1.35 s, 20 m LOB about
      2.2 s, 15 m BULLET about 0.72 s.
- [ ] A BULLET past about 45 m silently becomes a TOUCH.
- [ ] A throw needing over 26 m/s reports `short` and `"OUT OF RANGE · FELL SHORT"`.
- [ ] Throws under 2.5 m, over 55 m, or more than 120 deg off facing are refused
      with their own messages.
- [ ] With `qbTo {offset = ...}` forcing a known offset, the ball lands within
      0.05 m of the predicted point — proving the solve, with RNG removed.
- [ ] Error radius scales as specified: a 20 m TOUCH set and square gives about
      0.93 m; the same at full sprint about 1.83 m.

Catching:

- [ ] Debug overlay reach spheres match the avatar's actual arm length, and **change
      with avatar proportions**.
- [ ] A press less than 0.12 s before contact is `TIPPED`, never a catch — and the
      ball stays live on a new arc.
- [ ] No hands up: `OFF_BODY`, ball stays live.
- [ ] A clean two-handed `secure` catch of any in-game throw succeeds **100%** of
      100 scripted reps (`limit 26 m/s` exceeds every throw speed). Use
      `dummyHands` + `qbTo`.
- [ ] The same ball one-handed, over the shoulder, at a fingertip stretch, or
      airborne on a non-aggressive intent fails at the margins predicted by 4.3.2 —
      and **always for the same reason, every time.** Zero variance across
      identical reps is the headline assertion: the model is deterministic.
- [ ] A catch with no foot in bounds is incomplete regardless of the ball.
- [ ] A 21 m/s point-blank bullet is caught two-handed and goes off the hands
      one-handed.
- [ ] Tips, off-hands rebounds and body drops produce the exact velocities in 4.3.3.
- [ ] Both receiver and thrower receive the reason string; the last 400 results are
      in `AWPracticeTest("results", n)`.

Lag and anti-cheat:

- [ ] With `setLag` forcing two receivers to 0.02 s and 0.15 s, the **earlier
      contact time** wins regardless of which resolves first. Run 100 reps; ping
      must not correlate with winning.
- [ ] A press backdated beyond `min(0.15, ping*2 + 0.05)` is clamped, not honoured.
- [ ] A client teleporting over 6 m in one 0.1 s check is snapped back and locked out
      for 1 s; the ball dies if they held it.
- [ ] A client at 1.5x sprint is caught within about 1.5 s; at 1.2x it is **not**
      caught (a known, accepted limit).
- [ ] Entry-pad placement does not trigger a false reject (`placedGrace 1.5 s`).
- [ ] Over 12 intents/s increments `stats.rateLimited`.

Integrity:

- [ ] No remote can set possession, ball position or any outcome. Re-read the two
      remote handlers and confirm.
- [ ] No value in `AWPractice.Config`, `AWFootball.Config`, `Receive.INTENTS` or
      `TeamFootballService.TC` is reachable from a purchase. Re-audit when DRIP STORE
      lands.

### 8.2 BUILT in `AWFootball` — verify separately

- [ ] Every outcome of `Rules.resolveTackle` is reachable, and the same inputs always
      give the same outcome (it is deterministic).
- [ ] A `WRAP` is escapable with juke/spin/stiff-arm inside `breakWindow 0.35 s` and
      not after; otherwise the carrier is down `wrapDrag 0.45 s` later.
- [ ] Juke, spin and stiff-arm grant their immunity windows (0.28 / 0.42 / 0.3 s)
      and respect their cooldowns.
- [ ] Jump-ball outcomes follow timing-versus-apex (4.6); `swatReach 1.7` versus
      `intReach 0.95` decides swat versus interception.
- [ ] 5 possessions each, 4 downs then turnover, TD 7, start at the 20, up to 3 OT
      rounds. **No first down ever occurs** — confirm this is intended.
- [ ] A false start costs 5 yards and replays the down.
- [ ] **Zero fumbles** in 200 tackles (there is no fumble code; this is a
      regression guard).

### 8.3 NOT BUILT — gates for the next stages

Stage 3, defender and tackling on the Practice Field:

- [ ] Choose: port `AWFootball`'s deterministic `resolveTackle`, or build the
      earlier draft's counter matrix. **Do not build both.**
- [ ] `pass.err.pressure 1.0` becomes live when a defender is near the thrower.
- [ ] Contested catches get a real contest (box-out, height, timing), not just the
      earliest-contact race.
- [ ] Interceptions exist as an outcome; `a.defense` becomes a real role rather than
      a test-dummy flag.
- [ ] A hit during the securing window dislodges the ball.
- [ ] Decide fumbles: yes or no. Today the answer is no, everywhere.

Stage 4, play cycle and scoring on the Practice Field:

- [ ] Ready, pre-snap, snap, live, whistle, spot — none of which exists today.
- [ ] Reuse `AWFootball.Config.rules` rather than adding a third rules table.
- [ ] Decide first downs (3.11). A possession is currently four plays.
- [ ] A real AI quarterback replaces the manually-triggered stand-in.

Stage 5, route practice:

- [ ] Route selection, ghost line, per-rep feedback, session stats, instant reset.
- [ ] Add the 4 missing routes (Out, Dig, Go, Comeback) to `Rules.ROUTES`, or cut
      them from the design.

Process gates the repo's own standards require and this system does not meet:

- [ ] `tests/` holds no automated tests for any of the pure modules
      (`Momentum`, `Flight`, `Receive.judge`, `BallState.can` are all pure and
      trivially testable). This is the clearest unmet standard in the project.
- [ ] `production/qa/evidence/` holds no retained screenshot for any
      player-observable behaviour, which `coding-standards.md` says is **not waived**
      at any QA level.
- [ ] `docs/architecture/` holds no ADR for the choices this document records —
      above all the analytic-arc decision and the `rev` counter, both of which are
      exactly what an ADR is for.

---

## OPEN-DECISIONS

**This replaces the earlier appendix entirely.** Everything the earlier version
listed as unknown that the code already answers has been deleted — the scoring
numbers, the play-cycle values, the naming conflicts, the Roblox API questions and
most of the "no number yet" list are all settled above. What remains is only what
the code genuinely does not decide.

### A. Real conflicts between the two codebases — pick one side

| # | Conflict | Practice Field says | `AWFootball` says | Recommendation |
|---|---|---|---|---|
| **A1** | **The catch model.** | Fully deterministic. Rig-measured reach, hands-up timing, and a ball-speed limit with readable multipliers. No RNG. (`Receive.judge`) | Reach bands plus a **quality roll**: secure 0.97, aggressive 0.80, no press 0.50, mistimed 0.35, CPU 0.86. Seeded LCG. (`Rules.resolveCatch`) | **Practice Field.** It matches the project's own pillar ("I know exactly why"), it already expresses every factor the roll was standing in for, and it is testable with zero variance. Porting it into `AWFootball` is real work; leaving two models is worse. **This is the most consequential decision in the document.** |
| **A2** | **Which catch model is even the intended one.** | `Receive.judge` runs. | `Flight.timingGrade` + `catchDifficulty` exist in `AWPractice`, are fully commented, have 11 config keys — and are **never called** (4.7). | Either wire them up or delete them **and** their config keys. They misled this audit. If wired: fix `EARLY 0.45 > NONE 0.4` (which rewards not trying) and the nondeterministic `pairs()` scan for the worst cause. |
| **A3** | **Lag compensation depth.** | Flat `latencySlack 0.35 m` + `catch.lagMax 0.15 s`, plus a per-receiver sweep cursor shifted to each player's own screen time. No position rewind. | — | **Keep the simple version for now**, and revisit only if playtests at 150-250 ms show unfair catches. The ball needs no rewind (its path is a closed form); only the *player* side is approximate. Decide with data, not in advance. Note 4.3.2 shows some catch margins are under 1 m/s, which is where 0.35 m of flat slack could start to bite. |
| **A4** | **Two speed scales.** | `sprint 7.8 m/s`. | `wrSpeed 9.6`, `dbSpeed 9.3`, `carrySpeed 9.0` — 15-23% faster. | Pick one. All catch, throw-error and tackle-reach tuning is implicitly calibrated against the speed scale of its own mode, so this is not a cosmetic difference. The Practice Field's momentum model is the one being kept, so its scale is the natural winner — but `AWFootball`'s numbers came from a playtested browser prototype and should not be dismissed. |
| **A5** | **Three gravities.** | `9.81` for ball and pass. | `13.5` for passes, `22` for jumps. | **`9.81` going forward.** `22` for jumps is a deliberate, well-reasoned exception and should stay (7.7). `13.5` is legacy from the browser build and should go when `AWFootball` adopts the chosen-flight-time solver. |

### B. Bugs that need a decision, not just a fix

| # | Issue | Where | Note |
|---|---|---|---|
| **B1** | **Any player can kill a live pass.** `doReset` refuses only "someone else holds it" and "already on the tee". `IN_FLIGHT` is not refused, so while a pass is in the air any player can press R / Y / TEE and reset it — destroying another player's throw and another player's catch. Cooldown is only 2 s. | `PracticeService`:324 | A one-line guard (`doQB`:728 already has it). The *decision* is whether a reset should ever be allowed while someone else's ball is live — probably never, not just not in flight. |
| **B2** | **`catchUp` bypasses every gate.** It is handled and returned **before** the rate limit, the in-zone check and the movement-check lockout. It is unmetered, and it defeats the 1 s lockout a failed movement check imposes. There is also a dead duplicate branch at :761. | `PracticeService`:750, :761 | Low practical impact (it only sets `hands.up` once), but it is an unrated remote path. Decide whether hand-lowering should be exempt deliberately — there is an argument that it should always be allowed, since it only ever *reduces* what you can do. |
| **B3** | **Timestamp backdating is bounded but asymmetric.** A client may claim a press up to `min(0.15, ping*2 + 0.05)` s ago. Since hands take `RAISE 0.12 s`, a 0.15 s backdate can convert a TIP into a catch — and a player with artificially inflated ping gets **more** allowance (`ping*2`). | `PracticeService`:337 | The cap is sane. The open question is whether the allowance should scale with ping at all, given that it rewards inflating it. A flat 0.15 s for everyone is simpler and harder to game. |

### C. Standards debts to decide on

| # | Debt | Note |
|---|---|---|
| **C1** | `TeamFootballService.TC` hardcodes ~25 gameplay values in the script, including a **second, contradicting** rules table (`maxOtRounds 2` versus `AWFootball.Config.rules`' `3`). `Receive.INTENTS` hardcodes its own reach and speed numbers. Both violate `coding-standards.md`. | Move into config, and delete one of the two rules tables. |
| **C2** | No automated tests, despite `Momentum`, `Flight`, `Receive.judge` and `BallState.can` being pure and trivially testable. No retained QA screenshots, which the standards say are never waived. No ADRs. | The in-Studio hooks (6.3) are most of a test harness already; the gap is that nothing persists its output. |
| **C3** | `turnFast` / `turnSlow` are named for the turn rate, not the runner's speed, and read backwards to almost everyone. | Rename to `turnAtRest` / `turnAtSprint`. A pure rename, two call sites. |

### D. Questions only the owner can answer

1. **Stamina: do you want it at all?** There is none in the code and no sign one
   was ever started. The earlier draft specified a full system. It would stop
   sprint-everywhere play and make the jog/sprint gap (only 1.3x) matter more — but
   it is new work, not a fix, and the build currently plays without it.
2. **First downs: yes or no?** Today a possession is "four plays, then the other
   player's turn", with yards shown but never converting. That is a clean arcade
   rule and might be the right one — but right now it is an omission rather than a
   choice.
3. **Fumbles: yes or no?** None exist anywhere. The `LOOSE` state is built and
   working, so the plumbing is there if you want them.
4. **Touch button count.** The build shows 8 context buttons; the earlier draft's
   own UX rule said at most 4. Which is right on a phone?
5. **One body scale for everyone?** Right now reach is **measured from each
   avatar's own rig**, so a longer-armed avatar genuinely catches balls a shorter
   one cannot. That is a lovely piece of engineering and a possible fairness
   problem. Is avatar-driven reach a feature, or should gameplay use one standard
   rig?
6. **Does the Practice Field ever become a match mode**, or does it stay a lab and
   hand its modules to `AWFootball`? The answer decides whether Stage 3 and 4 get
   built here at all, and it is the biggest structural question in the project.
