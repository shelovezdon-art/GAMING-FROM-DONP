# 7v7 Football Format + Clean Animation Reference — ALLSTAR WORLD

**Date:** 2026-11-02 · **Author:** game-designer research agent · **Status:** research reference, not a GDD.
**Scope:** (1) the real 7-on-7 passing-league format (no linemen), (2) what makes big football
games' animation read "clean", (3) Roblox/R15 feasibility, (4) prioritized recommendations.

> **Evidence honesty note.** The research environment had web *search* but no page *fetch*.
> Every claim is tagged:
> - `[VERIFIED — source]` — the linked source plainly confirms it (title/abstract-level, or an
>   official publisher page on exactly that topic).
> - `[ASSUMPTION]` — consistent convention across the rulebooks found and/or training knowledge;
>   **confirm against a linked rulebook before encoding a number in `Config`.**
> - `[GDD]` — read directly from `design/gdd/football-core.md` (audited against the build).
>
> 7v7 is not governed by one rulebook — every tournament/state association publishes its own.
> Numbers below are the *modal* convention; the Sources section lists actual rulebooks to pin
> exact values against when we write the ruleset GDD section.

---

## 1. The real 7-on-7 format (college/HS passing leagues)

7v7 is the offseason passing-league format colleges and high schools use: no linemen, no
blocking, no pads — it isolates exactly what we want to build (QB, routes, coverage, catches).
`[VERIFIED — Under Armour "What is 7 on 7 football", https://www.underarmour.com/en-us/t/playbooks/football/what-is-7-on-7-football-format]`

### 1.1 Common ruleset (modal values across tournament rulebooks)

| Rule | Modal convention | Tag |
|---|---|---|
| Players | 7 offense vs 7 defense; **no offensive or defensive linemen**; all players eligible receivers | [ASSUMPTION — universal across the rulebooks listed in Sources] |
| Field length | **40–45 yd** of playing field + 10 yd end zone; most tournaments start offense at the 40- or 45-yard line and play toward the goal line | [ASSUMPTION] |
| Field width | Full-width hash-to-sideline (53⅓ yd) or reduced; varies by venue | [ASSUMPTION] |
| Snap | No real snap — QB starts with ball ("ghost snap") or a non-blocking snapper tosses it back; play starts on referee whistle/QB's cadence | [ASSUMPTION] |
| QB release clock | **4.0 seconds** to release the ball (range seen: 3.5–4.5 s). Timer expiry = "sack" = dead ball, **loss of down** | [ASSUMPTION — 4.0 s is the most common figure in tournament rulebooks] |
| Pass rush | **None.** No rush, no blitz. The 4-second clock *is* the pass rush | [ASSUMPTION] |
| Running plays | **Not allowed.** Pass-only; QB may not scramble past the line; most leagues forbid handoffs (some allow one backward pass/screen behind the LOS) | [ASSUMPTION] |
| "Tackle" | **One-hand or two-hand touch** below the neck in most college/HS passing leagues (not flags); ball dead at spot of touch. Youth variants use flags | [ASSUMPTION] |
| First downs | Zone-based: cross the next zone line (commonly every **15 yd**, e.g. 45→30→15→goal), typically 3 downs per zone | [ASSUMPTION — zone size varies 10–20 yd by league] |
| Scoring | TD = **6** (some leagues 7); PAT by play: **1 pt from the 5**, **2 pt from the 10**; no kicking of any kind | [ASSUMPTION] |
| Defensive scoring | Interception commonly worth **2–3 pts** to the defense + possession; some leagues allow INT returns for 6, others blow it dead | [ASSUMPTION] |
| Play clock | ~**25 s** between plays (range 20–30 s) | [ASSUMPTION] |
| Game clock | Two **20-minute running-clock halves**, or a fixed play count / timed games of 20–25 min in tournament pool play | [ASSUMPTION] |
| Turnovers | Incompletions = next down; INT = ball to the other team at the standard starting spot (no return) in most tournament formats | [ASSUMPTION] |
| Overtime | Alternating possessions from a short field (e.g. the 10 or 15) | [ASSUMPTION] |

