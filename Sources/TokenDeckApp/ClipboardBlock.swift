import AppKit
import SwiftUI
import TokenDeckCore

/// Histórico da área de transferência. Clicar num item devolve o conteúdo
/// para a área de transferência.
struct ClipboardBlock: View {
    let items: [ClipboardItem]
    let retentionHours: Double
    let onCopy: (ClipboardItem) -> Void
    let onRemove: (ClipboardItem) -> Void
    let onClear: () -> Void

    @State private var justCopied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("TRANSFERÊNCIA")
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                if !items.isEmpty {
                    Button("limpar", action: onClear)
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            if items.isEmpty {
                Text("Nada guardado. Senhas e chaves são descartadas, e o resto expira em \(Int(retentionHours))h.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 3) {
                    ForEach(items.prefix(5)) { item in
                        ClipboardRow(
                            item: item,
                            copied: justCopied == item.id,
                            onCopy: {
                                onCopy(item)
                                justCopied = item.id
                                Task {
                                    try? await Task.sleep(for: .milliseconds(1200))
                                    if justCopied == item.id { justCopied = nil }
                                }
                            },
                            onRemove: { onRemove(item) }
                        )
                    }
                }
            }
        }
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    let copied: Bool
    let onCopy: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                .font(.system(size: 9))
                .foregroundStyle(copied ? Theme.statusColor(.idle) : .white.opacity(0.3))
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.07 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onCopy)
        .help(item.text.count > 400 ? String(item.text.prefix(400)) + "…" : item.text)
    }

    private var subtitle: String {
        var parts = [Format.elapsed(since: item.copiedAt)]
        if let app = item.sourceApp { parts.append(app) }
        if item.lineCount > 1 { parts.append("\(item.lineCount) linhas") }
        return parts.joined(separator: " · ")
    }
}
