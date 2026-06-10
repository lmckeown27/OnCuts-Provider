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
    /// Tracks an in-flight booking-details fetch so menu actions don't stack.
    private var isLoadingBooking = false
    private var linkedBooking: SimpleBookingDTO?
    private let rescheduleBannerView = ProviderPendingRescheduleBannerView()
    private var tableViewTopToHeaderConstraint: NSLayoutConstraint?
    private var tableViewTopToBannerConstraint: NSLayoutConstraint?

    private let headerBar = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let trailingStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        return stack
    }()
    private let safetyMenuButton = UIButton(type: .system)

    private static let headerIconTint = ProviderChatDesignTokens.Color.providerOlive

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBookingsChangedNotification),
            name: .providerBookingsChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleBookingsChangedNotification() {
        Task { await refreshLinkedBooking() }
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
        view.endEditing(true)
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = ProviderChatDesignTokens.Color.screenBackground

        headerBar.backgroundColor = ProviderAppearance.neutralPushedBackdrop
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        let headerDivider = UIView()
        headerDivider.backgroundColor = ProviderChatDesignTokens.Color.separator
        headerDivider.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerDivider)

        backButton.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
        backButton.tintColor = Self.headerIconTint
        backButton.accessibilityLabel = "Back"
        backButton.addTarget(self, action: #selector(conversationBackTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false

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

        inputBar.delegate = self

        loadingIndicator.color = Self.headerIconTint
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
            headerDivider.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            headerDivider.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    private func setupHeaderBar() {
        refreshSafetyMenu()
        safetyMenuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        safetyMenuButton.tintColor = Self.headerIconTint
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

            backButton.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 4),
            backButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            trailingStack.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -18),
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

        // Pin the composer above the keyboard (when shown) while hugging the safe-area
        // bottom when the keyboard is down. Two cooperating constraints — `required`
        // never-overlap-the-keyboard and `defaultHigh` rest-on-the-safe-area — are the
        // canonical iOS 15+ `keyboardLayoutGuide` pattern from Apple's "Adopt the New Look
        // of iOS 15" / WWDC sessions.
        //
        // When the keyboard is up, `keyboardLayoutGuide.topAnchor` is above the safe area;
        // the `defaultHigh` safe-area equality is forced to break and the optimizer pulls
        // the composer to `keyboard.top`. When the keyboard is down, the layout guide's
        // top sits at `view.bottomAnchor`, the required `<=` is trivially satisfied, and
        // the safe-area equality rests the composer on the safe-area bottom (above the
        // home indicator). This matches how Messages and WhatsApp position their
        // composers.
        let aboveKeyboard = inputBar.bottomAnchor.constraint(
            lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor
        )
        aboveKeyboard.priority = .required
        aboveKeyboard.isActive = true

        let restOnSafeArea = inputBar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor
        )
        restOnSafeArea.priority = .defaultHigh
        restOnSafeArea.isActive = true

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

    // MARK: - Data

    private var consumerDisplayName: String {
        if let display = conversation.otherUser?.displayName, !display.isEmpty { return display }
        let first = conversation.otherUser?.firstName ?? ""
        let last = conversation.otherUser?.lastName ?? ""
        let joined = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? "Chat" : joined
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
        feedItems = ProviderChatFeedItem.from(messages: messages)
        tableView.reloadData()
        scrollToBottom(animated: false)
        updateLoadingOverlay()
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

        Task { @MainActor in
            defer {
                isSending = false
                inputBar.setSending(false)
            }
            do {
                try await ProviderMessagesService.sendText(conversationId: conversation.id, text: text)
                inputBar.clearDraft()
                loadMessages()
            } catch {
                presentError(error)
            }
        }
    }

    private func sendPhoto(_ image: UIImage) {
        guard !isSending else { return }
        isSending = true
        inputBar.setSending(true)

        Task { @MainActor in
            defer {
                isSending = false
                inputBar.setSending(false)
            }
            do {
                try await ProviderMessagesService.sendPhoto(conversationId: conversation.id, image: image)
                loadMessages()
            } catch {
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

        linkedBooking = try? await ProviderBookingsService.fetchBooking(id: bookingId)
        updateRescheduleBannerVisibility()
    }

    private func updateRescheduleBannerVisibility() {
        guard let booking = linkedBooking,
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
            cell.configure(message: message)
            return cell

        case .bookingRequest(let message):
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ProviderChatBookingRequestCell.reuseIdentifier,
                for: indexPath
            ) as? ProviderChatBookingRequestCell else {
                return UITableViewCell()
            }
            cell.delegate = self
            cell.configure(message: message, consumerName: consumerDisplayName)
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension ProviderChatDetailViewController: UITableViewDelegate {}

// MARK: - ProviderChatInputAccessoryViewDelegate

extension ProviderChatDetailViewController: ProviderChatInputAccessoryViewDelegate {
    func chatInputAccessoryViewDidTapSend(_ view: ProviderChatInputAccessoryView, text: String) {
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
        sendPhoto(image)
    }
}

extension ProviderChatDetailViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            Task { @MainActor in
                self?.sendPhoto(image)
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
                    try await ProviderBookingRequestsService.accept(bookingId: bookingId, barberTableId: barberTableId, message: nil)
                } else {
                    try await ProviderBookingRequestsService.reject(bookingId: bookingId, barberTableId: barberTableId, reason: "Declined in chat")
                }
                loadMessages()
            } catch {
                presentError(error)
            }
        }
    }
}
