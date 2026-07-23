import UIKit

// MARK: - ProviderBlockedUsersViewController

/// Blocked-account management (Guideline 1.2 safety). Lists people this operator blocked
/// via `GET /messages/blocks/accounts`.
final class ProviderBlockedUsersViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private var blockedUsers: [BlockedConsumerRow] = []
    private var loadErrorText: String?
    private var unblockingUserIds = Set<String>()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        loadBlockedUsers()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = ProviderChatDesignTokens.Color.screenBackground

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.register(ProviderBlockedUserCell.self, forCellReuseIdentifier: ProviderBlockedUserCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = ProviderChatDesignTokens.Font.body(15)
        emptyLabel.textColor = ProviderChatDesignTokens.Color.previewText
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(emptyLabel)
    }

    // MARK: - Auto Layout Constraints

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    // MARK: - Data

    private func loadBlockedUsers() {
        Task { @MainActor in
            do {
                blockedUsers = try await ProviderMessagesService.listBlockedUsers()
                loadErrorText = nil
            } catch {
                blockedUsers = []
                loadErrorText = Self.userFacingError(from: error)
            }
            refreshEmptyState()
            tableView.reloadData()
        }
    }

    private func refreshEmptyState() {
        if let loadErrorText {
            emptyLabel.text = loadErrorText
            emptyLabel.isHidden = false
        } else if blockedUsers.isEmpty {
            emptyLabel.text = "No blocked users."
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
    }

    private func unblockUser(_ user: BlockedConsumerRow) {
        guard !unblockingUserIds.contains(user.blockedUserId) else { return }

        unblockingUserIds.insert(user.blockedUserId)
        reloadRow(for: user.blockedUserId)

        Task { @MainActor in
            defer { unblockingUserIds.remove(user.blockedUserId) }
            do {
                try await ProviderMessagesService.unblockUser(userId: user.blockedUserId)
                if let idx = blockedUsers.firstIndex(where: { $0.blockedUserId == user.blockedUserId }) {
                    blockedUsers.remove(at: idx)
                    tableView.deleteRows(at: [IndexPath(row: idx, section: 0)], with: .automatic)
                }
                refreshEmptyState()
            } catch {
                reloadRow(for: user.blockedUserId)
                presentSimpleAlert(
                    title: "Couldn’t unblock",
                    message: (error as? LocalizedError)?.errorDescription
                        ?? "Please try again."
                )
            }
        }
    }

    private func reloadRow(for userId: String) {
        guard let idx = blockedUsers.firstIndex(where: { $0.blockedUserId == userId }) else { return }
        tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
    }

    private func presentSimpleAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private static func userFacingError(from error: Error) -> String {
        if let http = error as? OnCutsHTTPError, case let .httpStatus(code, body) = http {
            if code == 404 {
                return "Blocked accounts aren’t available on this server yet."
            }
            if code == 503, body?.contains("UGC_SCHEMA_MISSING") == true {
                return "Blocked accounts aren’t available right now. Please try again later."
            }
        }
        return (error as? LocalizedError)?.errorDescription
            ?? "Couldn’t load blocked users."
    }
}

// MARK: - UITableViewDataSource

extension ProviderBlockedUsersViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        blockedUsers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ProviderBlockedUserCell.reuseIdentifier,
            for: indexPath
        ) as? ProviderBlockedUserCell else {
            return UITableViewCell()
        }
        let user = blockedUsers[indexPath.row]
        cell.configure(
            with: user,
            isUnblocking: unblockingUserIds.contains(user.blockedUserId)
        ) { [weak self] in
            self?.unblockUser(user)
        }
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ProviderBlockedUsersViewController: UITableViewDelegate {}

// MARK: - ProviderBlockedUserCell

private final class ProviderBlockedUserCell: UITableViewCell {
    static let reuseIdentifier = "ProviderBlockedUserCell"

    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let textStack = UIStackView()
    private let unblockButton = UIButton(type: .system)
    private var onUnblock: (() -> Void)?

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
        onUnblock = nil
        unblockButton.isEnabled = true
        unblockButton.setTitle("Unblock", for: .normal)
    }

    func configure(with user: BlockedConsumerRow, isUnblocking: Bool, onUnblock: @escaping () -> Void) {
        self.onUnblock = onUnblock
        nameLabel.text = user.resolvedDisplayName

        var detailParts: [String] = []
        if let email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            detailParts.append(email)
        }
        if let date = user.blockedAt {
            detailParts.append("Blocked \(date.formatted(date: .abbreviated, time: .omitted))")
        } else if detailParts.isEmpty {
            detailParts.append("Blocked")
        }
        detailLabel.text = detailParts.joined(separator: "\n")
        detailLabel.isHidden = detailParts.isEmpty

        unblockButton.isEnabled = !isUnblocking
        unblockButton.setTitle(isUnblocking ? "…" : "Unblock", for: .normal)
    }

    private func setupUI() {
        backgroundColor = ProviderChatDesignTokens.Color.cardBackground
        selectionStyle = .none

        nameLabel.font = ProviderChatDesignTokens.Font.heading(16)
        nameLabel.textColor = ProviderChatDesignTokens.Color.lavaShellCream
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail

        detailLabel.font = ProviderChatDesignTokens.Font.caption(12)
        detailLabel.textColor = ProviderChatDesignTokens.Color.previewText
        detailLabel.numberOfLines = 2

        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(detailLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.filled()
        config.title = "Unblock"
        config.baseBackgroundColor = ProviderAppearance.olive
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = ProviderChatDesignTokens.Font.badge(13)
            return outgoing
        }
        unblockButton.configuration = config
        unblockButton.setContentHuggingPriority(.required, for: .horizontal)
        unblockButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        unblockButton.translatesAutoresizingMaskIntoConstraints = false
        unblockButton.addTarget(self, action: #selector(unblockTapped), for: .touchUpInside)
        unblockButton.accessibilityLabel = "Unblock"

        contentView.addSubview(textStack)
        contentView.addSubview(unblockButton)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: unblockButton.leadingAnchor, constant: -12),

            unblockButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            unblockButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @objc private func unblockTapped() {
        onUnblock?()
    }
}
