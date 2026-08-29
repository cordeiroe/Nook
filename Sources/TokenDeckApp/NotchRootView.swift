import AppKit
import SwiftUI
import TokenDeckCore
import UniformTypeIdentifiers

/// Conteudo do painel do notch. Em repouso e uma area invisivel do tamanho
/// exato do recorte, com um arco de alerta quando algum limite aperta.
/// Aberto, o cartao desce a partir dele.
struct NotchRootView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var controller: NotchController

    private var notchSize: CGSize {
        controller.geometry?.notchRect.size ?? CGSize(width: 200, height: 38)
    }

    /// Fracao do medidor mais pressionado, quando passa do limite configurado.
    private var alert: Double? {
        guard let ratio = model.snapshot.headline?.ratio,
              ratio >= model.config.alertThreshold
        else { return nil }
        return ratio
    }

    var body: some View {
        VStack(spacing: 0) {
            neck
            if controller.isOpen {
                NotchCard(
                    snapshot: model.snapshot,
                    modules: model.enabledModules,
                    onDrop: model.addToShelf,
                    onRemove: model.removeFromShelf
                )
                .frame(width: NotchController.cardWidth)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: controller.isOpen)
        .onHover { controller.setPointerInside($0) }
    }

    /// Pescoco que liga o recorte ao cartao. Preto sobre preto quando o notch e
    /// fisico, entao a juncao some. Fechado fica transparente mas clicavel, que
    /// e o que faz o proprio notch ser o alvo do hover.
    private var neck: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(controller.isOpen ? Color.black : Color.clear)

            if !controller.isOpen, let alert {
                Capsule()
                    .fill(Theme.alertTint(alert))
                    .frame(width: notchSize.width * 0.5, height: 3)
                    .padding(.bottom, 3)
                    .shadow(color: Theme.alertTint(alert).opacity(0.7), radius: 4)
                    .transition(.opacity)
            }
        }
        .frame(width: notchSize.width, height: notchSize.height)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.25), value: alert != nil)
        // Arrastar um arquivo sobre o notch abre o painel. Sem isto nao haveria
        // como largar nada na prateleira, porque em repouso ela nem existe.
        .onDrop(of: [.fileURL], isTargeted: nil) { _ in false }
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { false },
            set: { hovering in if hovering { controller.setPointerInside(true) } }
        )) { _ in false }
    }
}

/// O cartao que desce do notch. Cada modulo e independente: se a fonte falhar,
/// o bloco some e o resto continua.
struct NotchCard: View {
    let snapshot: DashboardSnapshot
    let modules: [ModuleKind]
    let onDrop: ([URL]) -> Void
    let onRemove: (ShelfItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if snapshot.providers.isEmpty && snapshot.capturedAt == .distantPast {
                loading
            } else {
                ForEach(Array(visible.enumerated()), id: \.element) { index, module in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.10)).padding(.vertical, 12)
                    }
                    block(for: module)
                }
            }
        }
        .padding(16)
        .frame(width: NotchController.cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        )
    }

    /// So entram modulos implementados e que tenham o que mostrar.
    private var visible: [ModuleKind] {
        modules.filter { module in
            switch module {
            case .usage:      return !snapshot.providers.isEmpty
            case .sessions:   return !snapshot.sessions.isEmpty
            case .nowPlaying: return snapshot.nowPlaying != nil
            case .shelf:      return true
            default:          return false
            }
        }
    }

    @ViewBuilder
    private func block(for module: ModuleKind) -> some View {
        switch module {
        case .usage:
            VStack(alignment: .leading, spacing: 13) {
                ForEach(snapshot.providers) { ProviderBlock(provider: $0) }
            }
        case .sessions:
            SessionsBlock(sessions: snapshot.sessions)
        case .nowPlaying:
            if let playing = snapshot.nowPlaying {
                NowPlayingBlock(playing: playing)
            }
        case .shelf:
            ShelfBlock(
                items: snapshot.shelf,
                access: snapshot.shelfAccess,
                onDrop: onDrop,
                onRemove: onRemove
            )
        default:
            EmptyView()
        }
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Lendo consumo…")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }
}

struct ProviderBlock: View {
    let provider: ProviderSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: Theme.symbol(for: provider.kind))
                    .font(.system(size: 14, weight: .medium))
                Text(provider.name)
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 6)
                Text("\(provider.percent)%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.tint(for: provider.ratio))
            }
            .foregroundStyle(.white)

            ForEach(provider.meters) { MeterRow(meter: $0) }
        }
    }
}

struct SessionsBlock: View {
    let sessions: [LiveSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SESSÕES")
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                let ativas = sessions.filter { $0.status == .busy }.count
                if ativas > 0 {
                    Text("\(ativas) rodando")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Theme.statusColor(.busy))
                }
            }

            ForEach(sessions.prefix(5)) { session in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Theme.statusColor(session.status))
                        .frame(width: 5, height: 5)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.label)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(subtitle(session))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.36))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func subtitle(_ s: LiveSession) -> String {
        let origem = s.provider == .claude ? "Claude" : (s.model ?? "opencode")
        let desde = s.statusSince ?? s.updatedAt
        let estado = s.status == .busy ? "ocupada há" : "ociosa há"
        return "\(origem) · \(s.shortDirectory) · \(estado) \(Format.elapsed(since: desde))"
    }
}

struct NowPlayingBlock: View {
    let playing: NowPlaying

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: playing.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(playing.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text("\(playing.artist) · \(playing.app)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

struct MeterRow: View {
    let meter: Meter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(meter.title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(meter.isQuota ? 0.88 : 0.6))
                if meter.estimated {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.white.opacity(0.28))
                        .help(meter.isQuota
                              ? "Teto definido em config.json, não pela Anthropic."
                              : "Janela de referência, não é limite de cota.")
                }
                Spacer(minLength: 6)
                Text("\(meter.percent)%")
                    .font(.system(size: 11.5, weight: meter.isQuota ? .semibold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(meter.isQuota ? 0.9 : 0.5))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.11))
                    Capsule()
                        // Janela de referencia nao ganha cor de cota: pintar de
                        // verde ou vermelho faria ela competir com os limites
                        // reais, que e o que confundia a leitura.
                        .fill(meter.isQuota ? Theme.tint(for: meter.ratio) : Color.white.opacity(0.28))
                        .frame(width: max(4, geo.size.width * meter.ratio))
                        .animation(.easeOut(duration: 0.5), value: meter.ratio)
                }
            }
            .frame(height: meter.isQuota ? 5 : 3)

            HStack(spacing: 4) {
                // Sem os valores absolutos, "Sessão 35%" ao lado de "Dia 14%"
                // parece contraditorio: os denominadores sao diferentes.
                Text(meter.detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.34))
                if !meter.isQuota {
                    Text("· referência")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.22))
                }
                Spacer(minLength: 4)
                if let footnote = meter.footnote {
                    Text(footnote)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.34))
                }
            }
        }
    }
}
