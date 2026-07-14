import PhotosUI
import SwiftUI
import UIKit

// MARK: - Delegate

protocol ProviderChatDetailViewControllerDelegate: AnyObject {
    func chatDetailViewControllerDidBlockConsumer(_ controller: ProviderChatDetailViewController, conversationId: Int)
}

// MARK: - ProviderChatDetailViewController

final class ProviderChatDetailViewController: UIViewController {
    weak var delegate: ProviderChatDetailViewControllerDelegate?

    private let conversation: ConversationRow
    var barberTableId: String?
    /// Pops the SwiftUI `messagesDetailPath` when hosted inside `NavigationStack`.
    var onNavigateBack: (() -> Void)?

    private var feedItems: [ProviderChatFeedItem] = []
    private var isLoading = false
    private var isSending = false
    private var pendingOutgoingMessageIDs = Set<Int>()
    private var pendingMessageIDSequence = 0
    private var pendingImageThumbnails: [Int: UIImage] = [:]
    private var animatedRevealIndexPaths = Set<IndexPath>()
    /// Tracks an in-flight booking-details fetch so menu actions don't stack.
    private var isLoadingBooking = false
    private var linkedBooking: SimpleBookingDTO?
    private let rescheduleBannerView = ProviderPendingRescheduleBannerView()
    private var tableViewTopToHeaderConstraint: NSLayoutConstraint?
    private var tableViewTopToBannerConstraint: NSLayoutConstraint?

