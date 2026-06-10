import CampusCutsModule
import UIKit

// MARK: - Message bubble cell

final class ProviderChatMessageCell: UITableViewCell {
    static let reuseIdentifier = "ProviderChatMessageCell"

    private let bubbleView = UIView()
    private let bubbleContentStack = UIStackView()
    private let messageLabel = UILabel()
    private let messageImageView = UIImageView()
    private let timestampLabel = UILabel()
    private let stack = UIStackView()

    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    private var imageLoadTask: URLSessionDataTask?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        setupConstraints()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageLoadTask?.cancel()
        imageLoadTask = nil
        messageImageView.image = nil
        messageImageView.isHidden = true
        messageLabel.isHidden = false
        messageLabel.text = nil
    }

    // MARK: - UI Setup

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        bubbleView.layer.cornerRadius = ProviderChatDesignTokens.Metrics.bubbleCornerRadius
        bubbleView.translatesAutoresizingMaskIntoConstraints = false

        bubbleContentStack.axis = .vertical
        bubbleContentStack.spacing = 4
        bubbleContentStack.alignment = .fill
        bubbleContentStack.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.font = ProviderChatDesignTokens.Font.body(15)
        messageLabel.numberOfLines = 0

        messageImageView.contentMode = .scaleAspectFill
        messageImageView.clipsToBounds = true
        messageImageView.layer.cornerRadius = 12
        messageImageView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        messageImageView.isHidden = true

        bubbleContentStack.addArrangedSubview(messageLabel)
        bubbleContentStack.addArrangedSubview(messageImageView)
        bubbleView.addSubview(bubbleContentStack)

        timestampLabel.font = ProviderChatDesignTokens.Font.caption(10)
        timestampLabel.textColor = ProviderChatDesignTokens.Color.timestampText
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(bubbleView)
        stack.addArrangedSubview(timestampLabel)
        contentView.addSubview(stack)
    }

    // MARK: - Auto Layout Constraints

    private func setupConstraints() {
        imageHeightConstraint = messageImageView.heightAnchor.constraint(
            equalToConstant: ProviderChatDesignTokens.Metrics.messageImageHeight
        )
        imageHeightConstraint?.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            bubbleContentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            bubbleContentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            bubbleContentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            bubbleContentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),

            messageImageView.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
            imageHeightConstraint!,

            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
        ])

        leadingConstraint = stack.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: ProviderChatDesignTokens.Metrics.horizontalPadding
        )
        trailingConstraint = stack.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor,
            constant: -ProviderChatDesignTokens.Metrics.horizontalPadding
        )
        leadingConstraint?.isActive = true
        trailingConstraint?.isActive = true
    }

    // MARK: - Configuration

    func configure(message: ChatMessageDTO) {
        let isOwn = message.isOwn == true

        if let date = message.createdAt {
            timestampLabel.text = date.formatted(date: .omitted, time: .shortened)
        } else {
            timestampLabel.text = nil
        }

        if isOwn {
            bubbleView.backgroundColor = ProviderChatDesignTokens.Color.providerSentBubble
            messageLabel.textColor = ProviderChatDesignTokens.Color.providerSentBubbleText
            timestampLabel.textAlignment = .right
            leadingConstraint?.constant = 72
            trailingConstraint?.constant = -ProviderChatDesignTokens.Metrics.horizontalPadding
            stack.alignment = .trailing
        } else {
            bubbleView.backgroundColor = ProviderChatDesignTokens.Color.consumerBubble
            messageLabel.textColor = ProviderChatDesignTokens.Color.consumerBubbleText
            timestampLabel.textAlignment = .left
            leadingConstraint?.constant = ProviderChatDesignTokens.Metrics.horizontalPadding
            trailingConstraint?.constant = -72
            stack.alignment = .leading
        }

        if message.isImage, let mediaPath = message.mediaUrl, !mediaPath.isEmpty {
            messageLabel.isHidden = true
            messageLabel.text = nil
            messageImageView.isHidden = false
            imageHeightConstraint?.constant = ProviderChatDesignTokens.Metrics.messageImageHeight
            loadMessageImage(from: mediaPath)
        } else {
            imageLoadTask?.cancel()
            imageLoadTask = nil
            messageImageView.isHidden = true
            messageImageView.image = nil
            messageLabel.isHidden = false
            messageLabel.text = message.content ?? ""
        }
    }

    private func loadMessageImage(from storedPath: String) {
        imageLoadTask?.cancel()
        messageImageView.image = nil
        guard let url = CampusCutsS3ImageURL.url(forStoredPath: storedPath) else { return }
        imageLoadTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.messageImageView.image = image
            }
        }
        imageLoadTask?.resume()
    }
}

