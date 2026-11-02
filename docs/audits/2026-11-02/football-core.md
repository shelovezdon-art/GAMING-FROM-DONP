# Football Core — code audit vs `design/gdd/football-core.md`

**Date:** 2026-11-02
**Scope:** read-only audit of Studio `52e32916-3102-403b-a01b-8b4d550c1fae` (Edit datamodel)
**The place was NOT modified.** Every Studio call was a read (`script_read`, `script_grep`, `search_game_tree`). No `execute_luau`, no writes, no play session.

Sources cached under `/home/claude/extracted/` — see `MANIFEST.md` there for what is mirrored and what was read but not mirrored.

---

## 0. Headline

The doc was written as a greenfield spec for a five-stage build. The reality is **two parallel football codebases**:

| | `AWPractice` + `PracticeService` / `PracticeClient` | `AWFootball` + `FootballService` / `TeamFootballService` |
|---|---|---|
| What it is | The Practice Field "Ball Lab" rebuild | The older 1v1 mode (and 2v2/5v5 team mode) |
| Stage 1 (momentum movement) | **BUILT** | partial (speed caps only, no momentum model) |
| Stage 2 (ball states, passing, catching) | **BUILT**, more carefully than the doc proposed | BUILT differently (reach + RNG quality rolls) |
| Stage 3 (defender, tackling, juke/spin/stiff-arm) | **NOT BUILT** | **BUILT** |
| Stage 4 (play cycle, downs, scoring, AI QB) | NOT BUILT (a stand-in partner throws; no play cycle) | **BUILT** |
| Stage 5 (jump balls, route practice) | NOT BUILT | jump balls BUILT; 5 routes BUILT |

So "Stage 3 is not built" is true *of the Practice Field*, which is the doc's declared scope — but the doc must not claim tackling is unbuilt engine-wide, because `AWFootball.Rules.resolveTackle` is live and wired into two services.

The doc's status header (`Status: SPEC — nothing in this document is built yet`) was wrong on its first line.

---

## 1. Units — the doc's single biggest error

`AWPractice.Config` line 2:

> `Logic units are metres and seconds; S converts metres to studs (1 stud = 0.35 m, the same scale as every other mode).`

`Config.S = 1 / 0.35` (line 6), `Config.YARD = 0.9144` (line 7). `AWFootball.Config` line 2 says the same and sets `STUD = 0.35`.

**Every number in the doc's §4 and §7 was in studs and is therefore wrong by a factor of ~2.857.** The code's convention wins. The corrected doc is in metres throughout, with studs only where the code genuinely works in studs (field placement, rig reach, part sizes).

Naming trap: in the code `S` multiplies **metres to studs**. Reading `x * S` as "scale down" is backwards.

---

## 2. Module-by-module: what is actually built

### 2.1 `AWPractice.Config` — tuning (BUILT, 107 lines)

| Code key | Value | Doc guessed | Verdict |
|---|---|---|---|
| `move.jog` | **6.0 m/s** | 16 studs/s (= 5.6 m/s) | close by accident, wrong unit |
| `move.sprint` | **7.8 m/s** | 24 studs/s (= 8.4 m/s) | wrong |
| `move.carryFactor` | **0.96** | absent | doc missed it |
| `move.accelTime` | **0.6 s** (standstill to full sprint) | `TAU_ACCEL` 0.25 s, exponential | **different model**, see 2.3 |
| `move.brakeTime` | **0.3 s** | `TAU_DECEL` 0.15 s | different model |
| `move.turnFast` | **720 deg/s — at a STANDSTILL** | `TURN_RATE_SLOW` 720 | value right, name inverted |
| `move.turnSlow` | **260 deg/s — at FULL SPRINT** | `TURN_RATE_FAST` 220 | close, name inverted |
| `move.cutAngle` | **75 deg** | `CUT_THRESHOLD` 35 deg | wrong |
| `move.pivotFraction` | **0.55** (of sprint = 4.29 m/s) | `PIVOT_SPEED` 4 studs/s | wrong |
| `move.sharpTurn` | **60 deg** | absent | doc missed it |
| `move.turnCost` | **0.45** (per 180 deg ask) | `CUT_PENALTY_K` 0.9 + `CUT_RETAIN_MIN` 0.35 | different model |
| `move.airControl` | **0.35** | absent | doc missed it |

