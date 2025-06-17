import SwiftUI
import Foundation
import UIKit

struct IdentifiableError: Identifiable {
    let id = UUID()
    let message: String
}

struct SportsBrowserView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @Binding var isPresented: Bool
    @State private var sports: [String] = []
    @State private var leagues: [String] = []
    @State private var teams: [FavoriteTeam] = []
    @State private var selectedSport: String? = nil
    @State private var selectedLeague: String? = nil
    @State private var isLoading = false
    @State private var error: IdentifiableError? = nil
    @State private var showNationalTeams = false
    
    // Sport-specific national teams
    private let nationalTeams: [String: [String]] = [
        "Football": ["England", "France", "Germany", "Spain", "Italy", "Brazil", "Argentina", "Portugal", "Netherlands"],
        "Basketball": ["USA", "Spain", "Australia", "France", "Serbia", "Argentina"],
        "Tennis": [], // Tennis doesn't have national teams in the same way
        "Cricket": ["India", "Australia", "England", "New Zealand", "Pakistan", "South Africa"],
        "Baseball": ["USA", "Japan", "Dominican Republic", "Cuba", "South Korea", "Mexico"]
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with close button and title
                HStack {
                    Button("Close") { isPresented = false }
                    Spacer()
                    Text("Sports Browser").font(.headline)
                    Spacer()
                    Button("") { }.opacity(0) // For balance
                }
                .padding()
                .background(Color(UIColor.systemBackground))
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading...")
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Sports section
                            VStack(alignment: .leading) {
                                Text("Select a Sport")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(["Football", "Basketball", "Tennis", "Cricket", "Baseball", "Formula 1", "MMA"], id: \.self) { sport in
                                            Button(action: {
                                                selectedSport = sport
                                                selectedLeague = nil
                                                teams = []
                                                showNationalTeams = false
                                                fetchLeagues(for: sport)
                                            }) {
                                                Text(sport)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 8)
                                                    .background(selectedSport == sport ? Color.blue : Color.gray.opacity(0.2))
                                                    .foregroundColor(selectedSport == sport ? .white : .primary)
                                                    .cornerRadius(20)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            
                            // Leagues section
                            if let sport = selectedSport, !leagues.isEmpty {
                                VStack(alignment: .leading) {
                                    Text("Select a League")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 10) {
                                            ForEach(leagues, id: \.self) { league in
                                                Button(action: {
                                                    selectedLeague = league
                                                    showNationalTeams = false
                                                    fetchTeams(for: league, sport: sport)
                                                }) {
                                                    Text(league)
                                                        .padding(.horizontal, 16)
                                                        .padding(.vertical, 8)
                                                        .background(selectedLeague == league ? Color.green : Color.gray.opacity(0.2))
                                                        .foregroundColor(selectedLeague == league ? .white : .primary)
                                                        .cornerRadius(20)
                                                }
                                            }
                                            
                                            // National Teams button - only show for sports that have national teams
                                            if let nationalTeamsForSport = nationalTeams[sport], !nationalTeamsForSport.isEmpty {
                                                Button(action: {
                                                    selectedLeague = nil
                                                    showNationalTeams = true
                                                    teams = nationalTeamsForSport.map { FavoriteTeam(name: $0) }
                                                }) {
                                                    Text("National Teams")
                                                        .padding(.horizontal, 16)
                                                        .padding(.vertical, 8)
                                                        .background(showNationalTeams ? Color.purple : Color.gray.opacity(0.2))
                                                        .foregroundColor(showNationalTeams ? .white : .primary)
                                                        .cornerRadius(20)
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // Teams section
                            if !teams.isEmpty {
                                VStack(alignment: .leading) {
                                    Text(showNationalTeams ? "National Teams" : "Club Teams")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 10) {
                                        ForEach(teams, id: \.name) { team in
                                            Button(action: {
                                                if let sport = selectedSport {
                                                    addTeamToFavorites(sport: sport, team: team)
                                                }
                                            }) {
                                                Text(team.name)
                                                    .padding()
                                                    .frame(minWidth: 150)
                                                    .background(Color.blue.opacity(0.1))
                                                    .cornerRadius(10)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            
                            // Favorites section
                            VStack(alignment: .leading) {
                                Text("Your Favorites")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                if viewModel.favoriteSports.isEmpty {
                                    Text("No favorites added yet")
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)
                                } else {
                                    ForEach(viewModel.favoriteSports) { sport in
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack {
                                                Text(sport.name)
                                                    .font(.subheadline)
                                                    .bold()
                                                Spacer()
                                                Button(action: { removeSport(sport.name) }) {
                                                    Image(systemName: "trash")
                                                        .foregroundColor(.red)
                                                }
                                            }
                                            
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack {
                                                    ForEach(sport.teams) { team in
                                                        HStack {
                                                            Text(team.name)
                                                                .font(.caption)
                                                            Button(action: { removeTeam(sport: sport.name, team: team.name) }) {
                                                                Image(systemName: "xmark.circle.fill")
                                                                    .font(.caption)
                                                                    .foregroundColor(.red)
                                                            }
                                                        }
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(Color.gray.opacity(0.1))
                                                        .cornerRadius(12)
                                                    }
                                                }
                                            }
                                        }
                                        .padding()
                                        .background(Color.gray.opacity(0.05))
                                        .cornerRadius(10)
                                    }
                                }
                            }
                            .padding(.top)
                        }
                        .padding(.vertical)
                    }
                }
            }
            .alert(item: $error) { error in
                Alert(title: Text("Error"), message: Text(error.message), dismissButton: .default(Text("OK")))
            }
        }
        .onAppear {
            if selectedSport == nil && !viewModel.favoriteSports.isEmpty {
                // Pre-select the first sport if user has favorites
                selectedSport = viewModel.favoriteSports[0].name
                fetchLeagues(for: selectedSport!)
            }
        }
    }
    
    private func fetchLeagues(for sport: String) {
        isLoading = true
        
        // For simplicity, using static leagues for now
        // In a real app, you would call an API here
        switch sport {
        case "Football":
            leagues = ["Premier League", "La Liga", "Serie A", "Bundesliga", "Ligue 1"]
        case "Basketball":
            leagues = ["NBA", "EuroLeague", "NBL"]
        case "Tennis":
            leagues = ["ATP", "WTA", "Grand Slams"]
        case "Cricket":
            leagues = ["IPL", "BBL", "CPL", "The Hundred"]
        case "Baseball":
            leagues = ["MLB", "NPB", "KBO"]
        case "Formula 1":
            leagues = ["F1 Teams", "F1 Drivers", "Grand Prix"]
        case "MMA":
            leagues = ["UFC", "Bellator", "ONE Championship", "PFL"]
        default:
            leagues = []
        }
        
        isLoading = false
    }
    
    private func fetchTeams(for league: String, sport: String) {
        isLoading = true
        teams = []
        
        // Map league names to league IDs for the API
        let leagueIDs: [String: Int] = [
            "Premier League": 8,
            "La Liga": 564,
            "Serie A": 384,
            "Bundesliga": 82,
            "Ligue 1": 301,
            "NBA": 1,
            "EuroLeague": 2,
            "MLB": 1
        ]
        
        if sport == "Football" && leagueIDs[league] != nil {
            // Use the API to fetch real teams
            let leagueID = leagueIDs[league]!
            let urlString = "https://api.sportmonks.com/v3/football/teams?filters[league_id]=\(leagueID)"
            
            guard let url = URL(string: urlString) else {
                isLoading = false
                return
            }
            
            var request = URLRequest(url: url)
            request.setValue(APIKeyManager.sportMonkKey, forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.error = IdentifiableError(message: "Network error: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let data = data else {
                        self.error = IdentifiableError(message: "No data received")
                        return
                    }
                    
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let dataObj = json["data"] as? [[String: Any]] {
                            
                            var fetchedTeams: [FavoriteTeam] = []
                            
                            for item in dataObj {
                                if let name = item["name"] as? String {
                                    fetchedTeams.append(FavoriteTeam(name: name))
                                }
                            }
                            
                            self.teams = fetchedTeams
                        } else {
                            self.error = IdentifiableError(message: "Failed to parse API response")
                        }
                    } catch {
                        self.error = IdentifiableError(message: "Error parsing data: \(error.localizedDescription)")
                    }
                }
            }.resume()
        } else if sport == "Basketball" {
            // Basketball teams
            switch league {
            case "NBA":
                teams = [
                    FavoriteTeam(name: "Los Angeles Lakers"),
                    FavoriteTeam(name: "Boston Celtics"),
                    FavoriteTeam(name: "Golden State Warriors"),
                    FavoriteTeam(name: "Chicago Bulls"),
                    FavoriteTeam(name: "Miami Heat"),
                    FavoriteTeam(name: "Brooklyn Nets"),
                    FavoriteTeam(name: "Philadelphia 76ers"),
                    FavoriteTeam(name: "Milwaukee Bucks"),
                    FavoriteTeam(name: "Denver Nuggets"),
                    FavoriteTeam(name: "Phoenix Suns"),
                    FavoriteTeam(name: "Dallas Mavericks"),
                    FavoriteTeam(name: "Atlanta Hawks"),
                    FavoriteTeam(name: "Toronto Raptors"),
                    FavoriteTeam(name: "Cleveland Cavaliers"),
                    FavoriteTeam(name: "Memphis Grizzlies"),
                    FavoriteTeam(name: "New Orleans Pelicans"),
                    FavoriteTeam(name: "Minnesota Timberwolves"),
                    FavoriteTeam(name: "Portland Trail Blazers"),
                    FavoriteTeam(name: "Sacramento Kings"),
                    FavoriteTeam(name: "San Antonio Spurs"),
                    FavoriteTeam(name: "Washington Wizards"),
                    FavoriteTeam(name: "Orlando Magic"),
                    FavoriteTeam(name: "Detroit Pistons"),
                    FavoriteTeam(name: "Indiana Pacers"),
                    FavoriteTeam(name: "Oklahoma City Thunder"),
                    FavoriteTeam(name: "Utah Jazz"),
                    FavoriteTeam(name: "Charlotte Hornets"),
                    FavoriteTeam(name: "Houston Rockets"),
                    FavoriteTeam(name: "Los Angeles Clippers"),
                    FavoriteTeam(name: "New York Knicks")
                ]
            case "EuroLeague":
                teams = [
                    FavoriteTeam(name: "Real Madrid"),
                    FavoriteTeam(name: "Barcelona"),
                    FavoriteTeam(name: "CSKA Moscow"),
                    FavoriteTeam(name: "Fenerbahçe"),
                    FavoriteTeam(name: "Olympiacos"),
                    FavoriteTeam(name: "Anadolu Efes"),
                    FavoriteTeam(name: "Maccabi Tel Aviv"),
                    FavoriteTeam(name: "Panathinaikos"),
                    FavoriteTeam(name: "Bayern Munich"),
                    FavoriteTeam(name: "Zalgiris Kaunas"),
                    FavoriteTeam(name: "Baskonia"),
                    FavoriteTeam(name: "Armani Milano"),
                    FavoriteTeam(name: "ASVEL"),
                    FavoriteTeam(name: "Red Star Belgrade"),
                    FavoriteTeam(name: "Alba Berlin"),
                    FavoriteTeam(name: "Valencia Basket")
                ]
            default:
                teams = []
            }
            isLoading = false
        } else if sport == "Tennis" {
            // Tennis players (treated as teams)
            switch league {
            case "ATP":
                teams = [
                    FavoriteTeam(name: "Novak Djokovic"),
                    FavoriteTeam(name: "Rafael Nadal"),
                    FavoriteTeam(name: "Roger Federer"),
                    FavoriteTeam(name: "Carlos Alcaraz"),
                    FavoriteTeam(name: "Daniil Medvedev"),
                    FavoriteTeam(name: "Alexander Zverev"),
                    FavoriteTeam(name: "Stefanos Tsitsipas"),
                    FavoriteTeam(name: "Andrey Rublev"),
                    FavoriteTeam(name: "Casper Ruud"),
                    FavoriteTeam(name: "Jannik Sinner"),
                    FavoriteTeam(name: "Felix Auger-Aliassime"),
                    FavoriteTeam(name: "Hubert Hurkacz"),
                    FavoriteTeam(name: "Taylor Fritz"),
                    FavoriteTeam(name: "Cameron Norrie"),
                    FavoriteTeam(name: "Matteo Berrettini")
                ]
            case "WTA":
                teams = [
                    FavoriteTeam(name: "Iga Swiatek"),
                    FavoriteTeam(name: "Aryna Sabalenka"),
                    FavoriteTeam(name: "Jessica Pegula"),
                    FavoriteTeam(name: "Elena Rybakina"),
                    FavoriteTeam(name: "Coco Gauff"),
                    FavoriteTeam(name: "Ons Jabeur"),
                    FavoriteTeam(name: "Maria Sakkari"),
                    FavoriteTeam(name: "Daria Kasatkina"),
                    FavoriteTeam(name: "Belinda Bencic"),
                    FavoriteTeam(name: "Caroline Garcia"),
                    FavoriteTeam(name: "Veronika Kudermetova"),
                    FavoriteTeam(name: "Danielle Collins"),
                    FavoriteTeam(name: "Beatriz Haddad Maia"),
                    FavoriteTeam(name: "Liudmila Samsonova"),
                    FavoriteTeam(name: "Victoria Azarenka")
                ]
            case "Grand Slams":
                teams = [
                    FavoriteTeam(name: "Australian Open"),
                    FavoriteTeam(name: "French Open"),
                    FavoriteTeam(name: "Wimbledon"),
                    FavoriteTeam(name: "US Open")
                ]
            default:
                teams = []
            }
            isLoading = false
        } else if sport == "Cricket" {
            // Cricket teams
            switch league {
            case "IPL":
                teams = [
                    FavoriteTeam(name: "Mumbai Indians"),
                    FavoriteTeam(name: "Chennai Super Kings"),
                    FavoriteTeam(name: "Royal Challengers Bangalore"),
                    FavoriteTeam(name: "Kolkata Knight Riders"),
                    FavoriteTeam(name: "Delhi Capitals"),
                    FavoriteTeam(name: "Punjab Kings"),
                    FavoriteTeam(name: "Rajasthan Royals"),
                    FavoriteTeam(name: "Sunrisers Hyderabad"),
                    FavoriteTeam(name: "Gujarat Titans"),
                    FavoriteTeam(name: "Lucknow Super Giants")
                ]
            case "BBL":
                teams = [
                    FavoriteTeam(name: "Adelaide Strikers"),
                    FavoriteTeam(name: "Brisbane Heat"),
                    FavoriteTeam(name: "Hobart Hurricanes"),
                    FavoriteTeam(name: "Melbourne Renegades"),
                    FavoriteTeam(name: "Melbourne Stars"),
                    FavoriteTeam(name: "Perth Scorchers"),
                    FavoriteTeam(name: "Sydney Sixers"),
                    FavoriteTeam(name: "Sydney Thunder")
                ]
            case "CPL":
                teams = [
                    FavoriteTeam(name: "Barbados Royals"),
                    FavoriteTeam(name: "Guyana Amazon Warriors"),
                    FavoriteTeam(name: "Jamaica Tallawahs"),
                    FavoriteTeam(name: "St Kitts & Nevis Patriots"),
                    FavoriteTeam(name: "Saint Lucia Kings"),
                    FavoriteTeam(name: "Trinbago Knight Riders")
                ]
            case "The Hundred":
                teams = [
                    FavoriteTeam(name: "Birmingham Phoenix"),
                    FavoriteTeam(name: "London Spirit"),
                    FavoriteTeam(name: "Manchester Originals"),
                    FavoriteTeam(name: "Northern Superchargers"),
                    FavoriteTeam(name: "Oval Invincibles"),
                    FavoriteTeam(name: "Southern Brave"),
                    FavoriteTeam(name: "Trent Rockets"),
                    FavoriteTeam(name: "Welsh Fire")
                ]
            default:
                teams = []
            }
            isLoading = false
        } else if sport == "Baseball" {
            // Baseball teams
            switch league {
            case "MLB":
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
                    FavoriteTeam(name: "Minnesota Twins"),
                    FavoriteTeam(name: "Milwaukee Brewers"),
                    FavoriteTeam(name: "Detroit Tigers"),
                    FavoriteTeam(name: "Colorado Rockies"),
                    FavoriteTeam(name: "Baltimore Orioles"),
                    FavoriteTeam(name: "Los Angeles Angels"),
                    FavoriteTeam(name: "Arizona Diamondbacks"),
                    FavoriteTeam(name: "Texas Rangers"),
                    FavoriteTeam(name: "Tampa Bay Rays"),
                    FavoriteTeam(name: "Pittsburgh Pirates"),
                    FavoriteTeam(name: "Miami Marlins"),
                    FavoriteTeam(name: "Kansas City Royals"),
                    FavoriteTeam(name: "Cincinnati Reds"),
                    FavoriteTeam(name: "Oakland Athletics"),
                    FavoriteTeam(name: "Washington Nationals")
                ]
            case "NPB":
                teams = [
                    FavoriteTeam(name: "Yomiuri Giants"),
                    FavoriteTeam(name: "Hanshin Tigers"),
                    FavoriteTeam(name: "Hiroshima Toyo Carp"),
                    FavoriteTeam(name: "Tokyo Yakult Swallows"),
                    FavoriteTeam(name: "Yokohama DeNA BayStars"),
                    FavoriteTeam(name: "Chunichi Dragons"),
                    FavoriteTeam(name: "Fukuoka SoftBank Hawks"),
                    FavoriteTeam(name: "Saitama Seibu Lions"),
                    FavoriteTeam(name: "Tohoku Rakuten Golden Eagles"),
                    FavoriteTeam(name: "Chiba Lotte Marines"),
                    FavoriteTeam(name: "Hokkaido Nippon-Ham Fighters"),
                    FavoriteTeam(name: "Orix Buffaloes")
                ]
            case "KBO":
                teams = [
                    FavoriteTeam(name: "Doosan Bears"),
                    FavoriteTeam(name: "Kiwoom Heroes"),
                    FavoriteTeam(name: "KT Wiz"),
                    FavoriteTeam(name: "LG Twins"),
                    FavoriteTeam(name: "Lotte Giants"),
                    FavoriteTeam(name: "NC Dinos"),
                    FavoriteTeam(name: "Samsung Lions"),
                    FavoriteTeam(name: "SSG Landers"),
                    FavoriteTeam(name: "Hanwha Eagles"),
                    FavoriteTeam(name: "Kia Tigers")
                ]
            default:
                teams = []
            }
            isLoading = false
        } else if sport == "Formula 1" {
            // Formula 1 teams/drivers
            switch league {
            case "F1 Teams":
                teams = [
                    FavoriteTeam(name: "Red Bull Racing"),
                    FavoriteTeam(name: "Ferrari"),
                    FavoriteTeam(name: "Mercedes"),
                    FavoriteTeam(name: "McLaren"),
                    FavoriteTeam(name: "Aston Martin"),
                    FavoriteTeam(name: "Alpine"),
                    FavoriteTeam(name: "Williams"),
                    FavoriteTeam(name: "RB"),
                    FavoriteTeam(name: "Sauber"),
                    FavoriteTeam(name: "Haas F1 Team")
                ]
            case "F1 Drivers":
                teams = [
                    FavoriteTeam(name: "Max Verstappen"),
                    FavoriteTeam(name: "Lewis Hamilton"),
                    FavoriteTeam(name: "Charles Leclerc"),
                    FavoriteTeam(name: "Lando Norris"),
                    FavoriteTeam(name: "Carlos Sainz"),
                    FavoriteTeam(name: "Fernando Alonso"),
                    FavoriteTeam(name: "George Russell"),
                    FavoriteTeam(name: "Sergio Perez"),
                    FavoriteTeam(name: "Oscar Piastri"),
                    FavoriteTeam(name: "Lance Stroll"),
                    FavoriteTeam(name: "Pierre Gasly"),
                    FavoriteTeam(name: "Esteban Ocon"),
                    FavoriteTeam(name: "Alexander Albon"),
                    FavoriteTeam(name: "Yuki Tsunoda"),
                    FavoriteTeam(name: "Daniel Ricciardo"),
                    FavoriteTeam(name: "Valtteri Bottas"),
                    FavoriteTeam(name: "Nico Hulkenberg"),
                    FavoriteTeam(name: "Zhou Guanyu"),
                    FavoriteTeam(name: "Kevin Magnussen"),
                    FavoriteTeam(name: "Logan Sargeant")
                ]
            default:
                teams = []
            }
            isLoading = false
        } else if sport == "MMA" {
            // MMA organizations and fighters
            switch league {
            case "UFC":
                teams = [
                    FavoriteTeam(name: "Jon Jones"),
                    FavoriteTeam(name: "Israel Adesanya"),
                    FavoriteTeam(name: "Alexander Volkanovski"),
                    FavoriteTeam(name: "Islam Makhachev"),
                    FavoriteTeam(name: "Leon Edwards"),
                    FavoriteTeam(name: "Amanda Nunes"),
                    FavoriteTeam(name: "Valentina Shevchenko"),
                    FavoriteTeam(name: "Conor McGregor"),
                    FavoriteTeam(name: "Dustin Poirier"),
                    FavoriteTeam(name: "Charles Oliveira"),
                    FavoriteTeam(name: "Max Holloway"),
                    FavoriteTeam(name: "Kamaru Usman"),
                    FavoriteTeam(name: "Francis Ngannou"),
                    FavoriteTeam(name: "Khabib Nurmagomedov"),
                    FavoriteTeam(name: "Alex Pereira")
                ]
            case "Bellator":
                teams = [
                    FavoriteTeam(name: "Patricio Pitbull"),
                    FavoriteTeam(name: "Cris Cyborg"),
                    FavoriteTeam(name: "Vadim Nemkov"),
                    FavoriteTeam(name: "Sergio Pettis"),
                    FavoriteTeam(name: "Ryan Bader"),
                    FavoriteTeam(name: "AJ McKee"),
                    FavoriteTeam(name: "Michael Page"),
                    FavoriteTeam(name: "Douglas Lima")
                ]
            case "ONE Championship":
                teams = [
                    FavoriteTeam(name: "Demetrious Johnson"),
                    FavoriteTeam(name: "Angela Lee"),
                    FavoriteTeam(name: "Rodtang Jitmuangnon"),
                    FavoriteTeam(name: "Christian Lee"),
                    FavoriteTeam(name: "Adriano Moraes"),
                    FavoriteTeam(name: "Stamp Fairtex")
                ]
            default:
                teams = []
            }
            isLoading = false
        } else {
            isLoading = false
        }
    }
    
    private func addTeamToFavorites(sport: String, team: FavoriteTeam) {
        // Check if this sport already exists in favorites
        if let index = viewModel.favoriteSports.firstIndex(where: { $0.name == sport }) {
            // Check if this team is already in favorites
            if !viewModel.favoriteSports[index].teams.contains(where: { $0.name == team.name }) {
                viewModel.favoriteSports[index].teams.append(team)
                print("Added \(team.name) to existing sport \(sport)")
            }
        } else {
            // Add new sport with this team
            viewModel.favoriteSports.append(FavoriteSport(name: sport, teams: [team]))
            print("Added new sport \(sport) with team \(team.name)")
        }
        
        // Enable sports schedule display
        viewModel.showSportsSchedule = true
        
        // Show confirmation to the user
        let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
        impactGenerator.impactOccurred()
    }
    
    private func removeSport(_ sportName: String) {
        viewModel.favoriteSports.removeAll { $0.name == sportName }
    }
    
    private func removeTeam(sport: String, team: String) {
        if let sportIndex = viewModel.favoriteSports.firstIndex(where: { $0.name == sport }) {
            viewModel.favoriteSports[sportIndex].teams.removeAll { $0.name == team }
            
            // If no teams left, remove the sport too
            if viewModel.favoriteSports[sportIndex].teams.isEmpty {
                viewModel.favoriteSports.remove(at: sportIndex)
            }
        }
    }
}