Representative rulebooks found (pin exact numbers against these):
- Premier Events USA 2026 7on7 tournament rules — https://cdn3.sportngin.com/attachments/document/df7b-3213884/2026_PremierEventsUSA_7ON7_PASSING_TOURNAMENT_RULES_MASTER_2.27.2026.pdf
- TAPPS (Texas private schools) 7on7/6on6 rules — https://tapps.biz/wp-content/uploads/2025/09/TAPPS-7-on-7-and-6-on-6-Rules.pdf
- Illinois 7on7 rules — https://www.7on7illinois.com/rules-regulations
- AAU Football 7-on-7 passing league guidelines — https://www.aaujumprope.org/football/7-on-7
- YMCA Fort Worth 2024 7on7 rules — https://ymcafw.org/wp-content/uploads/2024/05/2024-7-on-7-Football-Rules.pdf

### 1.2 Delta vs our documented IFAF-style 5v5 flag ruleset

Our current team modes run a 5v5 flag ruleset (TD 6 + declared try, timed halves) `[GDD — task
brief + football-core.md]`. The deltas that matter for design:

| Dimension | Our IFAF-style 5v5 (current) | Real 7v7 passing format | Design consequence |
|---|---|---|---|
| Players/side | 5 | 7 | +2 route runners / +2 coverage — needs zone coverage AI or more human slots |
| Field | ~50 × 25 m flag field [ASSUMPTION — confirm in GDD §rules] | 40–45 yd + 10 yd EZ, often full width (~41–50 m long, up to ~49 m wide) | Bigger horizontal space; route spacing and safety help become real |
| Contact | Flag pull | One/two-hand **touch** | Touch is *simpler* than our flag model — a proximity/contact check, no flag objects |
| Running game | Runs allowed (with no-run zones) | **Pass-only**, no handoffs | Deletes the run fit/pursuit problem — plays directly to the Practice Field's pass-first core |
| Pass rush | Rusher(s) permitted from a setback | **No rush**; 4-second release clock | Deletes pass-rush animation/AI entirely — the single biggest scope cut |
| QB clock | (per our GDD/IFAF convention) | **4.0 s** hard sack timer | A server timer we already know how to build; readable HUD element |
| First downs | Midfield line (IFAF convention) | Zone lines every ~15 yd | More frequent micro-goals → better meso-loop pacing |
| Try | Declared 1 pt (5 m) / 2 pt (12 m) | 1 pt from the 5 / 2 pt from the 10, pass-only | Nearly identical — keep our declared-try UI |
| Defensive INT | Possession change | Possession **+ 2–3 pts** in many leagues | Makes defense a scoring role — serves the defender fantasy (GDD §2) |
| Snap | Snap cadence w/ false starts (AWFootball) | Ghost snap / whistle start | Optionally keep our cadence — it's *more* football than real 7v7 has |

**Design read:** real 7v7 is almost exactly "our Practice Field plus coverage" — pass-only, no
rush, no blocking, no linemen. It is the lowest-animation-cost full-team football format that
exists in the real sport. `[ASSUMPTION — design inference]`

---

## 2. How the big games make animation read clean

### 2.1 EA Madden / College Football 25 (publicly documented tech)

- **BOOM Tech** — Madden NFL 25's physics-informed branching tackling: tackles select and
  branch animation using ball-carrier/defender momentum, weight and speed rather than playing
  one canned pair-animation. `[VERIFIED — EA official tech post, https://www.ea.com/technology//news/boom-tech-ea-sports-madden-nfl-25]`
- **Physics-based tackling + new catch mechanics** were the headline gameplay features of
  Madden 25's reveal. `[VERIFIED — https://gamingbolt.com/madden-nfl-25-reveal-trailer-highlights-physics-based-tackling-new-catch-mechanics-and-more]`
