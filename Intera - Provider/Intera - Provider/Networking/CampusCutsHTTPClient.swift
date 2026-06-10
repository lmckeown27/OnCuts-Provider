import CampusCutsModule
import Foundation

enum CampusCutsHTTPError: LocalizedError {
    case invalidURL
    case notAuthenticated
    case httpStatus(Int, String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .notAuthenticated: return "Sign in again to continue."
        case .httpStatus(let code, let msg):
            return msg ?? "Request failed (\(code))"
        case .decoding: return "Could not read server response."
        }
    }
}

/// Minimal JSON client for Provider; uses JWT from `CampusCutsAuthTokenStore` when `token` is nil.
enum CampusCutsHTTPClient {
    static func request(
        path: String,
        method: String = "GET",
        jsonBody: [String: Any]? = nil,
        token: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let base = AppConfiguration.apiV1BaseTrimmed
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: base + "/" + trimmed) else {
            throw CampusCutsHTTPError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let bearer = (token ?? CampusCutsAuthTokenStore.loadAccessToken())?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bearer, !bearer.isEmpty else {
            throw CampusCutsHTTPError.notAuthenticated
        }
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw CampusCutsHTTPError.httpStatus(-1, nil)
        }
        return (data, http)
    }

    static func requestDataThrowingSuccess(
        path: String,
        method: String = "GET",
        jsonBody: [String: Any]? = nil,
        acceptableStatuses: Range<Int> = 200 ..< 300
    ) async throws -> Data {
        let (data, http) = try await request(path: path, method: method, jsonBody: jsonBody)
        guard acceptableStatuses.contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw CampusCutsHTTPError.httpStatus(http.statusCode, msg)
        }
        return data
    }

    /// Multipart upload (e.g. `POST upload/chat-image` with field name `image`).
    static func uploadMultipart(
        path: String,
        fieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) async throws -> Data {
        let base = AppConfiguration.apiV1BaseTrimmed
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: base + "/" + trimmed) else {
            throw CampusCutsHTTPError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(
            name: fieldName,
            fileName: fileName,
            mimeType: mimeType,
            fileData: fileData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let bearer = CampusCutsAuthTokenStore.loadAccessToken()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bearer, !bearer.isEmpty else {
            throw CampusCutsHTTPError.notAuthenticated
        }
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw CampusCutsHTTPError.httpStatus(-1, nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw CampusCutsHTTPError.httpStatus(http.statusCode, msg)
        }
        return data
    }

    static func jsonDecoderSnake() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if try c.decodeNil() {
                throw DecodingError.valueNotFound(
                    Date.self,
                    DecodingError.Context(codingPath: dec.codingPath, debugDescription: "Unexpected null date")
                )
            }
            if let s = try? c.decode(String.self) {
                if let parsed = ProviderBookingScheduleParsing.parseAPIDateString(s) {
                    return parsed
                }
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(s)")
            }
            if let ms = try? c.decode(Double.self) {
                return Date(timeIntervalSince1970: ms / (ms > 1_000_000_000_000 ? 1000 : 1))
            }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported date encoding")
        }
        return d
    }
}

private extension Data {
    mutating func appendMultipartField(
        name: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        boundary: String
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
