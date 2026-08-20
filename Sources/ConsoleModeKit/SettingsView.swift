import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var launchAtLoginError: String?

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                setLaunchAtLogin(enabled)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Shortcut")
                    .font(.headline)
                KeyboardShortcuts.Recorder("Toggle console:", name: .toggleConsole)
            }

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

            VStack(alignment: .leading, spacing: 6) {
                Text("Storage")
                    .font(.headline)
                Text(NoteStore.defaultDatabaseURL().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 460, height: 320, alignment: .topLeading)
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
