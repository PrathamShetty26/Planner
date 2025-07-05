import Foundation
import EventKit
import UserNotifications
import SwiftUI
import HealthKit

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
    
    private var eventStore: EKEventStore
    private var hasRequestedCalendarPermission = false
    private var hasRequestedNotificationPermission = false
    private var isInitializingPermissions = false
    private var hasInitializedPermissions = false
    
    private let healthKitManager = HealthKitManager()
    
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
        print("Found \(userItems.count) user items for date \(date)")
        
        fetchSportsSchedule(for: date) { sportsItems in
            print("Found \(sportsItems.count) sports items for date \(date)")
            var all = userItems + sportsItems
            all.sort { (lhs, rhs) -> Bool in
                let lhsTime = lhs.time ?? lhs.date
                let rhsTime = rhs.time ?? rhs.date
                return lhsTime < rhsTime
            }
            print("Returning \(all.count) combined items")
            completion(all)
        }
    }
    
    @MainActor
    func fetchHealthData(for date: Date) async {
        guard showHealthData && healthKitAuthorizationStatus == .sharingAuthorized else { return }
        
        do {
            // Use async let to fetch steps and energy concurrently
            async let stepsTask = try healthKitManager.fetchStepCount(for: date)
            async let energyTask = try healthKitManager.fetchActiveEnergy(for: date)
            
            self.steps = try await stepsTask
            self.activeEnergy = try await energyTask
        } catch {
            print("Failed to fetch health data: \(error.localizedDescription)")
            self.steps = 0
            self.activeEnergy = 0
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

                        self.calendarAccessStatus = .fullAccess
                    } else {
                        self.calendarAccessStatus = .authorized
                    }
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

    @MainActor
    func requestHealthKitPermission() async {
        do {
            // This presents the permission sheet to the user.
            try await healthKitManager.requestAuthorization()
            // After the user responds, we must check the new status to see what they chose.
            await self.checkInitialHealthKitStatus()
        } catch {
            self.healthKitAuthorizationStatus = .sharingDenied
            self.permissionErrorMessage = "Please enable Health access in Settings. Error: \(error.localizedDescription)"
            self.showSettingsPrompt = true
        }
    }
    
    // Move the static flag outside the function as a class property
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
    
    // MARK: - Sports Schedule Management

    // Sports API endpoints for different sports
    private enum SportsAPIEndpoint {
        case theSportsDB(sport: String)
        case mlb
        case nhl
        
        var baseURL: String {
            switch self {
            case .theSportsDB:
                return "https://www.thesportsdb.com/api/v1/json/3" // Free tier API key is "3"
            case .mlb:
                return "https://statsapi.mlb.com/api/v1"
            case .nhl:
                return "https://statsapi.web.nhl.com/api/v1"
            }
        }
        
        var path: String {
            switch self {
            case .theSportsDB(let sport):
                return "/eventsnextleague.php?id=\(leagueIDForSport(sport))"
            case .mlb:
                return "/schedule"
            case .nhl:
                return "/schedule"
            }
        }
        
        // Helper to map sports to TheSportsDB league IDs
        private func leagueIDForSport(_ sport: String) -> String {
            switch sport.lowercased() {
            case "soccer", "football": return "4328" // English Premier League
            case "basketball": return "4387" // NBA
            case "baseball": return "4424" // MLB
            case "hockey": return "4380" // NHL
            case "formula 1", "f1": return "4370" // Formula 1
            case "mma", "ufc": return "4443" // UFC
            default: return "4328" // Default to EPL
            }
        }
        
        // Build URL with query parameters
        func buildURL(date: Date) -> URL? {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: date)
            
            switch self {
            case .theSportsDB:
                // TheSportsDB already returns next events with the league endpoint
                return URL(string: baseURL + path)
                
            case .mlb:
                // MLB API allows date range queries
                var components = URLComponents(string: baseURL + path)
                components?.queryItems = [
                    URLQueryItem(name: "sportId", value: "1"),
                    URLQueryItem(name: "date", value: dateString),
                    URLQueryItem(name: "hydrate", value: "team,venue")
                ]
                return components?.url
                
            case .nhl:
                // NHL API allows date queries
                var components = URLComponents(string: baseURL + path)
                components?.queryItems = [
                    URLQueryItem(name: "date", value: dateString)
                ]
                return components?.url
            }
        }
    }

    
    // 1. Add rate limiting to prevent too many API calls
    private var lastAPICallTime: Date?
    private let minTimeBetweenAPICalls: TimeInterval = 1.0 // 1 second between calls

    func fetchSportsSchedule(for date: Date, completion: @escaping ([TimelineItem]) -> Void) {
        guard !favoriteSports.isEmpty && showSportsSchedule else {
            print("Sports schedule disabled or no favorite sports")
            completion([])
            return
        }
        
        print("Fetching sports schedule for \(date)")
        
        var allItems: [TimelineItem] = []
        let group = DispatchGroup()
        
        // Process each favorite sport with the appropriate API
        for sport in favoriteSports {
            // Skip if no teams are selected for this sport
            if sport.teams.isEmpty {
                continue
            }
            
            print("Fetching schedule for \(sport.name) with \(sport.teams.count) favorite teams")
            
            switch sport.name.lowercased() {
            case "baseball":
                group.enter()
                fetchMLBSchedule(date: date, favoriteTeams: sport.teams) { items in
                    allItems.append(contentsOf: items)
                    group.leave()
                }
                
            case "hockey":
                group.enter()
                fetchNHLSchedule(date: date, favoriteTeams: sport.teams) { items in
                    allItems.append(contentsOf: items)
                    group.leave()
                }
                
            default:
                // Use TheSportsDB for all other sports
                group.enter()
                fetchTheSportsDBSchedule(sport: sport.name, favoriteTeams: sport.teams) { items in
                    allItems.append(contentsOf: items)
                    group.leave()
                }
            }
        }
        
        group.notify(queue: .main) {
            print("Returning \(allItems.count) sports events")
            completion(allItems)
        }
    }

    private func fetchTheSportsDBSchedule(sport: String, favoriteTeams: [FavoriteTeam], completion: @escaping ([TimelineItem]) -> Void) {
        let endpoint = SportsAPIEndpoint.theSportsDB(sport: sport)
        
        // Create a list of lowercase team names for easier comparison
        let favoriteTeamNames = favoriteTeams.map { $0.name.lowercased() }
        print("Looking for \(sport) games with teams: \(favoriteTeamNames.joined(separator: ", "))")
        
        guard let url = endpoint.buildURL(date: Date()) else {
            print("Invalid URL for TheSportsDB API")
            completion([])
            return
        }
        
        print("Fetching from TheSportsDB: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("TheSportsDB API error: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let data = data else {
                print("No data received from TheSportsDB")
                completion([])
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let events = json["events"] as? [[String: Any]] {
                    
                    var items: [TimelineItem] = []
                    let favoriteTeamNames = favoriteTeams.map { $0.name.lowercased() }
                    
                    for event in events {
                        // Extract event details
                        guard let homeTeam = event["strHomeTeam"] as? String,
                              let awayTeam = event["strAwayTeam"] as? String,
                              let dateString = event["dateEvent"] as? String,
                              let timeString = event["strTime"] as? String else {
                            continue
                        }
                        
                        // Check if this event involves any of our favorite teams
                        let isRelevant = favoriteTeamNames.contains { teamName in
                            homeTeam.lowercased().contains(teamName) || 
                            awayTeam.lowercased().contains(teamName)
                        }
                        
                        if isRelevant {
                            // Parse date and time
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd"
                            guard let eventDate = dateFormatter.date(from: dateString) else { continue }
                            
                            // Parse time if available
                            var eventTime = eventDate
                            if timeString != "00:00:00" {
                                let timeFormatter = DateFormatter()
                                timeFormatter.dateFormat = "HH:mm:ss"
                                if let parsedTime = timeFormatter.date(from: timeString) {
                                    let calendar = Calendar.current
                                    let hour = calendar.component(.hour, from: parsedTime)
                                    let minute = calendar.component(.minute, from: parsedTime)
                                    eventTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: eventDate) ?? eventDate
                                }
                            }
                            
                            // Create end time (2 hours after start)
                            let endTime = Calendar.current.date(byAdding: .hour, value: 2, to: eventTime)!
                            
                            // Get venue if available
                            let venue = event["strVenue"] as? String ?? "Stadium"
                            
                            // Get league name
                            let league = event["strLeague"] as? String ?? sport
                            
                            let item = TimelineItem(
                                id: UUID(),
                                title: "\(sport): \(homeTeam) vs \(awayTeam)",
                                type: .event,
                                date: eventDate,
                                isCompleted: false,
                                notes: league,
                                time: eventTime,
                                endDate: endTime,
                                location: venue
                            )
                            
                            items.append(item)
                        }
                    }
                    
                    completion(items)
                } else {
                    print("Invalid response format from TheSportsDB")
                    completion([])
                }
            } catch {
                print("Error parsing TheSportsDB data: \(error)")
                completion([])
            }
        }.resume()
    }

    private func fetchMLBSchedule(date: Date, favoriteTeams: [FavoriteTeam], completion: @escaping ([TimelineItem]) -> Void) {
        let endpoint = SportsAPIEndpoint.mlb
        
        guard let url = endpoint.buildURL(date: date) else {
            print("Invalid URL for MLB API")
            completion([])
            return
        }
        
        print("Fetching from MLB API: \(url.absoluteString)")
        
        // Create a list of lowercase team names for easier comparison
        let favoriteTeamNames = favoriteTeams.map { $0.name.lowercased() }
        print("Looking for MLB games with teams: \(favoriteTeamNames.joined(separator: ", "))")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("MLB API error: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let data = data else {
                print("No data received from MLB API")
                completion([])
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dates = json["dates"] as? [[String: Any]],
                   let firstDate = dates.first,
                   let games = firstDate["games"] as? [[String: Any]] {
                    
                    var items: [TimelineItem] = []
                    let favoriteTeamNames = favoriteTeams.map { $0.name.lowercased() }
                    
                    for game in games {
                        guard let teams = game["teams"] as? [String: Any],
                              let homeTeam = teams["home"] as? [String: Any],
                              let awayTeam = teams["away"] as? [String: Any],
                              let homeTeamData = homeTeam["team"] as? [String: Any],
                              let awayTeamData = awayTeam["team"] as? [String: Any],
                              let homeName = homeTeamData["name"] as? String,
                              let awayName = awayTeamData["name"] as? String,
                              let gameDate = game["gameDate"] as? String else {
                            continue
                        }
                        
                        // Check if this game involves any of our favorite teams
                        let isRelevant = favoriteTeamNames.contains { teamName in
                            homeName.lowercased().contains(teamName) || 
                            awayName.lowercased().contains(teamName)
                        }

                        // Only add games that involve the user's favorite teams
                        if isRelevant {
                            // Parse the game date (ISO 8601 format)
                            let dateFormatter = ISO8601DateFormatter()
                            guard let parsedDate = dateFormatter.date(from: gameDate) else { continue }
                            
                            // Get venue if available
                            var venue = "Stadium"
                            if let venueData = game["venue"] as? [String: Any],
                               let venueName = venueData["name"] as? String {
                                venue = venueName
                            }
                            
                            // Create end time (3 hours after start for baseball)
                            let endTime = Calendar.current.date(byAdding: .hour, value: 3, to: parsedDate)!
                            
                            let item = TimelineItem(
                                id: UUID(),
                                title: "Baseball: \(homeName) vs \(awayName)",
                                type: .event,
                                date: parsedDate,
                                isCompleted: false,
                                notes: "MLB Game",
                                time: parsedDate,
                                endDate: endTime,
                                location: venue
                            )
                            
                            items.append(item)
                        }
                    }
                    
                    completion(items)
                } else {
                    print("Invalid response format from MLB API")
                    completion([])
                }
            } catch {
                print("Error parsing MLB data: \(error)")
                completion([])
            }
        }.resume()
    }

    private func fetchNHLSchedule(date: Date, favoriteTeams: [FavoriteTeam], completion: @escaping ([TimelineItem]) -> Void) {
        let endpoint = SportsAPIEndpoint.nhl
        
        guard let url = endpoint.buildURL(date: date) else {
            print("Invalid URL for NHL API")
            completion([])
            return
        }
        
        print("Fetching from NHL API: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("NHL API error: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let data = data else {
                print("No data received from NHL API")
                completion([])
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dates = json["dates"] as? [[String: Any]],
                   let firstDate = dates.first,
                   let games = firstDate["games"] as? [[String: Any]] {
                    
                    var items: [TimelineItem] = []
                    let favoriteTeamNames = favoriteTeams.map { $0.name.lowercased() }
                    
                    for game in games {
                        guard let teams = game["teams"] as? [String: Any],
                              let homeTeam = teams["home"] as? [String: Any],
                              let awayTeam = teams["away"] as? [String: Any],
                              let homeTeamData = homeTeam["team"] as? [String: Any],
                              let awayTeamData = awayTeam["team"] as? [String: Any],
                              let homeName = homeTeamData["name"] as? String,
                              let awayName = awayTeamData["name"] as? String,
                              let gameDate = game["gameDate"] as? String else {
                            continue
                        }
                        
                        // Check if this game involves any of our favorite teams
                        let isRelevant = favoriteTeamNames.contains { teamName in
                            homeName.lowercased().contains(teamName) || 
                            awayName.lowercased().contains(teamName)
                        }
                        
                        if isRelevant {
                            // Parse the game date (ISO 8601 format)
                            let dateFormatter = ISO8601DateFormatter()
                            guard let parsedDate = dateFormatter.date(from: gameDate) else { continue }
                            
                            // Get venue if available
                            var venue = "Arena"
                            if let venueData = game["venue"] as? [String: Any],
                               let venueName = venueData["name"] as? String {
                                venue = venueName
                            }
                            
                            // Create end time (2.5 hours after start for hockey)
                            let endTime = Calendar.current.date(byAdding: .minute, value: 150, to: parsedDate)!
                            
                            let item = TimelineItem(
                                id: UUID(),
                                title: "Hockey: \(homeName) vs \(awayName)",
                                type: .event,
                                date: parsedDate,
                                isCompleted: false,
                                notes: "NHL Game",
                                time: parsedDate,
                                endDate: endTime,
                                location: venue
                            )
                            
                            items.append(item)
                        }
                    }
                    
                    completion(items)
                } else {
                    print("Invalid response format from NHL API")
                    completion([])
                }
            } catch {
                print("Error parsing NHL data: \(error)")
                completion([])
            }
        }.resume()
    }

    // Add this enum to replace SportMonkEndpoint
    private enum SportType: String {
        case football = "football"
        case baseball = "baseball"
        case formula1 = "formula-1"
        case mma = "mma"
        case basketball = "basketball"
        case hockey = "hockey"
        
        var displayName: String {
            switch self {
            case .football: return "Football"
            case .baseball: return "Baseball"
            case .formula1: return "Formula 1"
            case .mma: return "MMA"
            case .basketball: return "Basketball"
            case .hockey: return "Hockey"
            }
        }
    }

    // Helper method to get team ID from name for SportMonk
    private func getTeamID(for teamName: String, sport: SportType, completion: @escaping (String?) -> Void) {
        // Hardcoded team ID mappings for common teams across sports
        let teamIDs: [String: [String: String]] = [
            "football": [
                "Paris Saint Germain": "85",
                "PSG": "85",
                "Manchester United": "33",
                "Manchester City": "17",
                "Liverpool": "8",
                "Chelsea": "38",
                "Arsenal": "42",
                "Barcelona": "529",
                "Real Madrid": "541",
                "Bayern Munich": "157"
            ],
            "baseball": [
                "New York Yankees": "1",
                "Boston Red Sox": "2",
                "Los Angeles Dodgers": "3",
                "Chicago Cubs": "4",
                "San Francisco Giants": "5"
            ],
            "formula-1": [
                "Ferrari": "2",
                "Red Bull Racing": "1",
                "Mercedes": "3",
                "McLaren": "4",
                "Aston Martin": "5"
            ]
        ]
        
        // Check if we have a hardcoded ID for this team
        if let sportTeams = teamIDs[sport.rawValue], let teamID = sportTeams[teamName] {
            print("Using hardcoded team ID \(teamID) for \(teamName)")
            completion(teamID)
            return
        }
        
        // For Formula 1, use a default team ID if not found
        if sport == .formula1 {
            print("Using default team ID for Formula 1")
            completion("1")  // Default to Red Bull Racing
            return
        }
        
        // If we don't have a hardcoded ID, use a default ID based on sport
        let defaultID = "1"  // Default to a common team ID
        print("Using default team ID \(defaultID) for \(teamName)")
        completion(defaultID)
    }

    // Search for team ID in SportMonk
    private func searchTeam(name: String, sport: String, completion: @escaping (String?) -> Void) {
        let encodedTeam = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        
        // We're no longer using SportMonk API, so this is a simplified version
        print("Searching for team: \(name) in sport: \(sport)")
        
        // Just return nil since we're using other APIs now
        completion(nil)
    }

    // Helper method to parse match data from response
    private func parseMatchFromResponse(_ matchData: [String: Any]?, sport: String, date: Date) -> TimelineItem? {
        guard let matchData = matchData else { return nil }
        
        let calendar = Calendar.current
        let targetDate = date
        
        // Different parsing logic based on sport
        switch sport {
        case "football":
            if let fixture = matchData["fixture"] as? [String: Any],
               let timestamp = fixture["timestamp"] as? TimeInterval,
               let teams = matchData["teams"] as? [String: Any],
               let home = teams["home"] as? [String: Any],
               let away = teams["away"] as? [String: Any],
               let homeName = home["name"] as? String,
               let awayName = away["name"] as? String {
                
                let venue = (fixture["venue"] as? [String: Any])?["name"] as? String ?? "Stadium"
                let matchDate = Date(timeIntervalSince1970: timestamp)
                
                let matchTime = matchDate
                
                // Only return if the match is on the requested date
                if calendar.isDate(matchDate, inSameDayAs: targetDate) {
                    return TimelineItem(
                        id: UUID(),
                        title: "Football: \(homeName) vs \(awayName)",
                        type: .event,
                        date: targetDate,
                        isCompleted: false,
                        notes: "Football Match",
                        time: matchTime,
                        endDate: calendar.date(byAdding: .hour, value: 2, to: matchTime),
                        location: venue
                    )
                }
            }
        
        case "basketball":
            if let game = matchData["game"] as? [String: Any],
               let timestamp = game["timestamp"] as? TimeInterval,
               let teams = matchData["teams"] as? [String: Any],
               let home = teams["home"] as? [String: Any],
               let away = teams["away"] as? [String: Any],
               let homeName = home["name"] as? String,
               let awayName = away["name"] as? String {
                
                let venue = (game["arena"] as? [String: Any])?["name"] as? String ?? "Arena"
                let matchDate = Date(timeIntervalSince1970: timestamp)
                
                let calendar = Calendar.current
                let matchTime = matchDate
                
                return TimelineItem(
                    id: UUID(),
                    title: "Basketball: \(homeName) vs \(awayName)",
                    type: .event,
                    date: date,
                    isCompleted: false,
                    notes: "Basketball Game",
                    time: matchTime,
                    endDate: calendar.date(byAdding: .hour, value: 2, to: matchTime),
                    location: venue
                )
            }
        
        case "baseball":
            if let game = matchData["game"] as? [String: Any],
               let timestamp = game["timestamp"] as? TimeInterval,
               let teams = matchData["teams"] as? [String: Any],
               let home = teams["home"] as? [String: Any],
               let away = teams["away"] as? [String: Any],
               let homeName = home["name"] as? String,
               let awayName = away["name"] as? String {
                
                let venue = (game["stadium"] as? [String: Any])?["name"] as? String ?? "Stadium"
                let matchDate = Date(timeIntervalSince1970: timestamp)
                
                let calendar = Calendar.current
                let matchTime = matchDate
                
                return TimelineItem(
                    id: UUID(),
                    title: "Baseball: \(homeName) vs \(awayName)",
                    type: .event,
                    date: date,
                    isCompleted: false,
                    notes: "Baseball Game",
                    time: matchTime,
                    endDate: calendar.date(byAdding: .hour, value: 2, to: matchTime),
                    location: venue
                )
            }
        
        case "formula1":
            if let race = matchData["race"] as? [String: Any],
               let competition = race["competition"] as? [String: Any],
               let name = competition["name"] as? String,
               let circuit = race["circuit"] as? [String: Any],
               let circuitName = circuit["name"] as? String,
               let dateString = race["date"] as? String,
               let timeString = race["time"] as? String {
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                let raceDateTime = dateFormatter.date(from: "\(dateString)T\(timeString)") ?? Date()
                
                // Check if the race is in the past (more than 1 day ago)
                let calendar = Calendar.current
                let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                
                // Skip past races
                if raceDateTime < yesterday {
                    return nil
                }
                
                return TimelineItem(
                    id: UUID(),
                    title: "Formula 1: \(name)",
                    type: .event,
                    date: date, // Use the passed date parameter, not the dateString
                    isCompleted: false,
                    notes: "Formula 1 Race",
                    time: raceDateTime,
                    endDate: calendar.date(byAdding: .hour, value: 2, to: raceDateTime),
                    location: circuitName
                )
            }
        
        case "mma":
            if let event = matchData["event"] as? [String: Any],
               let name = event["name"] as? String,
               let location = event["location"] as? String,
               let dateString = event["date"] as? String,
               let timeString = event["time"] as? String {
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                let eventDateTime = dateFormatter.date(from: "\(dateString)T\(timeString)") ?? Date()
                
                // For MMA, we might have multiple fights in one event
                if let fights = matchData["fights"] as? [[String: Any]],
                   let mainEvent = fights.first,
                   let fighter1 = mainEvent["fighter1"] as? [String: Any],
                   let fighter2 = mainEvent["fighter2"] as? [String: Any],
                   let fighter1Name = fighter1["name"] as? String,
                   let fighter2Name = fighter2["name"] as? String {
                    
                    return TimelineItem(
                        id: UUID(),
                        title: "MMA: \(name) - \(fighter1Name) vs \(fighter2Name)",
                        type: .event,
                        date: date, // Use the passed date parameter, not the dateString
                        isCompleted: false,
                        notes: "MMA Event",
                        time: eventDateTime,
                        endDate: Calendar.current.date(byAdding: .hour, value: 3, to: eventDateTime),
                        location: location
                    )
                } else {
                    return TimelineItem(
                        id: UUID(),
                        title: "MMA: \(name)",
                        type: .event,
                        date: date, // Use the passed date parameter, not the dateString
                        isCompleted: false,
                        notes: "MMA Event",
                        time: eventDateTime,
                        endDate: Calendar.current.date(byAdding: .hour, value: 3, to: eventDateTime),
                        location: location
                    )
                }
            }
        
        default:
            print("Unsupported sport type: \(sport)")
        }
        
        return nil
    }

    // MARK: - API Data Fetching

    // We only use API data for sports schedules, no simulations or hardcoded events

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
    private func checkInitialCalendarStatus() async {
        calendarAccessStatus = EKEventStore.authorizationStatus(for: .event)
        
        if calendarAccessStatus == .notDetermined {
            showCalendarPrompt = true
        }
    }

    @MainActor
    private func checkInitialHealthKitStatus() async {
        healthKitAuthorizationStatus = healthKitManager.healthStore.authorizationStatus(for: HKObjectType.quantityType(forIdentifier: .stepCount)!)
        if healthKitAuthorizationStatus == .sharingAuthorized {
            await fetchHealthData(for: Date())
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
        guard let time = item.time, let itemEndDate = item.endDate else { return }
        
        let accessGranted: Bool
        if #available(iOS 17.0, *) {
            accessGranted = calendarAccessStatus == .fullAccess || calendarAccessStatus == .writeOnly
        } else {
            accessGranted = calendarAccessStatus == .authorized
        }
        
        guard accessGranted else { return }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = item.title
        event.notes = item.notes
        event.startDate = item.time ?? item.date
        event.endDate = itemEndDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: item.time ?? item.date) ?? item.date
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            print("Error saving event to calendar: \(error)")
        }
    }
    
    @MainActor
    private func updateEventInCalendar(_ item: TimelineItem) async {
        guard let _ = item.time, let itemEndDate = item.endDate else { return }
        
        let accessGranted: Bool
        if #available(iOS 17.0, *) {
            accessGranted = calendarAccessStatus == .fullAccess || calendarAccessStatus == .writeOnly
        } else {
            accessGranted = calendarAccessStatus == .authorized
        }
        
        guard accessGranted else { return }
        
        // Find the event by title (since we don't store EKEvent identifiers)
        let startDate = Calendar.current.date(byAdding: .day, value: -1, to: item.date) ?? item.date
        let searchEndDate = Calendar.current.date(byAdding: .day, value: 1, to: item.date) ?? item.date
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: searchEndDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        if let event = events.first(where: { $0.title == item.title }) {
            event.title = item.title
            event.notes = item.notes
            event.startDate = item.time ?? item.date
            event.endDate = itemEndDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: item.time ?? item.date) ?? item.date
            
            do {
                try eventStore.save(event, span: .thisEvent)
            } catch {
                print("Error updating event in calendar: \(error)")
            }
        }
    }
    
    @MainActor
    private func removeEventFromCalendar(_ item: TimelineItem) async {
        guard let _ = item.time, let _ = item.endDate else { return }
        
        let accessGranted: Bool
        if #available(iOS 17.0, *) {
            accessGranted = calendarAccessStatus == .fullAccess || calendarAccessStatus == .writeOnly
        } else {
            accessGranted = calendarAccessStatus == .authorized
        }
        
        guard accessGranted else { return }
        
        // Find the event by title
        let startDate = Calendar.current.date(byAdding: .day, value: -1, to: item.date) ?? item.date
        let searchEndDate = Calendar.current.date(byAdding: .day, value: 1, to: item.date) ?? item.date
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: searchEndDate, calendars: nil)
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

