import SwiftUI

struct ProviderScheduleBookingMoveConfirmBanner: View {
    let consumerName: String
    let originalTime: Date
    let proposedTime: Date
    let isSaving: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move appointment?")
                .font(.provider(.headline, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)

            Text(consumerName)
                .font(.provider(.subheadline, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)

            HStack(spacing: 16) {
                moveTimeColumn(title: "From", date: originalTime)
                Image(systemName: "arrow.right")
                    .font(.provider(.caption, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                moveTimeColumn(title: "To", date: proposedTime)
            }

            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.provider(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.providerScheduleTrackStroke, lineWidth: 0.8)
                    }

                Button(action: onConfirm) {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(Color.lavaShellCream)
                        } else {
                            Text("Confirm")
                                .font(.provider(.subheadline, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.lavaShellCream)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.providerOlive)
                }
                .disabled(isSaving)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.providerScheduleCardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.providerScheduleTrackStroke, lineWidth: 0.8)
                }
        }
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }

    private func moveTimeColumn(title: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.provider(.caption2, weight: .medium))
                .foregroundStyle(Color.lavaShellCreamSecondary)
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.provider(.footnote, weight: .semibold))
                .foregroundStyle(Color.lavaShellCream)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
