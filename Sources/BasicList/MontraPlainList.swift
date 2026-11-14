import SwiftUI

/// List `.plain` trần đúng chuẩn house — nền của mọi list trong app.
///
/// Ba cài đặt định danh chữ "trần": nền trong suốt (screen tự đổ nền qua
/// `montraBackground`, list không tự có màu), content margins 0 (nội
/// dung chạm mép, cell tự vẽ padding/card của nó), row height tối thiểu
/// 0 (row cao bao nhiêu do nội dung, không bị padding hệ thống nâng).
///
/// Chọn view nào:
/// - Screen TỰ dựng sections/rows phức tạp riêng (sections tuỳ ý, content
///   xen kẽ giữa các khối) → dùng trực tiếp view này.
/// - "Array vào — item ra" với header/empty-state/swipe/tap/refresh/
///   load-more có sẵn → dùng `MontraListView` (dựng TRÊN nền này — mọi
///   list của app cùng một ngôn ngữ render).
///
/// Khoảng trống đáy list (clearing cho tab bar) lấy từ
/// `config.bottomClearance` — caller truyền giá trị chuẩn của app
/// (`MontraListConfig.house`); context khác không che đáy thì truyền 0.
public struct MontraPlainList<Content: View>: View {

    package let config: MontraListConfig
    package let content: () -> Content

    public init(
        config: MontraListConfig,
        @ViewBuilder _ content: @escaping () -> Content
    ) {
        self.config = config
        self.content = content
    }

    public var body: some View {
        List {
            content()
            MontraListSpacer(height: config.bottomClearance)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
