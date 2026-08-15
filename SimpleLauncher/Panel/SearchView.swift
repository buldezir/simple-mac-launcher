import AppKit
import SwiftUI

struct SearchView: View {
    @ObservedObject var model: LauncherViewModel
    @ObservedObject private var ai: AskAIService
    @FocusState private var queryFocused: Bool

    init(model: LauncherViewModel) {
        self.model = model
        self._ai = ObservedObject(wrappedValue: model.ai)
    }

    var body: some View {
        ZStack {
            // Soft rounded shadow layers (avoids SwiftUI .shadow + material corner artifacts)
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.22))
                .blur(radius: 22)
                .offset(y: 12)
                .padding(.horizontal, 6)

            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.12))
                .blur(radius: 8)
                .offset(y: 4)

            panelCard
        }
        .padding(36)
        // Hug content for intrinsic sizing, but top-align when the panel is
        // temporarily taller mid-resize (keeps the search field pinned).
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            KeyEventHandler { event in
                handleKey(event)
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .onAppear {
            queryFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .launcherPanelDidShow)) { _ in
            queryFocused = true
        }
    }

    private static let cornerRadius: CGFloat = 16

    private var panelCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 18, weight: .medium))

                TextField("Search apps, calculate, or ask AI…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .regular))
                    .focused($queryFocused)
                    .onSubmit {
                        model.handleReturn()
                    }

                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // Layout must update immediately (no SwiftUI height animation) so the
            // panel can top-anchor resize without the search field drifting.
            resultsBody
        }
        .frame(width: 640)
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var resultsBody: some View {
        if ai.isAnswerMode {
            AnswerPaneView(
                answer: ai.answer,
                isStreaming: ai.isStreaming,
                errorMessage: ai.errorMessage,
                statusText: ai.statusText,
                maxContentHeight: model.maxAnswerHeight
            )
        } else if case .historyDetail(let entry) = model.overlayMode {
            AnswerPaneView(
                answer: entry.answer,
                isStreaming: false,
                errorMessage: nil,
                heading: "History",
                headingImage: "clock",
                question: entry.prompt,
                maxContentHeight: model.maxAnswerHeight
            )
        } else if model.isShowingHistoryList {
            HistoryPaneView(
                model: model,
                maxContentHeight: model.maxAnswerHeight
            )
        } else if model.results.isEmpty {
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                    ResultRowView(
                        result: result,
                        isSelected: index == model.selectedIndex,
                        shortcutHint: index < 9 ? "⌘\(index + 1)" : nil
                    )
                    .id(result.id)
                    .onTapGesture {
                        model.activateIndex(index)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }

    private var emptyMessage: String {
        if let input = SlashInput.parse(model.query) {
            if input.token.isEmpty {
                return "Type a command, e.g. /h for history"
            }
            return "No commands match"
        }
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Type to search apps, calculate (100-20%), ask AI with ? or ask, or / for commands"
        }
        return "No results"
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers,
           let digit = chars.first,
           digit.isNumber {
            let number = Int(String(digit)) ?? -1
            let index = number == 0 ? 9 : number - 1
            if index >= 0, !model.isShowingAnswerPane {
                model.activateIndex(index)
            }
            return true
        }

        switch event.keyCode {
        case 125: // down
            if !model.isShowingAnswerPane {
                model.moveSelection(by: 1)
            }
            return true
        case 126: // up
            if !model.isShowingAnswerPane {
                model.moveSelection(by: -1)
            }
            return true
        case 36, 76: // return / keypad enter
            model.handleReturn()
            return true
        case 53: // escape
            if model.handleEscape() {
                return true
            }
            NotificationCenter.default.post(name: .launcherShouldHide, object: nil)
            return true
        default:
            return false
        }
    }
}

extension Notification.Name {
    static let launcherPanelDidShow = Notification.Name("launcherPanelDidShow")
}

/// Captures key-downs that TextField would otherwise swallow incompletely.
private struct KeyEventHandler: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> HandlerView {
        let view = HandlerView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: HandlerView, context: Context) {
        nsView.handler = handler
    }

    final class HandlerView: NSView {
        var handler: ((NSEvent) -> Bool)?
        var monitor: Any?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }

        private func setup() {
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        override var isOpaque: Bool { false }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let handler = self.handler else { return event }
                    return handler(event) ? nil : event
                }
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
