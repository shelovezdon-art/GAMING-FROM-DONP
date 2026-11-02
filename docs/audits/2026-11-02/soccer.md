# ALLSTAR WORLD — Soccer audit: what is actually built

Read-only audit of a live Studio session (`52e32916-3102-403b-a01b-8b4d550c1fae`, Edit
datamodel), 2026-11-02. Nothing in the place was modified.

Sources read in full:

| Path | Lines |
|---|---|
| `ServerScriptService.SoccerService` (Script) | 1675 |
| `StarterPlayer.StarterPlayerScripts.SoccerClient` (LocalScript) | 354 |
| `ReplicatedStorage.AWSoccer.Config` | 42 |
| `ReplicatedStorage.AWSoccer.Rules` | 125 |
| `ReplicatedStorage.AWSoccer.Touch` | 77 |
| `ReplicatedStorage.AWSoccer.BallLook` | 76 |
| `ReplicatedStorage.AWSoccer.Kick` | 129 |
| `ReplicatedStorage.AWSoccer.SoccerCam` | 184 |
| `ReplicatedStorage.AWSoccer.Athlete` | 119 |

All line references are from those reads and are stable while the place is unedited.

---

## Headline correction

**Soccer is much further along than "mid-priority, behind football" suggests.** The two things
named as the headline asks — a close-control touch model and a low behind-the-player camera —
are **both already built and wired end to end**, and the **outdoor stadium is built, tagged and
is the pitch the service actually resolves at startup**. The gap to the vision is now mostly
*surfacing and finish* (grass material, ball scale, stale signage), not architecture.

What is genuinely missing is the referee layer (no offside, no fouls) and anti-cheat.

---

## 1. Ball physics and authority

### Authority: server-owned, and correctly so

**The ball is server-authoritative.** It exists only as a plain Lua table on the server
(`SoccerService:413-422`) — `{x, y, z, vx, vy, vz, curl, held, dr, lastTouch, lastToucher}`. There
is no ball `BasePart` in the world at all; `AWSoccer.BallLook` builds a purely cosmetic,
`Anchored = true`, `CanCollide = false`, `CanQuery = false` view model on each client
(`BallLook.lua:21-43`). Clients cannot touch, push or own the ball.

The server advances it on `RunService.Heartbeat` (`SoccerService:1578-1582`) through
`Rules.step`, which fixed-substeps at 120 Hz (`Rules.lua:66-74`) so the result is
frame-rate independent. Clients receive snapshots and run **the same integrator** locally to
interpolate between them (`SoccerClient:344-349`), with the snapshot's transport lag replayed on
arrival and a decaying position offset to hide the correction (`SoccerClient:274-281`,
`345-347`). This is the right design and is cleanly done.

Snapshot rate: 4 Hz for a loose ball (`SoccerService:1480-1481`, `snapTimer = 0.25`), plus an
immediate `sendBall()` on every state change (touch, strike, tackle, save, restart). While the
ball is carried, no position is sent at all — only the **touch plan** is (see §2), so the client
reconstructs the carry exactly. Bandwidth is low and the approach is sound.

**All scoring is server-side.** Goals are detected inside the integrator by plane crossing
(`Rules.lua:49-62`) and raised to `G:goal()` (`SoccerService:1083-1085`). A client cannot
assert a goal. The scoreboard the client renders is pushed from the server at 10 Hz
(`SoccerService:1514-1523`). **No client-trusted scoring.**

### Physics model — BUILT

Metres and seconds throughout the logic; `S = 1/0.35` converts to studs at the edges only.

| Quantity | Value | Where |
|---|---|---|
| Gravity | 9.81 m/s^2 | `Config:9` |
| Ball radius | **0.22 m** (0.44 m diameter) | `Config:9` — see risk R-07 |
| Bounce restitution | 0.55, only when `vy < -1.2` | `Config:9`, `Rules.lua:45` |
| Roll friction | exponential, `k = e^(-0.9*dt)` | `Config:9`, `Rules.lua:29-31` |
| Air drag | linear 0.06, horizontal only | `Config:9`, `Rules.lua:26-27` |
| Curl (side-spin) | 4.5 m/s^2 lateral, decays `*(1-0.45*dt)` | `Config:31`, `Rules.lua:34-41` |
| Sleep threshold | speed^2 < 0.0025 -> zeroed | `Rules.lua:31` |

