#if os(iOS)
import SwiftUI
import UIKit
import Testing
@testable import BasicList

// MARK: - Load-more simulator tests (Docs/LoadMoreVerification.md §5)
//
// Runs ONLY on an iOS simulator host (`xcodebuild test -destination
// 'platform=iOS Simulator,...'`). On macOS (`swift test`) this file compiles
// empty. Scenarios mirror the measured baseline B1–B8 in the verification
// doc; assertions pin the post-fix acceptance criteria:
//   - trigger exactly at the configured threshold (no inset bias)
//   - ONE load per region entry (engine gate collapses duplicates)
//   - attach: short list fires once, loads one page
//   - exhausted/idle stop cleanly — no infinite loop

@MainActor
final class GateVM: @unchecked Sendable {
    let t0 = Date()
    var events: [String] = []
    var page = 1
    var lastPage = Int.max
    var appended: [Int] = []
    var fires = 0

    func log(_ text: String) {
        events.append(String(format: "[%.3f|%.3f] %@", Date().timeIntervalSince(t0),
                             Date().timeIntervalSince1970, text))
    }
    func dump(_ tag: String) {
        print("LMTEST >>> \(tag): fires=\(fires) loads=\(appended.count) page=\(page) appended=\(appended)")
        for e in events { print("LMEV >>> \(e)") }
    }
}

private struct LRow: Identifiable { let id: Int; var label: String }

private struct LoadMoreHarness: View {
    let vm: GateVM
    let rowsPerPage: Int
    let mode: BasicListLoadMoreMode
    let bottomInset: CGFloat
    @State private var items: [LRow]

    init(vm: GateVM, initialRows: Int, rowsPerPage: Int,
         mode: BasicListLoadMoreMode, bottomInset: CGFloat = 0) {
        self.vm = vm
        self.rowsPerPage = rowsPerPage
        self.mode = mode
        self.bottomInset = bottomInset
        _items = State(initialValue: (1...initialRows).map { LRow(id: $0, label: "p1r\($0)") })
    }

    var body: some View {
        BasicListView(
            items: items,
            config: BasicListConfig(destructiveActionTint: .red, bottomClearance: 0)
        ) { row in
            Text(row.label).frame(height: 60)
        }
        .onLoadMore(mode: mode) {
            vm.fires += 1
            vm.log("FIRE #\(vm.fires) (page=\(vm.page))")
            if vm.page < vm.lastPage {
                let next = vm.page + 1
                vm.appended.append(next)
                vm.page = next
                items += (1...rowsPerPage).map {
                    LRow(id: (next - 1) * rowsPerPage + $0, label: "p\(next)r\($0)")
                }
                vm.log("  LOAD page \(next)")
            } else {
                vm.log("  no-op exhausted")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if bottomInset > 0 { Color.clear.frame(height: bottomInset) }
        }
        .onScrollGeometryChange(for: String.self) { geo in
            "GEO size=\(geo.contentSize.height) container=\(geo.containerSize.height) "
                + "top=\(geo.contentInsets.top) bottom=\(geo.contentInsets.bottom) "
                + "offY=\(geo.contentOffset.y) visMaxY=\(geo.visibleRect.maxY)"
        } action: { _, line in
            vm.log(line)
        }
    }
}

@Suite(.serialized)
@MainActor
struct LoadMoreSimulatorTests {

    // MARK: harness helpers

    private func pump(_ seconds: Double = 0.25) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    private func settle(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
    private func drain(_ times: Int = 3) async throws {
        for _ in 0..<times {
            pump(0.2)
            try await settle(0.05)
        }
    }
    private func attach(_ view: some View) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        pump(1.0)
        pump(0.5)
        UIView.setAnimationsEnabled(false)
        return window
    }
    private func findScroll(in window: UIWindow?) -> UIScrollView? {
        func find(_ v: UIView) -> UIScrollView? {
            if let s = v as? UIScrollView { return s }
            for c in v.subviews { if let f = find(c) { return f } }
            return nil
        }
        return window.flatMap(find)
    }
    private func truth(_ s: UIScrollView) -> String {
        let rem = s.contentSize.height - s.contentOffset.y - s.bounds.height
        return String(format: "UK size=%.0f bounds=%.0f offY=%.0f adjTop=%.0f adjBottom=%.0f remUK=%.0f",
                      s.contentSize.height, s.bounds.height, s.contentOffset.y,
                      s.adjustedContentInset.top, s.adjustedContentInset.bottom, rem)
    }
    private func scrollTo(remUK target: CGFloat, _ s: UIScrollView) {
        let y = s.contentSize.height - s.bounds.height - target
        s.setContentOffset(CGPoint(x: 0, y: y), animated: false)
    }
    private func step(_ window: UIWindow, rem target: CGFloat) async throws {
        scrollTo(remUK: target, findScroll(in: window)!)
        pump(0.25)
        try await settle(0.05)
        pump(0.25)
        try await settle(0.05)
    }

