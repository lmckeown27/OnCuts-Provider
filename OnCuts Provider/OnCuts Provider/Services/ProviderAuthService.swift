import CampusCutsModule
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
    static func login(email: String, password: String) async throws -> CampusCutsVerifiedSession {
        try await CampusCutsAuthService.loginWithEmailPassword(
            email: email,
            password: password,
            apiV1BaseTrimmed: AppConfiguration.apiV1BaseTrimmed
        )
    }

    static func persistSession(_ session: CampusCutsVerifiedSession) {
        CampusCutsAuthTokenStore.save(accessToken: session.accessToken, refreshToken: session.refreshToken)
    }

    static func clearSession() {
        CampusCutsAuthTokenStore.clear()
    }

    /// Exchange the stored refresh token for a new access token whose `role` claim matches the
    /// current database role. Admin users can pass `GET /auth/me` while still
    /// carrying an older JWT (e.g. from before promotion) that `/admin/*` rejects.
    @discardableResult
    static func refreshAccessTokenIfPossible() async throws -> Bool {
        guard let refresh = CampusCutsAuthTokenStore.loadRefreshToken()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !refresh.isEmpty
        else {
            return false
        }

        let base = AppConfiguration.apiV1BaseTrimmed
        guard let url = URL(string: base + "/auth/refresh-token") else {
            throw CampusCutsHTTPError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["refreshToken": refresh], options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw CampusCutsHTTPError.httpStatus(-1, nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw CampusCutsHTTPError.httpStatus(http.statusCode, msg)
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
            throw CampusCutsHTTPError.decoding
        }

        CampusCutsAuthTokenStore.save(accessToken: access, refreshToken: refresh)
        return true
    }

    /// After `auth/me`, refresh the JWT when the account is admin so `/admin/*` calls use an up-to-date role claim.
    static func syncAccessTokenForElevatedPrivileges(_ user: AuthMeUser) async {
        guard user.hasAdminPrivileges else { return }
        _ = try? await refreshAccessTokenIfPossible()
    }

    static func fetchAuthMe() async throws -> AuthMeUser {
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "auth/me")
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let env = try dec.decode(AuthMeEnvelope.self, from: data)
        guard let u = env.data else {
            throw CampusCutsHTTPError.decoding
        }
        return u
    }

    /// `POST /upload/profile-photo` — multipart field `image` (web `userService.uploadProfilePhoto`).
    /// Updates `users."avatarUrl"` on the server for the signed-in user.
    static func uploadProfilePhoto(jpegData: Data, fileName: String = "profile.jpg") async throws -> String {
        let data = try await CampusCutsHTTPClient.uploadMultipart(
            path: "upload/profile-photo",
            fieldName: "image",
            fileName: fileName,
            mimeType: "image/jpeg",
            fileData: jpegData
        )
        let dec = CampusCutsHTTPClient.jsonDecoderSnake()
        let env = try dec.decode(ProfilePhotoUploadEnvelope.self, from: data)
        guard let url = env.data?.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            throw CampusCutsHTTPError.decoding
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
        let data = try await CampusCutsHTTPClient.requestDataThrowingSuccess(path: "barbers/me")
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let env = try dec.decode(BarberMeEnvelope.self, from: data)
        guard let p = env.data else {
            throw CampusCutsHTTPError.httpStatus(404, env.message)
        }
        return p
    }

    /// `PUT /barbers/:id` — updates `users` display name / Instagram and `barbers` bio, specialties, visibility.
    /// `DELETE /users/:id` — permanent account deletion (web `userService.deleteAccount` parity).
    /// Omit `password` when the account is Apple-linked without a CampusCuts password; the backend
    /// accepts an empty body after the client has confirmed device ownership.
    static func deleteAccount(userId: String, password: String?) async throws {
        let enc = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        var body: [String: Any] = [:]
        if let password, !password.isEmpty {
            body["password"] = password
        }
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "users/\(enc)",
            method: "DELETE",
            jsonBody: body
        )
    }

    static func updateMyBarberProfile(
        barberId: String,
        displayName: String,
        bio: String,
        instagramHandle: String,
        specialties: [String],
        isActive: Bool
    ) async throws {
        let enc = barberId.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) ?? barberId
        let body: [String: Any] = [
            "display_name": displayName,
            "bio": bio,
            "instagram_handle": instagramHandle,
            "specialties": specialties,
            "is_active": isActive,
        ]
        _ = try await CampusCutsHTTPClient.requestDataThrowingSuccess(
            path: "barbers/\(enc)",
            method: "PUT",
            jsonBody: body
        )
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
