# Harness run — try flow + config unification in TeamFootballService

Date: 2026-11-02 · Studio play session, server-side via `TestHookTeam` (hook H1)
Procedure: `docs/practice/ROBLOX-PRACTICE.md` §4 — loadstring compile → inline logic
checks → live harness → console check. Visual (HUD try panel on screen): **pending,
next playtest with the owner** — the client HUD compiled but was not visually checked.

## What changed (Studio: `ServerScriptService.TeamFootballService`)

- Duplicate local config removed: `startYard/td/safety/otPossessionsEach/maxOtRounds`
  now read `AWFootball.Config` (`CFG.rules`, `CFG.scoring` via `Rules.scoreFor`).
  Originals kept in same-line comments.
- TD is now **6** + a declared try (was 7 flat).
- New try flow: TD → `nextStep="try"` → `tryDeclare` state (8 s window,
  `TC.tryDeclareTime`) → human offense declares via new `declareTry` intent
  (1 = from the 5, pass only · 2 = from the 10, run or pass); AI declares 2 when
  trailing, else 1; timeout auto-declares 1. Resolution through `Rules.resolveTry`
  with the reason string surfaced to players.
- `downText()` now says "& TO MIDFIELD"/"& GOAL" (IFAF series), "TRY FOR n" on a try.
- HUD message gains `series = {down, toGain="mid"|"goal"}` and `try = {phase, team,
  declared, canDeclare, timeLeft}`; `fb()` gains a `reason` param, wired at the
  catch site (`res.detail`).
- `TestHookTeam` gained `call`/`set`/`snap` driving commands (Studio-gated).

## Static checks — PASS

- `loadstring(TeamFootballService.Source)` → COMPILES (after each edit batch)
- `loadstring(TeamFootballClient.Source)` → COMPILES (785 lines, agent's HUD work)
- Hook logic (inline): athlete resolver @home1/@away2/bad-tag, dotted-path set,
  call, scalar snapshot → 6/6 PASS
- `Rules` pure functions: 13/13 assertions PASS (prior run, same session)
- Client reads `h.try` — server field renamed from `tryState` to `try` to match

## Live harness — PASS

| # | Forced situation | Expected | Observed |
|---|---|---|---|
| 1 | endPlay("TD") while live | +6 (not 7), nextStep=try | `home=6`, `nextStep=try`, msg "TOUCHDOWN HOME!" |
| 2 | advance after TD, human QB | tryDeclare state, 8 s timer, prompt | `state=tryDeclare timer=7.48`, msg "CHOOSE YOUR TRY · +1 FROM THE 5 (PASS ONLY) · +2 FROM THE 10 (RUN OR PASS)" |
| 3 | declare window expires (real time) | auto-declare 1 | spot 4.57 m from goal, declared=1; late `declareTry(2)` correctly rejected by phase guard |
| 4 | run scores on the auto-declared 1-pt | 0 points + reason | score unchanged, msg "TRY · DECLARED THE 1-POINT TRY FROM THE 5, WHICH IS PASS ONLY - A RUN CANNOT SCORE IT" |
| 5 | declare 2 in time, run it in | spot 9.14 m, +2 | `spotDist=9.14`, `home 6→14`, msg "TWO-POINT TRY GOOD ON A RUN" |
| 6 | AI offense (away, trailing 0–14) | AI auto-declares 2 | AI declared before the harness could; `away 0→8`, msg "TWO-POINT TRY GOOD ON A PASS" (passCaught forced) |
| 7 | possession after each try | swaps | offense home → away between tests |

Console after the run: **no errors or warnings from the game flow.** The only two
errors were the harness's own bad probe (`pos` with no athlete) before the tests.

## Live harness, second pass — game clock (C1–C7) — PASS

| # | Forced situation | Observed |
|---|---|---|
| C1 | before any clock test | half 1, clock carried over, running |
| C2 | after a snap, 1.2 s real time | clock fell 270.38 → 268.87, `started=true stopped=false` |
| C3 | incomplete OUTSIDE the final window | clock kept falling (268.05 → 267.23), no stop |
| C4 | incomplete INSIDE the window (set to 45 s) | `stopped=true`, clock frozen at 44.37 across 1 s |
| C5 | clock expired at a dead ball, half 1 | half 2, fresh 300 s, AWAY receives ("HALFTIME · HALF 2 · AWAY BALL") |
| C6 | next snap after a window stop | stop cleared, clock running again |
| C7 | clock expired in half 2, score 0–0 | correctly into "OVERTIME 1 · one possession each" (tie path) |
| C7b | OT: away TD + try, home turnover on downs | "AWAY WINS · FINAL HOME 0 – 6 AWAY" (win path) |

A complete match therefore runs start to finish: regulation → halftime → regulation end →
(tie) overtime → FINAL with a winner — the quality bar in the development standard.
`endPlay` also hardened: a nil `detail` no longer crashes the play-end path.

## Not yet covered

- Human 1-pt pass try through the real catch path (unit-covered by `Rules.resolveTry`;
  flow path identical to #5/#6).
- Defensive try touchdown — unreachable today: the service deadballs INT instantly
  (`interceptionReturnsLive=true` in Config is not yet honoured). Logged as a gap.
- Visual: try panel, series bar, reason line on screen → next owner playtest.
- Clock/halves, penalties on-field detection, IFAF overtime — next passes (plan §2).