    /// The gate guarantee: no two fires closer than the cooldown window —
    /// duplicate sources (transition + estimate steps + sentinel, measured
    /// 1–400 ms apart) must be collapsed.
    private func assertNoDuplicateFires(_ vm: GateVM, _ comment: String) {
        let times = vm.events.compactMap { line -> Double? in
            guard line.contains("FIRE #") else { return nil }
            let t = line.dropFirst(1).split(separator: "]").first
            return t.flatMap { Double($0) }
        }
        for (a, b) in zip(times, times.dropFirst()) {
            #expect(b - a >= 0.35,
                    "\(comment): duplicate fire — gap \(b - a)s < cooldown")
        }
    }

    // MARK: scenarios

    @Test("B1 — attach short list: no duplicate fires; chain loads only while in region")
    func b1() async throws {
        let vm = GateVM()
        vm.lastPage = 6
        let window = attach(LoadMoreHarness(vm: vm, initialRows: 6, rowsPerPage: 10,
                                            mode: .pixelThreshold(600)))
        try await drain(4)
        vm.dump("B1 attach-short")
        #expect(vm.fires >= 1, "short list inside the region must fire at attach")
        #expect(vm.appended.first == 2, "first load must be page 2, got \(vm.appended)")
        assertNoDuplicateFires(vm, "B1")
        // 6 rows ≈ 361pt — after page 2 attaches the list is still deep in
        // the region (≈167pt ≤ 600), so the DESIGNED continuous chain loads
        // page 3 and then exits it (≈767 > 600). Anything beyond [2, 3] on a
        // static list would be a duplicate.
        #expect(vm.appended == [2, 3], "got \(vm.appended)")
        let before = vm.fires
        try await drain(3)
        #expect(vm.fires == before, "idle drift fires: \(vm.fires - before)")
    }

    @Test("B3 — attach in-region list (~1.2 screens): fires once")
    func b3() async throws {
        let vm = GateVM()
        vm.lastPage = 6
        let window = attach(LoadMoreHarness(vm: vm, initialRows: 15, rowsPerPage: 10,
                                            mode: .pixelThreshold(600)))
        try await drain(4)
        vm.dump("B3 in-region attach")
        #expect(vm.fires == 1, "expected exactly 1 fire at attach, got \(vm.fires)")
        #expect(vm.appended == [2])
    }

