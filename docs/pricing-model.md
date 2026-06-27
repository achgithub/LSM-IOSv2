# Pricing model

Status: **revised 2026-06-27**, supersedes the 2026-06-21 league-only ladder.
Key changes: cloud features bundled into league tiers (no standalone Cloud Bundle
SKU), 1:3:20 ratio introduced, ladder extended to 20 leagues, full P&L model
including Apple commission, office, equipment, electricity, staff, and tax.

---

## The ladder

### Ratio: 1 league : 3 active games : 20 PWA links

Every league tier is derived mechanically from this ratio. Cloud features
(Backup, Publish, PWA) unlock in full at 3 Leagues and stay on for every
tier above — the quantity caps do the differentiation work, not a feature
split.

| Tier | UK £/mo | EUR €/mo | USD $/mo | Leagues | Active games | PWA links | Cloud |
|---|---|---|---|---|---|---|---|
| Free | £0 | €0 | $0 | 1 | 2 | — | ✗ (ads) |
| No Ads | £2.49 | €2.99 | $3.49 | 1 | 3 | — | ✗ |
| 3 Leagues | £3.49 | €3.99 | $4.49 | 3 | 9 | 60 | ✓ Backup + Publish + PWA |
| 5 Leagues | £4.49 | €4.99 | $5.49 | 5 | 15 | 100 | ✓ |
| 7 Leagues | £5.49 | €5.99 | $6.49 | 7 | 21 | 140 | ✓ |
| 10 Leagues | £6.99 | €7.49 | $7.99 | 10 | 30 | 200 | ✓ |
| 15 Leagues | £9.49 | €9.99 | $10.49 | 15 | 45 | 300 | ✓ |
| 20 Leagues | £11.99 | €12.49 | $12.99 | 20 | 60 | 400 | ✓ |

**Tiers above 7 Leagues activate as the catalogue grows.** Today's catalogue
is 7 leagues (PL/ELC/PD/Bundesliga/Serie A/Ligue 1/Eredivisie). The 10/15/20
tiers are priced and structured; they become meaningful as new leagues are added.

### Pricing formula

- **No Ads**: £2.49 flat (removes ads, no other change)
- **League tiers**: previous tier price + (league increment × £0.50)
  - 3L: £2.49 + 2×£0.50 = £3.49
  - 5L: £3.49 + 2×£0.50 = £4.49
  - 7L: £4.49 + 2×£0.50 = £5.49
  - 10L: £5.49 + 3×£0.50 = £6.99
  - 15L: £6.99 + 5×£0.50 = £9.49
  - 20L: £9.49 + 5×£0.50 = £11.99
- **EUR**: UK face value + €0.50
- **USD**: UK face value + $1.00
- **Rest of world**: auto-convert from USD via Apple's standard price-tier FX
- **No annual option at launch** — monthly only; revisit with real conversion data
- **No mid-season price hikes on existing subscribers** — Apple grandfathers
  existing subscribers on any price rise, so this is the real launch price

### Cloud features — what each unlocks at 3 Leagues+

- **Backup**: R2 blob snapshot of game data. User-triggered. Restore code for
  device migration. Paid/durability feature, not a storage play (worst case
  ~20–30 MB/season even with 3 leagues).
- **Publish**: PIN-gated standings snapshot page hosted on Cloudflare Pages.
  Manager selects fixtures and scores; app uploads a self-contained blob.
  Access URL is unguessable UUID; PIN validated server-side; names never in the
  openly-served payload.
- **PWA**: Per-player web submission links (pick/prediction via browser).
  PWA links are minted per-player per-game; each active link counts against the
  tier's link cap. Link can be revoked and re-minted (token rotates; old link
  dies). The submission queue, approval flow, and D1 submissions inbox are part
  of this feature.

### Active games definition

"Active" = a game that has rounds in progress or is open for a new round.
Completed/archived games do not count against the cap.

**Tournament games** (e.g. Euros, World Cup knockout) are periodic one-off
events, not rolling weekly games. Decision: exclude tournament-type games from
the active game cap — they run once every 1–2 years and counting them against
the cap would create frustration during major events with no compensating
revenue reason.

### Why no Unlimited tier

Dropping Unlimited avoids entitling a subscriber paying today's rate to refresh
an arbitrarily large, arbitrarily expensive future catalogue at no extra cost.
The 1:3:20 ratio means adding a new tier (e.g. 25 Leagues) is a pricing decision
not a structural change. The top tier always equals today's catalogue maximum;
higher tiers open up as the catalogue grows.

### Upgrade pressure with multiple game types