- **TrueStep locomotion** — EA's foot-planting locomotion tech (every step is a planted,
  physically plausible step; acceleration/deceleration/turn all cost time), marketed as a
  next-gen Madden pillar. `[VERIFIED — topic of https://www.osftw.com/news/638870/next-gen-madden-nfl-25-features-truestep-phase-matching-immersion-more]`
- **Gameplay deep-dives** (hit-stick refinement, tackle variety tiers, signature QB throw
  styles, pre-play presentation) — `[VERIFIED as topics — https://mut.gg/news/madden-nfl-25-gameplay-deep-dive, https://operationsports.com/madden-nfl-25-gameplay-deep-dive-and-impressions, https://worthplaying.com/article/2024/7/23/news/142893-madden-nfl-25-shows-off-gameplay-physics-based-tackling-signature-styles-pre-play-mechanics-and-more-new-features-screens-trailer]`
- CFB 25 shares Madden's tech base and differentiates on pace/variety (option game, wide-open
  spacing) rather than different animation tech. `[ASSUMPTION — training knowledge]`

### 2.2 What actually makes movement read "clean" (distilled)

These are the perceptual ingredients, in rough order of how much each contributes
`[ASSUMPTION — synthesis of the above + animation practice]`:

1. **Locomotion continuity** — idle↔walk↔jog↔sprint blend with no pops; stride rate matches
   ground speed (no foot-sliding/"ice skating"). Foot sliding is the #1 "cheap game" tell.
2. **Foot planting on direction change** — a visible plant step on cuts; the body *banks into*
   turns (lean) instead of rotating like a statue on a turntable.
3. **Momentum honesty** — the animation never shows a change the movement model didn't pay for.
   Our `Momentum` model already charges for cuts (GDD §3.3) — the animation must *show* the charge.
4. **Contextual catch variety** — over-shoulder, high-point, low scoop, sideline toe-tap,
   one-hand stretch. Selection must be *deterministic from geometry* (ball approach vector,
   height, separation) so the same catch always looks the same — which matches our
   deterministic catch model's philosophy (GDD §2).
5. **Throw styles** — bullet = compact fast arm, touch/lob = longer wind-up and follow-through;
   release timing matches the server's actual release tick.
6. **Transition ownership** — every state change (catch→run, plant→accelerate, touch/tag→dead
   ball) has a dedicated short transition animation; it's the *transitions*, not the loops,
   that read as quality.
7. **Secondary motion** — head tracks the ball (look-at), ball carried in a believable arm
   position, subtle idle sway.
8. **Moment presentation** — TD celebrations, first-down signal, a brief camera push-in on
   big catches. Cheap, huge perceived-quality return.
9. **Camera discipline** — stable chase/broadcast camera with mild lag and FOV kick at sprint;
   camera noise makes clean animation look dirty.

### 2.3 Smaller/arcade football games with no linemen

- Arcade titles (Wild Card Football, backyard-football style games) lean on exaggerated,
  readable silhouettes, big wind-ups and stylized catches instead of simulation blending —
  fewer animations, each more legible. `[ASSUMPTION — training knowledge]`
- Top Roblox football games (Football Fusion 2, Ultimate Football) are community-known for:
  magnet-then-animate catches (snap the ball to the hand, then play the catch pose), a small
  set of catch poses (over-shoulder, dive, one-hand) selected by geometry, jump-timing-based
  contested catches, and heavy reliance on dive/jump as the skill expression.
  `[ASSUMPTION — community knowledge; the web results for FF2 were SEO spam, nothing citable]`
- Lesson: **a small set of well-chosen, geometry-selected animations beats a large set of
  poorly blended ones.** 6–8 catch animations with deterministic selection is the FF2-tier bar.
  `[ASSUMPTION — design inference]`

---

## 3. Roblox / R15 feasibility

No native blend trees exist in Roblox; quality is achieved with these techniques:

| Technique | What it does | Tag |
|---|---|---|
| **Weighted track crossfade** — multiple looping `AnimationTrack`s (idle/walk/jog/sprint) playing simultaneously, blended with `track:AdjustWeight(w, fadeTime)` | Poor-man's 1D blend tree for locomotion | [ASSUMPTION — standard Roblox practice; see runtime threads below] |
| **New animation runtime / `AnimationWeightedBlendFix`** — Roblox replaced the legacy runtime; weighted blending semantics changed (normalized weighted blending), and the old property is being removed as the new runtime becomes default | Our weight math must assume the NEW runtime; don't copy pre-2023 forum blend code | [VERIFIED as topics — https://devforum.roblox.com/t/animation-engine-runtime-changes-and-fixes/1320674, https://devforum.roblox.com/t/new-animation-runtime-rollout-upcoming-property-removal/2018704] |
| **`track:AdjustSpeed(groundSpeed/strideSpeed)`** — scale animation playback to measured ground speed | Kills foot-sliding; the single highest-value code-only fix | [ASSUMPTION — standard practice] |
| **`IKControl`** (Position/LookAt/Transform on R15 limbs) | Foot planting on slopes/cuts; head/torso look-at tracking the ball | [ASSUMPTION — official Roblox API, standard use; confirm per-limb setup in docs] |
| **Procedural lean** — tilt `Root`/`LowerTorso` Motor6D `C0` by lateral acceleration | Banking into cuts without authoring per-angle animations | [ASSUMPTION — standard practice] |
| **Animation priorities** (Core < Idle < Movement < Action..Action4) for upper/lower split | Carry/throw/catch on upper body while legs keep locomotion | [ASSUMPTION — official priority system] |
| **Track-count limits** — legacy warning at **256 tracks per Animator**; the **Server Authority beta** imposes a much tighter per-Animator track budget (brief states **8**) | Pre-load one small pool of tracks per rig and reuse; never `LoadAnimation` per event. **Must verify the exact Server Authority number before architecting** | [VERIFIED — 256-limit warning thread https://devforum.roblox.com/t/arbitrary-warning-spamming-of-animationtrack-limit-of-256-tracks-for-one-animator-exceeded-new-animations-will-not-be-played/2878602; 8-track figure is [ASSUMPTION — stated in task brief; confirm in https://devforum.roblox.com/t/server-authority-studio-beta-updates/4503827]] |
| **Animation replication** — server-created `Animator` replicates client-played tracks; second/local Animators break replication | Keep ONE Animator per rig; play locally for responsiveness, replicate by default path | [VERIFIED as topics — https://devforum.roblox.com/t/animations-replicate-inconsistently/351907, https://devforum.roblox.com/t/creating-a-second-local-animator-breaks-animation-replication/4753287] |

**Hard constraint for us:** if we adopt Roblox Server Authority (which fits our
server-authoritative design), the tight per-Animator track budget means the whole animation
set must be organized as a few *composite* tracks + weight blending, not dozens of tiny
clips. This is an architecture decision, not a polish decision. `[ASSUMPTION — consequence of
the budget; verify the number first]`

---

## 4. Prioritized recommendations — top 10 animation improvements

For a no-linemen 7v7-or-5v5 flag/touch game, R15 rigs, in impact order:

| # | Improvement | Why first | Label |
|---|---|---|---|
| 1 | **Stride-synced locomotion**: `AdjustSpeed` from measured ground speed; crossfade idle/jog/sprint weights from `Momentum` state | Kills foot-sliding — the #1 cheap-game tell; `Momentum` already exposes speed | code-only |
| 2 | **Procedural lean into cuts** from `Momentum`'s turn deficit (`left` angle) | Makes the existing turn-cost model *visible*; zero new assets | code-only |
| 3 | **Plant-step animation on hard cut** — trigger a short plant clip when `Momentum` enters its >75°-at-speed plant branch | The model already has the discrete event (GDD §3.3); the animation just shows it | needs-animation-assets |
| 4 | **Catch animation set selected by geometry** (6–8: over-shoulder, high-point, chest, low scoop, sideline toe-tap, one-hand, dive, contested) chosen deterministically from the existing catch model's approach vector/height | Catches are our core moment; selection inputs already computed in `Receive` | needs-animation-assets |
| 5 | **Throw styles per pass type** — distinct wind-up/release for BULLET / TOUCH / LOB, release frame synced to server release | Pass types already exist (GDD §3.6); readable intent for the defender | needs-animation-assets |
| 6 | **Head/torso look-at ball via IKControl** during routes and flight | Biggest "alive" signal per unit of work; code-only once rig set up | code-only |
| 7 | **Catch→run / catch→secure transitions** matching the existing `recoverTime` speed caps (aggressive vs secure) | The caps exist (GDD §3.3) and currently read as invisible rubber-banding | needs-animation-assets |
| 8 | **Touch/flag resolution animation** — tag reach + ball-carrier "dead ball" pull-up (or flag pull), ~0.3 s, server-confirmed | The play-ending moment must read clean or nothing else matters | needs-animation-assets |
| 9 | **TD/first-down moment presentation** — celebration set + brief camera push + first-down signal | Macro-loop reward beat; cheap perceived quality | needs-animation-assets |
| 10 | **Animator track architecture for Server Authority** — pre-loaded pool, composite clips, weight blending within the per-Animator budget | Decides whether 1–9 are even implementable under the track limit | needs-decision |

**Also needs-decision (format):** adopt real-7v7 rules (pass-only, no rush, 4 s clock,
touch, zone first downs) as the team-mode ruleset vs keep IFAF 5v5 and only grow to 7v7 player
count. §1.2 shows 7v7 is the cheaper build. Owner call.

---

## 5. Sources

7v7 format:
- https://www.underarmour.com/en-us/t/playbooks/football/what-is-7-on-7-football-format
- https://cdn3.sportngin.com/attachments/document/df7b-3213884/2026_PremierEventsUSA_7ON7_PASSING_TOURNAMENT_RULES_MASTER_2.27.2026.pdf
- https://tapps.biz/wp-content/uploads/2025/09/TAPPS-7-on-7-and-6-on-6-Rules.pdf
- https://www.7on7illinois.com/rules-regulations
- https://www.aaujumprope.org/football/7-on-7
- https://ymcafw.org/wp-content/uploads/2024/05/2024-7-on-7-Football-Rules.pdf
- https://coachingkidz.com/what-is-7-on-7-football/
- https://d3d4football.com/what-is-7-on-7-football-rules-format-and-how-to-play/

EA animation tech:
- https://www.ea.com/technology//news/boom-tech-ea-sports-madden-nfl-25
- https://gamingbolt.com/madden-nfl-25-reveal-trailer-highlights-physics-based-tackling-new-catch-mechanics-and-more
- https://www.osftw.com/news/638870/next-gen-madden-nfl-25-features-truestep-phase-matching-immersion-more
- https://mut.gg/news/madden-nfl-25-gameplay-deep-dive
- https://operationsports.com/madden-nfl-25-gameplay-deep-dive-and-impressions
- https://worthplaying.com/article/2024/7/23/news/142893-madden-nfl-25-shows-off-gameplay-physics-based-tackling-signature-styles-pre-play-mechanics-and-more-new-features-screens-trailer

Roblox animation:
- https://devforum.roblox.com/t/animation-engine-runtime-changes-and-fixes/1320674
- https://devforum.roblox.com/t/new-animation-runtime-rollout-upcoming-property-removal/2018704
- https://devforum.roblox.com/t/arbitrary-warning-spamming-of-animationtrack-limit-of-256-tracks-for-one-animator-exceeded-new-animations-will-not-be-played/2878602
- https://devforum.roblox.com/t/server-authority-studio-beta-updates/4503827
- https://devforum.roblox.com/t/animations-replicate-inconsistently/351907
- https://devforum.roblox.com/t/creating-a-second-local-animator-breaks-animation-replication/4753287

Internal: `design/gdd/football-core.md` (audited 2026-11-02) — §2 Player Fantasy, §3.3 Movement,
§3.6 Passing.
