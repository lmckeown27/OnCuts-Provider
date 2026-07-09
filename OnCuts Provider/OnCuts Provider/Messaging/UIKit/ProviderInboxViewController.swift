import UIKit

// MARK: - ProviderInboxViewController

final class ProviderInboxViewController: UIViewController {
    var barberTableId: String?
    var onConversationSelected: ((ConversationRow) -> Void)?
    var onConversationsUpdated: (([ConversationRow]) -> Void)?

    /// Signed-in user's UUID. Set by the SwiftUI bridge from `session.authUser?.id`.
    ///
    /// Forwarded into each `ProviderConversationPresentation` so the inbox row can compare
    /// against `lastMessage.senderId` and color its direction dot accordingly. When `nil` (e.g.
    /// during initial bootstrap before auth-me resolves), every row's dot will be hidden — the
    /// list still renders normally, just without the at-a-glance direction cue.
    var currentUserId: String? {
        didSet {
            guard oldValue != currentUserId, !presentations.isEmpty else { return }
            let rows = presentations.map { $0.row }
            presentations = rows.map { ProviderConversationPresentation(row: $0, currentUserId: currentUserId) }
            tableView.reloadData()
        }
    }

    private var presentations: [ProviderConversationPresentation] = []
    private var isLoading = false

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let emptyStateView = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        loadConversations()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUnreadCountShouldRefresh),
            name: .providerMessagingUnreadCountShouldRefresh,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleUnreadCountShouldRefresh() {
        loadConversations()
    }

    func reloadConversations() {
        loadConversations()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = ProviderAppearance.neutralPushedBackdrop

        tableView.backgroundColor = .clear
        tableView.separatorColor = ProviderChatDesignTokens.Color.separator
        tableView.separatorInset = UIEdgeInsets(top: 0, left: ProviderChatDesignTokens.Metrics.horizontalPadding, bottom: 0, right: 0)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ProviderConversationCell.self, forCellReuseIdentifier: ProviderConversationCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        refreshControl.tintColor = ProviderChatDesignTokens.Color.brandAccent
        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        tableView.refreshControl = refreshControl

        loadingIndicator.color = ProviderChatDesignTokens.Color.brandAccent
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        configureEmptyState()
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(loadingIndicator)
    }

    private func configureEmptyState() {
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true

        let titleLabel = UILabel()
        titleLabel.text = "No conversations yet"
        titleLabel.font = ProviderChatDesignTokens.Font.heading(20)
        titleLabel.textColor = ProviderChatDesignTokens.Color.lavaShellCream
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "You'll receive conversations here when a customer books an appointment with you."
        subtitleLabel.font = ProviderChatDesignTokens.Font.body(15)
        subtitleLabel.textColor = ProviderChatDesignTokens.Color.previewText
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyStateView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: emptyStateView.trailingAnchor, constant: -28),
        ])
    }

    // MARK: - Auto Layout Constraints

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.topAnchor.constraint(equalTo: tableView.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: tableView.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Data

    private func loadConversations() {
        guard !isLoading else { return }
        isLoading = true
        if presentations.isEmpty {
            loadingIndicator.startAnimating()
        }

        Task { @MainActor in
            defer {
                isLoading = false
                loadingIndicator.stopAnimating()
                refreshControl.endRefreshing()
            }
            do {
                let rows = try await ProviderMessagesService.listConversations()
                presentations = rows.map { ProviderConversationPresentation(row: $0, currentUserId: currentUserId) }
                onConversationsUpdated?(rows)
                reloadTable()
            } catch {
                presentError(error)
            }
        }
    }

    private func reloadTable() {
        emptyStateView.isHidden = !presentations.isEmpty
        tableView.reloadData()
    }

    private func removeConversation(id: Int) {
        presentations.removeAll { $0.row.id == id }
        onConversationsUpdated?(presentations.map(\.row))
        reloadTable()
    }

    // MARK: - Action Handlers

    @objc private func refreshPulled() {
        loadConversations()
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: "Couldn’t load messages",
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ProviderInboxViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        presentations.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: ProviderConversationCell.reuseIdentifier,
            for: indexPath
        ) as? ProviderConversationCell else {
            return UITableViewCell()
        }
        cell.configure(with: presentations[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ProviderInboxViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        ProviderConversationMessagesPrefetch.prefetch(conversationId: presentations[indexPath.row].row.id)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onConversationSelected?(presentations[indexPath.row].row)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let archive = UIContextualAction(style: .normal, title: "Archive") { [weak self] _, _, completion in
            self?.archiveConversation(at: indexPath)
            completion(true)
        }
        archive.backgroundColor = ProviderChatDesignTokens.Color.brandPrimary

        let more = UIContextualAction(style: .normal, title: "More") { [weak self] _, _, completion in
            self?.presentMoreActions(for: indexPath)
            completion(true)
        }
        more.backgroundColor = ProviderChatDesignTokens.Color.brandAccent

        return UISwipeActionsConfiguration(actions: [more, archive])
    }

    private func archiveConversation(at indexPath: IndexPath) {
        let conversationId = presentations[indexPath.row].row.id
        removeConversation(id: conversationId)
    }

    private func presentMoreActions(for indexPath: IndexPath) {
        let presentation = presentations[indexPath.row]
        let sheet = UIAlertController(title: presentation.displayName, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Mark as read", style: .default) { [weak self] _ in
            Task { @MainActor in
                try? await ProviderMessagesService.markRead(conversationId: presentation.row.id)
                self?.loadConversations()
            }
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: indexPath)
        }
        present(sheet, animated: true)
    }
}
