# Cosmetics & DRIP STORE — ALLSTAR WORLD

> **Status: DESIGN DRAFT 1 — 2026-11-02. Nothing in this document is built.**
> Owner brief: *"I do want to add cosmetics into there. It would be cool."*
> Engine: Roblox (Luau). **Hard law carried from `football-core.md`:**
> monetization is cosmetic only — verified in the audit, no value in any config
> table is purchase-linked — and this document may never change that. The
> catch/tackle/movement math is untouchable by anything sold or earned here.
> Storefront: the existing DRIP STORE in the hub (`04_Lobby`: `Sign_DRIP STORE`,
> the CLEATS & KICKS shoe wall, GAME DAY / PRACTICE / STREET / CLUB wayfinding).
> All prices, earn rates and names below are **[ASSUMPTION]** until the owner
> sets them — the *structure* is the spec; the numbers are starting points for
> the economy-designer.

---

## 1. Overview

A cosmetics system in seven categories — jersey kits, cleats, gloves/sleeves,
ball trails, celebration emotes, banners/titles, and field-entrance effects —
sold and equipped through the existing DRIP STORE lobby build and a quick-equip
loadout panel. Players earn a soft currency from playing matches and spend it
directly on visible items; Robux buys premium-tier *cosmetic* variants only;
there are **no loot boxes and no paid randomness of any kind**. Ownership and
equips live in a server-validated player profile (Roblox DataStore); the server
renders worn items (jersey/cleats/gloves) through character appearance so
replication is free, while effects (trails, entrances, celebrations) render
client-side from replicated equip state. V1 ships three categories — ball
trails, jersey tints, one celebration — plus the earn loop; everything else is
staged behind it.

## 2. Player Fantasy

**"That's MY player — and everybody saw it."** Expression on a fair field: the
drip says who you are, never how you play. The receiver who wins the jump ball
in a flamingo-trim kit and hits an earned celebration is *recognized*; the
defender across from him knows the kit changed nothing about the catch math.
MDA: **Expression** first, **Fellowship** second (team identity, club colors
later); SDT **Relatedness** (being seen) and **Autonomy** (loadout choices).
The fairness pillar is part of the fantasy, not a constraint on it: on a
kid-heavy platform, "you can't buy wins here" is a trust feature players repeat
to each other.

## 3. Detailed Design

### 3.1 Categories — what exists, who sees it, when

| Category | Store wing (04_Lobby wayfinding) | Visible to whom, when | Render path |
|---|---|---|---|
| **Jersey kits** (team-tint aware) | GAME DAY | everyone, on-field + lobby | server (clothing/SurfaceAppearance) |
| **Cleats** | CLEATS & KICKS wall (exists) | everyone, on-field + lobby | server |
| **Gloves / sleeves** | GAME DAY | everyone, on-field + lobby | server |
| **Ball trails** | STREET | everyone, while *you* are the thrower/carrier (§3.4) | client, from replicated equip |
| **Celebration emotes** | STREET | everyone, TD beat + lobby free-play | client animation (§3.5) |
| **Banners / titles** (incl. ANKLE BREAKER badge styles) | CLUB | everyone: your lower-third/badge chrome and lobby nameplate | client UI |
| **Field-entrance effects** | CLUB | everyone, kickoff intro and lobby entrance — **never during live play** | client VFX |

**Team-tint law (jerseys).** On-field team identity is sacred: HOME BLUE
(70,150,255) / AWAY GOLD (255,191,58) must stay the dominant jersey read.
A kit cosmetic owns only the *secondary* zones — trim, sleeves, number style,
collar — capped at **≤ 35% of torso surface area [ASSUMPTION — tune in
playtest]**. The kit defines its accents per-slot so one item works on both
teams ("team-tint aware"): `kit = { trimColor, sleeveStyle, numberFont }`
applied over whichever base the server assigns. A kit whose accent matches the
*opposing* team's base color renders desaturated 40% that match (anti-confusion
rule).

