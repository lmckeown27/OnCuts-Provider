import SwiftUI

/// Reschedule sheet for an existing booking — availability-aware date + hour picker.
struct ProviderBookingRescheduleSheetView: View {
    let booking: SimpleBookingDTO
    let barberId: String
    let onSave: (Date) -> Void
    let onCancel: () -> Void

    @State private var selectedDateTime: Date
    @State private var hasConflict = false

    @Environment(\.colorScheme) private var colorScheme

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
        // Default "Changing to" to the current appointment so Save is a no-op exit
        // if the provider opened Reschedule by accident and didn't pick a new slot.
        _selectedDateTime = State(initialValue: booking.scheduledTime ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    scheduleComparisonHeader

                    ProviderPendingRequestScheduleEditor(
                        barberId: barberId,
                        bookingId: booking.id,
                        selectedDateTime: $selectedDateTime,
                        hasConflict: $hasConflict,
                        showsSelectedDayHeadline: false,
                        preserveSelectionUntilEdited: true
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .providerPageNavigationTitle("Reschedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .font(.provider(.body))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isUnchangedFromCurrentAppointment {
                            onCancel()
                        } else {
                            onSave(selectedDateTime)
                        }
                    }
                    .font(.provider(.body, weight: .semibold))
                    .disabled(hasConflict && !isUnchangedFromCurrentAppointment)
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
        if booking.hasPendingRescheduleRequest,
           let proposed = booking.pendingRescheduleRequest?.proposedScheduledTime,
           let scheduled = booking.scheduledTime,
           !Calendar.current.isDate(proposed, equalTo: scheduled, toGranularity: .minute) {
            return proposed
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

    private var isUnchangedFromCurrentAppointment: Bool {
        guard let scheduled = booking.scheduledTime else { return false }
        return Calendar.current.isDate(scheduled, equalTo: selectedDateTime, toGranularity: .minute)
    }

    private var proposedChangeFootnote: String? {
        if isUnchangedFromCurrentAppointment {
            return "Same as current appointment"
        }
        guard let reference = consumerReferenceDate else { return nil }
        guard Calendar.current.isDate(reference, equalTo: selectedDateTime, toGranularity: .minute) else {
            return nil
        }
        return booking.hasPendingRescheduleRequest ? "Same as consumer request" : "Same as current appointment"
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
                .foregroundStyle(emphasized ? onEmphasizedCardSecondary : Color.lavaShellCreamSecondary)

            if let date {
                Text(formattedDateLine(for: date))
                    .font(.provider(.title3, weight: emphasized ? .semibold : .medium))
                    .foregroundStyle(emphasized ? onEmphasizedCardPrimary : Color.lavaShellCream)
                Text(formattedTimeLine(for: date))
                    .font(.provider(.subheadline, weight: emphasized ? .semibold : .regular))
                    .foregroundStyle(emphasized ? onEmphasizedCardSecondary : Color.lavaShellCreamSecondary)
            } else {
                Text("Time TBD")
                    .font(.provider(.title3, weight: .medium))
                    .foregroundStyle(emphasized ? onEmphasizedCardSecondary : Color.lavaShellCreamSecondary)
            }

            if let footnote {
                Text(footnote)
                    .font(.provider(.caption))
                    .foregroundStyle(emphasized ? onEmphasizedCardTertiary : Color.lavaShellCreamTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(emphasized ? emphasizedCardFill : Color.providerScheduleCardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            emphasized ? emphasizedCardStroke : Color.providerScheduleCardStroke,
                            lineWidth: emphasized ? 1.2 : 0.6
                        )
                }
        }
        .animation(.easeInOut(duration: 0.2), value: date?.timeIntervalSince1970)
    }

    private var emphasizedCardFill: Color {
        colorScheme == .dark
            ? Color.providerOlive.opacity(0.52)
            : Color.providerOlive.opacity(0.92)
    }

    private var emphasizedCardStroke: Color {
        Color.providerOlive.opacity(colorScheme == .dark ? 0.75 : 0.85)
    }

    private var onEmphasizedCardPrimary: Color {
        colorScheme == .dark ? Color.lavaShellCream : Color.providerOnOliveFill
    }

    private var onEmphasizedCardSecondary: Color {
        colorScheme == .dark ? Color.lavaShellCreamSecondary : Color.providerOnOliveFillSecondary
    }

    private var onEmphasizedCardTertiary: Color {
        colorScheme == .dark ? Color.lavaShellCreamTertiary : Color.providerOnOliveFillTertiary
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
