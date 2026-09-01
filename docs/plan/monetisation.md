# Plan: AdMob + "Ads Free" purchase

Two features that only make sense together: interstitial ads after a
disappointing run, and a one-off purchase that removes them.

Nothing here is built yet. Written after checking what actually ships, so the
version numbers and the delivery mechanisms are real rather than assumed.

---

## The surprise worth knowing first

**AdMob is not a plugin — it is a custom export template.**

Game Center drops a `.xcframework` into `ios/plugins/`. AdMob cannot: the
Google Mobile Ads SDK has to be linked into the engine binary itself. So
[poingstudios/godot-admob-plugin][p] ships *modified export templates*:

| Asset (release v5.0.0, stable) | What it is |
|---|---|
| `ios-template-v4.7.2.zip` | iOS export template, engine + GMA SDK |
| `android-template-v4.7.2.zip` | Android equivalent |
| `poing-godot-admob-v5.0.0.zip` | the GDScript addon (`addons/admob/`) |

There are builds for **exactly 4.7.2**, so nothing needs compiling — unlike
Game Center, which had no Godot 4 build at all and had to be built from source
and patched.

The older `poingstudios/godot-admob-ios` and `-android` repos are **archived**;
`godot-admob-plugin` is the successor.

[p]: https://github.com/poingstudios/godot-admob-plugin

### The risk this creates

Our Game Center plugin is a static library **we built ourselves against stock
4.7.2 headers**. It has to link against Poing's custom template, which is a
different engine build. If they compiled with different flags, the
`ClassDB::bind_methodfi` mismatch that already bit us once comes back:

```
Undefined symbols: "ClassDB::bind_methodfi(..., char const*, ...)"
```

**Verify this before building anything on top.** Swap in the custom template,
export, and confirm the link is clean. If it is not, the gamecenter plugin must
be rebuilt against Poing's engine source rather than stock. This is the single
thing most likely to cost a day, so do it first.

---

## Phase 1 — Prove the template works (half a day)

1. Download `ios-template-v4.7.2.zip` and the addon from release v5.0.0.
2. Point the iOS preset at the custom template
   (`custom_template/debug` and `/release`).
3. Export debug. **Check the link, and check Game Center still signs in.**
4. Only then continue.

Do not write any ad code until this passes.

## Phase 2 — Ads (1–2 days)

`scripts/ads.gd`, autoloaded as `Ads`, following the shape `GameServices`
already uses: guarded, silent when unavailable, never load-bearing.

```
Ads.available()          # plugin present and initialised
Ads.show_interstitial()  # no-op when unavailable, disabled, or capped
Ads.preload()            # interstitials must be loaded before they can show
```

Interstitials are **not instant** — one has to be requested and loaded in
advance. Load at the start of a run so it is ready by game over; a show that
finds nothing loaded should be skipped silently, never waited on.

### When to show — and a caveat

The request is "when the player loses or does not beat their record." Taken
literally that is *almost every run*, since losing is how every run ends and
records are rare. In this game a run is roughly one to three minutes, so that
is an interstitial every couple of minutes.

That is likely to hurt more than it earns:

- Google's policies prohibit ads that "interfere with app navigation" and
  repeated interstitials draw scrutiny; a high frequency with low engagement
  depresses eCPM.
- The retention cost of an ad after *every* failure is exactly when the player
  is already frustrated.

**Recommendation, still honouring the intent:**

| Rule | Value | Why |
|---|---|---|
| Show on | game over **without** a new best | as asked |
| Never show on | a new best, or a solved Puzzle board | do not punish success |
| Minimum runs between ads | 3 | the main lever |
| Minimum seconds between ads | 120 | protects against very short runs |
| Skip the first | 3 runs | let a new player learn the game first |
| Show | *after* the game-over panel is dismissed | never interrupt the score reveal |

All constants in one table in `ads.gd`, so the cadence is tunable without
touching logic. If you want it more aggressive, that is one number — but start
conservative and watch retention.

## Phase 3 — Ads Free purchase (1–2 days)

The `inappstore` plugin lives in the **same godot-ios-plugins tree we already
built Game Center from**, so the toolchain is set up and the recipe in
`docs/gamecenter.md` applies unchanged. Its API:

```
request_product_info, purchase, restore_purchases,
finish_transaction, set_auto_finish_transaction,
get_pending_event_count, pop_pending_event
```

Good news: it never touches the root view controller, so **the UIScene bug that
broke Game Center does not affect it**.

Caveat: it is **StoreKit 1**. Still supported, but Apple prefers StoreKit 2 for
new apps. Acceptable for one non-consumable; worth knowing if the shop ever
grows.

- Product: one **non-consumable**, e.g. `com.suryatresna.pixelblast.adsfree`.
- Entitlement persists in `user://settings.cfg`, and is re-derived on restore.
- **Apple requires a visible "Restore Purchases" control** for non-consumables.
  An app without one gets rejected. The design's Settings screen already lists
  `RESTORE PURCHASES` — build it here.

## Phase 4 — The menu (half a day)

The design (section 07, "POWERS & SHOP") already has the card language. A
single "ADS FREE" card fits the existing `ModeCard` variation.

- Menu entry hidden once purchased — replaced by a quiet "Ads removed. Thank
  you." line rather than a dead button.
- Price comes from `request_product_info`, never hardcoded: the App Store
  returns it localised, and a hardcoded "$2.99" is wrong in every other
  storefront.
- Handle all three outcomes: purchased, cancelled, failed.

---

## Compliance — the parts that cause rejections

- **`GADApplicationIdentifier` in Info.plist is mandatory.** The Google SDK
  **crashes on launch** without it. Goes in the preset's additional plist data.
- **`SKAdNetworkItems`** — Google publishes the list; ships with the plugin.
- **App Tracking Transparency.** iOS 14.5+ requires the ATT prompt before any
  tracking for personalised ads. Without it, ads still serve but
  non-personalised at much lower revenue. Needs `NSUserTrackingUsageDescription`
  and a prompt shown at a sensible moment — *not* on first launch.
- **Privacy manifest.** `PrivacyInfo.xcprivacy` already exists and must gain
  the ad-related API and data-collection declarations.
- **App Store privacy answers** must disclose data collection for ads.
- **Test ad unit IDs during development, always.** Clicking your own live ads
  gets the AdMob account suspended. Equally, never ship the test IDs.
- **Ads Free must disable ads immediately**, including for a restore on a fresh
  install, before any ad is requested.

## Cannot be done from this repo

- AdMob account, app registration, and ad unit IDs.
- The App Store Connect IAP product, its pricing, and review submission.
- Anything requiring a device: ATT prompt, real ad fill, sandbox purchases.

## Order, and why

1. **Template compatibility** — cheapest thing that can invalidate everything.
2. **Ads Free purchase before ads.** If ads ship first and the purchase slips,
   there is no way to turn them off, and the first review cycle is the
   expensive place to discover a bug in that path.
3. Ads.
4. The menu.

## Open questions

- Android too, or iOS first? The plugin covers both, but Play Billing is a
  separate integration from StoreKit — Phase 3 is iOS-only as written.
- Rewarded ads as well? A "continue this run" reward converts far better than
  interstitials and is less resented. Not in the request; worth considering.
- Price for Ads Free.
