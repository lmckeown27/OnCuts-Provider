import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// After payment is received, add this booking’s work to its specialty. Up to 4 photos and 1 video.
struct ProviderPostServicePortfolioView: View {
    let barberId: String
    let bookingId: String
    let serviceName: String
    let onClose: () -> Void

    @State private var photos: [UploadedMedia] = []
    @State private var video: UploadedMedia?
    @State private var specialtyId: String?
    @State private var isPosting = false
    @State private var errorText: String?
    @State private var libraryPickerItem: PhotosPickerItem?
    @State private var showingLibrary = false
    @State private var showingAddMenu = false
    @State private var cameraCapture: ProviderPortfolioCameraPicker.Capture?

    private var canAddPhoto: Bool { photos.count < ProviderOperatorPortfolioService.maxPhotosPerBooking }
    private var canAddVideo: Bool { video == nil }
    private var canAddWork: Bool { (canAddPhoto || canAddVideo) && specialtyId != nil && !isPosting }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorText, !errorText.isEmpty {
                        Text(errorText)
                            .font(.provider(.footnote))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    Text(serviceName)
                        .font(.provider(.title3, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(photos) { photo in
                            uploadedTile(photo, isVideo: false)
                        }
                        if let video {
                            uploadedTile(video, isVideo: true)
                        }
                        if canAddPhoto || canAddVideo {
                            Button { showingAddMenu = true } label: {
                                addWorkTile
                            }
                            .buttonStyle(.plain)
                            .disabled(!canAddWork)
                            .accessibilityLabel("Add work")
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: ProviderAppearance.shellBase).ignoresSafeArea())
            .navigationTitle(serviceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { discard() }
                        .disabled(isPosting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Confirm") { Task { await confirm() } }
                        .disabled(isPosting)
                }
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .interactiveDismissDisabled(true)
        .confirmationDialog("Add work", isPresented: $showingAddMenu, titleVisibility: .visible) {
            if canAddPhoto || canAddVideo {
                Button("Upload from camera") { cameraCapture = captureKind }
                Button("Upload from library") { showingLibrary = true }
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showingLibrary, selection: $libraryPickerItem, matching: libraryFilter)
        .onChange(of: libraryPickerItem) { _, item in
            guard let item else { return }
            Task { await importLibrary(item) }
        }
        .sheet(item: $cameraCapture) { capture in
            ProviderPortfolioCameraPicker(
                capture: capture,
                onPhoto: { image in
                    if let data = image.jpegDataForChatUpload() {
                        stagePhoto(data)
                    }
                },
                onVideo: { data, _ in
                    stageVideo(data)
                }
            )
            .ignoresSafeArea()
        }
        .task { await resolveSpecialty() }
    }

    private var captureKind: ProviderPortfolioCameraPicker.Capture {
        if canAddPhoto && canAddVideo { return .both }
        return canAddVideo ? .video : .photo
    }

    private var libraryFilter: PHPickerFilter {
        if canAddPhoto && canAddVideo { return .any(of: [.images, .videos]) }
        return canAddVideo ? .videos : .images
    }

    private var addWorkTile: some View {
        Color.clear
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.providerOlive, lineWidth: 1.5)
                VStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Add work")
                        .font(.provider(.subheadline, weight: .medium))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.providerOlive)
                .padding(.horizontal, 12)
            }
    }

    private func uploadedTile(_ media: UploadedMedia, isVideo: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Color.providerScheduleCardFill
                .aspectRatio(9 / 16, contentMode: .fit)
                .overlay {
                    if isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.lavaShellCream)
                    } else {
                        #if canImport(UIKit)
                        if let image = UIImage(data: media.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        }
                        #endif
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button {
                remove(media, isVideo: isVideo)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.providerOnOliveFill)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.providerOlive))
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel("Remove upload")
        }
    }

    private func importLibrary(_ item: PhotosPickerItem) async {
        defer { libraryPickerItem = nil }
        let isVideo = item.supportedContentTypes.contains {
            $0.conforms(to: .movie) || $0.conforms(to: .video)
        }
        if isVideo {
            guard canAddVideo, let movie = try? await item.loadTransferable(type: PortfolioVideoFile.self) else { return }
            stageVideo(movie.data)
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            #if canImport(UIKit)
            let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.86) ?? data
            #else
            let jpeg = data
            #endif
            stagePhoto(jpeg)
        }
    }

    private func stagePhoto(_ data: Data) {
        guard canAddPhoto else { return }
        photos.append(UploadedMedia(id: UUID().uuidString, data: data))
    }

    private func stageVideo(_ data: Data) {
        guard canAddVideo else { return }
        video = UploadedMedia(id: UUID().uuidString, data: data)
    }

    private func resolveSpecialty() async {
        let catalog = (try? await ProviderBarberServicesService.fetchServiceCatalog()) ?? []
        let key = serviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        specialtyId = catalog.first {
            $0.name.lowercased() == key || $0.slug.lowercased() == key
        }?.slug ?? key.replacingOccurrences(of: " ", with: "-")
    }

    private func remove(_ media: UploadedMedia, isVideo: Bool) {
        if isVideo {
            video = nil
        } else {
            photos.removeAll { $0.id == media.id }
        }
    }

    private func confirm() async {
        guard let specialtyId else {
            errorText = "Could not match this service."
            return
        }
        isPosting = true
        errorText = nil
        defer { isPosting = false }
        var createdIds: [String] = []
        do {
            for photo in photos {
                let created = try await ProviderOperatorPortfolioService.upload(
                    barberId: barberId,
                    fileData: photo.data,
                    fileName: "portfolio.jpg",
                    mimeType: "image/jpeg",
                    specialtyId: specialtyId,
                    bookingId: bookingId
                )
                createdIds.append(created.id)
            }
            if let video {
                let created = try await ProviderOperatorPortfolioService.upload(
                    barberId: barberId,
                    fileData: video.data,
                    fileName: "portfolio.mp4",
                    mimeType: "video/mp4",
                    specialtyId: specialtyId,
                    bookingId: bookingId
                )
                createdIds.append(created.id)
            }
            finish()
        } catch {
            for itemId in createdIds {
                try? await ProviderOperatorPortfolioService.deleteItem(barberId: barberId, itemId: itemId)
            }
            errorText = ProviderOperatorPortfolioService.message(from: error)
        }
    }

    private func discard() {
        photos = []
        video = nil
        finish()
    }

    private func finish() {
        ProviderPortfolioPromptMemory.dismiss(bookingId)
        onClose()
    }
}

private struct UploadedMedia: Identifiable {
    let id: String
    let data: Data
}

private struct PortfolioVideoFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .movie) { PortfolioVideoFile(data: $0) }
        DataRepresentation(importedContentType: .mpeg4Movie) { PortfolioVideoFile(data: $0) }
        DataRepresentation(importedContentType: .video) { PortfolioVideoFile(data: $0) }
    }
}
