//
//  Model.swift
//  Planner
//
//  Created by Pratham Shetty on 28/05/25.
//
import Foundation
import EventKit

// MARK: - Core Models
public struct TimelineItem: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var type: ItemType
    public var date: Date
    public var isCompleted: Bool
    public var notes: String?
    public var time: Date?
    public var endDate: Date?
    public var location: String?
    
    public static func == (lhs: TimelineItem, rhs: TimelineItem) -> Bool {
        lhs.id == rhs.id
    }
}

public enum ItemType: String, CaseIterable {
    case habit = "Habit"
    case task = "Task"
    case event = "Event"
}

public enum RepeatOption: String, CaseIterable {
    case never = "Never"
    case daily = "Every day"
    case weekly = "Custom"
    
    public var systemImage: String {
        switch self {
        case .never: return "xmark.circle"
        case .daily: return "repeat"
        case .weekly: return "calendar"
        }
    }
}

public enum Weekday: Int, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    
    public var shortName: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thur"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }
}

// Keep only one definition of each model
// If these are already defined elsewhere in the file, remove these duplicates
public struct FavoriteSport: Codable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public var teams: [FavoriteTeam]
}

public struct FavoriteTeam: Codable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
}
