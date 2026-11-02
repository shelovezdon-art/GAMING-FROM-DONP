# Animation Sourcing, Legally — Mixamo as interim body for ALLSTAR WORLD

Research date: 2 November 2026. **I am not a lawyer and this is not legal advice.**
Where a decision carries commercial risk I say so and name the source so the
owner can read it himself or take advice.

---

## 1. Mixamo's current licence — what it does and does not permit

### What is permitted — **VERIFIED, primary source**

[Mixamo FAQ, Adobe](https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html):

- **"Mixamo is available free for anyone with an Adobe ID."** It **"does not
  require a subscription to Creative Cloud."**
- Quoted: **"You can use both characters and animations royalty free for
  personal, commercial, and non-profit projects including:"** — and the listed
  examples explicitly include **"creating video games."**
- **Excluded account types:** Enterprise and Federated IDs. Users with a **China**
  country code are also excluded.

**So: using Mixamo characters and animation clips in a monetised Roblox game is
permitted by Adobe's own FAQ.** That is the headline and it is good news for the
interim-body plan.

### ⚠️ The four conditions and risks that are not in that headline

**Risk 1 — the FAQ page is stale. VERIFIED.** The Adobe FAQ page itself is marked
**"Last updated on Sep 14, 2021."** A five-year-old FAQ is the primary licence
reference for a decision that will sit inside a monetised product. An independent
archive of that page dated **15 September 2026** shows the same royalty-free
language ([Rendered Influence](https://renderedinfluence.com/notes/adobe-mixamo-and-substance-3d-character-tooling-documentation/)),
which is reassuring — but that same check notes **"the live Adobe help page
returned access errors when checked, so current status couldn't be confirmed."**
**Action: screenshot the FAQ page, with its URL and date visible, on the day you
commit to Mixamo.** If the terms change later, your record of what they said when
you relied on them is the only thing you will have.

**Risk 2 — the standalone-redistribution limit. This is the one that touches your
DRIP STORE.** Adobe's FAQ does **not** address redistribution at all
(**UNVERIFIED from the primary source** — I checked and the page is silent). Two
secondary sources state the restriction consistently:
- Mixamo assets **"cannot be redistributed as standalone assets"** and must be
  incorporated into a larger project
  ([Mixamo License Guide](https://www.licenseorg.com/guide/3d-assets/mixamo)).
- Mixamo animations **cannot be included as standalone assets in an asset pack
  sold to others** ([MoCap Online](https://mocaponline.com/blogs/mocap-news/mixamo-alternatives)
  — note this is a competing vendor's blog).

**What this means concretely:**
- ✅ Mixamo bodies and clips **inside** ALLSTAR WORLD, driving your players —
  this is "a larger project". Fine.
- ❓ Selling an **avatar item on the Roblox Marketplace** whose mesh is a Mixamo
  character, or an **emote** that is a Mixamo clip, is much closer to
  redistributing the asset standalone. **Do not do this.** DRIP STORE items should
  be your own meshes on your own rig.
- ❓ Uploading a Mixamo body to Roblox makes a copy on Roblox's servers that other
  creators could potentially extract. That is an inherent exposure of the
  platform, not something you can contract around.

**Risk 3 — Mixamo is stagnant and Creative Cloud coupling has tightened.
Secondary source, treat with care.** [MoCap Online](https://mocaponline.com/blogs/mocap-news/mixamo-alternatives)
reports no meaningful updates since Adobe's acquisition, says **"Adobe has given
no official timeline for Mixamo's discontinuation"**, and reports that Adobe began
tightening Creative Cloud integration with **access disruptions for developers
without a CC subscription**. Caveats I must flag: this is **a competitor's blog**,
and **it contradicts itself** — it dates the CC shift to 2024 in one section and
"around 2022–2023" in another, and gives the library as ~2,000 animations in a
table and ~300 in its FAQ. Adobe's own FAQ still says no CC subscription is
required. **Treat "Mixamo may become harder to access" as a risk to plan around,
not an established fact.**

**Action: download everything you will ever need now, in one session, and keep it
in version control.** The licence covers assets you obtained under it; it cannot
make a withdrawn service available again.

**Risk 4 — the auto-rigger's input requirements.** If you rig your own sculpt
through Mixamo later, the character must be humanoid, in a **"default or neutral
pose"**, centred at the scene origin, with **"no other content in the file"** and a
**"clean and error free"** mesh. Floating heads detached from a body are not
supported ([Rendered Influence](https://renderedinfluence.com/notes/adobe-mixamo-and-substance-3d-character-tooling-documentation/)).

---

## 2. The bigger problem: Mixamo rigs do not match Roblox's character spec

**This will cost more time than the licensing will.** Roblox's character body
specification is strict and specific, and a Mixamo skeleton does not satisfy it.

### Roblox's published character body spec — **VERIFIED**

From [Character specifications](https://create.roblox.com/docs/art/characters/specifications)
(official):

**Geometry**
- **Exactly 15 separate meshes.**
- **Maximum 4 bone/joint influences per vertex.** Root bone takes no influences.
- Transformations frozen, pivot at 0,0,0; facing **+Z**, up **+Y**; watertight,
  quad-based topology where possible.
- Opacity 100%. Torso/arm/leg/head parts must fill **at least 50%** of their
  bounding box from front, side and back.

**Triangle budget — total 10,742 across the whole body**

| Asset | Meshes | Max tris |
|---|---|---|
| DynamicHead | Head | 4,000 |
| Torso | UpperTorso, LowerTorso | 1,750 |
| LeftArm / RightArm | Upper Arm, Lower Arm, Hand (each) | 1,248 each |
| LeftLeg / RightLeg | Upper Leg, Lower Leg, Foot (each) | 1,248 each |
| **Total** | **15** | **10,742** |

**Rigging**
- **Standard R15 = 15 bones** (LowerTorso, UpperTorso, Head, 6 arm, 6 leg) plus
  **Root** and **HumanoidRootNode**. LowerTorso and Root at position 0,0,0.
- **Advanced R15 allows up to 37 optional additional bones/joints.**
- Pose: **I-Pose, A-Pose or T-Pose.**
- Digits need one `DigitsRigDescription` per hand with optional bones.

**19 attachment points, each suffixed `_Att`**: Head (FaceCenter, FaceFront, Hat,
Hair); UpperTorso (LeftCollar, RightCollar, Neck, BodyBack, BodyFront); LowerTorso
(Root at 0,0,0, WaistFront, WaistBack, WaistCenter); RightUpperArm/LeftUpperArm
(RightShoulder/LeftShoulder); RightHand/LeftHand (**RightGrip/LeftGrip**);
RightFoot/LeftFoot.

**Textures:** Marketplace assets **max 2048 × 2048**.
*(Note the tension with `performance.md`: Roblox's performance docs say images
"usually need at most 512×512". 2048 is the Marketplace ceiling, not a target.)*

**Outer cages:** named `<MeshName>_OuterCage`. Character bodies need **only an
outer cage**; layered accessories need **inner and outer**.

**Marketplace requirements:** Material `Plastic`, Transparency `0`, VertexColor
`1,1,1`, and **no extra Scripts or Parts in the model.**

### Why this matters for the interim plan

A Mixamo humanoid is a single skinned mesh on a skeleton with far more joints than
R15 and no notion of Roblox's 15-mesh split, 19 named attachments, or outer cage.
**Bridging that is real work, and three of the gaps are structural, not cosmetic:**

1. **The 15-mesh split.** Roblox does provide a tool: the **Avatar Setup tool** can
   split a single-mesh model into the 15 required body parts
   ([Importing character bodies](https://create.roblox.com/docs/en-us/art/characters/import)).
   Start there.
2. **Joint remapping.** For advanced R15 rigs you may need
   `HumanoidRigDescription`/`DigitsRigDescription` objects and the **Adaptive
   Animation plugin** to remap joints and set a T-pose reference (same source).
   Import settings that page specifies: **Rig Type** = `Custom Humanoid` only for
   an advanced R15 rig; **Rig Scale** matching your Body Scale; **Constraint Type**
   = `Joint Upgrade`.
3. **The `RightGrip`/`LeftGrip` attachments are your dribble.** Those two named
   attachment points are where a held ball lives. If the interim body lacks them
   correctly placed, your `Motor6D` ball attachment (see `dribbling.md` §1) has
   nothing clean to hang off. **Get the grips right on the interim body or the
   dribble work does not transfer to the commissioned sculpt.**

**The strategic consequence.** The interim body's value is that it lets you build
and test the dribble, tackle and camera systems before the sculpt exists. That
value is only realised if **the interim rig matches the final rig's skeleton and
attachment layout.** So: decide the skeleton spec *first*, conform the Mixamo body
to it, and write it into the commission brief. Otherwise you will rebuild every
animation when the sculpt lands — and per `dribbling.md`, the animation set *is*
the dribble feature.

---

## 3. How FBX animation import actually works today — **VERIFIED**

**The importer and the animation editor are two different paths. Use both.**

**Meshes/bodies** — Studio's **Importer** (Home tab ⟩ Import). Accepts a rigged
character as **`.fbx` or `.gltf`**, creates a `Model` in the workspace
([Importing character bodies](https://create.roblox.com/docs/en-us/art/characters/import)).
Supported mesh formats overall: **`.fbx`, `.obj`, `.gltf`** (and `.glb`).
**`.fbx` and `.gltf` carry animation data; `.obj` does not.**
([3D importer](https://create.roblox.com/docs/en-us/studio/importer.md)).

**Animation clips** — the **Animation Editor / Clip Editor**, not the Importer
([Importing emotes](https://create.roblox.com/docs/en-us/avatar/emotes/import)):
1. Have a character with a standard **R15** rig in the workspace.
2. Avatar tab ⟩ **Clip Editor**, select the rigged character.
3. In the Animation Editor: **⋯ ⟩ Import ⟩ From File**, choose the `.fbx`. The
   animation appears in the timeline.
4. Publish via **⋯ ⟩ Publish to Roblox** to get an asset ID.

Two details that matter:
- **Emotes specifically** must be a **`CurveAnimation`**, not a
  `KeyframeSequence`: "The animation data for emotes must be a CurveAnimation
  object instead of a KeyframeSequence object." Convert via the **Curve Editor**
  button beside the timeline.
- **Selling an emote on the Marketplace costs an upload fee of 80 Robux**, and
  requires Content Type = `Avatar Item`, Asset Category = `Emote`. Gameplay
  animations used inside your own experience do **not** need this.

**Stated limits:** the importer page gives **no** numeric triangle, bone, texture
or file-size limits — it defers to the character specifications in §2 above
(**UNVERIFIED** elsewhere; §2 is the authoritative numbers).

**Practical note:** Mixamo exports one clip per download. A 2K-style dribble set is
dozens of clips, each needing the import-and-publish cycle above. That is hours of
mechanical work; budget it, and name/version the clips systematically from the
start.

---

## 4. The realistic alternatives

| Route | Cost | Licence clarity | Fit for ALLSTAR WORLD |
|---|---|---|---|
| **Mixamo** (current plan) | Free, Adobe ID | **Good for in-game use** (primary source); **unclear on standalone redistribution**; FAQ dated 2021 | ✅ Right call for the interim body. Download now, screenshot the terms, keep it out of DRIP STORE items |
| **Roblox's own animation tools** (Animation Editor, Curve Editor, Adaptive Animation plugin) | Free | **Unambiguous** — first-party, no third-party licence at all | ✅ Use for anything bespoke, and for every retarget. Zero licensing risk |
| **Roblox Creator Store / Marketplace packs** | Varies | **Per-asset — must be read each time.** Creator Store minimums: **$4.99** plugins, **$2.99** models; creator share net of taxes and payment fees; **30-day escrow** ([Monetization](https://create.roblox.com/docs/en-us/production/monetization)) | ⚠️ Convenient but you inherit whatever the uploader's rights actually were. Highest hidden risk of anything on this list |
| **Commissioned animation** | Highest cash cost | **Best** — if the contract assigns copyright to you | ✅ The right destination for your signature moves. See §5 |
| **Dedicated mocap libraries** — MoCap Online ($29–$299/pack, explicit commercial licence, Standard and Commercial tiers), ActorCore, Rokoko, Cascadeur, DeepMotion | Paid | **Explicit commercial licences** — their selling point over Mixamo | ✅ Strong middle option if Mixamo access degrades. Source is a vendor's own comparison ([MoCap Online](https://mocaponline.com/blogs/mocap-news/mixamo-alternatives)) — verify each licence directly |
| **CMU Graphics Lab Motion Capture Database** | Free | ⚠️ **Conflicting** — described as free for "research and commercial use" in body text but as a **research licence** in the same article's table | ❌ Do not use in a monetised game without reading CMU's own terms |
| **Self-captured mocap** | Time | **You own it outright** | ✅ Hobbyists are doing real-time mocap in Roblox today ([Showcase](https://devforum.roblox.com/t/showcase-real-time-motion-capture-in-roblox-looking-for-feedback/3250296)). Cheapest route to a *large, original* dribble library |

---

## 5. What would actually be a licensing problem in a monetised game

Flagged in order of how likely it is to bite:

1. **🔴 Selling Mixamo-derived meshes or clips as DRIP STORE / Marketplace items.**
   This is the clearest line. In-game use is covered; selling the asset itself
   approaches standalone redistribution. **DRIP STORE items must be original or
   commissioned work on your own rig.**

2. **🔴 Real players, teams, leagues and kits.** A realistic football game is under
   constant temptation here. Real player names, numbers, likenesses, signature
   celebrations, team names, crests, kit designs and stadium trade dress are all
   licensed property — NFL marks are licensed to Voldex and the NFL on Roblox
   specifically ([Pocket Tactics](https://www.pockettactics.com/roblox/nfl-universe-football)).
   **Create-a-Club makes this worse, not better**, because you would be *hosting*
   user-made infringing crests and kits. Ship original crest primitives and
   moderate user-made marks from day one.

3. **🟠 A commission contract that licenses rather than assigns.** If a
   commissioned sculpt or animation set is *licensed* to you, you may be unable to
   sell cosmetics built on it, or to use it if the relationship ends. **Require
   written assignment of copyright, with the right to sublicense, and an explicit
   grant covering sale of derived cosmetic items.** Get this right before the
   sculpt, not after — it is the asset your whole store sits on.

4. **🟠 Marketplace/Creator Store packs of unverifiable provenance.** You inherit
   the uploader's rights. A pack of "realistic football animations" cheaply priced
   is more likely to be ripped from a commercial game than motion-captured. Ripped
   animation from a real sports title in a monetised game is the fastest route to a
   takedown of your whole experience.

5. **🟡 Mixamo access or terms changing mid-project.** Mitigated by downloading
   everything up front and keeping a dated screenshot of the terms.

6. **🟡 Roblox's own upload rules.** Everything you upload must be content you have
   the right to upload; moderation applies regardless of your private licence
   position. A correct Mixamo licence is not a defence against a moderation action
   on an asset that *looks* like someone's IP.

### The practical decision

**Proceed with Mixamo as the interim body — the primary source supports it — but
do these five things:**

1. **Screenshot the Mixamo FAQ** with URL and date, today.
2. **Download the full set of clips you expect to need**, now, into version
   control.
3. **Define the final skeleton and the 19 `_Att` attachment points first**, conform
   the Mixamo body to it, and put that spec in the commission brief — so animation
   work transfers to the sculpt.
4. **Never put a Mixamo-derived asset in DRIP STORE or on the Marketplace.**
5. **Write copyright assignment into the sculpt commission** before work starts.
