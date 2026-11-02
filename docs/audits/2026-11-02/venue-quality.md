# ALLSTAR WORLD — Venue build-quality audit (2026-11-02)

Read-only. 18 areas scored, 38 defects logged, dimensions measured against regulation for all four sports.
Scale convention: **1 stud = 0.35 m (2.857 studs/m)**.

## SCORECARD

| Area | /10 | Verdict | Worst defect |
|---|---|---|---|
| 06_FootballPark / Field_5v5 | **7** | Hero venue; only area that clears the bar — real mow-striped grass, correct yardage, team-coloured crowd | Light towers are props: zero illumination, field sits near-dark |
| 18_BasketballCourts | **7** | Best-composed area; genuinely reads 2K park | Court surface is SmoothPlastic — glossy flat plastic, the signature slop tell |
| 03_TrenchShell | **6** | Strong glass-and-fin architecture, correctly brick-free | Purple `Ambient` tints every neutral mauve instead of charcoal/off-white |
| 04_Lobby | **6** | Good two-storey mezzanine and curtain wall | Floor and mullions read lavender; black unlit ceiling; west glass passes no sunset light |
| 02_Props | **5** | Competent parking/street dressing | 9,358 parts of parked cars; `02_Props_2` is an empty orphan folder |
| 09_PerformanceCenter | **5** | Material mix (Rubber 512, Carpet 240, Glass 216) reads like a real gym | 127 parts named `Part`; no point lights at all, 12 SurfaceLights for 2,156 parts |
| 01_Ground | **5** | Does its job | 0.17-stud lip where campus ground meets `16_FarGround` — hairline ring seam around the map |
| 19_PracticeField | **4** | Correct markings on the wrong grass | Mow stripes are literally `255,255,255` on pale yellow-green — a far worse palette than the hero field |
| 43_GrandStadium | **4** | A rectangular crate with a flat roof ring, not a bowl | Full-width black unlit void band across the facade reads as a hole in the building |
| 05_Arenas | **3** | Underground arena complex the strip-down was supposed to remove | Duplicate football field and soccer pitch still standing at Y ≈ −6.7 |
| 17_ArrivalPress + 17b_ArrivalFans | **3** | Two separate crowds in the same 90×115-stud footprint | 104 blocky dummies interpenetrating on the spawn-to-lobby walk |
| 08_SitePlan (+ spawn plaza) | **3** | Good wayfinding, wrong thing underfoot | Orange zero-thickness crosshair marker painted on the plaza directly under spawn |
| 10_FieldHouse | **3** | Concrete slab, dark Slate floor, 142×320-stud empty "CourtsReserve" lot | Placeholder reserve lot still standing as finished-looking ground |
| 16_Landscape / 16_FarGround | **3** | Eight flat dark-olive plates to the horizon, no silhouette | Campus edge reads as a green void; tile folders unevenly populated (129/147/171 vs 180) |
| 15_ZoneFloors / 15_LobbyFill | **3** | Half-finished migration left visible | 37 `LobbyFillEmitter` placeholder plates floating at y=9.1; crowd fill never generated |
| 11_ShowcaseStadium | **1** | Two canopies on stilts over empty grass — no floor, pitch or seats | Entire structure floats: lowest part bottoms out at y=15.6, columns end in mid-air |
| 07_Doors | **1** | Six doors, 48 unanchored parts, zero scripts | Every door collapses the instant physics runs, and none open |

---

## GLOBAL DEFECTS — these hurt every venue at once

**1. The campus is too dark to read as premium.** `ClockTime = 17.700` puts `SunDirection.Y` at **+0.074** —
the sun is 4.2° above the horizon, almost due west. Geometrically golden hour; in practice everything is
self-shadowed and the golden hour survives only as a thin orange band on the skyline. Fields, plazas and grass
render near-black. *Fix: raise ClockTime to ~16.4–17.0 (sun 10–15° up), lift `ExposureCompensation` from
−0.15 toward 0.* **QUICK WIN**

**2. Purple ambient is tinting the whole build mauve.** `Ambient = 0.314, 0.290, 0.337` and
`OutdoorAmbient = 0.588, 0.471, 0.588` are both purple-weighted; `ColorShift_Bottom = 0.431, 0.353, 0.549` is
violet. Every neutral — plaza concrete, lobby marble, Trench mullions, Grand Stadium fins — renders
lavender-pink. The brief says **charcoal and off-white**; the build renders pink. **The single largest gap
between intent and result.** *Fix: neutralise OutdoorAmbient toward warm grey, drop Ambient to ~0.12 so
interiors are lit by fixtures.* **QUICK WIN**

