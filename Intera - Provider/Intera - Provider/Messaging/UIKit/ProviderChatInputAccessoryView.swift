import UIKit

// MARK: - Composer (formerly "input accessory")

protocol ProviderChatInputAccessoryViewDelegate: AnyObject {
    func chatInputAccessoryViewDidTapSend(_ view: ProviderChatInputAccessoryView, text: String)
    func chatInputAccessoryViewDidTapAttachment(_ view: ProviderChatInputAccessoryView)
}

/// The chat composer bar — message text field, attachment shortcut, and send button.
///
/// **History note (kept here on purpose because the bug it fixes recurred for a while):**
///
/// This view used to be installed via `UIResponder.inputAccessoryView` on the chat VC.
/// That's the textbook UIKit pattern and works perfectly in a stock `UINavigationController`
/// app — UIKit's keyboard-host window sizes the accessory to full screen width on attach,
/// and `autoresizingMask = [.flexibleHeight, .flexibleWidth]` keeps it tracking through
/// rotation / split-view changes.
///
/// It does **not** work reliably for this app, because the chat VC is hosted inside a
/// SwiftUI `NavigationStack` (`ProviderMessagesInboxUIKitHost` is a `UIViewControllerRepresentable`).
/// SwiftUI re-parents the keyboard-host window across pushes, modal sheet presentations,
/// and interactive-pop transitions, and the bar's frame gets snapshotted at a transient
/// width and never recovers — even with both flexible-axis flags set, even with manual
/// `resign → becomeFirstResponder` recovery, even after switching from sheet presentation
/// to push navigation. The symptom is the composer collapsing to its minimum width (the
/// stack getting squeezed down to attachment-button + send-button with the textView pinched
/// to ~0pt) whenever the user returns to the chat from any pushed/presented screen.
///
/// The fix is to abandon `inputAccessoryView` entirely and make the composer a *regular
/// subview* of the chat VC's view. The VC pins us to its leading/trailing edges (so the
/// width is literally `view.bounds.width` — impossible to collapse) and pins our bottom
/// to `view.keyboardLayoutGuide.topAnchor` with a soft pin to the safe area when the
/// keyboard is down. iOS 15+ `keyboardLayoutGuide` handles all keyboard animation,
/// interactive dismissal, and orientation changes for us. This is the same pattern Apple's
/// own samples have used since iOS 15 and is what modern messaging apps (Messages,
/// WhatsApp, Telegram) ship.
///
/// The type name (`ProviderChatInputAccessoryView`) is retained for blast-radius reasons —
/// changing it would touch the inbox bridge and a few other call sites without any user
/// benefit — but mentally treat this as `ProviderChatComposerBar`.
final class ProviderChatInputAccessoryView: UIView {
    weak var delegate: ProviderChatInputAccessoryViewDelegate?

    private let attachmentButton = UIButton(type: .system)
    private let textView = UITextView()
    private let sendButton = UIButton(type: .system)
    private let separator = UIView()
    private let stack = UIStackView()

