import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AVKit)
import AVKit
#endif

/// Operator portfolio: specialty covers, per-service gallery, and the client preview.
struct ProviderPortfolioView: View {
    @Environment(ProviderSession.self) private var session
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var items: [OperatorPortfolioItem] = []
    @State private var specialties: [PortfolioSpecialty] = []
    @State private var sectionOrder: [String] = []
    @State private var operatorProfile: PortfolioOperatorProfile?
    @State private var clientView = false
    @State private var openSpecialtyId: String?
    @State private var clientSpecialtyId: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var showingServices = false
    @State private var servicesRevision = 0
    @State private var lightboxItem: OperatorPortfolioItem?
    @State private var taggingItem: OperatorPortfolioItem?
    @State private var tagSelection: String = ""
    @State private var uploadTarget: PortfolioUploadTarget?
    @State private var libraryPickerItem: PhotosPickerItem?
    @State private var showingLibraryPicker = false
    @State private var cameraCapture: ProviderPortfolioCameraPicker.Capture?
    @State private var addMenuSpecialtyId: String?
    @State private var pendingReplaceId: String?
    @State private var pendingReplaceAsCover = false
    @State private var pendingRemoveSpecialty: PortfolioSpecialty?
    @State private var draggingSpecialtyId: String?
    @State private var pressingSpecialtyId: String?
    @State private var pressBeganAt: Date?
    @State private var dragOffset: CGSize = .zero
    @State private var coverCardSize: CGSize = .zero
    @State private var orderAtDragStart: [String] = []
    @State private var specialtyStep: CGFloat = 180

    private let specialtyColumnSpacing: CGFloat = 12

    private var ordered: [PortfolioSpecialty] {
        ProviderOperatorPortfolioService.orderedSpecialties(specialties, savedOrder: sectionOrder, items: items)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorText, !errorText.isEmpty {
                        Text(errorText)
                            .font(.provider(.footnote))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    if isLoading {
                        ProgressView("Loading portfolio…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else if clientView {
                        clientPreview
                    } else if let openSpecialtyId, let specialty = ordered.first(where: { $0.id == openSpecialtyId }) {
                        gallery(for: specialty)
                    } else {
                        editCovers
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: ProviderAppearance.shellBase).ignoresSafeArea())
            .providerPageNavigationTitle("Portfolio")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if clientView, clientSpecialtyId != nil {
                        Button {
                            clientSpecialtyId = nil
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .accessibilityLabel("All specialties")
                    } else if clientView {
                        Button("Edit") {
                            clientView = false
                            clientSpecialtyId = nil
                        }
                    } else if openSpecialtyId != nil {
                        Button("All specialties") { openSpecialtyId = nil }
                    } else {
                        Button("Client View") {
                            openSpecialtyId = nil
                            clientView = true
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Services") { showingServices = true }
                }
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .task { await reload() }
        .onChange(of: servicesRevision) { _, revision in
            guard revision > 0 else { return }
            Task { await reload() }
        }
        .background(PortfolioEscapeCatcher { closeTopLayer() })
        .sheet(isPresented: $showingServices, onDismiss: { servicesRevision += 1 }) {
            NavigationStack {
                ProviderBarberServicesView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingServices = false }
                        }
                    }
            }
        }
        .photosPicker(isPresented: libraryPickerOnPage, selection: $libraryPickerItem, matching: libraryFilter)
        .onChange(of: libraryPickerItem) { _, item in
            guard let item else { return }
            Task { await importLibraryItem(item) }
        }
        .sheet(item: pageCameraCapture) { capture in
            ProviderPortfolioCameraPicker(
                capture: capture,
                onPhoto: { image in
                    guard let target = uploadTarget, let data = image.jpegData(compressionQuality: 0.86) else { return }
                    Task { await upload(data: data, fileName: "portfolio.jpg", mimeType: "image/jpeg", target: target) }
                },
                onVideo: { data, mime in
                    guard let target = uploadTarget else { return }
                    Task { await upload(data: data, fileName: "portfolio.mov", mimeType: mime, target: target) }
                }
            )
            .ignoresSafeArea()
        }
        .confirmationDialog("Add work", isPresented: pageAddMenuPresented, titleVisibility: .visible) {
            addWorkDialogButtons
        }
        .sheet(item: $taggingItem) { item in
            tagDialog(item)
        }
        .fullScreenCover(item: $lightboxItem) { item in
            PortfolioLightbox(item: item) { lightboxItem = nil }
        }
    }

    private var pageAddMenuPresented: Binding<Bool> {
        Binding(
            get: { addMenuSpecialtyId != nil && taggingItem == nil },
            set: { if !$0 { addMenuSpecialtyId = nil } }
        )
    }

    private var libraryPickerOnPage: Binding<Bool> {
        Binding(
            get: { showingLibraryPicker && taggingItem == nil },
            set: { showingLibraryPicker = $0 }
        )
    }

    private var pageCameraCapture: Binding<ProviderPortfolioCameraPicker.Capture?> {
        Binding(
            get: { taggingItem == nil ? cameraCapture : nil },
            set: { cameraCapture = $0 }
        )
    }

    @ViewBuilder
    private var addWorkDialogButtons: some View {
        Button("Upload from camera") {
            beginUpload(
                specialtyId: addMenuSpecialtyId,
                asCover: pendingReplaceAsCover,
                kind: pendingReplaceAsCover ? .photo : .both,
                source: .camera,
                replaceId: pendingReplaceId
            )
        }
        Button("Upload from library") {
            beginUpload(
                specialtyId: addMenuSpecialtyId,
                asCover: pendingReplaceAsCover,
                kind: pendingReplaceAsCover ? .photo : .both,
                source: .library,
                replaceId: pendingReplaceId
            )
        }
        Button("Cancel", role: .cancel) {
            pendingReplaceId = nil
            pendingReplaceAsCover = false
        }
    }