### 3.2 Economy — earn vs buy

**Soft currency:** working name **DRIP [ASSUMPTION — owner names it]**, earned
only by playing:

| Source | Amount [ASSUMPTION] | Notes |
|---|---|---|
| Match completed (5v5/2v2, full) | 20 | leaving early forfeits it (anti-AFK: must be present at final whistle) |
| Win bonus | +15 | |
| First win of the day | +50 | daily hook, once per UTC day |
| Badge earned in-match (ANKLE BREAKER, etc.) | +5 each, cap 25/match | ties the feel systems to the economy |
| Practice Field session ≥ 10 catches | +5, cap 10/day | keeps the Ball Lab alive without making it farmable |

**Prices by rarity [ASSUMPTION]:** Common 150 · Rare 500 · Epic 1,200 ·
Legendary 3,000 DRIP. A casual player (2 wins/day ≈ 120 DRIP) reaches a Rare in
~4 days, a Legendary in ~25 — tune against retention data later.

**Robux:** premium cosmetic variants only — Epic/Legendary skins sold directly
at a visible fixed price (**49–399 Robux [ASSUMPTION]**). Every Robux item is a
*specific, previewable item*. Robux never buys DRIP multipliers, never buys
anything a config table reads, and premium items have earnable siblings of
equal visual tier in every category (premium = different, not better).

**No loot boxes — stated reasons, on the record:**
1. **Kid-heavy platform.** Undisclosed-odds purchases are gambling-shaped
   mechanics aimed at an audience that cannot evaluate them; regulatory
   pressure worldwide is moving against them, and Roblox's own policy climate
   punishes them. Direct purchase is the durable choice.
2. **The fairness pillar extends to spending:** "what you see is what you buy"
   is the economic version of "I know exactly why." A random reward breaks the
   same promise a random catch roll would.
3. Operationally: no odds tables to disclose, no refund disputes over
   duplicates, no region-law matrix.

**Rarity palette** (the game's existing color language):

| Tier | Color | RGB |
|---|---|---|
| Common | Navy | (7, 16, 28) frame, MUTED label |
| Rare | Teal | (64, 199, 195) [ASSUMPTION — art-director confirms exact teal] |
| Epic | Flamingo | (255, 112, 160) [ASSUMPTION — art-director confirms] |
| Legendary | Gold | (255, 191, 58) |

Rarity colors are *frame/label chrome* in the store and loadout UI — never a
gameplay signal, and rarity tier text always accompanies the color (no
color-only information).

### 3.3 Store and equip flow

**DRIP STORE (04_Lobby) — the storefront is the existing build:**
1. Walk up to a wing (wayfinding signs route GAME DAY / PRACTICE / STREET /
   CLUB); interacting with a display (shoe wall shelf, mannequin, kiosk) opens
   the store panel filtered to that wing.
2. **Browse** — grid of item cards (rarity frame, name, price, OWNED tag).
3. **Try on** — selecting an item previews it *locally only* (your client
   dresses your rig / shows the trail on a looping throw ghost at the store's
   preview spot); nothing replicates.
4. **Buy** — two-step confirm (`BUY · 500 DRIP` → `CONFIRM`), server validates
   and deducts; Robux items route through `MarketplaceService` prompt.
5. **Equip** — one tap on an owned item; server validates and writes the slot.

**Quick-equip (lobby):** a LOADOUT button on the lobby panel opens a single
6-slot panel (kit, cleats, gloves, trail, celebration, banner) showing equipped
items with one-tap swap among *owned* items. No purchasing here — buying stays
a deliberate act in the store (kid-safety: distance between impulse and spend).

**In-match:** equips are **locked from kickoff to final whistle**; a mid-match
equip intent is refused with `"LOCKED UNTIL THE FINAL WHISTLE"` and applies
nothing (prevents mid-play appearance swaps confusing coverage reads).

**Input parity:** the store panel and loadout are full keyboard / gamepad /
touch navigable (D-pad grid focus, A select, B back); touch targets ≥ 1 cm²;
same `viewK()` scaling as the broadcast UI.

### 3.4 Ball trails — the rules that keep the game readable

The ball already has a gold comet trail in flight plus a white-flashing outline
and landing ring when the catch window opens (`TeamFootballClient` catch-sense,
2026-11-02). Cosmetic trails **recolor the comet only**:

- Trail color = the **thrower's** equipped trail for a pass in flight; the
  **carrier's** for a run [ASSUMPTION — simplest ownership rule; owner may
  prefer QB-only]. Practice Field: your own trail on your reps.
