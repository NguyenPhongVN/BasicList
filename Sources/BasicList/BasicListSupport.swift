import SwiftUI

// MARK: - Vocabulary dùng chung của BasicList
//
// Các type nhỏ đi kèm engine: mode header, section, swipe action, spacer,
// sentinel, row style. Ba nhóm người dùng chung một ngôn ngữ render:
// engine (`BasicListView`), list trần (`BasicPlainList`), và screen
// tự dựng List riêng (sentinel/spacer/row-style vẫn áp dụng được).

/// Mode header của `BasicListView`:
/// - `.scrollsWithContent`: header lướt cùng nội dung (mặc định).
/// - `.pinnedTop`: ghim đỉnh — sticky như supplementary view của UIKit.
public enum BasicListHeaderMode {
    case scrollsWithContent
    case pinnedTop
}

/// Một nhóm có sticky header riêng — hình điển hình: một ngày + các
/// giao dịch trong ngày đó.
///
/// Header lưu CLOSURE thay vì view đã dựng: mảng sections thường là
/// computed property của screen (chạy lại mỗi lần body re-eval) — build
/// sẵn `AnyView` ở đây là dựng header cho những lượt render bị vứt;
/// closure chỉ tiêu hao khi list thật sự render group đó.
public struct BasicListSection<Item> {
    package let section: AnyHashable
    package let header: () -> AnyView
    package let items: [Item]
    package let itemID: (Item) -> AnyHashable

    public init(
        section: any Hashable,
        items: [Item],
        itemID: @escaping (Item) -> any Hashable,
        @ViewBuilder header: @escaping () -> some View
    ) {
        self.section = AnyHashable(section)
        self.items = items
        self.itemID = { item in AnyHashable(itemID(item)) }
        self.header = { AnyView(header()) }
    }
}

/// Một swipe action trả về từ handler `.rowSwipeActions` — data in,
/// events out: caller mô tả nút (title/glyph/cờ destructive), engine vẽ
/// và hồi báo handler khi user bấm. Tint của nút destructive KHÔNG nằm
/// ở đây — lấy từ `BasicListConfig.destructiveActionTint` của list.
public struct BasicListSwipeAction {
    package let title: String
    package let systemImage: String
    package let isDestructive: Bool
    package let handler: () -> Void

    public init(
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.handler = handler
    }
}

/// Style chuẩn của MỘT row trong list house: không inset, không
/// separator, nền trong suốt — cell tự vẽ nền/card của nó. Idempotent:
/// engine nội bộ cũng áp trên row đã style, gọi lại không đổi gì.
public extension View {
    func basicListRowStyle() -> some View {
        self
            .listRowInsets(EdgeInsets.zero)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

package extension EdgeInsets {
    /// Đối trọng `EdgeInsets.zero` cho list house — dùng cùng
    /// `basicListRowStyle()`.
    static let zero = EdgeInsets()
}

/// Row trong suốt cao `height` — chèn đáy `BasicPlainList` (clearing
/// tab bar) hoặc bất kỳ khoảng đệm cuộn-cùng-nội dung nào cần nằm trong
/// list.
public struct BasicListSpacer: View {
    package let height: CGFloat

    public init(height: CGFloat) {
        self.height = height
    }

    public var body: some View {
        Color.clear
            .frame(height: height)
            .basicListRowStyle()
            // Spacer thuần cơ học — không phải điểm dừng VoiceOver.
            .accessibilityHidden(true)
    }
}

/// Sentinel đáy: row trong suốt 1pt mang `onAppear` — fire load-more
/// khi materialize. Dùng nội bộ của `BasicListView` và như row cuối
/// của screen dựng List riêng.
///
/// Vai trò: BÙ FIRE LÚC GẮN cho list ngắn. Load-more chính chạy bằng
/// probe geometry trên thân List (`.basicListBottomProbe`, private của
/// engine) — observer sống trọn vòng đời list, fire theo chuyển trạng
/// thái vào vùng đáy. Nhưng trang đầu chưa đủ đầy màn thì không có phép
/// đổi geometry nào sau lúc probe gắn (khoảng cách đáy âm — đã trong
/// vùng — nhưng không bao giờ "đi vào" vùng nữa): sentinel nằm cuối list
/// ngắn materialize NGAY, `onAppear` kêu về VM nạp tiếp cho tới khi list
/// vượt vùng. Với list dài, List lazy chỉ materialize sentinel khi user
/// đã cuộn vào vùng đáy — đúng điều kiện. Lượt fire trùng (probe +
/// sentinel cùng nổ) chặn phía VM (`Paging.inFlight` / `exhausted`) —
/// sentinel không giữ state nào.
public struct BasicListScrollSentinel: View {

    /// Vào vùng trigger khi còn cách đáy dưới ngưỡng này — ngưỡng mặc
    /// định dùng chung cho probe thân List (`.basicListBottomProbe`).
    public static let defaultBottomThreshold: CGFloat = 600

    package let onLoadMore: () async -> Void

    public init(onLoadMore: @escaping () async -> Void) {
        self.onLoadMore = onLoadMore
    }

    public var body: some View {
        Color.clear
            .frame(height: 1)
            .basicListRowStyle()
            // Row ảo 1pt — ẩn khỏi VoiceOver (không phải nội dung).
            .accessibilityHidden(true)
            .onAppear {
                Task { await onLoadMore() }
            }
    }
}
