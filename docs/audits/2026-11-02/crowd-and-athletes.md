# ALLSTAR WORLD — Crowd / NPC / athlete-body audit (2026-11-02)

Read-only. Place unmodified (63,866 descendants; `FootTraffic_Local` absent, confirming nothing ran).

## HEADLINE: all three crowd subsystems are dead at runtime

---

## What exists

### `CrowdAnimator` (StarterPlayerScripts, 213 lines, LocalScript)
Client-side cosmetic poser. Targets three paths (L5–9); only `Field_5v5.Crowd` exists — `Field_2v2-e`
and `Field_2v2-w` were deleted in the strip-down (bleachers survive in `ServerStorage.Bleachers_Backup`).
Caches `Fan` models carrying a `Base` CFrame attribute, then at 30 Hz (L10) picks a crowd mood — big play
every 20–34 s, Mexican wave every 45–75 s (L90–99) — and pushes pose CFrames via `workspace:BulkMoveTo` (L212).

Measured: **852 animated fans** (EastStand 432, WestStand 420), **8,463 parts**, **852 face SurfaceGuis**.
All parts already `CastShadow=false, CanCollide=false, CanQuery=false` — done right.
Modes: pump 238, snack 142, calm 127, clap 113, wave 103, phone 52, shout 41, sign 36; 93 flagged `Super`.

### `FootTraffic` (258 lines, LocalScript)
Builds pedestrians from scratch on every client at join — `Instance.new` parts, no models from the place
(L47 creates `workspace.FootTraffic_Local`). 21 routes summing to **182 walker slots**, ~25% spawn as pairs
→ **≈228 walkers**, plus 14 idle chat groups of 2–3 → **≈35 more**. ≈263 bodies × ≈16 parts ≈ **4,200 parts**,
each with a hand-drawn `SurfaceGui` face (L64–73) of ~9 Frames ≈ **2,400 GUI objects**.
Seeded `Random.new(31337)` (L38) so every client builds an identical crowd; positions from
`workspace:GetServerTimeNow()`, so walkers are genuinely synced across players.

### `AthleteMotion` (221 lines, LocalScript) — the best code in this set
Procedural layer on `PreSimulation` over whatever animation is playing: speed-scaled forward lean,
acceleration push, braking plant, banking into cuts with head kept level (L160–172), amplified hip/knee
swing at sprint (L182–186), arm drive opposite the legs (L188–199). Gated at `MAX_DIST = 260` studs (L85).
Tracks every `Humanoid` in Workspace — **there are zero NPC Humanoids in the place**, so today it only runs
on player characters and AI athletes the sport services spawn at runtime.

### `AWMotion` (115 lines, ModuleScript)
Shared vocabulary, not a runtime system: arm-claim registry with 0.15 s expiry (L7–15), layer registry
(L20–24), and **26 hand-authored joint poses** (9 football, 13 hoops, 5 soccer). Header at L26–28 records the
real constraint: since Roblox's avatar joint upgrade, R15 joints are `AnimationConstraint`s whose `C0` cannot
be written, so the server publishes `AWPose`/`AWPoseT` attributes and each client redraws the pose locally.

### `PressFlashService` (34 lines, Server Script)
Bare `while true` loop (L24). Pops random camera flashes from the 52 parts tagged `AWPressFlash`; faster when
a player is in the trench (±12 m in x, z 60–108 m, L11).

### `IndoorAtmosphere` (64 lines)
Eases Lighting toward indoor values inside parts tagged `AWIndoorZone`. **Zero objects carry that tag.**
A 4 Hz infinite loop that has never done anything.

### World
- `17_ArrivalPress`: 54 photographer bodies, 52 CameraBody + Flash + FlashLight.
- `17b_ArrivalFans`: 50 `Fan` models with **no attributes at all** — `cacheFan` bails at L20, so they are
  frozen props the animator never even caches.
- `11_ShowcaseStadium`: 103-part bare shell.
- `43_GrandStadium` (2,139 parts), `05_Arenas` (1,615), `18_BasketballCourts` (568), `04_Lobby` (752):
  **no crowd whatsoever**.
- `06_FootballPark` alone is **32,324 of 63,866 objects — 51%**. `StreamingEnabled = true`.

---

## Believability — three silent defects kill the football crowd

