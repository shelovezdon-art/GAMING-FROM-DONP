# ALLSTAR WORLD — Performance Risk, Ranked

Target platform: **Roblox mobile**. All numbers measured read-only in the Edit session
on 2026-11-02. Every risk below carries its measurement, its fix, and the rough win.

## What is already right

Credit where due — several expensive mistakes have already been avoided:

- **20,265 of 38,483 parts have `CastShadow = false`** (53%). Someone did this pass.
- **Only 8 of 630 lights cast shadows.** Correct call.
- **`StreamingEnabled = true`.**
- **Only 48 unanchored parts** in the whole world, all of them door frames in
  `07_Doors`, all `CanCollide = false`, and all accounted for by the 48 WeldConstraints.
  This is not the frame-rate killer it usually is. Leave it alone.
- **1,069 of 1,444 SurfaceGuis have a `MaxDistance` limit set.**
- Zero scripts in Workspace means zero per-frame Lua in the world itself.

The problems are concentrated, not diffuse. Three fixes get most of the win.

---

# Will hurt phones NOW

## Risk 1 — The decorative crowd is half the world — CRITICAL

**Measurement.** `06_FootballPark.Field_5v5.Crowd` = **29,777 instances, 47% of the
entire build.** 852 `Fan` models, each 31 instances: 7 Parts, 1 SurfaceGui, 12 Frames,
10 UICorners, 1 UIStroke. That is **852 live SurfaceGui render surfaces** at
`PixelsPerStud = 50`, and **8,478 UICorners + 881 UIStrokes** — both of which force
per-frame GPU work that cannot be batched. The crowd contributes 20,458 of the world's
22,231 GUI objects (92%).

They are static props. None of them move.

**Why it is worse on mobile.** Each SurfaceGui is a render target the GPU must compose
and sample. `UICorner` and `UIStroke` defeat the UI batcher — a mobile GPU pays for all
8,478 corner rounds every frame that any part of the stand is on screen. Both stands are
visible from the field in a single camera frustum (`shots/02`).

**Fix.** Delete the `Phone`/`PhoneScreen` sub-assembly and its SurfaceGui from every
Fan. The phones are 2 of 7 parts and 100% of the GUI cost, and at playing distance they
are two pixels. Then flatten each remaining 5-part fan, or replace whole rows with a
single textured billboard per bleacher row.

**Win.** Removing just the phone assembly: **−26,412 instances (−41% of the world)** and
**−852 render targets**. This one change is larger than every other optimisation on this
list added together.

## Risk 2 — ~11,500 decorative parts are in the physics broadphase — HIGH

**Measurement.** World-wide: `CanCollide` on 6,899 parts, but **`CanQuery` on 18,415**
and **`CanTouch` on 18,130**. The gap is ~11,500 parts that collide with nothing yet sit
in the spatial query structure and the touch broadphase.

Worst folders:

| Folder | Parts | CanCollide | CanQuery | CanTouch |
|---|---|---|---|---|
| `02_Props` | 12,441 | 1,432 (12%) | **11,321** | **11,385** |
| `WasteStations` | 1,457 | 62 (4%) | **1,457** | **1,457** |
| `10_FieldHouse` | 377 | 65 (17%) | 275 | 275 |
| `16_Landscape` | 2,067 | 689 (33%) | 689 | 689 |

**Fix.** Set `CanQuery = false` and `CanTouch = false` on every decorative part that
already has `CanCollide = false`. This is mechanical and safe — a part that does not
collide and is not a gameplay trigger has no reason to be queryable.

**Win.** ~11,500 parts out of the broadphase. Directly cuts the cost of every raycast
the gameplay code will fire (ball physics, player aim, camera collision) and shrinks the
touch-event work the engine does each step. On a phone this is the difference between a
raycast that is free and one that is not.

## Risk 3 — The spawn point is stranded outside the streaming radius — HIGH

**Measurement.** `AW_Spawn` is at (0, 0.29, 428.57). Distance to each playable area:

| Area | Distance from spawn |
|---|---|
| Outdoor basketball court | **668 studs** |
| `43_GrandStadium` (soccer) | **906 studs** |
| `19_PracticeField` | **997 studs** |
| `Field_5v5` (football) | **1,175 studs** |

