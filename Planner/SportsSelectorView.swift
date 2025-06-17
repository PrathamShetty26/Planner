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
    @State private var showToggle = true
    
    let availableSports = ["Football", "Basketball", "Baseball", "Hockey", "Formula 1", "MMA"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showToggle {
                Toggle("Show Sports Schedule", isOn: $viewModel.showSportsSchedule)
                    .padding(.bottom, 8)
            }
            
            // 1. Sports bubbles
            Text("Choose a Sport:").font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
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
            }
            
            // 2. Leagues bubbles
            if let sport = selectedSport, !leagues.isEmpty {
                Text("Choose a League:").font(.subheadline).padding(.top, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(leagues, id: \.id) { league in
                            Button(action: {
                                withAnimation {
                                    selectedLeague = league
                                    teams = []
                                    fetchTeams(for: league.id, sport: sport)
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
            
            // Loading indicators
            if isLoadingLeagues {
                ProgressView("Loading leagues...")
            }
            
            // 3. Teams bubbles
            if selectedLeague != nil {
                if isLoadingTeams {
                    ProgressView("Loading teams...")
                } else if !teams.isEmpty {
                    Text("Choose a Team:").font(.subheadline).padding(.top, 8)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(teams) { team in
                                Button(action: {
                                    addTeamToFavorites(sport: selectedSport!, team: team)
                                }) {
                                    HStack {
                                        Text(team.name)
                                        
                                        // Show checkmark if team is already in favorites
                                        if isTeamInFavorites(sport: selectedSport!, team: team) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                    }
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
                Divider().padding(.vertical, 8)
                
                HStack {
                    Text("Your Favorites:").font(.headline)
                    Spacer()
                    Button(action: { viewModel.favoriteSports = [] }) {
                        Text("Clear All")
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                
                ForEach(viewModel.favoriteSports.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.favoriteSports[index].name).font(.subheadline).bold()
                        
                        ForEach(viewModel.favoriteSports[index].teams.indices, id: \.self) { teamIndex in
                            HStack {
                                Text(viewModel.favoriteSports[index].teams[teamIndex].name)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button(action: {
                                    removeTeamFromFavorites(sportIndex: index, teamIndex: teamIndex)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.footnote)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            if selectedSport == nil && !viewModel.favoriteSports.isEmpty {
                // Pre-select the first sport if user has favorites
                selectedSport = viewModel.favoriteSports[0].name
                fetchLeagues(for: selectedSport!)
            }
        }
    }
    
    private func fetchLeagues(for sport: String) {
        isLoadingLeagues = true
        error = nil
        
        // For simplicity, using static leagues for now
        switch sport.lowercased() {
        case "football":
            leagues = [
                (id: 8, name: "Premier League"),
                (id: 564, name: "La Liga"),
                (id: 384, name: "Serie A"),
                (id: 82, name: "Bundesliga"),
                (id: 301, name: "Ligue 1")
            ]
        case "basketball":
            leagues = [
                (id: 1, name: "NBA"),
                (id: 2, name: "EuroLeague"),
                (id: 3, name: "NBL")
            ]
        case "baseball":
            leagues = [
                (id: 1, name: "MLB"),
                (id: 2, name: "NPB"),
                (id: 3, name: "KBO")
            ]
        case "hockey":
            leagues = [
                (id: 1, name: "NHL"),
                (id: 2, name: "KHL"),
                (id: 3, name: "SHL")
            ]
        case "formula 1":
            leagues = [
                (id: 1, name: "F1 Teams"),
                (id: 2, name: "F1 Drivers")
            ]
        case "mma":
            leagues = [
                (id: 1, name: "UFC"),
                (id: 2, name: "Bellator"),
                (id: 3, name: "ONE Championship")
            ]
        default:
            leagues = []
        }
        
        isLoadingLeagues = false
    }
    
    private func fetchTeams(for leagueID: Int, sport: String) {
        isLoadingTeams = true
        teams = []
        
        // For simplicity, using static teams for popular leagues
        switch sport.lowercased() {
        case "football":
            if leagueID == 8 { // Premier League
                teams = [
                    FavoriteTeam(name: "Arsenal"),
                    FavoriteTeam(name: "Aston Villa"),
                    FavoriteTeam(name: "Bournemouth"),
                    FavoriteTeam(name: "Brentford"),
                    FavoriteTeam(name: "Brighton"),
                    FavoriteTeam(name: "Chelsea"),
                    FavoriteTeam(name: "Crystal Palace"),
                    FavoriteTeam(name: "Everton"),
                    FavoriteTeam(name: "Fulham"),
                    FavoriteTeam(name: "Liverpool"),
                    FavoriteTeam(name: "Manchester City"),
                    FavoriteTeam(name: "Manchester United"),
                    FavoriteTeam(name: "Newcastle"),
                    FavoriteTeam(name: "Nottingham Forest"),
                    FavoriteTeam(name: "Sheffield United"),
                    FavoriteTeam(name: "Tottenham"),
                    FavoriteTeam(name: "West Ham"),
                    FavoriteTeam(name: "Wolverhampton")
                ]
            }
        case "baseball":
            if leagueID == 1 { // MLB
                teams = [
                    FavoriteTeam(name: "New York Yankees"),
                    FavoriteTeam(name: "Boston Red Sox"),
                    FavoriteTeam(name: "Los Angeles Dodgers"),
                    FavoriteTeam(name: "Chicago Cubs"),
                    FavoriteTeam(name: "San Francisco Giants"),
                    FavoriteTeam(name: "Atlanta Braves"),
                    FavoriteTeam(name: "Houston Astros"),
                    FavoriteTeam(name: "St. Louis Cardinals"),
                    FavoriteTeam(name: "Philadelphia Phillies"),
                    FavoriteTeam(name: "Toronto Blue Jays"),
                    FavoriteTeam(name: "New York Mets"),
                    FavoriteTeam(name: "Cleveland Guardians"),
                    FavoriteTeam(name: "Chicago White Sox"),
                    FavoriteTeam(name: "Seattle Mariners"),
                    FavoriteTeam(name: "San Diego Padres"),
                    FavoriteTeam(name: "Minnesota Twins")
                ]
            }
        case "hockey":
            if leagueID == 1 { // NHL
                teams = [
                    FavoriteTeam(name: "Boston Bruins"),
                    FavoriteTeam(name: "Toronto Maple Leafs"),
                    FavoriteTeam(name: "Montreal Canadiens"),
                    FavoriteTeam(name: "New York Rangers"),
                    FavoriteTeam(name: "Detroit Red Wings"),
                    FavoriteTeam(name: "Chicago Blackhawks"),
                    FavoriteTeam(name: "Edmonton Oilers"),
                    FavoriteTeam(name: "Pittsburgh Penguins"),
                    FavoriteTeam(name: "Colorado Avalanche"),
                    FavoriteTeam(name: "Tampa Bay Lightning"),
                    FavoriteTeam(name: "Vegas Golden Knights"),
                    FavoriteTeam(name: "Washington Capitals")
                ]
            }
        default:
            // Add more teams for other sports as needed
            teams = []
        }
        
        isLoadingTeams = false
    }
    
    private func addTeamToFavorites(sport: String, team: FavoriteTeam) {
        // Check if this sport already exists in favorites
        if let index = viewModel.favoriteSports.firstIndex(where: { $0.name == sport }) {
            // Check if this team is already in favorites
            if !viewModel.favoriteSports[index].teams.contains(where: { $0.name == team.name }) {
                viewModel.favoriteSports[index].teams.append(team)
                print("Added \(team.name) to existing sport \(sport)")
            } else {
                // If team already exists, remove it (toggle behavior)
                viewModel.favoriteSports[index].teams.removeAll(where: { $0.name == team.name })
                print("Removed \(team.name) from sport \(sport)")
                
                // If no teams left for this sport, remove the sport
                if viewModel.favoriteSports[index].teams.isEmpty {
                    viewModel.favoriteSports.remove(at: index)
                    print("Removed sport \(sport) as it has no teams")
                }
            }
        } else {
            // Add new sport with this team
            viewModel.favoriteSports.append(FavoriteSport(name: sport, teams: [team]))
            print("Added new sport \(sport) with team \(team.name)")
        }
    }
    
    private func removeTeamFromFavorites(sportIndex: Int, teamIndex: Int) {
        viewModel.favoriteSports[sportIndex].teams.remove(at: teamIndex)
        
        // If no teams left for this sport, remove the sport
        if viewModel.favoriteSports[sportIndex].teams.isEmpty {
            viewModel.favoriteSports.remove(at: sportIndex)
        }
    }
    
    private func isTeamInFavorites(sport: String, team: FavoriteTeam) -> Bool {
        if let sportIndex = viewModel.favoriteSports.firstIndex(where: { $0.name == sport }) {
            return viewModel.favoriteSports[sportIndex].teams.contains(where: { $0.name == team.name })
        }
        return false
    }
} 
