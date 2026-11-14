# BasicList

Engine list SwiftUI **"array vào — item ra"** cho house list — một view cho cả hình flat và sectioned (sticky header từng nhóm), kèm đầy đủ header / empty-state / footer / swipe actions / row tap / pull-to-refresh / load-more liên tục / reorder.

Tách từ package [BasicMontra](https://github.com/NguyenPhongVN/BasicMontra) thành package độc lập, thuần SwiftUI — **không đọc design layer của app nào cả**: mọi màu/thông số truyền vào qua `MontraListConfig`.

## Tính năng

- ✅ Flat list (`items:`) và sectioned list (`sections:`) với sticky header từng nhóm — **một** engine cho cả hai
- ✅ Header 2 mode: lướt cùng nội dung (`.scrollsWithContent`) hoặc ghim đỉnh (`.pinnedTop`)
- ✅ Empty-state chạy **trong** list (giữ identity list giữa hai pha rỗng/có data)
- ✅ Footer cuộn cùng nội dung như một section thật
- ✅ Swipe actions per-row (data in, events out), full-swipe, tint destructive theo config
- ✅ Row tap toàn vùng, VoiceOver đầy đủ (button trait + accessibility actions)
- ✅ Pull-to-refresh (lỗi handler tự xử lý trong handler — spinner tự kết thúc)
- ✅ Load-more liên tục: probe geometry trên thân List + sentinel bù list ngắn
- ✅ Reorder flat list (`onMoveRows` + `montraEditMode`) — iOS only
- ✅ Reorder + swipe + tap + refresh + load-more **dùng chung một list không xung đột identity**

## Yêu cầu

| | |
|---|---|
| Platforms | iOS 26+ · macOS 26+ · tvOS 26+ · watchOS 26+ · visionOS 26+ |
| Swift | tools 6.4, Swift 6 mode, `ApproachableConcurrency` |
| Dependencies | **NONE** — thuần SwiftUI |

## Cài đặt

**Swift Package Manager:**

```swift
dependencies: [
    .package(url: "https://github.com/NguyenPhongVN/BasicList.git", branch: "main"),
]
```

Hoặc path dependency cục bộ (cách BasicMontra đang dùng khi phát triển song song):

```swift
dependencies: [
    .package(path: "../BasicList"),
]
```

Rồi import:

```swift
import BasicList
```

## Sử dụng nhanh

### Flat list

Item tự `Identifiable`:

```swift
MontraListView(items: accounts, config: .house) { account in
    AccountRowView(account)
}
```

Item chưa `Identifiable` — dán id qua closure, như `ForEach(id:)`:

```swift
MontraListView(items: accounts, id: \.name, config: .house) { account in
    AccountRowView(account)
}
```

### Sectioned list — sticky header từng nhóm

```swift
let sections: [MontraListSection<Transaction>] = [
    MontraListSection(section: "Today", items: todays, itemID: \.id) {
        DayHeader("TODAY")          // sticky khi cuộn
    },
    MontraListSection(section: "Yesterday", items: yesterdays, itemID: \.id) {
        DayHeader("YESTERDAY")
    },
]

MontraListView(sections: sections, config: .house) { transaction in
    TransactionRowView(transaction)
}
```

### Chain modifiers

Modifier builder-style, trả `Self` — chain thoải mái, không có state ẩn đổi theo thứ tự gọi:

```swift
MontraListView(items: transactions, config: .house) { TransactionRowView($0) }
    .montraListHeader { AccountBalanceHeader() }        // hoặc .montraListHeader(mode: .pinnedTop) { ... }
    .montraListEmptyState { EmptyHero() }               // list rỗng
    .montraListFooter { SuggestionCategories() }        // đáy list
    .rowSwipeActions { transaction in                    // swipe trái
        [
            MontraListSwipeAction(title: "Delete", systemImage: "trash", isDestructive: true) {
                vm.delete(transaction)
            },
        ]
    }
    .onRowTap { vm.open($0) }
    .onRefresh { try await api.reload() }
    .onLoadMore { try await api.nextPage() }            // pixelThreshold: 400 để đổi ngưỡng
```

Reorder (flat list, iOS only — handle hiện khi `editMode` `.active`):

```swift
MontraListView(items: categories, config: .house) { CategoryRowView($0) }
    .onMoveRows { vm.move($0, to: $1) }
    .montraEditMode($editMode)
```

### List trần — `MontraPlainList`

Screen **tự dựng** sections/rows phức tạp riêng → dùng trực tiếp list trần (nền trong suốt, content margins 0, row height tối thiểu 0):

```swift
MontraPlainList(config: .house) {
    ForEach(sections) { ... }
}
```

`MontraListView` dựng TRÊN nền này — mọi list của app cùng một ngôn ngữ render.

### Khối dựng list riêng

Ba khối vocabulary vẫn áp dụng được khi screen tự viết `List`:

```swift
// Style chuẩn của MỘT row house — idempotent
row.montraListRowStyle()

// Spacer đáy cuộn cùng nội dung (clearing tab bar)
MontraListSpacer(height: config.bottomClearance)

// Sentinel load-more cho list tự dựng
MontraListScrollSentinel { await vm.loadMore() }
```

## Config — `MontraListConfig`

Mọi màu/thông số truyền vào qua config — **thiếu config là lỗi compile**, không có diện mạo lặng lẽ nào cả:

| Field | Ý nghĩa |
|---|---|
| `destructiveActionTint` | Tint của swipe action có cờ `isDestructive: true` |
| `bottomClearance` | Khoảng trống đáy list (clearing tab bar) — context không che đáy thì truyền `0` |

App layer tập hợp giá trị chuẩn tại **một điểm** thay vì rải màu ở từng call site:

```swift
extension MontraListConfig {
    static var house: MontraListConfig {
        MontraListConfig(
            destructiveActionTint: .red,
            bottomClearance: 80)
    }
}
```

Đổi diện mạo list toàn app chỉ sửa đúng file wiring đó.

## Ba nguyên tắc của engine

1. **Data in, events out** — swipe/tap/move/refresh/load-more đều là closure caller truyền vào; engine không giữ state nghiệp vụ nào, nguồn dữ liệu duy nhất là mảng/sections đưa vào.
2. **Immutable, modifier trả `Self`** — chain thoải mái, không có state ẩn đổi theo thứ tự gọi modifier.
3. **Design đi qua config** — không màu/thông số hardcode trong module; app quyết định diện mạo.

## API public

| Symbol | Vai trò |
|---|---|
| `MontraListView` | Engine chính — flat & sectioned |
| `MontraPlainList` | List `.plain` trần — nền của mọi list house |
| `MontraListConfig` | Màu/thông số truyền vào |
| `MontraListSection` | Một nhóm + sticky header |
| `MontraListSwipeAction` | Mô tả một swipe action |
| `MontraListHeaderMode` | `.scrollsWithContent` / `.pinnedTop` |
| `MontraListSpacer` | Spacer trong suốt cuộn cùng nội dung |
| `MontraListScrollSentinel` | Sentinel bù fire load-more list ngắn |
| `View.montraListRowStyle()` | Style row house — idempotent |

Chi tiết cơ chế load-more (probe geometry + sentinel), rule bắt buộc và A11y — xem [`Sources/BasicList/README.md`](Sources/BasicList/README.md).

## License

[MIT](LICENSE) — Copyright (c) 2026 NguyenPhongVN
