# Load-more — Sources of truth & verification protocol

> Context: load-more went through several fix iterations without a measurement loop.
> This document pins down (1) the sources of truth used to judge correctness,
> (2) the behavior baseline measured on a real simulator, (3) known issues with exact
> numbers, and (4) acceptance criteria for any future change to this mechanism.
>
> All numbers below were measured on **2026-11-14**, iPhone 18 Pro Max simulator
> (iOS 27.0), harness = `UIHostingController` + the real `BasicListView`, scrolling
> driven with `setContentOffset` on the underlying `UIScrollView`.

## 1. Three layers of truth (in order of authority for runtime behavior)

| Layer | What it is | When to use it |
|---|---|---|
| 1. Shipped SDK spec | `.swiftinterface` / `.swiftdoc` inside the local Xcode SDK — Apple's own doc comments | Analyzing APIs, availability |
| 2. UIKit ground truth | The physical definition of "true bottom": `maxOffsetY = contentSize.height − bounds.height + adjustedContentInset.bottom` | The ruler every formula must match |
| 3. Measurement | Harness on the simulator, on the actual device | Final word on runtime behavior |

Commands to extract the spec verbatim from your own machine:

```bash
IFACE="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-ios.swiftinterface"
grep -A20 "struct ScrollGeometry" "$IFACE"

SWIFTDOC=$(find /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/SwiftUICore.framework -name "arm64e-apple-ios.swiftdoc" | head -1)
strings "$SWIFTDOC" | grep -A4 "The visible rect of the scroll view"
strings "$SWIFTDOC" | grep -A3 "overall size of the scroll view"
```

Verbatim quotes (iOS 27.x SDK):

- `containerSize` — *"The size of the container of the scroll view. This is the overall
  size of the scroll view. Combining this and the content offset will give you the
  current visible rect of the scroll view."*
- `visibleRect` — *"The visible rect of the scroll view. This value is computed from the
  scroll view's content offset, content insets, and its container size."*
- `onScrollGeometryChange` action — *"called whenever the data type changes"* (no promise
  of an initial call).

**Design consequence:** never re-derive "distance from bottom" from
`contentOffset`/`containerSize`/`contentInsets` parts — use `visibleRect`, the primitive
Apple already computes and defines.

## 2. Measured `ScrollGeometry` baseline (C1–C4)

`engineD` below is the current engine formula
(`contentSize.height − contentInsets.bottom − (contentOffset.y + containerSize.height)`)
evaluated at UIKit's true max offset:

| Config | `containerSize` | insets (top, bottom) | `engineD` at true bottom | Bias |
|---|---|---|---|---|
| C1 bare ScrollView + env inset | 782 (= 844 − 62) | 62, 0 | 62 | +top |
| C2 ScrollView + `safeAreaInset(50)` | 724 | 62, 58 | 4 | top − bottom |
| C3 ScrollView + `contentMargins(30/50)` | 702 | 92, 50 | 42 | top − bottom |
| C4a List (engine structure), no outer inset | 844 | 62, 0 | 0 | none (accidental match) |
| C4b List + `safeAreaInset(83)` | 844 | 62, 91 | −182 | −2 × bottom |

⚠️ `containerSize` does **not** have a stable meaning across structures (782 / 724 / 702
/ 844 measured). The doc says "overall size"; in practice it depends on how the inset
originates (margin vs safe area vs List internals). The cause is not documented by
Apple → **do not build distance math on `containerSize`.**

Candidate fix `distance = contentSize.height − visibleRect.maxY`, verified at true bottom:

- C4a: 5724 − 5724 = **0** ✓
- C4b: 5724 − 5815 = **−91** = exactly −bottomInset, consistent ✓

→ screen-basis semantics, identical across embeddings.

## 3. Measured engine behavior baseline (B1–B8)

Harness params: window 390×844, rows `Text.frame(height: 60)`, 10 rows per page, handler
logs every entry; per step: `setContentOffset` → pump RunLoop (sample geometry, spawn
Tasks) → await settle (drain Tasks). See §6 for the three harness traps.

| Scenario | Config | Measured result |
|---|---|---|
| B1/B2 attach short list (6 rows) | pixel 600 | fires=**2**, loads=[2,3] — 2 pages load at open; `maxConcurrent=1` → a VM-side `inFlight` guard is USELESS (fires are sequential, ~1 ms apart) |
| B3 attach 15 rows (~1.2 screens, in region) | pixel 600 | fires=1, loads=[2] ✓ |
| B4 scan to bottom | pixel 600, bottom 0 | fires exactly at the engineD 700→500 crossing (threshold 600 ✓ — bottom=0 so no bias in this config); **7 region entries → 15 loads (~2.1/entry)**; idle-fires=0 |
| B5 scan | pixel 600, bottom 91 | fires at remUK ≤ 691 (= 600 + 91 bias — fires ~1 bottom-inset early) |
| B8 scan | pagesAhead 2, bottom 91 | region = 2 × container(844) = 1688 → fires at remUK ≤ 1779; **10 entries → 22 loads (~2.2/entry)** |
| B6 deep jump into region | pixel 600 | fires=2 within ONE entry |
| B7 exhausted (lastPage 6) | pixel 600 | loads exactly 5 pages, idle-fires=0 — clean stop ✓ |

