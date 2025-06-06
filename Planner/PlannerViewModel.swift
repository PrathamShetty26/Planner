import Foundation
import EventKit
import UserNotifications
import SwiftUI

class PlannerViewModel: ObservableObject {
    @Published private(set) var items: [TimelineItem] = []
    @Published var calendarAccessStatus: EKAuthorizationStatus = .notDetermined
    @Published var showCalendarPrompt = false
    @Published var showSettingsPrompt = false
    @Published var permissionErrorMessage: String?
    @Published var showCompletedItems = true
    @Published var groupByType = false
    
    private var eventStore: EKEventStore
    private var hasRequestedCalendarPermission = false
    private var hasRequestedNotificationPermission = false
    
    init() {
        self.eventStore = EKEventStore()
        Task {
            await initializePermissions()
            if calendarAccessStatus == .authorized || calendarAccessStatus == .fullAccess {
                await syncCalendarEvents()
            }
        }
    }
    
    // MARK: - Public Methods
    
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
    func requestCalendarPermission() async {
        if #available(iOS 17.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                if granted {
                    self.calendarAccessStatus = .fullAccess
                    self.permissionErrorMessage = nil
                    self.eventStore = EKEventStore()
                    await syncCalendarEvents()
                } else {
                    self.calendarAccessStatus = .denied
                    self.showSettingsPrompt = true
                    self.permissionErrorMessage = "Please enable Calendar access in Settings"
                }
            } catch {
                self.calendarAccessStatus = .denied
                self.showSettingsPrompt = true
                self.permissionErrorMessage = "Failed to request calendar access: \(error.localizedDescription)"
            }
        } else {
            let status = EKEventStore.authorizationStatus(for: .event)
            if status == .notDetermined {
                let granted = await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, error in
                        continuation.resume(returning: granted)
                    }
                }
                
                if granted {
                    self.calendarAccessStatus = .authorized
                    self.permissionErrorMessage = nil
                    self.eventStore = EKEventStore()
                    await syncCalendarEvents()
                } else {
                    self.calendarAccessStatus = .denied
                    self.showSettingsPrompt = true
                    self.permissionErrorMessage = "Please enable Calendar access in Settings"
                }
            }
        }
    }
    
    @MainActor
    func requestNotificationPermission() async {
        if !hasRequestedNotificationPermission {
            hasRequestedNotificationPermission = true
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                print("Notification permission \(granted ? "granted" : "denied")")
            } catch {
                print("Error requesting notification permission: \(error)")
            }
        }
    }
    
    // MARK: - Private Methods
    
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
    
    // MARK: - Calendar Sync
    @MainActor
    private func syncCalendarEvents() async {
        guard calendarAccessStatus == .authorized || calendarAccessStatus == .fullAccess else { return }
        
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let endDate = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        // Convert EKEvents to TimelineItems
        let newItems = events.map { event in
            TimelineItem(
                id: UUID(),
                title: event.title,
                type: .event,
                date: event.startDate,
                isCompleted: false,
                notes: event.notes,
                time: event.startDate,
                endDate: event.endDate
            )
        }
        
        // Add only events that don't already exist
        let existingTitles = Set(items.filter { $0.type == .event }.map { $0.title })
        items.append(contentsOf: newItems.filter { !existingTitles.contains($0.title) })
    }
    
    @MainActor
    private func addEventToCalendar(_ item: TimelineItem) async {
        guard calendarAccessStatus == .authorized || calendarAccessStatus == .fullAccess else { return }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = item.title
        event.notes = item.notes
        event.startDate = item.time ?? item.date
        event.endDate = item.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: item.time ?? item.date) ?? item.date
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            print("Error saving event to calendar: \(error)")
        }
    }
    
    @MainActor
    private func updateEventInCalendar(_ item: TimelineItem) async {
        guard calendarAccessStatus == .authorized || calendarAccessStatus == .fullAccess else { return }
        
        // Find the event by title (since we don't store EKEvent identifiers)
        let startDate = Calendar.current.date(byAdding: .day, value: -1, to: item.date) ?? item.date
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: item.date) ?? item.date
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        if let event = events.first(where: { $0.title == item.title }) {
            event.title = item.title
            event.notes = item.notes
            event.startDate = item.time ?? item.date
            event.endDate = item.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: item.time ?? item.date) ?? item.date
            
            do {
                try eventStore.save(event, span: .thisEvent)
            } catch {
                print("Error updating event in calendar: \(error)")
            }
        }
    }
    
    @MainActor
    private func removeEventFromCalendar(_ item: TimelineItem) async {
        guard calendarAccessStatus == .authorized || calendarAccessStatus == .fullAccess else { return }
        
        // Find the event by title
        let startDate = Calendar.current.date(byAdding: .day, value: -1, to: item.date) ?? item.date
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: item.date) ?? item.date
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        if let event = events.first(where: { $0.title == item.title }) {
            do {
                try eventStore.remove(event, span: .thisEvent)
            } catch {
                print("Error removing event from calendar: \(error)")
            }
        }
    }
    
    private func scheduleNotification(for item: TimelineItem) {
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
}

extension Calendar {
    func isDateInFuture(_ date: Date) -> Bool {
        let today = startOfDay(for: Date())
        let compareDate = startOfDay(for: date)
        return compareDate > today
    }
}
