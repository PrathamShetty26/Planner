//
//  AddTaskView.swift
//  Planner
//
//  Created by Pratham Shetty on 28/05/25.
//


import SwiftUI

struct AddTaskView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @State private var title = ""
    @State private var date = Date()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Task Title", text: $title)
                DatePicker("Due Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
            }
            .navigationTitle("Add Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !title.isEmpty {
                            viewModel.addTask(title: title, date: date)
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}
