# Basketball shot clips — authored, NOT wired (2026-11-02)

Owner ask: *"Better layup animations like 360 layup, jelly layup, mid-range jumper, three-point jumper, floater."*

Five hand-keyed KeyframeSequences now live in `ServerStorage.AW_Animations` beside the 8 football clips
(folder: 15 children). All `Loop=false`, `Priority=Action`, `AuthoredHipHeight=2`, full 16-pose R15 tree on
every keyframe. **38/38 structural checks PASS**, plus a load round-trip confirming each reported `Length`
exactly matches its authored duration.

| Clip | Dur | KFs | Intent |
|---|---|---|---|
| `aw_bb_layup_360` | 0.95 s | 7 | Full 360° in the air, head leads, eyes back to the rim before the release, high off the glass. Spin track +360° total with a 90° max segment so slerp can't shortcut; all Linear. |
| `aw_bb_layup_jelly` | 0.85 s | 6 | Torso rolls 29° away from the rim, legs scissor, right arm extends LATE and scoops while the body is already falling away. |
| `aw_bb_jumper_mid` | 0.75 s | 6 | Dip, square, rise with the right elbow 90° tucked (Z-flare ≤5°), snap, follow-through held, lands where it left. |
| `aw_bb_jumper_three` | 0.85 s | 7 | Same mechanics reading as *more effort*: dip to knees −70°, explosive drive frame, higher apex, 0.35-stud drift, longer hold. |
| `aw_bb_floater` | 0.70 s | 5 | One-foot push off the inside leg while still moving, short lift, early fingertip release deliberately short of extension. |

Temp preview ids and a paste-ready Command Bar snippet are in the new `PREVIEW_HOW_TO_BB` StringValue
(the football `PREVIEW_HOW_TO` was not modified). Ids are content hashes, so re-registering an unchanged clip
returns the same string — reproducible across restarts, but still session-local: **do not wire temp hashes
into game code.** Preview trap: `AnimationTrack.Length` reads 0.00 until the asset resolves; wait before
believing a zero.

## THE DECISION BEFORE WIRING (architectural, needs an owner/orchestrator call)

**Basketball finishes are not animation-asset-driven today.** `AWHoops.Clips` builds them **procedurally**
(`BUILD.layup` / `runlayup` / `dunk360`, around :99-104) and every client samples them at the same server
time from the `AWClip` attribute — deliberately, so gather, release and landing track the server's own
`Finish3` timeline. A fixed-duration KeyframeSequence **will drift from the real release** unless played with
a per-shot `AdjustSpeed`.

Two routes:
1. **Replace** the `Clips.sample` path for those kinds with the authored clips (+ per-shot AdjustSpeed).
2. **Port the keys into `Clips.BUILD`** entries parameterised by `tRel`/`tLand` — *recommended by the author*,
   and cheap: `Clips` already uses the same AWMotion angle conventions and the same joint short names.

**The two jumpers have no such conflict** — the jumper path doesn't go through `Clips` — so they are the
straightforward wins and should be wired first.

## Fire points (read-only findings; nothing was wired)
Shot flow: `BallCtl:603 G:startShot` → `Finish.choose` (`AWHoops.Finish3:44`) returns a finish kind or nil;
nil falls through to the jumper path at `BallCtl:616-631`. AI selection is `Brain:437/439`.
(`BallCtl:646` is `G:handsUpAt`, a contest helper — *not* the release.)

- `aw_bb_jumper_mid` → jumper path, `BallCtl:630` `setPose(a,"shoot",0.12)`, when `self.shot.three == false`
  (set at `:628` from `court:isThree`).
- `aw_bb_jumper_three` → same site, `self.shot.three == true`.
- `aw_bb_layup_jelly` → `kind == "layup"` (`Finish3:58`), best gated on high `ctx.pressure` or
  `ctx.defSide == hand` — the off-balance case `Finish3:66` already branches on it.
- `aw_bb_floater` → nearest existing kind is `runlayup` (`Finish3:55`); a true floater sits between
  `F.layupMax` and jumper range and **has no kind today** — needs one.
- `aw_bb_layup_360` → the spin branch `Finish3:49` yields only `dunk360` today, and `BallCtl:610` hard-rejects
  anything else from the spin button, so a *layup* 360 needs a new `layup360` kind in `Finish3.KINDS` plus
  `:610` broadened.

## Owner action
Right-click each of the five KeyframeSequences → **Save to Roblox** → hand the five permanent asset ids over.
Until then they exist only in the unsaved place.
