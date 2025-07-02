import Foundation

// Protocol for testability and dependency injection
protocol SportsFetching {
    func fetchSportsSchedule(for date: Date, favoriteSports: [FavoriteSport], showSportsSchedule: Bool, completion: @escaping ([TimelineItem]) -> Void)
}

class SportsAPIService: SportsFetching {
    
    // A simple in-memory cache for API responses.
    // Key: URL string, Object: Array of TimelineItems
    private let cache = NSCache<NSString, NSArray>()
    
    private let sportsDBLeagueIDs: [String: String] = [
        "football": "4328", // English Premier League
        "soccer": "4328",   // Alias for Football
        "basketball": "4387", // NBA
        "baseball": "4424", // MLB
        "hockey": "4380",   // NHL
        "mma": "4443",       // UFC
        "formula 1": "4370", // Formula 1
        "f1": "4370"         // Alias for F1
    ]
    
    func fetchSportsSchedule(for date: Date, favoriteSports: [FavoriteSport], showSportsSchedule: Bool, completion: @escaping ([TimelineItem]) -> Void) {
        guard !favoriteSports.isEmpty && showSportsSchedule else {
            print("Sports schedule disabled or no favorite sports")
            DispatchQueue.main.async {
                completion([])
            }
            return
        }
        
        print("Fetching sports schedule for \(date)")
        
        var allItems: [TimelineItem] = []
        let group = DispatchGroup()
        
        for sport in favoriteSports {
            if sport.teams.isEmpty {
                continue
            }
            
            print("Fetching schedule for \(sport.name) with \(sport.teams.count) favorite teams")
            
            group.enter()
            switch sport.name.lowercased() {
            case "formula 1", "f1":
                fetchFormula1ScheduleFromErgast(date: date, favoriteTeams: sport.teams) { ergastItems, error in
                    if let error = error {
                        print("Ergast API failed with error: \(error.localizedDescription). Trying TheSportsDB as a fallback.")
                        self.fetchDefaultLeagueSchedule(sportName: sport.name, date: date, favoriteTeams: sport.teams) { sportsDBItems, _ in
                            allItems.append(contentsOf: sportsDBItems)
                            group.leave()
                        }
                    } else {
                        allItems.append(contentsOf: ergastItems)
                        group.leave()
                    }
                }
            default:
                fetchDefaultLeagueSchedule(sportName: sport.name, date: date, favoriteTeams: sport.teams) { items, _ in
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
    
    private func getLeagueIDForSport(_ sportName: String) -> String? {
        return sportsDBLeagueIDs[sportName.lowercased()]
    }
    
    private func fetchDefaultLeagueSchedule(sportName: String, date: Date, favoriteTeams: [FavoriteTeam], completion: @escaping ([TimelineItem], Error?) -> Void) {
        guard let leagueID = getLeagueIDForSport(sportName) else {
            print("No league ID configured for sport: \(sportName)")
            completion([], nil)
            return
        }

        let baseURL = "https://www.thesportsdb.com/api/v1/json/3"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        let path = "/eventsday.php?d=\(dateString)&l=\(leagueID)"

        guard let url = URL(string: baseURL + path) else {
            print("Invalid URL for TheSportsDB API")
            completion([], nil)
            return
        }
        fetchSportEventsFromAPI(url: url, sport: sportName, favoriteTeams: favoriteTeams, completion: completion)
    }
    
    private func fetchFormula1ScheduleFromErgast(date: Date, favoriteTeams: [FavoriteTeam], completion: @escaping ([TimelineItem], Error?) -> Void) {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        
        guard let url = URL(string: "https://ergast.com/api/f1/\(year).json") else {
            print("Invalid URL for Ergast F1 API")
            completion([], nil)
            return
        }

        if let cachedItems = cache.object(forKey: url.absoluteString as NSString) as? [TimelineItem] {
            print("Returning cached F1 schedule from Ergast")
            completion(cachedItems, nil)
            return
        }

        print("Fetching F1 schedule from Ergast: \(url.absoluteString)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Ergast API error: \(error.localizedDescription)")
                completion([], error)
                return
            }

            guard let data = data else {
                print("No data received from Ergast API")
                completion([], nil)
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let mrData = json["MRData"] as? [String: Any],
                      let raceTable = mrData["RaceTable"] as? [String: Any],
                      let races = raceTable["Races"] as? [[String: Any]] else {
                    print("Invalid JSON structure from Ergast API")
                    completion([], nil)
                    return
                }

                var f1Items: [TimelineItem] = []
                let favoriteConstructorNames = favoriteTeams.map { $0.name.lowercased() }

                for raceData in races {
                    let raceName = raceData["raceName"] as? String ?? "F1 Race"
                    let circuitName = (raceData["Circuit"] as? [String: Any])?["circuitName"] as? String ?? "F1 Circuit"

                    func parseSession(sessionKey: String, sessionName: String, durationHours: Int = 1) {
                        guard let sessionInfo = raceData[sessionKey] as? [String: Any],
                              let sessionDateStr = sessionInfo["date"] as? String,
                              let sessionTimeStr = sessionInfo["time"] as? String,
                              let sessionFullDate = self.dateFromErgast(dateStr: sessionDateStr, timeStr: sessionTimeStr) else {
                            return
                        }

                        if calendar.isDate(sessionFullDate, inSameDayAs: date) {
                            let endTime = calendar.date(byAdding: .hour, value: durationHours, to: sessionFullDate) ?? sessionFullDate
                            var title = "F1: \(raceName) - \(sessionName)"
                            if !favoriteConstructorNames.isEmpty {
                                 title += " (\(favoriteConstructorNames.joined(separator: "/")) interest)"
                            }

                            let item = TimelineItem(id: UUID(), title: title, type: .event, date: sessionFullDate, isCompleted: false, notes: "Formula 1", time: sessionFullDate, endDate: endTime, location: circuitName)
                            f1Items.append(item)
                        }
                    }

                    parseSession(sessionKey: "FirstPractice", sessionName: "Practice 1")
                    parseSession(sessionKey: "SecondPractice", sessionName: "Practice 2")
                    if raceData["ThirdPractice"] != nil { parseSession(sessionKey: "ThirdPractice", sessionName: "Practice 3") }
                    if raceData["Sprint"] != nil { parseSession(sessionKey: "Sprint", sessionName: "Sprint Race", durationHours: 1) }
                    parseSession(sessionKey: "Qualifying", sessionName: "Qualifying")
                    
                    if let raceDateStr = raceData["date"] as? String, let raceTimeStr = raceData["time"] as? String, let raceFullDate = self.dateFromErgast(dateStr: raceDateStr, timeStr: raceTimeStr), calendar.isDate(raceFullDate, inSameDayAs: date) {
                        // Manually create a "Race" session object to parse
                        let raceSessionData: [String: Any] = ["date": raceDateStr, "time": raceTimeStr]
                        let raceEvent = raceData.merging(["self_race_event": raceSessionData]) { (_, new) in new }
                        parseSession(sessionKey: "self_race_event", sessionName: "Race", durationHours: 2)
                    }
                }
                self.cache.setObject(f1Items as NSArray, forKey: url.absoluteString as NSString)
                completion(f1Items, nil)
            } catch {
                print("Error parsing Ergast F1 data: \(error)")
                completion([], error)
            }
        }.resume()
    }
    
    private func fetchSportEventsFromAPI(url: URL, sport: String, favoriteTeams: [FavoriteTeam], completion: @escaping ([TimelineItem], Error?) -> Void) {
        if let cachedItems = cache.object(forKey: url.absoluteString as NSString) as? [TimelineItem] {
            print("Returning cached data for \(sport) from TheSportsDB")
            completion(cachedItems, nil)
            return
        }

        let favoriteTeamNames = favoriteTeams.map { $0.name.lowercased() }
        print("Fetching sports data from: \(url.absoluteString)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("API error: \(error.localizedDescription)")
                completion([], error)
                return
            }
            
            guard let data = data else {
                print("No data received from API")
                completion([], nil)
                return
            }
            
            var items: [TimelineItem] = []
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    guard let eventsData = json["events"], !(eventsData is NSNull) else {
                        print("No events found or events key is null for \(sport) on this day.")
                        completion([], nil)
                        return
                    }
                    if let events = eventsData as? [[String: Any]] {
                        for event in events {
                            guard let homeTeam = event["strHomeTeam"] as? String,
                                  let awayTeam = event["strAwayTeam"] as? String,
                                  let dateString = event["dateEvent"] as? String,
                                  let timeString = event["strTime"] as? String else {
                                continue
                            }
                            
                            let isRelevant = favoriteTeamNames.isEmpty || favoriteTeamNames.contains { teamName in
                                homeTeam.lowercased().contains(teamName.lowercased()) ||
                                awayTeam.lowercased().contains(teamName.lowercased())
                            }
                            
                            if isRelevant {
                                let dateFormatter = DateFormatter()
                                dateFormatter.dateFormat = "yyyy-MM-dd"
                                guard let eventDate = dateFormatter.date(from: dateString) else { continue }
                                
                                let timeFormatter = DateFormatter()
                                timeFormatter.dateFormat = "HH:mm:ss"
                                
                                if let eventTime = timeFormatter.date(from: timeString) {
                                    let calendar = Calendar.current
                                    let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: eventTime)
                                    let combinedDateTime = calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: timeComponents.second ?? 0, of: eventDate) ?? eventDate
                                    let endTime = Calendar.current.date(byAdding: .hour, value: 2, to: combinedDateTime)!
                                    let venue = event["strVenue"] as? String ?? "Stadium"
                                    let league = event["strLeague"] as? String ?? sport
                                    
                                    let item = TimelineItem(id: UUID(), title: "\(sport): \(homeTeam) vs \(awayTeam)", type: .event, date: eventDate, isCompleted: false, notes: league, time: combinedDateTime, endDate: endTime, location: venue)
                                    items.append(item)
                                }
                            }
                        }
                        print("Found \(items.count) relevant events for \(sport)")
                        self.cache.setObject(items as NSArray, forKey: url.absoluteString as NSString)
                        completion(items, nil)
                    } else {
                        completion([], nil)
                    }
                } else {
                    completion([], nil)
                }
            } catch {
                print("Error parsing API data: \(error)")
                completion([], error)
            }
        }.resume()
    }

    private func dateFromErgast(dateStr: String, timeStr: String) -> Date? {
        let dateTimeStr = "\(dateStr)T\(timeStr)"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateTimeStr) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateTimeStr)
    }
}