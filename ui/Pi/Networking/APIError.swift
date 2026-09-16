import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case forbidden
    case notFound
    case conflict(String)
    case server(String)
    case decode(Error)
    case network(Error)
    case badURL

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired — sign in again."
        case .forbidden: return "You don't have permission to do that."
        case .notFound: return "Not found."
        case .conflict(let msg): return msg
        case .server(let msg): return msg
        case .decode: return "Unexpected response from the server."
        case .network(let err): return err.localizedDescription
        case .badURL: return "Invalid server URL."
        }
    }
}