With LMS, Predictor, Tournament Knockout, and Pick 6, the ceiling is 4 game
types per league. The 1:3 ratio means you're always about one game type per
league short of running everything:

| Tier | Game slots | 4 types × leagues | Gap |
|---|---|---|---|
| 3 Leagues | 9 | 12 | −3 |
| 5 Leagues | 15 | 20 | −5 |
| 7 Leagues | 21 | 28 | −7 |
| 10 Leagues | 30 | 40 | −10 |

This creates natural upgrade pressure at every tier without being arbitrary —
you hit the limit because your usage genuinely grew, not because of an
artificial cap.

---

## Implementation status

`Entitlements.Tier` currently has: `free` / `no_ads` / `leagues_3` /
`leagues_5` / `leagues_7`.

**Changes needed for this revised model:**

- Remove `cloud_bundle` entitlement entirely — cloud is now bundled into league
  tiers, no standalone SKU
- Add `maxActiveGames: Int` per tier (2 / 3 / 9 / 15 / 21 / 30 / 45 / 60)
- Add `maxPWALinks: Int?` per tier (nil for Free/No Ads = unavailable; 60/100/
  140/200/300/400 for league tiers)
- Add `cloudFeatureLevel: CloudLevel` enum (`.none` / `.full`) — unlocks at
  leagues_3, stays `.full` for all tiers above
- Add `leagues_10_monthly`, `leagues_15_monthly`, `leagues_20_monthly` to
  RevenueCat when catalogue grows to those counts
- Gate game creation on `maxActiveGames` — prompt to upgrade when limit hit
- Gate PWA link minting on `maxPWALinks` with count check across all active games
- Gate backup/publish/PWA on `cloudFeatureLevel == .full`

**RevenueCat package identifiers (current — no change to existing):**

| Package id | Tier | Billing |
|---|---|---|
| `no_ads` | `no_ads` | monthly |
| `leagues_3_monthly` | `leagues_3` | monthly |
| `leagues_5_monthly` | `leagues_5` | monthly |
| `leagues_7_monthly` | `leagues_7` | monthly |

**To add when catalogue grows:**

| Package id | Tier | Billing |
|---|---|---|
| `leagues_10_monthly` | `leagues_10` | monthly |
| `leagues_15_monthly` | `leagues_15` | monthly |
| `leagues_20_monthly` | `leagues_20` | monthly |

Still open: confirm existing identifiers in RevenueCat dashboard match
`PurchaseOption.packageId`; set real API key; confirm `cloud_bundle` entitlement
removal doesn't break existing RevenueCat configuration (it should not exist yet
as a live product).

---

## Cost and revenue model

### Apple's commission — the dominant cost

Apple is the merchant of record for all App Store subscriptions and handles
VAT collection/remittance. Developer receives revenue net of Apple's cut:

- **15%** — Small Business Program (annual App Store proceeds < ~£790K/year,
  equivalent to ~$1M USD). Also applies after the first year of any subscription
  regardless of program status.
- **30%** — Standard rate, applies above the £790K/year threshold.

The ~£790K threshold is crossed at approximately:
- **~112,000 users** under conservative uptake (ARPU £0.59)
- **~40,000 users** under optimistic uptake (ARPU £1.69)

Apple's commission is the single largest cost at every scale — larger than all
infrastructure, larger than office costs, and at 50K+ users larger than the
entire staff bill.

### Per-request infra load (measured from actual worker code)

One "pull live data" tap (`LeagueData.pullLiveScores`, hits `/scores`
`/fixtures` `/teams`) = **per league, per tap**:
- 3 Workers requests
- 7 KV reads (`/scores`: 3 gate + 1 blob; `/fixtures`: 3 gate; `/teams`: 0)
- ~420 D1 rows read (`/fixtures` full season ~400 rows + `/teams` ~20 rows)

Client-side cooldown: 120s, shared across the Scores tab and Results entry's
"Pull results from server".

Cloud feature overhead (backup writes + publish page views + PWA submissions):
approximately 200 additional Workers requests/month per active cloud subscriber.

### Cloudflare cost stack

- Workers Paid: $5/mo base, 10M requests included, $0.30/M beyond
- KV: 10M reads/month included, $0.50/M beyond
- D1: 25B rows/month included, $0.001/M beyond (never material)
- R2 (backup/publish blobs): $0.015/GB storage, $4.50/M write ops, $0.36/M
  read ops — negligible at any realistic scale (~£2-8/month at 10K cloud users)

**Cloudflare variable cost by user count** (worst case: heavy engagement,
optimistic uptake — 15 taps/day, 20 active days/month, 1.9 avg leagues):

