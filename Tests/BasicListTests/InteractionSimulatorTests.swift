#if os(iOS)
import SwiftUI
import UIKit
import Testing
@testable import BasicList

// MARK: - Interaction simulator tests
//
// The host suite can only assert the WIRING (stored closures, last-call-wins);
// this suite verifies the engine actually ATTACHES the interactions to rows in
// a real List — through the accessibility contract the engine itself documents:
//   - row tap   → `.isButton` trait + default a11y action; activating the
//                 element (VoiceOver double-tap) reports the item
//   - swipe     → named a11y actions per row (VoiceOver has no swipe gesture —
//                 the engine exposes every action via the rotor). The actions
//                 are closure-backed (nil target/selector) and can only be
//                 performed by the real assistive-tech AX server — firing
//                 them from a test process is impossible via public API, so
//                 this suite pins the ROTOR WIRING; the handler-call behavior
//                 is pinned by BasicListSwipeActionTests.
//   - reorder   → drag handles render ONLY when `editMode` is `.active`
//                 (`_UICollectionViewListCellReorderControl`, UIKit-level)
//   - render    → header / empty-state / footer rows match the data shape
//
// The a11y tree only materializes when an assistive client connects — the
// harness forces it by posting `.screenChanged`/`.layoutChanged`
// notifications (what VoiceOver does on focus changes); simulator
// accessibility defaults are NOT required (verified on a fresh simulator).
//
// ⚠️ RUN THIS SUITE SEPARATELY from LoadMoreSimulatorTests (CI does — two
// sequential xcodebuild invocations). Both suites are @MainActor with
// blocking RunLoop pumps; swift-testing serializes WITHIN each suite only,
// so running them in ONE invocation interleaves their measurement windows
// and perturbs the load-more timing assertions (CI run #11 failure).
//
// Same harness discipline as LoadMoreSimulatorTests (§6 of the verification
// doc): hosted UIWindow kept STRONG, pump-based settling, @Suite(.serialized).

private struct IRow: Identifiable { let id: Int; let label: String }

@MainActor
private final class TapRecorder {
    var tapped: Int?
}

@MainActor
@Observable
private final class ReorderRecorder {
    var editMode: EditMode = .inactive
}

@MainActor
private struct ReorderHarness: View {
    let recorder: ReorderRecorder
    let config: BasicListConfig

    var body: some View {
        BasicListView(items: [IRow(id: 1, label: "Row alpha"), IRow(id: 2, label: "Row beta")],
                      config: config) { row in
            Text(row.label)
        }
        .onMoveRows { _, _ in }
        .basicEditMode(Binding(get: { recorder.editMode }, set: { recorder.editMode = $0 }))
    }
}

@MainActor
@Suite(.serialized)
struct InteractionSimulatorTests {

    private let config = BasicListConfig(destructiveActionTint: .red, bottomClearance: 0)

    // MARK: harness helpers

    private func pump(_ seconds: Double = 0.25) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
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

    /// Force the accessibility engine to materialize SwiftUI's a11y tree:
    /// post `.screenChanged` (what VoiceOver does on focus changes) and give
    /// the tree a beat to rebuild. Retried — a cold runner may need several
    /// rounds before the engine connects. Inspection only — no behavior change.
    private func activateA11y() {
        for _ in 0..<3 {
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
            pump(0.4)
        }
    }

    private func a11yElements(in window: UIWindow) -> [NSObject] {
        var found: [NSObject] = []
        func walk(_ node: Any) {
            if let view = node as? UIView {
                if view.isAccessibilityElement { found.append(view) }
                if let elements = view.accessibilityElements {
                    for element in elements { walk(element) }
                }
                for subview in view.subviews { walk(subview) }
            } else if let element = node as? NSObject {
                found.append(element)
            }
        }
        walk(window)
        return found
    }

    /// Every a11y element carrying `label` — the tree mirrors elements at two
    /// depths, so callers assert over all matches (duplicates are harmless).
    private func elements(labeled label: String, in window: UIWindow) -> [NSObject] {
        a11yElements(in: window).filter { $0.accessibilityLabel == label }
    }

    /// Drag handles are UIKit views (`_UICollectionViewListCellReorderControl`),
    /// not a11y elements — matched by class-name substring, stable since the
    /// UICollectionView List era (iOS 14+).
    private func reorderControls(in window: UIWindow) -> [UIView] {
        var found: [UIView] = []
        func walk(_ view: UIView) {
            if String(describing: type(of: view)).contains("ReorderControl") {
                found.append(view)
            }
            for subview in view.subviews { walk(subview) }
        }
        walk(window)
        return found
    }

    // MARK: row tap

