# Football Core — ALLSTAR WORLD

> **Status: SPEC — nothing in this document is built yet.**
> Engine: Roblox (Luau). Units: studs, seconds, degrees.
> Scope: the football ball/possession core, built in five staged builds on one
> Practice Field, covering 1v1 (AI QB) and 2v2 (human QB). 5v5 reuses these
> rules and gets its own spec later.
> Monetization: cosmetic only. No purchasable item changes any value here.
> Authors: game-designer (1,2,3,5,8), systems-designer (4,7), network-programmer (6).
> Open decisions are listed in `OPEN-DECISIONS` at the end — resolve before Stage 2.

---

## 1. Overview

Football Core is the server-authoritative movement, ball and play-cycle layer for
ALLSTAR WORLD football. It is rebuilt in five staged builds on one Practice Field.
It covers momentum-based athlete movement, an explicit ball state machine, a
snap-to-whistle play cycle, three pass types, normal/diving/contested catches,
wrap and dive tackling with counter moves, rare fumbles, and drive-based scoring
for 1v1 (human receiver vs human defender, AI quarterback) and 2v2 (human QB).
5v5 reuses these rules and gets its own spec later. Every outcome is decided on
the server. Clients only predict visuals. Purchases never affect any rule here.

---

## 2. Player Fantasy

**"I beat him clean, and I know exactly how."** The receiver should feel like a
playmaker: a sharp cut opens a window, the ball arrives in stride, and a late
high-point catch over a defender feels earned. The defender should feel like a
hunter: reading the route, closing ground, timing the swat or landing the hit.
Every win and loss has a readable cause (late jump, boxed out, bad angle, wrong
counter). That serves **Challenge** first, then **Sensation** (punchy NFL Street
hits and cuts) and **Expression** (your own route running and move choices).

SDT targets: **Competence** comes from deterministic resolution and reason tags.
**Autonomy** comes from real route and move choices. **Relatedness** comes from
1v1 rivalry and 2v2 QB-receiver chemistry.

---

## 3. Detailed Design

### 3.1 Authority Model
- The server owns ball state, possession, catch/tackle resolution, spot and score.
- Clients send inputs with timestamps. The server rewinds positions by
  min(ping, [LAG_COMP_MAX]) when it checks catch and tackle windows.
- The ball is **not** a Roblox physics object. The server computes its flight
  (parabola) and loose-ball bounces. Clients render the server's trajectory.

### 3.2 Movement States
Every athlete has velocity, facing and a current state. Speed changes through
acceleration, never instantly.

| State | Entry | Rules |
|---|---|---|
| Idle/Jog | Default with/without move input | Accelerates to [JOG_SPEED] at [JOG_ACCEL]. Turning is free. |
| Sprint | Hold Sprint while moving | Accelerates to [SPRINT_SPEED] at [SPRINT_ACCEL]. Turn rate capped at [SPRINT_TURN_RATE]. Drains [SPRINT_STAMINA_MAX] at [STAMINA_DRAIN]/s and regenerates at [STAMINA_REGEN]/s when not sprinting. At 0 stamina, Sprint acts as Jog. |
| Cut | Direction change > [CUT_ANGLE_THRESHOLD] while above jog speed | Plant step lasting [CUT_DURATION]. Exit speed = current speed × [CUT_SPEED_RETENTION]. A cut never makes you faster. |
| Juke | Juke input + direction (receiver before catch, or ball carrier) | Lateral burst of [JUKE_DISTANCE] over [JUKE_DURATION]. Cooldown [JUKE_COOLDOWN]. |
| Spin | Spin input (ball carrier only) | Rotation lasting [SPIN_DURATION]. During [SPIN_ACTIVE_WINDOW], wrap tackles from any angle fail. Speed × [SPIN_SPEED_RETENTION]. Cooldown [SPIN_COOLDOWN]. |
| Stiff-arm | Stiff-arm input (ball carrier only) | Active for [STIFFARM_ACTIVE] in a frontal cone of [STIFFARM_CONE_ANGLE]. Cooldown [STIFFARM_COOLDOWN]. |
| Stumble | Broken tackle | Speed × [STUMBLE_SPEED_LOSS] for [STUMBLE_DURATION]. No evasive moves while stumbling. |
| Grounded | Tackled, dove, dive-caught | No input for [GROUNDED_DURATION] (or until whistle). |

Evade chaining: each successful evade in one play multiplies the cooldowns of
later evades in that play by [EVADE_CHAIN_MULT]. This stops endless highlight
runs from move spam.

### 3.3 Ball States

| State | Meaning | Exits to |
|---|---|---|
| Dead | Between plays, ball spotted | Snapped (snap input or auto-snap) |
| Snapped | Moving to QB over [SNAP_TIME]. Can't be touched. | Held (QB) |
| Held | Attached to a carrier | InFlight (pass), Loose (fumble), Dead (whistle) |
| InFlight | Server trajectory in progress | Caught, Contested, Loose→Dead (incomplete) |
| Contested | InFlight with ≥2 opposing players inside the catch window at arrival | Caught or Dead (incomplete) |
| Caught | Secure window of [CATCH_SECURE_TIME] after a catch | Held (secured) or Dead (incomplete, if hit or dislodged) |
| Loose | Fumble only, never an incomplete pass | Held (recovery) or Dead |

An InFlight ball touching the ground or crossing the boundary below
[OOB_HEIGHT] is incomplete. It goes straight to Dead and never becomes Loose.

### 3.4 Play Cycle
1. **Ready (huddle):** Offense picks a play/route within [READY_TIMEOUT]. When time
   runs out, the last play is reused (or a default Go route).
2. **Pre-snap:** Players are placed at formation spots. An invisible line of
   scrimmage (LOS) wall stops either side crossing before the snap. Offside is
   prevented, not penalized.
3. **Snap:** QB presses Snap (2v2) or the receiver presses Snap (1v1). Auto-snap
   happens after [AUTO_SNAP_TIME].
4. **Live:** Plays out under the rules below. Safety cap: [PLAY_MAX_DURATION].
5. **Whistle** on any of: carrier down (tackle resolved), carrier out of bounds,
   incomplete pass, touchdown, safety, sack, dive-catch landing, loose ball out
   of bounds, loose ball not recovered within [LOOSE_BALL_MAX_TIME], or play cap.
6. **Spot:** The ball is placed at forward progress (the ball's position at the
   down tick), at the sideline crossing point, or at the previous spot after an
   incompletion. Then back to Ready after [BETWEEN_PLAY_TIME].

### 3.5 Passing
Only the QB, behind the LOS, holding the ball, can pass. Pass input is disabled
once the QB crosses the LOS (he becomes a runner).

| Type | Input intent | Flight | Use |
|---|---|---|---|
| Touch (lead) | Tap pass | Medium arc, [TOUCH_SPEED] | Default. Leads the receiver into space. |
| Bullet | Hold pass for [BULLET_CHARGE_TIME] | Flat, [BULLET_SPEED] | Tight windows. Harder to catch when not facing the ball. |
| Lob | Lob modifier + pass | High arc, [LOB_SPEED] | Deep shots, creates jump balls. |

**Lead calculation:** The server aims at the predicted intercept point of the
target, using the target's velocity at release. Error radius = [BASE_THROW_ERROR],
plus [ON_RUN_ERROR] if the QB is moving above jog speed, plus [PRESSURE_ERROR] if
a defender is within [PRESSURE_RADIUS]. Once released, the trajectory is fixed.

**Aim by input type.** All three end up as the same server-side request:
"target receiver X, type T, offset O".
- **KB/M:** The mouse cursor puts a ground reticle on the field. If a receiver is
  within [AIM_ASSIST_RADIUS] of the reticle, the pass leads that receiver and the
  reticle offset becomes a placement offset (capped at [PLACEMENT_MAX_OFFSET]).
  Otherwise it is thrown to the spot.
- **Gamepad:** The right stick picks the receiver closest to the stick direction.
  Left-stick tilt at release gives a placement offset (same cap).
- **Touch:** Each eligible receiver shows a tappable icon. Tap = Touch. Press and
  hold = Bullet. Swipe up on the icon = Lob. No placement offset (lower ceiling,
  same floor). Track this for fairness in playtests.

### 3.6 Catching
- **Catch window:** a sphere of [CATCH_RADIUS] around a player's catch point
  (raised by [JUMP_REACH] while jumping).
- **Normal catch:** automatic and deterministic. If the ball arrives in the
  window, the player isn't Grounded/Stumbling, and nobody contests, it's caught.
  Exception: a Bullet caught while facing more than [CATCH_FACING_ANGLE] away
  from the ball is dropped. That is the only uncontested drop.
- **Diving catch:** press Dive while the ball's arrival point is outside
  [CATCH_RADIUS] but within [DIVE_CATCH_REACH]. A catch means the player is down
  at the landing spot (whistle). A miss leaves the player Grounded.
- **Swat/Interception (defender):** a defender with the ball in their window
  presses Catch/Jump. Uncontested (no offensive player in a window) = interception.
- **Contested / jump ball:** when players from both teams have the ball in their
  windows at arrival, the server scores each contestant on:
  1. **Timing:** how close the jump/catch press was to the ideal moment before
     arrival ([JUMP_TIMING_WINDOW]).
  2. **Position:** distance from the ball to the catch point, plus a bonus for
     being between the opponent and the ball ("boxing out").
  3. **Body state:** a penalty for mid-cut, stumbling or still turning, a bonus
     for being set or attacking the ball.
  4. A small random tiebreak, weighted [CONTEST_RNG_WEIGHT].

  Best offensive score wins → catch. Best defensive score wins: by more than
  [INT_MARGIN] → interception, otherwise → incomplete (breakup). Within
  [CONTEST_TIE_EPSILON] → offense (simultaneous possession). The client shows a
  reason tag to both players ("Late jump", "Boxed out", "Off balance").
- Same-team overlap: the teammate with the closest catch point catches it. No contest.

### 3.7 Tackling
Any opposing player can tackle the ball carrier (including the QB before the
throw, which is a sack). Teammates can't tackle each other. Non-carriers can't
be tackled. Contact without the ball is only body blocking.

| Tackle | Input | Range | On miss |
|---|---|---|---|
| Wrap | Tackle (tap) | [WRAP_RANGE] | Tackler slowed by [WRAP_MISS_SLOW] |
| Dive | Dive Tackle (any speed, lunges [DIVE_RANGE]) | [DIVE_RANGE] | Tackler Grounded for [DIVE_MISS_RECOVERY] |

**Counter matrix** (checked on the server tick the tackle connects):

