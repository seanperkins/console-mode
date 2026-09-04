import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var shell: ConsoleShell

    @State private var launchAtLoginError: String?
    @State private var config = TaggerSettings.current
    @State private var usage = UsageSettings.current
    @State private var terminal = TerminalSettings.current
    @State private var obsidian = ObsidianSettings.current
    @State private var actionReview = ActionReviewSettings.current
    @State private var claudeStatusLine = ClaudeStatusLineSettings.current
    @State private var claudeStatusLineError: String?
    @State private var deepSeek = DeepSeekSettings.current
    @State private var deepSeekAPIKey: String = ""
    @State private var deepSeekKeychainError: String?
    @State private var deepSeekTestResult: String?
    @State private var deepSeekTestInFlight = false
    private let deepSeekCredentialStore: any DeepSeekCredentialStore = KeychainDeepSeekCredentialStore()
    @State private var openRouter = OpenRouterSettings.current
    @State private var openRouterAPIKey: String = ""
    @State private var openRouterKeychainError: String?
    @State private var openRouterTestResult: String?
    @State private var openRouterTestInFlight = false
    private let openRouterCredentialStore: any OpenRouterCredentialStore = KeychainOpenRouterCredentialStore()
    @State private var isConfirmingClearAll = false
    @State private var pendingDeleteCount = 0
    @State private var exportFormat: NoteExportFormat = .markdown
    @State private var exportError: String?

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
                terminalSection
                claudeStatusLineSection
                deepSeekSection
                openRouterSection
                startupSection
                taggingSection
                actionReviewSection
                obsidianSection
                storageSection
            }
            .padding(24)
            .frame(width: 520, alignment: .topLeading)
        }
        .frame(width: 520, height: 700)
        .onAppear {
            deepSeekAPIKey = deepSeekCredentialStore.loadAPIKey() ?? ""
            openRouterAPIKey = openRouterCredentialStore.loadAPIKey() ?? ""
        }
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

    // MARK: - Terminal

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Terminal")
                .font(.headline)

            Toggle("Show the Terminal tab", isOn: $terminal.isEnabled)

            TextField("Working directory (blank = home folder)", text: $terminal.workingDirectory)
                .textFieldStyle(.roundedBorder)
                .disabled(!terminal.isEnabled)

            TextField("Shell path (blank = $SHELL)", text: $terminal.shellPath)
                .textFieldStyle(.roundedBorder)
                .disabled(!terminal.isEnabled)

            HStack {
                Text("Scrollback limit")
                Stepper(value: $terminal.scrollbackLimitMB, in: 5...500, step: 5) {
                    Text("\(terminal.scrollbackLimitMB) MB")
                        .monospacedDigit()
                }
                .fixedSize()
            }
            .disabled(!terminal.isEnabled)

            HStack(spacing: 10) {
                Button("Restart terminal") {
                    shell.restartTerminal()
                }
                .disabled(!shell.hasActivatedTerminal)
                .help("Ends the current shell session and starts a fresh one")
            }

            Text(
                "A real PTY to your own login shell (not a sandboxed emulation) — the same engine the " +
                    "actual Ghostty app uses. Spawns only the first time you open the tab, never at " +
                    "launch, and stops rendering the instant you switch away or dismiss the panel; the " +
                    "shell process itself keeps running so your working directory and scrollback survive " +
                    "both. Working directory and shell path changes apply the next time a session spawns " +
                    "(this session, or use Restart above to apply them now)."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: terminal) { previous, updated in
            TerminalSettings.current = updated
            if previous.isEnabled != updated.isEnabled {
                shell.setTerminalEnabled(updated.isEnabled)
            }
        }
    }

    // MARK: - Claude Code statusline

    private var claudeStatusLineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude Code usage")
                .font(.headline)

            Toggle("Show Claude Code's rate limits and cost estimate", isOn: claudeStatusLineInstalledBinding)

            TextField(
                "settings.json path (blank = ~/.claude/settings.json)",
                text: $claudeStatusLine.settingsPath
            )
            .textFieldStyle(.roundedBorder)

            Text(claudeStatusLineStatusText)
                .font(.caption)
                .foregroundStyle(claudeStatusLineError == nil ? Color.secondary : Color.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                "Installs a tiny wrapper as Claude Code's statusLine command so this app can read the " +
                    "account-wide rate limits and Claude's own cost estimate it already reports there — no " +
                    "credentials read, nothing scraped. If you already have a statusline (cship, a custom " +
                    "script, ...), it keeps working exactly as before; the wrapper forwards to it unchanged. " +
                    "If you don't have one yet, this becomes your only statusline command, which replaces " +
                    "Claude Code's built-in footer hints with nothing visible — quota data is still captured " +
                    "either way. When a fresh reading is available it replaces (not duplicates) the Anthropic " +
                    "row from omp usage."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: claudeStatusLine) { _, updated in
            ClaudeStatusLineSettings.current = updated
        }
    }

    private var claudeStatusLineInstaller: ClaudeStatusLineInstaller {
        .resolved(settingsPath: claudeStatusLine.settingsPath)
    }

    private var claudeStatusLineInstalledBinding: Binding<Bool> {
        Binding(
            get: { claudeStatusLineInstaller.isInstalled },
            set: { newValue in
                claudeStatusLineError = nil
                do {
                    if newValue {
                        try claudeStatusLineInstaller.install()
                        claudeStatusLine.wasEverInstalled = true
                        ClaudeStatusLineSettings.current = claudeStatusLine
                    } else {
                        try claudeStatusLineInstaller.uninstall()
                        claudeStatusLine.wasEverInstalled = false
                        ClaudeStatusLineSettings.current = claudeStatusLine
                    }
                } catch {
                    claudeStatusLineError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        )
    }

    private var claudeStatusLineStatusText: String {
        if let claudeStatusLineError { return claudeStatusLineError }
        if claudeStatusLineInstaller.isInstalled {
            return "Installed. Claude Code writes a fresh reading on its next turn."
        }
        // A user who turned this on but never explicitly turned it back off
        // has drifted, not opted out — a hand-edited settings.json, another
        // statusline tool reinstalling itself over ours, or a deleted
        // wrapper file. Plain "Not installed." would read as "never asked
        // for this", which is misleading and would hide a silently stopped
        // feed.
        if claudeStatusLine.wasEverInstalled {
            return "⚠ Was installed, but another tool (or a hand edit) has taken over the statusline command. Toggle off then on to reclaim it."
        }
        return "Not installed."
    }

    // MARK: - DeepSeek balance

    private var deepSeekSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DeepSeek balance")
                .font(.headline)

            Toggle("Show DeepSeek's real account balance", isOn: $deepSeek.isEnabled)

            SecureField("API key (from platform.deepseek.com)", text: $deepSeekAPIKey)
                .textFieldStyle(.roundedBorder)
                .disabled(!deepSeek.isEnabled)
                .onChange(of: deepSeekAPIKey) { _, updated in
                    do {
                        try deepSeekCredentialStore.saveAPIKey(updated)
                        deepSeekKeychainError = nil
                    } catch {
                        deepSeekKeychainError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }

            HStack(spacing: 10) {
                Button("Test connection") {
                    Task { await testDeepSeekConnection() }
                }
                .disabled(deepSeekAPIKey.isEmpty || deepSeekTestInFlight)

                if deepSeekTestInFlight {
                    ProgressView().controlSize(.small)
                }

                if let deepSeekTestResult {
                    Text(deepSeekTestResult)
                        .font(.caption)
                        .foregroundStyle(deepSeekTestResult.hasPrefix("✓") ? Color.green : Color.red)
                }
            }

            Text(deepSeekStatusText)
                .font(.caption)
                .foregroundStyle(deepSeekStatusIsError ? Color.red : Color.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                "Reads the account's real remaining balance directly from DeepSeek's own " +
                    "`GET /user/balance` endpoint — the actual dollar figure you'd pay, not the " +
                    "catalog-priced token estimate `omp stats` falls back to for providers " +
                    "`omp usage` doesn't track. When enabled this replaces (not duplicates) the " +
                    "estimate row for DeepSeek. The key is stored in the Keychain, never in " +
                    "app settings, and never leaves this request."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: deepSeek) { _, updated in
            DeepSeekSettings.current = updated
        }
    }

    @MainActor
    private func testDeepSeekConnection() async {
        deepSeekTestInFlight = true
        deepSeekTestResult = nil
        defer { deepSeekTestInFlight = false }
        do {
            let balance = try await DeepSeekClient(apiKey: deepSeekAPIKey).fetch()
            let entry = balance.balanceInfos.first { $0.currency.caseInsensitiveCompare("USD") == .orderedSame }
                ?? balance.balanceInfos.first
            if let entry, let total = Double(entry.totalBalance) {
                let currency = entry.currency.uppercased()
                let amount = String(format: "%.2f", total)
                deepSeekTestResult = "✓ " + (currency == "USD" ? "$\(amount)" : "\(amount) \(currency)")
            } else {
                deepSeekTestResult = "✓ Connected"
            }
        } catch {
            deepSeekTestResult = "✗ " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private var deepSeekStatusIsError: Bool {
        shell.usage.deepSeekError != nil
    }

    private var deepSeekStatusText: String {
        if let error = shell.usage.deepSeekError { return error }
        guard deepSeek.isEnabled else { return "Off." }
        guard let fetchedAt = shell.usage.deepSeekBalanceFetchedAt else { return "Not fetched yet." }
        return "Balance as of " + UsageView.clock(fetchedAt)
    }

    // MARK: - OpenRouter balance

    private var openRouterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OpenRouter balance")
                .font(.headline)

            Toggle("Show OpenRouter's real credit balance", isOn: $openRouter.isEnabled)

            SecureField("Management key (from openrouter.ai/settings/provisioning-keys)", text: $openRouterAPIKey)
                .textFieldStyle(.roundedBorder)
                .disabled(!openRouter.isEnabled)
                .onChange(of: openRouterAPIKey) { _, updated in
                    do {
                        try openRouterCredentialStore.saveAPIKey(updated)
                        openRouterKeychainError = nil
                    } catch {
                        openRouterKeychainError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }

            HStack(spacing: 10) {
                Button("Test connection") {
                    Task { await testOpenRouterConnection() }
                }
                .disabled(openRouterAPIKey.isEmpty || openRouterTestInFlight)

                if openRouterTestInFlight {
                    ProgressView().controlSize(.small)
                }

                if let openRouterTestResult {
                    Text(openRouterTestResult)
                        .font(.caption)
                        .foregroundStyle(openRouterTestResult.hasPrefix("✓") ? Color.green : Color.red)
                }
            }

            Text(openRouterStatusText)
                .font(.caption)
                .foregroundStyle(openRouterStatusIsError ? Color.red : Color.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                "Reads the account's real remaining credit balance directly from OpenRouter's own " +
                    "`GET /api/v1/credits` endpoint — the actual dollar figure you'd pay, not the " +
                    "catalog-priced token estimate `omp stats` falls back to for providers " +
                    "`omp usage` doesn't track. Needs a **Management key**, not a standard inference " +
                    "key — create one at openrouter.ai/settings/provisioning-keys. When enabled this " +
                    "replaces (not duplicates) the estimate row for OpenRouter. The key is stored in " +
                    "the Keychain, never in app settings, and never leaves this request."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: openRouter) { _, updated in
            OpenRouterSettings.current = updated
        }
    }

    @MainActor
    private func testOpenRouterConnection() async {
        openRouterTestInFlight = true
        openRouterTestResult = nil
        defer { openRouterTestInFlight = false }
        do {
            let balance = try await OpenRouterClient(apiKey: openRouterAPIKey).fetch()
            openRouterTestResult = "✓ $" + String(format: "%.2f", balance.remaining)
        } catch {
            openRouterTestResult = "✗ " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private var openRouterStatusIsError: Bool {
        shell.usage.openRouterError != nil
    }

    private var openRouterStatusText: String {
        if let error = shell.usage.openRouterError { return error }
        guard openRouter.isEnabled else { return "Off." }
        guard let fetchedAt = shell.usage.openRouterBalanceFetchedAt else { return "Not fetched yet." }
        return "Balance as of " + UsageView.clock(fetchedAt)
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


    private var actionReviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Action review")
                .font(.headline)

            Toggle("Classify notes with omp + Claude", isOn: $actionReview.isEnabled)

            LabeledContent("Model") {
                TextField("claude-opus-5", text: $actionReview.model)
                    .textFieldStyle(.roundedBorder)
            }
            .disabled(!actionReview.isEnabled)

            HStack {
                Text("Batch size")
                Stepper(value: $actionReview.batchSize, in: 1...50) {
                    Text("\(actionReview.batchSize) notes")
                        .monospacedDigit()
                }
                .fixedSize()
            }
            .disabled(!actionReview.isEnabled)

            TextField("omp path (blank = use LLM usage path)", text: $actionReview.ompPath)
                .textFieldStyle(.roundedBorder)
                .disabled(!actionReview.isEnabled)

            HStack(spacing: 10) {
                Button("Analyze pending notes") {
                    ActionReviewSettings.current = actionReview
                    model.backfillActionReview()
                }
                .disabled(!actionReview.isEnabled || model.isAnalyzing)

                if model.isAnalyzing {
                    ProgressView().controlSize(.small)
                }

                if let status = model.analyzeStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                "Use /analyze in the console to send notes to Claude via omp. Actionable notes show a bolt and a short next-step summary."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: actionReview) { _, updated in
            ActionReviewSettings.current = updated
        }
    }

    // MARK: - Obsidian

    private var obsidianSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Obsidian export")
                .font(.headline)

            Toggle("Append new notes to a daily note", isOn: $obsidian.isEnabled)

            LabeledContent("Vault folder") {
                TextField("~/Obsidian/MyVault", text: $obsidian.vaultPath)
                    .textFieldStyle(.roundedBorder)
            }
            .disabled(!obsidian.isEnabled)

            LabeledContent("Daily notes folder") {
                TextField("Daily (optional)", text: $obsidian.dailyFolder)
                    .textFieldStyle(.roundedBorder)
            }
            .disabled(!obsidian.isEnabled)

            Text(
                "Each captured note appends a checkbox line to yyyy-MM-dd.md with the time, body, and project tag."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: obsidian) { _, updated in
            ObsidianSettings.current = updated
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
                Picker("Export as", selection: $exportFormat) {
                    ForEach(NoteExportFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .fixedSize()

                Button("Export notes…") {
                    exportNotes()
                }
                .disabled(model.noteCount == 0)

                if let exportError {
                    Text(exportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Text("Writes every note — body, tags, timestamps — to a single file you choose. A full backup, not incremental.")
                .font(.caption)
                .foregroundStyle(.secondary)

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

    private func exportNotes() {
        exportError = nil
        let notes = model.exportAllNotes()
        guard !notes.isEmpty else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "console-mode-notes.\(exportFormat.fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try NoteExporter.write(notes, as: exportFormat, to: url)
        } catch {
            exportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
