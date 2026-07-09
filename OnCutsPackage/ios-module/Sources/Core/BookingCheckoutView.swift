import Foundation

#if os(iOS)
import StripePaymentSheet
import SwiftUI

/// Native Stripe checkout: loads keys via `BookingCheckoutViewModel` + `StripeManager`, presents `.paymentSheet`.
public struct BookingCheckoutView: View {
    @ObservedObject private var model: BookingCheckoutViewModel
    private let currencyFormatter: NumberFormatter

    public init(model: BookingCheckoutViewModel) {
        self._model = ObservedObject(wrappedValue: model)
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        self.currencyFormatter = f
    }

    public var body: some View {
        Group {
            if let sheet = model.paymentSheet {
                checkoutContent
                    .paymentSheet(
                        isPresented: $model.isPresentingPaymentSheet,
                        paymentSheet: sheet,
                        onCompletion: { result in
                            model.handlePaymentSheetResult(result)
                        }
                    )
            } else {
                checkoutContent
            }
        }
    }

    @ViewBuilder
    private var checkoutContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.phase {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .ready, .failed:
                amountSummary
                payButton
            case .bookingConfirmed:
                confirmedBanner
            }
            if case .failed(let msg) = model.phase {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .task {
            await model.loadPaymentSession()
        }
    }

    private var amountSummary: some View {
        let text = currencyFormatter.string(from: NSDecimalNumber(value: Double(model.amountCents) / 100.0))
            ?? String(format: "$%.2f", Double(model.amountCents) / 100.0)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Total")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var payButton: some View {
        Button {
            guard model.paymentSheet != nil, !model.hasCompletedPayment else { return }
            model.isPresentingPaymentSheet = true
        } label: {
            Text("Pay with card or Apple Pay")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.hasCompletedPayment || model.paymentSheet == nil || model.phase == .loading)
    }

    private var confirmedBanner: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Booking confirmed")
                .font(.title2.weight(.bold))
            Text("Your payment completed successfully.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#endif
