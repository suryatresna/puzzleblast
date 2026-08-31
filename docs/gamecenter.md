# Game Center

`scripts/game_services.gd` (autoloaded as `GameServices`) authenticates on
launch, submits every finished run, and opens Apple's leaderboard UI.

**The plugin is built and installed** — `ios/plugins/` holds a Game Center
build made against Godot 4.7.2, and the iOS preset has `plugins/GameCenter=true`.
A debug `.ipa` exports cleanly with it linked.

**What remains is the App Store Connect side** (§3) and a device test (§4);
both need your Apple account and hardware.

Until the leaderboards exist, submissions go nowhere but nothing breaks: every
call is a no-op without the plugin, and failures are warnings. The local
leaderboard is always the source of truth.

## Why a plugin is needed

Godot 4 **removed the built-in Game Center module** — it existed in 3.x and was
moved out of the engine. Integration now goes through the `GameCenter`
singleton supplied by [godot-ios-plugins][p]. `GameServices` binds to it at
runtime with `Engine.has_singleton("GameCenter")`, so the project builds and
runs fine without it.

[p]: https://github.com/godotengine/godot-ios-plugins

## 1. The plugin — done, and how to rebuild it

`ios/plugins/` contains:

```
gamecenter.gdip                 # descriptor: name, init symbols, GameKit dep
gamecenter.release.xcframework  # for release exports
gamecenter.debug.xcframework    # for debug exports
```

**There are no prebuilt Godot 4 binaries.** The upstream repo moved to
[godot-sdk-integrations/godot-ios-plugins][p] and its releases stop at 3.5, so
this was built from `master` (which supports `version=4.0`) against the Godot
4.7.2 source.

### Why both debug and release

`ClassDB::bind_methodfi` changes signature with `DEBUG_METHODS_ENABLED`: debug
engine builds take a `MethodDefinition`, release builds take a `char const*`.
Ship only one variant and the other export target fails at link with

```
Undefined symbols: "ClassDB::bind_methodfi(..., char const*, ...)"
  referenced from: GameCenter::_bind_methods() in libgamecenter...a
```

Godot resolves this automatically: with `binary="gamecenter.xcframework"` in
the `.gdip`, it looks for `gamecenter.release.xcframework` **and**
`gamecenter.debug.xcframework` and picks per target. Both must exist.

### Rebuild recipe

Needed when upgrading Godot — the plugin links against engine internals.

```bash
python3 -m venv .venv && ./.venv/bin/pip install scons
curl -L -o p.tar.gz https://github.com/godot-sdk-integrations/godot-ios-plugins/archive/refs/heads/master.tar.gz
tar xzf p.tar.gz && mv godot-ios-plugins-master plugins

# Godot source, for headers only. The tag must match your engine.
curl -L -o g.tar.gz https://github.com/godotengine/godot/archive/refs/tags/4.7.2-stable.tar.gz
tar xzf g.tar.gz && rm -rf plugins/godot && mv godot-4.7.2-stable plugins/godot

# Generate the .gen.h files, then stop -- a full engine build is not needed.
cd plugins/godot && scons platform=ios target=template_debug arch=arm64 -j6
#   ...kill it once core/version_generated.gen.h and modules/modules_enabled.gen.h exist
cd ..

# Apply the UIScene fix first -- see "The plugin needs a patch for Godot 4.7".
patch -p1 -d plugins < ../tools/patches/gamecenter-uiscene-root-controller.patch

# Build both variants, three slices each. NOTE: the plugin predates Godot 4's
# target names -- it wants release / release_debug, not template_release.
for T in release release_debug; do
  scons target=$T arch=arm64 plugin=gamecenter version=4.0 -j6
  scons target=$T arch=arm64  simulator=yes plugin=gamecenter version=4.0 -j6
  scons target=$T arch=x86_64 simulator=yes plugin=gamecenter version=4.0 -j6
  lipo -create bin/libgamecenter.{x86_64,arm64}-simulator.$T.a -output bin/libgamecenter-simulator.$T.a
  xcodebuild -create-xcframework \
	-library bin/libgamecenter.arm64-ios.$T.a \
	-library bin/libgamecenter-simulator.$T.a \
	-output bin/gamecenter.$T.xcframework
done
mv bin/gamecenter.release_debug.xcframework bin/gamecenter.debug.xcframework
```

