# Football Broadcast UI — ESPN/NFL-Style Presentation Skin

> **Status: DESIGN DRAFT 1 — 2026-11-02. Nothing in this document is built.**
> Owner brief: *"I like a better UI, like a sports UI, like ESPN, NFL. It's
> getting there but it's just visuals."*
> Engine: Roblox (Luau). Units: **pixels at 1080p reference scale** (`k = 1`),
> scaled by the existing `viewK()` rule. Baseline measured from the real client:
> `src/football/team/TeamFootballClient.client.lua` (mirror, 2026-11-02,
> post feature-wave-2 + ankle-breaker). This is a **presentation skin** — no
> gameplay rule, remote, or server message changes. Every element keeps its
> existing data source; only chrome, layout and event routing change.

---

## 1. Overview

This system replaces the current generic scoreboard (`board`, 440×80 top-center)
and series strip (`seriesF`, 520×56 below it) with a single broadcast-style
**score bug** — one anchored top-center bar carrying team blocks, scores,
possession, down & distance, half and clock — and routes the game's big moments
(TOUCHDOWN, TRY GOOD, BREAKAWAY, ANKLE BREAKER, INTERCEPTION, FINAL) through
**lower-third banners** instead of the center message label. The pre-snap
play-call dashboard and try picker adopt the same card chrome so the whole HUD
reads as one broadcast package. A **clean-feed rule** defines exactly what is on
screen while the ball is live. Implementation is cut into two passes: pass 1 is
the score bug + lower thirds; pass 2 is chrome unification and clean-feed
polish. All of it is client-only (`TeamFootballClient` plus the existing
`AWBroadcast`/`ScoreBug` ScreenGui path the series strip already docks under).

## 2. Player Fantasy

**"I'm on TV."** The player should feel like their 5v5 match is being broadcast:
a permanent, professional score bug that always answers *score, down, distance,
clock* at a glance; big plays celebrated with the slide-in banner a real network
would use; nothing amateur floating mid-screen. For the owner's pillars this is
P1 support ("I know exactly why") delivered through *information hierarchy* —
the right fact in the same place every time — and the macro-loop reward beat the
animation reference names (its §2.2 item 8: moment presentation is the cheapest
perceived-quality win). MDA: **Sensation** (broadcast sting on big plays) and
**Challenge** support (down/distance/clock never ambiguous).

## 3. Detailed Design

### 3.0 Palette, type and chrome language (shared by every element)

Carried from the existing client, with two additions:

| Token | RGB | Use |
|---|---|---|
| `NAVY` | (7, 16, 28) | panel bodies (bug, cards, lower thirds) |
| `GOLD` | (255, 191, 58) | AWAY team, accents, stopped clock, strokes |
| `BLUE` | (70, 150, 255) | HOME team |
| `WHITE` | (255, 255, 255) | primary text, live clock |
| `MUTED` | (170, 182, 200) | secondary labels |
| `GOOD` | (90, 220, 120) | positive feedback |
| `BAD` | (255, 95, 70) | negative feedback, red-zone accent |
| `NAVY_LIGHT` *(new)* | (16, 32, 54) | card inner cells, bug cell separation |
| `SHEEN` *(new)* | UIGradient, white → transparent, vertical, 0.92 → 1.0 transparency | top 25% of bug/lower-third bodies — the "glass" broadcast look |

- **Fonts:** `GothamBlack` for every numeral and headline; `GothamBold` for
  labels and sublines. No other fonts anywhere in the football HUD.
- **Chrome:** `BackgroundTransparency = 0.05` on the bug and lower thirds
  (solid broadcast read — the current 0.18 is too ghostly for a score bug);
  0.18 stays acceptable for secondary panels. `UICorner` 10 px on bars,
  12 px on cards (matches the existing `panel()` helper). `UIStroke` GOLD,
  2 px, transparency 0.35, `Border` mode. Roblox has no drop shadow — the
  stroke + SHEEN gradient is the whole depth treatment; do not fake shadows
  with offset frames (doubles the element count on phones).
- **Scale:** every broadcast element carries a `UIScale` driven by the existing
  `viewK()` = `clamp(min(vpX/1100, vpY/640), 0.55, 1)`. Nothing defines its own
  scale rule.

### 3.1 The score bug — one bar, top center

