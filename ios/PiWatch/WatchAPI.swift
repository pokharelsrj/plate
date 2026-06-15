import Foundation
import WatchConnectivity

enum WatchAPIError: LocalizedError {
    case phoneUnreachable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .phoneUnreachable: return "iPhone unreachable — keep it nearby."
        case .server(let msg): return msg
        }
    }
}

/// All networking goes through the paired iPhone (which holds the credentials
/// and the VPN/LAN path). Requests are WatchConnectivity messages; the phone
/// replies with the API's JSON.
final class WatchAPI: NSObject, WCSessionDelegate {
    static let shared = WatchAPI()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func activate() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func request<T: Decodable>(_ payload: [String: Any]) async throws -> T {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            throw WatchAPIError.phoneUnreachable
        }
        let reply: [String: Any] = try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(payload, replyHandler: { reply in
                continuation.resume(returning: reply)
            }, errorHandler: { error in
                continuation.resume(throwing: WatchAPIError.server(error.localizedDescription))
            })
        }
        if let message = reply["error"] as? String {
            throw WatchAPIError.server(message)
        }
        guard let data = reply["data"] as? Data else {
            throw WatchAPIError.server("Empty reply from iPhone")
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    // MARK: - Typed calls

    func exercises() async throws -> ExercisesResponse {
        try await request(["action": "exercises"])
    }

    func workout(date: String, exerciseId: Int64?) async throws -> WorkoutResponse {
        var payload: [String: Any] = ["action": "workout", "date": date]
        if let exerciseId { payload["exerciseId"] = NSNumber(value: exerciseId) }
        return try await request(payload)
    }

    func addSet(date: String, exerciseId: Int64, reps: Int, weightLbs: Double?) async throws -> WorkoutSet {
        var payload: [String: Any] = [
            "action": "addSet", "date": date,
            "exerciseId": NSNumber(value: exerciseId), "reps": NSNumber(value: reps),
        ]
        if let weightLbs { payload["weightLbs"] = NSNumber(value: weightLbs) }
        return try await request(payload)
    }

    // MARK: - Timer mirroring (best-effort, no reply needed)

    func notifyTimerStarted(_ startedAt: Date, exercise: String) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([
            "timer": "started",
            "startedAt": NSNumber(value: startedAt.timeIntervalSince1970),
            "exercise": exercise,
        ], replyHandler: nil, errorHandler: nil)
    }

    func notifyTimerEnded() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["timer": "ended"], replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Delegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}
