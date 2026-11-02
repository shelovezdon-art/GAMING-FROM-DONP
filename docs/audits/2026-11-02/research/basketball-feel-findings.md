# Basketball feel — measured findings (2026-11-02)

Prompted by owner playtest feedback: *"the court is kind of bunching up too much… no reward for playing
good defense and getting rebounds… make it more physical and have more space… I want to shoot threes but
the dude's running next to me."*

Everything here is measured off the live place and the live source. **No code was changed** — the device
bridge dropped before the build phase. This doc exists so the measurements survive.

## 1. The court does NOT need to be bigger — the premise was wrong

| Built (studs) | × 0.35 | Code expects | |
|---|---|---|---|
| 98.2286 | 34.380 m | `G.length = 28.65 × 1.2` | exact |
| 52.2514 | 18.288 m | `G.width = 15.24 × 1.2` | exact |
| 16.7314 (lane) | 5.856 m | `laneHalf × 2 = 2.44 × 1.2 × 2` | exact |
| 6.5357 (board) | 2.288 m | `boardW = 1.83 × 1.25` | exact |
| 8.7143 (rim) | 3.050 m | `rimHeight = 3.05` | exact |

The court is **already 1.2× regulation** horizontally (`GEO.COURT = 1.2`) with the rim deliberately left at
regulation height. At 34.38 × 18.29 m for six players that is **104.8 m² per player against 43.7 m² for an
NBA 5v5** — roughly 2.4× an NBA player's floor. Enlarging it would stretch rotations and push the 8.69 m arc
further out for no gain. **Recommendation: do not enlarge the court.**

Dimensions come from the **instances** (`Core:buildCourt` reads HoopA/HoopB/CenterAnchor/CourtSurface and
multiplies by `STUD = 0.35`), not from Tuning3 — so any future resize is a geometry edit the code picks up
automatically, with only spacing spots and shot ranges living code-side in `GEO.COURT`.

## 2. The real cause of bunching: bodies pass through each other, and only AI gets pushed

- `Hoops3Modules.Roster:19` — `CollisionGroupSetCollidable("AWHoopsPeople", "AWHoopsPeople", false)`.
  Basketball athletes **have no mutual collision at all** (football and soccer copy the same pattern).
- The only separation is `Body:softContact` (`Body:60-88`) at `personalSpace = 0.72 m`, and its push weights
  are **nonzero only for `a.kind == "ai"`** (`Body:76-77`) — **a human is never displaced; only the AI is
  shoved aside.** That is simultaneously the owner's complaint and a violation of the fairness pillar
  (identical rules for humans and AI).
- `T.move.contactSlow = 0.55` is read in exactly one place — `Hoops3Client:648`, **client-side,
  human-handler-only**, never server-enforced, never applied to AI.
- 0.72 m = 2.06 studs centre-to-centre against a ~2-stud R15 torso, so bodies visually overlap even at the clamp.

**This, not square footage, is why players jumble.**

## 3. A contest model already exists — it just isn't decisive or legible

`Play.contest` (`Play3:40-64`), called at `BallCtl:618` (meter window), `:646` (make), `:526` (lob), `:876`,
and `Brain:432` (AI shot selection). Terms: distance within `radius = 2.1 m`, a between-ness term
(`inFront = 0.35`), and a hands-up bonus (`handsUpBonus = 0.25`) when the defender's jump peak lands within
`contestJumpWindow = 0.35 s` of release; combined as `best + 0.35 × second`. The shot is a seeded roll
(`BallCtl:667`), so the fix is to extend the terms, not replace the model.

Expected points computed from live Tuning3 + Geometry (arc 8.688 m, `rangeMult` 0.683):

| Shot | Make | Expected pts |
|---|---|---|
| Open three, perfect release | 0.628 | **1.885** |
| Open three, good release | 0.478 | 1.434 |
| Contested three, perfect | 0.264 | 0.792 |
| Open layup | 0.860 | 1.720 |
| Contested layup | 0.301 | 0.602 |
| Open dunk | 0.970 | **1.940** |

So an open three beats an open layup by only 0.17 pts and still **loses to a dunk** — the owner's instinct
that spacing isn't rewarded is numerically correct. Reason strings exist (`BallCtl:675`: OPEN / LIGHT
CONTEST / CONTESTED / SMOTHERED) but the thresholds **0.15 / 0.45 / 0.75 are hardcoded there, not in
Tuning3**, and there is no WIDE OPEN tier.

## 4. Rebounds — specified, not verified

`Tuning3.rebound` defines a positional/timing model (`reach`, `bodyR`, `contestRange`, `tipBand`,
`secureTime`, `boxOut = 0.55`, `timing = 0.6`, `read`); `BallCtl:10` says rebounds go to whoever gets a hand
on it; `reboundContact` is at `BallCtl:300`; `ai.crashers = 1` caps the scrum; `ai.spacing = 4.32 m`.
**How it actually resolves was not read** (bridge died) — do not claim it is or isn't skill-based until
`BallCtl:280-400` and `Brain` are read.

## 5. DRIP is already wired for basketball
`DripService:124-133` handles `rebound` (with `m.offensive`), `block`, `steal`, `contestForcedMiss`, `bucket`
(with `m.three`); `Catalog.earn` carries reboundDef 12 / reboundOff 15 / block 18 / steal 18 /
contestForcedMiss 10 / bucket 6 / three 10, cap 250. Hoops3Service only needs to **fire** the events.

## The build order when the bridge returns
1. **Collisions + physicality** — give basketball its own self-colliding group; make `softContact`
   symmetric (humans get displaced too) and server-enforce `contactSlow` for both humans and AI.
2. **Make space decisive** — move the contest thresholds into Tuning3, add a WIDE OPEN tier, and raise the
   open-three reward until an open three is clearly the best shot in the game.
3. **Fire the DRIP events** from Hoops3Service (handlers and amounts already exist).
4. **Rebounds** — read the resolver first, then make position and timing decide it.
5. **Do not enlarge the court.**
