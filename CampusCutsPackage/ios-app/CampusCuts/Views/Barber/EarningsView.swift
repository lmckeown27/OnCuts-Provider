import SwiftUI

struct EarningsView: View {
    @StateObject private var viewModel = EarningsViewModel()
    @State private var selectedPeriod: TimePeriod = .week
    
    enum TimePeriod: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        case all = "All Time"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Period selector
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(TimePeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    // Total earnings card
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total Earnings")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text("$\(viewModel.totalEarnings)")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.green)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.green.opacity(0.3))
                        }
                        
                        Divider()
                        
                        HStack {
                            EarningsDetailItem(
                                label: "Available",
                                value: "$\(viewModel.availableBalance)",
                                color: .green
                            )
                            
                            Divider()
                            
                            EarningsDetailItem(
                                label: "Pending",
                                value: "$\(viewModel.pendingBalance)",
                                color: .orange
                            )
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Payout button
                    if viewModel.availableBalance > 10 {
                        Button(action: {
                            Task {
                                await viewModel.requestPayout()
                            }
                        }) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Label("Request Instant Payout", systemImage: "arrow.down.circle.fill")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .disabled(viewModel.isLoading)
                    }
                    
                    // Transaction history
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transaction History")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if viewModel.transactions.isEmpty {
                            Text("No transactions yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(viewModel.transactions) { transaction in
                                TransactionRowView(transaction: transaction)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Earnings")
            .refreshable {
                await viewModel.loadEarnings()
            }
            .task {
                await viewModel.loadEarnings()
            }
        }
    }
}

struct EarningsDetailItem: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .bold()
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TransactionRowView: View {
    let transaction: Transaction
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(.body)
                
                Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("$\(transaction.amount)")
                .font(.headline)
                .foregroundColor(.green)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct Transaction: Identifiable {
    let id: String
    let description: String
    let amount: Int
    let date: Date
    let status: String
}

@MainActor
class EarningsViewModel: ObservableObject {
    @Published var totalEarnings = 0
    @Published var availableBalance = 0
    @Published var pendingBalance = 0
    @Published var transactions: [Transaction] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let networkManager = NetworkManager.shared
    
    func loadEarnings() async {
        isLoading = true
        
        do {
            struct EarningsResponse: Codable {
                let success: Bool
                let data: EarningsData
            }
            
            struct EarningsData: Codable {
                let totalEarned: String
                let paidOut: String
                let pending: String
                let totalTransactions: String
                
                enum CodingKeys: String, CodingKey {
                    case totalEarned = "total_earned"
                    case paidOut = "paid_out"
                    case pending
                    case totalTransactions = "total_transactions"
                }
            }
            
            let response: EarningsResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.earnings,
                authenticated: true
            )
            
            totalEarnings = Int(Double(response.data.totalEarned) ?? 0)
            availableBalance = Int(Double(response.data.paidOut) ?? 0)
            pendingBalance = Int(Double(response.data.pending) ?? 0)
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func requestPayout() async {
        isLoading = true
        
        do {
            struct PayoutRequest: Codable {
                let amount: Int
            }
            
            let _: SuccessResponse = try await networkManager.request(
                endpoint: Constants.API.Endpoints.payout,
                method: "POST",
                body: PayoutRequest(amount: availableBalance * 100),
                authenticated: true
            )
            
            await loadEarnings()
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

#Preview {
    EarningsView()
}

