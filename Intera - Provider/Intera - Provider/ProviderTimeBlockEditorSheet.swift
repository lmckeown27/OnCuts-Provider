import SwiftUI

/// One-off **barber time block** editor (parity with web `BlockTimeModal` / Manage availability).
struct ProviderTimeBlockEditorSheet: View {
    let barberId: String?
    let navigationTitle: String
    let confirmButtonTitle: String
    let onSaved: (BarberTimeBlockDTO?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var start: Date
    @State private var end: Date
    @State private var reason: String = ""
    @State private var isSaving = false
    @State private var errorText: String?

    init(
        barberId: String?,
        navigationTitle: String = "Add time block",
        confirmButtonTitle: String = "Save",
        initialDate: Date? = nil,
        initialStart: Date? = nil,
        initialEnd: Date? = nil,
        onSaved: @escaping (BarberTimeBlockDTO?) -> Void
    ) {
        self.barberId = barberId
        self.navigationTitle = navigationTitle
        self.confirmButtonTitle = confirmButtonTitle
        self.onSaved = onSaved
        let cal = Calendar(identifier: .gregorian)
        let day0 = initialDate.map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: .now)
        _date = State(initialValue: day0)
        let s = initialStart ?? Self.time(on: day0, hour: 9, calendar: cal)
        let e = initialEnd ?? Self.time(on: day0, hour: 10, calendar: cal)
        _start = State(initialValue: s)
        _end = State(initialValue: e)
    }

    private static func time(on day: Date, hour: Int, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Date", selection: $date, in: Date().addingTimeInterval(-86_400)..., displayedComponents: .date)
                }
                Section("Time") {
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                }
                Section("Reason (optional)") {
                    TextField("Vacation, lunch, appointment…", text: $reason, axis: .vertical)
                        .lineLimit(1 ... 3)
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .providerLavaIntegratedFormSurface()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : confirmButtonTitle) {
                        Task { await save() }
                    }
                    .disabled(isSaving || barberId == nil)
                }
            }
        }
        .foregroundStyle(Color.lavaShellCream)
        .tint(.providerOlive)
        .providerLavaScreenChrome()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() async {
        guard let barberId else { return }
        guard start < end else {
            errorText = "End time must be after start time."
            return
        }
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        let dateString = f.string(from: date)
        let startString = Self.hhmmFromDate(start)
        let endString = Self.hhmmFromDate(end)
        do {
            let block = try await ProviderAvailabilityManagementService.createTimeBlock(
                barberId: barberId,
                blockDate: dateString,
                startTime: startString,
                endTime: endString,
                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reason.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            onSaved(block)
            dismiss()
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "Could not save time block."
        }
    }

    private static func hhmmFromDate(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return String(format: "%02d:%02d", h, m)
    }
}
