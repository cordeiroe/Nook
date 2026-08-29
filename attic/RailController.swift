import AppKit
import Combine
import SwiftUI
import TokenDeckCore

/// Painel sem borda que nao rouba foco. Sem isso, clicar na regua tiraria
/// o cursor do editor onde o usuario esta trabalhando.
final class RailPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Regua ancorada numa borda da tela. O usuario arrasta livre e, ao soltar,
/// ela cola na borda mais proxima e passa a deslizar so ao longo dela.
@MainActor
final class RailController: NSObject, ObservableObject {
    @Published private(set) var layout = RailLayout()
    @Published private(set) var edge: RailEdge = .right

    /// Em repouso so a aba aparece. O hover revela a regua de aneis.
    @Published private(set) var isCollapsed = true

    private var railPanel: RailPanel?
    private var bubblePanel: RailPanel?
    private var bubbleHost: NSHostingView<AnyView>?

    private let model: DashboardModel
    private var cancellables: Set<AnyCancellable> = []

    private var fraction: Double = 0.5
    private var bubbleVisible = false
    private var closeTask: Task<Void, Never>?

    /// Qual provider esta sob o cursor. A view usa pra destacar o anel.
    @Published private(set) var hoveredGroup: String?

    /// Tempo que a bolha sobrevive depois que o cursor sai. Cobre o vao entre
    /// dois aneis, que senao apagaria e reacenderia a bolha a cada movimento.
    private static let closeDelay: Duration = .milliseconds(180)

    /// Atraso pra recolher depois que o cursor sai. Maior que o da bolha:
    /// recolher e um movimento maior e merece mais tolerancia a tremida.
    private static let collapseDelay: Duration = .milliseconds(260)

    private var collapseTask: Task<Void, Never>?

    /// Posicao livre enquanto o arrasto acontece. Fora do arrasto e nil e a
    /// regua vive presa a borda.
    private var dragOrigin: CGPoint?

    init(model: DashboardModel) {
        self.model = model
        super.init()
    }

    // MARK: - Ciclo de vida

    func show() {
        guard railPanel == nil else {
            railPanel?.orderFrontRegardless()
            return
        }

        edge = RailEdge(rawValue: model.config.railEdge) ?? .right
        fraction = model.config.railOffsetFraction
        layout = RailLayout.fit(itemCount: model.snapshot.providers.count, on: anchorScreen(), axis: edge.axis)

        let panel = makePanel(size: layout.tabSize)
        panel.contentView = NSHostingView(rootView: RailRootView(model: model, controller: self))
        railPanel = panel
        applyFrame()
        persist()
        panel.orderFrontRegardless()

        // `@Published` emite em willSet: sem o hop de runloop, o sink leria
        // `model.snapshot` antes da propriedade ser escrita e dimensionaria a
        // regua com a contagem antiga de medidores.
        model.$snapshot
            .map { $0.providers.count }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyFrame(animated: true) }
            .store(in: &cancellables)

        // A bolha aberta precisa acompanhar o dado novo.
        model.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshBubble() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func hide() {
        collapseTask?.cancel()
        collapseTask = nil
        hideBubble()
        railPanel?.orderOut(nil)
        railPanel = nil
        cancellables.removeAll()
    }

    func toggle() {
        model.config.railVisible.toggle()
        model.config.railVisible ? show() : hide()
    }

    /// Volta pro meio da borda direita do monitor principal.
    func resetPosition() {
        dragOrigin = nil
        edge = .right
        fraction = 0.5
        model.config.railScreenNumber = nil
        persist()
        applyFrame(animated: true)
    }

    func moveTo(edge newEdge: RailEdge) {
        dragOrigin = nil
        edge = newEdge
        persist()
        applyFrame(animated: true)
    }

    private func makePanel(size: CGSize) -> RailPanel {
        let panel = RailPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        // Sem isto o painel nao recebe mouseMoved e o onHover do SwiftUI perde
        // a saida do cursor, deixando a bolha acesa pra sempre.
        panel.acceptsMouseMovedEvents = true
        return panel
    }

