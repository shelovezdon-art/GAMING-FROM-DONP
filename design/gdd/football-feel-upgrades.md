# Football Feel Upgrades — RAC, DB Risk/Reward, Animation Wiring

> **Status: DESIGN DRAFT 1 — 2026-11-02. Nothing in this document is built.**
> Owner brief: "How can they improve the gameplay? How can they improve the catch
> after play? How can the DB get penalized for not jumping the right way? Make sure
> those animations are able to catch the ball and put the hands up. Everything that
> football has, we need to imitate everything."
> Engine: Roblox (Luau). **Units: METRES, SECONDS, DEGREES** (1 stud = 0.35 m).
> Baseline: the measured 2026-11-02 state of `TeamFootballService` /
> `AWFootball.Config` / `AWFootball.Rules` (mirrors in `src/football/team/`),
> which supersedes stale lines in `football-core.md`. Pillars, by name:
> **P1 "I know exactly why I lost"**, **P2 "both sides have a fantasy"**,
> **P3 "deep balls rewarded"**.

---

## 1. Overview

This document specifies the next feel pass on the 5v5/2v2 snap-to-whistle loop:
(a) ten ranked gameplay improvements, (b) a real **run-after-catch (RAC)** game
grown out of the existing `catch.runAfterCatch = 0.45 s` immunity beat,
(c) a **DB risk/reward system** where a mistimed jump, a bitten double move, or a
wrong-way swat press each carry an explicit, readable cost with a reason string —
mirrored by receiver-side costs so neither fantasy is cheapened, and (d) the
**wiring map** that connects the 8 authored-but-unwired KeyframeSequences
(`aw_sprint`, `aw_catch_high`, `aw_catch_over_shoulder`, `aw_catch_scoop`,
`aw_juke_left/right`, `aw_spin`, `aw_tackle_wrap`) to gameplay moments the server
already computes, plus the pre-catch **hands-up** moment the owner called out and
the list of clips football still needs. Every new rule is deterministic from
geometry and input, keeps the server authoritative, applies identically to humans
and AI, and lands in `AWFootball.Config` as data, never hardcoded.

## 2. Player Fantasy

**Receiver:** "I caught it *moving* and made the first man miss." The catch is not
the end of the play; a catch in stride flows into a juke, a broken angle, a house
call. MDA: **Sensation** and **Challenge**; SDT **Competence** (the stride catch is
earned by route timing, not granted).

**DB:** "I read it, I timed it, I made the play — and when I guessed wrong, I know
exactly what I bit on." The DB's jump is a real wager: time it and you sky for the
swat or the pick; mistime it and you land stunned watching the catch. P2 demands
the DB's half be as expressive as the receiver's; P1 demands every lost rep name
its cause ("BIT ON THE SLANT · SLUGGO", "JUMPED EARLY · HE WASN'T THERE YET").

**QB:** the double move and the pump fake make the DB's discipline *the* thing the
QB attacks — chess, not darts. P3: the deep shot stays the high-variance payoff.

## 3. Detailed Design

### 3.1 Ranked top-10 gameplay improvements (snap to whistle)

Effort classes: `config-tune` (values only) · `code-small` (≤ ~1 session in one
service) · `code-large` (new subsystem) · `needs-assets` (clips/art first).

