import SwiftUI

struct LibraryScreen: View {
    var body: some View {
        EmptyStateView(systemImage: "books.vertical", title: "Library", message: "Coming together…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .canvasBackground()
            .navigationTitle("Library")
    }
}
