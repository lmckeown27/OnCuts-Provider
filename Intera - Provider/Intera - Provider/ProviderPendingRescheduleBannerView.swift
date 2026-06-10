import UIKit

/// Banner for a consumer's pending schedule-change request — used in booking detail and chat.
final class ProviderPendingRescheduleBannerView: UIView {
    var onApprove: (() -> Void)?
    var onDecline: (() -> Void)?

    private let card = UIView()
    private let titleLabel = UILabel()
    private let bodyStack = UIStackView()
    private let approveButton = UIButton(type: .system)
    private let declineButton = UIButton(type: .system)
    private let buttonRow = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(booking: SimpleBookingDTO, request: BookingPendingRescheduleRequestDTO) {
        bodyStack.arrangedSubviews.forEach {
            bodyStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        bodyStack.addArrangedSubview(detailRow(
            title: "Current appointment",
            value: booking.formattedSchedule()
        ))
        bodyStack.addArrangedSubview(detailRow(
            title: "Requested time",
            value: request.formattedProposedSchedule(),
            emphasized: true
        ))

        if let location = request.proposedLocation?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            bodyStack.addArrangedSubview(detailRow(title: "Requested location", value: location))
        }
        if let notes = request.proposedNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            bodyStack.addArrangedSubview(detailRow(title: "Notes", value: notes))
        }
    }

    func setActionsEnabled(_ enabled: Bool) {
        approveButton.isEnabled = enabled
        declineButton.isEnabled = enabled
        approveButton.alpha = enabled ? 1 : 0.55
        declineButton.alpha = enabled ? 1 : 0.55
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        card.backgroundColor = ProviderAppearance.olive.withAlphaComponent(0.18)
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 1
        card.layer.borderColor = ProviderAppearance.olive.withAlphaComponent(0.45).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = "Schedule change pending approval"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = ProviderAppearance.primaryText
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyStack.axis = .vertical
        bodyStack.spacing = 8
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        approveButton.setTitle("Approve", for: .normal)
        approveButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        approveButton.backgroundColor = ProviderChatDesignTokens.Color.statusGreen
        approveButton.setTitleColor(.white, for: .normal)
        approveButton.layer.cornerRadius = 10
        approveButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        approveButton.addTarget(self, action: #selector(approveTapped), for: .touchUpInside)

        declineButton.setTitle("Decline", for: .normal)
        declineButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        declineButton.backgroundColor = ProviderAppearance.elevatedSurface
        declineButton.setTitleColor(ProviderAppearance.primaryText, for: .normal)
        declineButton.layer.cornerRadius = 10
        declineButton.layer.borderWidth = 1
        declineButton.layer.borderColor = ProviderAppearance.elevatedSurfaceStroke.cgColor
        declineButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        declineButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)

        buttonRow.axis = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fillEqually
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.addArrangedSubview(approveButton)
        buttonRow.addArrangedSubview(declineButton)

        addSubview(card)
        card.addSubview(titleLabel)
        card.addSubview(bodyStack)
        card.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            bodyStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            bodyStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            bodyStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            buttonRow.topAnchor.constraint(equalTo: bodyStack.bottomAnchor, constant: 12),
            buttonRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            buttonRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            buttonRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
    }

    private func detailRow(title: String, value: String, emphasized: Bool = false) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = ProviderAppearance.secondaryText

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 14, weight: emphasized ? .semibold : .regular)
        valueLabel.textColor = ProviderAppearance.primaryText
        valueLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }

    @objc private func approveTapped() { onApprove?() }
    @objc private func declineTapped() { onDecline?() }
}
