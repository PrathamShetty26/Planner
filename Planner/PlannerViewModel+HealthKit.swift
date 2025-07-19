import Foundation
import HealthKit

extension PlannerViewModel {

    // MARK: - HealthKit Integration

    /// Presents the official HealthKit permission sheet to the user.
    @MainActor
    public func requestHealthKitPermission() async {
        do {
            // This shows the system's permission sheet. The `await` pauses execution
            // until the user makes a choice.
            try await healthKitManager.requestAuthorization()

            // IMPORTANT: There is a known race condition where the OS needs a moment
            // to update the app's authorization status after the prompt is dismissed.
            // A short, non-blocking delay gives the system time to process the change.
            try? await Task.sleep(for: .milliseconds(500))

            // After the user makes a choice, we must immediately re-check the status
            // to update the UI and fetch data if permission was granted.
            await self.checkHealthKitAuthorization()
        } catch {
            self.permissionErrorMessage = "Please enable Health access in Settings. Error: \(error.localizedDescription)"
            self.showSettingsPrompt = true
        }
    }

    /// Checks the current HealthKit authorization status, updates the UI state, and fetches data if permitted.
    /// This is the main workhorse function for keeping HealthKit data in sync.
    @MainActor
    public func checkHealthKitAuthorization() async {
        // Safely unwrap the health data types we need to check.
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            // This is a developer error state, meaning the identifiers are wrong.
            // We should treat this as if access is denied.
            self.healthKitAuthorizationStatus = .sharingDenied
            // Clear data if we can't even check status
            self.steps = 0
            self.activeEnergy = 0
            return
        }

        let stepStatus = healthKitManager.healthStore.authorizationStatus(for: stepType)
        let energyStatus = healthKitManager.healthStore.authorizationStatus(for: energyType)

        // Determine the aggregate authorization status for the UI.
        if stepStatus == .notDetermined || energyStatus == .notDetermined {
            // If any permission is still not determined, we show the 'Enable' button.
            self.healthKitAuthorizationStatus = .notDetermined
        } else if stepStatus == .sharingAuthorized || energyStatus == .sharingAuthorized {
            // If at least ONE permission is granted, we show the green checkmark.
            self.healthKitAuthorizationStatus = .sharingAuthorized
        } else {
            // Only if BOTH are denied do we show the 'Open Settings' button.
            self.healthKitAuthorizationStatus = .sharingDenied
        }

        print("HealthKit: UI status determined as \(self.healthKitAuthorizationStatus.rawValue)")

        // Fetch data if the feature is enabled in the app's settings.
        // The fetch function itself will handle which specific data points to get based on permissions.
        if self.showHealthData {
            await self.fetchHealthData(for: self.currentlyDisplayedDate)
        } else {
            // If the user has the feature toggled off, clear the data.
            self.steps = 0
            self.activeEnergy = 0
        }
    }

    /// Fetches health data for a specific date. This function is now robust against partial permissions.
    @MainActor
    public func fetchHealthData(for date: Date) async {
        print("HealthKit: Fetching data for \(date)...")
        
        // Reset values before fetching to avoid showing stale data from a previous day.
        self.steps = 0
        self.activeEnergy = 0

        // Fetch steps and energy concurrently but handle errors individually.
        // This ensures that if one fails (e.g., permission denied), the other can still succeed.
        async let stepsResult: Result<Double, Error> = Task { try await healthKitManager.fetchStepCount(for: date) }.result
        async let energyResult: Result<Double, Error> = Task { try await healthKitManager.fetchActiveEnergy(for: date) }.result

        if case .success(let steps) = await stepsResult {
            self.steps = steps
        }

        if case .success(let energy) = await energyResult {
            self.activeEnergy = energy
        }
    }
}