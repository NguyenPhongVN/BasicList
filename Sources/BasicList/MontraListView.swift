import SwiftUI

// MARK: - MontraListView — engine "array vào — item ra"
//
// Một view cho cả hai hình: flat (`items:`) và sectioned với sticky
// header từng nhóm (`sections:`). Kèm header 2 mode, empty-state, footer,
// swipe actions, row tap, refresh, load-more liên tục, reorder flat list
// (onMove + editMode). Nền là `MontraPlainList` — list .plain trần house.
//
// MÀU/THÔNG SỐ: truyền vào qua `MontraListConfig` — engine thuần
// SwiftUI, không đọc design layer. Cách chọn view, config, cơ chế
// load-more và rule bắt buộc — xem README.md của module.

/// Base "array vào — item ra" cho house list.
///
/// Ba nguyên tắc của engine:
/// - **Data in, events out** — swipe/tap/move/refresh/load-more đều là
///   closure caller truyền vào; engine không giữ state nghiệp vụ nào,
///   nguồn dữ liệu duy nhất là mảng/sections đưa vào.
/// - **Immutable, modifier trả `Self`** — chain thoải mái, không có
///   state ẩn đổi theo thứ tự gọi modifier.
/// - **Design đi qua config** — không màu/thông số hardcode trong module;
///   thiếu config là lỗi compile.
///
/// ```swift
/// MontraListView(items: accounts, config: .house) { account in
///     AccountRowView(account)
/// }
/// .montraListHeader { AccountBalanceHeader() }
/// .onRefresh { try await api.reload() }
/// .onLoadMore { try await api.nextPage() }
/// .rowSwipeActions { account in deleteActions(for: account) }
///
/// MontraListView(sections: dayGroups, config: .house) { transaction in
///     TransactionRowView(transaction)
/// }
/// ```
public struct MontraListView<Item, Content: View>: View {

    private struct Row: Identifiable {
        let item: Item
        let id: AnyHashable
    }

    /// Section nội bộ: flat là một nhóm duy nhất với header rỗng.
    private struct Group: Identifiable {
        let section: AnyHashable
        let header: () -> AnyView
        let rows: [Row]
        var id: AnyHashable { section }
    }

    private let isSectioned: Bool
    private let groups: [Group]
    private let rows: [Row]
    private let content: (Item) -> Content
    /// Màu/thông số truyền vào từ caller (xem `MontraListConfig`) — engine
    /// không tự đọc giá trị design.
    private let config: MontraListConfig
    private var headerBuilder: (() -> AnyView)?
    private var headerMode: MontraListHeaderMode = .scrollsWithContent
    private var emptyStateBuilder: (() -> AnyView)?
    private var footerBuilder: (() -> AnyView)?
    private var rowSwipeHandler: ((Item) -> [MontraListSwipeAction])?
    private var rowTapHandler: ((Item) -> Void)?
    private var onMoveHandler: ((IndexSet, Int) -> Void)?
    #if os(iOS)
    private var editModeBinding: Binding<EditMode>?
    #endif
    private var onRefreshHandler: (() async throws -> Void)?
    private var onLoadMoreHandler: (() async -> Void)?
    private var bottomThreshold = MontraListScrollSentinel.defaultBottomThreshold

    /// Item tự `Identifiable`.
    public init(
        items: [Item],
        config: MontraListConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) where Item: Identifiable {
        self.isSectioned = false
        self.groups = []
        self.rows = items.map { Row(item: $0, id: $0.id) }
        self.content = content
        self.config = config
    }

    /// Item chưa `Identifiable` — dán id qua closure, như `ForEach(id:)`.
    public init(
        items: [Item],
        id: @escaping (Item) -> any Hashable,
        config: MontraListConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.isSectioned = false
        self.groups = []
        self.rows = items.map { Row(item: $0, id: AnyHashable(id($0))) }
        self.content = content
        self.config = config
    }

    /// Danh sách section, mỗi nhóm một sticky header (`section.header`).
    public init(
        sections: [MontraListSection<Item>],
        config: MontraListConfig,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.isSectioned = true
        self.groups = sections.map { section in
            Group(
                section: section.section,
                header: section.header,
                rows: section.items.map { Row(item: $0, id: section.itemID($0)) })
        }
        self.rows = []
        self.content = content
        self.config = config
    }