    private let headerBar = UIView()
    private let headerBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let backButton = ProviderChatHeaderGlassButton(symbolName: "chevron.backward")
    private let titleLabel = UILabel()
    private let trailingStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        return stack
    }()
    private let safetyMenuButton = ProviderChatHeaderGlassButton(symbolName: "ellipsis")

    private let tableView = UITableView(frame: .zero, style: .plain)
    private lazy var inputBar = ProviderChatInputAccessoryView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    private var backPanIsHorizontal: Bool?

    init(conversation: ConversationRow) {
        self.conversation = conversation
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        // Banner must be in `view` before `setupConstraints()` pins it to `headerBar`.
        setupRescheduleBanner()
        setupConstraints()
        setupHeaderBar()
        loadMessages()
        Task { await refreshLinkedBooking() }
        installBackPanGestures()
        installKeyboardDismissGestures()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBookingsChangedNotification),
            name: .providerBookingsChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConversationShouldRefreshNotification),
            name: .providerMessagingConversationShouldRefresh,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleBookingsChangedNotification() {
        Task { await refreshLinkedBooking() }
    }

    @objc private func handleConversationShouldRefreshNotification(_ notification: Notification) {
        guard conversationId(from: notification.userInfo) == conversation.id else { return }
        ProviderConversationMessagesPrefetch.invalidate(conversationId: conversation.id)
        reloadMessagesFromServer()
    }

    private func conversationId(from userInfo: [AnyHashable: Any]?) -> Int? {
        guard let userInfo else { return nil }
        switch userInfo["conversationId"] {
        case let value as Int: return value
        case let value as Int64: return Int(value)
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    private func reloadMessagesFromServer() {
        guard !isLoading else { return }
        isLoading = true
        updateLoadingOverlay()

        Task { @MainActor in
            defer {
                isLoading = false
                updateLoadingOverlay()
            }

            Task { try? await ProviderMessagesService.markRead(conversationId: conversation.id) }

            do {
                let messages = try await ProviderMessagesService.listMessages(conversationId: conversation.id)
                ProviderConversationMessagesPrefetch.store(conversationId: conversation.id, messages: messages)
                applyMessages(messages)
            } catch {
                if feedItems.isEmpty {
                    presentError(error)
                }
            }
        }
    }

    private func setupRescheduleBanner() {
        rescheduleBannerView.isHidden = true
        rescheduleBannerView.onApprove = { [weak self] in self?.approveLinkedRescheduleRequest() }
        rescheduleBannerView.onDecline = { [weak self] in self?.declineLinkedRescheduleRequest() }
        view.addSubview(rescheduleBannerView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // The composer is a regular subview (see `ProviderChatInputAccessoryView`'s type
        // doc for the *why*), so it can never collapse on return. Dismiss the keyboard
        // when leaving so the next screen doesn't inherit a stray edit session.
        inputBar.resignComposerFocus()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = ProviderChatDesignTokens.Color.screenBackground

        headerBar.backgroundColor = .clear
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        headerBlurView.translatesAutoresizingMaskIntoConstraints = false
        headerBar.insertSubview(headerBlurView, at: 0)

        let headerDivider = UIView()
        headerDivider.backgroundColor = ProviderChatDesignTokens.Color.separator
        headerDivider.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerDivider)

        backButton.accessibilityLabel = "Back"
        backButton.addTarget(self, action: #selector(conversationBackTapped), for: .touchUpInside)

        titleLabel.text = consumerDisplayName
        titleLabel.font = ProviderChatDesignTokens.Font.heading(17)
        titleLabel.textColor = ProviderChatDesignTokens.Color.lavaShellCream
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        trailingStack.translatesAutoresizingMaskIntoConstraints = false

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.keyboardDismissMode = .interactive
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ProviderChatMessageCell.self, forCellReuseIdentifier: ProviderChatMessageCell.reuseIdentifier)
        tableView.register(ProviderChatBookingRequestCell.self, forCellReuseIdentifier: ProviderChatBookingRequestCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        let topPadding = ProviderChatDesignTokens.Metrics.messageListTopPadding
        tableView.contentInset.top = topPadding
        tableView.scrollIndicatorInsets.top = topPadding

        inputBar.delegate = self

        loadingIndicator.color = ProviderChatDesignTokens.Color.lavaShellCream
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerBar)
        headerBar.addSubview(backButton)
        headerBar.addSubview(titleLabel)
        headerBar.addSubview(trailingStack)
        view.addSubview(tableView)
        view.addSubview(inputBar)
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
            headerBlurView.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerBlurView.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            headerBlurView.topAnchor.constraint(equalTo: headerBar.topAnchor),
            headerBlurView.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerDivider.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            headerDivider.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    private func setupHeaderBar() {
        refreshSafetyMenu()
        safetyMenuButton.accessibilityLabel = "Conversation options"
        safetyMenuButton.showsMenuAsPrimaryAction = true
        trailingStack.addArrangedSubview(safetyMenuButton)
    }

    private var hasLinkedBooking: Bool {
        guard let bookingId = conversation.bookingId?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !bookingId.isEmpty
    }

    private func refreshSafetyMenu() {
        safetyMenuButton.menu = makeSafetyMenu()
    }

    // MARK: - Auto Layout Constraints

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 44),

            backButton.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 14),
            backButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            trailingStack.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -14),
            trailingStack.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: headerBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -8),

            rescheduleBannerView.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 8),
            rescheduleBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            rescheduleBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // Hard-pin the table's bottom to the composer's top so the list always sits
            // strictly above the composer. No more `contentInset` fudging.
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Pin the composer to the keyboard layout guide so it tracks presentation and
        // dismissal animations. When the keyboard is hidden the guide's top sits at the
        // safe-area bottom — no separate safe-area fallback constraint is needed.
        inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor).isActive = true

        tableViewTopToHeaderConstraint = tableView.topAnchor.constraint(equalTo: headerBar.bottomAnchor)
        tableViewTopToBannerConstraint = tableView.topAnchor.constraint(equalTo: rescheduleBannerView.bottomAnchor, constant: 8)
        tableViewTopToHeaderConstraint?.isActive = true
    }

    private func installBackPanGestures() {
        guard let rootView = view else { return }
        for gestureView in [rootView, headerBar, tableView, inputBar] as [UIView] {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleBackPan(_:)))
            pan.delegate = self
            pan.cancelsTouchesInView = false
            gestureView.addGestureRecognizer(pan)
        }
    }

    private func installKeyboardDismissGestures() {
        for target in [tableView, headerBar, rescheduleBannerView] as [UIView] {
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismissComposerKeyboard))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            target.addGestureRecognizer(tap)
        }
    }

    @objc private func dismissComposerKeyboard() {
        inputBar.resignComposerFocus()
    }

    // MARK: - Data

    private var consumerDisplayName: String {
        if let display = conversation.otherUser?.displayName, !display.isEmpty { return display }
        let first = conversation.otherUser?.firstName ?? ""
        let last = conversation.otherUser?.lastName ?? ""
        let joined = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? "Chat" : joined
    }

    private var linkedBookingScheduleSummary: String? {
        guard let linkedBooking else { return nil }
        let formatted = linkedBooking.formattedProviderEffectiveSchedule()
        return formatted == "Time TBD" ? nil : formatted
    }

    private func loadMessages() {
        guard !isLoading else { return }
        isLoading = true

        if feedItems.isEmpty,
           let cached = ProviderConversationMessagesPrefetch.cachedMessages(for: conversation.id) {
            applyMessages(cached)
        }
        updateLoadingOverlay()

        Task { @MainActor in
            defer {
                isLoading = false
                updateLoadingOverlay()
            }

            // Don't block the thread fetch on read-receipt bookkeeping.
            Task { try? await ProviderMessagesService.markRead(conversationId: conversation.id) }

            do {
                let messages = try await ProviderMessagesService.listMessages(conversationId: conversation.id)
                ProviderConversationMessagesPrefetch.store(conversationId: conversation.id, messages: messages)
                applyMessages(messages)
            } catch {
                if feedItems.isEmpty {
                    presentError(error)
                }
            }
        }
    }

    private func applyMessages(_ messages: [ChatMessageDTO]) {
        pendingOutgoingMessageIDs.removeAll()
        pendingImageThumbnails.removeAll()
        feedItems = ProviderChatFeedItem.from(messages: messages)
        tableView.reloadData()
        scrollToBottom(animated: false)
        updateLoadingOverlay()
    }

    private func generatePendingMessageID() -> Int {
        pendingMessageIDSequence -= 1
        return pendingMessageIDSequence
    }

    private func insertOutgoingFeedItems(_ items: [ProviderChatFeedItem], animated: Bool) {
        guard !items.isEmpty else { return }

        let startIndex = feedItems.count
        let indexPaths = items.indices.map { IndexPath(row: startIndex + $0, section: 0) }
        if animated {
            animatedRevealIndexPaths.formUnion(indexPaths)
        }

        tableView.performBatchUpdates {
            feedItems.append(contentsOf: items)
            tableView.insertRows(at: indexPaths, with: .none)
        } completion: { [weak self] _ in
            guard let self else { return }
            self.scrollToBottom(animated: true)
            if animated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    self.animatedRevealIndexPaths.subtract(indexPaths)
                }
            }
        }
    }

    private func removePendingMessage(id pendingID: Int) {
        pendingOutgoingMessageIDs.remove(pendingID)
        pendingImageThumbnails.removeValue(forKey: pendingID)
        guard let index = feedItems.firstIndex(where: { $0.id == pendingID }) else { return }

        tableView.performBatchUpdates {
            feedItems.remove(at: index)
            tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .none)
        }
    }

    private func finalizeSend(replacingPendingID pendingID: Int) async {
        do {
            let messages = try await ProviderMessagesService.listMessages(conversationId: conversation.id)
            ProviderConversationMessagesPrefetch.store(conversationId: conversation.id, messages: messages)

            let serverFeed = ProviderChatFeedItem.from(messages: messages)
            let localRealIDs = Set(feedItems.map(\.id).filter { $0 > 0 })
            let newFromServer = serverFeed.filter { !localRealIDs.contains($0.id) }

            guard feedItems.contains(where: { $0.id == pendingID }) else {
                applyMessages(messages)
                return
            }

            pendingOutgoingMessageIDs.remove(pendingID)
            pendingImageThumbnails.removeValue(forKey: pendingID)

            guard !newFromServer.isEmpty else {
                removePendingMessage(id: pendingID)
                return
            }

            let pendingIndex = feedItems.firstIndex(where: { $0.id == pendingID }) ?? (feedItems.count - 1)
            let insertPaths = newFromServer.indices.map { IndexPath(row: pendingIndex + $0, section: 0) }
            animatedRevealIndexPaths.formUnion(insertPaths)

            tableView.performBatchUpdates {
                feedItems.remove(at: pendingIndex)
                tableView.deleteRows(at: [IndexPath(row: pendingIndex, section: 0)], with: .none)

                for (offset, item) in newFromServer.enumerated() {
                    feedItems.insert(item, at: pendingIndex + offset)
                }
                tableView.insertRows(at: insertPaths, with: .none)
            } completion: { [weak self] _ in
                guard let self else { return }
                self.scrollToBottom(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    self.animatedRevealIndexPaths.subtract(insertPaths)
                }
            }
        } catch {
            removePendingMessage(id: pendingID)
            presentError(error)
        }
    }

    private func updateLoadingOverlay() {
        let show = isLoading && feedItems.isEmpty
        loadingIndicator.isHidden = !show
        if show {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    private func scrollToBottom(animated: Bool) {
        guard !feedItems.isEmpty else { return }
        let indexPath = IndexPath(row: feedItems.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }

    private func sendMessage(_ text: String) {
        guard !isSending else { return }
        isSending = true
        inputBar.setSending(true)

        let pendingID = generatePendingMessageID()
        pendingOutgoingMessageIDs.insert(pendingID)
        let pending = ChatMessageDTO.pendingOutbound(id: pendingID, text: text)
        inputBar.clearDraft()
        insertOutgoingFeedItems([.text(pending)], animated: true)

        Task { @MainActor in
            defer {
                isSending = false
                inputBar.setSending(false)
            }
            do {
                try await ProviderMessagesService.sendText(conversationId: conversation.id, text: text)
                await finalizeSend(replacingPendingID: pendingID)
            } catch {
                removePendingMessage(id: pendingID)
                inputBar.restoreDraft(text)
                presentError(error)
            }
        }
    }

    private func sendPhoto(_ image: UIImage) {
        guard !isSending else { return }
        isSending = true
        inputBar.setSending(true)
        inputBar.clearDraftPhoto()

        let pendingID = generatePendingMessageID()
        pendingOutgoingMessageIDs.insert(pendingID)
        pendingImageThumbnails[pendingID] = image
        let pending = ChatMessageDTO.pendingOutboundImage(id: pendingID)
        insertOutgoingFeedItems([.text(pending)], animated: true)

        Task { @MainActor in
            defer {
                isSending = false
                inputBar.setSending(false)
            }
            do {
                try await ProviderMessagesService.sendPhoto(conversationId: conversation.id, image: image)
                await finalizeSend(replacingPendingID: pendingID)
            } catch {
                removePendingMessage(id: pendingID)
                inputBar.setDraftPhoto(image)
                presentError(error)
            }
        }
    }

    // MARK: - Action Handlers

    @objc private func conversationBackTapped() {
        if let onNavigateBack {
            onNavigateBack()
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @objc private func handleBackPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            backPanIsHorizontal = nil
        case .changed:
            guard backPanIsHorizontal == nil else { return }
            let translation = recognizer.translation(in: view)
            guard abs(translation.x) > 8 || abs(translation.y) > 8 else { return }
            backPanIsHorizontal = abs(translation.x) >= abs(translation.y) * 0.85
        case .ended, .cancelled:
            defer { backPanIsHorizontal = nil }
            guard backPanIsHorizontal == true else { return }
            let translation = recognizer.translation(in: view)
            let velocity = recognizer.velocity(in: view)
            guard translation.x > 0 else { return }
            let swipeDistance = translation.x / max(view.bounds.width, 1)
            if swipeDistance >= ProviderShellNavigator.interactiveDismissSwipeFraction || velocity.x > 300 {
                conversationBackTapped()
            }
        default:
            break
        }
    }

    /// Loads the linked booking (including any pending reschedule request) for the chat banner.
    private func refreshLinkedBooking() async {
        guard hasLinkedBooking,
              let bookingId = conversation.bookingId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bookingId.isEmpty
        else {
            linkedBooking = nil
            updateRescheduleBannerVisibility()
            return
        }

        let previousSchedule = linkedBooking?.providerEffectiveScheduledTime
        linkedBooking = try? await ProviderBookingsService.fetchBooking(id: bookingId)
        updateRescheduleBannerVisibility()
        if linkedBooking?.providerEffectiveScheduledTime != previousSchedule {
            reloadBookingRequestCells()
        }
    }

    private func reloadBookingRequestCells() {
        let bookingRequestIndexPaths = feedItems.enumerated().compactMap { index, item -> IndexPath? in
            if case .bookingRequest = item { return IndexPath(row: index, section: 0) }
            return nil
        }
        guard !bookingRequestIndexPaths.isEmpty else { return }
        tableView.reloadRows(at: bookingRequestIndexPaths, with: .none)
    }

    private func updateRescheduleBannerVisibility() {
        guard let booking = linkedBooking,
              booking.statusUpper != "PENDING",
              booking.hasPendingRescheduleRequest,
              let request = booking.pendingRescheduleRequest
        else {
            rescheduleBannerView.isHidden = true
            tableViewTopToBannerConstraint?.isActive = false
            tableViewTopToHeaderConstraint?.isActive = true
            return
        }

        rescheduleBannerView.configure(booking: booking, request: request)
        rescheduleBannerView.setActionsEnabled(!isLoadingBooking)
        rescheduleBannerView.isHidden = false
        tableViewTopToHeaderConstraint?.isActive = false
        tableViewTopToBannerConstraint?.isActive = true
    }

    private func approveLinkedRescheduleRequest() {
        guard let bookingId = linkedBooking?.id else { return }
        Task { @MainActor in
            rescheduleBannerView.setActionsEnabled(false)
            defer { rescheduleBannerView.setActionsEnabled(true) }
            do {
                try await ProviderBookingsService.approveRescheduleRequest(bookingId: bookingId)
                await refreshLinkedBooking()
                NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
            } catch {
                presentError(error)
            }
        }
    }

    private func declineLinkedRescheduleRequest() {
        guard let bookingId = linkedBooking?.id else { return }
        let sheet = UIAlertController(
            title: "Decline schedule change?",
            message: "The appointment will stay at the current date and time.",
            preferredStyle: .alert
        )
        sheet.addAction(UIAlertAction(title: "Keep Request", style: .cancel))
        sheet.addAction(UIAlertAction(title: "Decline", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.rescheduleBannerView.setActionsEnabled(false)
                defer { self.rescheduleBannerView.setActionsEnabled(true) }
                do {
                    try await ProviderBookingsService.rejectRescheduleRequest(bookingId: bookingId)
                    await self.refreshLinkedBooking()
                    NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
                } catch {
                    self.presentError(error)
                }
            }
        })
        present(sheet, animated: true)
    }

    private func bookingDetailsTapped() {
        guard !isLoadingBooking,
              let bookingId = conversation.bookingId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bookingId.isEmpty
        else { return }
        Task { @MainActor in
            await fetchAndPresentBookingDetails(bookingId: bookingId)
        }
    }

    /// Resolves `conversation.bookingId` to a full `SimpleBookingDTO` and presents booking detail modally.
    private func fetchAndPresentBookingDetails(bookingId: String) async {
        isLoadingBooking = true
        defer { isLoadingBooking = false }

        let booking: SimpleBookingDTO
        do {
            booking = try await ProviderBookingsService.fetchBooking(id: bookingId)
            linkedBooking = booking
            updateRescheduleBannerVisibility()
        } catch {
            presentError(error)
            return
        }

        // Present modally — conversation detail lives in SwiftUI `NavigationStack`, not a UIKit nav push.
        let detail = BookingDetailViewController(
            booking: booking,
            barberTableId: barberTableId,
            showsOpenConversationButton: false,
            onChanged: {
            await MainActor.run {
                NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
            }
        }
        )
        detail.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .plain,
            target: self,
            action: #selector(dismissPresentedBookingDetails)
        )
        let nav = UINavigationController(rootViewController: detail)
        ProviderChatNavigationBarStyle.apply(to: nav.navigationBar)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    @objc private func dismissPresentedBookingDetails() {
        dismiss(animated: true)
    }

    private func makeSafetyMenu() -> UIMenu {
        var items: [UIMenuElement] = []

        if hasLinkedBooking {
            let bookingDetails = UIAction(
                title: "Booking Details",
                image: UIImage(systemName: "calendar")
            ) { [weak self] _ in
                self?.bookingDetailsTapped()
            }
            items.append(bookingDetails)
        }

        let block = UIAction(title: "Block Consumer", attributes: .destructive) { [weak self] _ in
            self?.confirmBlockConsumer()
        }
        let report = UIAction(title: "Report Abuse", attributes: .destructive) { [weak self] _ in
            self?.presentReportFlow()
        }
        items.append(contentsOf: [block, report])

        return UIMenu(title: "", options: .displayInline, children: items)
    }

    private func confirmBlockConsumer() {
        let sheet = UIAlertController(
            title: "Block Consumer?",
            message: "You will no longer receive messages from this customer.",
            preferredStyle: .alert
        )
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.addAction(UIAlertAction(title: "Block", style: .destructive) { [weak self] _ in
            self?.blockConsumer()
        })
        present(sheet, animated: true)
    }

    private func blockConsumer() {
        guard let userId = conversation.otherUser?.id else {
            delegate?.chatDetailViewControllerDidBlockConsumer(self, conversationId: conversation.id)
            return
        }

        Task { @MainActor in
            do {
                try await ProviderMessagesService.blockConsumer(userId: userId)
                delegate?.chatDetailViewControllerDidBlockConsumer(self, conversationId: conversation.id)
            } catch {
                presentError(error)
            }
        }
    }

    private func presentReportFlow() {
        let sheet = UIAlertController(title: "Report Abuse", message: "Tell us what happened.", preferredStyle: .alert)
        sheet.addTextField { field in
            field.placeholder = "Reason"
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.addAction(UIAlertAction(title: "Submit", style: .destructive) { [weak self] _ in
            self?.submitReport(reason: sheet.textFields?.first?.text ?? "Unspecified")
        })
        present(sheet, animated: true)
    }

    private func submitReport(reason: String) {
        guard let userId = conversation.otherUser?.id else { return }
        Task { @MainActor in
            do {
                try await ProviderMessagesService.reportConsumer(
                    userId: userId,
                    conversationId: conversation.id,
                    reason: reason
                )
                let alert = UIAlertController(title: "Report submitted", message: "Our team will review this conversation.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            } catch {
                presentError(error)
            }
        }
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ProviderChatDetailViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        feedItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch feedItems[indexPath.row] {
        case .text(let message):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ProviderChatMessageCell.reuseIdentifier,
                for: indexPath
            ) as? ProviderChatMessageCell else {
                return UITableViewCell()
            }
            cell.configure(message: message, pendingImage: pendingImageThumbnails[message.id])
            return cell

        case .bookingRequest(let message):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ProviderChatBookingRequestCell.reuseIdentifier,
                for: indexPath
            ) as? ProviderChatBookingRequestCell else {
                return UITableViewCell()
            }
            cell.delegate = self
            cell.configure(
                message: message,
                consumerName: consumerDisplayName,
                scheduleSummary: linkedBookingScheduleSummary
            )
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension ProviderChatDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard animatedRevealIndexPaths.contains(indexPath) else { return }

        cell.contentView.alpha = 0
        cell.contentView.transform = CGAffineTransform(translationX: 0, y: 18).scaledBy(x: 0.96, y: 0.96)
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.25,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            cell.contentView.alpha = 1
            cell.contentView.transform = .identity
        }
    }
}

// MARK: - ProviderChatInputAccessoryViewDelegate

extension ProviderChatDetailViewController: ProviderChatInputAccessoryViewDelegate {
    func chatInputAccessoryViewDidTapSend(_ view: ProviderChatInputAccessoryView, text: String, draftPhoto: UIImage?) {
        if let draftPhoto {
            sendPhoto(draftPhoto)
            return
        }
        sendMessage(text)
    }

    func chatInputAccessoryViewDidTapAttachment(_ view: ProviderChatInputAccessoryView) {
        presentPhotoSourceSheet()
    }

    private func presentPhotoSourceSheet() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.presentPhotoLibraryPicker()
        })
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
                self?.presentCameraPicker()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = inputBar
            pop.sourceRect = CGRect(x: 0, y: 0, width: 44, height: 44)
        }
        present(sheet, animated: true)
    }

    private func presentPhotoLibraryPicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentCameraPicker() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = self
        present(picker, animated: true)
    }
}

