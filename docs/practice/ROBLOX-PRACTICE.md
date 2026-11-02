# ALLSTAR WORLD — Roblox working practice

**For:** Don, Arnold, and every AI agent working on this project. **Read this before changing the game.**
It replaces the template's Godot/Unity/Unreal procedures for this project. Where the template's rules still apply
(the collaboration protocol, the ADR rules, evidence in `production/qa/evidence/`), this doc points back to them
and doesn't repeat them.

Companion: [`DEFINITION-OF-DONE.md`](DEFINITION-OF-DONE.md), the checklist a story must pass before it can be called done.

---

## 1. Where things live

| What | Lives in | Notes |
|---|---|---|
| **Game code, world, config** | **Roblox Studio** (the place file) | This is the source of truth. There is **no Rojo sync** today. |
| Design (GDDs), plans, ADRs, audits, QA plans, evidence | this repo | `design/`, `production/`, `docs/`, `production/qa/` |
| Mirrored source | `src/` (e.g. `src/football/stage3/`) | A **copy** made to review or ship code into Studio. It can go stale. Studio wins on any disagreement. |
| Session checkpoint | `production/session-state/active.md` | Read it first after a compaction, a crash or `/clear`. |

**How code moves today:**
- **Studio → repo:** read through the bridge (`script_read`) and write the copy under `src/<sport>/…`. Put the date and the Studio path in a header comment.
- **Repo → Studio:** paste it in with `multi_edit`, or pull it over HTTP. To pull: turn on `HttpService.HttpEnabled`, `GetAsync` the raw file URL from this repo, and assign it to `.Source`. **Turn `HttpEnabled` back off afterwards** (it was `false` when checked on 2026-11-02). Never leave it on as a side effect.
- **Later:** Rojo would make `src/` the source of truth and allow real diffs and CI (see `coding-standards.md` → CI). That needs an owner decision, and nothing in this doc assumes it.

---

## 2. Gate 0: save before you change anything

**The place was unsaved all day on 2026-11-02.** An unsaved place can't be restored. The `_preFix` attributes and
`AW_Archive` let you undo individual edits, but they don't protect against a crash or a bad bulk edit.

