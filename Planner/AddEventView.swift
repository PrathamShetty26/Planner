import SwiftUI
import EventKit

struct AddEventView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PlannerViewModel
    @Binding var isPresented: Bool
    
    @State private var title = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showCalendarPrompt = false
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes)
                }
                
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                }
                
                if viewModel.calendarAccessStatus == .notDetermined {
                    Section {
                        Button("Sync with Calendar") {
                            showCalendarPrompt = true
                        }
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarItems(
                leading: Button("Cancel") { isPresented = false },
                trailing: Button("Add") {
                    addEvent()
                }
                .disabled(title.isEmpty)
            )
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Calendar Access", isPresented: $showCalendarPrompt) {
                Button("Allow Access") {
                    Task {
                        await viewModel.requestCalendarPermission()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Would you like to sync your events with the calendar?")
            }
        }
    }
    
    private func addEvent() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let event = TimelineItem(
            id: UUID(),
            title: title,
            type: .event,
            date: startOfDay,
            isCompleted: false,
            notes: notes.isEmpty ? nil : notes,
            time: nil,
            endDate: endOfDay
        )
        
        viewModel.addItem(event)
        isPresented = false
    }
}

#Preview {
    AddEventView(
        viewModel: PlannerViewModel(),
        isPresented: .constant(true)
    )
} 