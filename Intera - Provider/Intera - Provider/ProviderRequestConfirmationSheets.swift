import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Layout metrics (280pt / 320pt compact sheets)

enum ProviderRequestSheetMetrics {
    static let approveHeight: CGFloat = 280
    static let declinePickerHeight: CGFloat = 320
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
    static let declineOrange = Color(red: 1, green: 0.58, blue: 0)
    static let titleText = Color.lavaShellCream
    static let bodyText = Color.lavaShellCream.opacity(0.9)
    static let mutedText = Color.lavaShellCream.opacity(0.78)

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

    static func capsuleFill(colorScheme: ColorScheme, selected: Bool) -> Color {
        if selected {
            return declineOrange.opacity(colorScheme == .dark ? 0.28 : 0.18)
        }
        return colorScheme == .dark
            ? Color.black.opacity(0.42)
            : Color.black.opacity(0.06)
    }
}

enum ProviderDeclineReason: String, CaseIterable, Identifiable {
    case scheduleConflict = "Schedule Conflict"
    case personalTimeOff = "Personal Time Off"
    case serviceMismatch = "Service Mismatch"
    case other = "Other"

    var id: String { rawValue }

    /// Text sent to the reject API — preset labels, or trimmed custom copy for **Other**.
    func apiReason(customOtherText: String) -> String? {
        if self == .other {
            let trimmed = customOtherText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return rawValue
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
            font: .system(size: 20, weight: .bold),
            color: ProviderRequestSheetColors.titleText,
            lineLimit: 2
          )
          ScaledSheetText(
            text: "This locks \(customerName) into your \(scheduleSummary) calendar.",
            font: .system(size: 14, weight: .regular),
            color: ProviderRequestSheetColors.bodyText,
            lineLimit: 4
          )
        }
        .padding(.horizontal, ProviderRequestSheetMetrics.horizontalPadding)
        .padding(.top, 14)

        Spacer(minLength: 8)

        Button(action: onApprove) {
          Text("Approve")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: ProviderRequestSheetMetrics.buttonHeight)
        }
        .background(
          RoundedRectangle(cornerRadius: ProviderRequestSheetMetrics.buttonCornerRadius, style: .continuous)
            .fill(ProviderRequestSheetColors.approveGreen)
        )
        .padding(.horizontal, ProviderRequestSheetMetrics.horizontalPadding)
        .padding(.bottom, ProviderRequestSheetMetrics.bottomBasinPadding)
      }
    }
  }
}

// MARK: - Blueprint 2: Decline reason picker (320pt)

struct ProviderDeclineReasonPickerSheet: View {
  @Binding var selectedReason: ProviderDeclineReason?
  @Binding var otherReasonText: String
  let onDecline: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @FocusState private var otherFieldFocused: Bool

  private let gridRows: [[ProviderDeclineReason]] = [
    [.scheduleConflict, .personalTimeOff],
    [.serviceMismatch, .other],
  ]

  private var canContinue: Bool {
    guard let selectedReason else { return false }
    if selectedReason == .other {
      return !otherReasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return true
  }

  private var sheetHeight: CGFloat {
    selectedReason == .other
      ? ProviderRequestSheetMetrics.declinePickerHeight + 56
      : ProviderRequestSheetMetrics.declinePickerHeight
  }

  var body: some View {
    ProviderRequestCompactSheetChrome(detentHeight: sheetHeight) {
      VStack(alignment: .leading, spacing: 0) {
        ScaledSheetText(
          text: "Select Reason for Decline",
          font: .system(size: 17, weight: .semibold),
          color: ProviderRequestSheetColors.titleText,
          lineLimit: 2
        )
        .padding(.horizontal, ProviderRequestSheetMetrics.horizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, 10)

        if selectedReason == .other {
          otherReasonEntry
            .padding(.horizontal, ProviderRequestSheetMetrics.horizontalPadding)
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
          VStack(spacing: 8) {
            ForEach(Array(gridRows.enumerated()), id: \.offset) { _, row in
              HStack(spacing: 8) {
                ForEach(row) { reason in
                  declineReasonCapsule(reason)
                }
              }
            }
          }
          .padding(.horizontal, ProviderRequestSheetMetrics.horizontalPadding)
          .transition(.opacity)
        }

        Spacer(minLength: 8)

        Button(action: onDecline) {
          Text("Decline")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: ProviderRequestSheetMetrics.buttonHeight)
        }
        .background(
          RoundedRectangle(cornerRadius: ProviderRequestSheetMetrics.buttonCornerRadius, style: .continuous)
            .fill(canContinue ? ProviderRequestSheetColors.lavaRed : ProviderRequestSheetColors.lavaRed.opacity(0.45))
        )
        .disabled(!canContinue)
        .padding(.horizontal, ProviderRequestSheetMetrics.horizontalPadding)
        .padding(.bottom, ProviderRequestSheetMetrics.bottomBasinPadding)
      }
      .animation(ProviderRequestSheetMetrics.sheetSpring, value: selectedReason)
    }
  }