    private var libraryFilter: PHPickerFilter {
        if uploadTarget?.asCover == true || uploadTarget?.kind == .photo { return .images }
        if uploadTarget?.kind == .video { return .videos }
        return .any(of: [.images, .videos])
    }

    private var editCovers: some View {
        VStack(alignment: .leading, spacing: 12) {
            if ordered.isEmpty {
                Text("Add a service to start your portfolio.")
                    .font(.provider(.subheadline))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }
            specialtyBoard
            if isSaving {
                ProgressView("Saving…")
            }
        }
    }

    /// Two specialties per row. Each pair fills the width, and further rows continue down the page.
    /// Cards stay in a stable stack and move only by position, so a drop never flashes the previous arrangement.
    private var specialtyBoard: some View {
        ZStack(alignment: .topLeading) {
            ForEach(anchoredSpecialties) { specialty in
                let index = ordered.firstIndex(where: { $0.id == specialty.id }) ?? 0
                coverCard(specialty)
                    .frame(width: columnWidth, alignment: .top)
                    .offset(cardPosition(for: specialty, index: index))
                    .zIndex(draggingSpecialtyId == specialty.id ? 3 : 0)
                    .animation(
                        draggingSpecialtyId != nil && draggingSpecialtyId != specialty.id
                            ? .spring(response: 0.22, dampingFraction: 0.92)
                            : nil,
                        value: sectionOrder
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: ordered.isEmpty ? 0 : boardHeight, alignment: .top)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateSpecialtyStep(geo.size.width) }
                    .onChange(of: geo.size.width) { _, width in
                        updateSpecialtyStep(width)
                    }
            }
        }
        .background(PortfolioBoardMarker())
    }

    private func columns(of specialties: [PortfolioSpecialty]) -> [[PortfolioSpecialty]] {
        stride(from: 0, to: specialties.count, by: 2).map { start in
            Array(specialties[start..<min(start + 2, specialties.count)])
        }
    }

    /// Identity order never follows the saved arrangement, so dropping cannot rebuild the slots.
    private var anchoredSpecialties: [PortfolioSpecialty] {
        ordered.sorted { $0.id < $1.id }
    }

    private var columnWidth: CGFloat {
        max(specialtyStep - specialtyColumnSpacing, 1)
    }

    private var boardHeight: CGFloat {
        let count = ordered.count
        guard count > 0 else { return 0 }
        let rows = (count + 1) / 2
        let cardHeight = coverCardSize.height > 1 ? coverCardSize.height : columnWidth * 16 / 9 + 44
        return 8 + CGFloat(rows) * cardHeight + CGFloat(max(rows - 1, 0)) * specialtyColumnSpacing
    }

    private func coverCard(_ specialty: PortfolioSpecialty) -> some View {
        let cover = ProviderOperatorPortfolioService.cover(in: items, specialtyId: specialty.id)
        let isDragging = draggingSpecialtyId == specialty.id
        let isPressing = pressingSpecialtyId == specialty.id && !isDragging
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 8) {
                mediaTile(item: cover, emptySymbol: "photo", emptyPrompt: cover == nil ? "Set Cover" : nil)
                    .overlay {
                        if isPressing, let pressBeganAt {
                            PortfolioCoverHoldIndicator(
                                startedAt: pressBeganAt,
                                commitDuration: PortfolioCoverDrag.moveHoldCommitDuration
                            )
                        } else if isDragging {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.92), lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                    }
                specialtyTitle(specialty, font: .provider(.subheadline, weight: .semibold))
            }
            .overlay {
                PortfolioCoverDragOverlay(
                    onHoldBegan: {
                        guard draggingSpecialtyId == nil else { return }
                        pressBeganAt = Date()
                        pressingSpecialtyId = specialty.id
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    },
                    onHoldEnded: {
                        guard draggingSpecialtyId != specialty.id else { return }
                        if pressingSpecialtyId == specialty.id {
                            pressingSpecialtyId = nil
                            pressBeganAt = nil
                        }
                    },
                    onMoveBegan: {
                        orderAtDragStart = sectionOrder
                        draggingSpecialtyId = specialty.id
                        pressingSpecialtyId = nil
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    },
                    onTap: { openSpecialtyId = specialty.id },
                    onChanged: { updateCoverDrag(of: specialty.id, to: $0) },
                    onEnded: { finishCoverDrag(of: specialty.id, at: $0) }
                )
            }
            Button {
                pendingRemoveSpecialty = specialty
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.providerOnOliveFill)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.providerOlive))
            }
            .padding(8)
            .accessibilityLabel("Remove \(specialty.name)")
            .popover(
                isPresented: removePopoverPresented(for: specialty),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                removeSpecialtyPopover(specialty)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateCoverCardSize(geo.size) }
                    .onChange(of: geo.size) { _, size in updateCoverCardSize(size) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .transaction { transaction in
            if isDragging {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .scaleEffect(isPressing ? 0.98 : 1)
        .shadow(color: Color.black.opacity(isDragging ? 0.22 : 0), radius: isDragging ? 8 : 0, y: isDragging ? 4 : 0)
        .animation(draggingSpecialtyId == nil ? .easeInOut(duration: 0.12) : nil, value: isPressing)
        .accessibilityHint("Opens this specialty. Press and hold to rearrange.")
    }

    private func gallery(for specialty: PortfolioSpecialty) -> some View {
        let sectionItems = ProviderOperatorPortfolioService.items(in: items, specialtyId: specialty.id)
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return VStack(alignment: .leading, spacing: 12) {
            specialtyTitle(specialty, font: .provider(.title3, weight: .semibold), centered: false)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(sectionItems) { item in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            tagSelection = item.primarySpecialtyId ?? specialty.id
                            taggingItem = item
                        } label: {
                            mediaTile(item: item, emptySymbol: item.isVideo ? "video" : "photo")
                        }
                        .buttonStyle(.plain)
                        Button { Task { await deleteItem(item) } } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(.white.opacity(0.92)))
                        }
                        .padding(6)
                    }
                }
                Button {
                    pendingReplaceId = nil
                    pendingReplaceAsCover = false
                    addMenuSpecialtyId = specialty.id
                } label: {
                    mediaTile(item: nil, emptySymbol: "plus", emptyPrompt: "Add Photo")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add photo or video")
            }
        }
    }

    private var clientPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                profilePhoto
                VStack(alignment: .leading, spacing: 4) {
                    Text(operatorProfile?.name ?? session.displayName)
                        .font(.provider(.headline, weight: .semibold))
                    if let handle = operatorProfile?.instagramHandle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !handle.isEmpty {
                        Button(handle.hasPrefix("@") ? handle : "@\(handle)") {
                            let bare = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                            if let url = URL(string: "https://instagram.com/\(bare)") { openURL(url) }
                        }
                        .font(.provider(.subheadline))
                    }
                }
                Spacer(minLength: 8)
                if let barberId = session.barberProfile?.id,
                   let url = AppConfiguration.consumerBookingPageURL(barberId: barberId) {
                    Button("Book") { openURL(url) }
                        .font(.provider(.callout, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.providerOlive))
                        .foregroundStyle(Color.providerOnOliveFill)
                }
            }
            if let clientSpecialtyId, let specialty = ordered.first(where: { $0.id == clientSpecialtyId }) {
                specialtyTitle(specialty, font: .provider(.title3, weight: .semibold), centered: false)
                clientWorkGrid(ProviderOperatorPortfolioService.items(in: items, specialtyId: specialty.id))
            } else if ordered.isEmpty {
                weeklyHours
            } else {
                weeklyHours
                VStack(spacing: specialtyColumnSpacing) {
                    ForEach(columns(of: ordered), id: \.self) { row in
                        HStack(alignment: .top, spacing: specialtyColumnSpacing) {
                            ForEach(row) { specialty in
                                clientSpecialtyCard(specialty)
                            }
                            if row.count == 1 {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func removePopoverPresented(for specialty: PortfolioSpecialty) -> Binding<Bool> {
        Binding(
            get: { pendingRemoveSpecialty?.id == specialty.id },
            set: { isPresented in
                if !isPresented, pendingRemoveSpecialty?.id == specialty.id {
                    pendingRemoveSpecialty = nil
                }
            }
        )
    }

    private func removeSpecialtyPopover(_ specialty: PortfolioSpecialty) -> some View {
        VStack(spacing: 0) {
            Text("Remove this specialty?")
                .font(.provider(.headline, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            Divider()
            Button(role: .destructive) {
                pendingRemoveSpecialty = nil
                Task { await removeSpecialty(specialty) }
            } label: {
                Text("Remove specialty and its work")
                    .font(.body)
                    .foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 280)
        .foregroundStyle(Color.lavaShellCream)
    }

    private func clientSpecialtyCard(_ specialty: PortfolioSpecialty) -> some View {
        let hasWork = items.contains { $0.primarySpecialtyId == specialty.id }
        let card = VStack(spacing: 8) {
            if hasWork {
                mediaTile(
                    item: ProviderOperatorPortfolioService.cover(in: items, specialtyId: specialty.id),
                    emptySymbol: "photo"
                )
            } else {
                clientEmptyWorkTile
            }
            specialtyTitle(specialty, font: .provider(.subheadline, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .top)
        return Group {
            if hasWork {
                Button { clientSpecialtyId = specialty.id } label: { card }
                    .buttonStyle(.plain)
            } else {
                card
            }
        }
    }

    private var clientEmptyWorkTile: some View {
        Color.clear
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.lavaShellCream.opacity(0.55), lineWidth: 1.5)
                Text("No Work Attached")
                    .font(.provider(.subheadline, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .padding(.horizontal, 12)
            }
    }

    private func clientWorkGrid(_ work: [OperatorPortfolioItem]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(work) { item in
                Button { lightboxItem = item } label: {
                    mediaTile(item: item, emptySymbol: item.isVideo ? "video" : "photo")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var profilePhoto: some View {
        Group {
            if let url = operatorProfile?.photoURL ?? session.barberProfile?.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill").resizable()
                }
            } else {
                Image(systemName: "person.crop.circle.fill").resizable()
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
    }

    private func specialtyTitle(_ specialty: PortfolioSpecialty, font: Font, centered: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(specialty.name)
                .lineLimit(2)
            if let price = specialty.price {
                Text(Self.specialtyPrice(price))
                    .layoutPriority(1)
            }
        }
        .font(font)
        .multilineTextAlignment(centered ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    fileprivate static func specialtyPrice(_ price: Double) -> String {
        if price.rounded() == price {
            return "$\(Int(price))"
        }
        return String(format: "$%.2f", price)
    }

    @ViewBuilder
    private func mediaTile(item: OperatorPortfolioItem?, emptySymbol: String, emptyPrompt: String? = nil) -> some View {
        Color.providerScheduleCardFill
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                if let item, let raw = item.mediaUrl, let url = URL(string: raw), item.isImage {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                } else if item?.isVideo == true {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.lavaShellCream)
                } else if let emptyPrompt {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .semibold))
                        Text(emptyPrompt)
                            .font(.provider(.subheadline, weight: .medium))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.providerOlive)
                    .padding(.horizontal, 12)
                } else {
                    Image(systemName: emptySymbol)
                        .font(.system(size: 22))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func cardPosition(for specialty: PortfolioSpecialty, index: Int) -> CGSize {
        let origin = coverSlotOrigin(index: index)
        guard draggingSpecialtyId == specialty.id else {
            return CGSize(width: origin.x, height: origin.y)
        }
        return CGSize(
            width: origin.x + dragOffset.width,
            height: origin.y + dragOffset.height
        )
    }

    private func updateSpecialtyStep(_ width: CGFloat) {
        let next = (width + specialtyColumnSpacing) / 2
        guard abs(next - specialtyStep) > 0.5 else { return }
        specialtyStep = next
    }

    private func updateCoverCardSize(_ size: CGSize) {
        guard abs(size.width - coverCardSize.width) > 0.5 || abs(size.height - coverCardSize.height) > 0.5 else { return }
        coverCardSize = size
    }

    private func updateCoverDrag(of specialtyId: String, to point: CGPoint) {
        guard draggingSpecialtyId == specialtyId, specialtyStep > 1, coverCardSize.width > 1 else { return }
        let current = ordered
        guard let from = current.firstIndex(where: { $0.id == specialtyId }) else { return }
        let target = coverDropIndex(at: point, count: current.count)
        var next = current
        if target != from {
            let moved = next.remove(at: from)
            next.insert(moved, at: min(target, next.count))
            sectionOrder = next.map(\.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        guard let placed = next.firstIndex(where: { $0.id == specialtyId }) else { return }
        let origin = coverSlotOrigin(index: placed)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragOffset = CGSize(
                width: point.x - (origin.x + coverCardSize.width / 2),
                height: point.y - (origin.y + coverCardSize.height / 2)
            )
        }
    }

    private func finishCoverDrag(of specialtyId: String, at point: CGPoint?) {
        let nextOrder: [String]
        if let point, draggingSpecialtyId == specialtyId {
            nextOrder = previewOrder(moving: specialtyId, to: point)
        } else if draggingSpecialtyId == specialtyId {
            nextOrder = orderAtDragStart
        } else {
            nextOrder = sectionOrder
        }
        let changed = point != nil && nextOrder != orderAtDragStart
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sectionOrder = nextOrder
            dragOffset = .zero
            draggingSpecialtyId = nil
            pressingSpecialtyId = nil
            pressBeganAt = nil
        }
        if changed {
            Task { await saveOrder(nextOrder) }
        }
    }

    private func previewOrder(moving specialtyId: String, to point: CGPoint) -> [String] {
        let current = ordered
        guard specialtyStep > 1, coverCardSize.width > 1,
              let from = current.firstIndex(where: { $0.id == specialtyId }) else {
            return current.map(\.id)
        }
        let target = coverDropIndex(at: point, count: current.count)
        var next = current
        if target != from {
            let moved = next.remove(at: from)
            next.insert(moved, at: min(target, next.count))
        }
        return next.map(\.id)
    }

    private func coverDropIndex(at point: CGPoint, count: Int) -> Int {
        guard count > 0, specialtyStep > 1 else { return 0 }
        let maxIndex = count - 1
        let col = min(1, max(0, Int(floor(point.x / specialtyStep))))
        let pitchY = max(coverCardSize.height + specialtyColumnSpacing, 1)
        let row = max(0, Int(floor(max(0, point.y - 4) / pitchY)))
        return min(row * 2 + col, maxIndex)
    }

    private func coverSlotOrigin(index: Int) -> CGPoint {
        let pitchY = coverCardSize.height + specialtyColumnSpacing
        return CGPoint(
            x: CGFloat(index % 2) * specialtyStep,
            y: 4 + CGFloat(index / 2) * pitchY
        )
    }

    private func beginUpload(
        specialtyId: String?,
        asCover: Bool,
        kind: PortfolioUploadTarget.Kind,
        source: PortfolioUploadTarget.Source,
        replaceId: String? = nil
    ) {
        guard let specialtyId else { return }
        uploadTarget = PortfolioUploadTarget(specialtyId: specialtyId, asCover: asCover, kind: kind, replaceId: replaceId)
        addMenuSpecialtyId = nil
        pendingReplaceId = nil
        pendingReplaceAsCover = false
        switch source {
        case .library:
            showingLibraryPicker = true
        case .camera:
            cameraCapture = kind == .video ? .video : (kind == .both ? .both : .photo)
        }
    }

    private func importLibraryItem(_ item: PhotosPickerItem) async {
        defer { libraryPickerItem = nil }
        guard let target = uploadTarget else { return }
        let isVideo = item.supportedContentTypes.contains {
            $0.conforms(to: .movie) || $0.conforms(to: .video) || $0.conforms(to: .mpeg4Movie)
        }
        if isVideo {
            if target.asCover {
                errorText = "A cover must be a photo"
                return
            }
            if let movie = try? await item.loadTransferable(type: PortfolioVideoFile.self) {
                await upload(data: movie.data, fileName: "portfolio.mp4", mimeType: "video/mp4", target: target)
            }
        } else if let data = try? await item.loadTransferable(type: Data.self) {
            #if canImport(UIKit)
            let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.86) ?? data
            #else
            let jpeg = data
            #endif
            await upload(data: jpeg, fileName: "portfolio.jpg", mimeType: "image/jpeg", target: target)
        }
    }

    private func upload(data: Data, fileName: String, mimeType: String, target: PortfolioUploadTarget) async {
        guard let barberId = session.barberProfile?.id else { return }
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        let isVideo = ProviderOperatorPortfolioService.isVideoFile(mimeType: mimeType, fileName: fileName)
        if target.asCover && isVideo {
            errorText = "A cover must be a photo"
            return
        }
        do {
            let created = try await ProviderOperatorPortfolioService.upload(
                barberId: barberId,
                fileData: data,
                fileName: fileName,
                mimeType: mimeType,
                specialtyId: target.specialtyId,
                isCover: target.asCover
            )
            if let replaceId = target.replaceId {
                try? await ProviderOperatorPortfolioService.deleteItem(barberId: barberId, itemId: replaceId)
                if taggingItem?.id == replaceId { taggingItem = nil }
            }
            var next = items.filter { $0.id != target.replaceId && $0.id != created.id }
            if target.asCover {
                next = next.map { entry in
                    entry.primarySpecialtyId == target.specialtyId && entry.isCover == true
                        ? entry.applying(isCover: false)
                        : entry
                }
            }
            let specialties = (created.specialties?.isEmpty == false) ? created.specialties : [target.specialtyId]
            next.append(created.applying(isCover: created.isCover ?? target.asCover, specialties: specialties))
            items = next
        } catch {
            errorText = ProviderOperatorPortfolioService.message(from: error)
        }
    }

    private func setCover(_ item: OperatorPortfolioItem, specialtyId: String) async {
        guard item.isImage, let barberId = session.barberProfile?.id else { return }
        do {
            _ = try await ProviderOperatorPortfolioService.setCover(
                barberId: barberId,
                itemId: item.id,
                specialtyId: specialtyId
            )
            items = items.map { entry in
                if entry.id == item.id { return entry.applying(isCover: true, specialties: [specialtyId]) }
                if entry.primarySpecialtyId == specialtyId && entry.isCover == true {
                    return entry.applying(isCover: false)
                }
                return entry
            }
            if taggingItem?.id == item.id {
                taggingItem = items.first { $0.id == item.id }
            }
        } catch {
            errorText = ProviderOperatorPortfolioService.message(from: error)
        }
    }

    private func deleteItem(_ item: OperatorPortfolioItem) async {
        guard let barberId = session.barberProfile?.id else { return }
        let specialtyId = item.primarySpecialtyId
        items.removeAll { $0.id == item.id }
        if taggingItem?.id == item.id { taggingItem = nil }
        do {
            try await ProviderOperatorPortfolioService.deleteItem(barberId: barberId, itemId: item.id)
            if item.isImage, let specialtyId {
                await backfillCover(specialtyId: specialtyId)
            }
        } catch {
            errorText = ProviderOperatorPortfolioService.message(from: error)
        }
    }

    private func removeSpecialty(_ specialty: PortfolioSpecialty) async {
        guard let barberId = session.barberProfile?.id else { return }
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        let nameKey = specialty.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let idKey = specialty.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func matches(_ value: String?) -> Bool {
            let key = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            return !key.isEmpty && (key == nameKey || key == idKey)
        }
        do {
            let fresh = try await ProviderOperatorPortfolioService.fetchOperatorProfile(barberId: barberId)
            let remainingNames = fresh.specialties.filter { !matches($0) }
            let remainingPricing = fresh.pricing.filter { !matches($0.name) && !matches($0.catalogId) }
            try await ProviderBarberServicesService.updateBarberServicesAndPricing(
                barberId: barberId,
                specialties: remainingNames,
                pricing: remainingPricing.compactMap { $0.name.isEmpty ? nil : $0.entry }
            )
            let doomed = items.filter { matches($0.primarySpecialtyId) }
            await withTaskGroup(of: Void.self) { group in
                for item in doomed {
                    group.addTask {
                        try? await ProviderOperatorPortfolioService.deleteItem(barberId: barberId, itemId: item.id)
                    }
                }
            }
            items.removeAll { matches($0.primarySpecialtyId) }
            specialties.removeAll { $0.id == specialty.id }
            sectionOrder.removeAll { $0 == specialty.id }
            try? await ProviderOperatorPortfolioService.saveSectionOrder(barberId: barberId, specialtyIds: sectionOrder)
            operatorProfile = PortfolioOperatorProfile(
                providerType: fresh.providerType,
                specialties: remainingNames,
                pricing: remainingPricing,
                name: fresh.name,
                photoURL: fresh.photoURL,
                instagramHandle: fresh.instagramHandle,
                weeklySchedule: fresh.weeklySchedule
            )
            if openSpecialtyId == specialty.id { openSpecialtyId = nil }
            if clientSpecialtyId == specialty.id { clientSpecialtyId = nil }
        } catch {
            errorText = ProviderOperatorPortfolioService.message(from: error)
        }
    }

    private func saveOrder(_ ids: [String]) async {
        guard let barberId = session.barberProfile?.id else { return }
        do {
            try await ProviderOperatorPortfolioService.saveSectionOrder(barberId: barberId, specialtyIds: ids)
        } catch {
            errorText = ProviderOperatorPortfolioService.message(from: error)
        }
    }

    private func reload() async {
        guard let barberId = session.barberProfile?.id else {
            isLoading = false
            return
        }
        isLoading = items.isEmpty
        errorText = nil
        defer { isLoading = false }
        do {
            items = try await ProviderOperatorPortfolioService.list(barberId: barberId)
        } catch {
            errorText = ProviderOperatorPortfolioService.message(from: error)
            return
        }
        sectionOrder = (try? await ProviderOperatorPortfolioService.sectionOrder(barberId: barberId)) ?? []
        do {
            let nextProfile = try await ProviderOperatorPortfolioService.fetchOperatorProfile(barberId: barberId)
            let catalog = (try? await ProviderBarberServicesService.fetchServiceCatalog(providerType: nextProfile.providerType)) ?? []
            operatorProfile = nextProfile
            specialties = ProviderOperatorPortfolioService.offeredSections(catalog: catalog, profile: nextProfile)
        } catch {
            operatorProfile = nil
            specialties = []
            if errorText == nil {
                errorText = ProviderOperatorPortfolioService.message(from: error)
            }
        }
        await backfillCovers()
    }

    private func backfillCovers() async {
        let specialtyIds = Set(items.compactMap(\.primarySpecialtyId))
        for specialtyId in specialtyIds {
            await backfillCover(specialtyId: specialtyId)
        }
    }

    private func backfillCover(specialtyId: String) async {
        let photos = items.filter { $0.primarySpecialtyId == specialtyId && $0.isImage }
        guard !photos.isEmpty, !photos.contains(where: { $0.isCover == true }) else { return }
        guard let latest = ProviderOperatorPortfolioService.cover(in: items, specialtyId: specialtyId),
              let barberId = session.barberProfile?.id else { return }
        do {
            _ = try await ProviderOperatorPortfolioService.setCover(
                barberId: barberId,
                itemId: latest.id,
                specialtyId: specialtyId
            )
            items = items.map { entry in
                if entry.id == latest.id { return entry.applying(isCover: true, specialties: [specialtyId]) }
                if entry.primarySpecialtyId == specialtyId && entry.isCover == true {
                    return entry.applying(isCover: false)
                }
                return entry
            }
        } catch {
            errorText = ProviderOperatorPortfolioService.message(from: error)
        }
    }

    private func saveTags() async {
        guard let item = taggingItem, let barberId = session.barberProfile?.id else { return }
        let selection = tagSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selection.isEmpty else { return }
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            let updated = try await ProviderOperatorPortfolioService.retag(
                barberId: barberId,
                itemId: item.id,
                specialtyIds: [selection]
            )
            items = items.map { entry in
                entry.id == item.id
                    ? updated.applying(isCover: updated.isCover ?? entry.isCover ?? false, specialties: [selection])
                    : entry
            }
            taggingItem = nil
            await backfillCover(specialtyId: selection)
            if let previous = item.primarySpecialtyId, previous != selection {
                await backfillCover(specialtyId: previous)
            }
        } catch {
            errorText = ProviderOperatorPortfolioService.message(from: error)
        }
    }

    private func closeTopLayer() {
        guard !isSaving else { return }
        if cameraCapture != nil {
            cameraCapture = nil
            return
        }
        if addMenuSpecialtyId != nil {
            addMenuSpecialtyId = nil
            return
        }
        if taggingItem != nil {
            taggingItem = nil
            return
        }
        if lightboxItem != nil {
            lightboxItem = nil
            return
        }
        if clientView {
            if clientSpecialtyId != nil {
                clientSpecialtyId = nil
            } else {
                clientView = false
            }
            return
        }
        if openSpecialtyId != nil {
            openSpecialtyId = nil
            return
        }
        dismiss()
    }

    private func tagDialog(_ item: OperatorPortfolioItem) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if item.isImage && item.isCover != true {
                    Button {
                        Task { await setCover(item, specialtyId: tagSelection.isEmpty ? (item.primarySpecialtyId ?? "") : tagSelection) }
                    } label: {
                        Text("Set as cover")
                            .font(.provider(.callout, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.providerOlive))
                            .foregroundStyle(Color.providerOnOliveFill)
                    }
                    .buttonStyle(.plain)
                    .disabled(tagSelection.isEmpty)
                    .opacity(tagSelection.isEmpty ? 0.45 : 1)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                Text("Categorize this service")
                    .font(.provider(.title3, weight: .semibold))
                if specialties.isEmpty {
                    Text("Add services to your profile before tagging work.")
                        .font(.provider(.subheadline))
                        .foregroundStyle(Color.lavaShellCreamSecondary)
                } else {
                    FlowSpecialtyPicker(specialties: specialties, selection: $tagSelection)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(uiColor: ProviderAppearance.shellBase).ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSaving ? "Saving…" : "Done") {
                        let selection = tagSelection.trimmingCharacters(in: .whitespacesAndNewlines)
                        if selection.isEmpty {
                            taggingItem = nil
                        } else {
                            Task { await saveTags() }
                        }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Replace") {
                        let specialtyId = openSpecialtyId ?? item.primarySpecialtyId ?? tagSelection
                        let displayedCover = openSpecialtyId.flatMap {
                            ProviderOperatorPortfolioService.cover(in: items, specialtyId: $0)
                        }
                        pendingReplaceId = item.id
                        pendingReplaceAsCover = displayedCover?.id == item.id
                        addMenuSpecialtyId = specialtyId
                    }
                }
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .presentationDetents([.medium, .large])
        .confirmationDialog("Add work", isPresented: addMenuPresented, titleVisibility: .visible) {
            addWorkDialogButtons
        }
        .photosPicker(isPresented: libraryPickerOnTagSheet, selection: $libraryPickerItem, matching: libraryFilter)
        .sheet(item: tagSheetCameraCapture) { capture in
            ProviderPortfolioCameraPicker(
                capture: capture,
                onPhoto: { image in
                    guard let target = uploadTarget, let data = image.jpegData(compressionQuality: 0.86) else { return }
                    Task { await upload(data: data, fileName: "portfolio.jpg", mimeType: "image/jpeg", target: target) }
                },
                onVideo: { data, mime in
                    guard let target = uploadTarget else { return }
                    Task { await upload(data: data, fileName: "portfolio.mov", mimeType: mime, target: target) }
                }
            )
            .ignoresSafeArea()
        }
    }

    private var addMenuPresented: Binding<Bool> {
        Binding(get: { addMenuSpecialtyId != nil }, set: { if !$0 { addMenuSpecialtyId = nil } })
    }

    private var libraryPickerOnTagSheet: Binding<Bool> {
        Binding(
            get: { showingLibraryPicker && taggingItem != nil },
            set: { showingLibraryPicker = $0 }
        )
    }

    private var tagSheetCameraCapture: Binding<ProviderPortfolioCameraPicker.Capture?> {
        Binding(
            get: { taggingItem != nil ? cameraCapture : nil },
            set: { cameraCapture = $0 }
        )
    }

    private var weeklyHours: some View {
        let rows = Self.weeklyRows(operatorProfile?.weeklySchedule)
        return Group {
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.day) { index, row in
                        HStack(alignment: .top, spacing: 0) {
                            Text(row.day)
                                .font(.provider(.subheadline, weight: .semibold))
                                .frame(width: 52, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(row.times, id: \.self) { time in
                                    Text(time)
                                        .font(.provider(.subheadline))
                                        .foregroundStyle(Color.lavaShellCreamSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                            }
                        }
                        if index < rows.count - 1 {
                            Divider().overlay(Color.white.opacity(0.12))
                        }
                    }
                }
                .background(Color.providerScheduleCardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            }
        }
    }

    private static func weeklyRows(_ schedule: WeeklyScheduleDTO?) -> [(day: String, times: [String])] {
        guard let schedule else { return [] }
        let order: [WeeklyScheduleDayKey] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        return order.compactMap { day in
            let entry = schedule[day]
            guard entry.enabled else { return nil }
            let ranges = entry.intervals.filter { !$0.start.isEmpty && !$0.end.isEmpty }
            guard !ranges.isEmpty else { return nil }
            return (day.shortName, ranges.map { "\(formatClock($0.start))–\(formatClock($0.end))" })
        }
    }

    private static func formatClock(_ time24: String) -> String {
        let parts = time24.split(separator: ":")
        guard parts.count >= 2, let hour24 = Int(parts[0]), let minute = Int(parts[1]) else { return time24 }
        let suffix = hour24 >= 12 ? "pm" : "am"
        let hour = hour24 % 12 == 0 ? 12 : hour24 % 12
        if minute == 0 { return "\(hour)\(suffix)" }
        return String(format: "%d:%02d%@", hour, minute, suffix)
    }
}

private struct PortfolioUploadTarget {
    enum Kind { case photo, video, both }
    enum Source { case camera, library }
    var specialtyId: String
    var asCover: Bool
    var kind: Kind
    var replaceId: String?
}

private struct FlowSpecialtyPicker: View {
    let specialties: [PortfolioSpecialty]
    @Binding var selection: String

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                ForEach(specialties) { specialty in
                    let selected = selection == specialty.id
                    Button {
                        selection = selected ? "" : specialty.id
                    } label: {
                        HStack(spacing: 4) {
                            Text(specialty.name)
                            if let price = specialty.price {
                                Text(ProviderPortfolioView.specialtyPrice(price))
                            }
                        }
                        .font(.provider(.subheadline, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule().fill(selected ? Color.providerOlive : Color.providerScheduleCardFill)
                            )
                            .foregroundStyle(selected ? Color.providerOnOliveFill : Color.lavaShellCream)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

extension ProviderPortfolioCameraPicker.Capture: Identifiable {
    var id: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video"
        case .both: return "both"
        }
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

#if canImport(UIKit)
private struct PortfolioEscapeCatcher: UIViewControllerRepresentable {
    var onEscape: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onEscape = onEscape
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onEscape = onEscape
    }

    final class Controller: UIViewController {
        var onEscape: () -> Void = {}

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override var canBecomeFirstResponder: Bool { true }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }

        override var keyCommands: [UIKeyCommand]? {
            [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape))]
        }

        @objc private func escape() { onEscape() }
    }
}
#endif

private enum PortfolioCoverDrag {
    static let moveHoldDuration = 0.55
    static let moveHoldHighlightDelay = 0.14
    static let moveHoldMaxDistance: CGFloat = 14
    static var moveHoldCommitDuration: Double { moveHoldDuration - moveHoldHighlightDelay }
}

private struct PortfolioCoverHoldIndicator: View {
    let startedAt: Date
    let commitDuration: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let progress = min(1, max(0, elapsed / commitDuration))
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.orange.opacity(0.10 + 0.10 * progress))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        Color.orange.opacity(0.35 + 0.45 * progress),
                        style: StrokeStyle(lineWidth: 2, dash: progress < 1 ? [5, 4] : [])
                    )
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.provider(size: 16, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.45 + 0.45 * progress))
                    .scaleEffect(0.88 + 0.12 * progress)
            }
        }
        .allowsHitTesting(false)
    }
}

#if canImport(UIKit)
private struct PortfolioCoverDragOverlay: UIViewRepresentable {
    var onHoldBegan: () -> Void
    var onHoldEnded: () -> Void
    var onMoveBegan: () -> Void
    var onTap: () -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onHoldBegan: onHoldBegan,
            onHoldEnded: onHoldEnded,
            onMoveBegan: onMoveBegan,
            onTap: onTap,
            onChanged: onChanged,
            onEnded: onEnded
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let preparing = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePreparing(_:))
        )
        preparing.minimumPressDuration = PortfolioCoverDrag.moveHoldHighlightDelay
        preparing.allowableMovement = PortfolioCoverDrag.moveHoldMaxDistance
        preparing.cancelsTouchesInView = false
        preparing.delegate = context.coordinator
        view.addGestureRecognizer(preparing)

        let commit = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCommit(_:))
        )
        commit.minimumPressDuration = PortfolioCoverDrag.moveHoldDuration
        commit.allowableMovement = PortfolioCoverDrag.moveHoldMaxDistance
        commit.cancelsTouchesInView = true
        commit.delegate = context.coordinator
        view.addGestureRecognizer(commit)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: commit)
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)

        context.coordinator.preparingRecognizer = preparing
        context.coordinator.commitRecognizer = commit
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onHoldBegan = onHoldBegan
        context.coordinator.onHoldEnded = onHoldEnded
        context.coordinator.onMoveBegan = onMoveBegan
        context.coordinator.onTap = onTap
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.endMove(at: nil)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onHoldBegan: () -> Void
        var onHoldEnded: () -> Void
        var onMoveBegan: () -> Void
        var onTap: () -> Void
        var onChanged: (CGPoint) -> Void
        var onEnded: (CGPoint?) -> Void
        weak var preparingRecognizer: UILongPressGestureRecognizer?
        weak var commitRecognizer: UILongPressGestureRecognizer?

        private var didBeginMove = false
        private var holdIsActive = false
        private var lockedScrollViews: [UIScrollView] = []

        init(
            onHoldBegan: @escaping () -> Void,
            onHoldEnded: @escaping () -> Void,
            onMoveBegan: @escaping () -> Void,
            onTap: @escaping () -> Void,
            onChanged: @escaping (CGPoint) -> Void,
            onEnded: @escaping (CGPoint?) -> Void
        ) {
            self.onHoldBegan = onHoldBegan
            self.onHoldEnded = onHoldEnded
            self.onMoveBegan = onMoveBegan
            self.onTap = onTap
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePreparing(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard !holdIsActive else { return }
                holdIsActive = true
                onHoldBegan()
            case .ended, .cancelled, .failed:
                guard holdIsActive else { return }
                holdIsActive = false
                if !didBeginMove { onHoldEnded() }
            default:
                break
            }
        }

        @objc func handleCommit(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard !didBeginMove else { return }
                didBeginMove = true
                lockScrolling(from: recognizer.view)
                onMoveBegan()
                report(recognizer)
            case .changed:
                guard didBeginMove else { return }
                report(recognizer)
            case .ended:
                endMove(at: contentPoint(recognizer))
            case .cancelled, .failed:
                endMove(at: nil)
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, !didBeginMove else { return }
            onTap()
        }

        func endMove(at point: CGPoint?) {
            restoreScrolling()
            let wasMoving = didBeginMove
            didBeginMove = false
            holdIsActive = false
            guard wasMoving else { return }
            onEnded(point)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            let pair: Set<ObjectIdentifier> = [
                ObjectIdentifier(gestureRecognizer),
                ObjectIdentifier(otherGestureRecognizer)
            ]
            guard let preparingRecognizer, let commitRecognizer else { return false }
            let allowed: Set<ObjectIdentifier> = [
                ObjectIdentifier(preparingRecognizer),
                ObjectIdentifier(commitRecognizer)
            ]
            return pair.isSubset(of: allowed)
        }

        private func lockScrolling(from view: UIView?) {
            lockedScrollViews = view?.enclosingScrollViews ?? []
            for scrollView in lockedScrollViews {
                scrollView.isScrollEnabled = false
            }
        }

        private func restoreScrolling() {
            for scrollView in lockedScrollViews {
                scrollView.isScrollEnabled = true
            }
            lockedScrollViews = []
        }

        private func report(_ recognizer: UILongPressGestureRecognizer) {
            guard let point = contentPoint(recognizer) else { return }
            onChanged(point)
        }

        private func contentPoint(_ recognizer: UILongPressGestureRecognizer) -> CGPoint? {
            guard let host = recognizer.view,
                  let board = host.enclosingBoard else { return nil }
            return recognizer.location(in: board)
        }
    }
}

