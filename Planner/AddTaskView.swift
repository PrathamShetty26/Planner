//
//  AddTaskView.swift
//  Planner
//
//  Created by Pratham Shetty on 28/05/25.
//


import SwiftUI

struct AddTaskView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @Binding var isPresented: Bool
    
    @State private var title = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var time = Date()
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes)
                }
                
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    DatePicker("Time", selection: $time, displayedComponents: [.hourAndMinute])
                }
            }
            .navigationTitle("New Task")
            .navigationBarItems(
                leading: Button("Cancel") { isPresented = false },
                trailing: Button("Add") {
                    let task = TimelineItem(
                        id: UUID(),
                        title: title,
                        type: .task,
                        date: date,
                        isCompleted: false,
                        notes: notes.isEmpty ? nil : notes,
                        time: time
                    )
                    viewModel.addItem(task)
                    isPresented = false
                }
                .disabled(title.isEmpty)
            )
        }
    }
}

#Preview {
    AddTaskView(viewModel: PlannerViewModel(), isPresented: .constant(true))
}
