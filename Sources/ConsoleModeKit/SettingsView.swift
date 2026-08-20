import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Toggle console:", name: .toggleConsole)
            }

            Section("Startup") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }
            }

            Section("Storage") {
                LabeledContent("Database") {
                    Text(NoteStore.defaultDatabaseURL().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login failed: \(error)")
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
