# Football — ruleset and ball physics research

> **Status: RESEARCH, 2026-11-02.** Every rule below was checked against the governing body's own document.
> Claims are marked **VERIFIED** (sourced) or **ASSUMPTION** (design inference). Where no sourced number exists —
> notably a published drag coefficient for a spiralling football — this document says so rather than inventing one.
> Sources are named inline; the full link list is in the research agent's transcript and should be appended here
> before this doc is used as a citation.

---

## 1. The recommended ruleset, in one sentence

**Use the IFAF Flag Football 5-on-5 rules as the base** — 45.72 × 22.86 m field with 9.14 m end zones, four downs
to a single midfield line to gain then four to score, every possession starting with a snap from the offence's own
4.57 m line with **no kicking at all**, TD 6 with a declared 1-point try from the 5 or 2-point try from the 10, and a
two-series midfield overtime — **with one deliberate, labelled deviation**: IFAF's no-contact chapter replaced by
NFHS/NCAA-style legal blocking and tackling (no blocks below the waist), plus a longer-lived fumble borrowed from
the contact small-sided codes.

### Why IFAF and not the alternatives
- It is the **only 5-on-5 code written by an international governing body** with a complete, self-consistent
  competition structure in one document. NFL FLAG is structurally near-identical but is a participation product
  (variable field sizes, a 30-point mercy rule) — a league convenience, not a ruleset to model.
- **Five-a-side is the native player count.** Scaling 11-a-side down means inventing exactly the rules you most
  need (how many on the line, who may rush, lateral spotting) — the silent blending the standard forbids.
- The two 5v5 codes **and** contact 7v7 independently agree on the three structural choices that matter most to a
  video game: no kicking, possession starts at the owner's own 5, one midfield line to gain. Convergence across
  three governing bodies is the strongest available signal.

### The labelled deviation — contact
IFAF explicitly prohibits blocking, tackling and kicking. This build wants arcade full contact, so the contact
chapter is replaced wholesale with 11-a-side norms as the small-sided contact codes already adapt them: clipping and
blocking below the waist banned at all times, holding banned with runner exceptions, blocking in the back permitted
under the 11-a-side rule. **Everything else in IFAF stands.** This is a deviation, not a blend.

---

## 2. Field, downs, scoring, restarts

### Field (metres — the codebase's unit)
| Element | Yards | Metres |
|---|---|---|
| Field of play | 50 | **45.72** |
| Width | 25 | **22.86** |
| End zone depth | 10 | **9.14** |
| Total length | 70 | **64.01** |
| No-run zone before each goal line | 5 | 4.57 |
| Safety area outside sidelines | 3 | 2.74 |
| Snap spot after a change of possession | own 5 | **4.57** |

National variations from 40–60 yd long and 20–30 yd wide are **inside the rules** — i.e. 35.6–54.9 m × 18.3–27.4 m —
which gives sanctioned room to size the 1v1 and 2v2 arenas without leaving the ruleset.

**Hash marks: none.** IFAF defines only a middle line; the ball is spotted where it is declared dead. On a 22.86 m
wide field hash marks would be an anachronism — **do not add them.**

### Downs — **first downs exist, and there is exactly one**
This is the clearest answer in the research, and it closes the project's "no first downs anywhere" gap.

A series is **4 consecutive scrimmage downs**, and the line to gain is **the middle of the middle line**. A new
series is awarded if the offence is beyond the middle when the ball is declared dead — the first time in the series —
or if an accepted penalty mandates a first down. Player-facing: **four plays to cross midfield, then four plays to
score.** Crossing midfield is the only way to earn a first down within a possession. No chains, no measurement
system. BAFA 7v7 is identical and notes there are no line-to-gain markers; a down box is recommended.

**Adopt exactly.** It is also the cheapest down system to render — one line on the field and a down counter — and
the only version that reads at a glance on a phone.

### Scoring — conversions exist and carry a real decision
Touchdown 6. Try from the 5 yd line = 1 point; from the 10 yd line = 2 points. Defensive touchdown on a try = 2.
Safety = 2 to the opponent; a safety on a try = 1 to the opponent.

Design value for free: the **1-point try from the 5 is pass-only, the 2-point try from the 10 may be run or pass, and
the offence declares its choice before the snap.** A genuine risk/reward decision, no new systems, no pay interaction.

### Restarts — **no kickoffs at all**
Coin toss at midfield decides who snaps first, from their own 5, and which side each team defends. The team that did
not start the first half snaps first in the second, also from its own 5. After a touchback, a safety, or a
touchdown: snap from the relevant team's own 5. Rookie Tackle confirms the pattern for contact — every possession
starts at a fixed yard line, no kickoffs, punts or field goals.

