import SwiftUI

/// Create an automation from a Hermes blueprint or from scratch.
struct NewAutomationSheet: View {
    var initialBlueprintKey: String?

    @Environment(AutomationsStore.self) private var store
    @Environment(TeamStore.self) private var teamStore
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable {
        case templates = "Templates"
        case custom = "Custom"
    }

    private enum Cadence: String, CaseIterable, Identifiable {
        case daily = "Daily"
        case weekdays = "Weekdays"
        case weekly = "Weekly"
        case hourly = "Hourly"
        case custom = "Cron"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .templates
    @State private var blueprint: CronBlueprint?
    @State private var values: [String: String] = [:]

    @State private var name = ""
    @State private var prompt = ""
    @State private var cadence: Cadence = .daily
    @State private var time = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var weekday = 1
    @State private var customCron = "0 8 * * *"
    @State private var profile = RoleStyle.defaultProfileName
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    if blueprint == nil {
                        Picker("Mode", selection: $mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                    }

                    switch (mode, blueprint) {
                    case (_, .some(let blueprint)):
                        blueprintForm(blueprint)
                    case (.templates, nil):
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Design.Spacing.sm) {
                            ForEach(store.blueprints) { item in
                                BlueprintCard(blueprint: item) { select(item) }
                            }
                        }
                    case (.custom, nil):
                        customForm
                    }
                }
                .padding(Design.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Design.Colors.canvas)
            .navigationTitle(blueprint?.title ?? "New automation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if blueprint != nil && initialBlueprintKey == nil {
                        Button("Back") { withAnimation(Design.Motion.standard) { blueprint = nil } }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else if blueprint != nil || mode == .custom {
                        Button("Create", action: submit)
                            .disabled(!canSubmit)
                            .accessibilityIdentifier("automation.create")
                    }
                }
            }
            .task {
                if store.blueprints.isEmpty { await store.refresh() }
                if let key = initialBlueprintKey, let match = store.blueprints.first(where: { $0.key == key }) {
                    select(match)
                }
            }
        }
    }

    // MARK: Blueprint form

    private func blueprintForm(_ blueprint: CronBlueprint) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            Text(blueprint.description)
                .font(.subheadline)
                .foregroundStyle(Design.Colors.textSecondary)
            VStack(spacing: 0) {
                ForEach(blueprint.fields.filter { !$0.isDelivery }, id: \.name) { field in
                    fieldRow(field)
                    if field.name != blueprint.fields.filter({ !$0.isDelivery }).last?.name {
                        Divider().overlay(Design.Colors.hairline)
                    }
                }
            }
            .cardSurface()
            if let human = blueprint.scheduleHuman {
                Label("Runs \(human)", systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(Design.Colors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: CronBlueprintField) -> some View {
        let binding = Binding(get: { values[field.name] ?? "" }, set: { values[field.name] = $0 })
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            if field.type == "time" {
                DatePicker(field.label, selection: timeBinding(binding), displayedComponents: .hourAndMinute)
                    .font(.subheadline.weight(.medium))
            } else if field.isChoice {
                HStack {
                    Text(field.label).font(.subheadline.weight(.medium))
                    Spacer()
                    Picker(field.label, selection: binding) {
                        ForEach(field.options, id: \.self) { option in
                            Text(Self.optionLabel(option, field: field)).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Design.Brand.accent)
                }
            } else {
                Text(field.label).font(.subheadline.weight(.medium))
                TextField(field.defaultValue ?? "", text: binding, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(Design.Colors.textPrimary)
            }
            if let help = field.help, !help.isEmpty, field.type != "time" {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(Design.Colors.textTertiary)
            }
        }
        .padding(Design.Spacing.md)
    }

    private static func optionLabel(_ option: String, field: CronBlueprintField) -> String {
        if field.name.hasSuffix("_min"), let minutes = Int(option) {
            return minutes % 60 == 0 ? "Every \(minutes / 60)h" : "Every \(minutes) min"
        }
        return option.prefix(1).uppercased() + option.dropFirst()
    }

    private func timeBinding(_ text: Binding<String>) -> Binding<Date> {
        Binding(
            get: {
                let parts = text.wrappedValue.split(separator: ":").compactMap { Int($0) }
                let hour = parts.first ?? 8
                let minute = parts.count > 1 ? parts[1] : 0
                return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                text.wrappedValue = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
            }
        )
    }

    private func select(_ blueprint: CronBlueprint) {
        var defaults: [String: String] = [:]
        for field in blueprint.fields {
            if field.isDelivery {
                defaults[field.name] = field.options.contains("local") ? "local" : (field.defaultValue ?? "local")
            } else if let value = field.defaultValue {
                defaults[field.name] = value
            }
        }
        values = defaults
        withAnimation(Design.Motion.standard) { self.blueprint = blueprint }
    }

    // MARK: Custom form

    private var customForm: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                TextField("Name (e.g. Morning briefing)", text: $name)
                    .font(.headline)
                Divider().overlay(Design.Colors.hairline)
                ZStack(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("What should Hermes do each time? Be specific — it runs without you.")
                            .font(.subheadline)
                            .foregroundStyle(Design.Colors.textTertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $prompt)
                        .font(.subheadline)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                }
            }
            .padding(Design.Spacing.md)
            .cardSurface()

            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                SectionHeader(title: "When")
                Picker("Cadence", selection: $cadence) {
                    ForEach(Cadence.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch cadence {
                case .daily, .weekdays:
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                case .weekly:
                    Picker("Day", selection: $weekday) {
                        ForEach(0 ..< 7, id: \.self) { Text(CronSchedulePreset.weekdayNames[$0]).tag($0) }
                    }
                    .tint(Design.Brand.accent)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                case .hourly:
                    EmptyView()
                case .custom:
                    TextField("Cron expression", text: $customCron)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Label(CronSchedulePreset.describe(expression: preset.expression) ?? preset.expression, systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(Design.Colors.textTertiary)
            }
            .padding(Design.Spacing.md)
            .cardSurface()

            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                SectionHeader(title: "Who runs it")
                Picker("Role", selection: $profile) {
                    ForEach(teamStore.roles) { role in
                        Text(RoleStyle.forProfile(role.name).displayName).tag(role.name)
                    }
                }
                .pickerStyle(.menu)
                .tint(RoleStyle.forProfile(profile).color)
            }
            .padding(Design.Spacing.md)
            .cardSurface()
        }
    }

    private var preset: CronSchedulePreset {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 8
        let minute = components.minute ?? 0
        switch cadence {
        case .daily: return .everyMorning(hour: hour, minute: minute)
        case .weekdays: return .weekdays(hour: hour, minute: minute)
        case .weekly: return .weekly(weekday: weekday, hour: hour, minute: minute)
        case .hourly: return .hourly
        case .custom: return .custom(customCron)
        }
    }

    // MARK: Submit

    private var canSubmit: Bool {
        if let blueprint {
            return blueprint.fields.allSatisfy { field in
                field.optional || field.isDelivery || !(values[field.name] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
        return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preset.expression.split(separator: " ").count == 5
    }

    private func submit() {
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                if let blueprint {
                    try await store.instantiate(blueprint, values: values)
                } else {
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    try await store.create(
                        CronJobDraft(
                            name: trimmedName.isEmpty ? String(trimmedPrompt.prefix(40)) : trimmedName,
                            prompt: trimmedPrompt,
                            schedule: preset.expression
                        ),
                        profile: profile
                    )
                }
                dismiss()
                toasts.show("Automation created", systemImage: "clock.badge.checkmark")
            } catch {
                toasts.showError(error.localizedDescription)
            }
        }
    }
}
