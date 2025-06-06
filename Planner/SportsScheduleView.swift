import SwiftUI

struct SportsScheduleView: View {
    @ObservedObject var viewModel: PlannerViewModel
    @State private var schedule: [TimelineItem] = []
    @State private var isLoading = true
    @State private var today: Date = Calendar.current.startOfDay(for: Date())
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLoading {
                ProgressView("Loading schedule...")
            } else if schedule.isEmpty {
                Text("No upcoming matches found.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(schedule) { match in
                    HStack {
                        Text(match.title)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        if let time = match.time {
                            Text(time, style: .time)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear(perform: loadSchedule)
    }
    
    private func loadSchedule() {
        isLoading = true
        viewModel.fetchSportsSchedule(for: today) { result in
            schedule = result
            isLoading = false
        }
    }
} 