# Football Playbook + Play-Call Screen — ALLSTAR WORLD

> **Status: DESIGN DRAFT 1 — 2026-11-02. Nothing in this document is built.**
> It specifies the expansion of `TeamFootballService`'s 5-play list into a real,
> categorized playbook, and a Madden-style play-call screen for the QB.
> Engine: Roblox (Luau). **Units: METRES, SECONDS, DEGREES** (1 stud = 0.35 m).
> Baseline build facts are from the 2026-11-02 audit (`football-core.md`) and the
> measured TeamFootballService state in the task brief: 5 plays per mode, each a
> name + 4 route assignments from an 8-route pool (`slant, curl, post, fade,
> cross, flat, wheel, seam`), QB picks with keys 1–5 at the line, receivers may
> override their own route, and the client→server wire format is
> `{ action = "play", index = n }`. **That wire format is preserved.**
> Ruleset base: IFAF 5v5 (`football-ruleset.md`) — QB + 4 skill players, one
> rusher, midfield line to gain, declared 1-pt (from the 5) / 2-pt (from the 10)
> tries, no-run zones inside 4.57 m of each goal line.

---

## 1. Overview

The playbook system replaces the QB's 5-item text list with a **15-play,
6-category playbook** and a **lower-third play-call screen** shown to the QB
between downs: a page of three play cards with the route tree drawn on each card,
category tabs, and pick-by-tap/click/key/D-pad with confirm. The server remains
the single authority: the playbook is a server-side table, the client renders
cards from a replicated read-only copy, and the QB's choice still travels as
`{ action = "play", index = n }` — the table just gets bigger and categorized.
Teammates see their own route preview update when the QB selects (the server
already rebroadcasts selection); the defense never sees the pick. A play clock
with an auto-call rule prevents stalling. Try downs filter the book to the
declared 1-pt or 2-pt page. 2v2 uses a smaller 6-play book through the same
screen and the same wire format.

## 2. Player Fantasy

