# 2K-Style Dribbling in Roblox — implementably

Research date: 2 November 2026.

---

## 1. How a ball visibly animated hand-to-floor is actually achieved

### The answer the working developers give: **animation-driven attachment via `Motor6D`**

This is the dominant pattern on Roblox and it is not IK and not physics.

**VERIFIED** from two DevForum threads where people built working dribbles:
[Dribbling Basketball System](https://devforum.roblox.com/t/dribbling-basketball-system/3989035)
and [How to make a basketball dribble system](https://devforum.roblox.com/t/how-to-make-a-basketball-dribble-system/1344420).

The construction:

1. The ball becomes **a member of the character's rig**. Create a `Motor6D` with
   `Part0` = the character's `HumanoidRootPart` (or `LowerTorso`) and `Part1` =
   the ball. Give the `Motor6D` a **unique name** — one thread's author calls his
   `Ball_Weld`, which is a misleading name for a `Motor6D`, but the mechanism is a
   motor, not a weld.
2. **Parent the ball to the character before the animation plays**, so it snaps
   into position.
3. **The animation drives the `Motor6D`.** The ball's entire hand-to-floor arc is
   authored as keyframes on that joint, exactly like a limb. One contributor
   (Yarik) is explicit: "you use `Motor6D` for animating," **not** attachments.
4. **Author the clips in Blender or Moon Animator.** Yarik reports Roblox's
   built-in animation editor struggled with this setup. Load clips via the
   `Animator` — `Humanoid:LoadAnimation` is deprecated.
5. **Kill the ball's physics while held.** Set the ball **massless**, `CanCollide
   = false`, and/or put it in a collision group that ignores the character.
   Reported failure mode without this: *the ball flings the player* on ground
   contact. Attributed to collision.

**Why this is right.** The ball is not being simulated and then hit by a hand; the
ball *is* a bone. Hand and ball cannot separate, because a single artist keyframed
them together. That is how 2K's dribble reads as weighted — the contact is
authored, not solved. It also means **the dribble costs you nothing at runtime**,
which matters enormously on phones (see `performance.md`).

**The cost, stated honestly.** Every move must be hand-authored as its own clip —
crossover left, crossover right, behind-the-back, between-the-legs, speed-dribble,
spin, each pickup and each transition. The second thread's structure makes this
plain: separate clips for pick-up, dribble-right and dribble-left, with the script
only managing *which hand is active*. **Your dribble quality is an animation
budget, not a code problem.** See `assets-and-licensing.md` — this is the single
biggest reason the Mixamo-as-interim-body decision matters.

### The two alternatives, and why they are not the main path

**Procedural IK — `IKControl`.** Roblox has first-class runtime IK
(**VERIFIED**: [Inverse kinematics](https://create.roblox.com/docs/animation/inverse-kinematics)).
You attach an `IKControl` to the `Humanoid`/`AnimationController` and set:
- `Type` — "Common behavior types are Position or Transform"
- `EndEffector` — a `BasePart` or `Bone` that moves toward the target, e.g. a hand
- `Target` — "can be any object with a world position" (i.e. the ball)
- `ChainRoot` — "All connected parts between the ChainRoot and the EndEffector are
  affected". `LeftUpperArm` moves the whole arm; `LeftLowerArm` only below the elbow.

Its documented weakness is exactly the one that kills it for dribbling: **"Even
with the elbow constraint, the IKControl can still produce unrealistic poses with
the wrists."** Constraining it is fiddly — a `HingeConstraint` for the elbow or
`BallSocketConstraint` for the wrist, whose attachments must match the `Motor6D`
parts, whose relative positions must match the `Motor6D` `C0`/`C1` CFrames, and
which must share the same parent `Model` as the `IKControl`.

Also **UNVERIFIED and important**: that page does **not** say how `IKControl`
blends with playing animations, does not document `Weight` or `Priority`, does
**not** say whether it replicates to other clients, and gives **no performance
guidance**. For a mechanic that must look identical on 10 clients on phones, three
unanswered questions is too many.

**Use `IKControl` for the garnish, not the dribble**: planting the off-hand on a
defender during contact, foot placement on uneven ground, a reach for a loose ball
that lands slightly off from the authored clip. Layer it on top of the authored
dribble; never let it own the ball.

**Physics.** Letting the ball actually bounce and having the hand meet it is the
intuitive approach and the wrong one. You inherit every problem in
`technical.md` §1 and §6 at 60 bounces a minute: the ball's owner sees contact the
others do not, and across an ownership boundary the body you do not simulate is
"infinitely massive". Physics is correct for the **free ball** — a pass in flight,
a loose ball, a rebound. It is wrong for the **held ball**.

### The architecture this implies

Model the ball as a small state machine with exactly one authority per state:

| State | Ball representation | Owner |
|---|---|---|
| **Held / dribbling** | `Motor6D` member of a character rig, massless, no collision | Server decides possession; the clip plays everywhere |
| **In flight** (pass, shot) | Real physics part, server-simulated, deterministic launch | Server |
| **Loose** | Real physics part | Server |

Possession changes are **state transitions on the server**, which is what makes
them cheat-resistant and identical on both screens. The visual dribble is then
pure presentation and can be driven locally with no risk — if a client's dribble
animation is 50 ms out of step, nothing about the match is wrong.

---

## 2. Mapping the controls across keyboard, gamepad and touch

### ⚠️ The API most tutorials use is being deprecated. This is the finding.

**VERIFIED**: the [`ContextActionService` reference](https://create.roblox.com/docs/reference/engine/classes/ContextActionService.md)
states that **`BindAction` is not recommended for new work and is planned for
deprecation**, and directs you to the **Input Action System** (`InputContext`,
`InputAction`, `InputBinding`).

Every dribble-controls tutorial you will find, and most of the incumbents' code,
uses `ContextActionService`. Do not start a 2026 project on it.

### Use the Input Action System

**VERIFIED**: [Input Action System](https://create.roblox.com/docs/input/input-action-system).

- **`InputContext`** groups related actions — e.g. a `PlayContext` for gameplay, a
  `NavContext` for menus. `Enabled` toggles the whole group; `Priority` decides
  which context wins; `Sink` blocks input reaching lower-priority contexts.
- **`InputAction`** is one mechanic. Its **`Type`** determines the value kind:
  **`Bool`** (default), **`Direction1D`**, **`Direction2D`**, **`Direction3D`**,
  **`ViewportPosition`**. It fires `Pressed`/`Released` (**`Bool` only**) and
  `StateChanged` (all types). Its read-only **`PreferredBinding`** returns the
  binding best matching the player's current device — **this is how you draw the
  correct glyph in a tutorial prompt without writing a platform check.**
- **`InputBinding`** is a child of an action. Set `KeyCode` for physical input, or
  **`UIButton`** to point at an on-screen button. **The docs recommend giving every
  action a binding for gamepad, keyboard/mouse and touch.**

**Required:** set `Workspace.PlayerScriptsUseInputActionSystem = Enabled`. (Note:
`AuthorityMode = Server` turns this on for you — see `technical.md` §0.)

The documented three-binding pattern, using Roblox's own Sprint example:
1. `KeyboardBinding`, `KeyCode = LeftShift`
2. `GamepadBinding`, `KeyCode = ButtonY`
3. `TouchBinding`, `UIButton` = a `SprintButton` inside a `ScreenGui` in `StarterGui`

Then one client script connects `Pressed`/`Released`. **One action, one handler,
three platforms, no branching.** The **Input Action Manager** (beta: File ⟩ Beta
Features ⟩ Input Action Manager) shows all bindings in a grid, with **yellow
warnings for a missing platform binding and red for duplicates** — i.e. the engine
will tell you when you have forgotten the touch binding, which is the bug every
Roblox sports game ships with.

**Documented limitations:**
- `InputActionLabel` is **beta**; the Input Action Manager is **beta**.
- `Pressed`/`Released` fire **only for `Bool`** actions. Analog triggers (`ButtonL2`,
  `ButtonR2`) use `PressedThreshold`/`ReleasedThreshold` instead.
- Reserved inputs cannot be overridden: `Esc`, `F9`, `F11`, `F12`, `PrintScreen`.
- Roblox advises overriding default controls only in specific cases.
- **`Direction2D` is listed for "2D directional movement such as camera rotation,
  or the standard Roblox character movement", but the page does not give a
  thumbstick setup for it or document what values it returns.** **UNVERIFIED** —
  prototype this before the control scheme depends on it.

### The concrete mapping for a 2K-style dribble

**Design constraint first.** From `landscape.md`: the #1 sports game on Roblox wins
with **two buttons**, and the #4 basketball game is known for **hold-to-shoot,
tap-to-pump-fake, space-to-dunk**. A dribble scheme needing six touch buttons
loses to those on a phone. The target is **one stick plus one modifier**.

| Action | `InputAction.Type` | Keyboard | Gamepad | Touch |
|---|---|---|---|---|
| `Move` | `Direction2D` | WASD | Left thumbstick | Existing left joystick |
| `DribbleAim` | `Direction2D` | Mouse delta / arrows | **Right thumbstick** | Right-side drag zone (invisible, not a button) |
| `SpeedDribble` | `Bool` | `LeftShift` | `ButtonL2`† | Hold-anywhere-right, or one visible button |
| `Spin` / signature | `Bool` | `Q` or `E` | `ButtonB` | One visible button |
| `Pass` | `Bool` | `F` / LMB | `ButtonX` | Button |
| `Shoot` | `Bool` | Space / RMB | `ButtonR2`† | Button (hold-to-charge) |

† analog triggers use `PressedThreshold`/`ReleasedThreshold`, not `Pressed`/`Released`.

**The crossover-left/right mapping — the actual trick.** Do not bind a separate
action per move. Bind **one `Direction2D` action** (`DribbleAim`) and derive the
move from the vector *relative to the character's facing*, at the moment the
dribble clip reaches its next contact frame:

- Vector roughly perpendicular-left ⇒ crossover to left hand
- Perpendicular-right ⇒ crossover to right hand
- Backward ⇒ hesitation / pull-back
- Forward while `SpeedDribble` held ⇒ speed dribble / push
- Perpendicular while `SpeedDribble` held ⇒ the aggressive variant of that crossover

This gives you a 2K-shaped move set from **one stick plus one hold**, maps
natively to a right thumbstick, and on touch becomes a **drag zone rather than a
button grid** — which is the only way this fits on a phone. It also scales: new
moves are new clips keyed off the same vector, with no new control surface.

**Gate the move on the animation's contact frame, not on the input.** The ball is
a `Motor6D` member of the rig, so a crossover can only begin where the authored
clip has the ball at a hand. Queue the requested move and start it at the next
contact frame. This is what produces the weighted, committed feel of 2K dribbling
instead of a rubber-band of interruptible clips — and it is why the state machine
in §1 wants the dribble clip to expose its contact frames as animation events.

**Touch specifics.** Keep visible buttons to **three at most** (speed, pass,
shoot) and make everything else gestural. If you must touch legacy
`ContextActionService` code, note the hard ceiling: **only seven touch buttons can
exist at once**
([`ContextActionService`](https://create.roblox.com/docs/reference/engine/classes/ContextActionService.md)).
Seven is not a budget, it is a warning.

---

## 3. Concrete examples and open-source references

What I can point at, with its status stated:

- **Roblox's own Soccer template**, shipped with Server Authority's full release
  (9 July 2026) alongside Racing and Laser Tag
  ([Full Release](https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993)).
  **This is the highest-value thing on this list and it is first-party.** Open it
  before writing any ball code. I could not inspect its contents from here — no
  Studio access — so I cannot tell you whether its ball is `Motor6D`-attached or
  physics-held. **Check that first.**
- **`Ulldren/server-authoritative-soccer-system`** — a Chickynoid fork with ball
  physics, "ball claiming prediction if you shot the ball last", ball curving and
  rotation, replicated character leaning, and goalkeeper lag compensation; tested
  on video at simulated 200 ping
  ([DevForum post](https://devforum.roblox.com/t/server-authoritative-soccer-system/3454547)).
  Author describes the code as "messy" and not extensively tested. **Read it for
  the ideas, do not depend on it.**
- **`Parihsz/Chrono`** — open-source custom physics replication: snapshot history
  for lag compensation, configurable interpolation delay, buffer serialisation,
  proximity-scaled update frequency, no packets while stationary
  ([DevForum](https://devforum.roblox.com/t/chrono-drop-in-custom-physics-replication-library/3873294)).
  Licence not stated in the post — **check the repo's licence before use.**
  Notably it does **not** use `UnreliableRemoteEvent`; the author called that an
  oversight. Relevant only if you reject Server Authority.
- **Real-time motion capture in Roblox** is being done by hobbyists
  ([Showcase](https://devforum.roblox.com/t/showcase-real-time-motion-capture-in-roblox-looking-for-feedback/3250296))
  — a cheaper route to a large authored dribble library than hand-keyframing.

**I found no open-source 2K-style Roblox dribble system.** The DevForum threads
above are the technique; nobody has published a complete implementation. Budget
for building it.

---

## 4. Identity boundary

The *mechanic* — a stick-driven dribble with crossovers and a speed modifier — is
a genre convention and yours to use. What is not: **NBA 2K's name, its HUD and
shot-meter design, its signature-move names, specific players' real signature
animations, and anything that reads as 2K's visual identity.** "2K-style" is a
fine internal shorthand for how the dribble should *feel*; it is not a thing to
put in your store listing, your UI, or a marketing reel.

The original route is to name the moves out of your own league fiction and design
your own dribble HUD from scratch. Worth doing well for its own sake: a distinctive
dribble indicator is a cheap, highly visible way for ALLSTAR WORLD to look like
itself in a reel, which is the market you are competing in (`landscape.md` §2).
