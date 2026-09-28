import SwiftUI

struct AutomationsScreen: View {
    var body: some View {
        EmptyStateView(systemImage: "clock.arrow.2.circlepath", title: "Automations", message: "Coming together…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .canvasBackground()
            .navigationTitle("Automations")
    }
}
