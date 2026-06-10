import SwiftUI

struct BarberDetailView: View {
    let barber: Barber
    @State private var selectedService: String?
    @State private var showingBookingFlow = false
    @StateObject private var reviewViewModel = ReviewViewModel()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with profile image
                BarberHeaderView(barber: barber)
                
                // Quick stats
                StatsRowView(barber: barber)
                
                Divider()
                
                // Services & Pricing
                ServicesPricingView(barber: barber, selectedService: $selectedService)
                
                Divider()
                
                // Portfolio
                if let portfolio = barber.portfolio, !portfolio.isEmpty {
                    PortfolioGalleryView(portfolio: portfolio)
                    Divider()
                }
                
                // Bio
                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .font(.headline)
                    
                    Text(barber.bio)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                Divider()
                
                // Reviews
                ReviewsSectionView(barberId: barber.id, viewModel: reviewViewModel)
            }
        }
        .navigationTitle(barber.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingBookingFlow = true
                }) {
                    Label("Book Now", systemImage: "calendar.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingBookingFlow) {
            BookingFlowView(barber: barber, selectedService: selectedService)
        }
        .task {
            await reviewViewModel.fetchBarberReviews(barberId: barber.id)
        }
    }
}

struct BarberHeaderView: View {
    let barber: Barber
    
    var body: some View {
        VStack(spacing: 12) {
            // Profile image
            if let imageUrl = barber.profileImageUrl {
                AsyncImage(url: URL(string: imageUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 120, height: 120)
                    
                    Text(barber.fullName.prefix(2).uppercased())
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.blue)
                }
            }
            
            VStack(spacing: 4) {
                Text(barber.fullName)
                    .font(.title2)
                    .bold()
                
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text(barber.formattedRating)
                        .bold()
                    Text("(\(barber.totalBookings) cuts)")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                
                if barber.instantBook {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                        Text("Instant Book Available")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct StatsRowView: View {
    let barber: Barber
    
    var body: some View {
        HStack(spacing: 0) {
            StatItemView(
                icon: "scissors",
                value: "\(barber.totalBookings)",
                label: "Cuts"
            )
            
            Divider()
            
            if let years = barber.yearsExperience {
                StatItemView(
                    icon: "calendar",
                    value: "\(years)",
                    label: "Years"
                )
                Divider()
            }
            
            if let responseTime = barber.averageResponseTime {
                StatItemView(
                    icon: "clock",
                    value: "\(responseTime)m",
                    label: "Response"
                )
            }
        }
        .padding(.horizontal)
    }
}

struct StatItemView: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.headline)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct ServicesPricingView: View {
    let barber: Barber
    @Binding var selectedService: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Services & Pricing")
                .font(.headline)
                .padding(.horizontal)
            
            ForEach(Array(barber.pricing.keys.sorted()), id: \.self) { service in
                Button(action: {
                    selectedService = service
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(service)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            // You could add service duration here if available
                        }
                        
                        Spacer()
                        
                        Text("$\(Int(barber.pricing[service] ?? 0))")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(
                        selectedService == service ?
                            Color.blue.opacity(0.1) :
                            Color(.secondarySystemBackground)
                    )
                    .cornerRadius(Constants.UI.cornerRadius)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct PortfolioGalleryView: View {
    let portfolio: [PortfolioImage]
    @State private var selectedImage: PortfolioImage?
    
    let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Portfolio")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(120))], spacing: 8) {
                    ForEach(portfolio, id: \.displayId) { image in
                        Button(action: {
                            selectedImage = image
                        }) {
                            AsyncImage(url: URL(string: image.url)) { img in
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 120, height: 120)
                            .clipped()
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .sheet(item: $selectedImage) { image in
            PortfolioImageDetailView(image: image)
        }
    }
}

struct PortfolioImageDetailView: View {
    let image: PortfolioImage
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                AsyncImage(url: URL(string: image.url)) { img in
                    img
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
                
                if let caption = image.caption {
                    Text(caption)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ReviewsSectionView: View {
    let barberId: String
    @ObservedObject var viewModel: ReviewViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reviews")
                    .font(.headline)
                
                Spacer()
                
                if !viewModel.reviews.isEmpty {
                    NavigationLink(destination: AllReviewsView(barberId: barberId)) {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal)
            
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if viewModel.reviews.isEmpty {
                Text("No reviews yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(viewModel.reviews.prefix(3)) { review in
                    ReviewCardView(review: review)
                        .padding(.horizontal)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        BarberDetailView(barber: Barber(
            id: "1",
            userId: "user1",
            bio: "Professional barber with 5 years experience",
            profileImageUrl: nil,
            pricing: ["Haircut": 25, "Fade": 30, "Beard Trim": 15],
            instantBook: true,
            averageResponseTime: 15,
            totalEarnings: 5000,
            totalBookings: 150,
            averageRating: 4.8,
            yearsExperience: 5,
            firstName: "John",
            lastName: "Doe",
            aptosAddress: "0x123",
            campusId: 1,
            portfolio: []
        ))
    }
}

