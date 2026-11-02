# ALLSTAR WORLD — World Build Inventory

Read-only audit, Studio Edit session, 2026-11-02. Nothing in the place was modified.

## Headline numbers

| Measure | Count |
|---|---|
| `Workspace` descendants (all) | 63,884 |
| `Workspace.AllstarWorld` descendants | 63,845 |
| BaseParts (Part 38,059 + WedgePart 424) | **38,483** |
| GUI objects living on parts in 3D space | **22,231** |
| Models | 2,299 |
| Lights (SurfaceLight 269 / SpotLight 214 / PointLight 147) | 630 |
| WeldConstraints | 48 |
| ProximityPrompts | 6 |
| SpecialMesh | 3 |
| ParticleEmitter | 1 |
| **MeshParts** | **0** |
| **Unions / CSG operations** | **0** |
| **Decals / Textures** | **0** |
| **SurfaceAppearance (PBR)** | **0** |
| **Scripts of any kind in Workspace** | **0** |
| `ServerStorage` instances | **170,776** |
| **Total instances in the saved file** | **~234,660** |

Two facts dominate everything below:

1. **The build is 100% primitive parts.** Not one MeshPart, union, decal, texture or
   PBR surface in 63,845 instances. Every object in the world is a Block, Cylinder or
   Ball (29,042 / 4,773 / 4,244) in one of 22 built-in materials and 84 BrickColors.
2. **ServerStorage is 2.7x heavier than the live world.** 170,776 archived instances
   ride along in every save, publish and Studio open.

## Per-folder breakdown (`Workspace.AllstarWorld`)

Sorted by descendant count. `coll` = CanCollide, `qry` = CanQuery, `tch` = CanTouch.

| Folder | Desc | Parts | Models | Lights | coll | qry | tch | GUI | Footprint (studs) |
|---|---|---|---|---|---|---|---|---|---|
| **06_FootballPark** | **32,324** | 10,698 | 922 | 34 | 1,723 | 1,731 | 1,799 | **20,639** | 1216 x 81 x 439 @(-242,40,-413) |
| **02_Props** | **12,958** | 12,441 | 244 | 128 | 1,432 | **11,321** | **11,385** | 108 | 1455 x 35 x 1621 @(-129,17,-165) |
| 16_Landscape | 2,768 | 2,067 | 689 | 0 | 689 | 689 | 689 | 0 | 1573 x 26 x 1415 @(-80,19,2) |
| 09_PerformanceCenter | 2,323 | 2,156 | 106 | 12 | 1,011 | 1,011 | 1,011 | 32 | 228 x 60 x 313 @(-382,29,-437) |
| 43_GrandStadium | 2,307 | 2,139 | 0 | 58 | 257 | 257 | 0 | 96 | 363 x 102 x 446 @(-741,48,-80) |
| WasteStations | 2,139 | 1,457 | 93 | 0 | 62 | 1,457 | 1,457 | 589 | 626 x 5 x 1150 @(-32,2,-47) |
| 03_TrenchShell | 1,984 | 1,754 | 0 | 138 | 639 | 639 | 639 | 84 | 570 x 114 x 740 @(0,47,86) |
| 05_Arenas | 1,937 | 1,615 | 8 | 105 | 61 | 61 | 61 | 205 | 447 x 60 x 215 @(2,23,-61) |
| 04_Lobby | 920 | 752 | 20 | 16 | 277 | 277 | 277 | 128 | 453 x 61 x 112 @(0,23,113) |
| 17_ArrivalPress | 863 | 744 | 54 | 52 | 2 | 2 | 2 | 12 | 89 x 13 x 113 @(0,0,248) |
| 19_PracticeField *(Model)* | 664 | 608 | 2 | 6 | 371 | 382 | 386 | 42 | 125 x 61 x 173 @(432,30,-465) |
| 18_BasketballCourts | 599 | 568 | 3 | 5 | 155 | 166 | 2 | 20 | 406 x 38 x 435 @(-356,17,96) |
| 17b_ArrivalFans | 575 | 424 | 50 | 0 | 0 | 0 | 0 | 100 | 93 x 6 x 112 @(0,3,246) |
| 10_FieldHouse | 474 | 377 | 25 | 9 | 65 | 275 | 275 | 60 | 258 x 20 x 564 @(390,10,-540) |
| 08_SitePlan | 385 | 222 | 64 | 16 | 65 | 65 | 65 | 82 | 585 x 22 x 714 @(0,11,168) |
| 01_Ground | 231 | 230 | 0 | 0 | 45 | 45 | 45 | 0 | 2097 x 88 x 1402 @(466,41,16) |
| 07_Doors | 175 | 78 | 18 | 0 | 12 | 12 | 12 | 24 | 460 x 19 x 346 @(0,3,0) |
| 11_ShowcaseStadium | 129 | 103 | 0 | 14 | 21 | 21 | 21 | 10 | 175 x 41 x 301 @(0,37,-430) |
| 15_LobbyFill | 75 | 37 | 0 | 37 | 0 | 0 | 0 | 0 | 411 x 0 x 91 @(-5,9,117) |
| 16_FarGround | 9 | 8 | 0 | 0 | 8 | 0 | 0 | 0 | 2742 x 0 x 2742 @(0,-2,0) |
| 15_ZoneFloors | 6 | 5 | 0 | 0 | 4 | 4 | 4 | 0 | 306 x 0 x 114 @(0,-6,-5) |
| **TOTAL** | **63,845** | **38,483** | 2,299 | 630 | 6,899 | 18,415 | 18,130 | 22,231 | |

