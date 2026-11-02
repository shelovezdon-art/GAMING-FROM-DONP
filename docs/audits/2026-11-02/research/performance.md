# Mobile Performance Budgets — Roblox, with numbers

Research date: 2 November 2026. Figures marked **VERIFIED** are from Roblox's own
documentation. Where Roblox publishes nothing, I say so rather than inventing a
number.

---

## 1. First, correct the premise about phones

The brief says "most Roblox players are on phones." **That is not what the data
shows, and the correction changes your optimisation priorities.**

**VERIFIED** — [2026 Roblox Benchmark Report, GameAnalytics](https://www.gameanalytics.com/reports/2026-roblox-report)
(device split, Aug 2025 – Jul 2026):

| Device profile | Share |
|---|---|
| Mobile **and** PC | 44.00% |
| **PC only** | **40.76%** |
| **Mobile only** | **11.55%** |
| Mobile + PC + Console | 1.62% |
| PC + Console | 1.61% |
| Console only | 0.43% |
| Mobile + Console | 0.03% |
| *Any console exposure* | *3.69%* |

Read it carefully: **~56% of players touch mobile at some point, but only 11.55%
are mobile-exclusive, and PC-only (40.76%) is nearly four times mobile-only.**

Caveats, stated honestly:
- This is **GameAnalytics-tracked games**, not the whole platform. Games that
  integrate an analytics SDK skew toward larger, more deliberately-built titles.
- **Roblox does not publish a device split.** I checked the Q3 2026 shareholder
  letter directly ([Q3 2026](https://s27.q4cdn.com/984876518/files/content_files/Q3-2026-Earnings-Shareholder-Letter.pdf)):
  it reports total DAU (138 million, down 9% YoY) and **no platform breakdown**.
  So the exact platform mix is **UNVERIFIED** at the platform level.

**What this means for ALLSTAR WORLD.** It is still true that you must run well on
a mid-range phone — nearly 6 in 10 of your players will play on one sometimes, and
a sports game lives or dies on frame-rate consistency. But "mobile-first" in the
sense of *sacrificing fidelity for phones* is the wrong trade when 40% of players
are PC-only and your differentiator is realistic fidelity (`landscape.md` §4).
**The right target is: build to the PC fidelity you want, then make the mobile
path cheap via quality tiers and streaming — not by reducing the asset itself.**

---

## 2. The documented budgets — **VERIFIED**

From [Design for performance](https://create.roblox.com/docs/performance-optimization/design)
(official):

| Budget | Figure | Quote |
|---|---|---|
| Frame rate target | **60 FPS** | — |
| **Frame budget** | **16.67 ms** | "At 60 FPS, the total budget for each frame is 16.67 milliseconds (ms)." |
| **Draw calls** | **< 1,000** | "you need to stay below 1,000 draw calls and 1,000,000 triangles for the game to run well on your baseline device" |
| **Triangles** | **< 1,000,000** | same |

Two more things that page says, which matter more than they look:

- **Avoid partial transparency.** Use `Transparency` 0 or 1 and nothing between.
  (Partial transparency forces alpha-blended draws and breaks occlusion — this is
  routinely the difference between 60 and 40 FPS on a phone.)
- **Studio's FPS lies.** Studio runs two instances of your game (server and
  client), so memory use is higher than on a real device. **Test on at least one
  real baseline device.** Shortcuts: **Shift+F2** for render/summary stats, **F9**
  for the Developer Console.

### What Roblox does **not** publish

- **No part-count budget.** **UNVERIFIED** — the page gives no part or instance
  count target. Anyone quoting you "keep under N parts" is quoting folklore.
- **No MeshPart count budget**, no per-mesh triangle cap on that page, no texture
  memory budget in MB, no device-tier specifications.

This is why **draw calls, not object count, is the number to design against.**
Which leads directly to your 64,000 objects.

---

## 3. Your 64,000 objects — what the number actually means

**64,000 objects is not, by itself, a problem. It is a draw-call risk and a
streaming requirement.**

Reasoning from the documented budgets:
- The budget is **< 1,000 draw calls**. If 64,000 objects were naively drawn, you
  would be ~64× over. They are not — Roblox instances identical meshes/materials —
  but **every distinct mesh+texture+material combination visible at once costs
  draw calls.**
- Therefore the question is never "how many objects does the place hold" but
  **"how many distinct mesh/material combinations are visible from a camera
  position, and how many are on screen at once."** A stadium of 64,000 objects
  built from 30 reused modular pieces is cheap. One built from 3,000 unique
  meshes is unshippable on a phone regardless of triangle count.

**Concrete actions, in order:**

1. **Measure, do not estimate.** Stand the camera at midfield, at a goal line, and
   in the stands, and read draw calls off **Shift+F2** at each. That is your real
   budget position. Everything below is guesswork until you have those three
   numbers.
2. **Count unique assets, not objects.** Target a small modular kit — tens of
   distinct meshes for a stadium, not thousands — and reuse aggressively. Roblox
   instances repeats; it cannot instance uniqueness.
3. **Collapse materials.** Each distinct `SurfaceAppearance`/texture set is a
   separate draw call family. Atlas where you can.
4. **Audit for partial transparency** across all 64,000. Nets, glass, banners,
   crowd cards and decals are where this hides.
5. **Mesh collision fidelity.** Documented as a performance sink
   ([Computation](https://create.roblox.com/docs/projects/performance-optimization/computation)):
   "overly precise mesh collision fidelity." Set every piece of stadium dressing
   to `Box` collision, or `CanCollide = false`, and reserve precise fidelity for
   the pitch and the few surfaces the ball must bounce off truthfully.

---

## 4. What actually sinks frame rate — **VERIFIED**

From [Computation performance](https://create.roblox.com/docs/projects/performance-optimization/computation)
(official), organised by subsystem:

**Rendering**
- High draw-call counts from poor instancing, excessive object density, complex
  meshes, and **shadow casting**.
- **Shadows are disabled at quality levels below 4** — so on a phone at low
  quality you are paying for shadow-casting geometry you cannot see. Author for
  that.
- The page gives **no draw-call number** (the 1,000 figure is on the Design page).

**Textures / memory**
- **Texture memory scales with pixel count.** A **1024×1024 texture uses four
  times the graphics memory** of a 512×512.
- **"Images usually need at most 512×512, and most minor images should be under
  256×256."** Treat that as your texture budget, because it is the only published
  one.
- Memory leaks: leaked connections and ever-growing tables.

**Physics**
- **Fixed 240 Hz stepping** is expensive. Adaptive mode steps at 60, 120 or 240 Hz
  by mechanism complexity; fixed mode steps **all** assemblies at 240 Hz —
  "four times per frame" — with "significantly more computation each frame".
- ⚠️ **Server Authority turns on `UseFixedSimulation`**
  ([Full Release](https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993)).
  So adopting Server Authority moves you to the expensive physics mode, and staff
  separately warn that it "increases server utilization". **Budget for this
  deliberately; do not discover it.**
- Many simulated assemblies, and precise mesh collision.

**Scripts**
- Expensive work on **per-frame** `RunService` events. The Design page's worked
  example: a 100 ms task every frame caps you at **10 FPS**; running it once a
  second gives 59 frames at 16.67 ms and one at 100 ms — **a visible stutter**.
  The fix is chunking: e.g. 5 ms per frame, result ready every 20 frames, holding
  60 FPS.
- Heavy serialisation or deep cloning of large tables.

**Networking**
- Excessive remote traffic; **replicating unchanged data every frame**; creating or
  removing large instance trees at runtime.
- **Named trap: server-side `TweenService` replicates the tweened property to every
  client every frame.** For a sports game full of UI and camera motion this is a
  silent bandwidth fire. Tween on the client.

**Avatars**
- MicroProfiler: `updateInvalidatedFastClusters` tags **over 4 ms** indicate
  excessive avatar invalidations. This is the one avatar-specific number Roblox
  publishes, and it is directly relevant to you — 10 custom-rigged players with
  cosmetics are exactly what invalidates avatar clusters. Watch this tag.

**Load times**
- Instance streaming disabled; bloated `ReplicatedStorage`/`ReplicatedFirst`.

---

## 5. StreamingEnabled for a large open place — **VERIFIED**

From [Instance streaming](https://create.roblox.com/docs/workspace/streaming)
(official). **For a 64,000-object place this is not optional.**

| Property | Default | Recommended | Notes |
|---|---|---|---|
| `StreamingEnabled` | **Enabled** for new places | Keep on | **Cannot be set from a script** — set it in Studio Properties |
| `StreamingMinRadius` | **64** | **Keep 64** | Streams in at highest priority and **never streams out**. Raising it costs memory and server bandwidth "at the expense of other components". Keeping it low "maximize[s] how much the engine can scale the game down for low-end devices" |
| `StreamingTargetRadius` | **1024** | **Keep 1024** | Max stream-in distance / farthest full detail. Smaller reduces server workload. Must be **larger** than min — **equal values leave no buffer and can cause network pauses** |
| `StreamOutBehavior` | `LowMemory` | **`Opportunistic`** | Default only streams out under memory pressure. `Opportunistic` lets the client drop content beyond the target radius without pressure — "significantly reduc[es] memory usage" and **prevents out-of-memory crashes** |
| `StreamingIntegrityMode` | not stated | **`PauseOutsideLoadedArea`** | Pauses gameplay if a player enters an unstreamed region. Use `Player.GameplayPaused` for a custom screen |
| `ModelStreamingBehavior` | `Legacy` | **`Improved`** | Most efficient for models with `BasePart` descendants; streams in once any `BasePart` is eligible, out with the last |
| `ModelStreamingMode` | `Nonatomic` | **Leave alone** | `Persistent` models are sent as a complete atomic unit soon after joining (before `Workspace.PersistentLoaded`) and **never stream out**. "Use them only in rare cases"; overuse "may negatively impact performance" |
| `PredictiveStreamingMode` | opt-in | **Test it** | Can reduce pauses and pop-in |

**Three warnings from that page that bite a sports game specifically:**

1. **Limit extra replication foci.** Each adds server streaming work. Quoted
   effect: **one player with nine moving foci can load the server about as much as
   ten players.** If you are tempted to add a focus for the ball, a focus for a
   camera cut, a focus per spectator — **do not.** That is how a 10-player match
   loads the server like a 90-player one.
2. **Avoid moving assemblies with very large numbers of instances** — streaming
   them in together causes network and CPU spikes. Relevant if a crowd, a scoreboard
   rig or a camera dolly is a single large moving assembly.
3. `StreamingEnabled` is **not scriptable**, so this is a build-time checklist
   item, not something you can toggle at runtime.

⚠️ **`AuthorityMode = Server` auto-enables `StreamingEnabled`**
([Full Release](https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993)).
If the place was built assuming everything is always loaded, Server Authority will
break that assumption the moment you flip it. Roblox ships an experimental AI
"Instance Streaming Conversion Skill" (used with MCP) for converting
non-streaming games — worth trying given 64,000 objects.

---

## 6. The budget sheet to design against

| Thing | Budget | Status |
|---|---|---|
| Frame rate | 60 FPS / **16.67 ms** per frame | **VERIFIED** |
| Draw calls, per camera position | **< 1,000** | **VERIFIED** |
| Triangles on screen | **< 1,000,000** | **VERIFIED** |
| Standard texture | **≤ 512×512**; minor images **< 256×256** | **VERIFIED** |
| Texture memory scaling | 1024² = **4×** the memory of 512² | **VERIFIED** |
| `StreamingMinRadius` / `TargetRadius` | **64 / 1024** | **VERIFIED** |
| `StreamOutBehavior` | **`Opportunistic`** | **VERIFIED (recommended)** |
| `ModelStreamingBehavior` | **`Improved`** | **VERIFIED (recommended)** |
| Extra replication foci | **as few as possible** — 9 ≈ 10 players of load | **VERIFIED** |
| Avatar invalidation (MicroProfiler) | `updateInvalidatedFastClusters` **< 4 ms** | **VERIFIED** |
| Partial transparency | **none** — 0 or 1 only | **VERIFIED** |
| Shadows | gone below quality level 4 — author for it | **VERIFIED** |
| Physics step | adaptive 60/120/240 Hz; fixed = 240 Hz for all | **VERIFIED** |
| Animation tracks per `Animator` **under Server Authority** | **8** | **VERIFIED** |
| Attributes per instance **under Server Authority** | **64**, limited string size | **VERIFIED** |
| Part / instance count | **no published budget** | **UNVERIFIED** |
| Per-client bandwidth cap | **no published figure** (throttling exists) | **UNVERIFIED** |
| Server Heartbeat rate | **not published** | **UNVERIFIED** |
| MeshPart count / per-mesh triangle cap | **not on the perf pages** | **UNVERIFIED** |

**The 8-animation-track limit deserves a line of its own.** A 2K-style dribble
system layers clips — base locomotion, dribble, lean, upper-body reach, reaction,
celebration. Eight tracks per `Animator` under Server Authority is a real design
constraint on exactly the feature that is meant to differentiate you. Design the
layering inside that budget now, not after the animation set exists.

---

## 7. The test protocol

1. **One real mid-range Android phone**, used for every build. Studio's numbers
   are not the phone's.
2. **Shift+F2 at three camera positions** (midfield, goal line, stands) every
   milestone. Record draw calls and triangles. These are your only real numbers.
3. **Emulate the device in Studio** via `NetworkSettings.EmulatedTotalMemoryInMB`
   to reproduce memory pressure
   ([NetworkSettings](https://create.roblox.com/docs/reference/engine/classes/NetworkSettings.md)).
4. **Play at 125 ms each way with jitter**, using the same `NetworkSettings`
   latency properties (see `technical.md` §2d). Frame rate and network feel are two
   different bugs and you will blame the wrong one if you only ever test locally.
5. **Watch `updateInvalidatedFastClusters`** in the MicroProfiler with a full
   10-player match of cosmetic-laden custom rigs. This is the most likely place
   your DRIP STORE quietly costs you frames.
