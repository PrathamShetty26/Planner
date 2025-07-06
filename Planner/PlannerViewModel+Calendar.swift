import Foundation
import EventKit

extension PlannerViewModel {

    // MARK: - Calendar Permissions & Sync

    @MainActor
    func requestCalendarPermission() async {
        if #available(iOS 17.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                if granted {
                    self.calendarAccessStatus = .fullAccess
                    self.permissionErrorMessage = nil
                    self.eventStore = EKEventStore() // Re-initialize after getting permission
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
            // Fallback for iOS 16 and below
            let granted = await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            
            if granted {
                self.calendarAccessStatus = .authorized
                self.permissionErrorMessage = nil
                self.eventStore = EKEventStore() // Re-initialize after getting permission
                await syncCalendarEvents()
            } else {
                self.calendarAccessStatus = .denied
                self.showSettingsPrompt = true
                self.permissionErrorMessage = "Please enable Calendar access in Settings"
            }
        }
    }

    @MainActor
    func checkInitialCalendarStatus() async {
        calendarAccessStatus = EKEventStore.authorizationStatus(for: .event)
        
        if calendarAccessStatus == .notDetermined {
            showCalendarPrompt = true
        }
    }

    @MainActor
    func syncCalendarEvents() async {
        guard calendarAccessStatus == .authorized || calendarAccessStatus == .fullAccess else { return }
        
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let endDate = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        // Convert EKEvents to TimelineItems, storing the unique identifier
        let newItems = events.map { event -> TimelineItem in
            // We will add `calendarEventIdentifier` to the TimelineItem struct in the next step
            return TimelineItem(
                id: UUID(),
                title: event.title,
                type: .event,
                date: event.startDate,
                isCompleted: false,
                notes: event.notes,
                time: event.startDate,
                endDate: event.endDate
                // calendarEventIdentifier: event.eventIdentifier // This will be added
            )
        }
        
        // A more robust sync: remove old calendar events and add the new ones.
        // This prevents duplicates if an event is changed in the Calendar app.
        items.removeAll { $0.type == .event } // A simplified removal; we'll make this more robust
        items.append(contentsOf: newItems)
    }

    @MainActor
    func addEventToCalendar(_ item: TimelineItem) async {
        guard let time = item.time, let itemEndDate = item.endDate else { return }
        
        let accessGranted = calendarAccessStatus == .authorized || calendarAccessStatus == .fullAccess
        guard accessGranted else { return }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = item.title
        event.notes = item.notes
        event.startDate = time
        event.endDate = itemEndDate
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)
            // After saving, we would update our item with the real calendar identifier
        } catch {
            print("Error saving event to calendar: \(error)")
        }
    }

    @MainActor
    func updateEventInCalendar(_ item: TimelineItem) async {
        // This logic will be updated to use the event identifier
        // For now, it mirrors the old, fragile title-based search
        let predicate = eventStore.predicateForEvents(withStart: item.date, end: item.endDate ?? item.date, calendars: nil)
        guard let event = eventStore.events(matching: predicate).first(where: { $0.title == item.title }) else {
            await addEventToCalendar(item) // If not found, create it
            return
        }
        
        event.title = item.title
        event.notes = item.notes
        event.startDate = item.time ?? item.date
        event.endDate = item.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: item.time ?? item.date)
        
        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            print("Error updating event in calendar: \(error)")
        }
    }

    @MainActor
    func removeEventFromCalendar(_ item: TimelineItem) async {
        // This logic will also be updated to use the event identifier
        let predicate = eventStore.predicateForEvents(withStart: item.date, end: item.endDate ?? item.date, calendars: nil)
        guard let event = eventStore.events(matching: predicate).first(where: { $0.title == item.title }) else { return }
        
        do {
            try eventStore.remove(event, span: .thisEvent)
        } catch {
            print("Error removing event from calendar: \(error)")
        }
    }
}