**`turnFast`/`turnSlow` are named for the turn rate, not the speed.** `Momentum.step` line 46: `rate = turnFast + (turnSlow - turnFast) * frac`, `frac = speed/sprint`. So 720 deg/s at rest falling to 260 deg/s at sprint. Anyone reading the names as "turn rate while moving fast" gets it exactly backwards. Rename candidate; not changed.

Ball: `gravity 9.81`, `radius 0.09`, `bounce 0.35`, `groundFriction 5.0`, `settleSpeed 0.15`, `looseTimeout 12`, `deadDelay 0.6`, `substep 1/120`.

Possession: `grabReach 1.3 m`, `grabAbove 0.9`, `grabBelow 1.35`, `latencySlack 0.35 m`, `tieMetres 0.02`, `grabCooldown 0.25 s`, `handoffReach 1.7`, `receiveLock 0.3`, `partnerHold 1.5`, `resetCooldown 2.0`.

Pass: `gravity 9.81`, `holdTouch 0.2 / holdLob 0.55 / maxHold 1.5`, `bulletSpeed 21 m/s`, `touchT0 0.55 + touchTk 0.04*d`, `lobT0 1.3 + lobTk 0.045*d`, `maxSpeed 26 m/s`, `maxRange 55 m`, `releaseUp 0.55`, `catchUp 0.25`, `targetCone 40 deg`, `maxOffFacing 120 deg`, `throwCooldown 0.35`.

Validate: `speedSlack 1.2` (9.36 m/s ceiling), `burstM 3.5`, `teleportM 6`, `lockout 1.0`, `placedGrace 1.5`. `net.maxIntentsPerSecond 12`.

### 2.2 `AWPractice.BallState` — state machine (BUILT, 39 lines)

States `TEE`, `HELD`, `LOOSE`, `DEAD`, `IN_FLIGHT`; transition table lines 22-28.

Different and better than the doc:

- `HELD -> HELD` is legal (a hand-off). The doc's table had no hand-off.
- `IN_FLIGHT -> IN_FLIGHT` is legal — a tipped or bobbled ball continues on a **new arc** instead of dying. The doc never considered this; `PracticeService:613` implements it (`launchFlight` with `deflected = true`).
- No `SNAPPED` (no play cycle) and no `CONTESTED` (contests resolve inside the flight sweep, not as a state).
- `DEAD -> TEE` only. No spotting; the ball always returns to a fixed tee.

**The `rev` counter is the pattern the doc missed and should keep.** `setState` (PracticeService:128) increments `ball.rev` on every transition; every client intent carries the `rev` it saw (`PracticeClient:268`); the server drops anything stale (`stats.stale`, e.g. PracticeService:293, 311, 426, 781). One rule kills duplicate taps, double-grabs and cross-play staleness, replacing the doc's `playId` + `seq` pair.

### 2.3 `AWPractice.Momentum` — movement model (BUILT, 58 lines)

Pure function, no Roblox objects — genuinely unit-testable, which the repo's standards ask for.

The model is **linear-rate, not exponential**: `accel = sprint/accelTime` = 13 m/s^2, `brake = sprint/brakeTime` = 26 m/s^2; decel toward a lower target uses `brake * 0.6`. The doc's `v + (v_target - v)(1 - e^(-dt/tau))` is not what is built.

The cut is a two-branch rule (lines 40-45, 46-54), not the doc's three-band formula:

- `ang > cutAngle (75)` **and** `speed > pivotFraction*sprint (4.29 m/s)` -> **plant**: brake at full rate toward pivot speed, turn at only `turnSlow/2 = 130 deg/s`, return early (no acceleration that frame).
- otherwise -> turn at `rate(speed)`, then target speed `= top * mag * (1 - turnCost * left/180)` where `left` is the residual angle the turn could not cover this frame. If `left > sharpTurn (60)`, target is additionally capped at pivot speed.

So the speed cost of a turn is **continuous and proportional to how much turn is still owed**, not a discrete penalty at a threshold. Cleaner than the doc's; kept.

`carrying` multiplies top speed by `carryFactor 0.96`. `grounded = false` scales accel, brake and turn rate by `airControl 0.35`.

### 2.4 `AWPractice.Carry` — ball attach (BUILT, 20 lines)

Ball attaches to the `RightHand` part (R15) with a fixed offset, falling back to `Right Arm` (R6) then `HumanoidRootPart`. Server and client call the same function, so the ball cannot drift from the animation. Not in the doc; worth stating as a rule.

