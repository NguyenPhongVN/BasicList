# BasicList

Engine list house — thuần SwiftUI, **deps NONE** (không phụ thuộc module
nào trong package; preview/demo dùng literal spacing). Module **không
đọc design layer của app** (không màu design, không tab metrics, không
token): mọi màu/thông số truyền vào qua `BasicListConfig` — engine
quyết định cơ chế, caller quyết định diện mạo.

## 1. Chọn view nào?

| Tình huống | Dùng |
|---|---|
| Có mảng items, cần header/empty-state/swipe/tap/refresh/load-more có sẵn | `BasicListView` |
| Screen tự dựng sections/rows phức tạp riêng (sections tuỳ ý, content xen kẽ) | `BasicPlainList` |

`BasicListView` dựng TRÊN `BasicPlainList` — mọi list của app cùng
một ngôn ngữ nền: trong suốt (screen tự đổ nền của mình), content
margins 0, row height tối thiểu 0.

## 2. Quick start

### Flat list — swipe + tap + refresh + load-more

```swift
BasicListView(items: accounts, config: .house) { account in
    AccountRowView(account)          // cell tự .basicListRowStyle()
}
.basicListHeader { AccountBalanceHeader() }   // header cuộn cùng nội dung
.basicListEmptyState { AccountEmptyView() }   // hiện khi items rỗng
.rowSwipeActions { account in
    [
        BasicListSwipeAction(title: "Sửa", systemImage: "pencil") { edit(account) },
        BasicListSwipeAction(title: "Xoá", systemImage: "trash",
                              isDestructive: true) { confirmDelete(account) },
    ]
}
.rowContextMenu { account in
    Button("Copy name") { copy(account.name) }
}
.onRowTap { account in openDetail(account) }
.onRefresh { try await api.reload() }
.onLoadMore { try await api.nextPage() }
```

### Sectioned list — sticky header từng nhóm

```swift
let sections = Dictionary(grouping: transactions, by: \.day)
    .map { day, txns in
        BasicListSection(section: day, items: txns, itemID: \.id) {
            TransactionDayHeader(day)      // sticky khi cuộn
        } footer: {
            TransactionDayFooter(day)      // tuỳ chọn — nhóm không cần thì dùng init không footer
        }
    }

BasicListView(sections: sections, config: .house) { transaction in
    TransactionRowView(transaction)
}
```

> `BasicListView` là struct immutable — mọi modifier trả `Self`, chain
> thoải mái. Item chưa `Identifiable` dùng
> `init(items:id:config:content:)`, dán id qua closure như `ForEach(id:)`.

## 3. Config — `BasicListConfig`

**Bắt buộc truyền khi dựng** — không có default gắn giá trị design
trong module: thiếu config là lỗi compile thay vì một diện mạo lặng lẽ.

| Field | Nghĩa | App truyền |
|---|---|---|
| `destructiveActionTint` | Tint nút swipe có cờ `isDestructive: true` (action thường giữ tint hệ thống) | màu đỏ destructive của app |
| `bottomClearance` | Spacer đáy list — clearing khi list nằm trên tab bar; context không che đáy truyền 0 | clearance tab bar chuẩn của app |

**Wiring một điểm duy nhất** — app layer tự đặt extension
`BasicListConfig.house` tập hợp giá trị chuẩn của app. Call site luôn
truyền `config: .house`; muốn đổi diện mạo list toàn app chỉ sửa đúng
file wiring đó, không rải giá trị ở từng màn.

## 4. API của `BasicListView`

| API | Tác dụng |
|---|---|
| `.basicListHeader(mode:_:)` | Header đầu list — `.scrollsWithContent` (cuộn cùng) hoặc `.pinnedTop` (ghim đỉnh) |
| `.basicListEmptyState(_:)` | Hero rỗng chạy TRONG list (giữ identity list giữa 2 pha rỗng/có data) |
| `.basicListFooter(_:)` | Nội dung đáy — sau rows, trước sentinel load-more |
| `.rowSwipeActions(edge:_:)` | Handler trả `[BasicListSwipeAction]` cho từng item — `.trailing` mặc định; gọi thêm lần nữa với `.leading` cho swipe mép trái |
| `.rowContextMenu(_:)` | Menu tap-giữ theo item — không chiếm tap thường lẫn cử chỉ swipe |
| `.onRowTap(_:)` | Tap toàn vùng row (contentShape) — không chiếm cử chỉ swipe |
| `.onMoveRows(_:)` | Kéo-thả sắp xếp lại flat list — handle chỉ hiện khi `editMode` `.active` |
| `.basicEditMode(_:)` | Ghim `editMode` của List theo binding của screen (iOS-only) |
| `.onRefresh(_:)` | Pull-to-refresh; lỗi nuốt trong handler (`try?`), spinner tự kết thúc |
| `.onLoadMore(pagesAhead:pixelThreshold:_:)` | Load-more liên tục khi cuộn sát đáy (mặc định 600pt); `pagesAhead > 0` → prefetch kiểu ASDK/IGListKit — vùng đáy = N × viewport, nạp liên tục trước khi tới đáy |