**3. Zero textures and zero decals in 63,866 objects.** `Texture = 0`, `Decal = 0`. Every surface is flat
material colour. This is why yard numbers are grey plastic rectangles and the court reads as plastic.

**4. The natural-grass MaterialVariants were authored and never connected.** `MaterialService` holds
`AW_NaturalGrass`, `AW_GrassPaint`, `AW_PitchGrass` (four copies of each). Applied: **`AW_PitchGrass` on 12
parts, `AW_PitchGrass2` on 1 — `AW_NaturalGrass` and `AW_GrassPaint` on zero.** 2,013 Grass parts, 13 use a
variant. The "real natural grass" work exists but is unplugged. **QUICK WIN**

**5. SmoothPlastic is 60% of the build** (19,130 of ~31,900 parts). With no textures, this is the mechanical
cause of the slop read.

**6. 1,147 parts still named `Part`** — 540 in `06_FootballPark`, 185 in `01_Ground`, 127 in
`09_PerformanceCenter`, 120 in `04_Lobby`.

---

## KEY AREA DEFECTS

### 07_Doors — worst functional defect
- **All six doors unanchored with no mechanism.** Each has 13 parts, 8 unanchored; `AllstarWorld` contains
  **0 scripts**. On the first physics step every panel falls. These are also the only unanchored parts in the
  static build. **QUICK WIN (anchoring half)**
- `Door_MAIN_ENTRANCE.PanelA/B.Glass` run y = −6.7 to +11.5 — an 18-stud slab, over 3× character height.

### Spawn and arrival
- **`AW_Spawn` (0, 0.29, 428.57) is 315 studs from the lobby and 635–1,157 from every playable surface.**
  Basketball 635, Showcase 873, Grand Stadium 908, practice field 995, football park **1,157**. ~40 seconds of
  empty walking at default walkspeed before anything is touchable.
- **Construction markers at the player's feet** — `08_SitePlan_1.Part` ×2, zero-thickness, 0.1 studs from
  spawn, rendering as a bright orange crosshair. **QUICK WIN: delete**
- **Facade billboards contradict an explicit decision.** Brief is "no facade billboards — only subtle blue
  LED", but `Sign_ALLSTAR WORLD`, `Sign_WIDE WORLD TRENCH` and a third strip sit stacked on the main facade.
  The LED edge lighting elsewhere is correct. **QUICK WIN: remove the three panels, keep the LED**
- **`17_ArrivalPress` and `17b_ArrivalFans` occupy the same footprint** (X ±45/±47, Z 190–305). 744 + 424
  parts, 54 press figures and 50 fans interpenetrating on the spawn-to-lobby walk.

### 11_ShowcaseStadium — remove or finish
103 parts; lowest part `CanopyColumn` at **minY = 15.6** — support columns terminate 15 studs in the air.
No floor, no pitch, no seating; 52 of 103 parts are Neon. Its own sign reads `Sign_OPENS IN MILESTONE 06`.

### 19_PracticeField
- **Mow stripes are pure white** (`255,255,255`, Material Grass) alternating with `176,204,158` on an apron of
  `190,205,165`. The hero field does this correctly with `53,128,55` / `58,138,60`. **QUICK WIN: copy the
  Field_5v5 palette**
- **Line markings use `Material = Grass` with white colour** — a grass normal map on a paint line gives fuzzy
  noisy edges. **QUICK WIN: switch `Lines` to SmoothPlastic**
- **Lines are exactly coplanar with stripes** — stripe tops y = 0.25, line bottoms land at exactly 0.25.
  Z-fighting at distance. **QUICK WIN: raise lines to y = 0.29**
- Yard numbers are grey plastic rectangles (`163,162,165`); no 50, no 5-yard intermediates.
- **Light towers and floodlights emit nothing** — 2 PointLights and 4 SpotLights for 608 parts. Same on
  Field_5v5: 1,024 parts of `LightTowers`, 4 PointLights and 30 SpotLights for the whole park.

### 43_GrandStadium
- **A rectangle, not a bowl.** `RoofFacade` is four straight slabs meeting at square corners. No curvature, no
  corner infill, no rake variation. *Chamfering the four corners is the highest-value change to its silhouette.*
- **Full-width black void band across the facade**; base disappears into darkness with no plinth.
- Pitch undersized (see DIMENSIONS); no corner flags; centre/penalty spots ~2× too large. **QUICK WIN**
- Pitch is 16 separate CanCollide strips at 16.07 studs with no overlap — seams every 16 studs.

