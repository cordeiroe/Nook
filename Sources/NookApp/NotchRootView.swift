import AppKit
import SwiftUI
import NookCore
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

    /// Cantos inferiores arredondados imitam o recorte do MacBook. Aberto, os
    /// cantos somem: o pescoço passa a ser continuação do cartão.
    private var notchShape: UnevenRoundedRectangle {
        let raio: CGFloat = (isVirtual && !controller.isOpen) ? 12 : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: raio,
            bottomTrailingRadius: raio, topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            neck
            if controller.isOpen {
                NotchCard(
                    content: NotchCardContent(
                        snapshot: model.snapshot,
                        modules: model.enabledModules,
                        selected: controller.selected,
                        config: model.config,
                        onSelect: controller.select,
                        onDrop: model.addToShelf,
                        onRemove: model.removeFromShelf,
                        onClipboardCopy: model.copyBack,
                        onClipboardRemove: model.removeFromClipboard,
                        onClipboardClear: model.clearClipboard,
                        onMediaCommand: model.mediaCommand,
                        onNotionSave: model.saveToNotion,
                        onFocusSession: model.focusSession
                    ),
                    height: controller.cardHeight,
                    scrolls: controller.cardScrolls
                )
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.2), value: controller.isOpen)
        .onHover { controller.setPointerInside($0) }
    }

    /// Numa tela sem recorte, ele é desenhado: sem isso o painel flutua solto
    /// no meio da barra de menus e perde a ideia de sair de algum lugar.
    private var isVirtual: Bool {
        controller.geometry.map { !$0.isPhysical } ?? false
    }

    /// Pescoco que liga o recorte ao cartao. Sobre um notch físico ele é preto
    /// sobre preto e a junção some; sobre um virtual, ele É o notch. Fechado e
    /// físico, fica transparente mas clicável, e é isso que faz o próprio
    /// recorte da tela ser o alvo do hover.
    private var neck: some View {
        ZStack {
            notchShape
                .fill(controller.isOpen || isVirtual ? Color.black : Color.clear)

            if !controller.isOpen {
                if isVirtual {
                    // Num recorte virtual há pixels para desenhar a marca, e o
                    // sorriso dela é o próprio traço de alerta.
                    BrandMark(notchHeight: notchSize.height, alert: alert)
                        .transition(.opacity)
                } else if let alert {
                    // Num notch físico não há onde desenhar dentro do recorte,
                    // então o aviso é só o traço, colado na borda de baixo.
                    VStack {
                        Spacer()
                        Capsule()
                            .fill(Theme.alertTint(alert))
                            .frame(width: notchSize.width * 0.5, height: 3)
                            .shadow(color: Theme.alertTint(alert).opacity(0.7), radius: 4)
                            .padding(.bottom, 3)
                    }
                    .transition(.opacity)
                }
            }
        }
        .frame(width: notchSize.width, height: notchSize.height)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.25), value: alert != nil)
        .animation(.easeOut(duration: 0.18), value: controller.isOpen)
        // Arrastar um arquivo sobre o notch abre o painel. Sem isto nao haveria
        // como largar nada na prateleira, porque em repouso ela nem existe.
        .onDrop(of: [.fileURL], isTargeted: nil) { _ in false }
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { false },
            set: { hovering in if hovering { controller.setPointerInside(true) } }
        )) { _ in false }
    }
}

/// O cartão que desce do notch. Com muitos módulos o conteúdo passa de dois
/// terços da altura da tela, então ele é limitado e rola por dentro.
struct NotchCard: View {
    let content: NotchCardContent
    let height: CGFloat
    let scrolls: Bool

    var body: some View {
        Group {
            if scrolls {
                ScrollView(.vertical, showsIndicators: false) { content }
                    .frame(width: NotchController.cardWidth, height: height)
            } else {
                content
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        )
    }
}

/// Conteúdo sem moldura. Separado porque o controller precisa medir a altura
/// natural: dentro de um ScrollView, `fittingSize` devolveria o tamanho da
/// área visível, não o do conteúdo.
///
/// Um módulo por vez, escolhido nas abas. Empilhar todos passava de dois terços
/// da tela e obrigava a rolar para ver o que importa.
struct NotchCardContent: View {
    let snapshot: DashboardSnapshot
    let modules: [ModuleKind]
    let selected: ModuleKind
    let config: Config
    let onSelect: (ModuleKind) -> Void
    let onDrop: ([URL]) -> Void
    let onRemove: (ShelfItem) -> Void
    let onClipboardCopy: (ClipboardItem) -> Void
    let onClipboardRemove: (ClipboardItem) -> Void
    let onClipboardClear: () -> Void
    let onMediaCommand: (NowPlayingReader.Command) -> Void
    let onNotionSave: (String) async -> String?
    let onFocusSession: (LiveSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleTabs(modules: modules, selected: selected, onSelect: onSelect)
            block(for: selected)
        }
        .padding(14)
        .frame(width: NotchController.cardWidth)
    }

