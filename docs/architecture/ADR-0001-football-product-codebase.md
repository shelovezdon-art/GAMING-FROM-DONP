# ADR-0001: TeamFootballService is the football product; the Practice Field is a test bench

## Status

Accepted

> Confirmed by the owner (Don) on 2026-11-02, in direct answer to "which football codebase becomes the product?"

## Date

2026-11-02

## Last Verified

2026-11-02

## Decision Makers

Don (owner), with the 2026-11-02 codebase audit as evidence.

## Summary

ALLSTAR WORLD carries two independent football codebases with two different catch models, two speed scales and
three gravities; the project standard forbids spreading effort across unfinished versions of one sport. Decided:
**`TeamFootballService` (5v5/2v2) is the product**, because it is the only one that can reach a full playable match
soon, and the Practice Field "Ball Lab" is demoted to what its name says — a test bench for ball and possession
work, not a second game.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Roblox (Luau) |
| **Domain** | Core |
| **Layer** | Foundation |
| **Knowledge Risk** | LOW — no post-cutoff API depends on this decision |
| **References Consulted** | `docs/audits/2026-11-02/football-core.md`, `design/gdd/football-core.md`, `design/gdd/football-ruleset.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | A full 5v5 match played start to finish before this ADR is considered discharged |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | The IFAF ruleset adoption; the Stage 3 tackling adaptation; retiring `HoopsService`-style dead code in football |
| **Blocks** | Every football epic — no football work should start in the Practice Field as a product path |
| **Ordering Note** | The Server Authority evaluation is independent and can be adopted into this choice later; it is not a prerequisite. |

## Context

### Problem Statement

The 2 November audit found football implemented twice. Continuing both violates the project standard ("work on one
sport at a time… do not spread effort across several unfinished sports") and guarantees divergence: the two catch
models, two speed scales (7.8 vs 9.0–9.6 m/s) and three gravities already disagree.

### Current State

**`TeamFootballService` (1,810 lines) + `FootballService` (1,198) + clients — has a game.**
Downs, touchdowns, scoring, snap cadence, five routes, jump balls, an AI quarterback, tackling with
juke/spin/stiff-arm, overtime, interceptions, penalties. The 5v5 Showcase walk-on panel was observed working in a
playtest on 2026-11-02: position slots per team, AI filling empty spots, auto-start at 40 s.
Its catch model rolls quality (0.97 / 0.80 / 0.50 / 0.35).

**`AWPractice` + `PracticeService` (1,107) + `PracticeClient` (892) — has a better ball.**
Momentum movement, a five-state ball machine with a revision counter that makes stale client requests harmless,
server-owned ball, analytic flight shared by server and clients, and a deterministic catch model whose reach is
measured off each avatar's own R15 rig. It has **no play cycle, no downs, no score, no AI QB and no routes.**
Stage 3 (tackling, jump balls) was installed 2026-11-02 and sits disabled.

### Constraints

- The standard's bar for a sport being ready is "a full match can be played from start to finish."
- Market timing: the category incumbent (Football Fusion 2) fell from 49,999 concurrent to 1,635 with no update in
  eight months. The opening is real but will not stay open.
- Solo developer with a partner; weeks spent in the wrong codebase are not recoverable.
- Monetization is cosmetic-only and must stay input-determined.

## Decision

`TeamFootballService` is the football product. The Practice Field remains as a test bench for ball, possession and
contact work, and is never shipped as a mode.

The Practice Field's **deterministic catch model is ported into `TeamFootballService` one piece at a time, behind a
config flag**, starting with `Receive`. The quality-roll model is retired once the deterministic one is at parity.

## Consequences

### Positive
- A match exists today; the standard's bar is reachable in weeks rather than months.
- Snap cadence, routes, AI QB, downs and scoring are already built and playtested.
- One football codebase, which is what the standard requires.

### Negative — accepted knowingly
- **Stage 3 tackling was written against Practice Field conventions** (`AWPractice.Config`, the `rev` pattern,
  `Receive.rig`). Adapting it to `TeamFootballService` is real work and was not free.
- The quality-roll catch model contradicts the project's "I know exactly why I lost" pillar and must be replaced,
  not merely left alone.
- 1,810 lines of interdependent code to change carefully, versus a clean build on a better foundation.
- `TeamFootballService`'s current rules (5 possessions each, TD 7, start at the 20) conflict with the researched
  IFAF ruleset (TD 6, snap from own 5, declared 1- or 2-point try) and must be reworked. Note this cost was roughly
  equal under either option and did not drive the decision.

### Neutral
- The Practice Field keeps its value as the place to prove ball and contact behaviour before it reaches the product.
  Stage 3 stays installed and disabled there as the reference implementation.

## Alternatives Considered

**Build the match onto the Practice Field (Stages 4–5).** Rejected: the better engineering is real, but no play
cycle, downs, score, AI QB or routes exist, so a full match is weeks further away, and the market opening stays open
while it is built.

**Settle Server Authority first.** Rejected as a *first* decision, not on merit: both codebases are already
server-authoritative in their own way, so the platform feature is an optimisation that can be adopted into either
choice later. It remains an open question, and its costs (forced 240 Hz physics, StreamingEnabled, 8 animation
tracks per `Animator`, breaking camera input) are recorded in `production/plan-2026-11.md`.

## Implementation Notes

First move: port `AWPractice.Receive`'s deterministic catch into `TeamFootballService` behind a config flag, so both
models can be compared on the same field before the roll model is removed.
