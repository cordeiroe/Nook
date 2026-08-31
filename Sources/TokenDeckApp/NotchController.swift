import AppKit
import Combine
import SwiftUI
import TokenDeckCore

/// Painel sem borda que nao rouba foco. Sem isso, tocar no painel tiraria
/// o cursor do editor onde o usuario esta trabalhando.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Ancora o painel no notch. Em repouso ele cobre exatamente o notch e nao
/// desenha nada: o alvo do hover e o proprio recorte da tela. No hover, o
/// painel desce a partir da base do notch.
@MainActor
final class NotchController: NSObject, ObservableObject {
    @Published private(set) var isOpen = false
    @Published private(set) var geometry: NotchGeometry?

    /// Altura medida do cartao. Fica publicada porque o painel precisa dela
    /// antes de a view existir, e ela muda com o conteudo.
    @Published private(set) var cardHeight: CGFloat = 240

    /// Verdadeiro quando o conteúdo não cabe e o cartão precisa rolar.
    @Published private(set) var cardScrolls = false

    /// Aba aberta. Um módulo por vez em vez de todos empilhados: com cinco
    /// blocos o cartão passava de dois terços da tela.
    @Published private(set) var selected: ModuleKind = .usage

    /// Fração máxima da altura da tela que o cartão pode ocupar.
    private static let maxHeightFraction: CGFloat = 0.66

    static let cardWidth: CGFloat = 380

    private var panel: NotchPanel?
    private let model: DashboardModel
    private var cancellables: Set<AnyCancellable> = []
    private var closeTask: Task<Void, Never>?

    /// Tolerancia antes de fechar. Cobre a tremida ao percorrer o painel.
    private static let closeDelay: Duration = .milliseconds(220)

    init(model: DashboardModel) {
        self.model = model
        super.init()
    }

    // MARK: - Ciclo de vida

    func show() {
        guard panel == nil else {
            panel?.orderFrontRegardless()
            return
        }
        guard let geo = NotchGeometry.detect(preferring: model.config.notchScreenNumber) else { return }
        geometry = geo
        selected = ModuleKind(rawValue: model.config.selectedModule)
            .flatMap { model.enabledModules.contains($0) ? $0 : nil }
            ?? model.enabledModules.first
            ?? .usage

        let panel = NotchPanel(
            contentRect: geo.collapsedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Acima da barra de menus: o painel precisa cobrir o notch e descer
        // por cima dela, senao ficaria recortado no topo.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: NotchRootView(model: model, controller: self))

        self.panel = panel
        applyFrame()
        panel.orderFrontRegardless()

        // `@Published` emite em willSet: sem o hop de runloop, o sink leria
        // `model.snapshot` antes da propriedade ser escrita.
        model.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.remeasure() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func hide() {
        closeTask?.cancel()
        closeTask = nil
        panel?.orderOut(nil)
        panel = nil
        cancellables.removeAll()
        isOpen = false
    }

    func toggleEnabled() {
        model.config.panelEnabled.toggle()
        model.config.panelEnabled ? show() : hide()
    }

    /// Move o painel pro proximo monitor, pra quem usa o Mac fechado ou com
    /// varias telas e quer o painel onde esta trabalhando.
    func cycleScreen() {
        let screens = NSScreen.screens.compactMap(NotchGeometry.id(of:))
        guard screens.count > 1 else { return }
        let current = geometry?.screenNumber
        let index = current.flatMap { screens.firstIndex(of: $0) } ?? 0
        model.config.notchScreenNumber = screens[(index + 1) % screens.count]
        relocate()
    }

    func select(_ module: ModuleKind) {
        guard module != selected else { return }
        selected = module
        model.config.selectedModule = module.rawValue
        remeasure()
    }

    // MARK: - Abrir e fechar

    func setPointerInside(_ inside: Bool) {
        if inside {
            closeTask?.cancel()
            closeTask = nil
            guard !isOpen else { return }
            isOpen = true
            applyFrame(animated: true)
        } else {
            guard isOpen, closeTask == nil else { return }
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: Self.closeDelay)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.close() }
            }
        }
    }

    private func close() {
        closeTask?.cancel()
        closeTask = nil
        guard isOpen else { return }
        isOpen = false
        applyFrame(animated: true)
    }

    // MARK: - Geometria

    @objc private func screensChanged() {
        relocate()
    }

    private func relocate() {
        guard let geo = NotchGeometry.detect(preferring: model.config.notchScreenNumber) else { return }
        geometry = geo
        applyFrame(animated: true)
    }

    /// Mede a altura real do cartao numa view descartavel. Ler fittingSize da
    /// view em tela logo apos trocar o conteudo devolve a medida anterior,
    /// porque a passada de layout ainda nao rodou.
    private func remeasure() {
        let probe = NSHostingView(
            rootView: AnyView(
                NotchCardContent(
                    snapshot: model.snapshot,
                    modules: model.enabledModules,
                    selected: selected,
                    config: model.config,
                    onSelect: { _ in },
                    onDrop: { _ in }, onRemove: { _ in },
                    onClipboardCopy: { _ in }, onClipboardRemove: { _ in },
                    onClipboardClear: {},
                    onMediaCommand: { _ in },
                    onNotionSave: { _ in nil }
                )
                .frame(width: Self.cardWidth)
            )
        )
        let natural = probe.fittingSize.height

        // O espaço disponível é o que sobra abaixo do notch.
        let available = (geometry.map { $0.screenFrame.height - $0.notchRect.height } ?? 800)
        let ceiling = available * Self.maxHeightFraction
        let height = min(natural, ceiling)
        let scrolls = natural > ceiling + 0.5

        guard abs(height - cardHeight) > 0.5 || scrolls != cardScrolls else { return }
        cardHeight = height
        cardScrolls = scrolls
        if isOpen { applyFrame(animated: false) }
    }

    private func applyFrame(animated: Bool = false) {
        guard let panel, let geo = geometry else { return }
        let frame = isOpen
            ? geo.expandedFrame(cardSize: CGSize(width: Self.cardWidth, height: cardHeight))
            : geo.collapsedFrame

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}
