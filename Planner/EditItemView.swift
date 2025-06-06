import SwiftUI

struct EditItemView: View {
    @ObservedObject var viewModel: PlannerViewModel
    let item: TimelineItem
    @Binding var isPresented: Bool
    
    @State private var title: String
    @State private var notes: String
    @State private var hasTime: Bool
    @State private var time: Date
    
    init(viewModel: PlannerViewModel, item: TimelineItem, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self.item = item
        self._isPresented = isPresented
        self._title = State(initialValue: item.title)
        self._notes = State(initialValue: item.notes ?? "")
        self._hasTime = State(initialValue: item.time != nil)
        self._time = State(initialValue: item.time ?? Date())
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes)
                }
                
                if item.type == .event {
                    Section {
                        Toggle("Has Time", isOn: $hasTime)
                        if hasTime {
                            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        }
                    }
                }
            }
            .navigationTitle("Edit \(item.type.rawValue)")
            .navigationBarItems(
                leading: Button("Cancel") { isPresented = false },
                trailing: Button("Save") {
                    var updatedItem = item
                    updatedItem.title = title
                    updatedItem.notes = notes.isEmpty ? nil : notes
                    updatedItem.time = hasTime ? time : nil
                    viewModel.updateItem(updatedItem)
                    isPresented = false
                }
                .disabled(title.isEmpty)
            )
        }
    }
} 