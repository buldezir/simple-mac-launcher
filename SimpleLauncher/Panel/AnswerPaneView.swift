import AppKit
import SwiftUI

struct AnswerPaneView: View {
    let answer: String
    let isStreaming: Bool
    let errorMessage: String?
    var statusText: String = "Thinking…"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(isStreaming ? statusText : "Answer", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ScrollView {
                Group {
                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if answer.isEmpty && isStreaming {
                        Text(" ")
                    } else {
                        Text(AnswerMarkdown.attributedString(from: answer))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                            .environment(\.openURL, OpenURLAction { url in
                                NSWorkspace.shared.open(url)
                                return .handled
                            })
                    }
                }
                .font(.system(size: 14))
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 360)

            Text("⏎ Copy  ·  Esc Back")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