Vocabulary dùng chung (`BasicListSupport.swift`) — engine và screen tự
dựng list đều dùng được:

| Type/helper | Nghĩa |
|---|---|
| `BasicListSection` | Một nhóm + header sticky + footer tuỳ chọn; header/footer lưu CLOSURE (chỉ dựng khi group thật sự render) |
| `BasicListSwipeAction` | Một swipe action; tint destructive lấy từ config, không nằm trong action |
| `BasicListSpacer(height:)` | Row trong suốt cao `height` — đệm cuộn-cùng-nội dung |
| `BasicListScrollSentinel` | Row 1pt fire `onAppear` — dùng như row cuối khi screen tự dựng list + load-more riêng |
| `.basicListRowStyle()` | Style chuẩn 1 row (không inset/separator, nền clear) — cell của bạn nên gọi |

⚠️ `.pinnedTop` + sectioned **chưa kiểm chứng** — pinned hiện chỉ đi với
flat list; tránh kết hợp cho tới khi cần và đã test.

## 5. Load-more vận hành thế nào

1. **Probe geometry** gắn TRÊN THÂN List (`onScrollGeometryChange`) —
   observer sống trọn vòng đời list (khác cơ chế cũ gắn probe lên row
   sentinel mà List lazy chỉ materialize khi user đã cuộn sát đáy).
   Fire theo CHUYỂN TRẠNG THÁI: đi vào vùng đáy, hoặc trang mới đính
   vào mà vẫn trong vùng (nạp tiếp liên tục cho tới khi ra khỏi vùng
   hoặc hết trang).
2. **Sentinel** (row 1pt cuối list) bù fire lúc gắn cho list ngắn —
   trang đầu chưa đủ màn thì không có phép đổi geometry nào sau lúc
   probe gắn.
3. **Chặn lặp nằm phía caller (VM)**: lượt fire trùng (probe + sentinel
   cùng nổ) do `Paging.inFlight` chặn song song, `exhausted` bỏ qua khi
   hết trang — probe/sentinel không giữ state.
4. **Prefetch `pagesAhead`** (kiểu ASDK `leadingScreensForBatching` /
   IGListKit): vùng đáy = `pagesAhead × chiều cao viewport` thay vì
   pixel tĩnh — trong vùng, probe nạp LIÊN TỤC theo từng trang đính
   vào cho tới khi cách đáy hơn vùng hoặc hết trang. `.onLoadMore(
   pagesAhead: 2)` ≈ giữ sẵn 2 trang phía trước user. `pagesAhead > 0`
   đè `pixelThreshold`; engine không đo chiều cao từng trang (data in/
   events out) — đơn vị đo là viewport.

## 6. Swipe actions — rule bắt buộc

- **KHÔNG dùng `role: .destructive`**: destructive-role + full swipe
  kích hoạt animation trượt row đi (SwiftUI coi row đã bị xoá) — không
  render lại thì row mất luôn dù data nguyên. Full swipe nổ handler,
  handler là hand-off confirm riêng (popup) của screen.
- Tint đỏ **chỉ** áp cho action `isDestructive: true`, màu lấy từ
  `config.destructiveActionTint`; action thường giữ tint hệ thống.
- Hai action trùng title vẫn là hai nút riêng (id theo vị trí, không id
  theo title).

## 7. Accessibility

- Row có tap → trait `.isButton` + `accessibilityAction` — rotor/tap
  đôi kích hoạt được, không chỉ cử chỉ tap thường.
- Swipe actions expose `.accessibilityAction(named:)` — cử chỉ swipe
  không tồn tại với VoiceOver.
- Sentinel/spacer ẩn khỏi VoiceOver (row ảo cơ học, không phải nội dung).

## 8. Preview

6 hình demo sống trong `BasicListView.swift` — mỗi hình một diện mạo
riêng (row glyph tròn màu + tiền, không phải `Text` trắng): flat
(swipe/tap/load-more/empty-state), sectioned sticky header, ít dòng,
4 trang phân trang + refresh đè load-more, refresh spinner chậm, refresh
lỗi tự xử lý trong handler. Config neutral — giá trị design thật chỉ
tồn tại ở app (`BasicListConfig.house`).

## 9. Ghi chú module

- Package độc lập, product `BasicList`. API `public` đúng mức cần thiết
  (types + init + modifier caller gọi); internals engine (probe, swipe
  render, Row/Group) vẫn private. App layer import tường minh
  `import BasicList`.
- Data in, events out xuyên suốt: engine không giữ state nghiệp vụ,
  nguồn dữ liệu duy nhất là mảng/sections caller đưa vào.