    // MARK: Modifiers (builder-style, trả Self để chain)

    /// Header đầu list, hai mode:
    /// - `.scrollsWithContent` — lướt cùng nội dung (mặc định).
    /// - `.pinnedTop` — ghim đỉnh, sticky như supplementary view UIKit.
    ///
    /// ⚠️ `.pinnedTop` + sectioned CHƯA KIỂM CHỨNG: header pinned là
    /// Section bao quanh các Section của groups — kết hợp này chưa có
    /// caller nào dùng, tránh cho tới khi cần và đã test.
    public func montraListHeader(
        mode: MontraListHeaderMode = .scrollsWithContent,
        @ViewBuilder _ builder: @escaping () -> some View
    ) -> Self {
        var copy = self
        copy.headerBuilder = { AnyView(builder()) }
        copy.headerMode = mode
        return copy
    }

    /// Nội dung thay thế rows khi list rỗng — hero rỗng chạy TRONG list
    /// (cuộn cùng, list giữ identity giữa hai pha rỗng/có dữ liệu) thay
    /// vì nhánh `if` bên ngoài làm list xuất hiện/biến mất.
    public func montraListEmptyState(@ViewBuilder _ builder: @escaping () -> some View) -> Self {
        var copy = self
        copy.emptyStateBuilder = { AnyView(builder()) }
        return copy
    }

    /// Nội dung đáy list — sau toàn bộ rows (hoặc empty-state), trước
    /// sentinel load-more; suggestion Categories chạy đây để cuộn cùng
    /// nội dung như một section thật của list.
    public func montraListFooter(@ViewBuilder _ builder: @escaping () -> some View) -> Self {
        var copy = self
        copy.footerBuilder = { AnyView(builder()) }
        return copy
    }

    /// Swipe actions trên từng dòng — data in, events out: handler trả
    /// danh sách action của mỗi item, list vẽ nút và hồi báo handler.
    public func rowSwipeActions(_ handler: @escaping (Item) -> [MontraListSwipeAction]) -> Self {
        var copy = self
        copy.rowSwipeHandler = handler
        return copy
    }

    /// Tap vào dòng — data in, events out như swipe actions: truyền
    /// handler thì row nhận tap toàn vùng (contentShape) và hồi báo
    /// item; không truyền thì row nguyên trạng. Tap không chiếm cử chỉ
    /// kéo ngang của swipe actions nên hai modifier dùng chung được.
    public func onRowTap(_ handler: @escaping (Item) -> Void) -> Self {
        var copy = self
        copy.rowTapHandler = handler
        return copy
    }

    /// Kéo-thả sắp xếp lại các dòng (flat list) — data in, events out:
    /// screen truyền handler, List hồi báo source/destination khi user
    /// kéo handle. Handle chỉ xuất hiện khi `editMode` đang `.active`
    /// (screen điều khiển qua `montraEditMode`); không truyền handler
    /// thì list nguyên trạng. Chỉ áp cho hình flat — sectioned chưa hỗ
    /// trợ reorder.
    public func onMoveRows(_ handler: @escaping (IndexSet, Int) -> Void) -> Self {
        var copy = self
        copy.onMoveHandler = handler
        return copy
    }

    #if os(iOS)
    /// Ghim `editMode` của List theo binding của screen — `.active` hiện
    /// drag handle của `onMoveRows`, `.inactive` trả list về tương tác
    /// thường. Không truyền (mặc định) là list nguyên trạng. iOS-only:
    /// `EditMode` unavailable trên macOS.
    public func montraEditMode(_ binding: Binding<EditMode>?) -> Self {
        var copy = self
        copy.editModeBinding = binding
        return copy
    }
    #endif