**1. The crowd is frozen. Permanently.**
Every fan's `Base` attribute sits exactly **765.8 studs** from where its torso actually is — a constant delta
of `(+765.0, −2.3, +34.6)` across all 852 fans (0 of 852 deviate by more than 1 stud). The `Crowd` folder was
moved after the attributes were baked and they were never re-baked. `CrowdAnimator` gates on
`(f.pos − camPos).Magnitude < VIEW_RANGE` where `f.pos` is the stale `Base` position (L106–107), so a player
at the field is 765 studs from the phantom position, fails the 320-stud gate, and **not one fan is ever
animated**. Fix: re-bake `Base` from each fan's current pivot. One pass turns the whole mood/wave/celebration
system on.

**2. No fan has arms that move.** Counting parts by attribute: **`arms = 0`**. Not one part carries the
`ArmSide` attribute `cacheFan` looks for (L32). `ArmR`/`ArmL` exist as parts but fall through to `f.static`
and are welded rigidly. Everything the script does with arms writes to an empty table. Meanwhile the
**702 held props** (cups, phones, snacks) *are* moved, to hand positions computed from arm angles no arm
follows. Once the crowd unfreezes, drinks will swing to 2.6 rad overhead while arms stay bolted to the torso.
Fix: set `ArmSide`/`ArmOff` attributes on `ArmR`/`ArmL` at bake time.

**3. Facial emotion is 100% dead.** The script switches between Calm/Hype/Shout/Upset (L48). The actual rig:
**845 fans have only a `Calm` frame, 7 have only `Hype`, and not one has `Shout` or `Upset`.** `setFace`
returns early when the target frame is missing (L69); for 845 fans the one frame present is also the initial
state, so it returns at the first line every time. Fix: author all four frames, or delete the system and
reclaim the per-fan GUI.

Other tells: one identical face on every fan, heavy torso-into-torso clipping in back rows, every fan at
precisely the same yaw, no legs visible from front rows, signs reading as floating billboards.
**Best value per hour is motion plus ±15° yaw jitter, not more fan detail.** A frozen 100%-aligned crowd reads
as cardboard at any polygon count.

**Arrival trench — handsome set, mannequin cast.** Real art direction (palms, banner towers, cyan signage),
but the 54 photographers are one silhouette repeated at near-perfect spacing, same yaw, same camera height,
arms as straight black bars. The 50 arrival fans hold an identical V-raise with signs floating above the hands.
Nothing moves except flash material swaps.

**Showcase Stadium, Grand Stadium, Arenas, Courts, Lobby — no people at all.** The soccer bowl is full
multi-tier seating with zero spectators: the most conspicuous crowd gap in the place, in a venue that survives
the strip-down.

---

## Cost

### Hurts phones now
1. **`FootTraffic` client build — worst offender.** ≈263 bodies, **≈4,200 parts and ≈2,400 GUI objects created
   by `Instance.new` on every client at join**, `task.wait()` only every 20 walkers (L169) → ~13 frames of build
   hitch. Locally created, so `StreamingEnabled` never unloads them — resident all session regardless of where
   the player stands. Routes cover parking lots, promenades and plazas the strip-down removes.
   **Fix:** cut the route table to surviving venues. **Win:** ~70% of routes → ~1,200 parts / ~700 GUI objects.
2. **Crowd geometry — 8,463 parts + 852 SurfaceGuis** streaming in near the field, inside a `06_FootballPark`
   that is 51% of the place. **Fix:** fuse each fan's non-moving parts; replace rear stand rows with a textured
   billboard. **Win:** the single biggest lever on total object count.
3. **`CrowdAnimator` per-frame — 25,560 wasted distance checks/sec today** (852 × 30 Hz, all failing the stale
   gate) producing nothing. Once `Base` is re-baked the bill becomes **8,463 CFrames × 30 Hz ≈ 254,000 CFrame
   writes/sec** via `BulkMoveTo` — heavy for a phone. **Fix before unfreezing:** for a `calm` fan `bounce` and
   `lean` are both 0, so `body == f.base` and the 7,725 static parts are rewritten to positions they already
   hold — early-out when `bounce`/`lean` are unchanged and write only arms/held/sign.
   **Win: ~90% of writes** → ~25,000/sec. Also drop `UPDATE_HZ` to 15 past ~150 studs.
4. **`PressFlashService` — permanent server-side replication trickle.** No player-count check, no proximity
   gate, no exit. Idle it fires ~1 flash per 0.6–2.2 s forever, in an empty server, with every player 800 studs
   away; in the trench ~18 pops/sec. Each pop writes `Material` + `Color` + light `Enabled`, twice → ~4–6
   replicated property changes per pop **broadcast to every client regardless of distance**.
   **Fix:** LocalScript gated on camera proximity.