Air drag is applied **only while airborne** and not to `vy`; rolling uses friction instead. Curl
bends the flight perpendicular to travel and fades — used for finesse shots (`:867`) and
in-swinging crosses (`:817`).

Goal frame is modelled properly: posts and crossbar are solid, with distinct restitution
(`Rules.lua:55-60` — post `vz*-0.7`, bar `vz*-0.5` plus upward kick), and the ball radius is
subtracted from the aperture so a ball clipping the post does not count.

---

## 2. Touch / dribble control — BUILT (this is the close-control model)

`AWSoccer.Touch` is a 77-line pure module implementing exactly the "ball is never glued to the
player" model the vision asks for. **This is the owner's headline ask, and it exists.**

A carry is a **drive**: `{t0, x0, z0, dx, dz, v0, a, T}` — the ball is pushed off the foot at `v0`,
decelerates at constant `a`, and the foot is due to meet it again after the stride `T`
(`Touch.lua:5-8`). The maths is closed-form and deliberate (`Touch.lua:33-39`):

```
a  = 8*L / T^2        v0 = vp + 0.5*a*T
```

which makes the ball peak exactly `L` metres ahead of a player moving at `vp` and arrive back at
his foot at `t = T`. Below `dribble.still` (0.5 m/s) the ball is left stationary — standing on it.

Rhythm scales with pace (`Touch.rhythm`, `Touch.lua:24-29`), interpolating walk->jog and
switching to a longer, heavier sprint touch:

| | stride `T` (s) | lead `L` (m) |
|---|---|---|
| walk (1.5 m/s) | 0.50 | 0.18 |
| jog (6.0 m/s) | 0.42 | 0.55 |
| sprint | 0.62 | **1.35** |

Re-touch is decided by `Touch.want` (`Touch.lua:51-67`), which fires on any of: the stride coming
round (`d <= reach` and `t >= 0.8*T`), the ball falling behind the foot (`along < -0.15`), the ball
going dead (`bv < 0.4`), or **a change of direction** — `(dr.u) < turnDot` where `turnDot = 0.8`,
i.e. a turn of more than ~37 degrees needs a fresh touch and until then the ball keeps rolling the
old way (`Touch.lua:64`). That last rule is precisely the "turns cost you a touch" feel.

Server side, `G:updateDribble` (`SoccerService:1159-1190`) runs this each tick against the
player's **foot** position (`G:foot`, `:604-607`, 0.42 m ahead of the body centre) and the
direction he is *asking* for — for a human that is `Humanoid.MoveDirection`, not his velocity, so
the stick leads the ball (`G:wantDir`, `:609-617`). Lose the ball by more than
`dribble.loseDist = 4.0 m` from the foot and it becomes loose with a "HEAVY TOUCH"
(`:1172-1179`). First touch on gaining possession kills the pace and restarts the drive from the
foot (`G:takeBall`, `:630-645`), followed by a `settle = 0.45 s` window before a pass or shot is
allowed (`:643`, enforced at `:651`).

The client reconstructs the identical drive from the 9-number packed array the server sends
(`SoccerService:1494`, decoded `SoccerClient:270-273`, evaluated `SoccerClient:331-336`), so
carried-ball motion is smooth and exact without streaming positions.

The body sells it: `AWSoccer.Kick` adds a toe-push on each touch (`Kick.lua:111-124`) and a full
plant / backswing / follow-through on strikes (`Kick.lua:14-78`), driven by attributes
(`AWSTouch`, `AWSTouchFoot`, `AWSStrike`) the server stamps on the model, and the correct foot is
chosen from which side of the body the ball sits (`SoccerService:665-666`, `:1185-1186`).

