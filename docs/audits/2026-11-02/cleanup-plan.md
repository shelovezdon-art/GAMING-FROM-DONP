# ALLSTAR WORLD — Cleanup Plan

**This is a proposal. Nothing has been deleted, moved or modified.** The audit session
was read-only.

Goal: get from the current build to the stripped-down version described in late October —
**one football field, one basketball court, one soccer stadium, mechanics focus, no city
skyline** — with real grass and a quality bar set by FIFA/EA FC, Madden and NBA 2K.

## How far along the strip-down already is

Verified against the live tree, not against the attributes:

| Target | Status | Evidence |
|---|---|---|
| One football field | **Done** — in `06_FootballPark` | `06_FootballPark` has exactly one field, `Field_5v5`. The 1v1-a/b/c/d and 2v2-e/w fields exist only as orphaned light towers and bleachers in `ServerStorage.PartnerOriginals`. |
| One basketball court, outdoors, as one park | **Done** | `18_BasketballCourts.Outdoor_Park` holds one `Court_bb-2` plus park furniture (stands, DJ stage, big board, fencing). The three indoor halls are in `AW_Archive` as `18_BasketballCourts_{1,2,3}_hall_before_2026-10`. |
| New outdoor soccer stadium | **Mostly done** | `43_GrandStadium` is a complete bowl: `Pitch` (143 x 241 studs, correct proportions), `Bowl`, `LEDRing`, `RoofFacade`, `PitchLights`, `Fixtures` (incl. `SoccerBigBoard`). `AWGrandStadiumCleared = v2`. |
| Remove city skyline buildings | **Done** | No instance in the world is named skyline, city, downtown or building. The only tall geometry left is `03_TrenchShell` (530 parts above Y=90), which is an enclosing shell over the lobby, not a skyline. `AWReno2026BlockMoved = true`. |
| Real natural grass, no fake turf, no Roblox slop | **Partial** | The soccer pitch and practice field have proper mowing stripes. The main 5v5 field does not. There are zero textures, zero PBR materials and zero MeshParts in the entire build — see looks.md. |
| Focus on mechanics | **Not started** | There are **no gameplay scripts anywhere in Workspace**. The only three scripts in the file (`Hoops3Service_halfcourt`, `Hoops3Client_halfcourt`, `TouchMoves_v1`) are sitting in `ServerStorage.AW_Archive`, i.e. they were archived during the October pass. |

**Honest summary: the venue strip-down is about 85% done.** The hard part — cutting six
football fields to one and three indoor halls to one outdoor court — has actually been
carried out. What remains is a second football field that should not exist, a large
amount of surviving support campus, an interrupted parking-lot migration, and the fact
that the thing the strip-down was *for* (mechanics) has not begun.

## What is still standing and still loading for players

Of 63,845 live instances, roughly **17,800 belong to the three venues the owner wants**
(`Field_5v5` 31,999 is misleading — 29,777 of it is decorative crowd; the field proper is
~2,200). The rest is support campus that survived:

| Still standing | Instances | In the stated plan? |
|---|---|---|
| `02_Props` | 12,958 | Partly — props serve whatever remains |
| `16_Landscape` | 2,768 | Yes — landscaping |
| `09_PerformanceCenter` | 2,323 | **No** |
| `WasteStations` | 2,139 | **No** — 1,457 bins |
| `03_TrenchShell` | 1,984 | **No** |
| `05_Arenas` | 1,937 | **No** — superseded by the three venues |
| `04_Lobby` + `15_LobbyFill` | 995 | **No** |
| `17_ArrivalPress` + `17b_ArrivalFans` | 1,438 | **No** |
| `19_PracticeField` | 664 | **No** — a second gridiron |
| `10_FieldHouse` | 474 | **No** |
| `11_ShowcaseStadium` | 129 | **No** |
| `08_SitePlan` | 385 | **No** — planning scaffold |

That is roughly **25,000 instances of campus that the October decision implies should go**,
and all of it loads for players today.

---

# The plan

Ordered so that every step is reversible and no step depends on a later one. Steps 1–5
are safe and uncontroversial. Steps 6–9 need the owner's call because they delete work.

## Conventions for every step

- **Nothing is deleted.** Everything is *moved* to
  `ServerStorage.AW_Archive.<Name>_<YYYY-MM-DD>`, matching the convention already
  established by `Simplify_2026-10-30` and `Outdoor_Park_backlot_2026-10-30`.
