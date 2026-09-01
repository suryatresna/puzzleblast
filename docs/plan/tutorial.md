# Plan: teaching the game

> **Status: delivered.** The coach ladder, the free tutorial bomb and the
> How to play screen all shipped. Open questions that remain: whether to gate
> to one new hint per run, and the copy for rungs 8-11 has not been seen in
> play. See `ui/widgets/coach.gd` for what exists.

How to teach thirteen powers, a charge economy, a skill tree and four modes
without a modal tutorial — and without touching `game.gd`'s input handling.

---

## Diagnosis

The game currently teaches exactly one thing, and it never changes:

```
scenes/game.tscn:388
text = "drag a card onto the board  ·  fill a row or column to clear it"
```

That string is static markup. `game.gd` has **zero** references to `%Hint`, so
every player sees the same sentence forever — on their first placement and on
their thousandth.

Everything else is undocumented in-product:

| System | How a player finds out today |
|---|---|
| Combos, and that two lines at once scores 4× two singles | Trial and error |
| Greyed-out cards mean "fits nowhere" | Inference |
| The power strip, and that powers drag like cards | Guessing |
| Charge comes from combos of 2+ | Guessing |
| A charged power keeps a dead tray alive | Never — the run just doesn't end |
| Powers are chosen on the Profile screen | Never |
| Levels come from lifetime score, so a bad run still counts | Never |
| The 2× session, and how to earn one | Never |
| That four modes exist | The Modes button |

The last four are invisible: there is no moment in play where the game says them.

## The constraint that decides the shape

From `docs/architecture.md`, describing why the loadout is a pre-run decision:

> …deliberately a pre-run decision, so `game.gd` never grows a second modal
> input state.

A scripted walkthrough — *"now drag **this** card **there**"* — is precisely that
second modal state. It must block input, gate what is tappable, survive the
player ignoring it, and unwind cleanly on pause, restart and game over.
`game.gd` is already ~1,400 lines and owns all pointer handling. Adding a modal
mode to it trades a real, recurring maintenance cost for a one-time onboarding
gain.

**So: coach, don't walk through.**

## Design

**One hint at a time, chosen from the player's actual state, shown in the label
that already exists, retired once seen.**

Why this shape:

- **Reuses `%Hint`.** Already positioned under the tray, themed `FaintLabel`,
  autowrapping. No new scene, no layout risk — and the board is width-limited,
  so there is no room for a new row anyway.
- **No input gating**, so no second modal state and no new failure mode.
- **Teaches each system when it first becomes relevant**, which is when it will
  stick. Nobody reads a wall of rules before playing.
- **State-driven, so it is testable headlessly** — no synthesised input needed
  to prove a hint fires.

### The ladder

Each entry is a condition, a line of copy, and an id. The coach shows the
highest-priority entry whose condition holds and whose id is unseen, then marks
it seen.

| # | Fires when | Copy |
|---|---|---|
| 1 | first ever run, nothing placed | drag a card onto the board |
| 2 | after the first placement | fill a row or column to clear it |
| 3 | a tray card is dimmed | greyed cards fit nowhere — plan around them |
| 4 | after the first clear | clear again next turn to build a combo |
| 5 | combo reaches 2 | two lines at once scores 4× two singles |
| 6 | the strip first appears, tutorial bomb pending | a free bomb — drag it onto the board |
| 7 | the tutorial bomb has been fired | that one was free; powers cost charge |
| 8 | `pending_unlocks > 0` | you've earned a power — choose it on the Profile |
| 9 | charge < the cheapest equipped cost | combos charge your powers, 2× and up |
| 10 | tray dead, a power affordable | a charged power can save a stuck board |
| 11 | after the first game over | every run banks XP, win or lose |

**Recurring, deliberately outside the seen-once ladder:** the 2× nudge
(`plays_today == PLAYS_FOR_BONUS - 1`) is a prompt, not a lesson, and should fire
every time it is true. `game.gd._bonus_hint()` already writes this on the
game-over panel; the coach should not duplicate it mid-run.

### The power tutorial: one free bomb

Powers are the hardest thing here to discover — a strip of icons that costs a
currency earned from a mechanic nobody has explained. It needs a worked example,
and the bomb is the right one: **half the board vanishing is unmistakable**,
where Fit or Collapse are subtle enough that a first-timer may not notice
anything happened.

**But the bomb is unreachable.** It sits in tier 5, gated at level 50 —
8,995,387 lifetime score, roughly 300 days of committed play. Tier 1 (Fit,
Collapse) is what a new player actually owns. So the tutorial cannot use the
bomb the player has; it has to hand them one.

**A one-off free bomb, outside the tree and outside the economy.** Granted the
first time the power strip appears (level 2, when the first loadout slot
unlocks), it sits in the strip beside the real slot, marked **FREE** rather than
with a charge cost, and is consumed by one use.

That teaches the whole loop in a single cast:

1. powers live in the strip
2. you drag them onto the board like a card
3. they do something dramatic
4. …and then rung 7 lands: *that one was free; powers cost charge* — which is
   the moment the charge meter under the strip starts meaning something.

It also gives the player a reason to look at the Profile, because the next power
is one they have to choose.

**Why not just move the bomb to tier 1?** Because the tree is ordered by charge
cost and the bomb is the most expensive power in the game at 8. Reordering it
would either break that ordering or misprice the bomb. A scripted gift is
honest: it is a lesson, not a reward.

