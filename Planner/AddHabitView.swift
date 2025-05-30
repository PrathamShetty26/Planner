//
//  AddHabitView.swift
//  Planner
//
//  Created by Pratham Shetty on 28/05/25.
//

import SwiftUI

struct AddHabitView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @State private var title = ""
    @State private var frequency = "Daily"
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                TextField("Habit Title", text: $title)
                Picker("Frequency", selection: $frequency) {
                    Text("Daily").tag("Daily")
                    Text("Weekly").tag("Weekly")
                }
            }
            .navigationTitle("Add Habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if !title.isEmpty {
                        viewModel.addHabit(title: title, frequency: frequency)
                        dismiss()
                    }
                }.disabled(title.isEmpty) }
            }
        }
    }
}