    // MARK: - Revelar e recolher

    /// Chamado pelo hover no painel inteiro. Entrar revela, sair recolhe.
    func setPointerInside(_ inside: Bool) {
        guard dragOrigin == nil else { return }
        if inside {
            collapseTask?.cancel()
            collapseTask = nil
            guard isCollapsed else { return }
            isCollapsed = false
            applyFrame(animated: true)
        } else {
            guard !isCollapsed, collapseTask == nil else { return }
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: Self.collapseDelay)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.collapse() }
            }
        }
    }

    private func collapse() {
        collapseTask?.cancel()
        collapseTask = nil
        hideBubble()
        guard !isCollapsed else { return }
        isCollapsed = true
        applyFrame(animated: true)
    }

    /// A aba em repouso, a regua quando revelada.
    private var widgetSize: CGSize {
        isCollapsed ? layout.tabSize : layout.railSize
    }

    // MARK: - Arrasto

    func beginDrag() {
        collapseTask?.cancel()
        collapseTask = nil
        hideBubble()
        dragOrigin = railPanel?.frame.origin ?? .zero
    }

    /// Recebe ja em coordenadas de tela. O arrasto e calculado a partir de
    /// `NSEvent.mouseLocation`, nao da translation do SwiftUI: a janela se move
    /// durante o gesto, entao qualquer coordenada relativa a ela realimentaria
    /// o proprio movimento.
    func moveTo(_ origin: CGPoint) {
        dragOrigin = origin
        railPanel?.setFrameOrigin(origin)
    }

    /// Ao soltar, decide a borda mais proxima e cola nela. A orientacao so muda
    /// aqui: trocar de eixo no meio do gesto seria desorientador.
    func endDrag() {
        guard let panel = railPanel, let origin = dragOrigin else { return }
        dragOrigin = nil

        let rect = CGRect(origin: origin, size: widgetSize)
        let screen = screenFor(rect: rect)
        let area = screen?.visibleFrame ?? rect

        let newEdge = RailEdge.nearest(to: rect, in: area)
        let newLayout = RailLayout.fit(itemCount: model.snapshot.providers.count, on: screen, axis: newEdge.axis)

        edge = newEdge
        layout = newLayout
        fraction = newEdge.fraction(centerAlong: newEdge.center(of: rect), in: area, railSize: newLayout.railSize)
        model.config.railScreenNumber = screen.flatMap(Self.displayID)
        persist()

        _ = panel
        applyFrame(animated: true)
    }

    var currentOrigin: CGPoint { railPanel?.frame.origin ?? .zero }

    // MARK: - Posicionamento

    @objc private func screensChanged() {
        dragOrigin = nil
        applyFrame()
    }

    private func applyFrame(animated: Bool = false) {
        guard let panel = railPanel, dragOrigin == nil else { return }

        let screen = anchorScreen()
        let fitted = RailLayout.fit(itemCount: model.snapshot.providers.count, on: screen, axis: edge.axis)
        if fitted != layout { layout = fitted }

        let area = screen?.visibleFrame ?? panel.frame
        let center = edge.centerAlong(in: area, railSize: layout.railSize, fraction: fraction)
        let frame = edge.frame(in: area, size: widgetSize, centerAlong: center)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        refreshBubble()
    }

    private func anchorScreen() -> NSScreen? {
        if let wanted = model.config.railScreenNumber,
           let match = NSScreen.screens.first(where: { Self.displayID($0) == wanted }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func screenFor(rect: CGRect) -> NSScreen? {
        let best = NSScreen.screens.max { a, b in
            overlap(rect, a.visibleFrame) < overlap(rect, b.visibleFrame)
        }
        if let best, overlap(rect, best.visibleFrame) > 0 { return best }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    private static func displayID(_ screen: NSScreen) -> Int? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
    }

    private func persist() {
        model.config.railEdge = edge.rawValue
        model.config.railOffsetFraction = fraction
    }

    // MARK: - Bolha

    func setHovered(_ group: String?) {
        guard dragOrigin == nil else { return }

        if let group {
            closeTask?.cancel()
            closeTask = nil
            guard group != hoveredGroup else { return }
            hoveredGroup = group
            refreshBubble()
            return
        }

        // Saida e sempre adiada: mover entre dois aneis passa por um instante
        // sem alvo, e fechar na hora faria a bolha piscar.
        guard hoveredGroup != nil, closeTask == nil else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.closeDelay)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.hideBubble() }
        }
    }

    private func refreshBubble() {
        guard let group = hoveredGroup, let rail = railPanel else { return }

        guard let provider = model.snapshot.providers.first(where: { $0.id == group }) else {
            return hideBubble()
        }

        let direction = edge.bubbleDirection
        let panel = bubblePanel ?? {
            // A bolha e so leitura: ignorar o mouse evita piscar o hover e
            // impede que ela engula cliques destinados ao que esta atras.
            let p = makePanel(size: .zero)
            p.ignoresMouseEvents = true
            bubblePanel = p
            return p
        }()

        // Mede a altura real do conteudo numa view descartavel. Ler fittingSize
        // logo depois de trocar o rootView da view em tela devolve a medida
        // anterior, porque a passada de layout ainda nao rodou.
        let content = BubbleView(provider: provider, direction: direction, pointerOffset: 0, layout: layout)
        let probe = NSHostingView(rootView: AnyView(content))
        let size = probe.fittingSize

        let host = bubbleHost ?? {
            let h = NSHostingView(rootView: AnyView(EmptyView()))
            bubbleHost = h
            panel.contentView = h
            return h
        }()

        let placed = place(bubble: size, beside: rail.frame, direction: direction)
        host.rootView = AnyView(
            BubbleView(provider: provider, direction: direction, pointerOffset: placed.pointerOffset, layout: layout)
        )
        panel.setFrame(NSRect(origin: placed.origin, size: size), display: true)

        if bubbleVisible {
            panel.orderFrontRegardless()
        } else {
            // So anima na primeira aparicao. As atualizacoes de 15s reusam a
            // mesma janela e nao podem re-piscar o fade.
            bubbleVisible = true
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.13
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    /// Encosta a bolha na regua e a mantem dentro da tela. A ponta continua
    /// apontando pro centro da regua mesmo quando a bolha e empurrada pra dentro.
    private func place(bubble size: CGSize, beside rail: CGRect, direction: BubbleDirection) -> (origin: CGPoint, pointerOffset: CGFloat) {
        let area = (screenFor(rect: rail)?.visibleFrame) ?? rail
        var origin = CGPoint.zero

        switch direction {
        case .right: origin.x = rail.maxX + layout.bubbleGap
        case .left:  origin.x = rail.minX - layout.bubbleGap - size.width
        case .up:    origin.y = rail.maxY + layout.bubbleGap
        case .down:  origin.y = rail.minY - layout.bubbleGap - size.height
        }

        if direction.isHorizontal {
            origin.y = rail.midY - size.height / 2
            origin.y = min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height))
            let limit = max(0, size.height / 2 - 26)
            return (origin, min(max(rail.midY - (origin.y + size.height / 2), -limit), limit))
        } else {
            origin.x = rail.midX - size.width / 2
            origin.x = min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width))
            let limit = max(0, size.width / 2 - 26)
            return (origin, min(max(rail.midX - (origin.x + size.width / 2), -limit), limit))
        }
    }

    private func hideBubble() {
        closeTask?.cancel()
        closeTask = nil
        hoveredGroup = nil
        guard bubbleVisible, let panel = bubblePanel else { return }
        bubbleVisible = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.11
            panel.animator().alphaValue = 0
        } completionHandler: {
            // Se voltou a aparecer durante o fade, nao esconde.
            if panel.alphaValue == 0 { panel.orderOut(nil) }
        }
    }
}
