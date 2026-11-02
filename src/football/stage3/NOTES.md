# Stage 3 — defender, tackling, contested catches

Five files, all under `/home/claude/build/stage3/`. Written to drop into the existing Practice Field rebuild
(`AWPractice`) without editing a line of `PracticeService` or `PracticeClient`.

| File | Goes to | Class |
|---|---|---|
| `Tackle.lua` | `ReplicatedStorage.AWPractice.Tackle` | ModuleScript |
| `Contest.lua` | `ReplicatedStorage.AWPractice.Contest` | ModuleScript |
| `config-additions.lua` | **patch** into `ReplicatedStorage.AWPractice.Config` | — |
| `TackleService.server.lua` | `ServerScriptService.TackleService` | Script, `Disabled = true` |
| `TackleClient.client.lua` | `StarterPlayer.StarterPlayerScripts.TackleClient` | LocalScript, `Disabled = true` |

Both scripts are safe to insert into the live place while disabled: nothing runs until you untick `Disabled`, and
when they do run they refuse to start (one `warn`, then `return`) if `AWPractice` is missing or if the Config patch
has not been applied. Neither ever writes to the ball, the field, or any instance the other scripts own.

Verified before handing over: all five files compile with `luau-compile`, and a 46-assertion behavioural harness
over `Tackle` and `Contest` passes — every cell of the counter matrix, 0 fumbles in 200 wrap tackles, the fatigue
cap, range/angle/startup rejections, tie-to-offence, and determinism (same input twice, same answer).

---

## Ported vs invented

### Ported, numbers unchanged, from `AWFootball.Config` / `AWFootball.Rules`
The older 1v1 mode already had a played-in tackle system. Most of this is that system, restructured.

- `tackle.cooldown 0.9`, `lungeTime 0.3` → `diveTime`, `lungeSpeed 12.5` → `diveSpeed`, `wrapDrag 0.45`,
  `breakWindow 0.35`, `jukeImmunity 0.28`, `facingCos 0.15` → `diveCos`.
- The whole `move` block: `jukeTime/jukeCooldown/jukeSpeed`, `spinTime/spinCooldown/spinSpeed`, `stiffArmStun 0.7`.
- `jump.jumpSpeed 6.2`, `jump.gravity 22` (so the leap's apex and height are identical to 1v1's),
  `catch.contestRadius 1.1` → `contest.radius`, `jump.needHeight 0.55` → `contest.heightTol`.
- The *shape* of `Rules.resolveTackle`: range gate → facing gate → juke immunity → closing speed and approach angle.
  `Tackle.geometry` computes exactly the same four numbers (`d`, `facingCos`, `closing`, `alphaCos`) with the same
  sign conventions, so the two modes describe the same events. Outcome names `NOT_LIVE / NO_CONTACT / WHIFF / WRAP`
  are carried over deliberately.
- The wrap lifecycle (wrap → break window → drag → down) is `FootballService:attemptTackle` / `breakWrap` /
  `finishWrap`, reorganised so the rules live in the module and only the effects live in the service.
- The whiff-cancels-recovery rule (a hit or a wrap voids the whiff penalty) is kept.

### Ported from the GDD as design, with its own starting numbers
- Wrap vs dive as two distinct tackles with different reach, arcs and miss costs.
- The counter matrix (§3.7), implemented cell-for-cell as rules checked before anything else.
- The break terms (§4.5.2): base / momentum / angle / stiff-arm quality / spin / fatigue, with the doc's values.
- Stiff-arm window 0.30 s peaking at 0.15 s, front 120° only, full cooldown on a whiff (§4.5.3).
- Momentum break and gang tackle (§3.7).
- The whole jump-ball calculation (§4.4): 0.45 timing / 0.35 position + box-out / 0.20 reach height, ties to the
  offence, `h_hand` parabola, `INT_THRESHOLD`.
- Latency handling (§4.6): client stamps every intent, the server clamps it to its own clock, positions come from a
  history buffer, contests resolve at arrival + `resolveDelay`.

