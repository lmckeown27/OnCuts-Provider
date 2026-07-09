import SwiftUI

struct AllReviewsView: View {
    let barberId: String
    @StateObject private var viewModel = ReviewViewModel()
    
    var body: some View {
        List {
            ForEach(viewModel.reviews) { review in
                ReviewCardView(review: review)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("All Reviews")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.fetchBarberReviews(barberId: barberId)
        }
    }
}

struct ReviewCardView: View {
    let review: Review
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Reviewer avatar
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(review.clientInitials)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.clientFullName ?? "Anonymous")
                        .font(.subheadline)
                        .bold()
                    
                    Text(review.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Rating stars (would use actual rating from blockchain)
                HStack(spacing: 2) {
                    ForEach(0..<5) { _ in
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
            }
            
            Text(review.reviewText)
                .font(.body)
                .foregroundColor(.primary)
            
            // Review images if any
            if let images = review.images, !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images, id: \.self) { imageUrl in
                            AsyncImage(url: URL(string: imageUrl)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(8)
                        }
                    }
                }
            }
            
            // Helpful button
            Button(action: {
                // Mark as helpful
            }) {
                HStack {
                    Image(systemName: "hand.thumbsup")
                        .font(.caption)
                    Text("Helpful (\(review.helpfulCount))")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct SubmitReviewView: View {
    let bookingId: Int
    let barberName: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ReviewViewModel()
    
    @State private var rating = 5
    @State private var reviewText = ""
    @State private var selectedImages: [PhotosPickerItem] = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Rating") {
                    HStack {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: {
                                rating = star
                            }) {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.title)
                                    .foregroundColor(star <= rating ? .yellow : .gray)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
                
                Section("Your Review") {
                    TextField("Share your experience with \(barberName)", text: $reviewText, axis: .vertical)
                        .lineLimit(5...10)
                }
                
                Section("Photos (Optional)") {
                    PhotosPicker(
                        selection: $selectedImages,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                    }
                    
                    if !selectedImages.isEmpty {
                        Text("\(selectedImages.count) photo(s) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button(action: {
                        Task {
                            await submitReview()
                        }
                    }) {
                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                Text("Submitting...")
                            }
                        } else {
                            Text("Submit Review")
                                .frame(maxWidth: .infinity)
                                .bold()
                        }
                    }
                    .disabled(reviewText.isEmpty || viewModel.isLoading)
                }
            }
            .navigationTitle("Write Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func submitReview() async {
        let success = await viewModel.submitReview(
            bookingId: bookingId,
            rating: rating,
            reviewText: reviewText,
            images: nil // Would upload images first
        )
        
        if success {
            dismiss()
        }
    }
}

@MainActor
class ReviewViewModel: ObservableObject {
    @Published var reviews: [Review] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let networkManager = NetworkManager.shared
    
    func fetchBarberReviews(barberId: String, page: Int = 1) async {
        isLoading = true
        
        do {
            let response: ReviewResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.barberReviews(barberId: barberId) + "?page=\(page)",
                authenticated: false
            )
            
            reviews = response.data
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func submitReview(bookingId: Int, rating: Int, reviewText: String, images: [String]?) async -> Bool {
        isLoading = true
        
        do {
            let request = SubmitReviewRequest(
                bookingId: bookingId,
                rating: rating,
                reviewText: reviewText,
                images: images
            )
            
            let _: SuccessResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.reviews,
                method: "POST",
                body: request,
                authenticated: true
            )
            
            isLoading = false
            return true
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return false
        }
    }
}

#Preview {
    ReviewCardView(review: Review(
        id: "1",
        blockchainReviewId: 1,
        bookingId: 1,
        reviewText: "Great haircut! Very professional and friendly. Would definitely recommend.",
        images: nil,
        helpfulCount: 5,
        createdAt: Date(),
        clientFirstName: "John",
        clientLastName: "Smith"
    ))
    .padding()
}

