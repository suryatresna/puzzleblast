# Prompt: build the Pix Blast marketing site

> **Status: proposed.** Nothing is built. Hand this whole file to an agent, or
> follow it yourself.

A one-page marketing site for **Pix Blast**, plus the two sub-pages the App
Store will not accept a submission without. Every image is a **placeholder**
with fixed dimensions, so the layout is final before any art lands and real
files drop in by overwriting a path.

---

## Goal

A single static landing page that makes someone want the game in about eight
seconds, and two supporting pages. No build step, no framework, no tracker.

**It must also do a job for the submission.** App Store Connect requires a
**support URL** and a **privacy policy URL** before you can submit. This site
is where both live — that is not a nice-to-have, it is the blocker this
removes.

## What the game is

A drag-and-drop block puzzle for iPhone. Five cards in a tray, drop one on the
board, fill a row or column and it clears. Beyond that: thirteen powers earned
through a level-gated skill tree, four modes, a local leaderboard.

- **App name in the app:** Pix Blast
- **App Store listing name:** `Pix Blast (Pixel Blast Puzzle)` — exactly 30
  characters, Apple's limit. Use the short name everywhere on the site; the
  long one is a store-search artefact, not a brand.
- **Bundle ID:** `com.suryatresna.pixelblast`
- **Price:** free. No ads, no in-app purchases, no analytics SDK. This is the
  strongest differentiator against every other block puzzle — give it a
  section, not a footnote.

## Pages

| Path | Purpose |
|---|---|
| `/index.html` | The landing page. Everything below. |
| `/privacy.html` | Privacy policy. **Required by App Store Connect.** |
| `/support.html` | Support / contact. **Required by App Store Connect.** |

### The privacy policy

**The app collects nothing, and that is verifiable rather than a claim.** The
shipped privacy manifest (`ios/PrivacyInfo.xcprivacy`) declares
`NSPrivacyTracking` **false** and carries **no `NSPrivacyCollectedDataTypes`
key at all**, and every `privacy/collected_data/*/collected` in
`export_presets.cfg` is `false`. There is no ad SDK, no analytics SDK and no
crash reporter in the project.

So write the short, true version. Do not paste a generic template — a policy
claiming to collect data the app never touches is worse than none, and it must
also **agree with the App Privacy answers in App Store Connect**, which for
this app is "Data Not Collected" across the board. A policy that contradicts
those answers is a rejection.

The page must say, in plain language:

- **No personal data is collected.** No name, email, address, phone number,
  contacts, photos, location or identifiers.
- **No account and no sign-in.** There is nothing to register.
- **No analytics, no advertising, no tracking**, and no third-party SDKs that
  could do any of it. Nothing is shared with anyone, because nothing is
  gathered.
- **Progress stays on the device.** Level, scores, settings and the local
  leaderboard are written to the app's own storage and never leave it. There
  is no server; the game works offline.
- **Deleting the app deletes everything.** That is the whole data-retention
  policy, and there is nothing to request or export because nothing was ever
  sent.
- **Children.** Nothing is collected from anyone, so nothing is collected from
  children either — worth stating outright, since it is the question most
  parents scan for.
- A contact address for privacy questions, and a "last updated" date.

Three things the app *does* touch, listed here only so nobody is surprised
reading the manifest: file timestamps, system boot time and available disk
space. These are Apple "required reason" APIs that the engine uses for saving
and timing. They are not collection and are never transmitted, so they do not
belong in the policy body — but do not let anyone describe them as data
collection either.

## Sections, in order

1. **Hero.** Wordmark, one-line hook, App Store badge, one device shot.
   Hook: *"Fill a row, watch it vanish. Then earn the powers that do it for you."*
2. **The loop.** Three short beats with a small image each: drop a piece,
   clear a line, build a combo. This is the part a stranger needs.
3. **Powers.** The thirteen, as a grid of name + one line. Lead with Bomb,
   Blackhole and Rewind — they are concrete and they tease the range.
