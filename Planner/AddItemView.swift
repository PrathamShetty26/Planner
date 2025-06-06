import SwiftUI
import Foundation

struct AddItemView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @Binding var isPresented: Bool
    @State private var selectedType: ItemType = .task
    @State private var title = ""
    @State private var date = Date()
    @State private var addToCalendar = false
    @State private var addTime = false
    @State private var makeRecurring = false
    @State private var addLocation = false
    @State private var location = ""
    @State private var time = Date()
    @State private var isEveryDay = false
    @State private var selectedDays: Set<Weekday> = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Type Selector
                Picker("Type", selection: $selectedType) {
                    ForEach(ItemType.allCases, id: \.self) { type in
                        Text(type.rawValue)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                Form {
                    Section {
                        TextField("Title", text: $title)
                    }
                    
                    if selectedType == .task {
                        Section {
                            DatePicker("Date", selection: $date, displayedComponents: [.date])
                        }
                    }
                    
                    Section(header: Text("Options")) {
                        if selectedType == .event {
                            Button(action: { addToCalendar.toggle() }) {
                                HStack {
                                    Image(systemName: "calendar")
                                    Text("Add to calendar")
                                    Spacer()
                                    if addToCalendar {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        if selectedType != .habit {
                            Button(action: { addTime.toggle() }) {
                                HStack {
                                    Image(systemName: "clock")
                                    Text("Add time")
                                    Spacer()
                                    if addTime {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        if selectedType == .event {
                            Button(action: { makeRecurring.toggle() }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Make recurring")
                                    Spacer()
                                    if makeRecurring {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            Button(action: { addLocation.toggle() }) {
                                HStack {
                                    Image(systemName: "location")
                                    Text("Add location")
                                    Spacer()
                                    if addLocation {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        if selectedType == .habit {
                            Button(action: { isEveryDay.toggle() }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Every day")
                                    Spacer()
                                    if isEveryDay {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            if !isEveryDay {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Weekday.allCases, id: \.self) { day in
                                            Button(action: {
                                                if selectedDays.contains(day) {
                                                    selectedDays.remove(day)
                                                } else {
                                                    selectedDays.insert(day)
                                                }
                                            }) {
                                                Text(day.shortName)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(
                                                        selectedDays.contains(day) ?
                                                        Color.accentColor :
                                                        Color(UIColor.systemGray5)
                                                    )
                                                    .foregroundColor(
                                                        selectedDays.contains(day) ?
                                                        .white :
                                                        .primary
                                                    )
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            
                            Button(action: { addTime.toggle() }) {
                                HStack {
                                    Image(systemName: "clock")
                                    Text("Add time")
                                    Spacer()
                                    if addTime {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    
                    if addTime {
                        Section(header: Text("Time")) {
                            DatePicker("Time", selection: $time, displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.wheel)
                        }
                    }
                    
                    if addLocation {
                        Section(header: Text("Location")) {
                            TextField("Location", text: $location)
                        }
                    }
                }
            }
            .navigationTitle("New \(selectedType.rawValue)")
            .navigationBarItems(
                leading: Button("Cancel") { isPresented = false },
                trailing: Button("Add") {
                    addItem()
                    isPresented = false
                }
                .disabled(title.isEmpty || (!isEveryDay && selectedType == .habit && selectedDays.isEmpty))
            )
        }
    }
    
    private func addItem() {
        switch selectedType {
        case .habit:
            if isEveryDay {
                // Add habits for the next 30 days
                for dayOffset in 0..<30 {
                    let habitDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: date) ?? date
                    let habit = TimelineItem(
                        id: UUID(),
                        title: title,
                        type: .habit,
                        date: habitDate,
                        isCompleted: false,
                        notes: nil,
                        time: addTime ? time : nil
                    )
                    viewModel.addItem(habit)
                }
            } else {
                // Add habits for selected days for the next 12 weeks
                let calendar = Calendar.current
                var currentDate = date
                let endDate = calendar.date(byAdding: .weekOfYear, value: 12, to: currentDate) ?? date
                
                while currentDate <= endDate {
                    let weekday = calendar.component(.weekday, from: currentDate)
                    if let day = Weekday(rawValue: weekday), selectedDays.contains(day) {
                        let habit = TimelineItem(
                            id: UUID(),
                            title: title,
                            type: .habit,
                            date: currentDate,
                            isCompleted: false,
                            notes: nil,
                            time: addTime ? time : nil
                        )
                        viewModel.addItem(habit)
                    }
                    currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? date
                }
            }
            
        default:
            let item = TimelineItem(
                id: UUID(),
                title: title,
                type: selectedType,
                date: date,
                isCompleted: false,
                notes: nil,
                time: addTime ? time : nil,
                location: addLocation ? location : nil
            )
            viewModel.addItem(item)
        }
    }
}

#Preview {
    AddItemView(viewModel: PlannerViewModel(), isPresented: .constant(true))
} 