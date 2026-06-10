import SwiftUI

struct CampusSelectionView: View {
    @Binding var selectedCampus: Campus?
    @Binding var campuses: [Campus]
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    
    var filteredCampuses: [Campus] {
        if searchText.isEmpty {
            return campuses
        }
        return campuses.filter { campus in
            campus.name.localizedCaseInsensitiveContains(searchText) ||
            campus.city.localizedCaseInsensitiveContains(searchText) ||
            campus.state.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCampuses) { campus in
                    Button(action: {
                        selectedCampus = campus
                        dismiss()
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(campus.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(campus.displayLocation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search campuses")
            .navigationTitle("Select Campus")
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
}

