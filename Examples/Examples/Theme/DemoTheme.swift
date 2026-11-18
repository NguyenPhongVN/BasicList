import SwiftUI
import BasicList

// MARK: - The demo look — one place to change everything
//
// Colors come from the asset catalog (`Demo*.colorset` with light + dark
// variants) so the demos follow the system appearance like a real app
// would. This file is the app's single wiring point for the package's two
// config structs.

enum DemoTheme {

    /// The canvas both the hub and every demo page pour behind themselves.
    static let canvas = Color("DemoCanvas")
    /// Fill of the search field pill.
    static let searchField = Color("DemoSearchField")
    /// Card surface of one demo/hub row (the grouped-list look: rows are
    /// cards floating on the canvas, light white / dark elevated).
    static let rowCard = Color("DemoRowCard")

    /// Page-level config for every `BasicListPage` demo.
    static let page = BasicListPageConfig(
        titleColor: .primary,
        titleFont: .system(.title2, design: .rounded).weight(.bold),
        subtitleColor: .secondary,
        subtitleFont: .system(.footnote, design: .rounded),
        backgroundColor: canvas,
        headerListSpacing: 8,
        searchBackground: searchField,
        searchForeground: .primary,
        emptyIcon: "tray",
        emptyTitle: "Nothing here yet",
        emptyMessage: "Items you add will show up in this list.",
        emptyIconColor: .secondary,
        progressTint: .blue,
        destructiveActionTint: .red,
        bottomClearance: 0)

    /// The app-side date pager's look (the pager is app chrome —
    /// `Components/DatePager.swift` — mounted into `.basicPageBottomBar`).
    static let pagerChevronColor = Color.primary
    static let pagerTextColor = Color.primary
    static let pagerTextFont = Font.system(.title3, design: .rounded).weight(.bold)

    /// Engine-level config for screens that mount `BasicListView` directly
    /// (the hub). Pushed pages cover the bottom — no tab bar clearance.
    static let list = BasicListConfig(destructiveActionTint: .red, bottomClearance: 0)
}
