import SwiftUI

struct ResultRowView: View {
    let result: SearchResult
    let isSelected: Bool
    let shortcutHint: String?

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let shortcutHint {
                Text(shortcutHint)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        switch result {
        case .app(let app):
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
        case .calculator:
            Image(systemName: "function")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
        case .askAI:
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 28, height: 28)
        case .slashCommand(let command):
            Image(systemName: command.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
        case .historyEntry:
            Image(systemName: "text.bubble")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 28, height: 28)
        }
    }
}
