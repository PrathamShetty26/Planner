import SwiftUI

struct SportsBrowserView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @Binding var isPresented: Bool
    @State private var sports: [(key: String, name: String)] = []
    @State private var selectedSport: (key: String, name: String)? = nil
    @State private var leagues: [(id: Int, name: String)] = []
    @State private var selectedLeague: (id: Int, name: String)? = nil
    @State private var teams: [FavoriteTeam] = []
    @State private var isLoading = false
    @State private var error: IdentifiableError? = nil
    @State private var navLevel: Int = 0 // 0: sports, 1: leagues, 2: teams
    @State private var staticSports: [String] = [
        "Football", "Basketball", "Tennis", "Cricket", "Baseball", "Hockey", "Rugby", "Golf", "Boxing", "Cycling", "F1", "MMA", "Volleyball", "Table Tennis"
    ]
    @State private var selectedStaticSport: String? = nil
    @State private var staticLeagues: [String: [String]] = [
        "Football": ["Premier League", "La Liga", "Serie A", "Bundesliga", "Ligue 1"],
        "Basketball": ["NBA", "EuroLeague", "NBL"],
        "Tennis": ["ATP", "WTA"],
        "Cricket": ["IPL", "BBL", "CPL"],
        "Baseball": ["MLB", "NPB"],
        "Hockey": ["NHL", "KHL"],
        "Rugby": ["Super Rugby", "Premiership"],
        "Golf": ["PGA Tour", "European Tour"],
        "Boxing": ["WBC", "WBA"],
        "Cycling": ["Tour de France", "Giro d'Italia"],
        "F1": ["Formula 1"],
        "MMA": ["UFC", "Bellator"],
        "Volleyball": ["FIVB"],
        "Table Tennis": ["ITTF"]
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerView
                contentView
                Divider().padding(.vertical)
                favoritesSection
                Spacer()
            }
            .onAppear(perform: fetchSports)
            .alert(item: $error) { err in
                Alert(title: Text("Error"), message: Text(err.message), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Button("Close") { isPresented = false }
                .padding()
            Spacer()
        }
    }
    
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Favorites").font(.headline)
            if viewModel.favoriteSports.isEmpty {
                Text("No favorites yet.").foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.favoriteSports) { sport in
                            HStack {
                                Text(sport.name).bold()
                                Spacer()
                                Button(action: { removeSport(sport) }) {
                                    Image(systemName: "trash").foregroundColor(.red)
                                }
                            }
                            ForEach(sport.teams) { team in
                                HStack {
                                    Text(team.name)
                                    Spacer()
                                    Button(action: { removeTeam(sport: sport, team: team) }) {
                                        Image(systemName: "minus.circle").foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch navLevel {
        case 0:
            sportsGrid
        case 1:
            leaguesGrid
        case 2:
            teamsGrid
        default:
            EmptyView()
        }
    }
    
    private var sportsGrid: some View {
        VStack {
            Text("Choose a Sport").font(.title2).padding(.bottom)
            ExpandingBubbleCloudView(
                items: staticSports,
                childMap: staticLeagues,
                onSelect: { sport in selectedStaticSport = sport },
                expanded: selectedStaticSport,
                onDismiss: { selectedStaticSport = nil }
            )
            .frame(height: 500)
        }
    }
    
    private var leaguesGrid: some View {
        VStack {
            HStack {
                Button(action: { navLevel = 0; selectedSport = nil }) {
                    Image(systemName: "chevron.left")
                }.padding(.leading)
                Text(selectedSport?.name ?? "").font(.title2)
                Spacer()
            }
            if isLoading { ProgressView() }
            else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 2), spacing: 16) {
                        ForEach(leagues, id: \.id) { league in
                            Button(action: {
                                selectedLeague = league
                                navLevel = 2
                                fetchTeams(for: league.id, sportKey: selectedSport?.key ?? "")
                            }) {
                                Text(league.name)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Color(UIColor.systemGray5))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private var teamsGrid: some View {
        VStack {
            HStack {
                Button(action: { navLevel = 1; selectedLeague = nil }) {
                    Image(systemName: "chevron.left")
                }.padding(.leading)
                Text(selectedLeague?.name ?? "").font(.title2)
                Spacer()
            }
            if isLoading { ProgressView() }
            else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 2), spacing: 16) {
                        ForEach(teams) { team in
                            Button(action: {
                                addTeamToFavorites(sport: selectedSport?.name ?? "", team: team)
                            }) {
                                Text(team.name)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Color(UIColor.systemGray5))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private func fetchSports() {
        isLoading = true
        error = nil
        let apiKey = "lmao"
        let urlString = "https://v3.football.api-sports.io/sports"
        guard let url = URL(string: urlString) else { isLoading = false; return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-apisports-key")
        URLSession.shared.dataTask(with: request) { data, _, err in
            DispatchQueue.main.async {
                isLoading = false
                if let err = err { error = IdentifiableError(message: err.localizedDescription); return }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let response = json["response"] as? [[String: Any]] else { error = IdentifiableError(message: "Failed to load sports"); return }
                sports = response.compactMap { dict in
                    if let key = dict["key"] as? String, let name = dict["name"] as? String {
                        return (key: key, name: name)
                    }
                    return nil
                }
            }
        }.resume()
    }
    
    private func fetchLeagues(for sportKey: String) {
        isLoading = true
        error = nil
        let apiKey = "dd06c346e5161e49a8908022ab081232"
        let urlString = "https://v3.football.api-sports.io/leagues?sport=\(sportKey)"
        guard let url = URL(string: urlString) else { isLoading = false; return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-apisports-key")
        URLSession.shared.dataTask(with: request) { data, _, err in
            DispatchQueue.main.async {
                isLoading = false
                if let err = err { error = IdentifiableError(message: err.localizedDescription); return }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let response = json["response"] as? [[String: Any]] else { error = IdentifiableError(message: "Failed to load leagues"); return }
                leagues = response.compactMap { dict in
                    if let league = dict["league"] as? [String: Any],
                       let id = league["id"] as? Int,
                       let name = league["name"] as? String {
                        return (id: id, name: name)
                    }
                    return nil
                }
            }
        }.resume()
    }
    
    private func fetchTeams(for leagueID: Int, sportKey: String) {
        isLoading = true
        error = nil
        let apiKey = "dd06c346e5161e49a8908022ab081232"
        let urlString = "https://v3.football.api-sports.io/teams?league=\(leagueID)&season=2023"
        guard let url = URL(string: urlString) else { isLoading = false; return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-apisports-key")
        URLSession.shared.dataTask(with: request) { data, _, err in
            DispatchQueue.main.async {
                isLoading = false
                if let err = err { error = IdentifiableError(message: err.localizedDescription); return }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let response = json["response"] as? [[String: Any]] else { error = IdentifiableError(message: "Failed to load teams"); return }
                teams = response.compactMap { dict in
                    if let team = dict["team"] as? [String: Any],
                       let name = team["name"] as? String {
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
    
    private func removeSport(_ sport: FavoriteSport) {
        viewModel.favoriteSports.removeAll { $0.id == sport.id }
    }
    
    private func removeTeam(sport: FavoriteSport, team: FavoriteTeam) {
        if let index = viewModel.favoriteSports.firstIndex(where: { $0.id == sport.id }) {
            viewModel.favoriteSports[index].teams.removeAll { $0.id == team.id }
            if viewModel.favoriteSports[index].teams.isEmpty {
                viewModel.favoriteSports.remove(at: index)
            }
        }
    }
}

struct IdentifiableError: Identifiable {
    let id = UUID()
    let message: String
}

struct ExpandingBubbleCloudView: View {
    let items: [String]
    let childMap: [String: [String]]
    let onSelect: (String) -> Void
    let expanded: String?
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            if let expanded = expanded, let children = childMap[expanded] {
                // Dimmed background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }
                // Expanded parent bubble
                BubbleView(
                    label: expanded,
                    isSelected: true,
                    size: 160,
                    onTap: {}
                )
                .position(x: UIScreen.main.bounds.width/2, y: 200)
                // Child bubbles
                let enumerated = Array(children.enumerated())
                ForEach(enumerated, id: \.0) { idx, child in
                    let angle = Double(idx) / Double(children.count) * 2 * .pi
                    let radius: CGFloat = 120
                    let x = cos(angle) * radius + UIScreen.main.bounds.width/2
                    let y = sin(angle) * radius + 200
                    BubbleView(
                        label: child,
                        isSelected: false,
                        size: 70,
                        onTap: {}
                    )
                    .position(x: x, y: y)
                    .transition(.scale)
                }
            } else {
                GeometryReader { geo in
                    ZStack {
                        let enumerated = Array(items.enumerated())
                        ForEach(enumerated, id: \.0) { idx, item in
                            let angle = Double(idx) / Double(items.count) * 2 * .pi
                            let radius = min(geo.size.width, geo.size.height) / 2.5
                            let x = cos(angle) * radius + geo.size.width/2
                            let y = sin(angle) * radius + geo.size.height/2
                            BubbleView(
                                label: item,
                                isSelected: false,
                                size: CGFloat(80 + (idx % 3) * 20),
                                onTap: { onSelect(item) }
                            )
                            .position(x: x, y: y)
                        }
                    }
                }
            }
        }
        .animation(.spring(), value: expanded)
    }
}

struct BubbleView: View {
    let label: String
    let isSelected: Bool
    let size: CGFloat
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.pink.opacity(0.8))
                .frame(width: size, height: size)
                .overlay(
                    Text(label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(8)
                )
                .scaleEffect(isSelected ? 1.15 : 1.0)
                .shadow(radius: isSelected ? 10 : 4)
                .animation(.spring(), value: isSelected)
        }
        .buttonStyle(.plain)
    }
} 
