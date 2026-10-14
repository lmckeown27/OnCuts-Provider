import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Admin **Data** — uploaded profile pictures, portfolio, and chat files.
/// Only the selected list is on screen. Export writes a CSV for that list alone.
struct ProviderAdminDataView: View {
    var reloadToken: Int = 0

    private enum Section: String, CaseIterable, Identifiable {
        case profile = "Profile pictures"
        case portfolio = "Portfolio"
        case chat = "Chat"
        var id: String { rawValue }
    }

    private enum MediaFilter: String, CaseIterable, Identifiable {
        case photo = "Photo"
        case video = "Video"
        var id: String { rawValue }
    }

    @Environment(\.openURL) private var openURL
    @State private var section: Section = .profile
    @State private var media: MediaFilter = .photo
    @State private var profile = AdminUploadedMediaBucket.empty
    @State private var portfolio = AdminUploadedMediaBucket.empty
    @State private var chat = AdminUploadedMediaBucket.empty
    @State private var isLoading = true
    @State private var isExporting = false
    @State private var errorText: String?
    @State private var exportNote: String?
    @State private var exportFile: AdminExportFile?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionBar

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.rawValue)
                            .font(.provider(.caption2, weight: .semibold))
                            .foregroundStyle(ProviderAdminChrome.secondaryText)
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Text(countLine)
                            .font(.provider(.caption))
                            .foregroundStyle(ProviderAdminChrome.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Button {
                        Task { await exportCurrentPage() }
                    } label: {
                        Label(isExporting ? "Exporting…" : "Export", systemImage: "square.and.arrow.down")
                            .font(.provider(.caption, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.providerOlive)
                    .disabled(isExporting || isLoading)
                }

                if section != .profile {
                    mediaBar
                }

                if let exportNote, !exportNote.isEmpty {
                    Text(exportNote)
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                }

                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading files…")
                            .font(.provider(.footnote))
                            .foregroundStyle(ProviderAdminChrome.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else if let errorText {
                    Text(errorText)
                        .font(.provider(.footnote))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if visibleItems.isEmpty {
                    Text(emptyMessage)
                        .font(.provider(.footnote))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .padding(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(ProviderAdminChrome.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        )
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(visibleItems) { item in
                            mediaCard(item)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .providerAdminCardBackground(cornerRadius: 16)
        }
        .task(id: reloadToken) { await load() }
        .sheet(item: $exportFile) { file in
            AdminCSVActivityView(url: file.url)
        }
    }

    private var sectionBar: some View {
        HStack(spacing: 4) {
            ForEach(Section.allCases) { item in
                segmentButton(title: item.rawValue, selected: section == item) {
                    section = item
                    exportNote = nil
                }
            }
        }
        .padding(4)
        .background(segmentChrome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Data")
    }

    private var mediaBar: some View {
        HStack(spacing: 4) {
            ForEach(MediaFilter.allCases) { item in
                segmentButton(title: item.rawValue, selected: media == item) {
                    media = item
                    exportNote = nil
                }
            }
        }
        .padding(4)
        .background(segmentChrome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(section.rawValue) media")
    }

    private var segmentChrome: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(ProviderAdminChrome.stoneMutedFill)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ProviderAdminChrome.stoneBorder, lineWidth: 0.6)
            )
    }

    private func segmentButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.provider(.caption2, weight: selected ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(selected ? ProviderAdminChrome.primaryText : ProviderAdminChrome.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ProviderAdminChrome.cardBackground)
                            .shadow(color: Color.primary.opacity(0.06), radius: 2, y: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func mediaCard(_ item: AdminUploadedMediaItem) -> some View {
        Button {
            if let url = Self.resolvedURL(item.mediaUrl) {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        previewFill(item)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .center) {
                        if item.isVideo {
                            Image(systemName: "play.circle.fill")
                                .font(.provider(.title2))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                    }

                Text(item.ownerName)
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
                    .lineLimit(1)
                Text(metaLine(item))
                    .font(.provider(.caption2))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
                    .lineLimit(1)
                Text(Self.displayWhen(item.createdAt))
                    .font(.provider(.caption2))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .providerAdminCardBackground(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .clipped()
        .accessibilityLabel("\(item.ownerName), \(metaLine(item))")
    }

    @ViewBuilder
    private func previewFill(_ item: AdminUploadedMediaItem) -> some View {
        let previewURL = Self.resolvedURL(item.thumbnailUrl ?? item.mediaUrl)
        GeometryReader { geo in
            ZStack {
                ProviderAdminChrome.mutedFill
                if item.isVideo, item.thumbnailUrl == nil {
                    Image(systemName: "video.fill")
                        .font(.provider(.title2))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                } else if let previewURL, !item.isVideo || item.thumbnailUrl != nil {
                    AsyncImage(url: previewURL) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private var visibleItems: [AdminUploadedMediaItem] {
        switch section {
        case .profile:
            return profile.items
        case .portfolio:
            return portfolio.items.filter { media == .video ? $0.isVideo : !$0.isVideo }
        case .chat:
            return chat.items.filter { media == .video ? $0.isVideo : !$0.isVideo }
        }
    }

    private var countBucket: AdminUploadedMediaBucket {
        if section == .profile { return profile }
        return AdminUploadedMediaBucket(items: visibleItems, total: visibleItems.count)
    }

    private var countLine: String {
        if isLoading { return "Loading files…" }
        let noun = countBucket.total == 1 ? "file" : "files"
        var line = "\(countBucket.total) \(noun)"
        if countBucket.total > countBucket.items.count {
            line += " · showing \(countBucket.items.count)"
        }
        return line
    }

    private var emptyMessage: String {
        switch section {
        case .profile: "No profile pictures."
        case .portfolio: media == .video ? "No portfolio videos." : "No portfolio photos."
        case .chat: media == .video ? "No chat videos." : "No chat photos."
        }
    }

    private var pageName: String {
        switch section {
        case .profile: "Profile pictures"
        case .portfolio: media == .video ? "Portfolio videos" : "Portfolio photos"
        case .chat: media == .video ? "Chat videos" : "Chat photos"
        }
    }

    private func metaLine(_ item: AdminUploadedMediaItem) -> String {
        var parts = [item.isVideo ? "Video" : "Photo"]
        if let specialty = item.specialty, !specialty.isEmpty {
            parts.append(specialty)
        }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            async let profileBucket = ProviderAdminService.listUploadedMedia(kind: "profile", limit: 120)
            async let portfolioBucket = ProviderAdminService.listUploadedMedia(kind: "portfolio", limit: 200)
            async let chatBucket = ProviderAdminService.listUploadedMedia(kind: "chat", limit: 200)
            let (profiles, portfolios, chats) = try await (profileBucket, portfolioBucket, chatBucket)
            profile = profiles
            portfolio = portfolios
            chat = chats
        } catch {
            guard !providerAdminIsBenignRequestCancellation(error) else { return }
            profile = .empty
            portfolio = .empty
            chat = .empty
            errorText = "Could not load uploaded files."
        }
    }

    private func exportCurrentPage() async {
        let name = pageName
        let kind: String
        switch section {
        case .profile: kind = "profile"
        case .portfolio: kind = "portfolio"
        case .chat: kind = "chat"
        }
        let wantVideo = media == .video
        isExporting = true
        exportNote = nil
        defer { isExporting = false }
        do {
            let bucket = try await ProviderAdminService.listUploadedMedia(kind: kind, limit: 2000)
            let rows = kind == "profile"
                ? bucket.items
                : bucket.items.filter { wantVideo ? $0.isVideo : !$0.isVideo }
            guard !rows.isEmpty else {
                exportNote = "No \(name.lowercased()) to export."
                return
            }
            let stamp = Self.fileStamp()
            let filename = "oncuts-uploads-\(Self.slug(name))-\(stamp).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try Self.csv(rows).write(to: url, atomically: true, encoding: .utf8)
            exportFile = AdminExportFile(url: url)
        } catch {
            guard !providerAdminIsBenignRequestCancellation(error) else { return }
            exportNote = "Could not export uploaded files."
        }
    }

    private static func csv(_ rows: [AdminUploadedMediaItem]) -> String {
        var lines = ["Section,Media type,Owner,Email,Specialty,Caption,Uploaded,File URL"]
        for row in rows {
            lines.append([
                sectionLabel(row),
                row.mediaType,
                row.ownerName,
                row.ownerEmail,
                row.specialty ?? "",
                row.caption ?? "",
                row.createdAt,
                row.mediaUrl,
            ].map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func sectionLabel(_ item: AdminUploadedMediaItem) -> String {
        switch item.kind {
        case "profile": return "Profile picture"
        case "portfolio": return item.isVideo ? "Portfolio video" : "Portfolio photo"
        default: return item.isVideo ? "Chat video" : "Chat photo"
        }
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func slug(_ name: String) -> String {
        let lowered = name.lowercased()
        let allowed = lowered.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let collapsed = String(allowed).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func displayWhen(_ value: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func resolvedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        let origin = AppConfiguration.webAppOriginURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return URL(string: origin + path)
    }
}

private struct AdminExportFile: Identifiable {
    let url: URL
    var id: String { url.lastPathComponent }
}

#if canImport(UIKit)
private struct AdminCSVActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
