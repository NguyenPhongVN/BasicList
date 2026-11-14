import SwiftUI
import Testing
@testable import BasicList

// MARK: - BasicListView engine smoke tests
//
// Host tests can't render a List — this suite's scope: every init +
// modifier COMBINES with all the others, chaining returns Self without
// breaking generics, and the body builds (the view tree is evaluated, not
// rendered). Render behavior belongs to the previews.

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
        .rowSwipeActions { _ in
            [BasicListSwipeAction(title: "Delete", systemImage: "trash", isDestructive: true) {}]
        }
        .rowSwipeActions(edge: .leading) { _ in
            [BasicListSwipeAction(title: "Pin", systemImage: "pin.fill") {}]
        }
        .rowContextMenu { _ in Button("Menu") {} }
        .onRowTap { _ in }
        .onMoveRows { _, _ in }
        .onRefresh {}
        .onLoadMore {}
        .onLoadMore(mode: .pagesAhead(2)) {}
        .onLoadMore(mode: .pixelThreshold(100)) {}
        _ = view.body
    }

    @Test("Flat init with id closure — item not Identifiable")
    func flatInitWithIDClosure() {
        let view = BasicListView(items: ["alpha", "beta"], id: { $0 }, config: config) {
            Text($0)
        }
        .basicListHeader { Text("Header") }
        .onRowTap { _ in }
        _ = view.body
    }

    @Test("Sectioned init — groups with and without footers both build")
    func sectionedInitMixedFooters() {
        let sections: [BasicListSection<Item>] = [
            BasicListSection(section: "Today", items: [Item(id: 1)], itemID: { AnyHashable($0.id) }) {
                Text("H1")
            } footer: {
                Text("F1")
            },
            BasicListSection(section: "Yesterday", items: [Item(id: 2)], itemID: { AnyHashable($0.id) }) {
                Text("H2")
            },
        ]
        let view = BasicListView(sections: sections, config: config) {
            Text("\($0.id)")
        }
        .basicListHeader { Text("Header") }
        .rowContextMenu { _ in Button("Menu") {} }
        .onLoadMore {}
        _ = view.body
    }

    @Test("Sectioned init accepts any AnyHashable — an Int section works too")
    func sectionedInitWithIntSection() {
        let sections = [
            BasicListSection(section: 2026, items: [Item(id: 1)], itemID: { AnyHashable($0.id) }) {
                Text("H")
            },
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
        .onMoveRows { _, _ in }
        .basicEditMode(Binding.constant(EditMode.active))
        _ = view.body
    }

    @Test("basicEditMode accepts nil — leaves the environment untouched, chain builds")
    func editModeNilBindingBuilds() {
        let view = BasicListView(items: [Item(id: 1)], config: config) {
            Text("\($0.id)")
        }
        .onMoveRows { _, _ in }
        .basicEditMode(Binding<EditMode>?(nil))
        _ = view.body
    }
    #endif
}