**Anchor decision.** Top-center, `AnchorPoint (0.5, 0)`,
`Position UDim2.new(0.5, 0, 0, 12)`. Recommended over bottom-left because
(a) the bottom edge is already owned by touch controls, prompt, chips, try
picker and the play-call dashboard — a bottom bug would fight five elements;
(b) the current build's eye-line is already trained top-center (`board` and
`seriesF` both live there, and the `AWBroadcast.ScoreBug` docking logic at
client line 446–453 assumes a top bug of ~88 px); (c) ESPN's college/top-strip
convention reads identically. Anchoring is a knob (§7) if the owner prefers the
NFL-on-FOX bottom bar later.

**Size:** 640 × 56 px at `k = 1`. At `k = 0.55` (small phone): 352 × 31 px.

**Segment layout, left → right (x offsets at `k = 1`):**

| Zone | x range | Contents | Spec |
|---|---|---|---|
| HOME block | 0–150 | team color tab, abbreviation, score, possession dot | 6×40 px BLUE tab inset (8,8); abbr `GothamBlack` 22 px WHITE at x 20, width 60, left-aligned; score `GothamBlack` 34 px WHITE right-aligned, width 52; timeout dots row under abbr (below) |
| divider | 152 | 2 px GOLD, transparency 0.5, height −14 | matches existing `sdiv` treatment |
| DOWN & DISTANCE cell | 156–366 | `"2ND & MIDFIELD"` / `"2ND & GOAL"` / `"TRY +2"` / `"FINAL"` | `GothamBlack` 22 px WHITE on `NAVY_LIGHT` cell (inset 2 px, corner 6); accent states §3.1.3 |
| CLOCK cell | 370–484 | half label over clock | `"2ND HALF"` / `"OVERTIME"` `GothamBold` 12 px MUTED top; clock `GothamBlack` 26 px below — WHITE running, GOLD stopped (keep the existing semantic exactly) |
| divider | 486 | as above | |
| AWAY block | 490–640 | mirror of HOME (tab on the right edge, GOLD) | score left-aligned, abbr right-aligned |

**Possession arrow:** a 10 px GOLD football-shaped dot (circle is acceptable
pass 1) sitting between the possessing team's abbr and score; hidden for the
other team. Data: `h.offense` (already in every hud message).

**Team abbreviations:** `"HOM"` / `"AWY"` from the existing `TEAMNAME` map
pass 1; real club abbreviations when Clubs ship. ≤ 3 characters, hard rule —
the cell does not grow.

**Timeout dots (future):** room is reserved now — a row of `timeoutsPerHalf`
(config: 2) 6 px circles under each abbr at y 44; WHITE filled = remaining,
NAVY_LIGHT outline = used. Rendered only when the server sends `h.timeouts`
(it does not today — the cell stays empty, costing nothing).

#### 3.1.1 Down & distance strings

Generated by the **existing** `seriesText()` logic unchanged; the bug shows its
`main` value, uppercased, with the ordinal compacted (`"2nd & TO MIDFIELD"` →
`"2ND & MIDFIELD"` — drop the word "TO", it is broadcast convention and buys
~34 px). The long `tag` line ("CROSS MIDFIELD FOR YOUR ONE FIRST DOWN") moves
to the **pre-snap ticker** (§3.1.2) — it must not live in the bug; it is
coaching copy, not score-bug copy.

#### 3.1.2 The pre-snap ticker

A 520 × 20 px GOLD-text strip (`GothamBold` 14 px, NAVY body transparency
0.25, corner 6) directly under the bug (y = 12 + 56·k + 4). Shows, in priority
order: the series tag line; the final-window "CLOCK STOPS ON …" content
(absorbing the existing `stopF` bar); flag summary one-liner while the flag
card is up. **Visible only when the ball is dead** (`h.state ~= "live"` and no
flight). This is where every sentence-length rules explanation now lives.

#### 3.1.3 Accent states