### 2.5 `AWPractice.Flight` — pass maths (BUILT, 94 lines)

`kindForHold`: hold `< 0.2 s` -> BULLET, `< 0.55 s` -> TOUCH, else LOB (band maxes at `maxHold 1.5 s`).

`Flight.solve` — two different solvers, which the doc did not anticipate:

- **BULLET**: fixed arm speed `bulletSpeed 21 m/s`, solving the **low-angle** root (line 29: `theta = atan((v^2 - sqrt(disc))/(g*d))`). If the discriminant is negative the ball cannot get there at 21 m/s and the kind **silently degrades to TOUCH** (line 33).
- **TOUCH / LOB**: pick a **flight time** growing linearly with distance (`T = t0 + tk*d`), then derive velocity. TOUCH at 20 m -> 1.35 s; LOB at 20 m -> 2.2 s. If the resulting speed exceeds `maxSpeed 26`, velocity is scaled down and `short = true` — the readable "out of range, fell short" failure.

`errorRadius` = `base[kind] + perM[kind]*d + moving*speedFrac^2 + facingK*(off-30)/90 + pressure`. Error is sampled as a **uniform disc** (`PracticeService:446`: `r = errR*sqrt(rand)`, uniform angle), not the doc's 2D Gaussian. `pressure` is plumbed but **always passed 0** from `doThrow` (PracticeService:445) — the hook exists, the defender that would populate it does not.

`timingGrade` and `catchDifficulty` exist (lines 66-92) and implement the grade ladder + difficulty threshold — **but they are dead code; see 5.1.**

### 2.6 `AWPractice.Receive` — catch geometry (BUILT, 253 lines; best-engineered module here)

**Reach is measured from the player's own R15 rig, not configured.** `Receive.rig` (line 43) reads the `Shoulder`/`Elbow`/`Wrist` joints, measures `boneU` (shoulder to elbow) and `boneL` (elbow to palm) in each part's own space, and sums them. A taller avatar with longer arms really does reach further. The doc's `CATCH_RADIUS 3.0 studs` and `REACH_STAND 6.5 studs` do not exist and have no equivalent.

**Three catch intents, chosen by what you are doing — never from a menu** (lines 28-33):

| intent | when | reach mul | speed allowance | securing | after the catch |
|---|---|---|---|---|---|
| `secure` | hands up, jogging/standing | 0.97 | 26 m/s | 0.30 s | speed x0.75 for 0.25 s |
| `run` | hands up while sprinting | 0.94 | 22 m/s | 0.16 s | no penalty |
| `aggressive` | JUMP with hands up | 1.00 | 24 m/s | 0.36 s | speed x0.50 for 0.45 s |

**`Receive.judge` (line 171) is fully deterministic — there is no drop roll anywhere.** Hands must be *fully* up (`raised >= 1`, i.e. `RAISE = 0.12 s` since the press) and the ball's speed relative to your body must be under a limit. The limit starts at the intent's allowance and is multiplied down by: `x0.8` body-trap (further `x0.85` if aggressive), `x0.72` one-handed, `x(1 - (stretch-0.85)*2.2)` at fingertips, `x0.85` over-the-shoulder, `x0.9` airborne-but-not-aggressive. Outcomes: `CAUGHT` / `TIPPED` (hands late) / `OFF_HANDS` (too hot) / `OFF_BODY` (no hands).

**The doc's additive `P_drop` formula, all its `DROP_*` knobs, `CONTEST_RADIUS`, `W_TIMING/W_POSITION/W_HEIGHT`, `TIE_MARGIN` and `INT_THRESHOLD` are fiction.** The code's model is more readable and already meets the doc's own stated goal ("every drop has a visible cause") better than the formula the doc proposed. The still-valuable ideas (box-out scoring above all) moved to "Proposed, not built".

**Deflections are deterministic** (`Receive.deflect`, line 199): TIP keeps 18% of horizontal velocity and adds +4.2 m/s up; OFF_HANDS reverses 28% and adds +1.8 up; a body hit reverses 12% and adds +1.2 up. The ball stays live on a new arc.

`Receive.solveArm` (line 222) is a two-bone IK solver posing the arms after the animation runs, per frame, on every client. There are no catch animations in the game — the pose is generated. Not in the doc at all.