// MARK: - Booking request card cell

protocol ProviderChatBookingRequestCellDelegate: AnyObject {
    func bookingRequestCell(_ cell: ProviderChatBookingRequestCell, didTapAccept message: ChatMessageDTO)
    func bookingRequestCell(_ cell: ProviderChatBookingRequestCell, didTapDecline message: ChatMessageDTO)
}

final class ProviderChatBookingRequestCell: UITableViewCell {
    static let reuseIdentifier = "ProviderChatBookingRequestCell"

    weak var delegate: ProviderChatBookingRequestCellDelegate?
    private var message: ChatMessageDTO?

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let acceptButton = UIButton(type: .system)
    private let declineButton = UIButton(type: .system)
    private let buttonRow = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        setupConstraints()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        cardView.backgroundColor = ProviderChatDesignTokens.Color.cardBackground
        cardView.layer.cornerRadius = ProviderChatDesignTokens.Metrics.cardCornerRadius
        cardView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = ProviderChatDesignTokens.Font.heading(15)
        titleLabel.textColor = ProviderChatDesignTokens.Color.lavaShellCream
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        acceptButton.setTitle("Accept", for: .normal)
        acceptButton.titleLabel?.font = ProviderChatDesignTokens.Font.heading(14)
        acceptButton.backgroundColor = ProviderChatDesignTokens.Color.statusGreen
        acceptButton.setTitleColor(.white, for: .normal)
        acceptButton.layer.cornerRadius = 10
        acceptButton.addTarget(self, action: #selector(acceptTapped), for: .touchUpInside)

        declineButton.setTitle("Decline", for: .normal)
        declineButton.titleLabel?.font = ProviderChatDesignTokens.Font.heading(14)
        declineButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        declineButton.setTitleColor(.white, for: .normal)
        declineButton.layer.cornerRadius = 10
        declineButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)

        buttonRow.axis = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fillEqually
        buttonRow.addArrangedSubview(declineButton)
        buttonRow.addArrangedSubview(acceptButton)
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(titleLabel)
        cardView.addSubview(buttonRow)
        contentView.addSubview(cardView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: ProviderChatDesignTokens.Metrics.horizontalPadding),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -ProviderChatDesignTokens.Metrics.horizontalPadding),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),

            buttonRow.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            buttonRow.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            buttonRow.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            buttonRow.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14),
            buttonRow.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    func configure(message: ChatMessageDTO, consumerName: String) {
        self.message = message
        let meta = message.metadata
        let service = meta?.serviceDisplayName ?? "Service"
        let when = [meta?.appointmentDate, meta?.appointmentTime].compactMap { $0 }.joined(separator: " · ")
        titleLabel.text = "Booking request from \(consumerName)\n\(service)\(when.isEmpty ? "" : "\n\(when)")"
    }

    @objc private func acceptTapped() {
        guard let message else { return }
        delegate?.bookingRequestCell(self, didTapAccept: message)
    }

    @objc private func declineTapped() {
        guard let message else { return }
        delegate?.bookingRequestCell(self, didTapDecline: message)
    }
}