- **Set an attribute on `Workspace.AllstarWorld`** recording each step, matching the
  existing `AW*Moved` convention, so a future session can tell what ran.
- **Reversal is always:** drag the archived folder from `ServerStorage.AW_Archive` back
  to `Workspace.AllstarWorld` and clear the attribute. Positions are preserved by the
  move, so geometry returns exactly where it was.
- **Save the place before step 1.** The place is currently unsaved with 63,866 objects of
  Don's and Arnold's work. Nothing below should run against an unsaved file.

---

## Step 1 — Save, and take a versioned backup

Before anything: save the place, then **File > Publish to Roblox As** a dated backup
place, or save a local .rbxl copy.

**Affected:** nothing. **Reversal:** n/a.

Everything that follows assumes this has happened.

---

## Step 2 — Fix the broken parking-lot migration (a bug, not a cut)

`AWParkWestLotMoved` and `AWSoccerLotMoved` are both set, but the job did not finish: the
lot pavement was moved out and the **stall striping and cars were left behind**, so ~100
white stall lines and ~30 cars now sit on open grass west of the campus
(`shots/03-parking-on-grass-overview.jpg`, `shots/04`, `shots/05`).

Two options — the owner picks:

- **(a) Finish the removal.** Move the orphaned stall lines and the cars in that area to
  `AW_Archive.ParkWestLot_orphans_<date>`. Affected: ~100 stripe parts plus car models in
  x[-540,-290] z[-10,260]. Reversal: move back.
- **(b) Restore the pavement.** Find the asphalt slab in
  `AW_Archive.Outdoor_Park_backlot_2026-10-30` (527 desc) or
  `AW_Archive.Simplify_2026-10-30` (54,426 desc) and move it back under the striping.
  Affected: one or a few large parts. Reversal: move out again.

**Recommendation: (a).** The west lot is not in the stripped-down plan, so finishing the
removal is consistent with the direction. Do not leave it as it is — it is the most
obviously broken thing in the build.

---

## Step 3 — Delete the phone assemblies from the crowd (the single biggest win)

For each of the 852 `Fan` models in `06_FootballPark.Field_5v5.Crowd`, remove the `Phone`
part, the `PhoneScreen` part, and the `SurfaceGui` with its 12 Frames, 10 UICorners and
1 UIStroke.

**Affected:** 26,412 instances — **41% of the entire world** — across
`Crowd.WestStand` (420 fans) and `Crowd.EastStand` (432 fans). The fans themselves stay:
5 body parts each, still a visible crowd. At playing distance the phones are 2 pixels.

**Reversal:** this one is *not* cleanly reversible per-fan by a move, because the parts
are nested inside 852 separate models. Therefore: **before running, copy the whole
`Crowd` folder to `ServerStorage.AW_Archive.Crowd_withPhones_<date>` (29,777 instances).**
Reversal is then: delete the stripped `Crowd` and move the archived copy back.

Note that `ServerStorage.PartnerOriginals.Field_5v5__Crowd` (97,287 instances) is an even
earlier version and is **not** a substitute for this backup — it is a different, heavier
crowd from before the October simplification.

**Set attribute:** `AWCrowdPhonesStripped = "<date>"`.

---

## Step 4 — Turn off CanQuery and CanTouch on decorative parts

For every part in `02_Props`, `WasteStations`, `16_Landscape` and `10_FieldHouse` where
`CanCollide == false`, set `CanQuery = false` and `CanTouch = false`.

**Affected:** ~11,500 parts. **Nothing is moved or deleted — only two boolean flags
change.** Specifically: `02_Props` ~11,000 parts, `WasteStations` ~1,395,
`10_FieldHouse` ~210, `16_Landscape` ~0 (its query count already matches its collide
count).

**Do not touch** `18_BasketballCourts`, `43_GrandStadium` or `Field_5v5` in this pass —
those contain gameplay surfaces where queries may matter.

**Reversal:** re-run the same pass setting both flags back to `true` for parts in those
four folders with `CanCollide == false`. Record the exact folder list in the attribute so
the reversal knows its scope.

**Set attribute:** `AWQueryFlagsCleaned = "02_Props,WasteStations,10_FieldHouse@<date>"`.

---

