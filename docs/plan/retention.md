# Plan: keeping players coming back

Research and recommendations for what to build next, ranked by what it is
likely to return against what it costs here.

---

## Diagnosis

The game already does the hard part well. What it is missing is not depth — it
is a reason to open the app tomorrow.

**Strong already (the "one more run" loop):**

| Hook | Where |
|---|---|
| Escalating combo tiers, five of them, with words and a colour flow | `effects.gd` |
| Difficulty that tightens with score across four bands | `difficulty.gd` |
| Four powers with distinct effects | `blocks.gd` |
| Personal-best chase with confetti on a new record | `game.gd` |
| Three modes | `modes.gd` |
| Game Center leaderboards | `game_services.gd` |

**Missing entirely (the "come back tomorrow" loop):**

Nothing in the game persists across sessions except a score table. There is no
progression, no daily reason to return, nothing to unlock, and nothing that
carries from one run to the next. A player who has beaten their best has no
open loop pulling them back.

Notably, **the design already specced exactly this** and it went unbuilt:
`DAILY` mode, a `LEVEL 026` readout with a progress bar, a gem currency, a
shop, and a `TILE SET` picker.

## A note on "addictive"

Worth separating two things, because they behave differently commercially:

**Compelling loops** — a daily reason to return, visible progress, a near-miss
that begs a retry — grow retention and revenue together. Everything
recommended below is this kind.

**Extractive patterns** — energy meters, harsh streak punishment, randomised
paid rewards — can lift short-term numbers but carry real costs: loot boxes are
banned in Belgium and the Netherlands and require odds disclosure in several
markets, both app stores demand disclosure, and in this genre the market
leaders (Block Blast, Woodoku) *do not use energy systems* and lead anyway.
Skipping them is a commercial judgement, not only an ethical one. Flagged
individually below.

---

## Ranked recommendations

### 1. Daily challenge + streak — biggest single lever

The strongest retention mechanic in this genre, and the design already has a
`DAILY` card.

- One seeded board per calendar day, same for everyone, **one attempt**.
- A visible streak counter; the streak is the hook, not the board.
- Show it on the menu with today's state: unplayed / played / streak length.

**Cheap here.** `Modes.puzzle_layout()` already generates a deterministic board
from a seed — pass the date as the seed and most of it exists. Estimated 1–2
days including the menu card.

**Do include a streak freeze** (one forgiven miss per week, or a cheap
buy-back). Streaks that shatter after 60 days cause churn at exactly the moment
the player was most invested.

### 2. Revive with a rewarded ad — retention *and* revenue

At game over, offer one continuation in exchange for watching a rewarded ad:
clear the bottom two rows and play on, once per run.

This is the best-fitting monetisation in the whole plan:

- Rewarded ads earn several times an interstitial's eCPM and are **opt-in**,
  so they are not resented.
- It is offered exactly when the player wants it — they just lost a good run.
- It lengthens sessions and raises scores, which feeds the leaderboard.
- It softens the interstitial cadence problem raised in
  `docs/plan/monetisation.md`: a rewarded revive gives a natural, welcome ad
  slot, so forced interstitials can stay rare.

Depends on Phase 1 of the monetisation plan. Estimated 1 day once the SDK works.

### 3. Progression: level and XP

The design shows `LEVEL 026` and a 10% progress bar in the HUD, and neither
exists.

- XP from every run — lines cleared, combos, board solved — so **every run
  advances something**, including a bad one. This is the key property: right
  now a poor run is worth nothing at all.
- Levels gate unlocks (below), giving the number meaning.

Estimated 2 days. Needs a small `Progress` autoload and a HUD bar.

### 4. Unlockable themes — nearly free, high perceived value

**The theme system is already built.** Three complete themes exist — Classic,
Pixel Warm, Pixel Dark — and `Themes.ACTIVE` currently hardcodes one, with the
picker deliberately removed.

Turning those into level unlocks is perhaps half a day: restore a picker,
gate entries on level, persist the choice. The design's `TILE SET · WARM RETRO ▸`
row is literally this.

Best effort-to-value ratio in the plan, because the expensive part is done.

### 5. Daily missions

Three rotating goals — "clear 20 lines", "reach a 3× combo", "use two lasers" —
refreshing daily, paying XP or currency.

Gives direction to a session beyond chasing score, and pulls players into modes
they would otherwise ignore. Estimated 2–3 days; wants the progression system
first.

### 6. Currency and shop — build last

The design has gems and purchasable powers. Reasonable, but:

- Earn-only first. Powers-for-money in a score game invites "pay to top the
  leaderboard", which devalues the board for everyone else.
- If powers are ever purchasable, consider a separate leaderboard for runs that
  used bought powers.

Estimated 3–4 days. Lowest priority: it monetises engagement that does not
exist yet.

---

## What I would not build

| Pattern | Why not |
|---|---|
| **Energy / lives** | Blocks play, which is the thing that retains. The genre leaders do not use it. Highest uninstall risk of anything here. |
| **Loot boxes / randomised paid rewards** | Banned in Belgium and the Netherlands, odds disclosure required in several markets, store disclosure required. Not worth it at this scale. |
| **Harsh streak loss** | Churns the most invested players. Use a freeze. |
| **Pay-to-win powers on the shared leaderboard** | Devalues the leaderboard, which is itself a retention feature. |

## You cannot measure any of this yet

There is **no analytics of any kind** in the project. Every recommendation
above is a hypothesis, and without instrumentation none of them can be
confirmed or unwound.

Before building much of it, record at minimum: runs per session, session
length, day-1 and day-7 return, daily-challenge participation, and revive
take-up. Local aggregate counters in `user://` are enough to start and need no
third-party SDK or extra privacy disclosure.

## Suggested order

1. **Analytics counters** — half a day, makes everything else measurable.
2. **Unlockable themes** — half a day, the work is already done.
3. **Daily challenge + streak** — the biggest lever.
4. **Rewarded revive** — after monetisation Phase 1.
5. **Level / XP** — gives 2 and 3 something to feed.
6. Daily missions.
7. Currency and shop.

Roughly two weeks to item 5, which is where most of the retention gain sits.

## Open questions

- Target audience age? If the game is aimed at children, the ad and data rules
  change completely (COPPA, restricted ad serving) and that reshapes the whole
  monetisation plan.
- Is the Daily meant to be competitive (a shared leaderboard per day) or
  personal? Competitive is stickier but needs a backend; Game Center can carry
  it with a daily-reset leaderboard.
