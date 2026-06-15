import Foundation
import WatchConnectivity

/// Relays watch requests to the Pi API. The watch never talks to the server
/// directly — the phone owns the credentials and the VPN/LAN path, so the
/// watch works anywhere the phone does. Also mirrors the watch's rest timer
/// into the phone's persisted timer + Live Activity.
final class WatchRelay: NSObject, WCSessionDelegate {
    static let shared = WatchRelay()
    var session: Session?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Request relay (sendMessage with reply)

    func session(_ wcSession: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            replyHandler(await self.handle(message))
        }
    }

    @MainActor
    private func handle(_ message: [String: Any]) async -> [String: Any] {
        guard let session, session.isAuthenticated else {
            return ["error": "Not signed in on iPhone"]
        }
        let client = session.client
        do {
            switch message["action"] as? String {
            case "exercises":
                return try encodeReply(try await client.exercises())
            case "workout":
                let date = message["date"] as? String ?? PiDate.todayString
                let eid = (message["exerciseId"] as? NSNumber)?.int64Value ?? 0
                return try encodeReply(try await client.workout(date: date, exerciseId: eid > 0 ? eid : nil))
            case "addSet":
                let date = message["date"] as? String ?? PiDate.todayString
                let eid = (message["exerciseId"] as? NSNumber)?.int64Value ?? 0
                let reps = (message["reps"] as? NSNumber)?.intValue ?? 0
                let weight = (message["weightLbs"] as? NSNumber)?.doubleValue
                let set = try await client.addSet(date: date, exerciseId: eid, reps: reps,
                                                  weightLbs: (weight ?? 0) > 0 ? weight : nil)
                return try encodeReply(set)
            default:
                return ["error": "unknown action"]
            }
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    private func encodeReply<T: Encodable>(_ value: T) throws -> [String: Any] {
        ["data": try APIClient.encoder.encode(value)]
    }

    // MARK: - Rest timer mirroring (fire-and-forget messages)

    func session(_ wcSession: WCSession, didReceiveMessage message: [String: Any]) {
        guard let event = message["timer"] as? String else { return }
        let defaults = UserDefaults.standard
        Task { @MainActor in
            switch event {
            case "started":
                let t = Date(timeIntervalSince1970: (message["startedAt"] as? NSNumber)?.doubleValue
                             ?? Date().timeIntervalSince1970)
                defaults.set(t, forKey: RestTimerStore.startKey)
                defaults.set(true, forKey: RestTimerStore.manualMarkKey)
                defaults.removeObject(forKey: RestTimerStore.stoppedKey)
                RestActivity.start(startedAt: t, exerciseName: message["exercise"] as? String ?? "Workout")
            case "ended":
                if let started = defaults.object(forKey: RestTimerStore.startKey) as? Date {
                    defaults.set(started, forKey: RestTimerStore.stoppedKey)
                }
                defaults.removeObject(forKey: RestTimerStore.startKey)
                defaults.removeObject(forKey: RestTimerStore.manualMarkKey)
                RestActivity.end()
            default:
                break
            }
        }
    }

    // MARK: - Required delegate plumbing

    func session(_ wcSession: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ wcSession: WCSession) {}
    func sessionDidDeactivate(_ wcSession: WCSession) {
        wcSession.activate()
    }
}