## Step 5 — Lighting and post-processing pass

Three independent changes, each trivially reversible:

1. `Lighting.SunRays.Enabled = false`. **Reversal:** set it back to `true`.
2. Reduce the world's 630 lights. Start with `02_Props` (128 decorative lights) and
   `15_LobbyFill` (37 lights on 37 parts — the folder is nothing but lights).
   **Reversal:** these are Light instances inside parts; move them to
   `AW_Archive.Lights_removed_<date>` rather than deleting, then move back.
3. Consider raising `ClockTime` from 17.7 toward midday. **Reversal:** set it back to
   `17.7`. This is a look decision as much as a perf one — see looks.md.

**Set attribute:** `AWLightingPass = "<date>"`.

---

## Step 6 — Move the second football field — NEEDS OWNER DECISION

`19_PracticeField` is a **full second gridiron** — 608 parts, mowing-striped turf, its
own goalposts, light towers and `ALLSTAR` end zone (`shots/08`). It sits at
(432, 30, -465), roughly 1,600 studs from `Field_5v5` and 997 studs from spawn, on the
far east side of the map with its own access roads.

This directly contradicts "one football field".

**Affected if moved:** the entire `19_PracticeField` Model, 664 instances. Note it is a
*Model* where every sibling is a Folder, so it moves as one unit cleanly.

**Reversal:** move `AW_Archive.PracticeField_<date>` back to `Workspace.AllstarWorld`.
Position is preserved; it will return exactly where it was.

**Why this needs a decision rather than a default:** a practice field is a legitimate
thing to keep in a sports game that has a training mode, and it is one of only two
surfaces in the build with proper mowing stripes. It may be the *better* of the two
football fields visually. The owner may prefer to keep this one and cut the 5v5 — but
the 5v5 has the crowd, stands and scoreboard. **Default recommendation if no answer:
archive it**, because "one football field" was explicit and this is reversible in ten
seconds.

**Set attribute:** `AWPracticeFieldMoved = "<date>"`.

---

## Step 7 — Resolve the surviving support campus — NEEDS OWNER DECISION

These eight folders total **~11,800 instances** and none of them are a football field, a
basketball court or a soccer stadium:

| Folder | Instances | What it is | Note |
|---|---|---|---|
| `05_Arenas` | 1,937 | Indoor arena shells with 105 lights | Superseded by the three outdoor venues |
| `09_PerformanceCenter` | 2,323 | Training facility | Has 1,011 colliding parts — a real interior |
| `WasteStations` | 2,139 | 1,457 bins over 626 x 1150 studs | Pure set dressing |
| `03_TrenchShell` | 1,984 | Enclosing shell over the lobby, 138 lights | The last tall structure in the build |
| `17_ArrivalPress` + `17b_ArrivalFans` | 1,438 | Press/fan arrival set | |
| `04_Lobby` + `15_LobbyFill` | 995 | Indoor lobby | |
| `10_FieldHouse` | 474 | Field house | |
| `08_SitePlan` | 385 | Planning scaffold — site-plan markers | Almost certainly dead weight |
| `11_ShowcaseStadium` | 129 | 103 parts, 14 lights | A stub |

**Recommended order, least controversial first:**

1. `08_SitePlan` (385) — a planning scaffold, not content. Archive it.
2. `WasteStations` (2,139) — 1,457 bins is set dressing for a campus that is being cut.
3. `11_ShowcaseStadium` (129) — a 103-part stub that duplicates `43_GrandStadium`'s role.
4. `05_Arenas` (1,937) — indoor arenas superseded by the outdoor venues.
5. `03_TrenchShell` (1,984) + `04_Lobby` + `15_LobbyFill` (995) — **move together**;
   the shell exists to enclose the lobby, so cutting one without the other leaves either
   a roofless lobby or an empty shell.
6. `17_ArrivalPress` + `17b_ArrivalFans` (1,438) — the arrival set, also tied to the lobby.
7. `09_PerformanceCenter` (2,323) and `10_FieldHouse` (474) — **keep for now.** These are
   the two that most plausibly become real features (training, locker room). They are
   also 2,797 instances, which is 4% of the build — not where the weight is.

**Affected per sub-step:** exactly the folder named, moved whole.
**Reversal for every sub-step:** move the folder back from
`AW_Archive.<FolderName>_<date>`. Because each is a top-level Folder moved intact, the
reversal is exact.

