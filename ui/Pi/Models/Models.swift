import Foundation

// All API JSON uses snake_case; the shared decoder/encoder in APIClient
// converts to/from these camelCase property names.

struct User: Codable, Identifiable, Hashable {
    let id: Int64
    let email: String
    var displayName: String?
    var role: String
    var dateOfBirth: String?
    var sex: String?
    var isActive: Bool?
    var createdAt: String?

    var isAdmin: Bool { role == "admin" }
    var name: String { displayName ?? email }
}

struct LoginResponse: Codable {
    let user: User
    let apiKey: String
}

struct PingResponse: Codable {
    let ok: Bool
    let version: String?
    let serverTime: String?
}

struct RotateKeyResponse: Codable {
    let apiKey: String
}

struct ExercisePR: Codable, Hashable {
    let maxWeightLbs: Double?
    let maxReps: Int

    var label: String {
        if let w = maxWeightLbs {
            let wStr = w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
            return "PR: \(wStr) lb × \(maxReps)"
        }
        return "PR: \(maxReps) reps"
    }
}

struct Exercise: Codable, Identifiable, Hashable {
    let id: Int64
    var name: String
    var bodyPart: String?
    var setCount: Int?
    var pr: ExercisePR?
}

struct ExercisesResponse: Codable {
    let exercises: [Exercise]
    let bodyParts: [String]
}

struct BodyPartTag: Codable, Identifiable, Hashable {
    let name: String
    let exerciseCount: Int
    var id: String { name }
}

struct BodyPartsResponse: Codable {
    let bodyParts: [BodyPartTag]
}

struct WorkoutSet: Codable, Identifiable, Hashable {
    let id: Int64
    let date: String
    let exerciseId: Int64
    var reps: Int
    var weightLbs: Double?
}

struct WorkoutGroup: Codable, Identifiable, Hashable {
    var id: Int64 { exerciseId }
    let exerciseId: Int64
    let exerciseName: String
    let bodyPart: String?
    let sets: [WorkoutSet]
}

struct WorkoutActive: Codable, Hashable {
    let exerciseId: Int64
    let exerciseName: String
    let bodyPart: String?
    let prefillReps: Int
    let prefillWeightLbs: Double?
    let todaySets: [WorkoutSet]
    let lastSessionDate: String?
    let lastSessionSets: [WorkoutSet]
}

struct WorkoutResponse: Codable {
    let date: String
    let totalSets: Int
    let exerciseCount: Int
    let groups: [WorkoutGroup]
    let active: WorkoutActive?
}

struct BodyMetric: Codable, Identifiable, Hashable {
    var id: String { date }
    let date: String
    let weightLbs: Double?
    let chestMm: Double?
    let abdomenMm: Double?
    let thighMm: Double?
    let bfPercent: Double?
}

struct BodyResponse: Codable {
    let history: [BodyMetric]
    let latestWeightLbs: Double?
    let latestBfPercent: Double?
}

struct HealthDay: Codable, Hashable {
    let date: String
    let steps: Int?
    let activeCalories: Double?
    let restingHr: Double?
    let sleepAsleepH: Double?
    let sleepDeepH: Double?
    let sleepRemH: Double?
    let sleepCoreH: Double?
    let sleepAwakeH: Double?
}

struct TodaySnapshot: Codable {
    let date: String
    let gym: GymInfo?
    let nutrition: Nutrition?
    let health: HealthDay?
    let body: BodyMetric?
    let workout: WorkoutSummary?

    struct GymInfo: Codable {
        let checkins: [String]
    }
    struct Nutrition: Codable {
        let calories: Double?
        let calorieBudget: Double?
        let proteinG: Double?
        let carbG: Double?
        let fatG: Double?
        let fibreG: Double?
    }
    struct WorkoutSummary: Codable {
        let totalSets: Int
        let exerciseCount: Int
        let groups: [WorkoutGroup]
    }
}

struct CalendarResponse: Codable {
    let view: String
    let label: String
    let prevDate: String
    let nextDate: String
    let today: String
    let cells: [CalendarCell]
    let stats: CalendarStats

