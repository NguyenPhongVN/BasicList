# BasicList

House list engine — pure SwiftUI, **deps NONE** (no dependency on any module inside the
package; preview/demo uses literal spacing). The module **reads no app design layer**
(no design colors, no tab metrics, no tokens): every color/metric comes in through
`BasicListConfig` — the engine decides the mechanism, the caller decides the look.

## 1. Which view?

| Situation | Use |
|---|---|
| Have an items array, need built-in header/empty-state/swipe/tap/refresh/load-more | `BasicListView` |
| Screen builds its own complex sections/rows (custom sections, interleaved content) | `BasicPlainList` |

`BasicListView` is built ON TOP of `BasicPlainList` — every list in the app shares one
render language: transparent (the screen pours its own background), content margins 0,
minimum row height 0.

## 2. Quick start

### Flat list — swipe + tap + refresh + load-more

```swift
BasicListView(items: accounts, config: .house) { account in
    AccountRowView(account)          // the cell applies .basicListRowStyle() itself
}
.basicListHeader { AccountBalanceHeader() }   // header scrolls with content
.basicListEmptyState { AccountEmptyView() }   // shown when items is empty
.rowSwipeActions { account in
    [
        BasicListSwipeAction(title: "Edit", systemImage: "pencil") { edit(account) },
        BasicListSwipeAction(title: "Delete", systemImage: "trash",
                             isDestructive: true) { confirmDelete(account) },
    ]
}
.rowContextMenu { account in
    Button("Copy name") { copy(account.name) }
}
.onRowTap { account in openDetail(account) }
.onRefresh { try await api.reload() }
.onLoadMore { try? await api.nextPage() }   // non-throwing: handle errors inside the handler
```

### Sectioned list — sticky header per group

```swift
let sections = Dictionary(grouping: transactions, by: \.day)
    .map { day, txns in
        BasicListSection(section: day, items: txns) {          // Identifiable items — no itemID needed
            TransactionDayHeader(day)      // sticky while scrolling
        } footer: {
            TransactionDayFooter(day)      // optional — omit the footer init when the group needs none
        }
    }

BasicListView(sections: sections, config: .house) { transaction in
    TransactionRowView(transaction)
}
```

Items that are NOT `Identifiable` → pass the `itemID:` closure instead (like `ForEach(id:)`), e.g. `itemID: \.key`.

> `BasicListView` is an immutable struct — every modifier returns `Self`, so chains are
> free. Items that aren't `Identifiable` use `init(items:id:config:content:)`, attaching
> an id via closure like `ForEach(id:)`.

## 3. Config — `BasicListConfig`

**Must be passed at construction** — the module has no default that injects a design
value: missing config is a compile error instead of a silent look.

| Field | Meaning | What the app passes |
|---|---|---|
| `destructiveActionTint` | Tint of the swipe action flagged `isDestructive: true` (regular actions keep the system tint) | the app's destructive red |
| `bottomClearance` | Bottom spacer of the list — clearance when the list sits above a tab bar; contexts that don't cover the bottom pass 0 | the app's standard tab-bar clearance |

**Single-point wiring** — the app layer defines an extension
`BasicListConfig.house` collecting the app's standard values. Call sites always pass
`config: .house`; changing the look of every list in the app means editing exactly that
one wiring file, not scattering values per screen.

**Evolution policy** — new fields ship ONLY as new `init` overloads with defaults (the
existing init signature never changes) or as builder methods; a signature change here
would break every list construction.

## 4. `BasicListView` API