    @Test("B4 — scan pixelThreshold=600: fires exactly at threshold, 1 load/entry, idle quiet")
    func b4() async throws {
        let vm = GateVM()
        vm.lastPage = 30
        let window = attach(LoadMoreHarness(vm: vm, initialRows: 45, rowsPerPage: 10,
                                            mode: .pixelThreshold(600)))
        try await drain(3)
        let s0 = findScroll(in: window)!
        print("LMTEST >>> B4 attach: fires=\(vm.fires) \(truth(s0))")
        #expect(vm.fires == 0, "long list out of region must not fire at attach")
        for target: CGFloat in [1500, 1100, 900, 700, 500, 400, 300, 200, 100, 50, 0] {
            try await step(window, rem: target)
            if target == 50 {
                #expect(vm.fires == 6, "entries 500…50 must be exactly 1 fire each, got \(vm.fires)")
            }
            print("LMTEST >>> B4 target=\(Int(target)) fires=\(vm.fires) loads=\(vm.appended.count) "
                + "page=\(vm.page) \(truth(findScroll(in: window)!))")
        }
        // Let pending retries land (a blocked chain fire retries +0.4 s
        // later), then assert the totals.
        try await drain(4)
        assertNoDuplicateFires(vm, "B4")
        // 7 entries (500…0) + legitimate chain follow-ups while the grown
        // list still sits inside the region.
        #expect(vm.appended == [2, 3, 4, 5, 6, 7, 8, 9],
                "expected 1 load per entry + bottom-chain follow-up, got \(vm.appended)")
        vm.dump("B4 scan")
        let before = vm.fires
        try await drain(4)
        #expect(vm.fires == before, "idle fires after scan: \(vm.fires - before)")
    }

    @Test("B8 — pagesAhead=2 + inset 83: no fire outside the region, correct crossing")
    func b8() async throws {
        let vm = GateVM()
        vm.lastPage = 30
        let window = attach(LoadMoreHarness(vm: vm, initialRows: 45, rowsPerPage: 10,
                                            mode: .pagesAhead(2), bottomInset: 83))
        try await drain(3)
        print("LMTEST >>> B8 attach: fires=\(vm.fires) \(truth(findScroll(in: window)!))")
        // Region = 2 × containerSize (844) = 1688 → no fire at remUK 2200/1900/1700.
        for target: CGFloat in [2200, 1900, 1700] {
            try await step(window, rem: target)
            #expect(vm.fires == 0, "fired outside the pagesAhead region at remUK \(Int(target))")
        }
        for target: CGFloat in [1500, 1300, 1100, 900, 700, 500, 300, 0] {
            try await step(window, rem: target)
            print("LMTEST >>> B8 target=\(Int(target)) fires=\(vm.fires) loads=\(vm.appended.count) "
                + "\(truth(findScroll(in: window)!))")
        }
        assertNoDuplicateFires(vm, "B8")
        #expect(vm.appended.count >= 8, "expected ≥1 load per in-region entry, got \(vm.appended)")
        // The region (1688) still contains the bottom state — step OUT of it
        // before asserting idleness, otherwise the designed continuous chain
        // keeps filling the region (correct behavior, not a leak).
        try await step(window, rem: 2200)
        let before = vm.fires
        try await drain(4)
        #expect(vm.fires == before, "idle fires after leaving the region: \(vm.fires - before)")
        vm.dump("B8 pagesAhead")
    }

    @Test("B7 — exhausted: loads exactly the remaining pages, then silence")
    func b7() async throws {
        let vm = GateVM()
        vm.lastPage = 6
        let window = attach(LoadMoreHarness(vm: vm, initialRows: 45, rowsPerPage: 10,
                                            mode: .pixelThreshold(600)))
        try await drain(3)
        for target: CGFloat in [900, 500, 100, 0] {
            try await step(window, rem: target)
        }
        try await drain(3)
        assertNoDuplicateFires(vm, "B7")
        // The last page loads by RE-ENTERING the region: a page attach grows
        // contentSize (rows + List estimate drift, measured +1086pt), which
        // can push the stationary user OUT of the region — the designed
        // semantics ("load until farther than the region") stop the chain,
        // and the next scroll delivers the remaining page.
        for _ in 0..<3 {
            try await step(window, rem: 0)
            if vm.appended.count >= 5 { break }
        }
        try await drain(3)
        #expect(vm.appended == [2, 3, 4, 5, 6], "got \(vm.appended)")
        let before = vm.fires
        try await drain(6)
        #expect(vm.fires == before, "fires after exhaustion: \(vm.fires - before)")
        vm.dump("B7 exhausted")
    }

    @Test("Fix A — engine distance equals UIKit ground truth at the true bottom")
    func fixA() async throws {
        let vm = GateVM()
        vm.lastPage = 30
        let window = attach(LoadMoreHarness(vm: vm, initialRows: 45, rowsPerPage: 10,
                                            mode: .pixelThreshold(600)))
        try await drain(3)
        let scroll = findScroll(in: window)!
        let maxY = scroll.contentSize.height - scroll.bounds.height
            + scroll.adjustedContentInset.bottom
        scroll.setContentOffset(CGPoint(x: 0, y: maxY), animated: false)
        pump(0.5)
        let remUK = scroll.contentSize.height - scroll.contentOffset.y - scroll.bounds.height
        // Parse the last GEO line's visMaxY — engine distance = size − visMaxY.
        guard let last = vm.events.last(where: { $0.contains("visMaxY=") }) else {
            Issue.record("no GEO line recorded")
            return
        }
        let parts = last.split(separator: " ").reduce(into: [String: Double]()) { acc, pair in
            let kv = pair.split(separator: "=")
            if kv.count == 2, let v = Double(kv[1]) { acc[String(kv[0])] = v }
        }
        let size = parts["size"] ?? -1
        let visMaxY = parts["visMaxY"] ?? -1
        let engineDistance = size - visMaxY
        print("LMTEST >>> FixA remUK=\(remUK) engineDistance=\(engineDistance) "
            + "adjBottom=\(scroll.adjustedContentInset.bottom)")
        #expect(abs(engineDistance - remUK) < 2,
                "engine distance \(engineDistance) diverges from UIKit ground truth \(remUK)")
    }
}
#endif
