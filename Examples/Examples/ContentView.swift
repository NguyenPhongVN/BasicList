import SwiftUI
import BasicList

// MARK: - The hub — the demo catalog, built ON the package itself
//
// The hub list is a `BasicListView` (the engine, dogfooded): rows via
// `onRowTap` → programmatic navigation, not NavigationLink — the same
// "data in, events out" contract the demos teach. Appearance defaults to
// the system; the toolbar toggle overrides it for side-by-side light/dark
// testing, and the choice persists across launches via `@AppStorage`.

/// The three states the toolbar toggle cycles through. Stored as a String
/// in `@AppStorage` because `Optional<ColorScheme>` isn't directly storable.
enum SchemePreference: String {
    case system
    case light
    case dark

    /// `nil` = follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct ContentView: View {
    @State private var path: [DemoKind] = []
    /// Persists across launches; defaults to following the system.
    @AppStorage("schemePreference") private var schemePreference: SchemePreference = .system

    init() {
        // Demo launch routing — `simctl launch ... Examples -datePager`
        // jumps straight to one demo (handy for screenshots and manual
        // testing); no argument → the hub.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-paged") {
            _path = State(initialValue: [.paged])
        } else if arguments.contains("-datePager") {
            _path = State(initialValue: [.datePager])
        } else if arguments.contains("-flat") {
            _path = State(initialValue: [.flat])
        } else if arguments.contains("-sectioned") {
            _path = State(initialValue: [.sectioned])
        } else if arguments.contains("-empty") {
            _path = State(initialValue: [.empty])
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            BasicListView(items: DemoKind.allCases, config: DemoTheme.list) { entry in
                HubRowView(entry: entry)
            }
            .basicListHeader {
                HubHeaderView()
            }
            .basicListFooter {
                Text("Built with BasicList — every screen here is the package's own API")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .onRowTap { path.append($0) }
            .background(DemoTheme.canvas)
            .navigationTitle("Examples")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // system → light → dark → system
                        switch schemePreference {
                        case .system: schemePreference = .light
                        case .light: schemePreference = .dark
                        case .dark: schemePreference = .system
                        }
                    } label: {
                        switch schemePreference {
                        case .light: Image(systemName: "sun.max.fill")
                        case .dark: Image(systemName: "moon.fill")
                        case .system: Image(systemName: "circle.lefthalf.filled")
                        }
                    }
                    .accessibilityLabel("Appearance")
                }
            }
            .navigationDestination(for: DemoKind.self) { $0.destination }
        }
        .preferredColorScheme(schemePreference.colorScheme)
    }
}

/// The demos the hub offers — each one exercises a layer of the package.
enum DemoKind: String, CaseIterable, Identifiable {
    case flat
    case paged
    case sectioned
    case datePager
    case empty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat: return "Flat page"
        case .paged: return "Refresh & load-more"
        case .sectioned: return "Sectioned page"
        case .datePager: return "Date pager"
        case .empty: return "Empty state"
        }
    }

    var subtitle: String {
        switch self {
        case .flat: return "Search · slots · swipe both edges · footer progress"
        case .paged: return "Slow network · refresh · exhausted state"
        case .sectioned: return "Sticky headers · group footers · swipe"
        case .datePager: return "Previous/next period · slide transition"
        case .empty: return "Default empty state · pull-to-load"
        }
    }

    var symbol: String {
        switch self {
        case .flat: return "list.bullet"
        case .paged: return "arrow.down.circle"
        case .sectioned: return "square.grid.2x2"
        case .datePager: return "calendar"
        case .empty: return "tray"
        }
    }

    var tint: Color {
        switch self {
        case .flat: return .blue
        case .paged: return .indigo
        case .sectioned: return .orange
        case .datePager: return .purple
        case .empty: return .secondary
        }
    }

    @ViewBuilder var destination: some View {
        switch self {
        case .flat: FlatPageDemo()
        case .paged: PagedListDemo()
        case .sectioned: SectionedPageDemo()
        case .datePager: DatePagerPageDemo()
        case .empty: EmptyPageDemo()
        }
    }
}

/// Hub header — what this catalog is, in two lines.
private struct HubHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BasicList Examples")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("Every demo exercises one layer of the package — page scaffold, engine, date pager.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hub row — same render language as the demo rows (glyph + title + note),
/// drawn as a card on the canvas; full-area tap comes from the engine's
/// `onRowTap` + VoiceOver button trait.
private struct HubRowView: View {
    let entry: DemoKind

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(entry.tint)
                .frame(width: 36, height: 36)
                .background(entry.tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(entry.subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(DemoTheme.rowCard, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .basicListRowStyle()
    }
}
