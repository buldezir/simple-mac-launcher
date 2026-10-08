import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var hotkeys = HotkeyManager.shared

    var body: some View {
        Form {
            Section("Ask AI") {
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
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 680)
        .onAppear { settings.refreshLaunchAtLogin() }
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