### Invented here (and why)
1. **Reach is measured, not a constant.** `Tackle.reach(armReachM, kind, cfg)` takes the tackler's real
   shoulder→elbow→palm length, read off the R15 joints by `Receive.rig` exactly as `Receive` does it, and only adds
   the margins: the carrier's torso (`bodySlack`, = `Receive.TORSO_R`), the network allowance (`latencySlack`, same
   0.35 m as `Config.possession`), and `diveExtra` for a full-stretch dive. A stock R15 gives wrap 1.26 m / dive
   1.61 m, which lands on the GDD's `TACKLE_RANGE` of 4 studs (1.40 m) from the other direction. The old mode's flat
   `reach = 1.35` is therefore *not* ported — it is now derived, and a long-armed avatar genuinely reaches further.
2. **Deterministic breaks instead of `P_break` dice.** The GDD offers `TACKLE_RESOLUTION = "threshold"` as an
   explicit knob; this takes it. The same terms are summed and compared to `breakAt = 0.5`, and the reason string
   names the term that decided it ("STIFF-ARM · BROKE IT", "ARM TACKLE FROM BEHIND · BROKE IT"). This is the
   Practice rebuild's house style — `Receive.judge` does the same thing for catches — and it is why the acceptance
   criterion "both players can explain why they won or lost" is reachable at all.
3. **Deterministic fumbles instead of a 1% roll.** A fumble needs four visible things true at the same instant: it
   was a dive, the ball was away from his body (spinning, or inside `jukeRecovery`), the closing speed was at least
   `fumbleClosing` (0.8) of a sprint, and it came from more than 120° behind him. Rare by construction rather than
   by probability, and never a mystery. `0 fumbles in 200 wrap tackles` is a theorem here, not a measurement.
4. **`maxBreaks = 2`, a hard fatigue stop.** The soft `BREAK_FATIGUE 0.10` term only bites on the score path; the
   counter-matrix cells hand the carrier a *free* win, so a runner with a stiff-arm off cooldown would break every
   tackle on a long carry. Past two breaks on one carry the matrix stops rescuing him and the reason reads
   "GASSED · 2 BROKEN ALREADY, NOTHING LEFT". The harness confirms the stiff-arm stops working after 2.
5. **A dive ignores a stiff-arm.** Needed to make the matrix exact — without it the dive's own `breakBaseDive 0.25`
   plus a peak stiff-arm clears `breakAt`, and the dive would lose to the arm, which is the opposite of the design.
   Now the dive explicitly goes in under it (`saQ = nil` for dives).
6. **`jukeRecovery 0.25 s`**, `missMargin`, `perfectBand 0.06`, `minToCatch 0.35`, `jukeAnswer 0.12`, `diveExtra 0.35`
   — small values the GDD leaves unnamed, each with a one-line rationale in `config-additions.lua`.
7. **Role is a toggle, not a team.** Practice has no teams, so a player presses `K` (or D-pad right) to stand on
   defence. Documented on the HUD. The carrier is always offence regardless of the toggle.
8. **The gamepad's two shoulder triggers do four jobs.** Stages 1–2 already spend every face button, D-pad direction
   but one, and both R-triggers. L1/L2 therefore mean different things by side, and on offence L1 reads the
   thumbstick (left/right = juke that way, centred = spin). The HUD always says which, so nothing is hidden.
   Keyboard keeps four distinct keys. This is the one place I'd expect Don to want a different answer.