// MARK: - Back swipe

extension ProviderChatDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer.view is UIScrollView
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer is UITapGestureRecognizer else { return true }
        let location = touch.location(in: view)
        return !inputBar.frame.contains(location)
    }
}

// MARK: - Camera & photo library

extension ProviderChatDetailViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        inputBar.setDraftPhoto(image)
    }
}

extension ProviderChatDetailViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            Task { @MainActor in
                self?.inputBar.setDraftPhoto(image)
            }
        }
    }
}

// MARK: - ProviderChatBookingRequestCellDelegate

extension ProviderChatDetailViewController: ProviderChatBookingRequestCellDelegate {
    func bookingRequestCell(_ cell: ProviderChatBookingRequestCell, didTapAccept message: ChatMessageDTO) {
        handleBookingRequest(message, accepted: true)
    }

    func bookingRequestCell(_ cell: ProviderChatBookingRequestCell, didTapDecline message: ChatMessageDTO) {
        handleBookingRequest(message, accepted: false)
    }

    private func handleBookingRequest(_ message: ChatMessageDTO, accepted: Bool) {
        guard let bookingId = message.metadata?.bookingId ?? conversation.bookingId,
              let barberTableId else {
            presentError(NSError(domain: "ProviderChat", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing booking context."]))
            return
        }

        Task { @MainActor in
            do {
                if accepted {
                    try await ProviderBookingRequestsService.acceptApplyingConsumerSchedule(
                        bookingId: bookingId,
                        barberTableId: barberTableId,
                        booking: self.linkedBooking,
                        message: nil
                    )
                } else {
                    try await ProviderBookingRequestsService.reject(bookingId: bookingId, barberTableId: barberTableId)
                }
                loadMessages()
            } catch {
                presentError(error)
            }
        }
    }
}
