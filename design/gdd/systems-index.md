# Systems Index — ALLSTAR WORLD

Engine: **Roblox (Luau)**. The repo template's engine options (Godot / Unity /
Unreal) do not apply to this project; engine-specific skills, code roots and test
runners from the template are unused. Design, planning and QA conventions still apply.

Design order: Foundation → Core → Feature → Presentation → Polish

| System | Doc | Category | Status | Notes |
|---|---|---|---|---|
| Football ruleset + ball physics | [football-ruleset.md](football-ruleset.md) | Foundation | RESEARCHED 2026-11-02 — IFAF 5v5 base with a labelled contact deviation; 7 owner decisions open |
| Football Core (Practice Field) | [football-core.md](football-core.md) | Core | DRAFT 1 — open decisions pending | Movement, ball states, passing/catching, tackling, jump balls, 1v1 AI QB, route practice. Server-authoritative. Built in 5 stages. |
| Football Playbook + Play-Call Screen | [football-playbook.md](football-playbook.md) | Feature | DESIGN DRAFT 1 — 2026-11-02, not built | 15-play / 6-category 5v5 book (+6-play 2v2), 4 new routes (out, dig, comeback, sluggo), Madden-style lower-third card screen for the QB with route trees drawn per card. Keeps the `{ action="play", index }` wire format; playbook data moves into `AWFootball.Config.playbook` (pays down debt C1). |

## Not yet specced

- Basketball Core (2K-style dribbling, half-court 1v1 / 3v3)
- Soccer Core (close-control touches, low behind-player camera, outdoor stadium)
- HUD / broadcast scoreboard (v2 milestone M05)
- 2v2 and 5v5 match structure (M06) — reuses Football Core rules
- Multiplayer architecture beyond Football Core's authority model (M07)
- DRIP STORE (M08) — cosmetic only, must not touch any Football Core knob
- Clubs (M09), National League (M10), Season Pass (M11)

## Blocking decisions

`football-core.md` § OPEN-DECISIONS lists 3 rule conflicts, 1 naming pass, the
unvalued scoring/clock knobs, and 7 questions for the owner. Resolve before
Stage 2 (ball states + passing/catching) is built.

## Audit 2026-11-02

`football-core.md` was rewritten to describe the **existing Roblox build** rather
than a greenfield spec, after a read-only audit of the live Studio place. Full
audit trail: `/home/claude/audit/findings.md`. Cached sources:
`/home/claude/extracted/`.

**Football Core row, corrected:**

| System | Doc | Category | Status | Notes |
|---|---|---|---|---|
| Football Core (Practice Field) | [football-core.md](football-core.md) | Core | **Stage 1 + 2 BUILT · Stage 3-5 NOT BUILT** | Practice Field "Ball Lab" (`AWPractice` + `PracticeService` / `PracticeClient`): momentum movement, 5-state ball machine with a `rev` guard, possession claims, three pass types on a deterministic analytic arc, rig-measured deterministic catch model with tips and deflections, server movement validation. **No defender, no tackling, no play cycle, no downs, no score, no AI QB, no route practice, no stamina, no fumbles.** Tackling, juke/spin/stiff-arm, snap cadence, 5 routes, jump balls, downs and an AI QB **do** exist in the older `AWFootball` 1v1 / team modes, which use a different (partly random) catch model. Units are **metres/seconds** (1 stud = 0.35 m), not studs. |

**Supersedes the old row's claims.** It listed tackling, jump balls, the AI QB and
route practice as part of one planned five-stage build in `DRAFT 1` status with
"nothing built yet". Two of those four are built, but in a *different* codebase,
and Stages 1-2 of the Practice Field are built and working.

**Blocking decisions — replaces the section below as it applied to this doc.** The
old three rule conflicts, the naming pass, the unvalued scoring knobs and the
Roblox API questions are **resolved**: `AWFootball.Config.rules` supplies
`possessionsEach 5, downs 4, td 7, startYard 20, otPossessionsEach 1,
maxOtRounds 3`, and the code's own names and values are now the doc's.

What actually blocks work now (`football-core.md` § OPEN-DECISIONS):

- **A1 — which catch model wins.** Two live models: the Practice Field's fully
  deterministic one and `AWFootball`'s quality-roll one. The most consequential
  open decision in the project.
- **A2 — `Flight.timingGrade` / `catchDifficulty` are dead code** with 11 config
  keys and no call sites. Wire up or delete.
- **A4 / A5 — two speed scales** (7.8 vs 9.0-9.6 m/s) and **three gravities**
  (9.81 / 13.5 / 22).
- **B1 — griefing bug:** any player can reset the ball mid-flight and destroy
  another player's pass (`PracticeService:324`).
- **D — owner's call:** stamina at all? first downs? fumbles? avatar-measured reach
  as a feature or a fairness problem? Does the Practice Field become a match mode,
  or hand its modules to `AWFootball`?

**Other systems in the place not yet indexed** (found during the audit, no GDDs):
`AWHoops` (14 modules — a substantially built basketball core, far beyond "not yet
specced" below), `AWSoccer` (7 modules), `AWMotion` (shared animation arbitration,
which Football Core depends on), and the `AWSessions` registry.