| Users | Cloudflare total (worst case) | As % of revenue (optimistic) |
|---|---|---|
| 1,000 | $5.00 | 0.4% |
| 10,000 | $22.12 | 0.2% |
| 50,000 | $122.59 | 0.2% |
| 100,000 | $248.16 | 0.2% |
| 500,000 | $1,252.80 | 0.2% |

Cloudflare variable cost is permanently immaterial to the economics. Workers +
KV + D1 + R2 combined stay under $1,300/month even at 500,000 users on the
heaviest engagement assumption. Pricing decisions are driven by value, not
infrastructure cost recovery.

### Infrastructure cost by environment phase

Environment costs increase as the product scales:

| Phase | Trigger | Environments | Cloudflare base | football-data | Apple Dev | Claude Max | **Monthly infra** |
|---|---|---|---|---|---|---|---|
| Solo | Launch | Prod only | £4 | £24 | £6 | — | **£34** |
| Dev + Prod | 100 users | 2 | £8 | £24 | £6 | £79 | **£117** |
| Dev + QA + Prod | 500 users | 3 | £12 | £24 | £6 | £79 | **£121** |

QA shares the football-data key with prod initially. Claude Max added at
~100 users; justified by that point and previously cost the fixed-cost floor
to double if added too early.

Variable Cloudflare overage is excluded from the monthly infra line — it is
<1% of revenue at every scale and is captured separately in worst-case scenarios.

### The football-data.org risk

At $30/month flat, football-data.org is the dominant cost below ~10K users and
the only line item that doesn't scale favourably. If it moves to metered pricing
or reprices upward, it hits margins directly with no offset. Contingency worth
planning before hard scaling: self-caching strategy, alternative providers, or
a contractual pricing clause.

### Uptake profiles

Revised for the expanded tier structure (speculative pre-launch):

| Tier | Conservative | Optimistic |
|---|---|---|
| Free | 82% | 50% |
| No Ads | 9% | 22% |
| 3 Leagues | 5% | 17% |
| 5 Leagues | 2.5% | 7% |
| 7 Leagues | 1% | 3% |
| 10+ Leagues | 0.5% | 1% |

Weighted average leagues per user: **1.3 (conservative) / 1.9 (optimistic)**
Cloud subscribers (3L+): **9% (conservative) / 28% (optimistic)**

