//
//  BarberDashboardView.swift
//  CampusCutsModule
//
//  Dashboard view for barbers to manage their bookings.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

internal struct BarberDashboardView: View {
    @StateObject var viewModel: BarberDashboardViewModel
    var liveDataSafetyMode: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if liveDataSafetyMode {
                    CampusCutsLiveDataModeBanner()
                }
                // Tab Picker
                tabPicker
                
                // Content
                if viewModel.isLoading && viewModel.currentBookings.isEmpty {
                    loadingView
                } else if viewModel.currentBookings.isEmpty {
                    emptyStateView
                } else {
                    bookingsList
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    profileMenu
                }
                #else
                ToolbarItem(placement: .automatic) {
                    profileMenu
                }
                #endif
            }
        }
        .task {
            await viewModel.loadBookings()
        }
    }
    
    private var profileMenu: some View {
        Menu {
            Button(role: .destructive) {
                viewModel.logout()
            } label: {
                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(.primary)
        }
    }
    
    // MARK: - Subviews
    
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(BarberDashboardViewModel.DashboardTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                            
                            if tab == .pending && viewModel.pendingCount > 0 {
                                Text("\(viewModel.pendingCount)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(viewModel.selectedTab == tab ? .semibold : .regular)
                        .foregroundStyle(viewModel.selectedTab == tab ? .primary : .secondary)
                        
                        Rectangle()
                            .fill(viewModel.selectedTab == tab ? Color.accentColor : .clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading bookings...")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No \(viewModel.selectedTab.rawValue.lowercased()) bookings")
                .font(.title2)
                .fontWeight(.semibold)
            Text("When you have bookings, they'll appear here")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
    
    private var bookingsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.currentBookings) { booking in
                    BookingCardView(
                        booking: booking,
                        showActions: viewModel.selectedTab == .pending,
                        onAccept: {
                            Task { await viewModel.acceptBooking(booking) }
                        },
                        onReject: {
                            Task { await viewModel.rejectBooking(booking) }
                        },
                        onComplete: viewModel.selectedTab == .upcoming ? {
                            Task { await viewModel.completeBooking(booking) }
                        } : nil
                    )
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.loadBookings()
        }
    }
}

// MARK: - Booking Card

internal struct BookingCardView: View {
    let booking: Booking
    let showActions: Bool
    let onAccept: (() -> Void)?
    let onReject: (() -> Void)?
    let onComplete: (() -> Void)?
    
    init(
        booking: Booking,
        showActions: Bool = false,
        onAccept: (() -> Void)? = nil,
        onReject: (() -> Void)? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.booking = booking
        self.showActions = showActions
        self.onAccept = onAccept
        self.onReject = onReject
        self.onComplete = onComplete
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(booking.consumerName ?? "Customer")
                        .font(.headline)
                    Text(booking.serviceName ?? "Service")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                statusBadge
            }
            
            Divider()
            
            // Details
            HStack(spacing: 16) {
                Label(formatDate(booking.bookingDate), systemImage: "calendar")
                Label("\(booking.startTime) - \(booking.endTime)", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            if let price = booking.servicePrice {
                HStack {
                    Text("$\(String(format: "%.2f", price))")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    if let tip = booking.tipAmount, tip > 0 {
                        Text("+ $\(String(format: "%.2f", tip)) tip")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            
            // Actions
            if showActions, let accept = onAccept, let reject = onReject {
                HStack(spacing: 12) {
                    Button {
                        reject()
                    } label: {
                        Text("Decline")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    
                    Button {
                        accept()
                    } label: {
                        Text("Accept")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            if let complete = onComplete {
                Button {
                    complete()
                } label: {
                    Text("Mark Complete")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(Color.platformBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var statusBadge: some View {
        Text(booking.status.rawValue.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }
    
    private var statusColor: Color {
        switch booking.status {
        case .pending: return .orange
        case .accepted: return .blue
        case .completed: return .green
        case .cancelled, .rejected: return .red
        case .noShow: return .gray
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        // Simple date formatting - could be enhanced
        let parts = dateString.split(separator: "-")
        if parts.count == 3 {
            return "\(parts[1])/\(parts[2])"
        }
        return dateString
    }
}