| API | Effect |
|---|---|
| `.basicListHeader(mode:_:)` | Header at the top of the list — `.scrollsWithContent` (scrolls with content) or `.pinnedTop` (pinned) |
| `.basicListEmptyState(_:)` | Empty hero that runs INSIDE the list (keeps list identity across the empty/loaded phases) |
| `.basicListFooter(_:)` | Bottom content — after rows, before the load-more sentinel |
| `.rowSwipeActions(edge:allowsFullSwipe:_:)` | Handler returns `[BasicListSwipeAction]` per item — `.trailing` by default; call again with `.leading` for left-edge swipe; `allowsFullSwipe: false` opts out of full swipe (default `true` — a full swipe fires the FIRST action of the edge immediately; the handler is a confirm hand-off) |
| `.rowContextMenu(_:)` | Long-press menu per item — doesn't steal regular taps or swipes |
| `.onRowTap(_:)` | Full-area row tap (contentShape) — doesn't steal the swipe gesture |
| `.onMoveRows(_:)` | Drag-to-reorder flat list — handle only appears when `editMode` is `.active` |
| `.basicEditMode(_:)` | Pins the List's `editMode` to the screen's binding (iOS-only) |
| `.onRefresh(_:)` | Pull-to-refresh; errors are swallowed inside the handler (`try?`), the spinner ends by itself |
| `.onLoadMore(mode:_:)` | Continuous load-more near the bottom — `mode: .pixelThreshold(CGFloat)` (default 600pt) or `mode: .pagesAhead(Int)` (ASDK/IGListKit-style prefetch, region = N × viewport); mutually exclusive by type via `BasicListLoadMoreMode`. Handler is non-throwing — handle errors inside it; an empty list still fires once at attach |

Shared vocabulary (`BasicListSupport.swift`) — usable by both the engine and screens
that build their own list:

| Type/helper | Meaning |
|---|---|
| `BasicListSection` | One group + sticky header + optional footer; header/footer stored as CLOSURES (built only when the group actually renders); `Item: Identifiable` → no `itemID:` needed (ids map to `\.id`) |
| `BasicListSwipeAction` | One swipe action; `role: .destructive` (or the boolean `isDestructive:` form) marks data-destroying actions — the tint comes from config, not from the action |
| `BasicListSpacer(height:)` | Transparent row of `height` — scrolls-with-content padding |
| `BasicListScrollSentinel` | 1pt row that fires on `onAppear` — use as the last row when a screen builds its own list + load-more |
| `.basicListRowStyle()` | Standard style for one row (no insets/separator, clear background) — your cell should call it |

⚠️ `.pinnedTop` + sectioned **is unverified** — pinned is currently only used with flat
lists; avoid the combination until it's needed and tested.

## 5. How load-more works

1. **Geometry probe** attached to the List BODY (`onScrollGeometryChange`) — the observer
   lives for the whole list lifetime (unlike attaching the probe to a sentinel row, which
   a lazy List only materializes when the user has already scrolled near the bottom).
   Fires on STATE TRANSITIONS: entering the bottom region, or a new page attaching while
   still in the region (keeps loading continuously until out of the region or out of
   pages).
2. **Sentinel** (1pt row at the end of the list) fires `onAppear` — backstop for short
   lists (< one screen).
3. **Loop prevention lives on the caller side (VM)**: `inFlight` blocks concurrent
   fires, `exhausted` skips when out of pages — probe/sentinel keep no state.
4. **Prefetch `pagesAhead`** (ASDK `leadingScreensForBatching` / IGListKit style): the
   bottom region = N × viewport height instead of a static pixel threshold —
   inside the region, the probe keeps loading as pages attach until the distance exceeds
   the region or pages run out. `.onLoadMore(mode: .pagesAhead(2))` ≈ keep 2 pages ahead
   of the user. The mode is the `BasicListLoadMoreMode` enum — `.pixelThreshold(CGFloat)`
   and `.pagesAhead(Int)` are mutually exclusive by type; the engine doesn't measure page
   height (data in / events out) — the unit of measure is the viewport.
5. **Lifecycle**: pending retries (gate-blocked fires waiting out the cooldown) are
   DISCARDED when the list leaves the hierarchy — firing against dead geometry is never
   useful. Already-dispatched handler tasks are NOT cancelled — keep handler work
   VM-owned so late runs are harmless (same contract as before).

