import SwiftUI
import BasicList

// MARK: - The demo row — glyph + title + note + money
//
// Drawn as a CARD floating on the canvas (the grouped-list look); the cell
// applies `.basicListRowStyle()` ITSELF — the engine never re-styles caller
// content. Used by every demo screen.

struct DemoRowView: View {
    let item: DemoItem

    private var tint: Color { item.isIncome ? .green : .orange }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(item.note)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
            }
            Text(demoAmount(item))
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(item.isIncome ? Color.green : Color.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(DemoTheme.rowCard, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .basicListRowStyle()
    }
}
