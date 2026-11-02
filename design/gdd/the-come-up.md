# THE COME UP — Player Progression & Attribute Growth (ALLSTAR WORLD)

> **Status: DESIGN DRAFT 1 — 2026-11-02. Nothing in this document is built, and
> nothing in it is scheduled.** Owner brief: *"Make a system: systemize all that,
> turn it into a system, and put it to the side. Label it as our gaming: as you go
> up, build your stats, just like 2Ks and FIFA 27's system of building your
> player."* **Parked by instruction — this is a design record, not a work order.**
>
> Engine: Roblox (Luau). **Units: METRES, SECONDS, DEGREES** (1 stud = 0.35 m).
> Baseline constants measured from the 2026-11-02 mirrors
> `src/football/team/Config.lua` and `src/football/team/Rules.lua`, and from
> `docs/audits/2026-11-02/research/basketball-feel-findings.md` for basketball.
>
> **Pillars this document is bound by, by name:**
> **P1 "I know exactly why I lost."** · **P2 "both sides have a fantasy."**
> **P3 "deep balls rewarded."** · **The fairness rule: humans and AI obey
> identical rules.** · **The monetization law (football-core.md, cosmetics.md):
> cosmetic only — no value in any gameplay config table may ever be
> purchase-linked.**
>
> Every invented number is tagged `[ASSUMPTION]`. Every number taken from the
> build is cited to its file and key. Basketball mappings that could not be
> measured are tagged `[BLOCKED — needs measurement]` and are **not** guesses.

---

## 0. Naming

The owner asked for this to be labelled as ours. Three candidates in the voice of
DRIP STORE / THE YARD / THE GAUNTLET / ALLSTAR WORLD:

| Candidate | Reads as | Against |
|---|---|---|
| **THE COME UP** | the whole progression system — "as you go up" literally | none; it is the owner's own phrase |
| **MY ALLSTAR** | the 2K MyPlayer analogue, instantly legible to the audience | derivative of 2K by design; weaker brand, and it names the *avatar* not the *climb* |
| **THE LADDER** | ranked/competitive flavour | collides conceptually with THE GAUNTLET; sounds like matchmaking, not growth |

**Recommendation: THE COME UP**, with two named sub-surfaces so the whole thing
has one vocabulary:

- **THE COME UP** — the system (XP, levels, points, attributes, badges, unlocks).
- **THE CARD** — the player-facing artifact: your OVR, archetype, ratings, badges.
- **THE TAPE** — the post-match box score + grade screen where XP is awarded and
  explained. ("Go watch the tape.")

**File slug:** this document is `design/gdd/the-come-up.md`, not
`allstar-career.md`. The `systems-index.md` row points here.

---

## 1. Overview

THE COME UP is ALLSTAR WORLD's player-growth system: the 2K MyPlayer / FIFA
player-growth analogue, adapted so it cannot break the project's fairness pillar.
A player earns **XP** from the same server-resolved match events that already feed
DRIP (TD, PERFECT CATCH, ANKLE BREAKER, tackle, interception, rebound, block,
steal, contest-forced-miss, bucket, three, win, match completion), levels up, and
spends **attribute points** on a **CARD** — a per-sport set of 70–99 ratings under
an archetype (DEEP THREAT, LOCKDOWN, GUNSLINGER…). Each rating scales exactly one
or two named constants in `AWFootball.Config` / `Tuning3` through a single pure
function, inside a deliberately **tight band**, and **rating 70 is defined as the
shipped value** — so a brand-new player plays today's game exactly, and growth can
only ever specialize a player, never make a newcomer worse than the current build.
The larger share of progression value is in **unlocked options** (routes, carrier
moves, playbook pages, pre-snap reads) and **badges** — conditional, named,
one-constant modifiers that announce themselves in the existing reason-string
channel, so a player who just lost to one is told which badge did it. XP and
attributes live in their own DataStore (`AWGrowth_v1`), never touch DRIP in either
direction, and nothing in this system may ever be sold for Robux.

**Relationship to DRIP, stated once and absolutely: DRIP buys looks. XP buys
ability. There is no conversion in either direction, ever, and Robux buys
neither.** `cosmetics.md` owns everything visible; this document owns everything
capable. The two systems share one input — the match-event BindableEvent — and
nothing else.

---

## 2. Player Fantasy

**"That's *my* guy, and I built him — and you can still beat him."**

The 2K feeling this is chasing is not *being stronger*. It is **legible identity
through accumulated choice**: the card is a record of how you play, readable at a
glance by you and by the person across from you. The DEEP THREAT is 99 SPEED and
baseline TACKLING and everybody in the lobby knows it, which is why the LOCKDOWN
plays him with a bigger cushion (`coverage.cushionMaxM 2.7`) and why beating that
cushion anyway is the best feeling in the game.

MDA aesthetics, in priority order: **Expression** (the card is a statement),
**Challenge** (specialization creates matchups, not gradients), **Fantasy** (the
ALLSTAR you are building), **Submission** (the loop that makes one more match
cheap). Deliberately *not* **Sensation** — nothing in this system is allowed to be
felt without being named.

SDT: **Competence** from THE TAPE (you are told, line by line, what you did and
what it was worth — the progression version of P1); **Autonomy** from point
allocation and archetype choice inside a real budget; **Relatedness** from the
card being seen — your OVR and badges are social objects in the lobby.

**The explicit anti-fantasy.** This system must never deliver "I lost because he
has been playing longer." Where a rating or a badge decides an outcome, the
existing reason string names it (§3.8). Where it cannot be named, the effect is
too small to be worth having and is cut.

---

## 3. Detailed Design

### 3.1 The central tension, and how it is resolved

A 2K-style attribute system means a veteran is objectively better than a newcomer
at the same inputs. That is in direct tension with this project's stated fairness
rule and with P1. The four branches, honestly:

| Branch | What it is | Pros | Cons | What it does to the pillars |
|---|---|---|---|---|
| **A. Separate tracks** | Attributes apply in solo/PvE/career; ranked & pickup PvP run on flat parity | Pillars fully intact in the mode that matters most; one config flag to implement; THE GAUNTLET becomes the pure-skill proving ground | Progression stops mattering exactly where players care most; two balance surfaces to tune forever; "my build does nothing in ranked" is a real complaint | **No pillar weakened.** Costs motivation, not fairness |
| **B. Rating-matched PvP** | Attributes always apply; matchmaking pairs similar OVR; AI fill scales to lobby rating | Preserves the 2K feel completely; AI fill scaling is a genuine fairness *improvement* over today's hardcoded `cpuWrSpeed 9.1` | **Requires a population Roblox indie titles do not have.** OVR-bucketed queues fragment a small lobby pool into empty ones; a kid-heavy audience will not wait. Also hides the problem rather than solving it: the gradient still exists, matchmaking just conceals it | Fairness rule survives *statistically*, not *per match*. P1 unaffected. **Fails on feasibility, not principle** |
| **C. Style not strength** | Progression unlocks options — routes, moves, playbook pages, reads, conditional badges — never raw physics | Pillars fully intact; every power difference is *visible on the field* and counterable (discipline beats a double move); maps onto work already specced (`football-playbook.md` 15 plays, the 4 new routes, `sluggo`) | Not what the owner asked for — no numbers go up on the card; a pure-unlock system has a short tail (once you have every route, progression is over); "more options" is also a real competitive advantage, just a harder-to-measure one | **No pillar weakened.** Weakest delivery of the owner's brief |
| **D. Tight band** | Attributes exist, spread is deliberately small, skill dominates | Delivers the brief literally — numbers on a card that go up; preserves per-match fairness because the band is below the noise floor of player skill | Risk of feeling pointless ("+2.5% speed, who cares"); risk of the opposite if any single constant is leverage-heavy (see §3.4: `catch.det.threshold` and `move.wrSpeed` are *not* safe at the same band) | Fairness rule survives if the band is honestly tight. **P1 survives only if effects are named** (§3.8) |

**Recommendation: C + D as the shipped system, with A as the ranked guard rail.**

