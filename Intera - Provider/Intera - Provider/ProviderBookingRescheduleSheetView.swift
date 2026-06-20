import SwiftUI

/// Reschedule sheet for an existing booking — availability-aware date + hour picker.
struct ProviderBookingRescheduleSheetView: View {
    let booking: SimpleBookingDTO
    let barberId: String
    let onSave: (Date) -> Void
    let onCancel: () -> Void

    @State private var selectedDateTime: Date
    @State private var hasConflict = false

    init(
        booking: SimpleBookingDTO,
        barberId: String,
        onSave: @escaping (Date) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.booking = booking
        self.barberId = barberId
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedDateTime = State(initialValue: booking.providerEffectiveScheduledTime ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    scheduleComparisonHeader

                    ProviderPendingRequestScheduleEditor(
                        barberId: barberId,
                        bookingId: booking.id,
                        customerName: booking.consumerDisplayName,
                        serviceType: booking.serviceDisplayName,
                        bookingStatus: booking.status,
                        selectedDateTime: $selectedDateTime,
                        hasConflict: $hasConflict,
                        showsSelectedDayHeadline: false
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .font(.provider(.body))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedDateTime)
                    }
                    .font(.provider(.body, weight: .semibold))
                    .disabled(hasConflict)
                }
            }
        }
        .font(.provider(.body))
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
    }

    private var scheduleComparisonHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .center, spacing: 4) {
                Text(booking.consumerDisplayName)
                    .font(.provider(.headline, weight: .semibold))
                    .foregroundStyle(Color.lavaShellCream)
                    .multilineTextAlignment(.center)
                Text(booking.serviceDisplayName)
                    .font(.provider(.subheadline))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            scheduleSnapshotCard(
                title: consumerReferenceTitle,
                date: consumerReferenceDate,
                footnote: consumerReferenceFootnote,
                emphasized: false
            )

            scheduleSnapshotCard(
                title: "Changing to",
                date: selectedDateTime,
                footnote: proposedChangeFootnote,
                emphasized: true
            )
        }
    }

    private var consumerReferenceTitle: String {
        booking.hasPendingRescheduleRequest ? "Consumer requested" : "Scheduled appointment"
    }

    private var consumerReferenceDate: Date? {
        if booking.hasPendingRescheduleRequest {
            return booking.pendingRescheduleRequest?.proposedScheduledTime ?? booking.scheduledTime
        }
        return booking.scheduledTime
    }

    private var consumerReferenceFootnote: String? {
        guard booking.hasPendingRescheduleRequest,
              let current = booking.scheduledTime,
              let proposed = booking.pendingRescheduleRequest?.proposedScheduledTime,
              current != proposed
        else { return nil }
        return "Current appointment: \(formattedScheduleLine(for: current))"
    }

    private var proposedChangeFootnote: String? {
        guard let reference = consumerReferenceDate else { return nil }
        guard !Calendar.current.isDate(reference, equalTo: selectedDateTime, toGranularity: .minute) else {
            return "Same as \(booking.hasPendingRescheduleRequest ? "consumer request" : "current appointment")"
        }
        return nil
    }

    private func scheduleSnapshotCard(
        title: String,
        date: Date?,
        footnote: String?,
        emphasized: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.provider(.caption, weight: .semibold))
                .foregroundStyle(emphasized ? Color.providerOlive : Color.lavaShellCreamSecondary)

            if let date {
                Text(formattedDateLine(for: date))
                    .font(.provider(.title3, weight: emphasized ? .semibold : .medium))
                    .foregroundStyle(Color.lavaShellCream)
                Text(formattedTimeLine(for: date))
                    .font(.provider(.subheadline, weight: emphasized ? .semibold : .regular))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            } else {
                Text("Time TBD")
                    .font(.provider(.title3, weight: .medium))
                    .foregroundStyle(Color.lavaShellCreamSecondary)
            }

            if let footnote {
                Text(footnote)
                    .font(.provider(.caption))
                    .foregroundStyle(Color.lavaShellCreamTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(emphasized ? Color.providerOlive.opacity(0.18) : Color.providerScheduleCardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            emphasized ? Color.providerOlive.opacity(0.55) : Color.providerScheduleCardStroke,
                            lineWidth: emphasized ? 1.2 : 0.6
                        )
                }
        }
        .animation(.easeInOut(duration: 0.2), value: date?.timeIntervalSince1970)
    }

    private func formattedDateLine(for date: Date) -> String {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func formattedTimeLine(for date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func formattedScheduleLine(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}