| # | Improvement | What | Why (pillar) | Effort |
|---|---|---|---|---|
| 1 | **Wire the deterministic catch model's inputs and flip it on** | `resolveArrival` currently passes only distances; compute and pass `arrivalYM` (ball y at arrival — the flight solver knows it), `facingDeg` (ball velocity vs receiver facing), `relSpeed`, `overShoulder`, `contested`, then flip `Config.catch.model = "deterministic"` after one parity playtest | P1. The roll model answers "why did I drop it?" with "dice." The deterministic model answers with a named term — and **the same geometry then drives animation selection (3.4) for free**. One computation, two payoffs | code-small |
| 2 | **DB risk/reward costs** (3.3) | Mistimed jump = landing stun; bitten double move = beaten stumble + reason; wrong swat press = recovery lockout | P1 + P2. Today a wrong jump costs nothing, so jumping is free spam and the receiver's win isn't earned | code-small |
| 3 | **Catch-in-stride RAC** (3.2) | Catch grade + receiver speed at arrival decide whether the 0.45 s beat becomes a 0.72 s rolling start or a 0.30 s settle | P2 + P3. Turns the owner's immunity beat into a skill, links throw timing (QB) to YAC (WR) | code-small |
| 4 | **Hands-up window + geometry-picked catch clips** (3.4) | Hands raise when the catch window opens; `aw_catch_high` / `over_shoulder` / `scoop` picked from arrival geometry | Owner's direct ask. Also a fair tell for the DB (hands up = ball is close), serving P2 | code-small + needs-assets (1 new reach clip) |
| 5 | **The double move (`sluggo`) + DB bite detection** | Add the playbook doc's sluggo route to the live route pool; detect a DB whose hips flipped toward the first break as the receiver releases vertical → beaten flag + stumble | P2 + P3. The double move is what makes DB discipline a *choice*; it is the attack that makes #2's costs matter | code-small |
| 6 | **QB pump fake** | Tap-throw cancel inside 0.25 s: plays the windup, no release; any DB who pressed swat or jumped during the fake eats the full #2 cost; QB pays `pumpTime 0.4 s` of pocket clock | P2. Gives the QB a direct counter to ball-hawking DBs; the rusher's 3.2 s clock prices it (P3's risk ledger) | code-small |
| 7 | **Swat press lockout + active swat moment** | A swat press outside the timing window locks the DB's contest out for `swatLockout 0.5 s` and shows the whiffed swing | P1. Today a human DB's press is one-shot but costless-if-early; the lockout makes the press a timed commitment like the receiver's | config-tune + code-small |
| 8 | **Breakaway / last-man-beaten rule** (3.2.5) | When the carrier is past every defender with ≥ `breakawayGap`, declare it: banner, FOV kick, no rubber-banding — the AI may not exceed its stated speeds to catch up | P2 (carrier fantasy) + P1 (the chase is honest). The house call must *feel* decided at the moment the angle broke | code-small |
| 9 | **Blocking readability pass** | Keep `engagedUntil`; add a sprint-block (blocker sprinting at contact ⇒ `blockDrag` 0.55 → 0.8 s), per-block feedback both ways, and a pancake reason string | P2 for the 3 players not in the throw; makes the RAC game a team game | config-tune |
| 10 | **Moment presentation: first-down signal + TD celebration beat** | 1.2 s dead-ball beat: first-down signal clip at the spot; TD celebration set + camera push | Macro-loop reward (animation reference §2.2 item 8); cheapest perceived-quality win on the list | needs-assets |

Ordering logic: #1 is the keystone — it is the only item that other items (#2's
reason strings, #4's clip selection) consume. #2/#3 are the two halves of the
owner's ask and are deliberately adjacent so neither side's buff ships without the
other's counter (P2). #5/#6 are the attacks that make #2 meaningful. #7–#10 are
polish on the same loop.

### 3.2 Run-after-catch (RAC) system

Grow `catch.runAfterCatch = 0.45 s` from a flat grace into a graded start. All
values live in a new `Config.rac` table (Tuning Knobs, §7).

**3.2.1 Catch-in-stride vs stationary catch.** At the moment `resolveArrival`
returns CATCH, the server already knows the receiver's velocity and the catch
grade (`Rules.catchGrade`). Classify:

| Class | Condition (all must hold) | Immunity | Speed after catch |
|---|---|---|---|
| **STRIDE** | receiver speed ≥ `strideSpeedMin` (7.2 m/s) · grade PERFECT or GOOD · velocity within `strideConeDeg` (100°) of upfield | `runAfterCatch × strideImmunityMul` = 0.45 × 1.6 = **0.72 s** | `carrySpeed` 9.0 immediately; an unexpired snap burst (`burstUntil`) carries over |
| **SET** | any catch that is not STRIDE and not AERIAL | **0.45 s** (current value, unchanged) | `settleTime` 0.30 s at ×`settleMult` 0.6, then `carrySpeed` |
| **AERIAL** | `highBall` catch (jump ball won) | **0.45 s** | landing recovery `landRecover` 0.40 s at ×0.5, then `carrySpeed` — the high point trades YAC for winning the contested ball |

Reason strings: `"CAUGHT IN STRIDE — RUN!"` / `"SECURED IT — GET UPFIELD"` /
`"CAME DOWN WITH IT — FIND YOUR FEET"`. The QB's throw placement now has a yield:
hitting the break in rhythm literally buys his receiver 2.5 extra metres (§4.2).