  private var otherReasonEntry: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        withAnimation(ProviderRequestSheetMetrics.sheetSpring) {
          selectedReason = nil
          otherReasonText = ""
        }
        ProviderRequestSheetHaptics.selection()
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "chevron.left")
            .font(.system(size: 13, weight: .semibold))
          Text("Back to reasons")
            .font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(ProviderRequestSheetColors.bodyText)
      }
      .buttonStyle(.plain)

      Text("Describe why you’re declining")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(ProviderRequestSheetColors.titleText)

      TextField("Type your reason…", text: $otherReasonText, axis: .vertical)
        .lineLimit(3 ... 5)
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .foregroundStyle(ProviderRequestSheetColors.titleText)
        .padding(12)
        .frame(minHeight: 88, alignment: .topLeading)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(ProviderRequestSheetColors.capsuleFill(colorScheme: colorScheme, selected: false))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(ProviderRequestSheetColors.panelStroke(colorScheme: colorScheme), lineWidth: 1)
        )
        .focused($otherFieldFocused)
        .onAppear { otherFieldFocused = true }
    }
  }

  private func declineReasonCapsule(_ reason: ProviderDeclineReason) -> some View {
    let isSelected = selectedReason == reason
    return Button {
      withAnimation(ProviderRequestSheetMetrics.sheetSpring) {
        selectedReason = reason
        if reason != .other {
          otherReasonText = ""
        }
      }
      ProviderRequestSheetHaptics.selection()
    } label: {
      HStack(spacing: 6) {
        ScaledSheetText(
          text: reason.rawValue,
          font: .system(size: 13, weight: isSelected ? .semibold : .medium),
          color: isSelected ? ProviderRequestSheetColors.declineOrange : ProviderRequestSheetColors.bodyText,
          lineLimit: 2
        )
        Spacer(minLength: 0)
        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
          .font(.system(size: 14))
          .foregroundStyle(isSelected ? ProviderRequestSheetColors.declineOrange : ProviderRequestSheetColors.mutedText)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(ProviderRequestSheetColors.capsuleFill(colorScheme: colorScheme, selected: isSelected))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(
            isSelected ? ProviderRequestSheetColors.declineOrange.opacity(0.75) : ProviderRequestSheetColors.panelStroke(colorScheme: colorScheme),
            lineWidth: isSelected ? 1.5 : 1
          )
      )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Blueprint 3: Submit decline (280pt)

struct ProviderSubmitDeclineConfirmSheet: View {
  let customerName: String
  let onSubmit: () -> Void

  var body: some View {
    ProviderRequestCompactSheetChrome(detentHeight: ProviderRequestSheetMetrics.submitDeclineHeight) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 26))
            .foregroundStyle(ProviderRequestSheetColors.lavaRed)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 6) {
            ScaledSheetText(
              text: "Submit Request Rejection?",
              font: .system(size: 20, weight: .bold),
              color: ProviderRequestSheetColors.titleText,
              lineLimit: 2
            )
            ScaledSheetText(
              text: "This cancels the inquiry and alerts \(customerName) via SMS.",
              font: .system(size: 14, weight: .regular),
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
            .font(.system(size: 17, weight: .bold))
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

// MARK: - Haptics

enum ProviderRequestSheetHaptics {
  static func selection() {
    #if canImport(UIKit)
    UISelectionFeedbackGenerator().selectionChanged()
    #endif
  }
}

// MARK: - Copy helpers

extension RequestTriageItem {
  var confirmCustomerName: String {
    row.customerName ?? "this customer"
  }

  var approveScheduleSummary: String {
    if let wallClock = ProviderBookingScheduleParsing.displayWallClockTime(from: row) {
      let datePart = requestedStart.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
      return "\(datePart) · \(wallClock)"
    }
    return requestedStart.formatted(.dateTime.weekday(.abbreviated).hour().minute())
  }
}
