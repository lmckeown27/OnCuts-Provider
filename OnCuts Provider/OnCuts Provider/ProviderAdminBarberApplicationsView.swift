import SwiftUI

/// Operators → Applications queue.
///
/// Kept as its own `View` type (not nested inside `ProviderAdminDashboardView`) so switching
/// to this segment does not deepen the already-huge Admin view-builder type — that nesting
/// was overflowing the stack (`EXC_BAD_ACCESS code=2`) on device.
struct ProviderAdminBarberApplicationsView: View {
    let applications: [BarberApplicationListRowDTO]
    let isLoading: Bool
    let errorText: String?
    let busyApplicationId: String?
    @Binding var selectedApplication: BarberApplicationListRowDTO?
    @Binding var inlineConfirmKind: ProviderAdminBarberApplicationConfirmKind?
    let onApprove: (BarberApplicationListRowDTO) -> Void
    let onReject: (BarberApplicationListRowDTO) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.provider(.caption))
                    .foregroundStyle(.red)
            }

            if let selected = selectedApplication {
                detail(selected)
            } else if isLoading, applications.isEmpty {
                loadingRow("Loading applications…")
            } else if applications.isEmpty {
                Text("No applications need review for this scope.")
                    .font(.provider(.footnote))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
            } else {
                ForEach(applications, id: \.adminQueueIdentity) { application in
                    row(application)
                }
            }
        }
    }

    private func row(_ application: BarberApplicationListRowDTO) -> some View {
        let isBusy = busyApplicationId == application.id
        return Button {
            inlineConfirmKind = nil
            selectedApplication = application
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(application.displayName)
                            .font(.provider(.subheadline, weight: .semibold))
                            .foregroundStyle(ProviderAdminChrome.primaryText)
                        if application.origin == .guest {
                            tag(text: "Guest", tint: Color.orange.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                        tag(
                            text: application.statusEnum?.displayLabel ?? application.status.capitalized,
                            tint: statusTint(application)
                        )
                    }
                    Text(application.email ?? "No email")
                        .font(.provider(.caption))
                        .foregroundStyle(ProviderAdminChrome.secondaryText)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let campus = application.campusName, !campus.isEmpty {
                            Text(campus)
                        }
                        if let years = application.yearsExperience, !years.isEmpty {
                            Text("·")
                            Text("\(years) yrs")
                        }
                        if let when = application.createdAt {
                            Text("·")
                            Text(relativeShort(when))
                        }
                    }
                    .font(.provider(.caption2))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.tertiaryText)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ProviderAdminChrome.stoneMutedFill)
            )
            .opacity(isBusy ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func detail(_ application: BarberApplicationListRowDTO) -> some View {
        let isBusy = busyApplicationId == application.id
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                selectedApplication = nil
                inlineConfirmKind = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back to Applications")
                }
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(ProviderAdminChrome.primaryText)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(application.displayName)
                        .font(.provider(.title3, weight: .semibold))
                        .foregroundStyle(ProviderAdminChrome.primaryText)
                    if application.origin == .guest {
                        tag(text: "Guest", tint: Color.orange.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    tag(
                        text: application.statusEnum?.displayLabel ?? application.status.capitalized,
                        tint: statusTint(application)
                    )
                }
                Text(application.email ?? "No email")
                    .font(.provider(.caption))
                    .foregroundStyle(ProviderAdminChrome.secondaryText)
                detailGrid(application)
                if let specialties = application.specialties, !specialties.isEmpty {
                    detailBlock(title: "Specialties", value: specialties.joined(separator: ", "))
                }
                detailBlock(
                    title: "Profession",
                    value: application.submittedProfessionLabel ?? "—"
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ProviderAdminChrome.stoneMutedFill)
            )

            if application.statusEnum == .pending {
                decisionButtons(application, isBusy: isBusy)
            }

            if isBusy {
                loadingRow("Updating application…")
            }
        }
    }

    @ViewBuilder
    private func decisionButtons(
        _ application: BarberApplicationListRowDTO,
        isBusy: Bool
    ) -> some View {
        VStack(spacing: 8) {
            if inlineConfirmKind != nil {
                Text("Are you sure?")
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(ProviderAdminChrome.primaryText)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                switch inlineConfirmKind {
                case nil:
                    Button {
                        inlineConfirmKind = .approve
                    } label: {
                        Text("Approve")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.providerOlive)
                    .disabled(isBusy)

                    Button {
                        inlineConfirmKind = .reject
                    } label: {
                        Text("Reject")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isBusy)

                case .approve:
                    Button {
                        inlineConfirmKind = nil
                    } label: {
                        Text("No")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)

                    Button {
                        inlineConfirmKind = nil
                        onApprove(application)
                    } label: {
                        Text("Yes")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.providerOlive)
                    .disabled(isBusy)

                case .reject:
                    Button {
                        inlineConfirmKind = nil
                        onReject(application)
                    } label: {
                        Text("Yes")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isBusy)

                    Button {
                        inlineConfirmKind = nil
                    } label: {
                        Text("No")
                            .font(.provider(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }
            }
        }
    }

    private func detailGrid(_ application: BarberApplicationListRowDTO) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        return LazyVGrid(columns: columns, spacing: 8) {
            metricCell(
                title: "Experience",
                value: application.yearsExperience.map { "\($0) years" } ?? "—"
            )
            metricCell(title: "Phone", value: phoneDisplay(application.phoneNumber))
            metricCell(
                title: "Own tools",
                value: application.hasOwnTools == true
                    ? "Yes"
                    : (application.hasOwnTools == false ? "No" : "—")
            )
            if let when = application.createdAt {
                metricCell(title: "Applied", value: when.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    private func phoneDisplay(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Not provided" }
        let hasApplicantFormatting = trimmed.contains(where: { !$0.isNumber && $0 != "+" })
        if hasApplicantFormatting {
            return trimmed
        }
        let digits = trimmed.filter(\.isNumber)
        if digits.count == 11, digits.hasPrefix("1") {
            return PhoneNumberInputFormatter.format(String(digits.dropFirst()), regionCode: "US")
        }
        if digits.count == 10 {
            return PhoneNumberInputFormatter.format(digits, regionCode: "US")
        }
        let region = Locale.current.region?.identifier ?? "US"
        let formatted = PhoneNumberInputFormatter.format(trimmed, regionCode: region)
        return formatted.isEmpty ? trimmed : formatted
    }

    private func metricCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.provider(.caption2))
                .foregroundStyle(ProviderAdminChrome.tertiaryText)
            Text(value)
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(ProviderAdminChrome.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ProviderAdminChrome.stoneMutedFill)
        )
    }

    private func detailBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.provider(.caption2))
                .foregroundStyle(ProviderAdminChrome.tertiaryText)
            Text(value)
                .font(.provider(.footnote))
                .foregroundStyle(ProviderAdminChrome.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ProviderAdminChrome.stoneMutedFill)
        )
    }

    private func statusTint(_ application: BarberApplicationListRowDTO) -> Color {
        switch application.statusEnum {
        case .pending: return Color.orange.opacity(0.55)
        case .approved: return Color.green.opacity(0.55)
        case .rejected: return Color.red.opacity(0.55)
        case .underReview, .interviewScheduled: return Color.blue.opacity(0.45)
        case nil: return ProviderAdminChrome.stoneMutedFill
        }
    }

    private func tag(text: String, tint: Color) -> some View {
        Text(text)
            .font(.provider(.caption2, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.6), in: Capsule())
    }

    private func loadingRow(_ msg: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(msg)
                .font(.provider(.footnote))
                .foregroundStyle(ProviderAdminChrome.secondaryText)
        }
    }

    private func relativeShort(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

enum ProviderAdminBarberApplicationConfirmKind: String, Equatable {
    case approve
    case reject
}
