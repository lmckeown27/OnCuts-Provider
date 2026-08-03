import Foundation

extension Date {
    /// ISO 8601 with fractional seconds for `bookings-simple` updates.
    func campusCutsISO8601String() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: self)
    }
}

extension SimpleBookingDTO {
    /// Pending booking display time with override hierarchy:
    /// 1. Provider reschedule (`scheduledTime` moved off the initial submission)
    /// 2. Consumer pending reschedule request (`proposedScheduledTime`)
    /// 3. Initial submission (`scheduledTime` / booking-request row)
    func providerPendingScheduleTime(originalSubmission: Date? = nil) -> Date? {
        guard statusUpper == "PENDING" else { return scheduledTime }

        guard let scheduled = scheduledTime else {
            return pendingRescheduleRequest?.proposedScheduledTime ?? originalSubmission
        }

        guard hasPendingRescheduleRequest,
              let proposed = pendingRescheduleRequest?.proposedScheduledTime,
              !Calendar.current.isDate(proposed, equalTo: scheduled, toGranularity: .minute) else {
            return scheduled
        }

        if let submission = originalSubmission {
            if Calendar.current.isDate(scheduled, equalTo: submission, toGranularity: .minute) {
                return proposed
            }
            return scheduled
        }

        return proposed
    }

    /// Effective pending time for schedule, chat, and booking detail surfaces.
    var providerEffectiveScheduledTime: Date? {
        providerPendingScheduleTime(originalSubmission: nil)
    }

    /// Effective pending time for booking-request triage cards.
    func providerBookingRequestScheduledTime(requestRow: BookingRequestRow) -> Date? {
        providerPendingScheduleTime(originalSubmission: requestRow.requestedScheduleInstant)
    }

    func updatingScheduledTime(_ time: Date, clearPendingReschedule: Bool = false) -> SimpleBookingDTO {
        SimpleBookingDTO(
            id: id,
            consumerId: consumerId,
            barberId: barberId,
            serviceType: serviceType,
            priceUsdCents: priceUsdCents,
            scheduledTime: time,
            status: status,
            location: location,
            notes: notes,
            serviceName: serviceName,
            review: review,
            paidAt: paidAt,
            completedAt: completedAt,
            paymentRequestedAt: paymentRequestedAt,
            tipRequestedAt: tipRequestedAt,
            tipDecidedAt: tipDecidedAt,
            cancelledAt: cancelledAt,
            tipAmountCents: tipAmountCents,
            totalPaidCents: totalPaidCents,
            paymentMethod: paymentMethod,
            commissionFreeApplied: commissionFreeApplied,
            pendingRescheduleRequest: clearPendingReschedule ? nil : pendingRescheduleRequest,
            consumer: consumer,
            consumerName: consumerName,
            barber: barber,
            barberName: barberName,
            conversationId: conversationId
        )
    }

    func updatingPaymentRequestedAt(_ date: Date?) -> SimpleBookingDTO {
        SimpleBookingDTO(
            id: id,
            consumerId: consumerId,
            barberId: barberId,
            serviceType: serviceType,
            priceUsdCents: priceUsdCents,
            scheduledTime: scheduledTime,
            status: status,
            location: location,
            notes: notes,
            serviceName: serviceName,
            review: review,
            paidAt: paidAt,
            completedAt: completedAt,
            paymentRequestedAt: date,
            tipRequestedAt: tipRequestedAt,
            tipDecidedAt: tipDecidedAt,
            cancelledAt: cancelledAt,
            tipAmountCents: tipAmountCents,
            totalPaidCents: totalPaidCents,
            paymentMethod: paymentMethod,
            commissionFreeApplied: commissionFreeApplied,
            pendingRescheduleRequest: pendingRescheduleRequest,
            consumer: consumer,
            consumerName: consumerName,
            barber: barber,
            barberName: barberName,
            conversationId: conversationId
        )
    }

    /// Prefer detail-endpoint tip / completion fields when the barber list omits them.
    func mergingTipLifecycle(from detail: SimpleBookingDTO) -> SimpleBookingDTO {
        SimpleBookingDTO(
            id: id,
            consumerId: consumerId,
            barberId: barberId,
            serviceType: serviceType,
            priceUsdCents: priceUsdCents,
            scheduledTime: scheduledTime,
            status: detail.status ?? status,
            location: location,
            notes: notes,
            serviceName: serviceName,
            review: review ?? detail.review,
            paidAt: paidAt ?? detail.paidAt,
            completedAt: completedAt ?? detail.completedAt,
            paymentRequestedAt: paymentRequestedAt ?? detail.paymentRequestedAt,
            tipRequestedAt: tipRequestedAt ?? detail.tipRequestedAt,
            tipDecidedAt: tipDecidedAt ?? detail.tipDecidedAt,
            cancelledAt: cancelledAt ?? detail.cancelledAt,
            tipAmountCents: tipAmountCents ?? detail.tipAmountCents,
            totalPaidCents: totalPaidCents ?? detail.totalPaidCents,
            paymentMethod: paymentMethod ?? detail.paymentMethod,
            commissionFreeApplied: commissionFreeApplied ?? detail.commissionFreeApplied,
            pendingRescheduleRequest: pendingRescheduleRequest ?? detail.pendingRescheduleRequest,
            consumer: consumer,
            consumerName: consumerName,
            barber: barber,
            barberName: barberName,
            conversationId: conversationId ?? detail.conversationId
        )
    }

    func formattedProviderEffectiveSchedule(reference: Date = .now) -> String {
        guard let time = providerEffectiveScheduledTime else { return "Time TBD" }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        return time.formatted(style)
    }

    func formattedSchedule(reference: Date = .now) -> String {
        guard let scheduledTime else { return "Time TBD" }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        return scheduledTime.formatted(style)
    }

    /// Date shown on booking rows / summaries: payment time once settled, otherwise the appointment.
    var providerListDisplayDate: Date? {
        paidAt ?? scheduledTime
    }

    func formattedListDisplayDate(reference: Date = .now) -> String {
        guard let time = providerListDisplayDate else { return "Time TBD" }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        return time.formatted(style)
    }

    func isSameCalendarDay(as date: Date, calendar: Calendar = .current) -> Bool {
        guard let scheduledTime else { return false }
        return calendar.isDate(scheduledTime, inSameDayAs: date)
    }

    func isInWeek(containing referenceMonday: Date, calendar: Calendar = .current) -> Bool {
        guard let scheduledTime else { return false }
        let end = calendar.date(byAdding: .day, value: 7, to: referenceMonday) ?? referenceMonday
        return scheduledTime >= referenceMonday && scheduledTime < end
    }

    func isInMonth(containing monthStart: Date, calendar: Calendar = .current) -> Bool {
        guard let scheduledTime else { return false }
        return calendar.isDate(scheduledTime, equalTo: monthStart, toGranularity: .month)
    }
}
