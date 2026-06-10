//
//  ConsumerHomeView.swift
//  CampusCutsModule
//
//  Main consumer view for browsing barbers and managing bookings.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

internal struct ConsumerHomeView: View {
    @StateObject var viewModel: ConsumerViewModel
    var liveDataSafetyMode: Bool = false
    @State private var selectedTab: Tab = .browse
    
    enum Tab: String, CaseIterable {
        case browse = "Browse"
        case bookings = "My Bookings"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if liveDataSafetyMode {
                    CampusCutsLiveDataModeBanner()
                }
                // Tab Picker
                tabPicker
                
                // Content based on tab
                Group {
                    switch selectedTab {
                    case .browse:
                        browseView
                    case .bookings:
                        bookingsView
                    }
                }
            }
            .navigationTitle("CampusCuts")
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
            await viewModel.loadBarbers()
            await viewModel.loadMyBookings()
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
    
    // MARK: - Tab Picker
    
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(tab.rawValue)
                            
                            if tab == .bookings && !viewModel.upcomingBookings.isEmpty {
                                Text("\(viewModel.upcomingBookings.count)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : .clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - Browse View
    
    private var browseView: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search barbers...", text: $viewModel.searchText)
            }
            .padding(12)
            .background(Color.platformGray6)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
            
            if viewModel.isLoading && viewModel.barbers.isEmpty {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                Spacer()
            } else if viewModel.filteredBarbers.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "scissors")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No barbers found")
                        .font(.headline)
                    Text("Try adjusting your search")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredBarbers) { barber in
                            Button {
                                Task {
                                    await viewModel.selectBarber(barber)
                                }
                            } label: {
                                BarberCardView(barber: barber)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await viewModel.loadBarbers()
                }
            }
        }
    }
    
    // MARK: - Bookings View
    
    private var bookingsView: some View {
        Group {
            if viewModel.isLoading && viewModel.myBookings.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                }
            } else if viewModel.myBookings.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("No bookings yet")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Book a haircut to get started!")
                        .foregroundStyle(.secondary)
                    
                    Button {
                        selectedTab = .browse
                    } label: {
                        Text("Browse Barbers")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 40)
                    
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Upcoming Section
                        if !viewModel.upcomingBookings.isEmpty {
                            Text("Upcoming")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(viewModel.upcomingBookings) { booking in
                                ConsumerBookingCard(booking: booking) {
                                    Task {
                                        await viewModel.cancelBooking(booking, reason: nil)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Past Section
                        if !viewModel.pastBookings.isEmpty {
                            Text("Past")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            
                            ForEach(viewModel.pastBookings) { booking in
                                ConsumerBookingCard(booking: booking, onCancel: nil)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .refreshable {
                    await viewModel.loadMyBookings()
                }
            }
        }
    }
}

// MARK: - Consumer Booking Card

internal struct ConsumerBookingCard: View {
    let booking: Booking
    let onCancel: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Barber Image
                AsyncImage(url: CampusCutsS3ImageURL.url(forStoredPath: booking.barberProfileImage)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(booking.barberBusinessName ?? booking.barberName ?? "Barber")
                        .font(.headline)
                    Text(booking.serviceName ?? "Haircut")
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
                Label("\(booking.startTime)", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            HStack {
                if let price = booking.servicePrice {
                    Text("$\(String(format: "%.2f", price))")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                // Cancel button for pending/accepted bookings
                if let cancel = onCancel, (booking.status == .pending || booking.status == .accepted) {
                    Button(role: .destructive) {
                        cancel()
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
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
        let parts = dateString.split(separator: "-")
        if parts.count == 3 {
            return "\(parts[1])/\(parts[2])"
        }
        return dateString
    }
}

