import SwiftUI

struct DiscoveryView: View {
    @StateObject private var viewModel = BarberViewModel()
    @EnvironmentObject var authViewModel: AuthViewModel
    
    let columns = [
        GridItem(.flexible(), spacing: Constants.UI.Grid.spacing),
        GridItem(.flexible(), spacing: Constants.UI.Grid.spacing)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    ProgressView("Finding barbers...")
                } else if viewModel.filteredBarbers.isEmpty {
                    ContentUnavailableView(
                        "No Barbers Found",
                        systemImage: "scissors",
                        description: Text("Try adjusting your filters or check back later")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Filter section
                            FilterSectionView(viewModel: viewModel)
                            
                            // Barber grid
                            LazyVGrid(columns: columns, spacing: Constants.UI.Grid.spacing) {
                                ForEach(viewModel.filteredBarbers) { barber in
                                    NavigationLink(destination: BarberDetailView(barber: barber)) {
                                        BarberGridCard(barber: barber)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("Discover Barbers")
            .searchable(text: $viewModel.searchText, prompt: "Search by name or specialty")
            .refreshable {
                await viewModel.fetchBarbers(campusId: authViewModel.currentUser?.campusId)
            }
            .task {
                await viewModel.fetchBarbers(campusId: authViewModel.currentUser?.campusId)
            }
        }
    }
}

struct FilterSectionView: View {
    @ObservedObject var viewModel: BarberViewModel
    @State private var showingFilters = false
    
    var body: some View {
        HStack {
            Text("\(viewModel.filteredBarbers.count) barbers")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: {
                showingFilters.toggle()
            }) {
                Label("Filters", systemImage: "slider.horizontal.3")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal)
        .sheet(isPresented: $showingFilters) {
            FilterSheetView(viewModel: viewModel)
        }
    }
}

struct FilterSheetView: View {
    @ObservedObject var viewModel: BarberViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Rating") {
                    HStack {
                        Text("Minimum Rating")
                        Spacer()
                        Text(String(format: "%.1f★", viewModel.minRating))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $viewModel.minRating, in: 0...5, step: 0.5)
                }
                
                Section("Availability") {
                    Toggle("Instant Book Only", isOn: $viewModel.instantBookOnly)
                }
                
                Section {
                    Button("Reset Filters") {
                        viewModel.minRating = 0
                        viewModel.maxPrice = 100
                        viewModel.instantBookOnly = false
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct BarberGridCard: View {
    let barber: Barber
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Portfolio image or placeholder
            if let firstImage = barber.portfolio?.first?.url {
                AsyncImage(url: URL(string: firstImage)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                }
                .frame(height: 180)
                .clipped()
                .cornerRadius(Constants.UI.cornerRadius)
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 180)
                    
                    Image(systemName: "scissors")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                }
                .cornerRadius(Constants.UI.cornerRadius)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(barber.fullName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    
                    Text(barber.formattedRating)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("(\(barber.totalBookings))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let lowestPrice = barber.pricing.values.min() {
                    Text("From $\(Int(lowestPrice))")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                
                if barber.instantBook {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                        Text("Instant Book")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(Constants.UI.cornerRadius)
        .shadow(radius: 2)
    }
}

#Preview {
    DiscoveryView()
        .environmentObject(AuthViewModel())
}

