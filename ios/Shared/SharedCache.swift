import Foundation

/// Snapshot cache in the App Group container — written by the app after every
/// successful Today fetch, read by the widget on each timeline refresh.
enum SharedCache {
    static let groupID = "group.com.srijanpokharel.pi"

    struct CachedToday: Codable {
        let snapshot: TodaySnapshot
        let fetchedAt: Date
    }

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("today.json")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func write(_ snapshot: TodaySnapshot) {
        guard let url = fileURL,
              let data = try? encoder.encode(CachedToday(snapshot: snapshot, fetchedAt: Date())) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> CachedToday? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CachedToday.self, from: data)
    }
}
