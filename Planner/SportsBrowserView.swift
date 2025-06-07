import SwiftUI

struct SportsBrowserView: View {
    @StateObject var viewModel: PlannerViewModel
    @Binding var isPresented: Bool
    @State private var sports: [String] = []
    @State private var leagues: [String] = []
    @State private var teams: [FavoriteTeam] = []
    @State private var selectedSport: String? = nil
    @State private var selectedLeague: String? = nil
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
                Group { dynamicContentView }
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
                            FavoriteSportView(
                                sport: sport,
                                removeSport: { removeSport(sport.name) },
                                removeTeam: { team in removeTeam(sport: sport.name, team: team.name) }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    @ViewBuilder
    private var dynamicContentView: some View {
        Group {
            if selectedSport != nil {
                leagueOrTeamView
            } else if !sports.isEmpty {
                sportsView
            } else {
                EmptyView()
            }
        }
        if isLoading {
            ProgressView().padding()
        }
    }

    @ViewBuilder
    private var leagueOrTeamView: some View {
        if selectedLeague != nil {
            ExpandingBubbleCloudView(
                items: teams.map { $0.name },
                onSelect: { _ in },
                expanded: nil,
                onDismiss: { self.selectedLeague = nil }
            )
            .frame(height: 500)
        } else {
            ExpandingBubbleCloudView(
                items: leagues,
                onSelect: { league in self.selectedLeague = league },
                expanded: nil,
                onDismiss: { self.selectedSport = nil }
            )
            .frame(height: 500)
        }
    }

    private var sportsView: some View {
        ExpandingBubbleCloudView(
            items: sports,
            onSelect: { sport in self.selectedSport = sport },
            expanded: nil,
            onDismiss: { }
        )
        .frame(height: 500)
    }
    
    private func fetchSports() {
        isLoading = true
        error = nil
        let apiKey = "3de6c9f8e325a86ac7613b56fd8f85fc"
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
                    dict["name"] as? String
                }
            }
        }.resume()
    }
    
    private func fetchLeagues(for sport: String) {
        isLoading = true
        error = nil
        let apiKey = "3de6c9f8e325a86ac7613b56fd8f85fc"
        let urlString = "https://v3.football.api-sports.io/leagues?sport=\(sport)"
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
                    if let league = dict["league"] as? [String: Any], let name = league["name"] as? String {
                        return name
                    }
                    return nil
                }
            }
        }.resume()
    }
    
    private func fetchTeams(for league: String) {
        isLoading = true
        error = nil
        let apiKey = "3de6c9f8e325a86ac7613b56fd8f85fc"
        let urlString = "https://v3.football.api-sports.io/teams?league=\(league)&season=2023"
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
                    if let team = dict["team"] as? [String: Any], let name = team["name"] as? String {
                        return FavoriteTeam(name: name)
                    }
                    return nil
                }
            }
        }.resume()
    }
    
    private func addTeamToFavorites(sport: String, team: String) {
        let favTeam = FavoriteTeam(name: team)
        if let index = viewModel.favoriteSports.firstIndex(where: { $0.name == sport }) {
            if !viewModel.favoriteSports[index].teams.contains(favTeam) {
                viewModel.favoriteSports[index].teams.append(favTeam)
            }
        } else {
            viewModel.favoriteSports.append(FavoriteSport(name: sport, teams: [favTeam]))
        }
    }
    
    private func removeSport(_ sport: String) {
        viewModel.favoriteSports.removeAll { $0.name == sport }
    }
    
    private func removeTeam(sport: String, team: String) {
        let favTeam = FavoriteTeam(name: team)
        if let index = viewModel.favoriteSports.firstIndex(where: { $0.name == sport }) {
            viewModel.favoriteSports[index].teams.removeAll { $0 == favTeam }
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
    let onSelect: (String) -> Void
    let expanded: String?
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            if let expanded = expanded {
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
            } else {
                GeometryReader { geo in
                    ZStack {
                        ForEach(0..<items.count, id: \.self) { idx in
                            let item = items[idx]
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

private struct FavoriteSportView: View {
    let sport: FavoriteSport
    let removeSport: () -> Void
    let removeTeam: (FavoriteTeam) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sport.name).bold()
                Spacer()
                Button(action: { removeSport() }) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
            }
            ForEach(sport.teams) { team in
                HStack {
                    Text(team.name)
                    Spacer()
                    Button(action: { removeTeam(team) }) {
                        Image(systemName: "minus.circle").foregroundColor(.red)
                    }
                }
            }
        }
    }
}
