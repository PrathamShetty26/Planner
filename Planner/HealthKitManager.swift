import Foundation
import HealthKit

class HealthKitManager {
    let healthStore = HKHealthStore()

    // Check if HealthKit is available on the device
    static var isHealthDataAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }

    // Data types to read
    private var readTypes: Set<HKObjectType> {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return []
        }
        return [stepType, activeEnergyType]
    }

    // Request authorization from the user
    func requestAuthorization() async throws {
        guard HealthKitManager.isHealthDataAvailable else {
            throw HealthError.notAvailableOnDevice
        }

        // This method is natively async since iOS 15
        try await healthStore.requestAuthorization(toShare: Set<HKSampleType>(), read: readTypes)
    }

    // Fetch step count for a given date using async/await
    func fetchStepCount(for date: Date) async throws -> Double {
        try await fetchCumulativeSum(for: .stepCount, unit: .count(), on: date)
    }

    // Fetch active energy for a given date using async/await
    func fetchActiveEnergy(for date: Date) async throws -> Double {
        try await fetchCumulativeSum(for: .activeEnergyBurned, unit: .kilocalorie(), on: date)
    }

    // Generic function to fetch cumulative sum for a given quantity type
    private func fetchCumulativeSum(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, on date: Date) async throws -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthError.dataTypeNotAvailable
        }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        // Using withCheckedThrowingContinuation to propagate errors
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    // If the error is simply that no data exists for the query, treat it as 0.
                    if (error as? HKError)?.code == .errorDataNotAvailable {
                        continuation.resume(returning: 0.0)
                    } else {
                        // For all other errors, propagate them.
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                guard let result = result, let sum = result.sumQuantity() else {
                    // If there's no error but also no sum, it means no data for that day. Return 0.
                    continuation.resume(returning: 0.0)
                    return
                }
                
                continuation.resume(returning: sum.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }
}

enum HealthError: Error {
    case notAvailableOnDevice
    case dataTypeNotAvailable
}