| Carrier state | vs Wrap | vs Dive |
|---|---|---|
| None | Tackled | Tackled |
| Stiff-arm active, tackler in front cone | Broken: tackler stunned [STIFFARM_STUN] | Tackled |
| Stiff-arm, tackler outside cone | Tackled | Tackled |
| Spin active window | Broken: carrier Stumbles | Tackled (fumble check, see 3.8) |
| Juke active (displaced) | Usually whiffs (geometry) | Usually whiffs (geometry) |

Result: wrap is safe but loses to stiff-arm and spin. Dive beats both but loses
to a well-timed juke and is costly when it misses. Neither tackle dominates.

**Momentum break:** a wrap from behind when the carrier's speed exceeds the
tackler's by more than [BREAK_SPEED_DELTA] causes a Stumble instead of a tackle.
**Gang tackle:** any tackle contact on a Stumbling carrier always succeeds.

### 3.8 Fumbles (Rare by Design)
A fumble can only happen when a **Dive tackle** connects during a carrier's
**Spin** or **Juke recovery** frames, with chance [FUMBLE_CHANCE]. Wrap tackles,
sacks and Caught-state hits never cause fumbles. A Caught-state hit is an
incompletion. Loose balls bounce on a server path. Any player who touches one
within [RECOVER_RADIUS] recovers it, and play continues.

### 3.9 Downs and Scoring (1v1, 2v2)
- Short field. Each drive starts [DRIVE_START_DISTANCE] from the goal line.
- [DOWNS_PER_SERIES] downs to gain [FIRST_DOWN_DISTANCE]. Gaining it gives a new
  series. Running out of downs = turnover on downs.
- Touchdown = [TD_POINTS]. Safety = [SAFETY_POINTS] to the defense. No kicking.
- Any drive end (TD, turnover on downs, interception, lost fumble, safety) →
  possession swaps. The next drive **always** starts at the standard spot. There
  is no field-position carryover. Exception: a defensive return TD scores first.
- **Rounds:** a round is one drive for each side. A win is checked only after a
  complete round: first to [WIN_SCORE] or more and ahead, or the leader when
  [MATCH_TIME] expires at a round boundary. Tied → overtime: alternating single
  plays from [OT_DISTANCE] until one side scores and the other doesn't.
- **1v1 roles:** player A is receiver (with AI QB) and B is defender, then they
  swap each drive.

### 3.10 AI Quarterback (1v1 and Route Practice)
- Stands in the pocket. Never scrambles, never runs, cannot be sacked.
- Knows the receiver's chosen route. Throws when the first of these happens:
  (a) separation ≥ [OPEN_SEPARATION] after the route break,
  (b) the receiver presses Call for Ball,
  (c) the defender crosses the LOS (instant throw to the current lead point),
  (d) [AI_QB_MAX_HOLD] elapsed (forced throw).
- Throw type: Bullet if the target is within [SHORT_THROW_DIST] and open. Lob if
  the target is beyond [DEEP_THROW_DIST] or the throw is forced while covered.
  Otherwise Touch.
- Fixed error [AI_QB_ACCURACY_ERROR]. No rubber-banding, no reading the score,
  same behavior for both players. This is what makes it fair.

### 3.11 Route Practice Mode (Solo, No AI Defender)
- The player picks a route from the tree (Slant, Out, In/Dig, Curl, Post, Corner,
  Go, Comeback). A ghost route line can be toggled on.
- The AI QB throws by rule 3.10 (a)/(b)/(d). The player can lock a throw type.
- The play ends at catch + [PRACTICE_YAC_TIME], end zone, out of bounds or
  incompletion. Instant reset, no Ready timeout.
- Per-rep feedback: caught/dropped, break timing vs ideal, separation proxy
  (distance from the ideal route), YAC. Session stats: catches/targets, best streak.
- No scoring, tackling or stamina drain (stamina still exists so it matches real play).

### 3.12 Controls
Context-sensitive: the same button changes meaning by role. The camera is a
fixed follow cam during live play, so the mouse is free for aiming.

| Action | Context | KB/M | Gamepad | Touch |
|---|---|---|---|---|
| Move | All | WASD | Left stick | Left virtual stick |
| Sprint | All | Shift (hold) | RT (hold) | Sprint button (hold) |
| Snap | QB / 1v1 receiver | Space | A | Snap button |
| Pass Touch / Bullet | QB | LMB tap / hold | A tap / hold | Tap / hold receiver icon |
| Lob | QB | RMB | RB + A | Swipe up on receiver icon |
| Target / aim | QB | Mouse reticle | Right stick | Receiver icons |
| Catch / Jump / Swat | Ball in flight | Space | A | Jump button |
| Dive catch | Receiver, ball in flight | Ctrl | B | Dive button |
| Call for Ball | 1v1 receiver | R | Y | Hand button |
| Juke | Receiver / carrier | Q + direction | Right-stick flick | Swipe left/right (right side) |
| Spin | Carrier | E | B | Spin button |
| Stiff-arm | Carrier | F | X | Stiff-arm button |
| Wrap tackle | Defender | LMB | X | Tackle button |
| Dive tackle | Defender | RMB | B | Dive button |

Touch shows at most 4 context buttons at once.

---

## 4. Formulas

### 4.1 Movement

#### 4.1.1 Acceleration / deceleration (frame-rate independent)

    v_next = v + (v_target − v) · (1 − e^(−dt / τ))
    τ = TAU_ACCEL   if |v_target| > |v|
    τ = TAU_DECEL   otherwise
    v_target = JOG_SPEED or SPRINT_SPEED (sprint held, stamina available) along input dir; 0 if no input

| Symbol | Type | Range | Description |
|---|---|---|---|
| v | float | 0–24 | Current horizontal speed (studs/s) |
| v_target | float | {0, 16, 24} | Speed the player is steering toward |
| dt | float | 0.008–0.05 | Frame delta (s) |
| TAU_ACCEL | float | 0.15–0.40 | Accel time constant (s) |
| TAU_DECEL | float | 0.10–0.25 | Decel time constant (s) |
| v_next | float | 0–24 | Speed next frame |

**Output range:** bounded in [0, v_target] by design (exponential approach never overshoots).
**Example:** 0→sprint with τ=0.25: 63% (15.2) at 0.25 s, 90% (21.6) at 0.58 s, 95% at 0.75 s. Releasing input at 24 with τ=0.15 gives stopping distance ≈ v·τ = 3.6 studs (~0.35 s).

#### 4.1.2 Turn-rate limit vs speed (momentum)

    ω_max(v) = TURN_RATE_SLOW − (TURN_RATE_SLOW − TURN_RATE_FAST) · clamp(v / SPRINT_SPEED, 0, 1)^TURN_CURVE_EXP
    turn_radius = v / (ω_max · π/180)

| Symbol | Type | Range | Description |
|---|---|---|---|
| v | float | 0–24 | Current speed |
| TURN_RATE_SLOW | float | 540–900 | Max heading change at standstill (°/s) |
| TURN_RATE_FAST | float | 150–300 | Max heading change at sprint (°/s) |
| TURN_CURVE_EXP | float | 1.0–2.0 | How late in the speed band turning stiffens |
| ω_max | float | 220–720 | Allowed heading change (°/s) |

**Output range:** [TURN_RATE_FAST, TURN_RATE_SLOW] = [220, 720]; min at sprint, max at rest.
**Example:** jog 16: ω = 720 − 500·0.667^1.5 = 448°/s → radius 2.0 studs. Sprint 24: ω = 220°/s → radius 6.25 studs (just over one body length — runners must "round" routes at full speed).

#### 4.1.3 Hard cut (plant) penalty

Let Δθ = angle between input direction and current velocity heading.

- Δθ ≤ CUT_THRESHOLD → smooth turn, limited by ω_max.
- CUT_THRESHOLD < Δθ ≤ CUT_MAX_ANGLE → plant: heading snaps over CUT_PLANT_TIME, then

      v_after = v · clamp(1 − CUT_PENALTY_K · (Δθ/180) · (0.5 + 0.5 · v/SPRINT_SPEED), CUT_RETAIN_MIN, 1)

- Δθ > CUT_MAX_ANGLE → no flip: brake (TAU_DECEL) to ≤ PIVOT_SPEED, then turn freely.

| Symbol | Type | Range | Description |
|---|---|---|---|
| Δθ | float | 0–180 | Requested direction change (°) |
| CUT_THRESHOLD | float | 25–50 | Above this angle, a turn counts as a hard cut |
| CUT_MAX_ANGLE | float | 120–150 | Above this angle, the player must brake to turn around |
| CUT_PENALTY_K | float | 0.6–1.2 | Cut severity |
| CUT_RETAIN_MIN | float | 0.25–0.5 | Floor on retained speed |
| v_after | float | 0.35v–v | Speed coming out of the cut |

**Output range:** [0.35·v, v]. Raw expression can go below the floor at 135° sprint (0.325), so the clamp is load-bearing.
**Example:** 90° cut at sprint: 1 − 0.9·0.5·1.0 = 0.55 → 13.2 studs/s. Same cut at jog: 1 − 0.9·0.5·0.833 = 0.625 → 10.0. Sprinting cuts are faster in absolute terms but cost more; it rewards throttling down before the break of a route.

#### 4.1.4 Sprint stamina

    S_next = S − STAMINA_DRAIN · dt                                   (sprinting)
    S_next = S + STAMINA_REGEN_MOVE · dt   (moving, not sprinting, ≥ STAMINA_REGEN_DELAY since last drain)
    S_next = S + STAMINA_REGEN_IDLE · dt   (speed < 2, after delay)
    S clamped to [0, STAMINA_MAX]. At S = 0: exhausted; sprint locked until S ≥ STAMINA_UNLOCK.
    Moves (juke/spin/stiff-arm/dive) cost a flat amount and require S ≥ cost.

| Symbol | Type | Range | Description |
|---|---|---|---|
| S | float | 0–100 | Current stamina |
| STAMINA_DRAIN | float | 12–25 | Per second of sprint |
| STAMINA_REGEN_MOVE | float | 10–30 | Regen while jogging |
| STAMINA_REGEN_IDLE | float | 20–50 | Regen while standing / huddle |
| STAMINA_UNLOCK | float | 15–40 | Hysteresis so exhaustion is a real cost |

**Output range:** clamped [0, 100].
**Example:** full bar = 100/18 = 5.6 s of continuous sprint, which covers a deep route plus a short run after the catch. A 7 s huddle idle restores 7·35 = 245, so a full bar every normal play. Only hurry-up/no-huddle drains across plays (intentional).

#### 4.1.5 Juke and spin

    Juke:  v_forward' = v_forward · JUKE_SPEED_RETAIN
           lateral velocity += JUKE_LATERAL_SPEED for JUKE_DURATION  (displacement = speed × duration)
    Spin:  v' = v · SPIN_SPEED_RETAIN for SPIN_DURATION; heading unchanged; grants SPIN_BREAK_BONUS (4.5.2)
    Any move blocks juke/spin/stiff-arm for MOVE_GLOBAL_LOCKOUT; each has its own cooldown.

