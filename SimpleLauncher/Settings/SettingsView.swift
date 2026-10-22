import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var hotkeys = HotkeyManager.shared
    @State private var locateGeneration = 0
    @State private var locatedCLIPath: String?
    @State private var cliLocateError: String?
    @State private var isLocatingCLI = false

    var body: some View {
        Form {
            Section("Ask AI") {
                Picker("Provider", selection: $settings.aiProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }

                if settings.aiProvider == .api {
                    TextField("Endpoint", text: $settings.endpoint)
                        .textFieldStyle(.roundedBorder)
                    SecureField("API Key", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model name", text: $settings.modelName)
                        .textFieldStyle(.roundedBorder)

                    Text("Use an OpenAI-compatible Chat Completions endpoint. Example: https://api.openai.com/v1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SecureField("Tavily API Key (optional)", text: $settings.tavilyAPIKey)
                        .textFieldStyle(.roundedBorder)
                    Text("When set, Ask AI gets web_search and web_fetch via Tavily. Requires a model that supports tool calling. Free tier: tavily.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    TextField("Model (optional)", text: cliModelBinding)
                        .textFieldStyle(.roundedBorder)
                        .id("cli-model-\(settings.aiProvider.rawValue)")
                    TextField("Executable (optional)", text: cliPathBinding)
                        .textFieldStyle(.roundedBorder)
                        .id("cli-path-\(settings.aiProvider.rawValue)")

                    Toggle("Auto mode", isOn: $settings.cliAutoMode)
                    Text(settings.cliAutoMode
                        ? "The agent may edit files and run commands in your home folder."
                        : "Read-only. The agent answers without editing files or running commands.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let cliLocateError {
                        Text(cliLocateError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if isLocatingCLI {
                        Text("Looking for `\(settings.aiProvider.commandName)`…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if cliLocateError == nil, let hint = cliHint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Stepper(value: $settings.aiHistoryLimit, in: SettingsStore.aiHistoryLimitRange) {
                    Text("Keep last \(settings.aiHistoryLimit) AI prompts")
                }
                Text("Stored on this Mac. Type /h in the launcher to browse. Set to 0 to disable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Launcher") {
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                Text("Open the app again while it’s running to show Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Launch at login", isOn: $settings.launchAtLogin)

                if settings.launchAtLoginNeedsApproval {
                    Text("Approval needed in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Activation hotkey") {
                    ActivationHotkeyRecorder(hotkey: $settings.activationHotkey)
                }
                if let error = hotkeys.registrationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Click the shortcut, then press a new one with ⌘, ⌥, ⌃, or ⇧. Esc cancels. ⌫ restores ⌥ Space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Type to search apps. Math like 100-20% or 1,5+2. Ask with ? or ask, or as fallback when nothing matches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            UpdatesSection()
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 740)
        .onAppear {
            settings.refreshLaunchAtLogin()
            refreshCLILocation()
        }
        .onChange(of: cliLocateKey) { _, _ in
            refreshCLILocation()
        }
    }

    private var cliLocateKey: String {
        "\(settings.aiProvider.rawValue)\n\(settings.cliExecutableOverride(for: settings.aiProvider))"
    }

    private func refreshCLILocation() {
        locateGeneration += 1
        let generation = locateGeneration
        let provider = settings.aiProvider
        guard provider.usesCLI else {
            locatedCLIPath = nil
            cliLocateError = nil
            isLocatingCLI = false
            return
        }
        let custom = settings.cliExecutableOverride(for: provider)
        if let problem = CLIAgentLocator.customPathProblem(provider: provider, customPath: custom) {
            locatedCLIPath = nil
            cliLocateError = problem
            isLocatingCLI = false
            return
        }
        if let known = CLIAgentLocator.preview(provider: provider, customPath: custom) {
            locatedCLIPath = known
            cliLocateError = nil
            isLocatingCLI = false
            return
        }

        locatedCLIPath = nil
        cliLocateError = nil
        isLocatingCLI = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                CLIAgentLocator.resolve(provider: provider, customPath: custom)
            }.value
            guard generation == locateGeneration else { return }
            isLocatingCLI = false
            switch result {
            case .success(let path):
                locatedCLIPath = path
                cliLocateError = nil
            case .failure(let error):
                locatedCLIPath = nil
                cliLocateError = error.localizedDescription
            }
        }
    }

    private var cliModelBinding: Binding<String> {
        switch settings.aiProvider {
        case .codex: return $settings.codexModel
        case .claude: return $settings.claudeModel
        case .cursor: return $settings.cursorModel
        case .opencode: return $settings.opencodeModel
        case .api: return .constant("")
        }
    }

    private var cliPathBinding: Binding<String> {
        switch settings.aiProvider {
        case .codex: return $settings.codexCLIPath
        case .claude: return $settings.claudeCLIPath
        case .cursor: return $settings.cursorCLIPath
        case .opencode: return $settings.opencodeCLIPath
        case .api: return .constant("")
        }
    }

    private var cliHint: String? {
        guard cliLocateError == nil, let path = locatedCLIPath else { return nil }
        let provider = settings.aiProvider
        if CLIAgentLocator.customPathProblem(
            provider: provider,
            customPath: settings.cliExecutableOverride(for: provider)
        ) != nil {
            return "Clear the executable field to auto-detect `\(provider.commandName)`."
        }
        let access = settings.cliAutoMode ? "Auto mode is on." : "Read-only."
        return "Using \(path). \(access) Uses your existing \(provider.title) login. Leave the model blank to use the CLI default."
    }
}

/// Whether the app looks for updates, and installs them by itself. The check
/// is here too, since the menu bar icon can be hidden.
private struct UpdatesSection: View {
    @Bindable private var updater = AppUpdater.shared

    var body: some View {
        if updater.isRelease {
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                Toggle("Download and install automatically", isOn: $updater.downloadsAutomatically)
                    .disabled(!updater.checksAutomatically)
                Text(updater.downloadsAutomatically && updater.checksAutomatically
                     ? "Once a day. A new version installs when you quit SimpleLauncher."
                     : "Once a day. SimpleLauncher asks before installing a new version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(updater.menuTitle) { updater.checkForUpdates() }
                    .disabled(!updater.canCheck && updater.available == nil)
            }
        }
    }
}

struct ActivationHotkeyRecorder: View {
    @Binding var hotkey: ActivationHotkey
    @State private var isRecording = false

    var body: some View {
        Button(isRecording ? "Press shortcut…" : hotkey.displayString) {
            isRecording.toggle()
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .frame(minWidth: 140)
        .background(HotkeyCapture(isRecording: $isRecording, hotkey: $hotkey))
        .help("Click, then press a shortcut. Esc cancels. Delete restores ⌥ Space.")
    }
}

private struct HotkeyCapture: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotkey: ActivationHotkey

    func makeCoordinator() -> Coordinator {
        Coordinator(isRecording: $isRecording, hotkey: $hotkey)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isRecording = isRecording
        context.coordinator.hotkey = $hotkey
        context.coordinator.isRecordingBinding = $isRecording
        if isRecording {
            context.coordinator.start()
        } else {
            context.coordinator.stop()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var isRecording: Bool
        var hotkey: Binding<ActivationHotkey>
        var isRecordingBinding: Binding<Bool>
        private var monitor: Any?

        init(isRecording: Binding<Bool>, hotkey: Binding<ActivationHotkey>) {
            self.isRecording = isRecording.wrappedValue
            self.hotkey = hotkey
            self.isRecordingBinding = isRecording
        }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isRecording, !event.isARepeat else { return event }
                return self.handle(event)
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            switch ActivationHotkey.interpret(event) {
            case .cancel:
                finish(nil)
            case .reset:
                finish(.default)
            case .invalid:
                NSSound.beep()
            case .recorded(let recorded):
                finish(recorded)
            }
            return nil
        }

        private func finish(_ recorded: ActivationHotkey?) {
            isRecording = false
            DispatchQueue.main.async {
                if let recorded {
                    self.hotkey.wrappedValue = recorded
                }
                self.isRecordingBinding.wrappedValue = false
            }
        }
    }
}