**This removes an entire subsystem** (kick meters, returns, special-teams AI) with full rules backing.

### Clock
IFAF: 40 minutes as two 20-minute halves, 2-minute intermission. In the **last 2 minutes of each half** the clock
stops for first downs, penalties, out-of-bounds, incomplete passes, scores and charged timeouts. Two charged
timeouts per half, non-carrying, up to 90 s.

**ASSUMPTION — the duration is a product decision, not a research finding.** Recommended: two halves of 4–6 real
minutes, running clock, IFAF's stop rules active only in the final 60 s of each half, 20–25 s play clock. Matches
must fit the 6–10 minute window a Roblox player gives a round. **Open question 1.**

### Possession changes and loose balls
- **Turnover on downs:** defence takes over at its own 5.
- **Interceptions:** defence gets it at the dead-ball spot as a new series; **returns stay live** until the ball is
  dead or out of bounds — the one exception to spotting at the 5, and the defence's only highlight.
- **Loose ball (IFAF):** a pass or fumble touching the ground makes the ball **dead**. A fumble touched by the
  fumbler's teammate before an opponent touches it is dead at the spot of the loss.
- **Contact codes keep it live longer:** Rookie Tackle has a fumble live until recovered or blown dead, with
  offensive players able to advance, but interception and defensive-recovery returns blown dead immediately.

**Recommendation:** ground = dead for passes (verified IFAF), but since this is contact, allow a **live fumble in the
air and for a short grace window on the ground** — a labelled deviation toward the contact codes, and the one place
arcade chaos earns its keep. **Open question 3.**

### Penalties — implement five, not dozens
| Foul | Enforcement | Why it matters |
|---|---|---|
| Defensive pass interference | +10 yd, automatic first down | The only thing stopping defenders running through receivers |
| Offensive PI / push-off | −10 yd, loss of down | Stops the same exploit from the offence |
| Defensive holding | automatic first down | Stops press being a hold |
| Offside / false start | −5 yd from the line of scrimmage | Makes the snap a real timing event |
| Unnecessary roughness / aiming | +10 yd, automatic first down | Keeps "full-contact arcade" from becoming a brawl |

Two conventions to copy verbatim: penalties are enforced from the line of scrimmage unless marked as spot fouls, and
**yardage is halved if it exceeds half the distance to the goal**. In small-sided contact codes, fouls that carry 15
yards in 11-a-side carry 10 — **there are no 15-yard penalties.**

A player who cannot name the foul that beat them reads it as unfair. Five is the budget.

### Overtime
IFAF: two-series shootout from the middle line, **no first down available at midfield**; if the defence scores in the
first series the period ends; later periods collapse to a 1-point try from the 5; no charged timeouts.
**Recommendation:** IFAF's midfield two-series period, then NFL FLAG's one-play try from period two onward.

---

## 3. Positions for 5-on-5

**Offence (real):** quarterback (receives the snap, passes or hands off, **cannot run with the ball after the
snap**); center (snaps, then may run a route as a receiver); wide receivers; running back (takes a handoff and runs
or throws, and can also catch).

**Defence (real):** defensive back (man or zone, intercepts); rusher (must start a set distance off the line —
note the source contradicts itself on that distance, giving both seven feet and seven yards, so **neither number is
verified**; IFAF no-run-zone geometry is the safer anchor); safety (deep, **less common in 5-on-5**).

Contact small-sided codes add structural constraints worth borrowing rather than inventing: exactly four on the line
of scrimmage, one defender at least 10 yd off with the rest 4 yd off, no trips formations, blitzing prohibited, and
players outside the guard-to-guard box at the snap may not rush the passer.

### Verdict on the existing slots
`QB/RUSH, X/CB, Z/CB, SLOT/NICKEL, RB/LB` is a good map and should mostly stand.

| Slot | Keep? | Note |
|---|---|---|
| QB / RUSH | Keep | Exactly the real pairing — but **someone must snap.** In a 5-player offence the center snaps then runs a route. **This is the one genuine gap in the current list.** See open question 2. |
| X / CB | Keep | Outside receiver vs press corner — the archetype with the most skill expression |
| Z / CB | Keep, **differentiate** | Z should be off-the-line and motion-capable, not a mirror of X, or two of five slots are identical |
| SLOT / NICKEL | Keep | Highest-value slot in 5v5: two-way leverage, shortest routes, most touches |
| RB / LB | Keep | Real on both sides; LB is the only defender playing run and pass equally |
| SAFETY | **Do not add as a sixth** | Less common in 5-on-5. Make it a *role toggle* on the LB or a CB |