## 4. Known issues (measured, NOT yet fixed)

### F1 — distance is biased, and the bias depends on how the list is embedded
The current formula (`BasicListView.swift:472-474`) re-derives from parts → the bias is a
function of `containerSize` semantics (table §2): List-style is off by −bottom (fires
`bottom` pt early); ScrollView-style is off by top−bottom. A screen without bottom insets
looks correct — that is exactly why the bug survives previews and why fixing one screen
breaks another.

### F2 — each region entry loads ~2 pages (2.1–2.2 loads/entry)
Three fire sources stack up, SEQUENTIALLY (1–400 ms apart): (a) the enter-transition;
(b) List's content-size estimate steps while lazy rows materialize (drift measured:
5724→6084) — each in-region step with a changed `contentHeight` is a legitimate fire
under the current guard; (c) the sentinel's `onAppear` when it is within the viewport.
A VM-side `inFlight` guard only blocks CONCURRENT fires — measured B2: guard on, still
[2,3].

### F3 — attaching a short list fires twice → 2 pages load at open
Mechanism: the probe's zero→settled transition (already in region) + sentinel/drift.
Measured B1/B2.

### F4 — `pagesAhead` region rides on the unstable `containerSize`
The mechanism works (B8), but the region = N × containerSize and containerSize varies by
embedding (§2).

### F5 — platforms
watchOS/tvOS are declared in `Package.swift` but **do not build**:
`listRowSeparator` (watchOS); `swipeActions` / `listRowSeparator` / `scrollContentBackground`
(tvOS). Reproduce:

```bash
xcodebuild build -scheme BasicList -destination 'generic/platform=watchOS Simulator'
xcodebuild build -scheme BasicList -destination 'generic/platform=tvOS Simulator'
```

CI currently runs only `swift build` / `swift test` on macOS → cannot catch this.
(macOS builds fine.)

## 5. Fix plan + acceptance criteria (PRE-REGISTERED — written before measuring; do not edit afterwards)

- **Fix A** — `distanceFromBottom = geometry.contentSize.height − geometry.visibleRect.maxY`
- **Fix B** — engine-side cooldown ~400 ms after each fire (mechanical state, not business state)
- **Fix C** — treat the first observation as baseline (no fire on the zero→settled
  transition); the sentinel still backstops short lists

| Metric | Before (measured) | After (predicted) |
|---|---|---|
| Trigger point | remUK ≤ T + bottom (List-style) | **remUK ≤ T in every config** |
| Loads per region entry | ~2.1 | **1** |
| Attach short list | fires 2, loads [2,3] | **fires 1, loads [2]** |
| Chain / exhausted / idle | correct | unchanged |
| `swift test` host suite | 17 pass | 17 pass |

Any deviation from this table = the fix is wrong → go back and fix; do not relax the
criteria.

## 6. Rebuilding the harness (for measurements outside the repo)

Deterministic params: window 390×844; row `Text.frame(height: 60)`; 10 rows per page;
find the UIScrollView in the hierarchy (List recycles its internal instance — re-find on
every step); keep a STRONG reference to the UIWindow (a sceneless window is deallocated
during async awaits, which tears the hierarchy down); hybrid step:
`setContentOffset → pump RunLoop (samples geometry, spawns Tasks) → await settle (drains
Tasks)` — handlers must be delay-0 (atomic) because the xctest executor does not
reliably resume child-task sleeps. Scenarios: B1–B8 per the table in §3.

(Plan: land this harness as an iOS simulator test target so `xcodebuild test` runs it —
the current CI only runs `swift test` on macOS and never exercises this layer.)

## 7. Real-app acceptance checklist (~3 minutes)

1. VM: add `print("LOAD page \(n)")` inside the load-more handler.
2. Open two screens: one with a tab bar (large bottom inset), one full-screen (small inset).
3. Scroll slowly to the bottom: EXACTLY **one** log line per region entry; the fire
   distance from the bottom ≈ the configured threshold, identical across both screens.
4. Open a short list (6–8 rows): exactly one log line — no double page load at open.
5. Scroll to the end of the data: logs stop; standing still fires nothing more.