## The worst individual offenders

### 1. `06_FootballPark.Field_5v5.Crowd` — 29,777 instances, 47% of the entire world

One folder holds nearly half the build. It is a decorative crowd: **852 `Fan` models**
across `WestStand` (420) and `EastStand`, and nothing else.

Each `Fan` is **31 instances**:

| Per fan | Count |
|---|---|
| Part | 7 (body blocks + `Phone` + `PhoneScreen`) |
| SurfaceGui | 1 (on the phone screen, `PixelsPerStud` 50, `MaxDistance` 110) |
| Frame | 12 |
| UICorner | 10 |
| UIStroke | 1 |

852 fans x 31 = **26,412 instances** for static spectators who do not move, and
**852 live SurfaceGui render surfaces** each rendering a 12-Frame, 10-UICorner phone
screen. This single decoration costs more than every other folder in the place combined.

It is also where the build's GUI mass comes from: of the world's 22,231 GUI objects,
**20,458 (92%) are inside this one crowd**.

### 2. `02_Props` — 12,441 parts with collision/query flags wrong

12,441 parts, of which only 1,432 collide — but **11,321 have `CanQuery` on and 11,385
have `CanTouch` on**. ~11,000 decorative props are sitting in the physics broadphase
and in every raycast the game will ever fire, for no gameplay reason.

### 3. `Field_5v5` structure — 284 loose children, flat and unsorted

The main field Model has 284 direct children, almost all loose Parts dumped at the top
level: ~140 `FencePost`, ~90 `Marking`, 11 `Turf`, plus `GoalPost`, `Scoreboard`,
`LOS_North/South`, `CameraAnchor`, `SpectatorAnchor`. Only `Crowd`, `LightTowers`,
`YardNumbers` and the two `Bleachers_*` are grouped. There is no sub-folder for
markings, fencing or furniture.

### 4. `WasteStations` — 1,457 parts, 1,457 CanQuery, 62 CanCollide

2,139 instances and 589 GUI objects of bins spread over a 626 x 1150 stud area. 4% of
its parts collide; 100% are query-traceable.

### 5. `01_Ground` / `16_FarGround` — 24 parts over 100,000 studs³

24 parts in the world exceed 100,000 cubic studs. `16_FarGround` is 8 colliding parts
spanning 2742 x 2742 studs. Parts this size never stream out and defeat frustum culling.

### 6. 314 co-located duplicate parts

314 parts share an identical position *and* size with another part — true overlapping
geometry. Concentrated in `Field_5v5.LightTowers` (4 x `Truss` fully co-incident) and in
the crowd's `Phone`/`PhoneScreen` pairs, which occupy the same space as each other.

## ServerStorage — 170,776 instances

