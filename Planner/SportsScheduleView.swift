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
                Text("No upcoming matches found. The free API plan only allows access to matches within 3 days of today.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
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
