import SwiftUI

struct HistoryPaneView: View {
    @ObservedObject var model: LauncherViewModel
    var maxContentHeight: CGFloat = 360

    @State private var hoveredID: String?

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
                                row(for: result, at: index)
                                    .id(result.id)
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

            Text("⏎ View  ·  ⌘⌫ Delete  ·  Esc Back")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Swaps the ⌘-number hint for a delete button while the pointer is over the row.
    @ViewBuilder
    private func row(for result: SearchResult, at index: Int) -> some View {
        let isHovered = hoveredID == result.id

        ZStack(alignment: .trailing) {
            ResultRowView(
                result: result,
                isSelected: index == model.selectedIndex,
                shortcutHint: isHovered || index >= 9 ? nil : "⌘\(index + 1)"
            )

            if isHovered, case .historyEntry(let entry) = result {
                Button {
                    model.deleteHistoryEntry(entry)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Delete this entry (⌘⌫)")
                .padding(.trailing, 12)
            }
        }
        .onHover { hovering in
            if hovering {
                hoveredID = result.id
            } else if hoveredID == result.id {
                hoveredID = nil
            }
        }
        .onTapGesture {
            model.activateIndex(index)
        }
    }

    private var emptyMessage: String {
        let remainder = SlashInput.parse(model.query)?.remainder ?? ""
        if remainder.isEmpty {
            return "No AI history yet. Ask with ? or ask"
        }
        return "No matching history"
    }
}
