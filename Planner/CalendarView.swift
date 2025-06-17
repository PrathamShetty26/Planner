import SwiftUI

struct CalendarView: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool
    @State private var currentMonth: Date
    @State private var selectedMonth: Date
    
    init(selectedDate: Binding<Date>, isPresented: Binding<Bool>) {
        self._selectedDate = selectedDate
        self._isPresented = isPresented
        let calendar = Calendar.current
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate.wrappedValue))!
        self._currentMonth = State(initialValue: startOfMonth)
        self._selectedMonth = State(initialValue: startOfMonth)
    }
    
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Month selector
                HStack {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Text(monthYearFormatter.string(from: currentMonth))
                        .font(.title2.bold())
                    
                    Spacer()
                    
                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal)
                
                // Days of week header
                HStack(spacing: 0) {
                    ForEach(daysOfWeek, id: \.self) { day in
                        Text(day)
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                // Calendar grid
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(0..<days.count, id: \.self) { index in
                        if let date = days[index] {
                            DayButton(
                                date: date,
                                isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                                isToday: Calendar.current.isDateInToday(date),
                                isCurrentMonth: Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month)
                            ) {
                                selectedDate = date
                                isPresented = false
                            }
                        } else {
                            // Empty cell
                            Rectangle()
                                .foregroundColor(.clear)
                                .frame(height: 40)
                                .id(UUID()) // Add a unique ID to each empty rectangle
                        }
                    }
                }
                .padding(.horizontal)
                
                // Today button
                Button("Today") {
                    selectedDate = Date()
                    let calendar = Calendar.current
                    currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
                    isPresented = false
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(20)
                .padding(.top)
                
                Spacer()
            }
            .padding(.top)
            .navigationBarItems(
                trailing: Button("Done") { isPresented = false }
            )
        }
    }
    
    private var days: [Date?] {
        let calendar = Calendar.current
        
        // Get the first day of the month
        let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        
        // Get the weekday of the first day (1 = Sunday, 2 = Monday, etc.)
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        
        // Calculate the number of days in the month
        let range = calendar.range(of: .day, in: .month, for: currentMonth)!
        let numDays = range.count
        
        // Create an array with empty cells for days before the first day of the month
        var days = Array(repeating: nil as Date?, count: firstWeekday - 1)
        
        // Add the days of the month
        for day in 1...numDays {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        
        // Add empty cells to complete the last week if needed
        let remainingCells = 7 - (days.count % 7)
        if remainingCells < 7 {
            days.append(contentsOf: Array(repeating: nil as Date?, count: remainingCells))
        }
        
        return days
    }
    
    private func previousMonth() {
        let calendar = Calendar.current
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            withAnimation {
                currentMonth = newMonth
            }
        }
    }
    
    private func nextMonth() {
        let calendar = Calendar.current
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            withAnimation {
                currentMonth = newMonth
            }
        }
    }
    
    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }
}

struct DayButton: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                    .foregroundColor(
                        isSelected ? .white :
                            isToday ? .blue :
                            isCurrentMonth ? .primary : .secondary
                    )
                    .frame(width: 40, height: 40)
                    .background(
                        isSelected ? Color.blue :
                            isToday ? Color.blue.opacity(0.2) : Color.clear
                    )
                    .clipShape(Circle())
            }
        }
    }
}

#Preview {
    CalendarView(selectedDate: .constant(Date()), isPresented: .constant(true))
}
