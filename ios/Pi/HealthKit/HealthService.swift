import Foundation
import HealthKit

/// Reads steps / active energy / resting HR / sleep from HealthKit and
/// pushes them to the Pi's /api/health/ingest endpoint.
@MainActor
final class HealthService: ObservableObject {
    static let shared = HealthService()

    private let store = HKHealthStore()
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date? = UserDefaults.standard.object(forKey: "health.lastSyncAt") as? Date

    /// Days pushed by the scheduled full sync — roughly a year of history.
    static let fullSyncDays = 365
    /// Days pushed by every background catch-up so recent edits are never missed.
    static let backgroundSyncDays = 2

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.restingHeartRate),
            HKCategoryType(.sleepAnalysis),
        ]
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Serialized sync entry points

    /// Tail of the serial sync chain — guarantees background and foreground syncs
    /// run one at a time. The ingest endpoint upserts by date, so overlapping
    /// ranges only ever refresh the same rows (overlaps are harmless).
    private var syncChain: Task<Void, Never> = Task {}

    @discardableResult
    private func enqueue(_ op: @escaping () async throws -> Void) -> Task<Void, Error> {
        let previous = syncChain
        let work = Task { () async throws -> Void in
            await previous.value
            try await op()
        }
        syncChain = Task { _ = try? await work.value }
        return work
    }

    /// Push the last `daysBack` days of HealthKit data to the Pi.
    func sync(daysBack: Int = 7, client: APIClient) async throws {
        try await enqueue { [weak self] in
            try await self?.performSync(daysBack: daysBack, client: client)
        }.value
    }

    /// Push a single day's HealthKit data to the Pi.
    func syncDay(_ date: Date, client: APIClient) async throws {
        try await enqueue { [weak self] in
            try await self?.performSyncDay(date, client: client)
        }.value
    }

    private func performSync(daysBack: Int, client: APIClient) async throws {
        guard Self.isAvailable else { return }
        isSyncing = true
        defer { isSyncing = false }

        var days: [HealthDay] = []
        let cal = Calendar.current
        for offset in 0..<daysBack {
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            if let payload = try? await read(date: day) {
                days.append(payload)
            }
        }
        guard !days.isEmpty else { return }
        try await client.ingestHealth(days: days)
        lastSyncAt = Date()
        UserDefaults.standard.set(lastSyncAt, forKey: "health.lastSyncAt")
    }

    private func performSyncDay(_ date: Date, client: APIClient) async throws {
        guard Self.isAvailable else { return }
        isSyncing = true
        defer { isSyncing = false }
        let payload = try await read(date: date)
        try await client.ingestHealth(days: [payload])
        lastSyncAt = Date()
        UserDefaults.standard.set(lastSyncAt, forKey: "health.lastSyncAt")
    }

    // MARK: - Background delivery

    private var backgroundStarted = false
    private var observerQueries: [HKObserverQuery] = []

    /// Registers HealthKit background delivery so the system wakes the app when
    /// new samples are written; each wake pushes the last couple of days. Safe to
    /// call repeatedly — it only wires up once per launch.
    func startBackgroundDelivery() {
        guard Self.isAvailable, !backgroundStarted else { return }
        backgroundStarted = true

        for type in readTypes.compactMap({ $0 as? HKSampleType }) {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                Task { @MainActor in
                    if let client = Session.backgroundClient() {
                        try? await self?.sync(daysBack: Self.backgroundSyncDays, client: client)
                    }
                    completion()
                }
            }
            store.execute(query)
            observerQueries.append(query)
        }
    }

    /// Read one calendar day's metrics.
    func read(date: Date) async throws -> HealthDay {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!

        async let steps = sumQuantity(.stepCount, unit: .count(), from: dayStart, to: dayEnd)
        async let energy = sumQuantity(.activeEnergyBurned, unit: .kilocalorie(), from: dayStart, to: dayEnd)
        async let restingHR = averageQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: dayStart, to: dayEnd)
        async let sleep = sleepStages(endingOn: date)

        let (s, e, hr, sl) = try await (steps, energy, restingHR, sleep)

        return HealthDay(
            date: PiDate.dayString(date),
            steps: s.map { Int($0) },
            activeCalories: e,
            restingHr: hr,
            sleepAsleepH: sl.asleep > 0 ? sl.asleep : nil,
            sleepDeepH: sl.deep > 0 ? sl.deep : nil,
            sleepRemH: sl.rem > 0 ? sl.rem : nil,
            sleepCoreH: sl.core > 0 ? sl.core : nil,
            sleepAwakeH: sl.awake > 0 ? sl.awake : nil
        )
    }

    // MARK: - Queries

    private func sumQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async throws -> Double? {
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func averageQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async throws -> Double? {
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .discreteAverage) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private struct SleepTotals {
        var asleep = 0.0, deep = 0.0, rem = 0.0, core = 0.0, awake = 0.0
    }

    /// Sleep for the night ending on `date` — samples between 6pm the prior evening and 6pm of `date`.
    private func sleepStages(endingOn date: Date) async throws -> SleepTotals {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let windowStart = cal.date(byAdding: .hour, value: -6, to: dayStart)!
        let windowEnd = cal.date(byAdding: .hour, value: 18, to: dayStart)!
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        var totals = SleepTotals()
        for sample in samples {
            let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .awake:
                totals.awake += hours
            case .asleepDeep:
                totals.deep += hours
            case .asleepREM:
                totals.rem += hours
            case .asleepCore, .asleepUnspecified:
                totals.core += hours
            default:
                break
            }
        }
        totals.asleep = totals.deep + totals.rem + totals.core
        return totals
    }
}