    /// Pull-to-refresh. Lỗi của handler KHÔNG ném lên SwiftUI — closure
    /// được gọi trong `refreshable` và spinner tự kết thúc bất kể kết quả
    /// (`try?` nuốt error): muốn trình bày lỗi thì tự xử lý ngay trong
    /// handler (alert/state của screen gọi).
    public func onRefresh(_ handler: @escaping () async throws -> Void) -> Self {
        var copy = self
        copy.onRefreshHandler = handler
        return copy
    }

    /// Load-more liên tục — cơ chế xem doc `.montraListBottomProbe` +
    /// `MontraListScrollSentinel` (probe trên thân List, sentinel bù fire
    /// list ngắn, chặn lặp nằm phía VM). `pixelThreshold` đổi ngưỡng vào
    /// vùng đáy (mặc định 600pt).
    public func onLoadMore(
        _ handler: @escaping () async -> Void,
        pixelThreshold: CGFloat = MontraListScrollSentinel.defaultBottomThreshold
    ) -> Self {
        var copy = self
        copy.onLoadMoreHandler = handler
        copy.bottomThreshold = pixelThreshold
        return copy
    }

    // MARK: Body

    public var body: some View {
        MontraPlainList(config: config) {
            if let headerBuilder, headerMode == .pinnedTop {
                Section {
                    rowsList
                } header: {
                    headerBuilder().montraListRowStyle()
                }
            } else {
                if let headerBuilder {
                    headerBuilder().montraListRowStyle()
                }
                rowsList
            }
            if let footerBuilder {
                footerBuilder().montraListRowStyle()
            }
            if let onLoadMoreHandler {
                MontraListScrollSentinel(onLoadMore: onLoadMoreHandler)
            }
        }
        .montraListRefreshable(onRefreshHandler)
        .montraListBottomProbe(
            bottomThreshold: bottomThreshold,
            onLoadMoreHandler)
        #if os(iOS)
        .montraListEditMode(editModeBinding)
        #endif
    }

    @ViewBuilder
    private var rowsList: some View {
        // Độ "rỗng" phải tính theo ĐÚNG hình đang dùng: list sectioned
        // giữ data trong `groups` (`rows` luôn rỗng) — kiểm `rows.isEmpty`
        // với sectioned có data sẽ nhầm là rỗng và hiện empty state.
        if isEmpty, let emptyStateBuilder {
            emptyStateBuilder().montraListRowStyle()
        } else if isSectioned {
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { rowView(_: $0) }
                } header: {
                    group.header().montraListRowStyle()
                }
            }
        } else if let onMoveHandler {
            // Flat + reorder: `.onMove` trên chính ForEach dữ liệu —
            // drag handle xuất hiện khi `editMode` `.active`, move hồi
            // báo handler (store tự lo local move + persist).
            ForEach(rows) { rowView(_: $0) }
                .onMove(perform: onMoveHandler)
        } else {
            ForEach(rows) { rowView(_: $0) }
        }
    }

    /// List không còn item nào để hiển thị — theo hình đang dùng.
    private var isEmpty: Bool {
        isSectioned ? groups.allSatisfy(\.rows.isEmpty) : rows.isEmpty
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        if let rowTapHandler {
            baseRow(row)
                // Hit area toàn chiều rộng row — cell chỉ phủ phần nội
                // dung, tap vào vùng đệm cũng phải tính.
                .contentShape(Rectangle())
                .onTapGesture { rowTapHandler(row.item) }
                // VoiceOver: row có hành động kích hoạt → phải là "nút"
                // và kích hoạt được bằng action mặc định (rotor/tap đôi),
                // không chỉ cử chỉ tap thường.
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { rowTapHandler(row.item) }
        } else {
            baseRow(row)
        }
    }

    private func baseRow(_ row: Row) -> some View {
        content(row.item)
            .montraListRowStyle()
            .montraRowSwipeActions(
                rowSwipeHandler?(row.item),
                destructiveTint: config.destructiveActionTint)
    }
}

// MARK: - Private internals (chỉ engine dùng — private extension cùng file)

private extension View {
    /// Refresh chỉ khi có handler — không thì giữ list nguyên trạng; lỗi
    /// nuộc trong chính refreshable (pull spinner tự kết thúc).
    @ViewBuilder
    func montraListRefreshable(_ handler: (() async throws -> Void)?) -> some View {
        if let handler {
            refreshable { try? await handler() }
        } else {
            self
        }
    }

