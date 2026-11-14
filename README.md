# BasicList

[![CI](https://github.com/NguyenPhongVN/BasicList/actions/workflows/ci.yml/badge.svg)](https://github.com/NguyenPhongVN/BasicList/actions/workflows/ci.yml)

A SwiftUI **"array in — item out"** list engine for house lists — one view for both flat and sectioned shapes (sticky header per group), with built-in header / empty-state / footer / swipe actions / row tap / pull-to-refresh / continuous load-more / reorder.

Standalone package, pure SwiftUI — **reads no app design layer**: every color/metric comes in through `BasicListConfig`.

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
- ✅ Reorder + swipe + tap + refresh + load-more share one list with no identity conflicts

## Requirements

| | |
|---|---|
| Platforms | iOS 26+ · macOS 26+ · tvOS 26+ · watchOS 26+ · visionOS 26+ — ⚠️ see note below |
| Swift | tools 6.3, Swift 6 mode, `ApproachableConcurrency` |
| Dependencies | **NONE** — pure SwiftUI |

> **Platform note**: tvOS & watchOS build (verified via `xcodebuild` against the
> simulator SDKs) but with reduced behavior — `swipeActions` doesn't exist there, so
> rows expose their actions as accessibility actions only; `listRowSeparator` and
> `scrollContentBackground` are likewise no-ops. Details:
> [Docs/LoadMoreVerification.md](Docs/LoadMoreVerification.md) §5.

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

## Quick start

### Flat list

Items that are already `Identifiable`:

```swift
BasicListView(items: accounts, config: .house) { account in
    AccountRowView(account)
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
    BasicListSection(section: "Today", items: todays, itemID: \.id) {
        DayHeader("TODAY")          // sticky while scrolling
    } footer: {
        DayFooter("TODAY")          // optional — omit the footer init when the group needs none
    },
    BasicListSection(section: "Yesterday", items: yesterdays, itemID: \.id) {
        DayHeader("YESTERDAY")
    },
]

BasicListView(sections: sections, config: .house) { transaction in
    TransactionRowView(transaction)
}
```

### Chain modifiers

Builder-style modifiers returning `Self` — chain freely, no hidden state depends on call order:

```swift
BasicListView(items: transactions, config: .house) { TransactionRowView($0) }
    .basicListHeader { AccountBalanceHeader() }        // or .basicListHeader(mode: .pinnedTop) { ... }
    .basicListEmptyState { EmptyHero() }               // when the list is empty
    .basicListFooter { SuggestionCategories() }        // bottom of the list
    .rowSwipeActions { transaction in                    // swipe from the right (default .trailing)
        [
            BasicListSwipeAction(title: "Delete", systemImage: "trash", isDestructive: true) {
                vm.delete(transaction)
            },
        ]
    }
    .rowSwipeActions(edge: .leading) { _ in              // add swipe from the left edge
        [BasicListSwipeAction(title: "Pin", systemImage: "pin.fill") { vm.pin($0) }]
    }
    .rowContextMenu { transaction in                     // long-press menu
        Button("Copy") { vm.copy(transaction) }
    }
    .onRowTap { vm.open($0) }
    .onRefresh { try await api.reload() }
    .onLoadMore(mode: .pagesAhead(2)) { try await api.nextPage() }   // prefetch 2 screens before the bottom; mode: .pixelThreshold(400) for a static threshold
```

Reorder (flat list, iOS only — the handle appears when `editMode` is `.active`):

```swift
BasicListView(items: categories, config: .house) { CategoryRowView($0) }
    .onMoveRows { vm.move($0, to: $1) }
    .basicEditMode($editMode)
```

### Bare list — `BasicPlainList`

A screen that **builds its own** complex sections/rows → use the bare list directly
(transparent background, content margins 0, minimum row height 0):

```swift
BasicPlainList(config: .house) {
    ForEach(sections) { ... }
}
```

`BasicListView` is built ON TOP of this — every list in the app shares one render language.

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

## Config — `BasicListConfig`

Every color/metric comes in through the config — **missing config is a compile error**, there is no silent default look:

| Field | Meaning |
|---|---|
| `destructiveActionTint` | Tint of the swipe action flagged `isDestructive: true` |
| `bottomClearance` | Bottom clearance of the list (clearing the tab bar) — pass `0` when the context doesn't cover the bottom |

The app layer assembles the standard values at **one point** instead of scattering colors across call sites:

```swift
extension BasicListConfig {
    static var house: BasicListConfig {
        BasicListConfig(
            destructiveActionTint: .red,
            bottomClearance: 80)
    }
}
```

Changing the look of every list in the app means editing exactly that one wiring file.

## The engine's three principles

1. **Data in, events out** — swipe/tap/move/refresh/load-more are all closures passed in by the caller; the engine keeps no business state, the single data source is the array/sections passed in.
2. **Immutable, modifiers return `Self`** — chain freely, no hidden state that changes with modifier call order.
3. **Design goes through config** — no hardcoded color/metric inside the module; the app decides the look.

## Public API

| Symbol | Role |
|---|---|
| `BasicListView` | The main engine — flat & sectioned |
| `BasicPlainList` | Bare `.plain` list — the base of every house list |
| `BasicListConfig` | Colors/metrics passed in |
| `BasicListSection` | One group + sticky header + optional footer |
| `BasicListSwipeAction` | Describes one swipe action |
| `BasicListHeaderMode` | `.scrollsWithContent` / `.pinnedTop` |
| `BasicListSpacer` | Transparent spacer that scrolls with content |
| `BasicListScrollSentinel` | Sentinel that fires load-more for short lists |
| `View.basicListRowStyle()` | Standard house row style — idempotent |

Load-more mechanics (probe geometry + sentinel), mandatory rules and A11y — see
[`Sources/BasicList/README.md`](Sources/BasicList/README.md). Measured baseline, known
issues and the verification protocol — see
[`Docs/LoadMoreVerification.md`](Docs/LoadMoreVerification.md).

## License

[MIT](LICENSE) — Copyright (c) 2026 NguyenPhongVN