**ARPU (net of Apple's 15% commission):**
- Conservative: £0.59 gross × 0.85 = **£0.50/user/month**
- Optimistic: £1.69 gross × 0.85 = **£1.44/user/month**

*(ARPU adjusts to × 0.70 above the Apple £790K/year threshold)*

### Annual revenue (gross and net of Apple)

*Annual gross = ARPU × users × 12 at steady state. Does not model growth
trajectory or monthly churn (typically 5–7% for subscription apps) — treat
as steady-state estimate. Churn and new user growth offset each other in
a growing product.*

| Users | Gross (cons.) | Gross (opt.) | Apple rate | Net revenue (cons.) | Net revenue (opt.) |
|---|---|---|---|---|---|
| 1,000 | £7,080 | £20,280 | 15% | **£6,018** | **£17,238** |
| 5,000 | £35,400 | £101,400 | 15% | **£30,090** | **£86,190** |
| 10,000 | £70,800 | £202,800 | 15% | **£60,180** | **£172,380** |
| 50,000 | £354,000 | £1,014,000 | 15% / 30%† | **£300,900** | **£709,800** |
| 100,000 | £708,000 | £2,028,000 | 15% / 30%† | **£601,800** | **£1,419,600** |

†Optimistic crosses the £790K/year threshold at ~40,000 users (30% Apple rate
applies above). Conservative crosses at ~112,000 users.

### Additional operating costs

**Office:**

| Team size | Setup | Monthly cost |
|---|---|---|
| Solo | Home working | £0 |
| 1 hire | Co-working (2 desks) | £400 |
| 2 hires | Serviced office | £1,000 |
| 3 hires | Small office | £1,800 |

Remote working eliminates office cost entirely — saves £4,800–£21,600/year at
scale and improves after-tax profit by approximately £3,600–£16,000 after
corporation tax relief. Viable for a digital product with a small, trusted team.

**Equipment (amortised over 3 years):**

- Solo: MacBook Pro £2,500 + iPhone £1,000 + peripherals £500 = £4,000 capex,
  amortised ~£111/month. Year 1 includes the £4,000 cash outflow.
- Per hire: ~£3,000 capex (MacBook + testing device), adds ~£83/month amortised.
- Ongoing maintenance (repairs, accessories): ~£20/month.

| Team size | Monthly equipment cost |
|---|---|
| Solo | £111 |
| +1 hire | £150 |
| +2 hires | £190 |
| +3 hires | £250 |

**Electricity:**

| Setup | Monthly |
|---|---|
| Home working | £50 |
| Co-working (partial) | £100 |
| Small office | £150 |
| Larger office | £200 |

**Employer costs on staff (UK):**

On top of gross salary:
- Employer National Insurance: 13.8% on earnings above £758/month
- Auto-enrolment pension: 3% of gross salary
- Combined overhead adds ~13–14% to gross salary cost

| Role | Gross/mo | Employer NI | Pension | Total cost/mo |
|---|---|---|---|---|
| Junior dev / contractor | £3,000 | £309 | £90 | **£3,399** |
| QA / support | £2,000 | £171 | £60 | **£2,231** |
| Senior dev | £5,000 | £585 | £150 | **£5,735** |

Contractors have no employer NI or pension overhead — ~14% cheaper than
employed staff. First hire is likely a contractor until revenue is comfortable.

**Corporation Tax (UK):**

- Up to £50K annual profit: 19% (small profits rate)
- £50K–£250K: ~26.5% (marginal relief band)
- Above £250K: 25% flat

Andrew's personal salary/dividends are not included in the model — that is a
separate personal tax decision. Typical UK owner-director approach: take a small
salary up to the NI threshold (£12,570/year) as a business cost, reducing CT on
that amount, then take the remainder as dividends at dividend tax rates.

**VAT:** App Store subscriptions are handled by Apple as merchant of record.
Apple collects and remits VAT — the developer receives net of VAT already
handled. No VAT burden on developer for App Store income. Any direct sales
channel above £90K/year would require VAT registration separately.

---

## Full annual P&L by milestone

### 1,000 users — Solo, home office, no hires

| | Conservative | Optimistic |
|---|---|---|
| Net revenue (after Apple 15%) | £6,018 | £17,238 |
| Infra | £1,452 | £1,452 |
| Office | £0 | £0 |
| Equipment (inc. Year 1 capex) | £1,332 | £1,332 |
| Electricity | £600 | £600 |
| Staff | £0 | £0 |
| **Total costs** | **£3,384** | **£3,384** |
| **Pre-tax profit** | **£2,634** | **£13,854** |
| Corporation Tax | £500 (19%) | £2,632 (19%) |
| **After-tax annual profit** | **£2,134** | **£11,222** |

### 10,000 users — Phase 3, one hire (junior dev, £3,000/mo gross)

| | Conservative | Optimistic |
|---|---|---|
| Net revenue (after Apple 15%) | £60,180 | £172,380 |
| Infra | £1,452 | £1,452 |
| Office (co-working) | £4,800 | £4,800 |
| Equipment (inc. hire capex) | £1,800 | £1,800 |
| Electricity | £1,200 | £1,200 |
| Staff gross | £36,000 | £36,000 |
| Employer NI | £3,708 | £3,708 |
| Employer pension | £1,080 | £1,080 |
| **Total costs** | **£50,040** | **£50,040** |
| **Pre-tax profit** | **£10,140** | **£122,340** |
| Corporation Tax | £1,927 (19%) | £29,870 (~25%) |
| **After-tax annual profit** | **£8,213** | **£92,470** |

### 50,000 users — Two hires (junior dev + QA/support, £5,000/mo gross combined)

†Optimistic above Apple £790K threshold at this scale → 30% commission applied.

| | Conservative | Optimistic† |
|---|---|---|
| Net revenue | £300,900 | £709,800 |
| Infra | £1,452 | £1,452 |
| Office (serviced) | £12,000 | £12,000 |
| Equipment | £2,280 | £2,280 |
| Electricity | £1,800 | £1,800 |
| Staff gross | £60,000 | £60,000 |
| Employer NI | £5,760 | £5,760 |
| Employer pension | £1,800 | £1,800 |
| **Total costs** | **£85,092** | **£85,092** |
| **Pre-tax profit** | **£215,808** | **£624,708** |
| Corporation Tax (~25%) | £53,952 | £156,177 |
| **After-tax annual profit** | **£161,856** | **£468,531** |

### 100,000 users — Three hires (junior dev + QA/support + senior dev, £10,000/mo gross combined)

†Conservative still below Apple threshold at this scale (15% applies). Optimistic
well above (30% applied to optimistic net revenue above).

| | Conservative† | Optimistic |
|---|---|---|
| Net revenue | £601,800 | £1,419,600 |
| Infra (inc. Cloudflare overage) | £2,052 | £2,052 |
| Office | £21,600 | £21,600 |
| Equipment | £3,000 | £3,000 |
| Electricity | £2,400 | £2,400 |
| Staff gross | £120,000 | £120,000 |
| Employer NI | £12,780 | £12,780 |
| Employer pension | £3,600 | £3,600 |
| **Total costs** | **£165,432** | **£165,432** |
| **Pre-tax profit** | **£436,368** | **£1,254,168** |
| Corporation Tax (25%) | £109,092 | £313,542 |
| **After-tax annual profit** | **£327,276** | **£940,626** |

---

## Summary — After-tax annual profit

| Users | Staff | After-tax (cons.) | After-tax (opt.) |
|---|---|---|---|
| 1,000 | Solo | £2,134 | £11,222 |
| 10,000 | 1 hire | £8,213 | £92,470 |
| 50,000 | 2 hires | £161,856 | £468,531 |
| 100,000 | 3 hires | £327,276 | £940,626 |

*All figures are annual. Monthly equivalent: divide by 12.*

---

## Staff hire triggers

Hire when after-tax profit comfortably covers role cost at 2× (safety margin
for slower months). Based on total employer cost including NI and pension.

| Role | Total employer cost/mo | Safe annual revenue needed | Users (cons.) | Users (opt.) |
|---|---|---|---|---|
| Junior dev / contractor | £3,399 | ~£85,000 net | ~10,600 | ~3,800 |
| QA / support | £2,231 | ~£58,000 net | ~7,200 | ~2,600 |
| Senior dev | £5,735 | ~£138,000 net | ~17,200 | ~6,100 |

The 10K conservative / first hire inflection is tight (£8,213 after-tax annual
profit against a hire costing £40,788/year). Under conservative uptake, the
first hire is financially comfortable closer to 15,000–20,000 users. Under
optimistic uptake it is viable from ~5,000 users.

---

## Breakeven (updated from prior model)

| Phase | Conservative | Optimistic |
|---|---|---|
| Early (no Claude Max, solo) | **~68 users** | **~24 users** |
| Growth (+ Claude Max, solo) | **~242 users** | **~84 users** |

Improved from the prior model's ~126/~31 (conservative/optimistic). The
improvement comes from higher ARPU driven by cloud bundling at the 3 Leagues
tier — the 3L tier is now meaningfully more valuable than before (leagues +
games + cloud vs leagues only), which lifts conversion and average spend.

---

## Key findings

1. **Apple's 15/30% commission is the largest cost at every scale** — plan
   around it. Above ~40K users (optimistic) or ~112K users (conservative) the
   rate doubles to 30%. Pricing decisions must account for this floor.

2. **Cloudflare cost is permanently immaterial.** Even at 500K users with
   maximum hammering, Cloudflare stays under $1,300/month. Never price for
   infra cost recovery — price for value.

3. **The danger zone is 100–3,000 users.** Three environments plus Claude Max
   cost £121/month in infra before office and equipment. Revenue is still modest.
   Conservative GP at 1,000 users is £502/month — profitable but thin. This is
   the phase where conversion rate at the 3 Leagues tier matters most.

4. **The first hire is the hardest inflection.** Under conservative uptake it
   doesn't become comfortable until ~15,000–20,000 users. The gap between
   conservative and optimistic is entirely ARPU-driven — 3 Leagues conversion
   rate is the single lever that determines when hiring becomes viable.

5. **Remote working saves £4,800–£21,600/year.** A remote-first team removes
   the office line entirely, improving after-tax profit by £3,600–£16,200.
   Worth establishing as the default while the team is small and trust-based.

6. **football-data.org is the only cost that doesn't scale favourably.** $30/mo
   flat, dominant at low user counts, and subject to repricing. Contingency:
   self-caching strategy, alternative providers, or a pricing clause. Address
   before hard scaling.

7. **This needs real RevenueCat data to validate.** Conversion rate assumptions
   (conservative 18% paid, optimistic 50% paid) are speculative. Every model
   output is downstream of these numbers. Treat as directional — run A/B price
   tests on the 3 Leagues tier first, as that's where most conversions will
   happen.

---

## Ad revenue

Ad revenue (free-tier users only, banner/interstitial):
- ~16% of total revenue under conservative uptake
- ~2% under optimistic uptake

Ads are a floor and churn offset, not the revenue engine. Subscriptions
dominate once any meaningful conversion happens. Assumption: $5 eCPM cautious
estimate, 65% ad fill+completion rate.
