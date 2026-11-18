import SwiftUI
import Testing
@testable import BasicList

// MARK: - BasicList vocabulary — tested on a macOS host (no UI rendering)
//
// The testable parts are pure value/mapping behavior: config, section identity +
// itemID mapping, optional footer, swipe action, spacer, sentinel,
// header mode. Rendering parts (probe geometry, sticky headers, swipe animation)
// belong to the Examples app — host tests can't build a List.

struct BasicListConfigTests {

    @Test("Init stores the values passed in")
    func initStoresValues() {
        let config = BasicListConfig(destructiveActionTint: .red, bottomClearance: 80)
        #expect(config.destructiveActionTint == .red)
        #expect(config.bottomClearance == 80)
    }

    @Test("Equatable — same values are equal, different values differ")
    func equality() {
        let red0 = BasicListConfig(destructiveActionTint: .red, bottomClearance: 0)
        let red1 = BasicListConfig(destructiveActionTint: .red, bottomClearance: 0)
        let blue = BasicListConfig(destructiveActionTint: .blue, bottomClearance: 0)
        #expect(red0 == red1)
        #expect(red0 != blue)
    }
}

struct BasicListSectionTests {

    private struct Item: Equatable, Identifiable { let id: Int }

    @Test("Section identity wraps AnyHashable — any Hashable is accepted")
    func sectionIdentityWrapsAnyHashable() {
        let section = BasicListSection(
            section: "Today", items: [Item(id: 1)], itemID: { $0.id }) {
            Text("H")
        }
        #expect(section.section == AnyHashable("Today"))
    }

    @Test("itemID applies the caller's id closure")
    func itemIDAppliesCallerClosure() {
        let section = BasicListSection(
            section: "day", items: [Item(id: 5)], itemID: { $0.id * 10 }) {
            Text("H")
        }
        #expect(section.itemID(Item(id: 5)) == AnyHashable(50))
    }

    @Test("Items keep their order and values")
    func itemsPassthrough() {
        let items = [Item(id: 3), Item(id: 1), Item(id: 2)]
        let section = BasicListSection(
            section: "day", items: items, itemID: { $0.id }) {
            Text("H")
        }
        #expect(section.items == items)
    }

    @Test("Header stored as a closure — calling it builds an AnyView")
    func headerBuildsAnyView() {
        let section = BasicListSection(
            section: "day", items: [Item(id: 1)], itemID: { $0.id }) {
            Text("Group header")
        }
        _ = section.header()
    }

    @Test("Init without footer → footer nil; init with footer → builds a view")
    func footerOptional() {
        let plain = BasicListSection(
            section: "day", items: [Item(id: 1)], itemID: { $0.id }) {
            Text("H")
        }
        #expect(plain.footer == nil)

        let withFooter = BasicListSection(
            section: "day", items: [Item(id: 1)], itemID: { $0.id }) {
            Text("H")
        } footer: {
            Text("Group footer")
        }
        #expect(withFooter.footer != nil)
        _ = withFooter.footer?()
    }

    @Test("Identifiable convenience — ids map to \\ .id, footer optional")
    func identifiableConvenience() {
        let plain = BasicListSection(section: "day", items: [Item(id: 7)]) {
            Text("H")
        }
        #expect(plain.section == AnyHashable("day"))
        #expect(plain.itemID(Item(id: 7)) == AnyHashable(7), "convenience maps \\ .id")
        #expect(plain.footer == nil)

        let withFooter = BasicListSection(section: "day", items: [Item(id: 7)]) {
            Text("H")
        } footer: {
            Text("F")
        }
        #expect(withFooter.footer != nil)
        _ = withFooter.footer?()
    }
}

struct BasicListSwipeActionTests {

    @Test("isDestructive defaults to false — regular actions keep the system tint")
    func nonDestructiveDefault() {
        let action = BasicListSwipeAction(title: "Pin", systemImage: "pin.fill") {}
        #expect(!action.isDestructive)
    }

    @Test("Role init — .destructive maps to isDestructive, nil keeps the system tint")
    func roleInit() {
        let destructive = BasicListSwipeAction(
            title: "Delete", systemImage: "trash", role: .destructive) {}
        #expect(destructive.isDestructive)
        let plain = BasicListSwipeAction(
            title: "Pin", systemImage: "pin.fill", role: nil) {}
        #expect(!plain.isDestructive)
    }

    @Test("Fields stored correctly; the handler fires as many times as called")
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

    @Test("Default bottom threshold 600pt — single source for probe + sentinel")
    func defaultBottomThreshold() {
        #expect(BasicListScrollSentinel.defaultBottomThreshold == 600)
    }

    @Test("Default load-more mode constant — pixelThreshold of the shared 600pt")
    func defaultLoadMoreMode() {
        #expect(BasicListLoadMoreMode.pixelDefault == .pixelThreshold(600))
    }

    @Test("Header mode has both cases — scrolls with content and pinned to top")
    func headerModeCases() {
        let scrolls: BasicListHeaderMode = .scrollsWithContent
        let pinned: BasicListHeaderMode = .pinnedTop
        if case .scrollsWithContent = scrolls {} else { Issue.record("Missing case .scrollsWithContent") }
        if case .pinnedTop = pinned {} else { Issue.record("Missing case .pinnedTop") }
    }

    @Test("Load-more mode — both cases carry their values, exclusive by type")
    func loadMoreModeCases() {
        #expect(BasicListLoadMoreMode.pixelThreshold(400) == .pixelThreshold(400))
        #expect(BasicListLoadMoreMode.pagesAhead(2) == .pagesAhead(2))
        #expect(BasicListLoadMoreMode.pagesAhead(2) != .pagesAhead(3))
        #expect(BasicListLoadMoreMode.pixelThreshold(400) != .pagesAhead(2))
    }

    @Test("Spacer keeps the height passed in")
    func spacerKeepsHeight() {
        #expect(BasicListSpacer(height: 42).height == 42)
    }
}

@MainActor
struct BasicListLoadGateTests {

    @Test("tryFire inside the cooldown window — second call is blocked")
    func blocksWithinWindow() {
        let gate = BasicListLoadGate(cooldown: 5)
        #expect(gate.tryFire(), "first call must fire")
        #expect(!gate.tryFire(), "second call inside the window must be blocked")
    }

    @Test("tryFire past the cooldown window — fires again")
    func firesAfterWindow() async throws {
        let gate = BasicListLoadGate(cooldown: 0.05)
        #expect(gate.tryFire())
        try await Task.sleep(for: .seconds(0.1))
        #expect(gate.tryFire(), "call past the window must fire")
    }

    @Test("Production default cooldown — 0.4 s (measured duplicate window)")
    func productionDefaultCooldown() {
        #expect(BasicListLoadGate().cooldown == 0.4)
    }
}
