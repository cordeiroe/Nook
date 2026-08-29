import AppKit
import SwiftUI
import TokenDeckCore
import UniformTypeIdentifiers

/// Prateleira: capturas recentes e arquivos largados, prontos pra arrastar.
struct ShelfBlock: View {
    let items: [ShelfItem]
    let access: ShelfStore.Access
    let onDrop: ([URL]) -> Void
    let onRemove: (ShelfItem) -> Void

    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PRATELEIRA")
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            if case .denied(let folder) = access {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Sem acesso à pasta \(folder), onde tuas capturas são salvas.",
                          systemImage: "lock")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Abrir Privacidade e Segurança") {
                        // Leva direto ao painel certo: dizer o caminho por
                        // extenso e pedir pro usuario cacar o item na lista.
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.vertical, 2)
            } else if items.isEmpty {
                Text("Arraste arquivos aqui. Capturas recentes aparecem sozinhas.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.32))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            ShelfTile(item: item, onRemove: { onRemove(item) })
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(height: 62)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    targeted ? Color.white.opacity(0.4) : Color.clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            collect(providers)
            return true
        }
    }

    private func collect(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { onDrop(urls) }
    }
}

struct ShelfTile: View {
    let item: ShelfItem
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Thumbnail(url: item.url)
                    .frame(width: 44, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )

                if hovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white, .black.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                }
            }

            Text(item.name)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 46)
        }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help(item.path)
    }
}

/// Miniatura com cache: sem ele cada atualizacao de 15s releria os arquivos
/// do disco so pra redesenhar a mesma imagem.
struct Thumbnail: View {
    let url: URL

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
    }

    private var image: NSImage {
        let key = url.path as NSString
        if let hit = Self.cache.object(forKey: key) { return hit }

        let produced: NSImage
        if let loaded = NSImage(contentsOf: url) {
            produced = loaded
        } else {
            produced = NSWorkspace.shared.icon(forFile: url.path)
        }
        produced.size = NSSize(width: 88, height: 80)
        Self.cache.setObject(produced, forKey: key)
        return produced
    }
}
