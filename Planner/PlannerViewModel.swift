import Foundation
import EventKit
import UserNotifications
import SwiftUI
import HealthKit

class PlannerViewModel: ObservableObject {
    @Published var items: [TimelineItem] = []
    @Published var calendarAccessStatus: EKAuthorizationStatus = .notDetermined
    @Published var isInitializing = true
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
    @Published var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var healthKitAuthorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var steps: Double = 0
    @Published var activeEnergy: Double = 0
    @Published var showHealthData: Bool = false {
        didSet {
            UserDefaults.standard.set(showHealthData, forKey: "showHealthData")
            // When the user toggles this, we just need to re-check our authorization and fetch.
            // The check function itself will handle clearing values if showHealthData is false or permissions are denied.
            Task {
                await self.checkHealthKitAuthorization()
            }
        }
    }
    
    // This property holds the date the user is currently viewing in the UI.
    // The UI will bind its date selection to this property.
    @Published var currentlyDisplayedDate: Date = Date() {
        didSet { Task { await checkHealthKitAuthorization() } }
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
        // Use the backing property `_propertyName` to set the initial value without triggering the `didSet` observer.
        // This is the correct way to initialize properties that have side effects in their setters.
        self._showSportsSchedule = Published(initialValue: UserDefaults.standard.bool(forKey: "showSportsSchedule"))
        self._showHealthData = Published(initialValue: UserDefaults.standard.bool(forKey: "showHealthData"))
        
        // Make sure we're not creating a task that might be causing a loop
        // By specifying @MainActor, we ensure all code inside this task runs on the main thread.
        Task { @MainActor in
            // Only initialize permissions once
            if !hasInitializedPermissions {
                hasInitializedPermissions = true
                await checkNotificationAuthorization()
                await checkInitialCalendarStatus()
                await checkHealthKitAuthorization()
                if calendarAccessStatus == .fullAccess {
                    await syncCalendarEvents()
                }
                // Signal that the initial setup is complete.
                isInitializing = false
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
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
    
    @MainActor
    public func timelineItems(for date: Date) -> [TimelineItem] {
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
    func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            // After the user responds, update our status.
            await checkNotificationAuthorization()
            print("Notification permission request completed. Granted: \(granted)")
        } catch {
            print("Error requesting notification permission: \(error)")
        }
    }

    /// Checks the current notification authorization status and updates the view model's state.
    @MainActor
    func checkNotificationAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        // This needs to be dispatched to the main actor to avoid publishing changes from a background thread.
        // The function is already @MainActor, so this is safe.
        self.notificationAuthorizationStatus = settings.authorizationStatus
        print("Notification: Initial status is \(settings.authorizationStatus.rawValue)")
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
    
    @objc private func appWillEnterForeground() {
        Task {
            await checkHealthKitAuthorization()
            // Also re-sync calendar events when the app comes to the foreground
            await syncCalendarEvents()
        }
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