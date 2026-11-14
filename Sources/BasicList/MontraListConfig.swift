import SwiftUI

// MARK: - Config của MontraList

/// Mọi màu/thông số của họ MontraList TRUYỀN VÀO qua struct này —
/// module không tự đọc design layer (màu app, tab metrics) ở bất kỳ đâu:
/// engine giữ thuần SwiftUI, caller quyết định diện mạo.
///
/// Bắt buộc truyền khi dựng — không có default gắn giá trị design trong
/// module: thiếu config là lỗi compile thay vì một diện mạo lặng lẽ.
/// App layer tập hợp giá trị chuẩn tại MỘT điểm (`MontraListConfig.house`)
/// thay vì rải màu/metrics ở từng call site — đổi diện mạo list toàn app
/// chỉ sửa đúng file wiring đó.
public struct MontraListConfig: Sendable, Equatable {

    /// Tint của swipe action có cờ `isDestructive: true` — ngôn ngữ riêng
    /// của hành động phá dữ liệu; action thường GIỮ tint mặc định hệ
    /// thống (xem `montraRowSwipeActions`).
    package var destructiveActionTint: Color

    /// Khoảng trống đáy list — `MontraPlainList` chèn spacer đáy bằng
    /// giá trị này để nội dung cuối không bị tab bar che. List ở context
    /// khác không che đáy → truyền 0.
    package var bottomClearance: CGFloat

    public init(destructiveActionTint: Color, bottomClearance: CGFloat) {
        self.destructiveActionTint = destructiveActionTint
        self.bottomClearance = bottomClearance
    }
}