**Verdict: the close-control model is built, coherent and better than typical Roblox sports
code.** What it lacks against the Instagram reference is listed in `gap-to-vision.md` section 1 —
it is tuning and shielding, not a rebuild.

---

## 3. Passing and shooting — BUILT

**Strike timing.** Passes and shots are not instant. `G:strike` (`:648-671`) starts a windup
(pass 0.17 s, through 0.20 s, shot 0.28 s — `Config:25`), rolls the ball onto the striking foot
over that window via `Touch.roll`, and the actual release happens in `G:updateStrike`
(`:672-680`) when the clock arrives. It refuses if the ball is further than
`strike.maxReach = 2.2 m` from where the foot will be ("GET TO THE BALL FIRST", `:661`).

**Passing** (`G:passNow`, `:782-833`). Target is chosen by a solver, not by the client: each
team-mate is scored on alignment with the aim direction, openness from the nearest defender, and
a long-range penalty (`G:passTarget`, `:702-719`,
`sc = align*3 + min(open,6)*0.35 - max(0,d-22)*0.2`). Velocity is solved so the ball *arrives* at
about `pass.arrive = 4.5 m/s` given exponential roll friction (`Rules.passVelocity`,
`Rules.lua:77-87`), clamped to 7-22 m/s. Variants:

- **Through ball** — hold-weighted. `w = 1 + held*holdLead`, pushing the target
  `throughLead*w` plus `throughExtra*w` downfield, and the receiver is given a `runOnto` order
  (`:805-810`).
- **Lofted through ball** — holding past `loftHold = 0.45 s` switches to a lob with 1.0-1.9 s
  hang time (`:812`, `Rules.lua:81-84`).
- **Cross** — automatic when a through ball is played from wide (`|x-cx| > halfW*0.5`) in the
  final third (`:796-798`). Retargets to the best runner in the box (`G:crossTarget`, `:722-740`),
  adds in-swinging curl (`:817`), and then **forward-simulates the real flight to find where it
  drops through head height** and sends the runner there (`:821-828`). A genuinely good touch.

**Shooting** (`G:shootNow`, `:835-877`). A held power meter: `chargeTime = 1.0 s`, sweet band
0.66-0.9 (`Config:29`), graded GREEN / GOOD / OVER / WEAK (`Rules.gradeShot`, `Rules.lua:90-96`).
Speed scales 12->28 m/s. Aim comes from the camera: the horizontal ray is intersected with the
goal line and clamped inside the frame (`:844-847`), and **camera pitch sets the height** —
look up for the top corner, down to drill it low (`:850-851`, `up` clamped -0.6..0.9,
`upGain = 2.4`). OVER adds `overLift = 1.6 m` so over-powering sails it. Accuracy is a Gaussian
with the same formula for humans and AI: `errGreen = 0.35` vs `errOff = 1.6`, plus
`errPressure = 0.9` when a defender is within 1.6 m and `errSprint = 0.5` when sprinting
(`:855-860`). Finesse curl is derived from aiming across the body (`:866-867`).

**Headers** — BUILT (`G:header`, `:744-781`): a ball between `headLo = 1.15 m` and
`headHi = 2.6 m` falling at `vy < 3` is met by the first outfield player within
`headReach = 2.2 m` (`:1106-1115`), nodded at goal inside `headShotRange = 18 m`, otherwise on to
a team-mate or down to his own feet.

**Blocks and heavy touches** — BUILT (`:1131-1142`): a shot over `blockSpeed = 14 m/s` always
deflects off an outfield player rather than being controlled; a firm pass over
`fastBall = 17 m/s` is a probabilistic heavy touch that gets harder with speed. Keepers are
exempt.