| Symbol | Type | Range | Description |
|---|---|---|---|
| JUKE_SPEED_RETAIN | float | 0.75–0.95 | Forward speed kept |
| JUKE_LATERAL_SPEED | float | 14–26 | Sidestep velocity (studs/s) |
| JUKE_DURATION | float | 0.12–0.25 | Sidestep length (s) |
| SPIN_SPEED_RETAIN | float | 0.65–0.9 | Speed kept through spin |
| SPIN_DURATION | float | 0.3–0.5 | Spin length (s) |

**Output range:** juke displacement = 20 × 0.18 = 3.6 studs lateral (enough to leave a 4-stud wrap cone that a tackler has committed to); post-juke sprint speed 20.4.
**Design note:** a juke keeps 85% of speed vs 55% for a 90° cut. Moves are better than raw cuts but are gated by cooldown and stamina. That is the skill trade.

---

### 4.2 Passing

#### 4.2.1 Throw types and power

Each type has a fixed horizontal ball speed s and a max range. The QB's charge `P ∈ [0,1]` (hold time / THROW_CHARGE_TIME) chooses the type band: tap = Bullet, hold = Lead, full hold = Lob. (Alternative: dedicated buttons. Input mapping belongs to the game-designer and UX, not this doc.)

| Type | s (studs/s) | Max range (studs) | Intended use |
|---|---|---|---|
| Bullet | 70 | 45 | Slants, comebacks, tight windows |
| Lead (touch) | 50 | 60 | Default in-stride throw |
| Lob | 34 | 75 | Over the top, jump balls |

Overall throw power range = 34–70 studs/s horizontal (≈ 9.5–19.6 m/s).

#### 4.2.2 Lead-pass target point (closed-form intercept)

The QB aims at the receiver's predicted position, plus a small lead so the ball arrives in front of the hands:

    d   = (P_r + û_r · LEAD_BIAS) − P_qb            (horizontal 2D)
    Solve for total time T:  |d + V_r · T| = s · (T − THROW_WINDUP)
    → a·T² + b·T + c = 0, where
       a = |V_r|² − s²
       b = 2(d·V_r) + 2·s²·THROW_WINDUP
       c = |d|² − s²·THROW_WINDUP²
    T = smallest root with T > THROW_WINDUP
    t_f = T − THROW_WINDUP          (ball flight time)
    Aim = P_qb + d + V_r · T        D = s · t_f

| Symbol | Type | Range | Description |
|---|---|---|---|
| P_qb, P_r | vec2 | field | QB release point, receiver position at throw input |
| V_r | vec2 | 0–24 mag | Receiver velocity, EMA-smoothed over RECEIVER_VEL_SMOOTH (stops one juke from yanking the aim) |
| û_r | vec2 | unit | Receiver direction of travel (0 if speed < 4) |
| s | float | 34–70 | Throw-type ball speed |
| THROW_WINDUP | float | 0.1–0.3 | Input-to-release delay (s) |
| T | float | >0.2 | Input-to-arrival time |
| D | float | 0–75 | Throw distance |

**Output range:** a < 0 whenever |V_r| < s (always true: 24 < 34), so one positive root always exists. If D > type max range, the throw is clamped to max range in the aim direction and arrives short. This is the readable "out of range" failure, and the aim reticle turns red.
**Ball inheritance:** the ball does NOT inherit QB velocity (BALL_INHERIT_QB_VEL = 0). Arcade-readable; throwing on the run is penalized through spread (4.2.4) instead.

#### 4.2.3 Ball arc (custom ball gravity, not workspace gravity)

Workspace gravity (196.2 studs/s²) makes bullets look like lobs. The ball is a server-simulated analytic projectile:

    v_z  = (Δh + ½ · G_BALL · t_f²) / t_f,     Δh = h_catch − h_release
    h(t) = h_release + v_z·t − ½·G_BALL·t²
    apex height above release = v_z² / (2·G_BALL)       at t = v_z / G_BALL
    Lob: h_catch = LOB_TARGET_HEIGHT (high-point catch) instead of chest height

| Symbol | Type | Range | Description |
|---|---|---|---|
| G_BALL | float | 50–120 | Ball gravity (studs/s²) |
| h_release | float | 5.0 | Release height (studs) |
| h_catch | float | 3.5 (chest) / 8.5 (lob) | Target arrival height |
| t_f | float | 0.15–2.2 | Flight time |
| v_z | float | ~3–90 | Launch vertical velocity |

**Output range:** apex ≈ G_BALL·t_f²/8 for level throws. Bullet 25 studs: t_f 0.36, apex +1.3. Lead 25: t_f 0.50, apex +2.5. Lob 40: t_f 1.18, apex +14.

Because the ball's path is closed-form, every client draws it exactly from (origin, velocity, G_BALL, t_launch) with no jitter. The server can also evaluate the ball's position at any past timestamp exactly (used in 4.6).

#### 4.2.4 Accuracy spread

    pressure = clamp((PRESSURE_RADIUS − d_def) / (PRESSURE_RADIUS − SACK_RADIUS), 0, 1)
    σ = SPREAD_BASE + SPREAD_MOVE · (v_qb / SPRINT_SPEED)
                    + SPREAD_PRESSURE · pressure
                    + SPREAD_OFF_PLATFORM · (φ_body / 180)
    Landing error: 2D Gaussian, per-axis std = D · tan(σ), each axis clamped to ±2 std.

| Symbol | Type | Range | Description |
|---|---|---|---|
| d_def | float | 0–∞ | Distance from the QB to the nearest pass rusher |
| v_qb | float | 0–24 | QB speed at release |
| φ_body | float | 0–180 | Angle between the QB's facing and the throw direction |
| σ | float | 0.5–8.5 | Spread (°) |

**Output range:** σ ∈ [0.5°, 8.5°]: minimum when set, clean and square; maximum when sprinting, defender within the sack radius, throwing backward. Error is capped at 2σ (≤ 17°) so there are no absurd misses. The live reticle draws the 1σ cone, so the player can read the spread rather than it feeling like dice. The server rolls with a per-match seeded `Random`.
**Example:** set QB, 26.5-stud lead: σ 0.5° → std 0.23 studs. Effectively perfect.

#### 4.2.5 AI QB throw decision (1v1)

    sep_req(t) = max(SEP_MIN, SEP_START − SEP_DECAY · (t − AI_READ_START))     for t ≥ AI_READ_START
    sep_pred   = |P_r(T) − P_d(T)|, each extrapolated linearly (defender speed capped at SPRINT_SPEED)
    Throw when sep_pred ≥ sep_req(t) (re-check every AI_TICK), then wait AI_REACTION, then THROW_WINDUP.
    Forced throw at t = AI_MAX_HOLD: Lob if sep_pred < SEP_MIN (jump ball), else Lead.
    Type choice: defender within 3 studs of the ball path at mid-flight → Lob;
                 receiver speed < 6 → Bullet; else Lead.
    Timing jitter: uniform ±AI_JITTER added to AI_READ_START per snap (anti-exploit).

| Symbol | Type | Range | Description |
|---|---|---|---|
| t | float | 0–AI_MAX_HOLD | Time since snap |
| SEP_START | float | 5–9 | Separation needed early (studs) |
| SEP_DECAY | float | 1.5–4 | How fast the AI lowers its bar (studs/s) |
| SEP_MIN | float | 1–3 | Floor (contested-ball threshold) |
| sep_req | float | 2–7 | Current required separation |

**Output range:** sep_req ∈ [2, 7]. With the defaults it reaches the floor at t = 0.9 + 2.0 = 2.9 s, so every snap gets a throw by 3.2 s at the latest. The receiver's route skill (making separation) is what makes the AI throw early and cleanly. AI σ uses SPREAD_BASE only (no pass rush in 1v1).

---

### 4.3 Catching

#### 4.3.1 Catch eligibility

    Eligible if, at arrival time t_a:  |ball(t_a) − catch_point_i| ≤ CATCH_RADIUS + CATCH_LATENCY_PAD
    Diving: radius = DIVE_CATCH_RADIUS (ellipse elongated along dive direction)
    catch_point = root + (0, 1.0, 0) studs (chest), or hand height while jumping (4.4)
    0 eligible → incomplete. 1 offensive → catch roll (4.3.3). 1 defensive → INT roll.
    ≥1 of each within CONTEST_RADIUS → jump ball (4.4).

#### 4.3.2 Catch press window — [CATCH_WINDOW]

    Pressed "secure" at t_p (lag-compensated, 4.6).  Secure if  t_a − CATCH_WINDOW_EARLY ≤ t_p ≤ t_a + CATCH_WINDOW_LATE
    [CATCH_WINDOW] = CATCH_WINDOW_EARLY + CATCH_WINDOW_LATE = 0.30 + 0.10 = 0.40 s

Uncontested catches are automatic (arcade). The press is a skill bonus, not a requirement.