### 18_BasketballCourts
- **Hoop assembly mounted ~1.46 studs too low.** The backboard is internally correct (3.82 × 6.54 studs =
  1.09 × 1.87 m vs regulation 1.05 × 1.80) and the rim sits 0.53 studs above the backboard bottom, matching the
  real 0.15 m. But the assembly is placed with the rim at **y = 9.21** where the court's own scale needs
  **10.68** — 2.63 m instead of 3.05 m. **Dunking will feel wrong.**
- **Apron wordmark is mirrored** — renders "ALLSTAR PARK · COURT 2" backwards. **QUICK WIN: rotate 180° about Y**
- **Signage references courts that don't exist** — one `Court_` object in the whole place. **QUICK WIN**
- `CourtSurface` and `Apron` are SmoothPlastic — a 98 × 52 stud glossy plastic sheet. Colours are good;
  material is the problem.
- **210 zero-thickness `Arc` parts** plus Lane/Baseline/Sideline/HalfCourt/FreeThrowLine at 0.01 studs. This
  court holds the bulk of the build's **623 degenerate parts**.
- Backboards are Glass at 0.09 studs — too thin to catch light, so the dark frame dominates.

### 05_Arenas — should not be standing
A four-bay underground complex survives at Y ≈ −6.9 to −6.7: `05_Arenas_1` hockey rink (`DasherBand`,
`DasherGlass`), `05_Arenas_3` indoor football field (`Turf`, `EndZoneSouth`, yard signs), `05_Arenas_4` indoor
soccer pitch (`GoalPost`, `Sign_SOCCER`). **Visible from the lobby through the curtain wall** — not hidden.
1,615 parts, 1,295 Metal, against a charcoal-and-glass brief.

### Hygiene
- Migration attributes all read `true` and the outdoor moves did complete — no skyline remains. But
  `AWGrandStadiumCleared` did not clear the duplicate venues in `05_Arenas`, and `15_LobbyFill` (37 placeholder
  emitters) and the unapplied grass variants are migrations that stopped halfway.
- Two stray `Accessory (Cristiano Ronaldo)` at the top of Workspace. **QUICK WIN: delete**
- `02_Props.02_Props_2` is an empty folder. **QUICK WIN**
- `16_Landscape` tiles unevenly populated — ten at 180 parts, but `_2` = 129, `_3` = 147, `_12` = 171.
- 0.17-stud lip at the world edge: `16_FarGround` tops at y = 0.00, campus ground at y = 0.17. **QUICK WIN**
- 31 `WasteStation` models at ~47 parts each (1,457 parts) — more detail in bins than in the Showcase
  Stadium (103 parts).
- 1,875 large parts at fractional X/Z. **Not sloppiness** — it falls out of the metric conversion (85.71,
  171.43, 264.6 studs). Pieces will never tile cleanly on a stud grid; design around it.

---

## DIMENSIONS

### American football — `Field_5v5` (hero field)
| Measure | Built | At 0.35 m/stud | Regulation | Verdict |
|---|---|---|---|---|
| Playing width | 105 studs | 36.8 m / 40 yd | 48.8 m / 53.3 yd | Narrow, acceptable for 5v5 |
| Playing length | 220 studs | 77 m / 84 yd | 91.4 m / 100 yd | Short, acceptable for 5v5 |
| Endzone depth | 15 studs | 5.25 m / 5.7 yd | 9.14 m / 10 yd | **42% short** |
| Mow stripe | 22 studs | 7.7 m | 5–8 m typical | Correct |

### American football — `19_PracticeField`
Internally consistent at **3.2 studs/yard**, i.e. a 50-yard half-field — but that **does not match the
2.61 studs/yd** that 0.35 m/stud requires, so it is ~22% oversized in its own units. Width is exactly half
regulation. Yard line width 0.29 studs = 0.10 m is **correct**. Yard lines 5–45 only; no 50, no intermediates.

### Soccer — `43_GrandStadium`
| Measure | Built | At 0.35 m/stud | Regulation | Verdict |
|---|---|---|---|---|
| Marked touchline | 228.57 studs | 80 m | 100–105 m | **Short** |
| Marked width | ~157 studs | ~55 m | 64–68 m | **Narrow** |
| Goal width | 20.91 studs | **7.32 m** | 7.32 m | **Exact** |
| Goal height | 6.97 studs | **2.44 m** | 2.44 m | **Exact** |
| Line width | 0.34 studs | 0.12 m | 0.12 m | **Exact** |
| Centre / penalty spot | 1.14 studs | 0.40 m | ~0.22 m | ~2× too large |

