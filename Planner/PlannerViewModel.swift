import Foundation
import EventKit
import UserNotifications
import SwiftUI
import HealthKit

class PlannerViewModel: ObservableObject {
    @Published var items: [TimelineItem] = []
    @Published var calendarAccessStatus: EKAuthorizationStatus = .notDetermined
    @Published var showCalendarPrompt = false
    @Published var showSettingsPrompt = false
    @Published var permissionErrorMessage: String?
    @Published var showCompletedItems = true
    @Published var groupByType = false
    @Published var favoriteSports: [FavoriteSport] = [] {
        didSet { saveFavoriteSports() }
    }
    @Published var showSportsSchedule: Bool = false {
        didSet { UserDefaults.standard.set(showSportsSchedule, forKey: "showSportsSchedule") }
    }
    @Published var healthKitAuthorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var steps: Double = 0
    @Published var activeEnergy: Double = 0
    @Published var showHealthData: Bool = false {
        didSet {
            UserDefaults.standard.set(showHealthData, forKey: "showHealthData")
            if showHealthData {
                // When toggled on, check authorization and fetch data if permitted.
                Task {
                    await checkInitialHealthKitStatus()
                }
            } else {
                // When toggled off, clear the values.
                self.steps = 0
                self.activeEnergy = 0
            }
        }
    }
    
    // Health Goals
    let stepGoal: Double = 10000
    let energyGoal: Double = 500
    
    var eventStore: EKEventStore
    private var hasRequestedCalendarPermission = false
    private var hasRequestedNotificationPermission = false
    private var isInitializingPermissions = false
    private var hasInitializedPermissions = false
    
    let healthKitManager = HealthKitManager()
    
    init() {
        self.eventStore = EKEventStore()
        loadFavoriteSports()
        showSportsSchedule = UserDefaults.standard.bool(forKey: "showSportsSchedule")
        showHealthData = UserDefaults.standard.bool(forKey: "showHealthData")
        
        // Make sure we're not creating a task that might be causing a loop
        Task {
            // Only initialize permissions once
            if !hasInitializedPermissions {
                hasInitializedPermissions = true
                await initializePermissions()
                if calendarAccessStatus == .fullAccess {
                    await syncCalendarEvents()
                }
                if showHealthData {
                    await checkInitialHealthKitStatus()
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    @MainActor
    func addItem(_ item: TimelineItem) {
        items.append(item)
        if item.type == .task {
            scheduleNotification(for: item)
        } else if item.type == .event {
            Task {
                await addEventToCalendar(item)
            }
        }
    }
    
    @MainActor
    func toggleCompletion(for item: TimelineItem) {
        guard let index = items.firstIndex(of: item) else { return }
        // Only allow completing items for today or past dates
        guard !Calendar.current.isDateInFuture(item.date) else { return }
        
        // For habits, create next day's habit if completing today's
        if item.type == .habit && Calendar.current.isDateInToday(item.date) {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let newHabit = TimelineItem(
                id: UUID(),
                title: item.title,
                type: .habit,
                date: tomorrow,
                isCompleted: false,
                notes: item.notes
            )
            items.append(newHabit)
        }
        
        items[index].isCompleted.toggle()
    }
    
    @MainActor
    func removeItem(_ item: TimelineItem) {
        items.removeAll { $0.id == item.id }
        if item.type == .task {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [item.id.uuidString])
        } else if item.type == .event {
            Task {
                await removeEventFromCalendar(item)
            }
        }
    }
    
    @MainActor
    func updateItem(_ item: TimelineItem) {
        guard let index = items.firstIndex(of: item) else { return }
        items[index] = item
        if item.type == .task {
            scheduleNotification(for: item)
        } else if item.type == .event {
            Task {
                await updateEventInCalendar(item)
            }
        }
    }
    
    func timelineItems(for date: Date) -> [TimelineItem] {
        let filtered = items.filter { item in
            let sameDay = Calendar.current.isDate(item.date, inSameDayAs: date)
            return showCompletedItems ? sameDay : (sameDay && !item.isCompleted)
        }
        
        if groupByType {
            return filtered.sorted { item1, item2 in
                if item1.type == item2.type {
                    return item1.time ?? item1.date < item2.time ?? item2.date
                }
                return item1.type.rawValue < item2.type.rawValue
            }
        } else {
            return filtered.sorted { item1, item2 in
                item1.time ?? item1.date < item2.time ?? item2.date
            }
        }
    }
    
    @MainActor
    private static var hasRequestedNotificationPermissionGlobally = false

    @MainActor
    func requestNotificationPermission() async {
        // Use the class-level static property instead of a local static variable
        if !PlannerViewModel.hasRequestedNotificationPermissionGlobally {
            PlannerViewModel.hasRequestedNotificationPermissionGlobally = true
            self.hasRequestedNotificationPermission = true
            
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                print("Notification permission \(granted ? "granted" : "denied")")
            } catch {
                print("Error requesting notification permission: \(error)")
            }
        } else {
            print("Notification permission already requested this session")
        }
    }
    
    // MARK: - Public Convenience Methods for Testing
    @MainActor
    func addEvent(title: String, startDate: Date, endDate: Date) {
        let event = TimelineItem(
            id: UUID(),
            title: title,
            type: .event,
            date: startDate,
            isCompleted: false,
            notes: nil,
            time: startDate,
            endDate: endDate
        )
        addItem(event)
    }
    
    @MainActor
    func addTask(title: String, date: Date) {
        let task = TimelineItem(
            id: UUID(),
            title: title,
            type: .task,
            date: date,
            isCompleted: false,
            notes: nil,
            time: date
        )
        addItem(task)
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func initializePermissions() async {
        // Check if we're already initializing to prevent recursive calls
        if isInitializingPermissions {
            print("Already initializing permissions, breaking potential loop")
            return
        }
        
        isInitializingPermissions = true
        
        // Request permissions
        await requestNotificationPermission()
        await checkInitialCalendarStatus()
        
        isInitializingPermissions = false
    }
    
    @MainActor
    func scheduleNotification(for item: TimelineItem) {
        let content = UNMutableNotificationContent()
        content.title = item.type.rawValue
        content.body = item.title
        content.sound = .default
        
        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: item.time ?? item.date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: item.id.uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    private func saveFavoriteSports() {
        if let data = try? JSONEncoder().encode(favoriteSports) {
            UserDefaults.standard.set(data, forKey: "favoriteSports")
        }
    }
    
    private func loadFavoriteSports() {
        if let data = UserDefaults.standard.data(forKey: "favoriteSports"),
           let sports = try? JSONDecoder().decode([FavoriteSport].self, from: data) {
            favoriteSports = sports
        }
    }
}

extension Calendar {
    func isDateInFuture(_ date: Date) -> Bool {
        let today = startOfDay(for: Date())
        let compareDate = startOfDay(for: date)
        return compareDate > today
    }
}