**AI fill:** acceptable for CENTER (snap then a fixed route), RUSH (one timed path with a depth constraint) and deep
CB (cushion maintenance). **Avoid AI on SLOT and NICKEL** — they require reading leverage, which is the actual skill
ceiling. The 1v1 AI QB works precisely because QB AI executes one decision on a timer.

---

## 4. Ball physics — config-ready

### Verified specification
Official (NFL Football Operations): long axis 11–11¼ in, long circumference 28–28½ in, short circumference
21–21¼ in, weight 14–15 oz, inflation 12½–13½ psi. In SI: **0.279–0.286 m long, 0.397–0.425 kg, 86–93 kPa.**
Flight literature uses **mass 0.411 kg, semi-major a = 0.141 m, semi-minor b = 0.086 m, a/b = 1.618**.

Moments of inertia (only needed if the nose is solved rather than lerped): **transverse 3.21×10⁻³, longitudinal
1.94×10⁻³ kg·m²**, ratio 0.604.

### The eight numbers for `Config`
| # | Constant | Value | Status |
|---|---|---|---|
| 1 | Mass | 0.397–0.425 kg (models use 0.411) | VERIFIED |
| 2 | Long axis / semi-axes | 0.279–0.286 m; a 0.141, b 0.086, ratio 1.618 | VERIFIED |
| 3 | Release speed | typical **20 m/s**, elite **25**, ceiling **~26.8**, deep-ball case **27.4 at 30°** | VERIFIED |
| 4 | Spin rate | **600 rpm = 10 rev/s = 62.8 rad/s** | VERIFIED |
| 5 | Drag reference area | **nose-on 0.023 m² → broadside 0.038 m²**; wind tunnel A = 0.0365 m², D = 0.29 m, ρ = 1.21 kg/m³ | VERIFIED |
| 6 | Nose-tracking precession | **2.52 rad/s** vs velocity-vector rotation **0.37 rad/s**; misalignment ≈13% of that rotation, centred at **9° yaw** | VERIFIED |
| 7 | Wobble (nutation) | **38.0 rad/s**, period ~0.19 s; precession radius grows 0.15 → 0.22 for a 10° pitch error | VERIFIED |
| 8 | Drag coefficient | **DELIBERATELY NOT SUPPLIED** — see below | — |

**Calibration targets, not config:** drag-free range **66.4 m in 2.80 s** at 27.4 m/s / 30° (a real deep ball must
land measurably shorter), and Magnus deflection **~0.8 m over 50 m** (small enough to omit).

### Throw types: vary angle, not speed
**ASSUMPTION.** No study measures bullet vs touch vs lob release velocity separately. What *is* verified is the
envelope (20–27 m/s) and that optimal range angle is 45°. So hold the speed band and vary **launch angle**:
bullet ≈5–15°, touch ≈20–30°, lob ≈35–45°. Three distinctly different flights from one sourced range, nothing
invented.

### Spiral, and why wobble is the most important ball-feel lever
A spiral stabilises the ball gyroscopically, and its elongated shape gives less drag than a sphere of similar size.
**A wobble presents more surface area to the air, increasing drag and shortening the throw** — and the cross-section
swing is large and verified: **πb² = 0.023 m² nose-on to πab = 0.038 m² broadside, a ~60% change in drag area.**

Two distinct wobbles exist: an imperfect throw gives torque-free precession from initial transverse spin, while the
high-frequency wobble in a *well*-thrown pass is aerodynamic-torque-driven nutation at **38.0 rad/s**, not
torque-free precession.

**This is the direct fix for "the ball doesn't move convincingly": a bad throw should visibly wobble AND travel
measurably shorter.** It is honest feedback through the physics rather than a UI message.

### Does drag matter? Mostly through torque
**Drag is dominant — but through orientation, not through slowing the ball.** The serious flight model *neglects net
drag on the centre of mass*, keeping the trajectory parabolic, and treats drag as relevant only via the torques it
produces. That is explicit licence to keep a near-parabolic trajectory and still be faithful.

**Lift / Magnus: omit.** ~0.8 m deflection over 50 m — "hardly noticeable", and wind matters more. Simulating it adds
an invisible deflection the player cannot learn.

**On the drag coefficient:** the wind-tunnel paper publishes C_D and C_L only as *figures*, with uncertainty ±0.094 —
13–55% of observed values — and the flight paper gives none. **Any single C_D would be invented.** Treat it as the
one tuned constant, calibrated against the areas in row 5 and the 66.4 m benchmark.