Goals and line widths are exactly right at 0.35 m/stud — **the pitch was simply drawn too small around them.**
Below the FIFA international minimum of 64 × 100 m.

### Basketball — `Court_bb-2`
Aspect ratio 1.876 vs regulation 1.867 — **proportionally correct**. Free-throw distance, lane width, corner
three and arc radius all good. But implied scale is **0.2857 m/stud (3.5 studs/m)** against the project's
0.35 — **22.5% oversized**. The rim is the one piece placed using the *other* convention, which is why it alone
is too low (2.63 m vs 3.05 m).

---

## STRIP-DOWN STATUS

Decision: **one football field, one basketball court, one soccer stadium; focus on mechanics; remove the city
skyline buildings.**

| Asked | Actually standing | Status |
|---|---|---|
| Remove skyline buildings | `Skyline` = 0, `Building` = 0, `Block` = 0 anywhere | **DONE** |
| One basketball court | Exactly one (`Court_bb-2`); signage says "COURT 2"; `CourtsReserve` 142×320 lot held for more | **DONE**, naming + reserve lot left |
| One soccer stadium | **Two**: `43_GrandStadium.Pitch` and `05_Arenas_4` | **NOT DONE** |
| One football field | **Three**: `Field_5v5`, `19_PracticeField`, `05_Arenas_3` | **NOT DONE** |
| *(surplus)* | `05_Arenas_1` full hockey rink | Surplus |
| *(surplus)* | `11_ShowcaseStadium` floating shell, "OPENS IN MILESTONE 06" | Surplus |
| *(surplus)* | `10_FieldHouse.TrainingRoom` (249), `09_PerformanceCenter` (2,323) | Surplus |

The outdoor consolidation happened. What the clear missed is **the underground level at Y ≈ −6.7**. A raycast
at X=0, Z=0 hits `Turf` at y = −6.69, and the lobby curtain wall looks straight out onto it — on display at the
campus centre.

**Net: roughly three football surfaces, two soccer pitches, one hockey rink and two unfinished venue shells,
when the decision called for three venues total.**

---

## FIRST IMPRESSION

Spawn is an 8×8 **Plastic** pad with an orange site-plan crosshair 0.1 studs away. Ahead is a 233-stud
promenade to the facade 315 studs north; every playable surface is 635–1,157 studs further. Roughly **40
seconds of empty walking** before the first touchable thing.

The arrival shot is genuinely the build's best composition — wide glass curtain wall, sweeping elliptical
canopy, palms, cyan-LED signage pylons, real campus scale. Three things undercut it immediately: the **three
prohibited facade billboards**, the **lavender-pink palette** where charcoal was specified, and a **navy sky
with visible stars** instead of golden hour.

Walking in at Z 300–190 the player passes 104 blocky figures from two crowd sets interpenetrating in one
footprint. At the entrance the main door's glass panels are 18 studs tall and unanchored — already collapsed.

The lobby is a good room (two-storey curtain wall, "PICK YOUR GAME", amber runner, mezzanine) but the floor is
mauve, the ceiling unlit black, and the west glass wall passes no light. The view through it is the underground
arena — **the first playing surface a player sees is one the strip-down meant to delete.**

**Verdict: the arrival silhouette and the basketball park clear the bar; the build as a whole does not — and
the reasons are concentrated, not diffuse. Three global settings (clock time, ambient colour, zero textures)
are responsible for most of the gap. Fixing them would lift the whole campus more than any new geometry.**

---

## REUSABLE CHECKLIST — run before any venue ships

Scale convention: **1 stud = 0.35 m (2.857 studs/m)**.

### A. Scale and dimensions
- [ ] Every dimension derived from **0.35 m/stud**; state the venue's stud/metre figure in its GDD section.
- [ ] One scale per venue. *Check: measure one floor feature and one mounted fixture; they must agree.*
- [ ] Football: field 100 yd ≈ 261 studs; width 53.3 yd ≈ 139 studs; **endzone 10 yd = 26 studs**; yard line
      0.29 studs; numerals every 10 yards both sides, mirrored on the far half.
- [ ] Soccer: pitch 105 × 68 m = 300 × 194 studs (never below 286 × 183); goal 20.91 × 6.97 studs; line width
      0.34 studs; spots ~0.63 studs; **four corner flags**.