**3.2.2 Moves and counters.** The built moves stay as tuned (juke 12.5 m/s ×
0.22 s, cd 1.1, immunity 0.28; spin 6.5 × 0.42, cd 1.6, immune for the spin;
stiff-arm reach 1.6 m, stun 0.7 s, cd 1.4). What is added is the **counter
matrix**, so every move has an answer (Sirlin: no dominant option):

| Defender choice | Beats | Loses to | Why |
|---|---|---|---|
| **Dive** (the existing tackle lunge, 12.5 m/s × 0.3 s) | stiff-arm (dive goes under the arm: a diving tackler ignores `stiffArmStun`), SET catches still settling | juke (lateral 12.5 m/s during a committed straight lunge), whiff costs `whiffRecovery` 0.65 s | commitment beats reach, agility beats commitment |
| **Squeeze** (new: no lunge — close to `reach` 1.35 m and hold `tackle` for a standing wrap) | juke (no commitment to beat; the wrap window outlasts `jukeImmunity` 0.28 s) | spin (carrier is immune the whole 0.42 s and exits behind), stiff-arm (squeezer is in the front arc at 1.6 m) | patience beats agility, power beats patience |
| **Gang** (existing: second defender within `lungeReach`+0.3 of a wrapped carrier finishes it) | break attempts | nothing — but needs two defenders out of position elsewhere | numbers always win locally, lose globally |

Implementation note: "squeeze" is the existing `WRAP` outcome made *selectable*
(hold vs tap on the tackle input) instead of being only the punishment for a weak
dive. Deterministic as today — `resolveTackle` already distinguishes the two by
closing speed and angle; the hold input simply enters the attempt without the
lunge.

**3.2.3 Teammate blocking.** Already built (`engagedUntil`, ×0.4 speed for
0.55 s, `blockReach` 1.2, cd 1.3). Additions: sprint-block (blocker sprint active
at contact ⇒ drag 0.8 s and reason `"PANCAKE!"` / `"FLATTENED"`), and blocks are
illegal more than `blockBehindM` 2 m behind the carrier's z (prevents a degenerate
escort wall camping the catch point — see §5.6).

**3.2.4 Pursuit angles.** AI pursuit currently leads the carrier by a flat
0.35 s. Replace with a proper intercept lead (§4.3) capped at `pursuitLeadMax`
1.0 s, and surface it to humans: the defender HUD's existing carrier marker gains
a faint **intercept point** dot so a human DB learns to run where the carrier is
*going*. Same information both sides: the carrier sees pursuers' angle normally.

**3.2.5 Breakaway (last man beaten).** Every tick of `phase == "run"`, if for
**every** defender `(carrierZ − defenderZ) · dir > breakawayAheadM` (1.0 m) and
the nearest defender is ≥ `breakawayGap` (4.0 m) behind: fire once —
banner `"LAST MAN BEATEN — HOUSE CALL?"`, client camera FOV kick, crowd audio
sting. Mechanically nothing speeds up or slows down (P1: the chase is honest; AI
keeps its stated speeds and its own stamina rules). A caught-from-behind breakaway
is therefore a genuine stamina/angle story, never rubber-banding.

### 3.3 DB risk/reward — "penalized for not jumping the right way"

Principle: **every guess is a wager; every lost wager has a price and a name.**
All costs are server-applied, identical for human and AI defenders, and every one
emits a reason string to *both* players (P1, P2). New `Config.dbRisk` table.

**3.3.1 Mistimed jump (jump balls).** `Rules.resolveJumpBall` currently treats a
mistimed jump as merely "not in." Add: a defender (or receiver) who jumped but
whose timing error exceeds `jumpWindow` (|−timing − apex| > 0.20 s, apex =
0.282 s) **lands stunned** for `landStun` 0.40 s (movement mult 0, via the
existing `stunUntil`). Strings: DB early — `"JUMPED EARLY · HE WASN'T THERE YET"`;
DB late — `"LATE OFF THE GROUND · HE SKIED FIRST"`; and the winner hears
`"YOU OUT-TIMED HIM AT THE PEAK"`. A receiver who mistimes eats the *same* 0.40 s
stun — on an incompletion that is pride; on a tipped ball it is real, because the
DB who stayed down can play the carom.

