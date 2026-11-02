# Technical Patterns — Roblox, verified against documentation

Research date: 2 November 2026. Every answer is marked **VERIFIED** (primary source
named) or **UNVERIFIED** (not published / only community claim).

---

## 0. Read this before anything else in this file

**Roblox shipped a first-party server-authoritative networking stack to full
release on 9 July 2026, and it includes a Soccer template.** This did not exist
in the era most of the DevForum threads below were written in, and it changes the
right answer to questions 1 and 2.

**VERIFIED** — [[Full Release] Ship Fair And Competitive Games with Server Authority](https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993):
- Released to all creators 9 July 2026. **Opt-in**, not default.
- Set `Workspace.AuthorityMode = Server`. That single switch auto-enables five
  engine settings: `NextGenerationReplication`, `PlayerScriptsUseInputActionSystem`,
  `SignalBehavior = Deferred`, `StreamingEnabled`, and `UseFixedSimulation`.
- It provides **client-side prediction with rollback and resimulation** built in.
  Staff explicitly contrast it with `SetNetworkOwner`: `SetNetworkOwner` "doesn't
  offset the latency of syncing instance changes", whereas Server Authority
  "builds prediction and rollback into server ownership".
- New APIs for the game loop: `BindToSimulation` and `InputAction`.
- Stated coverage includes **character movement, vehicles, and sports physics**.
  Backpacks and Tools are fully supported.
- Roblox ships **Racing, Soccer and Laser Tag template games** as examples.
- It also ships an **upgraded Studio network simulation** for testing latency and
  packet loss.

Known limits and costs, same source:
- **8** actively playing animation tracks per `Animator`.
- **64** attributes per instance, with limited string size. Both limits come from
  Next Generation Replication; staff are "actively exploring" loosening them.
- Remote events are **not** synchronised with the shared timeline and can drift.
  Staff put the drift at roughly **40–50 ms** from the client's timeline.
- Camera `InputAction` stops syncing — breaking change. Use
  `Player:GetCameraState()` (returns `CFrame`, `FieldOfView`, `ViewportSize`).
  `Player.InputContexts.CameraContext.CameraAction` goes away.
- The `Animate` script's custom emotes, default mood logic and strafing
  animations are **not supported**.
- Server utilisation increases. Staff: impact is "most likely" small unless you
  were already near the server utilisation limit or run heavy server physics.
- Mobile and console clients typically lag desktop by a few days on rollout and
  cannot connect until they update.
- Staff (Khanovich): "Server Authority isn't the right decision for all games" —
  it will **not** become mandatory, and distributed authority stays.