- [ ] Basketball: 28 × 15 m = 80 × 43 studs; **rim at 3.05 m = 8.71 studs**; backboard 3.00 × 5.14 studs;
      arc 20.7 studs; corner three 2.57 studs from sideline.
- [ ] Sanity-check against a 5-stud character: drop a reference block and screenshot it on the surface.

### B. Playing surfaces
- [ ] Grass uses `Material = Grass` **and** carries the `AW_NaturalGrass` / `AW_PitchGrass` MaterialVariant.
      *Verify by reading `part.MaterialVariant`, not MaterialService — a variant can exist and be applied to nothing.*
- [ ] No SmoothPlastic on any playing surface. Court = Asphalt or Concrete + variant.
- [ ] Mow stripes are **two greens** within ~10 RGB points. No white, grey or yellow-green.
      Reference: `53,128,55` / `58,138,60`.
- [ ] No part named `Turf` on an outdoor natural-grass venue.
- [ ] Line markings are SmoothPlastic, **never** Grass with a white colour.
- [ ] Line parts **≥ 0.04 studs thick** — no zero-thickness geometry anywhere.
- [ ] Line bottoms **≥ 0.02 studs above** the surface top. Compute both sides; exactly equal means z-fighting.
- [ ] Numerals and wordmarks are **decals**, not coloured rectangles.
- [ ] Every text surface checked for mirroring from the player's normal approach.
- [ ] Surface built as one part where possible; if striped, no seam gaps, decorative strips `CanCollide = false`
      with one collision slab beneath.

### C. Lighting
- [ ] `ClockTime` lands the sun **10–15° above horizon**: `Lighting:GetSunDirection().Y` between **0.17 and
      0.26**. Below 0.10 the campus goes black.
- [ ] `Ambient` ≤ 0.15 and colour-neutral.
- [ ] `OutdoorAmbient` carries **no purple**: B must not exceed R.
- [ ] Charcoal and off-white surfaces screenshot as charcoal and off-white, not mauve.
- [ ] Every light tower, floodlight and mast **emits**: count SpotLight/PointLight per venue, not geometry.
- [ ] No unlit interior ceilings or black void bands on facades.
- [ ] Glass walls facing the sun pass light into the room — verify with an interior screenshot.

### D. Geometry and craft
- [ ] **Zero unanchored parts.** Query `not part.Anchored` and require 0.
- [ ] No part with any dimension < 0.02 studs.
- [ ] No large part floating unsupported unless deliberately cantilevered; every support column reaches grade
      *(raycast down from each column's bottom face)*.
- [ ] No structure crossing the ground plane unintentionally; confirm which level each piece belongs to.
- [ ] Adjacent ground plates meet within 0.02 studs — no lips or ring seams.
- [ ] Buildings have a visible plinth; nothing meets the ground in darkness.
- [ ] Stadium bowls chamfered or curved at the corners — a four-slab rectangle reads as a crate.
- [ ] Repeated props vary in scale or rotation; no grid of identical copies.

### E. Collision and containment
- [ ] Decorative parts (lines, crowd figures, fascia, LED strips) are `CanCollide = false`.
- [ ] Walkable surfaces `CanCollide = true` and continuous; no gaps to drop through.
- [ ] Doors and gates anchored **and** with a working mechanism, or clearly sealed.
- [ ] Walk the perimeter: no escape routes, no invisible walls where geometry should read solid.

### F. Hygiene and naming
- [ ] **Zero parts named `Part`, `Union`, `MeshPart`, `Part1`.** Blocking.
- [ ] Model and folder names match what is standing — no signage pointing at deleted venues.
- [ ] No empty folders.
- [ ] No placeholder emitters, markers or site-plan guides in the shipping build.
- [ ] No test assets at the root of Workspace.
- [ ] MaterialVariant library has no numbered duplicates (`X`, `X1`, `X2`, `X3`).
- [ ] If a migration attribute is `true`, re-verify it completed — **including below ground**. Attributes record
      intent, not outcome.
- [ ] Every venue appears exactly once. Count surfaces by sport across the whole place, not per folder.

### G. First-impression check (from spawn, every time)
- [ ] Spawn within ~150 studs of something playable or interactive.
- [ ] Screenshot from spawn at eye height: nothing placeholder, degenerate or mis-coloured in frame.
- [ ] Walk spawn → venue, screenshot every ~100 studs. No empty stretches, no crowd interpenetration, no
      collapsed doors.
- [ ] Facade carries **only subtle blue LED** — no billboards.
- [ ] A still from the main approach would pass as a FIFA/2K/Madden environment screenshot. If not, name the one
      thing that gives it away and fix that first.
