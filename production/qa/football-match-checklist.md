# Football — "can a full match be played start to finish?" checklist

**One page. Walk it in order. One tester, one Studio session.**
Product: `TeamFootballService` 5v5 (repeat for 2v2). Full test detail: `football-test-plan.md`.
Studio: `52e32916-3102-403b-a01b-8b4d550c1fae`. Date: ______ Tester: ______ Mode: 5v5 / 2v2

**Setup before you start:** open the Output window, clear it, and start a play session on the Football Park.
Screenshots go to `production/qa/evidence/MATCH-<yyyymmdd>-<step>.png`. **A warning in the Output window is a FAIL
on whatever step it appeared under** — `TeamFootballService` wraps each field's update in a `pcall` that warns and
resets the game, so a silent reset looks like normal play.

| # | Step | Pass if | Record | P/F |
|---|---|---|---|---|
| 1 | **Join** — walk to a JOIN pad, press E | You are teleported to the pad and placed on a team; `TestHookTeam:Invoke("state")` shows you in the roster | Screenshot of the lobby with your name in a slot | ☐ |
| 2 | **Roster fill** — tap READY | Every empty slot is filled by AI on **both** sides; `state.humans` = your count, total bodies = `size × 2`; countdown starts at **4 s** (`TC.readyCountdown`) and auto-starts at **40 s** (`TC.lobbyAutoStart`) if nobody readies | Screenshot of the full roster + countdown | ☐ |
| 3 | **Opening snap** (there is no kickoff) | HUD reads `"5v5 KICKOFF · <field> · HOME ball first"` — a **label, not a kick**. Offence is placed at its **own 20 yd** (`TC.startYard`), `down = 1`, `toGain` = the middle line | Screenshot of the first pre-snap; note `state.los` and `state.toGain` | ☐ |
| 4 | **First possession** — snap, throw, run | Snap happens (human: auto at **15 s**, **4 s** once SET). Ball leaves the QB, a receiver catches or it's incomplete, play ends with a clear reason on screen. Repeat for 4 downs | Screenshot mid-play; the outcome text of each down | ☐ |
| 5 | **A first down** — cross the middle line | `down` resets to **1**, `toGain` becomes the **goal line**, HUD shouts `"FIRST DOWN!"`. Cross it a second time in the same possession → **no** second first down (one per possession) | Screenshot of the FIRST DOWN toast + the HUD before/after | ☐ |
| 6 | **A score** — reach the end zone | `"TOUCHDOWN"`, scoreboard increments. **Expect 7** (`TC.td`) — the ruleset says **6**. Note which you saw | Scoreboard screenshot | ☐ |
| 7 | **A try (1-pt or 2-pt)** | **EXPECTED FAIL — not implemented.** No declaration prompt appears; play goes straight to the next possession | Screenshot showing no try prompt after the TD | ☐ |
| 8 | **Possession change** — fail on 4th down, or throw an interception | `"TURNOVER ON DOWNS"` (or the pick resolves); `possession` increments; the new offence is placed at **its own 20**. On an interception, note whether the return stayed live and where it was spotted | `state.possession / offense / los` before and after; screenshot | ☐ |
| 9 | **Fumble** | **EXPECTED FAIL — not implemented.** No tackle in the product can strip the ball | Note that no fumble occurred in any contact all match | ☐ |
| 10 | **The second half** | **EXPECTED FAIL — there are no halves.** The match is **4 possessions each (8 total)**, counted not timed. `state.possession` reads `"n/8"` | Screenshot of the possession counter | ☐ |
| 11 | **The clock** | **EXPECTED FAIL — there is no game clock.** No clock on the HUD, no final-minute stop rules, no timeouts. Time the whole match on a stopwatch instead | Wall-clock match length (minutes:seconds) — this is the data the owner's match-length decision needs | ☐ |
| 12 | **Overtime (if tied)** | At a tie after possession 8: `"OVERTIME 1 · one possession each"`, up to **2** rounds (`TC.maxOtRounds`). Expect **one** possession each **from the own 20** — the ruleset wants **two series from midfield with no first down available**. A first down **is** earnable in OT: note if it happens | Screenshot of the OT banner + `state.otRound / los / toGain` | ☐ |
| 13 | **Match end** | `state = "final"`, scoreboard shows `· FINAL`, board holds for **7 s** (`TC.finalTime`), then everyone returns to the lobby with the score shown | Final scoreboard screenshot + lobby-return screenshot | ☐ |
| 14 | **Rejoin** | Leave mid-match (or walk **45 m** off the field) → AI takes your slot immediately. Rejoin → you **queue** (`state.pending`) and take a slot **at the next dead ball**, not mid-play | Screenshot of the roster showing the AI substitution, then your re-entry | ☐ |
| 15 | **Clean output** | Zero warnings in the Output window for the whole match. Any `[TeamFootball] <field>: <error>` line means the game silently reset | Screenshot of the Output window at match end | ☐ |

