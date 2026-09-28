import SwiftUI

/// App-wide transient confirmations ("Assigned to Researcher", "Saved").
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let systemImage: String
        let actionTitle: String?
        let isError: Bool

        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    private(set) var current: Toast?
    private var action: (@MainActor () -> Void)?
    private var dismissTask: Task<Void, Never>?

    func show(
        _ message: String,
        systemImage: String = "checkmark.circle.fill",
        actionTitle: String? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        present(Toast(message: message, systemImage: systemImage, actionTitle: actionTitle, isError: false), action: action)
    }

    func showError(_ message: String) {
        present(Toast(message: message, systemImage: "exclamationmark.triangle.fill", actionTitle: nil, isError: true), action: nil)
    }

    func performAction() {
        action?()
        dismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
        action = nil
    }

    private func present(_ toast: Toast, action: (@MainActor () -> Void)?) {
        dismissTask?.cancel()
        current = toast
        self.action = action
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(toast.isError ? 4 : 3))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}

private struct ToastOverlay: ViewModifier {
    let center: ToastCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = center.current {
                HStack(spacing: Design.Spacing.xs) {
                    Image(systemName: toast.systemImage)
                        .foregroundStyle(toast.isError ? Design.Colors.danger : Design.Colors.success)
                    Text(toast.message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Design.Colors.textPrimary)
                        .lineLimit(2)
                    if let actionTitle = toast.actionTitle {
                        Button(actionTitle) { center.performAction() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Design.Brand.accent)
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
                .adaptiveGlass(in: .capsule)
                .padding(.bottom, 96)
                .padding(.horizontal, Design.Spacing.md)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { center.dismiss() }
                .id(toast.id)
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(Design.Motion.standard, value: center.current)
    }
}

extension View {
    func toastOverlay(_ center: ToastCenter) -> some View {
        modifier(ToastOverlay(center: center))
    }
}
