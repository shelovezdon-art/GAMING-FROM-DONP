# Definition of Done: ALLSTAR WORLD (Roblox)

Built from the owner's standard and `.claude/docs/coding-standards.md`, adapted to Roblox.
How to run each check: [`ROBLOX-PRACTICE.md`](ROBLOX-PRACTICE.md).

> *"Do not label placeholder behaviour, disconnected animations, or partially implemented mechanics as finished."*

**How to use this.** Every box needs **a link or a pasted line as proof**: an evidence path, a PASS line, a
`script_grep` hit. A tick with no proof counts as unticked. If any box in A–D is unticked, the story isn't **Done**.
It is **Partial**, and the gap is written down (section E).

---

## A. It exists and is wired up

- [ ] The code runs in the **product path**. For football that's `TeamFootballService` (ADR-0001), not the Practice Field test bench, and not a `Disabled = true` script.
- [ ] Every config key the story adds or depends on is **read by a service**. Prove it with a `script_grep` hit on the key. A key that's declared but never read means the feature doesn't exist. (`CFG.clock`, `penalty`, `overtime` and `catch.det` all looked done on 2026-11-02 and weren't.)
- [ ] No config value points at code that doesn't exist (e.g. `catch.model` naming a missing `Rules.judgeCatchDeterministic`).
- [ ] No second source of truth for the same rule (e.g. `TC.td = 7` alongside `CFG.scoring.touchdown = 6`). One stays; the other is removed or derived from it.
- [ ] Gameplay values live in config, not inline in the code.

## B. It was verified, in order (practice §4)

- [ ] **Compiles:** `loadstring(Source)` returns no error, for every script the story touched.
- [ ] **Evaluated without `require`:** `loadstring(Source)()` loads cleanly.
- [ ] **Logic:** a harness in `tests/roblox/<system>/` prints `PASS` for every rule the story adds, and the console output is saved as evidence.
- [ ] **Bug fix:** the regression check was run against the **unfixed** code and **seen to FAIL**, then seen to pass after the fix.
- [ ] **Playtest:** the feature was exercised in a play session, and `get_console_output` shows **zero warnings and zero errors** for that session (a `pcall` warning means the game silently reset).
- [ ] **Observed:** a retained screenshot of the feature working is on disk in `production/qa/evidence/`, and the story states one `Run result: OBSERVED | NOT VERIFIED | N/A — <reason>` line. `NOT VERIFIED` blocks a Visual/Feel or UI story.

## C. It is true, not assumed (practice §5–6)

- [ ] Every claim the story makes about geometry, speed, timing or presence was **measured** on the built place, with how it was measured. Unmeasured claims are tagged `INFERRED`, and the story isn't Done while one stands in for an acceptance criterion.
- [ ] Units are stated on every new value and test output. Every `S`/`STUD` use was checked against its definition.

## D. It is not a placeholder

A story is **not Done** if any of these is true. Each one turns "partial" into something you can check:

- [ ] **False:** Any acceptance criterion is satisfied by a stub, a `TODO`, a hardcoded result, a label in place of a mechanic (e.g. a HUD reading "KICKOFF" with no kick), or a code path no playtest reached.
- [ ] **False:** An animation plays without being driven by the event it depicts (e.g. a catch animation that doesn't track the ball, a tackle pose with no contact). **Disconnected animation = not Done.**
- [ ] **False:** The feature works only on the test bench, only through a test hook, or only for AI and not for a human player (or the other way round) where the story covers both.
- [ ] **False:** It works only in one mode (5v5) when the story names several (5v5 and 2v2).
- [ ] **False:** An outcome happens without a reason the player can see (the "I know exactly why I lost" pillar). There must be on-screen text or a state the player can read.

*Tick a box only once you have confirmed its statement is false. If any statement is true, the story is Partial.*

## E. It is reversible and recorded

- [ ] Every changed value has its original in a same-line comment or a `_preFix` attribute. Every deletion is a move into `AW_Archive.Removed_<date>`.
- [ ] Anything toggled for the work (`HttpEnabled`, a disabled script, a test flag) is back to how it was.
- [ ] The place was **saved to Roblox** after the change. The save time is recorded in `active.md`.
- [ ] Known limitations are written down in the story's `## Completion Notes`, or in the GDD as `KNOWN LIMITATION`. **A limitation that isn't written down is a defect.**
- [ ] The repo mirror (`src/…`), if one exists for the touched script, matches Studio or is marked stale.
- [ ] Any decision made along the way is in an ADR (`Proposed` until the owner accepts it) or in a dated decision row.

---

## Sport-level Done: "ready to expand beyond"

A sport is ready to expand beyond only when **all** of these hold, each backed by evidence:

| # | Owner's criterion | Proof required |
|---|---|---|
| 1 | A full match can be played from start to finish | `production/qa/football-match-checklist.md` walked with every verdict step passing, screenshots retained, **in both 5v5 and 2v2** |
| 2 | Core actions work reliably | The repeatable tests for passes, catches, tackles, possession changes, scoring and restarts pass on **two separate runs** |
| 3 | Ball behaviour is consistent and recognisable | The flight/spiral/nose-orientation tests pass; side-by-side screenshots against the real-world reference (test plan §15) |
| 4 | Rules, scoring, possession and restarts resolve correctly | No `EXPECTED FAIL` left in the match checklist that the ruleset requires, or each one formally deferred by an owner decision |
| 5 | Athletes and animations support believable interactions | Section D's animation box holds for every contact and catch type; reviewed by a human |
| 6 | No unresolved defects that routinely break play | No open defect that resets a match, desyncs possession or blocks a human input |
| 7 | Remaining limitations are clearly documented | A single "Known limitations" list in the sport's GDD, dated |
