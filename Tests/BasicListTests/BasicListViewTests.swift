import SwiftUI
import Testing
@testable import BasicList

// MARK: - BasicListView engine smoke tests
//
// Host tests can't render a List — this suite's scope: every init +
// modifier COMBINES with all the others, chaining returns Self without
// breaking generics, and the body builds (the view tree is evaluated, not
// rendered). Render behavior belongs to the Examples app.

@MainActor
struct BasicListViewTests {

    private struct Item: Identifiable { let id: Int }
    private let config = BasicListConfig(destructiveActionTint: .red, bottomClearance: 0)

    @Test("Flat init (Identifiable item) + full modifier chain — still Self")
    func flatChainAllModifiers() {
        let view = BasicListView(items: [Item(id: 1), Item(id: 2)], config: config) {
            Text("\($0.id)")
        }
        .basicListHeader { Text("Header") }
        .basicListHeader(mode: .pinnedTop) { Text("Pinned") }
        .basicListEmptyState { Text("Empty") }
        .basicListFooter { Text("Footer") }
        .basicListSwipeActions { _ in
            [BasicListSwipeAction(title: "Delete", systemImage: "trash", isDestructive: true) {}]
        }
        .basicListSwipeActions(edge: .leading) { _ in
            [BasicListSwipeAction(title: "Pin", systemImage: "pin.fill") {}]
        }
        .basicListContextMenu { _ in Button("Menu") {} }
        .basicListRowTap { _ in }
        .basicListMoveRows { _, _ in }
        .basicListRefresh {}
        .basicListLoadMore {}
        .basicListLoadMore(mode: .pagesAhead(2)) {}
        .basicListLoadMore(mode: .pixelThreshold(100)) {}
        _ = view.body
    }

    @Test("Flat init with id closure — item not Identifiable")
    func flatInitWithIDClosure() {
        let view = BasicListView(items: ["alpha", "beta"], id: { $0 }, config: config) {
            Text($0)
        }
        .basicListHeader { Text("Header") }
        .basicListRowTap { _ in }
        _ = view.body
    }

    @Test("Flat init with a key-path — generic id closure accepts key paths")
    func flatInitWithKeyPath() {
        struct Tag { let key: String }
        let tags = [Tag(key: "a"), Tag(key: "b")]
        let view = BasicListView(items: tags, id: \.key, config: config) {
            Text($0.key)
        }
        _ = view.body
    }

    @Test("Sectioned init — groups with and without footers both build")
    func sectionedInitMixedFooters() {
        let sections: [BasicListSection<Item>] = [
            BasicListSection(section: "Today", items: [Item(id: 1)], itemID: { $0.id }) {
                Text("H1")
            } footer: {
                Text("F1")
            },
            BasicListSection(section: "Yesterday", items: [Item(id: 2)], itemID: { $0.id }) {
                Text("H2")
            }
        ]
        let view = BasicListView(sections: sections, config: config) {
            Text("\($0.id)")
        }
        .basicListHeader { Text("Header") }
        .basicListContextMenu { _ in Button("Menu") {} }
        .onLoadMore {}
        _ = view.body
    }

    @Test("Sectioned init accepts any AnyHashable — an Int section works too")
    func sectionedInitWithIntSection() {
        let sections = [
            BasicListSection(section: 2026, items: [Item(id: 1)], itemID: { $0.id }) {
                Text("H")
            }
        ]
        #expect(sections[0].section == AnyHashable(2026))
        let view = BasicListView(sections: sections, config: config) { Text("\($0.id)") }
        _ = view.body
    }

    #if os(iOS)
    @Test("basicEditMode pins a binding into the chain — body still builds")
    func editModeChainBuilds() {
        let view = BasicListView(items: [Item(id: 1), Item(id: 2)], config: config) {
            Text("\($0.id)")
        }
        .basicListMoveRows { _, _ in }
        .basicListEditMode(Binding.constant(EditMode.active))
        _ = view.body
    }