Roblox's default `StreamingTargetRadius` is **1,024 studs**. The main football field —
the core of the game — sits **beyond the default radius from spawn**. (The streaming
radius properties are not readable from the script sandbox in this session, so I cannot
confirm they are at defaults; if they were raised, that is its own problem, because a
raised radius on mobile means streaming in more of a 38,483-part world at once.)

Meanwhile the *densest* geometry in the build — `02_Props` (12,441 parts),
`03_TrenchShell` (1,754 parts, 138 lights), `04_Lobby`, `17_ArrivalPress` — is clustered
right at the origin, which is what the player loads into.

**Fix.** Move `AW_Spawn` to the football park. The player should land on the thing the
game is about, not 1,175 studs of empty campus away from it. If the arrival plaza is
meant to be the entry experience, keep it but add a teleport, and shrink the props.

**Win.** Correct first-load content set, and the long walk stops being the first
experience of the game.

## Risk 4 — 630 dynamic lights plus a full post-processing stack — HIGH

**Measurement.** 630 lights: 269 SurfaceLight, 214 SpotLight, 147 PointLight.
Concentrated in `03_TrenchShell` (138), `02_Props` (128), `05_Arenas` (105),
`43_GrandStadium` (58), `17_ArrivalPress` (52), `15_LobbyFill` (37).

Lighting: `GlobalShadows = true`, `ShadowSoftness = 0.2`, `Brightness = 2`,
`ClockTime = 17.7`, `ExposureCompensation = -0.15`.

Post-processing children, all enabled except one: `Sky`, **`SunRaysEffect` (on)**,
`Atmosphere`, **`BloomEffect` (on)**, `DepthOfFieldEffect` (off — good),
**`ColorCorrectionEffect "AW_Grade"` (on)**.

**Why it hurts.** `ClockTime 17.7` is dusk, which is the single most expensive time of
day: every one of those 630 lights is visually active against a dark scene, which is
exactly what the screenshots show. SunRays and Bloom are both full-screen passes. On a
mid-range phone, SunRays alone is commonly 2–4 ms per frame.

**Fix.** Three steps, in order of payoff:
1. Disable `SunRaysEffect` on mobile. Keep Bloom and the colour grade — they are doing
   most of the visual work and cost less.
2. Cull the light count. `03_TrenchShell`'s 138 lights are in a structure that is a
   deletion candidate anyway (see Risk 7). `02_Props`' 128 are decorative.
   Target under 150 world-wide.
3. Consider pushing `ClockTime` toward midday for the default. Dusk is beautiful and
   expensive; it is also why every screenshot of the campus reads as murky.

**Win.** Removing SunRays plus ~300 lights should be worth several ms/frame on mobile —
likely the second-biggest single win after the crowd.

## Risk 5 — 1,704 semi-transparent parts cause overdraw — MEDIUM-HIGH

**Measurement.** 1,704 parts have `Transparency` strictly between 0 and 1. With 1,347
Glass-material and 1,950 Neon parts in the build, and the arrival facade being a wall of
glass panels (`shots/01`, `shots/05`), many of these overlap in depth.

**Why it hurts.** Transparent surfaces cannot be depth-culled against each other. The
mobile GPU shades every layer. A glass facade 6 panels deep means 6x the fragment work
for that part of the screen.

**Fix.** Audit the glass curtain walls in `04_Lobby`, `09_PerformanceCenter` and
`17_ArrivalPress`. Where a facade is multiple parallel transparent panes, collapse it to
one. Replace interior glass the player never sees through with opaque.

**Win.** Hard to quantify without a device profile, but facade-heavy views are where the
frame rate will be worst, and these views are at spawn.

---

# Will hurt LATER

## Risk 6 — ServerStorage is 73% of the saved file — MEDIUM

**Measurement.** ServerStorage holds **170,776 instances** against the world's 63,884.
`PartnerOriginals` = 107,831 (of which `Field_5v5__Crowd` alone is **97,287**).
`AW_Archive` = 58,847 (of which `Simplify_2026-10-30` is **54,426**).

**Why it is "later" and not "now".** ServerStorage does not replicate to clients, so it
costs players nothing at runtime. But it costs **server RAM on every server instance**,
it costs save/publish time, and it makes the .rbxl slow to open — which is a tax on every
future editing session. It also means a single accidental drag into Workspace adds
100,000 instances.