**Verdict:** a match is *playable start to finish* if steps 1–6, 8, 13, 14 and 15 all pass. Steps 7, 9, 10, 11 and
part of 12 are expected failures against the ruleset and are tracked as blockers below, not as regressions.

---

## Blockers — what currently makes a full *rules-correct* match impossible

In priority order. Each is specific, and each is traced.

1. **No clock, no halves. Match length is undecided.**
   The product counts possessions (`TC.modes.*.possessionsEach = 4`), so there is no first half, no second half, no
   final-minute stop rules and no timeouts. `CFG.clock` holds the whole IFAF structure (`halves 2`,
   `intermissionSeconds 120` [VERIFIED], `stopClockWindowSeconds 60`, `playClockSeconds 22`, `timeoutsPerHalf 2`,
   `timeoutSeconds 90`, and the six `stopOn` triggers) and **no service reads it.** `halfSeconds = 300` is explicitly
   an assumption, not research. **This is owner open question 1 (`football-ruleset.md §7`) and it blocks steps 10,
   11 and 12.** Nothing else can be specified until the match's shape is decided.

2. **No try after a touchdown, and a touchdown is worth the wrong number.**
   `TC.td = 7` (a browser-prototype TD-plus-automatic-extra-point) while both `CFG.rules.td` and
   `CFG.scoring.touchdown` now say **6**. The declared **1-point pass-only try from the 5** and **2-point run-or-pass
   try from the 10** — the ruleset's single best risk/reward decision, and the whole point of scoring 6 — do not
   exist, nor does the defensive try TD (2) or the safety on a try (1). A match therefore cannot produce a legal
   scoreline. Two sources of truth for the same rule is also a standards violation (`coding-standards.md`:
   gameplay values must be data-driven).

3. **Four of the five penalties do not exist.**
   Only **false start** is implemented (−5 from the LOS, replay the down). Missing: **defensive PI** (+10, automatic
   first down), **offensive PI** (−10, loss of down), **defensive holding** (automatic first down), **offside** (−5),
   and **unnecessary roughness** (+10, automatic first down) — the one that keeps full-contact arcade from becoming a
   brawl. All six are sitting in `CFG.penalty.fouls`, complete with the half-the-distance rule, unread. Without
   defensive PI there is nothing stopping a defender running through a receiver, which makes coverage untestable
   as a skill.

4. **Every possession restarts at the own 20, not the own 5.**
   `TC.startYard = 20`; the ruleset and `CFG.series.snapOwnM` both say **4.57 m (own 5)**. That is 15 yards of field
   given away on every change of possession, which changes how many plays a drive needs and therefore whether "four
   to cross midfield" is a real constraint. Also: **no coin toss** — HOME always snaps first.

5. **No fumbles in the product at all.**
   The only fumble logic in the project is `AWPractice.Tackle.fumbles` (deterministic: a **dive**, on an **exposed**
   ball, at **≥ 0.80 × sprint** closing speed, from the **blind side** beyond 120°). It is reachable only through
   `TackleService`, which is **`Disabled = true`**, and even when enabled its possession seam
   (`ServerStorage.AWPracticeBall`) is **not installed**, so it reports outcomes and never blows the whistle. How live
   a fumble should be is **owner open question 3**.

6. **Overtime is the wrong shape.**
   One possession each from the own 20, up to 2 rounds. The ruleset wants a **two-series period from the middle
   line with no first down available**, the period ending if the defence scores, collapsing from period 2 onward to a
   **single try play from the 5**. None of `CFG.overtime` is read. In the product a tie after OT simply stands.

7. **No test hook good enough to make any of this repeatable.**
   `TestHookTeam` can only `state`, `athletes`, `join` and `intent` — it cannot place a body, set a velocity, force a
   down or a score, or read the outcome log it already maintains. `TeamFootballClient` has **no** hook at all.
   `Hoops3Service.TestHook3` already has the three generic commands that fix this (`call`, `set`, `snap`). **Copying
   them onto `TestHookTeam` is the single cheapest unblock in this document** — it converts 20 manual tests into
   scripted ones and is a paste of code already working in another mode.

8. **Nobody snaps the ball, and the formation rules are unspecified.**
   The 5-player offence has no CENTER; whether the QB self-snaps or a slot becomes the center is **owner open
   question 2**. The ruleset's borrowed structural constraints (exactly four on the line, one defender ≥10 yd off and
   the rest at 4 yd, no blitzing, no rushing from outside the box) are not implemented — the product uses
   `rushDepth 6` / `cushion 5` / `rushCount 3.0–3.2` instead.

### Not blockers — things that are already right

No kicking anywhere (correct: the format has none). Ground = dead for a loose ball (correct, and `groundIsDead` is
the honest call — real prolate bounce would decide turnovers with no player input). The **midfield first down works**
— `TeamFootballService:1415` resets the down and moves `toGain` to the goal line on crossing the middle, exactly as
the ruleset specifies, and exactly once per possession. Safety = 2. Server-authoritative with clients sending intents
only. Nothing in any config is purchase-linked.