    @ViewBuilder
    private func block(for module: ModuleKind) -> some View {
        switch module {
        case .usage:
            if snapshot.providers.isEmpty {
                Placeholder(text: "Lendo consumo…", loading: true)
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(Array(snapshot.providers.enumerated()), id: \.element.id) { index, provider in
                        if index > 0 {
                            Divider().overlay(Color.white.opacity(0.10))
                        }
                        ProviderBlock(provider: provider)
                    }
                }
            }
        case .sessions:
            if snapshot.sessions.isEmpty {
                Placeholder(text: "Nenhuma sessão rodando.")
            } else {
                SessionsBlock(sessions: snapshot.sessions, onFocus: onFocusSession)
            }
        case .nowPlaying:
            if let playing = snapshot.nowPlaying {
                NowPlayingBlock(playing: playing, onCommand: onMediaCommand)
            } else {
                Placeholder(text: "Nada tocando no Spotify nem no app Música.")
            }
        case .notion:
            NotionBlock(
                recent: snapshot.notionRecent,
                ready: snapshot.notionReady,
                onSave: onNotionSave
            )
        case .calendar:
            CalendarBlock(events: snapshot.agenda, access: snapshot.agendaAccess)
        case .clipboard:
            ClipboardBlock(
                items: snapshot.clipboard,
                retentionHours: config.clipboardRetentionHours,
                onCopy: onClipboardCopy,
                onRemove: onClipboardRemove,
                onClear: onClipboardClear
            )
        case .shelf:
            ShelfBlock(
                items: snapshot.shelf,
                access: snapshot.shelfAccess,
                onDrop: onDrop,
                onRemove: onRemove
            )
        default:
            Placeholder(text: "Módulo ainda não implementado.")
        }
    }
}

/// Abas dos módulos. A selecionada mostra o rótulo; as outras, só o ícone.
struct ModuleTabs: View {
    let modules: [ModuleKind]
    let selected: ModuleKind
    let onSelect: (ModuleKind) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(modules, id: \.self) { module in
                Button { onSelect(module) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: module.symbol)
                            .font(.system(size: 12, weight: .medium))
                        if module == selected {
                            Text(module.label)
                                .font(.system(size: 11.5, weight: .medium))
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, module == selected ? 9 : 6)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(module == selected ? 0.15 : 0))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(module == selected ? 0.95 : 0.42))
                .help(module.label)
            }

            Spacer(minLength: 4)
            SettingsMenu()
        }
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

struct SettingsMenu: View {
    var body: some View {
        Menu {
            Button("Abrir pasta de ajustes") { NSWorkspace.shared.open(Paths.support) }
            if NSScreen.screens.count > 1 {
                Button("Trocar de tela") { AppDelegate.current?.notch?.cycleScreen() }
            }
            Divider()
            Button("Sair do Nook") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.white.opacity(0.4))
    }
}

struct Placeholder: View {
    let text: String
    var loading: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if loading { ProgressView().controlSize(.small) }
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
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
    let onFocus: (LiveSession) -> Void

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
                SessionRow(session: session, subtitle: subtitle(session)) {
                    onFocus(session)
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

/// Linha de sessão. Clicar traz o terminal dela para frente.
struct SessionRow: View {
    let session: LiveSession
    let subtitle: String
    let onFocus: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.statusColor(session.status))
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: session.pid != nil ? "arrow.up.forward.app" : "folder")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(hovering ? 0.55 : 0))
                .padding(.top, 2)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onFocus)
        .help(session.pid != nil
              ? "Trazer o terminal desta sessão para frente"
              : "Abrir \(session.shortDirectory) no Finder")
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
