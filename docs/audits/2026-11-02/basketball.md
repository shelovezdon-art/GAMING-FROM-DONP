# ALLSTAR WORLD — Basketball audit (2026-11-02)

Read-only audit of the live Studio place. Nothing was modified.

## The two systems

- `ServerScriptService.HoopsService` (1038 lines) + `HoopsClient` (322) — half-court **1v1 vs CPU**, first to 21,
  12 s shot clock, check ball, clear-the-arc rule. Code-complete.
- `ServerScriptService.Hoops3Service` (204) + `Hoops3Modules/{Core,Roster,Body,BallCtl,Actions,Match,Brain}` (2857)
  + `Hoops3Client` (669) — **full-court 3v3**, HOME vs AWAY, 3 friend slots per team, AI fills the rest.
  **This is the real game.**

They were designed to coexist on different courts (`HoopsService:46` claims courts *without* `Mode3v3`;
`Hoops3Service:34` claims `CourtId == "bb-2"`). The October 2026 renovation collapsed the world to **one** court
and `HoopsService` was never migrated.

## Dead-but-running: the 1v1 has zero courts

The only `AWCourt`-tagged instance is
`Workspace.AllstarWorld.18_BasketballCourts.Outdoor_Park.Court_bb-2`, and `Mode3v3=true` is **persisted on the
saved model**, not merely set at runtime — so `discoverCourts` (`HoopsService:44-67`) rejects it deterministically,
regardless of script load order.

Consequences:
- `setupPrompts` (`:954-988`) creates **no** "Play 1v1 vs CPU" prompt → no entry point exists.
- The Quick Match `JOIN` binds loop (`:1013-1022`) binds nothing.
- A `Heartbeat` connection (`:970-975`) runs every frame over a permanently empty table.
- A `while true … task.wait(0.5)` loop (`:1023-1037`) runs forever over an empty list.
- `HoopsClient` sits on every client with its HUD built and `State.OnClientEvent` connected, never firing.

Not load-bearing: `Hoops3Modules.Roster:16-17` registers the `AWHoopsPeople`/`AWHoopsBall` collision groups itself,
so removing `HoopsService` would not break the 3v3.

## What is built (3v3) — substantial

- `Flow3` is a real guard, not documentation: an explicit legal-transition table (`Flow3:22-34`) whose `go()`
  refuses and counts illegal moves.
- One authoritative never-drawn ball part per game, published as attributes clients only read (`BallSync`).
- No engine physics on the ball: every rim-out, glass kiss and roll is a `BallPath` solved ahead and published
  segment-by-segment, so screens draw exactly the path the server rules on.
- Baskets count once, only going **down** through the ring (`rimCatch = 0.234 m`).
- Geometric rebounds: swept ball vs reach cylinder, jump timing, box-out, tip resolution.
- Layups / dunks / 360s / power finishes with physical gates (dunk needs ≤3.0 m, ≥3.4 m/s approach, 1.15 m
  clearance) and a 3.0 m travel cap — no warp to the rim.
- Alley-oops with an eligibility check and a timed FINISH window, explicitly "never a guaranteed score".
- Per-player token bucket (14/s, burst 8). Validated position claims (`Actions:216-231`) with NaN and 12 m/s
  sanity rejection.
- Team AI (`Brain`, 679 lines) routed through the **same** action doors as humans: 0.22 s decision, 0.24 s
  reaction, seeded release error. Verifiably fair — no AI bypass.

## Dribbling is largely already built — the big surprise

- `AWHoops.Dribble` (136 lines) is a pure function of `{hand, t0, move}` and the server clock, so server and every
  client compute an identical ball position.
- Seven moves with real differentiation (`Dribble.MOVES:18-27`). The per-move `exposed` multiplier is load-bearing:
  `Dribble.exposure:114-120` makes a crossover **2.2×** more stealable than a plain dribble and a spin **0.25×** —
  a genuine risk/reward economy.
- `DribbleLook` (195) adds per-move palm keyframes, a bounce-height curve, and a body channel carrying
  crouch/shift/yaw/roll/pitch/lead-foot/stance, plus a 0.16 s cross-fade out of moves.
- `BallView` (871) solves two-bone IK on the stock R15 rig, reading the palm back **after** the pose is applied so
  the ball leaves the hand where the hand really is, and builds a true sphere from four welded seam cylinders
  (no mesh asset).

**Hand-to-floor is real, not parented.** The headline ask is closer to done than expected.

## Top 5 gaps to the stated vision

1. **Half-court does not exist in live code** (vision: 2K-style half-court 1v1 + 3v3).
   `Court3` is hard-coded full-court: two hoops with each team permanently assigned one (`:41-44`), `inBounds`
   spans the whole floor (`:54-57`), `inboundSpot("made")` puts the inbounder behind the scored-on baseline
   (`:118-123`). No single-hoop mode, no half-court boundary, no clear-the-ball rule anywhere in `Hoops3`.
   Needs changes in `Court3` + `Match.setupInbound`/`scoreBasket` + `Flow3.afterMade`/`afterRecovery`.
   **Mitigating:** `ServerStorage.AW_Archive.Hoops3Service_halfcourt` (1233 lines) is a previously-working
   half-court 3v3 — port the rules, don't invent them. Medium-large; everything else depends on it.
