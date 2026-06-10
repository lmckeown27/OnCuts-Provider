//
//  CampusCutsHomeView.swift
//  CampusCutsModule
//
//  Main entry view that routes to Consumer or Barber views based on role.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

internal struct CampusCutsHomeView: View {
    @StateObject var viewModel: CampusCutsHomeViewModel
    var liveDataSafetyMode: Bool = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.barbers.isEmpty {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    mainContent
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
            await viewModel.loadInitialData()
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
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading barbers...")
                .foregroundStyle(.secondary)
        }
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Text("We couldn’t load right now")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task {
                    await viewModel.loadInitialData()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            if liveDataSafetyMode {
                CampusCutsLiveDataModeBanner()
            }
            // Campus Picker
            if !viewModel.campuses.isEmpty {
                campusPicker
            }
            
            // Search Bar
            searchBar
            
            // Barber List
            if viewModel.filteredBarbers.isEmpty {
                emptyStateView
            } else {
                barberList
            }
        }
    }
    
    private var campusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.campuses) { campus in
                    Button {
                        Task {
                            await viewModel.selectCampus(campus)
                        }
                    } label: {
                        Text(campus.name)
                            .font(.subheadline)
                            .fontWeight(viewModel.selectedCampus?.id == campus.id ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                viewModel.selectedCampus?.id == campus.id
                                    ? Color.accentColor
                                    : Color.platformGray5
                            )
                            .foregroundStyle(
                                viewModel.selectedCampus?.id == campus.id
                                    ? .white
                                    : .primary
                            )
                            .clipShape(Capsule())
                    }
                }
            }
            .padding()
        }
        .background(Color.platformBackground)
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search barbers...", text: $viewModel.searchText)
        }
        .padding(12)
        .background(Color.platformGray6)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "scissors")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No barbers found")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Try selecting a different campus or adjusting your search")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
    
    private var barberList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredBarbers) { barber in
                    BarberCardView(barber: barber)
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.refreshBarbers()
        }
    }
}

// MARK: - Barber Card

internal struct BarberCardView: View {
    let barber: Barber

    var body: some View {
        HStack(spacing: 16) {
            // Profile Image
            AsyncImage(url: CampusCutsS3ImageURL.url(forStoredPath: barber.profileImageUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(barber.businessName)
                    .font(.headline)
                
                if let bio = barber.bio {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 12) {
                    if let rating = barber.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    
                    if let count = barber.completedBookings {
                        Text("\(count) \(count == 1 ? "cut" : "cuts")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Available indicator
            if barber.isAvailableNow == true {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
            }
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.platformBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

