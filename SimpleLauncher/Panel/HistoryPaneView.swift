import SwiftUI

struct HistoryPaneView: View {
    @ObservedObject var model: LauncherViewModel
    var maxContentHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("History", systemImage: "clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if model.results.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
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
                    }
                    .frame(maxHeight: maxContentHeight)
                    .onChange(of: model.selectedIndex) { _, newValue in
                        guard model.results.indices.contains(newValue) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(model.results[newValue].id, anchor: .center)
                        }
                    }
                }
            }

            Text("⏎ View  ·  Esc Back")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyMessage: String {
        let remainder = SlashInput.parse(model.query)?.remainder ?? ""
        if remainder.isEmpty {
            return "No AI history yet. Ask with ? or ask"
        }
        return "No matching history"
    }
}
