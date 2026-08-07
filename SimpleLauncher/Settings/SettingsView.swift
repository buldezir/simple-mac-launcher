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

                SecureField("Tavily API Key (optional)", text: $settings.tavilyAPIKey)
                    .textFieldStyle(.roundedBorder)
                Text("When set, Ask AI gets web_search and web_fetch via Tavily. Requires a model that supports tool calling. Free tier: tavily.com")
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

                LabeledContent("Toggle hotkey", value: "⌥ Space (Alt+Space)")
                Text("Type to search apps. Math like 100-20%. Ask with ? or ask, or as fallback when nothing matches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 620)
        .onAppear { settings.refreshLaunchAtLogin() }
    }
}
