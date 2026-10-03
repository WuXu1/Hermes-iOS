import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    @Binding var pendingAttachments: [PendingAttachment]
    let isStreaming: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void
    let onAttach: () -> Void
    let onSlashCommand: (SlashCommand, String?) -> Void
    /// When set, sending creates a kanban task for this role instead of a chat message.
    var assignee: Binding<String?> = .constant(nil)
    var assignableRoles: [HermesProfile] = []

    @Environment(ChatStore.self) private var chatStore
    @Environment(AgentStore.self) private var agents
    @Environment(ToastCenter.self) private var toasts

    @State private var recorder = VoiceNoteRecorder()
    @State private var isTranscribing = false

    private var assignedStyle: RoleStyle? {
        assignee.wrappedValue.map { RoleStyle.forProfile($0) }
    }

    private var canSend: Bool {
        if assignee.wrappedValue != nil {
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !pendingAttachments.isEmpty
        let hasRunnableSlashCommand = isSlashMode && hasText && text.trimmingCharacters(in: .whitespacesAndNewlines) != "/" && !hasAttachments
        return hasRunnableSlashCommand || ((hasText || hasAttachments) && !isSlashMode)
    }

    private var isSlashMode: Bool {
        assignee.wrappedValue == nil && text.hasPrefix("/")
    }

    /// Parses the command and any trailing argument from the text field.
    private var parsedSlashInput: (command: String, argument: String?) {
        let raw = String(text.dropFirst()).lowercased()
        let parts = raw.split(separator: " ", maxSplits: 1)
        let cmd = parts.first.map(String.init) ?? raw
        let arg = parts.count > 1 ? String(parts[1]) : nil
        return (cmd, arg)
    }

    /// Uses the dynamic catalog from ChatStore (fetched from the Hermes host).
    /// Falls back to the built-in list if the catalog hasn't loaded yet.
    private var filteredCommands: [SlashCommand] {
        let query = parsedSlashInput.command.lowercased()
        let argument = parsedSlashInput.argument?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = chatStore.commandCatalog.filter(\.showInAutocomplete)

        if query.isEmpty {
            return all.filter { $0.suggestedArgument == nil }
        }

        if let exact = all.first(where: { $0.name == query && $0.suggestedArgument == nil }), exact.acceptsArgument {
            let argumentSuggestions = all.filter { command in
                command.name == query
                    && command.suggestedArgument != nil
                    && (argument == nil
                        || argument!.isEmpty
                        || command.suggestedArgument!.lowercased().hasPrefix(argument!))
            }
            if !argumentSuggestions.isEmpty {
                return argumentSuggestions
            }
            return [exact]
        }

        return all.filter {
            $0.suggestedArgument == nil && $0.name.hasPrefix(query)
        }
    }

    var body: some View {
        VStack(spacing: Design.Spacing.xs) {
            if isSlashMode && !filteredCommands.isEmpty {
                SlashCommandMenu(commands: filteredCommands) { command in
                    let arg = command.suggestedArgument ?? (command.acceptsArgument ? parsedSlashInput.argument : nil)
                    text = ""
                    onSlashCommand(command, arg)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Composer container
            VStack(spacing: 0) {
                // Attachment preview strip
                if !pendingAttachments.isEmpty {
                    attachmentPreviewStrip
                }

                if let style = assignedStyle {
                    assignmentChip(style)
                }

                // Text input area
                TextField(
                    recorder.isRecording ? "Recording..." : assignedStyle.map { "Describe the task for \(agents.label(for: $0.name))" } ?? "Reply to Hermes",
                    text: $text,
                    axis: .vertical
                )
                    .accessibilityIdentifier("chat.composer")
                    .accessibilityLabel("Reply to Hermes")
                    .font(Design.Typography.body)
                    .foregroundStyle(Design.Colors.foreground)
                    .lineLimit(1...5)
                    .focused(isFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend {
                            handlePrimaryAction()
                        }
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.top, pendingAttachments.isEmpty ? Design.Spacing.sm : Design.Spacing.xs)
                    .padding(.bottom, Design.Spacing.xs)

                // Bottom action bar
                HStack(spacing: Design.Spacing.xs) {
                    // + Attachment button
                    Button(action: onAttach) {
                        Image(systemName: "plus")
                            .font(.system(size: Design.Size.iconMedium, weight: .medium))
                            .foregroundStyle(Design.Colors.secondaryForeground)
                            .frame(width: 36, height: 36)
                            .background(Design.Colors.surface)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Add attachment")
                    .disabled(assignee.wrappedValue != nil)

                    if !assignableRoles.isEmpty {
                        assignMenu
                    }

                    Spacer()

                    // Voice note button
                    if !isStreaming {
                        Button {
                            toggleVoiceNote()
                        } label: {
                            if isTranscribing {
                                ProgressView()
                                    .frame(width: 36, height: 36)
                            } else if recorder.isRecording {
                                HStack(spacing: 4) {
                                    Image(systemName: "stop.fill")
                                    Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern: .minuteSecond)))
                                        .font(.caption.monospacedDigit())
                                }
                                .font(.system(size: Design.Size.iconMedium, weight: .medium))
                                .foregroundStyle(.red)
                                .padding(.horizontal, Design.Spacing.sm)
                                .frame(height: 36)
                                .background(Design.Colors.surface)
                                .clipShape(Capsule())
                            } else {
                                Image(systemName: "mic")
                                    .font(.system(size: Design.Size.iconMedium, weight: .medium))
                                    .foregroundStyle(Design.Colors.secondaryForeground)
                                    .frame(width: 36, height: 36)
                            }
                        }
                        .disabled(isTranscribing)
                        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Record voice note")
                    }

                    // Send / Stop button
                    actionButton
                }
                .padding(.horizontal, Design.Spacing.sm)
                .padding(.bottom, Design.Spacing.sm)
            }
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: Design.CornerRadius.xxl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.CornerRadius.xxl, style: .continuous)
                    .strokeBorder(assignedStyle?.color.opacity(0.6) ?? .clear, lineWidth: 1.2)
            )
            .padding(.horizontal, Design.Spacing.md)
            .padding(.bottom, Design.Spacing.sm)
        }
        .animation(Design.Motion.quickResponse, value: assignee.wrappedValue)
        .animation(Design.Motion.quickResponse, value: isSlashMode)
        .animation(Design.Motion.quickResponse, value: isStreaming)
        .animation(Design.Motion.quickResponse, value: canSend)
    }

    // MARK: - Attachment Preview Strip

    private var attachmentPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.sm) {
                ForEach(pendingAttachments) { attachment in
                    attachmentThumbnail(attachment)
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.top, Design.Spacing.sm)
            .padding(.bottom, Design.Spacing.xxs)
        }
    }

    private func attachmentThumbnail(_ attachment: PendingAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbData = attachment.thumbnailData,
                   let uiImage = UIImage(data: thumbData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // File icon fallback
                    VStack(spacing: 4) {
                        Image(systemName: fileIcon(for: attachment.mimeType))
                            .font(.system(size: 20))
                            .foregroundStyle(Design.Colors.secondaryForeground)
                        Text(attachment.fileName)
                            .font(Design.Typography.caption)
                            .foregroundStyle(Design.Colors.secondaryForeground)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Design.Colors.surface)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Design.CornerRadius.sm)
                    .stroke(Design.Colors.divider, lineWidth: 1)
            )

            // Remove button
            Button {
                withAnimation(Design.Motion.quickResponse) {
                    pendingAttachments.removeAll { $0.id == attachment.id }
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Design.Colors.foreground)
                    .background(Circle().fill(Design.Colors.background).padding(2))
            }
            .offset(x: 6, y: -6)
        }
    }

    private func fileIcon(for mimeType: String) -> String {
        PendingAttachment.symbolName(forMimeType: mimeType)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isStreaming {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Design.Colors.foreground)
                    .frame(width: 36, height: 36)
                    .background(Design.Colors.surface)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Stop generating")
        } else if canSend {
            Button(action: handlePrimaryAction) {
                Image(systemName: assignedStyle == nil ? "arrow.up" : "person.fill.checkmark")
                    .font(.system(size: assignedStyle == nil ? 16 : 14, weight: .bold))
                    .foregroundStyle(Design.Colors.background)
                    .frame(width: 36, height: 36)
                    .background(assignedStyle?.color ?? Design.Brand.accent)
                    .clipShape(Circle())
            }
            .accessibilityLabel(assignedStyle.map { "Assign to \(agents.label(for: $0.name))" } ?? "Send message")
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Assign to a role

    private var assignMenu: some View {
        Menu {
            Section("Give this to…") {
                ForEach(assignableRoles) { profile in
                    let style = RoleStyle.forProfile(profile.name)
                    Button {
                        assignee.wrappedValue = profile.name
                        isFocused.wrappedValue = true
                    } label: {
                        Label(agents.label(for: profile.name), systemImage: style.symbol)
                    }
                }
            }
            if assignee.wrappedValue != nil {
                Button("Back to chat", systemImage: "bubble.left") { assignee.wrappedValue = nil }
            }
        } label: {
            Image(systemName: assignedStyle?.symbol ?? "person.badge.plus")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(assignedStyle?.color ?? Design.Colors.secondaryForeground)
                .frame(width: 36, height: 36)
                .background(Design.Colors.surface)
                .clipShape(Circle())
        }
        .accessibilityLabel("Assign to a team role")
        .accessibilityIdentifier("chat.assign")
    }

    private func assignmentChip(_ style: RoleStyle) -> some View {
        HStack(spacing: Design.Spacing.xxs) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2.weight(.bold))
            Text("New task for \(agents.label(for: style.name))")
                .font(.caption.weight(.semibold))
            Button {
                assignee.wrappedValue = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .accessibilityLabel("Cancel assignment")
        }
        .foregroundStyle(style.color)
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, 5)
        .background(Capsule().fill(style.color.opacity(0.14)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.sm)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Voice notes

    private func toggleVoiceNote() {
        if recorder.isRecording {
            let audio: Data
            do { audio = try recorder.stop() } catch {
                toasts.showError(error.localizedDescription)
                return
            }
            isTranscribing = true
            Task {
                defer { isTranscribing = false }
                do {
                    let transcript = try await chatStore.transcribe(audio)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !transcript.isEmpty else {
                        toasts.showError("No speech was picked up.")
                        return
                    }
                    let base = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    text = base.isEmpty ? "🎙️ \(transcript)" : "\(base) 🎙️ \(transcript)"
                } catch {
                    toasts.showError(error.localizedDescription)
                }
            }
        } else {
            Task {
                do { try await recorder.start() } catch { toasts.showError(error.localizedDescription) }
            }
        }
    }

    private func handlePrimaryAction() {
        onSend()
    }
}