**Implementation.** `Progress` gains `_tutorial_power_used: bool` (persisted
beside `seen_hints`) with `tutorial_power_pending()` and `use_tutorial_power()`.
`game.gd._sync_powers()` renders one extra strip slot while pending;
`_begin_drag` picks it up like any other power — the guard there tests
`can_afford`, so the free bomb needs an explicit exemption — and `_fire_power`
special-cases it to skip `Progress.spend()` and call `use_tutorial_power()`
instead.

`Blocks.bomb_piece()` already exists and is **currently unused** — a leftover
from before powers moved to the strip. This gives it a purpose; otherwise it
should be deleted.

**The invariants this must not break:**

- **It must not be free charge.** `use_tutorial_power()` sets the flag *before*
  `place()` is called, or a board that refuses the drop hands out a second free
  bomb. The existing rule is the opposite way round — read the level before
  spending, spend after `place()` returns — so this is a deliberate exception
  and needs saying at the call site.
- **It must not appear in Puzzle mode**, where `_powers_enabled` is false and a
  seeded board plus a bomb is not the same puzzle for two players.
- **It must not survive a wipe.** `Progress.wipe()` resets it, so a reset
  profile is taught again.
- **The strip's slot count is level-derived** (`loadout_size()`), and
  `_begin_drag` guards on `i >= loadout_size()`. The tutorial slot sits outside
  that range, so both the render loop and the input loop need to know about it —
  miss the second and the bomb is drawn but not draggable, which is exactly the
  class of bug that killed dragging once already.

### Files

| File | Change |
|---|---|
| `ui/widgets/coach.gd` | **New**, ~120 lines. Owns the ladder as a table and picks the current hint. Pure: takes state, returns an id and a string. |
| `scenes/game.gd` | Call `_coach.refresh()` where the HUD already syncs — `_sync_tray`, `_on_lines_cleared`, `_sync_powers`, `_restart`. No new input paths. |
| `autoload/progress.gd` | Persist `seen_hints: Array[int]` beside `seen_level`; `mark_hint_seen()` / `hint_seen()`. Plus `_tutorial_power_used` and its two accessors. |
| `scenes/game.gd` (strip) | One extra slot while the tutorial bomb is pending, in **both** `_sync_powers` and `_begin_drag`; `_fire_power` skips the charge spend for it. |
| `scenes/how_to_play.{tscn,gd}` | **New.** Static reference, built like `about.gd` on `MenuScreen`, rows from a table as `settings.gd` does. |
| `scenes/main_menu.tscn` | One entry point to the above. |

Keeping the ladder a **table** matters for the same reason `POWER_ATMOSPHERE`
and `Modes.DEFS` are tables: adding a hint should be one row, not one branch.

### The static screen

"How to play", reached from the menu, is the reference for someone who wants the
whole picture at once: the scoring formula, what each power does, what charge is,
how levels work. It is cheap — it is the About page with more rows — and it takes
the *completeness* burden off the coach, which then only has to handle first
contact.

Note `README.md` already contains most of this copy and is accurate; it is the
obvious source.

## Verification

- **Each hint fires, once.** Drive `Progress` and a bare `Board` into each of the
  ten conditions and assert the expected id. Then assert it does **not** fire a
  second time, and that `seen_hints` survives a reload.
- **Priority is unambiguous.** Construct a state where several conditions hold at
  once and assert which wins. Ambiguity here is the likeliest defect.
- **A veteran sees nothing.** A profile with every hint seen shows the original
  static line, not a blank label.
- **Extend `tools/e2e.tscn`** — it already boots the app and plays a real run.
  Assert a wiped profile sees hint #1 on its first frame, and that after the run
  the seen set has grown.
- **The free bomb is free, once.** Fire it and assert charge is unchanged and the
  flag is set; fire again and assert it is gone from the strip and the next cast
  bills normally. Drop it off the board and assert it is **not** handed out
  twice.
- **Screenshot the bomb cast**, because "half the board vanished" is the entire
  lesson and no assertion can tell you it read as dramatic.
- **Screenshot the first-run state**, since a hint that is present but unreadable
  against the backdrop passes every assertion. `--headless` cannot judge this;
  use a windowed Movie Maker capture at 540×960 (see `docs/testing.md`).

## Risks and open questions

- **Copy length.** `%Hint` is one autowrapping line under the tray. Anything
  longer than about eight words will wrap to two and push the layout. Write to
  the width, and check the longest entry in a capture.
- **Hint fatigue.** Ten hints in the first few runs is a lot. Consider gating to
  at most one *new* hint per run, so they arrive over a week rather than in the
  first four minutes.
- **The recurring 2× nudge is the exception**, and exceptions in a seen-once
  system are where bugs live. Keep it structurally separate rather than adding a
  `repeatable` flag to the ladder.
- **The tutorial bomb is the one piece of scripted state in an otherwise passive
  design.** It is worth it — powers are the least discoverable system here — but
  it is also the only part that can leave the strip in a state the economy did
  not produce. Keep it to a single flag and a single use.
- **Scope.** Hints 1–4 cover the actual first-run cliff and are roughly a third
  of the work. If this should ship small, ship those and the static screen; 5–10
  teach systems a player only meets after several sessions.

## What this deliberately does not do

- **No scripted walkthrough.** See the constraint above.
- **No forced first-run flow.** A player who already understands block puzzles
  should be able to play immediately; every hint here is passive text.
- **No new HUD furniture.** The board is width-limited at 1048 of 1080px and
  Sprint has no vertical slack, so a coach panel would cost board size. The
  existing label is free.