| Folder | Desc | Parts | GUI | Models | What it is |
|---|---|---|---|---|---|
| **PartnerOriginals** | **107,831** | 26,293 | 80,545 | 876 | Pre-simplification originals. `Field_5v5__Crowd` alone is **97,287** — the uncompressed crowd before it was cut to 29,777. Also light towers and bleachers for fields `1v1-a/b/c/d`, `2v2-e/w`, `5v5` that no longer exist in the world. |
| **AW_Archive** | **58,847** | 22,914 | 35,048 | 740 | The strip-down spoil heap. `Simplify_2026-10-30` = **54,426** (93% of it). Plus the three removed indoor basketball halls, the indoor centre court, `Courts_preReno2026`, `Outdoor_Park_backlot_2026-10-30`, `FootballMove_2026-10-30`, a stray `WorldBoundary` Part, and the only three gameplay scripts anywhere in the file (`Hoops3Service_halfcourt`, `Hoops3Client_halfcourt`, `TouchMoves_v1`). |
| Cars_Backup | 3,343 | 3,119 | 0 | 223 | 223 car models |
| CarTemplates | 228 | 223 | 0 | 5 | 5 source cars: Regent, Pulse, Brute, Summit, Strike |
| YardNumbers_Backup | 165 | 54 | 108 | 0 | Yard numbers for 5v5, 2v2-e, 2v2-w |
| ParkingLights_Backup | 160 | 160 | 0 | 0 | 160 loose lamp parts, no grouping |
| DumbbellRacks_Backup | 76 | 72 | 0 | 0 | 4 racks |
| Lights_Backup | 70 | 48 | 0 | 0 | Lights for 6 deleted fields |
| Bleachers_Backup | 43 | 39 | 0 | 0 | Stands for 5v5, 2v2-e, 2v2-w |
| AWBuild | 3 | 0 | 0 | 0 | `Lib`, `CourtKit`, `GrandStadium` ModuleScripts |

`AWBuild` is the only ServerStorage folder with current value. The other nine are
history. Note `Cars_Backup` (3,343) duplicates work already covered by `CarTemplates`
(228) — 223 instanced copies kept alongside the 5 sources they came from.

## Strays and naming

- **Two `Accessory (Cristiano Ronaldo)` at Workspace top level.** One is an empty husk
  (3 descendants: thumbnail config only, no Handle). The other has a real `Handle` Part
  with a live `TouchInterest` and a `SpecialMesh`. Both are catalogue-accessory debris
  with nothing to do with the game.
- **`AW_Spawn` is stranded.** At (0, 0.29, 428.57), it is 668–1,175 studs from every
  playable area (see performance.md).
- **Naming is inconsistent in three different styles.** Numbered-prefix folders
  (`06_FootballPark`), auto-generated sequence folders (`03_TrenchShell_1`..`_8`,
  `16_Landscape_1`..`_12`, `05_Arenas_1`..`_4`) which carry no meaning at all, and
  hand-named content (`Field_5v5`, `Outdoor_Park`). Two numbers are skipped entirely
  (12, 13, 14) and `15_` appears twice (`15_LobbyFill`, `15_ZoneFloors`) while
  `17_`/`17b_` and `19_`/`43_` break the sequence. `19_PracticeField` is a Model where
  every sibling is a Folder.
- **`06_FootballPark_4` is an empty Folder** (0 descendants).
- Signs are named with their label text including punctuation and spaces:
  `Sign_SOCCER 1v1 · 2v2  ▲`, `Sign_WALK-ON · 5v5`.

## Migration attributes — what they actually left behind

`Workspace.AllstarWorld` carries seven attributes recording past jobs. All seven read as
done, but one left visible damage:

| Attribute | Value | State |
|---|---|---|
| `AWGrandStadiumCleared` | `v2` | Complete — stadium bowl and pitch are intact |
| `AWCourtsPropsMoved` | true | Complete |
| `AWParkWestLotMoved` | true | **Incomplete — see below** |
| `AWReno2026ParkMoved` | true | Complete |
| `AWReno2026BlockMoved` | true | Complete — no skyline geometry found |
| `AWSoccerLotMoved` | true | **Incomplete — see below** |
| `AWParkPropsMoved` | true | Complete |

**The interrupted job.** The car-park *pavement* was moved out, but the **stall striping
and the cars were not**. In the area x[-540,-290] z[-10,260] the only large surfaces left
are `01_Ground_1/Driveway` (Asphalt), `01_Ground_1/Grass` (Grass), `Outdoor_Park/Path`
and `CourtsPlaza/Promenade` (Pavement). The result is ~100 white parking-stall lines and
roughly 30 cars sitting directly on a grass field, lit by parking lights, with no asphalt
beneath them. This is clearly visible from the west side of the campus
(`shots/03`, `shots/04`, `shots/05`).
