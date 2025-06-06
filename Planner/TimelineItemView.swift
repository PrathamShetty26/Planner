//
//  TimelineItemView.swift
//  Planner
//
//  Created by Pratham Shetty on 28/05/25.
//


import SwiftUI

struct TimelineItemView: View {
    @ObservedObject var viewModel: PlannerViewModel
    let item: TimelineItem
    @State private var showingEditSheet = false
    
    var body: some View {
        HStack {
            Circle()
                .fill(itemColor)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 17, weight: .medium))
                    .strikethrough(item.isCompleted)
                
                if let notes = item.notes {
                    Text(notes)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                if item.type == .event {
                    Text("All day")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            if item.type == .task, let time = item.time {
                Text(time.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            if !Calendar.current.isDateInFuture(item.date) {
                Button(action: { viewModel.toggleCompletion(for: item) }) {
                    Label(item.isCompleted ? "Mark Incomplete" : "Mark Complete", 
                          systemImage: item.isCompleted ? "xmark.circle" : "checkmark.circle")
                }
            }
            
            Button(action: { showingEditSheet = true }) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive, action: { viewModel.removeItem(item) }) {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditItemView(viewModel: viewModel, item: item, isPresented: $showingEditSheet)
        }
    }
    
    private var itemColor: Color {
        switch item.type {
        case .habit: return .blue
        case .task: return .orange
        case .event: return .purple
        }
    }
}

struct TimelineItemView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TimelineItemView(
                viewModel: PlannerViewModel(),
                item: TimelineItem(
                    id: UUID(),
                    title: "Sample Task",
                    type: .task,
                    date: Date(),
                    isCompleted: false,
                    notes: "Task notes",
                    time: Date()
                )
            )
            
            TimelineItemView(
                viewModel: PlannerViewModel(),
                item: TimelineItem(
                    id: UUID(),
                    title: "Sample Event",
                    type: .event,
                    date: Date(),
                    isCompleted: false,
                    notes: "Event notes"
                )
            )
            
            TimelineItemView(
                viewModel: PlannerViewModel(),
                item: TimelineItem(
                    id: UUID(),
                    title: "Sample Habit",
                    type: .habit,
                    date: Date(),
                    isCompleted: false,
                    notes: "Habit notes"
                )
            )
        }
        .padding()
    }
}