private struct PortfolioBoardMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.accessibilityIdentifier = PortfolioBoardMarker.identifier
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static let identifier = "portfolio-specialty-board"
}

private extension UIView {
    var enclosingScrollViews: [UIScrollView] {
        sequence(first: superview, next: { $0?.superview })
            .compactMap { $0 as? UIScrollView }
    }

    var enclosingBoard: UIView? {
        if let match = sequence(first: self, next: { $0.superview })
            .first(where: { $0.accessibilityIdentifier == PortfolioBoardMarker.identifier }) {
            return match
        }
        guard let window else { return nil }
        return window.view(withBoardIdentifier: PortfolioBoardMarker.identifier)
    }

    func view(withBoardIdentifier identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        for subview in subviews {
            if let match = subview.view(withBoardIdentifier: identifier) { return match }
        }
        return nil
    }
}
#endif

private struct PortfolioLightbox: View {
    let item: OperatorPortfolioItem
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if item.isVideo, let raw = item.mediaUrl, let url = URL(string: raw) {
                #if canImport(AVKit)
                VideoPlayer(player: AVPlayer(url: url))
                #endif
            } else if let raw = item.mediaUrl, let url = URL(string: raw) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.white.opacity(0.18)))
                    }
                }
                Spacer()
            }
            .padding()
        }
    }
}
