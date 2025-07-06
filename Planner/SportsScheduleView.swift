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
        .onAppear {
            Task {
                await loadSchedule()
            }
        }
    }
    
    @MainActor
    private func loadSchedule() async {
        isLoading = true
        // Create a local, unwrapped reference to the viewModel to avoid compiler confusion.
        let localViewModel = self.viewModel
        let today = Calendar.current.startOfDay(for: Date())
        schedule = await localViewModel.fetchSportsSchedule(for: today)
        isLoading = false
    }
}
