import Foundation

extension PlannerViewModel {

    // MARK: - Sports Schedule Management

    @MainActor
    public func timelineItemsWithSports(for date: Date) async -> [TimelineItem] {
        let userItems = timelineItems(for: date)
        print("Found \(userItems.count) user items for date \(date)")

        let sportsItems = await fetchSportsSchedule(for: date)
        print("Found \(sportsItems.count) sports items for date \(date)")

        var allItems = userItems + sportsItems
        allItems.sort { ($0.time ?? $0.date) < ($1.time ?? $1.date) }

        print("Returning \(allItems.count) combined items")
        return allItems
    }

    @MainActor
    public func fetchSportsSchedule(for date: Date) async -> [TimelineItem] {
        guard !favoriteSports.isEmpty && showSportsSchedule else {
            print("Sports schedule disabled or no favorite sports")
            return []
        }

        print("Fetching sports schedule for \(date)")

        // Use a TaskGroup to run network calls concurrently and safely.
        // This prevents the data race that was causing the crash.
        return await withTaskGroup(of: [TimelineItem].self) { group in
            var allItems: [TimelineItem] = []

            for sport in favoriteSports where !sport.teams.isEmpty {
                print("Fetching schedule for \(sport.name) with \(sport.teams.count) favorite teams")

                group.addTask {
                    switch sport.name.lowercased() {
                    case "baseball":
                        return await self.fetchMLBSchedule(date: date, favoriteTeams: sport.teams)
                    case "hockey":
                        return await self.fetchNHLSchedule(date: date, favoriteTeams: sport.teams)
                    default:
                        return await self.fetchTheSportsDBSchedule(sport: sport.name, favoriteTeams: sport.teams)
                    }
                }
            }

            // Collect results from all tasks as they complete.
            for await items in group {
                allItems.append(contentsOf: items)
            }

            print("Returning \(allItems.count) sports events")
            return allItems
        }
    }

