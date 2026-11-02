# ALLSTAR WORLD — Visual Assessment

Eight screenshots taken read-only from the Edit camera, saved under
`/home/claude/audit/world/shots/`. Assessed against the owner's stated bar: FIFA/EA FC,
Madden, NBA 2K, **real natural grass, no fake turf, nothing that looks like default
"Roblox slop"**.

## The one measurement that frames everything

In 63,845 instances there are:

- **0 MeshParts**
- **0 Unions or CSG operations**
- **0 Decals or Textures**
- **0 SurfaceAppearance (PBR) objects**

Every single object in this world is a Roblox primitive — 29,042 Blocks, 4,773 Cylinders,
4,244 Balls — in one of 22 built-in materials and 84 BrickColors. There is no custom art
in the build at all.

That is the technical definition of the thing the owner said he did not want. Whether it
*reads* as slop is a separate question, and the honest answer is more interesting than
the measurement suggests.

---

## Shot by shot

### `01-spawn-arrival-plaza.jpg` — spawn, looking at the arrival facade

A glass curtain-wall facade with a cyan LED trim line, a paved plaza, street trees,
lamp standards, a parking lot with varied cars, dusk sky behind.

**This does not read as slop.** The glazing module is consistent, the mullion spacing is
regular, the LED trim is a deliberate accent, and the composition has real depth. It
reads like competent architectural massing.

What gives it away on close inspection: the palm trees are three flat green wedges on a
brown cylinder, the planters are untextured grey slabs, and the whole scene is in the
heavy purple-grey cast that `ClockTime 17.7` plus the `AW_Grade` colour correction puts
over everything. **The composition is good; the surfaces are bare.**

### `02-football-field5v5-crowd.jpg` — the main 5v5 field

The strongest "it's a real game" shot in the build. Full gridiron with yard numbers at
every ten, hash marks down both sides, a coloured end zone reading `SHOWCASE`, a
goalpost, two full bleacher stands packed with fans, and a large stadium structure with
a video board behind the north end.

**This clears the bar at a distance.** A screenshot of this on a phone would not
immediately read as a default Roblox build.

Three problems up close:

1. **The playing surface is flat.** The field is one uniform green with no mowing
   stripes, no wear, no variation — compare it directly against `06` and `08`, both of
   which *do* have stripes. The main field is the one that needed them most.
2. **The crowd reads as coloured blocks.** At this distance it works as a texture; from
   the sideline it will not. This is the 29,777-instance crowd — the most expensive thing
   in the build is also the thing least able to survive a close look.
3. **The ground just ends.** A hard black void on the right where `01_Ground` stops. The
   field sits near the western edge of the ground plane with nothing beyond it.

### `03`, `04`, `05` — the parking lot on grass (**a visible bug**)

Three angles on the same broken migration. Roughly 100 white parking-stall stripes and
about 30 cars sit **directly on an open grass field**. There is no asphalt. Parking
lights illuminate green lawn. The stall lines float on turf.

This is the `AWParkWestLotMoved` / `AWSoccerLotMoved` job that ran halfway: the pavement
was moved out, the striping and cars were not. It is the most obviously wrong thing in
the world and it is directly beside the west gate, i.e. on the path a player walks.

**Fix before anything cosmetic.** See cleanup-plan.md step 2.

### `06-grandstadium-soccer-pitch.jpg` — `43_GrandStadium`

**The best asset in the build, by a clear margin.**

A full soccer bowl: three tiers of seating in blue, yellow and white bands, a continuous
LED ring, a yellow big screen, floodlight towers at the corners, and — importantly — a
pitch with **proper alternating mowing stripes**, a centre circle, a halfway line,
penalty areas and goals. The pitch measures 143 x 241 studs, which is correct
proportionally for a football pitch.

This is the one place where the build genuinely hits the FIFA/EA FC reference. Someone
knew what they were doing here.

Two gaps: the stands are empty (banded coloured parts, no crowd), and the bowl is sunk
into a vast flat lavender-grey slab with no exterior treatment and no landscaping — from
outside it is a hole in a car park. The interior is finished; the exterior is not.

### `07-outdoor-basketball-court.jpg` — `18_BasketballCourts.Outdoor_Park`

A single full outdoor court: dark green surface with orange keys, crisp white line work
(three-point arc, keys, centre circle, halfway), two hoops with backboards on proper
cantilever stanchions, bleachers in green and gold, perimeter fencing, floodlights, a
big board, a DJ stage, and an `ALLSTAR PARK` sign.

**This is exactly what the owner asked for** — basketball outdoors, as one park, not an
indoor hall. The line work is accurate and the park furniture gives it character. It
reads as a real streetball court.

The court surface is flat SmoothPlastic with no texture, and the whole scene is dim
because of the dusk clock.

### `08-practice-field-second-gridiron.jpg` — `19_PracticeField`