#### 4.3.3 Drop chance (additive, low, readable)

    P_drop = clamp( DROP_BASE
                  + DROP_OVER_SHOULDER · [ball arrives from behind the receiver's facing]
                  + DROP_REACH_BACK · clamp(−(offset · look) / CATCH_RADIUS, 0, 1)
                  + DROP_HOT_BALL · clamp((v_rel − HOT_BALL_MIN) / HOT_BALL_SPAN, 0, 1)
                  + DROP_DIVE · [diving]
                  + DROP_HIT · [defender contact within HIT_WINDOW of catch and not secured]
                  − DROP_SECURE · [secured], 0, DROP_MAX)
    Defender INT attempt: same formula with DROP_BASE replaced by INT_DROP_BASE.

| Symbol | Type | Range | Description |
|---|---|---|---|
| offset | vec3 | ≤ radius | Ball arrival point − catch point |
| look | vec3 | unit | Receiver root LookVector |
| v_rel | float | 0–100 | Ball speed relative to the receiver |
| P_drop | float | 0–0.25 | Drop probability |

**Output range:** [0, 0.25]. Sum of positives can reach 0.34, so DROP_MAX caps it.
**Readability rule:** a clean, secured, in-stride ball is exactly 0%. Every drop has a visible cause (behind you, too hot, diving, hit on the catch).
**Example:** go-route lead (Ex. 1): 0.01 + 0.03 (over shoulder) = 4% unsecured, 0% secured.

---

### 4.4 Jump ball / contested catch — [JUMPBALL_TIMING_WINDOW]

Triggered when players from both teams have catch points within CONTEST_RADIUS of ball(t_a). The result is a fixed calculation: no random roll.

    Hand height after jump press (τ = time since press, t_ap = JUMP_APEX_TIME):
      h_hand(τ) = REACH_STAND + JUMP_HEIGHT · max(0, 1 − ((τ − t_ap)/t_ap)²)    for 0 ≤ τ ≤ 2·t_ap
      h_hand = REACH_STAND if no jump / landed

    Timing   T_i = clamp(1 − max(0, |τ_i(t_a) − t_ap| − JUMPBALL_PERFECT_BAND) / JUMPBALL_TIMING_WINDOW, 0, 1)
               (T_i = 0 if no jump)
    Position P_i = clamp(1 − d_i / CONTEST_RADIUS + BOXOUT_BONUS · [box-out], 0, 1)
               box-out: d_i < d_j AND angle between (P_i − ball) and (P_j − ball) ≤ BOXOUT_ANGLE
    Height   H_i = clamp(1 − max(0, h_ball − h_hand_i) / HEIGHT_TOL, 0, 1)

    Score_i = W_TIMING·T_i + W_POSITION·P_i + W_HEIGHT·H_i         (weights sum to 1)

    Resolve (best offense O vs best defense X):
      |Score_O − Score_X| < TIE_MARGIN → both ≥ 0.5: catch to offense (simultaneous possession); else incomplete (batted)
      Score_O wins → catch (secured automatically, DROP_HIT still applies if unsecured)
      Score_X wins → Score_X ≥ INT_THRESHOLD: interception; else pass breakup

| Symbol | Type | Range | Description |
|---|---|---|---|
| τ_i(t_a) | float | 0–∞ | Player i's time since jump press at ball arrival |
| d_i | float | 0–4 | Horizontal distance from catch point to ball arrival point |
| h_ball | float | 0–15 | Ball height at t_a |
| T_i, P_i, H_i | float | 0–1 | Component scores |
| Score_i | float | 0–1 | Contest score |

**Output range:** Score ∈ [0, 1]. Minimum: no jump, at the edge of the radius, ball over reach. Maximum: perfect jump, on the spot with box-out, hands above ball.
**Why this weighting:** timing (0.45) is pure input skill; position (0.35) rewards route running and coverage; height (0.20) only matters when someone jumped badly. Same body scale for everyone, so height is earned, never bought.

---

### 4.5 Tackling

#### 4.5.1 Tackle initiation — [TACKLE_RANGE]

    Wrap: |P_c − P_t| ≤ TACKLE_RANGE + TACKLE_LATENCY_PAD and angle(look_t, P_c − P_t) ≤ WRAP_CONE_HALF
          startup WRAP_STARTUP; miss → WRAP_MISS_RECOVERY
    Dive: initiate ≤ DIVE_TACKLE_RANGE; lunge DIVE_LUNGE_SPEED for DIVE_LUNGE_TIME, contact radius 2.5 along the path;
          miss → DIVE_MISS_RECOVERY on the ground

#### 4.5.2 Broken-tackle chance

    m      = clamp((v_c − v_t,close) / SPRINT_SPEED, −1, 1)
    q_sa   = clamp(1 − |(t_contact − t_sa) − STIFFARM_PEAK| / STIFFARM_PEAK, 0, 1)
    SA     = [0 ≤ t_contact − t_sa ≤ STIFFARM_WINDOW and tackler in front arc] · (SA_BONUS_MIN + SA_BONUS_SCALE · q_sa)

    P_break = clamp( BREAK_BASE_[WRAP|DIVE]
                   + BREAK_MOMENTUM_K · m
                   + BREAK_ANGLE_K · (1 − cos α)/2
                   + SA
                   + SPIN_BREAK_BONUS_[WRAP|DIVE] · [spinning at contact]
                   − BREAK_FATIGUE · n_broken,
                   BREAK_MIN, BREAK_MAX)

| Symbol | Type | Range | Description |
|---|---|---|---|
| v_c | float | 0–24 | Carrier speed |
| v_t,close | float | 0–30 | Tackler velocity component toward the carrier |
| α | float | 0–180 | Angle between carrier velocity and carrier→tackler (0 = head-on, 180 = from behind) |
| t_sa | float | — | Stiff-arm press time (compensated) |
| n_broken | int | 0–∞ | Tackles already broken this play |
| P_break | float | 0.02–0.75 | Chance the carrier breaks the tackle |

**Output range:** clamped [0.02, 0.75]. The raw maximum is 0.25 + 0.15 + 0.15 + 0.45 + 0.10 ≈ 1.1, so the 0.75 cap guarantees any tackle has at least a 25% chance to land. The raw minimum is negative, so the 0.02 floor keeps a tiny chance of a miracle break.
**Feedback loop:** BREAK_FATIGUE is deliberate dampening (negative feedback). Each broken tackle makes the next one 10 points easier for the defense, so a single runner can't break every tackle on one play.
**Resolution mode knob:** `TACKLE_RESOLUTION = "roll"` (default) or `"threshold"` (break if P_break ≥ 0.5, no dice). Threshold mode is fully skill-based but every outcome becomes predictable; playtest both.

#### 4.5.3 Stiff-arm — [STIFFARM_WINDOW]

Active for STIFFARM_WINDOW = 0.30 s after the press. The bonus peaks at STIFFARM_PEAK = 0.15 s (the best moment is mid-window). It works only against a tackler in the front 120° arc. Speed × STIFFARM_SPEED_RETAIN while active. A whiffed stiff-arm (no contact) still triggers the full STIFFARM_COOLDOWN, so spamming it is punished.

#### 4.5.4 Fumble — [FUMBLE_CHANCE]

Rolled only on a completed tackle (never on a broken one):

    P_fumble = min(FUMBLE_CHANCE · M_blind · M_bighit · M_gang · M_protect, FUMBLE_CAP)
    M_blind = FUMBLE_BLINDSIDE_MULT if α > 120°, else 1
    M_bighit = FUMBLE_BIGHIT_MULT if v_t,close ≥ 0.8·SPRINT_SPEED, else 1
    M_gang = FUMBLE_GANG_MULT if a 2nd tackler makes contact within 0.5 s, else 1
    M_protect = FUMBLE_PROTECT_MULT if the carrier is holding protect-ball (no sprint), else 1

**Output range:** [0.0025, 0.06]. Minimum: protected, head-on, soft hit. Maximum: capped (raw max = 0.01·2·1.5·1.5 = 0.045, so the cap only matters if knobs are raised). At the default 1%, that's roughly one fumble every 40–70 tackles counting the multipliers. Rare, and always caused by something you can see.

---

### 4.6 Latency tolerance — [LATENCY_GRACE]

    Client sends each action (catch press, jump, tackle, stiff-arm, juke, spin) with t_client = workspace:GetServerTimeNow().
    Server:  t_action = clamp(t_client, t_recv − LATENCY_GRACE, t_recv)
    Positions are evaluated from a server history buffer (POSITION_HISTORY_LEN) at t_action.
    Ball position at t_action is exact (analytic, 4.2.3); no rewind is needed for the ball.
    Spatial pad:  pad = clamp(v_rel · min(RTT_i/2 + INTERP_DELAY, LATENCY_GRACE), 0, PAD_MAX)
       applied to CATCH_RADIUS (PAD_MAX = CATCH_PAD_MAX) and TACKLE_RANGE (PAD_MAX = TACKLE_PAD_MAX)
    Conflict rule: earliest validated t_action wins (a juke stamped before a tackle beats the tackle).
    Contested outcomes (jump balls, simultaneous tackles) resolve at t_a + CONTEST_RESOLVE_DELAY so late packets arrive;
       the catch/collision animation covers the delay.
    Sanity: reported speed > SPRINT_SPEED · SPEED_TOLERANCE (outside move bursts) → position rejected and snapped back.

| Symbol | Type | Range | Description |
|---|---|---|---|
| t_recv | float | — | Server receive time |
| RTT_i | float | 0.05–0.25+ | Player round-trip time |
| INTERP_DELAY | float | ~0.1 | Roblox remote-character render lag |
| pad | float | 0–1.5 | Extra radius granted |

**Output range:** t_action ∈ [t_recv − 0.20, t_recv]. Players above ~250 ms RTT get partial compensation; the claim is capped so laggy or spoofed timestamps can't rewrite more than 0.2 s of history. Pad is clamped by PAD_MAX so that at sprint closing speeds (v_rel 48 × 0.2 = 9.6 studs raw) tackles don't connect across the field.

---

### 4.7 Worked examples

**Example 1: ~26.5-stud lead pass to a sprinting receiver (go route, clean pocket)**
QB set at (0,0). Receiver at (0, 8) running straight downfield at sprint, V_r = (0, 24). Lead pass: s = 50, THROW_WINDUP = 0.20, LEAD_BIAS = 1.0.
- d = (0, 9). The problem is 1D: 9 + 24T = 50(T − 0.20) → 26T = 19 → **T = 0.731 s**, t_f = 0.531 s.
- D = 50 × 0.531 = **26.5 studs**. Aim (0, 26.5). Receiver at arrival: 8 + 24 × 0.731 = 25.5, so the ball is 1 stud ahead, in stride. ✓
- Arc: Δh = 3.5 − 5.0 = −1.5. v_z = (−1.5 + 40 × 0.282)/0.531 = 18.4 studs/s. Apex +2.1 → 7.1 studs high at t = 0.23 s, about 11.5 studs downfield. A defender standing under that point (reach 6.5) needs a jump to tip it.
- Spread: σ = 0.5° → std 0.23 studs → lands inside CATCH_RADIUS ~100%.
- Drop: 0.01 + 0.03 (over the shoulder) = **4% unsecured, 0% with a timed secure press**.
- *Variant, rolling right under pressure:* QB moving 16 studs/s, rusher 6 studs away (pressure = 6/9 = 0.667), throwing 90° off his facing. σ = 0.5 + 1.67 + 2.33 + 1.0 = **5.5°** → std 26.5 × tan 5.5° = 2.55 studs per axis. P(within 3 studs) = 1 − e^(−9/(2 × 2.55²)) ≈ **50%**; with a dive (radius 5) ≈ **85%**, drop 0.01 + 0.03 + 0.06 = 10%. The risk is big and you can see it coming.

**Example 2: jump ball on a fade (lob, h_ball = 8.5)**
Receiver R: presses jump 0.32 s before arrival (|0.32 − 0.30| = 0.02 ≤ band) → T = 1.0. Hand height at τ 0.32 ≈ 8.99 ≥ 8.5 → H = 1. d = 1.2, boxing out the defender → P = 0.70 + 0.25 = 0.95.
Score_R = 0.45 + 0.3325 + 0.20 = **0.983**.
Defender X: presses 0.18 s before arrival (|0.18 − 0.30| = 0.12) → T = 1 − 0.08/0.25 = 0.68. Hand 8.6 → H = 1. d = 2.4, no box-out → P = 0.40.
Score_X = 0.306 + 0.14 + 0.20 = **0.646** → margin 0.34 → **catch**.
*Flip:* R jumps 0.15 s late (T = 0.56, hand 8.375 → H = 0.95) → Score_R = 0.252 + 0.3325 + 0.19 = 0.775. X times it perfectly from d = 1.6 → Score_X = 0.45 + 0.21 + 0.20 = 0.86. Margin 0.085 ≥ 0.08 and 0.86 ≥ INT_THRESHOLD → **interception**. Both outcomes trace directly to inputs; no dice.

**Example 3: stiff-arm vs a wrap tackle**
Carrier at sprint 24. Tackler closing at 18 studs/s from the front-side (α = 45°), wrap. Stiff-arm pressed 0.12 s before contact.
- m = (24 − 18)/24 = 0.25 → +0.0375. Angle: 0.15 × (1 − cos 45°)/2 = +0.022.
- q_sa = 1 − |0.12 − 0.15|/0.15 = 0.80 → SA = 0.15 + 0.30 × 0.80 = +0.39.
- P_break = 0.10 + 0.0375 + 0.022 + 0.39 = **0.55** (no stiff-arm: **0.16**). Threshold mode: broken.
- If the tackle lands instead: front hit, tackler at 18 < 19.2 (not a big hit), so P_fumble = **1%**.
- Next tackle this play: −0.10 fatigue applies.

---

---

## 5. Edge Cases

1. **Simultaneous catch, opposing teams, exact tie:** offense gets it (3.6).
2. **Simultaneous catch, same team:** closest catch point wins. No contest.
3. **Airborne sideline catch:** decided on landing. The catcher's root must land
   in bounds. Landing out of bounds = incomplete. Where the ball is doesn't matter.
4. **Ball crosses boundary in flight above [OOB_HEIGHT]:** still live. An
   in-bounds player can catch it. Below that height = incomplete.
5. **Tackle at the goal line:** on the down tick, if the ball's attach point has
   broken the goal-line plane, it's a TD. Otherwise spot at forward progress.
6. **Stiff-arm and tackle input on the same tick:** the server applies
   lag-compensated timestamps. Whichever started first wins. Exact tie = the
   carrier's active move state wins (offense advantage in ties, consistent with 1).
7. **Hit during Caught secure window:** incomplete, never a fumble.
8. **Carrier disconnects mid-play:** immediate whistle, ball dead at current spot.
   Match pauses for [REJOIN_GRACE]. No return = the leaver's side forfeits.
9. **Targeted receiver disconnects while ball in flight:** the flight continues.
   Anyone else can catch or contest it. Otherwise incomplete.
10. **Interception downed in the defender's own end zone:** touchback. Possession
    swaps to a standard drive start.
11. **Fumble out of bounds:** the last team in possession keeps it at the crossing point.
12. **Fumble out the back of an end zone:** turnover. Standard drive start for the
    recovering side.
13. **Loose ball stuck on geometry or nobody recovers it:** after
    [LOOSE_BALL_MAX_TIME], whistle and the last possession keeps it at the ball's spot.
14. **QB crosses LOS:** passing is disabled. A pass input does nothing (no illegal
    forward pass to adjudicate).
15. **1v1 defender blitzes the AI QB:** instant throw at the lead point (3.10c).
    Blitzing gives up an open receiver, which corrects itself.
16. **Two defenders tackle on the same tick:** one tackle, credited to the earlier timestamp.
17. **Client shows a catch, server says no:** the server wins. The client corrects
    with a bobble animation and shows the reason tag.
18. **Carrier stalls behind the LOS / runs backward:** [PLAY_MAX_DURATION] ends
    the play at the current spot. Ending in own end zone = safety.
19. **Endless evade chain:** [EVADE_CHAIN_MULT] stretches cooldowns. Stumble
    blocks moves. Gang tackle finishes it.
20. **Receiver calls for ball at the snap every play:** allowed. A short Bullet
    to a covered receiver is a fair contest for the defender.

---

## 6. Dependencies


| System | Direction | Contract |
|---|---|---|
| Input (keyboard/gamepad/touch) | Feeds this | Produces Throw/Catch/Tackle/Snap *intents*; never outcomes. Mobile gets a catch-assist button, validated with the same rules. |
| Movement (momentum controller) | Feeds this / constrained by this | Client-simulated (Roblox default character ownership). Publishes its max-speed/boost caps to `NetConfig` so MovementSanity can check them. |
| Animation | Consumes | Optimistic local anims (reach, dive, tackle lunge); server result triggers confirm or "bobble/whiff" fallback. |
| Camera | Consumes | Follows the client-rendered ball and carrier. No authority. |
| HUD / Scoreboard | Consumes | Reads replicated attributes only (score, down, possession, play clock). |
| Match / Mode Manager | Bidirectional | Owns modes (1v1, 2v2, 5v5), downs, clock, forfeits. Receives `PlayResult` from this system; tells it who is QB and when a play may start. |
| AI QB (1v1) | Feeds this | Server-side; calls `BallAuthority.Throw()` directly through the same validated path as human QBs. |
| Matchmaking / Lobby (later) | Feeds Mode Manager | Not a direct dependency; provides team rosters. |
| DRIP STORE cosmetics | Consumes | Ball skins, trails, celebration anims. Cosmetic only; never affects hitboxes, [CATCH_RADIUS], or speed. |

### 6.1 Networking & Authority Model

#### Targets
Fair at 50–250 ms round-trip ping; the 250 ms ceiling is this doc's latency target. Every tunable lives in `NetConfig`, never in code.

#### Core rule
The server is the only authority on **possession, ball state, catch/tackle results, spots, and score**. Clients send *intents* with a server-time timestamp. The server validates and broadcasts outcomes. There are no remotes that let a client set possession, score, or ball position.

#### Ball state machine (server-owned, `BallAuthority`)

| State | Data | Exits |
|---|---|---|
| `DEAD` | spot, outcome | Mode Manager starts play → `SNAPPED` |
| `SNAPPED` | spot, center/QB ids | `SnapIntent` from QB (or AI/play clock) → `HELD(QB)` |
| `HELD` | carrierUserId | `ThrowIntent` from carrier (behind LOS rules per design) → `IN_FLIGHT`; valid tackle → `DEAD(tackled)`; carrier crosses goal line → `DEAD(TD)`; out of bounds → `DEAD(OOB)`; fumble (design rule) → `LOOSE`; carrier leaves → `DEAD(spot)` |
| `IN_FLIGHT` | launch packet (see below) | first valid `CatchIntent` → `CONTESTED`; arc hits ground → `DEAD(incomplete)` |
| `CONTESTED` | claims list, window end time | window closes → `HELD(winner)` or `DEAD(incomplete)` / `LOOSE` per jump-ball rule |
| `LOOSE` | bounce segment packet | valid recovery intent → `HELD`; rest/timeout → `DEAD` |

Each transition increments `seq`; each play has a `playId`. Intents carrying a stale `playId` or an illegal-for-state action are dropped.

#### In-flight ball: deterministic arc (recommended)

On a validated throw the server computes launch values and broadcasts one reliable packet:

`BallLaunched { playId, seq, t0 = Workspace:GetServerTimeNow(), p0: Vector3, v0: Vector3, g: number, throwerId }`

Position at any server time `t`: `p(t) = p0 + v0·(t−t0) + ½·g·(t−t0)²` (shared pure module `BallArc`, used by server and all clients). Landing time is solved analytically.

**Why this rather than physics/network ownership:**
- Giving a client network ownership of the ball (`SetNetworkOwner(player)`) lets that client move it anywhere. That's an exploit by design.
- A server-owned physics ball (`SetNetworkOwner(nil)`) is safe but arrives on clients late and jittery. Each client sees it at a different place, which is exactly what makes contested catches feel unfair.
- A fixed arc is evaluated *identically* by everyone for any given server time. It costs one packet per throw, keeps working through a server hitch, and can be rewound exactly for lag compensation.

**Rendering:** there is no replicated physical ball. Each client spawns a local, anchored, non-colliding visual ball. During `HELD` it's attached to the carrier's hand rig. During `IN_FLIGHT` it's placed every RenderStepped at `BallArc.eval(GetServerTimeNow())`, with the local time clamped so it never runs backwards. The thrower plays the release instantly and blends into the server arc over `THROW_BLEND_TIME`. If the server rejects the throw, the visual snaps back to the hand. Loose-ball bounces use the same approach: each bounce is a new arc segment packet.

#### Lag compensation: position history
`PositionHistory` records every player's server-observed HumanoidRootPart position and velocity each Heartbeat into a ring buffer (`HISTORY_SECONDS`, starting value 1.0 s). Because clients own their characters, the server's copy of a player lags their own view by about one-way latency. Checks therefore compare the client's *claimed* position to the server's history over a window, not to a single sample.

#### Catch validation
Client sends `CatchIntent { playId, tClaim, claimedPos }` when the local ball is within [CATCH_RADIUS] of the local hands and catch is pressed or auto-assisted. The server rejects the claim unless all of these hold:
1. State is `IN_FLIGHT` or `CONTESTED` with a matching `playId`.
2. `now − [LATENCY_GRACE] ≤ tClaim ≤ now + CLOCK_SLACK` (no claims from the future, nothing older than grace).
3. `|claimedPos − history(player, around tClaim)| ≤ POS_TOLERANCE`. The search window runs from tClaim to tClaim + the player's measured one-way latency.
4. `|BallArc.eval(tClaim) − claimedPos| ≤ [CATCH_RADIUS] + CATCH_SLACK`.

Backdating `tClaim` doesn't help a cheater. The ball was somewhere else at the earlier time, so check 4 fails, and grace caps how far back a claim can go anyway.

#### Contested catches (jump balls)
The first valid claim moves the ball to `CONTESTED` and opens a window of [CATCH_WINDOW] by server time. The window closes no earlier than the first claim's arrival + [LATENCY_GRACE], so a 250 ms player's claim can still land. Every valid claim inside the window is collected. Ping doesn't decide who wins, because claims are compared by their `tClaim` in server time, not by arrival order:
- Claims more than [CATCH_WINDOW] apart: the earliest `tClaim` wins.
- Claims within [CATCH_WINDOW] of each other count as simultaneous. A **jump-ball rule** decides (e.g. distance to ball centre at `tClaim`, vertical reach, body position, then a fixed tie-break). *That rule is a game-designer decision; networking supplies the inputs.*

Clients play an optimistic "reach/contested" animation right away but show no possession HUD until `PlayResult` arrives.

#### Tackle validation
`TackleIntent { playId, targetUserId, tClaim, claimedPos }`. The server checks that the state is `HELD` by the target, the time window is the same as for catches, and the defender's claimed position matches their history. It then checks `|claimedPos − history(target, tClaim)| ≤ [TACKLE_RANGE] + TACKLE_SLACK`.

Tackles never rely on physics contact. Characters owned by different clients collide inconsistently. Order is decided by timestamp: if the carrier's validated history shows them over the goal line before `tClaim`, the TD stands. The ball is spotted at the carrier's history position at `tClaim`. The `[LATENCY_GRACE]` cap limits how far "tackled from behind after I'd already passed" can stretch for a low-ping carrier.

#### Anti-exploit rules
- **No outcome remotes.** Score, possession, spot, and down are written only by server modules.
- **Movement sanity (`MovementSanity`):** each Heartbeat, displacement/dt is checked against the movement caps × `SPEED_TOLERANCE` (starting value 1.25), with vertical limits for jumps. Over-limit frames add strikes. At `STRIKE_LIMIT` the server snaps the character back to the last good position. Sustained violations get logged and flagged. The server can't *prevent* client movement, only detect and correct it.
- **Server owns WalkSpeed/JumpPower** values; client-side edits are caught by the position check, not trusted.
- **`RemoteGuard`** wraps every remote: per-player token bucket rate limits; `typeof` checks; rejects NaN/inf (`x ~= x`); bounds-checks vectors to field size; `playId`/`seq` checks. Rejects are counted and logged with a rate limit (one summary per player per `LOG_INTERVAL`).
- Starting rate limits (`NetConfig`): Throw 2/s, Snap 2/s, Catch 6/s, Tackle 6/s, AimPreview 20/s.
- **AI QB** runs on the server only; its throw lead uses the server's view of the receiver plus their estimated latency.

#### Replication: what, how, priority

| Tier | Data | Mechanism |
|---|---|---|
| 1 – must arrive, state | ball `State`, `CarrierUserId`, `PlayId`, `Seq`, score, down, clock | **Attributes** on a server-owned `ReplicatedStorage.Football.MatchState` folder (change-driven, readable by late joiners) |
| 1 – must arrive, events | `BallLaunched`, `PlayResult {playId, outcome, winnerId, spot}`, bounce segments | **RemoteEvent** (reliable). The launch packet is also mirrored into attributes for late joiners. |
| 2 – client→server intents | Snap/Throw/Catch/Tackle intents | **RemoteEvent** (reliable). Losing a catch claim is worse than a few bytes. |
| 3 – cosmetic | QB aim preview, "hands up" pose, emotes | **UnreliableRemoteEvent**, latest-wins, keep payloads small |

Clients ignore events whose `seq` is older than the current attribute `Seq`. Attribute changes and remote events aren't guaranteed to arrive in a set order relative to each other.

**Bandwidth (custom traffic only; Roblox's character replication is extra and engine-managed):** launch packet ≈ 60–80 B per throw; intents ≈ 30–50 B each; attribute changes are a handful per play. Budget: ≤ 1.5 KB/s down and ≤ 0.5 KB/s up per player at 5v5, dominated by tier-3 aim preview (≈ 20/s × ~24 B, sent only to the QB's teammates during the pre-throw phase). Server Heartbeat drives the history and sanity checks at ~60 Hz; nothing ball-related is streamed per frame.

#### Script / module layout (Practice Field → 5v5)

ReplicatedStorage/Football/
- `NetConfig` (ModuleScript): every tunable and placeholder value.
- `BallArc` (ModuleScript): pure arc and landing-time math shared by server and client.
- `BallStates` (ModuleScript): state enum plus legal transition table.
- `Schema` (ModuleScript): payload shapes and type validators.
- `Remotes/` (Folder): `SnapIntent`, `ThrowIntent`, `CatchIntent`, `TackleIntent`, `BallLaunched`, `PlayResult` (RemoteEvents); `AimPreview` (UnreliableRemoteEvent).
- `MatchState` (Folder): replicated attributes.

ServerScriptService/Football/
- `FootballServer` (Script): bootstrap; wires remotes to modules.
- `BallAuthority`: owns the state machine; the only writer of ball state.
- `PositionHistory`: per-player ring buffer for lag compensation.
- `CatchResolver`: validates claims, runs contested windows.
- `TackleResolver`: validates tackles and computes spots.
- `MovementSanity`: speed/teleport checks and corrections.
- `RemoteGuard`: rate limits and payload validation.
- `PlayController`: play lifecycle; reports `PlayResult` to the Mode Manager.
- `AIQuarterback`: 1v1 AI QB; throws via `BallAuthority`.

StarterPlayer/StarterPlayerScripts/Football/
- `FootballClient` (LocalScript): bootstrap; reads attributes and listens to events.
- `BallView`: local visual ball (hand attach, arc replay, blends).
- `IntentSender`: builds timestamped intents from input (incl. mobile assist).
- `ContestFeedback`: optimistic anims plus confirm/reject fallbacks.

Practice Field uses the same modules with one human and the AI QB. Scaling to 5v5 changes rosters and Mode Manager rules, not this layout.

#### Networking edge cases
- **Carrier disconnects while holding:** on `PlayerRemoving`, the ball goes to `DEAD` at the carrier's last validated position. The Mode Manager decides forfeit/sub/AI fill.
- **QB disconnects pre-snap / mid-throw:** before release → `DEAD`, play reset. After release the arc is already server-owned and the play continues.
- **Claimant disconnects inside a contested window:** their claim is dropped; the remaining claims are resolved normally.
- **Two catch claims in the same server frame:** arrival order doesn't matter; both go into the window and are ordered by `tClaim`. If they're within [CATCH_WINDOW], the jump-ball rule decides.
- **High-ping player (>250 ms or spiking):** claims older than [LATENCY_GRACE] are rejected. Grace isn't extended for one player because that hurts their opponent. Show a ping indicator. Rejected claims play a "bobble" animation so the result reads as a play, not a bug.
- **Server hiccup:** arcs are evaluated from server time, not frame counts, so clients keep rendering correctly and the server catches up on resume. Position-history gaps are interpolated. Speed checks are skipped across gaps longer than `HICCUP_SKIP` to avoid false strikes. Contested windows close by time, not frames.
- **Client clock not settled after join:** intents are ignored for `JOIN_SETTLE_TIME`, or while the player's claim/history mismatch rate stays high.
- **Stale intents across plays:** dropped by `playId`/`seq`.
- **Exploiter spoofing timestamps/positions:** limited by grace, history comparison and the arc geometry check; repeat offenders get logged and flagged for security-engineer review.

#### Open questions
- Jump-ball tie-break rule and fumble rules (game-designer).
- Strike thresholds and what action follows them (security-engineer).
- Whether mobile catch-assist gets the same [CATCH_RADIUS] (design + security).

#### API notes to verify in Studio before build
- Client-side accuracy of `Workspace:GetServerTimeNow()` right after joining (draft clamps time so it never runs backwards).
- Whether a server write to a client-owned `HumanoidRootPart.CFrame` reliably overrides the client.
- `UnreliableRemoteEvent` payload limit (believed ~900 bytes) and lack of ordering.
- Server Heartbeat rate (~60 Hz) and per-client bandwidth limits (commonly quoted ~50 KB/s).

---

## 7. Tuning Knobs

All knobs live in `FootballConfig` (UPPER_SNAKE keys as below). Per-mode overrides are allowed (e.g. Practice mode can set STAMINA_DRAIN = 0).

### 7.1 Movement

| Knob | Starting value | Safe range | What it affects (and why this value) |
|---|---|---|---|
| [JOG_SPEED] | 16 studs/s | 14–18 | Base run speed. Matches Roblox default, so it feels familiar on first spawn. |
| [SPRINT_SPEED] | 24 studs/s | 20–30 | Top speed. 1.5× jog: clearly faster, still catchable by ball speeds ≥ 34. |
| TAU_ACCEL | 0.25 s | 0.15–0.40 | Burst feel. 90% of top speed in ~0.6 s: arcade-snappy but momentum still matters. |
| TAU_DECEL | 0.15 s | 0.10–0.25 | Stopping. Faster than accel because floaty stops feel like lag. |
| TURN_RATE_SLOW | 720 °/s | 540–900 | Turning at low speed. Near-instant facing when set; good for QBs in the pocket. |
| TURN_RATE_FAST | 220 °/s | 150–300 | Turning at sprint. A 6.25-stud radius makes full-speed cuts cost something. |
| TURN_CURVE_EXP | 1.5 | 1.0–2.0 | Where stiffening kicks in. Agile until ~2/3 speed. |
| CUT_THRESHOLD | 35° | 25–50 | Above this a turn becomes a plant. Lower = more cuts trigger penalties. |
| CUT_MAX_ANGLE | 135° | 120–150 | Above this you must brake. This enforces "no instant flips". |
| CUT_PLANT_TIME | 0.10 s | 0.06–0.15 | Plant animation length. Enough to read, short enough not to feel stuck. |
| CUT_PENALTY_K | 0.9 | 0.6–1.2 | Cut severity. A 90° sprint cut keeps 55%. |
| CUT_RETAIN_MIN | 0.35 | 0.25–0.50 | Floor on cut speed so sharp cuts don't feel like a full stop. |
| PIVOT_SPEED | 4 studs/s | 2–6 | Speed below which you can reverse freely. |
| STAMINA_MAX | 100 | fixed | Scale reference. Tune the drain/regen knobs instead. |
| STAMINA_DRAIN | 18 /s | 12–25 | Sprint duration: 5.6 s, about one deep route plus a short run after the catch. |
| STAMINA_REGEN_MOVE | 20 /s | 10–30 | Jogging recovery. About 1 s jogging buys 1 s of sprint. |
| STAMINA_REGEN_IDLE | 35 /s | 20–50 | Huddle refill. Full bar in under 3 s, so normal plays start fresh. |
| STAMINA_REGEN_DELAY | 0.5 s | 0.3–1.0 | Stops sprint-feathering exploits. |
| STAMINA_UNLOCK | 30 | 15–40 | Exhaustion lockout. Hitting 0 costs ~1.5 s of no sprint. |
| JUKE_SPEED_RETAIN | 0.85 | 0.75–0.95 | Juke value vs a raw cut (0.55). |
| JUKE_LATERAL_SPEED | 20 studs/s | 14–26 | Sidestep size: 3.6 studs, just clears the wrap cone. |
| JUKE_DURATION | 0.18 s | 0.12–0.25 | Snap of the juke. |
| JUKE_COOLDOWN | 1.8 s | 1.2–3.0 | At most ~2 jukes per typical run. |
| JUKE_STAMINA_COST | 10 | 5–15 | Ties moves to the sprint economy. |
| SPIN_SPEED_RETAIN | 0.80 | 0.65–0.90 | Spin is slower than a juke but beats wraps. |
| SPIN_DURATION | 0.40 s | 0.30–0.50 | Long enough to be readable and punishable by a dive. |
| SPIN_COOLDOWN | 3.0 s | 2.0–4.0 | Spin is the stronger move, so it gets the longer cooldown. |
| SPIN_STAMINA_COST | 12 | 6–18 | Costs slightly more than a juke. |
| MOVE_GLOBAL_LOCKOUT | 0.5 s | 0.3–0.8 | Blocks juke→spin→stiff-arm chaining in one instant. |

### 7.2 Passing

| Knob | Starting value | Safe range | What it affects (and why this value) |
|---|---|---|---|
| BULLET_SPEED / RANGE | 70 / 45 | 60–85 / 35–55 | Fast and flat (25 studs ≈ 0.36 s) for tight windows. |
| LEAD_SPEED / RANGE | 50 / 60 | 42–60 / 45–70 | Default throw. About 2× sprint speed, so leads always converge on the receiver. |
| LOB_SPEED / RANGE | 34 / 75 | 28–40 / 60–90 | Hang time for jump balls. Must stay > SPRINT_SPEED or lead math breaks. |
| THROW_CHARGE_TIME | 0.6 s | 0.4–0.9 | Hold length for full lob. |
| THROW_WINDUP | 0.20 s | 0.10–0.30 | Release delay. Gives defenders a read and is included in the lead math. |
| LEAD_BIAS | 1.0 stud | 0–2.5 | Ball lands just ahead of the hands, giving an in-stride catch. |
| RECEIVER_VEL_SMOOTH | 0.15 s | 0.08–0.30 | Aim stability against last-instant jukes. |
| BALL_INHERIT_QB_VEL | 0 | 0–0.5 | Arcade aim. Raise toward realism later. |
| G_BALL | 80 studs/s² | 50–120 | Arc shape. Workspace 196 is too loopy. |
| H_RELEASE | 5.0 studs | 4.5–5.5 | Over-the-head release. |
| LOB_TARGET_HEIGHT | 8.5 studs | 7.5–9.5 | High-point: above standing reach (6.5), inside jump reach (9.0). |
| SPREAD_BASE | 0.5° | 0.2–1.0 | Clean-throw error. Near-perfect, which rewards a set QB. |
| SPREAD_MOVE | 2.5° | 1.5–4.0 | On-the-run cost. |
| SPREAD_PRESSURE | 3.5° | 2.0–5.0 | Pass-rush value. Pressure has to matter. |
| SPREAD_OFF_PLATFORM | 2.0° | 1.0–3.0 | Throwing across your body. |
| PRESSURE_RADIUS / SACK_RADIUS | 12 / 3 studs | 9–15 / 2–4 | Where pressure starts and maxes. |
| AI_READ_START | 0.9 s | 0.6–1.4 | 1v1 drop-back. Gives the receiver time to make a first move. |
| SEP_START | 7 studs | 5–9 | AI patience early. Wide open = immediate throw. |
| SEP_DECAY | 2.0 studs/s | 1.5–4.0 | How fast the AI settles for less separation. |
| SEP_MIN | 2.0 studs | 1–3 | Contested floor (~half CONTEST_RADIUS). |
| AI_MAX_HOLD | 3.2 s | 2.5–4.0 | Forced throw so plays never stall. |
| AI_REACTION | 0.15 s | 0.08–0.30 | Human-like delay. Also a difficulty knob. |
| AI_JITTER | ±0.10 s | 0–0.2 | Breaks timing exploits. |
| AI_TICK | 0.05 s | 0.03–0.1 | Decision re-check rate. |

### 7.3 Catching and jump balls

| Knob | Starting value | Safe range | What it affects (and why this value) |
|---|---|---|---|
| [CATCH_RADIUS] | 3.0 studs | 2.5–4.0 | Catchable zone (~0.85 m). Generous arcade hands, still tighter than 2σ misses. |
| DIVE_CATCH_RADIUS | 5.0 studs | 4.0–6.0 | Dive reach. Turns ~50% throws into ~85% at a drop cost. |
| [CATCH_WINDOW] | 0.40 s (−0.30/+0.10) | 0.25–0.55 | Secure-press window. Biased early because you get hands up before the ball arrives. |
| DROP_BASE | 0.01 | 0–0.03 | Clean-catch drop floor. |
| DROP_OVER_SHOULDER | 0.03 | 0–0.06 | Small cost for over-the-shoulder. Go routes stay viable. |
| DROP_REACH_BACK | 0.08 | 0.04–0.12 | Thrown behind the receiver, which rewards accurate leads. |
| DROP_HOT_BALL / HOT_BALL_MIN / SPAN | 0.06 / 45 / 30 | — | Point-blank bullets get harder to catch. |
| DROP_DIVE | 0.06 | 0.03–0.10 | Cost of the extra reach. |
| DROP_HIT / HIT_WINDOW | 0.10 / 0.25 s | 0.05–0.15 / 0.15–0.35 | Big hit on the catch. Negated by securing. |
| DROP_SECURE | 0.04 | 0.02–0.06 | Secure press. Large enough to zero a clean ball. |
| DROP_MAX | 0.25 | 0.15–0.30 | Cap that keeps drops rare. |
| INT_DROP_BASE | 0.15 | 0.05–0.25 | Defender hands are worse, so uncontested INTs stay earned. |
| CONTEST_RADIUS | 4.0 studs | 3.0–5.0 | Distance at which a catch becomes a jump ball. |
| JUMP_HEIGHT | 2.5 studs | 2.0–3.0 | Catch jump. Workspace default (~6.4) is too high for football. |
| JUMP_APEX_TIME | 0.30 s | 0.25–0.40 | Time to the top of the jump. Long enough to aim the timing. |
| REACH_STAND | 6.5 studs | fixed per body | Standing hand height (standard body). |
| [JUMPBALL_TIMING_WINDOW] | 0.25 s | 0.15–0.35 | Falloff from perfect to zero timing credit. Main skill-ceiling knob. |
| JUMPBALL_PERFECT_BAND | 0.04 s | 0.02–0.06 | Full credit band. Absorbs frame and timestamp jitter. |
| BOXOUT_BONUS / BOXOUT_ANGLE | 0.25 / 35° | 0.15–0.35 / 25–45° | Value of body position. |
| HEIGHT_TOL | 2.5 studs | 1.5–3.5 | Penalty for hands below the ball. |
| W_TIMING / W_POSITION / W_HEIGHT | 0.45 / 0.35 / 0.20 | must sum to 1 | Skill mix. Timing-led. |
| TIE_MARGIN | 0.08 | 0.04–0.12 | Ties go to the receiver; prevents coin-flip edges. |
| INT_THRESHOLD | 0.60 | 0.5–0.75 | Winning defender below this = PBU, not INT. |

### 7.4 Tackling and fumbles

| Knob | Starting value | Safe range | What it affects (and why this value) |
|---|---|---|---|
| [TACKLE_RANGE] | 4.0 studs | 3.0–5.0 | Wrap reach (~body + arms). Paired with juke size 3.6. |
| WRAP_CONE_HALF | 60° | 45–75° | Wrap needs facing, which rewards tackling angles. |
| WRAP_STARTUP / MISS_RECOVERY | 0.10 / 0.40 s | 0.05–0.15 / 0.3–0.6 | Commitment cost of whiffing. |
| DIVE_TACKLE_RANGE | 9.0 studs | 7–11 | Long reach for a last-ditch dive. |
| DIVE_LUNGE_SPEED / TIME | 30 / 0.30 s | 26–34 / 0.25–0.35 | Covers ~9 studs, faster than sprint. |
| DIVE_MISS_RECOVERY | 1.0 s | 0.8–1.5 | A whiffed dive takes you out of the play. |
| BREAK_BASE_WRAP / DIVE | 0.10 / 0.25 | 0.05–0.2 / 0.15–0.35 | A dive trades extra reach for being easier to break. |
| BREAK_MOMENTUM_K | 0.15 | 0.08–0.25 | Speed wins collisions. |
| BREAK_ANGLE_K | 0.15 | 0.08–0.25 | Chasing arm tackles are weak. |
| [STIFFARM_WINDOW] | 0.30 s | 0.20–0.40 | Active window. Fits typical 0.1–0.2 s contact reads. |
| STIFFARM_PEAK | 0.15 s | ½ window | Mid-window sweet spot. |
| SA_BONUS_MIN / SCALE | 0.15 / 0.30 | 0.1–0.2 / 0.2–0.4 | Max +0.45. The single biggest skill lever for the carrier. |
| STIFFARM_COOLDOWN | 2.5 s | 1.8–3.5 | Whiffs pay the full cooldown, so spamming is punished. |
| STIFFARM_SPEED_RETAIN | 0.90 | 0.8–0.95 | Small cost to stiff-arm. |
| SPIN_BREAK_BONUS_WRAP / DIVE | 0.20 / 0.10 | 0.1–0.3 / 0.05–0.15 | Spin beats wraps; dives beat spins. |
| BREAK_FATIGUE | 0.10 per break | 0.05–0.15 | Negative feedback that stops unstoppable runners. |
| BREAK_MIN / BREAK_MAX | 0.02 / 0.75 | 0–0.05 / 0.6–0.85 | Every tackle has a ≥25% chance to land. |
| TACKLE_RESOLUTION | "roll" | roll / threshold | Dice vs deterministic tackles. Playtest both. |
| [FUMBLE_CHANCE] | 0.01 | 0.005–0.02 | Base fumble on a completed tackle. Rare. |
| FUMBLE_BLINDSIDE / BIGHIT / GANG MULT | 2.0 / 1.5 / 1.5 | 1–3 | Each fumble has a visible cause. |
| FUMBLE_PROTECT_MULT | 0.25 | 0.1–0.5 | Protect-ball trades speed for security. |
| FUMBLE_CAP | 0.06 | 0.04–0.10 | Hard ceiling. |

### 7.5 Network and latency

| Knob | Starting value | Safe range | What it affects (and why this value) |
|---|---|---|---|
| [LATENCY_GRACE] | 0.20 s | 0.10–0.30 | Max rewind. Covers ~250 ms RTT one-way plus a share of interpolation. |
| INTERP_DELAY | 0.10 s | measured | Remote render lag used in the pad. |
| CATCH_PAD_MAX | 0.75 studs | 0.25–1.25 | Extra catch radius for high ping. |
| TACKLE_PAD_MAX | 1.5 studs | 0.5–2.0 | Extra tackle reach. Capped so tackles don't connect from far away. |
| CONTEST_RESOLVE_DELAY | 0.20 s | = LATENCY_GRACE | Wait so all inputs arrive before a jump ball resolves. |
| POSITION_HISTORY_LEN | 1.0 s | 0.5–2.0 | Rewind buffer depth. |
| SPEED_TOLERANCE | 1.10 | 1.05–1.20 | Anti-speedhack slack. |

---

## 8. Acceptance Criteria

### Stage 1: Movement (Practice Field, no ball)
- [ ] Jog/Sprint reach [JOG_SPEED]/[SPRINT_SPEED] within ±5% after the accel time. No instant velocity changes.
- [ ] Turns past [CUT_ANGLE_THRESHOLD] at speed play a Cut and exit at [CUT_SPEED_RETENTION] of speed.
- [ ] Stamina drains and regenerates per knobs. Sprint at 0 stamina behaves as Jog.
- [ ] Juke/Spin/Stiff-arm trigger with correct durations and cooldowns. Spin and Stiff-arm only work while carrying a test ball.
- [ ] All values load from external config. Changing a value needs no code change.
- [ ] Same movement works on KB/M, gamepad and touch on a phone-sized screen.
- [ ] Playtest: 3 of 3 testers describe movement as "weighty but responsive", not "boxy" or "floaty".

### Stage 2: Ball States + Passing/Catching (no defender)
- [ ] The ball is never a physics-owned part. The server log shows every state transition, with only legal transitions (3.3).
- [ ] Touch, Bullet and Lob produce distinct arcs and speeds, and look the same on all clients.
- [ ] A Touch pass to a receiver running straight at constant speed lands within [BASE_THROW_ERROR] of the receiver's catch point.
- [ ] On-run and pressure error apply only when their conditions are met.
- [ ] Uncontested catches in the window succeed 100% (except the facing-angle Bullet drop rule).
- [ ] Dive catch works only inside the reach band and ends in a whistle at the landing spot.
- [ ] Ground or out-of-bounds contact → incomplete → ball returns to the previous spot.
- [ ] Aim works on all three input types and sends identical server requests for an equivalent throw.
- [ ] At 150 ms simulated latency, server and client agree on catch/no-catch in ≥95% of 100 scripted reps.

### Stage 3: Defender + Tackling
- [ ] Wrap and Dive connect only within range. Miss penalties apply.
- [ ] Every cell of the counter matrix (3.7) produces its listed result in a scripted test.
- [ ] Momentum break and gang tackle trigger only under their conditions.
- [ ] Fumbles happen only on Dive-vs-Spin/Juke-recovery. 0 fumbles across 200 scripted wrap tackles.
- [ ] Loose ball recovery and timeout work. A Caught-state hit = incomplete.
- [ ] Contested resolution follows timing > position > body state. The reason tag shows for both players.
- [ ] Playtest: in 20 contested reps, both players can explain why they won or lost in ≥80% of reps.

### Stage 4: 1v1 with AI QB
- [ ] The full play cycle runs Ready → Snap → Live → Whistle → Spot without manual resets.
- [ ] Downs, first downs, TD, safety, turnover on downs and possession swap all score correctly.
- [ ] A win is only declared at a round boundary. Overtime resolves a tie.
- [ ] The AI QB fires on each trigger (a)–(d) and picks the throw type per the rules. Identical behavior for both players (logged).
- [ ] Defender crossing the LOS → instant throw. The QB is never sacked.
- [ ] Disconnect mid-play whistles the play dead and starts the rejoin grace.
- [ ] Playtest: across 10 matches, receiver-side and defender-side win rates per play are both within [FAIRNESS_BAND] of 50%.

### Stage 5: Jump Balls + Route Practice Polish
- [ ] Forced and deep throws produce contested jump balls. High-point timing visibly changes outcomes.
- [ ] Ties go to the offense. Interceptions need a margin above [INT_MARGIN].
- [ ] Route Practice: all 8 routes are selectable, the ghost line toggles, reset is instant, per-rep and session stats are correct.
- [ ] Route Practice runs with no defender, no tackling and no score UI.
- [ ] Playtest: a new player completes 10 Route Practice reps without outside help and can name a route they improved on.
- [ ] No purchasable item changes any value in this document (audit config and the shop catalog).

---

## OPEN-DECISIONS (resolve before Stage 2 build)

The three sections of this spec were drafted in parallel and then merged. These
are the places where they disagree or where a value is still missing. Nothing
should be coded against a conflicted rule until it is settled.

### A. Real conflicts — pick one side

| # | Conflict | §3 (rules) says | §4 (formulas) says | Recommendation |
|---|---|---|---|---|
| A1 | **Dropped catches** | Uncontested catches are automatic and deterministic. The only drop is a Bullet caught while facing away. | Every catch rolls a drop chance (0–25%) from several added factors: over-shoulder, reach-back, hot ball, diving, hit on the catch. | Go with §4, but keep §3's promise: clean + secured + in-stride = exactly 0%. Drops only appear on balls the player can see are hard. |
| A2 | **Jump-ball randomness** | Score includes a small random tiebreak (`[CONTEST_RNG_WEIGHT]`). | Fully deterministic — no dice at all. | Go with §4 (no dice). Fairness and "I know why I lost" matter more than variety. Delete `[CONTEST_RNG_WEIGHT]`. |
| A3 | **When fumbles can happen** | Only when a Dive tackle hits a Spin or juke-recovery. Wraps and sacks never fumble. | Any completed tackle can fumble (1% base), multiplied by blindside / big hit / gang tackle. | Decide: §3 is tighter and more predictable; §4 is more realistic and still ~1-in-50. Either works, but the code must only implement one. |

### B. Same knob, two names — one naming pass needed

| §3 name | §4 name |
|---|---|
| `[WRAP_RANGE]` | `TACKLE_RANGE` |
| `[DIVE_RANGE]` | `DIVE_TACKLE_RANGE` |
| `[CUT_ANGLE_THRESHOLD]` | `CUT_THRESHOLD` |
| `[CUT_SPEED_RETENTION]` | `CUT_PENALTY_K` + `CUT_RETAIN_MIN` |
| `[SPRINT_TURN_RATE]` | `TURN_RATE_FAST` |
| `[JOG_ACCEL]` / `[SPRINT_ACCEL]` | `TAU_ACCEL` (one time constant covers both) |
| `[TOUCH_SPEED]` | `LEAD_SPEED` |
| `[JUMP_REACH]` | `JUMP_HEIGHT` |
| `[JUMP_TIMING_WINDOW]` | `JUMPBALL_TIMING_WINDOW` |
| `[SPIN_SPEED_RETENTION]` | `SPIN_SPEED_RETAIN` |
| `[SPRINT_STAMINA_MAX]` | `STAMINA_MAX` |
| `[BASE_THROW_ERROR]` / `[ON_RUN_ERROR]` / `[PRESSURE_ERROR]` | `SPREAD_BASE` / `SPREAD_MOVE` / `SPREAD_PRESSURE` |
| `[AI_QB_MAX_HOLD]` | `AI_MAX_HOLD` |
| `[AI_QB_ACCURACY_ERROR]` | `SPREAD_BASE` (AI uses base only) |
| `[OPEN_SEPARATION]` | `SEP_START` / `SEP_DECAY` / `SEP_MIN` |
| `[LAG_COMP_MAX]` | `LATENCY_GRACE` |
| `[EVADE_CHAIN_MULT]` | partially replaced by `BREAK_FATIGUE` — **keep both?** (one stretches cooldowns, the other lowers break chance) |

Resolution: §4's names win, since the config module uses them. §3 gets a find-and-replace.

### C. Still has no number

These were named in the rules but never given a value. All are play-cycle, scoring
or mode knobs rather than physics, so they are quick to fill but need Don's call on
match shape.

- **Scoring / match:** `DRIVE_START_DISTANCE`, `DOWNS_PER_SERIES`, `FIRST_DOWN_DISTANCE`, `TD_POINTS`, `SAFETY_POINTS`, `WIN_SCORE`, `MATCH_TIME`, `OT_DISTANCE`
- **Play cycle timings:** `SNAP_TIME`, `READY_TIMEOUT`, `AUTO_SNAP_TIME`, `BETWEEN_PLAY_TIME`, `PLAY_MAX_DURATION`, `LOOSE_BALL_MAX_TIME`, `CATCH_SECURE_TIME`
- **Recovery states:** `GROUNDED_DURATION`, `STUMBLE_DURATION`, `STUMBLE_SPEED_LOSS`, `WRAP_MISS_SLOW`, `STIFFARM_STUN`, `SPIN_ACTIVE_WINDOW`, `STIFFARM_ACTIVE`, `STIFFARM_CONE_ANGLE`
- **Field / ball:** `OOB_HEIGHT`, `RECOVER_RADIUS`, `BREAK_SPEED_DELTA`, `DIVE_CATCH_REACH` (vs `DIVE_CATCH_RADIUS` = 5.0)
- **Aim:** `AIM_ASSIST_RADIUS`, `PLACEMENT_MAX_OFFSET`, `BULLET_CHARGE_TIME`, `SHORT_THROW_DIST`, `DEEP_THROW_DIST`, `CATCH_FACING_ANGLE`
- **Jump ball:** `INT_MARGIN` (vs `TIE_MARGIN` = 0.08), `CONTEST_TIE_EPSILON`
- **Practice / QA:** `PRACTICE_YAC_TIME`, `REJOIN_GRACE`, `FAIRNESS_BAND`, `JUKE_DISTANCE` (derived: 3.6 studs)

### D. Questions for Don

1. **Tackles: dice or no dice?** `TACKLE_RESOLUTION` can be `"roll"` (chance) or `"threshold"` (break if the computed chance is ≥ 50%, fully deterministic). Threshold is the fairest and matches the jump-ball approach, but every outcome becomes predictable. Default is `"roll"`; worth testing both.
2. **Same body size for everyone?** Proposed fairness rule: all avatars use one standard body scale for gameplay (hitbox, reach, jump), so no cosmetic or body type changes any hitbox. DRIP STORE items are visual only. Confirm.
3. **Can the receiver call for the ball in 1v1?** Proposed: yes, once separation is at least `SEP_MIN`. It is a strong skill hook but changes how 1v1 plays.
4. **Field position:** proposed that every drive starts at the same spot, with no carryover from where a turnover happened. Simpler and fairer, but loses field-position strategy.
5. **Sprint stamina:** proposed 5.6 s of sprint on a full bar, refilling during the huddle. Confirm you want a stamina meter at all.
6. **Touch controls have a lower ceiling:** phone players cannot fine-tune where a pass lands (no placement offset). Easier to play, but PC may have an edge in 2v2. Stage 4 playtests should measure it.
7. **Disconnects:** proposed forfeit after a short rejoin grace, with no bot replacement.

### E. Roblox API points to verify in Studio before Stage 2

Drafted against documented behaviour, but worth a 10-minute check in your own place:
- Accuracy of `Workspace:GetServerTimeNow()` on a client right after joining.
- Whether a server write to a client-owned `HumanoidRootPart.CFrame` reliably overrides the client.
- `UnreliableRemoteEvent` payload limit and lack of ordering.
- Server Heartbeat rate and per-client bandwidth limits.