### Nose orientation — the cheapest big visual win
**Yes, the long axis follows the velocity vector.** Drag on the leading edge moves the centre of pressure ahead of
the centre of mass, producing a pitching torque; because angular momentum stays near the symmetry axis, that torque
causes gyroscopic *precession* about the drag-force axis. Tracking error stays small: a roughly circular path centred
near zero pitch and **9° yaw**, radius ~13% of the velocity's rotation over the pass. A 10° initial pitch error grows
the radius from 0.15 to 0.22.

**Implementation (ASSUMPTION built on verified numbers):** no rigid-body solver needed. Point the long axis along
velocity, lag it with a first-order filter tuned to ~2.5 rad/s, add a constant ~9° yaw offset, and scale wobble
amplitude by throw quality. Two lerps reproduce the published behaviour.

**Flat vs deep:** since misalignment is proportional to how much the velocity vector rotates, **a bullet's nose
should stay nearly fixed and a deep ball's should visibly pitch over through the apex.** Follows from the
0.37 / 2.52 rad/s ratio; not stated as such in any source.

Worth one line of polish: initial lateral motion from the throwing hand's off-centre torque — yaw left then right
for a right-hander, ~0.8 m total drift on a 50 m pass.

### Ground bounce — **do not simulate**
The only sourced statement is that the ball "can bounce unpredictably," with no explanation. No peer-reviewed study
of American-football ground bounce exists comparable to the flight literature. Mechanically it follows from the
prolate shape (contact normal varies strongly with orientation) and the 1.65 inertia ratio.

**This is the one place realism is actively hostile to the game.** An unpredictable loose ball means a turnover is
decided by chaos rather than either player's input — in a cosmetic-only game that reads as cheating. The IFAF rule
makes it free: ground = dead. Give the fumble its live window **in the air**, where a player can contest it.

### Catching
Verified technique: hands up, palms out, thumbs together, arms not fully extended, chest high. **Above the waist:
fingers up, thumbs touching. Below the waist: hands turned down, pinkies meeting, scooping from underneath.**
Securing is taught as five points of contact — fingertips, palm, forearm, bicep, chest.

**ASSUMPTION:** the thumbs-up / pinkies-down switch at the waist is the real, teachable, binary rule and is the right
basis for both the animation selector and a catch window whose difficulty is a function of arrival height relative to
the waist, arrival speed, and the angle between ball velocity and receiver facing. Over-the-shoulder and contested
catches being harder is universal coaching lore but **could not be sourced** — treat those penalties as tuning, not
fact.

### Kicking — omit entirely
No kickoffs, punts or field goals in the small-sided contact codes; an illegal kick is a 5-yard penalty. If ever
added, note a kicked ball **tumbles rather than spirals**, which changes the aerodynamics completely (rotating drag
coefficient, lift peaking twice per revolution, Magnus mattering far more).

---

## 5. What skilled play looks like — the three contests

Everything in the coaching literature reduces to three readable, learnable contests. This is where real football
knowledge transfers.

1. **Leverage — VERIFIED, binary, teachable.** In Cover-1 (deep help) the defender takes the outside eye; in Cover-0
   (no help) the inside eye. The defender chooses a side to surrender; the receiver attacks it.
2. **Cushion — VERIFIED, a single scalar.** Align **4.6–6.4 m** (5–7 yd) off, defend a **1.8–2.7 m** (2–3 yd)
   cushion. Coaches treat cushion as lost when the receiver can step on the defender's toes.
3. **The break — VERIFIED, and the moment knowledge pays.** The real cue is **hip orientation**, the most accurate
   indicator of route intent. The defender must commit on the hip cue; early or late loses.

**Footwork is already a state machine**, stated with its transition conditions: a **control pedal** at 75% speed
maintains cushion → a **speed pedal** once cushion is threatened → a **man turn** (flipping the hips) once the
receiver has broken the cushion. Three animation states, explicit triggers. Rare gift.

**Press (verified):** corners line up ~1.4 m (1½ yd) off. Eyes start on the jersey numbers, then shift to the hips
after the release. Stay patient, let the receiver move his feet, react once he declares, keep inside leverage, use
the sideline as an extra defender. Use an **off-hand jam**, not a two-hand jam, which causes overextension —
*squeeze* (outside hand on the hip) against inside releases, *wedge* (inside hand) to push outside releases toward
the sideline.

**How the receiver beats press:** double moves (the corner has no deep help), staying near the line to delay the jam,
or getting on top of a safety who must then regain phase by tracking the near hip.

**QB–receiver timing is an ASSUMPTION** — no source publishes release-timing-to-break windows. The inference: a throw
released *before* the break and arriving *as* the receiver clears leverage is the skill expression, and the game
should reward anticipation over reaction.

