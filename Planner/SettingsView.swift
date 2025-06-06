import SwiftUI
import EventKit
import UserNotifications

struct SettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: PlannerViewModel
    @State private var showCalendarPrompt = false
    @State private var showNotificationPrompt = false
    @State private var showSportsBrowser = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Calendar")) {
                    HStack {
                        Text("Calendar Sync")
                        Spacer()
                        if viewModel.calendarAccessStatus == .notDetermined {
                            Button("Enable") {
                                showCalendarPrompt = true
                            }
                        } else if viewModel.calendarAccessStatus == .authorized || viewModel.calendarAccessStatus == .fullAccess {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
                
                Section(header: Text("Notifications")) {
                    HStack {
                        Text("Task Reminders")
                        Spacer()
                        Button("Configure") {
                            showNotificationPrompt = true
                        }
                    }
                }
                
                Section(header: Text("Display")) {
                    Toggle("Show Completed Items", isOn: $viewModel.showCompletedItems)
                    Toggle("Group by Type", isOn: $viewModel.groupByType)
                }
                
                Section(header: Text("Sports")) {
                    Button(action: { showSportsBrowser = true }) {
                        HStack {
                            Text("Sports")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") { isPresented = false })
            .alert("Calendar Access", isPresented: $showCalendarPrompt) {
                Button("Allow Access") {
                    Task {
                        await viewModel.requestCalendarPermission()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Allow access to sync your events with the calendar?")
            }
            .alert("Notifications", isPresented: $showNotificationPrompt) {
                Button("Enable") {
                    Task {
                        await viewModel.requestNotificationPermission()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Enable notifications for task reminders?")
            }
            .fullScreenCover(isPresented: $showSportsBrowser) {
                SportsBrowserView(viewModel: viewModel, isPresented: $showSportsBrowser)
            }
        }
    }
}

#Preview {
    SettingsView(isPresented: .constant(true), viewModel: PlannerViewModel())
} 