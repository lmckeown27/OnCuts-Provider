import UIKit

// MARK: - ConversationCell

final class ProviderConversationCell: UITableViewCell {
    static let reuseIdentifier = "ProviderConversationCell"

    private let avatarImageView = UIImageView()
    private let avatarLoader = ProviderRemoteAvatarLoader()
    private let onlineIndicator = UIView()
    private let nameLabel = UILabel()
    private let previewBubbleShell = UIView()
    private let previewLabel = UILabel()
    private let statusBadgeShell = UIView()
    private let statusBadgeLabel = UILabel()
    private let timestampLabel = UILabel()
    private let metadataStack = UIStackView()
    private let textStack = UIStackView()

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
        avatarLoader.cancel()
        avatarImageView.image = UIImage(systemName: "person.circle.fill")
        avatarImageView.tintColor = ProviderChatDesignTokens.Color.previewText
        avatarImageView.contentMode = .scaleAspectFill
        statusBadgeShell.isHidden = true
        // Restore the neutral preview color before recycling — otherwise a row that's reused on
        // scroll could briefly flash with the previous row's green tint before `configure(with:)`
        // resets it.
        previewLabel.textColor = ProviderChatDesignTokens.Color.previewText
        previewBubbleShell.backgroundColor = .clear
        onlineIndicator.isHidden = true
    }

    // MARK: - UI Setup

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .default
        let selected = UIView()
        selected.backgroundColor = ProviderChatDesignTokens.Color.conversationRowSelection
        selectedBackgroundView = selected

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = ProviderChatDesignTokens.Metrics.avatarSize / 2
        avatarImageView.backgroundColor = ProviderChatDesignTokens.Color.cardBackground
        avatarImageView.tintColor = ProviderChatDesignTokens.Color.previewText
        avatarImageView.image = UIImage(systemName: "person.circle.fill")

        onlineIndicator.translatesAutoresizingMaskIntoConstraints = false
        onlineIndicator.backgroundColor = ProviderChatDesignTokens.Color.statusGreen
        onlineIndicator.layer.cornerRadius = ProviderChatDesignTokens.Metrics.onlineDotSize / 2
        onlineIndicator.layer.borderWidth = 2
        onlineIndicator.layer.borderColor = ProviderChatDesignTokens.Color.inboxBackdrop.cgColor
        onlineIndicator.isHidden = true

        nameLabel.font = ProviderChatDesignTokens.Font.heading(16)
        nameLabel.textColor = ProviderChatDesignTokens.Color.lavaShellCream
        nameLabel.numberOfLines = 1

        previewLabel.font = ProviderChatDesignTokens.Font.body(14)
        previewLabel.textColor = ProviderChatDesignTokens.Color.previewText
        previewLabel.numberOfLines = 1
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        previewBubbleShell.layer.cornerRadius = ProviderChatDesignTokens.Metrics.inboxPreviewCornerRadius
        previewBubbleShell.clipsToBounds = true
        previewBubbleShell.translatesAutoresizingMaskIntoConstraints = false
        previewBubbleShell.addSubview(previewLabel)

        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading
        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(previewBubbleShell)

        statusBadgeShell.translatesAutoresizingMaskIntoConstraints = false
        statusBadgeShell.layer.cornerRadius = ProviderChatDesignTokens.Metrics.conversationStatusBadgeCornerRadius
        statusBadgeShell.clipsToBounds = true
        statusBadgeShell.layer.borderWidth = 0.5
        statusBadgeShell.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        statusBadgeShell.setContentHuggingPriority(.required, for: .horizontal)
        statusBadgeShell.setContentCompressionResistancePriority(.required, for: .horizontal)

        statusBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBadgeLabel.font = ProviderChatDesignTokens.Font.badge(12)
        statusBadgeLabel.textAlignment = .center
        statusBadgeLabel.numberOfLines = 1
        statusBadgeLabel.backgroundColor = .clear
        statusBadgeShell.addSubview(statusBadgeLabel)

        timestampLabel.font = ProviderChatDesignTokens.Font.caption(11)
        timestampLabel.textColor = ProviderChatDesignTokens.Color.timestampText
        timestampLabel.textAlignment = .right

        metadataStack.axis = .vertical
        metadataStack.alignment = .trailing
        metadataStack.spacing = 6
        metadataStack.addArrangedSubview(statusBadgeShell)
        metadataStack.addArrangedSubview(timestampLabel)

        contentView.addSubview(avatarImageView)
        contentView.addSubview(onlineIndicator)
        contentView.addSubview(textStack)
        contentView.addSubview(metadataStack)
    }

    // MARK: - Auto Layout Constraints

    private func setupConstraints() {
        textStack.translatesAutoresizingMaskIntoConstraints = false
        metadataStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: ProviderChatDesignTokens.Metrics.horizontalPadding),
            avatarImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: ProviderChatDesignTokens.Metrics.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: ProviderChatDesignTokens.Metrics.avatarSize),

            onlineIndicator.widthAnchor.constraint(equalToConstant: ProviderChatDesignTokens.Metrics.onlineDotSize),
            onlineIndicator.heightAnchor.constraint(equalToConstant: ProviderChatDesignTokens.Metrics.onlineDotSize),
            onlineIndicator.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 1),
            onlineIndicator.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 1),

            textStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: metadataStack.leadingAnchor, constant: -10),

            metadataStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -ProviderChatDesignTokens.Metrics.horizontalPadding),
            metadataStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            metadataStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),

            statusBadgeLabel.topAnchor.constraint(
                equalTo: statusBadgeShell.topAnchor,
                constant: ProviderChatDesignTokens.Metrics.conversationStatusBadgePaddingV
            ),
            statusBadgeLabel.bottomAnchor.constraint(
                equalTo: statusBadgeShell.bottomAnchor,
                constant: -ProviderChatDesignTokens.Metrics.conversationStatusBadgePaddingV
            ),
            statusBadgeLabel.leadingAnchor.constraint(
                equalTo: statusBadgeShell.leadingAnchor,
                constant: ProviderChatDesignTokens.Metrics.conversationStatusBadgePaddingH
            ),
            statusBadgeLabel.trailingAnchor.constraint(
                equalTo: statusBadgeShell.trailingAnchor,
                constant: -ProviderChatDesignTokens.Metrics.conversationStatusBadgePaddingH
            ),
            statusBadgeShell.heightAnchor.constraint(
                greaterThanOrEqualToConstant: ProviderChatDesignTokens.Metrics.conversationStatusBadgeMinHeight
            ),

            previewLabel.topAnchor.constraint(
                equalTo: previewBubbleShell.topAnchor,
                constant: ProviderChatDesignTokens.Metrics.inboxPreviewPaddingV
            ),
            previewLabel.bottomAnchor.constraint(
                equalTo: previewBubbleShell.bottomAnchor,
                constant: -ProviderChatDesignTokens.Metrics.inboxPreviewPaddingV
            ),
            previewLabel.leadingAnchor.constraint(
                equalTo: previewBubbleShell.leadingAnchor,
                constant: ProviderChatDesignTokens.Metrics.inboxPreviewPaddingH
            ),
            previewLabel.trailingAnchor.constraint(
                equalTo: previewBubbleShell.trailingAnchor,
                constant: -ProviderChatDesignTokens.Metrics.inboxPreviewPaddingH
            ),
            previewBubbleShell.trailingAnchor.constraint(
                lessThanOrEqualTo: textStack.trailingAnchor
            ),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
    }

    // MARK: - Configuration

    func configure(with presentation: ProviderConversationPresentation) {
        nameLabel.text = presentation.displayName
        previewLabel.text = presentation.preview
        timestampLabel.text = presentation.timestamp
        onlineIndicator.isHidden = !presentation.isOnline

        avatarLoader.load(
            into: avatarImageView,
            storedPath: presentation.row.otherUser?.profilePicture,
            fallbackSystemImage: "person.circle.fill",
            fallbackTint: ProviderChatDesignTokens.Color.previewText
        )

        if let badge = presentation.badgeText,
           let background = presentation.badgeBackgroundColor,
           let foreground = presentation.badgeForegroundColor {
            statusBadgeShell.isHidden = false
            statusBadgeLabel.text = badge
            statusBadgeShell.backgroundColor = background
            statusBadgeLabel.textColor = foreground
        } else {
            statusBadgeShell.isHidden = true
        }

        // Mini bubble preview — same palette as the conversation thread:
        // grey fill for inbound, olive fill + white text for outbound.
        applyPreviewBubbleStyle(for: presentation.lastMessageDirection)
    }

    private func applyPreviewBubbleStyle(for direction: ProviderConversationLastMessageDirection) {
        switch direction {
        case .received:
            previewBubbleShell.backgroundColor = ProviderChatDesignTokens.Color.consumerBubble
            previewLabel.textColor = ProviderChatDesignTokens.Color.consumerBubbleText
        case .sent:
            previewBubbleShell.backgroundColor = ProviderChatDesignTokens.Color.providerSentBubble
            previewLabel.textColor = ProviderChatDesignTokens.Color.providerSentBubbleText
        case .none:
            previewBubbleShell.backgroundColor = .clear
            previewLabel.textColor = ProviderChatDesignTokens.Color.previewText
        }
    }
}