---

## 6. Simulate / simplify / assist

| Element | Call | Reason |
|---|---|---|
| IFAF field 45.72 × 22.86 m | **Simulate** | Exact, free, and the legal range covers 1v1/2v2 arenas |
| Four downs to midfield, one first down | **Simulate** | Verified, and the cheapest to render — one line, one counter |
| No kickoffs, snap from own 5 | **Simulate** | Removes a whole subsystem with rules backing |
| Clock structure | **Simplify** | Keep the final-minutes stop rules (they make the endgame tense); 20-minute halves are not a Roblox round |
| Declared 1-pt / 2-pt try | **Simulate** | A real decision for zero systems cost |
| Penalties | **Simplify to five** | A player who can't name the foul reads it as unfair |
| Contact / tackling | **Assisted** | The tackle must land when the input says so; simulated momentum and whiffs on touch is where legibility dies |
| Loose ball on the ground | **Simplify — kill it** | Ground = dead is already the rule; chaos removes both players' agency |
| Ball mass / dimensions | **Simulate** | Verified exact numbers, zero cost |
| Release speed 20–27 m/s | **Simulate the band, assist the choice** | Input picks launch *angle*, not a metered velocity |
| Spiral ~600 rpm | **Simulate (visual)** | One spin value; the most recognisable thing about a thrown football |
| Wobble → more drag → shorter throw | **Simulate** | The honest feedback channel, and the direct fix for the ball not reading right |
| Net drag on centre of mass | **Simplify** | The literature itself neglects it and keeps the parabola |
| Lift / Magnus | **Omit** | ~0.8 m over 50 m; an invisible deflection the player cannot learn |
| Nose tracking velocity | **Simulate cheaply** | Two lerps reproduce 2.5 rad/s precession and the 9° yaw bias — highest visual return per line in the list |
| Nose-on vs broadside drag area | **Simulate** | What makes spiral *quality* matter rather than just look nice |
| Catch above/below waist | **Simplify the rule, assist the window** | Great animation selector; a realistic catch radius on a thumbstick is unplayable |
| Over-the-shoulder / contested | **Assisted** | Visibly harder but still landable; the penalty belongs in the window, not the camera |
| Leverage | **Simulate** | The clearest place real knowledge transfers; legible on every input device |
| Cushion 1.8–2.7 m | **Simulate** | A single sourced scalar the game can feel or display |
| Three-state pedal → man turn | **Simulate** | The source states both the states and the transitions |
| Press jam (squeeze / wedge) | **Simplify to one button** | Two hand techniques resolved contextually by release side |
| Reading hips for the break | **Assisted** | The real cue is invisible at Roblox camera distance and on a phone. Keep hip animation as the honest source of truth but add a readable tell (foot-plant flash or audio hit). **The one place the real cue must be augmented or skill becomes guesswork.** |
| Hash marks | **Omit** | Anachronistic at 22.86 m wide |
| Kicking | **Omit** | Not in the small-sided contact codes |

**Where realism would make controls worse — flagged explicitly:** hip-reading as the *only* break cue; a realistic
catch radius on touch; simulated tackle momentum and whiffs; unpredictable ground bounce; separate press
hand-technique inputs; a velocity-metered throw. In all six the realistic version removes the player's ability to
predict the outcome of their own input.

**Monetization check:** leverage, cushion, break timing, spiral quality and catch windows are all
**input-determined**, so cosmetic-only holds by construction — nothing recommended here could be sold.

---

## 7. Open questions for the owner

1. **Match length.** Structure is verified; duration is a product decision. How long is one ALLSTAR WORLD match?
2. **Who snaps in a 5-player offence?** The real format has a center who snaps then runs a route; the current slot
   list has none. Does the QB self-snap (arcade), or does a slot become CENTER?
3. **How live is a fumble?** Recommended air-live / ground-dead, deviating toward the contact codes. How much chaos
   does a contact arcade mode want?
4. **Is the break cue augmented?** Real skill reads hips, but hips are unreadable on a phone. Adding a tell makes the
   game fair and the realism slightly dishonest. Which would you rather defend?
5. **Does 1v1 use the full field?** 40–60 × 20–30 yd is legal; a receiver-vs-defender duel may want much less.
6. **What does "realistic later" mean?** 11-a-side NFL rules (a different ruleset, new field, kicking, chains), or
   the same IFAF 5v5 with assists turned down? Very different amounts of work — and the ball config above only
   serves the second.
7. **First downs confirmed?** The research answer is unambiguous across three governing bodies. The project
   currently has none, so this needs an explicit yes before it enters the GDD.