    #if os(iOS)
    /// Ghim `editMode` của List chỉ khi có binding — list không reorder
    /// giữ nguyên trạng thái environment.
    @ViewBuilder
    func montraListEditMode(_ binding: Binding<EditMode>?) -> some View {
        if let binding {
            self.environment(\.editMode, binding)
        } else {
            self
        }
    }
    #endif

    /// Nếu handler trả actions, gắn swipe tại row; không thì giữ row nguyên.
    /// `allowsFullSwipe: true` — full swipe nổ handler ngay, nhưng handler chỉ
    /// là hand-off confirm-riêng (popup). KHÔNG dùng `role: .destructive`:
    /// destructive-role + full swipe kích hoạt animation trượt row đi (SwiftUI
    /// coi row đã bị xoá) — không render lại thì row mất luôn dù data nguyên.
    /// Look đỏ giữ bằng `.tint` trên Button — màu từ `MontraListConfig`
    /// truyền xuống (`destructiveTint`), engine không tự đọc token design.
    /// Mỗi action còn expose `.accessibilityAction(named:)`: cử chỉ swipe
    /// không tồn tại với VoiceOver, actions phải kích hoạt được từ rotor.
    @ViewBuilder
    func montraRowSwipeActions(
        _ actions: [MontraListSwipeAction]?,
        destructiveTint: Color
    ) -> some View {
        if let actions, !actions.isEmpty {
            self.swipeActions(edge: .trailing, allowsFullSwipe: true) {
                // Id theo vị trí: hai action trùng title vẫn là hai nút
                // riêng (id \.title sẽ đụng nhau → ForEach undefined).
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button {
                        action.handler()
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    // Chỉ destructive nhận tint theo config — action thường
                    // giữ tint mặc định của hệ thống như bản gốc. KHÔNG
                    // dùng role .destructive (xem doc phía trên).
                    .tint(action.isDestructive ? destructiveTint : nil)
                }
            }
            .accessibilityActions {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.title) { action.handler() }
                }
            }
        } else {
            self
        }
    }

    /// Probe đáy gắn TRÊN THÂN List (`onScrollGeometryChange` quan sát
    /// scroll view tại điểm gắn): observer sống trọn vòng đời list và
    /// nhận mọi thay đổi geometry từ lúc list xuất hiện — đây là điểm
    /// khác biệt với cơ chế cũ gắn probe lên row sentinel, mà List lazy
    /// chỉ materialize row đó khi user đã cuộn sát đáy, nên observer
    /// không tồn tại trong suốt hành trình cuộn và ngưỡng threshold
    /// thành vô nghĩa (load-more chỉ nổ khi cell cuối hiện ra).
    ///
    /// Fire theo CHUYỂN TRẠNG THÁI, không fan theo tick cuộn: (1) đi
    /// vào vùng đáy — ngoài ngưỡng → trong ngưỡng; (2) trang mới đính
    /// vào (`contentHeight` đổi) mà vẫn trong vùng — nạp tiếp cho tới
    /// khi ra khỏi vùng hoặc hết trang. Lượt trang đầu list ngắn — chưa
    /// đủ đầy màn thì không có phép đổi geometry nào sau lúc gắn — do
    /// `MontraListScrollSentinel` bù bằng `onAppear`. Lượt fire trùng
    /// (probe + sentinel cùng nổ) nằm phía VM: `Paging.inFlight` chặn
    /// song song, `exhausted` bỏ qua khi hết trang — probe không giữ
    /// state, action vô trạng thái (old/new từ chính modifier).
    @ViewBuilder
    func montraListBottomProbe(
        bottomThreshold: CGFloat,
        _ handler: (() async -> Void)?
    ) -> some View {
        if let handler {
            onScrollGeometryChange(for: MontraListBottomProbe.self) { geometry in
                MontraListBottomProbe(
                    distanceFromBottom: geometry.contentSize.height
                        - geometry.contentInsets.bottom
                        - (geometry.contentOffset.y + geometry.containerSize.height),
                    contentHeight: geometry.contentSize.height)
            } action: { old, new in
                let isNearBottom = new.distanceFromBottom <= bottomThreshold
                let wasNearBottom = old.distanceFromBottom <= bottomThreshold
                guard isNearBottom,
                      !wasNearBottom || new.contentHeight != old.contentHeight
                else { return }
                Task { await handler() }
            }
        } else {
            self
        }
    }
}

