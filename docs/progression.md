# Progression

Levels, the skill tree that gates the powers, and the game modes.

## The skill tree

`Progress.POWER_TIERS` is the single source of truth for the order the player meets the powers in: five tiers, ordered weakest to strongest by charge cost, each sealed behind an account level (1, 25, 30, 45, 50). **Two powers break that ordering on purpose.** *Rewind* — at 7 charge it belongs in tier 5, but it is the forgiveness power and gating it behind the hardest levels would put it furthest from the players who need it most. *Bomb* — at 8 it is the dearest power in the game, yet it opens the tree, because it is the one power a new player cannot misread: half the board vanishing explains itself, where Fit and Collapse are subtle enough to go unnoticed. Its price is the brake — at `BASE_MAX_CHARGE` it takes most of a full bank, so owning it early does not mean firing it often. Tiers need not be the same width — a new power joins the tier its cost puts it in rather than getting a gate of its own. `unlock()` refuses a power whose tier has not opened, so a **banked unlock cannot skip a gate** — which of a tier's two you take is your choice, the order the tiers arrive in is not. `profile.gd` builds the list straight off this table rather than off `Blocks.ALL_POWERS`, so a re-tiering needs no UI change.

**Retuning the curve re-levels every save**, because `_level` is derived from `_total_score` on load and never stored. `Progress._catch_up_rewards()` is what makes that survivable: it pays out every level reached but not yet settled and records how far it has got in `rewarded_through`. Before it existed, `_apply_reward` ran only inside `add_score`'s own loop, so a level arriving any other way silently skipped its grants — a save jumping L6→L30 lost 4 of its 6 power unlocks permanently, landing on an open tier with nothing to spend. `"slot"` and `"charge"` never had the problem: `loadout_size()` and `max_charge()` re-derive from `_level` rather than accumulating. **Any future change to `LEVEL_GROWTH` is safe only because of this ledger.**

`REWARDS`' `"power"` grants are spaced to match the gates (2, 4, then two per tier as it opens). **Keep them in step**: the old schedule handed out all ten by L20, which under the tree would leave eight unlocks stuck in the bank behind a gate. There is a test asserting no level ever banks more unlocks than the open tiers can absorb.

**The curve was retuned to make the tree reachable.** At `LEVEL_GROWTH` 1.35 only tier 1 was obtainable: L25 was 3.8M lifetime score, L30 17.2M, L45 1.55 **billion** — against maybe 1–20k a run. Four of five tiers and the 12×12 board were decoration. At **1.16** the same gate levels cost 214k / 456k / 4.3M / 9.0M, or roughly a week, a fortnight, five months and ten months of committed play. `LEVEL_BASE` is unchanged, so L2 is still exactly 1,000 and no early-game copy went stale.

The last `"power"` grant sits at **L52, not L55**: tier 5 opens at L50, and on this curve L55 is 630 days against L50's 300, so the tier's second power arrived more than twice as late as the tier itself. Every tier now completes within ~100 days of opening. Since the bomb moved to tier 1, tier 5 holds Blackhole alone — the L50 and L52 grants clear it and any unlock still banked from an earlier tier.

## The doubled-XP session

A banked 2× session, earned two ways — a **3-day play streak**, or **3 plays in one day** — both granting the same single bonus. `_bonus_ready` is a bool rather than a count, so hitting both triggers, or one repeatedly, can never stack them into a farm. `Progress` owns it beside the streak it already tracked; `game.gd._restart()` calls `touch_day()` (which can itself bank one) then `note_run_started()` then `claim_bonus()`, in that order, so a bonus earned by crossing into a new day is spendable on that very run.

**It doubles the XP banked, not the board score.** `_bank()` is the single place run score becomes XP, so the multiplier goes on the delta there; doubling `board.score` would push an inflated number through `Scores.submit` and make bonus runs incomparable on the leaderboard.

The session announces itself for its whole length rather than once: `Effects.time_field()` is re-lit on a slow repeating tween and `%XpKey` reads `LEVEL 12 · 2x`. The backdrop is deliberately untouched — the combo flow owns it, and a session-long tint would fight every clear. The game-over panel appends the nudge the feature exists for ("2 more runs today earn DOUBLE XP") to `%RankLabel`.

Worth knowing: this is a **retention loop, not a pacing fix**. At 10 runs a day it adds roughly 3–25% to accumulation. Even doubling every run forever would leave the old ×1.35 L50 318 years away — the curve retune above is what actually opened the tree.

## Game modes

Three, defined in `Modes.DEFS`; the picker (`scenes/mode_select.tscn`) builds its cards from that table, so a fourth mode is a table entry plus whatever `game.gd` needs in `_setup_mode()`.

- **Palette** — the endless run. Its grid is **level-driven**: 8x8 until `Progress.BIG_BOARD_LEVEL` (25), then 12x12. `Modes.grid_of()` reads `Progress` at call time, guarded, because `Modes` is registered first.
- **Big Palette** — the same rules on a 12x12 grid. The board's grid is a variable (`Board.grid`, set from `Modes.GRIDS` in `_setup_mode`), not a constant; `Board.SIZE` is only the default now.
- **Sprint** — `scripts/fuse_bar.gd` counts 60 seconds down as a burning fuse; when it empties it calls `_board.declare_game_over()` rather than ending the run itself, so every end-of-run path stays in one place.
- **Puzzle** — `Modes.puzzle_layout(level)` returns a starting board, seeded from the level so board N is always identical. Two invariants it must keep: no row or column may start full (it would clear the instant it is drawn), and the board must leave room for the opening deal. The objective is lines-cleared, tracked in `game.gd._puzzle_cleared`.

**The design says "120 hand-built boards"; these are generated, not authored.** Replacing `puzzle_layout()` with real layouts is the only change that would need.

The design's fourth mode (Daily) and the `TILE SET` row are not built — Daily is gated on a level system that does not exist, and the tile set is fixed by `Themes.ACTIVE`.
