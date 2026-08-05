import SwiftUI

struct AnswerPaneView: View {
    let answer: String
    let isStreaming: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(isStreaming ? "Thinking…" : "Answer", systemImage: "sparkles")
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
                    } else if let attributed = try? AttributedString(
                        markdown: answer.isEmpty ? " " : answer,
                        options: AttributedString.MarkdownParsingOptions(
                            interpretedSyntax: .full
                        )
                    ) {
                        Text(attributed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    } else {
                        Text(answer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
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
