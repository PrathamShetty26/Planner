import Foundation
import EventKit

extension PlannerViewModel {

    // MARK: - Calendar Permissions & Sync

    @MainActor
    func requestCalendarPermission() async {
        // For iOS 17+, this single call requests access for both events and reminders
        // if the appropriate usage descriptions are in Info.plist.
        if #available(iOS 17.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                if granted {
                    self.calendarAccessStatus = .fullAccess
                    self.permissionErrorMessage = nil
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
        
        // The event fetching can block the main thread, causing a freeze.
        // We perform this work in a detached, background task to keep the UI responsive.
        let events = await Task.detached {
            let predicate = self.eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
            return self.eventStore.events(matching: predicate)
        }.value
        
        // Safely unwrap the optional 'events' array and convert to TimelineItems
        let newItems = (events ?? []).map { event -> TimelineItem in
            return TimelineItem(
                id: UUID(),
                title: event.title,
                type: .event,
                date: event.startDate,
                isCompleted: false,
                notes: event.notes,
                time: event.startDate,
                endDate: event.endDate,
                calendarItemIdentifier: event.eventIdentifier // Link to the original EKEvent
            )
        }
        
        // A more robust sync: remove old calendar events and add the new ones.
        items.removeAll { $0.type == .event && $0.calendarItemIdentifier != nil }
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
            // After saving, update our local item with the real calendar identifier
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].calendarItemIdentifier = event.eventIdentifier
            }
        } catch {
            print("Error saving event to calendar: \(error.localizedDescription)")
        }
    }

    @MainActor
    func updateEventInCalendar(_ item: TimelineItem) async {
        // Use the unique identifier to find the exact event to update.
        guard let identifier = item.calendarItemIdentifier,
              let event = eventStore.event(withIdentifier: identifier) else {
            // If we can't find it by ID, it might be a new item created in the app.
            await addEventToCalendar(item)
            return
        }
        
        event.title = item.title
        event.notes = item.notes
        event.startDate = item.time ?? item.date
        event.endDate = item.endDate ?? item.time ?? item.date
        
        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            print("Error updating event in calendar: \(error.localizedDescription)")
        }
    }

    @MainActor
    func removeEventFromCalendar(_ item: TimelineItem) async {
        // Use the unique identifier to find the exact event to remove.
        guard let identifier = item.calendarItemIdentifier,
              let event = eventStore.event(withIdentifier: identifier) else { return }
        
        do {
            try eventStore.remove(event, span: .thisEvent)
        } catch {
            print("Error removing event from calendar: \(error.localizedDescription)")
        }
    }
}
