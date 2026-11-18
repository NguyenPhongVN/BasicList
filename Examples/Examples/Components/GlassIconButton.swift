import SwiftUI

// MARK: - GlassIconButton — the demo app's trailing-slot button
//
// The HIG-compliant round action: Liquid Glass visual (36pt), 44pt hit
// floor, light haptic on tap, accessibility label required by the caller.

struct GlassIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .semibold))
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