### Changed on purpose
- `wrapCos = 0.5` (60°, the GDD's `WRAP_CONE_HALF`) instead of the old mode's single `facingCos = 0.15` (≈81°) for
  both tackles. A wrap now needs you to be facing him, which is what makes taking an angle a skill; the dive keeps
  the old forgiving 0.15 because it is aimed and committed.
- `jump.gravity 22` and `jumpSpeed 6.2` are reused as the *contest's* jump model only. They are not Roblox's gravity
  and nothing is simulated with them — they define the `h_hand` curve so the contest and 1v1 agree on what a
  well-timed leap is worth.

---

## The seam `TackleService` needs from `PracticeService`

`PracticeService` owns the ball and exposes no server-side way to change possession. `TackleService` needs exactly
three verbs, and looks for them on **one optional BindableFunction**, `ServerStorage.AWPracticeBall`:

| Invoke | Does | Needed for |
|---|---|---|
| `("down", cause)` | `HELD → DEAD` with that cause | a completed tackle, an incompletion |
| `("fumble", {pos, vel, cause})` | `HELD → LOOSE` at `pos` with `vel` (studs) | a fumble |
| `("award", {model, cause})` | `→ HELD` by that body | a won jump ball, an interception |

The twelve lines to add are quoted verbatim in the header of `TackleService.server.lua`. They only call
`goDead`, `setState` and `giveTo`, which already exist, and change no existing behaviour.

**It runs without the seam.** Every tackle is still decided, reported and penalised (tackler recovery, grounded,
stun, carrier drag and stumble, fatigue), and both players see the reason. What it cannot do is blow the whistle, so
the carrier stays up; one warning is printed once, and `stats.noSeam` counts how often it mattered. Fumbles have a
zero-seam fallback: the carrier's own `drop` intent is replayed through the existing `AWPracticeTest` hook, which is
a legal `HELD → LOOSE` transition. Jump balls without the seam are an advisory ruling only — `PracticeService`'s own
catch sweep still decides possession, and the contest message is the explanation shown to both players.

### What it reads with no seam at all
- **Ball state and revision** — `ServerStorage.AWPracticeTest:Invoke("ball")`, already present, read-only.
- **The securing window** — `…:Invoke("log")`, read-only, to learn the intent of the last catch so a hit on an
  unsecured ball is an incompletion rather than a tackle. *(This is the one read I am least comfortable with: that
  hook is described in `PracticeService` as a Studio test hook. If you would rather not depend on it in production,
  the cleanest fix is one extra attribute — `PracticeService` setting `AWSecuringUntil` on the carrier's model — and
  `TackleService` reading that instead. Everything else degrades gracefully; this one silently stops distinguishing
  a hit-before-secure, which then reads as a normal tackle.)*
- **Who is carrying** — geometrically. A held ball sits exactly on `Carry.cframe(holder)`, so the body whose hand
  frame matches the ball part (within 0.35 studs) is the carrier. No name matching, so two players with the same
  display name cannot confuse it.
- **Velocities** — `TackleService`'s own position history, same 0.1 s window method as `PracticeService.bodyVel`.
- **Reach and standing reach** — `Receive.rig(model)` on the real avatar.
- **Movement plausibility** — `Config.validate.speedSlack`, read-only. `PracticeService` owns pulling people back;
  `TackleService` only *refuses a contact intent* from a body that was moving impossibly, so a speed exploit cannot
  buy a tackle. Two scripts must never both snap a character back.

### Why its own remotes
`TackleIntent` / `TackleState`, not `PracticeService`'s `Intent` / `State`. Sharing `Intent` would mean tackle taps
drain the Stage 1–2 token bucket (`Config.net.maxIntentsPerSecond`) and starve passing. The client *listens* to
`State` read-only to learn the ball revision, which is safe — every handler on a RemoteEvent still fires.

---

## Every decision made on Don's behalf

1. Deterministic break resolution, not dice (GDD's own `threshold` knob).
2. Deterministic fumbles — four visible conditions — instead of a 1% roll.
3. `maxBreaks = 2` as a hard fatigue stop on top of the soft `fatigue` term.
4. A dive ignores a stiff-arm (required to make the matrix exact).
5. Reach measured off the rig, replacing the old flat `tackle.reach = 1.35`.
6. `wrapCos` tightened to 60°; `diveCos` left at the old forgiving 0.15.
7. Separate remotes rather than sharing `Intent`.
8. Carrier resolved geometrically rather than by `holder` name.
9. Role chosen by a toggle key, since Practice has no teams.
10. Gamepad L1/L2 are side-dependent, and L1 reads the thumbstick on offence.
11. New keyboard keys `Z X C V B N K`, chosen to leave every PracticeClient binding alone
    (it has `E T O Q R F G SHIFT SPACE`), and CAS priority 3090 (below its 3100) so nothing of Stages 1–2 is sunk.
12. Touch buttons on the **left** of the screen; PracticeClient's are all on the right.
13. The optimistic lunge is applied from `Heartbeat`, which runs after PracticeClient's movement step, so for those
    few frames this script is the last word on `WalkSpeed` / `Humanoid:Move`. Nothing is patched to achieve that.
14. The client never claims an outcome. If the server does not answer within 0.4 s the lunge is cancelled and the
    toast says so. Penalties are only ever applied from the server's message.
15. A dive is an *open window* (`diveTime`) re-checked every tick against the real measured positions, rather than a
    simulated lunge on the server. The client owns character movement, so the server has no business predicting it.
16. The contest resolves at the ball's observed closest approach plus `resolveDelay`. Nothing is predicted — the
    real ball part's position is read each tick.
17. `PracticeService`'s partner and its scripted test dummies are adopted as bodies, so they can be tackled and can
    contest; a dummy with the attribute `AWRole = "defense"` counts as a defender.

---

## How to test it in Studio

**Install (place is unsaved — save a copy first).**
1. Apply `config-additions.lua` into `ReplicatedStorage.AWPractice.Config`: paste the two blocks between
   `Config.pass = { … }` and `Config.net = { … }`. Change nothing else.
2. Add `Tackle` and `Contest` as ModuleScripts under `ReplicatedStorage.AWPractice`.
3. Add `TackleService` as a Script in `ServerScriptService` and `TackleClient` as a LocalScript in
   `StarterPlayer.StarterPlayerScripts`. **Leave both `Disabled` until you have read them.**
4. Add the twelve-line seam to the end of `PracticeService` (quoted in `TackleService`'s header). Optional — skip it
   for the first pass if you want to watch the reasons without the ball ever changing hands.
5. Untick `Disabled` on both scripts.

**Smoke test (one player, Play Solo).**
1. Walk onto the Practice Field. Two HUD panels: Stage 1–2's on the right, `CONTACT · OFFENCE` on the left.
2. Press `T` — the partner throws you a pass; hold `E` and catch it. The left panel should now say
   `CONTACT · CARRYING` with `RUN IT`.
3. Press `Z`, `X`, `C`, `V`. Each should cut/spin/throw the arm out instantly (optimistic) and its bar should empty
   and refill at the cooldown in `Config.tackle`.
4. Press `K`. The panel turns to `CONTACT · DEFENCE` and shows `B WRAP` / `N DIVE`.
5. `E` the ball onto the partner (hand-off), then stand next to him and press `B`. Output window: a `[Tackle]`
   result. Console: `ServerStorage.AWTackleTest:Invoke("results", 10)`.
6. Press `N` from 2 m out with nothing in front of you — you should end up on the floor for ~1 s.

**Scripted tests (Server-side console, during Play).** Combines the two hooks; nothing here needs a human.

```lua
local ST, PT = game.ServerStorage.AWTackleTest, game.ServerStorage.AWPracticeTest
-- a defender dummy two metres in front of the tee, marked as defence
PT:Invoke("dummy", { key = "D1", pos = Vector3.new(432, 0.25, -470), defense = true })
PT:Invoke("dummy", { key = "R1", pos = Vector3.new(432, 0.25, -476) })
PT:Invoke("give", "R1")                               -- R1 is the carrier
ST:Invoke("role", { name = "TestDummy_D1", role = "defense" })
ST:Invoke("tackle", { by = "TestDummy_D1", kind = "wrap" })
print(ST:Invoke("results", 5)[1].reason)              -- expect "WRAPPED UP" or a stated break
```

- **Counter matrix, cell by cell.** `ST:Invoke("move", { by = "TestDummy_R1", move = "stiffarm" })` then immediately
  a `wrap` → `BROKEN`, reason names the stiff-arm. The same against a `dive` → `TACKLED`. `move = "spin"` then
  `wrap` → `BROKEN`; `spin` then `dive` → `TACKLED`. `jukeL` then either → `WHIFF`.
- **Fatigue.** Repeat stiff-arm + wrap on the same carry. The third should read `GASSED · 2 BROKEN ALREADY`.
- **0 fumbles in 200 wrap tackles.** Loop the `wrap` call 200 times and read `ST:Invoke("state").stats.fumbles`.
  It is 0 by construction — a wrap never reaches the fumble test.
- **Jump ball.** `PT:Invoke("qbTo", { to = "R1", kind = "LOB", aimUp = 1.2 })`, then
  `ST:Invoke("jump", { name = "TestDummy_R1" })` and `ST:Invoke("jump", { name = "TestDummy_D1", at = workspace:GetServerTimeNow() + 0.2 })`
  to give the defender a late leap. Read `ST:Invoke("contests")` — each entry has the result, the reason, and every
  component score. Give them identical jump times to see `SIMULTANEOUS CATCH · BALL GOES TO THE OFFENCE`.
- **Rate limiting and staleness.** Fire more than `Config.net.maxIntentsPerSecond` tackle intents in a second and
  watch `stats.rateLimited`; change possession between the client's `rev` and the server's and watch `stats.stale`.
- **No seam.** Delete `ServerStorage.AWPracticeBall` and re-run a tackle: exactly one warning, the reason still
  shows, `stats.noSeam` increments, the carrier stays up.

**Evidence to retain** (`coding-standards.md` makes Visual and UI blocking): a screenshot of each HUD state —
`CONTACT · OFFENCE`, `CONTACT · CARRYING`, `CONTACT · DEFENCE`, a `WRAPPED · x.xxs TO BREAK IT` countdown, and a
contest toast showing the component scores — into `production/qa/evidence/`.

---

## Things I am not fully confident about

1. **`Heartbeat` runs after PracticeClient's movement step.** This is the one load-bearing assumption in the
   optimistic animation. PracticeClient moves on `RunService:BindToSimulation(…, Hz60)` where available and
   `PreSimulation` otherwise; `Heartbeat` fires after physics, so the last `Humanoid:Move` before the next step
   should be mine. **Verify in Studio** by diving and watching whether the lunge actually displaces you. If it does
   not, bind the lunge to `PreSimulation` at a later connection instead — the fix is one line.
2. **`RunService.BindToSimulation` / `Enum.StepFrequency`** are newer APIs that PracticeClient already guards with
   `pcall`. `TackleClient` does not use them at all, so this only matters for point 1.
3. **Multiple `OnClientEvent` handlers on one RemoteEvent.** `TackleClient` listens to `PracticeService`'s `State`
   read-only to learn the ball revision. I am confident every connected handler fires, but it is worth one glance:
   if the revision in the left panel ever lags, read the ball part's `rev` attribute instead.
4. **`UserInputService:GetGamepadState`** returns a table of `InputObject`s and I read `Thumbstick1` from it. Fine
   on a real pad; untested with no pad connected (it returns an empty table, which falls through to `doSpin`, which
   is the intended default).
5. **`Players:CreateHumanoidModelFromDescription` dummies and `Receive.rig`.** The rig reader returns `nil` for
   anything that is not a full R15, and both reach functions fall back to a stock arm (0.72 m / 2.1 m standing).
   Worth checking that the test dummies actually read as R15 rather than silently taking the fallback —
   `ST:Invoke("state")` does not report it, so add a `print(Receive.rig(model) ~= nil)` if it looks off.
6. **`AnimationConstraint` vs `Motor6D`.** `Receive.isJoint` already handles both and I did not touch it, but
   `Tackle`/`Contest` inherit whatever it decides about a given avatar.
7. **The contest's closest-approach detection** fires on the first tick the ball's distance stops shrinking. At 60 Hz
   and a 21 m/s bullet that is a ~35 cm granularity, which is fine for a lob but coarse for a flat pass. If contested
   bullets read wrong, the fix is to interpolate the closest approach across the two ticks the way
   `Receive.segSeg` does for the hands, rather than taking the tick itself.
8. **`contest.resolveDelay = 0.20 s`** is a real 200 ms wait between the ball reaching the hands and the ruling
   appearing. The GDD says the catch animation covers it. There is no catch animation yet, so it may read as a hitch;
   lower it to 0.12 if so.
9. **Spin/juke directions** are sent to clients as `move` messages and animated locally; the server only uses the
   *timing windows*, never the displacement. So a spin that looks like it carried you somewhere the server disagrees
   with is possible at high ping. The movement checks `PracticeService` already runs are what bound that, and I
   deliberately did not add a second one.
