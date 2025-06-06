import SwiftUI

struct AddHabitView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @Binding var isPresented: Bool
    
    @State private var title = ""
    @State private var notes = ""
    @State private var repeatOption: RepeatOption = .daily
    @State private var selectedDays: Set<Weekday> = []
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes)
                }
                
                Section {
                    Picker("Repeat", selection: $repeatOption) {
                        ForEach(RepeatOption.allCases, id: \.self) { option in
                            Label(option.rawValue, systemImage: option.systemImage)
                        }
                    }
                    
                    if repeatOption == .weekly {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Weekday.allCases, id: \.self) { day in
                                    DaySelectionButton(
                                        day: day,
                                        isSelected: selectedDays.contains(day),
                                        action: {
                                            if selectedDays.contains(day) {
                                                selectedDays.remove(day)
                                            } else {
                                                selectedDays.insert(day)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("New Habit")
            .navigationBarItems(
                leading: Button("Cancel") { isPresented = false },
                trailing: Button("Add") {
                    addHabit()
                    isPresented = false
                }
                .disabled(title.isEmpty || (repeatOption == .weekly && selectedDays.isEmpty))
            )
        }
    }
    
    private func addHabit() {
        switch repeatOption {
        case .never:
            let habit = TimelineItem(
                id: UUID(),
                title: title,
                type: .habit,
                date: Date(),
                isCompleted: false,
                notes: notes.isEmpty ? nil : notes
            )
            viewModel.addItem(habit)
            
        case .daily:
            // Add habits for the next 30 days
            for dayOffset in 0..<30 {
                let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
                let habit = TimelineItem(
                    id: UUID(),
                    title: title,
                    type: .habit,
                    date: date,
                    isCompleted: false,
                    notes: notes.isEmpty ? nil : notes
                )
                viewModel.addItem(habit)
            }
            
        case .weekly:
            // Add habits for selected days for the next 12 weeks
            let calendar = Calendar.current
            var currentDate = Date()
            let endDate = calendar.date(byAdding: .weekOfYear, value: 12, to: currentDate) ?? Date()
            
            while currentDate <= endDate {
                let weekday = calendar.component(.weekday, from: currentDate)
                if let day = Weekday(rawValue: weekday), selectedDays.contains(day) {
                    let habit = TimelineItem(
                        id: UUID(),
                        title: title,
                        type: .habit,
                        date: currentDate,
                        isCompleted: false,
                        notes: notes.isEmpty ? nil : notes
                    )
                    viewModel.addItem(habit)
                }
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? Date()
            }
        }
    }
}

#Preview {
    AddHabitView(
        viewModel: PlannerViewModel(),
        isPresented: .constant(true)
    )
} 