**3.3.2 Biting on the double move (the sluggo).** Detection, all from data the
server already tracks per tick: the DB is `beaten by bite` when (a) his man's
route has a registered fake-break point (sluggo's 3rd point), (b) the DB's
velocity at the fake-break tick pointed within `biteConeDeg` 50° of the fake break
direction **or** his pedal had already flipped (`st.pedal == false`) toward it,
and (c) within `biteWindow` 0.6 s the man's separation grows past
`pedal.beatenMargin` 0.6 m going vertical. Cost: the existing beaten-deep stumble
(`flipUntil = now + beatenStumble` 0.3 s) **plus** `biteSlow` ×0.8 speed for
1.0 s — being beaten on a double move is worse than being beaten on speed,
because it was a decision. Strings: DB `"BIT ON THE SLANT · SLUGGO!"`; receiver
`"YOU SOLD IT — HE BIT"`; QB `"HE BIT — THROW IT DEEP"` (fires at detection, not
at the catch, so the QB's read is rewarded in real time).

**3.3.3 Wrong-way / early swat press.** The swat press is one-shot per flight
(built) but a bad press costs nothing today. Add: a press whose timing lands
outside `[−windowEarly, windowLate]` = [−0.5, +0.22] s **or** thrown while the
ball's arrival point is beyond `swatReach` 1.7 m sets `swatLockout` 0.5 s during
which the DB cannot contest (his `dbPlay` is false even if the ball arrives in
reach) and his movement is ×`swatSlow` 0.85 (arms committed). Strings: DB
`"SWUNG EARLY · BALL WASN'T THERE"` / `"WRONG SIDE · IT WENT BY YOU"`; receiver on
the resulting catch: `"HE COMMITTED FIRST — EASY MONEY"`. This kills press spam
without touching the reward: a *timed* press is exactly as strong as today.

**3.3.4 The mirror (fairness ledger).** Receivers already pay for mistimed
presses (quality 0.35, EARLY/LATE strings) and now pay the aerial landing
(3.2.1) and the same jump stun (3.3.1). The pump fake (#6) is the QB-side risk:
0.4 s of pocket clock against a 3.2 s rusher. P2 check: every new defensive cost
in this section has an offensive cost in the same table below.

| Wager | Offense pays | Defense pays |
|---|---|---|
| Jump timing | 0.40 s land stun | 0.40 s land stun |
| Press timing | quality 0.35 + EARLY/LATE string (built) | 0.5 s lockout + ×0.85 slow |
| The break | route takes longer (sluggo breaks at ~1.0 s vs slant 0.8 s — rusher risk) | bite stumble 0.3 s + ×0.8 for 1.0 s |
| Pump fake | 0.4 s pocket clock vs the rush | full jump/press cost spent on nothing |

### 3.4 Animation wiring map

The 8 authored clips await owner publish for permanent ids; wiring is specced now
so publish day is wiring day. Selection is **deterministic from the same server
geometry as the catch result** (one truth, two renderings — P1). Playback is
client-side off replicated state; the server never animates.
Track budget: all selections below fit the small per-Animator pool the animation
reference flags (preload once, reuse).

**3.4.1 The pre-catch hands-up moment (the owner's callout).** When a live ball's
remaining flight ≤ `handsUpLead` (= `windowEarly` 0.5 s), these rigs enter a
hands-up reach pose: **the target receiver always**, and **any defender whose
distance to the aim point ≤ `swatReach` 1.7 m**. The reach *variant* is chosen by
the same geometry as the catch clip (high/over-shoulder/scoop below) so hands go
up *where the ball will be* — high point = arms above head, scoop = palms down,
pinkies together (the verified real-technique switch at the waist,
`football-ruleset.md` §4). On humans the pose layers on the upper body only
(Action priority), legs keep locomotion. **This needs one new asset**:
`aw_hands_up_reach` (or a 3-pose set), listed in 3.4.3. Until it exists, the
existing IK-style posing (`AWMotion.setPose`) can approximate it — ship the beat,
upgrade the pose.

**3.4.2 Wiring table — existing 8 clips.**

| Clip | Plays when | Server data that triggers it (already computed) |
|---|---|---|
| `aw_sprint` (loop) | sprint active: `sprintStep` returning `mult > 1` | `a.st.sprintOn` + stamina gate; blend weight from speed (AWMotion.locomote) |
| `aw_catch_high` | CATCH with arrival height ≥ `highCatchM` 1.7 m above feet, or any won `highBall` | `highBall` flag; deterministic model's `arrivalYM` (jump balls: `jump.highCatchHeight` 2.05) |
| `aw_catch_over_shoulder` | CATCH with `facingDeg` > 120° (ball from behind the shoulder line) | `facingDeg` — the #1 wiring item adds it to `resolveArrival` |
| `aw_catch_scoop` | CATCH with arrival height < `catch.det.waistM` 1.05 m | `arrivalYM` vs `waistM` (the thumbs-up/pinkies-down line) |
| `aw_juke_left` / `aw_juke_right` | juke intent accepted (cooldown passed) | the existing `lunge` client message, `dir` sign picks left/right |
| `aw_spin` | spin intent accepted | existing `lunge … spin = true` message |
| `aw_tackle_wrap` | `WRAP` result and `finishWrap` | `attemptTackle`'s result; also the "squeeze" entry (3.2.2) |

Default chest catch (none of the three conditions) currently has no clip — listed
below. Selection priority when conditions overlap: high > over-shoulder > scoop >
chest (a leaping over-shoulder ball is a high-point first).

**3.4.3 Clips football still needs ("imitate everything"), in order.**

| Clip | Moment | Priority |
|---|---|---|
| `aw_hands_up_reach` (3 variants: high / chest / scoop) | window-open pre-catch (3.4.1) | 1 — the owner's callout |
| `aw_catch_chest` | default CATCH | 1 |
| `aw_swat` | timed swat press (and the 3.3.3 whiff plays the same clip hitting air — the miss *looks* like the miss it was) | 1 |
| `aw_tackle_dive` | the existing dive lunge (`dive = true`) | 2 |
| `aw_qb_dropback` + `aw_throw_bullet` / `aw_throw_lob` | pocket + both throw flavors, release frame synced to the server release tick | 2 |
| `aw_stiff_arm` | stiff-arm landed | 2 |
| `aw_first_down_signal` | new-series dead ball (#10) | 3 |
| `aw_celebrate_set` (3+) | TD beat | 3 |
| `aw_beaten_stumble` | 3.3.1/3.3.2 costs — the penalty must *read* | 3 |
| `aw_pedal_loop` + `aw_hip_flip` | backpedal and the flip (today: static poses) | 3 |
| `aw_presnap_stances` in motion (WR stance sway, DB crouch sway, QB cadence) | pre-snap life | 4 |
| `aw_tag_pull` | only if the owner ever flips contact → flag/tag; not needed under the contact deviation | hold |

### 3.5 Gap list vs real football

Consistent with one-sport-at-a-time and the IFAF 5v5 base + labelled contact
deviation (ADR-0001). "Never" = never *for this ruleset*, with the rule cited.

| Real football has | Game status | Call | Why |
|---|---|---|---|
| Double moves / route trees beyond 8 | sluggo specced (playbook §3.3) | **adopt-now** | #5; the attack that prices DB discipline |
| Pump fake | none | **adopt-now** | #6; cheap, pure counterplay |
| Catch technique variety (high/scoop/over-shoulder) | computed but invisible | **adopt-now** | clips exist; wiring in 3.4 |
| First-down signal, celebrations | none | **adopt-now** | #10; presentation only |
| Pass interference / holding enforcement | config exists (`Config.penalty`), never called in live play | **later** | needs robust contact classification in coverage; wrong calls are worse than none (P1) |
| Zone coverage, safeties/deep help | man-only (`d.man`) | **later** | real design work; leverage/cushion config already anticipates it |
| Pre-snap motion | none | **later** | playbook doc defers it (false-start interactions) |
| Designed run plays / handoffs | QB scramble only; 2-pt try may run | **later** | pass-first is the identity today; runs need blocking depth first |
| QB throw styles readable by defense | one windup pose | **later** | needs the throw clip set (3.4.3) |
| Timeouts, 2-minute drill UI | clock rules built; no timeout UI | **later** | config is live (`timeoutsPerHalf 2`); pure UI |
| Fumbles (ground-live) | none | **later/owner** | ruleset open Q3: air-live only is the recommended deviation; ground bounce stays dead (chaos removes agency — P1) |
| Kicking (kickoffs, punts, FGs) | none | **never** | IFAF 5v5 has none; removes a whole subsystem by rule |
| Hash marks, chains/measurements | none | **never** | IFAF: one middle line; chains don't exist in this format |
| Linemen / 11-man blocking fronts | none | **never** | wrong ruleset; 5v5 is the native count |
| Unpredictable loose-ball bounce | none | **never** | `ballPhysics.groundIsDead`; realism hostile to input-decided outcomes |

## 4. Formulas

### 4.1 DB wager ledger (3.3)

    jumpErr   = | -timing - apex |,  apex = jumpSpeed/gravity = 6.2/22 = 0.282 s
    mistimed  = jumped and (jumpErr > jumpWindow 0.20 or not jumpReaches)
    cost      = stun(landStun 0.40 s)                       -- movement mult 0 via stunUntil

    swatBad   = pressed and (timing < -windowEarly 0.5 or timing > windowLate 0.22
                 or aimDist > swatReach 1.7)
    cost      = lockout(swatLockout 0.5 s) + speed × swatSlow 0.85 for its duration

    bite      = (dbVel · fakeBreakDir > cos(biteConeDeg 50°) at fake-break tick
                 or pedal already flipped toward it)
                and separation grows > beatenMargin 0.6 m within biteWindow 0.6 s
    cost      = flipUntil += beatenStumble 0.3 s, then speed × biteSlow 0.8 for 1.0 s

Variables: `timing` = press/jump time minus arrival time (s, negative = early),
ranges as configured. Worked example — a DB who jumps 0.45 s before arrival:
jump must start 0.282 s early to peak on time, so his error is |−0.45 + 0.282| =
0.168 s → inside `jumpWindow`, **no cost, he contests**. Jumping 0.60 s early:
error 0.318 s > 0.20 → stunned 0.40 s on landing; at `carrySpeed` 9.0 the
receiver banks ~3.6 m of separation. That is the "penalized for not jumping the
right way" number.

### 4.2 RAC yield (3.2.1)

    freeMetres(class) = immunity × carrySpeed
      STRIDE: 0.72 × 9.0 = 6.5 m   (plus burst carryover if burstUntil > now)
      SET:    0.45 × 9.0 × blend(settle) ≈ 0.45×9.0 − 0.30×9.0×0.4 ≈ 3.0 m
      AERIAL: ≈ 0.45×9.0 − 0.40×9.0×0.5 ≈ 2.2 m

So a rhythm throw to a crosser in stride is worth ~3.5 m more YAC runway than a
contested high point — which is the intended price curve: the deep contested ball
pays in field position (P3), the rhythm ball pays in RAC (P2). Inputs:
`carrySpeed` 9.0 m/s, `strideSpeedMin` 7.2 = 0.75 × `wrSpeed` 9.6. Outputs
bounded 2–7 m by the §7 knob ranges.

### 4.3 Pursuit intercept lead (3.2.4)

    tau   = clamp( d / max(closing, 1.0), 0, pursuitLeadMax 1.0 )     -- s
    aim   = carrierPos + carrierVel × tau

where `d` = distance to carrier (m), `closing` = pursuer speed toward him (m/s).
Replaces the flat `vel × 0.35` lead. At d = 9 m closing at 9.3 m/s: τ ≈ 0.97 s —
a real cutoff angle; at d = 2 m: τ ≈ 0.22 s — near-direct, so close pursuit
cannot orbit. Degenerate input `closing ≤ 0` (carrier faster, moving away):
τ = `pursuitLeadMax`, the pursuer runs the best available angle — which is what
makes 3.2.5's breakaway honest rather than scripted.

### 4.4 Stride classification (3.2.1)

    stride = speed ≥ strideSpeedMin 7.2
             and grade ∈ {PERFECT, GOOD}        -- Rules.catchGrade windows as built
             and angle(vel, dir·ẑ) ≤ strideConeDeg 100

`grade` uses the built windows (`windowEarly` 0.5, `windowLate` 0.22, PERFECT at
|timing + 0.1| < 0.12). No new timing system: the stride catch is the existing
catch timing *paying more*.

## 5. Edge Cases

1. **Both jump, both mistime.** Both land stunned; ball falls incomplete
   (`"nobody came down with it"`). No winner is invented.
2. **Tipped jump ball + stunned DB.** A tip keeps the ball live only in the
   Practice Field model; in team mode the arrival resolves once. If the owner
   adopts tips later, the stun (0.40 s) must be shorter than any tip rearc
   (≥ 0.6 s) so a stunned player can never be locked out of the whole carom chain.
3. **Sluggo vs a DB who never flipped.** No bite is detected (condition (b)
   fails); the vertical move is then a pure footrace — correct: discipline is the
   counter to the double move, and it must actually work (P2).
4. **Pump fake with no DB reaction.** QB paid 0.4 s for nothing. Self-balancing
   against the 3.2 s rusher; no further rule.
5. **Breakaway declared, then a block frees a trailing defender.** The banner
   fires once per play, never un-fires; whether he finishes is the chase. No
   re-evaluation flicker.
6. **Escort-wall degenerate.** Receivers hovering at the catch point to chain
   blocks: prevented by `blockBehindM` (a block only engages within 2 m behind the
   carrier's z going forward) and the built `blockCooldown` 1.3 s. If playtests
   still show catch-point camping, route-release enforcement is the next lever —
   flag to the owner before adding rules.
7. **Stun/lockout stacking.** All 3.3 costs clamp to `max(current, new)` on the
   same field (`stunUntil`, `flipUntil`) — they never add. Worst case a DB is
   immobile 0.40 s, degraded ≤ 1.0 s. A cost chain longer than one play is a
   tuning bug, caught by acceptance test F6.
8. **AI parity.** AI DBs roll the same wagers through the same code paths
   (`jumpPlanned` error already models mistiming; it now also pays the stun). AI
   receivers classify STRIDE/SET/AERIAL identically. Nothing branches on
   `kind == "human"` except feedback routing.
9. **Carrier leaves/disconnects during breakaway or wrap.** Existing swap-to-AI
   path (`G:leave`) already transfers `carrier`/`wrap`; new fields (`strideClass`,
   lockouts) live in `a.st` and transfer with it.
10. **Zero/extreme values.** `strideSpeedMin > wrSpeed` makes STRIDE unreachable
    (legal downtune, never an error); `landStun = 0` restores today's costless
    jump (the off switch); `breakawayGap < 2` would fire banners constantly —
    floor it at 2.0 in validation.

## 6. Dependencies

| System | Direction | Contract |
|---|---|---|
| `TeamFootballService` | owns all of this | Applies costs in `resolveArrival` / `resolveJumpBall` call sites, `updatePedals` (bite), intents (swat lockout, pump fake, squeeze hold); computes `arrivalYM`/`facingDeg`/`relSpeed` for #1 and hands them to both Rules and the animation state |
| `AWFootball.Rules` | extended | `resolveJumpBall` returns mistime flags per contestant; `judgeCatchDeterministic` consumed as built; no RNG added anywhere |
| `AWFootball.Config` | stores | new `rac`, `dbRisk` tables + §7 knobs; pays down the `TC`-table debt rather than deepening it |
| `AWMotion` / client | consumes | clip selection table (3.4.2), hands-up trigger, breakaway FOV kick; plays clips locally off replicated state |
| `football-playbook.md` | pairs | sluggo route definition and the deep-page risk curve (§4.2 there); the bite system is that doc's sluggo payoff — ship #5 with or after the route |
| `football-core.md` | parent | deterministic-catch philosophy (its §3.7) is the model #1 flips on in team mode; that doc's OPEN-DECISIONS A1 is **answered "deterministic" by this doc** pending the parity playtest |
| `football-ruleset.md` | rules base | waist-line catch technique (hands-up variants), ground-is-dead (gap list), IFAF base for every never-row |
| Owner clip publish | blocks 3.4 | permanent asset ids for the 8 clips + priority-1 new clips |
| `ux-designer` | coordinate | reason-string surfacing, intercept-point dot, breakaway banner |
| DRIP STORE (future) | must not touch | nothing here may be purchase-linked; celebrations are the only legal cosmetic surface |

## 7. Tuning Knobs

All in `AWFootball.Config` (`rac` / `dbRisk` / existing tables), never hardcoded.

| Knob | Default | Safe range | Category | Affects |
|---|---|---|---|---|
| `rac.strideSpeedMin` | 7.2 m/s | 6.0–8.5 | curve | how hard a stride catch is to earn (0.75 × wrSpeed) |
| `rac.strideImmunityMul` | 1.6 | 1.2–2.0 | curve | STRIDE free metres (4.2) |
| `rac.strideConeDeg` | 100° | 60–120 | curve | whether crossers qualify as in-stride |
| `rac.settleTime` / `settleMult` | 0.30 s / 0.6 | 0.15–0.5 / 0.4–0.8 | feel | SET catch pause |
| `rac.landRecover` | 0.40 s | 0.25–0.6 | feel | AERIAL landing (mirrors dbRisk.landStun) |
| `rac.breakawayGap` / `breakawayAheadM` | 4.0 / 1.0 m | 2.0–8.0 / 0.5–2.0 | gate | house-call banner moment |
| `rac.pursuitLeadMax` | 1.0 s | 0.4–1.5 | curve | pursuit angle quality (4.3) |
| `rac.blockBehindM` | 2.0 m | 1.0–4.0 | gate | escort-wall prevention (5.6) |
| `rac.sprintBlockDrag` | 0.8 s | 0.55–1.1 | feel | pancake payoff (vs blockDrag 0.55) |
| `dbRisk.jumpWindow` | 0.20 s | 0.12–0.30 | curve | how forgiving jump timing is |
| `dbRisk.landStun` | 0.40 s | 0.2–0.6 | curve | the mistimed-jump price; 0 = off switch |
| `dbRisk.swatLockout` / `swatSlow` | 0.5 s / 0.85 | 0.3–0.8 / 0.7–1.0 | curve | wrong-press price |
| `dbRisk.biteConeDeg` / `biteWindow` / `biteSlow` | 50° / 0.6 s / 0.8 | 30–70 / 0.4–1.0 / 0.65–0.9 | curve | double-move punish; pair-tune with sluggo geometry |
| `qb.pumpTime` | 0.4 s | 0.25–0.6 | gate | pump-fake cost vs `rusherCross` 3.2 s |
| `anim.handsUpLead` | 0.5 s (= windowEarly) | 0.3–0.7 | feel | when hands go up; also the DB's honest tell |
| `anim.highCatchM` | 1.7 m | 1.5–2.0 | feel | high vs chest clip boundary |

Pair-tuning law: `dbRisk.*` and `rac.strideImmunityMul` move the same WR-vs-DB
balance in the same direction — never buff both in one pass. Every default above
links to its rationale in §3/§4 (balance-value rule).

## 8. Acceptance Criteria

Functional — pure-Luau Command Bar harnesses in `tests/roblox/feel-upgrades/`,
PASS lines retained per `DEFINITION-OF-DONE.md` (no CI exists; the harness is the
evidence):

- [ ] **F1 stride ledger**: synthetic catches at (speed, grade, angle) grid
      classify STRIDE/SET/AERIAL exactly per 4.4, and immunity values match 4.2.
- [ ] **F2 jump wager**: jump offsets −0.60/−0.45/0.0 s produce stun/contest/stun
      per 4.1, identically for `kind = human` and `ai` inputs, with the stated
      reason strings.
- [ ] **F3 swat lockout**: an early press blocks `dbPlay` for exactly
      `swatLockout`; a timed press is bit-identical to today's resolution.
- [ ] **F4 bite detection**: a scripted sluggo vs (a) a flipped DB → bite + both
      strings; (b) a disciplined pedal DB → no bite (edge case 3).
- [ ] **F5 pursuit**: 4.3 at d = 9/2 m and closing ≤ 0 returns the stated τ; no
      NaN at d = 0.
- [ ] **F6 no stacking**: any sequence of costs on one athlete never exceeds
      0.40 s immobile / 1.0 s degraded (edge case 7).
- [ ] **F7 determinism**: with `catch.model = "deterministic"`, the same arrival
      inputs produce the same result and reason 1000/1000 times; no RNG call on
      the catch path.

Experiential — playtest with console capture + retained screenshots in
`production/qa/evidence/` (Visual/Feel evidence BLOCKS per coding standards):

- [ ] **E1 hands up**: screenshot sequence showing the target receiver's hands
      rising ≥ `handsUpLead` before arrival, in the variant matching arrival
      height; a nearby DB's hands rise too.
- [ ] **E2 clip selection**: one retained screenshot each of high / over-shoulder
      / scoop / chest catches, with the console line showing the geometry that
      picked the clip (same numbers as the catch reason — P1 check).
- [ ] **E3 the DB story**: a playtest clip where a DB bites a sluggo, stumbles,
      and both screens show their reason strings within 0.5 s (micro-feedback
      budget).
- [ ] **E4 RAC feel**: a stride catch visibly rolls through the catch (no pause);
      a SET catch visibly gathers. If testers can't tell them apart blind, retune
      `settleTime` before ship.
- [ ] **E5 breakaway**: banner + FOV kick fires exactly once on a last-man-beaten
      run and never when a defender is still ahead.
- [ ] **E6 balance smoke**: across a full 5v5 match, DBs still win ≥ 30% of
      contested jump balls (the costs punish *mistiming*, not jumping); if DBs
      stop jumping entirely, `landStun` is too high — retune, don't remove.
