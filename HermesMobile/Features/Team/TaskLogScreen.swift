import SwiftUI

/// The raw worker log for a task, newest output at the bottom.
struct TaskLogScreen: View {
    let taskID: String

    @Environment(TeamStore.self) private var store
    @State private var log: KanbanTaskLog?
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let log, log.exists, !log.content.isEmpty {
                VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                    if log.truncated {
                        Text("Showing the end of a long log.")
                            .font(.caption)
                            .foregroundStyle(Design.Colors.textTertiary)
                    }
                    Text(log.content)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Design.Colors.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Design.Spacing.md)
            } else if let error {
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load the log", message: error)
            } else if log != nil {
                EmptyStateView(systemImage: "terminal", title: "No log yet", message: "The log appears once a worker picks up the task.")
            } else {
                ProgressView().tint(Design.Brand.accent).padding(.top, Design.Spacing.xxl)
            }
        }
        .background(Design.Colors.canvas)
        .navigationTitle("Worker log")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            log = try await store.log(for: taskID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Shows a task attachment: markdown/text inline, images previewed.
struct AttachmentSheet: View {
    let attachment: KanbanAttachment

    @Environment(TeamStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var payload: HermesFilePayload?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let data = payload?.data {
                        content(for: data)
                    } else if let error {
                        EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't open the file", message: error)
                    } else {
                        ProgressView().tint(Design.Brand.accent).padding(.top, Design.Spacing.xxl)
                    }
                }
                .padding(Design.Spacing.md)
            }
            .background(Design.Colors.canvas)
            .navigationTitle(attachment.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if let data = payload?.data, let text = String(data: data, encoding: .utf8) {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .task {
                do {
                    payload = try await store.attachment(attachment)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private func content(for data: Data) -> some View {
        if attachment.isImage, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        } else if let text = String(data: data, encoding: .utf8) {
            let ext = (attachment.filename as NSString).pathExtension.lowercased()
            if ["md", "markdown"].contains(ext) || attachment.contentType == "text/markdown" {
                MarkdownContentView(content: text, isStreaming: false)
                    .textSelection(.enabled)
            } else {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            EmptyStateView(systemImage: "doc", title: "Preview not available", message: "This file type can't be shown on the phone.")
        }
    }
}
