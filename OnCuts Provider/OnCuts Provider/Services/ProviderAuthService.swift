import OnCutsModule
import Foundation
import UIKit

private struct ProfilePhotoUploadEnvelope: Decodable {
    let data: ProfilePhotoUploadData?
}

private struct ProfilePhotoUploadData: Decodable {
    let url: String?
}

@MainActor
enum ProviderAuthService {
    static func login(email: String, password: String) async throws -> OnCutsVerifiedSession {
        try await OnCutsAuthService.loginWithEmailPassword(
            email: email,
            password: password,
            apiV1BaseTrimmed: AppConfiguration.apiV1BaseTrimmed
        )
    }

    static func persistSession(_ session: OnCutsVerifiedSession) {
        OnCutsAuthTokenStore.save(accessToken: session.accessToken, refreshToken: session.refreshToken)
    }

    static func clearSession() {
        OnCutsAuthTokenStore.clear()
    }

    /// Exchange the stored refresh token for a new access token whose `role` claim matches the
    /// current database role. Admin users can pass `GET /auth/me` while still
    /// carrying an older JWT (e.g. from before promotion) that `/admin/*` rejects.
    @discardableResult
    static func refreshAccessTokenIfPossible() async throws -> Bool {
        guard let refresh = OnCutsAuthTokenStore.loadRefreshToken()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !refresh.isEmpty
        else {
            return false
        }

        let base = AppConfiguration.apiV1BaseTrimmed
        guard let url = URL(string: base + "/auth/refresh-token") else {
            throw OnCutsHTTPError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refreshToken": refresh], options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OnCutsHTTPError.httpStatus(-1, nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw OnCutsHTTPError.httpStatus(http.statusCode, msg)
        }

        struct RefreshEnvelope: Decodable {
            let data: RefreshData?
            struct RefreshData: Decodable {
                let token: String?
                let accessToken: String?
            }
        }

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? dec.decode(RefreshEnvelope.self, from: data).data,
              let access = payload.accessToken ?? payload.token,
              !access.isEmpty
        else {
            throw OnCutsHTTPError.decoding
        }

        OnCutsAuthTokenStore.save(accessToken: access, refreshToken: refresh)
        return true
    }

    /// After `auth/me`, refresh the JWT when the account is admin so `/admin/*` calls use an up-to-date role claim.
    static func syncAccessTokenForElevatedPrivileges(_ user: AuthMeUser) async {
        guard user.hasAdminPrivileges else { return }
        _ = try? await refreshAccessTokenIfPossible()
    }

    static func fetchAuthMe() async throws -> AuthMeUser {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "auth/me")
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let env = try dec.decode(AuthMeEnvelope.self, from: data)
        guard let u = env.data else {
            throw OnCutsHTTPError.decoding
        }
        return u
    }

    /// `POST /upload/profile-photo` — multipart field `image` (web `userService.uploadProfilePhoto`).
    /// Updates `users."avatarUrl"` on the server for the signed-in user.
    static func uploadProfilePhoto(jpegData: Data, fileName: String = "profile.jpg") async throws -> String {
        let data = try await OnCutsHTTPClient.uploadMultipart(
            path: "upload/profile-photo",
            fieldName: "image",
            fileName: fileName,
            mimeType: "image/jpeg",
            fileData: jpegData
        )
        let dec = OnCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(ProfilePhotoUploadEnvelope.self, from: data)
        guard let url = env.data?.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            throw OnCutsHTTPError.decoding
        }
        return url
    }

    /// Scales down and JPEG-encodes for profile upload (5 MB server cap; web parity).
    static func jpegDataForProfileUpload(from image: UIImage) -> Data? {
        let maxBytes = 5 * 1024 * 1024
        var quality: CGFloat = 0.88
        var scaled = image.scaledForProfileUpload(maxPixel: 1600)
        while quality >= 0.5 {
            guard let data = scaled.jpegData(compressionQuality: quality) else { return nil }
            if data.count <= maxBytes { return data }
            quality -= 0.12
        }
        return scaled.jpegData(compressionQuality: 0.5)
    }

    static func fetchBarberMe() async throws -> BarberMeProfile {
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(path: "barbers/me")
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let env = try dec.decode(BarberMeEnvelope.self, from: data)
        guard let p = env.data else {
            throw OnCutsHTTPError.httpStatus(404, env.message)
        }
        // Payload may include both `isHidden` and `is_hidden`; snake-case conversion can drop one.
        if let hidden = ProviderMarketplaceVisibility.isHidden(in: data) {
            return p.withMarketplaceHidden(hidden)
        }
        return p.withMarketplaceHidden(p.isHidden == true)
    }

    /// `DELETE /users/:id` — permanent account deletion (web `userService.deleteAccount` parity).
    /// Omit `password` when the account is Apple-linked without a CampusCuts password; the backend
    /// accepts an empty body after the client has confirmed device ownership.
    static func deleteAccount(userId: String, password: String?) async throws {
        let enc = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        var body: [String: Any] = [:]
        if let password, !password.isEmpty {
            body["password"] = password
        }
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "users/\(enc)",
            method: "DELETE",
            jsonBody: body
        )
    }

    /// `PUT /barbers/:id` — display name, Instagram, bio, specialties. Visibility is a separate call.
    static func updateMyBarberProfile(
        barberId: String,
        displayName: String,
        bio: String,
        instagramHandle: String,
        specialties: [String]
    ) async throws {
        let enc = barberId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? barberId
        let body: [String: Any] = [
            "display_name": displayName,
            "bio": bio,
            "instagram_handle": instagramHandle,
            "specialties": specialties,
        ]
        _ = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(enc)",
            method: "PUT",
            jsonBody: body
        )
    }

    /// Owner-only marketplace hide. Sends both key spellings; does **not** send `isActive`.
    @discardableResult
    static func updateMarketplaceHidden(barberId: String, isHidden: Bool) async throws -> Bool {
        let enc = barberId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? barberId
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(enc)",
            method: "PUT",
            jsonBody: [
                "isHidden": isHidden,
                "is_hidden": isHidden,
            ]
        )
        return ProviderMarketplaceVisibility.isHidden(in: data) ?? isHidden
    }

    /// `PUT /barbers/:id` — owner-only client cancel full-refund window (`1, 2, 4, 6, 12, 24` hours).
    @discardableResult
    static func updateClientCancelRefundHours(barberId: String, hours: Int) async throws -> Int {
        let allowed = Set(ClientCancelRefundHoursPreset.allCases.map(\.rawValue))
        let resolved = allowed.contains(hours) ? hours : 1
        let enc = barberId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? barberId
        let data = try await OnCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(enc)",
            method: "PUT",
            jsonBody: ["client_cancel_refund_hours": resolved]
        )
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        if let env = try? dec.decode(BarberMeEnvelope.self, from: data),
           let profile = env.data {
            return profile.resolvedClientCancelRefundHours
        }
        if let profile = try? dec.decode(BarberMeProfile.self, from: data) {
            return profile.resolvedClientCancelRefundHours
        }
        return resolved
    }
}

private extension UIImage {
    func scaledForProfileUpload(maxPixel: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxPixel, maxSide > 0 else { return self }
        let scale = maxPixel / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