4. **Earned, not bought.** The skill tree: five tiers behind account levels,
   three equipped at a time, paid for with charge earned from combos. The
   point is that no amount of money moves this bar.
5. **Modes.** Four cards: Palette, Big Palette, Sprint, Puzzle.
6. **The video.** The 19-second app preview, muted autoplay with controls, a
   poster frame behind it.
7. **No ads. No purchases. No timers.** Its own band, high contrast.
8. **Footer.** Support and privacy links, the music credit, copyright.

Copy for 2–5 can be lifted from the App Store description; keep sentences
short and never invent a feature.

## Brand

Taken from the shipped Pixel Dark theme. Do not invent colours.

| Token | Hex | Use |
|---|---|---|
| Background base | `#17120f` | Page ground |
| Background top | `#2a211a` | Top of the page gradient |
| Card / panel | `#241c16` | Cards, code blocks |
| Text | `#f0e2c6` | Body |
| Muted | `#a08b67` | Secondary text |
| Faint | `#6e5c42` | Captions, rules |
| Accent | `#d6a549` | Buttons, links |
| Highlight | `#e8bc61` | Headings, the wordmark |
| Danger | `#d0603a` | One accent only — do not use for errors |

Block tints, for decorative squares: `#8fa9a1` sage, `#a8842f` olive,
`#d0603a` rust, `#e8bc61` ochre.

**Type.** Both faces are on Google Fonts under the OFL, so link them rather
than self-hosting:

- **Silkscreen** — headings and the wordmark only. It is crisp *only* at
  multiples of its 8px design grid, so use 16/24/32/48px and nothing between.
  Never set body copy in it.
- **Pixelify Sans** — sub-headings and short labels.
- **A normal system stack** — all body copy. Paragraphs of pixel type are
  unreadable and will cost you the visitor.

**The logo** is four blocks in a 2×2 with the bottom-right one turned 14°.
The gap between blocks is 12.5% of a block, which is exactly the margin the
turned one needs — change one and the blocks touch. Colours clockwise from
top-left: ochre, rust, sage (turned), olive. `ui/logo.svg` in the game repo is
this shape already and can be used directly.

## Image placeholders

**Every image is a placeholder at a fixed size.** Reserve the box with a
`width`/`height` attribute pair *and* an `aspect-ratio` in CSS so nothing
reflows when real art arrives. Draw each placeholder as an inline SVG data URI
on `#241c16` with its own filename and pixel size printed in `#6e5c42`, so an
unreplaced slot is obvious rather than invisible.

| Path | Size | Contents |
|---|---|---|
| `assets/logo.svg` | 256×256 | The 2×2 mark |
| `assets/hero-device.png` | 886×1920 | Gameplay, powers charged |
| `assets/loop-drop.png` | 540×960 | A piece mid-drag |
| `assets/loop-clear.png` | 540×960 | A line clearing |
| `assets/loop-combo.png` | 540×960 | A combo call-out |
| `assets/shot-powers.png` | 540×960 | The power strip, charged |
| `assets/shot-blackhole.png` | 540×960 | Blackhole imploding |
| `assets/shot-bomb.png` | 540×960 | Bomb detonating |
| `assets/shot-skill-tree.png` | 540×960 | The skill tree |
| `assets/shot-leaderboard.png` | 540×960 | The leaderboard |
| `assets/preview.mp4` | 886×1920 | The 19s app preview |
| `assets/preview-poster.png` | 886×1920 | First frame of the video |
| `assets/og-card.png` | 1200×630 | Social share card |
| `assets/favicon.png` | 512×512 | Favicon source |
| `assets/appstore-badge.svg` | 120×40 | Apple's official badge |

**Real versions of most of these already exist** in the game repo under
`screenshots/` (540×960), `screenshots/store/iphone-6.9-1320x2868/`, and
`screenshots/store/preview/`. Dropping them in is a copy, not a re-shoot. The
`og-card.png` and the badge are the two that must be made.

Every screenshot is **9:19.5**, not 16:9. Frame them tall; do not letterbox
them into a wide box.

## Technical

