import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// After the tip is decided: “Add this service to your portfolio?” Up to 4 photos and 1 video.
struct ProviderPostServicePortfolioView: View {
    let barberId: String
    let bookingId: String
    let serviceName: String
    let onClose: () -> Void

    @State private var step: Step = .prompt
    @State private var photos: [Data] = []
    @State private var video: Data?
    @State private var specialtyId: String?
    @State private var isPosting = false
    @State private var errorText: String?
    @State private var libraryPickerItem: PhotosPickerItem?
    @State private var showingLibrary = false
    @State private var libraryKind: Kind = .photo
    @State private var cameraCapture: ProviderPortfolioCameraPicker.Capture?

    private enum Step { case prompt, upload }
    private enum Kind { case photo, video }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.provider(.footnote))
                        .foregroundStyle(.red.opacity(0.9))
                }
                switch step {
                case .prompt:
                    prompt
                case .upload:
                    uploadStep
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(uiColor: ProviderAppearance.shellBase).ignoresSafeArea())
            .navigationTitle(step == .prompt ? "Portfolio" : serviceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .photosPicker(isPresented: $showingLibrary, selection: $libraryPickerItem, matching: libraryKind == .video ? .videos : .images)
        .onChange(of: libraryPickerItem) { _, item in
            guard let item else { return }
            Task { await importLibrary(item) }
        }
        .sheet(item: $cameraCapture) { capture in
            ProviderPortfolioCameraPicker(
                capture: capture,
                onPhoto: { image in
                    if let data = image.jpegData(compressionQuality: 0.86) { addPhoto(data) }
                },
                onVideo: { data, _ in
                    video = data
                }
            )
            .ignoresSafeArea()
        }
        .task { await resolveSpecialty() }
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add this service to your portfolio?")
                .font(.provider(.title3, weight: .semibold))
            Text("You can add up to 4 photos and 1 video from \(serviceName).")
                .font(.provider(.subheadline))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Button("Add work") { step = .upload }
                .font(.provider(.body, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.providerOlive))
                .foregroundStyle(Color.providerOnOliveFill)
        }
    }

    private var uploadStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(photos.count) of 4 photos")
                .font(.provider(.subheadline, weight: .semibold))
            HStack(spacing: 10) {
                Button("Camera") { cameraCapture = .photo }
                    .disabled(photos.count >= ProviderOperatorPortfolioService.maxPhotosPerBooking)
                Button("Library") {
                    libraryKind = .photo
                    showingLibrary = true
                }
                .disabled(photos.count >= ProviderOperatorPortfolioService.maxPhotosPerBooking)
            }
            .buttonStyle(.bordered)

            Text(video == nil ? "No video" : "1 video selected")
                .font(.provider(.subheadline, weight: .semibold))
            HStack(spacing: 10) {
                Button("Camera") { cameraCapture = .video }
                    .disabled(video != nil)
                Button("Library") {
                    libraryKind = .video
                    showingLibrary = true
                }
                .disabled(video != nil)
            }
            .buttonStyle(.bordered)

            Button(isPosting ? "Posting…" : "Post to portfolio") {
                Task { await post() }
            }
            .font(.provider(.body, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.providerOlive))
            .foregroundStyle(Color.providerOnOliveFill)
            .disabled(isPosting || (photos.isEmpty && video == nil) || specialtyId == nil)
        }
    }

    private func addPhoto(_ data: Data) {
        guard photos.count < ProviderOperatorPortfolioService.maxPhotosPerBooking else { return }
        photos.append(data)
    }

    private func importLibrary(_ item: PhotosPickerItem) async {
        defer { libraryPickerItem = nil }
        if libraryKind == .video {
            if let movie = try? await item.loadTransferable(type: PortfolioVideoFile.self) {
                video = movie.data
            }
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            #if canImport(UIKit)
            addPhoto(UIImage(data: data)?.jpegData(compressionQuality: 0.86) ?? data)
            #else
            addPhoto(data)
            #endif
        }
    }

    private func resolveSpecialty() async {
        let catalog = (try? await ProviderBarberServicesService.fetchServiceCatalog()) ?? []
        let key = serviceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        specialtyId = catalog.first {
            $0.name.lowercased() == key || $0.slug.lowercased() == key
        }?.slug ?? key.replacingOccurrences(of: " ", with: "-")
    }

    private func post() async {
        guard let specialtyId else { return }
        isPosting = true
        errorText = nil
        defer { isPosting = false }
        do {
            for photo in photos {
                _ = try await ProviderOperatorPortfolioService.upload(
                    barberId: barberId,
                    fileData: photo,
                    fileName: "portfolio.jpg",
                    mimeType: "image/jpeg",
                    specialtyId: specialtyId,
                    bookingId: bookingId
                )
            }
            if let video {
                _ = try await ProviderOperatorPortfolioService.upload(
                    barberId: barberId,
                    fileData: video,
                    fileName: "portfolio.mp4",
                    mimeType: "video/mp4",
                    specialtyId: specialtyId,
                    bookingId: bookingId
                )
            }
            ProviderPortfolioPromptMemory.dismiss(bookingId)
            onClose()
        } catch {
            errorText = ProviderOperatorPortfolioService.message(from: error)
        }
    }

    private func dismiss() {
        ProviderPortfolioPromptMemory.dismiss(bookingId)
        onClose()
    }
}

private struct PortfolioVideoFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .movie) { PortfolioVideoFile(data: $0) }
        DataRepresentation(importedContentType: .mpeg4Movie) { PortfolioVideoFile(data: $0) }
        DataRepresentation(importedContentType: .video) { PortfolioVideoFile(data: $0) }
    }
}