**Hard dependency:** if steps 5–6 of this list run, `07_Doors` loses most of its purpose
(its 18 door models include `Door_MAIN_ENTRANCE`, `Door_WEST_GATE`, `Door_EAST_GATE`,
`Door_NORTH_GATE_PARK`, which are lobby and campus doors). Check `07_Doors` afterwards
and archive the orphaned ones. `Door_FOOTBALL` and `Door_SOCCER_BETA` should stay.

**Set attributes:** one per sub-step, e.g. `AWSitePlanMoved = "<date>"`.

---

## Step 8 — Export and remove the ServerStorage archives

ServerStorage holds **170,776 instances**, 73% of the saved file.

1. Right-click `ServerStorage.PartnerOriginals` (107,831) > **Save to File** >
   `PartnerOriginals_<date>.rbxm`. Store it outside the place, in the repo or a backup.
2. Same for `ServerStorage.AW_Archive` (58,847) > `AW_Archive_<date>.rbxm`.
3. Verify both files open correctly in a scratch place. **Only then** remove them from
   ServerStorage.
4. **Keep `AWBuild`** (3 ModuleScripts: `Lib`, `CourtKit`, `GrandStadium`) — it is the
   only live code in the file.
5. **Before removing `AW_Archive`, move the three gameplay scripts out of it** —
   `Hoops3Service_halfcourt`, `Hoops3Client_halfcourt`, `TouchMoves_v1` are the only
   gameplay code that exists anywhere, and they belong in `ServerScriptService` /
   `StarterPlayerScripts`, not in an archive folder.

**Affected:** 166,678 instances leave the place file. Nothing the player sees changes —
ServerStorage does not replicate to clients.

**Reversal:** insert the .rbxm back into ServerStorage. This is why step 3 of this
sequence must not be skipped.

**Do this step last**, after steps 2–7, because those steps *add* to `AW_Archive`.

---

## Step 9 — Small hygiene items

Each is independent and takes under a minute:

1. **Delete the two `Accessory (Cristiano Ronaldo)` instances** at Workspace top level.
   One is an empty husk (3 descendants, no Handle); the other has a `Handle` part with a
   live `TouchInterest`. Both are catalogue debris. **Reversal:** none needed, but if you
   want one, move them to `AW_Archive` instead of deleting.
2. **Move `AW_Spawn`** from (0, 0.29, 428.57) to the football park. It is currently
   668–1,175 studs from every playable area. **Reversal:** move it back; record the old
   position in an attribute first.
3. **Delete the empty folder `06_FootballPark.06_FootballPark_4`** (0 descendants).
4. **Fix the 4 coincident `Truss` parts** in `Field_5v5.LightTowers` — four towers each
   have a `Truss` at an identical position and size, which z-fights. Keep one per tower
   and reposition, or delete the three duplicates.
5. **Remove the stray `WorldBoundary` Part** sitting loose in `AW_Archive`.
6. **Rename for consistency.** The folder numbering has gaps (no 12, 13, 14), a
   duplicate (`15_LobbyFill`, `15_ZoneFloors`), an out-of-sequence `43_`, and twelve
   meaningless auto-generated sub-folders (`16_Landscape_1`..`_12`,
   `03_TrenchShell_1`..`_8`, `05_Arenas_1`..`_4`). After steps 6–7 cut most of these
   folders, renumber what survives as a single clean sequence.

---

## What the build looks like after the plan

| Stage | Live instances | ServerStorage | File total |
|---|---|---|---|
| Today | 63,845 | 170,776 | ~234,660 |
| After steps 3–5 (safe) | ~37,400 | ~200,600 | ~238,000 |
| After steps 6–7 (cuts) | ~25,000 | ~213,000 | ~238,000 |
| After step 8 (export) | ~25,000 | **3** | **~25,000** |

**From 234,660 instances to about 25,000** — a 90% reduction in file weight and a 61%
reduction in what players load — while keeping all three venues the owner asked for, and
with every cut reversible from a dated archive or an .rbxm on disk.

The point of all of it: at ~25,000 instances with the query flags fixed and the light
count down, the place stops being a thing that has to be managed and becomes a place you
can iterate mechanics in. That was the stated reason for the strip-down in the first
place, and it is the one part that has not started.
