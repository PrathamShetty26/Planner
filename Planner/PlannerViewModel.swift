import Foundation
import EventKit
import UserNotifications

class PlannerViewModel: ObservableObject {
    @Published var tasks: [PlannerModels.Task] = []
    @Published var habits: [PlannerModels.Habit] = []
    @Published var events: [EKEvent] = []
    @Published var permissionErrorMessage: String?
    @Published var calendarAccessStatus: EKAuthorizationStatus = .notDetermined
    @Published var showCalendarPrompt = false
    @Published var showSettingsPrompt = false
    
    private var eventStore: EKEventStore
    private var hasRequestedCalendarPermission = false
    private var hasRequestedNotificationPermission = false

    init() {
        self.eventStore = EKEventStore()
        Task {
            await initializePermissions()
        }
    }
    
    @MainActor
    private func initializePermissions() async {
        await requestNotificationPermission()
        await checkInitialCalendarStatus()
    }
    
    @MainActor
    private func checkInitialCalendarStatus() async {
        if #available(iOS 17.0, *) {
            calendarAccessStatus = EKEventStore.authorizationStatus(for: .event)
        } else {
            calendarAccessStatus = EKEventStore.authorizationStatus(for: .event)
        }
        
        if calendarAccessStatus == .notDetermined {
            showCalendarPrompt = true
        }
    }

    @MainActor
    private func requestNotificationPermission() async {
        if !hasRequestedNotificationPermission {
            hasRequestedNotificationPermission = true
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    print("Notification permission granted")
                } else {
                    print("Notification permission denied")
                }
            } catch {
                print("Error requesting notification permission: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func requestCalendarPermission() async {
        if #available(iOS 17.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            print("iOS 17+ Calendar permission status before request: \(status.rawValue)")
            
            do {
                print("Attempting to request full calendar access...")
                let granted = try await eventStore.requestFullAccessToEvents()
                print("Calendar access request result: \(granted)")
                
                // Check status again after request
                let newStatus = EKEventStore.authorizationStatus(for: .event)
                print("Calendar status after request: \(newStatus.rawValue)")
                
                if granted {
                    print("Calendar permission granted successfully")
                    self.calendarAccessStatus = .fullAccess
                    self.permissionErrorMessage = nil
                    // Reinitialize event store after permission granted
                    self.eventStore = EKEventStore()
                    await self.fetchCalendarEvents()
                } else {
                    print("Calendar access denied by user")
                    self.calendarAccessStatus = .denied
                    self.showSettingsPrompt = true
                    self.permissionErrorMessage = "Please enable Calendar access in Settings > Privacy & Security > Calendars"
                }
            } catch {
                print("Error requesting calendar access: \(error)")
                print("Detailed error: \(error.localizedDescription)")
                self.calendarAccessStatus = .denied
                self.showSettingsPrompt = true
                self.permissionErrorMessage = "Failed to request calendar access: \(error.localizedDescription)"
            }
        } else {
            // Pre-iOS 17 handling
            let status = EKEventStore.authorizationStatus(for: .event)
            print("Pre-iOS 17 Calendar permission status: \(status.rawValue)")
            
            if status == .notDetermined {
                print("Pre-iOS 17: Requesting calendar access...")
                let granted = await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error = error {
                            print("Error in pre-iOS 17 request: \(error)")
                        }
                        continuation.resume(returning: granted)
                    }
                }
                
                // Check status after request
                let newStatus = EKEventStore.authorizationStatus(for: .event)
                print("Pre-iOS 17 status after request: \(newStatus.rawValue)")
                
                if granted {
                    print("Calendar permission granted successfully")
                    self.calendarAccessStatus = .authorized
                    self.permissionErrorMessage = nil
                    // Reinitialize event store after permission granted
                    self.eventStore = EKEventStore()
                    await self.fetchCalendarEvents()
                } else {
                    print("Calendar access denied by user")
                    self.calendarAccessStatus = .denied
                    self.showSettingsPrompt = true
                    self.permissionErrorMessage = "Please enable Calendar access in Settings > Privacy & Security > Calendars"
                }
            } else if status != .authorized {
                print("Calendar permission already determined: \(status)")
                self.calendarAccessStatus = status
                self.showSettingsPrompt = true
                self.permissionErrorMessage = "Please enable Calendar access in Settings > Privacy & Security > Calendars"
            }
        }
    }

    @MainActor
    private func fetchCalendarEvents() async {
        if #available(iOS 17.0, *) {
            guard calendarAccessStatus == .fullAccess else {
                print("Cannot fetch events - no full access")
                return
            }
        } else {
            guard calendarAccessStatus == .authorized else {
                print("Cannot fetch events - no authorization")
                return
            }
        }
        
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.startOfDay(for: now)
        let endDate = calendar.date(byAdding: .day, value: 7, to: startDate)!
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let fetchedEvents = eventStore.events(matching: predicate)
        self.events = fetchedEvents
        print("Fetched \(fetchedEvents.count) events")
    }

    func addTask(title: String, date: Date) {
        let newTask = PlannerModels.Task(id: UUID(), title: title, date: date, isCompleted: false)
        tasks.append(newTask)
        scheduleNotification(for: newTask)
    }

    func addHabit(title: String, frequency: String) {
        let newHabit = PlannerModels.Habit(id: UUID(), title: title, frequency: frequency, isCompletedToday: false)
        habits.append(newHabit)
    }

    @MainActor
    func addEvent(title: String, startDate: Date, endDate: Date) async {
        let status = EKEventStore.authorizationStatus(for: .event)
        print("Adding event, current permission status: \(status.rawValue) (\(status))")
        
        if status == .fullAccess {
            let event = EKEvent(eventStore: self.eventStore)
            event.title = title
            event.startDate = startDate
            event.endDate = endDate
            event.calendar = self.eventStore.defaultCalendarForNewEvents
            
            do {
                try self.eventStore.save(event, span: .thisEvent)
                self.events.append(event)
                print("Event saved successfully: \(event.eventIdentifier ?? "")")
                self.permissionErrorMessage = nil
            } catch {
                print("Error saving event: \(error.localizedDescription)")
                self.permissionErrorMessage = "Failed to save event: \(error.localizedDescription)"
            }
        } else {
            await requestCalendarPermission()
        }
    }

    func toggleHabitCompletion(habit: PlannerModels.Habit) {
        if let index = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[index].isCompletedToday.toggle()
            print("Toggled habit: \(habit.title), isCompleted: \(habit.isCompletedToday)")
        }
    }

    func scheduleNotification(for task: PlannerModels.Task) {
        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = "Don't forget: \(task.title)"
        content.sound = .default

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: task.date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("Notification scheduled for task: \(task.title)")
            }
        }
    }

}