### 2.7 `PracticeService` — server authority (BUILT, 1107 lines)

Ball part is `Anchored`, `CanCollide = false`, `CanQuery = false`, `CanTouch = false` (lines 80-89), moved only by this script. **The doc's "never give a client network ownership" recommendation is already honoured.** No physics ball anywhere.

Remote contract is two events (`Intent` client-to-server, `State` server-to-client, lines 70-77) — far simpler than the doc's seven-remote layout. Actions: `grab`, `handoff`, `drop`, `reset`, `throw`, `catchDown`, `catchUp`, `catchIntent`, `qb`, `partner` (dispatcher lines 745-766).

Flight resolution (`stepFlight` line 616; `sweepReceiver` line 505) is the strongest thing in the build and the doc has no equivalent:

- Each receiver's hands and body are **swept along the ball's real path in 1/240 s steps** (`SUB`, line 486 — about 11 cm at the fastest throw), with a true segment-vs-capsule test for the body (`Receive.hitsBody`). A fast ball cannot tunnel through anyone.
- Each receiver is swept **only up to the moment their own screen is showing**: `now - receiverLag(c) - f.t0` (line 629), `receiverLag = clamp(ping*0.5 + 0.02, 0, 0.15)`.
- The **earliest contact wins, but only once nobody else could still have got there first** (`minCursor` gate, line 644). Exact tie -> the intended receiver, then the offense (line 640).

A genuinely good answer to "whose catch is it", and it needs no position-history ring buffer, because the thing being rewound is the *ball*, whose path is analytic.

Lag handling: `clientTime` (line 337) clamps a claimed timestamp to `[now - min(catch.lagMax 0.15, ping*2 + 0.05), now]`. Movement validation (`checkMovement`, line 831) runs at 10 Hz with a **distance budget** refilling at `sprint * speedSlack = 9.36 m/s`, capped at `burstM 3.5 m`, plus a hard `teleportM 6 m` single-step check. Failure -> `reject` (line 814): 1 s action lockout, snap back to `lastGood`, ball dies if they were carrying.

**The doc proposed per-ping rewind against a `PositionHistory` ring buffer. The code uses a fixed `latencySlack = 0.35 m` added to grab reach plus `catch.lagMax = 0.15 s`.** Simpler, and — because the ball path is analytic and the receiver sweep is already lag-shifted per player — probably good enough. There *is* a short history buffer (`a.hist`, 0.3 s, line 375) but it only computes body velocity for the relative-speed test (`bodyVel`, line 381), never rewinds geometry.

Loose-ball physics (`stepLoose`, line 876) is custom, server-only, substepped at 1/120 s: gravity, bounce `0.35` only if impact speed > 1 m/s, ground friction `5.0 m/s^2`, settle below `0.15 m/s`.

The **stand-in practice partner** (`buildPartner`, line 222) is an anchored R15 body with an idle animation. It is not AI. It can be moved to 8/15/25/35 yards (`partnerYards`) and throws TOUCH/BULLET/LOB in rotation (`doQB` line 726; `partnerThrow` line 671). `partnerThrow` runs **four fixed-point iterations** of solve-then-re-lead (lines 688-692) to converge on where you will be when the ball arrives — a real lead calculation, numerical rather than the doc's closed-form quadratic. Its error radius is the normal one x0.6 (line 697).

There is an extensive **Studio test hook** (`SS.AWPracticeTest`, lines 984-1104) with 20 commands: `dummy` (spawn a test receiver or defender), `dummyHands` (script a hands-up press at a chosen time), `drive` (move a dummy at a set velocity), `setLag` (force a fake lag value), `qbTo`, `throwFrom`, `results`, `flight`, `geometry`, `resetStats`. **This is a scripted-test rig good enough to satisfy most of the doc's acceptance criteria, and the doc does not know it exists.**

### 2.8 `PracticeClient` — client (BUILT, 892 lines)

Movement is client-simulated for responsiveness. It **replaces `ControlModule.moveFunction`** with its own capture function (`takeOverMovement`, line 435), then drives `Humanoid:Move` + `WalkSpeed` from the `Momentum` result (`moveStep`, line 528). Binds to `RunService:BindToSimulation(..., Hz60)` where available, falling back to `PreSimulation` (lines 551-572). Movement is hijacked **only inside the practice zone** and released on leaving (line 567) — a real correctness concern, handled properly.

