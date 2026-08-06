import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

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
            }

            Section("Launcher") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)

                if settings.launchAtLoginNeedsApproval {
                    Text("Approval needed in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Toggle hotkey", value: "⌥ Space (Alt+Space)")
                Text("Type to search apps. Math like 100-20%. Ask with ? or ask, or as fallback when nothing matches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 480)
        .onAppear { settings.refreshLaunchAtLogin() }
    }
}
