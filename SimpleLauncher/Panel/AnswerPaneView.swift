import AppKit
import SwiftUI

struct AnswerPaneView: View {
    let answer: String
    let isStreaming: Bool
    let errorMessage: String?
    var statusText: String = "Thinking…"
    var heading: String? = nil
    var headingImage: String = "sparkles"
    var question: String? = nil
    var footer: String = "⏎ Copy  ·  Esc Back"
    var maxContentHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(headerTitle, systemImage: headingImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let question, !question.isEmpty {
                Text(question)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
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
            .frame(maxHeight: maxContentHeight)

            Text(footer)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var headerTitle: String {
        if let heading, !heading.isEmpty { return heading }
        return isStreaming ? statusText : "Answer"
    }
}