| State | Trigger (existing client data) | Treatment |
|---|---|---|
| **Red zone** | series `goal == true` (from `seriesInfo`) | 3 px BAD underline bar inside the down & distance cell; text stays WHITE |
| **Try** | `type(h.try) == "table"` | cell flips to GOLD background, NAVY text: `"TRY +1"` / `"TRY +2"` (declared), `"TRY · DECLARE"` during the declare phase |
| **Breakaway** | the feel-upgrades breakaway banner event [ASSUMPTION — message kind TBD by that doc's implementation] | bug UIStroke pulses GOLD→WHITE at 2 Hz for the banner duration; nothing inside the bug changes (live play — minimal) |
| **Final** | `h.state == "final"` | cell shows `"FINAL"`; clock cell shows the half label only |

### 3.2 Lower thirds — the big-moment channel

Two variants, chosen by whether the ball is dead. This single rule keeps the
clean feed (§3.4) self-enforcing: full banners physically cannot cover live
play.

**A. Full lower third (dead ball only).** Frame `AnchorPoint (0.5, 1)`,
`Position UDim2.new(0.5, 0, 1, -270)` (above the try picker at −160 and the
prompt at −150, clear of both touch clusters), size 520 × 64 px. Anatomy:
8 px accent bar flush left (event color), NAVY body (transparency 0.05) +
SHEEN, headline `GothamBlack` 28 px WHITE, subline `GothamBold` 15 px MUTED.
Motion: slides in from x −600 offset over 0.3 s `Back/Out` (same easing family
as the existing flag card), holds (table below), slides out 0.2 s `Quad/In`.
One at a time; a new event replaces the current one instantly.

**B. Live sting (ball live).** Slim bar `AnchorPoint (0.5, 0)` docked directly
under the score bug (y = bug bottom + 4), 320 × 36 px, headline only
(`GothamBlack` 20 px), same accent-bar anatomy, slide-down 0.2 s, hold 1.4 s.

| Event | Variant | Accent | Headline / subline | Hold |
|---|---|---|---|---|
| TOUCHDOWN | full | scoring team color | `"TOUCHDOWN"` / `"HOME 21 – 14 AWAY"` (live score line) | 3.0 s |
| TRY GOOD | full | GOOD | `"TRY GOOD · +2"` / score line | 2.2 s |
| TRY NO GOOD | full | BAD | `"NO GOOD"` / reason string | 2.2 s |
| INTERCEPTION | full (ball is dead or possession flips) | intercepting team color | `"INTERCEPTED"` / catch reason string | 2.5 s |
| FIRST DOWN (midfield crossed) | full | GOLD | `"FIRST DOWN"` / `"GOAL TO GO"` tag | 1.8 s |
| HALFTIME / FINAL | full | GOLD | `"HALFTIME"` or `"FINAL"` / score line | 4.0 s |
| BREAKAWAY | live sting | GOLD | `"LAST MAN BEATEN"` | 1.4 s |
| ANKLE BREAKER | live sting | GOLD | `"ANKLE BREAKER"` + badge glyph [ASSUMPTION — badge payload shape pending the badges feature] | 1.4 s |
| SACK / TURNOVER ON DOWNS | full | BAD (for offense) | headline + existing reason string | 2.2 s |

**What stays a small badge instead:** catch reason strings, move feedback,
pancakes, cooldown events, movement-check messages — everything currently in
`fbL`/`fbReasonL` keeps that channel (restyled pass 2, §3.5). Rule of thumb:
a lower third marks a *scoreboard or possession consequence*; a badge marks a
*rep-level outcome*.

**Center text after this change:** `bigL` is reserved exclusively for the snap
cadence (`SET…`, `HUT!`) — unchanged, it is gameplay timing, not presentation.
`msgF` keeps only messages that are neither cadence nor a lower-third event
(lobby notices, instructional lines); every event in the table above stops
rendering through `msgF`.

### 3.3 Pre-snap: dashboard, chips, try picker adopt the card language

No layout changes — chrome only (pass 2):

- **Play-call dashboard (`pbF`)**: body to `BackgroundTransparency 0.05` +
  SHEEN; title row restyled as a tab-like GOLD strip (`"CALL THE PLAY"` left,
  page arrows right — becomes the real category tab row when the playbook GDD's
  screen ships; this doc deliberately specs only the *skin*, that doc owns the
  structure). Cards: `NAVY_LIGHT` body, selected card = GOLD stroke + GOLD
  name (already true) **plus** a 4 px GOLD top bar, so selection reads on
  phones where the stroke is 1–2 physical px.
- **Pinned/selected play confirmation**: the existing selected-card highlight
  is the pin; after the QB confirms, the dashboard's collapsed state is a
  one-line bar in lower-third anatomy (accent GOLD, `"MESH RAIL — SNAP WHEN
  READY"`), per the playbook GDD §3.6.
- **Route chips (`chipsF`, legacy fallback + receiver route row)**: same
  button chrome as cards — NAVY_LIGHT body, GOLD selected state, corner 10.
- **Try picker (`tryF`)**: already close; add the accent-bar anatomy (8 px
  GOLD bar on the selected option) and SHEEN. No behavior change.

### 3.4 The clean-feed rule

While the ball is **live** (`h.state == "live"` or a flight is active), the
screen may contain ONLY:

1. The score bug (§3.1) — never hidden.
2. Touch controls (touch devices only) — never hidden; they are input.
3. The prompt line (`promptF`) — context help, one line.
4. The timing bar (`timingF`) during flight — it is gameplay.
5. Cooldown/sprint pips (`cdF`) — gameplay state.
6. Small badges (`fbL`/`fbReasonL`) and live stings (§3.2 B).
7. World-space elements (LOS/gain lines, pylons, QB receiver tags, man ring,
   ball trail) — field truth, not HUD.

Everything else is dead-ball-only and must hide at the snap: pre-snap ticker,
play-call dashboard (already does), chips (already pre-snap-gated — the gate
becomes explicit), try picker (already), flag card (slides out at the snap if
still up), full lower thirds (cannot fire live by rule), **LEAVE button**
(pass 2: moves into dead-ball visibility only — mid-play it is both clutter
and a misclick hazard next to the throw buttons on touch).

**Mobile addendum:** at `k < 0.7`, the pre-snap ticker hides entirely (the
series tag is coaching copy phones don't have room for — the information
remains available because the same text reaches `promptF` context lines when
relevant [ASSUMPTION — verify prompt coverage in playtest]); lower-third
sublines drop to 13 px, never below.

### 3.5 Migration map — every existing element

| Existing element (client ref) | Pass | Verdict | What it did → where that job goes |
|---|---|---|---|
| `board` "Scoreboard" (440×80) + `homeS/awayS/downL/possL` | 1 | **replaced** | score/teams/down/possession → score bug. `roleL` ("YOU: WR · AWAY (offense)") has **nowhere in the bug** — it moves to a small role chip, `GothamBold` 14 px, bottom-left above the prompt, dead-ball only. Flagged: do not silently drop it; it is the only place a new player learns their role |
| `seriesF` "SeriesStrip" (+ `seriesL/seriesTag/halfL/clockL`) | 1 | **absorbed** | down & distance + clock/half → bug cells; tag line → pre-snap ticker; the `placeRules()` docking logic is retired with it |
| `stopF` final-window bar | 1 | **absorbed** | content → pre-snap ticker (same strings, built from `CFG.clock.stopOn` exactly as today) |
| `msgF`/`msgL` center message | 1 | **reduced** | big events → lower thirds; residue (non-event notices) stays |
| `bigL` (SET…/HUT!) | — | **kept as-is** | cadence timing; broadcast skin never touches it |
| `fbL` + `fbReasonL` feedback | 2 | **restyled** | same position/data; gains NAVY badge body + accent bar instead of bare stroked text |
| `flagF` flag card | 2 | **restyled** | already lower-third-shaped (slide-in, accent bar); unify measurements with §3.2 anatomy; top-left position kept (real broadcasts put flags separate from score events) |
| `timingF` + `windowF` timing bar | 2 | **restyled** | chrome only: corner 10, NAVY_LIGHT track, GOLD window as-is — the Config-driven window math is untouched |
| `chipsF` chips | 2 | **restyled** | card chrome (§3.3); behavior identical |
| `pbF` play-call dashboard + cards | 2 | **restyled** | §3.3; structure owned by football-playbook.md |
| `tryF` try picker | 2 | **restyled** | §3.3 |
| `cdPips` cooldown + sprint pips | 2 | **restyled** | corner 10, `GothamBold`; colors unchanged (GOOD sprint-on / GOLD recover is a learned semantic) |
| `leaveB` LEAVE | 2 | **moved** | dead-ball-only visibility (§3.4); position unchanged |
| touch buttons (`goB/fB/rB/...`) | 2 | **restyled only** | stroke + font pass; sizes/positions are muscle memory, frozen |
| lobby panel | 2 | **restyled** | same chrome tokens; out of scope otherwise |
| `toast()` | 2 | **restyled** | lower-third anatomy, top position kept |
| world visuals (ball, trail, LOS, pylons, tags, ring) | — | **untouched** | field truth; the gold trail is also a cosmetics surface — see cosmetics.md §3.4 |
| `AWBroadcast.ScoreBug` (separate ScreenGui, referenced at client 446–453) | 1 | **superseded** | whichever script owns it adopts this spec or is disabled; two score bugs must never render at once — acceptance F1 |

### 3.6 Two-pass implementation plan

**Pass 1 — the broadcast spine** (ship together, one story each):
1. Score bug replacing `board` + absorbing `seriesF`/`stopF` (+ role chip).
2. Lower-third system + event routing table + live stings; `msgF` reduction.

**Pass 2 — chrome unification**: ticker polish, flag/feedback/timing/chips/
dashboard/try/pips restyle, LEAVE gating, toast restyle, clean-feed audit.

Pass 1 is self-contained and visibly "the new UI"; pass 2 is mechanical
restyling with zero new logic. Nothing in pass 2 blocks pass 1.

## 4. Formulas

### 4.1 Scale and derived sizes

    k = clamp(min(vpX / 1100, vpY / 640), 0.55, 1)        -- existing viewK()
    bugW, bugH   = 640·k, 56·k
    tickerY      = 12 + 56·k + 4
    stingY       = tickerY                                 -- sting and ticker never co-visible (sting is live-only)
    lowerThirdY  = viewport.Y − 270·k

| Variable | Range | Meaning |
|---|---|---|
| `vpX, vpY` | ≥ 320 px | viewport size |
| `k` | 0.55–1.0 | global HUD scale |

Worked example — iPhone-class 844×390 viewport: `k = min(844/1100, 390/640) =
min(0.767, 0.609) → 0.609`. Bug = 390×34 px; clock text ≈ 16 px; abbr ≈ 13 px —
above the 12 px readability floor (§8 E2 verifies on device).

### 4.2 Lower-third motion

    in:   Position.X from −(W + 40) offset → anchor, 0.3 s, Back/Out
    hold: per-event table (§3.2), range 1.4–4.0 s
    out:  anchor → +(W + 40), 0.2 s, Quad/In
    replace: a new event skips `out` and plays its own `in` immediately

## 5. Edge Cases

1. **Two events in one dead ball** (TD then try declare): the TD lower third
   holds its 3.0 s; the try picker opens concurrently at −160 — the 270 px
   anchor gap means no overlap at any `k`. If a TRY GOOD fires while the TD
   banner is still up, replace-rule applies.
2. **Breakaway that ends in a TD**: live sting (1.4 s) may still be up at the
   whistle; the TD full lower third replaces it (different slots — sting top,
   full bottom — so "replace" = sting force-out at whistle).
3. **Flag during a lower third**: flag card is top-left, lower third bottom
   center — both render; the ticker shows the flag one-liner next dead ball.
4. **`h.series` absent (old server)**: `seriesText()` fallback parsing already
   handles it; the bug renders whatever `main` string results. Never blank —
   if both structured and parsed fail, the cell shows `h.down` raw (today's
   behavior).
5. **Overtime**: clock cell half-label shows `"OVERTIME"` (existing `ot`
   logic); down cell unchanged.
6. **Spectator/lobby**: bug renders only in `mode == "game"` (same gate as
   `hudF` today). The lobby keeps its own panel.
7. **`AWBroadcast` ScoreBug also enabled**: pass 1 must detect and disable one
   (acceptance F1). The new bug wins; the old docking offset logic is deleted.
8. **Very long reason strings** on sublines: `TextTruncate = AtEnd` at one
   line; the full string still reaches `fbReasonL` (badges channel) so nothing
   is lost.
9. **Colorblind check**: possession is shown by dot *position* (next to the
   possessing team), not color alone; clock stopped-state is GOLD **and** the
   ticker says why the clock stopped in the final window; red-zone accent is
   an underline position cue, not only red. No information is color-only.
10. **Flashing**: the breakaway stroke pulse is 2 Hz, well under photosensitive
    thresholds; no element strobes faster than 3 Hz anywhere in this spec.

## 6. Dependencies

| System | Direction | Contract |
|---|---|---|
| `TeamFootballClient` | owns rendering | all elements live here; data sources (`h.*`, `CFG.*`) unchanged |
| `TeamFootballService` | upstream, unchanged | no new server messages required for pass 1; INT/first-down/sack lower thirds consume existing `h.feedback`/`h.message` events. [ASSUMPTION] a structured `h.event = {kind, team, detail}` field is cleaner — request, don't require |
| `AWBroadcast` ScoreBug | superseded | §3.5 last row; one bug on screen, ever |
| `AWFootball.Config` | reads | clock/scoring/penalty/catch windows — exactly the keys the client reads today |
| `football-playbook.md` | pairs | §3.6 there owns play-call screen *structure*; this doc owns its *skin tokens* |
| `football-feel-upgrades.md` | pairs | breakaway/ankle-breaker events, first-down signal beat (#10 there) — their reason strings are this doc's banner copy |
| `cosmetics.md` | pairs | banner/badge *styles* are a cosmetic surface; ball-trail recolor must preserve the white catch-window flip this HUD relies on |
| ui-programmer | implements | this doc is the build spec; measurements are at `k = 1` |
| accessibility (`design/accessibility-requirements.md`) | constrains | §5.9–5.10 here; UI scales at all resolutions via `viewK` |

## 7. Tuning Knobs

Client-side table (`BroadcastUI.Config` in the LocalScript or a ModuleScript),
never hardcoded inline:

| Knob | Default | Safe range | Affects |
|---|---|---|---|
| `bug.anchor` | `"top"` | top / bottomLeft | §3.1 anchor decision reversal |
| `bug.width` | 640 | 560–720 | bug footprint; below 560 the down cell truncates |
| `bug.opacity` | 0.95 | 0.8–1.0 | broadcast solidity |
| `lowerThird.holds` | §3.2 table | 1.0–5.0 s each | event pacing |
| `lowerThird.y` | −270 | −320…−220 | collision margin vs try picker (−160) |
| `sting.hold` | 1.4 s | 1.0–2.0 | live sting duration |
| `ticker.minK` | 0.7 | 0.6–0.85 | phone cutoff for the ticker |
| `pulse.hz` | 2 | 1–3 | breakaway stroke pulse (hard cap 3 — §5.10) |
| `scale.clamp` | 0.55–1.0 | floor ≥ 0.5 | global `viewK` bounds (shared, change with care) |

## 8. Acceptance Criteria

Functional (Command Bar harness where pure-Luau applies, else playtest —
PASS lines / evidence retained per `DEFINITION-OF-DONE.md`):

- [ ] **F1 one bug**: with `AWBroadcast` present and enabled, exactly one score
      bug renders; the series strip and old board no longer exist in the tree.
- [ ] **F2 string parity**: for a scripted sequence of hud messages (downs 1–4,
      goal-to-go, try declare/declared, final, OT), the bug's down cell shows
      exactly the §3.1.1 strings; clock gold-when-stopped preserved.
- [ ] **F3 event routing**: each §3.2 table event produces its banner variant
      exactly once, with the stated accent color and hold; none of them renders
      through `msgF` anymore; `SET…`/`HUT!` still render through `bigL` only.
- [ ] **F4 clean feed**: at the snap, every §3.4 dead-ball element is invisible
      within one frame; a full lower third never appears while live.
- [ ] **F5 no data change**: packet/log inspection shows zero new client→server
      intents and zero required new server fields for pass 1.

Experiential (retained screenshots in `production/qa/evidence/` — UI stories
BLOCKING):

- [ ] **E1** screenshots: bug + ticker at `k = 1`, `k ≈ 0.6` (phone), and
      tablet; try state, red-zone state, final state.
- [ ] **E2** on a real phone, every bug text readable at arm's length; abbr and
      clock ≥ 12 physical px.
- [ ] **E3** screenshot sequence of a TD: live play (clean feed) → whistle →
      lower third in → try picker opening below it, no overlap.
- [ ] **E4** breakaway sting during live play covers no gameplay-relevant field
      area (clip retained).
- [ ] **E5** a new playtester can answer "score, down, time left, who has the
      ball" within 3 seconds of looking, on phone — ask, don't infer.