    @Test("basicEditMode accepts nil — leaves the environment untouched, chain builds")
    func editModeNilBindingBuilds() {
        let view = BasicListView(items: [Item(id: 1)], config: config) {
            Text("\($0.id)")
        }
        .basicListMoveRows { _, _ in }
        .basicListEditMode(Binding<EditMode>?(nil))
        _ = view.body
    }
    #endif

    // MARK: Emptiness rule (package member — pinned per shape)

    @Test("isEmpty — flat: rows present vs rows empty")
    func isEmptyFlat() {
        let nonEmpty = BasicListView(items: [Item(id: 1)], config: config) { _ in Text("") }
        #expect(!nonEmpty.isEmpty)
        let empty = BasicListView(items: [Item](), config: config) { _ in Text("") }
        #expect(empty.isEmpty)
    }

    @Test("isEmpty — sectioned: empty only when EVERY group is empty")
    func isEmptySectioned() {
        func section(_ name: String, ids: [Int]) -> BasicListSection<Item> {
            BasicListSection(section: name, items: ids.map(Item.init), itemID: { $0.id }) {
                Text(name)
            }
        }
        let oneGroupHasItems = BasicListView(
            sections: [section("A", ids: []), section("B", ids: [1])],
            config: config) { _ in Text("") }
        #expect(!oneGroupHasItems.isEmpty)
        let allGroupsEmpty = BasicListView(
            sections: [section("A", ids: []), section("B", ids: [])],
            config: config) { _ in Text("") }
        #expect(allGroupsEmpty.isEmpty, "every group empty → the list is empty")
        let noSections: [BasicListSection<Item>] = []
        let noGroups = BasicListView(sections: noSections, config: config) { _ in Text("") }
        #expect(noGroups.isEmpty, "no groups at all → the list is empty")
    }

    // MARK: Replace semantics (package members — last call wins)

    @Test("Modifiers replace on re-call — last call wins, both edges coexist")
    func lastCallWins() {
        var view = BasicListView(items: [Item(id: 1)], config: config) { _ in Text("") }
        #expect(view.headerBuilder == nil, "no header yet")
        #expect(view.headerMode == .scrollsWithContent, "default header mode")

        // Header: second call replaces builder + mode.
        view = view.basicListHeader { Text("First") }
        view = view.basicListHeader(mode: .pinnedTop) { Text("Second") }
        #expect(view.headerBuilder != nil)
        #expect(view.headerMode == .pinnedTop, "re-calling basicListHeader replaces mode")

        // Swipe, same edge: second call replaces the handler.
        view = view.basicListSwipeActions { _ in
            [BasicListSwipeAction(title: "First", systemImage: "1") {}]
        }
        view = view.basicListSwipeActions { _ in
            [BasicListSwipeAction(title: "Second", systemImage: "2") {}]
        }
        guard let trailing = view.rowSwipeHandler else {
            Issue.record("trailing handler missing")
            return
        }
        #expect(trailing(Item(id: 1)).first?.title == "Second",
                "same edge replaces the handler")

        // Swipe, other edge: coexists with the trailing handler, not replace.
        view = view.basicListSwipeActions(edge: .leading) { _ in
            [BasicListSwipeAction(title: "Pin", systemImage: "pin") {}]
        }
        guard let leading = view.rowSwipeLeadingHandler else {
            Issue.record("leading handler missing")
            return
        }
        #expect(trailing(Item(id: 1)).first?.title == "Second")
        #expect(leading(Item(id: 1)).first?.title == "Pin")

        // Full-swipe opt-out is per edge — trailing keeps the default `true`.
        view = view.basicListSwipeActions(edge: .leading, allowsFullSwipe: false) { _ in [] }
        #expect(view.rowSwipeAllowsFullSwipe, "trailing edge unchanged by the leading call")
        #expect(!view.rowSwipeLeadingAllowsFullSwipe, "leading edge opted out of full swipe")

        // Load-more: second call replaces handler + mode.
        view = view.basicListLoadMore {}
        view = view.basicListLoadMore(mode: .pagesAhead(3)) {}
        #expect(view.onLoadMoreHandler != nil)
        #expect(view.loadMoreMode == .pagesAhead(3), "re-calling onLoadMore replaces mode")
    }
}