**Skill moves** — BUILT (`G:skill`, `:950-992`). The stick direction picks the move, FIFA-style:
straight ahead -> knock-on (ball 2.6 m ahead plus a burst), to a side -> cut/step-over, back or
standing -> roulette. Each gives `immune = 0.4 s` of tackle immunity and a `cd = 1.1 s` cooldown,
and the body is posed by `Kick.lua:80-110`.

**Tackling** — BUILT. Standing tackle (`G:tackle`, `:994-1024`) is a chance model:
`standBase = 0.5`, x1.35 if the carrier is sprinting, x0.5 if he is nearly stationary (shielding),
0 during immunity, and raised to 0.85 when the ball is off his foot — "nicking" it
(`:1008`, `nickFrom = 0.85 m`, `nickReach = 0.7 m`). Slide tackle (`G:slide`, `:1026-1038`,
resolved in `G:updateSlides`, `:1040-1064`) lunges 10.5 m/s for 0.45 s with a 0.9 s recovery and
a 1.6 s cooldown, and only connects on a ball under 0.7 m high.

---

## 4. Goals and scoring — BUILT

Detection is geometric and server-side (`Rules.lua:49-62`), raised at `SoccerService:1083-1085`.
`G:goal` (`:523-540`) handles: score increment, **own-goal detection**
(`own = scorer.team ~= team`, `:527`), "TOP BINS" when the ball crosses above `topBins = 1.6 m`
(`:528`), header attribution (`:529`), scorer naming, cheer poses, the celebration broadcast, and
an LED flash of the scoring team's colour across the stadium ring and facade (`G:ledFlash`,
`:543-562`, which restores the original colours afterwards — correctly written).

Match flow — BUILT. States `lobby -> countdown -> kickoff -> live -> (goal | restart) -> final`
driven from one `update` (`:1424-1484`). 5-minute clock (`match.duration = 300`), 8 s countdown,
4 s goal delay, 7 s final. Restarts cover **kick-in, corner and goal kick**
(`G:restart`, `:476-521`) with correct last-touch attribution, the taker placed behind the ball,
opponents pushed back 3.2 m, and a 6 s auto-play for humans who dawdle
(`humanRestartAuto`, `:503`, fired at `:1447`).

**Not built: any referee layer.** No offside, no fouls, no free kicks, no penalties, no cards, no
advantage. A slide tackle through the back of a player is never punished. Grep confirms the words
`offside` and `penalty` appear only in a comment and in the name of a decorative `PenaltySpot`
part.

---

## 5. Camera — BUILT (this is the low behind-player camera)

`AWSoccer.SoccerCam` (184 lines) is a bespoke `BindToRenderStep` camera at
`RenderPriority.Camera + 1` (`SoccerCam.lua:66`) that fully replaces Roblox's follow cam
(`CameraType.Scriptable`). **The owner's second headline ask, and it exists.** Three cycling
modes plus a goal cam (`V` / `R3` / the CAM button, `SoccerClient:218`, `:233`):

| Mode | Geometry (studs) | FOV |
|---|---|---|
| **PLAYER** (default) | 14 back, **7.5 up**, looks 6 ahead, lead 0.35, turn rate 4.5, follow 9 | 62 |
| **TV** | 34 high on the -X touchline, 30 back, lead 0.55 | 48 |
| **FREE** | Roblox default restored | 70 |
| **GOAL** | slow orbit of the scorer, radius 12->, descending, FOV eased to 40 | 40 |

PLAYER mode (`SoccerCam.lua:159-178`) derives yaw from the player's **velocity** when moving
faster than 2 studs/s and his facing otherwise, eases it exponentially
(`1 - e^(-4.5*dt)`), pulls back up to 0.9 studs per m/s over 4 m/s at sprint (`:170`), and leans
the look point toward the ball proportionally to its distance, capped at 0.45 (`:173`). Movement
stays camera-relative, so pushing up the stick runs up the screen (`:7`).

It also fades scenery between camera and player, on that client only, with up to 5 chained
raycasts and an exponential fade to 0.85 transparency, skipping anything with a `Humanoid` or the
ball view (`SoccerCam.lua:34-58`) — and restores `LocalTransparencyModifier` on stop (`:59`).
Goal celebrations hand off to `Cam.celebrate` (`:95-101`), called from `SoccerClient:294`.

