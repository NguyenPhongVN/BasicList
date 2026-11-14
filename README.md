# BasicList

[![CI](https://github.com/NguyenPhongVN/BasicList/actions/workflows/ci.yml/badge.svg)](https://github.com/NguyenPhongVN/BasicList/actions/workflows/ci.yml)

Engine list SwiftUI **"array vào — item ra"** cho house list — một view cho cả hình flat và sectioned (sticky header từng nhóm), kèm đầy đủ header / empty-state / footer / swipe actions / row tap / pull-to-refresh / load-more liên tục / reorder.

Package độc lập, thuần SwiftUI — **không đọc design layer của app nào cả**: mọi màu/thông số truyền vào qua `BasicListConfig`.

## Tính năng

- ✅ Flat list (`items:`) và sectioned list (`sections:`) với sticky header từng nhóm — **một** engine cho cả hai
- ✅ Header 2 mode: lướt cùng nội dung (`.scrollsWithContent`) hoặc ghim đỉnh (`.pinnedTop`)
- ✅ Empty-state chạy **trong** list (giữ identity list giữa hai pha rỗng/có data)
- ✅ Footer cuộn cùng nội dung như một section thật
- ✅ Swipe actions per-row (data in, events out) — **cả hai mép** trái/phải (`edge: .leading`), full-swipe, tint destructive theo config
- ✅ Context menu tap-giữ theo row — không chiếm tap thường lẫn swipe
- ✅ Footer cho **từng section** — đối xứng với sticky header
- ✅ Row tap toàn vùng, VoiceOver đầy đủ (button trait + accessibility actions)
- ✅ Pull-to-refresh (lỗi handler tự xử lý trong handler — spinner tự kết thúc)
- ✅ Load-more liên tục: probe geometry trên thân List + sentinel bù list ngắn
- ✅ Reorder flat list (`onMoveRows` + `basicEditMode`) — iOS only
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
    .package(url: "https://github.com/NguyenPhongVN/BasicList.git", from: "1.0.0"),
]
```

Hoặc bám branch `main` để nhận luôn thay đổi (không khuyến khích cho app thật):

```swift
dependencies: [
    .package(url: "https://github.com/NguyenPhongVN/BasicList.git", branch: "main"),
]
```

Hoặc path dependency cục bộ (khi phát triển song song trong monorepo):

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
BasicListView(items: accounts, config: .house) { account in
    AccountRowView(account)
}
```

Item chưa `Identifiable` — dán id qua closure, như `ForEach(id:)`:

```swift
BasicListView(items: accounts, id: \.name, config: .house) { account in
    AccountRowView(account)
}
```

### Sectioned list — sticky header từng nhóm

```swift
let sections: [BasicListSection<Transaction>] = [
    BasicListSection(section: "Today", items: todays, itemID: \.id) {
        DayHeader("TODAY")          // sticky khi cuộn
    } footer: {
        DayFooter("TODAY")          // tuỳ chọn — nhóm không cần thì dùng init không footer
    },
    BasicListSection(section: "Yesterday", items: yesterdays, itemID: \.id) {
        DayHeader("YESTERDAY")
    },
]

BasicListView(sections: sections, config: .house) { transaction in
    TransactionRowView(transaction)
}
```

### Chain modifiers

Modifier builder-style, trả `Self` — chain thoải mái, không có state ẩn đổi theo thứ tự gọi:

```swift
BasicListView(items: transactions, config: .house) { TransactionRowView($0) }
    .basicListHeader { AccountBalanceHeader() }        // hoặc .basicListHeader(mode: .pinnedTop) { ... }
    .basicListEmptyState { EmptyHero() }               // list rỗng
    .basicListFooter { SuggestionCategories() }        // đáy list
    .rowSwipeActions { transaction in                    // swipe trái (mặc định .trailing)
        [
            BasicListSwipeAction(title: "Delete", systemImage: "trash", isDestructive: true) {
                vm.delete(transaction)
            },
        ]
    }
    .rowSwipeActions(edge: .leading) { _ in              // thêm swipe mép trái
        [BasicListSwipeAction(title: "Pin", systemImage: "pin.fill") { vm.pin($0) }]
    }
    .rowContextMenu { transaction in                     // tap-giữ mở menu
        Button("Copy") { vm.copy(transaction) }
    }
    .onRowTap { vm.open($0) }
    .onRefresh { try await api.reload() }
    .onLoadMore { try await api.nextPage() }            // pixelThreshold: 400 để đổi ngưỡng
```

Reorder (flat list, iOS only — handle hiện khi `editMode` `.active`):

```swift
BasicListView(items: categories, config: .house) { CategoryRowView($0) }
    .onMoveRows { vm.move($0, to: $1) }
    .basicEditMode($editMode)
```

### List trần — `BasicPlainList`

Screen **tự dựng** sections/rows phức tạp riêng → dùng trực tiếp list trần (nền trong suốt, content margins 0, row height tối thiểu 0):

```swift
BasicPlainList(config: .house) {
    ForEach(sections) { ... }
}
```

`BasicListView` dựng TRÊN nền này — mọi list của app cùng một ngôn ngữ render.

### Khối dựng list riêng

Ba khối vocabulary vẫn áp dụng được khi screen tự viết `List`:

```swift
// Style chuẩn của MỘT row house — idempotent
row.basicListRowStyle()

// Spacer đáy cuộn cùng nội dung (clearing tab bar)
BasicListSpacer(height: config.bottomClearance)

// Sentinel load-more cho list tự dựng
BasicListScrollSentinel { await vm.loadMore() }
```

## Config — `BasicListConfig`

Mọi màu/thông số truyền vào qua config — **thiếu config là lỗi compile**, không có diện mạo lặng lẽ nào cả:

| Field | Ý nghĩa |
|---|---|
| `destructiveActionTint` | Tint của swipe action có cờ `isDestructive: true` |
| `bottomClearance` | Khoảng trống đáy list (clearing tab bar) — context không che đáy thì truyền `0` |

App layer tập hợp giá trị chuẩn tại **một điểm** thay vì rải màu ở từng call site:

```swift
extension BasicListConfig {
    static var house: BasicListConfig {
        BasicListConfig(
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
| `BasicListView` | Engine chính — flat & sectioned |
| `BasicPlainList` | List `.plain` trần — nền của mọi list house |
| `BasicListConfig` | Màu/thông số truyền vào |
| `BasicListSection` | Một nhóm + sticky header + footer tuỳ chọn |
| `BasicListSwipeAction` | Mô tả một swipe action |
| `BasicListHeaderMode` | `.scrollsWithContent` / `.pinnedTop` |
| `BasicListSpacer` | Spacer trong suốt cuộn cùng nội dung |
| `BasicListScrollSentinel` | Sentinel bù fire load-more list ngắn |
| `View.basicListRowStyle()` | Style row house — idempotent |

Chi tiết cơ chế load-more (probe geometry + sentinel), rule bắt buộc và A11y — xem [`Sources/BasicList/README.md`](Sources/BasicList/README.md).

## License

[MIT](LICENSE) — Copyright (c) 2026 NguyenPhongVN
