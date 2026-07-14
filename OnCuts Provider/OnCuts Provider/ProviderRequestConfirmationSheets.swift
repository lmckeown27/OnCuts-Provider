import SwiftUI

// MARK: - Layout metrics (compact confirmation sheets)

enum ProviderRequestSheetMetrics {
    static let approveHeight: CGFloat = 280
    static let submitDeclineHeight: CGFloat = 280
    static let dragWidth: CGFloat = 36
    static let dragHeight: CGFloat = 5
    static let dragTopMargin: CGFloat = 10
    static let bottomBasinPadding: CGFloat = 34
    static let buttonHeight: CGFloat = 50
    static let buttonCornerRadius: CGFloat = 12
    static let buttonRowSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 20
    static let sheetSpring = Animation.spring(response: 0.35, dampingFraction: 0.82, blendDuration: 0)
    /// Expand/collapse for booking-request triage cards — slower, heavily damped for a smooth reveal.
    static let triageCardSpring = Animation.spring(response: 0.48, dampingFraction: 0.92, blendDuration: 0.12)
}

enum ProviderRequestSheetColors {
    static let approveGreen = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255) // #34C759
    static let lavaRed = Color(red: 1, green: 69 / 255, blue: 58 / 255) // #FF453A
    static let titleText = Color.lavaShellCream
    static let bodyText = Color.lavaShellCream.opacity(0.9)

    static func panelFill(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 12 / 255, green: 14 / 255, blue: 22 / 255).opacity(0.96)
            : Color(red: 0.99, green: 0.98, blue: 0.96).opacity(0.98)
    }

    static func panelStroke(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.lavaShellCream.opacity(0.24)
            : Color.black.opacity(0.12)
    }
}

// MARK: - Shared chrome

private struct ProviderRequestCompactSheetChrome<Content: View>: View {
  let detentHeight: CGFloat
  @ViewBuilder var content: () -> Content
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ProviderLavaSheetContainer {
      ZStack {
        ProviderRequestSheetLavaScrim()
        VStack(spacing: 0) {
          ProviderRequestSheetDragHandle()
            .padding(.top, ProviderRequestSheetMetrics.dragTopMargin)
          content()
            .providerRequestSheetReadablePanel()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .providerLavaScreenChrome()
    .presentationDetents([.height(detentHeight)])
    .presentationDragIndicator(.hidden)
    .presentationCornerRadius(20)
    .presentationBackground {
      ZStack {
        Color.black.opacity(colorScheme == .dark ? 0.72 : 0.35)
        Rectangle().fill(.ultraThickMaterial)
      }
    }
  }
}

/// Darkens animated lava behind compact confirmation sheets so foreground stays readable.
private struct ProviderRequestSheetLavaScrim: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Rectangle()
      .fill(
        colorScheme == .dark
            ? Color.black.opacity(0.58)
            : Color.white.opacity(0.55)
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)
  }
}

private struct ProviderRequestSheetReadablePanel: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 8)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .top)
      .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(ProviderRequestSheetColors.panelFill(colorScheme: colorScheme))
          .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .strokeBorder(ProviderRequestSheetColors.panelStroke(colorScheme: colorScheme), lineWidth: 1)
          }
          .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.12), radius: 12, y: 4)
      }
  }
}

private extension View {
  func providerRequestSheetReadablePanel() -> some View {
    modifier(ProviderRequestSheetReadablePanel())
  }
}

private struct ProviderRequestSheetDragHandle: View {
  var body: some View {
    Capsule()
      .fill(Color.lavaShellCream.opacity(0.55))
      .frame(width: ProviderRequestSheetMetrics.dragWidth, height: ProviderRequestSheetMetrics.dragHeight)
      .frame(maxWidth: .infinity)
      .accessibilityLabel("Dismiss sheet")
  }
}

private struct ScaledSheetText: View {
  let text: String
  let font: Font
  let color: Color
  var lineLimit: Int = 3

  var body: some View {
    Text(text)
      .font(font)
      .foregroundStyle(color)
      .lineLimit(lineLimit)
      .minimumScaleFactor(0.75)
      .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - Blueprint 1: Approve (280pt)

struct ProviderApproveBookingConfirmSheet: View {
  let customerName: String
  let scheduleSummary: String
  let onApprove: () -> Void

  var body: some View {
    ProviderRequestCompactSheetChrome(detentHeight: ProviderRequestSheetMetrics.approveHeight) {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 6) {
          ScaledSheetText(
            text: "Confirm Appointment Slot",
            font: .provider(size: 20, weight: .bold),
            color: ProviderRequestSheetColors.titleText,
            lineLimit: 2
          )
          ScaledSheetText(
            text: "This locks \(customerName) into your calendar on \(scheduleSummary)",
            font: .provider(size: 14, weight: .regular),
            color: ProviderRequestSheetColors.bodyText,
            lineLimit: 4
          )
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, ProviderRequestSheetMetrics.horizontalPadding)
        .padding(.top, 14)

        Spacer(minLength: 8)

        Button(action: onApprove) {
          ProviderBlackOutlinedText("Approve", fill: .white)
            .font(.provider(size: 17, weight: .bold))
            .frame(maxWidth: .infinity)
            .frame(height: ProviderRequestSheetMetrics.buttonHeight)
        }
        .background(
          Capsule()
            .fill(ProviderRequestSheetColors.approveGreen)
        )
        .padding(.horizontal, ProviderRequestSheetMetrics.horizontalPadding)
        .padding(.bottom, ProviderRequestSheetMetrics.bottomBasinPadding)
      }
    }
  }
}

// MARK: - Decline confirm (280pt)

struct ProviderSubmitDeclineConfirmSheet: View {
  let customerName: String
  let onSubmit: () -> Void

  var body: some View {
    ProviderRequestCompactSheetChrome(detentHeight: ProviderRequestSheetMetrics.submitDeclineHeight) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.provider(size: 26))
            .foregroundStyle(ProviderRequestSheetColors.lavaRed)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 6) {
            ScaledSheetText(
              text: "Submit Request Rejection?",
              font: .provider(size: 20, weight: .bold),
              color: ProviderRequestSheetColors.titleText,
              lineLimit: 2
            )
            ScaledSheetText(
              text: "This cancels the inquiry and alerts \(customerName) via SMS.",
              font: .provider(size: 14, weight: .regular),
              color: ProviderRequestSheetColors.bodyText,
              lineLimit: 4
            )
          }
        }
        .padding(.horizontal, ProviderRequestSheetMetrics.horizontalPadding)
        .padding(.top, 14)

        Spacer(minLength: 12)

        Button(action: onSubmit) {
          Text("Submit Rejection")
            .font(.provider(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: ProviderRequestSheetMetrics.buttonHeight)
        }
        .background(
          RoundedRectangle(cornerRadius: ProviderRequestSheetMetrics.buttonCornerRadius, style: .continuous)
            .fill(ProviderRequestSheetColors.lavaRed)
        )
        .padding(.horizontal, ProviderRequestSheetMetrics.horizontalPadding)
        .padding(.bottom, ProviderRequestSheetMetrics.bottomBasinPadding)
      }
    }
  }
}

// MARK: - Copy helpers

extension RequestTriageItem {
  var confirmCustomerName: String {
    row.customerName ?? "this customer"
  }

  var approveScheduleSummary: String {
    requestedStart.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
  }
}
