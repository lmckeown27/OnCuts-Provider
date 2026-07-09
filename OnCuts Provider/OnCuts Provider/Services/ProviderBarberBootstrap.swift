import OnCutsModule
import Foundation

/// Calls public `GET /barbers/user/:userId`, which auto-creates a `barbers` row when the DB role is **BARBER** or **CAMPUS_MANAGER** (e.g. after application approval).
enum ProviderBarberBootstrap {
    static func trySyncBarberRow(userId: String) async {
        let enc = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        let base = AppConfiguration.apiV1BaseTrimmed
        let trimmed = "barbers/user/\(enc)"
        guard let url = URL(string: base + "/" + trimmed) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let tok = OnCutsAuthTokenStore.loadAccessToken(), !tok.isEmpty {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        _ = try? await URLSession.shared.data(for: req)
    }
}
