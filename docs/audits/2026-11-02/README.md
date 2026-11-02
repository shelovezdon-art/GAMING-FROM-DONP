# ALLSTAR WORLD — full project audit, 2 November 2026

A read-only audit of the live Roblox place plus web research, run overnight. **Nothing in the place was
modified.** Every finding below was measured from the code or the build, not inferred.

## Contents

| File | What it covers |
|---|---|
| `football-core.md` | Football audit. Feeds the rewritten `design/gdd/football-core.md`. |
| `basketball.md` | `HoopsService` (1v1) and `Hoops3Service` (3v3), dribble systems, courts. |
| `soccer.md` | `SoccerService`, `AWSoccer`, touch model, camera, stadium. |
| `crowd-and-athletes.md` | `CrowdAnimator`, `FootTraffic`, `AthleteMotion`, `AWMotion`, press/fans, athlete bodies. |
| `venue-quality.md` | 18 areas scored, 38 defects, regulation dimensions, strip-down status, reusable checklist. |
| `inventory.md`, `performance.md`, `cleanup-plan.md`, `looks.md` | World weight, mobile performance, ordered cleanup plan, visual read. |
| `research/` | Roblox sports-game landscape, verified API behaviour, dribbling techniques, performance budgets, licensing, monetization. 114 cited sources. |

Screenshots: `production/qa/evidence/2026-11-02/`.
Stage 3 tackling code (not yet applied): `src/football/stage3/`.

## The five things that matter most

1. **Three systems trust the client where they must not.** Basketball's shot meter accepts a release up to
   250 ms off against a 45 ms perfect window, and a perfect 1v1 shot is a guaranteed make — a modified client
   scores 100% from anywhere. Soccer has the same meter flaw *and* no server-side position validation anywhere
   in 1,675 lines, while the server reads player position as truth for possession, shot range and tackles.
   Football's Practice Field rebuild is the exception and validates movement properly. **The newest code is
   safe; everything older is not.**

2. **Roblox shipped first-party server-authoritative networking on 9 July 2026, with a Soccer template.**
   Prediction and rollback are now platform features. This should be evaluated before more hand-rolled ball
   networking is written. Costs: fixed 240 Hz physics, StreamingEnabled, 8 animation tracks per Animator,
   breaking camera input change.

3. **A great deal of finished work is switched off.** 852 crowd fans are frozen by a stale baked attribute
   (a constant 765.8-stud offset on all 852). Twelve authored natural-grass MaterialVariants are applied to 13
   parts out of 2,013. A lean Rthro athlete body exists in `AWSoccer.Athlete` and football never calls it. A
   working half-court 3v3 sits in `AW_Archive`. **The cheapest wins in this audit are all reconnection, not
   construction.**

4. **Three global settings are flattening good architecture.** Sun at 4.2° above the horizon, purple ambient
   tinting every neutral mauve, and zero textures or decals in 63,866 objects. The buildings, signage system,
   mow-striped hero field and 2K-style basketball park are genuinely good work rendering badly.

5. **The strip-down is incomplete below ground.** The outdoor consolidation happened and no skyline remains,
   but a four-bay arena complex at Y ≈ −6.7 still holds a duplicate football field, a duplicate soccer pitch
   and a hockey rink — visible from the lobby through the curtain wall.

## Method and limits

- All Studio access was read-only: `search_game_tree`, `script_read`, `script_grep`, `screen_capture`, and
  `execute_luau` calls returning strings only. No writes, no play sessions.
- Line numbers cited are stable as of this date.
- The three large football scripts were read in full but not mirrored to disk; re-pulling is cheaper than
  re-emitting. See `/home/claude/extracted/MANIFEST.md`.
- Research could not verify the internals of the "realistic upcoming Roblox football" tier — named projects
  exist but no primary sources on their ball control, camera or animation. Benchmark against shipped player
  counts instead of reels.
