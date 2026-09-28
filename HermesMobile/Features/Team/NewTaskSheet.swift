import SwiftUI

struct NewTaskSheet: View {
    var prefill: KanbanTaskDraft?

    var body: some View {
        EmptyStateView(systemImage: "plus", title: "New task", message: "Coming together…")
    }
}
