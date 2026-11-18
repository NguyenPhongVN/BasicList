# BasicList

[![CI](https://github.com/NguyenPhongVN/BasicList/actions/workflows/ci.yml/badge.svg)](https://github.com/NguyenPhongVN/BasicList/actions/workflows/ci.yml)

A SwiftUI **"array in — item out"** list engine for house lists — one view for both flat and sectioned shapes (sticky header per group), with built-in header / empty-state / footer / swipe actions / row tap / pull-to-refresh / continuous load-more / reorder — plus a **page scaffold** (`BasicListPage`) that wraps the engine with page chrome (title header, slots, inline search, loading row, bottom bar).

Standalone package, pure SwiftUI, **zero dependencies** — **reads no app design layer**: every color/metric comes in through config, the engine decides the mechanism, the caller decides the look.

## Features

- ✅ Flat list (`items:`) and sectioned list (`sections:`) with a sticky header per group — **one** engine for both shapes
- ✅ Header with 2 modes: scrolls with content (`.scrollsWithContent`) or pinned to the top (`.pinnedTop`)
- ✅ Empty-state runs **inside** the list (keeps list identity across the empty/loaded phases)
- ✅ Footer scrolls with content like a real section
- ✅ Per-row swipe actions (data in, events out) — **both edges** (`edge: .leading`), full swipe, destructive tint from config
- ✅ Long-press context menu per row — doesn't steal regular taps or swipes
- ✅ Per-section footer — symmetric with the sticky header
- ✅ Full-area row tap, complete VoiceOver support (button trait + accessibility actions)
- ✅ Pull-to-refresh (errors are handled inside the handler — the spinner ends by itself)
- ✅ Continuous load-more: geometry probe on the List body + sentinel backstop for short lists; **prefetch via `mode: .pagesAhead(2)`** à la ASDK/IGListKit — loads before the user reaches the bottom
- ✅ Flat-list reorder (`onMoveRows` + `basicEditMode`) — iOS only
- ✅ Page scaffold: self-rendered title header + leading/trailing slots, inline search (works outside a `NavigationStack`), loading row, below-list bottom bar, content-key slide transitions
- ✅ Reorder + swipe + tap + refresh + load-more share one list with no identity conflicts

## Requirements

| | |
|---|---|
| Platforms | iOS 26+ · macOS 26+ · tvOS 26+ · watchOS 26+ · visionOS 26+ |
| Swift | tools 6.2, Swift 6 mode, `ApproachableConcurrency` |
| Dependencies | **NONE** — pure SwiftUI |

> **Platform note**: tvOS & watchOS build (verified via `xcodebuild` against the
> simulator SDKs) but with reduced behavior — `swipeActions` doesn't exist there, so
> rows expose their actions as accessibility actions only; `listRowSeparator` and
> `scrollContentBackground` are likewise no-ops.

## Installation

**Swift Package Manager:**

```swift
dependencies: [
    .package(url: "https://github.com/NguyenPhongVN/BasicList.git", from: "1.0.0"),
]
```

Or track `main` to pick up changes immediately (not recommended for production apps):

```swift
dependencies: [
    .package(url: "https://github.com/NguyenPhongVN/BasicList.git", branch: "main"),
]
```

Or a local path dependency (for parallel development in a monorepo):

```swift
dependencies: [
    .package(path: "../BasicList"),
]
```

Then import:

```swift
import BasicList
```

## Usage

### Which view?

| Situation | Use |
|---|---|
| Have an items array, need built-in header/empty-state/swipe/tap/refresh/load-more | `BasicListView` |
| Need a full PAGE around the list — title, slots, search, bottom bar | `BasicListPage` |
| Screen builds its own complex sections/rows (custom sections, interleaved content) | `BasicPlainList` |

`BasicListView` is built ON TOP of `BasicPlainList` — every list shares one render language: transparent (the screen pours its own background), content margins 0, minimum row height 0.

### Flat list

Items that are already `Identifiable`:

```swift
BasicListView(items: accounts, config: .house) { account in
    AccountRowView(account)          // the cell applies .basicListRowStyle() itself
}
```

Items that are not `Identifiable` — attach an id via closure, like `ForEach(id:)`:

```swift
BasicListView(items: accounts, id: \.name, config: .house) { account in
    AccountRowView(account)
}
```

### Sectioned list — sticky header per group

```swift
let sections: [BasicListSection<Transaction>] = [
    BasicListSection(section: "Today", items: todays) {          // Identifiable items — no itemID needed
        DayHeader("TODAY")          // sticky while scrolling
    } footer: {
        DayFooter("TODAY")          // optional — omit the footer init when the group needs none
    },
    BasicListSection(section: "Yesterday", items: yesterdays) {
        DayHeader("YESTERDAY")
    },
]

BasicListView(sections: sections, config: .house) { transaction in
    TransactionRowView(transaction)
}
```

Items that are NOT `Identifiable` — attach an id via the `itemID:` closure:

```swift
BasicListSection(section: "Today", items: rows, itemID: \.key) { DayHeader("TODAY") }
```

### Chain modifiers

Builder-style modifiers returning `Self` — chain freely, no hidden state depends on call order.

> ⚠️ **Chain rule**: `basicList*` modifiers only attach directly to `BasicListView` — a
> system modifier (`padding`, `background`, …) returns `some View` and ends the chain.
> Apply system modifiers **last**:

```swift
BasicListView(items: transactions, config: .house) { TransactionRowView($0) }
    .basicListHeader { AccountBalanceHeader() }        // or .basicListHeader(mode: .pinnedTop) { ... }
    .basicListEmptyState { EmptyHero() }               // when the list is empty
    .basicListFooter { SuggestionCategories() }        // bottom of the list
    .rowSwipeActions { transaction in                  // swipe from the right (default .trailing)
        [
            BasicListSwipeAction(title: "Delete", systemImage: "trash", isDestructive: true) {
                vm.delete(transaction)
            },
        ]
    }
    .rowSwipeActions(edge: .leading) { _ in            // add swipe from the left edge
        [BasicListSwipeAction(title: "Pin", systemImage: "pin.fill") { vm.pin($0) }]
    }
    .rowContextMenu { transaction in                   // long-press menu
        Button("Copy") { vm.copy(transaction) }
    }
    .onRowTap { vm.open($0) }
    .onRefresh { try await api.reload() }
    .onLoadMore(mode: .pagesAhead(2)) { try? await api.nextPage() }  // prefetch 2 screens; handler is non-throwing — handle errors inside it
```

Reorder (flat list, iOS only — the handle appears when `editMode` is `.active`):

```swift
BasicListView(items: categories, config: .house) { CategoryRowView($0) }
    .onMoveRows { vm.move($0, to: $1) }
    .basicEditMode($editMode)
```

### Page scaffold — `BasicListPage`

`BasicListPage` wraps the engine with the chrome a list page shares: a **self-rendered header** (title + subtitle + leading/trailing slots — no `navigationTitle`, so it runs standalone in a sheet/cover AND inside a `NavigationStack`), an **inline search field** (NOT `.searchable`), a **loading row** that never swaps the list out, and a **bottom bar** slot below the list. The inits mirror the engine's three forms (flat `Identifiable` / flat with `id:` / `sections:`); every engine modifier is forwarded unchanged under the `basicPage*` prefix (replace semantics included).

```swift
BasicListPage(title: "Log", subtitle: "October", items: transactions, config: .pageHouse) {
    TransactionRowView($0)
}
.basicPageSearch($query, prompt: "Search transactions")   // inline field under the header — caller owns filtering
.basicPageTrailing { Button { vm.add() } label: { Image(systemName: "plus.circle.fill") } }
.basicPageIsLoading(vm.isLoading)                          // ProgressView row between chrome and list — list stays mounted
.basicPageRowTap { vm.open($0) }
.basicPageRowSwipeActions { vm.swipeActions(for: $0) }
.basicPageRefresh { try await api.reload() }
.basicPageLoadMore { try? await api.nextPage() }
```

The two page-only mechanics for time-windowed pages:

```swift
// Bottom bar — a below-list slot for the caller's OWN component (the package
// ships the slot, never the component — a period stepper is app chrome):
.basicPageBottomBar { PeriodStepper(windowStart: $windowStart, anchor: currentPeriod) }

// Content key — rebuilds the list under a NEW identity when the key changes,
// so the transition animates the flip while the chrome stays put (pair with
// a withAnimation around the window change on the caller's side):
.basicPageContentKey(windowStart, transition: .asymmetric(
    insertion: .move(edge: pageForward ? .trailing : .leading),
    removal: .move(edge: pageForward ? .leading : .trailing)))
```

The default empty state (icon + title + message) comes from `BasicListPageConfig`; `.basicPageEmptyState { ... }` replaces it.

### Bare list — `BasicPlainList`

A screen that **builds its own** complex sections/rows → use the bare list directly (transparent background, content margins 0, minimum row height 0):

```swift
BasicPlainList(config: .house) {
    ForEach(sections) { ... }
}
```

### Standalone building blocks

The same vocabulary applies when a screen writes its own `List`:

```swift
// The standard style of ONE house row — idempotent
row.basicListRowStyle()

// Bottom spacer that scrolls with content (clearing the tab bar)
BasicListSpacer(height: config.bottomClearance)

// Load-more sentinel for self-built lists
BasicListScrollSentinel { await vm.loadMore() }
```

## Config

### `BasicListConfig` — the engine

Every color/metric comes in through the config — **missing config is a compile error**, there is no silent default look:

| Field | Meaning |
|---|---|
| `destructiveActionTint` | Tint of the swipe action flagged `isDestructive: true` |
| `bottomClearance` | Bottom clearance of the list (clearing the tab bar) — pass `0` when the context doesn't cover the bottom |

### `BasicListPageConfig` — the page chrome

Same contract for the page layer (title/subtitle colors + fonts, page background, search colors, default empty state wording/icon, loading tint) plus the two forwarded engine fields (`destructiveActionTint`, `bottomClearance` — the page derives the inner `BasicListConfig` from them, so a screen wires ONE config).

### Single-point wiring

The app layer assembles the standard values at **one point** instead of scattering colors across call sites:

```swift
extension BasicListConfig {
    static var house: BasicListConfig {
        BasicListConfig(destructiveActionTint: .red, bottomClearance: 80)
    }
}
```

Changing the look of every list in the app means editing exactly that one wiring file.

**Evolution policy** — the config structs are the library's main semver surface: new fields ship ONLY as new `init` overloads with defaults (existing init signatures never change) or as builder methods, so upgrades stay source-compatible.

## Public API

### Engine

| Symbol | Role |
|---|---|
| `BasicListView` | The main engine — flat & sectioned |
| `BasicPlainList` | Bare `.plain` list — the base of every house list |
| `BasicListConfig` | Engine colors/metrics passed in |
| `BasicListSection` | One group + sticky header + optional footer (headers stored as closures — built only when the group renders) |
| `BasicListSwipeAction` | Describes one swipe action (`role: .destructive` takes the config tint) |
| `BasicListHeaderMode` | `.scrollsWithContent` / `.pinnedTop` |
| `BasicListLoadMoreMode` | `.pixelThreshold(CGFloat)` / `.pagesAhead(Int)` — mutually exclusive by type |
| `BasicListSpacer` | Transparent spacer that scrolls with content |
| `BasicListScrollSentinel` | 1pt row firing on `onAppear` — load-more for self-built lists |
| `View.basicListRowStyle()` | Standard house row style — idempotent |

### Engine modifiers (`.basicList*` chain)

| API | Effect |
|---|---|
| `.basicListHeader(mode:_:)` | Header at the top of the list — scrolls or pinned |
| `.basicListEmptyState(_:)` | Empty hero INSIDE the list (keeps list identity) |
| `.basicListFooter(_:)` | Bottom content — after rows, before the sentinel |
| `.rowSwipeActions(edge:allowsFullSwipe:_:)` | Handler returns `[BasicListSwipeAction]` per item — both edges coexist; `allowsFullSwipe: false` opts out of full swipe |
| `.rowContextMenu(_:)` | Long-press menu per item |
| `.onRowTap(_:)` | Full-area row tap — doesn't steal the swipe gesture |
| `.onMoveRows(_:)` + `.basicEditMode(_:)` | Drag-to-reorder flat list (iOS) |
| `.onRefresh(_:)` | Pull-to-refresh; errors handled inside the handler |
| `.onLoadMore(mode:_:)` | Continuous load-more near the bottom |

### Page scaffold (`BasicListPage`)

| API | Effect |
|---|---|
| `init(title:subtitle:items/sections:config:content:)` | The three engine inits + page chrome |
| `.basicPageLeading/_basicPageTrailing` | Header slots (nav-bar-leading/trailing roles without a nav bar) |
| `.basicPageSearch(_:prompt:)` | Inline search field under the header — runs outside a `NavigationStack` |
| `.basicPageIsLoading(_:)` | Loading row above the list — list identity never breaks |
| `.basicPageBottomBar(_:)` | Below-list slot for the caller's own component (stepper, legend…) |
| `.basicPageContentKey(_:transition:)` | Re-keys the list content — asymmetric slide for paged pages |
| `.basicPageListHeader / .basicPageEmptyState / .basicPageFooter / .basicPageRowSwipeActions / .basicPageRowContextMenu / .basicPageRowTap / .basicPageMoveRows / .basicPageEditMode (iOS) / .basicPageRefresh / .basicPageLoadMore` | Forwards to the engine's `.basicList*` surface unchanged |

## Swipe actions — mandatory rules

- **Never use `role: .destructive`'s system role**: destructive-role + full swipe triggers the row slide-away animation (SwiftUI considers the row deleted) — if nothing re-renders, the row disappears even though the data is intact. Full swipe fires the handler; the handler is the screen's own confirm hand-off (popup). The package tints the button via config instead.
- The red tint applies **only** to destructive actions — `role: .destructive` (role form, preferred) or `isDestructive: true` (boolean form) — taken from `config.destructiveActionTint`; regular actions keep the system tint.
- Two actions with the same title remain two separate buttons (identity by position, not by title).

## Load-more — mechanics & verification

1. **Geometry probe** attached to the List BODY (`onScrollGeometryChange`) — the observer lives for the whole list lifetime. Distance from bottom = `contentSize.height − visibleRect.maxY` — the primitive Apple already computes; **never re-derive it from `contentOffset`/`containerSize`/`insets` parts** (`containerSize` measured 782/724/702/844 across embeddings — unstable semantics, documented by Apple as "overall size" only).
2. **Sentinel** (1pt row at the end) fires `onAppear` — backstop for short lists (< one screen).
3. **Fire gate** — at most ONE fire per 400 ms cooldown window (`ContinuousClock`, engine-side `BasicListLoadGate`) across all trigger sources: duplicate sources land 1–400 ms apart; a blocked legitimate chain fire RETRIES after the window against the CURRENT geometry (never strands the last page, never fires after the user left). On disappear the probe invalidates pending retries against dead geometry.
4. **Loop prevention lives on the caller side (VM)**: `inFlight` blocks concurrent fires, `exhausted` skips when out of pages — probe/sentinel keep no state.

Measured invariants (iPhone 18 Pro Max simulator, `LoadMoreSimulatorTests`): the trigger lands exactly at the configured threshold in every embedding; one load per region entry; attaching a short list fires once; exhaustion stops clean; idle is silent. **Chain length beyond one entry is runtime-dependent** (List estimate drift differs per OS) — design invariants assert on every runtime, exact baselines are pinned per device.

Re-run the simulator suite:

```bash
xcodebuild test -scheme BasicList \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -only-testing:BasicListTests/LoadMoreSimulatorTests
```

Real-app acceptance (~3 minutes): log inside the load-more handler → scroll slowly on one screen with a tab bar and one full-screen → exactly ONE log per region entry, fire distance ≈ threshold on both; a short list opens with exactly one fire; scrolling stops → logs stop; standing still fires nothing.

## Accessibility

- Row with tap → trait `.isButton` + `accessibilityAction` — rotor/double-tap activates it, not just the raw tap gesture.
- Swipe actions expose `.accessibilityAction(named:)` — the swipe gesture doesn't exist for VoiceOver.
- Sentinel/spacer are hidden from VoiceOver (mechanical virtual rows, not content).
- Page title carries the heading trait (VoiceOver rotor navigation); the search field reads its prompt.
- These contracts are PINNED by `InteractionSimulatorTests` (a11y tree inspection + activation on a real simulator — CI enables simulator accessibility for the suite).

## Demos — the Examples app

Live demos live in the `Examples/` app at the repo root (open `SC.xcworkspace`): a hub plus one demo per layer — flat page (search · slots · swipe both edges · context menu · refresh · load-more), sectioned page (sticky headers + group footers with totals), date pager (previous/next period with the `.basicPageContentKey` slide), empty state. Launch arguments (`-flat` / `-sectioned` / `-datePager` / `-empty`) jump straight to one demo — handy for `simctl` screenshots.

## Project layout

```
Sources/BasicList/
├── Engine/   — BasicListView · BasicPlainList · BasicListConfig · BasicListSupport
└── Page/     — BasicListPage · BasicListPageConfig
```

One module, two layers — folders are organizational only. The page forwards the engine's surface, so the shared vocabulary stays engine-side.

## The engine's three principles

1. **Data in, events out** — swipe/tap/move/refresh/load-more are all closures passed in by the caller; the engine keeps no business state, the single data source is the array/sections passed in.
2. **Immutable, modifiers return `Self`** — chain freely, no hidden state that changes with modifier call order.
3. **Design goes through config** — no hardcoded color/metric inside the module; the app decides the look.

## License

[MIT](LICENSE) — Copyright (c) 2026 NguyenPhongVN