5. **`IndoorAtmosphere`** — 4 Hz infinite loop over an empty tag list, forever. Negligible CPU, but pure
   dead-but-running code, and interiors are consequently *not* being corrected.

### Hurts later
6. **Football AI Humanoids keep full state machines.** `TeamFootballService:159` and `FootballService:124`
   disable only `Dead`. `FallingDown`, `Ragdoll`, `GettingUp`, `Climbing`, `Swimming`, `PlatformStanding` stay
   live — per-frame floor raycasts and state transitions server-side per athlete per field.
   `Hoops3Modules.Roster:50–52` already does this correctly. **This is the one that bites at 10+ concurrent.**
7. **ServerStorage archives:** `PartnerOriginals` 107,831 + `AW_Archive` 58,847 descendants. No runtime cost,
   but every save and publish carries them. A workflow tax.
8. **630 PointLights in Workspace** (8 shadow-casting; 52 press flashes, 138 in `03_TrenchShell`).

---

## Athlete body

**`AthleteMotion` today** never plays an animation. It reads `.Transform` on R15 `AnimationConstraint`s after
the animator writes them and modifies the result. Engine-version-aware (the `C0`-read-only workaround),
distance-gated, `pcall`-wrapped per body, explicitly non-authoritative (L8–9: it never moves anyone, so it
cannot affect fairness). **Good code; the asset worth protecting through any body swap.**

**What football athletes actually are.** `TeamFootballService:147–180` builds AI bodies with
`Players:CreateHumanoidModelFromDescription(desc, R15)` where `desc` sets **colours only — no body-part asset
ids**. That is the default blocky Roblox avatar. Animations are Roblox stock: run `913376220`,
idle `507766388`, walk `913402848`. Jersey numbers are SurfaceGui TextLabels (L161–170).

**The lean athletic body Don wants already exists — in soccer only.**
`ReplicatedStorage.AWSoccer.Athlete` (119 lines) uses Roblox Rthro "Skater Boi" body meshes (`Athlete.BODY`,
L9) with `TextureID` stripped so plain kit colours show (L33), the Rthro animation set (`Athlete.ANIM`, L10),
and `SCALE = { height 1.04, width 0.95, depth 0.95, head 0.95 }` (L11) — slim, slightly tall, real legs.
L1 records the brief verbatim: *"do we have to run with a block? the legs don't have to be so blocky… a little
bit of an adjusted build."* It paints shirt/shorts/socks/boots per body part (L76–82) and prints a gold-star
crest and numbers (L86–106). **Football never calls any of it.**

**No placeholder "soldier" body is wired in anywhere** — grepped the whole script tree for `[Ss]oldier`:
no matches. No Humanoid templates and no Animation objects in ServerStorage or ReplicatedStorage; every
animation id is an inline string literal.

**Highest-value change available today, before any Mixamo work:** point the football services at
`AWSoccer.Athlete.describe`. Close to a drop-in — football already builds its description the same way — and
it puts the lean Rthro build and Rthro animations on football athletes immediately. Also de-risks the Mixamo
route by proving `AthleteMotion` survives a body swap.

**What importing Mixamo FBX would require**
1. **The rig is the whole risk.** Mixamo exports a `mixamorig:` skeleton, not R15. `AthleteMotion.resolve`
   (L59–64) demands exactly 13 joints by Roblox name, each an `AnimationConstraint` or `Motor6D`. If the body
   isn't a conforming R15 rig, `resolve` returns `nil`, sets `st.retryAt = os.clock() + 2`, and **the athlete
   silently loses all procedural motion with no error** — it just goes stiff. Retarget to R15 in Blender
   before upload.
2. **Animations go through Studio's Animation Editor** — import FBX clip, publish, take the asset id. Then
   replace hardcoded literals at **five sites**: `FootballService:84`, `TeamFootballService:134`,
   `HoopsService:94`, `PracticeService:250`, `Hoops3Modules.Roster:23`. Hoist them into one module first (the
   way `AWSoccer.Athlete.ANIM` already does) so the next swap is one edit.
3. **Bodies:** if the Mixamo mesh is uploaded as 15 R15 MeshParts, only `Athlete.BODY` and `Athlete.SCALE`
   change — **no change to `AthleteMotion` or `AWMotion` at all.** The clean path.
