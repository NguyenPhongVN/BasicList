import SwiftUI
import Testing
@testable import BasicList

// MARK: - Smoke test engine BasicListView
//
// Host test không render được List — scope của suite này: mọi init +
// modifier TỔ HỢP được với nhau, chain trả Self không phá generic, body
// dựng được (đánh giá cây view, không render). Hành vi render thuộc preview.

@MainActor
struct BasicListViewTests {

    private struct Item: Identifiable { let id: Int }
    private let config = BasicListConfig(destructiveActionTint: .red, bottomClearance: 0)

    @Test("Flat init (Item Identifiable) + chain đầy đủ modifier — vẫn Self")
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
        .onLoadMore(pagesAhead: 2) {}
        .onLoadMore(pixelThreshold: 100) {}
        _ = view.body
    }

    @Test("Flat init với id closure — item chưa Identifiable")
    func flatInitWithIDClosure() {
        let view = BasicListView(items: ["alpha", "beta"], id: { $0 }, config: config) {
            Text($0)
        }
        .basicListHeader { Text("Header") }
        .onRowTap { _ in }
        _ = view.body
    }

    @Test("Sectioned init — nhóm có footer lẫn không footer cùng dựng được")
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

    @Test("Sectioned init nhận AnyHashable nào — section là Int cũng chạy")
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
}