/// Probe đáy của load-more — giá trị biến đổi theo scroll geometry để
/// so sánh "đã tới vùng đáy". `contentHeight` nằm trong probe để trang
/// mới đính vào (list cao thêm) là một PHÉP ĐỔI riêng, dù khoảng cách
/// đáy tình cờ giữ nguyên.
private struct MontraListBottomProbe: Equatable {
    let distanceFromBottom: CGFloat
    let contentHeight: CGFloat
}

// MARK: - Preview
//
// Demo sống của engine — 6 hình: flat (swipe/tap/load-more/empty-state),
// sectioned (sticky header), ít dòng, phân trang + refresh, refresh chậm,
// refresh lỗi tự xử lý. Data là fixture giao dịch tiếng Anh qua
// `PreviewRow` (glyph tròn + tiêu đề + phụ đề + tiền) cho mỗi hình có
// diện mạo riêng, không qua bảng Localizable của app. Config neutral
// (giá trị design thật do caller truyền — app truyền qua
// `MontraListConfig.house`).

private let previewConfig = MontraListConfig(
    destructiveActionTint: .red, bottomClearance: 60)

private struct PreviewItem: Identifiable {
    let id = UUID()
    let title: String
    let note: String
    let symbol: String
    let amount: Double
    let isIncome: Bool
}

/// Fixture giao dịch tiếng Anh dùng chung mọi preview — đủ đa dạng
/// glyph/màu/tiền để các hình demo không nhìn như nhau. Chuỗi là fixture
/// của preview, không qua bảng Localizable của app.
private let previewFixtures: [
    (title: String, note: String, symbol: String, amount: Double, isIncome: Bool)
] = [
    ("Whole Foods", "Groceries", "cart.fill", 86.40, false),
    ("Salary", "October payroll", "banknote.fill", 2_400, true),
    ("Uber", "Commute", "car.fill", 14.20, false),
    ("Freelance", "Logo project", "laptopcomputer", 350, true),
    ("Netflix", "Monthly plan", "play.tv.fill", 15.99, false),
    ("Rent", "Apartment", "house.fill", 780, false),
    ("Coffee", "Latte, size M", "cup.and.saucer.fill", 4.50, false),
    ("Dividend", "Quarterly payout", "chart.line.uptrend.xyaxis", 62.30, true),
]

/// Item từ fixture (index 1-based, quay vòng khi vượt) — `note` ép đè
/// khi caller cần nhãn riêng (vd "Loaded round 2").
private func fixtureItem(at index: Int, note: String? = nil) -> PreviewItem {
    let fixture = previewFixtures[(index - 1) % previewFixtures.count]
    return PreviewItem(
        title: fixture.title, note: note ?? fixture.note,
        symbol: fixture.symbol, amount: fixture.amount,
        isIncome: fixture.isIncome)
}

/// Item từ fixture kèm nhãn trang — nhịp load-more hiện ngay trong data.
private func pagedFixtureItem(at index: Int, page: Int) -> PreviewItem {
    fixtureItem(at: index, note: "\(previewFixtures[(index - 1) % previewFixtures.count].note) · page \(page)")
}

/// "+$2,400.00" / "−$86.40" — thu xanh, chi màu thường, chữ số đều nhau
/// (monospaced) để cột tiền thẳng hàng.
private func previewAmount(_ item: PreviewItem) -> String {
    String(format: item.isIncome ? "+$%.2f" : "−$%.2f", item.amount)
}

/// Row demo của preview: glyph tròn màu + tiêu đề + phụ đề + tiền —
/// gần khúc dạo đầu của cell app hơn một `Text` trần.
private struct PreviewRow: View {
    let item: PreviewItem

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
            Text(previewAmount(item))
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(item.isIncome ? Color.green : Color.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .montraListRowStyle()
    }
}

