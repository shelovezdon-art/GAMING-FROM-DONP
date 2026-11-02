# ALLSTAR WORLD — Football test plan (repeatable)

**Date:** 2026-11-02
**Product under test:** `ServerScriptService.TeamFootballService` (2v2 / 5v5) — the football product per **ADR-0001**.
**Not under test as product:** `PracticeService` + `ReplicatedStorage.AWPractice` (test bench, never shipped) and
`FootballService` (legacy 1v1). They appear here only as *sources of hooks and reference implementations*.

**Standard this plan is written to (owner's words):**
> "Use repeatable tests for passes, shots, bounces, collisions, possession changes, scoring, and restarts. Compare
> representative situations with real-world references. Test complete matches as well as isolated mechanics."

**Traceability.** Every expected value carries a tag:
`[RULESET §n]` = `design/gdd/football-ruleset.md`; `[AUDIT §n]` = `docs/audits/2026-11-02/football-core.md`;
`[CFG <path>]` = a key read live out of Studio on 2026-11-02 (`52e32916-3102-403b-a01b-8b4d550c1fae`, Edit datamodel).
**`[OWNER — BLANK]`** means the correct value is an open owner decision; the expectation is deliberately empty and the
test is not runnable until it is answered. **No number in this plan was invented.**

**Evidence.** Every test that changes something player-observable closes with a retained screenshot in
`production/qa/evidence/` named `<TEST-ID>-<yyyymmdd>.png`. A parse check is not a run
(`.claude/docs/coding-standards.md`).

---

## 0. Test hooks — what exists, what must be built

### 0.1 What exists today

| Hook | Where | Commands | Serves |
|---|---|---|---|
| **`ReplicatedStorage.AWFootball.TestHookTeam`** | `TeamFootballService:1735` (script_read numbering) | `fields`, `join(player, fieldId, team)`, `intent(player, data)`, `state`, `athletes` | **the product** |
| `ServerStorage.AWPracticeTest` | `PracticeService:985` | 20 commands: `dummy`, `dummyHands`, `drive`, `setLag`, `qbTo`, `throwFrom`, `ball`, `log`, `results`, `flight`, `geometry`, `resetStats` … | test bench only |
| `ServerStorage.AWTackleTest` | `TackleService:794` | `state`, `role`, `tackle{by,kind}`, `move{by,move}`, `jump{name,at}`, `results`, `contests`, `resetStats` | test bench only, **and the script is `Disabled = true`** |
| `ReplicatedStorage.AWHoops.TestHook3` | `Hoops3Service:103` | `join`, `intent`, `start`, **`call(method,args)`**, **`set(objPath,key,value)`**, **`snap()`** | basketball — **the template to copy** |
| `PlayerGui.Debug` (BindableFunction) | `PracticeClient:700` | `trace`, `hands`, `raise`, `lower`, `pose`, `input` | test bench client |
| `PlayerGui.AW3TestInput` (BindableEvent) | `Hoops3Client:493` | drives the real key handlers | basketball client |

### 0.2 The first finding, and the first ask

**`TestHookTeam` is an observation hook, not a test rig.** It can read state and inject an intent. It **cannot**:
place a body, set a velocity, force a down/score/possession, fake lag, or read per-outcome logs. By contrast
`Hoops3Service.TestHook3` has exactly the three generic commands that make basketball scriptable — `call`, `set`,
`snap`. **`TeamFootballClient` (533 lines) has no test hook at all** — no equivalent of `AW3TestInput` — so no human
*client* input path can be driven; only server-side intents via `TestHookTeam.intent`.

Consequence: **most tests below are MANUAL today and become AUTOMATABLE the moment the hooks in 0.3 exist.** This
plan states, per test, which hook it needs.

### 0.3 Hooks that must be built (priority order)

| ID | Hook | Shape | Why |
|---|---|---|---|
| **H1** | `TestHookTeam.call` / `set` / `snap` | **Copy verbatim from `Hoops3Service` TestHook3** (`call(method,{args})` with `@home1` athlete resolution; `set(objOrNil, "a.b.c", v)`; `snap()` returning every athlete's `x,z,speed,man` plus ball, state, phase, holder) | Unblocks ~all setup. Single highest-leverage item in this plan. |
| **H2** | `TestHookTeam.place(id, x, z, headingDeg, speedMps)` | Position + facing + velocity in metres, field coords | Every geometry test (tackle matrix, catch, coverage) needs a known start. `G:place` already exists internally. |
| **H3** | `TestHookTeam.results(n)` / `events(n)` | Return the last n entries of `self.events` (already maintained, capped 400, `G:log` at `:453`) with outcome + reason strings | Turns a visual judgement into an assertion. The log exists; it just isn't exposed. |
| **H4** | `TestHookTeam.setLag(player, seconds)` | Mirror of `AWPracticeTest.setLag` | Nothing in the product can be lag-tested today. |
| **H5** | `AWTFTestInput` BindableEvent in `TeamFootballClient` | Mirror of `Hoops3Client:493` `AW3TestInput` | The only way to test the real client input path (press timing, hold-vs-tap) without a human. |
| **H6** | `TestHookTeam.forceScoreboard(down, los, toGain, possession, score, otRound)` | Direct state set — or just use **H1 `set`** | Reaching down 4, OT, or a 20-0 scoreline otherwise takes a full match per test. |

> H1 alone makes H2 and H6 unnecessary (`set`/`call` cover them). Build H1 first; it is a paste of code that already
> works in the basketball service.

### 0.4 Harness convention for every AUTOMATABLE test

```lua
-- Studio Command Bar / a Script under ServerScriptService, Edit or Run mode
local H = game.ReplicatedStorage.AWFootball.TestHookTeam
local function s() return H:Invoke("state") end
-- setup → act → read → print one PASS/FAIL line, then screenshot the output window
```
Every automatable test must print exactly one line of the form
`[TEST-ID] PASS|FAIL expected=<x> actual=<y>` and that console line is the recorded observation.

---

## 1. Movement

> **Honest state:** the product has **no acceleration, braking or turn-rate model.** `TeamFootballService` reads only
> `CFG.move` (`[CFG AWFootball.Config.move]`) — flat top speeds — and never `AWPractice.Momentum`. The momentum model
> (`accelTime 0.6 s`, `brakeTime 0.3 s`, `turnFast 720°/s at rest → turnSlow 260°/s at sprint`, `cutAngle 75°`
> `[AUDIT §2.1, §2.3]`) exists **only on the test bench**. So MOV-2/3/4 below test an absence.

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **MOV-1** | 5v5 field, join one human to `home` slot 2 (receiver), AI fills rest. Live play, `phase = "run"` not required. | Hold sprint forward down the sideline for 3 s. | Top speed **9.6 m/s** for a WR `[CFG move.wrSpeed]`; a DB **9.3** `[CFG move.dbSpeed]`; carrying the ball **9.0** `[CFG move.carrySpeed]`. | H1 `snap()` → `speed` field, sampled 10×/s; take the max. Today: `athletes` gives x,z only, so differentiate position over time. | **AUTOMATABLE (needs H1; degraded MANUAL today)** |
| **MOV-2** | Same. | From a standstill, full sprint input; time to reach 9.5 m/s. | **`[OWNER — BLANK]`** — the product defines no accel time. Record the measured value as the baseline. Do **not** assert `0.6 s`: `move.accelTime` belongs to `AWPractice.Config` `[AUDIT §2.1]` and is not read here. | Speed trace from H1 `snap()`. | AUTOMATABLE (needs H1) |
| **MOV-3** | Same, at full sprint. | Reverse input 180°. | **`[OWNER — BLANK]`** — no turn-rate limit exists in the product. Record degrees/second actually achieved and whether speed is retained through the reversal. If it reverses instantly at full speed, that is a defect to log, not a pass. | Heading from H1 `snap()`; plus a screenshot of the reversal. | AUTOMATABLE (needs H1) + MANUAL eyes |
| **MOV-4** | Human carrier in `phase = "run"`. | Sprint 3 s carrying, then compare with MOV-1. | Carrying top speed **9.0 m/s** `[CFG move.carrySpeed]` — i.e. **93.8 %** of `wrSpeed`. (The bench's `carryFactor 0.96` `[AUDIT §2.1]` is a different number in a different codebase; do not mix them.) | H1 `snap()`. | AUTOMATABLE (needs H1) |
| **MOV-5** | Human QB with the ball, `phase = "pocket"`. | Sprint. | Capped at **7.2 m/s** `[CFG TC.qbPocketSpeed]`, enforced at `TeamFootballService:1538`(read)/`:769`-region. | H1 `snap()`; HUD. | AUTOMATABLE (needs H1) |
| **MOV-6** | Human DB in coverage, pre-release. | Backpedal. | Pedal speed **6.6 m/s**, hip flip takes **0.18 s** `[CFG pedal.speed, pedal.flipTime]`; beaten by **0.6 m** forces a flip with a **0.3 s** stumble `[CFG pedal.beatenMargin, pedal.beatenStumble]`. | H1 `snap()` for speed; screenshot for the flip animation. | AUTOMATABLE (needs H1) + MANUAL (the flip reads as a flip) |

---

## 2. The snap and cadence

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **SNAP-1** | 5v5, all slots AI, start a match. | Let the AI QB snap. | AI cadence is random in **0.9–2.2 s** `[CFG stance.cadenceMin/Max]`; over 20 snaps every value lies inside the band and the mean is near 1.55 s. | `TestHookTeam.state` polled for `phase` flipping `pre → pocket`; timestamp each. | **AUTOMATABLE today** (`state` + poll) |
| **SNAP-2** | Human QB, slot 1, in `preSnap`. | Do nothing. | Auto-snap after **15 s** `[CFG TC.humanSnapAuto]`; once SET, **4 s** to snap `[CFG TC.humanSetToSnap]`. | `state.phase`; HUD countdown. | AUTOMATABLE today |
| **SNAP-3** | Human receiver, `pre = "set"`. | Move before the HUT. | **FALSE START**, `−5 yd` from the LOS, **replay the down** (`G:falseStart`, `TeamFootballService:769`; `[CFG stance.falseStartYards = 5]`, grace `setGrace 0.45 s`). Matches `[RULESET §2 penalties]` (−5 from the LOS) and `[CFG penalty.fouls.falseStart]`. | `state.los` before/after; the toast text; screenshot of the toast. | AUTOMATABLE (needs H2/H1 to move a body) + MANUAL screenshot |
| **SNAP-4** | Human receiver on the line. | Release exactly on the HUT. | **PERFECT** inside **0.15 s** → burst ×**1.18** for **0.7 s**; **GOOD** inside **0.35 s** → ×**1.08**; auto-release at **0.6 s** `[CFG stance.perfect, good, perfectBurst, goodBurst, burstTime, autoRelease]`. | H5 to press at a scripted offset; speed via H1 `snap()`. | AUTOMATABLE (needs **H5 + H1**) |
| **SNAP-5** | 5v5 pre-snap. | Count bodies on the line and their depths. | **`[OWNER — BLANK]`** — `[RULESET §3]` borrows "exactly four on the line, one defender ≥10 yd off, rest 4 yd off, no blitzing, no rushing from outside the box"; the product instead uses `rushDepth 6`, `cushion 5`, `rushCount 3.0 (2v2) / 3.2 (5v5)` `[CFG TC]`, and **nobody snaps the ball** — `[RULESET §7 Q2]` (QB self-snap vs a CENTER slot) is unanswered. Record the actual formation; assert nothing. | Screenshot of the pre-snap formation from the sideline camera + H1 `snap()` coordinates. | **MANUAL** |

---

## 3. Throws — all three types

> Product throw model: `Rules.flightTime` derives flight time from a **speed** clamp `throwSpeedMin 14 → throwSpeedMax 24`
> then clamps the time to `minFlight 0.55 – maxFlight 1.6 s`, with `ball.gravity = 13.5` `[CFG qb, ball]` `[AUDIT §6]`.
> The ruleset's model is the opposite — hold the 20–27 m/s band and vary **launch angle** (`BULLET 5–15°`,
> `TOUCH 20–30°`, `LOB 35–45°`) `[CFG ballPhysics.throwAngleDeg]` `[RULESET §4]`. **These disagree.** The tests record
> the product's behaviour and compare it against the sourced reference; THR-4 is the reference test.

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **THR-1 (bullet)** | AI-only 5v5; place QB at own 20, a receiver on a `slant` at 8 m `[CFG Rules.ROUTES]`. | Tap throw (no hold). | Flight time ≥ **0.55 s** `[CFG ball.minFlight]`; release speed inside **14–24 m/s** `[CFG qb.throwSpeedMin/Max]`; arc is visibly flat. Against the reference: a real bullet leaves at **≈20 m/s typical / 25 elite** at **5–15°** `[CFG ballPhysics.releaseTypicalMps, throwAngleDeg.BULLET]` — the product's 24 m/s ceiling is inside the sourced band, the **angle is not controlled at all**. | H3 `events` for the throw record; stopwatch via `state.phase` `pocket → flight → run`; one screenshot at mid-flight. | AUTOMATABLE (needs **H1 + H3**) |
| **THR-2 (touch)** | Same, receiver on a `curl` ~12 m. | Hold < `lobHold 0.35 s` `[CFG TC.lobHold]`. | Flight time between `minFlight 0.55` and `maxFlight 1.6` s; ball arrives at `catchHeight 1.25 m` `[CFG ball.catchHeight]`. Reference: a touch pass is **20–30°** `[CFG throwAngleDeg.TOUCH]`. | As THR-1. | AUTOMATABLE (needs H1+H3) |
| **THR-3 (lob / jump ball)** | Same, receiver on a `fade` or `seam`. | Hold ≥ **0.35 s** `[CFG TC.lobHold]`. | Flags a **high ball**: `highBall = true`; apex gives a catch height of **2.05 m** `[CFG jump.highCatchHeight]`; flight scaled ×**1.35**, capped **1.95 s** `[CFG jump.flightScale, jump.maxFlight]`. HUD must read "JUMP BALL · SPACE at the peak" (`TeamFootballService:2910`-region). | `state`; HUD screenshot at the apex. | AUTOMATABLE (needs H1+H3) + MANUAL screenshot |
| **THR-4 (real-world reference)** | Any throw over the longest available distance on the 45.72 m field `[CFG field.lengthM]`. | Maximum-range throw. | **Calibration, not pass/fail:** a drag-free **27.4 m/s at 30°** travels **66.4 m in 2.80 s** `[CFG ballPhysics.dragFreeRangeM, dragFreeTimeS]`; a real throw must land **measurably shorter**. The product's `maxFlight 1.6 s` ceiling means it *cannot* produce a 2.8 s ball at all. Record measured range and time; file the gap as a finding. | H3 `events` + a measured landing spot via H1 `snap()`. | AUTOMATABLE (needs H1+H3) |
| **THR-5 (accuracy / pressure)** | AI QB; one run with a rusher within `pressureRadius 2.6 m`, one clean. | Throw. | Error grows: `err = (1 − accuracy 0.82) × 3.2 + rushedPenalty 0.9 (if rushed or pressured) + onRunPenalty 0.6 (if moving > onRunSpeed 3.5 m/s)` `[CFG qb.accuracy, qb.rushedPenalty, TC.pressureRadius, TC.onRunPenalty, TC.onRunSpeed]` (`TeamFootballService:1985`-region, script_read). Over 20 throws each, mean miss distance is larger under pressure. | H3 `events` → ball landing vs target; aggregate. | AUTOMATABLE (needs H1+H3) |
| **THR-6 (spiral / nose — visual)** | Any pass. | Watch the ball. | Spiral **≈62.8 rad/s** (600 rpm), nose tracks velocity with **2.52 rad/s** precession and a **9°** yaw bias; a bad throw **wobbles at 38.0 rad/s AND lands measurably shorter** `[CFG ballPhysics.spinRadS, precessionRadS, yawOffsetDeg, nutationRadS]` `[RULESET §4]`. **None of `ballPhysics` is read by any service** (see §16) — so today this test's expected result is *"the ball does not spiral or track at all"*. Record what it actually does. | Retained screenshot at three points of one flight + a short screen recording if available. | **MANUAL** |

---

## 4. Catching

> The product resolves normal catches with **`Rules.resolveCatch`, which is RNG**: human secure **0.97**, aggressive
> **0.80**, no press `autoChance 0.50`, mistimed press **0.35**, seeded LCG `seed = 1337` `[AUDIT §2.9]` `[CFG seed]`.
> A deterministic alternative is **configured but does not exist**: `CFG.catch.model = "roll"` points at
> `Rules.judgeCatchDeterministic`, and `Rules` has no such function (its 13 functions are `clamp, newRng, routeWorld,
> solveThrow, flightTime, resolveTackle, catchGrade, jumpHeight, jumpApexTime, jumpReaches, resolveJumpBall,
> resolveCatch, yardsBetween`). **That dead pointer is a defect; log it.**
> Because catches are random, every catch test is a **frequency test over ≥ 50 reps with the seed fixed**, not a
> single-trial assertion.

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **CAT-1 (clean, secure)** | AI QB, human receiver uncovered, ball inside `secureReach 1.3 m` `[CFG catch.secureReach]`. | Press catch inside the window (`windowEarly 0.4 s`, `windowLate 0.15 s` `[CFG catch.windowEarly/Late]`). | Caught **≈97 %** of 50 reps `[AUDIT §2.9]`. Outside the window → **35 %**. | H3 `events` tally; one screenshot of the catch. | AUTOMATABLE (needs **H1+H3+H5**) |
| **CAT-2 (no press)** | Same, never press. | Nothing. | Auto-catch at **50 %** within `autoReach 0.9 m` `[CFG catch.autoChance, autoReach]`. | H3 tally. | AUTOMATABLE (needs H1+H3) |
| **CAT-3 (contested)** | Defender inside `contestRadius 1.1 m` at arrival `[CFG catch.contestRadius]`. | Receiver presses secure. | AI receiver quality drops by `cpuContestedPenalty 0.4` from `cpuBase 0.86` `[CFG catch.cpuBase, cpuContestedPenalty]` (`Rules:110`). For a **human** receiver, record the measured rate — the penalty applies to the CPU branch. `[RULESET §4]` flags "contested is harder" as **unsourced coaching lore — tuning, not fact**, so this is a baseline, not a correctness assertion. | H3 tally + screenshot of the contest. | AUTOMATABLE (needs H1+H3) |
| **CAT-4 (over-the-shoulder)** | Receiver running away from the QB, ball arriving behind the head. | Catch. | **`[OWNER — BLANK]`** for a pass/fail threshold. The sourced technique rule is the **thumbs-up above the waist / pinkies-down below it** switch at `waistM 1.05`, with `overShoulderAdd 0.22` `[CFG catch.det.waistM, overShoulderAdd]` — but `catch.det` is **unwired** (`model = "roll"`, and the deterministic function is missing). Record the rate and whether the *animation* selects correctly. | H3 tally + screenshot of the hand position. | AUTOMATABLE rate (H1+H3) + **MANUAL** for the hands |
| **CAT-5 (hit before secure)** | Receiver catching, defender arrives during the securing window. | Tackle at the instant of arrival. | **INCOMPLETE, not a tackle** — the bench's `Tackle.resolve` returns `INCOMPLETE "HIT BEFORE HE SECURED IT"` when `securingUntil > 0` (`AWPractice.Tackle:170`). **The product has no securing window at all** — `TeamFootballService` reads `CFG.tackle` (`reach 1.35`, `facingCos 0.15`, `jukeImmunity 0.28`, `cleanClosingSpeed 4.0` `[CFG tackle]`) and `Rules.resolveTackle`, whose outcomes are `NOT_LIVE / NO_CONTACT / WHIFF / EVADED / WRAP / CLEAN_TACKLE` `[AUDIT §2.9]` — **no INCOMPLETE**. So the expected result today is "the hit is scored as a tackle". **This is a rules defect; log it.** | H3 `events` outcome string. | AUTOMATABLE (needs H1+H2+H3) |
| **CAT-6 (swat / interception)** | Human defender, ball in flight toward his man. | Press swat. | Swat within **1.7 m**, intercept within **0.95 m** `[CFG defend.swatReach, defend.intReach]`; AI attempts at `cpuAttemptChance 0.55` after `reaction 0.22 s` `[CFG defend]`. | H3 `events`; screenshot of the interception. | AUTOMATABLE (needs H1+H3+H5) |

---

## 5. Tackling — the full wrap/dive counter matrix

> **Where the matrix lives.** The complete, deterministic counter matrix is `ReplicatedStorage.AWPractice.Tackle`
> (`Tackle.resolve`, 263 lines, pure maths, no Roblox objects) with its config in `AWPractice.Config.tackle`. It is
> driven by `ServerScriptService.TackleService`, which is **`Disabled = true`** and whose possession seam
> (`ServerStorage.AWPracticeBall`) is **not installed** — so a tackle there is reported but the whistle never blows.
> **The product uses a different, smaller resolver:** `AWFootball.Rules.resolveTackle` →
> `NOT_LIVE / NO_CONTACT / WHIFF / EVADED / WRAP / CLEAN_TACKLE`, with a `0.35 s` break window and a
> `cpuBreakChance 0.35` **roll** for AI breaks `[AUDIT §2.9]` `[CFG tackle]`.
>
> So TKL-1…TKL-12 are written against `AWPractice.Tackle` because **that is the only place the matrix exists**, and
> they are the acceptance tests for porting it into the product. Each row says what the *product* does today.

**TKL-0 — unit-test harness (the one genuinely free test).** `AWPractice.Tackle` has no Roblox dependencies, so the
whole matrix is testable with `loadstring` and no play session:

```lua
-- Edit mode, Command Bar. Reads only. require() caches, so loadstring the source.
local Tackle = loadstring(game.ReplicatedStorage.AWPractice.Tackle.Source)()
local CFG    = loadstring(game.ReplicatedStorage.AWPractice.Config.Source)()
local T, SPRINT = CFG.tackle, CFG.move.sprint            -- sprint = 7.8 m/s [AUDIT §2.1]
local function geo(dx, dz, fx, fz, tvx, tvz, cvx, cvz)
    return Tackle.geometry{ dx=dx, dz=dz, fx=fx, fz=fz, tvx=tvx, tvz=tvz, cvx=cvx, cvz=cvz }
end
local function run(id, input, want)
    local r = Tackle.resolve(input, T)
    print(("[%s] %s expected=%s actual=%s · %s · by=%s")
        :format(id, r.outcome == want and "PASS" or "FAIL", want, r.outcome, r.reason, tostring(r.decidedBy)))
end
```
`Tackle.reach(armReachM, kind, cfg)` = `armReachM + bodySlack 0.19 + latencySlack 0.35` (+ `diveExtra 0.35` for a
dive) `[CFG AWPractice.Config.tackle]`. Use a representative R15 arm of **0.60 m** → wrap reach **1.14 m**, dive
reach **1.49 m**. State the arm length in the test output, because reach is measured off the real rig
(`Receive.rig`) and is **not** a constant `[AUDIT §2.6]`.

| ID | Matrix cell / setup (metres, m/s) | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **TKL-1** | `d = reach + missMargin + 0.1` (> 1.14+1.2) | wrap | **`NO_CONTACT`**, `decidedBy = "range"`, no commitment cost `[Tackle:155]` | console line | **AUTOMATABLE today (TKL-0)** |
| **TKL-2** | `reach < d ≤ reach + missMargin 1.2` | wrap | **`WHIFF`**, `decidedBy = "range"`, reason names the shortfall in metres `[Tackle:158]` | console | AUTOMATABLE today |
| **TKL-3** | in reach, `facingCos < wrapCos 0.5` (> 60° off) | wrap | **`WHIFF`**, `decidedBy = "angle"` `[CFG tackle.wrapCos]` | console | AUTOMATABLE today |
| **TKL-3b** | in dive reach, `facingCos` between `diveCos 0.15` and `0.5` (~81° arc) | dive | **connects** — a dive has the wider arc `[CFG tackle.diveCos]` | console | AUTOMATABLE today |
| **TKL-4** | in reach, `age < wrapStartup 0.10 s` | wrap | **`NO_CONTACT`**, `"ARMS WEREN'T CLOSED YET"`, `decidedBy = "startup"` `[Tackle:165]` | console | AUTOMATABLE today |
| **TKL-5** | `securingUntil > 0` | wrap or dive | **`INCOMPLETE`** — a hit before the catch is secured is an incompletion `[Tackle:170]` | console | AUTOMATABLE today |
| **TKL-6** | `stumbleUntil > 0` (gang tackle / off his feet) | any contact | **`TACKLED`** (or `FUMBLE` if TKL-11's four conditions all hold), `decidedBy = "stumbling"` `[Tackle:174]` | console | AUTOMATABLE today |
| **TKL-7** | `jukeUntil > 0` | wrap | **`WHIFF`**, `"JUKED YOU OUT OF YOUR BOOTS"`, `decidedBy = "juke"`. Juke immunity lasts `jukeImmunity 0.28 s` after `jukeTime 0.22 s` at `jukeSpeed 12.5` `[CFG tackle]` | console | AUTOMATABLE today |
| **TKL-8** | live stiff-arm, `stiffAge 0.15 s` (= `stiffPeak`, quality 1.0), tackler inside the front 120° (`alphaCos ≥ stiffCone −0.5`), `broken < maxBreaks 2` | **wrap** | **`BROKEN`**, `decidedBy = "matrix:stiffArmVsWrap"`, tackler stunned `stiffStun 0.70 s` `[Tackle:195]` | console | AUTOMATABLE today |
| **TKL-8b** | same stiff-arm | **dive** | stiff-arm **ignored** (`saQ = nil` for a dive, `Tackle:187`) → falls through to the score; a dive goes in under the arm | console | AUTOMATABLE today |
| **TKL-8c** | stiff-arm live but tackler **behind** (`alphaCos < −0.5`) | wrap | stiff-arm does **not** apply `[Tackle:186]`; score decides | console | AUTOMATABLE today |
| **TKL-9** | `spinUntil > 0`, `broken < 2` | **wrap** | **`BROKEN`**, `"SPUN OUT OF THE WRAP"`, `decidedBy = "matrix:spinVsWrap"`, carrier stumbles `stumble 0.35 s` `[Tackle:199]` | console | AUTOMATABLE today |
| **TKL-9b** | `spinUntil > 0` | **dive** | **`TACKLED`**, `decidedBy = "matrix:diveVsSpin"` — dives beat spins `[Tackle:207]` | console | AUTOMATABLE today |
| **TKL-10 (fatigue)** | `broken = 2` (= `maxBreaks`) with a peak stiff-arm **or** spinning | wrap | **`WRAPPED`**, `"GASSED · 2 BROKEN ALREADY"`, `decidedBy = "fatigue:gassed"`, `drag = wrapDrag 0.45`, `breakWindow 0.35` `[Tackle:203]`. Also assert the soft term: `fatigue = −0.10 × broken` inside `breakScore` `[CFG tackle.fatigue]`. | console | AUTOMATABLE today |
| **TKL-10b (momentum break)** | wrap from behind (`alphaCos < −0.5`) with `carrierSpeed − max(closing,0) > breakSpeedDelta 2.0` | wrap | **`STUMBLE`**, reason quotes the m/s differential, `decidedBy = "matrix:momentumBreak"` `[Tackle:213]` | console | AUTOMATABLE today |
| **TKL-10c (score path)** | no matrix cell applies; sweep `closing` and `alphaCos` | wrap / dive | `score = clamp(base + 0.15·momentum + 0.15·angle + stiff + spin − 0.10·broken, 0.02, 0.75)`; `base` = `0.10` wrap / `0.25` dive; **breaks at ≥ `breakAt 0.50`** `[CFG tackle.*]`. Assert the boundary at 0.49 vs 0.50 and that `decidedBy` names the largest term. | console | AUTOMATABLE today |
| **TKL-11 (fumble — all four)** | **dive** AND (`spinning` OR `jukeRecoveryUntil > 0`, i.e. ball away from the body) AND `closing ≥ fumbleClosing 0.80 × sprint 7.8 = 6.24 m/s` AND `alphaCos < fumbleBlindCos −0.5` (blind side, > 120° off) | dive | **`FUMBLE`**, `"STRIPPED ON THE BLIND SIDE · BALL'S OUT"` `[Tackle.fumbles:125]`. Then negate each of the four in turn → **no fumble**. Four negative cases are mandatory; a fumble that can happen on a wrap is a defect. | console | AUTOMATABLE today |
| **TKL-12 (wrap answer)** | `WRAPPED` with score `s`, inside `breakWindow 0.35 s` | `spin` / `stiffarm` / `juke` / nothing | `spin` and `stiffarm` **always** break it; `juke` breaks it only if `s ≥ breakAt 0.50 − jukeAnswer 0.12 = 0.38`; nothing → `"NO ANSWER · TAKEN DOWN"`; and at `broken ≥ 2` **all** answers fail with `"GASSED"` `[Tackle.answerWrap:240]` | console | AUTOMATABLE today |
| **TKL-13 (miss penalty)** | each outcome | — | `NO_CONTACT` → 0; wrap miss → `wrapMiss 0.40 s` slowed; dive miss → `diveMiss 1.00 s` of which `grounded 1.00 s` on the floor; attempts gated by `cooldown 0.90 s` `[Tackle.missPenalty:254]` | console | AUTOMATABLE today |
| **TKL-14 (in the product)** | 5v5, human defender, AI carrier running. | Tackle. | Product outcomes only: `WHIFF / EVADED / WRAP / CLEAN_TACKLE`; `CLEAN_TACKLE` needs `closing ≥ cleanClosingSpeed 4.0` **and** `angle ≥ cleanAngleCos −0.2`; a `WRAP` gives `breakWindow 0.35 s` then `wrapDrag 0.45 s` to the ground; the AI breaks on a **`cpuBreakChance 0.35` roll** `[AUDIT §2.9]` `[CFG tackle]`. **No fumble, no fatigue, no INCOMPLETE.** | H3 `events` outcome + reason; screenshot of the tackle. | AUTOMATABLE (needs H1+H2+H3) + MANUAL screenshot |
| **TKL-15 (dive visual)** | — | Dive. | Travel = `diveSpeed 12.5 × diveTime 0.30 = 3.75 m` `[Tackle.diveTravel]`. Measure it on the field; it must read as a full-length lunge, not a step. | H1 `snap()` start/end + screenshot mid-dive. | AUTOMATABLE distance + **MANUAL** look |
| **TKL-16 (blocks / collisions)** | 5v5, offensive body runs into a defender in `phase = "run"`. | Collide. | Defender slowed for `blockDrag 0.55 s` at `engagedScale 0.40` of speed, within `blockReach 1.2 m`, blocker cooldown `blockCooldown 1.3 s` `[CFG TC]` (`TeamFootballService:2517`-region). Collision group `AWFootball` is non-collidable with itself (`:46`-`:48`), so bodies pass through each other — **confirm that reads acceptably or log it.** | H1 `snap()` speed trace; screenshot of the block. | AUTOMATABLE (needs H1) + **MANUAL** |

---

## 6. Jump balls

> `Rules.resolveJumpBall` is **mostly** deterministic: both leaps' timing error vs the apex is compared, nearest wins;
> defender needs `swatReach 1.7` to swat, `intReach 0.95` to intercept; an aggressive receiver gets
> `aggressiveMargin 0.05`; **the one roll is the uncontested skied catch (quality 0.95)** `[AUDIT §2.9]` `[CFG jump, defend]`.
> The bench's `AWPractice.Contest` is a fully deterministic alternative (`wTiming 0.45 / wPosition 0.35 / wHeight 0.20`,
> `perfectBand 0.06`, `timingWindow 0.22`, `heightTol 0.55`, `boxoutBonus 0.15`, `tieMargin 0.04`,
> `minToCatch 0.35`, `intThreshold 0.62` `[CFG AWPractice.Config.contest]`) and is **not wired into the product**.

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **JMP-1** | Lob to a receiver with a defender inside `tightCoverage 2.2 m` `[CFG jump.tightCoverage]`. | Both jump; receiver's timing nearer the apex. | Receiver wins. Apex at `jumpSpeed 6.2 / gravity 22 = 0.282 s`, height **0.87 m** `[CFG jump]` `[AUDIT §6]`. | H3 `events`; screenshot at the apex. | AUTOMATABLE (needs H1+H3+H5) |
| **JMP-2** | Same, defender's timing nearer. | Both jump. | Defender swats (within 1.7 m) or intercepts (within 0.95 m) `[CFG defend]`. | H3 `events`. | AUTOMATABLE (needs H1+H3+H5) |
| **JMP-3** | Identical timing to within `aggressiveMargin 0.05 s`. | Both jump; receiver uses the aggressive catch. | **Receiver** wins the tiebreak `[CFG jump.aggressiveMargin]`. Repeat 20× — the result must be the **same every time** (no roll in the contested path). | H3 `events` tally. | AUTOMATABLE (needs H1+H3+H5) |
| **JMP-4** | Uncontested sky catch. | Jump alone. | **≈95 %** caught `[AUDIT §2.9]` — and record that this is the one RNG path in jump balls, which the pillar "I know exactly why" argues against. | H3 tally over 50 reps. | AUTOMATABLE (needs H1+H3) |
| **JMP-5 (height needed)** | Ball at `highCatchHeight 2.05 m`, receiver not jumping. | Press secure. | Must miss — `needHeight 0.55 m` of leap is required `[CFG jump.needHeight, highCatchHeight]`. | H3 `events`. | AUTOMATABLE (needs H1+H3) |

---

## 7. Possession changes

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **POS-1 (turnover on downs)** | Force `down = 4`, LOS short of midfield (H1 `set`). | Run a play that fails to cross the middle line. | `"TURNOVER ON DOWNS"`; `nextStep = "possession"`; `possession += 1`; new offence placed at **its own `startYard 20` yd** `[CFG TC.startYard]` (`G:newPossession:587-590`). **`[RULESET §2]` says the snap spot is the own 5 (`4.57 m`), and `[CFG series.snapOwnM = 4.57]` exists — but `TeamFootballService` never reads `CFG.series`.** Assert 20 as the product's behaviour and log the 15-yard discrepancy. | `state.down / possession / los / offense`; HUD screenshot. | AUTOMATABLE (needs H1/H6) |
| **POS-2 (interception)** | Defender intercepts inside `intReach 0.95 m` `[CFG defend.intReach]`. | Intercept. | Product: possession flips. `[RULESET §2]` requires the defence to take over **at the dead-ball spot** with the **return staying live** (`[CFG series.interceptionReturnsLive = true]`) — the one exception to the own-5 rule. Record whether the product spots at the interception point or at `startYard 20`. | `state.los` immediately after; H3 `events`. | AUTOMATABLE (needs H1+H3) |
| **POS-3 (fumble)** | — | — | **NOT TESTABLE — the mechanic does not exist.** `script_grep "fumble"` matches nothing in `TeamFootballService` or `FootballService` `[AUDIT §4]`; the only fumble code is `AWPractice.Tackle.fumbles`, reachable only through `TackleService`, which is `Disabled = true` with no possession seam. Covered in isolation by **TKL-11**. | — | **BLOCKED** |
| **POS-4 (sack / safety)** | Carrier tackled in his own end zone. | Tackle. | `SAFETY`, **+2 to the opponent** `[CFG TC.safety = 2]`, matching `[RULESET §2]` and `[CFG scoring.safety = 2]` (`TeamFootballService:2617, :2685`-region). | `state.score`; HUD screenshot. | AUTOMATABLE (needs H1+H2) |
| **POS-5 (out of bounds)** | Carrier or ball crosses `halfW` `[CFG field.widthM 22.86 → half 11.43 m]`. | Step out. | Play ends `OOB`; ball spotted where it went out; no possession change. A pass out of bounds → `OUT_OF_BOUNDS` → incomplete (`:1916, :2064`-region). | `state.los`, `events`. | AUTOMATABLE (needs H1+H3) |
| **POS-6 (ground = dead)** | Pass hits the turf. | Throw into the dirt. | **Dead immediately** — `[RULESET §2, §4]` and `[CFG ballPhysics.groundIsDead = true]`: no bounce, no loose ball. **This is the "bounces" item in the owner's list, and the correct answer is that there are no live bounces in football.** Record that the ball does not roll live. (The bench has real loose-ball physics — `bounce 0.35`, `groundFriction 5.0`, `settleSpeed 0.15` `[AUDIT §2.1]` — which is **test-bench only** and must not reach the product.) | Screenshot of the dead ball + `events`. | AUTOMATABLE (needs H3) + MANUAL screenshot |

---

## 8. The midfield first down

> **This corrects the audit.** `[AUDIT §4]` states "no first downs (engine-wide)". That is **true of
> `FootballService` (1v1)** but **false of the product**: `TeamFootballService` sets `toGain = field.mid`
> (`:591`), and on crossing it sets `down = 1; toGain = goalZ()` and announces `"FIRST DOWN!"` (`:1415-1418`).
> **The product already implements exactly the one-first-down-at-midfield rule of `[RULESET §2]`.** Worth testing
> properly rather than rebuilding.

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **FD-1 (earn it)** | New possession at own 20; LOS just short of `field.mid`. | Gain enough to cross the middle line. | `down` resets to **1**; `toGain` becomes the **goal line**; HUD reads `"FIRST DOWN!"`; `nextStep = "down"` `[:1415]`. Matches `[RULESET §2]` "four plays to cross midfield, then four plays to score". | `state.down / toGain`; HUD screenshot. | AUTOMATABLE (needs H1) |
| **FD-2 (only one per possession)** | After FD-1, cross midfield again on a later play in the **same** possession. | Gain yards past midfield again. | **No second first down** — `toGain` is now the goal line, so the test is that `down` keeps incrementing. `[RULESET §2]` and `[CFG series.firstDownOnlyAtMiddle = true]`. | `state.down` across four plays. | AUTOMATABLE (needs H1) |
| **FD-3 (incomplete does not count)** | LOS already beyond `toGain`. | Throw an incompletion. | **No first down** — `kind ~= "INCOMPLETE"` is an explicit condition at `:1415`. | `state.down`; `events`. | AUTOMATABLE (needs H1+H3) |
| **FD-4 (no chains)** | Any down. | Look at the field. | **One middle line and a down counter — no chains, no line-to-gain markers, no hash marks** `[RULESET §2]`, `[CFG field.hashMarks = false]`. A down box is acceptable. | Retained screenshot of the field from the sideline camera. | **MANUAL** |
| **FD-5 (down text)** | Each of downs 1–4, and a goal-to-go situation. | Read the HUD. | `"1st/2nd/3rd/4th"` + yards to `toGain` via `Rules.yardsBetween`, with a goal-to-go variant when `|toGain − goalZ| < 0.01` (`G:downText:597`). Yards floor at 1. | Screenshot of each of the five HUD states. | **MANUAL** |

---

## 9. Scoring, including both try types

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **SCR-1 (TD value)** | Carrier crosses the goal line. | Score. | **Product awards 7** `[CFG TC.td = 7]` (`:2716`-region). **The ruleset says 6** `[RULESET §2]`, and `AWFootball.Config` was updated today to `rules.td = 6` and `scoring.touchdown = 6` — but `TeamFootballService` uses its **own local `TC.td = 7`**, a second source of truth `[AUDIT §5.4]`. **Assert 7 as today's behaviour and log the contradiction as a blocker.** | `state.score`; scoreboard screenshot. | AUTOMATABLE (needs H1) |
| **SCR-2 (1-point try)** | After a TD. | Declare a 1-point try. | **NOT IMPLEMENTED.** `[RULESET §2]`: 1 point, snap from the **5 (`4.57 m`)**, **pass-only**, declared **before the snap** `[CFG scoring.try1, try1SpotM, try1PassOnly]`. `TeamFootballService` reads no `CFG.scoring` at all and goes straight to the next possession. | — | **BLOCKED (no code)** |
| **SCR-3 (2-point try)** | After a TD. | Declare a 2-point try. | **NOT IMPLEMENTED.** `[RULESET §2]`: 2 points from the **10 (`9.14 m`)**, **run or pass** `[CFG scoring.try2, try2SpotM, try2PassOnly = false]`. | — | **BLOCKED (no code)** |
| **SCR-4 (defensive TD on a try)** | Try intercepted and returned. | — | **NOT IMPLEMENTED.** `[RULESET §2]` / `[CFG scoring.defensiveTryTouchdown = 2]`. | — | **BLOCKED (no code)** |
| **SCR-5 (safety on a try)** | — | — | **NOT IMPLEMENTED.** `[CFG scoring.safetyOnTry = 1]`. | — | **BLOCKED (no code)** |
| **SCR-6 (safety in play)** | Carrier down in his own end zone. | Tackle. | **+2 to the opponent** `[CFG TC.safety = 2]` = `[CFG scoring.safety]` = `[RULESET §2]`. Note `[AUDIT §2.9]`: there is **no safety in 1v1**, only in the product. | `state.score`; screenshot. | AUTOMATABLE (needs H1+H2) |
| **SCR-7 (no kicking)** | Any state. | Attempt a kick, punt or field goal. | **No kicking input exists anywhere** — correct `[RULESET §2, §4]`, `[CFG series.kickoffs/punts/fieldGoals = false]`. The `"KICKOFF"` string at `:542` is a **label on the opening possession only**, not a kick. Confirm no kick action is reachable from any input. | Input list screenshot; grep of the intent actions (`leave, ready, pick, team, play, route, primary, flip, call, throw, throwAim, catch, catchAggressive, swat, jukeL, jukeR, spin, stiffarm, tackle`). | **MANUAL** |
| **SCR-8 (scoreboard)** | Any score. | Read the board. | `"HOME n – m AWAY"`, `· FINAL` appended in `state = "final"` (`:615`). | Screenshot. | **MANUAL** |

---

## 10. Restarts

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **RST-1 (every possession)** | Any change of possession, touchback, safety or TD. | Observe the next snap spot. | **Product: own `startYard 20` yd** `[CFG TC.startYard]` (`:590`). **Ruleset: own 5 = `4.57 m`** `[RULESET §2]`, `[CFG series.snapOwnM]`. Record 20; log the discrepancy. | `state.los` vs `ownGoalZ`. | AUTOMATABLE (needs H1) |
| **RST-2 (who snaps first)** | Match start. | Observe. | Product: **HOME always** (`:542` `"HOME ball first"`). **Ruleset: a coin toss at midfield** decides who snaps first and which side each team defends `[RULESET §2]`. No toss exists. Log it. | HUD screenshot + `state.offense`. | AUTOMATABLE (needs H1) |
| **RST-3 (second half)** | — | — | **NOT TESTABLE — there is no second half.** The product's match structure is **4 possessions each (8 total), no clock, no halves** `[CFG TC.modes.*.possessionsEach = 4]` (`:522`). `[RULESET §2]` requires the team that did not start the first half to snap first in the second, from its own 5. | — | **BLOCKED (no code)** |
| **RST-4 (dead ball → next snap)** | Any play ends. | Wait. | `state = "downOver"`, `phase = "dead"`, timer `downOverTime 2.4 s` `[CFG TC.downOverTime]` (`:1385`), then `advance()` → `setupDown` → `preSnap`. Bodies re-placed in formation. | `state` polled; screenshot of the reset formation. | **AUTOMATABLE today** |
| **RST-5 (rejoin)** | A human leaves mid-match and rejoins. | Leave (or walk `leaveDistance 45 m` from the field centre `[CFG TC.leaveDistance]`), then rejoin via the JOIN pad. | Leaver's slot is taken by AI **on the spot**; the rejoiner **queues** and takes an AI slot **at the next dead ball** (header comment, `:1-4`); `pending` count in `state` reflects the queue. | `state.pending / humans`; screenshot of the roster. | AUTOMATABLE (needs H1) + MANUAL |

---

## 11. Penalties — all five

> `[RULESET §2]` specifies exactly five fouls, enforced **from the line of scrimmage** unless marked a spot foul, with
> **yardage halved if it exceeds half the distance to the goal**, and **no 15-yard penalties**. All five are present as
> config `[CFG penalty.fouls]` — including the deliberate split of the single −5 foul into `offside` + `falseStart` so
> the HUD can name which side moved. **`TeamFootballService` reads no `CFG.penalty` at all.** Only one of the five is
> implemented, through `CFG.stance.falseStartYards`.

| ID | Foul | Setup / Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **PEN-1** | **False start** | Offensive player moves after SET, past `setGrace 0.45 s` (`:1591`). | **−5 yd from the LOS, replay the down** `[CFG stance.falseStartYards = 5]` = `[CFG penalty.fouls.falseStart]` = `[RULESET §2]`. `G:falseStart` also clamps the LOS inside the goal lines (`:771`). | `state.los` before/after; `state.down` unchanged; toast screenshot. | AUTOMATABLE (needs H1+H2) — **the only implemented penalty** |
| **PEN-2** | **Offside** | Defender across the LOS at the snap. | **−5 yd** `[CFG penalty.fouls.offside]`. **NOT IMPLEMENTED** — there is no offside wall or check. | — | **BLOCKED (no code)** |
| **PEN-3** | **Defensive PI** | Defender contacts a receiver through the ball's arrival. | **+10 yd, automatic first down** `[CFG penalty.fouls.defensivePI]` `[RULESET §2]`. **NOT IMPLEMENTED.** | — | **BLOCKED (no code)** |
| **PEN-4** | **Offensive PI / push-off** | Receiver pushes off. | **−10 yd, loss of down** `[CFG penalty.fouls.offensivePI]`. **NOT IMPLEMENTED.** | — | **BLOCKED (no code)** |
| **PEN-5** | **Defensive holding** | Defender holds at the line. | **Automatic first down, 0 yards** `[CFG penalty.fouls.defensiveHolding]`. **NOT IMPLEMENTED.** | — | **BLOCKED (no code)** |
| **PEN-6** | **Unnecessary roughness** | A hit outside the legal envelope (`[RULESET §1]`: no blocking below the waist, no clipping). | **+10 yd, automatic first down** `[CFG penalty.fouls.unnecessaryRoughness]`. **NOT IMPLEMENTED** — and nothing detects an illegal hit. | — | **BLOCKED (no code)** |
| **PEN-7** | **Half the distance** | Any penalty with the LOS inside twice the penalty distance from the goal. | Yardage **halved** `[CFG penalty.halfTheDistance = true]` `[RULESET §2]`. Testable today only for the false start: set the LOS to the own 3 yd and commit one. Assert the LOS does not cross the goal line. | `state.los`. | AUTOMATABLE (needs H1+H2) |
| **PEN-8** | **No 15-yard penalties** | Review every penalty the game can award. | Max magnitude is **10 yd** `[RULESET §2]`. Today the only penalty is 5. | Config read + HUD screenshots. | **MANUAL** |

---

## 12. Overtime

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **OT-1 (entry)** | Tie after all 8 possessions (H1 `set` the score and `possession`). | Let the last possession end. | `otRound += 1`; `totalPossessions += otPossessionsEach 1 × 2`; HUD `"OVERTIME n · one possession each"`; up to `maxOtRounds 2` rounds `[CFG TC]` (`:1431-1434`). **`[RULESET §2]` specifies a *two-series* period from the middle line** `[CFG overtime.seriesPerPeriod = 2, fromMiddleLine = true]` — the product gives **one** possession each **from the own 20**. Record the product's behaviour; the divergence is a finding. | `state.possession / otRound / los`; HUD screenshot. | AUTOMATABLE (needs H1/H6) |
| **OT-2 (spot)** | In OT. | Observe the snap spot. | Product: own `startYard 20`. **Ruleset: the middle line, with no first down available at midfield** `[CFG overtime.firstDownAvailable = false]`. Since the product's `toGain` is always `field.mid`, **an OT possession can earn a first down** — directly contrary to `[RULESET §2]`. Assert and log. | `state.los / toGain`. | AUTOMATABLE (needs H1) |
| **OT-3 (defensive score ends the period)** | Defence scores in the first OT series. | Score on defence. | `[CFG overtime.defensiveScoreEndsPeriod = true]` `[RULESET §2]`. **NOT IMPLEMENTED.** | — | **BLOCKED (no code)** |
| **OT-4 (collapse to one play)** | Reach OT period 2. | — | `[RULESET §2]` / `[CFG overtime.collapseAfterPeriod = 1, collapseSpotM = 4.57]`: period 2+ is **a single try play from the 5**. **NOT IMPLEMENTED** — round 2 is another full possession. | — | **BLOCKED (no code)** |
| **OT-5 (still tied after OT)** | Tie after `maxOtRounds 2`. | Finish. | `state = "final"` with `finalTime 7 s` on the board `[CFG TC.maxOtRounds, TC.finalTime]` (`:1447`), then back to the lobby. **Confirm a tie is allowed to stand** and reads clearly. | Scoreboard screenshot. | AUTOMATABLE (needs H1) + MANUAL |
| **OT-6 (no timeouts)** | In OT. | Try to call a timeout. | `[CFG overtime.timeouts = 0]` `[RULESET §2]`. Vacuously true — **no timeout exists anywhere in the product** (see CLK-3). | Input list. | **MANUAL** |

---

## 13. The clock

> **There is no game clock.** `TeamFootballService` has a per-play `playClock` (used only for AI QB read timing:
> `dropbackTime 0.8`, `minReadTime 1.1`, `deadline 3.4` `[CFG qb]`), a `downOverTime 2.4 s` dead-ball timer and a
> `finalTime 7 s` board timer. Match length is **possession-counted, not timed**. The full IFAF clock is config-only:
> `halfSeconds 300` (**`[ASSUMPTION]` — the owner's `[RULESET §7 Q1]` decision**), `halves 2`,
> `intermissionSeconds 120` `[VERIFIED]`, `stopClockWindowSeconds 60` `[ASSUMPTION]`, `playClockSeconds 22`
> `[ASSUMPTION]`, `timeoutsPerHalf 2` / `timeoutSeconds 90` `[VERIFIED]`, and `stopOn{firstDown, penalty,
> outOfBounds, incomplete, score, timeout}` `[CFG clock]` — **none of it read by any service.**

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **CLK-1 (match length)** | Play a full match. | Time it wall-clock. | **`[OWNER — BLANK]`** — `[RULESET §7 Q1]` is open. `halfSeconds = 300` is explicitly flagged "do not treat this value as researched" `[CFG clock.halfSeconds]`. Record the measured length of an 8-possession match as the input to that decision. | Stopwatch + `state.possession` trace. | **AUTOMATABLE today** (poll `state`) — produces data, not a verdict |
| **CLK-2 (final-minute stop rules)** | Inside the last `stopClockWindowSeconds 60` of a half. | Earn a first down, draw a penalty, go out of bounds, throw an incompletion, score. | Clock stops on **all six** triggers `[CFG clock.stopOn]` `[RULESET §2]`. **NOT TESTABLE — no clock, no halves.** | — | **BLOCKED (no code)** |
| **CLK-3 (timeouts)** | Any half. | Call a timeout. | 2 per half, non-carrying, up to 90 s `[CFG clock.timeoutsPerHalf, timeoutSeconds]` `[RULESET §2]`. **NOT IMPLEMENTED.** | — | **BLOCKED (no code)** |
| **CLK-4 (play clock)** | Pre-snap. | Wait. | Product: auto-snap at **15 s** for a human `[CFG TC.humanSnapAuto]`, **4 s** once SET `[CFG TC.humanSetToSnap]`, `cpuSnapDelay 1.8 s` for AI `[CFG flow.cpuSnapDelay]`. Ruleset recommends a **22 s** play clock `[CFG clock.playClockSeconds]` `[ASSUMPTION]`. Record both; the gap is a tuning decision, not a defect. | `state.phase` timestamps; HUD screenshot. | AUTOMATABLE today |

---

## 14. Complete matches (the owner's "test complete matches as well")

| ID | Setup | Action | Expected | Observe | Mode |
|---|---|---|---|---|---|
| **MATCH-1 (AI vs AI, 5v5)** | All 10 slots AI. Start the match; leave it alone. | Watch to `state = "final"`. | Runs 8 possessions to a final score with **no error in the output** and no `pcall` recovery (`:1730` warns and calls `g:reset()` on any error — **a single warn line is a FAIL**). Record: possessions played, score, every outcome in `events`. | Console (zero warnings) + H3 `events` + a final-scoreboard screenshot. | **AUTOMATABLE today** (`state` polling) |
| **MATCH-2 (AI vs AI, 2v2)** | All 4 slots AI on the 2v2 field. | Same. | Same, with `possessionsEach 4`, `rushCount 3.0` `[CFG TC.modes["2v2"]]`. | As MATCH-1. | AUTOMATABLE today |
| **MATCH-3 (one human, full match)** | One human in slot 1 (QB), rest AI. | Play start → finish, using every input at least once. | Walk the checklist in `football-match-checklist.md`. Every line pass/fail. | Checklist + the screenshots it names. | **MANUAL** |
| **MATCH-4 (soak)** | AI-only. | 10 consecutive matches without leaving the session. | No warnings, no leaked bodies (`athletes` count stays at `size × 2`), no leaked ball parts, `events` stays capped at 400 (`G:log:453`), memory flat. | Console; `athletes` count each match; one screenshot of the final console. | AUTOMATABLE today |
| **MATCH-5 (two humans, opposite teams)** | Two clients, one per team. | Play a full match. | Both HUDs agree on `down`, `los`, `toGain`, `score`, `possession` at every dead ball. Server state is authority (`state`). | Side-by-side HUD screenshots at three dead balls + `state`. | **MANUAL** |

---

## 15. Real-world reference comparisons

Explicitly required by the standard. Each is a **recorded comparison, not a pass/fail gate.**

| ID | Situation | Real-world reference | How to compare | Mode |
|---|---|---|---|---|
| **REF-1** | A deep throw at maximum range. | Drag-free **66.4 m in 2.80 s** at **27.4 m/s / 30°**; a real ball must land measurably shorter `[CFG ballPhysics.dragFreeRangeM, dragFreeTimeS]` `[RULESET §4]`. | Measure the product's longest throw (range + time) via H3 `events`. The product's `maxFlight 1.6 s` cap means it cannot reach 2.80 s — **state that in the result.** | AUTOMATABLE (H1+H3) |
| **REF-2** | A spiral vs a wobble. | Spiral **62.8 rad/s**; nose-on drag area **0.023 m²** → broadside **0.038 m²**, a **~60 % swing**, so a wobble **must travel measurably shorter** `[CFG ballPhysics.areaNoseOnM2, areaBroadsideM2, nutationRadS]`. | Throw a good and a bad pass at the same distance; compare range. The product has **no throw-quality→range channel at all** — record the absence as the finding. | **MANUAL** |
| **REF-3** | A DB in coverage. | Align **4.6–6.4 m** off, defend a **1.8–2.7 m** cushion, press at **1.4 m**; control pedal at **75 %** of top speed; three states `controlPedal → speedPedal → manTurn` with transitions at `2.7 m` threatened / `1.8 m` broken `[CFG coverage.*]` `[RULESET §5]`. | Measure the product's actual alignment and cushion via H1 `snap()`. Product values are `cushion 5` and `rushDepth 6` `[CFG TC]` and **`CFG.coverage` is not read**, so compare and record. | AUTOMATABLE (H1) |
| **REF-4** | Player top speed. | A WR at **9.6 m/s** `[CFG move.wrSpeed]` ≈ 34.6 km/h — elite human sprint speed, so the ceiling is plausible. | Confirm MOV-1's measurement and note the comparison. | AUTOMATABLE (H1) |
| **REF-5** | Field dimensions. | **45.72 × 22.86 m** with **9.14 m** end zones, no hash marks `[CFG field.*]` `[RULESET §2]`. | Measure the built field in Studio (`EndZoneNorth` / `EndZoneSouth` sizes, read-only) against those numbers. | **AUTOMATABLE today** (read-only instance measurement) |

---

## 16. What is testable today vs what needs code

### 16.1 Testable today, with no new hook (28 automatable + 11 manual-only)
TKL-0 through TKL-13 — **the whole counter matrix, 19 rows, as pure-Luau unit tests via `loadstring`, needing no play
session and no hook at all** — plus SNAP-1, SNAP-2, RST-4, CLK-1, CLK-4, MATCH-1, MATCH-2, MATCH-4 and REF-5 off the
existing `TestHookTeam.state` / `athletes`. The manual-only observations (FD-4, FD-5, SCR-7, SCR-8, PEN-8, OT-6,
SNAP-5, MATCH-3, MATCH-5, THR-6, REF-2) also need nothing new — only eyes and a screenshot.

### 16.2 Testable once H1 (+H2/H3/H5) exists
All of §1 movement, §3 throws, §4 catching, §6 jump balls, §7 possession (except POS-3), §8 first downs, SCR-1/6,
RST-1/2/5, PEN-1/7, OT-1/2/5, TKL-14/15/16, REF-1/3/4.

### 16.3 Blocked — the mechanic does not exist (16 tests)
POS-3 (fumble), SCR-2/3/4/5 (tries), RST-3 (second half), PEN-2/3/4/5/6 (four of the five penalties + roughness),
OT-3/4, CLK-2/3, and SNAP-5's formation rules.

### 16.4 Config declared but not read by any service — the largest single gap
`AWFootball.Config` was extended **today** with the full sourced ruleset, but `TeamFootballService` and
`FootballService` each read only `STUD, ai, ball, defend, flow, jump, move, pedal, qb, rules, seed, stance, tackle`.
**Unread blocks:** `YARD`, `field`, `series`, `scoring`, `penalty`, `overtime`, `clock`, `ballPhysics`, `coverage`,
and `catch.det`. Every number in them is sourced and ready; nothing consumes them. Additionally
`CFG.catch.model = "roll"` names `Rules.judgeCatchDeterministic`, **which does not exist** — a dead pointer in
config that reads as authoritative (the same failure mode as `[AUDIT §5.1]`).

### 16.5 Test count

Counted off the table rows in §§1–15 (one row = one test):

| | Count |
|---|---|
| **AUTOMATABLE** (scriptable from a hook, existing or requested) | **76** |
| &nbsp;&nbsp;…of which also need eyes on a screenshot (AUTOMATABLE + MANUAL) | 12 |
| &nbsp;&nbsp;…of which run **today**, with no new hook | **28** |
| **MANUAL only** (needs eyes, nothing to assert) | **11** |
| **BLOCKED** (no code exists to test) | **15** |
| **Total** | **102** |

Per group: MOV 6 · SNAP 5 · THR 6 · CAT 6 · **TKL 22** · JMP 5 · POS 6 · FD 5 · SCR 8 · RST 5 · PEN 8 · OT 6 ·
CLK 4 · MATCH 5 · REF 5.

Of the 76 automatable, **28 run today with no new hook** — chiefly the 22-row tackle matrix (TKL-0…TKL-13, pure-Luau
`loadstring` unit tests) plus SNAP-1/2, RST-4, CLK-1/4, MATCH-1/2/4 and REF-5 off the existing
`TestHookTeam.state`/`athletes`. The remaining **48 need H1**, which is a paste of `Hoops3Service`'s `TestHook3`.

---

## 17. Defects found while writing this plan (not fixed, reported)

1. **`TC.td = 7` contradicts `CFG.rules.td = 6` and `CFG.scoring.touchdown = 6`** — two sources of truth for the score
   of a touchdown, and the product uses the one the ruleset says is wrong `[AUDIT §5.4]`.
2. **`CFG.catch.model` points at `Rules.judgeCatchDeterministic`, which does not exist.** The deterministic catch model
   is configured, documented and absent.
3. **`TackleService` is `Disabled = true` and `ServerStorage.AWPracticeBall` is not installed**, so the only fumble and
   contest code in the project cannot blow a whistle or change possession.
4. **No test hook in `TeamFootballClient`** (533 lines) — the product's client input path is untestable.
5. **`[AUDIT §4]`'s "no first downs engine-wide" is wrong for the product.** `TeamFootballService:1415` implements the
   midfield first down. The audit should be corrected so nobody rebuilds it.
6. **Collision group `AWFootball` is set non-collidable with itself** (`:46-48`) — bodies pass through each other.
   Intentional or not, it makes "collisions" in the owner's standard a blocking/slowdown system only (TKL-16).
