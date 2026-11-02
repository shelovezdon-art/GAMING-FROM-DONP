# Cosmetic-Only Monetization in Roblox Sports Games

Research date: 2 November 2026. The owner's plan — **DRIP STORE, Season Pass,
Create-a-Club, all strictly cosmetic** — is sound and compliant. The useful work
here is the platform rules that constrain *how* you structure it, and the earnings
reality to calibrate against.

---

## 1. Calibrate on real numbers before designing anything

**VERIFIED** — [2026 Roblox Benchmark Report, GameAnalytics](https://www.gameanalytics.com/reports/2026-roblox-report)
(500+ titles with 1M+ MAU, Aug 2025 – Jul 2026):

| Metric | p25 | **Median** | p75 | p90 | p95 | p99 |
|---|---|---|---|---|---|---|
| **ARPPU** (per game) | $0.32 | **$0.70** | $1.25 | $2.33 | $4.80 | $55.31 |
| **Spend per paying player** (platform-wide) | — | **$0.81** | $2.75 | $8.88 | $20.31 | $86.36 |

**Conversion: "3.80% of tracked players paid anything at all"** across the period.
ARPDAU is not reported.

**Read this carefully, because it is the most important number in this file.**
Median ARPPU is **$0.70** and conversion is **~3.8%**. That implies a median game
earns roughly **2–3 cents per player who ever shows up.** The p99 game earns
$55.31 ARPPU — the distribution is brutally top-heavy.

Put against the retention benchmarks (`landscape.md` §3: median D1 **10.3%**, D30
**0.5%**), the structural conclusion is:

> **Cosmetic monetization on Roblox earns from a small, retained, repeat-spending
> core — not from converting the acquisition flood.** Every design choice below
> should serve the player who is still there on day 30, because the other 99.5%
> will not pay you regardless of what the store looks like.

This argues directly for the owner's instinct: cosmetics plus club identity plus a
season rhythm is exactly a retained-core model. It argues *against* an aggressive
first-session store push.

And the platform context from `landscape.md` §0: Roblox bookings are **down 12%
YoY** and DevEx payouts **down 6% YoY** ([Q3 2026](https://s27.q4cdn.com/984876518/files/content_files/Q3-2026-Earnings-Shareholder-Letter.pdf)).
The pie is shrinking slightly. Plan on share, not growth.

---

## 2. The mechanisms available — **VERIFIED**

From [Monetization](https://create.roblox.com/docs/en-us/production/monetization) (official):

| Mechanism | What it is | Fit |
|---|---|---|
| **Passes** | One-time Robux purchase granting a privilege — area access, an avatar item, a permanent power-up | ✅ Season Pass, permanent cosmetic unlocks |
| **Developer products** | Repeatable purchases — currency, consumables | ✅ Soft-currency top-ups, single DRIP STORE items |
| **Subscriptions** | Recurring monthly benefits | ✅ See §3 — **battle passes are explicitly allowed as subscriptions** |
| **Avatar items (Catalog/Marketplace)** | Accessories and clothing sold after an upload fee and moderation. Creator earns a commission per purchase; **the game owner also earns a commission when items are bought in-game** via the avatar inspect menu or avatar editor service | ⚠️ Secondary. See the caution in `assets-and-licensing.md` §5 |
| **Immersive ads** | Ad units Roblox serves inside your game | ❌ Not for a premium-feel sports game at this stage |

**No commission percentages are stated on that page.** The documented figures I
could find are: Creator Store minimums of **$4.99** (plugins) and **$2.99**
(models), with only taxes and payment-processing fees deducted and **30-day
escrow** per sale. Marketplace avatar-item commission rates: **UNVERIFIED** — not
published on the pages I could reach.

---

## 3. Season Pass — the structural decision, with real numbers

**The key permission, VERIFIED:** [Subscriptions](https://create.roblox.com/docs/production/monetization/subscriptions)
states subscriptions **may "be battle passes sold as subscriptions."** So you have
a genuine choice of structure, and the economics differ materially.

### Option A — Season Pass as a **Pass** (one-time Robux purchase)

Simple, familiar, no eligibility constraints. The player buys each season
separately. No published revenue-share figure for passes on the pages I reached
(**UNVERIFIED**).

### Option B — Season Pass as a **Subscription**

**VERIFIED** — [Subscriptions](https://create.roblox.com/docs/production/monetization/subscriptions)
and [Subscriptions in Robux announcement](https://devforum.roblox.com/t/let-your-players-pay-for-subscriptions-within-experiences-in-robux/4552995)
(Robux payment added **1 April 2026**):

| | **Robux** | **Local currency** |
|---|---|---|
| **Price points** | **Any amount ≥ 49 Robux** | **Exactly five tiers: $2.99, $4.99, $7.99, $9.99, $14.99** |
| **Payout** | **70% every month** | **70% month 1, then 100% from month 2 onward** |
| **Eligibility** | All creators, all platforms, all supported countries | **Requires ID- or phone-verified account.** Web, App Store, Google Play only. **Not available** in Argentina, China, Colombia, India, Indonesia, Japan, Russia, Taiwan, Türkiye, UAE, Ukraine, Vietnam |
| **Regional pricing** | **Forced on — creators cannot opt out** (this drew pushback in the announcement comments) | — |
| **Price changes** | Every **60 days**; increases announced to users **≥30 days** ahead; decreases apply at next renewal | — |
| Earnings hold | — | Held **30 days** after the full term is delivered |

**The 100%-from-month-two local-currency rate is the single most valuable
monetization fact in this research.** A retained subscriber in local currency pays
you the full price from their second month. Nothing else on Roblox pays 100%.

But note the trap: it **requires a verified account and excludes a long list of
countries**, and the docs warn that offering a subscription outside supported
regions means **"users can see the offer but cannot complete the purchase"** — a
visible, broken buy button. A **Robux** subscription is available everywhere and
pays a flat 70%.

**A subscription is priced in either Robux or local currency — not both.** To
offer both you create **two separate subscriptions.**

### Rules a Season Pass must obey — **VERIFIED**

Subscriptions **must**:
- Align with Roblox's Terms of Use and Community Standards.
- Use **short, distinct names**, and **show price and duration** when merchandised
  in-game.
- Provide **the same benefits regardless of where purchased**.
- **Deliver the promised benefits for the full term, without revoking them behind
  the scenes.**

Subscriptions **may not**:
- Be scams or misleading offerings.
- **Use mutually exclusive tiers — "Mutually exclusive subscriptions are not
  supported."** ⚠️ **This kills a Bronze/Silver/Gold Season Pass ladder.** Design
  one pass, not a tier ladder.
- Direct users to purchase on another platform through the Roblox app.
- **Require extra tasks, such as social media posts, before users can access
  benefits they have paid for.** ⚠️ Relevant to any "follow us to unlock" idea.

### Recommendation

**Season 1 as a one-time Pass; evaluate a subscription from Season 2.** Reasons:
a one-time pass has no verification or regional constraints and no "benefits for
the full term" obligation to honour while your content cadence is still
stabilising. Once you can prove you ship weekly, the subscription's 100%
month-two rate becomes the best deal on the platform — and by then you will know
whether your D30 cohort is large enough to make recurring revenue real.

---

## 4. The rule that most constrains DRIP STORE: paid random items

The owner's plan is **strictly cosmetic**, which is the right call. But "cosmetic"
does **not** exempt you from Roblox's randomisation rules — a cosmetic loot crate
is still a paid random item.

**VERIFIED** — [Randomized virtual items policy](https://create.roblox.com/docs/production/monetization/randomized-virtual-items-policy):

**Scope — broader than people expect.** It applies when random items are bought
**directly *or indirectly*** with Robux, including with paid in-game currency.
Covered: **capsule items** (wheel spins, egg hatching, chests), **enhancement
items**, **combination items**, and **probability modifiers** (luck boosts, pity
systems, enhanced drops, rate-up scrolls). Buying gems or spin tickets with Robux
and spending those on a wheel **is covered.**

**Disclosure requirements:**
- You must disclose **all possible outcomes and their actual numerical odds**.
- Odds must be shown as **percentages totalling exactly 100%**. Long decimals may
  be rounded **with a disclaimer** that displayed probabilities may not total 100%.
- Odds must be disclosed **before** the user spends the currency — including for
  keys, re-roll tokens and spin tickets.
- Odds-boosting items must be explained **numerically before purchase** and their
  enhanced odds must **update dynamically while active**.
- If a user can obtain only one instance of an outcome, **remaining odds must
  update to reflect that user's current chances.**
- UI: a clickable pop-up with an **"Info" or "Details"** control is acceptable for
  long lists. **A standalone (i) icon alone is NOT sufficient.**
- **Rewards earned through gameplay without paying Robux or in-game currency need
  no odds disclosure.**

**Per-user restrictions — you must handle these in code.** Call
`PolicyService:GetPolicyInfoForPlayerAsync()` and read:
- **`ArePaidRandomItemsRestricted`** — if restricted, the user **cannot** interact
  with paid random item generators at all. You must then do **one** of: offer an
  unpaid way to earn the item; show outcomes in a predetermined order disclosed
  before purchase; offer specific outcomes for direct purchase **at an
  expected-value price**; remove or hide the item; block the purchase with an
  error message; or move the user out of areas containing paid random items.
- **`IsPaidItemTradingAllowed`** — for users where this is not allowed, you must
  **not** permit trading of paid-random-item outcomes or other paid items.

### The DRIP STORE recommendation

**Make DRIP STORE a direct-purchase store with no randomisation at all.**

Rationale, not squeamishness:
1. It removes an entire compliance surface — no odds UI, no dynamic odds updates,
   no `PolicyService` branching, no per-user alternative treatments, no exposure to
   a policy that is tightening across the industry.
2. It is a **better fit for realistic sports cosmetics.** Players want *a specific
   kit*, *a specific cleat*. A crate that might give them a wristband is worse at
   selling the thing they came for.
3. It matches the retained-core economics in §1 — your buyers are a small group
   who know exactly what they want.

If a crate is ever added, it must be built to the full policy above from the first
line of code, and the `PolicyService` branching treated as a launch requirement,
not a follow-up.

---

## 5. Create-a-Club — where the money and the risk both sit

Club customisation is the strongest cosmetic hook in a team sport, because it sells
to a *group* and creates social pressure to match. Structure:

- **Free tier:** a usable club — name, a small palette, a handful of crest
  primitives. Every player can make one. This is the acquisition funnel.
- **Paid cosmetics:** additional crest primitives, kit patterns, stadium dressing,
  entrance animations, celebration sets, club banners. Direct purchase.
- **Season Pass track:** club-level unlocks, so the pass benefits the player's
  whole group and renews for social reasons, not completionist ones.

**Strictly cosmetic means strictly cosmetic.** No club-level stat boosts, no
pay-gated formations, no paid-only ranked access. Beyond being the right call, it
keeps you clear of the fairness complaints that make a sports game's reviews
collapse — and `landscape.md` shows the like-ratio spread in this genre is wide
(Football Fusion 2 at **83.9%**, Blue Lock: Rivals at **96.6%**).

**⚠️ The risk, restated from `assets-and-licensing.md` §5.** Create-a-Club makes
you a *host* of user-generated marks. Players will immediately attempt real club
crests and kits. You need crest primitives that cannot easily assemble into a real
mark, plus a moderation and reporting path, from launch. This is a product
requirement, not a legal afterthought.

---

## 6. Platform rules checklist

| Rule | Source | Effect on the plan |
|---|---|---|
| Battle passes **may** be sold as subscriptions | [Subscriptions](https://create.roblox.com/docs/production/monetization/subscriptions) | ✅ Season Pass structure is a real choice |
| **Mutually exclusive subscription tiers are not supported** | same | ⚠️ **No Bronze/Silver/Gold pass ladder** |
| Must show **price and duration** when merchandising a subscription | same | ⚠️ Store UI requirement |
| Must **deliver benefits for the full term**, no silent revocation | same | ⚠️ A season's content is a commitment once sold |
| May **not** require extra tasks (e.g. social posts) for paid benefits | same | ⚠️ No "follow to unlock" on paid tiers |
| Robux subscriptions: **≥49 Robux**, **70%**, everywhere | same + [announcement](https://devforum.roblox.com/t/let-your-players-pay-for-subscriptions-within-experiences-in-robux/4552995) | ✅ Safe default |
| Local currency: 5 tiers $2.99–$14.99, **70% then 100%**, verified account, 12 countries excluded | [Subscriptions](https://create.roblox.com/docs/production/monetization/subscriptions) | ✅ Best rate, narrower reach |
| Robux subscription **regional pricing cannot be disabled** | [announcement](https://devforum.roblox.com/t/let-your-players-pay-for-subscriptions-within-experiences-in-robux/4552995) | ⚠️ Revenue per sub varies by region |
| Price changes only every **60 days**, **30 days'** notice for increases | same | ⚠️ Price the pass right the first time |
| Any paid randomisation ⇒ **full numerical odds, summing to 100%, before spend** | [Randomized items policy](https://create.roblox.com/docs/production/monetization/randomized-virtual-items-policy) | ✅ Avoided entirely by direct-purchase DRIP STORE |
| **`PolicyService`** gating for restricted users | same | ✅ Avoided; required if crates are ever added |
| Gameplay-earned rewards need **no** odds disclosure | same | ✅ Free reward tracks are unconstrained |
| Marketplace avatar items: upload fee + moderation; emote upload **80 Robux** | [Monetization](https://create.roblox.com/docs/en-us/production/monetization), [Emote import](https://create.roblox.com/docs/en-us/avatar/emotes/import) | ⚠️ Only for original assets — see `assets-and-licensing.md` |
| Game owner earns commission on in-game avatar-item purchases | [Monetization](https://create.roblox.com/docs/en-us/production/monetization) | ✅ Small secondary line |

---

## 7. What I could not verify

- **Actual price points used by Roblox sports games** for their passes and
  cosmetics. Searches returned only low-quality SEO content
  (e.g. [generalistprogrammer](https://generalistprogrammer.com/tutorials/roblox-game-pass-pricing-guide),
  [ugccraft](https://ugccraft.com/blog/roblox-game-passes-pricing-guide/)) with no
  methodology or primary data. **I will not quote a price benchmark I cannot
  source.** The reliable way to get this: open Volleyball Legends, Blue Lock:
  Rivals and Basketball: Zero and read their store pages directly. That is an hour
  of work and yields better data than anything published.
- **Marketplace avatar-item commission percentages** — not stated on the pages I
  could reach.
- **Pass revenue share** — no figure published for one-time passes.
- **Per-genre monetization benchmarks** — the GameAnalytics report gives **no genre
  breakdown**, so there is no sports-specific ARPPU figure available.
- **Whether the top sports games use randomised cosmetics.** Unverified. Do not
  assume crates are necessary because competitors may use them.

---

## 8. The recommendation

1. **DRIP STORE: direct purchase only, no randomisation.** Sidesteps the entire
   paid-random-items policy and sells realistic sports cosmetics better anyway.
2. **Season Pass: a one-time Pass for Season 1.** Move to a subscription from
   Season 2, in **local currency** if you can clear ID verification (**100% from
   month two**) and in **Robux** as the universally available option. **One pass,
   never a tier ladder** — tiers are prohibited.
3. **Create-a-Club: free base, paid cosmetic expansion, club unlocks on the pass
   track.** Original crest primitives plus a moderation path, from launch.
4. **Build the free earn-track first.** Gameplay-earned rewards carry **no odds
   disclosure obligation**, drive the D7–D30 retention that the paying core comes
   out of, and are the honest answer to pay-to-win accusations.
5. **Set expectations at median: ~3.8% conversion, ~$0.70 ARPPU.** Build the
   business case on the retained core, and treat the first 30 seconds of a new
   player's session as a retention problem, not a conversion opportunity.