    private func fetchTheSportsDBSchedule(sport: String, favoriteTeams: [FavoriteTeam]) async -> [TimelineItem] {
        let endpoint = SportsAPIEndpoint.theSportsDB(sport: sport)
        let favoriteTeamNames = favoriteTeams.map { $0.name.lowercased() }

        guard let url = endpoint.buildURL(date: Date()) else {
            print("Invalid URL for TheSportsDB API")
            return []
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = json["events"] as? [[String: Any]] else {
                print("Invalid response format from TheSportsDB")
                return []
            }

            var items: [TimelineItem] = []
            for event in events {
                guard let homeTeam = event["strHomeTeam"] as? String,
                      let awayTeam = event["strAwayTeam"] as? String,
                      let dateString = event["dateEvent"] as? String,
                      let timeString = event["strTime"] as? String else { continue }

                let isRelevant = favoriteTeamNames.contains { homeTeam.lowercased().contains($0) || awayTeam.lowercased().contains($0) }

                if isRelevant {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    guard let eventDate = dateFormatter.date(from: dateString) else { continue }

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

                    let item = TimelineItem(
                        id: UUID(),
                        title: "\(sport): \(homeTeam) vs \(awayTeam)",
                        type: .event,
                        date: eventDate,
                        isCompleted: false,
                        notes: event["strLeague"] as? String ?? sport,
                        time: eventTime,
                        endDate: Calendar.current.date(byAdding: .hour, value: 2, to: eventTime)!,
                        location: event["strVenue"] as? String ?? "Stadium"
                    )
                    items.append(item)
                }
            }
            return items
        } catch {
            print("Error fetching or parsing TheSportsDB data: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchMLBSchedule(date: Date, favoriteTeams: [FavoriteTeam]) async -> [TimelineItem] {
        let endpoint = SportsAPIEndpoint.mlb
        guard let url = endpoint.buildURL(date: date) else { return [] }
        let favoriteTeamNames = favoriteTeams.map { $0.name.lowercased() }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dates = json["dates"] as? [[String: Any]],
                  let firstDate = dates.first,
                  let games = firstDate["games"] as? [[String: Any]] else {
                print("Invalid response format from MLB API")
                return []
            }

            var items: [TimelineItem] = []
            for game in games {
                guard let teams = game["teams"] as? [String: Any],
                      let homeTeam = (teams["home"] as? [String: Any])?["team"] as? [String: Any],
                      let awayTeam = (teams["away"] as? [String: Any])?["team"] as? [String: Any],
                      let homeName = homeTeam["name"] as? String,
                      let awayName = awayTeam["name"] as? String,
                      let gameDate = game["gameDate"] as? String else { continue }

                let isRelevant = favoriteTeamNames.contains { homeName.lowercased().contains($0) || awayName.lowercased().contains($0) }

                if isRelevant {
                    let dateFormatter = ISO8601DateFormatter()
                    guard let parsedDate = dateFormatter.date(from: gameDate) else { continue }

                    let item = TimelineItem(
                        id: UUID(),
                        title: "Baseball: \(homeName) vs \(awayName)",
                        type: .event,
                        date: parsedDate,
                        isCompleted: false,
                        notes: "MLB Game",
                        time: parsedDate,
                        endDate: Calendar.current.date(byAdding: .hour, value: 3, to: parsedDate)!,
                        location: (game["venue"] as? [String: Any])?["name"] as? String ?? "Stadium"
                    )
                    items.append(item)
                }
            }
            return items
        } catch {
            print("Error fetching or parsing MLB data: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchNHLSchedule(date: Date, favoriteTeams: [FavoriteTeam]) async -> [TimelineItem] {
        let endpoint = SportsAPIEndpoint.nhl
        guard let url = endpoint.buildURL(date: date) else { return [] }
        let favoriteTeamNames = favoriteTeams.map { $0.name.lowercased() }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dates = json["dates"] as? [[String: Any]],
                  let firstDate = dates.first,
                  let games = firstDate["games"] as? [[String: Any]] else {
                print("Invalid response format from NHL API")
                return []
            }

            var items: [TimelineItem] = []
            for game in games {
                guard let teams = game["teams"] as? [String: Any],
                      let homeTeam = (teams["home"] as? [String: Any])?["team"] as? [String: Any],
                      let awayTeam = (teams["away"] as? [String: Any])?["team"] as? [String: Any],
                      let homeName = homeTeam["name"] as? String,
                      let awayName = awayTeam["name"] as? String,
                      let gameDate = game["gameDate"] as? String else { continue }

                let isRelevant = favoriteTeamNames.contains { homeName.lowercased().contains($0) || awayName.lowercased().contains($0) }

                if isRelevant {
                    let dateFormatter = ISO8601DateFormatter()
                    guard let parsedDate = dateFormatter.date(from: gameDate) else { continue }

                    let item = TimelineItem(
                        id: UUID(),
                        title: "Hockey: \(homeName) vs \(awayName)",
                        type: .event,
                        date: parsedDate,
                        isCompleted: false,
                        notes: "NHL Game",
                        time: parsedDate,
                        endDate: Calendar.current.date(byAdding: .minute, value: 150, to: parsedDate)!,
                        location: (game["venue"] as? [String: Any])?["name"] as? String ?? "Arena"
                    )
                    items.append(item)
                }
            }
            return items
        } catch {
            print("Error fetching or parsing NHL data: \(error.localizedDescription)")
            return []
        }
    }

    // Sports API endpoints for different sports
    private enum SportsAPIEndpoint {
        case theSportsDB(sport: String)
        case mlb
        case nhl

        var baseURL: String {
            switch self {
            case .theSportsDB: return "https://www.thesportsdb.com/api/v1/json/3" // Free tier API key is "3"
            case .mlb: return "https://statsapi.mlb.com/api/v1"
            case .nhl: return "https://statsapi.web.nhl.com/api/v1"
            }
        }

        var path: String {
            switch self {
            case .theSportsDB(let sport): return "/eventsnextleague.php?id=\(leagueIDForSport(sport))"
            case .mlb, .nhl: return "/schedule"
            }
        }

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

        func buildURL(date: Date) -> URL? {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: date)

            var components = URLComponents(string: baseURL + path)

            switch self {
            case .theSportsDB:
                return components?.url
            case .mlb:
                components?.queryItems = [
                    URLQueryItem(name: "sportId", value: "1"),
                    URLQueryItem(name: "date", value: dateString),
                    URLQueryItem(name: "hydrate", value: "team,venue")
                ]
                return components?.url
            case .nhl:
                components?.queryItems = [URLQueryItem(name: "date", value: dateString)]
                return components?.url
            }
        }
    }
}