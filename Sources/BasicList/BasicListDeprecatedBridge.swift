import SwiftUI

// MARK: - Deprecated pre-unification names — the 1.2.0 removal is THIS FILE
//
// The pre-unification names of the 1.0.0 API refactor (one `basicList*`
// prefix for the engine, one mechanical `basicPage*` mirror for the page).
// Every symbol here is `@available(*, deprecated)` — deprecated in 1.0.0,
// REMOVED in 1.2.0 (README — Config, evolution policy, deprecation bridge):
// the 1.2.0 release deletes this WHOLE file. Nothing in it has a successor
// here, so the removal is one physical action instead of a symbol hunt.
// `@available(obsoleted:)` can't express a package-version removal in
// source distribution (it reacts to OS deployment targets, not package
// versions) — the file itself is the enforcement.
//
// The deprecated flat init of `BasicListPageConfig` also goes in 1.2.0, but
// stays in its own file: an extension in another file can't assign the
// struct's stored properties.

extension BasicListView {

    /// Renamed to `basicListSwipeActions` — one `basicList*` prefix for the
    /// whole engine surface.
    @available(*, deprecated, renamed: "basicListSwipeActions",
               message: "Deprecated in 1.0.0 — removed in 1.2.0.")
    public func rowSwipeActions(
        edge: HorizontalEdge = .trailing,
        allowsFullSwipe: Bool = true,
        _ handler: @escaping (Item) -> [BasicListSwipeAction]
    ) -> Self {
        basicListSwipeActions(edge: edge, allowsFullSwipe: allowsFullSwipe, handler)
    }

    /// Renamed to `basicListContextMenu` — one `basicList*` prefix for the
    /// whole engine surface.
    @available(*, deprecated, renamed: "basicListContextMenu",
               message: "Deprecated in 1.0.0 — removed in 1.2.0.")
    public func rowContextMenu(
        @ViewBuilder _ handler: @escaping (Item) -> some View
    ) -> Self {
        basicListContextMenu(handler)
    }

    /// Renamed to `basicListRowTap` — one `basicList*` prefix for the whole
    /// engine surface.
    @available(*, deprecated, renamed: "basicListRowTap",
               message: "Deprecated in 1.0.0 — removed in 1.2.0.")
    public func onRowTap(_ handler: @escaping (Item) -> Void) -> Self {
        basicListRowTap(handler)
    }

    /// Renamed to `basicListMoveRows` — one `basicList*` prefix for the whole
    /// engine surface.
    @available(*, deprecated, renamed: "basicListMoveRows",
               message: "Deprecated in 1.0.0 — removed in 1.2.0.")
    public func onMoveRows(_ handler: @escaping (IndexSet, Int) -> Void) -> Self {
        basicListMoveRows(handler)
    }

    /// Renamed to `basicListRefresh` — one `basicList*` prefix for the whole
    /// engine surface.
    @available(*, deprecated, renamed: "basicListRefresh",
               message: "Deprecated in 1.0.0 — removed in 1.2.0.")
    public func onRefresh(_ handler: @escaping () async throws -> Void) -> Self {
        basicListRefresh(handler)
    }

    /// Renamed to `basicListLoadMore` — one `basicList*` prefix for the whole
    /// engine surface.
    @available(*, deprecated, renamed: "basicListLoadMore",
               message: "Deprecated in 1.0.0 — removed in 1.2.0.")
    public func onLoadMore(
        mode: BasicListLoadMoreMode = .pixelDefault,
        _ handler: @escaping () async -> Void
    ) -> Self {
        basicListLoadMore(mode: mode, handler)
    }
}

#if os(iOS)
extension BasicListView {

    /// Renamed to `basicListEditMode` — one `basicList*` prefix for the whole
    /// engine surface.
    @available(*, deprecated, renamed: "basicListEditMode",
               message: "Deprecated in 1.0.0 — removed in 1.2.0.")
    public func basicEditMode(_ binding: Binding<EditMode>?) -> Self {
        basicListEditMode(binding)
    }
}
#endif

extension BasicListPage {

    /// Renamed to `basicPageSwipeActions` — the page mirrors the engine's
    /// `basicList*` surface mechanically.
    @available(*, deprecated, renamed: "basicPageSwipeActions",
               message: "Deprecated in 1.0.0 — removed in 1.2.0.")
    public func basicPageRowSwipeActions(
        edge: HorizontalEdge = .trailing,
        allowsFullSwipe: Bool = true,
        _ handler: @escaping (Item) -> [BasicListSwipeAction]
    ) -> Self {
        basicPageSwipeActions(edge: edge, allowsFullSwipe: allowsFullSwipe, handler)
    }

    /// Renamed to `basicPageContextMenu` — the page mirrors the engine's
    /// `basicList*` surface mechanically.
    @available(*, deprecated, renamed: "basicPageContextMenu",
               message: "Deprecated in 1.0.0 — removed in 1.2.0.")
    public func basicPageRowContextMenu(
        @ViewBuilder _ handler: @escaping (Item) -> some View
    ) -> Self {
        basicPageContextMenu(handler)
    }
}