2. **Two of three courts missing.** Only `bb-2` exists. `AW_Archive.Courts_preReno2026` holds `Outdoor_Skyline`,
   `Outdoor_Block`, `Outdoor_Park` — three outdoor courts existed once. The park aesthetic is **already correct**:
   `Style=outdoor-park`, `Venue=ALLSTAR PARK`, 152×111 deck, fencing, four 36-stud floodlights, DJ stage,
   BigBoard, open stands, no roof. Reinstating two neighbours into one park is mostly world work plus giving each
   a `CourtId`/`Modes` attribute. Medium; depends on (1) for what mode each hosts.
3. **Dribble input, not dribble mechanics.** Joystick flick already exists but is **gamepad-only**:
   `HoopsClient.stickFlick:148-161` and `Hoops3Client:337-343` read `Thumbstick2`, require 0.8 magnitude, latch
   until the stick returns inside 0.35, and map direction → move (◀▶ crossover, ▼ legs, ▲ hesi, ↙↘ behind).
   Touch gets discrete buttons (`TouchMoves:54-60`); mouse/keyboard gets Q/E/Z/B/H/C/V. The overhaul is:
   (a) a touch-drag flick reader reusing the same latch logic;
   (b) make flick direction **movement-relative** rather than screen-relative — `doMove` already resolves
       direction against the attacked rim (`Actions:94-109`), so only the client-side mapping changes;
   (c) a dedicated speed-dribble button on touch (currently SPIN-hold, 0.22 s, easy to mis-trigger);
   (d) port the ankle-breaker from `HoopsService:365-377`/`:446-457` (0.45 s reversal window, 0.9 s stumble) into
       `Actions:doMove`, which has no equivalent — the 3v3 lost it.
   Small-to-medium; no rewrite of `Dribble`/`DribbleLook` needed. Depends on nothing.
4. **No human 1v1 and no mode selector.** `Match.new` takes a single player and builds one `HoopsCPU_<id>`
   (`HoopsService:162-179`); `Hoops3` has no 1v1/2v2 variant. Cheapest path is a slots-per-team parameter on
   `Hoops3` after (1), retiring `HoopsService` rather than reviving it. Medium; depends on (1).
5. **Two diverging rules stacks** (`Rules`+`Config` vs `Play3`+`Tuning3`). The 1v1's perfect shot is a **1.00**
   guaranteed make; the 3v3's is 0.92 capped at 0.98. Keeping both means every balance change lands twice and
   drifts. Consolidate on `Play3`/`Tuning3` (fairer, better structured). Small-medium; best done with (4).

Also against the quality bar: there is **no monetization code at all** in basketball — nothing to fix for
cosmetic-only, it simply isn't built. No progression, stats or badges either.

---

# RISKS

## R1 (CRITICAL) — client-trusted shot meter allows guaranteed perfect shooting

Release time is measured entirely on the client (`HoopsClient:132-137`: `held = os.clock() - pressAt`) and the
server accepts it with a tolerance far wider than the reward band.

**1v1:** `HoopsService:902` — `held = Rules.clamp(held, elapsed - 0.25, elapsed)`. Jumper fill 0.75 s, target 0.88,
window 0.12, GREEN at `|e| ≤ w×0.25 = 0.03` → an honest player must hit a **45 ms** window; the accepted skew is
**250 ms**. Worse, the server *tells the client* `fill`, `w` and `target` in the meter message
(`HoopsService:513`). A modified client waits until `elapsed ≥ 0.6825`, then sends `held = 0.88 × 0.75 = 0.66` —
always inside the clamp, always GREEN — and `Config.shot.greenMake = 1.00`.
**Result: a deterministic 100% make rate on every shot, including threes.**

**3v3:** same shape — `Actions:247` clamps to `maxHeldSkew = 0.3 s` (`Tuning3.net:151`) against a perfect band of
`0.03 × 0.78 = 23 ms`, a 13× margin. Less catastrophic only because `baseMake.perfect = 0.92`, not 1.00.

Root cause is one validation gap, not a design choice: the trusted window must be no wider than the perfect
half-width, or the release must be timed from server receipt. **Not fixed.**

## R2 — dead `HoopsService` still executing
Keeps a per-frame `Heartbeat` and a 0.5 s infinite loop alive and publishes unusable remotes. Harmless today, but
it is 1360 lines of live code that looks like a working feature and will mislead the next change.

## R3 — needless replication load
`Hoops3Service:190-203` rewrites nine `Configuration` attributes every 0.5 s unconditionally → ~18 attribute
writes/sec to every client forever, even in an empty lobby. `sendHud` (`Match:283-305`) fires 10 Hz per human
carrying arrays of `Instance` references (`bodies`, `mates`, `holder`, `man`).

## R4 — client-authoritative character position and speed
The avatar is an ordinary client-owned Roblox character and `HoopsClient:306-312` writes
`hrp.AssemblyLinearVelocity` directly, so position and speed are client-authoritative. The server reads
`hrp.Position` for three-point determination, steal reach and contest. `Hoops3` mitigates with
`maxHumanSpeed = 12` in claim validation (`Actions:224`); `HoopsService` has only a crude `dist > 40` bail-out
(`:798`). Client-set `JumpPower` (`HoopsClient:117-123`) is likewise trusted.

## R5 — incoherent test hook
`Hoops3Service:103-105` looks up `TestHook3` in `ReplicatedStorage.AWHoops` but parents it to `ServerStorage`.
A pre-existing hook in `AWHoops` would be silently relocated.

## R6 — contradictory help text
`Hoops3Client:9`/`:181` tell controller users "right stick moves" while `:471` binds `Thumbstick2` to dribble
flicks.
