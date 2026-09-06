import SwiftUI

/// A month grid for picking the two ends of a date range.
///
/// AppKit's calendar (`NSDatePicker`) draws its own bezel and accent no matter
/// how it is configured, which reads as a system dialog dropped into a 290pt
/// popover. Thirty lines of grid buy the app's own colours, the range shaded
/// between the two ends, and future days that simply aren't tappable.
struct RangeCalendar: View {
    @Binding var start: Date
    @Binding var end: Date
    /// Which end the next tap sets. Owned by the caller so the chips above the
    /// calendar can move it too.
    @Binding var editingEnd: Bool

    @State private var month: Date = Date()
    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    var body: some View {
        VStack(spacing: 8) {
            header
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(DS.caption).foregroundStyle(DS.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 2) {
                ForEach(weeks, id: \.first) { week in
                    HStack(spacing: 0) {
                        ForEach(week, id: \.self) { date in
                            day(date)
                        }
                    }
                }
            }
        }
        .onAppear { month = calendar.startOfDay(for: editingEnd ? end : start) }
    }

    private var header: some View {
        HStack {
            step(-1, icon: "chevron.left")
            Spacer()
            Text(monthTitle).font(DS.body.weight(.semibold)).foregroundStyle(DS.ink)
            Spacer()
            step(1, icon: "chevron.right")
        }
    }

    private func step(_ months: Int, icon: String) -> some View {
        Button {
            if let moved = calendar.date(byAdding: .month, value: months, to: month) { month = moved }
        } label: {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.inkSecondary)
        .disabled(months > 0 && calendar.isDate(month, equalTo: today, toGranularity: .month))
    }

    private func day(_ date: Date) -> some View {
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let future = date > today
        let isStart = calendar.isDate(date, inSameDayAs: start)
        let isEnd = calendar.isDate(date, inSameDayAs: end)
        let inRange = date > min(start, end) && date < max(start, end)
        return Button {
            select(date)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(DS.caption.weight(isStart || isEnd ? .semibold : .regular))
                .foregroundStyle(colour(inMonth: inMonth, future: future, selected: isStart || isEnd))
                .frame(maxWidth: .infinity, minHeight: 22)
                .background(background(selected: isStart || isEnd, inRange: inRange))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
    }

    private func colour(inMonth: Bool, future: Bool, selected: Bool) -> Color {
        if selected { return .white }
        if future || !inMonth { return DS.inkTertiary.opacity(future ? 0.4 : 1) }
        return DS.ink
    }

    @ViewBuilder
    private func background(selected: Bool, inRange: Bool) -> some View {
        if selected {
            Circle().fill(DS.brand).frame(width: 22, height: 22)
        } else if inRange {
            Rectangle().fill(DS.brand.opacity(0.10))
        }
    }

    /// First tap sets the start and moves on to the end, second tap sets the
    /// end — the order everyone expects from a range picker. A date before the
    /// start becomes the new start instead of an empty range.
    private func select(_ date: Date) {
        if editingEnd {
            if date < start { start = date } else { end = date; editingEnd = false }
        } else {
            start = date
            if end < date { end = date }
            editingEnd = true
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: month).capitalized
    }

    private var weekdaySymbols: [String] {
        let symbols = DateFormatter().shortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first]).map { String($0.prefix(2)) }
    }

    /// Six weeks, always: a grid that changes height as you page through months
    /// makes the popover jump.
    private var weeks: [[Date]] {
        guard let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let firstShown = calendar.date(byAdding: .day,
                                             value: -((calendar.component(.weekday, from: firstOfMonth)
                                                       - calendar.firstWeekday + 7) % 7),
                                             to: firstOfMonth) else { return [] }
        return (0..<6).map { week in
            (0..<7).compactMap { weekday in
                calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstShown)
            }
        }
    }
}