    private var heightConstraint: NSLayoutConstraint?
    private var composerContentHeight = ProviderChatDesignTokens.Metrics.inputBarMinContentHeight

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Auto-layout managed; the chat VC owns our width/leading/trailing/bottom
        // constraints. No autoresizing — that path was the source of the historical
        // collapse bug documented in the type doc.
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        setupConstraints()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: composerContentHeight)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyComposerFieldChrome()
        textView.typingAttributes = ProviderChatDesignTokens.composerTypingAttributes()
    }

    private func applyComposerFieldChrome() {
        textView.backgroundColor = ProviderChatDesignTokens.Color.composerFieldBackground
        textView.layer.cornerRadius = 12
        textView.layer.borderWidth = 1
        textView.layer.borderColor = ProviderChatDesignTokens.Color.composerFieldBorder.cgColor
    }

    // MARK: - Public API

    var draftText: String {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearDraft() {
        textView.text = ""
        recomputeContentHeight()
    }

    func restoreDraft(_ text: String) {
        textView.text = text
        textViewDidChange(textView)
    }

    /// Toggles the bar's "send in flight" state — disables inputs and dims the affordances
    /// while a network round-trip is happening so the user can't double-send.
    func setSending(_ sending: Bool) {
        attachmentButton.isEnabled = !sending
        attachmentButton.alpha = sending ? 0.45 : 1
        sendButton.isEnabled = !sending && !draftText.isEmpty
        sendButton.alpha = sendButton.isEnabled ? 1 : 0.45
        textView.isEditable = !sending
    }

    /// Convenience: focus the text field. The chat VC calls this when an external trigger
    /// (e.g. tapping a "Reply" affordance on a row) should pop the keyboard.
    @discardableResult
    func focusForReply() -> Bool {
        textView.becomeFirstResponder()
    }

    /// Resigns composer focus so UIKit animates keyboard dismissal in sync with `keyboardLayoutGuide`.
    func resignComposerFocus() {
        textView.resignFirstResponder()
    }

    // MARK: - UI Setup

    private func setupUI() {
        backgroundColor = ProviderChatDesignTokens.Color.screenBackground

        separator.backgroundColor = ProviderChatDesignTokens.Color.separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        attachmentButton.translatesAutoresizingMaskIntoConstraints = false
        let plusConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        attachmentButton.setImage(
            UIImage(systemName: "plus.circle.fill", withConfiguration: plusConfig),
            for: .normal
        )
        attachmentButton.tintColor = ProviderChatDesignTokens.Color.providerOlive
        attachmentButton.addTarget(self, action: #selector(attachmentTapped), for: .touchUpInside)
        attachmentButton.setContentHuggingPriority(.required, for: .horizontal)
        attachmentButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        textView.font = ProviderChatDesignTokens.Font.body(15)
        textView.textColor = ProviderChatDesignTokens.Color.lavaShellCream
        textView.tintColor = ProviderChatDesignTokens.Color.providerOlive
        textView.typingAttributes = ProviderChatDesignTokens.composerTypingAttributes()
        textView.textContainer.lineFragmentPadding = 0
        applyComposerFieldChrome()
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        // Yield horizontal space to the buttons — the textView is the elastic element of
        // the stack so it can stretch to fill whatever room the buttons don't claim.
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        sendButton.setTitle("Send", for: .normal)
        sendButton.titleLabel?.font = ProviderChatDesignTokens.Font.heading(15)
        sendButton.setTitleColor(ProviderChatDesignTokens.Color.providerOlive, for: .normal)
        sendButton.setTitleColor(ProviderChatDesignTokens.Color.lavaShellCreamSecondary, for: .disabled)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.isEnabled = false
        sendButton.alpha = 0.45
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.addArrangedSubview(attachmentButton)
        stack.addArrangedSubview(textView)
        stack.addArrangedSubview(sendButton)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(separator)
        addSubview(stack)
    }

    // MARK: - Auto Layout Constraints

    private func setupConstraints() {
        // Height is intrinsic-driven via `composerContentHeight`; we publish it as an
        // explicit equality constraint so the chat VC's `tableView.bottom = composer.top`
        // pin gives the table a precise growth animation when the composer expands for
        // multi-line typing.
        let h = heightAnchor.constraint(equalToConstant: composerContentHeight)
        h.priority = .required
        h.isActive = true
        heightConstraint = h

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            stack.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ProviderChatDesignTokens.Metrics.horizontalPadding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ProviderChatDesignTokens.Metrics.horizontalPadding),

            attachmentButton.widthAnchor.constraint(equalToConstant: ProviderChatDesignTokens.Metrics.composerAttachmentSize),
            attachmentButton.heightAnchor.constraint(equalToConstant: ProviderChatDesignTokens.Metrics.composerAttachmentSize),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
    }

    private func recomputeContentHeight() {
        // `bounds.width` is reliable here because we're a regular subview, not an input
        // accessory — by the time text is being entered, our layout pass has already run
        // and `bounds` is correct.
        let width = max(textView.bounds.width, 120)
        let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let metrics = ProviderChatDesignTokens.Metrics.self
        let newHeight = min(
            max(metrics.inputBarMinContentHeight, size.height + 24),
            metrics.inputBarMaxContentHeight
        )
        guard abs(newHeight - composerContentHeight) > 0.5 else { return }
        composerContentHeight = newHeight
        heightConstraint?.constant = newHeight
        invalidateIntrinsicContentSize()
    }

    // MARK: - Action Handlers

    @objc private func sendTapped() {
        let text = draftText
        guard !text.isEmpty else { return }
        delegate?.chatInputAccessoryViewDidTapSend(self, text: text)
    }

    @objc private func attachmentTapped() {
        delegate?.chatInputAccessoryViewDidTapAttachment(self)
    }
}

// MARK: - UITextViewDelegate

extension ProviderChatInputAccessoryView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        textView.typingAttributes = ProviderChatDesignTokens.composerTypingAttributes()
        let hasText = !draftText.isEmpty
        sendButton.isEnabled = hasText
        sendButton.alpha = hasText ? 1 : 0.45
        recomputeContentHeight()
    }
}
