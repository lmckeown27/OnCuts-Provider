import SwiftUI

/// Admin Controls → **Notifications**. Mirrors web `AdminNotificationControls`.
struct ProviderAdminNotificationControlsView: View {
    @State private var templates: [AdminNotificationTemplateDTO] = []
    @State private var isLoading = true
    @State private var filter: AdminNotificationFilter = .all
    @State private var errorText: String?
    @State private var statusText: String?

    @State private var editingId: String?
    @State private var draftLabel = ""
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var draftAudience: AdminNotificationAudience = .both
    @State private var savingId: String?
    @State private var sendingId: String?

    @State private var isAdding = false
    @State private var addTitle = ""
    @State private var addBody = ""
    @State private var addAudience: AdminNotificationAudience = .both
    @State private var isCreating = false
    @State private var pendingRemove: AdminNotificationTemplateDTO?

    private var visible: [AdminNotificationTemplateDTO] {
        templates.filter { $0.matches(filter: filter) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text("Notifications")
                    .font(.provider(.caption2, weight: .semibold))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer(minLength: 8)
                Button(isAdding ? "Cancel" : "Add") {
                    editingId = nil
                    isAdding.toggle()
                }
                .font(.provider(.caption, weight: .semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 4) {
                ForEach(AdminNotificationFilter.allCases) { item in
                    let selected = filter == item
                    Button {
                        filter = item
                    } label: {
                        Text(item.segmentTitle)
                            .font(.provider(.caption, weight: .semibold))
                            .foregroundStyle(selected ? ProviderAdminChrome.primaryText : ProviderAdminChrome.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                if selected {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(ProviderAdminChrome.cardBackground)
                                        .shadow(color: Color.primary.opacity(0.06), radius: 1, y: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ProviderAdminChrome.mutedFill)
            )

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.provider(.caption))
                    .foregroundStyle(.red)
            }
            if let statusText, !statusText.isEmpty {
                Text(statusText)
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
            }

            if isAdding {
                addComposer
            }

            if isLoading, templates.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading…")
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                }
            } else if visible.isEmpty {
                Text("No notifications for this filter.")
                    .font(.provider(.subheadline))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
            } else {
                VStack(spacing: 10) {
                    ForEach(visible) { row in
                        templateRow(row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .providerAdminCardBackground(cornerRadius: 16)
        .task { await load() }
        .confirmationDialog(
            "Remove this custom notification?",
            isPresented: Binding(
                get: { pendingRemove != nil },
                set: { if !$0 { pendingRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let row = pendingRemove {
                    pendingRemove = nil
                    Task { await removeCustom(row) }
                }
            }
            Button("Cancel", role: .cancel) { pendingRemove = nil }
        }
    }

    private var addComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom announcement")
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(ProviderAdminChrome.primaryText)
            TextField("Title", text: $addTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Message", text: $addBody, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            audiencePicker(selection: $addAudience, legend: "Send to")
            Button {
                Task { await createCustom() }
            } label: {
                if isCreating {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Save")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.providerOlive)
            .controlSize(.small)
            .disabled(isCreating)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ProviderAdminChrome.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func templateRow(_ row: AdminNotificationTemplateDTO) -> some View {
        let isEditing = editingId == row.id
        let busy = savingId == row.id || sendingId == row.id
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.resolvedLabel)
                        .font(.provider(.subheadline, weight: .semibold))
                        .foregroundStyle(ProviderAdminChrome.primaryText)
                    Text(metaLine(for: row))
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                }
                Spacer(minLength: 8)
                if busy {
                    ProgressView().controlSize(.small)
                }
                Toggle(
                    "",
                    isOn: Binding(
                        get: { row.isEnabled },
                        set: { _ in
                            guard !busy else { return }
                            Task { await toggleEnabled(row) }
                        }
                    )
                )
                .labelsHidden()
                .tint(.providerOlive)
                .disabled(busy)
            }

            if isEditing {
                TextField("Label", text: $draftLabel)
                    .textFieldStyle(.roundedBorder)
                TextField("Title", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Body", text: $draftBody, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                audiencePicker(selection: $draftAudience, legend: "Audience")
                if row.resolvedKind == .system, let placeholders = row.placeholders, !placeholders.isEmpty {
                    Text("Placeholders: \(placeholders.map { "{{\($0)}}" }.joined(separator: ", "))")
                        .font(.provider(.caption2))
                        .foregroundStyle(ProviderAdminChrome.tertiaryText)
                }
                HStack(spacing: 8) {
                    Button {
                        Task { await saveEdit(row) }
                    } label: {
                        Text(savingId == row.id ? "Saving…" : "Save")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.providerOlive)
                    .controlSize(.small)
                    .disabled(busy)
                    Button("Cancel") { editingId = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                Text(row.resolvedTitle)
                    .font(.provider(.subheadline))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
                Text(row.resolvedBody)
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Edit") { startEdit(row) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    if row.isCustom {
                        Button {
                            Task { await sendCustom(row) }
                        } label: {
                            Text(sendingId == row.id ? "Sending…" : "Send")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(busy || !row.isEnabled)
                        Button("Remove", role: .destructive) {
                            pendingRemove = row
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(busy)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ProviderAdminChrome.border, lineWidth: 1)
        )
    }

    private func audiencePicker(selection: Binding<AdminNotificationAudience>, legend: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(legend)
                .font(.provider(.caption2, weight: .semibold))
                .foregroundStyle(ProviderAdminChrome.secondaryText)
                .textCase(.uppercase)
            ForEach(AdminNotificationAudience.allCases) { item in
                Button {
                    selection.wrappedValue = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selection.wrappedValue == item ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(
                                selection.wrappedValue == item
                                    ? Color.providerOlive
                                    : ProviderAdminChrome.tertiaryText
                            )
                        Text(item.chipLabel)
                            .font(.provider(.subheadline))
                            .foregroundStyle(ProviderAdminChrome.primaryText)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metaLine(for row: AdminNotificationTemplateDTO) -> String {
        var parts = [
            row.isCustom ? "Custom" : "Automatic",
            row.resolvedAudience.chipLabel,
        ]
        if let sent = row.lastSentAt?.trimmingCharacters(in: .whitespacesAndNewlines), !sent.isEmpty {
            parts.append("Sent \(Self.displaySentAt(sent))")
        }
        return parts.joined(separator: " · ")
    }

    private static func displaySentAt(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        if let date = iso.date(from: raw) ?? isoBasic.date(from: raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return raw
    }

    private func startEdit(_ row: AdminNotificationTemplateDTO) {
        isAdding = false
        editingId = row.id
        draftLabel = row.resolvedLabel
        draftTitle = row.resolvedTitle
        draftBody = row.resolvedBody
        draftAudience = row.resolvedAudience
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            templates = try await ProviderAdminService.listNotificationTemplates()
        } catch {
            guard !providerAdminIsBenignRequestCancellation(error) else { return }
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not load notifications"
        }
    }

    private func toggleEnabled(_ row: AdminNotificationTemplateDTO) async {
        savingId = row.id
        errorText = nil
        defer { savingId = nil }
        do {
            let updated = try await ProviderAdminService.updateNotificationTemplate(
                id: row.id,
                enabled: !row.isEnabled
            )
            replace(updated)
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not update notification"
        }
    }

    private func saveEdit(_ row: AdminNotificationTemplateDTO) async {
        let label = draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !title.isEmpty, !body.isEmpty else {
            errorText = "Label, title, and body are required"
            return
        }
        savingId = row.id
        errorText = nil
        defer { savingId = nil }
        do {
            let updated = try await ProviderAdminService.updateNotificationTemplate(
                id: row.id,
                label: label,
                title: title,
                body: body,
                audience: draftAudience
            )
            replace(updated)
            editingId = nil
            statusText = "Notification saved"
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not save notification"
        }
    }

    private func createCustom() async {
        let title = addTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = addBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else {
            errorText = "Title and body are required"
            return
        }
        isCreating = true
        errorText = nil
        defer { isCreating = false }
        do {
            let created = try await ProviderAdminService.createNotificationTemplate(
                title: title,
                body: body,
                audience: addAudience
            )
            templates.append(created)
            isAdding = false
            addTitle = ""
            addBody = ""
            addAudience = .both
            statusText = "Notification added"
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not add notification"
        }
    }

    private func sendCustom(_ row: AdminNotificationTemplateDTO) async {
        sendingId = row.id
        errorText = nil
        defer { sendingId = nil }
        do {
            let result = try await ProviderAdminService.sendNotificationTemplate(id: row.id)
            let queued = result.queued ?? 0
            let audience = AdminNotificationAudience(rawValue: (result.audience ?? row.resolvedAudience.rawValue).lowercased())
                ?? row.resolvedAudience
            let who: String
            switch audience {
            case .both: who = "users"
            case .consumer: who = "consumers"
            case .operator: who = "operators"
            }
            statusText = "Sending to \(queued) \(who)"
            await load()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not send notification"
        }
    }

    private func removeCustom(_ row: AdminNotificationTemplateDTO) async {
        guard row.isCustom else { return }
        savingId = row.id
        errorText = nil
        defer { savingId = nil }
        do {
            try await ProviderAdminService.deleteNotificationTemplate(id: row.id)
            templates.removeAll { $0.id == row.id }
            if editingId == row.id { editingId = nil }
            statusText = "Notification removed"
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not remove notification"
        }
    }

    private func replace(_ updated: AdminNotificationTemplateDTO) {
        if let index = templates.firstIndex(where: { $0.id == updated.id }) {
            templates[index] = updated
        } else {
            templates.append(updated)
        }
    }
}