Specifically:
1. **The floor is today's build.** Player ratings run **70–99**, and **rating 70 is
   defined as the currently shipped constant, bit-for-bit** (acceptance F3). A
   brand-new player's card is uniform 70s. Nobody is ever below the current game.
   This removes the entire "newcomer is handicapped" half of the problem at a
   stroke — and it means turning this system on cannot regress today's feel.
2. **Growth is zero-sum-ish, not additive.** Points are a budget (§4.4); archetype
   caps stop any build from being uniformly high. A maxed veteran is **+29 in two
   or three attributes and baseline in the rest**. He is *specialized*, not better.
   A newcomer is *unspecialized*, not weak.
3. **Bands are per-attribute and tight** — 2.5% half-range on SPEED, 1.5% on
   THROW POWER (bounded by sourced real-world ceilings), up to 15% only on
   low-leverage feel knobs like `sprint.staminaMax`. One global band would be
   wrong: §3.4 shows these constants have wildly different leverage.
4. **Most of the perceived progression is branch C** — routes, moves, playbook
   pages, and AWARENESS *information* unlocks. Progression buying **information**
   (`Rules.pedalState` / `Rules.leverage` already return player-readable strings
   that nothing currently shows) is the single best lever available: it is
   strongly motivating, it is pure Competence, and it changes no physics at all.
5. **Branch A is kept as one flag, not a second system.** `Growth.PARITY = true`
   pins every rating to 70 while leaving unlocks and badges active. It is the
   default for Stages 0–1 (§3.10) and the permanent setting for any ranked ladder
   the owner later builds on THE GAUNTLET.
6. **AI gets a card.** AI athletes carry a generated card and go through the
   **identical** `Growth.scale` call — satisfying the fairness rule literally,
   with one function and one call site. This is a net fairness *gain*: today
   `move.cpuWrSpeed 9.1` / `cpuDbSpeed 9.25` are separate constants from
   `wrSpeed 9.6` / `dbSpeed 9.3`, i.e. **the build already gives humans and AI
   different speeds**, and expressing AI as a rating retires that asymmetry.

**Where a pillar would be weakened — stated loudly:**
- **Any band wider than §3.4's** weakens the fairness rule, and the first
  attribute to break it is SPEED: `move.wrSpeed 9.6` vs `coverage.cushionMinM 1.8`
  means a 5% speed edge sustained over a 20 m route is worth most of a DB's
  cushion. SPEED is capped at 2.5% for this reason, not for tidiness.
- **Unnamed effects weaken P1.** A rating or badge that changes an outcome without
  appearing in a reason string is a dice roll with extra steps — exactly what
  `football-core.md` §3.7 withdrew the drop-probability model to avoid.
- **Selling anything in this document breaks the monetization law outright.** Not
  "is risky" — breaks it. §3.9 is a prohibition list, not a guideline.
- **Avatar-measured reach (football-core OPEN-DECISIONS D) stacks with CATCH
  REACH.** `AWPractice.Receive.rig` measures real avatar arm length, so a tall
  avatar already reaches further. Adding a REACH rating on top compounds an
  unresolved fairness question. **CATCH REACH must not ship until D is decided.**

### 3.2 Loops

- **Micro (30 s, one play):** act → the existing reason string → a counter ticks
  on the card (`contestedCatches`, `ankleBreakers`). Nothing new is built here;
  the counters are a side-effect of events that already fire.
- **Meso (5–15 min, one match):** play → **THE TAPE** → XP, a grade per phase,
  and sometimes a point to spend. The point is the meso-loop reward.
- **Macro (session):** spend the point on THE CARD, see the OVR move, pick the
  next unlock target. The natural stopping point is "I spent it"; the reason to
  return is a visible next unlock at a named level.

### 3.3 Attributes — football

Each attribute maps to **one or two named constants** and nothing else. `n` is the
normalized rating (§4.1); all values below are from `src/football/team/Config.lua`,
2026-11-02.

| Attribute | Constant(s) it scales | @70 (shipped) | @99 | Half-range | Why this band |
|---|---|---|---|---|---|
| **SPEED** | `move.wrSpeed` / `move.dbSpeed` / `move.carrySpeed` | 9.6 / 9.3 / 9.0 | 9.84 / 9.53 / 9.23 | **2.5%** | Highest-leverage constant in the game. +0.24 m/s over a 2 s route ≈ 0.5 m — a quarter of `coverage.cushionMinM 1.8`, felt but not decisive |
| **ACCELERATION** | `stance.burstTime` (0.7) | 0.70 | 0.81 | 8% | Lengthens the snap burst you already earned with timing; does not raise top speed. (Practice-Field twin: `Momentum accelTime 0.6`) |
| **HANDS** | `catch.det.comfortSpeedMps` (14.0); `catch.det.threshold` (1.0) | 14.0 / 1.00 | 15.1 / 1.04 | 8% / **0.04 abs** | `threshold` is the master dial of the whole deterministic catch model — a 1% move there shifts every term at once. Deliberately the tightest absolute band in the document |
| **ROUTE RUNNING** | `catch.windowEarly` (0.5) / `windowLate` (0.22); `stance.perfect` (0.15) / `good` (0.35) | as shipped | 0.55 / 0.242; 0.165 / 0.385 | 10% | Widens *timing* windows, not reach. Rewards the skill it represents. Also the gate for route unlocks (§3.6) |
| **CATCH REACH** | `catch.secureReach` (1.5) / `aggressiveReach` (2.3) | 1.5 / 2.3 | 1.56 / 2.39 | 4% | **DO NOT SHIP until football-core OPEN-DECISIONS D (avatar-measured reach) is resolved** — it stacks |
| **THROW POWER** | `qb.throwSpeedMax` (27) | 27.0 | **27.4** | **1.5%** | Hard-clamped to `ballPhysics.releaseDeepCaseMps 27.4`, the sourced real-world deep-ball case. 99 THROW POWER = the fastest throw physics says exists. Real elite spread is tiny; the band honours that. Real progression value is the deep playbook + the DEEP THREAT badge |
| **ACCURACY** | `qb.accuracy` (0.82), `qb.rushedPenalty` (0.9) — **AI-thrown balls only today** | 0.82 / 0.90 | 0.886 / 0.945 | 8% / 5% | **GAP:** `Rules.solveThrow` applies *no error term to a human throw* in the team product. A human QB's accuracy is his aim. ACCURACY has nothing to scale for a human until the Practice Field's `pass.err` model (base/perM/moving/facingK/`pressure 1.0`) lands in `TeamFootballService`. Until then ACCURACY is **display-only on a human card** and must be labelled so |
| **TACKLING** | `tackle.cleanClosingSpeed` (4.0, ↓) ; `tackle.reach` (1.35) | 4.0 / 1.35 | 3.76 / 1.40 | 6% ↓ / 4% | Lowering `cleanClosingSpeed` converts marginal WRAPs into CLEAN_TACKLEs — a *readable* outcome flip, since `Rules.resolveTackle` already returns which one happened |
| **COVERAGE** | `pedal.flipTime` (0.18, ↓); `pedal.speed` (6.6) | 0.18 / 6.6 | 0.158 / 6.86 | 12% ↓ / 4% | Hip flip is the DB's skill expression (P2). `defend.reaction 0.22` is AI-only and scales on AI cards only |
| **PHYSICALITY** | `move.stiffArmStun` (0.7); `tackle.breakWindow` (0.35) | 0.7 / 0.35 | 0.77 / 0.385 | 10% | Both are *time to make a decision*, not raw force — the safest shape of buff |
| **ELUSIVENESS** | `move.jukeCooldown` (1.1, ↓) / `spinCooldown` (1.6, ↓); `move.jukeBreakRadius` (3.5) | 1.1 / 1.6 / 3.5 | 0.99 / 1.44 / 3.78 | 10% ↓ / 8% | Cooldowns are the cleanest progression knob in the game: more attempts, same per-attempt power. `jukeBreakClosingMps 2` is **not** scaled — patient defenders must never bite |
| **STAMINA** | `sprint.staminaMax` (3.0); `sprint.recoverRate` (0.6) | 3.0 / 0.6 | 3.45 / 0.69 | **15%** | Lowest-leverage, highest-felt knob in the config. Where a generous band belongs |
| **AWARENESS** | **nothing numeric.** Unlocks pre-snap information (§3.6) | — | — | — | Pure branch C. `Rules.pedalState` and `Rules.leverage` already return player-ready strings that no UI shows. Progression buys knowledge, not physics |