- [ ] Before any session that writes to Studio, the owner does **File → Save to Roblox** (this creates a version in the place's version history). Record the time in `active.md`: `Saved to Roblox: <date time> by <who>`.
- [ ] Save again after every completed batch of changes, and before any playtest that could crash Studio.
- [ ] An agent **cannot save to Roblox through the bridge.** If there is no recorded save from this session, the agent stops and asks for one. It does not carry on and hope.

---

## 3. Making a change safely

### 3.1 Scope it before you start
- Every agent or person writing to the live place is assigned **named instances or scripts**. Write them in the brief, e.g. "you may edit `TeamFootballService` and `AWFootball.Config` only". Anything outside the list is read-only. This is how several agents edited one live place on 2026-11-02 without any collisions.
- Two writers never share a script at the same time. If you need a file someone else owns, ask; don't edit it.
- Read-only work (`script_read`, `script_grep`, `inspect_instance`, `execute_luau` that only reads) needs no scope.

### 3.2 Make every change reversible
| Change | How to keep it reversible |
|---|---|
| A value in code or config | Put the original in a **same-line comment**: `td = 6, -- was 7 (2026-11-02, ruleset §2)` |
| An instance property | Store the old value in an attribute before you write: `inst:SetAttribute("<Prop>_preFix", old)` |
| Deleting anything | **Don't delete it. Move it** to `ServerStorage.AW_Archive.Removed_<yyyy-mm-dd>` |
| Lighting / global services | Back it up to an attribute folder first (the precedent is `ServerStorage.AW_LightingBackup`) |
| A whole script being replaced | Clone the old one into `AW_Archive` with a dated name first (the precedent is `Hoops3Service_halfcourt`) |

### 3.3 Write it down where it happened
Note each change with what it touched in the session log or `active.md`. The plan's "Done" table
(`production/plan-2026-11.md` §0) is the model: change, where, and how to undo it.

### 3.4 Follow the template's collaboration protocol
Question → options → decision → draft → approval (`CLAUDE.md`). Ask before writing. No commits without the owner's
instruction. A question that was skipped isn't an answer.

---

## 4. How to verify a change, in order

Each step catches something the one before it can't. **Don't skip ahead, and don't report a step you didn't run.**

| # | Step | How | Catches |
|---|---|---|---|
| 1 | **Compile** | `execute_luau`: `local f, err = loadstring(inst.Source); assert(f, err)` | Syntax errors. *Only* syntax errors. |
| 2 | **Evaluate without `require`** | `local M = loadstring(inst.Source)()` | Errors at load time. **`require()` caches results for the whole Studio session**, so after an edit it can hand back the old table. On 2026-11-02 that produced false readings more than once. Never verify an edit through `require`. |
| 3 | **Run the pure-function harness** | Command Bar or `execute_luau`, Edit mode, no play session needed. Each check prints one line: `[TEST-ID] PASS\|FAIL expected=<x> actual=<y>` | Logic: formulas, rule tables, state transitions |
| 4 | **Playtest and read the console** | `start_stop_play` → wait for the field to run → drive it (`execute_luau` in the **Server** datamodel calling `TestHookTeam:Invoke("state")` etc.) → `get_console_output` → stop | Runtime errors, wiring between systems. **Any warning is a failure.** `TeamFootballService` wraps each field's update in a `pcall` that warns and resets the game, so a silent reset looks like normal play. |
| 5 | **Retained screenshot** | `screen_capture` while the state is on screen, saved into `production/qa/evidence/` (§6). `ls` the file to confirm it's on disk. | How it looks. A parse check isn't a run. |

**Harnesses that exist today, all run with `loadstring`:**
- **TKL-0**, the tackle counter matrix (`AWPractice.Tackle`). The harness code is in `production/qa/football-test-plan.md` §5. It's pure Luau and needs no play session.
- `src/football/stage3/NOTES.md` describes a **46-assertion harness** over `Tackle` and `Contest`. **That harness isn't in this repo.** Until someone adds it under `tests/roblox/`, don't cite it as evidence.
- The 28 tests in `football-test-plan.md` §16.1 run today. The other 48 automatable tests need hook **H1** (`call`/`set`/`snap` copied from `Hoops3Service`'s `TestHook3`), which **doesn't exist yet**.

**Hooks you can drive today:** `TestHookTeam` (`state`, `athletes`, `fields`, `join`, `intent`). The service creates it
**at runtime** (`TeamFootballService:1735`), so it only exists during a play session, never in Edit mode.
`TeamFootballClient` has **no** test hook, so the real client input path can only be tested by a human.

**Where harness code goes:** `tests/roblox/<system>/<system>_<feature>.spec.lua`, as a Command Bar snippet that
reads `loadstring(...)()` and prints PASS/FAIL lines. Each line names the scenario and the expected result
(`[TKL-3] wrap_from_front_on_jukeRecovery → BROKE`). Arrange/act/assert, deterministic, no `math.random` without a
fixed seed, no wall-clock assertions. This is the template's `test-standards.md` written for Luau.

---

## 5. Measure, don't infer

**Never state how the built game behaves from a config number, a variable name or a code comment. Measure the
built thing, or label the claim `INFERRED`.**

On 2026-11-02, four separate claims were wrong. Each was caught only because someone measured:

| Claim (inferred) | Measured truth |
|---|---|
| The football ball needs reshaping into an ellipsoid | It already was a correct ellipsoid |
| The basketball rim is 1.46 studs too low | It sits 8.714 studs above the floor = **3.050 m, regulation**. The audit had measured against the court's built scale, not the code's conversion. |
| An animation cap diagnosis | Metres and studs were mixed up; the diagnosis didn't hold |
| "No first downs exist" | `TeamFootballService:1415` implements the midfield first down, once per possession |

**How to apply it:**
- [ ] Any claim about geometry, speed, height, timing or "X doesn't exist" comes with *how it was measured*: the `execute_luau` read, the `script_grep` hit, the `snap()` trace, the screenshot.
- [ ] "Doesn't exist" means you grepped all scripts (`script_grep`, including `ServerStorage` and `AW_Archive`) and say what you searched for.
- [ ] Positions and sizes: read `Position`/`Size`/`CFrame` from the instance. Don't compute them from the builder script.
- [ ] Runtime values (speeds, cooldowns) come from a playtest trace. Config is what was *intended*, not what *happens*.
- [ ] Findings that weren't measured are tagged `INFERRED`. Audits and plans must not drop that tag when they repeat a finding.

---

## 6. Units

**Logic is in metres and seconds. The world is in studs. The whole project uses one scale: 1 stud = 0.35 m.** Two
spellings of that scale are in use, and they are reciprocals:

| Constant | Meaning | Value | Where (read live 2026-11-02) |
|---|---|---|---|
| `STUD` | **metres per stud** | `0.35` | `AWFootball.Config` (**the product**), `AWSoccer.Config`, `AWHoops.Config`, `AWHoops.Geometry`, `Hoops3Modules.Core`, `AWBuild.Lib` |
| `S` in `AWPractice.Config` | **studs per metre** | `1/0.35 = 2.857…` | Practice Field (test bench) only |
| `S` at soccer/football call sites | often a local alias of `STUD`, so **metres per stud** | `0.35` | check each site |

Rules:
- [ ] Before using an `S`, find where it's defined. **Multiply or divide is decided by the definition, not the name.**
- [ ] Put units in names when you write new code (`speedMps`, `heightM`, `sizeStuds`). Write `-- m` / `-- studs` on config keys.
- [ ] Built geometry isn't guaranteed to match the code's scale. The basketball court was built at **3.5 studs/m** while the code converts at **2.857**, so the court and backboard are ~22% oversized. Check built geometry by measuring it (§5).
- [ ] Every test output that depends on scale says the unit: `expected=3.05m actual=3.050m (8.714 studs)`.

---

## 7. Evidence

- Screenshots are kept in `production/qa/evidence/`. A capture that was taken and thrown away counts as an assertion, not evidence.
- **Naming in use today is inconsistent:** `2026-11-02/NN-what.jpg` on disk, `<TEST-ID>-<yyyymmdd>.png` in the test plan, `MATCH-<yyyymmdd>-<step>.png` in the match checklist, `[story-slug]/NN-what.png` in `run-and-observe.md`. Until the owner picks one, use **`production/qa/evidence/<yyyy-mm-dd>/<ID>-<what>.<png|jpg>`**, where `<ID>` is the test or story ID.
- Console output that proves a harness passed is evidence too. Save it next to the screenshot as `<ID>-console.txt`.
- `review-receipts.sh` stamps can only hash files in the repo. Studio-only code isn't in the repo, so for a Studio change write `stamp.txt` with the script's full path, `#inst.Source` and its line count at the time of the run.

---

## 8. Decisions: ADRs

- Architecture decisions go in `docs/architecture/ADR-NNNN-<slug>.md`, in the template format (see ADR-0001).
- **New ADRs are written as `Proposed`.** Only the owner, or the `technical-director` agent on the owner's explicit confirmation, moves an ADR to `Accepted` (`/architecture-decision accept`). An Accepted ADR changes only through a superseding ADR.
- When an owner answer is recorded in an ADR, quote it and date it (ADR-0001's "Confirmed by the owner … in direct answer to" is the model).
- Smaller decisions (tuning, owner answers to open questions) go in the GDD's open-questions section or the plan's decision table, with the date.

---

## 9. Agent checklist for one session in Studio

1. [ ] Read `active.md`. Confirm there's a **Saved to Roblox** time from this session (§2).
2. [ ] Confirm your scope: the exact instances and scripts you may write to (§3.1).
3. [ ] Before each write: record the original value (comment, `_preFix` attribute, archive move).
4. [ ] After each write: compile → `loadstring` evaluate → harness (§4, steps 1–3).
5. [ ] Before claiming anything about the built game: measure it (§5). Check units (§6).
6. [ ] If anything is player-observable: playtest, read the console, take a retained screenshot (§4, steps 4–5).
7. [ ] Put back anything you toggled (`HttpEnabled`, test flags, disabled scripts).
8. [ ] Update `active.md`: what changed, where, how to undo it, the evidence paths. Ask for a save.