Two speed caps the doc has no concept of (lines 537-540): holding CATCH with `secure` intent caps you at `jog * 0.92`; a recovery window after a hard catch caps you at `sprint * recoverMul`. Line 544: if the body is physically slower than the model (a wall, a teammate), momentum is clamped to actual + 1.5 — "never run ahead of the body".

`JumpHeight` is set to **0.75 m** (line 499: `0.75 * S`), with `UseJumpPower = false`. The doc's `JUMP_HEIGHT 2.5 studs` (0.875 m) is coincidentally close but arrived at differently.

Full touch support: 8 context buttons, re-laid out for phone vs tablet (`layout`, line 151). Gamepad and KB/M bound. The doc's "at most 4 context buttons" rule is violated by the build.

Client test hook too (`gui.Debug`, line 675): `trace`, `hands`, `raise`, `lower`, `pose`, `input`.

### 2.9 `AWFootball.Config` / `Rules` and `FootballService` — the older 1v1 mode (BUILT)

`AWFootball.Config.rules = { possessionsEach = 5, downs = 4, td = 7, startYard = 20, otPossessionsEach = 1, maxOtRounds = 3 }`. **This answers most of the doc's section-C "still has no number" list.**

What the scoring actually does (`FootballService:860-909`):

- Each side gets 5 possessions, starting at `startYard 20` from own goal (line 342).
- 4 downs, then **turnover on downs** (line 884). **There are no first downs at all** — `script_grep "firstDown"` returns nothing engine-wide. Yards gained are computed and displayed (`Rules.yardsBetween`) but never reset the down counter. The doc's `FIRST_DOWN_DISTANCE` and "gaining it gives a new series" describe a mechanic that does not exist.
- TD = 7. **No safety in 1v1** — `safety = 2` appears only in `TeamFootballService`'s own local table (line 28), never in `AWFootball.Config`. No kicking, no extra point.
- Tie after regulation -> up to 3 OT rounds of one possession each (lines 896-901).
- False start is a real penalty: -5 yards, replay the down (line 499).

`Rules.resolveTackle` (Rules:30) returns `NOT_LIVE` / `NO_CONTACT` / `WHIFF` / `EVADED` / `WRAP` / `CLEAN_TACKLE`, **fully deterministic — no dice**. Gates in order: reach (`tackle.reach 1.35`, or `lungeReach 1.7` while lunging, with a 1.2 m "no contact" band beyond), facing (`facingCos 0.15`), juke/spin immunity (`immuneUntil`), then closing speed >= `cleanClosingSpeed 4.0` **and** angle >= `cleanAngleCos -0.2` for a `CLEAN_TACKLE`; otherwise `WRAP`.

A `WRAP` is a drag with a **break window** (`FootballService:814-823`): the carrier has `breakWindow 0.35 s` to press juke/spin/stiff-arm and escape (`breakWrap` line 830), otherwise `wrapDrag 0.45 s` later they go down (`finishWrap` line 845). The CPU's break is a `cpuBreakChance 0.35` roll (line 786).

Juke / spin / stiff-arm are built (`FootballService:1052-1078`): juke `jukeSpeed 12.5 m/s` for `jukeTime 0.22 s`, cooldown 1.1 s, granting `jukeImmunity 0.28 s`; spin `spinSpeed 6.5` for `spinTime 0.42 s`, cooldown 1.6 s, immunity = spin duration; stiff-arm within `stiffArmReach 1.6 m` and front arc `cosA > -0.2` stuns the defender `stiffArmStun 0.7 s`, cooldown 1.4 s.

**There are no fumbles anywhere in the codebase.** `script_grep "fumble"` -> no matches. The doc's whole 3.8 and 4.5.4 (`FUMBLE_CHANCE`, blindside/big-hit/gang multipliers, `FUMBLE_CAP`) describe nothing. The `LOOSE` state exists in the Practice build but is only reached by a voluntary drop or the partner setting the ball down — never by a tackle.

Routes: 5 built (`Rules.ROUTES`) — `slant`, `curl`, `post`, `fade`, `cross`, plus `free`. The doc's 8-route tree is aspirational; **Out, Dig, Go and Comeback do not exist.**