**"I'm the field general — I saw the coverage, I called the shot."** The QB
should feel like they are playing chess at the line: flip to the vertical page,
see FOUR VERTS drawn as four arrows climbing the card, tap it, and watch four
teammates' route ghosts snap into place. Receivers should feel *informed, not
commanded* — their route appears the instant the call is made, and their
existing override stays their escape hatch. The defense should feel the QB's
tendencies becoming readable over a game ("third MESH RAIL this half — jump the
wheel"), which is counterplay earned by attention, not a UI leak.

MDA aesthetics served: **Challenge** first (the call is a read-and-decide skill
with a clock on it), then **Expression** (your playbook identity: quick-game
grinder vs deep-shot gambler) and **Fellowship** (a called play is a shared plan
— the QB-receiver chemistry the core GDD names under Relatedness). SDT:
**Autonomy** is the headline — 15 genuinely different answers instead of 5, with
no dominant pick (see Edge Cases, degenerate strategies). **Competence** is
served by the pillar rule carried from `football-core.md` §2: play-call outcomes
produce readable reason strings ("CLOCK RAN OUT — COACH CALLED CURL FLAT"), so
"I know exactly why I lost" survives the new layer.

## 3. Detailed Design

### 3.1 Playbook structure — server-side table

One table, `PLAYBOOK`, lives in `ReplicatedStorage.AWFootball.Config` under a new
`playbook` key (NOT in `TeamFootballService.TC` — this is the chance to pay down
standards debt C1, not deepen it). Shape:

```
playbook = {
  plays5 = { [1..15] = {
      name       = "MESH RAIL",          -- uppercase, <= 14 chars (card width)
      category   = "CROSSERS",           -- one of the 6 category ids
      formation  = "SPREAD",             -- key into playbook.formations
      routes     = { X = "cross", Z = "post", SLOT = "crossL", RB = "wheel" },
      tryOnly    = nil,                  -- nil | 1 | 2  (try-page plays)
      mirrored   = false,                -- RT version; client may offer LT flip
  } },
  plays2 = { [1..6] = { ... } },         -- 2v2 book, same shape, 1 receiver route
  formations = { SPREAD = {...}, TRIPS = {...}, BUNCH = {...}, TIGHT = {...}, BACKS = {...} },
  routes     = { ...existing 8 + the 4 new routes in §3.3... },
}
```

The server validates every intent against this table (§3.8). The client reads
the same table to draw cards — one source of truth, already replicated because
it lives in `ReplicatedStorage`.

**Category ids (6):** `QUICK`, `CROSSERS`, `VERTS`, `MISDIRECTION`, `GOALLINE`,
`SPECIALS`. `SPECIALS` holds the try plays; `GOALLINE` plays are legal anywhere
but tuned for the compressed field inside the no-run zone (all plays are passes,
so IFAF's no-run restriction costs the playbook nothing).

### 3.2 Formations — 5 spots, named sets

Coordinates are **(lateral, depth)** in metres from the snap spot: lateral
positive = right (mirrored wholesale for LT versions), depth negative = behind
the line of scrimmage. Field half-width is 11.43 m; all laterals are clamped to
±10.5 m at placement (§5.9).

| Formation | QB | X | Z | SLOT | RB | Use |
|---|---|---|---|---|---|---|
| `SPREAD` (2×2) | (0, −3.5) | (−9, 0) | (+9, −0.9) | (+4.5, −0.5) | (−4.5, −0.5) | Base; most plays |
| `TRIPS` (3×1 right) | (0, −3.5) | (−9, 0) | (+6.5, −0.9) | (+3.5, −0.5) | (+9, −0.9) | Flood one side |
| `BUNCH` (right) | (0, −3.5) | (−9, 0) | (+6, −0.9) | (+7, −0.3) | (+5, −0.8) | Rubs, mesh |
| `TIGHT` (goal line) | (0, −3.5) | (−5, 0) | (+5, −0.9) | (+2.5, −0.5) | (−2.5, −0.5) | Compressed field |
| `BACKS` | (0, −3.5) | (−9, 0) | (+9, −0.9) | (+4.5, −0.5) | (+1.5, −3.0) | RB wheel/swing |

Defense alignment stays as built (RUSH, CB×2, NICKEL, LB); the defensive
auto-alignment should mirror receiver laterals the way it does today. The QB
self-snaps (current build convention; the ruleset's open "who snaps" question
does not block this system — the formation table just gains a CENTER spot if the
owner later adds one).

### 3.3 Route pool — 8 existing + 4 new

Existing (unchanged, points as built): `slant, curl, post, fade, cross, flat,
wheel, seam`. New routes, defined like the existing ones — a polyline of
(lateral, downfield) points in metres **relative to the receiver's alignment**,
lateral positive toward the nearest sideline, mirrored for left-side alignment:

| Route | Points (lateral, downfield) | Concept |
|---|---|---|
| `out` | (0,0) → (0, 7) → (+6, 7) | Speed out at 7 m; sideline timing throw |
| `dig` | (0,0) → (0, 10) → (−8, 10) | Square-in at 10 m breaking to the middle |
| `comeback` | (0,0) → (0, 12) → (+2, 10) | Drive to 12 m, break back down toward the sideline |
| `sluggo` | (0,0) → (−2, 4) → (−2.5, 6) → (+0.5, 26) | Slant-and-go: three steps inside, then vertical. **The double move** |

The final `sluggo` point (26 m) and all deep terminal points are **clipped at
runtime** to 1 m short of the end line (§5.8), so the same route data works on
the current field and the owner's coming bigger "Yard" field. All 12 route
definitions move into `playbook.routes` config — route points are gameplay data
and must not stay hardcoded (coding standard: data-driven values).

### 3.4 The 15-play 5v5 book

Routes listed as X / Z / SLOT / RB. `crossL`/`crossR` denotes the existing cross
mirrored to meet its partner (mesh).

**QUICK — ball out before the rusher (release target < 2.0 s):**
1. **DOUBLE SLANT** — SPREAD — slant / fade / slant / flat. Two in-breakers off the snap; fade clears the corner.
2. **CURL FLAT** — SPREAD — curl / curl / seam / flat. The classic hi-lo on the flat defender.
3. **QUICK OUTS** — SPREAD — out / out / slant / flat. Sideline timing; stops the clock late in halves.

**CROSSERS — horizontal stress:**
4. **MESH RAIL** — BUNCH — crossR / post / crossL / wheel. Two shallows cross under a post; the RB rail is the sprint-button payoff when the LB chases mesh.
5. **SHALLOW DIG** — TRIPS — dig / fade / cross / flat. Hi-lo in the middle: shallow pulls, dig replaces.

**VERTS — the deep-ball page (max arm 27 m/s, 2.15 s hang):**
6. **FOUR VERTS** — SPREAD — fade / fade / seam / seam. Four climbers; one deep defender cannot cover two seams.
7. **SLUGGO SHOT** — SPREAD — sluggo / comeback / dig / flat. The double move: sell the slant, sprint past the bitten corner, throw while the rusher closes.
8. **POST WHEEL** — BACKS — curl / post / cross / wheel. Post drags the deep help; the wheel sprints into the vacated sideline.

**MISDIRECTION:**
9. **SWITCH VERTS** — SPREAD — post / dig / wheel / flat. X and SLOT swap releases (inside post, outside wheel); man coverage has to trade or chase.
10. **JET WHEEL** — TRIPS — dig / slant / wheel / flat. SLOT sprints the wheel off the trips stack; the slant holds the inside.

**GOALLINE — compressed field, no-run zone legal (all passes):**
11. **GOAL FADE** — TIGHT — fade / fade / out / flat. Back-corner balls; the aggressive-catch jump contest is the finish.
12. **UNDER** — BUNCH — slant / curl / slant / flat. Legal natural rub out of bunch; the flat is the hot answer.

**SPECIALS — try plays (declared, per IFAF):**
13. **MONEY OUT** — TIGHT — slant / fade / out / flat — `tryOnly = 1` (from the 5, pass-only).
14. **TEN SHOT** — SPREAD — dig / comeback / seam / wheel — `tryOnly = 2` (from the 10).
15. **RAIL SWING** — BACKS — comeback / post / cross / wheel — `tryOnly = 2`. The RB wheel from the backfield is the surprise.

Deep-ball + sprint weaponizers, as briefed: **FOUR VERTS, SLUGGO SHOT, POST
WHEEL** (plus TEN SHOT on tries).

### 3.5 The 2v2 book (6 plays, 1 receiver route each)

`SLANT`, `CURL`, `COMEBACK`, `POST`, `SLUGGO`, `GO` (fade). Same screen, same
wire format, `plays2` table; one route arrow per card. No categories — a single
page of 6 (two rows of 3).

### 3.6 The play-call screen

**Layout (landscape, all platforms):** a **lower-third panel** on the QB's
client only, opening at the whistle/spot and closing at the snap. Full-screen is
deliberately avoided — the QB should keep seeing the field and the play clock.

- **Tab row** (top edge of panel): the 6 category tabs. The active tab is
  highlighted; `SPECIALS` is visible only on a try down, and on a try down it is
  the *only* tab (§5.5).
- **Card row**: **3 play cards per page**; categories with more than 3 plays
  page horizontally (current book: max 3 per category, so one page each).
- **Each card** shows: play name (top), formation tag (bottom-left), and the
  **route tree drawn in the card body** — see §3.7.
- **Footer buttons**: `REPEAT` (last play called, shown with its name) and
  `COACH` (weighted suggestion for down/distance — §4.3; one tap accepts it).
- **Play clock** stays in the existing HUD; the panel border pulses when the
  clock reaches `warnAt` (default 5 s).

**Selection vs confirmation are separate steps.** Highlighting a card
(focus/hover/first tap) sends a lightweight *preview* selection; confirming
(second tap / A / Enter / number key again) sends the real
`{ action = "play", index = n }`. Until the snap, a new confirm simply replaces
the old one (last-wins, §5.7).

**Input paths:**

| Action | KB/M | Gamepad | Touch |
|---|---|---|---|
| Switch category tab | Q / E (or ← →) | LB / RB | tap tab |
| Move card focus | 1 / 2 / 3 or mouse hover | D-pad left/right | tap card (= focus + preview) |
| Confirm play | same number again, or click | A | tap focused card again |
| Repeat last play | R | Y | REPEAT button |
| Coach suggestion | C | X | COACH button |
| Dismiss/peek field | Tab (hold) | hold LT | drag panel down |

Keys 1–5 at the line are **retired** in favour of 1–3 within a page — the
muscle-memory loss is accepted because 15 plays cannot live on 5 keys; `REPEAT`
(R) covers the "fast re-snap" habit the 1–5 flow served. Touch targets are
≥ 1 cm² and the panel honours the existing phone-vs-tablet relayout used by the
try picker.

**What teammates see:** no panel. On the QB's *confirm*, the server rebroadcasts
the play (existing behaviour) and each offensive client draws **its own route**
as the existing pre-snap ghost line, updating live if the QB re-confirms a
different play. Receivers' own route override stays exactly as built, applied on
top of the called play (§5.3). **Defensive clients receive the formation only**
(they see bodies line up); the play index is never replicated to them (§3.9).

**What the QB sees after confirm:** the panel collapses to a one-line banner
("MESH RAIL — snap when ready") so the field is clear; reopening (Tab/LT/drag)
is allowed until the snap.

### 3.7 Card route-tree rendering (client)

The client already has route points. A card renders them with a fixed affine
projection from field space to card space — no art assets needed:

- Card body is a stylized half-field: LOS at 15% from the bottom, 24 m of depth
  to the top, full 22.86 m width.
- For each of the 4 roles (2v2: 1): plot alignment dot at the formation offset,
  then the route polyline (alignment + each route point, lateral mirrored for
  left-aligned players), with an arrowhead on the final segment.
- Role colours fixed and consistent everywhere (X red, Z blue, SLOT yellow,
  RB green); the QB dot is white, no route.
- Routes deeper than the card's 24 m window draw to the top edge with the
  arrowhead pinned there (reads as "go").
- Line width ≥ 3 px at 1080p and ≥ 4 px on phones; this is the readability
  budget that caps plays at 4 routes and cards at 3 per row.

### 3.8 Server validation (authority unchanged)

On `{ action = "play", index = n }` the server checks, in order: sender is the
QB; game state is pre-snap (play not live); `n` is an integer index present in
the active mode's table (`plays5`/`plays2`); the play's `tryOnly` matches the
current down (nil on normal downs; equals the declared try value on a try).
Any failure: refuse silently, count in `stats.badPlayCall`, and keep the
previous call. The existing `rev`-style staleness philosophy applies: an intent
arriving after the snap is refused, not queued.

### 3.9 Timing, anti-stall, and the play clock

- The play-call window opens when the ball is spotted and runs on the **existing
  auto-snap play clock** (knob `playClock`, default 20 s). Browsing never pauses
  it.
- At `warnAt` (5 s) the panel pulses and the HUD clock turns amber.
- At 0, **auto-call**: the server calls `REPEAT` (last play) if one exists this
  possession, else the COACH pick (§4.3), then snaps per the existing auto-snap.
  Reason string to the whole offense: `"CLOCK RAN OUT — COACH CALLED <NAME>"`.
  No yardage penalty — in a 6–10 minute Roblox match, delay-of-game yardage
  punishes new players for reading the UI; the stolen choice *is* the cost.
  (Owner may flip `autoCallPenalty` on later; it is a knob, not a rewrite.)
- A confirmed call cannot be "un-called", only replaced; the snap locks it.

### 3.10 Counterplay and readability (the defense's experience)

- **The pick is secret; the formation is not.** Formation is honest information
  — TRIPS means flood, BACKS means a wheel threat. That is the designed tell,
  and it is why plays are bound to formations instead of all running from SPREAD.
- **Tendencies are the second tell.** Nothing hides repetition: a QB who calls
  MESH RAIL every down *should* get jumped. Per Sirlin, countering a habit is
  healthy mastery; the playbook's job is only to make sure a counter exists for
  every play (each category attacks a different defensive answer, §5.10).
- **No UI leak:** route ghosts render on offensive clients only; the play index
  and route table for the live play are not sent to defensive clients until the
  snap (post-snap they see the routes run, which is the game).
- **Reason strings** (pillar: "I know exactly why I lost"), added where the call
  directly produces the outcome: `"CLOCK RAN OUT — COACH CALLED <NAME>"` (§3.9);
  `"SACKED — RUSHER HOME, BALL NEVER OUT"` when the existing 3.2 s rusher ends
  the play with no throw; `"<NAME> — <player> ON THE <ROUTE>"` on every
  completion banner; and `"ROUTE CHANGED — QB THREW THE CALLED SPOT"` when a
  receiver override moved the target away from where the called route (and the
  QB's throw) went (§5.3).

---

## 4. Formulas

### 4.1 Route timing vs the rush and the arm

Receiver ground speed in team mode is `wrSpeed 9.6 m/s` (sprint-button value;
`carrySpeed 9.0` after the catch), with the Momentum-style accel making the
first ~0.6–0.8 s partial. Approximate time to a break at depth `d` (straight
stem): `t(d) ≈ 0.4 + d / 9.6` (0.4 s is the accel deficit, to be measured per
Definition-of-Done rather than trusted).

| Break | Depth | t(break) | vs rusher (3.2 s) |
|---|---|---|---|
| slant | ~4 m | ≈ 0.8 s | ball out long before pressure — QUICK page |
| out | 7 m | ≈ 1.1 s | quick |
| dig | 10 m | ≈ 1.4 s | intermediate — thrown at ~1.5–2.0 s |
| comeback | 12 m | ≈ 1.7 s | intermediate |
| sluggo 2nd move | 6 m → go | move at ≈ 1.0 s | deep — see 4.2 |

### 4.2 The deep-shot window (why VERTS plays are a risk/reward)

Deep ball: arm `27 m/s`, hang `2.15 s` (team-mode values per owner priority).
A vertical receiver at 9.6 m/s is at depth `9.6·(t−0.4)` when the ball must be
*thrown* at `t_throw = t_arrive − 2.15`. For the ball to arrive at ~27 m depth:
receiver reaches 27 m at `t ≈ 3.2 s`; the QB must release at `t_throw ≈ 1.1 s`
*leading* him, or hold to `t ≈ 2.8–3.1 s` and throw to ~32 m arriving at ~5 s —
**inside or just past the rusher's 3.2 s crossing time**. Example calculation,
SLUGGO SHOT: second move at ~1.0 s, corner bitten for ~0.5 s, separation window
~1.5–3.0 s; a release at 2.9 s is 0.3 s *after* the rusher may cross — the deep
page structurally trades pressure risk for separation. That is the intended
curve; the tuning anchors are `rusherCross 3.2 s`, `armMax 27 m/s`,
`deepHang 2.15 s`, and route terminal depths (26 m), and they must be tuned
together (see Tuning Knobs).

### 4.3 COACH / AI QB play selection

The AI QB and the COACH button use the same weighted pick over the legal plays:

    w(play) = base[category] · downMod(down) · distMod(toGain)
    P(play) = w(play) / Σ w                     -- cumulative sample

| Variable | Default | Meaning |
|---|---|---|
| `base` | QUICK 1.0, CROSSERS 0.9, VERTS 0.6, MISDIRECTION 0.5, GOALLINE 0 (unless inside 10 m: 1.2), SPECIALS 0 (unless try: 1) | category priors |
| `downMod` | down 4 and > 8 m to gain: VERTS ×1.6; down 1: ×1.0 all | desperation shifts deep |
| `distMod` | toGain ≤ 4 m: QUICK ×1.4; toGain ≥ 15 m: VERTS ×1.3, QUICK ×0.7 | distance realism |

Worked example — 4th down, 12 m to the midfield line: VERTS weight
`0.6·1.6·1.3 = 1.25` vs QUICK `1.0·1.0·0.7 = 0.7`; across the book VERTS plays
are each ≈ 1.8× as likely as a quick-game play. The RNG picks a *choice*, not an
outcome, so the determinism pillar is intact; for harness tests the sampler
takes a seed so distributions are reproducible.

### 4.4 Card projection

For a field point `(x, y)` (lateral, downfield from the snap spot) on a card of
pixel size `(W, H)`:

    px = W/2 + x · (W / 22.86)
    py = H · 0.85 − y · (H · 0.85 / 24)        -- LOS at 15% from the bottom; 24 m visible
    py = max(py, H · 0.05)                     -- deep arrows pin to the top margin

Inputs: `x ∈ [−11.43, 11.43]`, `y ∈ [−4, ∞)`. Output is always inside the card.

## 5. Edge Cases

1. **QB leaves/disconnects mid-pick.** Server closes the window on all clients,
   promotes the next offensive player to QB per the existing role-assignment
   order, restarts the play clock at `max(remaining, 8 s)`, and reopens the
   screen for the new QB. If no human remains, the AI QB (§4.3) calls and plays.
2. **AI QB.** Picks from the same table via §4.3 at a fixed `aiCallDelay 2.0 s`
   after spot — never instant, so humans can read the formation forming.
3. **Receiver route override.** Unchanged and still legal after the call: the
   override replaces that player's route in the server's play state and is
   rebroadcast (existing behaviour). The QB's banner marks overridden roles with
   a ⟲ glyph. If the QB's throw resolves at the *called* route's spot after an
   override, the incompletion reason is `"ROUTE CHANGED — QB THREW THE CALLED
   SPOT"` — both players learn why, nobody is lied to.
4. **Play intent with invalid index / wrong mode / not QB / post-snap.** Refused
   silently, counted in `stats.badPlayCall`; previous call (or none) stands.
5. **Try downs.** When the existing try picker declares 1 or 2, the screen opens
   with only the matching `tryOnly` plays (plus — owner option, default off —
   the GOALLINE page for variety). A `tryOnly` play is refused on a normal down
   and vice versa (§3.8). Declared 1-pt tries are pass-only by rule; every play
   in the book is a pass, so no extra validation is needed.
6. **2v2 mode.** `plays2` table, one route per card, no tabs. Same intent, same
   validation, same auto-call. A `plays5` index sent in 2v2 is case 4.
7. **Two confirms before the snap.** Last-wins; the rebroadcast updates every
   teammate's ghost. There is no penalty for re-calling — hiding intent by
   re-calling late is legitimate play.
8. **Route deeper than the remaining field.** At play start the server clips
   every route point's downfield value to `(distance to end line − 1 m)` and
   laterals to ±10.5 m; a fully clipped vertical becomes a fade to the back
   line. Cards do not re-render for this (the card is the concept; the field is
   the truth).
9. **Formation near a sideline/goal line.** Formation laterals clamp to
   ±10.5 m; depths clamp so no one starts in the end zone. Clamping never
   reorders players across each other.
10. **Degenerate strategies.** (a) *Spam the best play*: countered by
    information, not rules — formations are visible and tendencies readable
    (§3.10); balance passes must keep every category's expected value within
    ~15% of the book mean or a dominant pick emerges. (b) *Stall in the
    playbook*: impossible — the play clock runs and auto-calls (§3.9).
    (c) *Call VERTS every down*: self-punishing via the §4.2 pressure window so
    long as `rusherCross` stays at or below ~3.4 s — flag any rusher-timing
    retune to this doc. (d) *Receiver overrides everything, playbook
    irrelevant*: acceptable — override is one player's route, not the play; if
    playtests show > 50% override rates the book's routes are wrong, which is a
    content fix, not a rules fix.
11. **Late joiner mid-pick.** Gets the existing state sync: formation and roles
    immediately; if on offense, their own route ghost on the next rebroadcast
    (the server re-sends the current call to a joining offensive client); if on
    defense, nothing but the formation, same as everyone.
12. **A category with zero legal plays** (e.g. SPECIALS off-try): tab hidden,
    never an empty page. If a config error empties *all* tabs, the screen shows
    the COACH button alone and logs a warning — the game must never be unable
    to call a play.

## 6. Dependencies

| System | Direction | Contract |
|---|---|---|
| `TeamFootballService` | **owns this system** | Holds play state; validates `{ action="play", index }` (§3.8); runs play clock + auto-call; clips routes (§5.8); rebroadcasts calls to the offense only. The 5-play tables are replaced by reads of `Config.playbook`. |
| `AWFootball.Config` | this system lives in it | New `playbook` table (§3.1): plays, formations, all 12 route point sets, and every knob in §7. Pays down debt C1 (values out of `TC`). |
| `TeamFootballClient` | consumes | Renders the panel, tabs, cards (§3.7 projection), input paths, route ghosts; sends preview + confirm intents. |
| Existing HUD (series bar, clock, try picker) | bidirectional | Try picker's declared value selects the `tryOnly` page (§5.5); play clock display gains the `warnAt` amber state. |
| AI QB (`Config.qb`) | consumes playbook | §4.3 weighted pick replaces nothing — it feeds the existing dropback/read/deadline AI a play instead of the old fixed list. |
| Routes/receiver override (built) | preserved | Override semantics unchanged (§5.3); overrides never mutate the playbook table. |
| Sprint button + bigger "Yard" field (coming) | tuned against | Deep depths (26 m terminals) and §4.2 windows assume sprint ≈ 9.6 m/s; field growth is absorbed by §5.8 clipping, not by new route data. |
| `football-core.md` | design parent | Authority model (§6.4 there), reason-string pillar (§2 there). That doc's §3.11 "play-selection timeout" proposal is **implemented by this doc** and should be marked so on its next edit. |
| DRIP STORE (future) | must not touch | No playbook value may be purchase-linked; card *cosmetics* (skins/colours) are the only legal store surface. |
| ux-designer | coordinate | §3.6–3.7 is the design intent; the per-screen spec belongs in `design/ux/play-call-screen.md`. |

## 7. Tuning Knobs

All in `AWFootball.Config.playbook`, never hardcoded.

| Knob | Default | Safe range | Category | Affects |
|---|---|---|---|---|
| `playClock` | 20 s | 15–30 | gate | Pace between downs; below 15 s phones can't browse |
| `warnAt` | 5 s | 3–8 | feel | Panel pulse / amber clock |
| `autoCallMode` | `repeat-then-coach` | enum: repeat-then-coach / coach / holdLast | gate | What fires at 0 (§3.9) |
| `autoCallPenalty` | off | off / −5 yd | gate | Owner's delay-of-game option |
| `aiCallDelay` | 2.0 s | 1–4 | feel | AI QB call pacing (§5.2) |
| `cardsPerPage` | 3 | 3–4 | feel | Readability budget (§3.7); 4 only on tablet+ |
| `coachWeights` (`base`, `downMod`, `distMod`) | §4.3 values | ±50% per entry | curve | COACH/AI play mix |
| `routes.*` points | §3.3 + built values | laterals ≤ 10.5 m; depths ≤ 30 m | curve | Every route shape; deep terminals pair-tuned with `rusherCross` |
| `deepTerminal` (fade/seam/sluggo/wheel) | 26 m | 20–30 | curve | The §4.2 risk/reward window — **retune whenever `armMax`, `deepHang`, sprint speed or `rusherCross 3.2 s` changes** |
| `previewThrottle` | 0.2 s | 0.1–0.5 | gate | Min interval between preview rebroadcasts (spam guard, rides the existing 12/s token bucket) |

## 8. Acceptance Criteria

Functional (harness, `tests/roblox/playbook/`, pure-Luau where possible —
PASS lines retained as evidence per `DEFINITION-OF-DONE.md`):

- [ ] **Table integrity**: every play in `plays5`/`plays2` has a name ≤ 14
      chars, a category from the 6, a formation key that exists, and routes
      drawn only from the 12-route pool; every route point obeys the §7 bounds.
      15 plays in `plays5`, 6 in `plays2`, exactly 3 `tryOnly` plays.
- [ ] **Validation**: non-QB sender, out-of-range index, wrong-mode index,
      post-snap intent, and `tryOnly` mismatch are each refused and increment
      `stats.badPlayCall`; a legal call replaces the previous one (last-wins).
- [ ] **Wire format unchanged**: the only client→server play message is
      `{ action = "play", index = n }`; a pre-playbook client sending index 1–5
      still calls a legal play.
- [ ] **Auto-call**: with no call, the server calls REPEAT-then-COACH exactly at
      `playClock` 0 and emits `"CLOCK RAN OUT — COACH CALLED <NAME>"`.
- [ ] **COACH distribution**: 1000 seeded picks at (4th down, 12 m to gain)
      match §4.3 within ±3% per category; the same seed gives the same sequence.
- [ ] **Clipping**: a FOUR VERTS call snapped 10 m from the goal line produces
      routes whose every point is ≥ 1 m short of the end line and within
      ±10.5 m lateral.
- [ ] **Secrecy**: packet inspection (or a logging client) confirms defensive
      clients receive no play index or route data before the snap.
- [ ] **Edge cases 1, 5, 6, 11**: scripted QB-leave, try filtering, 2v2 book,
      and late-join each behave exactly as §5 states.

Experiential (playtest + retained screenshots in `production/qa/evidence/`,
UI stories BLOCKING per coding standards):

- [ ] Screenshots of the panel on KB/M, gamepad glyphs, phone and tablet
      layouts; every card's route tree readable at arm's length on a phone.
- [ ] A first-time QB on touch can find and call a named play in ≤ 8 s; a
      practiced one in ≤ 4 s (REPEAT in ≤ 1 s).
- [ ] Teammates' route ghosts update within 0.5 s of the QB's confirm
      (micro-feedback budget), observed on a second client.
- [ ] Across a full 5v5 playtest match, every play-ending outcome shows a
      reason string; no outcome occurs "for no visible reason"
      (Definition-of-Done section D).
- [ ] Deep page feels like a gamble: in playtest logs, VERTS completion rate
      sits meaningfully below QUICK but yards-per-completion meaningfully above
      — if either inverts, retune §4.2 anchors before ship.

### Known limitations (design-time)

- Pre-snap motion is **not** in this draft — "misdirection" is achieved through
  route geometry only. True motion needs movement-before-snap rules (false-start
  interaction) and is deferred to the owner.
- No audibles/hot-route *menu* for the QB (receivers keep their own override);
  a QB-side hot-route UI is a natural v2 of this screen.
- Formation mirroring (RT/LT flip) is specced in data (`mirrored`) but the UI
  flip control is v2; draft 1 ships RT versions only.
