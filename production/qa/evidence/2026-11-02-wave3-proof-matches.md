# Proof matches — wave 3 + 1v1 Gauntlet + DRIP + broadcast UI

Date: 2026-11-02 evening · Studio play session, server-driven via `TestHookTeam` (owner away).
Procedure: ROBLOX-PRACTICE §4 — compile checks per batch (all PASS, per each agent's report +
orchestrator re-verification), AI-vs-AI live matches, console capture. Visual/screenshot
evidence: **pending owner playtest** (capture bridge intermittent; owner is the eyeball).

## Field discovery — PASS
Console: `[TeamFootball] team fields ready: 5v5, yard, youth1, youth2` — all four fields,
including the new 1v1 mode (THE GAUNTLET) and the youth 2v2 (BACKYARD).

## AI-vs-AI proof matches (hook `startGame`, ~45 s of play each)

### youth1 — THE GAUNTLET (1v1, new mode)
Score HOME 14 – 0 AWAY · clock ran 300→254 · event log tally:
`HANDOFF=7` (one per snap — the GAUNTLET keeper play fires every down),
`AI_JUKE=2, AI_SPIN=4` (the new spin mix), `ANKLE_BREAK=4` (charging tacklers froze),
`BREAKAWAY=3`, `TACKLE=8`, `TRY_DECLARED=1, TRY_RESULT=1` (forced 2-pt run try after the TD),
`SETUP/SNAP/PLAY_END=7`. Downs, possessions, scoring, clock all advancing.

### youth2 — BACKYARD 2v2
Clock 300→249, down 2 · `THROW=5, ARRIVAL=5, READ=5` (AI QB reading and throwing),
`HANDOFF=1` (the AI called the DRAW run play unprompted), `AI_JUKE=2, ANKLE_BREAK=1,
BREAKAWAY=1, TACKLE=2, RELEASE=14`. Full 2v2 loop alive.

## Console — CLEAN (script errors: zero)
Startup lines all present incl. `[DripService] up · 10 items · packs dormant=true`.
Only warnings: DataStoreService `StudioAccessToApisNotAllowed` + DripService's single
designed fallback warning (expected until the owner enables Studio API access in
Game Settings → Security).

## Defect found and fixed during proof
`[Football] fields ready: youth1, indoor` — the legacy 1v1 FootballService ALSO discovered
the Gauntlet (its discovery matches `Mode == "1v1"`), so two services claimed one field.
Fix: FootballService discovery now skips `FieldId == "youth1"` (one-line guard, "-- was"
comment, compile-verified). TeamFootballService owns the Gauntlet.

## Owed before Done (DEFINITION-OF-DONE)
- Owner playtest of: score bug + lower thirds (visual), DRIP store buy/equip flow,
  pinned play card, PASS|RUN tabs, 1v1 as a human, trail recolor, celebration pose.
- Retained screenshots in this folder.
- Owner File → Save to Roblox (everything since the 14:40 save is unsaved).
- Owner Creator Hub steps for Robux packs (3 Developer Products → ids into AWDrip.Catalog).
