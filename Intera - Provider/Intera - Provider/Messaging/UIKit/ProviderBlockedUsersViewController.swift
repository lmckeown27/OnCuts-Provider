import UIKit

// MARK: - ProviderBlockedUsersViewController

/// Placeholder screen for blocked-account management (Guideline 1.2 safety anchor).
final class ProviderBlockedUsersViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private var blockedUsers: [BlockedConsumerRow] = []

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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BlockedUserCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.text = "No blocked users."
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
            } catch {
                blockedUsers = []
            }
            emptyLabel.isHidden = !blockedUsers.isEmpty
            tableView.reloadData()
        }
    }
}

// MARK: - UITableViewDataSource

extension ProviderBlockedUsersViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        blockedUsers.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BlockedUserCell", for: indexPath)
        let user = blockedUsers[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = user.displayName ?? "Blocked user"
        content.textProperties.color = .white
        if let date = user.blockedAt {
            content.secondaryText = "Blocked \(date.formatted(date: .abbreviated, time: .omitted))"
            content.secondaryTextProperties.color = ProviderChatDesignTokens.Color.previewText
        }
        cell.contentConfiguration = content
        cell.backgroundColor = ProviderChatDesignTokens.Color.cardBackground
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ProviderBlockedUsersViewController: UITableViewDelegate {}