**Not scalable, and why — the do-not-touch list.** `ballPhysics.*` (sourced
measurements of a real football), `field.*`, `series.*`, `scoring.*`, `penalty.*`,
`overtime.*`, `clock.*` (the IFAF ruleset — rules are not attributes),
`catch.det.waistM` (human anatomy), `seed`, `jukeBreakClosingMps`,
`coverage.brokenAtM` / `threatenedAtM` (the coverage state machine's own
definition — moving it would make `pedalState`'s reason strings lie).

### 3.4 Attributes — basketball

Basketball's live numbers are in
`docs/audits/2026-11-02/research/basketball-feel-findings.md`. Two of them block
this mapping and must be fixed first.

| Attribute | Constant(s) | Status |
|---|---|---|
| **THREE** | `shot.openBonus`; the open-three make rate behind `rangeMult 0.683` at arc 8.688 m (measured: open/perfect three = 0.628 make, 1.885 expected pts) | **[BLOCKED]** the contest reason thresholds **0.15 / 0.45 / 0.75 are hardcoded at `BallCtl:675`, not in `Tuning3`**. Nothing may scale a hardcoded literal. Move them into `Tuning3` first (basketball build-order item 2) |
| **MID / FINISHING** | the layup (0.860 open) and dunk (0.970 open) make rates | **[BLOCKED]** same reason; also note the measured imbalance — an open three (1.885) *loses* to an open dunk (1.940), so these rates need a balance pass **before** any rating multiplies them |
| **HANDLES** | `move.contactSlow` (0.55) | **[BLOCKED]** read only at `Hoops3Client:648`, **client-side, human-handler-only, never server-enforced, never applied to AI** — a live violation of the fairness rule. Not scalable until it is symmetric and server-side |
| **PERIMETER D** | `Play.contest` terms: `radius` (2.1), `inFront` (0.35), `handsUpBonus` (0.25), `contestJumpWindow` (0.35) | Mappable. Recommend PERIMETER D scales `radius` (±4%) and `contestJumpWindow` (±10%) only — `inFront` and `handsUpBonus` are the *legibility* terms and should stay fixed so OPEN/CONTESTED means the same thing for everyone |
| **REBOUNDING** | `rebound.boxOut` (0.55), `rebound.timing` (0.6), `rebound.reach` | **[BLOCKED]** the audit states plainly that *how rebounds actually resolve was not read* (`BallCtl:280-400` and `Brain` unread). Do not map an attribute onto a resolver nobody has read |
| **ATHLETICISM** | `personalSpace` (0.72) / `Body:softContact` push weights | **[BLOCKED]** push weights are **nonzero only for `a.kind == "ai"`** (`Body:76-77`) — humans are never displaced. Fairness violation first, attribute second |

**Conclusion for basketball: THE COME UP cannot ship for basketball until the five
items in the basketball build order are done.** Football first, as the owner's
order already has it. One attribute (PERIMETER D) is mappable today; the rest is
honestly blocked, and that is the correct answer rather than a table of guesses.

### 3.5 Earning XP

**Reuse the existing spine.** The match-event BindableEvent that `DripService`
already consumes (`DripService:124-133` handles `rebound` with `m.offensive`,
`block`, `steal`, `contestForcedMiss`, `bucket` with `m.three`; football fires TD,
PERFECT CATCH, ANKLE BREAKER and friends) gains **one more subscriber**:
`GrowthService`. No new event surface, no change to any emitter.

**The coupling this creates, named so it is not discovered the hard way.** One
event now prices into **two economies**. Adding, renaming or re-weighting an event
changes both DRIP income and XP income. **Rule: any change to the event set must
be priced in `cosmetics.md` §3.2 and this document's §3.5 in the same change, or
it is not done.**

**XP table [ASSUMPTION — all values].** Deliberately *not* proportional to DRIP:
DRIP rewards *visible flair*, XP rewards *the thing the attribute represents*.

| Event | XP | Per-match paid cap | Note |
|---|---|---|---|
| Match completed (present at final whistle) | 75 | 1 | the floor — a loss still progresses you |
| Win | 100 | 1 | |
| Touchdown | 60 | 4 | |
| Interception | 50 | 3 | |
| Breakaway declared | 30 | 2 | pairs with feel-upgrades #8 |
| ANKLE BREAKER | 25 | 4 | |
| PERFECT CATCH (`Rules.catchGrade` = PERFECT) | 20 | 6 | |
| Swat / forced incomplete | 20 | 5 | P2: the DB's half pays the same as the WR's |
| First down (crossing the middle line) | 15 | 4 | |
| Catch (any) | 10 | 6 | |
| Tackle (CLEAN_TACKLE or completed WRAP) | 10 | 8 | |
| Basketball mirrors | `DripService` ratios × 2 | per event | bucket 12 / three 20 / block 36 / steal 36 / reboundOff 30 / reboundDef 24 / contestForcedMiss 20 — **parked behind §3.4** |

**Caps and decay:**
- **Per-match XP cap:** 600 [ASSUMPTION]. **Soft** — events past the cap pay 25%,
  so a dominant performance is never flatly truncated (a hard wall teaches players
  to stop trying, which is the opposite of the intent).
- **Per-event-type caps** as tabled above: the real anti-farm mechanism. Capping
  *catches at 6* stops a two-player pitch-and-catch loop without capping anything
  a real match produces.
- **Daily decay:** `dayMul = clamp(1 - 0.15 · floor(matchesToday / 3), 0.4, 1)`
  [ASSUMPTION]. Matches 1–3 full value; floor at 40% from match 13. Protects the
  protocol-minded player (and the kid audience) from grind pressure while leaving
  a long session worthwhile.
- **Interaction with DRIP's cap, stated:** DRIP's `Catalog.earn` cap is **250 per
  match** (measured). XP's cap is **separate and independent**. They must never be
  combined into one budget — a player who hits the DRIP cap must still earn XP, or
  the two systems start competing for the same play.

**Anti-farm:**

| Vector | Rule |
|---|---|
| Private servers | **XP = 0.** Matches `cosmetics.md` §4.2's flagged safer option. Consistency between the two tracks matters more than either choice |
| AI-only / 1-human lobby | XP × 0.25 and **no badge counters advance**. Badges are earned against people |
| Practice Field | Separate capped bucket: `practiceXp` up to 150/day [ASSUMPTION], contributing to level but **not** to badge counters. Keeps the Ball Lab alive (it is the best-engineered thing in the build) without making it the optimal route |
| Stat padding against one opponent | XP from events against the same opponent `UserId` within one match decays ×0.6 per repetition past the type cap |
| Fabricated events | **XP is only paid for an event that carried a server-resolved reason string.** This is the elegant one: P1 already requires every outcome to be explainable, so the reason string *is* the audit record. No reason, no XP |
| AFK / leave-early | Match-completion XP requires presence at the final whistle (same rule as DRIP) |
| Score-margin farming | Win XP is flat. There is no margin bonus, ever — it would reward stomping a weaker card, which is the exact dynamic this system must not create |

### 3.6 Spending and shaping

**Both, in sequence: usage proposes, allocation confirms.** Pure usage-based growth
(FIFA-like) removes Autonomy and punishes experimenting; pure allocation (2K-like)
ignores how you actually play. So:

1. Playing accrues **XP** (level) and **counters** (per-attribute usage).
2. Levelling grants **points** (§4.4).
3. Points are spent by the player on THE CARD. Counters do not auto-spend — they
   **recommend** ("your last 10 matches: 41 contested catches → HANDS").

**Ratings run 70–99 for players.** `Growth.scale` accepts 41–99 so AI cards can sit
*below* baseline for a PvE ladder; no human card ever does.

**Archetypes** (football). Each sets soft caps; an attribute above its cap costs
2 points per rating instead of 1, and hard-stops at the cap + 10.

| Archetype | 99-capable | Capped at 85 | Capped at 78 |
|---|---|---|---|
| **DEEP THREAT** | SPEED, ACCELERATION, ROUTE RUNNING | HANDS, ELUSIVENESS, STAMINA | TACKLING, COVERAGE, PHYSICALITY |
| **ROUTE TECHNICIAN** | ROUTE RUNNING, HANDS, AWARENESS | ACCELERATION, STAMINA | SPEED, TACKLING, COVERAGE |
| **POWER BACK** | PHYSICALITY, ELUSIVENESS, STAMINA | SPEED, HANDS | COVERAGE, THROW POWER, ACCURACY |
| **LOCKDOWN** | COVERAGE, SPEED, AWARENESS | TACKLING, ACCELERATION | THROW POWER, PHYSICALITY |
| **GUNSLINGER** | THROW POWER, ACCURACY | AWARENESS, STAMINA | SPEED, COVERAGE, TACKLING |
| **FIELD GENERAL** | AWARENESS, ACCURACY, ROUTE RUNNING | THROW POWER | SPEED, ELUSIVENESS |

**Hard caps so nobody becomes a god:**
- Rating ceiling **99**, absolutely, with the per-constant clamps of §3.3 applied
  after scaling (`qb.throwSpeedMax ≤ ballPhysics.releaseDeepCaseMps 27.4`).
- Point budget `5 × level`, max level **25** → **125 points** (§4.4). At 125
  points a build is +29 in three attributes and ~baseline elsewhere. **Not every
  attribute can be high, by arithmetic, not by promise.**
- **Combined-leverage cap:** the product of all active multipliers on any single
  constant (rating + badge) may not exceed **1.12** (or 0.88 downward). Enforced in
  `Growth.scale`, not by convention (acceptance F7).
- Archetype soft/hard caps above.

**Unlocks (branch C — the bulk of felt progression).** Gated on level, not points,
so they cannot be traded away:

| Level | Unlock | Source already specced |
|---|---|---|
| 2 | `spin` carrier move | `move.spinTime/spinCooldown/spinSpeed` exist |
| 4 | Routes `out`, `dig` | `Rules.ROUTES` — already in the table, unused by the 5-route pool |
| 6 | `stiffArm` | `move.stiffArmReach/Stun/Cooldown` exist |
| 8 | **Coverage read** — show `Rules.pedalState`'s string pre-snap (AWARENESS ≥ 78) | `Rules.pedalState` returns it today; nothing displays it |
| 10 | Route `comeback` | exists, with `settle = true` |
| 12 | **Leverage read** — `Rules.leverage`'s string (AWARENESS ≥ 85) | exists today, unused |
| 14 | Route `sluggo` (the double move) | `football-feel-upgrades.md` #5 |
| 16 | QB pump fake | feel-upgrades #6, `qb.pumpPoseS 0.2` |
| 18+ | Playbook pages | `football-playbook.md`'s 15-play / 6-category book |

**Respec.** Free while level < 10. Then: **one free respec per season**, further
respecs cost **XP** (`respecCost = 2 × xpToLevel(currentLevel)` [ASSUMPTION]) or
wait out a 7-day cooldown. **Respec never costs DRIP and is never purchasable** —
the moment a currency can buy a build, DRIP has bought ability. Archetype changes
are a respec. Respec is refused during a match.

### 3.7 Badges

2K-style conditional modifiers, in this project's deterministic idiom. A badge is:

```
badge = {
  id, name, tier,              -- bronze | silver | gold
  trigger,                     -- a predicate over server-known geometry/state only
  effect = { key, delta },     -- EXACTLY ONE config key
  reason,                      -- one sentence, shown to BOTH players
  counter, thresholds,         -- how it is earned (usage), per tier
}
```

**Five laws, all enforceable:**
1. **One badge touches one constant.** No badge has two effects.
2. **No two active badges may touch the same constant.** Refused at equip time, not
   resolved by stacking. This is what kills multiplicative blowup.
3. **Max 3 equipped** (one per phase: ball-in-air, ball-in-hand, defence).
4. **Every firing broadcasts its reason string to both players**, through the
   existing reason channel and the broadcast-UI badge banner anatomy. A badge that
   decided an outcome and did not say so is a P1 violation and a defect.
5. **Magnitude cap:** a gold badge's delta ≤ 1.5× the full 70→99 rating spread of
   the same constant, and it still obeys the 1.12 combined-leverage cap.

**Starting set [ASSUMPTION — all deltas]:**

| Badge | Phase | Trigger (server-known) | Effect (gold) | Reason string |
|---|---|---|---|---|
| **MOSSED** | air | `contested == true` | `catch.det.contestedAdd` 0.30 → 0.22 | "MOSSED HIM · BADGE: traffic bothers him less" |
| **SURE HANDS** | air | `relSpeed < catch.det.comfortSpeedMps` | `catch.det.threshold` +0.05 | "SURE HANDS · BADGE: he doesn't drop the easy one" |
| **HIGH POINT** | air | `highBall` jump ball | `jump.aggressiveMargin` 0.05 → 0.08 | "HIGH POINT · BADGE: he wins the tiebreak in the air" |
| **ANKLE BREAKER** | hand | first juke/spin of the play | `move.jukeBreakRadius` 3.5 → 3.9 | "ANKLE BREAKER · BADGE: his first move reaches further" |
| **ARM BAR** | hand | inside `move.stiffArmReach` | `move.stiffArmStun` 0.7 → 0.80 | "ARM BAR · BADGE: his stiff-arm holds you longer" |
| **CLOSER** | defence | carrier within 3 m of a sideline | `tackle.cleanClosingSpeed` 4.0 → 3.5 | "CLOSER · BADGE: he finishes at the boundary" |
| **MIRROR** | defence | cushion > `coverage.threatenedAtM` 2.7 | `pedal.flipTime` 0.18 → 0.155 | "MIRROR · BADGE: his hips flip faster with a cushion" |
| **ICE IN THE VEINS** | any | inside `clock.stopClockWindowSeconds` 60 | `qb.rushedPenalty` 0.9 → 0.95 | "ICE IN THE VEINS · BADGE: pressure doesn't rush him late" |
| **DEEP THREAT** | air | throw distance > 25 m | `ball.maxFlight` 2.15 → 2.30 | "DEEP THREAT · BADGE: the deep ball hangs for him" (P3) |

Earned by **usage counters only** — never bought, never dropped randomly. Tiers
bronze/silver/gold at counter thresholds (e.g. MOSSED at 25 / 100 / 300 contested
catches [ASSUMPTION]), with the delta scaling 0.4 / 0.7 / 1.0 of the gold value.

**Note on P2.** The defence gets three badges to the offence's three by
construction. If a playtest shows the offence's badges are stronger, the fix is to
cut an offence badge, not to add a fourth defensive one.

### 3.8 Legibility — the mechanism that makes any of this pillar-safe

Three channels, all already built or specced:

1. **Reason strings.** `Rules.judgeCatchDeterministic` already returns
   `{ result, detail, difficulty, threshold, terms }` — a *per-term breakdown*.
   When a rating or badge moved a term, the term's name plus the source is
   appended: `"dropped — it arrived too hot (his HANDS 94 raised the limit)"`.
   The infrastructure for this exists; it needs one extra field.
2. **The pre-snap card read.** Both players see the other's OVR, archetype and
   equipped badge names before the snap. **An unknown advantage is the unfair one.**
3. **THE TAPE.** Post-match, every XP line is named (§3.9).

**Rule:** if an effect cannot be stated in one sentence a 10-year-old understands,
it does not ship. That is the test, and it is why no badge has two effects.

### 3.9 Persistence and data model

**Store:** `AWGrowth_v1`, key = `UserId` — a **separate DataStore from
`AWDrip_v1`**, behind a shared `AWProfile` façade. Reasons: (a) a growth migration
bug must not be able to destroy cosmetics ownership, which is the store with real
money in it; (b) different write cadences (DRIP writes on purchase, growth writes
on match end); (c) the fairness grep (cosmetics acceptance F5) stays trivially
checkable when the two are distinct modules.

```lua
profile = {
  v = 1,
  xp       = { football = 12840, basketball = 0 },
  practiceXp = { football = 90, dayKey = "2026-11-02" },
  level    = { football = 14 },
  cards = {
    football = {
      archetype = "DEEP_THREAT",
      ratings   = { speed=92, accel=84, hands=78, route=88, reach=70, throwPower=70,
                    accuracy=70, tackling=70, coverage=70, physicality=70,
                    elusiveness=76, stamina=80, awareness=70 },
      unspent   = 3,
      badges    = { mossed = "silver", ankleBreaker = "gold" },
      equipped  = { "ankleBreaker", "mossed" },           -- max 3, §3.7 law 3
      counters  = { contestedCatches=141, jukes=612, ... },
    },
  },
  unlocks = { routes = { out=true, dig=true, comeback=true },
              moves  = { spin=true, stiffArm=true },
              reads  = { coverageLabel=true },
              plays  = {} },
  season  = { id = "S1", respecsUsed = 1, lastRespecAt = 0 },
  audit   = { lastMatchId, lastXpAt, matchesToday = 2, dayKey = "2026-11-02" },
}
```

**Authority.** The card is server-only. **No client ever sends a rating**; the
client receives a read-only replicated snapshot for display. One accessor:

```
Growth.scale(configKey, card) -> number     -- pure, no Instances, no RNG
CFG:get(configKey, actorCard) -> number     -- the ONLY way a service reads a scalable key
```

Every service reads scalable constants through `CFG:get`, humans and AI alike —
that single call site **is** the fairness rule, mechanically (acceptance F10). It
is also where `Growth.PARITY` lives.

**Versioning.** `v` is an integer; `Migrations[n]` are pure functions applied in
order; unknown keys are preserved, never pruned. A profile from a future `v` is
loaded read-only with a HUD notice rather than coerced.

**Studio API access off / DataStore unavailable** (mirroring what `DripService`
already handles): an in-memory profile with `ephemeral = true`, a HUD line
`"OFFLINE PROFILE · PROGRESS NOT SAVED"`, and — the important part — **`PARITY` is
forced on**, so every rating is pinned to 70. An unsaved session can neither farm
XP nor carry a phantom card. Failing safe here means failing *to today's build*,
which is the whole reason rating 70 is defined as the shipped value.

### 3.10 Build order and MVP cut

**Stage 0 — THE TAPE + THE CARD, with zero gameplay change (the recommended MVP).**
`PARITY = true` globally. Ships: the post-match box score and grade screen, XP, levels,
points accruing, and a visible card whose ratings are **displayed and inert**. No
constant is scaled by anything.
*Why first:* it proves the event spine, the DataStore, the migration path and the
UI; it gives the owner weeks of real XP-curve data before a single number touches
gameplay; and it independently fixes a real gap — **there is no box score today**.
It is also the cheapest thing on this list and the most visible per minute.

**Stage 1 — unlocks only (branch C).** Routes (`out`, `dig`, `comeback`),
`spin`, `stiffArm`, AWARENESS reads. Still `PARITY = true`. Progression now has
teeth and the fairness pillar has not been touched once.

**Stage 2 — scaling on the three lowest-leverage attributes.** STAMINA
(`sprint.*`), ELUSIVENESS (cooldowns only), COVERAGE (`pedal.flipTime`). Measure
win rates by OVR before going further. **This is the first stage that can weaken a
pillar, and it is the stage to be slowest about.**

**Stage 3 — SPEED, HANDS, TACKLING + AI cards.** Generate AI cards from the
lobby's mean OVR and **retire `move.cpuWrSpeed` / `cpuDbSpeed`** in favour of AI
ratings through the same accessor (a fairness-rule fix, not just a feature).

**Stage 4 — badges.** Last of the football work: badges are the most legibility-
expensive feature and should land only once reason strings carry rating sources.

**Stage 5 — ranked PARITY mode** on THE GAUNTLET, if the owner wants a ladder;
then basketball, after the five basketball build-order items are done.

### 3.11 Monetization boundary

**MAY be sold (Robux or DRIP), because none of it is capability:**
card frames and backgrounds · nameplate/banner and badge *chrome* styles (pairs
with `football-broadcast-ui.md` and `cosmetics.md` §3.1) · THE TAPE presentation
skins · a lobby card-showcase display · the existing seven cosmetic categories ·
a Season Pass **whose entire paid track is cosmetic**.

**MUST NEVER be sold, in any form, bundled or otherwise — this is a prohibition
list, not a preference:**
XP · XP multipliers, boosts or "double XP" of any kind · attribute points ·
ratings · respecs or archetype changes · badges or badge tiers · route, move,
playbook or AWARENESS-read unlocks · level skips · "catch-up" or "veteran" bundles ·
removal of the daily decay · private-server XP · any paid random reward (already
banned by `cosmetics.md`) · **any cosmetic whose name or art asserts a rating**
(a purchasable "99 OVR" frame is a lie the store is telling).

**The grey zone, decided here so it is not decided accidentally:** a Season Pass
may contain XP **only on its free track**. A paid premium track that grants XP is
pay-to-win under this document's definition, because XP buys ability and the
definition has to hold even when the conversion is two steps long.

**Revenue is not harmed by this.** `cosmetics.md` already establishes the earnable
seven categories and a 49–399 Robux premium cosmetic tier; THE COME UP *adds*
sellable surface (card frames, TAPE skins, badge chrome, showcase) without touching
a single gameplay constant. On a kid-heavy platform, "you cannot buy a better
player here" is the trust asset that makes the cosmetic spend durable.

---

## 4. Formulas

All [ASSUMPTION] unless the input constant is cited to a file.

### 4.1 Rating scaling — the one function everything goes through

    n(r)              = clamp((r - 70) / 29, -1, +1)
    scale(v70, r, h)  = v70 * (1 + h * n(r))                 -- "up" attributes
    scaleDown(v70,r,h)= v70 * (1 - h * n(r))                 -- attributes where LOWER is better
    final             = clamp(scale(...), hardMin, hardMax)  -- §3.3 per-constant clamps

| Symbol | Type | Range | Meaning |
|---|---|---|---|
| `r` | int | 41–99 (players 70–99) | the rating |
| `n` | float | −1 … +1 | normalized rating; **0 at exactly 70** |
| `v70` | float | the shipped constant | from `src/football/team/Config.lua` |
| `h` | float | 0.015 – 0.15 | half-range, per §3.3 |

**Properties, each an acceptance criterion:** `n(70) = 0`, so `scale(v70, 70, h) =
v70` exactly for every `h` (F3 — the no-regression proof). Monotonic in `r`.
Bounded in `[v70(1−h), v70(1+h)]`. Pure: no Instances, no RNG, no `os.clock`.

**Worked example 1 — SPEED, `h = 0.025`, `v70 = move.wrSpeed 9.6`:**
`r = 99` → `n = 1` → `9.6 × 1.025 = 9.84 m/s`. Against a 70 DB at
`dbSpeed 9.3 m/s`: the gap grows 0.54 m/s instead of 0.30. Over a 10 m vertical
release (≈1.05 s) that is **0.57 m of extra separation vs 0.32 m** — about 14 cm
of the DB's `coverage.cushionMinM 1.8 m`. Felt on film; not decisive on the play.

**Worked example 2 — THROW POWER, `h = 0.015`, `v70 = qb.throwSpeedMax 27`:**
`r = 99` → `27 × 1.015 = 27.405` → clamped to `ballPhysics.releaseDeepCaseMps`
**27.4 m/s**. `r = 41` → `26.595`. The entire player range sits inside the sourced
real-world band (`releaseEliteMps 25.0` … `releaseCeilingMps 26.8` …
`releaseDeepCaseMps 27.4`), so no card can throw a ball physics says is impossible.

**Worked example 3 — HANDS at the threshold, `h` expressed as an absolute +0.05
on `catch.det.threshold 1.0`:** take the shipped deterministic model with a
contested over-the-shoulder ball at 16 m/s relative, 2.0 m arrival height, chest
1.50, two hands:
`height = max(0, |2.0−1.5| − 0.45) × 0.55 = 0.0275`;
`speed = (16 − 14.0)/12.0 = 0.1667`; `facing = 0`;
`overShoulder = 0.22`; `contested = 0.30` → **difficulty = 0.714**.
Caught at threshold 1.00 and at 1.05 alike. Now one hand: `× oneHandMul 1.30 =
0.928` — still caught. Add `stretch = 0.92`: `+ (0.92−0.85) × 2.2 = +0.154` →
**1.082**. At threshold **1.00 → DROP** (inside `dropBandM 0.35`, so the message is
"dropped — fingertips"). At a 99-HANDS threshold **1.05 → CATCH, "one-handed
grab."** That single rep is exactly the intended size of the whole system: the
rating decides the 8%-of-cases ball, and the reason string says which term did it.

### 4.2 Overall (OVR)

    OVR(position) = round( Σ w[position][a] * r[a] )

Weights sum to 1.0 per position [ASSUMPTION]:

| | SPD | ACC | HND | RTE | RCH | PWR | ACU | TKL | COV | PHY | ELU | STA | AWR |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **QB** | .08 | .05 | — | — | — | .20 | .30 | — | — | — | .05 | .07 | .25 |
| **WR** | .20 | .10 | .25 | .22 | .08 | — | — | — | — | — | .10 | .05 | — |
| **DB** | .20 | .10 | .05 | — | — | — | — | .15 | .28 | — | .07 | .05 | .10 |
| **CARRIER** | .20 | .12 | .12 | — | — | — | — | — | — | .20 | .24 | .12 | — |

The card shows **OVR for the archetype's primary position** large, and the other
three small. A uniform-70 rookie is **70 OVR at every position**; a 125-point
DEEP THREAT is roughly **85 OVR at WR and 71 at DB**. That asymmetry is the
system's actual output: specialization, legible at a glance.

### 4.3 XP and levels

    xpToLevel(L)  = round(200 * L^1.4)                 -- XP for level L, L = 1..25
    xpTotal(L)    = Σ_{i=1..L} xpToLevel(i)
    matchXp       = min( Σ paid events , 600 ) + 0.25 * max(0, Σ events - 600)
    effective     = matchXp * dayMul * lobbyMul
    dayMul        = clamp(1 - 0.15 * floor(matchesToday / 3), 0.40, 1.00)
    lobbyMul      = 0 (private server) | 0.25 (fewer than 2 humans) | 1.0

| Symbol | Range | Meaning |
|---|---|---|
| `L` | 1–25 | level; 25 is max |
| `matchXp` | 0–~900 | pre-multiplier match XP, soft-capped at 600 |
| `dayMul` | 0.40–1.00 | daily decay |
| `lobbyMul` | 0, 0.25, 1.0 | anti-farm gate |

**Worked example — pacing.** `xpTotal(10) ≈ 23,400`; `xpTotal(25) ≈ 197,600`. At a
measured-later average of ~450 effective XP per match: **level 10 ≈ 52 matches**
(the point at which `sluggo` is in sight and a build is visibly specialized),
**level 25 ≈ 440 matches** (~110 h at 15 min a match). Target band: level 10 inside
**40–70 matches**, level 25 inside **350–550**. If measured pacing lands in the
band, do not touch it; if it misses, **move `xpToLevel`'s coefficient, not the
event table** — the event table also paces DRIP (§3.5).

### 4.4 Point budget

    budget(L)  = 5 * L                                   -- 125 at level 25
    cost(a, r) = 1 if r < softCap(archetype, a) else 2
    spent      = Σ_a Σ_{k=71..r[a]} cost(a, k)
    invariant  = spent <= budget(level)      -- checked server-side on every allocation
    hardStop   = r[a] <= min(99, softCap(archetype, a) + 10)

**Worked example — a level-25 DEEP THREAT.** Budget 125. SPEED 70→99 = 29 points
(99-capable, 1/pt). ROUTE RUNNING 70→95 = 25. ACCELERATION 70→92 = 22. HANDS
70→85 = 15 (at its 85 soft cap, all 1/pt). ELUSIVENESS 70→85 = 15. STAMINA 70→85 =
15. **Total 121 of 125**, with TACKLING, COVERAGE, PHYSICALITY, THROW POWER,
ACCURACY, REACH and AWARENESS all at **70 — identical to a brand-new player.**
That is the design working: against this card, a rookie DB is at zero disadvantage
in COVERAGE, SPEED is 9.84 vs 9.3 (the matchup), and the rookie's counter is the
cushion the coverage state machine already gives him.

### 4.5 Badge delta cap

    spread(key)      = |v70 * h(key)|                       -- the full 70->99 rating swing
    maxBadgeDelta    = 1.5 * spread(key)
    totalMultiplier  = (rating factor) * (badge factor)
    require |totalMultiplier - 1| <= 0.12                   -- hard, enforced in Growth.scale

**Worked example.** `pedal.flipTime 0.18`, COVERAGE `h = 0.12` → `spread = 0.0216`.
MIRROR gold's delta is 0.18 → 0.155 = **0.025**, which exceeds
`1.5 × 0.0216 = 0.0324`? No — 0.025 < 0.0324, legal. Combined with a 99 COVERAGE
rating: `0.18 × 0.88 = 0.1584`, then MIRROR's 0.025 → `0.1334`, a total factor of
**0.741 — which violates the 0.12 cap.** So `Growth.scale` clamps the stack to
`0.18 × 0.88 = 0.1584`, and the badge contributes nothing on an already-maxed
card. **This is intended and must be surfaced on the card** ("MIRROR: capped — your
COVERAGE already maxes this"), or players will believe a badge is working when it
is not.

---

## 5. Edge Cases

Each states what happens, not that it is handled.

1. **No profile / first join.** A uniform-70 card is synthesized in memory, OVR 70,
   archetype `UNSET`, 0 points. The player plays today's build exactly. First save
   happens at the first final whistle, not at join.
2. **`nil` or malformed card reaches `CFG:get`.** Returns `v70` unchanged and
   increments `stats.cardMissing`. It never errors and never returns `nil` into a
   physics calculation. Failing safe = failing to the shipped constant.
3. **Rating outside 41–99** (corrupt profile, bad migration). `n` is clamped, the
   rating is written back clamped, and the event is logged. No rating is ever used
   unclamped.
4. **Level-up mid-match.** XP is credited at the final whistle only; a level-up
   mid-match is impossible by construction. Points become spendable in the lobby.
5. **Allocation during a match.** Refused: `"LOCKED UNTIL THE FINAL WHISTLE"` —
   same rule and same string as a cosmetics equip (`cosmetics.md` §3.3). A card is
   snapshotted at kickoff and is immutable for the match, so no constant can change
   between two plays of the same drive.
6. **Two equipped badges target the same constant.** Refused at equip with
   `"ONE BADGE PER STAT — SWAP, DON'T STACK"`. Never silently resolved.
7. **Badge capped by the leverage ceiling** (§4.5 worked example). The badge still
   fires its reason string but reports `capped = true`, and the card shows it.
8. **Scaled value crosses a sourced ceiling.** Clamped (`qb.throwSpeedMax` ≤ 27.4).
   The clamp is in `Growth.scale`, so no call site can forget it.
9. **A scaled value crosses a rules threshold.** `tackle.reach` at 99 TACKLING is
   1.404 m, still well under `lungeReach 1.7`; `pedal.speed` at 99 is 6.86 m/s,
   still under `dbSpeed 9.3`. **Any new mapping must be checked against the
   thresholds its constant is compared to** — that check is acceptance F11.
10. **DataStore unavailable / Studio API access off.** Ephemeral profile, `PARITY`
    forced on, HUD line shown, nothing saved, no XP credited (so a player cannot
    farm an unsaved session and cannot lose a saved one to a phantom write).
11. **DataStore write fails at the final whistle.** The session cache stays
    authoritative with retry/backoff; XP is never credited twice (idempotent by
    `audit.lastMatchId`). A replayed match ID grants nothing.
12. **Profile from a newer `v`.** Loaded read-only; the player can play (at
    `PARITY`) but not allocate. Never coerced, never pruned.
13. **Player leaves mid-match.** No completion/win XP; event XP already accrued in
    the session is credited at disconnect if `lobbyMul > 0`, so a crash is not a
    total loss but quitting a losing match is not profitable.
14. **Rejoin after a disconnect into the same match.** The kickoff card snapshot is
    reused; XP already credited for that match ID is not re-credited.
15. **Archetype `UNSET` with points to spend.** All attributes treated at the 85
    soft cap until an archetype is chosen; choosing one re-validates spend and, if
    the chosen archetype makes a spend illegal, grants a free respec automatically.
16. **Respec requested with an illegal resulting build.** Refused whole; a respec
    is atomic, never partial.
17. **AI card in an empty or one-sided lobby.** AI cards are generated from the mean
    OVR of **human** players present; with no humans present (shouldn't happen),
    AI is 70. AI never exceeds the lobby mean by more than 5 OVR.
18. **Practice Field XP overflow.** `practiceXp` is capped at 150/day on a UTC
    `dayKey`; past the cap events are acknowledged with a HUD line and pay 0, so
    the player is told rather than silently farming nothing.
19. **Clock rollover / UTC day change mid-session.** `dayKey` is re-read at each
    final whistle; `matchesToday` resets on change. A player who plays across
    midnight gets the reset, which is a player-favourable choice made on purpose.
20. **Degenerate strategy — pitch-and-catch farming.** Two cooperating players
    maximize catch XP. Mitigated by the per-type cap (6 catches/match), the
    same-opponent decay, the private-server zero, and the requirement that XP
    follow a server-resolved reason. Residual exposure: a public 2v2 of four
    cooperating players. **Accepted** — it yields ~60 XP/match over the match floor
    (75+100), i.e. farming is strictly worse than playing. That is the test a
    mitigation has to pass: not "impossible" but "not optimal."
21. **Degenerate strategy — stat-stuffing the DB side.** Swat XP (20, cap 5) could
    encourage spamming the swat press. Mitigated by feel-upgrades #7's
    `swatLockout 0.5 s`, which prices the press. **Swat XP must not ship before
    that lockout does** — otherwise the XP rewards the exact spam the lockout
    exists to stop.
22. **Degenerate strategy — the SPEED monobuild.** If SPEED's 2.5% band still wins
    every matchup, the symptom is a win-rate skew by SPEED rating in the Stage 2/3
    data, and the fix is the band, not an added counter. **Pre-committed: SPEED's
    half-range may be reduced to 0 without redesign.** Every band in §3.3 is
    allowed to go to zero; the system still works as branch C.
23. **Healthy mastery vs degenerate play (Sirlin).** Learning that a 99-SPEED DEEP
    THREAT must be played with a larger cushion is mastery and should be *taught*
    by the pre-snap card read (§3.8). Queue-dodging a high OVR, or farming XP in a
    rigged lobby, is degenerate and is priced out above.
24. **A rating decides an outcome and no string names it.** This is a **defect, not
    an edge case**, and blocks the story (acceptance E2, Definition of Done §D's
    last box).

---

## 6. Dependencies

| System | Direction | Contract |
|---|---|---|
| `AWFootball.Config` / `Rules` (mirrors in `src/football/team/`) | **reads (scaled)** | THE COME UP provides `CFG:get(key, card)`; it requires that every scalable key stays in config and that no service reads a scalable key directly (F10). It changes **no** rule function |
| `TeamFootballService` | bidirectional | provides: the kickoff card snapshot, scaled constants, the XP credit at the final whistle. requires: the match-event BindableEvent, the final-whistle signal, the match ID, human/AI roster |
| `DripService` / `cosmetics.md` | **shared input only** | both subscribe to the same event spine. **No data flows between them in either direction.** DRIP cap 250/match and the XP cap are independent (§3.5). Any event-set change must be priced in both docs in one change |
| `football-feel-upgrades.md` | pairs | #1 (deterministic catch wiring) is a **hard prerequisite** for HANDS; #7 (`swatLockout`) for swat XP; #5/#6 supply the `sluggo` and pump-fake unlocks; #8 supplies breakaway XP |
| `football-playbook.md` | pairs | supplies the 15-play book that levels 18+ unlock; this doc requires the playbook data to live in `Config.playbook` as that doc specifies |
| `football-broadcast-ui.md` | pairs | THE CARD and THE TAPE use its chrome tokens (`NAVY`, `GOLD`, `NAVY_LIGHT`, `SHEEN`, GothamBlack/Bold, `viewK()`, 10/12 px corners, GOLD 2 px stroke); badge banners reuse its lower-third anatomy; the **clean-feed rule** forbids card data on screen during live play |
| `football-core.md` | law + blocker | the cosmetic-only monetization law and P1 bind this doc. **OPEN-DECISIONS D (avatar-measured reach) blocks CATCH REACH**; A1 (catch model) is already resolved to `deterministic`, which HANDS depends on |
| `football-ruleset.md` / `ballPhysics` | hard clamps | supplies `releaseEliteMps 25.0`, `releaseCeilingMps 26.8`, `releaseDeepCaseMps 27.4` as the THROW POWER ceiling. Rules and ball physics are **never** attribute-scaled |
| `AWHoops` / `Tuning3` | blocked | §3.4: four of seven basketball attributes are blocked on measurement or on fairness bugs in the live build |
| THE GAUNTLET | pairs | the natural home for a `PARITY = true` ranked ladder (branch A) |
| DataStore / platform | persistence | `AWGrowth_v1`, separate from `AWDrip_v1`; idempotent credit by `lastMatchId` |
| `systems-designer` | delegate | per-attribute band calibration and the badge delta table |
| `economy-designer` | delegate | every XP value, the level curve coefficient, the caps |
| `analytics-engineer` | delegate | win rate by OVR delta — the single metric that decides whether Stage 2 proceeds |

**Bidirectionality debt — not silently fixed.** The design-doc standard requires
dependencies to be mutual. Adding reciprocal mentions of THE COME UP to
`cosmetics.md`, `football-core.md`, `football-feel-upgrades.md`,
`football-playbook.md` and `football-broadcast-ui.md` is a **pending edit to five
existing documents and is not made by this draft** — it needs the owner's go-ahead,
since those docs are the current record of a shipped or queued system.

---

## 7. Tuning Knobs

All live in `AWGrowth.Config`, never hardcoded, per the data-driven standard.

| Knob | Default | Safe range | Category | Rationale |
|---|---|---|---|---|
| `PARITY` | **true** | true / false | **gate** | Off = attributes inert. The master switch; default on through Stage 1, permanent for any ranked mode |
| `ratingMin` / `ratingMax` | 70 / 99 | 70 / 99 (players) | gate | 70 = the shipped build. Raising `ratingMin` above 70 would put a newcomer below today's game — **never do this** |
| `band.speed` | 0.025 | 0 – 0.04 | **curve** | Highest-leverage constant (§3.3). Allowed to go to 0 |
| `band.hands.threshold` | 0.05 abs | 0 – 0.08 abs | curve | Master dial of the catch model; absolute, not fractional, on purpose |
| `band.hands.comfortSpeed` | 0.08 | 0 – 0.12 | curve | |
| `band.throwPower` | 0.015 | 0 – 0.015 | curve | Ceiling is physics, not taste — do not raise |
| `band.tackling` / `band.coverage` | 0.06 / 0.12 | 0 – 0.10 / 0 – 0.15 | curve | COVERAGE's band is wider because `flipTime` is a *time to decide*, not a speed |
| `band.stamina` | 0.15 | 0.05 – 0.20 | **feel** | Lowest-leverage, highest-felt. Tune by playtest |
| `band.elusiveness` | 0.10 | 0 – 0.15 | feel | Cooldowns only |
| `band.reach` | **0** | 0 until OPEN-DECISIONS D | gate | Ships at 0. Non-zero requires the reach decision first |
| `leverageCap` | 0.12 | 0.05 – 0.15 | curve | The hard ceiling on rating × badge. Lowering it is always safe |
| `xp.event[*]` | §3.5 | ±50% | curve | **Move with `cosmetics.md` §3.2 in the same change** |
| `xp.matchCap` / `softRate` | 600 / 0.25 | 400–900 / 0–0.5 | gate | Session-length pacing |
| `xp.typeCap[*]` | §3.5 | ±50% | gate | The real anti-farm lever |
| `xp.dayDecayStep` / `floor` | 0.15 / 0.40 | 0.05–0.25 / 0.25–1.0 | gate | Grind pressure; 1.0 floor disables decay |
| `xp.lobbyMul.private` | **0** | 0 only | gate | Matches DRIP's safer option. Do not expose a non-zero value |
| `xp.practiceDailyCap` | 150 | 0–300 | gate | Keeps the Ball Lab alive without making it optimal |
| `level.coef` / `level.exp` / `level.max` | 200 / 1.4 / 25 | 120–300 / 1.2–1.6 / 15–30 | curve | Tune pacing **here**, not in the event table (§4.3) |
| `points.perLevel` | 5 | 3–7 | curve | Directly sets how specialized a maxed card can be |
| `badge.equipMax` | 3 | 1–3 | gate | More than 3 defeats the one-sentence legibility test |
| `badge.deltaMul[tier]` | 0.4 / 0.7 / 1.0 | — | curve | Bronze/silver/gold |
| `respec.freeBelowLevel` / `perSeason` / `cooldownDays` | 10 / 1 / 7 | 5–15 / 0–3 / 0–14 | gate | **`respec.robuxPrice` must not exist as a key** |
| `tape.enabled` | true | true only | gate | THE TAPE is the P1 surface for progression, not a preference |

---

## 8. Acceptance Criteria

Per `docs/practice/DEFINITION-OF-DONE.md`. **No headless CI exists** — evidence is
the ordered manual verification of `ROBLOX-PRACTICE.md` §4: `loadstring` compile →
evaluate without `require` → pure-Luau Command Bar harness in
`tests/roblox/growth/` with retained PASS lines → playtest with zero console
warnings/errors → retained screenshot in `production/qa/evidence/`.

**Functional** (harnesses in `tests/roblox/growth/`, PASS lines retained):

- [ ] **F1 `Growth.scale` is pure and monotonic.** No Instances, no RNG, no
      `os.clock`. Strictly monotonic in `r` across 41–99 for every mapped key.
- [ ] **F2 every mapped key exists.** For each entry in the attribute→constant
      table, a `script_grep` hit proves the key is present in the live
      `AWFootball.Config` and read by a service. A mapping onto a key nothing reads
      is a mapping onto nothing (DoD §A).
- [ ] **F3 NO-REGRESSION — the critical one.** For every mapped key,
      `Growth.scale(v70, 70, h) == v70` **bit-for-bit**, and a full match played
      with all cards at 70 produces byte-identical config reads to a match with the
      system disabled. Turning THE COME UP on must change nothing until a point is
      spent.
- [ ] **F4 clamps hold.** 99 THROW POWER yields `≤ 27.4`
      (`ballPhysics.releaseDeepCaseMps`). Ratings outside 41–99 are clamped and
      written back clamped. `nil`/malformed card returns `v70`.
- [ ] **F5 leverage cap.** No combination of rating and badge produces a total
      multiplier outside `[0.88, 1.12]`; a capped badge reports `capped = true`.
- [ ] **F6 badge laws.** Two badges on one constant are refused; a 4th equip is
      refused; every badge table has exactly one `effect.key` and a non-empty
      `reason`.
- [ ] **F7 XP caps.** A synthetic 20-TD match grants `matchCap` plus the soft rate,
      not more; each per-type cap binds; `dayMul` floors at 0.40; private-server
      and <2-human multipliers apply.
- [ ] **F8 idempotent credit.** A replayed `lastMatchId` grants 0 XP. A simulated
      DataStore failure then success credits exactly once.
- [ ] **F9 migration round-trip.** A `v1` profile survives `Migrations` with
      unknown keys preserved; a `v2` profile loads read-only without error.
- [ ] **F10 one accessor — the fairness proof, mechanized.** `script_grep` shows
      **no service reads any scalable key directly**; every read goes through
      `CFG:get`, and the same call site serves humans and AI. Run on every COME UP
      change.
- [ ] **F11 threshold safety.** For every mapped key, its value at rating 99 is
      compared against every rules threshold it is tested against
      (`tackle.reach` vs `lungeReach`, `pedal.speed` vs `dbSpeed`,
      `secureReach` vs `aggressiveReach`) and no ordering inverts.
- [ ] **F12 separation from DRIP, both directions.** No gameplay or growth module
      reads the cosmetics catalog/profile, **and** no cosmetics module reads the
      growth profile. (The bidirectional form of `cosmetics.md` F5.)
- [ ] **F13 PARITY.** With `PARITY = true`, every scaled read equals `v70` and
      unlocks and badges still function.
- [ ] **F14 OVR arithmetic.** Position weights sum to 1.0; a uniform-70 card is 70
      OVR at all four positions; the §4.4 worked build reproduces its stated spend
      and OVRs.
- [ ] **F15 budget invariant.** No allocation sequence can exceed `budget(level)`;
      an illegal respec is refused whole; soft-cap double-cost is applied.
- [ ] **F16 offline fallback.** With DataStore unavailable, the profile is
      ephemeral, `PARITY` is forced on, 0 XP is credited, and the HUD line is
      present.

**Experiential** (playtest + retained screenshots, with one
`Run result: OBSERVED | NOT VERIFIED | N/A — <reason>` line per story):

- [ ] **E1 the fairness test, measured.** The same tester plays both sides of a
      70-OVR vs 85-OVR 1v1, 20 reps each way. **Target: the lower card wins ≥ 35%
      of reps.** Below that, the band is too wide and §7's bands come down. This is
      the single experiential criterion that decides whether Stage 2+ ships.
- [ ] **E2 every rating- or badge-decided outcome names itself.** 20 consecutive
      contested reps reviewed; each outcome's on-screen reason names the term and
      its source. **Any unnamed one blocks the story** (DoD §D, last box).
- [ ] **E3 THE TAPE.** Screenshot of the post-match screen on phone, gamepad and
      KB/M: box score, per-phase grade, and **every XP line named by source**.
      Touch targets ≥ 1 cm²; `viewK()` scaling only.
- [ ] **E4 THE CARD.** Screenshot of the card at 70 uniform (new player) and at a
      125-point build. The new player's card must read as **"unspecialized, not
      punished"** — owner sign-off required, the same bar `cosmetics.md` E5 sets for
      the default look.
- [ ] **E5 clean feed.** Screenshot during live play showing **no card data on
      screen**, per `football-broadcast-ui.md`'s clean-feed rule. Pre-snap card read
      appears only in the pre-snap phase.
- [ ] **E6 the owner reads a loss.** The owner plays one match against a
      higher-OVR card, loses a rep, and states the cause unprompted. If he says
      "he's just better," the system has failed P1 and the reason strings, not the
      bands, are the fix.
- [ ] **E7 no-regression by feel.** Owner plays a 70-vs-70 match with the system on
      and confirms it feels identical to the current build (pairs with F3).

**Known limitations, dated 2026-11-02** (DoD §E — a limitation that is not written
down is a defect):

1. **Basketball is blocked**, not deferred: four of seven attributes sit on
   hardcoded literals, an unread rebound resolver, or live human/AI asymmetries
   (§3.4).
2. **ACCURACY has nothing to scale for a human QB** — the team product applies no
   error term to a human throw (§3.3).
3. **CATCH REACH ships at band 0** pending `football-core.md` OPEN-DECISIONS D.
4. **HANDS depends on feel-upgrades #1** (wiring the deterministic catch model's
   inputs) being done first.
5. **Swat XP depends on feel-upgrades #7** (`swatLockout`) shipping first.
6. **Every number in §3.5, §3.7 and §4.3–4.5 is `[ASSUMPTION]`** and has never been
   playtested.
7. **The five reciprocal dependency edits (§6) are not made.**
8. **This system is parked by owner instruction.** Nothing here is scheduled.