    struct CalendarCell: Codable, Identifiable, Hashable {
        var id: String { date }
        let date: String
        let day: Int
        let inPeriod: Bool
        let isToday: Bool
        let hasGym: Bool
        let hasWorkout: Bool
        let hasWeight: Bool
        let hasCalories: Bool
        let calories: Double?
        let calorieBudget: Double?
        let hasSteps: Bool
        let steps: Int?
        let hasSleep: Bool
        let sleepHours: Double?
    }

    struct CalendarStats: Codable {
        let gymDays: Int
        let avgCalories: Double
        let avgSteps: Double
        let avgSleepH: Double
        let workoutDays: Int
        let totalSets: Int
    }
}

struct SyncStatusResponse: Codable {
    let sources: [SyncSource]
    let recentRuns: [SyncRun]

    struct SyncSource: Codable, Identifiable, Hashable {
        var id: String { name }
        let name: String
        let running: Bool
        let pushBased: Bool?
        let lastSuccessAt: String?
        let lastRecords: Int?
    }

    struct SyncRun: Codable, Identifiable, Hashable {
        let id: Int64
        let source: String
        let startedAt: String
        let completedAt: String?
        let status: String
        let recordsSynced: Int
        let errorMessage: String?
    }
}

struct TrendsResponse: Codable {
    let points: [TrendPoint]
    let rangeDays: Int
    let latestWeight: Double?
    let latestBf: Double?
    let avgCalories: Double?
    let avgSteps: Double?
    let avgSleep: Double?
    let gymDays: Double?
    let workoutDays: Int?
    let totalSets: Int?

    struct TrendPoint: Codable, Identifiable, Hashable {
        var id: String { date }
        let date: String
        let weightLbs: Double?
        let bfPercent: Double?
        let calories: Double?
        let steps: Int?
        let sleepAsleep: Double?
        let restingHr: Double?
        let gym: Bool
        let hasWorkout: Bool
    }
}

struct AdminUsersResponse: Codable {
    let users: [User]
}

struct AdminCreatedUser: Codable {
    let user: User
    let apiKey: String
}

// MARK: - Workout Stats

struct WorkoutStats: Codable {
    let rangeDays: Int
    let frequency: Frequency
    let prs: [PR]
    let weeklySets: [WeeklySets]
    let setsByBodyPart: [String: Int]
    let progressions: [Progression]

    struct Frequency: Codable {
        let totalSessions: Int
        let totalSets: Int
        let avgSetsPerSession: Double
        let sessionsPerWeek: Double
        let daysSinceLast: Int
        let weekStreak: Int
    }

    struct PR: Codable, Identifiable, Hashable {
        var id: Int64 { exerciseId }
        let exerciseId: Int64
        let exercise: String
        let bodyPart: String
        let sets: Int
        let isBodyweight: Bool
        let bestWeightLbs: Double?
        let bestWeightReps: Int
        let estOneRm: Double?
        let bestReps: Int
        let lastDate: String
    }

    struct WeeklySets: Codable, Identifiable, Hashable {
        var id: String { week }
        let week: String
        let label: String
        let byBodyPart: [String: Int]
        let total: Int
    }

    struct Progression: Codable, Identifiable, Hashable {
        var id: Int64 { exerciseId }
        let exerciseId: Int64
        let exercise: String
        let bodyPart: String
        let isBodyweight: Bool
        let points: [Point]

        struct Point: Codable, Hashable {
            let date: String
            let estOneRm: Double?
            let topWeight: Double?
            let bestReps: Int
        }
    }
}

// MARK: - Date helpers

enum PiDate {
    static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parseDay(_ s: String) -> Date? { dayFormat.date(from: s) }

    static func dayString(_ d: Date) -> String { dayFormat.string(from: d) }

    static var todayString: String { dayString(Date()) }

    static func parseISO(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }

    /// "Jun 11" style label from a YYYY-MM-DD string.
    static func shortLabel(_ s: String) -> String {
        guard let d = parseDay(s) else { return s }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Wednesday, June 11" style label.
    static func longLabel(_ s: String) -> String {
        guard let d = parseDay(s) else { return s }
        return d.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}
