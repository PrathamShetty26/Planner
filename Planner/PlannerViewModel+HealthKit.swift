import Foundation
import HealthKit

extension PlannerViewModel {

    // MARK: - HealthKit

    @MainActor
    public func fetchHealthData(for date: Date) async {
        guard showHealthData && healthKitAuthorizationStatus == .sharingAuthorized else { return }

        do {
            // Use async let to fetch steps and energy concurrently
            async let stepsTask = try healthKitManager.fetchStepCount(for: date)
            async let energyTask = try healthKitManager.fetchActiveEnergy(for: date)

            self.steps = try await stepsTask
            self.activeEnergy = try await energyTask
        } catch {
            print("Failed to fetch health data: \(error.localizedDescription)")
            self.steps = 0
            self.activeEnergy = 0
        }
    }

    @MainActor
    public func requestHealthKitPermission() async {
        do {
            // This presents the permission sheet to the user.
            try await healthKitManager.requestAuthorization()
            // After the user responds, we must check the new status to see what they chose.
            await self.checkInitialHealthKitStatus()
        } catch {
            self.healthKitAuthorizationStatus = .sharingDenied
            self.permissionErrorMessage = "Please enable Health access in Settings. Error: \(error.localizedDescription)"
            self.showSettingsPrompt = true
        }
    }

    @MainActor
    public func checkInitialHealthKitStatus() async {
        healthKitAuthorizationStatus = healthKitManager.healthStore.authorizationStatus(for: HKObjectType.quantityType(forIdentifier: .stepCount)!)
        if healthKitAuthorizationStatus == .sharingAuthorized {
            await fetchHealthData(for: Date())
        }
    }
}