Honest assessment against the reference: at **7.5 studs up / 14 back (~2.6 m / 4.9 m)** this is a
low, tight camera and is the right shape. It is somewhat higher and further than the tightest
Instagram references, and it has no shoulder offset, no speed-based FOV, and no ball-anticipation
lead. See `gap-to-vision.md` section 2 — a tuning pass, not a rebuild.

---

## 6. AI — BUILT

Empty outfield slots and **both keepers are always AI** (`startGame`, `:418-421`). The stated
design — same rules for humans and AI — holds in code: the AI calls the same
`G:pass`/`G:shoot`/`G:tackle`/`G:skill` entry points, so it goes through the same solver, the same
windup, the same Gaussian error.

- **`G:aiStep`** (`:1196-1232`) — locomotion. Drives `Humanoid:Move` toward a steer target, slows
  into it (`speed = min(wantSpeed, d*4+1)`), honours lunges and stun, forces facing via
  `hrp.CFrame` when asked, and drives the run/idle animation tracks with speed-matched playback
  including a reverse-shuffle when back-pedalling (`:1229`).
- **`G:aiOutfield`** (`:1240-1367`) — decisions, with `cpu.decide = 0.25 s` cadence and
  `cpu.reaction = 0.2 s`: shoot inside `shootRange = 24 m` at `shootChance = 0.7`, cross at 0.45,
  skill at 0.3, pass under pressure within `passPressure = 2.4 m` at 0.55, tackle every 0.7-1.5 s
  at `tackleChance = 0.5`. Shots use `cpuSigma = 0.1` as a human-like meter error.
- **`G:aiKeeper`** (`:1368-1410`) — positions on an arc between `depthMin 0.6` and
  `depthMax 3.2` m off the line.
- **Saves** (`G:planSave`, `:880-900`) are resolved *deterministically on the shot's clock* rather
  than by collision: predict the crossing with the real integrator, then
  `reach = 0.9 + 4.2*min(flightTime - react, 0.5) - (0.45 if high)` against
  `|crossingX - keeperX|`. A shot that beats that reach is beaten, and `:1124-1128` plus
  `:918-922` make sure a **beaten keeper stays beaten** — his dive animation cannot scoop a ball
  the plan already conceded. This is careful, well-reasoned work and is the most defensible part
  of the AI.

Reaction is beatable by design: `react = 0.28 +/- 0.1 s`, `diveMax = 0.5 s`, and
`highPenalty = 0.45` means placement and power genuinely matter — consistent with "fair and
skill-rewarding".

Deterministic RNG throughout: an LCG seeded per match (`Rules.newRng`, `Rules.lua:9-11`,
`Config.seed = 777`, reseeded at `:414`), with Box-Muller for the Gaussians (`Rules.lua:12-15`).

---

## 7. Modes and player counts — BUILT

- **4v4 outfield + 1 AI keeper per side**, HOME vs AWAY. `SIZE = 4`, roles from `ROLE`.
- **Human capacity 8** (4 per team), enforced at `G:join` (`:351-366`); over-full is refused with
  a toast steering the player to the other side.
- **Drop-in**: late joiners queue in `self.pending` and are seated into AI slots at the next
  kickoff or restart (`G:seatPending`, `:367-390`, called from `:445` and `:477`).
- **Entry** via `JOIN HOME` / `JOIN AWAY` pads built by `G:buildPads` (`:230-261`), plus the
  `Door_SOCCER_BETA` lobby door.
- **Session registry (M07)** — BUILT (`:1617-1674`). Publishes a `Configuration` to
  `ReplicatedStorage.AWSessions` every 0.5 s with state, human count, capacity 8, live score, a
  join pad position and a watch camera, and binds `AWSessionJoin`/`AWSessionHas` handlers, so
  soccer appears in Quick Match / Live Games / Watch and supports drop-in teleport.
