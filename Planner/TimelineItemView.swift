//
//  TimelineItemView.swift
//  Planner
//
//  Created by Pratham Shetty on 28/05/25.
//


import SwiftUI

struct TimelineItemView: View {
    let item: TimelineItem
    var endDate: Date?
    
    @State private var isCompleted: Bool
    @StateObject private var viewModel = PlannerViewModel()
    
    init(item: TimelineItem, endDate: Date? = nil) {
        self.item = item
        self.endDate = endDate
        _isCompleted = State(initialValue: item.isCompleted)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Time column
            VStack(alignment: .trailing) {
                Text(item.date.formatted(.dateTime.hour().minute()))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                if let endDate = endDate {
                    Text(endDate.formatted(.dateTime.hour().minute()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 50)
            
            // Vertical line with dot
            VStack(spacing: 0) {
                Circle()
                    .fill(itemColor)
                    .frame(width: 12, height: 12)
                
                Rectangle()
                    .fill(itemColor.opacity(0.2))
                    .frame(width: 2)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .foregroundColor(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted)
                
                if item.type == .habit {
                    Text(habitFrequencyText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Completion checkbox for tasks and habits
            if item.type != .event {
                Button(action: toggleCompletion) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isCompleted ? itemColor : .secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    private var itemColor: Color {
        switch item.type {
        case .event:
            return .blue
        case .task:
            return .green
        case .habit:
            return .orange
        }
    }
    
    private var habitFrequencyText: String {
        "Daily" // You can expand this based on your habit frequency model
    }
    
    private func toggleCompletion() {
        withAnimation {
            isCompleted.toggle()
            // Update the completion status in your view model here
            if item.type == .task {
                viewModel.toggleTaskCompletion(taskId: item.id)
            } else if item.type == .habit {
                viewModel.toggleHabitCompletion(habitId: item.id)
            }
        }
    }
}

#Preview {
    TimelineItemView(
        item: TimelineItem(
            id: "1",
            title: "Sample Item",
            date: Date(),
            type: .task,
            isCompleted: false
        )
    )
    .padding()
}
