import SwiftUI
import Testing
@testable import BasicList

// MARK: - Vocabulary của BasicList — test trên macOS host (không render UI)
//
// Phần test được là giá trị/mapping thuần: config, section identity +
// itemID mapping, footer tuỳ chọn, swipe action, spacer, sentinel,
// header mode. Phần render (probe geometry, sticky header, swipe animation)
// thuộc preview — host test không dựng được List.

struct BasicListConfigTests {

    @Test("Init lưu đúng giá trị truyền vào")
    func initStoresValues() {
        let config = BasicListConfig(destructiveActionTint: .red, bottomClearance: 80)
        #expect(config.destructiveActionTint == .red)
        #expect(config.bottomClearance == 80)
    }

    @Test("Equatable — cùng giá trị bằng nhau, khác giá trị khác nhau")
    func equality() {
        let a = BasicListConfig(destructiveActionTint: .red, bottomClearance: 0)
        let b = BasicListConfig(destructiveActionTint: .red, bottomClearance: 0)
        let c = BasicListConfig(destructiveActionTint: .blue, bottomClearance: 0)
        #expect(a == b)
        #expect(a != c)
    }
}

struct BasicListSectionTests {

    private struct Item: Equatable { let id: Int }

    @Test("Section identity bọc AnyHashable — Hashable nào cũng nhận được")
    func sectionIdentityWrapsAnyHashable() {
        let section = BasicListSection(
            section: "Today", items: [Item(id: 1)], itemID: { AnyHashable($0.id) }) {
            Text("H")
        }
        #expect(section.section == AnyHashable("Today"))
    }

    @Test("itemID áp đúng closure id của caller")
    func itemIDAppliesCallerClosure() {
        let section = BasicListSection(
            section: "day", items: [Item(id: 5)], itemID: { AnyHashable($0.id * 10) }) {
            Text("H")
        }
        #expect(section.itemID(Item(id: 5)) == AnyHashable(50))
    }

    @Test("items giữ nguyên thứ tự và giá trị")
    func itemsPassthrough() {
        let items = [Item(id: 3), Item(id: 1), Item(id: 2)]
        let section = BasicListSection(
            section: "day", items: items, itemID: { AnyHashable($0.id) }) {
            Text("H")
        }
        #expect(section.items == items)
    }

    @Test("Header lưu closure — gọi dựng được AnyView")
    func headerBuildsAnyView() {
        let section = BasicListSection(
            section: "day", items: [Item(id: 1)], itemID: { AnyHashable($0.id) }) {
            Text("Header của nhóm")
        }
        _ = section.header()
    }

    @Test("Init không footer → footer nil; init có footer → dựng được view")
    func footerOptional() {
        let plain = BasicListSection(
            section: "day", items: [Item(id: 1)], itemID: { AnyHashable($0.id) }) {
            Text("H")
        }
        #expect(plain.footer == nil)

        let withFooter = BasicListSection(
            section: "day", items: [Item(id: 1)], itemID: { AnyHashable($0.id) }) {
            Text("H")
        } footer: {
            Text("Footer của nhóm")
        }
        #expect(withFooter.footer != nil)
        _ = withFooter.footer?()
    }
}

struct BasicListSwipeActionTests {

    @Test("isDestructive mặc định false — action thường giữ tint hệ thống")
    func nonDestructiveDefault() {
        let action = BasicListSwipeAction(title: "Pin", systemImage: "pin.fill") {}
        #expect(!action.isDestructive)
    }

    @Test("Fields lưu đúng; handler gọi được bao nhiêu lần tuỳ ý")
    func fieldsAndHandler() {
        var called = 0
        let action = BasicListSwipeAction(
            title: "Delete", systemImage: "trash", isDestructive: true) { called += 1 }
        #expect(action.title == "Delete")
        #expect(action.systemImage == "trash")
        #expect(action.isDestructive)
        action.handler()
        action.handler()
        #expect(called == 2)
    }
}

struct VocabularyTests {

    @Test("Ngưỡng đáy mặc định 600pt — nguồn duy nhất cho probe + sentinel")
    func defaultBottomThreshold() {
        #expect(BasicListScrollSentinel.defaultBottomThreshold == 600)
    }

    @Test("Header mode đủ 2 case — cuộn cùng nội dung và ghim đỉnh")
    func headerModeCases() {
        let scrolls: BasicListHeaderMode = .scrollsWithContent
        let pinned: BasicListHeaderMode = .pinnedTop
        if case .scrollsWithContent = scrolls {} else { Issue.record("Thiếu case .scrollsWithContent") }
        if case .pinnedTop = pinned {} else { Issue.record("Thiếu case .pinnedTop") }
    }

    @Test("Spacer giữ height đã truyền")
    func spacerKeepsHeight() {
        #expect(BasicListSpacer(height: 42).height == 42)
    }

    @Test("EdgeInsets.zero shim trùng EdgeInsets rỗng — đối trọng của basicListRowStyle()")
    func edgeInsetsZeroShim() {
        #expect(EdgeInsets.zero == EdgeInsets())
    }
}