- **Auto-leave** if a player wanders more than `halfL + 55*0.35` m from the centre (`:1441`).
- **`TestHook`** BindableFunction (`:1584-1615`) exposing `join`, `intent`, `state`, `pitch`,
  `give`, `ball` for automated testing. Good practice — but see risk R-04.

---

## 8. World side — the outdoor stadium

**The outdoor stadium exists and is the live pitch.** `findPitch` (`:127-166`) prefers whatever
carries the `AWSoccerPitch` CollectionService tag and only falls back to the old indoor hall
(`:129-132`). Exactly one instance is tagged:

```
Workspace.AllstarWorld.43_GrandStadium.Pitch   (Folder)
```

I replicated `findPitch`'s logic against it: it finds 4 `GoalPost` parts, a `floorTop` of 0.3
studs, 2 long sidelines and a crossbar, so **it resolves successfully** and soccer runs in the
stadium, not the hall.

Resolved geometry:

| | Resolved | Real / full-size |
|---|---|---|
| Pitch length | **80.0 m** | 100-105 m |
| Pitch width | **50.0 m** | 64-68 m |
| Goal | **7.20 m x 2.44 m** | 7.32 m x 2.44 m |
| Floor Y | 0.10 m | — |

`43_GrandStadium` is a substantial build — **2307 descendants**: a `Bowl` (1116) with 756 `Fans`,
164 `Seats` and 164 `Step`, a `RoofFacade` (470) and `FacadeExtra` (282), an `LEDRing` (120) with
30 `LEDBoard` and 30 `LEDStrip`, `PitchLights` with 42 `Flood` and 48 `SpotLight`, 8 `Suite`
boxes, 7 flags, a `Plaza` and `Walkways`. It carries `@MovedOnBuild = 1`, `@FloorY = 0.3`,
`@PitchCX = -765`, `@PitchCZ = -58`, and `Workspace.AllstarWorld` has
`AWGrandStadiumCleared = v2` and `AWSoccerLotMoved = true` — consistent with the relocation the
brief suspected. The relocation looks complete and the service follows it via the tag.

**The grass is the real gap.** The 16 `Pitch` surface parts are plain
`Enum.Material.Grass` with **`MaterialVariant = ""`** and two flat mowing-stripe colours
(`RGB 55,138,59` / `63,154,67`). Meanwhile **twelve** custom grass MaterialVariants have already
been generated and are sitting unused in `MaterialService.AssistantMaterials` —
`AW_PitchGrass` 0-3, `AW_NaturalGrass` 0-3, `AW_GrassPaint` 0-3 — each with a ColorMap, NormalMap
*and* RoughnessMap. So the asset work for "real natural grass, no fake turf, no Roblox slop" is
**done but not assigned**. This is the cheapest high-visibility win in the whole audit (see
`gap-to-vision.md` section 3).

**Stale signage.** The old indoor arena `05_Arenas_4` still holds a full decorative pitch — 12
`Pitch` parts, 4 `GoalPost`, 2 `GoalNet`, 21 `Line`, and 4 `Sign_SOCCER` / 4 `Sign_BETA · PITCH`
/ `Sign_SOCCER PITCH` — and lobby wayfinding (`04_Lobby_2.Sign_SOCCER PITCH`,
`10_FieldHouse_3.Sign_SOCCER 1v1 · 2v2`, `03_TrenchShell_1.Sign_SOCCER`) still points players at
it. Those signs now lead to an empty hall. The `Sign_SOCCER 1v1 · 2v2` and
`Sign_1v1 · 2v2 PITCHES SOON` wording also contradicts the 4v4 mode that is actually implemented.

**No audio at all.** Zero `Sound` instances under `43_GrandStadium`, and no `Sound` reference in
any soccer script. No kick, no net, no whistle, no crowd.

---

## 9. BUILT / PARTIAL / NOT BUILT

