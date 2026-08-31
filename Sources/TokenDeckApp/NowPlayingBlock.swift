import AppKit
import SwiftUI
import TokenDeckCore

/// Capa do álbum. O Spotify entrega uma URL do CDN dele, então a imagem é
/// baixada uma vez por faixa e fica em memória: sem cache, cada atualização
/// de 15s refaria a requisição da mesma capa.
struct Artwork: View {
    let url: URL?
    let size: CGFloat

    @State private var image: NSImage?

    private static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.07))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.32))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let hit = Self.cache.object(forKey: url as NSURL) {
            image = hit
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let loaded = NSImage(data: data)
        else { return }
        Self.cache.setObject(loaded, forKey: url as NSURL)
        image = loaded
    }
}

struct NowPlayingBlock: View {
    let playing: NowPlaying
    let onCommand: (NowPlayingReader.Command) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 11) {
                Artwork(url: playing.artworkURL, size: 54)

                VStack(alignment: .leading, spacing: 2) {
                    Text(playing.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(playing.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                    if !playing.album.isEmpty {
                        Text(playing.album)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.33))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            // A posição avança sozinha a partir do instante da captura, então a
            // barra corre suave sem consultar o Spotify a cada segundo.
            TimelineView(.periodic(from: .now, by: playing.isPlaying ? 1 : 3600)) { context in
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.13))
                            Capsule()
                                .fill(Color.white.opacity(0.75))
                                .frame(width: max(2, geo.size.width * playing.progress(at: context.date)))
                        }
                    }
                    .frame(height: 3)

                    HStack {
                        Text(NowPlaying.clock(playing.position(at: context.date)))
                        Spacer()
                        Text(NowPlaying.clock(playing.duration))
                    }
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.35))
                }
            }

            HStack(spacing: 22) {
                Spacer(minLength: 0)
                control("backward.fill", size: 12) { onCommand(.previous) }
                control(playing.isPlaying ? "pause.fill" : "play.fill", size: 16) { onCommand(.playPause) }
                control("forward.fill", size: 12) { onCommand(.next) }
                Spacer(minLength: 0)
            }
        }
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