4. **The 26 poses in `AWMotion` need a retune pass.** Directions are proportion-independent, magnitudes were
   authored against default R15. `FOOTBALL.wrStance` and `dbCrouch` use deep knee folds (−60°, −70°) and a −34°
   waist; on a taller slimmer rig those will read wrong. Budget a tuning session, not a rewrite.
5. **One stated invariant breaks.** `AWSoccer.Athlete:6` records *"All asset ids below are Roblox-owned
   (bundles 357 and 356); no third-party models."* Mixamo is third-party — free commercially, but Roblox upload
   moderation can reject imported humanoid meshes, and that comment stops being true. Worth an ADR before the
   first upload.

---

## Keep / cut / defer

- **KEEP and fix now — `CrowdAnimator` + the 852 football fans.** The one crowd attached to the one venue that
  survives the strip-down, three small bakes from working: re-bake `Base`, add `ArmSide` attributes, author the
  four face frames. Add the calm-fan early-out *in the same pass* so it doesn't go from 0 to 254,000 CFrame
  writes/sec on a phone. **Highest payoff per hour in the entire audit** — the asset is built and paid for, it
  is simply switched off.
- **KEEP untouched — `AthleteMotion` and `AWMotion`.** Most valuable people code in the place. Don't refactor
  during a body swap; they are what makes the swap safe.
- **KEEP and extend — point football at `AWSoccer.Athlete`.** Nearly free.
- **CUT most of — `FootTraffic`.** Worst phone cost, and most routes serve removed geography.
- **DEFER — `PressFlashService` and both arrival areas.** This is where effort is going into something already
  decided against. At minimum gate the flash loop to a client near the trench.
- **CUT or activate — `IndoorAtmosphere`.** Zero tagged zones. Either tag the lobby and arena interiors (good
  code, and interiors genuinely are washed out by the sunset grade) or disable the loop.

**Order to spend effort:** (1) re-bake `Base` + arms + static early-out; (2) football onto `AWSoccer.Athlete`;
(3) trim `FootTraffic` routes; (4) Humanoid state-machine disables. All small, none is new content.

---

## Risks

1. **CRITICAL — entering the Showcase Stadium rips the entire football crowd out of its stands.** Stale `Base`
   positions cluster around `(−84, 7, −460)`; `11_ShowcaseStadium` spans x −88…88, z −582…−280, centred
   `(0, 37, −431)`. A player at its centre is ~84 studs from the phantom positions — well inside
   `VIEW_RANGE = 320`. The gate passes, `BulkMoveTo` fires, and **all 8,463 fan parts teleport 765 studs out of
   the football bleachers into the empty Showcase Stadium deck**, in one frame, visible to that client. Latent
   only because nobody has walked there while the crowd was in view. Re-baking `Base` fixes freeze and hazard
   together.
2. **Two threads leaked forever.** `CrowdAnimator` L53–64 spawn a thread per path blocking on `WaitForChild`
   for `Field_2v2-e` and `Field_2v2-w`, both deleted in the strip-down. Two threads per client park on an
   unresolvable wait for the session's life.
3. **`PressFlashService` runs unconditionally and forever.** Degrades with player count — every pop broadcast
   to everyone.
4. **Football AI Humanoids keep `FallingDown`, `Ragdoll`, `Climbing`, `Swimming`, `PlatformStanding` enabled**
   (`TeamFootballService:159`, `FootballService:124`). Fix already exists at `Hoops3Modules.Roster:50–52`.
5. **`hum.MaxHealth = math.huge; hum.Health = math.huge`** (`TeamFootballService:158`). Infinities can produce
   `nan` in downstream ratio arithmetic. Prefer a large finite value.
6. **`FootTraffic` never destroys anything and ignores streaming.** No parent guard, no cleanup path.
   Contrast `CrowdAnimator`, which does guard with `first.part.Parent` (L105).
7. **Held props will detach visibly the moment the crowd unfreezes.** Fix arms in the same change as the
   `Base` re-bake or this is the first thing anyone notices.
8. **Exploit surface: essentially nil.** `CrowdAnimator`, `FootTraffic`, `AthleteMotion` and
   `IndoorAtmosphere` are client-local cosmetics with no RemoteEvents and no gameplay authority. The only
   server-side reader of player state is `PressFlashService.trenchBusy`; spoofing position there gets more
   camera flashes. No action needed.