### BUILT
- Server-authoritative ball, no ball part, shared 120 Hz-substep integrator on both sides
- Close-control touch/drive model with pace-scaled stride, turn-costs-a-touch, collect, lose-ball
- Strike windup (plant/backswing/contact/follow-through) with ball rolled onto the foot
- Ground pass with arrival-speed solve; pass target solver; hold-weighted through ball; lofted
  through ball; automatic cross with in-swing curl and flight-predicted runner
- Power-meter shooting with sweet band, grades, camera-pitch height aim, finesse curl, Gaussian
  error with pressure and sprint penalties
- Headers; shot blocks; heavy-touch dice roll on firm balls
- Skill moves (knock-on / cut / roulette) with immunity and cooldown
- Standing and slide tackles with a chance model and ball-off-the-foot nicking
- Goal detection with posts, crossbar, own goals, top bins; LED celebration; goal orbit camera
- Kick-in / corner / goal-kick restarts with correct last-touch attribution
- 5-minute match flow: lobby -> countdown -> kickoff -> live -> goal -> final, with auto-reset
- Keeper AI with deterministic shot-clock save resolution and beaten-keeper correctness
- Outfield AI using the same solvers as humans; deterministic seeded RNG
- Three-mode bespoke camera (low behind-player / TV / free) plus occluder fading
- Panelled ball view with rolling rotation and a soft shadow
- Rthro athlete bodies, kit painting, shirt numbers and crest
- 4v4 + keepers, 8-human capacity, drop-in queueing, join pads
- Session registry for Quick Match / Live Games / Watch
- Outdoor stadium built (2307 parts) and resolved live via the `AWSoccerPitch` tag
- `TestHook` for automated testing

### PARTIAL
- **Pitch grass** — 12 custom grass MaterialVariants generated, none assigned; pitch is default
  `Material.Grass` with flat colours
- **Ball scale** — radius 0.22 m (0.44 m across, ~2x a real size-5 ball); the `Config:8` comment
  describes 0.14 and is out of step with the value
- **Pitch size** — 80 x 50 m with a **full-size 7.2 m goal**; the goal is large relative to a
  small-sided pitch
- **Signage / wayfinding** — still directs players to the decommissioned indoor hall, and still
  advertises "1v1 · 2v2" rather than 4v4
- **Cosmetics** — kit colours are hardcoded constants; nothing hooks a cosmetic store, so the
  stated cosmetic-only monetization has no attachment point yet
- **Stamina** — drains and regenerates and gates sprint, but has no effect on touch quality,
  accuracy or tackle success
- **Dead/duplicated branches** still executing (see risks R-05, R-06)

### NOT BUILT
- **Referee layer**: no offside, no fouls, no free kicks, no penalties, no cards, no advantage
- **No half-time**, no extra time, no shootout, no added time
- **No anti-cheat / position validation** of any kind (risk R-01)
- **No server-side verification of shot power** (risk R-02)
- **No audio**: no kick, net, whistle, crowd or stadium ambience
- **No substitutions**, no formations/tactics selection, no captain or set-piece roles
- **No persistence**: no soccer stats, records, leaderboard or progression
- **No spectator UI** beyond the session registry's watch camera
- **No replays**, despite an event log (`G:log`, capped at 400) that would support them

---

## Recommendation: rebuild on `AWPractice`, or extend where it stands?

**Extend where it stands. Do not rebuild.** High confidence.

### Soccer already follows the AWPractice conventions — it does not diverge from them

The brief framed `AWPractice` as "the football rebuild's cleaner architecture" and asked whether
soccer follows or diverges. Comparing the cached practice modules against the soccer ones, soccer
**already embodies every convention on that list**, and in two places goes further:

