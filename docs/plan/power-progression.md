# Plan: powers as a daily progression

> **Status: delivered.** The skill tree, charge economy and power levels described
> here shipped. Kept for the reasoning. See `docs/powers.md` and
> `docs/progression.md` for what exists.

Turning bomb, laser, collapse and fit from a lucky spike inside one run into
something that carries across days.

---

## What is wrong with them today

Powers arrive two ways — a per-hand roll weighted by `Difficulty.tray_special`,
and a combo reward — and are consumed the moment they are placed. Nothing about
them persists. `scores.cfg` records no power use, and no file anywhere stores a
count.

So a power is a pleasant surprise and nothing more. **Nothing the player does
today makes tomorrow's powers better**, and there is no reason to open the app
on Tuesday because of what happened on Monday. That is the gap.

The design already anticipated the fix: section 07 shows powers as an owned
inventory with counts (`BOMB 2 · LASER 1 · FALL 3 · FIT 1`) and a shop.

---

## The mechanism

Four layers. Each is useful alone, and they are listed in build order.

### Layer 1 — Powers become owned

An inventory that survives a run: `{bomb: 2, laser: 1, collapse: 3, fit: 1}` in
`user://`, with the HUD strip the design already draws. A owned power is
deployed deliberately rather than dealt.

**The rule that makes this safe: owned powers are ADDITIVE.** The existing
random drops stay exactly as they are. Inventory is a bonus on top, never a
replacement.

This matters more than it sounds. If owned powers *replaced* drops, a player
who spends their stock has a worse game than one who never played — the game
gets harder the more you play it, which is an energy system wearing a costume.
`docs/plan/retention.md` argues against those, and this would be one.

### Layer 2 — Power mastery *(the interesting part)*

Each power keeps its own XP track, levelled by **using** it:

| Power | Lv1 (today) | Lv2 | Lv3 |
|---|---|---|---|
| Bomb | clears half the board | +1 row beyond the split | leaves the split row primed for a clear |
| Laser | one row + column | beam widens to two | fires the diagonals too |
| Collapse | drops every tile | drops, then compacts toward the centre | chains once if the drop clears a line |
| Fit | fills up to 5 cells | up to 7 | prefers cells that complete a line |

Why this is the strongest of the four layers:

- **It rewards spending, not hoarding.** The classic failure of an owned-item
  system is that players save everything for a run that never comes. Mastery
  inverts that: the only way to a better bomb is to keep using bombs.
- **Four parallel tracks** give a long tail without new content.
- It is progress that **cannot be lost** and does not gate play.

### Layer 3 — Daily charge and streak *(the daily hook)*

- Opening the game grants the day's charge: **3 powers**, plus **+1 per
  consecutive day** up to a cap of 7.
- Unused powers **roll over** to a ceiling (say 12). A player is never punished
  for having played yesterday.
- A missed day costs the streak bonus, not the stock.

This is the "tracking level daily" piece: the streak is visible on the menu,
and the number going up is the reason to come back.

### Layer 4 — Account level

XP from every run — lines, combos, powers used, boards solved — feeding the
`LEVEL 026` readout the design already draws in the HUD.

Levels should buy **capacity, not power**: +1 daily charge, +1 rollover
ceiling, a fourth mastery slot. Keep raw strength on the mastery tracks, where
it is earned by using the thing rather than by playing a lot.

Every run advances something, including a bad one — which is the property the
game currently lacks entirely.

### Layer 5 — Gems and shop *(last, and optional)*

Only after the above works. Keep every power earnable by play; a shop that
sells the only route to powers turns the leaderboard into a price list. See the
pay-to-win note in `retention.md`.

---

## Risks worth deciding on before building

**Difficulty double-dip.** `Difficulty.tray_special` already scales power
frequency by score band — deliberately dropping to 0.15 in Super Hard so the
late game is bare. Adding owned powers on top makes exactly that stretch easier
again, undoing the ramp. Either the high bands need retuning, or owned powers
should be unavailable above a score threshold. **Decide this first; it changes
the tuning of everything else.**

**Score inflation.** Mastery makes powers stronger over months, so scores drift
upward and old leaderboard entries become unreachable. Options: accept it
(most games do), reset boards seasonally, or record mastery level alongside the
score. Worth a decision, not worth blocking on.

**Hoarding.** Mastery counteracts it, but reinforce it: show mastery progress
in the HUD at the moment a power is spent, so spending visibly *is* progress.

**The energy trap.** Restated because it is the one that would actually damage
the game: if daily charge ever becomes the *only* source of powers, this plan
has made the game worse. Random drops stay.

---

## Build order

| # | Layer | Effort | Why here |
|---|---|---|---|
| 0 | Analytics counters | 0.5 d | Power use, hoard rate and daily return are unmeasurable now. From `retention.md`. |
| 1 | Inventory + HUD strip | 2 d | Everything else needs it. |
| 2 | Mastery tracks | 3 d | The actual hook. Four effects to write and balance. |
| 3 | Daily charge + streak | 1.5 d | The daily reason to return. |
| 4 | Account level + XP | 2 d | Ties runs to the other three. |
| 5 | Gems and shop | 3–4 d | Only if 1–4 land. |

Roughly two weeks to layer 4.

**Sequencing note:** ship layers 1 and 2 together. Inventory without mastery is
just a thing to hoard, and it is the version most likely to make the game
slightly worse on its own.

## Open questions

- Should powers be usable **on demand** from the inventory, or only appear in
  the tray? On-demand is a bigger change to `game.gd` input and lets a player
  break a stall — which is powerful, and possibly better sold as the rewarded
  ad revive from `monetisation.md` than given away.
- Does mastery apply in **Puzzle** mode? A seeded board plus a levelled bomb is
  no longer the same puzzle for two players, which undermines "board N is
  identical for everyone".
- Should Big Palette get its own charge rate? A 12x12 board absorbs powers very
  differently from 8x8.