Jump balls are built (`Rules.resolveJumpBall`, Rules:70) and **mostly** deterministic: both contestants' jump timing error against apex is compared, nearest wins; the defender needs `swatReach 1.7` to swat and `intReach 0.95` to intercept; an aggressive receiver gets an `aggressiveMargin 0.05` tiebreak. The one roll is the *uncontested* skied catch (line 90, human quality 0.95). `Rules.resolveCatch` (line 93) for normal catches is **substantially RNG**: human secure 0.97, aggressive 0.80, no press `autoChance 0.50`, mistimed press 0.35. Seeded LCG, `seed = 1337`.

Two catch models now exist side by side — the Practice Field's deterministic speed-limit model and AWFootball's reach + quality-roll model. That is the most important architectural divergence in the project.

### 2.10 `TeamFootballService` (skimmed)

2v2 and 5v5 exist, sharing `AWFootball.Config` and `Rules`, with its **own local `TC` table** of ~25 gameplay values hardcoded in the script (lines 23-34), including a *second, different* `startYard`/`td`/`safety`/`maxOtRounds` set. See 5.4.

---

## 3. What the doc got right

Worth saying plainly, because most of it was corrected:

1. **Server-authoritative, no physics ball, no client network ownership.** Exactly what is built, and the doc's reasoning for it is correct and worth keeping verbatim.
2. **Deterministic analytic arc, evaluated identically on server and all clients from `(from, vel, g, t0)`.** Built — `PracticeClient:702` and `PracticeService:494` compute the same thing.
3. **Clients send intents, never outcomes.** Built, with a tighter remote surface than proposed.
4. **Rate limiting and payload validation on remotes.** Built — token bucket at `maxIntentsPerSecond 12` (`takeToken`, PracticeService:277), `typeof` guards at line 746.
5. **Movement sanity with snap-back.** Built, as a distance budget rather than a strike counter.
6. **Speed-based turn limiting / momentum as the core movement feel.** Right idea; wrong numbers and wrong formula.
7. **Three pass types distinguished by hold time.** Built, with the right ordering.
8. **"Every outcome has a readable cause."** The build goes *further* than the doc — every contact produces a `reason` string shown to both players and logged (`resolveContact`, PracticeService:579-586).
9. **Cosmetic-only monetization.** Nothing in any config is purchase-linked. Verified by reading all four config tables.
10. **Jump-ball timing-vs-apex as the skill axis.** Built in `AWFootball`, close in spirit to the doc's 4.4.

---

## 4. What is genuinely NOT built

Practice Field (`AWPractice`), the doc's declared scope:

- **No stamina.** `script_grep` finds no stamina/fatigue anything. The doc's 4.1.4, all six `STAMINA_*` knobs, the exhaustion lockout and the move stamina costs are invented. **Nothing in the code suggests stamina was ever planned.**
- **No defender, no tackling, no sack.** No juke, spin, stiff-arm, stumble or grounded state on the Practice Field.
- **No play cycle.** No Ready / Pre-snap / Snap / Whistle / Spot. No LOS, no offside wall, no play clock, no `PLAY_MAX_DURATION`. The ball returns to a fixed tee, always.
- **No downs, score, possession or match structure** in the Practice build.
- **No AI quarterback.** The "partner" is an anchored dummy you trigger manually; no read, no separation logic, no deadline, no decision. The doc's 3.10 (a)-(d) triggers and all `AI_*` / `SEP_*` knobs are unbuilt.
- **No route practice mode.** No route selection, no ghost line, no per-rep or session stats, no reset loop. (Routes exist in `AWFootball`, not here.)
- **No contested-catch / jump-ball resolution** on the Practice Field. Multiple receivers are handled by "earliest contact wins", which is a race, not a contest: no box-out, no height comparison, no timing score.
- **No interception concept.** `a.defense` exists as a flag on test dummies (PracticeService:1056) and is read in exactly one tie-break (line 640). Nothing else distinguishes a defender.
- **No fumbles** (engine-wide).
- **No first downs** (engine-wide).
- **No safety** in 1v1.
- **No `pressure` term in throw error** — the parameter is plumbed and always 0.
- **No `Flight.timingGrade` / `catchDifficulty` usage.** See 5.1.

Doc-wide:

- **No `NetConfig`, `BallArc`, `BallStates`, `Schema`, `PositionHistory`, `CatchResolver`, `TackleResolver`, `MovementSanity`, `RemoteGuard`, `PlayController`, `AIQuarterback`, `BallView`, `IntentSender`, `ContestFeedback`.** The doc's entire 6.1 module layout is a proposal; none of those names exist. The real layout is `AWPractice/{Config,BallState,Momentum,Carry,Flight,Receive}` plus two scripts.
- **No ADRs, no tests on disk, no QA evidence.** `design/gdd/` holds two files; there is no `tests/`, no `docs/architecture/`, no `production/qa/evidence/` content for this system. The repo's own testing standards are unmet — though the in-Studio test hooks (2.7) are a real, usable substitute that simply is not wired to anything producing retained evidence.

---

## 5. Bugs, exploits and smells noticed in passing

**Not fixed. Reported only.**

### 5.1 `Flight.timingGrade` and `Flight.catchDifficulty` are dead code — HIGH confusion risk

`AWPractice.Flight` lines 66-92 implement the grade ladder (`PERFECT/GOOD/LATE/EARLY/NONE`) and the difficulty-under-1.0 model, and `Config.pass.catch` carries all the knobs for them (`perfectBefore`, `perfectAfter`, `goodBefore`, `earlyLimit`, `lateAfter`, `timing{}`, `threshold`, `reachK`, `runK`, `comfortSpeed`, `speedScale`).

**Neither function is called anywhere.** `script_grep` confirms no call sites. The Practice build decides catches entirely in `Receive.judge`, which uses a *different* model (speed-limit multipliers) and a different subset of config (`Receive.INTENTS`, which **hardcodes** its own reach and speed numbers rather than reading `Config.pass.catch.reach 0.95`).

This matters: the timing-grade model *is* in the code, it is the better-documented of the two, and it is **not the one that runs**. The corrected doc describes `Receive.judge` as the built model and lists the grade ladder as "present but unwired".

Also, inside `catchDifficulty` the timing penalties are `PERFECT 0, GOOD 0.15, LATE 0.35, EARLY 0.45, NONE 0.4` — **pressing too early (0.45) is penalised harder than never pressing at all (0.40)**, so the model rewards not trying. If it is ever wired up, fix that inversion.

Separately, `catchDifficulty` iterates `parts` with `pairs()` to find the `worst` contributor. `pairs` order is not deterministic in Luau, so **which cause is reported on an exact tie is nondeterministic**. The `total` is unaffected.

`Receive.lua:88` defines `closestOnSegment` and never uses it. Harmless.

### 5.2 Any player can kill a live pass — griefing, MEDIUM

`doReset` (PracticeService:324) refuses only two cases: someone *else* is holding the ball, or the ball is already on the tee. **`IN_FLIGHT` is not refused**, so while a pass is in the air any player on the field can press R / Y / TEE and `goDead("RESET")` it — destroying another player's throw and another player's catch. Cooldown is only `resetCooldown 2.0 s`.

By contrast `doQB` (line 728) *does* guard `IN_FLIGHT`. The guard was simply not added to `doReset`.

### 5.3 `catchUp` bypasses every gate — LOW/MEDIUM

`onIntent` (PracticeService:750) handles `catchUp` and returns **before** `takeToken` (rate limit), before the `a.inZone` check, and before the `a.lockUntil` movement-check lockout:

    if action == "catchUp" then doCatchUp(a, data); return end
    if not takeToken(a) then stats.rateLimited += 1; return end
    if not a.inZone then return end

So `catchUp` is unmetered — a client can spam it freely. Practical impact is small (`doCatchUp` only sets `a.hands.up` once and clears an attribute), but it is an unrated remote path and it defeats the lockout a failed movement check is meant to impose. There is then a **dead duplicate branch** at line 761 (`elseif action == "catchUp"`) that can never be reached.

### 5.4 Gameplay values hardcoded in `TeamFootballService` — standards violation

`TC` (TeamFootballService:23-34) holds ~25 tunables inline, including a second `startYard = 20, td = 7, safety = 2, otPossessionsEach = 1, maxOtRounds = 2` that **duplicates and contradicts** `AWFootball.Config.rules` (`maxOtRounds = 3` there). Two sources of truth for the same rules.

The repo's own `coding-standards.md` says "Gameplay values must be data-driven (external config), never hardcoded". `Receive.INTENTS` has the same problem on a smaller scale.

### 5.5 Timestamp backdating is bounded but asymmetric — LOW

