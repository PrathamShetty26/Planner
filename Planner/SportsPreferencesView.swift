import SwiftUI

struct SportsPreferencesView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @Binding var isPresented: Bool
    @State private var selectedSport: String = ""
    @State private var teamSearch: String = ""
    @State private var tempSports: [FavoriteSport] = []
    @State private var searchResults: [FavoriteTeam] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? = nil
    
    let availableSports = ["Football", "Basketball", "Cricket", "Tennis"] // You can expand this
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Choose Sports")) {
                    Picker("Sport", selection: $selectedSport) {
                        ForEach(availableSports, id: \.self) { sport in
                            Text(sport)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if !selectedSport.isEmpty {
                    Section(header: Text("Search Teams for \(selectedSport)")) {
                        TextField("Search Team Name", text: $teamSearch)
                            .onChange(of: teamSearch) { newValue in
                                searchTask?.cancel()
                                if newValue.count > 1 {
                                    isSearching = true
                                    searchTask = Task {
                                        await searchTeams(query: newValue, sport: selectedSport)
                                    }
                                } else {
                                    searchResults = []
                                    isSearching = false
                                }
                            }
                        if isSearching {
                            ProgressView()
                        }
                        ForEach(searchResults) { team in
                            Button(action: { addTeam(team) }) {
                                Text(team.name)
                            }
                        }
                        if let sportIndex = tempSports.firstIndex(where: { $0.name == selectedSport }) {
                            ForEach(tempSports[sportIndex].teams) { team in
                                HStack {
                                    Text(team.name)
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                            .onDelete { indices in
                                tempSports[sportIndex].teams.remove(atOffsets: indices)
                            }
                        }
                    }
                }
                if !tempSports.isEmpty {
                    Section(header: Text("Your Favorites")) {
                        ForEach(tempSports) { sport in
                            VStack(alignment: .leading) {
                                Text(sport.name).bold()
                                Text(sport.teams.map { $0.name }.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete { indices in
                            tempSports.remove(atOffsets: indices)
                        }
                    }
                }
            }
            .navigationTitle("Favorite Sports")
            .navigationBarItems(leading: Button("Cancel") { isPresented = false }, trailing: Button("Save") {
                viewModel.favoriteSports = tempSports
                isPresented = false
            }.disabled(tempSports.isEmpty))
            .onAppear {
                tempSports = viewModel.favoriteSports
            }
        }
    }
    
    private func addTeam(_ team: FavoriteTeam) {
        guard !selectedSport.isEmpty else { return }
        if let index = tempSports.firstIndex(where: { $0.name == selectedSport }) {
            if !tempSports[index].teams.contains(team) {
                tempSports[index].teams.append(team)
            }
        } else {
            tempSports.append(FavoriteSport(name: selectedSport, teams: [team]))
        }
        teamSearch = ""
        searchResults = []
    }
    
    private func searchTeams(query: String, sport: String) async {
        // Only Football is supported for now
        guard sport == "Football" else { searchResults = []; isSearching = false; return }
        let apiKey = "3215f5cdc36a0197b86f6090c7666c2d"
        let urlString = "https://v3.football.api-sports.io/teams?search=\(query)"
        guard let url = URL(string: urlString) else { searchResults = []; isSearching = false; return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-apisports-key")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let response = json["response"] as? [[String: Any]] {
                let teams: [FavoriteTeam] = response.compactMap { dict in
                    if let teamDict = dict["team"] as? [String: Any],
                       let name = teamDict["name"] as? String {
                        return FavoriteTeam(name: name)
                    }
                    return nil
                }
                await MainActor.run {
                    searchResults = teams
                    isSearching = false
                }
            } else {
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        } catch {
            await MainActor.run {
                searchResults = []
                isSearching = false
            }
        }
    }
} 
