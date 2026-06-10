//
//  CampusCutsS3ImageURL.swift
//  CampusCutsModule
//

import Foundation

/// Builds public HTTPS URLs for objects in the `campuscut-images` S3 bucket.
public enum CampusCutsS3ImageURL: Sendable {
    public static let bucketHost = "campuscut-images.s3.amazonaws.com"

    /// Returns a URL suitable for `AsyncImage`. Accepts a full URL string or a bucket-relative key/path.
    public static func url(forStoredPath path: String?) -> URL? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let key = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        let encoded = key.split(separator: "/").map { segment in
            String(segment).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
        }.joined(separator: "/")
        return URL(string: "https://\(bucketHost)/\(encoded)")
    }
}
