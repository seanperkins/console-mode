import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var shell: ConsoleShell

    @State private var launchAtLoginError: String?
    @State private var config = TaggerSettings.current
    @State private var usage = UsageSettings.current
    @State private var isConfirmingClearAll = false
    @State private var pendingDeleteCount = 0

    private var model: NoteListModel { shell.notes }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                setLaunchAtLogin(enabled)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                shortcutSection
                appearanceSection
                usageSection
                startupSection
                taggingSection
                storageSection
            }
            .padding(24)
            .frame(width: 520, alignment: .topLeading)
        }
        .frame(width: 520, height: 620)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance")
                .font(.headline)

            Picker("Theme:", selection: themeBinding) {
                ForEach(ThemeID.allCases) { id in
                    Text(id.title).tag(id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(shell.themeID.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            ThemePreview(tokens: shell.theme)
        }
    }

    /// Writes through the shell so the live panel restyles immediately.
    private var themeBinding: Binding<ThemeID> {
        Binding(
            get: { shell.themeID },
            set: { shell.applyTheme($0) }
        )
    }

    // MARK: - Usage

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LLM usage")
                .font(.headline)

            Toggle("Show the Usage tab", isOn: $usage.isEnabled)
            Toggle("Warn at 20%, 10% and 5% remaining", isOn: $usage.alertsEnabled)
                .disabled(!usage.isEnabled)

            HStack {
                Text("Refresh every")
                Stepper(value: $usage.pollMinutes, in: 1...60) {
                    Text("\(usage.pollMinutes) min")
                        .monospacedDigit()
                }
                .fixedSize()
            }
            .disabled(!usage.isEnabled)

            HStack {
                Text("Alert shows for")
                Stepper(value: $usage.alertSeconds, in: 2...30, step: 1) {
                    Text("\(Int(usage.alertSeconds))s")
                        .monospacedDigit()
                }
                .fixedSize()
            }
            .disabled(!usage.isEnabled || !usage.alertsEnabled)

            TextField("omp path (blank = auto-detect)", text: $usage.ompPath)
                .textFieldStyle(.roundedBorder)
                .disabled(!usage.isEnabled)

            HStack(spacing: 10) {
                Button("Refresh now") {
                    Task { await shell.usage.refresh() }
                }
                .disabled(!usage.isEnabled || shell.usage.isRefreshing)

                Button("Re-arm warnings") {
                    shell.usage.resetFiredThresholds()
                }
                .help("Allow already-fired thresholds to alert again")

                if shell.usage.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }

            Text(usageStatusText)
                .font(.caption)
                .foregroundStyle(shell.usage.lastError == nil ? Color.secondary : Color.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: usage) { previous, updated in
            UsageSettings.current = updated
            if previous.isEnabled != updated.isEnabled {
                shell.setUsageEnabled(updated.isEnabled)
            }
        }
    }

    private var usageStatusText: String {
        if let error = shell.usage.lastError { return error }
        let detected = UsageClient(executableOverride: usage.ompPath).resolveExecutable()
        guard let detected else { return "omp not found — set the path above." }
        let providers = shell.usage.rollup.count
        return "Using \(detected)" + (providers > 0 ? " · \(providers) providers" : "")
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shortcut")
                .font(.headline)
            KeyboardShortcuts.Recorder("Toggle console:", name: .toggleConsole)
        }
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Startup")
                .font(.headline)
            Toggle("Open at login", isOn: launchAtLoginBinding)

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)

                Text(
                    "If you run from the repo, `make bundle` deletes and recreates ConsoleMode.app — " +
                        "the login item may point at a stale path. Toggle off, rebuild, then toggle on again."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var taggingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Project tagging")
                .font(.headline)

            Toggle("Tag notes with a local model", isOn: $config.isEnabled)

            LabeledContent("Endpoint") {
                TextField("http://127.0.0.1:1234", text: $config.baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Model") {
                TextField("ornith-1.5-9b-mlx", text: $config.model)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 10) {
                Button("Tag existing notes") {
                    TaggerSettings.current = config
                    model.backfillTags()
                }
                .disabled(!config.isEnabled || model.isBackfilling)

                if model.isBackfilling {
                    ProgressView()
                        .controlSize(.small)
                }

                if let status = model.tagStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                "Tagging runs in the background after a note is saved, so capture stays instant. " +
                    "Requires LM Studio's server to be running."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: config) { _, updated in
            TaggerSettings.current = updated
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Storage")
                .font(.headline)
            Text(NoteStore.defaultDatabaseURL().path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()
                .padding(.vertical, 6)

            HStack(spacing: 10) {
                Button("Clear all notes…", role: .destructive) {
                    pendingDeleteCount = model.noteCount
                    isConfirmingClearAll = true
                }
                .disabled(model.noteCount == 0)

                Text(noteCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Deleting notes cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            "Delete all \(pendingDeleteCount) note\(pendingDeleteCount == 1 ? "" : "s")?",
            isPresented: $isConfirmingClearAll,
            titleVisibility: .visible
        ) {
            Button("Delete \(pendingDeleteCount) note\(pendingDeleteCount == 1 ? "" : "s")", role: .destructive) {
                model.deleteAllNotes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every note from \(NoteStore.defaultDatabaseURL().lastPathComponent). It cannot be undone.")
        }
    }

    private var noteCountLabel: String {
        let count = model.noteCount
        if let status = model.statusMessage, status.hasPrefix("Deleted ") {
            return status
        }
        return count == 0 ? "No notes stored." : "\(count) note\(count == 1 ? "" : "s") stored."
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
            NSLog("Launch at login failed: \(error)")
        }
    }
}