**Fix.** Export `PartnerOriginals` and `AW_Archive` to .rbxm files on disk, keep them in
version control or a backup folder, then remove them from the place. Do **not** delete
without exporting first — `PartnerOriginals` is the partner's original work and
`Simplify_2026-10-30` is the only record of what the October strip-down removed.

**Win.** ~170,000 instances out of the file. Faster opens, smaller publishes, lower
server memory floor.

## Risk 7 — `03_TrenchShell`: 1,754 parts and 138 lights around a lobby — MEDIUM

**Measurement.** 1,754 parts, 639 colliding, **138 lights**, spanning 570 x 114 x 740
studs centred on the origin — directly over the spawn. It contains **530 of the world's
554 parts whose top surface is above Y=90**; it is the only tall structure left standing.

**Why it matters.** It is a large enclosing shell wrapped around the lobby area that the
player loads into, and it is the densest light cluster in the build. Whatever its
original purpose, the owner's stated direction is to strip the campus to three venues
and focus on mechanics — a 1,754-part architectural shell around a lobby is not that.

**Fix.** Decide whether the lobby survives the strip-down at all (see cleanup-plan.md
step 6). If it does not, this folder goes with it.

**Win.** −1,984 instances, −138 lights, and the spawn area stops being the heaviest
place in the world.

## Risk 8 — 852 Atomic streaming models fragment the streaming budget — MEDIUM

**Measurement.** 2,299 Models: **852 `Atomic`**, 1,447 `Default`. All 2,299 are
`LevelOfDetail = Automatic`. The 852 Atomic models are the crowd Fans.

**Why it matters.** `Atomic` means the model streams in or out as one indivisible unit,
and the engine tracks it as a separate streaming region. 852 atomic units for static
decoration is a lot of bookkeeping for the streaming system to do, and it prevents the
engine from partially streaming a stand.

**Fix.** Resolved automatically if Risk 1 is fixed — a billboard crowd is a handful of
parts, not 852 atomic models. If the fans are kept, set them to `Default`.

## Risk 9 — 24 oversized parts defeat culling — LOW-MEDIUM

**Measurement.** 24 parts exceed 100,000 cubic studs. `16_FarGround` is 8 colliding
parts spanning **2,742 x 2,742 studs**. `01_Ground` spans 2,097 x 1,402.

**Why it matters.** A part larger than the streaming radius can never stream out, and it
is always in the camera frustum, so it is always submitted for rendering. For ground
planes this is usually acceptable; for 8 *colliding* parts covering 7.5 million square
studs it also means every downward raycast in the game hits a huge collision primitive.

**Fix.** Leave the ground planes but split `16_FarGround` into a grid if the far ground
is ever given detail. Low priority — the cost is bounded and small.

## Risk 10 — 314 co-located duplicate parts — LOW

**Measurement.** 314 parts share an identical position *and* size with another part.
Concentrated in `Field_5v5.LightTowers` (4 `Truss` parts fully coincident with each
other) and the crowd's `Phone`/`PhoneScreen` pairs.

**Why it matters.** Pure waste: double the geometry, and z-fighting wherever two opaque
faces are coplanar. The light-tower trusses are a real modelling error.

**Fix.** Z-fighting is a visual bug, not just a perf one — fix the 4 `LightTower` trusses
by hand. The phone duplicates vanish with Risk 1.

---

## Recommended order of execution

| # | Action | Instances removed | Effort |
|---|---|---|---|
| 1 | Strip phone assemblies from 852 Fans (Risk 1) | −26,412 | Low — one scripted pass |
| 2 | `CanQuery`/`CanTouch` off for non-colliding decor (Risk 2) | 0 (flags only) | Low — one scripted pass |
| 3 | Disable SunRays; cull lights to <150 (Risk 4) | −~480 lights | Low |
| 4 | Move `AW_Spawn` to the football park (Risk 3) | 0 | Trivial |
| 5 | Export then remove ServerStorage archives (Risk 6) | −~170,000 | Medium — export first |
| 6 | Collapse multi-pane glass facades (Risk 5) | few hundred | Medium — by hand |
| 7 | Resolve `03_TrenchShell` with the lobby decision (Risk 7) | −1,984 | Depends on step 6 of cleanup plan |

Steps 1–4 are roughly a day's work and address every CRITICAL and HIGH risk. They take
the live world from 63,845 to about **37,400 instances** without touching a single thing
the player is meant to look at.
