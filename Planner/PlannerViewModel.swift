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
    @Published var favoriteSports: [FavoriteSport] = [] {
        didSet { saveFavoriteSports() }
    }
    @Published var showSportsSchedule: Bool = false {
        didSet { UserDefaults.standard.set(showSportsSchedule, forKey: "showSportsSchedule") }
    }
    
    private var eventStore: EKEventStore
    private var hasRequestedCalendarPermission = false
    private var hasRequestedNotificationPermission = false
    
    init() {
        self.eventStore = EKEventStore()
        loadFavoriteSports()
        showSportsSchedule = UserDefaults.standard.bool(forKey: "showSportsSchedule")
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
    
    func timelineItemsWithSports(for date: Date, completion: @escaping ([TimelineItem]) -> Void) {
        let userItems = timelineItems(for: date)
        fetchSportsSchedule(for: date) { sportsItems in
            var all = userItems + sportsItems
            all.sort { (lhs, rhs) -> Bool in
                let lhsTime = lhs.time ?? lhs.date
                let rhsTime = rhs.time ?? rhs.date
                return lhsTime < rhsTime
            }
            completion(all)
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
    
    // MARK: - Sports API
    func fetchSportsSchedule(for date: Date, completion: @escaping ([TimelineItem]) -> Void) {
        guard !favoriteSports.isEmpty && showSportsSchedule else {
            completion([])
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        var allMatches: [TimelineItem] = []
        let group = DispatchGroup()
        
        // For each favorite sport and team
        for sport in favoriteSports {
            for team in sport.teams {
                group.enter()
                
                // Use the API to fetch matches for this team on this date
                let teamName = team.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? team.name
                let urlString = "https://v3.football.api-sports.io/fixtures?team=&date=\(dateString)&search=\(teamName)"
                
                guard let url = URL(string: urlString) else {
                    group.leave()
                    continue
                }
                
                var request = URLRequest(url: url)
                request.setValue("3215f5cdc36a0197b86f6090c7666c2d", forHTTPHeaderField: "x-apisports-key")
                
                URLSession.shared.dataTask(with: request) { data, response, error in
                    defer { group.leave() }
                    
                    guard let data = data, error == nil else { return }
                    
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let response = json["response"] as? [[String: Any]] {
                            
                            for match in response {
                                if let fixture = match["fixture"] as? [String: Any],
                                   let timestamp = fixture["timestamp"] as? TimeInterval,
                                   let teams = match["teams"] as? [String: Any],
                                   let home = teams["home"] as? [String: Any],
                                   let away = teams["away"] as? [String: Any],
                                   let homeName = home["name"] as? String,
                                   let awayName = away["name"] as? String {
                                    
                                    let matchDate = Date(timeIntervalSince1970: timestamp)
                                    let matchTime = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: matchDate),
                                                                             minute: Calendar.current.component(.minute, from: matchDate),
                                                                             second: 0, of: date)
                                    
                                    let item = TimelineItem(
                                        id: UUID(),
                                        title: "\(sport.name): \(homeName) vs \(awayName)",
                                        type: .event,
                                        date: date,
                                        isCompleted: false,
                                        notes: "Sports Match",
                                        time: matchTime,
                                        endDate: Calendar.current.date(byAdding: .hour, value: 2, to: matchTime ?? date),
                                        location: nil
                                    )
                                    
                                    DispatchQueue.main.async {
                                        allMatches.append(item)
                                    }
                                }
                            }
                        }
                    } catch {
                        print("Error parsing match data: \(error)")
                    }
                }.resume()
            }
        }
        
        group.notify(queue: .main) {
            // Sort matches by time
            let sortedMatches = allMatches.sorted { ($0.time ?? $0.date) < ($1.time ?? $1.date) }
            completion(sortedMatches)
        }
    }
    
    // MARK: - Public Convenience Methods for Testing
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