    @Test("Row tap — `.isButton` trait present; a11y activation reports the item")
    func tapRow() {
        let recorder = TapRecorder()
        let window = attach(BasicListView(
            items: [IRow(id: 1, label: "Row alpha"), IRow(id: 2, label: "Row beta")],
            config: config
        ) { row in Text(row.label) }
        .onRowTap { recorder.tapped = $0.id })

        activateA11y()

        let alpha = elements(labeled: "Row alpha", in: window)
        #expect(alpha.count >= 1, "row must exist in the a11y tree")
        for element in alpha {
            #expect(element.accessibilityTraits.contains(.button),
                    "a tap-handled row must expose the button trait to VoiceOver")
        }
        for element in elements(labeled: "Row beta", in: window) {
            #expect(element.accessibilityTraits.contains(.button),
                    "every row carries the tap handler (whole-list modifier)")
        }

        if let element = alpha.first {
            let activated = element.accessibilityActivate()
            pump(0.25)
            #expect(activated, "default a11y action (VoiceOver double-tap) must connect")
            #expect(recorder.tapped == 1,
                    "activation must report the tapped item, got \(String(describing: recorder.tapped))")
        }
    }

    // MARK: swipe actions

    @Test("Swipe actions — named a11y actions exist per row (rotor contract)")
    func swipeActions() {
        let window = attach(BasicListView(
            items: [IRow(id: 1, label: "Row alpha")],
            config: config
        ) { row in Text(row.label) }
        .rowSwipeActions { row in
            [BasicListSwipeAction(title: "Delete \(row.id)", systemImage: "trash", role: .destructive) {},
             BasicListSwipeAction(title: "Pin \(row.id)", systemImage: "pin") {}]
        })

        activateA11y()

        let rows = elements(labeled: "Row alpha", in: window)
        #expect(rows.count >= 1)
        // Without an `.onRowTap` handler the row must NOT be a button.
        for element in rows {
            #expect(!element.accessibilityTraits.contains(.button),
                    "no tap handler → no button trait")
        }
        // Every row exposes BOTH actions through the rotor (VoiceOver has no
        // swipe gesture — the engine's documented a11y contract).
        for element in rows {
            let names = (element.accessibilityCustomActions ?? []).map(\.name)
            #expect(names.contains("Delete 1"), "destructive action must be rotor-activatable, got \(names)")
            #expect(names.contains("Pin 1"), "regular action must be rotor-activatable, got \(names)")
        }
    }

    // MARK: reorder

    @Test("Reorder — drag handles render only in `.active` editMode")
    func reorder() {
        let recorder = ReorderRecorder()
        let window = attach(ReorderHarness(recorder: recorder, config: config))

        activateA11y()

        // `.inactive` — no drag handle, no move actions in the a11y tree.
        #expect(reorderControls(in: window).isEmpty,
                "inactive editMode must not render drag handles")
        for element in elements(labeled: "Row alpha", in: window) {
            let names = (element.accessibilityCustomActions ?? []).map(\.name)
            #expect(!names.contains("Move Up") && !names.contains("Move Down"),
                    "inactive editMode must not expose move actions, got \(names)")
        }

        // `.active` — the drag handle renders (the documented "handle only
        // appears when `editMode` is `.active`" contract). The move gesture
        // itself is UIKit-drag-driven; the handler wiring is pinned by the
        // host suite's chain tests.
        recorder.editMode = .active
        pump(0.5)
        activateA11y()

        #expect(!reorderControls(in: window).isEmpty,
                "active editMode must render drag handles")
    }

    // MARK: render presence

    @Test("Render — header/empty-state/footer presence matches the data shape")
    func renderPresence() {
        // Empty list: header + empty-state + footer, and NO row content.
        let emptyWindow = attach(BasicListView(items: [IRow](), config: config) { row in
            Text("row \(row.id)") // never rendered
        }
        .basicListHeader { Text("Demo header") }
        .basicListEmptyState { Text("Nothing here yet") }
        .basicListFooter { Text("Demo footer") })

        activateA11y()

        #expect(!elements(labeled: "Demo header", in: emptyWindow).isEmpty, "header must render")
        #expect(!elements(labeled: "Nothing here yet", in: emptyWindow).isEmpty, "empty-state must render")
        #expect(!elements(labeled: "Demo footer", in: emptyWindow).isEmpty, "footer must render")
        #expect(elements(labeled: "row 1", in: emptyWindow).isEmpty, "row content must NOT render")

        // Loaded list: header + rows + footer, and NO empty-state.
        let loadedWindow = attach(BasicListView(
            items: [IRow(id: 1, label: "row 1"), IRow(id: 2, label: "row 2")],
            config: config
        ) { row in Text(row.label) }
        .basicListHeader { Text("Demo header") }
        .basicListEmptyState { Text("Nothing here yet") }
        .basicListFooter { Text("Demo footer") })

        activateA11y()

        #expect(!elements(labeled: "Demo header", in: loadedWindow).isEmpty)
        #expect(!elements(labeled: "row 1", in: loadedWindow).isEmpty)
        #expect(!elements(labeled: "row 2", in: loadedWindow).isEmpty)
        #expect(!elements(labeled: "Demo footer", in: loadedWindow).isEmpty)
        #expect(elements(labeled: "Nothing here yet", in: loadedWindow).isEmpty,
                "empty-state must not render once the list has data")
    }
}
#endif