Copy the two xcframeworks and `plugins/gamecenter/gamecenter.gdip` into
`ios/plugins/`.

`.gitignore` excludes `/ios/*` **by contents rather than as a directory** —
git cannot re-include anything inside an excluded directory, so the plugin
would otherwise be untrackable. `!/ios/plugins/` brings just this back; the
~800 MB of Xcode output stays ignored.

[p]: https://github.com/godot-sdk-integrations/godot-ios-plugins

## 2. Export preset — done

`entitlements/game_center=true` and `plugins/GameCenter=true` are both set in
`export_presets.cfg`.

Verified end to end: `godot --headless --export-debug "iOS" app.ipa` succeeds,
links `libgamecenter.arm64-ios.release_debug.a`, and the resulting binary has
`GameKit.framework` linked and the `com.apple.developer.game-center`
entitlement.

## 3. App Store Connect

Enable **Game Center** on the app record, then create one leaderboard per mode.
The identifiers must match `GameServices.LEADERBOARDS` **exactly**; a mismatch
fails silently on Apple's side, which is the single most common cause of
"scores never appear".

| Mode | Leaderboard ID | Suggested name | Sort |
|---|---|---|---|
| Palette | `com.suryatresna.pixelblast.palette` | Palette — Endless | High to low |
| Sprint | `com.suryatresna.pixelblast.sprint` | Sprint — 60 Seconds | High to low |
| Puzzle | `com.suryatresna.pixelblast.puzzle` | Puzzle | High to low |

Score format: **Integer**. Scores are submitted raw, with no multiplier.

These are reverse-DNS on the bundle id, Apple's convention: ids are unique
across the whole developer account, not per app. **They cannot be renamed after
creation** — changing one later means a new board and the old scores are
stranded. `GameServices.LEADERBOARDS` is the only place they appear.

## The plugin needs a patch for Godot 4.7

**Upstream's plugin does not work on Godot 4.7 unmodified.** It reaches the
root view controller the pre-iOS-13 way:

```objc
[[UIApplication sharedApplication] delegate].window.rootViewController
```

Godot 4.7 uses the **UIScene lifecycle** — `UIApplicationSceneManifest` is in
the exported Info.plist, and the window belongs to the `UIWindowScene`. The
app delegate's `window` getter polls its services, and
`drivers/apple_embedded/app_delegate_service.mm` only ever sets that to `nil`.
So the expression is permanently `nil`, `authenticate()` returns `FAILED`
before Apple is contacted, and the app can never sign in. The symptom is an
endless

```
game_center.mm:92:authenticate(): Condition "!root_controller" is true. Returning: FAILED
```

`tools/patches/gamecenter-uiscene-root-controller.patch` resolves the
controller through `UIApplication.connectedScenes`, preferring the key window,
and keeps the delegate path as a fallback for older engines. It fixes both call
sites — `authenticate()` and `show_game_center()`. **Apply it before building**,
and re-apply after pulling upstream.

## Timing: sign-in cannot happen at startup

The plugin's `authenticate()` needs the app's root view controller:

```objc
root_controller = [[UIApplication sharedApplication] delegate].window.rootViewController;
ERR_FAIL_COND_V(!root_controller, FAILED);
```

An autoload's `_ready()` runs **before UIKit has built the window**, so calling
it there returns `FAILED`, no handler is installed, and the app never signs in
— silently, because the failure happens before Apple is ever contacted.

`GameServices` therefore does not authenticate in `_ready()`. The first attempt
is deferred by `AUTH_FIRST_DELAY` and retried every `AUTH_RETRY_DELAY` until
the call is accepted, giving up after `AUTH_MAX_ATTEMPTS` with an explanatory
`last_error`. Being *accepted* is not the same as being *signed in*: Apple
reports the outcome later through the event queue.

The engine logs `Condition "!root_controller" is true` for each rejected
attempt. A few of those during startup are expected and harmless.

## Diagnosing "it never signs in"

The app side is verifiable from here and is known good: the singleton registers
as `GameCenter`, `com.apple.developer.game-center` is in the built
entitlements, and `GameKit.framework` is linked. So a device that never
authenticates is almost always **Apple-side configuration**, in this order:

1. **Game Center is not enabled on the App ID.** Developer portal →
   Certificates, Identifiers & Profiles → Identifiers → `com.suryatresna.pixelblast`
   → tick **Game Center**. This is the usual cause.
2. **The provisioning profile predates that change.** A profile only carries
   the entitlements the App ID had when it was generated. After enabling Game
   Center you must **regenerate the profile** and re-export — editing the App
   ID does not update existing profiles.
3. **No app record in App Store Connect**, or Game Center not enabled on it.
   Apple reports this as *"this application is not recognized by Game Center"*.
4. **The device is not signed in.** Settings → Game Center, with a sandbox
   Apple ID.

### Reading the failure

`GameServices.last_error` holds Apple's own `error_description` and
`error_code`, and every failure is also a `push_warning`. **About shows a
`Game Center: …` line on iOS**, so a device build can be diagnosed without a
console — it reads `signed in as <name>`, `sign-in failed: <Apple's reason>`,
`plugin missing: …`, or `signing in...`.

`GameServices.GK_ERRORS` maps Apple's `GKErrorCode` to plain words, and the
message keeps the raw code. The ones that come up:

| Code | Meaning | Retried? |
|---|---|---|
| 2 | cancelled by the player | no — a decision |
| 3 | cannot reach Game Center servers | **yes** |
| 4 | the player denied access | no — a decision |
| 15 | this app is not recognised by Game Center | no — configuration |
| 16 | Game Center not supported here | no |

Transient codes (`1`, `3`, `7`) are retried after `AUTH_RECOVER_DELAY` (30s),
up to `AUTH_MAX_RECOVERIES`. Apple's sandbox fails this way often enough that
giving up on the first one is wrong.

### GKError 3 with `GKServerStatusCode=5001` / `MZBasicDBException ... CAS operation failed`

Apple's own backend, not the app: `MZ*` is Apple's media-services layer and
*CAS* is a compare-and-swap, so the server failed to write the player↔app
record. Seen when:

- **The app has no App Store Connect record**, or Game Center is not enabled on
  it — the backend has no app to associate the player with. Most likely if you
  have not created the record yet.
- **The sandbox player's record is wedged.** Sign out (Settings → Game Center),
  sign back in, or use a fresh sandbox Apple ID.
- **Apple-side flakiness.** Genuinely common in the sandbox; the built-in
  retry exists for this.

The app is doing its part by this point — sign-in was requested, the handler
was installed, and Apple answered. Nothing here is fixable in code.

## 4. Testing

- Game Center does **not** work in the Simulator for sign-in; use a real
  device. (Note this project cannot use the iOS Simulator on Apple Silicon at
  all — see the note in `CLAUDE.md`.)
- Sign in with a **sandbox** Apple ID: Settings → Game Center on the device.
- Sandbox and production leaderboards are separate. A score posted in sandbox
  never shows in production.
- A brand-new leaderboard can take a while to appear, and stays hidden from
  non-testers until the app is approved.

## How it behaves

- **Authentication** runs once on launch, iOS only. Apple shows its own sign-in
  banner; the game does not gate anything on the result.
- **The welcome page greets the player** — "Welcome <name>!" — from the
  `displayName` in the authentication event, falling back to `alias`. Sign-in
  usually lands *after* the menu is already on screen, so the label is bound to
  `authentication_changed` rather than only read once. It hides itself when
  signed out or when the name comes back blank, so there is never a
  "Welcome !". The name is another user's account text and is only ever put in
  a plain `Label`, never BBCode.
- **Submission** happens on every game over, alongside the local record. If a
  run finishes before sign-in completes, the score is queued (up to
  `MAX_PENDING`, 16) and flushed when authentication lands — a run ending
  during the sign-in banner is the normal case, not an edge case.
- **The Game Center button** on the leaderboard screen is hidden unless the
  plugin is present and signed in, rather than shipped as a dead control.
- Failures are logged with `push_warning` and otherwise ignored.

## Not built yet

Achievements. `GameServices` covers authentication and leaderboards only; the
plugin exposes an achievements API if you want them later.