- **Reserved signals, never overridable:** the white catch-window flip
  (outline, ring, and any trail brightening at window-open), and the reticle
  color semantics (GOLD normal / BAD high ball / WHITE in-window). A trail
  color within ΔE of plain white is not sellable — white means "window open."
- Trails must differ by **pattern as well as hue** at Epic+ (sparkle, dash,
  dual-stripe) so colorblind players can tell drip apart; hue-only variants are
  Common/Rare.

### 3.5 Celebration emotes and the 8-track budget

Celebrations ride the authored-animation pipeline (`aw_celebrate_set` in
`football-feel-upgrades.md` §3.4.3, priority 3) and play only in the TD
dead-ball beat (feel-upgrades #10) and in the lobby.

**Track budget law:** the animation reference flags a tight per-Animator track
budget under Server Authority (~8, unverified). Therefore:
- Exactly **one celebration slot** is equippable; its track is **not**
  preloaded into the gameplay pool. It is loaded at the TD beat, played once
  (≤ 4 s), and destroyed — net steady-state track cost: **0**.
- If the load misses the beat window (slow client), the celebration is skipped
  silently — the beat never waits on a cosmetic.
- Lobby playback uses the lobby Animator freely (no gameplay pool there).

### 3.6 Data model and authority (sketch for ui-programmer / systems)

```
-- DataStore "PlayerCosmetics_v1", key = UserId   [ASSUMPTION: plain DataStore
-- with session cache; ProfileService-style locking if trade/gifting ever ships]
profile = {
  drip     = 1240,
  owned    = { ["trail_teal_dash"] = true, ... },        -- catalog ids
  equipped = { kit=?, cleats=?, gloves=?, trail=?, celebration=?, banner=? },
  ledger   = { lastDaily = "2026-11-02", receipts = { [receiptId]=true } },
}
```

- **Catalog** is a server module (`ReplicatedStorage.AWCosmetics.Catalog`):
  `id → { category, rarity, price, robuxProductId?, assetRefs }`. Read-only on
  clients (renders store + items); gameplay configs never import it
  (acceptance F5).
- **Server-validated equips:** intent `{action="equip", slot, id}` → server
  checks id exists, is owned, category matches slot, player not in a locked
  match; token-bucket rate limit (reuse the 12 intents/s pattern from
  `PracticeService`). Equip state replicates via a per-player attribute or the
  existing State channel; clients render from that, never from local claims.
- **Purchases:** DRIP purchases are a single server transaction (check → deduct
  → grant → save). Robux via `MarketplaceService.ProcessReceipt`, idempotent
  by `receiptId` in `ledger.receipts` (grant once, record, then
  `PurchaseGranted`).
- **Render split:** worn gear server-side (appearance replication is free and
  cheat-proof); trails/entrances/celebrations client-side from replicated equip
  state (effects are visual-only, so client render is safe — a tampered client
  can only lie to its own screen).

### 3.7 MVP cut

**V1 (recommended):**
1. **Ball trails** — 6 items (2 Common hues, 2 Rare hues, 2 Epic patterned).
   Cheapest to build (the Trail object exists), most visible per minute.
2. **Jersey tints** — 4 trim kits (team-tint aware per §3.1). The "that's me"
   anchor.
3. **One celebration** — proves the TD-beat pipeline and the track-budget
   discipline end to end.
4. The DRIP earn loop + store panel on the existing lobby build + quick-equip.

**V1 explicitly excludes:** Robux products (ship earn-only first — trust
before monetization, and it halves v1's compliance surface), cleats wall
stock, gloves, banners/titles, entrance effects, gifting/trading (never
without a full safety review).

**V2+:** cleats (the wall is built — highest-value shelf), gloves, banner/badge
styles (pairs with broadcast-ui badges), entrance effects, Robux premium tier.
**Club kits** wait for Clubs.

## 4. Formulas

### 4.1 Earn curve [ASSUMPTION — economy-designer owns tuning]

    dailyDrip(casual)  = 2 matches · (20 + 15·winRate) + 50·firstWin
                       ≈ 2·(20 + 7.5) + 50 = 105/day   (winRate 0.5)
    daysToTier(tier)   = price[tier] / dailyDrip
                       → Common ≈ 1.4 d · Rare ≈ 4.8 d · Epic ≈ 11.4 d · Legendary ≈ 28.6 d

| Variable | Range | Meaning |
|---|---|---|
| `winRate` | 0–1 | expected 0.5 with matchmaking |
| `price[tier]` | §3.2 table | DRIP prices |

Target band: first cosmetic inside 2 days (hook), Legendary ≈ a month
(aspiration). If measured `daysToTier(Legendary)` leaves 20–40 days, do not
touch; outside it, move prices, not earn rates (earn rates also pace badges).

### 4.2 Match earn cap (anti-farm)

    matchDrip = min(20 + 15·won + 5·badges, 60)

Caps a badge-farming stomp at 3× a plain loss — enough to feel skill, not
enough to farm bots in private servers [ASSUMPTION: private-server earn = 0 is
the safer owner option; flag as open question].

## 5. Edge Cases

1. **DataStore write fails on purchase:** transaction order is check → deduct
   in session cache → grant → async save with retry; on repeated failure the
   session cache is still authoritative until exit (Roblox standard). Never
   deduct without granting in the same server step.
2. **ProcessReceipt retry (Robux):** `receiptId` already in `ledger.receipts`
   → return `PurchaseGranted` without granting again (idempotent).
3. **Equipped item removed from catalog:** slot falls back to default at
   profile load; the player keeps `owned` (re-equips if it returns); no error.
4. **Mid-match join with cosmetics:** worn gear applies at spawn (server
   appearance); trail/banner state replicates with the join sync. Equip
   changes stay locked (§3.3).
5. **Celebration asset fails to load in the TD beat:** skip silently (§3.5);
   the TD presentation (camera push, lower third) never waits.
6. **Two players, same trail, jump-ball tip chain:** trail ownership follows
   the last thrower/carrier state the server replicated; a tip does not change
   the thrower, so no flicker.
7. **Trail vs catch-window white:** catalog validation rejects any trail color
   with all RGB channels ≥ 230 (≈ white) at build time (acceptance F4).
8. **Player with 0 items:** defaults exist for every slot (plain team kit,
   plain gold trail — today's look is the default skin). The free look must
   never read as a punishment: defaults are clean, not gray.
9. **Griefing via celebration length:** hard cap 4 s, dead-ball beat only,
   no movement during playback, skippable by the next phase starting.
10. **Refund/chargeback:** Roblox handles Robux revocation;
    on a revoked receipt (if surfaced), mark the item `revoked` rather than
    deleting the profile — never negative-balance DRIP.

## 6. Dependencies

| System | Direction | Contract |
|---|---|---|
| 04_Lobby DRIP STORE build (exists) | storefront | wings per §3.1; shoe wall = cleats shelf; no new world-building required for v1 beyond interaction points |
| `TeamFootballService` | hooks | TD dead-ball beat (celebration trigger), match-complete/win/badge events (DRIP grants), equip lock window |
| `TeamFootballClient` / `AWMotion` | renders | trail recolor on the existing Trail object; celebration playback; loadout/store panels (broadcast-ui chrome tokens) |
| `football-broadcast-ui.md` | pairs | banner/badge styles are chrome variants of its lower-third/badge anatomy; reserved-white rule shared |
| `football-feel-upgrades.md` | pairs | `aw_celebrate_set` pipeline + TD beat (#10); badge events feed earn rates |
| `football-core.md` | law | cosmetic-only monetization (verified); nothing here may become an input to any gameplay config |
| economy-designer | owns numbers | every [ASSUMPTION] price/rate in §3.2/§4 |
| art-director | owns look | rarity palette exact values, kit/trail/cleat visual style — this doc specs surfaces and rules only |
| DataStore / platform | persistence | `PlayerCosmetics_v1`, ProcessReceipt idempotency |
| DON brand houses | content pipeline | Don Athletics / Luxury of Don drops as kit/cleat lines is an owner option — flagged, not designed |

## 7. Tuning Knobs

All in a server config (`AWCosmetics.Config`), never hardcoded:

| Knob | Default | Safe range | Affects |
|---|---|---|---|
| `earn.*` (complete/win/daily/badge/badgeCap) | §3.2 | ±50% | economy pace; move with prices, not alone |
| `price[rarity]` | 150/500/1200/3000 | ±50% | §4.1 target band |
| `matchDripCap` | 60 | 40–100 | anti-farm ceiling |
| `kit.accentAreaMax` | 0.35 | 0.2–0.45 | team-read protection (§3.1) |
| `trail.whiteFloor` | 230 | 210–245 | reserved-white rejection threshold |
| `celebration.maxLen` | 4 s | 2–6 | TD beat length pairing |
| `equip.rate` | 12/s bucket | 4–12 | equip spam guard |
| `store.confirmStep` | on | on only | two-step buy is a kid-safety gate, not a preference — do not expose "off" |

## 8. Acceptance Criteria

Functional (pure-Luau harnesses in `tests/roblox/cosmetics/`, PASS lines
retained per `DEFINITION-OF-DONE.md`):

- [ ] **F1 catalog integrity**: every item has a valid category/rarity/price;
      every `equipped` slot name maps to a category; no id collisions.
- [ ] **F2 equip validation**: unowned id, wrong-slot id, unknown id, and
      in-match equip are each refused (counted), and a legal equip persists
      across a simulated save/load.
- [ ] **F3 purchase paths**: DRIP purchase deducts exactly once; a replayed
      `receiptId` grants nothing twice; insufficient DRIP refuses cleanly.
- [ ] **F4 reserved white**: catalog validation rejects a trail at RGB
      (235,235,235) and accepts (200,180,255).
- [ ] **F5 fairness proof**: grep/static check — no module under gameplay
      config (`AWFootball.*`, `AWPractice.*`) requires or reads the cosmetics
      catalog or profile; run it in review on every cosmetics PR.
- [ ] **F6 earn caps**: a synthetic 10-badge win grants `matchDripCap`, not
      more; daily bonus fires once per UTC day.

Experiential (playtest + retained screenshots in `production/qa/evidence/`):

- [ ] **E1** store flow on phone, gamepad and KB/M: browse → try on → buy →
      equip, screenshots of each step; touch targets ≥ 1 cm².
- [ ] **E2** on-field screenshot: two full teams in mixed kits — team identity
      (who is HOME) readable at gameplay camera distance in < 1 s (ask a
      tester).
- [ ] **E3** flight screenshot with a cosmetic trail: the white catch-window
      flip still clearly reads (compare against default-trail screenshot).
- [ ] **E4** TD beat with a celebration: console shows track count never
      exceeding the Animator budget; beat timing unchanged vs no-celebration.
- [ ] **E5** a new player's default look screenshot approved by the owner as
      "clean, not punished."
