# Systems Index — ALLSTAR WORLD

Engine: **Roblox (Luau)**. The repo template's engine options (Godot / Unity /
Unreal) do not apply to this project; engine-specific skills, code roots and test
runners from the template are unused. Design, planning and QA conventions still apply.

Design order: Foundation → Core → Feature → Presentation → Polish

| System | Doc | Category | Status | Notes |
|---|---|---|---|---|
| Football Core (Practice Field) | [football-core.md](football-core.md) | Core | DRAFT 1 — open decisions pending | Movement, ball states, passing/catching, tackling, jump balls, 1v1 AI QB, route practice. Server-authoritative. Built in 5 stages. |

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
