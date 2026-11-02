# HANDOFF — football stance + pre-snap presentation (interrupted by bridge drop)

Owner ask (2026-11-02 ~16:08): *"football the only thing is more better movement like them
lining up for the ball, db stance, qb two hands on ball."*

Work was ~40% complete in Studio when the device bridge dropped at ~16:19. **Everything below
was verified in Studio but is UNSAVED** — if Studio restarted, re-verify before trusting it.

## DONE and verified in Studio (unsaved)

### `ReplicatedStorage.AWMotion` — 30 harness checks, 0 fail
- `dbCrouch` deepened so it reads at distance: root −0.45→−0.62, waist −22→−30, hips 40→46
  with hip roll |Z| 8→16 (wider feet), knees −70→−84, ankles 30→38, shoulders 25→38 with
  |Z| 22→38, elbows 45→78 (hands up ready).
- `pedal` reshaped: chest over toes (waist −16→−26) and legs deliberately **staggered**
  (L knee −54 / R knee −42) — a symmetric frozen stance reads as standing still.
- `qbSet` reworked to a true two-hand cradle: both shoulders +45 **rolled inward**
  (L +22°Z, R −22°Z) so the hands meet at the midline, elbows +75. *The old pose had
  shoulders 30/35 with no roll, so both hands sat wide of the ball — that is why the QB
  never looked like he was holding it.*
- NEW poses: `qbCarry` (upright cradle, pocket), `snap` (deep hinge over the ball:
  waist −55, knees −70, shoulders 70 forward/down, elbows 20 so hands reach the ground),
  `cover` (ready stance for the DB hole below).
- NEW `Motion.STANCE_FADE` + `Motion.stanceWeight(poseKey, spStuds)`.

### `StarterPlayerScripts.AthleteMotion` — 8 checks, 0 fail
Stance-fade blend applied (two edits in the pose block).

## FINDINGS (measured — these change how the rest should be built)

1. **Poses never froze locomotion.** AthleteMotion applies a pose *multiplicatively* over the
   animation (`cur * j[key].Transform`, line 145), so legs always kept cycling underneath.
   The real defect is the inverse: a full-depth crouch applied to a sprinting body reads as
   *a man running in a squat*, and the deeper `dbCrouch`/`snap` would have made it worse.
   Hence the fade, as data: only poses in `STANCE_FADE` fade; `throw`, `collapse`, `reach`
   verified to apply at full weight at 25–30 studs/s. `qbCarry` and `pedal` keep a 0.55
   weight floor (a backpedal must still look like a backpedal; the cradle must survive a
   pocket shuffle).

2. **The DB "standing around" hole is `G:flip` (TeamFootballService:829)** — it clears the
   pose to `nil`, so from the hip-flip onward the covering defender in `aiDefender`'s
   man-coverage branch (:1579–1583) and the break-on-ball branch (:1573–1575) have **no pose
   at all** and run the stock animation. `dbCrouch` *is* held through the whole pre-snap
   (:722) and `pedal` *is* set on release (:809) — those were fine. Fix: apply `cover`
   after the flip instead of clearing.

3. **Snapper = slot 5 (the RB), not the SLOT receiver.** Measured from the built
   `EndZoneNorth` parts: Field_5v5 halfW 18.375 m → slot 4 sits 7.73 m from the ball vs
   slot 5 at 5.10 m; Field_Yard halfW 28 m → slot 4 at 12.53 m vs slot 5 at 5.10 m. Slot 4
   only wins on the youth fields (smaller `wide`). The helper must **measure the formation
   table each `setupDown`**, not hardcode a slot.

## REMAINING (all blocked on the bridge)

- `TeamFootballService`: `snapperSlot` helper; edits in `setupDown` (ball spotted on the
  ground at the LOS + snapper placed over it in pose `snap`), `getSet`, `snap` (hand off to
  QB = the snap moment; set `qbCarry`), handoff, scramble, `pumpFake`, `flip` (apply `cover`
  per finding 2), `aiDefender`, `sendBall` (new `mode = "spotted"`).
- `TeamFootballClient`: render `mode == "spotted"` (ball laid on the ground at the LOS,
  ~8° nose-up, trail/glow off) and position the held ball at the **LeftHand–RightHand
  midpoint** for the QB. Plan: identify the QB from the published `AWPose` attribute
  (`football:qbSet` / `qbCarry`) rather than adding a server field, and claim arms as
  `"busy"` for him so the `tuckR` layer doesn't fight the cradle — the running carrier's
  `tuckR` stays exactly as it is.

## On reconnect, in this order
1. Verify `AWMotion` and `AthleteMotion` still hold the work above (compile + pose keys).
2. Re-run the 9-script mirror (see `active.md` — only TeamFootballService is fresh).
3. Finish the remaining edits above.
