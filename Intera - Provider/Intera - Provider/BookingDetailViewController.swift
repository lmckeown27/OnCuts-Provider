import SwiftUI
import UIKit

// MARK: - BookingDetailViewController

/// Native UIKit booking-details screen for the provider app.
///
/// **Origin.** Started life as a translation of the web "Booking Details" modal layout
/// (card-based, with a header status capsule, "When / Where" sections, and a stacked
/// action footer). It has since been re-skinned to the app's dark lava / olive theme so
/// it sits flush next to the other provider screens and wired to live booking data, so
/// it can fully replace the old SwiftUI `ProviderBookingDetailView` at every call site:
///
/// 1. **Chat conversation** — `ProviderChatDetailViewController` pushes us when the
///    barber taps the calendar bar button on a booking-tied chat.
/// 2. **Dashboard shell** — `ProviderDashboardShellView`'s
///    `.navigationDestination(for: SimpleBookingDTO.self)`.
/// 3. **Bookings list** — `ProviderBookingsListView`'s
///    `.navigationDestination(for: SimpleBookingDTO.self)`.
///
/// Sites (2) and (3) are SwiftUI navigation destinations, so this VC is bridged into
/// SwiftUI via `BookingDetailHost` (defined at the bottom of this file).
///
/// **Action surface.** The visible buttons are status-driven, matching the legacy
/// SwiftUI implementation exactly so existing barber muscle memory is preserved:
///
/// | Status     | Visible actions                                                  |
/// |------------|------------------------------------------------------------------|
/// | PENDING    | Accept · Decline · Reschedule                                    |
/// | ACCEPTED   | Request Payment · Reschedule · Cancel                            |
/// | COMPLETED  | Undo completion                                                  |
/// | other      | (read-only — no action buttons)                                  |
///
/// All mutations go through `ProviderBookingsService`. On success the supplied
/// `onChanged` callback fires so the parent (list / dashboard / chat) can refresh.
final class BookingDetailViewController: UIViewController {

    // MARK: - Theme tokens (dark lava)

