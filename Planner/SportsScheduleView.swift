import SwiftUI

struct SportsScheduleView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @State private var schedule: [TimelineItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLoading {
                ProgressView("Loading schedule...")
                    .padding(.vertical, 8)
            } else if let error = errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.vertical, 4)
            } else if schedule.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No upcoming games found for your favorite teams.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    if viewModel.favoriteSports.isEmpty {
                        Text("Add favorite teams in Settings to see their schedule.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Try selecting different teams or check back later.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                ForEach(schedule) { match in
                    HStack {
                        Text(match.title)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let time = match.time {
                            Text(time, style: .time)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .onAppear(perform: loadSchedule)
    }
    
    private func loadSchedule() {
        isLoading = true
        
        // Get today's date
        let today = Calendar.current.startOfDay(for: Date())
        
        // Only look ahead for the next 3 days (free API plan limitation)
        viewModel.fetchSportsSchedule(for: today) { items in
            DispatchQueue.main.async {
                self.schedule = items
                self.isLoading = false
            }
        }
    }
}