- **Static.** Hand-written HTML and CSS, one file each. No framework, no
  bundler, no npm. It has to still build in three years.
- **One `<style>` block** in the head, or one `site.css`. No CSS-in-JS.
- **JavaScript is optional and must be removable.** The page has to work fully
  with it disabled.
- **Responsive from 320px up, mobile first.** Most traffic is a phone that
  just left the App Store, so the phone layout is the design and the desktop
  one is the adaptation — not the reverse. Specifics:
  - Breakpoints at **480, 768 and 1100px**. Below 480 everything is one
    column; the screenshot strip goes 1 up on phones, 2 at 768, 3 or 4 at
    1100. Content caps at about 1100px and centres.
  - **No horizontal scrolling at 320px**, and no element wider than its
    container. Test at 320, 390, 768 and 1280.
  - Screenshots are **9:19.5** and tall. On a phone show one at a time in a
    swipeable `overflow-x: auto` strip with scroll snapping, rather than
    shrinking six of them into thumbnails nobody can read.
  - The video is full width on a phone, capped near **380px** on desktop —
    a portrait video stretched across a wide screen is absurd.
  - **Touch targets at least 44x44px** with real spacing between them, per
    Apple's own guidance. The App Store button is the one thing on the page
    that must never be fiddly.
  - Use `dvh`, not `vh`, for anything full-height. Mobile Safari's toolbar
    makes `100vh` overflow.
  - **Do not fluid-scale the Silkscreen headings.** `clamp()` is right for
    body copy in the system font, but Silkscreen is crisp only at multiples
    of 8px, so headings must step 16 -> 24 -> 32 -> 48 at breakpoints. A
    fluid pixel heading is blurry at every size in between.
- **Dark by default**, because the game is. If you support light, define the
  full palette on `:root` and override under `prefers-color-scheme`.
- **`image-rendering: pixelated`** on every screenshot and on the logo. Pixel
  art scaled with smooth interpolation looks broken, and this is the single
  most likely visual mistake on this site.
- **`prefers-reduced-motion`** must disable any animation, including the
  video's autoplay.
- **Accessible:** real alt text, one `<h1>`, 4.5:1 contrast on body text,
  visible focus rings. `#a08b67` on `#17120f` passes; `#6e5c42` does not — keep
  faint text off body copy.
- **Meta:** title, description, Open Graph and Twitter card pointing at
  `og-card.png`, `theme-color: #17120f`, canonical URL.
- **No third-party requests except Google Fonts.** No analytics, no pixel, no
  consent banner needed — and that is the point, given the privacy page.

## Traps

Four of these are specific to this game and will read as errors if missed.

- **Do not claim online leaderboards or Game Center.** The code is complete but
  it is not live: there are no App Store Connect leaderboards yet. The
  leaderboard is **local only**. Advertising it is a one-star review on day one.
- **The music credit is a licence obligation, not a courtesy.** The footer must
  carry *"Music by Abstraction"* linking to https://abstractionmusic.com/. The
  in-game About page carries it for the same reason.
- **Do not describe Puzzle mode as hand-built boards.** They are generated
  deterministically from the level number — identical for every player, but
  nobody authored them.
- **Powers are not purchasable and never were.** Any copy hinting at a shop
  contradicts the section that is the site's best argument.
- **The App Store badge has rules.** Use Apple's official artwork at its
  official proportions, with the clear space around it, from the Apple
  marketing guidelines. Do not redraw it.
- **Silkscreen at a non-multiple of 8px goes blurry**, which looks like a
  broken font rather than a design choice.

## Done when

- All three pages render with placeholders, no console errors, no layout shift.
- Replacing any file in `assets/` needs no HTML or CSS change.
- Lighthouse: 100 accessibility, 100 best practices, and no render-blocking
  request other than the font stylesheet.
- The support and privacy URLs can be pasted into App Store Connect, and the
  privacy page agrees with the "Data Not Collected" answers there.
- No horizontal scrollbar at 320px, and the page is usable one-handed on a
  phone.
