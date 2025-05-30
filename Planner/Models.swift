//
//  Model.swift
//  Planner
//
//  Created by Pratham Shetty on 28/05/25.
//
import Foundation

enum PlannerModels {
    struct Task: Identifiable {
        let id: UUID
        let title: String
        let date: Date
        var isCompleted: Bool
    }

    struct Habit: Identifiable {
        let id: UUID
        let title: String
        let frequency: String
        var isCompletedToday: Bool
    }
}

enum TimelineItemType {
    case event
    case task
    case habit
}

struct TimelineItem: Identifiable {
    let id: String
    let title: String
    let date: Date
    let type: TimelineItemType
    let isCompleted: Bool
}