    private enum Token {
        /// Midnight base — matches the lava-lamp's base color so the screen blends with
        /// the dashboard's animated background when pushed onto the SwiftUI nav stack.
        static let background = InteraLavaMidnight.uiColor
        /// Olive accent shared with the rest of the provider chrome.
        static let accent = ProviderAppearance.olive
        static let primaryText = ProviderAppearance.primaryText
        static let secondaryText = ProviderAppearance.secondaryText
        static let cardSurface = ProviderAppearance.elevatedSurface
        static let cardBorder = ProviderAppearance.elevatedSurfaceStroke
        /// Status palette.
        static let statusGreen = ProviderChatDesignTokens.Color.statusGreen
        static let statusYellow = ProviderChatDesignTokens.Color.statusYellow
        /// Destructive — adaptive for light/dark backgrounds.
        static let destructiveFill = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x7F / 255, green: 0x1D / 255, blue: 0x1D / 255, alpha: 0.32)
                : UIColor(red: 0xFE / 255, green: 0xE2 / 255, blue: 0xE2 / 255, alpha: 1)
        }
        static let destructiveText = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0xFE / 255, green: 0xB2 / 255, blue: 0xB2 / 255, alpha: 1)
                : UIColor(red: 0xB9 / 255, green: 0x1C / 255, blue: 0x1C / 255, alpha: 1)
        }
        /// Cancel booking — stronger contrast in light mode than generic destructive secondary buttons.
        static let cancelButtonFill = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x7F / 255, green: 0x1D / 255, blue: 0x1D / 255, alpha: 0.45)
                : UIColor(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255, alpha: 1)
        }
        static let cancelButtonText = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0xFE / 255, green: 0xB2 / 255, blue: 0xB2 / 255, alpha: 1)
                : UIColor.white
        }

        static let cardCornerRadius: CGFloat = 14
        static let stackSpacing: CGFloat = 16
        static let contentMargin: CGFloat = 20
    }

    // MARK: - Data

    private let booking: SimpleBookingDTO
    private let barberTableId: String?
    private let showsOpenConversationButton: Bool
    private let onOpenConversation: ((Int) -> Void)?
    private let onChanged: () async -> Void

    /// Set while a `ProviderBookingsService` call is in flight; disables every action
    /// button and shows the centered spinner so the user can't double-trigger.
    private var isWorking = false {
        didSet {
            for button in actionButtons { button.isEnabled = !isWorking }
            messageCustomerControlView?.isUserInteractionEnabled = !isWorking
            messageCustomerControlView?.alpha = isWorking ? 0.55 : 1
            spinnerOverlay.isHidden = !isWorking
            if isWorking { spinner.startAnimating() } else { spinner.stopAnimating() }
        }
    }

    /// Collected so `isWorking` can disable all of them at once without each section
    /// needing to expose its own enable handle.
    private var actionButtons: [UIButton] = []
    private weak var messageCustomerControlView: UIView?

    /// Held so we can rebuild the actions stack in place when `booking` is replaced after
    /// a successful mutation (e.g. PENDING → ACCEPTED removes the Accept/Decline pair and
    /// surfaces Request Payment).
    private var actionsContainer: UIStackView?

    /// Held so we can update the capsule label/color when the status changes.
    private weak var statusCapsule: UIView?
    private weak var statusCapsuleLabel: UILabel?

    /// Locally-mutated copy of the booking. Initialized from the injected `booking`, then
    /// replaced after each successful mutation via the optimistic-update helper. Keeps
    /// the parent's refresh asynchronous (`onChanged()` does the network reload) without
    /// flickering stale UI in the meantime.
    private var current: SimpleBookingDTO {
        didSet {
            clearAwaitingPaymentStateIfResolved()
            applyCurrent()
        }
    }

    /// Local flag that flips `true` after a successful `requestPayment` call.
    ///
    /// **Backend reality.** `POST /bookings-simple/:id/request-payment` does *two*
    /// things server-side: it stamps `payment_requested_at` and it transitions the
    /// booking's `status` from `ACCEPTED` straight to `COMPLETED`. There is no separate
    /// `AWAITING_PAYMENT` status today, so the only signal the client has that a
    /// `COMPLETED` booking is actually "waiting for the customer to pay" (rather than
    /// "barber tapped Mark Complete and we're just done") is this in-memory flag,
    /// mirrored to `ProviderAwaitingPaymentTracker.shared` so it survives view
    /// teardown.
    ///
    /// While this is `true` *and* `current.statusUpper` is one of
    /// {ACCEPTED, COMPLETED}, the action stack renders an inert "Awaiting Payment"
    /// status pill with an "Undo Completion" follow-up. The two-status window covers
    /// both the optimistic flash right after a tap (status briefly still ACCEPTED) and
    /// the steady state once the round-trip lands and the server-fresh booking shows
    /// up as COMPLETED. The tracker mirror also lets the dashboard render an "Awaiting
    /// Payment" banner above the schedule and lets the user re-enter the same booking
    /// and still see the pill instead of a fresh "Request Payment" CTA.
    private var paymentRequested = false {
        didSet {
            guard oldValue != paymentRequested else { return }
            if paymentRequested {
                ProviderAwaitingPaymentTracker.shared.markRequested(current.id)
            } else {
                ProviderAwaitingPaymentTracker.shared.clearRequest(for: current.id)
            }
            // The tracker is intentionally written before the view rebuild so dashboard
            // observers that wake on the same tracker change see a consistent picture.
            if isViewLoaded {
                applyCurrent()
            }
        }
    }

    init(
        booking: SimpleBookingDTO,
        barberTableId: String?,
        showsOpenConversationButton: Bool = true,
        onOpenConversation: ((Int) -> Void)? = nil,
        onChanged: @escaping () async -> Void
    ) {
        self.booking = booking
        self.barberTableId = barberTableId
        self.showsOpenConversationButton = showsOpenConversationButton
        self.onOpenConversation = onOpenConversation
        self.current = booking
        self.onChanged = onChanged
        super.init(nibName: nil, bundle: nil)
        // Re-hydrate the "Awaiting Payment" state if the tracker still has this booking.
        // The `didSet` will fire (oldValue == false ≠ new value), update the tracker
        // idempotently, and defer `applyCurrent()` because `isViewLoaded` is still
        // false here. `viewDidLoad`'s `buildSections()` call picks up the correct UI on
        // first layout.
        if ProviderAwaitingPaymentTracker.shared.requestedIds.contains(booking.id)
            || booking.paymentRequestedAt != nil,
           Self.canShowAwaitingPayment(for: booking) {
            paymentRequested = true
        } else if Self.isPaymentResolved(booking) {
            ProviderAwaitingPaymentTracker.shared.clearRequest(for: booking.id)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Subviews

    private let scrollView = UIScrollView()
    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Token.stackSpacing
        stack.alignment = .fill
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: Token.contentMargin,
            left: Token.contentMargin,
            bottom: Token.contentMargin,
            right: Token.contentMargin
        )
        return stack
    }()

    private let spinner = UIActivityIndicatorView(style: .large)
    private let spinnerOverlay: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Token.background
        navigationItem.largeTitleDisplayMode = .never

        setupHierarchy()
        setupConstraints()
        buildSections()
        scheduleDeferredRefresh()

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

    /// Defers network refresh until after the shell slide-in so the page appears immediately.
    private func scheduleDeferredRefresh() {
        Task { @MainActor in
            await Task.yield()
            await refreshBookingDetailsIfNeeded()
        }
    }

    @objc private func handleBookingsChangedNotification() {
        Task { await refreshBookingDetailsIfNeeded() }
    }

    /// Refreshes from `GET /bookings-simple/:id` when the booking may have been paid since
    /// the list payload was loaded (common after the consumer completes checkout).
    private func refreshBookingDetailsIfNeeded() async {
        let awaitingLocally = paymentRequested
            || ProviderAwaitingPaymentTracker.shared.requestedIds.contains(current.id)
        let needsPaymentFields = current.statusUpper == "PAID"
            && current.tipAmountCents == nil
            && current.totalPaidCents == nil
        let mayHaveRescheduleRequest = Self.mayHavePendingRescheduleRequest(current)
        guard awaitingLocally || needsPaymentFields || mayHaveRescheduleRequest else { return }

        do {
            let fresh = try await ProviderBookingsService.fetchBooking(id: current.id)
            current = fresh
        } catch {
            // List payload may already include payment data; keep showing what we have.
        }
    }

    private func clearAwaitingPaymentStateIfResolved() {
        guard Self.isPaymentResolved(current) else { return }
        let wasTracked = paymentRequested
            || ProviderAwaitingPaymentTracker.shared.requestedIds.contains(current.id)
        guard wasTracked else { return }

        if paymentRequested {
            paymentRequested = false
        } else {
            ProviderAwaitingPaymentTracker.shared.clearRequest(for: current.id)
        }
        NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
    }

    private static func isPaymentResolved(_ booking: SimpleBookingDTO) -> Bool {
        booking.statusUpper.contains("PAID") || booking.paidAt != nil
    }

    private static func canShowAwaitingPayment(for booking: SimpleBookingDTO) -> Bool {
        ProviderAwaitingPaymentTracker.isAwaitingEligible(status: booking.statusUpper, paidAt: booking.paidAt)
    }

    private static func mayHavePendingRescheduleRequest(_ booking: SimpleBookingDTO) -> Bool {
        if booking.hasPendingRescheduleRequest { return true }
        guard ProviderBookingStatusDisplay.isEligibleForPendingRescheduleRequest(status: booking.status) else {
            return false
        }
        // List payloads omit reschedule requests; only refetch for pending bookings.
        return booking.statusUpper == "PENDING"
    }

    // MARK: - Setup

    private func setupHierarchy() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .always
        scrollView.backgroundColor = .clear
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        view.addSubview(scrollView)

        spinner.color = Token.accent
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinnerOverlay.addSubview(spinner)
        view.addSubview(spinnerOverlay)
    }

    private func setupConstraints() {
        let frameGuide = scrollView.frameLayoutGuide
        let contentGuide = scrollView.contentLayoutGuide

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: frameGuide.widthAnchor),

            spinnerOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            spinnerOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            spinnerOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            spinnerOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: spinnerOverlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: spinnerOverlay.centerYAnchor),
        ])
    }

    private func buildSections() {
        // Tear down whatever's there (we re-call this on `current` change to refresh).
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        actionButtons.removeAll()

        [
            makeHeader(),
            makeClientBanner(),
            makeOpenConversationSection(),
            makePendingRescheduleSection(),
            makeServicePricingGrid(),
            makeWhenGrid(),
            makeNotesSection(),
            makePaymentSection(),
            makeReferenceFooter(),
            makeActionStack(),
        ].compactMap { $0 }.forEach { contentStack.addArrangedSubview($0) }
    }

    /// Re-render after a successful mutation. We rebuild the whole content stack rather
    /// than mutating individual labels because the *set* of visible buttons depends on
    /// status, and rebuilding is simpler than threading visibility toggles through every
    /// section helper.
    private func applyCurrent() {
        buildSections()
    }

    // MARK: - Sections — Header (status capsule)

    private func makeHeader() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = "Booking Details"
        titleLabel.font = .provider(size: 22, weight: .semibold)
        titleLabel.textColor = Token.primaryText
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let capsule = makeStatusCapsule(forStatus: current.statusUpper)
        capsule.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, capsule])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let row = UIView()
        row.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: row.topAnchor),
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        return row
    }

    /// Builds a pill that color-codes the booking status. The label text is the raw
    /// upper-case status (`PENDING`, `ACCEPTED`, …) — kept in sync with the legacy
    /// SwiftUI badge so the inbox / list / detail screens read identically.
    private func makeStatusCapsule(forStatus status: String) -> UIView {
        let (background, foreground) = statusPalette(for: status)
        let label = UILabel()
        label.text = status.isEmpty ? "—" : ProviderBookingStatusDisplay.title(for: status)
        label.font = .provider(size: 11, weight: .heavy)
        label.textColor = foreground
        label.translatesAutoresizingMaskIntoConstraints = false

        let pill = UIView()
        pill.backgroundColor = background
        pill.layer.cornerRadius = 12
        pill.layer.masksToBounds = true
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -12),
        ])

        statusCapsule = pill
        statusCapsuleLabel = label
        return pill
    }

    /// Color story for the status capsule. Mirrors `ProviderScheduleDashboardView`'s
    /// `statusColor(for:)` so the badge here matches what the user just tapped through.
    private func statusPalette(for status: String) -> (background: UIColor, foreground: UIColor) {
        let s = status.uppercased()
        if s.contains("PAID") || s.contains("COMPLETE") {
            return (Token.statusGreen, .white)
        }
        if s.contains("ACCEPT") {
            return (Token.accent, .white)
        }
        if s.contains("PENDING") {
            return (Token.statusYellow, UIColor(white: 0.1, alpha: 1))
        }
        if s.contains("CANCEL") || s.contains("REJECT") {
            return (Token.destructiveFill, Token.destructiveText)
        }
        return (UIColor.white.withAlphaComponent(0.16), Token.primaryText)
    }

    // MARK: - Sections — Client banner

    private func makeClientBanner() -> UIView {
        let card = makeCard()

        let nameLabel = UILabel()
        nameLabel.text = current.consumerDisplayName
        nameLabel.font = .provider(size: 22, weight: .semibold)
        nameLabel.textColor = Token.primaryText
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            nameLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            nameLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            nameLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        return card
    }

    // MARK: - Sections — Conversation

    private func makeOpenConversationSection() -> UIView? {
        guard showsOpenConversationButton else { return nil }

        let host = UIHostingController(
            rootView: MessageCustomerButtonView(
                background: Color(uiColor: Token.accent.withAlphaComponent(0.22)),
                action: { [weak self] in self?.openConversationTapped() }
            )
        )
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        messageCustomerControlView = host.view
        return host.view
    }

    @objc private func openConversationTapped() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            defer { self.isWorking = false }
            do {
                guard let conversationId = try await self.resolveConversationId() else {
                    self.presentError(
                        NSError(
                            domain: "BookingDetail",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "No conversation is linked to this booking yet."]
                        )
                    )
                    return
                }
                if let onOpenConversation {
                    onOpenConversation(conversationId)
                } else {
                    NotificationCenter.default.post(
                        name: .interaOpenMessagingConversation,
                        object: nil,
                        userInfo: ["conversationId": conversationId]
                    )
                }
            } catch {
                self.presentError(error)
            }
        }
    }

    private func resolveConversationId() async throws -> Int? {
        if let conversationId = current.conversationId {
            return conversationId
        }

        let fresh = try await ProviderBookingsService.fetchBooking(id: current.id)
        if let conversationId = fresh.conversationId {
            current = fresh
            return conversationId
        }

        return try await ProviderMessagesService.conversationId(forBookingId: current.id)
    }

    // MARK: - Sections — Pending schedule change

    private func makePendingRescheduleSection() -> UIView? {
        guard current.statusUpper != "PENDING",
              current.hasPendingRescheduleRequest,
              let request = current.pendingRescheduleRequest
        else { return nil }

        let header = makeSectionHeader(text: "Schedule Change")
        let banner = ProviderPendingRescheduleBannerView()
        banner.configure(booking: current, request: request)
        banner.setActionsEnabled(!isWorking)
        banner.onApprove = { [weak self] in self?.approveRescheduleTapped() }
        banner.onDecline = { [weak self] in self?.declineRescheduleTapped() }

        let wrap = UIStackView(arrangedSubviews: [header, banner])
        wrap.axis = .vertical
        wrap.spacing = 8
        return wrap
    }

    // MARK: - Sections — Service & pricing

    private func makeServicePricingGrid() -> UIView {
        let header = makeSectionHeader(text: "Service")
        let serviceCard = makeVerticalMetaCard(title: "Type", value: current.serviceDisplayName)
        let priceCard = makeVerticalMetaCard(title: "Price", value: formattedPrice() ?? "—")

        let grid = UIStackView(arrangedSubviews: [serviceCard, priceCard])
        grid.axis = .horizontal
        grid.distribution = .fillEqually
        grid.spacing = 12

        let wrap = UIStackView(arrangedSubviews: [header, grid])
        wrap.axis = .vertical
        wrap.spacing = 8
        return wrap
    }

    // MARK: - Sections — When grid

    private func makeWhenGrid() -> UIView {
        let header = makeSectionHeader(text: "When")
        let dateCard = makeVerticalMetaCard(title: "Date", value: formattedDate())
        let timeCard = makeVerticalMetaCard(title: "Time", value: formattedTime())

        let grid = UIStackView(arrangedSubviews: [dateCard, timeCard])
        grid.axis = .horizontal
        grid.distribution = .fillEqually
        grid.spacing = 12

        let wrap = UIStackView(arrangedSubviews: [header, grid])
        wrap.axis = .vertical
        wrap.spacing = 8
        return wrap
    }

    // MARK: - Sections — Notes (optional)

    private func makeNotesSection() -> UIView? {
        let notes = (current.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return nil }
        let header = makeSectionHeader(text: "Notes")
        let card = makeCard()
        let label = UILabel()
        label.text = notes
        label.font = .provider(size: 15, weight: .regular)
        label.textColor = Token.primaryText
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        let wrap = UIStackView(arrangedSubviews: [header, card])
        wrap.axis = .vertical
        wrap.spacing = 8
        return wrap
    }

    // MARK: - Sections — Payment (paid bookings)

    private func makePaymentSection() -> UIView? {
        guard current.statusUpper == "PAID" else { return nil }

        let header = makeSectionHeader(text: "Payment")
        let card = makeCard()
        card.backgroundColor = Token.accent.withAlphaComponent(0.12)
        card.layer.borderColor = Token.accent.withAlphaComponent(0.35).cgColor

        let totalTitle = UILabel()
        totalTitle.text = "Total Paid"
        totalTitle.font = .provider(size: 15, weight: .medium)
        totalTitle.textColor = Token.primaryText
        totalTitle.translatesAutoresizingMaskIntoConstraints = false

        let totalValue = UILabel()
        totalValue.text = formattedTotalPaid()
        totalValue.font = .provider(size: 18, weight: .bold)
        totalValue.textColor = Token.accent
        totalValue.translatesAutoresizingMaskIntoConstraints = false
        totalValue.setContentHuggingPriority(.required, for: .horizontal)

        let totalRow = UIView()
        totalRow.translatesAutoresizingMaskIntoConstraints = false
        totalRow.addSubview(totalTitle)
        totalRow.addSubview(totalValue)

        let tipTitle = UILabel()
        tipTitle.text = "Tip"
        tipTitle.font = .provider(size: 14, weight: .medium)
        tipTitle.textColor = Token.secondaryText
        tipTitle.translatesAutoresizingMaskIntoConstraints = false

        let tipValue = UILabel()
        if let cents = current.tipAmountCents, cents > 0 {
            tipValue.text = formattedCurrency(cents: cents)
            tipValue.textColor = Token.statusGreen
        } else {
            tipValue.text = "No tip"
            tipValue.textColor = Token.secondaryText
        }
        tipValue.font = .provider(size: 15, weight: .semibold)
        tipValue.translatesAutoresizingMaskIntoConstraints = false
        tipValue.setContentHuggingPriority(.required, for: .horizontal)

        let tipRow = UIView()
        tipRow.translatesAutoresizingMaskIntoConstraints = false
        tipRow.addSubview(tipTitle)
        tipRow.addSubview(tipValue)

        let divider = UIView()
        divider.backgroundColor = Token.cardBorder
        divider.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [totalRow, divider, tipRow])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            totalTitle.leadingAnchor.constraint(equalTo: totalRow.leadingAnchor),
            totalTitle.centerYAnchor.constraint(equalTo: totalRow.centerYAnchor),
            totalValue.trailingAnchor.constraint(equalTo: totalRow.trailingAnchor),
            totalValue.centerYAnchor.constraint(equalTo: totalRow.centerYAnchor),
            totalValue.leadingAnchor.constraint(greaterThanOrEqualTo: totalTitle.trailingAnchor, constant: 12),
            totalRow.heightAnchor.constraint(equalToConstant: 28),

            divider.heightAnchor.constraint(equalToConstant: 1),

            tipTitle.leadingAnchor.constraint(equalTo: tipRow.leadingAnchor),
            tipTitle.centerYAnchor.constraint(equalTo: tipRow.centerYAnchor),
            tipValue.trailingAnchor.constraint(equalTo: tipRow.trailingAnchor),
            tipValue.centerYAnchor.constraint(equalTo: tipRow.centerYAnchor),
            tipValue.leadingAnchor.constraint(greaterThanOrEqualTo: tipTitle.trailingAnchor, constant: 12),
            tipRow.heightAnchor.constraint(equalToConstant: 24),

            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        let wrap = UIStackView(arrangedSubviews: [header, card])
        wrap.axis = .vertical
        wrap.spacing = 8
        return wrap
    }

    // MARK: - Section helpers

    /// Stacked title → value card. Used in the Service and When grids where two columns
    /// share a row and need to be narrow.
    private func makeVerticalMetaCard(title: String, value: String) -> UIView {
        let card = makeCard()

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .provider(size: 11, weight: .semibold)
        titleLabel.textColor = Token.secondaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .provider(size: 15, weight: .semibold)
        valueLabel.textColor = Token.primaryText
        valueLabel.numberOfLines = 1
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(titleLabel)
        card.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            valueLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
            valueLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        return card
    }

    private func makeSectionHeader(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .provider(size: 12, weight: .semibold)
        label.textColor = Token.secondaryText
        return label
    }

    // MARK: - Sections — Reference footer

    private func makeReferenceFooter() -> UIView {
        let caption = UILabel()
        caption.text = "Booking Reference"
        caption.font = .provider(size: 12, weight: .medium)
        caption.textColor = Token.secondaryText
        caption.textAlignment = .center

        let code = UILabel()
        code.text = bookingReferenceCode()
        code.font = .provider(size: 16, weight: .semibold)
        code.textColor = Token.primaryText
        code.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [caption, code])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center
        return stack
    }

    // MARK: - Sections — Action stack (status-driven)

    /// Builds the visible action set for `current.statusUpper`. Returns `nil` for
    /// statuses that have no actions (e.g. CANCELLED, REJECTED) so the contentStack
    /// doesn't get a dangling empty section.
    ///
    /// Layout:
    ///   - Zero or more **full-width** primary-style buttons stacked vertically at the
    ///     top. This is how the "Awaiting Payment" status pill + "Undo Completion"
    ///     follow-up render — two full-width affordances stacked.
    ///   - Then any secondary + destructive buttons paired into two-per-row split rows
    ///     (`Reschedule`, then `Cancel` for accepted bookings).
    private func makeActionStack() -> UIView? {
        let status = current.statusUpper

        var fullWidthButtons: [UIButton] = []
        var secondaryButtons: [UIButton] = []
        var destructiveButtons: [UIButton] = []

        // "Awaiting Payment" is a *cross-status* UI mode. The backend stamps
        // `status = COMPLETED` the moment `request-payment` succeeds (there is no
        // dedicated AWAITING_PAYMENT status). On first render right after the tap the
        // optimistic local status may still read ACCEPTED for a tick; on re-entry from
        // the dashboard banner it reads COMPLETED. Both should look identical to the
        // barber: an inert pill + an undo affordance. Anything else (PENDING, PAID,
        // CANCELLED, ...) falls through to the normal status-driven branches below.
        let isAwaitingPayment = paymentRequested && (status == "ACCEPTED" || status == "COMPLETED")

        if isAwaitingPayment {
            // Inert status pill — looks button-shaped to keep the visual hierarchy
            // consistent with the page-default "Request Payment" but is deliberately
            // un-tappable (no target, `isUserInteractionEnabled = false`, dimmed
            // glass fill) so the barber understands the request is in flight. Not
            // added to `actionButtons` so the `isWorking` toggle can't accidentally
            // re-enable it.
            fullWidthButtons.append(
                makeInertStatusButton(
                    title: "Awaiting Payment",
                    icon: "hourglass"
                )
            )
            // Real server-side undo: the backend is already in COMPLETED, so this
            // routes through `undoCompleteTapped` which calls
            // `ProviderBookingsService.undoComplete` to flip the server back to
            // ACCEPTED. The didSet on `paymentRequested = false` clears the tracker
            // and the next `applyCurrent()` renders the regular "Request Payment"
            // CTA again.
            fullWidthButtons.append(
                makePrimaryActionButton(
                    title: "Undo Completion",
                    icon: "arrow.uturn.backward",
                    background: Token.accent,
                    foreground: .white,
                    action: #selector(undoCompleteTapped)
                )
            )
            // Intentionally no secondary actions in this state. The booking is server-
            // side COMPLETED with a pending payment request — Reschedule / Mark
            // Complete / Cancel either make no sense or would race the payment flow.
            // The barber undoes first if they need any of those.
        } else if status == "PENDING" {
            return makePendingActionStack()
        } else if status == "ACCEPTED" {
            fullWidthButtons.append(
                makePrimaryActionButton(
                    title: "Request Payment",
                    background: Token.accent,
                    foreground: .white,
                    action: #selector(requestPaymentTapped)
                )
            )
        } else if status == "COMPLETED" {
            fullWidthButtons.append(
                makePrimaryActionButton(
                    title: "Undo Completion",
                    icon: "arrow.uturn.backward",
                    background: Token.accent,
                    foreground: .white,
                    action: #selector(undoCompleteTapped)
                )
            )
        }

        // Secondary block: accepted bookings get Reschedule and Cancel.
        if !isAwaitingPayment, status == "ACCEPTED" {
            secondaryButtons.append(
                makeSecondaryActionButton(
                    title: "Reschedule",
                    background: Token.statusYellow,
                    foreground: UIColor(white: 0.1, alpha: 1),
                    action: #selector(rescheduleTapped)
                )
            )
            if status == "ACCEPTED" {
                destructiveButtons.append(
                    makeSecondaryActionButton(
                        title: "Cancel",
                        background: Token.cancelButtonFill,
                        foreground: Token.cancelButtonText,
                        action: #selector(cancelTapped)
                    )
                )
            }
        }

        guard !fullWidthButtons.isEmpty || !secondaryButtons.isEmpty || !destructiveButtons.isEmpty else {
            return nil
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        for button in fullWidthButtons {
            stack.addArrangedSubview(button)
        }

        // Pair up secondary actions two-per-row. With an odd count, the last takes a
        // full row.
        let pairables = secondaryButtons + destructiveButtons
        var index = 0
        while index < pairables.count {
            if index + 1 < pairables.count {
                let row = UIStackView(arrangedSubviews: [pairables[index], pairables[index + 1]])
                row.axis = .horizontal
                row.distribution = .fillEqually
                row.spacing = 12
                stack.addArrangedSubview(row)
                index += 2
            } else {
                stack.addArrangedSubview(pairables[index])
                index += 1
            }
        }

        actionsContainer = stack
        return stack
    }

    /// Compact, centered pill actions for pending booking requests.
    private func makePendingActionStack() -> UIView {
        let accept = makePrimaryActionButton(
            title: "Accept",
            icon: "checkmark.circle.fill",
            background: Token.statusGreen,
            foreground: .white,
            action: #selector(acceptTapped),
            compact: true
        )
        let reschedule = makeSecondaryActionButton(
            title: "Reschedule",
            icon: "calendar.badge.clock",
            background: Token.statusYellow,
            foreground: UIColor(white: 0.1, alpha: 1),
            action: #selector(rescheduleTapped),
            compact: true
        )
        let decline = makeSecondaryActionButton(
            title: "Decline",
            icon: "xmark",
            background: Token.destructiveFill,
            foreground: Token.destructiveText,
            action: #selector(declineTapped),
            compact: true
        )

        let secondaryRow = UIStackView(arrangedSubviews: [reschedule, decline])
        secondaryRow.axis = .horizontal
        secondaryRow.spacing = 12
        secondaryRow.alignment = .center
        secondaryRow.distribution = .equalSpacing

        let stack = UIStackView(arrangedSubviews: [accept, secondaryRow])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center

        actionsContainer = stack
        return stack
    }

    private static func applyPlatformButtonTitleFont(
        to config: inout UIButton.Configuration,
        textStyle: UIFont.TextStyle = .body
    ) {
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = UIFont.providerPreferred(forTextStyle: textStyle, weight: .semibold)
            return out
        }
    }

    private func makePrimaryActionButton(
        title: String,
        icon: String? = nil,
        background: UIColor,
        foreground: UIColor,
        action: Selector,
        compact: Bool = false
    ) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        if let icon {
            config.image = UIImage(
                systemName: icon,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: compact ? 15 : 16, weight: .semibold)
            )
            config.imagePadding = 8
        }
        config.cornerStyle = .capsule
        config.baseBackgroundColor = background
        config.baseForegroundColor = foreground
        if compact {
            config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 26, bottom: 18, trailing: 26)
        } else {
            config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        }
        Self.applyPlatformButtonTitleFont(to: &config, textStyle: compact ? .subheadline : .body)

        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: compact ? 58 : 56).isActive = true
        if compact {
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        actionButtons.append(button)
        return button
    }

    private func makeSecondaryActionButton(
        title: String,
        icon: String? = nil,
        background: UIColor,
        foreground: UIColor,
        action: Selector,
        compact: Bool = false
    ) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        if let icon {
            config.image = UIImage(
                systemName: icon,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            )
            config.imagePadding = 6
        }
        config.cornerStyle = .capsule
        config.baseBackgroundColor = background
        config.baseForegroundColor = foreground
        if compact {
            config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 26, bottom: 18, trailing: 26)
        } else {
            config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        }
        Self.applyPlatformButtonTitleFont(to: &config, textStyle: compact ? .subheadline : .body)

        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: compact ? 58 : 50).isActive = true
        if compact {
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        actionButtons.append(button)
        return button
    }

    /// Renders a primary-shaped, *non-interactive* "status pill" — same footprint as a
    /// primary action button (full-width, 52pt min height, capsule shape) but
    /// dimmed and disabled so the user reads it as a state indicator rather than a CTA.
    ///
    /// Deliberately **not** added to `actionButtons`, so the `isWorking` `didSet`
    /// (which re-enables every tracked action button) cannot accidentally make this
    /// tappable again. Used for the "Awaiting Payment" affordance after a successful
    /// `requestPayment` call.
    private func makeInertStatusButton(title: String, icon: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(
            systemName: icon,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        config.imagePadding = 8
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.10)
        config.baseForegroundColor = Token.secondaryText
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        Self.applyPlatformButtonTitleFont(to: &config)

        let button = UIButton(configuration: config)
        button.isUserInteractionEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        // NOTE: intentionally *not* appended to `actionButtons` — see method doc.
        return button
    }

    // MARK: - Card factory

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = Token.cardSurface
        card.layer.cornerRadius = Token.cardCornerRadius
        card.layer.masksToBounds = true
        card.layer.borderColor = Token.cardBorder.cgColor
        card.layer.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    // MARK: - Formatting

    private func formattedPrice() -> String? {
        guard let cents = current.priceUsdCents else { return nil }
        return formattedCurrency(cents: cents)
    }

    private func formattedTotalPaid() -> String {
        if let cents = current.totalPaidCents {
            return formattedCurrency(cents: cents)
        }
        if let cents = current.priceUsdCents {
            return formattedCurrency(cents: cents)
        }
        return "—"
    }

    private func formattedCurrency(cents: Int) -> String {
        (Double(cents) / 100.0).formatted(.currency(code: "USD"))
    }

    private func formattedDate() -> String {
        guard let time = current.providerEffectiveScheduledTime else { return "TBD" }
        return time.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func formattedTime() -> String {
        guard let time = current.providerEffectiveScheduledTime else { return "TBD" }
        return time.formatted(date: .omitted, time: .shortened)
    }

    /// Short 8-character uppercase tag derived from the booking UUID for the footer.
    /// Matches the format the web dashboard's "Booking Reference" stamp uses.
    private func bookingReferenceCode() -> String {
        let stripped = current.id.replacingOccurrences(of: "-", with: "")
        return String(stripped.prefix(8)).uppercased()
    }

    // MARK: - Action Handlers

    @objc private func acceptTapped() {
        if current.statusUpper == "PENDING" {
            guard let barberTableId else {
                presentError(NSError(
                    domain: "BookingDetail",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Barber profile not loaded. Pull to refresh and try again."]
                ))
                return
            }
            run(optimisticStatus: "ACCEPTED") {
                try await ProviderBookingRequestsService.acceptApplyingConsumerSchedule(
                    bookingId: self.current.id,
                    barberTableId: barberTableId,
                    booking: self.current,
                    message: nil
                )
            } onSuccess: {
                NotificationCenter.default.post(name: .providerRequestsListShouldRefresh, object: nil)
            }
            return
        }

        run(optimisticStatus: "ACCEPTED") {
            try await ProviderBookingsService.updateBookingStatus(id: self.current.id, status: "ACCEPTED")
        }
    }

    @objc private func declineTapped() {
        confirm(
            title: "Decline this booking?",
            message: "The customer will be notified that you can't take this booking.",
            confirmTitle: "Decline",
            destructive: true
        ) { [weak self] in
            guard let self else { return }
            if self.current.statusUpper == "PENDING" {
                guard let barberTableId = self.barberTableId else {
                    self.presentError(NSError(
                        domain: "BookingDetail",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Barber profile not loaded. Pull to refresh and try again."]
                    ))
                    return
                }
                self.run(optimisticStatus: "REJECTED") {
                    try await ProviderBookingRequestsService.reject(
                        bookingId: self.current.id,
                        barberTableId: barberTableId,
                        reason: "Declined by provider"
                    )
                } onSuccess: {
                    NotificationCenter.default.post(name: .providerRequestsListShouldRefresh, object: nil)
                }
                return
            }

            self.run(optimisticStatus: "REJECTED") {
                try await ProviderBookingsService.updateBookingStatus(id: self.current.id, status: "REJECTED")
            }
        }
    }

    @objc private func markCompleteTapped() {
        run(optimisticStatus: "COMPLETED") {
            try await ProviderBookingsService.markComplete(id: self.current.id)
        }
    }

    @objc private func undoCompleteTapped() {
        // Clears any stale "Awaiting Payment" UI as part of returning the booking to
        // its pre-completion state — keeps the in-page UI consistent if the user goes
        // COMPLETED → undo while a payment request was previously fired.
        paymentRequested = false
        run(optimisticStatus: "ACCEPTED") {
            try await ProviderBookingsService.undoComplete(id: self.current.id)
        }
    }

    @objc private func requestPaymentTapped() {
        // The backend transitions `status` ACCEPTED → COMPLETED inside the same call
        // (it also stamps `payment_requested_at`). Mirror that locally so `current`
        // and the server agree once the round-trip lands, and so the action stack's
        // `isAwaitingPayment = paymentRequested && status ∈ {ACCEPTED, COMPLETED}`
        // short-circuit holds even after a subsequent parent-driven refresh swaps in
        // the server-fresh DTO. Order matters: flip `paymentRequested` first so the
        // very first rebuild already shows the "Awaiting Payment" pill instead of
        // briefly rendering the plain `COMPLETED` "Undo Completion" branch.
        run(optimisticStatus: nil) {
            try await ProviderBookingsService.requestPayment(id: self.current.id)
        } onSuccess: { [weak self] in
            guard let self else { return }
            self.paymentRequested = true
            self.current = self.with(status: "COMPLETED").updatingPaymentRequestedAt(Date())
        }
    }

    @objc private func rescheduleTapped() {
        presentReschedulePicker()
    }

    @objc private func cancelTapped() {
        presentCancelReasonPrompt()
    }

    @objc private func approveRescheduleTapped() {
        runAndRefreshBooking {
            try await ProviderBookingsService.approveRescheduleRequest(bookingId: self.current.id)
        }
    }

    @objc private func declineRescheduleTapped() {
        confirm(
            title: "Decline schedule change?",
            message: "The appointment will stay at the current date and time.",
            confirmTitle: "Decline",
            destructive: true
        ) { [weak self] in
            guard let self else { return }
            self.runAndRefreshBooking {
                try await ProviderBookingsService.rejectRescheduleRequest(bookingId: self.current.id)
            }
        }
    }

    // MARK: - Reschedule sheet (native UIKit)

    private func presentReschedulePicker() {
        guard let barberId = barberTableId ?? current.barberId,
              !barberId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            presentError(NSError(
                domain: "BookingDetail",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Barber profile is required to reschedule this booking."]
            ))
            return
        }

        let sheet = ProviderBookingRescheduleSheetView(
            booking: current,
            barberId: barberId,
            onSave: { [weak self] date in
                self?.dismiss(animated: true) {
                    self?.performReschedule(to: date)
                }
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            }
        )

        let host = UIHostingController(rootView: sheet)
        host.modalPresentationStyle = .formSheet
        present(host, animated: true)
    }

    private func performReschedule(to date: Date) {
        run(optimisticStatus: nil) {
            try await ProviderBookingsService.reschedule(
                id: self.current.id,
                scheduledTimeISO: date.campusCutsISO8601String(),
                location: nil,
                notes: nil
            )
        } onSuccess: { [weak self] in
            self?.applyOptimisticScheduledTime(date)
        }
    }

    // MARK: - Cancel sheet (native UIKit)

    private func presentCancelReasonPrompt() {
        let alert = UIAlertController(
            title: "Cancel booking?",
            message: "This will notify the customer. You can leave an optional reason.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Reason (optional)"
        }
        alert.addAction(UIAlertAction(title: "Keep Booking", style: .cancel))
        alert.addAction(UIAlertAction(title: "Cancel Booking", style: .destructive) { [weak self] _ in
            guard let self else { return }
            let raw = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reason = raw.isEmpty ? nil : raw
            self.run(optimisticStatus: "CANCELLED") {
                try await ProviderBookingsService.cancelBooking(id: self.current.id, reason: reason)
            }
        })
        present(alert, animated: true)
    }

    @objc private func dismissPresentedSheet() {
        dismiss(animated: true)
    }

    // MARK: - Mutation runner

    /// Refreshes `current` from the server after a mutation that may change schedule or payment fields.
    private func runAndRefreshBooking(
        _ block: @escaping () async throws -> Void,
        onSuccess: (() -> Void)? = nil
    ) {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            do {
                try await block()
                self.current = try await ProviderBookingsService.fetchBooking(id: self.current.id)
                onSuccess?()
                NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
                await self.onChanged()
            } catch {
                self.presentError(error)
            }
            self.isWorking = false
        }
    }

    /// Single chokepoint for every booking mutation. Toggles `isWorking`, fires the
    /// network call, optionally optimistically advances the local `current.status` so
    /// the UI flips immediately (the parent `onChanged()` will re-sync from the server
    /// anyway), and surfaces errors via an alert.
    private func run(
        optimisticStatus: String?,
        _ block: @escaping () async throws -> Void,
        onSuccess: (() -> Void)? = nil
    ) {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            do {
                try await block()
                if let optimisticStatus {
                    self.current = self.with(status: optimisticStatus)
                }
                onSuccess?()
                NotificationCenter.default.post(name: .providerBookingsChanged, object: nil)
                await self.onChanged()
            } catch {
                self.presentError(error)
            }
            self.isWorking = false
        }
    }

    /// Synthesizes a new `SimpleBookingDTO` with the given status applied to `current`.
    /// Used by the optimistic-update path so we don't have to wait for the server round
    /// trip + parent refresh to flip the badge / refresh the action set.
    private func with(status newStatus: String) -> SimpleBookingDTO {
        let clearsPendingReschedule = !ProviderBookingStatusDisplay.isEligibleForPendingRescheduleRequest(status: newStatus)
        return SimpleBookingDTO(
            id: current.id,
            consumerId: current.consumerId,
            barberId: current.barberId,
            serviceType: current.serviceType,
            priceUsdCents: current.priceUsdCents,
            scheduledTime: current.scheduledTime,
            status: newStatus,
            location: current.location,
            notes: current.notes,
            serviceName: current.serviceName,
            review: current.review,
            paidAt: current.paidAt,
            paymentRequestedAt: current.paymentRequestedAt,
            tipAmountCents: current.tipAmountCents,
            totalPaidCents: current.totalPaidCents,
            paymentMethod: current.paymentMethod,
            pendingRescheduleRequest: clearsPendingReschedule ? nil : current.pendingRescheduleRequest,
            consumer: current.consumer,
            consumerName: current.consumerName,
            barber: current.barber,
            barberName: current.barberName,
            conversationId: current.conversationId
        )
    }

    /// Same idea but for the rescheduled time — we mutate locally so the WHEN cards
    /// flip before the parent refresh lands.
    private func applyOptimisticScheduledTime(_ date: Date) {
        let clearPending = current.statusUpper == "PENDING" && current.hasPendingRescheduleRequest
        current = current.updatingScheduledTime(date, clearPendingReschedule: clearPending)
    }

    // MARK: - Misc helpers

    private func confirm(
        title: String,
        message: String,
        confirmTitle: String,
        destructive: Bool,
        action: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep", style: .cancel))
        alert.addAction(UIAlertAction(title: confirmTitle, style: destructive ? .destructive : .default) { _ in
            action()
        })
        present(alert, animated: true)
    }

    private func presentError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let alert = UIAlertController(title: "Something went wrong", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentToast(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - SwiftUI bridge

/// Lets the UIKit `BookingDetailViewController` be used as the destination of a SwiftUI
/// `.navigationDestination(for: SimpleBookingDTO.self)`. The dashboard shell and the
/// bookings list both rely on that destination registration, so wrapping rather than
/// rewriting them keeps blast radius small.
struct BookingDetailHost: UIViewControllerRepresentable {
    @Environment(ProviderSession.self) private var session
    let booking: SimpleBookingDTO
    let onChanged: () async -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let detail = BookingDetailViewController(
            booking: booking,
            barberTableId: session.barberProfile?.id,
            onOpenConversation: { conversationId in
                NotificationCenter.default.post(
                    name: .interaOpenMessagingConversation,
                    object: nil,
                    userInfo: ["conversationId": conversationId]
                )
            },
            onChanged: onChanged
        )
        #if os(iOS)
        return ProviderOpaqueScreenContainerViewController(
            content: detail,
            fillColor: InteraLavaMidnight.uiColor
        )
        #else
        return detail
        #endif
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let detail: BookingDetailViewController?
        #if os(iOS)
        if let container = uiViewController as? ProviderOpaqueScreenContainerViewController {
            detail = container.children.first { $0 is BookingDetailViewController } as? BookingDetailViewController
        } else {
            detail = uiViewController as? BookingDetailViewController
        }
        #else
        detail = uiViewController as? BookingDetailViewController
        #endif
        guard detail != nil else { return }
    }
}

/// Booking detail screen — title is rendered in-page; shell pushes show a leading exit chevron.
struct BookingDetailScreen: View {
    let booking: SimpleBookingDTO
    var showsShellBackButton: Bool = false
    let onChanged: () async -> Void

    var body: some View {
        BookingDetailHost(booking: booking, onChanged: onChanged)
            .navigationBarBackButtonHidden(true)
            .toolbar(showsShellBackButton ? .visible : .hidden, for: .navigationBar)
    }
}

private struct MessageCustomerButtonView: View {
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "message")
                    .font(.provider(.body, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                ProviderBlackOutlinedText("Message Customer")
                    .font(.provider(.body, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
