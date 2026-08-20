import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var model: NoteListModel

    @State private var launchAtLoginError: String?
    @State private var config = TaggerSettings.current

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
                startupSection
                taggingSection
                storageSection
            }
            .padding(24)
            .frame(width: 460, alignment: .topLeading)
        }
        .frame(width: 460, height: 460)
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
        }
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