| Convention | `AWPractice` | `AWSoccer` |
|---|---|---|
| Metres & seconds in logic | yes | yes — `Config:1` states it; studs only at the edges |
| Stud conversion constant | `Config.S = 1/0.35` | `Config.STUD = 0.35`, `S = 1/CFG.STUD` at each consumer |
| Pure rules modules, no Instances | yes | yes — `Rules` and `Touch` are Instance-free, shared verbatim by server and client |
| Shared integrator both sides | yes | yes — `Rules.step` on server and client |
| Outcomes carry readable reasons | yes | yes — `G:log` structured events + typed player feedback (`G:fb`) |
| Deterministic seeded RNG | — | yes — LCG + Box-Muller, seeded per match |
| Closed-form touch model | `Carry` | **more developed** — `Touch` solves `a = 8L/T^2`, `v0 = vp + aT/2` |

The one real divergence is cosmetic and is the single thing worth normalising: the stud constant
is **inverted** between the two (`Practice.Config.S = 1/0.35 ~= 2.857` is studs-per-metre;
`Soccer.Config.STUD = 0.35` is metres-per-stud, with each consumer computing `S = 1/STUD`). Same
number, opposite sense, same letter `S` in use at the call sites — a genuine foot-gun for anyone
moving between the two codebases, and a 20-minute fix.

The other gap is the `rev` counter on practice's `BallState`. Soccer has no snapshot revision
number, so a reordered or stale `State` packet cannot be detected and discarded — see risk R-08.
That is worth borrowing, and it is a small, additive change.

### Why a rebuild would be a mistake

1. **There is no architectural defect to rebuild away.** The authority model is already correct
   and is the hard part of a multiplayer ball game. A rebuild would re-derive the same design.
2. **The two headline asks are already in the code.** A rebuild would be re-implementing
   `Touch` and `SoccerCam` to reach a place soccer is already at.
3. **The real gaps are not structural.** Unassigned grass materials, ball scale, stale signage,
   missing audio, no offside, no anti-cheat — every one of these is additive work that lands the
   same whether or not the foundation is rewritten.
4. **~2,800 lines of working, commented, internally consistent code** would be put at risk,
   including the subtle parts that are easy to get wrong and are currently right: the
   beaten-keeper rule, the cross flight prediction, the heavy-touch dice roll, the LED colour
   restore.
5. **Soccer is mid-priority.** Spending the larger budget on a rebuild of the one sport that is
   *not* the current focus, to reach feature parity with itself, is the worst available use of the
   time — particularly with football still the stated first priority.

### Rough cost either way

Estimates are engineering-days for one developer, and are rough.

**Extend (recommended) — about 9-15 days to reach the stated vision**

| Work | Days |
|---|---|
| Assign grass MaterialVariants, mowing stripes, pitch finish (gap section 3) | 0.5-1 |
| Ball scale correction + re-tune the handful of coupled values | 0.5-1 |
| Camera tuning pass: shoulder offset, speed FOV, ball anticipation (gap section 2) | 1-2 |
| Close-control polish: shielding, first-touch error, knock-on weight (gap section 1) | 2-3 |
| Anti-cheat: server position/speed validation + server-timed shot meter (R-01, R-02) | 2-3 |
| Signage and wayfinding repoint, retire the indoor pitch | 0.5-1 |
| Audio pass: kick, net, post, whistle, crowd beds | 1-2 |
| Fix R-03..R-08; normalise the stud constant; add a `rev` counter | 1-2 |
| **Total** | **9-15** |

**Rebuild on the AWPractice pattern — about 25-40 days, for no architectural gain**

Re-deriving `Rules`, `Touch`, the strike pipeline, the save planner, the AI, the camera, the HUD
and the session registry against a new module layout is essentially re-authoring 2,800 lines, plus
re-tuning every number in `Config` against the new code, plus re-testing the whole thing — and it
arrives at the same authority model. It would also stall soccer entirely for the duration while
football is the priority.

**If convergence with the football core is wanted later**, the cheap path is to lift soccer's
`Touch` into a shared module that *both* sports consume (it is already pure, Instance-free and the
more developed of the two carry models), rather than to rewrite soccer to look like practice. That
is a 2-4 day refactor and it moves value in the useful direction.
