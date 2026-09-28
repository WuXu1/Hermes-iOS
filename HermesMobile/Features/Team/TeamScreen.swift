import SwiftUI

struct TeamScreen: View {
    var body: some View {
        EmptyStateView(systemImage: "person.3", title: "Team", message: "Coming together…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .canvasBackground()
            .navigationTitle("Team")
    }
}