Design note from the engineering thread
([Server Authority — Tech Deep Dive](https://devforum.roblox.com/t/server-authority-tech-deep-dive-engineering-insights/4624565)):
reconciliation is **pull-free** — "we wait until the Server pushes an update
before we check whether we need to reconcile/resimulate". Mispredictions cause
resimulation and "performance spikes are expected whenever you mispredict".
Staff expect steady-state mispredicts only at "floating point drift … edges of
0.05 studs". Staff position: **"Zero mispredicts is not the goal: smooth
gameplay is the goal."**

⚠️ **Conflict I could not resolve.** The Character Controller Library full-release
post says CCL is "compatible with the Server Authority beta, though some features
are still being refined"
([CCL full release](https://devforum.roblox.com/t/full-release-the-future-of-character-movement-character-controller-library/4565267),
live 8 April 2026). The Server Authority deep-dive thread reports staff saying
"legacy CCL code is not Server Authority compatible", with **Legacy Humanoid plus
manual controllers** being the tested configuration. Treat the supported pairing
as unsettled and test it yourself before committing the football core to CCL.

---

## 1. Server-authoritative ball possession in Roblox

### 1a. What `SetNetworkOwner` actually does and costs — **VERIFIED**

Source: [Network ownership](https://create.roblox.com/docs/physics/network-ownership) (official docs).

- Roblox physics is **distributed** between server and clients. The engine assigns
  ownership per part, considering the client's hardware and its proximity to the
  part: "parts close to a player's character are more likely to become
  player-owned." **No numeric distance threshold is published.**
- The server **always** owns anchored `BasePart`s and you cannot change that.
  Anchoring a lone assembly moves it to the server, and on unanchoring "its
  previous ownership state is lost."
- "Clients experience more responsive physics interactions with parts that they
  own." Conversely, with server ownership a player "will have to wait several
  network cycles before their input is recognized."
- Security, quoted: **"Roblox cannot verify physics calculations when a client has
  ownership over a BasePart."** Clients "can exploit this and send bad data to the
  server." `Touched` is tied to ownership — a client can fire it while "the server
  doesn't see it touch anything."
- Docs advise **conservative** use of server ownership for gameplay-critical
  parts, because "it may result in jittery physics interactions for clients."
- Studio's ownership visualisation: green = your client owns and simulates it;
  grey/white = server or another client owns it.

### 1b. The three options, trade-offs and failure modes

| Approach | Feel for the owner | Feel for everyone else | Cheat exposure | Failure mode |
|---|---|---|---|---|
| `SetNetworkOwner(ballToPlayer)` | Best — zero input latency | Ball arrives late; contested outcomes disagree | **Worst** — client can set `BodyVelocity`/`LinearVelocity` freely | Ownership thrash on possession change ⇒ visible stutter |
| Server simulates the ball | Input delayed several network cycles | Consistent for all | Best | Sluggish touch; everyone interpolates a ~20 Hz stream |
| Client predicts + server reconciles | Good | Consistent | Good | Mispredict ⇒ visible snap/rollback; expensive to hand-roll |

Observed cost of server ownership, from the staff-answered collision thread
([odd collision behaviour across ownership](https://devforum.roblox.com/t/odd-collision-behaviour-between-very-high-density-part-network-owner-player-and-very-low-density-part-network-owner-server/163363)):
the reporter measured the server-ownership delay at **about 0.1–0.2 seconds**.
**UNVERIFIED as a general figure** — one developer's measurement, not a published
number, and pre-dates the 2026 replication work.

Ownership-thrash is the most commonly reported failure mode in the wild. Threads:
[How can I make Network Ownership smoother with a soccer ball?](https://devforum.roblox.com/t/how-can-i-make-network-ownership-smoother-with-a-soccer-ball/3248924),
[Soccer ball becomes "local" for each player after a random amount of time](https://devforum.roblox.com/t/soccer-ball-becomes-local-for-each-player-after-a-random-amount-of-time/2096458),
[SetNetwork constantly switching between server and player](https://devforum.roblox.com/t/setnetwork-constantly-switching-between-server-and-player/2002938),
[Lag spikes … with SetNetworkOwnershipAuto](https://devforum.roblox.com/t/lag-spikes-in-multiplayer-game-with-physics-using-setnetworkownershipauto/2143432).
Cause: `SetNetworkOwnershipAuto` keeps reassigning as players move near the ball.
Mitigation is to call `SetNetworkOwner` explicitly on every possession change and
never leave the ball on auto.

The exploit exposure is not theoretical — a developer states it plainly in
[How to keep network ownership physics secure?](https://devforum.roblox.com/t/how-to-keep-network-ownership-physics-secure/3401807):
an exploiter "could just add a bodyVelocity that makes the ball go SUPER fast",
and subtler value tweaks are hard to spot. His own conclusion: with network
ownership "there is not much you can do." **That is the honest state of the
pre-Server-Authority world.**

### 1c. Recommendation for ALLSTAR WORLD

Evaluate `AuthorityMode = Server` **against the shipped Soccer template** before
hand-rolling anything. The alternative — writing prediction and reconciliation
yourself — is a multi-month networking project; the one public example of a
hand-rolled server-authoritative soccer system
([Server Authoritative Soccer System](https://devforum.roblox.com/t/server-authoritative-soccer-system/3454547))
is a fork of Chickynoid whose own author calls the code "messy" and
"hasn't been extensively tested for bugs". It does contain two ideas worth
stealing conceptually: **"ball claiming prediction if you shot the ball last"**
(helps at high ping) and **goalkeeper lag compensation**. No implementation detail
is given in the post; the repo is `Ulldren/server-authoritative-soccer-system`.

If you stay off Server Authority, the defensible middle path is: **server owns and
simulates the ball at all times; the possessing client runs a local visual-only
copy** (`CanCollide = false`) for responsiveness. That pattern is exactly what a
developer proposes in the staff thread above — "the server should own the ball's
physics, with clients treating it as a visual effect".

---

## 2. Lag compensation for contested physical outcomes at 50–250 ms

### 2a. The standard technique — **VERIFIED as a community pattern, not a Roblox API**

Roblox provides **no built-in lag-compensation or server-rewind API** for
developer-defined contests. Staff listed "server-side rewind hit detection for
shooters" as a **future roadmap item**, not a shipped feature
([Server Authority full release](https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993)).
So you build it.

The canonical Roblox write-up is
[Lag compensation with hitscan revisited](https://devforum.roblox.com/t/lag-compensation-with-hitscan-revisited/763848):
- Store **one CFrame per player per physics frame** in a **ring buffer of 60
  frames** — i.e. a **1-second** rewind window.
- It explicitly follows Valve's model, which keeps "a history of all recent player
  positions for one second."
- Memory cost, worked through in the thread: 20 players × 1 CFrame × 12 floats ×
  4 bytes × 60 frames = **~57 KB**. Negligible.
- Measure ping by piggybacking on messages you already send, rather than adding a
  dedicated mechanism.

### 2b. Timestamp validation and grace — **UNVERIFIED**

I could not find a published or community-consensus number for how much grace is
standard on Roblox. The hitscan thread **explicitly does not cover it**: the
author says rollbacks need sanity checks so clients can't request hits from any
point in their movement history, but the thread never describes those checks, and
gives **no thresholds, margins or tolerances**. Searches surfaced no DevForum
thread or doc that states a standard figure.

What I can state as sound engineering rather than sourced fact, flagged as my
inference:
- Clamp the rewind request to your buffer length (1 s above) **and** to the
  server's own measurement of that client's RTT, not to the timestamp the client
  claims. A client claiming 250 ms while the server measures 60 ms is cheating.
- Reject timestamps in the future outright.
- Budget for the documented **40–50 ms** remote-event drift under Server Authority
  when sizing any tolerance, since your contest messages are remote events and are
  **not** on the synchronised timeline.

### 2c. What feels fair to both sides

The top reply in that same thread is advice worth taking seriously for a solo
founder: **do not build lag compensation until players actually complain about hit
delay.** The developer who did try it found it "not the easiest thing in the
world" and noted limited control over Roblox's network stack.

For a two-player contest for one ball, the fairness choice is structural, not
numeric. Pick one rule and state it in the GDD:
- **Favour the actor** (rewind to the challenger's view): the challenger's screen
  never lies; the defender gets "I had it and it was taken". This is what shooters
  do and what players are trained to accept.
- **Favour the incumbent** (possession wins ties): the defender's screen never
  lies; the challenger whiffs on a ball that looked reachable.
A tie-break that is *deterministic and explained* beats one that is *accurate*.

### 2d. You can test 50–250 ms without a single real player — **VERIFIED**

Source: [NetworkSettings](https://create.roblox.com/docs/reference/engine/classes/NetworkSettings.md).
Playtest-only properties: `InboundNetworkMinDelayMs`, `InboundNetworkJitterMs`,
`OutboundNetworkMinDelayMs`, `OutboundNetworkJitterMs` (per-packet delay rounded
to 1 ms); `InboundNetworkLossPercent` and `OutboundNetworkLossPercent`, both
**capped at 0.5%**; `IncomingReplicationLag` (seconds) adds delay to all incoming
messages. Server Authority also ships an "upgraded Studio network simulation".

**This is the single highest-leverage item in this file for a solo developer.**
Set 125 ms each way plus jitter and play your own game.

---

## 3. `Workspace:GetServerTimeNow()` — the owner's spec depends on this

### 3a. Is it monotonic? — **VERIFIED (community, with a Roblox bug ticket open)**

Source: [Workspace:GetServerTimeNow() documentation incorrect …](https://devforum.roblox.com/t/workspacegetservertimenow-documentation-incorrect-and-datetimenow-needs-more-information/1909687).

**Yes, treat it as monotonic.** In that thread Qualadore states
`GetServerTimeNow` is monotonic, and ContextLost explains why: it uses **the same
internal monotonic clock as `tick()`**, with constant synchronisation and
smoothing. By contrast `os.time()` and `DateTime.now()` read system time and
"wouldn't stay monotonic across leap seconds and clock updates" — **do not use
those for match timing.**

### 3b. What it actually returns, and the accuracy caveat — **VERIFIED**

Same thread. Two things your spec must absorb:

1. **The documentation was wrong and Roblox acknowledged it.** The docs described
   it as the client's best guess at what `os.clock` would return on the server,
   which is meaningless because `os.clock()` has no Unix epoch baseline. Roblox
   staff (Focia19, 5 Aug 2022): *"We've filed a ticket to our internal database for
   this issue. We will come back as soon as we have updates!"* No resolution appears
   in the thread.

2. **It applies NTP-like latency compensation — it is not raw server time.**
   ContextLost describes it as approximately
   **`lastReceivedServerTime + (ping / 2)`**, extrapolated to track server
   wall-clock time. Critically, the same engineer argues this compensation is
   **usually unwanted for coordinating networked simulations**, and says he was
   "disappointed it was added", recommending instead that you either process client
   actions on receipt or offset them by the client's full round-trip time.

   **This matters directly for a football spec.** If you use
   `GetServerTimeNow()` to timestamp a client action, you are already embedding a
   half-RTT estimate in it. If you then *also* compensate for latency server-side,
   you double-count. Two developers in that thread asked for a non-extrapolated
   server-synced timestamp and for access to the raw `lastReceivedServerTime` —
   **neither request was answered.** There is no documented way to get the raw
   value.

3. **Accuracy is explicitly not guaranteed.** ContextLost: clients have "no
   guarantee of accuracy or sanity in their clock."

### 3c. Behaviour for a client that has just joined — **UNVERIFIED**

I could not verify this, and I checked both threads that address it directly. In
[How does workspace:GetServerTimeNow() work?](https://devforum.roblox.com/t/how-does-workspacegetservertimenow-work-does-it-replicate-time-on-every-call-or-in-the-background/3673444)
a developer (Tomi1231) raises exactly this question — noting the server could send
its time on connection but that ping compensation needs a round trip, and
speculating the value may be fetched before the client starts — and **no reply
confirms or rejects it.** The thread's own summary is that validity at join time is
unresolved. No Roblox staff reply. No documented answer exists.

The same thread does establish, as an observation, that it is **not** a per-call
network request: a developer ran **100,000 calls** and saw no spike in `recv` in
Network Stats. Consistent with background sync, but that is inference from one
test, not documentation.

**Spec guidance.** Because join-time validity is undocumented, do not let a
freshly joined client's first `GetServerTimeNow()` reading gate anything
match-critical. Have the client compare its first few readings and only trust the
clock once successive samples agree within your tolerance, or have the server
stamp the authoritative kickoff time and replicate it. Design so a wrong clock in
the first second degrades presentation, never possession or scoring.

---

## 4. `UnreliableRemoteEvent` — **VERIFIED**

### 4a. Real payload limit: **1000 bytes** (not 900)

Source: [Introducing UnreliableRemoteEvents](https://devforum.roblox.com/t/introducing-unreliableremoteevents/2724155).
The original post's known-issues section said payloads "should be at most 900
bytes." The **12 March 2025 update supersedes it: "Payload limit has been
increased to 1000 bytes on both Client and Server."**

The class reference page is no help here — [UnreliableRemoteEvent](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent)
says **nothing** about payload limits, when to prefer it, or any caveats. Its only
substantive line is the description: "asynchronous, unordered and unreliable,
one-way communication across the client-server boundary", plus "Scripts firing a
UnreliableRemoteEvent do not yield."

**The limit applies to the compressed size, not `buffer.len`.** In
[Incorrect size of data being sent limit specified…](https://devforum.roblox.com/t/incorrect-size-of-data-being-sent-limit-specified-when-using-unreliableremoteevent/3048788)
a developer sent a 3,855-byte payload successfully and had 3,875 bytes dropped,
and even pushed a 10,000-byte buffer through — because his test data was highly
repetitive. The community explanation (thebigkannye) is that buffers are
**compressed in transit**. When the developer refilled the buffer with
`math.random` values, behaviour **matched the documented limit**. No staff reply;
thread auto-closed July 2024.

**Consequence for your spec: budget 1000 bytes of *entropy*, not 1000 bytes of
struct.** Real gameplay state (positions, velocities) compresses poorly. Do not
size packets against a repetitive test.

### 4b. Guarantees: none worth relying on

Same announcement, quoted:
- "sends the event unreliably and unordered through the network".
- **"There is no ordering guarantee between UnreliableRemoteEvents and anything
  else."** — not just between each other; between them and *anything*, reliable
  remotes included.
- "Events with a larger payload will be dropped." Studio logs how many bytes over.
- "UnreliableRemoteEvents may be dropped to prioritize bandwidth or CPU usage" —
  i.e. in addition to ordinary packet loss, the engine may drop them deliberately.
- **"UnreliableRemoteEvents are not currently prioritized over other traffic."**
- Ones with no listeners connected are no longer queued.

### 4c. When to prefer it

Roblox's own recommendation: "particle effects, sound bites, and events that
impact visuals but are not crucial for game state."

Applied to football: **yes** for continuous, self-superseding streams where the
next packet makes the last one irrelevant — ball spin for the visual mesh,
cosmetic limb/lean state, crowd and camera flourishes, a dribble-phase hint.
**No** for anything a possession, tackle, score or purchase depends on. Because
there is no ordering guarantee against reliable remotes either, never split one
logical decision across a reliable and an unreliable event and expect them to
arrive in order. Every unreliable packet must carry its own timestamp and be
safe to drop or apply out of order.

---

## 5. Server Heartbeat rate and per-client bandwidth limits

### 5a. Heartbeat rate — **UNVERIFIED. Roblox does not publish a figure.**

I checked [Design for performance](https://create.roblox.com/docs/performance-optimization/design)
and [Computation performance](https://create.roblox.com/docs/projects/performance-optimization/computation).
Neither states a Heartbeat rate. The computation page only warns that tying
expensive work to per-frame `RunService` events repeats it every frame. Say
"once per render/simulation step", not "60 Hz", in the spec.

What **is** documented, and is the number you can design against:
- **Frame budget, quoted: "At 60 FPS, the total budget for each frame is 16.67
  milliseconds (ms)."** Target 60 FPS ([Design for performance](https://create.roblox.com/docs/performance-optimization/design)).
- **Physics stepping rate is documented and configurable** ([Computation](https://create.roblox.com/docs/projects/performance-optimization/computation)):
  in **adaptive** mode physics steps at **60, 120 or 240 Hz** depending on
  mechanism complexity; in **fixed** mode **all** assemblies step at **240 Hz**,
  described as "four times per frame", with significantly more computation per
  frame. Note Server Authority turns on `UseFixedSimulation`.

### 5b. Physics replication rate — **UNVERIFIED (community figure: 20 Hz)**

No official figure. The widely repeated community number is **20 Hz**, stated by
the author of the Chrono library
([Chrono — drop-in custom physics replication library](https://devforum.roblox.com/t/chrono-drop-in-custom-physics-replication-library/3873294)),
who says Roblox replicates physics at "20hz" with a large, non-configurable
interpolation delay. A standing feature request exists to make it configurable
([Allow game developers to configure the physics replication rate](https://devforum.roblox.com/t/allow-game-developers-to-configure-the-physics-replication-rate-for-their-games/4005498)).
Treat 20 Hz as a working assumption to be measured, not a fact.

### 5c. Per-client bandwidth limits — **UNVERIFIED. Not published.**

Neither [NetworkSettings](https://create.roblox.com/docs/reference/engine/classes/NetworkSettings.md)
nor the performance pages state any bandwidth, send-rate or throughput cap.
`NetworkSettings` exposes only playtest latency/jitter/loss simulation and memory
emulation.

Two things are nonetheless documented about throttling behaviour:
- Bandwidth limiting **exists** and is unchanged by the 2026 replication upgrade:
  staff say "bandwidth limits are unchanged, so large explosions are still
  throttled" ([Upcoming rollout of improved physics replication](https://devforum.roblox.com/t/heads-up-upcoming-rollout-of-improved-physics-replication/4618365)).
- Unreliable remotes "may be dropped to prioritize bandwidth or CPU usage"
  ([Introducing UnreliableRemoteEvents](https://devforum.roblox.com/t/introducing-unreliableremoteevents/2724155)).

So: a cap exists, Roblox will silently drop your traffic to respect it, and you
cannot look up the number. **Measure it** with Network Stats (Shift+F2 for
render/summary stats; F9 for the Developer Console, per
[Design for performance](https://create.roblox.com/docs/performance-optimization/design)).

Also relevant and dated: the improved physics-replication rollout **was rolled
back once**. Timeline from the staff post: rolled out 4 May 2026 (3:45–4:45pm
PST), **"HAS BEEN ROLLED BACK"** by 5 May 2026 11:20am, with a further rollout
planned around 9 June 2026. Its one real addition is **eventual consistency** —
"the final updates are sent over the wire before parts fall asleep", so a part's
resting position is confirmed by all observers. A known limitation remains:
anchoring updates are still not synchronised with physics, so parts can end up
anchored in the wrong place during complex events. Community members found
switching `workspace.SignalBehavior` to `Deferred` helped frozen-ball cases, but
**staff did not endorse it** and others said `Deferred` broke their animations.

---

## 6. Character replication: why characters owned by different clients collide
inconsistently, and what that means for tackle detection

### 6a. The mechanism — **VERIFIED, with a Roblox staff explanation**

Source: [odd collision behaviour between … network owner player and … network owner server](https://devforum.roblox.com/t/odd-collision-behaviour-between-very-high-density-part-network-owner-player-and-very-low-density-part-network-owner-server/163363).

Roblox staff (Khanovich), on what happens "when 2 objects cross-simulation
boundaries interact": **the object you do not simulate is effectively
"infinitely massive" from your side.** In the reported case a player-owned block
pushing a server-owned ball was itself displaced, because the ball it did not own
was treated as immovable.

Further, from the same thread:
- Roblox **tries to mitigate** this by locally simulating the other object on the
  client when it gets close.
- That local simulation is **blocked** when the part is driven by property-based
  motion such as `BodyPosition` or `BodyGyro`. Khanovich said he requested this be
  documented. `BodyVelocity` behaved better in his tests, though he noted a
  sleep-related bug and velocity not transferring properly during collisions.
- A developer (FieryEvent) states the core problem plainly: **objects on different
  owners see the world at different times**, so a ball can pass through a paddle on
  one side while colliding on the other.

**The structural truth: physics is not one shared simulation.** Ownership decides
which machine has authority, and cross-owner contacts are resolved **without a
shared timeline**. Density does not decide the outcome; ownership does. In that
report, adding or removing a character changed the result, and so did the
constraint type.

### 6b. What this means for tackle detection

Two characters are owned by two different clients. Therefore:

1. **Never detect a tackle from a collision or `Touched` between two characters.**
   Each side resolves the contact against its own stale view of the other, and the
   non-owned body behaves as infinitely massive. The two clients can legitimately
   disagree about whether contact happened at all. `Touched` is additionally
   ownership-bound and client-forgeable — the docs say a client can fire it while
   "the server doesn't see it touch anything"
   ([Network ownership](https://create.roblox.com/docs/physics/network-ownership)).

2. **Detect tackles as a server-side geometric query over replicated positions,
   on the server's own clock** — a distance/overlap test between torso positions
   plus a facing/velocity condition — not as a physics event. This makes the
   outcome a *decision* you control and can rewind (see §2), rather than an
   emergent physics result you cannot reproduce.

3. **Keep character-vs-character physical collision out of the gameplay path.**
   Put characters in a collision group that does not physically collide with each
   other, and express the tackle's *feel* as animation, camera and a server-applied
   impulse/stagger state. This is the same shape as the advice to let the server own
   ball physics while clients treat the ball as a visual effect.

4. **Expect ragdolls and reaction animations to differ per client.** Related report:
   [Ragdoll inconsistent between clients](https://devforum.roblox.com/t/ragdoll-inconsistent-between-clients/3858938).
   Treat ragdoll as cosmetic; never read a gameplay result back out of it.

5. If you adopt Server Authority, the server runs movement for everyone, which
   removes the cross-client ownership boundary for characters specifically — but
   remember the **8-animation-track-per-Animator** limit and that remote events may
   be **40–50 ms** off the simulation timeline, so a tackle decided by a remote
   event is not on the same clock as the bodies it is judging. Decide tackles
   inside `BindToSimulation`, not in a remote handler.

---

## Summary table

| Question | Verdict | Source |
|---|---|---|
| Ball possession: best current pattern | **VERIFIED** — first-party Server Authority (prediction + rollback) shipped 9 Jul 2026 with a Soccer template; opt-in via `AuthorityMode = Server` | [Full Release](https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993) |
| `SetNetworkOwner` responsiveness/security trade-off | **VERIFIED** — owner gets responsiveness; "Roblox cannot verify physics calculations when a client has ownership" | [Network ownership](https://create.roblox.com/docs/physics/network-ownership) |
| Auto-ownership distance threshold | **UNVERIFIED** — no number published, only "parts close to a player's character are more likely to become player-owned" | same |
| Lag-comp rewind window | **VERIFIED as community standard** — 60-frame ring buffer ≈ 1 s, following Valve; ~57 KB for 20 players | [Lag compensation with hitscan revisited](https://devforum.roblox.com/t/lag-compensation-with-hitscan-revisited/763848) |
| Standard grace/tolerance value | **UNVERIFIED** — no published or consensus figure; the canonical thread explicitly omits it | same |
| Built-in server rewind API | **VERIFIED absent** — roadmap item only | [Full Release](https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993) |
| Testing 50–250 ms | **VERIFIED** — `NetworkSettings` playtest delay/jitter; loss capped at 0.5% | [NetworkSettings](https://create.roblox.com/docs/reference/engine/classes/NetworkSettings.md) |
| `GetServerTimeNow` monotonic? | **VERIFIED (community)** — yes; same monotonic clock as `tick()`. Unlike `os.time()`/`DateTime.now()` | [DevForum thread](https://devforum.roblox.com/t/workspacegetservertimenow-documentation-incorrect-and-datetimenow-needs-more-information/1909687) |
| `GetServerTimeNow` accuracy | **VERIFIED** — NTP-like extrapolation ≈ `lastReceivedServerTime + ping/2`; no accuracy guarantee; docs acknowledged wrong, Roblox ticket filed Aug 2022, unresolved in thread | same |
| `GetServerTimeNow` on a just-joined client | **UNVERIFIED** — asked twice on DevForum, never answered, not documented | [DevForum thread](https://devforum.roblox.com/t/how-does-workspacegetservertimenow-work-does-it-replicate-time-on-every-call-or-in-the-background/3673444) |
| `GetServerTimeNow` call cost | **UNVERIFIED (observed)** — 100k calls, no `recv` spike ⇒ background sync, not per-call | same |
| `UnreliableRemoteEvent` payload limit | **VERIFIED — 1000 bytes** (raised from 900 on 12 Mar 2025), applied to the **compressed** size | [Introducing UnreliableRemoteEvents](https://devforum.roblox.com/t/introducing-unreliableremoteevents/2724155), [size thread](https://devforum.roblox.com/t/incorrect-size-of-data-being-sent-limit-specified-when-using-unreliableremoteevent/3048788) |
| `UnreliableRemoteEvent` ordering | **VERIFIED — none.** "No ordering guarantee between UnreliableRemoteEvents and anything else"; may be dropped for bandwidth/CPU; not prioritised | [Introducing UnreliableRemoteEvents](https://devforum.roblox.com/t/introducing-unreliableremoteevents/2724155) |
| Server Heartbeat rate | **UNVERIFIED — not published.** Frame budget 16.67 ms @ 60 FPS *is* documented | [Design for performance](https://create.roblox.com/docs/performance-optimization/design) |
| Physics step rate | **VERIFIED** — adaptive 60/120/240 Hz; fixed 240 Hz ("four times per frame") | [Computation](https://create.roblox.com/docs/projects/performance-optimization/computation) |
| Physics replication rate | **UNVERIFIED** — community says 20 Hz; no official figure; feature request open | [Chrono](https://devforum.roblox.com/t/chrono-drop-in-custom-physics-replication-library/3873294) |
| Per-client bandwidth cap | **UNVERIFIED — not published**, though throttling demonstrably exists | [Physics replication rollout](https://devforum.roblox.com/t/heads-up-upcoming-rollout-of-improved-physics-replication/4618365) |
| Cross-owner collision inconsistency | **VERIFIED, staff-explained** — the object you don't simulate is "infinitely massive"; different owners see the world at different times | [DevForum thread](https://devforum.roblox.com/t/odd-collision-behaviour-between-very-high-density-part-network-owner-player-and-very-low-density-part-network-owner-server/163363) |
