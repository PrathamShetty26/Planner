import Foundation

struct APIKeyManager {
    static var sportMonkKey: String {
        // This should be your SportMonk key
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "SPORTMONK_KEY") as? String else {
            // Fallback to a hardcoded key for development
            return "OAtmtO0BFwRQI4QOy4NzXmGisrwfm8L14MDBwrMG8trKc7luKX4oXeEx9qDK" // SportMonk API key
        }
        return apiKey
    }
}