`clientTime` (PracticeService:337) lets a client claim its press happened up to `min(catch.lagMax 0.15, ping*2 + 0.05)` seconds ago. Because hands take `RAISE 0.12 s` to come up, backdating a press by 0.15 s can turn a `raised < 1` TIP into a `raised = 1` catch. It is capped and the cap is sane, but it is a direct, exploitable 0.15 s of free reaction time, and a player with artificially inflated ping gets *more* of it (`ping*2`). Worth a look if catching ever feels inconsistent between players.

### 5.6 Smaller notes

- `stats.doubleOwner` (PracticeService:130) is incremented when `HELD` is set with no holder — the code counts a bug it believes impossible. Good instinct; worth confirming the counter really is 0 in a session.
- `buildPartner` anchors the partner's `HumanoidRootPart` (line 242) and never movement-checks it (`a.inZone = true`, line 245). Correct for a dummy, a trap if it ever becomes AI.
- `eligible` (line 495) excludes the thrower from catching their own forward pass unless the ball was deflected. Correct football, and the doc never mentioned it.
- The doc's own UX rule "Touch shows at most 4 context buttons at once" is violated by the build's 8 touch buttons.
- `AWFootball` uses `ball.gravity = 13.5` and `jump.gravity = 22`; `AWPractice` uses real `9.81` for both. See section 6.

---

## 6. Reconciling the three gravities

| Where | Value | Used for |
|---|---|---|
| `AWPractice.Config.ball.gravity` | **9.81 m/s^2** | loose-ball bounce/roll |
| `AWPractice.Config.pass.gravity` | **9.81 m/s^2** | pass arcs |
| `AWFootball.Config.ball.gravity` | **13.5 m/s^2** | pass arcs in 1v1 / team modes |
| `AWFootball.Config.jump.gravity` | **22 m/s^2** | the player's catch-jump arc only |
| doc's `G_BALL` | 80 studs/s^2 (= 28 m/s^2) | nothing |

Why they differ, read from how each is used:

**`AWPractice` can afford real gravity because it chooses flight time directly.** `Flight.solve` for TOUCH/LOB picks `T = t0 + tk*d` and *derives* launch velocity from it. The arc shape you want comes from choosing `T`, so gravity never has to be faked; it stays at 9.81 and the physics stays honest and explicable.

**`AWFootball` inherited an arcade gravity from the browser prototype.** `Rules.flightTime` (Rules:26) derives `T` from a *speed* clamp (`throwSpeedMin 14` to `throwSpeedMax 24`, then clamped to `minFlight 0.55`-`maxFlight 1.6`). With flight times capped at 1.6 s, real gravity would make every pass a flat line drive with no readable arc; raising g to 13.5 buys visible arc height back inside a short flight. A presentation fix, not a simulation.

**`jump.gravity = 22` is deliberately not ball gravity.** With `jumpSpeed 6.2`, apex time is `6.2/22 = 0.282 s` and apex height is `0.87 m`. At 9.81 the same launch speed gives 0.63 s hang and 1.96 m — a floaty moon-jump, and a 0.63 s apex window makes jump-ball timing far too forgiving. High gravity makes the jump snappy and the timing window tight, which is exactly what `resolveJumpBall` measures.

So two of the three are defensible and one (`ball.gravity 13.5`) is legacy. The doc's 80 studs/s^2 matches none of them and is dropped. **The Practice Field's 9.81 is the convention to carry forward**, and the corrected doc says so and explains the other two rather than pretending they agree.

---

## 7. Recommendations (not actions)

1. **Fix 5.2 first** — a one-line guard, and it is player-visible griefing.
2. **Decide the catch model.** Two live models (deterministic speed-limit vs reach + quality roll) will diverge further every sprint. The Practice Field's is better; `AWFootball`'s has RNG that the project's own design pillar ("I know exactly why") argues against.
3. **Either wire up or delete `Flight.timingGrade`/`catchDifficulty` and their config keys.** Dead code that looks authoritative is worse than no code — it misled this audit and will mislead the next reader.
4. **Rename `turnFast`/`turnSlow`** to something unambiguous (`turnAtRest`/`turnAtSprint`).
5. **Move `TC` and `Receive.INTENTS` numbers into config** to satisfy the repo's own standard.
6. **Decide first downs.** Today a possession is "4 plays, then it's the other guy's turn" — a real and arguably good arcade design, but not what the doc described, and it should be an explicit choice rather than an omission.