### Measured behavior — post-fix verification 2026-11-14
([Docs/LoadMoreVerification.md](../../Docs/LoadMoreVerification.md))

- The trigger lands exactly at the configured threshold on every embedding —
  the distance comes from `visibleRect` (Apple's own primitive, computed from
  offset + insets + container); the old manual algebra was biased by how the
  list was embedded (measured 782/724/702/844 for `containerSize`).
- One fire per cooldown window (400 ms) across ALL sources (probe transition +
  List content-size estimate steps + sentinel) — measured duplicates arrived
  1–400 ms apart and are now collapsed. A chain fire blocked by the window
  retries once against FRESH geometry — continuous loading never strands, and
  a retry whose region check fails is discarded.
- Chain loads continue while the grown list stays inside the region and stop
  when a page push exits it (or pages run out) — idle is silent.
- Attaching a short list fires once (gate collapses the transition + sentinel
  duplicates); the chain may load further pages while the list remains inside
  the region — that is the designed prefetch, not a duplicate.
- A page attach grows contentSize (rows + List estimate drift, measured
  +1086 pt) which can push a stationary user out of the region — the chain
  stops and the next scroll delivers the remaining page.

Any change to the probe/sentinel MUST re-run the simulator suite
(`Tests/BasicListTests/LoadMoreSimulatorTests.swift`) and compare against the
tables in the verification doc.

## 6. Swipe actions — mandatory rules

- **Never use `role: .destructive`**: destructive-role + full swipe triggers the row
  slide-away animation (SwiftUI considers the row deleted) — if nothing re-renders, the
  row disappears even though the data is intact. Full swipe fires the handler; the
  handler is the screen's own confirm hand-off (popup).
- The red tint applies **only** to destructive actions — `role: .destructive` (role
  form, preferred) or `isDestructive: true` (boolean form) — taken from
  `config.destructiveActionTint`; regular actions keep the system tint.
- Two actions with the same title remain two separate buttons (identity by position,
  not by title).

## 7. Accessibility

- Row with tap → trait `.isButton` + `accessibilityAction` — rotor/double-tap activates
  it, not just the raw tap gesture.
- Swipe actions expose `.accessibilityAction(named:)` — the swipe gesture doesn't exist
  for VoiceOver.
- Sentinel/spacer are hidden from VoiceOver (mechanical virtual rows, not content).

## 8. Preview

13 live demo shapes in `Sources/BasicList/BasicListPreviews.swift` — a catalog
covering EVERY public API (one preview per capability, coverage matrix at the top
of the file): the three data-in shapes (flat / non-Identifiable / sectioned),
both header modes, empty state (at launch + after removing rows), footer, swipe
on both edges, context menu, row tap, reorder + editMode (iOS), pull-to-refresh
(slow / error-in-handler), all three load-more modes (`.pixelDefault`,
`.pixelThreshold(150)`, `.pagesAhead(2)`), `BasicPlainList`, and the
self-built-list vocabulary (`BasicListScrollSentinel` + `BasicListSpacer` +
`.basicListRowStyle()`). Each row has its own look (colored glyph + money, not a
bare `Text`). Neutral config — the real design values exist only in the app
(`BasicListConfig.house`).

## 9. Module notes

- Standalone package, product `BasicList`. `public` API is exactly what callers need
  (types + inits + modifiers); engine internals (probe, swipe rendering, Row/Group) stay
  private — a handful of stored properties are `package` so the host test suite can
  assert the replace (last-call-wins) and emptiness semantics, still invisible to
  consumers. The app layer imports explicitly with `import BasicList`.
- **Code standard**: SwiftLint `--strict` is the gate — CI enforces it on every push/PR;
  `.swiftlint.yml` documents every deviation from defaults with its reason.
- Data in, events out throughout: the engine keeps no business state, the single data
  source is the array/sections the caller passes in.