/// Header demo — tiêu đề + phụ đề giải thích kịch bản, thay cho dòng
/// `Text` trần khó phân biệt giữa các preview.
private struct PreviewHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text(subtitle)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Preview dựng qua struct riêng — logic phức tạp (state mutate trong
/// closures) nhồi thẳng vào macro #Preview làm type-checker crash.
private struct FlatListPreview: View {
    @State private var items: [PreviewItem] = (1...12).map { fixtureItem(at: $0) }
    @State private var loadRound = 0

    var body: some View {
        MontraListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .montraListHeader {
                PreviewHeader(
                    title: "Demo list",
                    subtitle: "Swipe left · tap to remove · scroll to bottom to load more")
            }
            .montraListEmptyState {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Nothing here — every row was removed")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(40)
            }
            .rowSwipeActions { _ in
                [MontraListSwipeAction(title: "Delete", systemImage: "trash", isDestructive: true) {}]
            }
            .onRowTap { tapped in
                items.removeAll { $0.id == tapped.id }
            }
            .onLoadMore {
                try? await Task.sleep(for: .seconds(0.3))
                loadRound += 1
                items += (1...6).map { offset in
                    fixtureItem(
                        at: loadRound * 6 + offset,
                        note: "Loaded round \(loadRound)")
                }
            }
            // Nền preview màu neutral — module không thấy modifier design app.
            .background(Color.secondary.opacity(0.12))
    }
}

private struct SectionedListPreview: View {
    /// Header nhóm: nhãn ngày + số giao dịch — sticky khi cuộn (đối
    /// trọng của sectionHeadersPinToVisibleBounds) nên phải tự đủ ngữ
    /// cảnh, không dựa vào nội dung đã cuộn qua.
    private static func sectionHeader(_ label: String, count: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(count) transactions")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    static let sections: [MontraListSection<PreviewItem>] = [
        MontraListSection(section: "Today", items: [
            fixtureItem(at: 7), fixtureItem(at: 3), fixtureItem(at: 1),
        ], itemID: \.id) {
            sectionHeader("TODAY", count: 3)
        },
        MontraListSection(section: "Yesterday", items: [
            fixtureItem(at: 5), fixtureItem(at: 6),
        ], itemID: \.id) {
            sectionHeader("YESTERDAY", count: 2)
        },
    ]

    var body: some View {
        MontraListView(sections: Self.sections, config: previewConfig) { PreviewRow(item: $0) }
            .montraListHeader {
                PreviewHeader(
                    title: "Day groups",
                    subtitle: "Sticky headers pin while scrolling")
            }
            .background(Color.secondary.opacity(0.12))
    }
}

/// 3 dòng — dưới một màn hình: không gắn onLoadMore nên probe đáy không
/// có nghĩa (list ngắn không tạo thay đổi geometry sau lúc gắn), header
/// lẫn footer vẫn cuộn cùng nội dung, swipe + tap vẫn sống. Hình "data
/// ít"
/// của app thật: vài dòng phải đứng đúng nhịp, không thêm trống ảo.
private struct FewItemsPreview: View {
    @State private var items = [7, 3, 1].map { fixtureItem(at: $0) }

    var body: some View {
        MontraListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .montraListHeader {
                PreviewHeader(
                    title: "Small list",
                    subtitle: "3 rows — no load-more attached, nothing fires")
            }
            .montraListFooter {
                Text("Footer scrolls with content")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            .rowSwipeActions { item in
                [MontraListSwipeAction(
                    title: "Delete \(item.title)", systemImage: "trash",
                    isDestructive: true) {}]
            }
            .onRowTap { tapped in
                items.removeAll { $0.id == tapped.id }
            }
            .background(Color.secondary.opacity(0.12))
    }
}

/// 4 trang × 25 dòng — trang đầu đủ dài để cuộn thật: vào vùng ngưỡng
/// đáy là probe fire, trang mới đính vào trong vùng là nạp TIẾP (liên
/// tục) cho tới trang 4; hết trang handler no-op — bắt chước `exhausted`
/// phía VM, nơi thật chặn fire trùng của probe + sentinel. Kèm refresh
/// đè load-more: về trang 1 dựng lại data — hai cơ chế dùng chung một
/// list không xung đột identity.
private struct PagedListPreview: View {
    private static let rowsPerPage = 25
    private static let lastPage = 4

    @State private var page = 1
    @State private var items = (1...25).map { pagedFixtureItem(at: $0, page: 1) }

    var body: some View {
        MontraListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .montraListHeader {
                PreviewHeader(
                    title: "Recent activity",
                    subtitle: page < Self.lastPage
                        ? "Page \(page)/\(Self.lastPage) — scroll to bottom to load more"
                        : "Page \(page)/\(Self.lastPage) — exhausted, load-more no-ops")
            }
            .onRefresh {
                try? await Task.sleep(for: .seconds(0.8))
                page = 1
                items = (1...Self.rowsPerPage).map { pagedFixtureItem(at: $0, page: 1) }
            }
            .onLoadMore {
                guard page < Self.lastPage else { return }
                try? await Task.sleep(for: .seconds(0.4))
                let next = page + 1
                items += (1...Self.rowsPerPage).map {
                    pagedFixtureItem(at: (next - 1) * Self.rowsPerPage + $0, page: next)
                }
                page = next
            }
            .background(Color.secondary.opacity(0.12))
    }
}

/// Refresh spinner đủ lâu (1.5s) để kéo-thả thấy rõ: spinner giữ tới khi
/// handler xong là tự kết thúc — không fan theo tick. Đếm lượt ở header
/// chứng minh mỗi pull đúng một lượt; `items.shuffle()` cho thay đổi
/// nhìn thấy sau mỗi lần kéo.
private struct SlowRefreshPreview: View {
    @State private var refreshCount = 0
    @State private var items = [7, 3, 1, 5].map { fixtureItem(at: $0) }

    var body: some View {
        MontraListView(items: items, config: previewConfig) { PreviewRow(item: $0) }
            .montraListHeader {
                PreviewHeader(
                    title: "Wallet",
                    subtitle: "Refreshed ×\(refreshCount) — pull to refresh (1.5s)")
            }
            .onRefresh {
                try? await Task.sleep(for: .seconds(1.5))
                refreshCount += 1
                items.shuffle()
            }
            .background(Color.secondary.opacity(0.12))
    }
}

/// Lỗi handler tự ném bị refreshable nuốt — spinner tự kết thúc, KHÔNG
/// có gì hiện lên SwiftUI: muốn trình bày lỗi phải tự xử lý ngay trong
/// handler (doc của `.onRefresh`). Preview bắt error và hiện banner
/// footer — pull refresh là thấy, chứng minh đường "lỗi tự xử lý".
private enum PreviewRefreshError: String, Error {
    case networkDown = "network down (simulated)"
}

private struct RefreshErrorPreview: View {
    @State private var lastError: String?

    var body: some View {
        MontraListView(items: [7, 2].map { fixtureItem(at: $0) }, config: previewConfig) { PreviewRow(item: $0) }
            .montraListHeader {
                PreviewHeader(
                    title: "Sync",
                    subtitle: "Pull to refresh — fails on purpose")
            }
            .montraListFooter {
                if let lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(.red)
                        .padding(12)
                }
            }
            .onRefresh {
                do {
                    try await Task.sleep(for: .seconds(0.8))
                    throw PreviewRefreshError.networkDown
                } catch {
                    lastError = error.localizedDescription
                }
            }
            .background(Color.secondary.opacity(0.12))
    }
}

#Preview("Flat — swipe, tap, load-more") {
    FlatListPreview()
}

#Preview("Sectioned — sticky headers") {
    SectionedListPreview()
}

#Preview("Flat — few rows (no load-more)") {
    FewItemsPreview()
}

#Preview("Flat — 4 pages, load-more + refresh") {
    PagedListPreview()
}

#Preview("Refresh — slow spinner") {
    SlowRefreshPreview()
}

#Preview("Refresh — error handled in handler") {
    RefreshErrorPreview()
}
