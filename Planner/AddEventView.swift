//
//  AddEventView.swift
//  Planner
//
//  Created by Pratham Shetty on 28/05/25.
//


import SwiftUI
import EventKit

struct AddEventView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PlannerViewModel()
    @Binding var isPresented: Bool
    
    @State private var title = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var notes = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Event Title", text: $title)
                        .font(.body)
                    
                    DatePicker("Starts", selection: $startDate)
                    DatePicker("Ends", selection: $endDate)
                    
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Notes (optional)")
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $notes)
                            .frame(height: 100)
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await addEvent()
                            isPresented = false
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
    
    private func addEvent() async {
        let event = EKEvent(eventStore: viewModel.eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.calendar = viewModel.eventStore.defaultCalendarForNewEvents
        
        do {
            try viewModel.eventStore.save(event, span: .thisEvent)
            await viewModel.loadEvents()
        } catch {
            print("Error saving event: \(error.localizedDescription)")
        }
    }
}

#Preview {
    AddEventView(isPresented: .constant(true))
}