A **second complete football field**, 997 studs from spawn on the far east side. Full
gridiron, yard numbers, `ALLSTAR` end zone, goalpost, two light towers, access roads and
tree lines.

And — notably — **it has mowing stripes that the main 5v5 field lacks.** Visually this is
the better-turfed of the two football fields.

It is also the clearest contradiction of "one football field". It sits almost unlit at
this hour, which is how a second field 1,600 studs from the first ends up being
forgotten. See cleanup-plan.md step 6.

---

## Verdict against the "not Roblox slop" bar

**Partial pass, and better than the instance data predicts.**

Where it passes:

- The **soccer stadium** (`06`) genuinely clears the bar. Striped pitch, tiered banded
  seating, LED ring — this is stadium design, not block-stacking.
- The **basketball park** (`07`) clears it. Accurate court markings and real park
  furniture.
- The **arrival facade** (`01`) clears it architecturally. Consistent glazing module,
  deliberate LED accent, proper massing.
- The **5v5 field** (`02`) clears it at distance on the strength of its markings, stands
  and scoreboard.

Where it fails:

1. **Zero textures, zero meshes, zero PBR.** Every surface in the world is a flat
   built-in material. This is the ceiling on everything else. Madden and 2K reference
   points are about *surface* — grass blade detail, jersey cloth, court sheen, crowd
   faces — and the build has no mechanism for any of it. Not one `SurfaceAppearance`.
2. **The main football field has no mowing stripes** while the soccer pitch and the
   practice field do. The flagship surface is the least finished one.
3. **The grass is wrong where it matters.** "Real natural grass, no fake turf" is not met
   on the 5v5: the playing surfaces use the `Grass` material in saturated default
   BrickColors — `Sea green` (×41), `Slime green` (×13), `Bright green` (×8),
   `Parsley green` (×2). Those are stock Roblox greens. Additionally **240 field lines
   are `Carpet`-material parts**, and one surface is literally named `IndoorTurf` in
   `Fabric` — fake turf, by name, in the build.
4. **The dusk clock is hurting the work.** `ClockTime 17.7` with `Brightness 2`, SunRays,
   Bloom and a purple-tinted colour grade puts a murky lavender cast over every shot.
   The basketball court and practice field are near-black. Good geometry is being hidden
   by the lighting. Raising the clock toward midday would make the build look
   substantially better *and* cost less on mobile — a rare case where the cheap option is
   also the better-looking one.
5. **Decorative detail is primitive where it is seen closest.** Palm fronds are flat
   wedges, trees are spheres on cylinders, and the crowd is blocks with phones.

## Ranked visual fixes

| # | Fix | Why |
|---|---|---|
| 1 | Finish the parking-lot migration (`shots/03-05`) | It is a visible bug on the player's path, not a taste question |
| 2 | Add mowing stripes to the 5v5 field | The technique already exists in this build — copy it from `43_GrandStadium.Pitch` |
| 3 | Raise `ClockTime` toward midday, drop SunRays | Looks better and runs faster; the only free win here |
| 4 | Re-colour playing surfaces off stock BrickColors | `Sea green`/`Slime green` are the single most recognisable Roblox-default tell |
| 5 | Add `SurfaceAppearance` / textures to the four hero surfaces | Pitch, court, 5v5 turf, stadium seating. Four assets would lift the whole build out of the primitive-only category |
| 6 | Finish the stadium exterior | Interior is excellent, exterior is a hole in a slab |
| 7 | Replace the block crowd with textured billboards | Looks better close up *and* removes 26,412 instances |

Item 7 is worth underlining: the single largest performance win in the entire build is
also a visual improvement. The 852-fan block crowd is simultaneously the heaviest and the
least convincing thing in the world.

---

## Screenshot index

| File | Camera | Looking at |
|---|---|---|
| `shots/01-spawn-arrival-plaza.jpg` | (60, 45, 500) | (0, 5, 420) — spawn / arrival facade |
| `shots/02-football-field5v5-crowd.jpg` | (-765, 120, -620) | (-765, 20, -440) — `Field_5v5` |
| `shots/03-parking-on-grass-overview.jpg` | (-356, 90, 230) | (-356, 12, 96) — west campus |
| `shots/04-parking-on-grass-closeup.jpg` | (-470, 55, 190) | (-410, 14, 120) — west lot |
| `shots/05-westgate-lot-grass.jpg` | (-520, 50, 40) | (-440, 14, 100) — west gate |
| `shots/06-grandstadium-soccer-pitch.jpg` | (-765, 150, 180) | (-765, 20, -60) — `43_GrandStadium` |
| `shots/07-outdoor-basketball-court.jpg` | (-445, 45, 10) | (-445, 8, -70) — `Outdoor_Park` |
| `shots/08-practice-field-second-gridiron.jpg` | (432, 95, -320) | (432, 15, -470) — `19_PracticeField` |
