import SwiftUI

// MARK: - App-side date pager (the BudgetStepperView pattern)
//
// The period-paging row of a time-windowed page: `‹ chevron — window label —
// chevron ›`, mounted BELOW the list through `.basicPageBottomBar`. The
// package ships the generic slot only — the pager is app chrome (in
// BasicMontra it lives in BasicDesignComponents, not BasicList), so it lives
// here with the app's look and wording.

/// One period unit of the date pager — a page is exactly one unit wide.
enum DemoPeriodUnit: Equatable {
    case day
    case week
    case month
    case year
}

/// The date pager — previous/next period with the window label between the
/// chevrons.
///
/// ## Contract (data in, events out — mechanical stepping inside)
/// - The pager OWNS the stepping: it mutates `windowStart` by exactly one
///   `unit` per tap, forward-disabled at `anchor` (the newest page).
/// - The caller owns everything the component can't know: the LABEL (`text`,
///   re-computed per body pass from `windowStart` with the caller's own date
///   formatter — the component never formats dates), the `anchor`, the look
///   (colors/font) and the page DATA for the displayed window.
/// - `onNavigate` reports the flip direction (`true` = forward / next date)
///   so the screen can build an asymmetric transition — the pager never
///   animates the caller's content.
///
/// ## Why month/year re-derive from the anchor
/// Anchors on the 29th–31st get calendar-clamped across short months
/// (Jan 31 → Feb 28). Compounding from the clamped date drifts one day
/// permanently: the current page can never be returned to and the pager
/// walks into the future. Month/year steps are re-derived from the ANCHOR
/// every time (period index computed against `anchor`, then applied to it)
/// so the math always lands back on the anchor's day-of-month — clamping
/// happens per-step, never accumulates.
///
/// Accessibility: the chevron Buttons carry the SF Symbols' built-in
/// localized descriptions ("chevron left" / "chevron right").
struct BasicListDatePager: View {

    /// The window label between the chevrons — caller-formatted per body
    /// pass (e.g. "Sep 1 - Sep 30").
    let text: String
    /// Start of the displayed page — stepped by the pager on navigation.
    let windowStart: Binding<Date>
    /// The newest page — forward stops here (disabled when the displayed
    /// page IS the anchor). Must be a page start produced by the same unit
    /// math (the exact-equality bound — dates only meet it when the same
    /// stepper built them).
    let anchor: Date
    let unit: DemoPeriodUnit
    /// Flip-direction callback — `true` = forward (next date).
    var onNavigate: ((Bool) -> Void)?

    // The look — app chrome values, wired from DemoTheme.
    let chevronColor: Color
    let textColor: Color
    let textFont: Font

    /// Forward is disabled exactly at the anchor — opacity 0.3 signals it,
    /// same language as the BudgetDetail stepper.
    var isForwardDisabled: Bool {
        windowStart.wrappedValue == anchor
    }

    /// Private calendar — `.current`: period boundaries follow the device's
    /// calendar, like the app's own window math.
    private var calendar: Calendar { .current }

    var body: some View {
        HStack {
            chevron(left: true, disabled: false) {
                onNavigate?(false)
                withAnimation(Self.pageAnimation) {
                    windowStart.wrappedValue = Self.step(
                        windowStart.wrappedValue, by: -1, anchor: anchor, unit: unit)
                }
            }
            Spacer()
            Text(text)
                .font(textFont)
                .foregroundStyle(textColor)
            Spacer()
            chevron(left: false, disabled: isForwardDisabled) {
                guard !isForwardDisabled else { return }
                onNavigate?(true)
                withAnimation(Self.pageAnimation) {
                    windowStart.wrappedValue = Self.step(
                        windowStart.wrappedValue, by: +1, anchor: anchor, unit: unit)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    /// Round chevron — 36pt visual inside a 44pt hit floor, disabled → 0.3
    /// opacity.
    private func chevron(
        left: Bool, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: left ? "chevron.left" : "chevron.right")
                .foregroundStyle(chevronColor)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
                .opacity(disabled ? 0.3 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// The shared page animation — same spring as the app's period paging.
    private static let pageAnimation = Animation
        .interactiveSpring(response: 0.35, dampingFraction: 0.86)

    /// Shifts `date` by `periods` units (negative = back). Day/week add
    /// directly; month/year re-derive from the ANCHOR (see the type doc —
    /// compounding from a clamped date drifts permanently).
    static func step(
        _ date: Date, by periods: Int, anchor: Date, unit: DemoPeriodUnit
    ) -> Date {
        let calendar = Calendar.current
        switch unit {
        case .day:
            return calendar.date(byAdding: .day, value: periods, to: date) ?? date
        case .week:
            return calendar.date(byAdding: .day, value: periods * 7, to: date) ?? date
        case .month, .year:
            let component: Calendar.Component = unit == .month ? .month : .year
            let delta = calendar.dateComponents([component], from: anchor, to: date)
            let current = (component == .month ? delta.month : delta.year) ?? 0
            return calendar.date(
                byAdding: component, value: current + periods, to: anchor) ?? date
        }
    }
}
