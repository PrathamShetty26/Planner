import SwiftUI

struct SportsSelectorView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @State private var selectedSport: String? = nil
    @State private var selectedLeague: (id: Int, name: String)? = nil
    @State private var selectedTeam: FavoriteTeam? = nil
    @State private var leagues: [(id: Int, name: String)] = []
    @State private var teams: [FavoriteTeam] = []
    @State private var isLoadingLeagues = false
    @State private var isLoadingTeams = false
    @State private var error: String? = nil
    
    let availableSports = ["Football"] 
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Sports bubbles
            Text("Choose a Sport:").font(.subheadline)
            HStack {
                ForEach(availableSports, id: \.self) { sport in
                    Button(action: {
                        withAnimation {
                            selectedSport = sport
                            selectedLeague = nil
                            leagues = []
                            teams = []
                            fetchLeagues(for: sport)
                        }
                    }) {
                        Text(sport)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedSport == sport ? Color.accentColor : Color(UIColor.systemGray5))
                            .foregroundColor(selectedSport == sport ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            // 2. Leagues bubbles
            if selectedSport != nil {
                if isLoadingLeagues {
                    ProgressView("Loading leagues...")
                } else if !leagues.isEmpty {
                    Text("Choose a League:").font(.subheadline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(leagues.indices, id: \.self) { index in
                                let league = leagues[index]
                                Button(action: {
                                    withAnimation {
                                        selectedLeague = league
                                        teams = []
                                        fetchTeams(for: league.id)
                                    }
                                }) {
                                    Text(league.name)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(selectedLeague?.id == league.id ? Color.accentColor : Color(UIColor.systemGray5))
                                        .foregroundColor(selectedLeague?.id == league.id ? .white : .primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            // 3. Teams bubbles
            if selectedLeague != nil {
                if isLoadingTeams {
                    ProgressView("Loading teams...")
                } else if !teams.isEmpty {
                    Text("Choose a Team:").font(.subheadline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(teams) { team in
                                Button(action: {
                                    addTeamToFavorites(sport: selectedSport!, team: team)
                                }) {
                                    Text(team.name)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color(UIColor.systemGray5))
                                        .foregroundColor(.primary)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            // 4. Error
            if let error = error {
                Text(error).foregroundColor(.red).font(.footnote)
            }
            // 5. Favorites
            if !viewModel.favoriteSports.isEmpty {
                Divider()
                Text("Your Favorites:").font(.subheadline)
                ForEach(viewModel.favoriteSports) { sport in
                    VStack(alignment: .leading) {
                        Text(sport.name).bold()
                        Text(sport.teams.map { $0.name }.joined(separator: ", "))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func fetchLeagues(for sport: String) {
        guard sport == "Football" else { leagues = []; return }
        isLoadingLeagues = true
        error = nil
        
        let urlString = "https://api.sportmonks.com/v3/football/leagues"
        guard let url = URL(string: urlString) else { leagues = []; isLoadingLeagues = false; return }
        
        var request = URLRequest(url: url)
        request.setValue(APIKeyManager.sportMonkKey, forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, _, err in
            DispatchQueue.main.async {
                isLoadingLeagues = false
                if let err = err { error = err.localizedDescription; return }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataObj = json["data"] as? [[String: Any]] else { error = "Failed to load leagues"; return }
                leagues = dataObj.compactMap { dict in
                    if let id = dict["id"] as? Int,
                       let name = dict["name"] as? String {
                        return (id: id, name: name)
                    }
                    return nil
                }
            }
        }.resume()
    }
    
    private func fetchTeams(for leagueID: Int) {
        isLoadingTeams = true
        error = nil
        
        let urlString = "https://api.sportmonks.com/v3/football/teams?filters[league_id]=\(leagueID)"
        guard let url = URL(string: urlString) else { teams = []; isLoadingTeams = false; return }
        
        var request = URLRequest(url: url)
        request.setValue(APIKeyManager.sportMonkKey, forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, _, err in
            DispatchQueue.main.async {
                isLoadingTeams = false
                if let err = err { error = err.localizedDescription; return }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataObj = json["data"] as? [[String: Any]] else { error = "Failed to load teams"; return }
                teams = dataObj.compactMap { dict in
                    if let name = dict["name"] as? String {
                        return FavoriteTeam(name: name)
                    }
                    return nil
                }
            }
        }.resume()
    }
    
    private func addTeamToFavorites(sport: String, team: FavoriteTeam) {
        if let index = viewModel.favoriteSports.firstIndex(where: { $0.name == sport }) {
            if !viewModel.favoriteSports[index].teams.contains(team) {
                viewModel.favoriteSports[index].teams.append(team)
            }
        } else {
            viewModel.favoriteSports.append(FavoriteSport(name: sport, teams: [team]))
        }
    }
} 