// Helper method to parse date strings from the API
private func parseDate(_ dateString: String) -> Date? {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    return dateFormatter.date(from: dateString)
}

// Helper for F1 session type
private func getF1SessionType(for weekday: Int) -> String {
    switch weekday {
    case 6: // Friday
        return "Practice"
    case 7: // Saturday
        return "Qualifying"
    case 1: // Sunday
        return "Race"
    default:
        return "Event"
    }
}


private func createF1SessionsForRaceWeekend(raceData: [String: Any], team: String, completion: @escaping ([TimelineItem]) -> Void) {
    var sessions: [TimelineItem] = []
    
    guard let race = raceData["race"] as? [String: Any],
          let circuit = raceData["circuit"] as? [String: Any],
          let competition = raceData["competition"] as? [String: Any],
          let raceName = competition["name"] as? String,
          let circuitName = circuit["name"] as? String,
          let raceDate = race["date"] as? String,
          let raceTime = race["time"] as? String else {
        print("Missing required F1 race data")
        completion([])
        return
    }
    
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    
    guard let raceDayDate = dateFormatter.date(from: raceDate) else {
        print("Invalid race date format")
        completion([])
        return
    }
    
    // Parse race time
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "HH:mm:ssZ"
    
    // Create race day event (Sunday) using API data
    guard let parsedRaceTime = timeFormatter.date(from: raceTime) else {
        completion([])
        return
    }
    
    let calendar = Calendar.current
    let raceHour = calendar.component(.hour, from: parsedRaceTime)
    let raceMinute = calendar.component(.minute, from: parsedRaceTime)
    
    let actualRaceTime = calendar.date(bySettingHour: raceHour, minute: raceMinute, second: 0, of: raceDayDate)!
    let raceEndTime = calendar.date(byAdding: .hour, value: 2, to: actualRaceTime)!
    
    let raceEvent = TimelineItem(
        id: UUID(),
        title: "F1: \(raceName) - Race (\(team))",
        type: .event,
        date: raceDayDate,
        isCompleted: false,
        notes: "Formula 1 Grand Prix",
        time: actualRaceTime,
        endDate: raceEndTime,
        location: circuitName
    )
    sessions.append(raceEvent)
    
    // Only add other sessions if they're provided by the API
    if let qualifyingData = raceData["qualifying"] as? [String: Any],
       let qualifyingDate = qualifyingData["date"] as? String,
       let qualifyingTime = qualifyingData["time"] as? String,
       let qualifyingDateObj = dateFormatter.date(from: qualifyingDate),
       let parsedQualTime = timeFormatter.date(from: qualifyingTime) {
        
        let qualHour = calendar.component(.hour, from: parsedQualTime)
        let qualMinute = calendar.component(.minute, from: parsedQualTime)
        
        let actualQualTime = calendar.date(bySettingHour: qualHour, minute: qualMinute, second: 0, of: qualifyingDateObj) ?? qualifyingDateObj
        let qualEndTime = calendar.date(byAdding: .hour, value: 1, to: actualQualTime) ?? actualQualTime
        
        let qualifyingEvent = TimelineItem(
            id: UUID(),
            title: "F1: \(raceName) - Qualifying (\(team))",
            type: .event,
            date: qualifyingDateObj,
            isCompleted: false,
            notes: "Formula 1 Qualifying",
            time: actualQualTime,
            endDate: qualEndTime,
            location: circuitName
        )
        sessions.append(qualifyingEvent)
    }
    
    // Add practice sessions only if provided by API
    if let practice1Data = raceData["practice1"] as? [String: Any],
       let practice1Date = practice1Data["date"] as? String,
       let practice1Time = practice1Data["time"] as? String,
       let practice1DateObj = dateFormatter.date(from: practice1Date),
       let parsedP1Time = timeFormatter.date(from: practice1Time) {
        
        let p1Hour = calendar.component(.hour, from: parsedP1Time)
        let p1Minute = calendar.component(.minute, from: parsedP1Time)
        
        let actualP1Time = calendar.date(bySettingHour: p1Hour, minute: p1Minute, second: 0, of: practice1DateObj) ?? practice1DateObj
        let p1EndTime = calendar.date(byAdding: .hour, value: 1, to: actualP1Time) ?? actualP1Time
        
        let fp1Event = TimelineItem(
            id: UUID(),
            title: "F1: \(raceName) - Practice 1 (\(team))",
            type: .event,
            date: practice1DateObj,
            isCompleted: false,
            notes: "Formula 1 Practice",
            time: actualP1Time,
            endDate: p1EndTime,
            location: circuitName
        )
        sessions.append(fp1Event)
    }
    
    if let practice2Data = raceData["practice2"] as? [String: Any],
       let practice2Date = practice2Data["date"] as? String,
       let practice2Time = practice2Data["time"] as? String,
       let practice2DateObj = dateFormatter.date(from: practice2Date),
       let parsedP2Time = timeFormatter.date(from: practice2Time) {
        
        let p2Hour = calendar.component(.hour, from: parsedP2Time)
        let p2Minute = calendar.component(.minute, from: parsedP2Time)
        
        let actualP2Time = calendar.date(bySettingHour: p2Hour, minute: p2Minute, second: 0, of: practice2DateObj) ?? practice2DateObj
        let p2EndTime = calendar.date(byAdding: .hour, value: 1, to: actualP2Time) ?? actualP2Time
        
        let fp2Event = TimelineItem(
            id: UUID(),
            title: "F1: \(raceName) - Practice 2 (\(team))",
            type: .event,
            date: practice2DateObj,
            isCompleted: false,
            notes: "Formula 1 Practice",
            time: actualP2Time,
            endDate: p2EndTime,
            location: circuitName
        )
        sessions.append(fp2Event)
    }
    
    if let practice3Data = raceData["practice3"] as? [String: Any],
       let practice3Date = practice3Data["date"] as? String,
       let practice3Time = practice3Data["time"] as? String,
       let practice3DateObj = dateFormatter.date(from: practice3Date),
       let parsedP3Time = timeFormatter.date(from: practice3Time) {
        
        let p3Hour = calendar.component(.hour, from: parsedP3Time)
        let p3Minute = calendar.component(.minute, from: parsedP3Time)
        
        let actualP3Time = calendar.date(bySettingHour: p3Hour, minute: p3Minute, second: 0, of: practice3DateObj) ?? practice3DateObj
        let p3EndTime = calendar.date(byAdding: .hour, value: 1, to: actualP3Time) ?? actualP3Time
        
        let fp3Event = TimelineItem(
            id: UUID(),
            title: "F1: \(raceName) - Practice 3 (\(team))",
            type: .event,
            date: practice3DateObj,
            isCompleted: false,
            notes: "Formula 1 Practice",
            time: actualP3Time,
            endDate: p3EndTime,
            location: circuitName
        )
        sessions.append(fp3Event)
    }
    
    completion(sessions)
}

// Helper method to create test matches when API fails
private func createTestMatch(for date: Date, sport: String, team: String) -> TimelineItem {
    let calendar = Calendar.current
    let matchTime = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: date)!
    let endTime = calendar.date(byAdding: .hour, value: 2, to: matchTime)!
    
    return TimelineItem(
        id: UUID(),
        title: "\(sport): \(team) vs Opponent",
        type: .event,
        date: date,
        isCompleted: false,
        notes: "Sports Match (Test Data)",
        time: matchTime,
        endDate: endTime,
        location: "Stadium"
    )
}

// processF1Race method removed as it's no longer needed
