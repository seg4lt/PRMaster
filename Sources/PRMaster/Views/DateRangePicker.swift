import SwiftUI

struct DateRangePicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @State private var showingPopover = false
    @State private var displayedMonth: Date = Date()

    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    var body: some View {
        Button {
            displayedMonth = startDate
            showingPopover = true
        } label: {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.secondary)
                Text(dateRangeText)
                    .foregroundColor(.primary)
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.caption2)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            calendarPopover
        }
    }

    private var calendarPopover: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(monthYearString(from: displayedMonth))
                    .font(.headline)

                Spacer()

                Button {
                    displayedMonth = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
            }

            calendarGrid

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start: \(formatDate(startDate))")
                        .font(.caption)
                    Text("End: \(formatDate(endDate))")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    showingPopover = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var calendarGrid: some View {
        let days = generateDaysInMonth(for: displayedMonth)
        let weekdays = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { date in
                    if let date = date {
                        dayButton(for: date)
                    } else {
                        Text("")
                            .frame(height: 28)
                    }
                }
            }
        }
    }

    private func dayButton(for date: Date) -> some View {
        let calendar = Calendar.current
        let isStart = calendar.isDate(date, inSameDayAs: startDate)
        let isEnd = calendar.isDate(date, inSameDayAs: endDate)
        let isInRange = date >= calendar.startOfDay(for: startDate) && date <= calendar.startOfDay(for: endDate)
        let isToday = calendar.isDateInToday(date)

        return Button {
            selectDate(date)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.caption)
                .frame(width: 28, height: 28)
                .background(
                    Group {
                        if isStart || isEnd {
                            Circle().fill(Color.accentColor)
                        } else if isInRange {
                            Circle().fill(Color.accentColor.opacity(0.2))
                        } else {
                            Circle().fill(Color.clear)
                        }
                    }
                )
                .foregroundColor(isStart || isEnd ? .white : (isToday ? .accentColor : .primary))
        }
        .buttonStyle(.plain)
    }

    @State private var selectionState: SelectionState = .none

    private enum SelectionState {
        case none
        case startSelected
    }

    private func selectDate(_ date: Date) {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: date)

        switch selectionState {
        case .none:
            startDate = selectedDay
            endDate = selectedDay
            selectionState = .startSelected
        case .startSelected:
            if selectedDay < startDate {
                startDate = selectedDay
            } else {
                endDate = selectedDay
            }
            selectionState = .none
        }
    }

    private func generateDaysInMonth(for date: Date) -> [Date?] {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: date)!
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)

        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)

        for day in range {
            if let dayDate = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(dayDate)
            }
        }

        return days
    }

    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
