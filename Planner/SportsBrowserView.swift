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
                                        ForEach(["Football", "Basketball", "Tennis", "Cricket", "Baseball"], id: \.self) { sport in
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
                                            
                                            // National Teams button
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
        default:
            leagues = []
        }
        
        isLoading = false
    }
    
    private func fetchTeams(for league: String, sport: String) {
        isLoading = true
        teams = []
        
        // For football, we can use real teams
        if sport == "Football" {
            switch league {
            case "Premier League":
                teams = [
                    FavoriteTeam(name: "Manchester United"),
                    FavoriteTeam(name: "Liverpool"),
                    FavoriteTeam(name: "Chelsea"),
                    FavoriteTeam(name: "Arsenal"),
                    FavoriteTeam(name: "Manchester City"),
                    FavoriteTeam(name: "Tottenham Hotspur"),
                    FavoriteTeam(name: "Leicester City"),
                    FavoriteTeam(name: "West Ham United")
                ]
            case "La Liga":
                teams = [
                    FavoriteTeam(name: "Real Madrid"),
                    FavoriteTeam(name: "Barcelona"),
                    FavoriteTeam(name: "Atletico Madrid"),
                    FavoriteTeam(name: "Sevilla"),
                    FavoriteTeam(name: "Valencia"),
                    FavoriteTeam(name: "Villarreal")
                ]
            case "Serie A":
                teams = [
                    FavoriteTeam(name: "Juventus"),
                    FavoriteTeam(name: "Inter Milan"),
                    FavoriteTeam(name: "AC Milan"),
                    FavoriteTeam(name: "Napoli"),
                    FavoriteTeam(name: "Roma"),
                    FavoriteTeam(name: "Lazio")
                ]
            case "Bundesliga":
                teams = [
                    FavoriteTeam(name: "Bayern Munich"),
                    FavoriteTeam(name: "Borussia Dortmund"),
                    FavoriteTeam(name: "RB Leipzig"),
                    FavoriteTeam(name: "Bayer Leverkusen"),
                    FavoriteTeam(name: "Eintracht Frankfurt")
                ]
            case "Ligue 1":
                teams = [
                    FavoriteTeam(name: "Paris Saint-Germain"),
                    FavoriteTeam(name: "Marseille"),
                    FavoriteTeam(name: "Lyon"),
                    FavoriteTeam(name: "Monaco"),
                    FavoriteTeam(name: "Lille")
                ]
            default:
                teams = []
            }
        } else if sport == "Basketball" {
            switch league {
            case "NBA":
                teams = [
                    FavoriteTeam(name: "Los Angeles Lakers"),
                    FavoriteTeam(name: "Boston Celtics"),
                    FavoriteTeam(name: "Golden State Warriors"),
                    FavoriteTeam(name: "Chicago Bulls"),
                    FavoriteTeam(name: "Miami Heat")
                ]
            case "EuroLeague":
                teams = [
                    FavoriteTeam(name: "Real Madrid"),
                    FavoriteTeam(name: "Barcelona"),
                    FavoriteTeam(name: "CSKA Moscow"),
                    FavoriteTeam(name: "Fenerbahçe")
                ]
            default:
                teams = []
            }
        } else {
            // For other sports, use generic team names for now
            teams = [
                FavoriteTeam(name: "\(league) Team 1"),
                FavoriteTeam(name: "\(league) Team 2"),
                FavoriteTeam(name: "\(league) Team 3"),
                FavoriteTeam(name: "\(league) Team 4")
            ]
        }
        
        isLoading = false
    }
    
    private func addTeamToFavorites(sport: String, team: FavoriteTeam) {
        // Check if this sport already exists in favorites
        if let index = viewModel.favoriteSports.firstIndex(where: { $0.name == sport }) {
            // Check if this team is already in favorites
            if !viewModel.favoriteSports[index].teams.contains(where: { $0.name == team.name }) {
                viewModel.favoriteSports[index].teams.append(team)
            }
        } else {
            // Add new sport with this team
            viewModel.favoriteSports.append(FavoriteSport(name: sport, teams: [team]))
        }
        
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
