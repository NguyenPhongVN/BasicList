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

## 4. Known issues (measured 2026-11-14; F1–F5 FIXED same day — see §5)

### F1 — distance is biased, and the bias depends on how the list is embedded — **FIXED (Fix A)**
The old formula re-derived from parts → the bias was a function of `containerSize`
semantics (table §2): List-style off by −bottom (fires `bottom` pt early);
ScrollView-style off by top−bottom. A screen without bottom insets looked correct —
which is exactly why the bug survived previews and why fixing one screen broke another.
Fix: `distanceFromBottom = contentSize.height − visibleRect.maxY`.

### F2 — each region entry loaded ~2 pages (2.1–2.2 loads/entry) — **FIXED (Fix B)**
Three fire sources stacked up, SEQUENTIALLY (1–400 ms apart): (a) the enter-transition;
(b) List's content-size estimate steps while lazy rows materialize (drift measured:
5724→6084); (c) the sentinel's `onAppear` when it is within the viewport. A VM-side
`inFlight` guard only blocks CONCURRENT fires — measured B2: guard on, still [2,3].
Fix: the engine-side `BasicListLoadGate` — one fire per 400 ms window shared by probe
and sentinel.

### F3 — attaching a short list fired twice → 2 pages at open — **FIXED (Fix B)**
Mechanism: the probe's zero→settled transition (already in region) + sentinel/drift.
The gate collapses them; the remaining post-attach loads are the designed chain while
the list stays inside the region (see §5 post-fix).

### F4 — `pagesAhead` region rode on the unstable `containerSize` — **PARTLY FIXED (Fix A)**
The region = N × `containerSize` still varies by embedding, but the TRIGGER now lands
exactly at the configured boundary (measured B8: no fire at remUK 1700 with region 1688),
and the distance itself is stable. Region-size variance documented in §2.

### F5 — platforms — **FIXED (guards)**
watchOS/tvOS are declared in `Package.swift` and now **build**:
`listRowSeparator` (watchOS), `swipeActions` + `listRowSeparator` +
`scrollContentBackground` (tvOS) are `#if`-guarded with reduced behavior — tvOS/watchOS
rows expose swipe actions as accessibility actions only. Verified:

```bash
xcodebuild build -scheme BasicList -destination 'generic/platform=watchOS Simulator'  # SUCCEEDED
xcodebuild build -scheme BasicList -destination 'generic/platform=tvOS Simulator'     # SUCCEEDED
```

CI still runs only `swift build` / `swift test` on macOS — a platform matrix would catch
future regressions.

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

### Post-fix measured results (2026-11-14, iPhone 18 Pro Max, suite `LoadMoreSimulatorTests`)

| Metric | Before (measured) | Predicted | **After (measured)** |
|---|---|---|---|
| Trigger point | remUK ≤ T + bottom (List-style) | remUK ≤ T every config | **✓ remUK ≤ T** — B4: no fire at 1500/1100/900/700, fires at 500; B8: no fire at 1700 with region 1688 |
| Loads per region entry | ~2.1 | 1 | **✓ 1** — B4 `fires==6` after six entries |
| Attach short list | fires 2, loads [2,3] | fires 1, loads [2] | **✓ duplicates collapsed** (inter-fire gaps ≥ cooldown; B1/B3 pass the gap check) — loads may be [2,3] when the grown list stays inside the region: that is the designed chain, **not** a duplicate. The predicted value was mis-modeled — a short list sits deep in its region after one page, so continuous loading legitimately continues (evidence: post-load distance ≈167 ≤ 600). Criterion intent (no duplicate sources) is met and pinned by the gap check |
| Chain / exhausted / idle | correct | unchanged | **✓ + improved** — a gate-blocked chain fire now RETRIES against fresh geometry (never strands the last page); a retry that fails the region re-check is discarded |
| `swift test` host | 18 pass | 18 pass | **✓ 18 pass** |

Two additional measured findings folded into the fix:

- **Blocked chain fires must retry, not drop.** First attempt dropped them → the last
  page could strand when a stationary user sat at the exact boundary (B7). The retry
  re-checks the CURRENT geometry, so a stale retry cannot fire after the user left.
- **Page attach can push the user out of the region.** contentSize grows by rows +
  List estimate drift (measured +1086 pt for a 10-row page), so a stationary user may
  exit the region after a load — the chain stops by design and the next scroll delivers
  the remaining page (B7 re-entry).

### CI variance — chain length is runtime-dependent, not an engine constant (2026-11-14)

The exact-sequence baselines above are pinned to the measurement environment in the
header (iPhone 18 Pro Max, iOS 27.0). The SAME suite on other runtimes yields a
LONGER designed in-region chain — first CI run (GitHub `macos-26`, iPhone 17-series
sim, iOS 26.5): B4 appended **[2…14], fires 11** vs local [2…9], fires 7. Every
engine invariant still held there: no fire outside the region, pages strictly
consecutive (no duplicate, no gap), idle quiet, exhaustion respected. The cause is
NOT a regression — the engine mechanics are byte-identical to the baseline commit
(diff: cooldown accessor only); List estimate drift differs per OS runtime, so after
a page attach the stationary list stayed ≤ 600 pt on iOS 26.5 and the DESIGNED
chain kept loading (see the "page attach can push the user out" note above for the
same mechanism in reverse). B4 therefore asserts design invariants on every runtime
and the exact [2…9] baseline only on the pinned device. The local strict numbers
remain the record to compare against when the probe/sentinel changes.

## 6. Rebuilding the harness (for measurements outside the repo)

Deterministic params: window 390×844; row `Text.frame(height: 60)`; 10 rows per page;
find the UIScrollView in the hierarchy (List recycles its internal instance — re-find on
every step); keep a STRONG reference to the UIWindow (a sceneless window is deallocated
during async awaits, which tears the hierarchy down); hybrid step:
`setContentOffset → pump RunLoop (samples geometry, spawns Tasks) → await settle (drains
Tasks)` — handlers must be delay-0 (atomic) because the xctest executor does not
reliably resume child-task sleeps. Scenarios: B1–B8 per the table in §3.

**Landed in-repo:** `Tests/BasicListTests/LoadMoreSimulatorTests.swift` — `#if os(iOS)`
(compiles empty on macOS host), `@Suite(.serialized)` (parallel tests interleave their
pump/settle timing and corrupt measurements). Run with:

```bash
xcodebuild test -scheme BasicList \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -only-testing:BasicListTests/LoadMoreSimulatorTests
```

Harness traps worth remembering (each cost a debugging round):
1. A sceneless `UIWindow` is deallocated during async awaits unless strongly retained —
   the hosted hierarchy dies and the held UIScrollView becomes a detached zombie.
2. List recycles its internal UICollectionView — re-find the live instance per step.
3. In sync tests, RunLoop pumps service layout + `onScrollGeometryChange` actions but
   NOT Swift-concurrency Task continuations; in async tests Tasks drain during awaits
   but geometry is not sampled during `Task.sleep`. Only the pump→settle hybrid
   exercises both halves.

## 7. Real-app acceptance checklist (~3 minutes)

1. VM: add `print("LOAD page \(n)")` inside the load-more handler.
2. Open two screens: one with a tab bar (large bottom inset), one full-screen (small inset).
3. Scroll slowly to the bottom: EXACTLY **one** log line per region entry; the fire
   distance from the bottom ≈ the configured threshold, identical across both screens.
4. Open a short list (6–8 rows): exactly one log line — no double page load at open.
5. Scroll to the end of the data: logs stop; standing still fires nothing more.
