import AppKit
import SwiftUI
import NookCore

/// Conteudo do painel da regua. A bolha vive em painel proprio, entao aqui
/// so existe a barra de aneis, o hover e o arrasto.
struct RailRootView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var controller: RailController

    @State private var dragAnchor: CGSize?

    var body: some View {
        ZStack {
            if controller.isCollapsed {
                TabHandle(
                    edge: controller.edge,
                    layout: controller.layout,
                    accent: model.snapshot.headline.map { Theme.tint(for: $0.ratio) } ?? .gray
                )
                .transition(.opacity)
            } else {
                rail
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: controller.isCollapsed)
        // Hover no painel inteiro revela e recolhe; o hover de cada anel,
        // mais abaixo, cuida so da bolha.
        .onHover { controller.setPointerInside($0) }
        .gesture(dragGesture)
        .contextMenu { menu }
    }

    private var rail: some View {
        let layout = controller.layout
        return items(layout: layout)
            .padding(layout.padding)
            .frame(width: layout.railSize.width, height: layout.railSize.height)
            .background(
                Theme.edgeShape(controller.edge, radius: layout.cornerRadius)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 4)
            )
    }

    @ViewBuilder
    private func items(layout: RailLayout) -> some View {
        if model.snapshot.providers.isEmpty {
            ProgressView().controlSize(.small)
        } else if layout.axis == .vertical {
            VStack(spacing: layout.itemSpacing) { rings(layout: layout) }
        } else {
            HStack(spacing: layout.itemSpacing) { rings(layout: layout) }
        }
    }

    private func rings(layout: RailLayout) -> some View {
        ForEach(model.snapshot.providers) { provider in
            RailItem(
                provider: provider,
                layout: layout,
                highlighted: controller.hoveredGroup == provider.id
            )
            .onHover { inside in
                controller.setHovered(inside ? provider.id : nil)
            }
        }
    }

    /// Arrasto livre em qualquer direcao, ancorado no ponto onde o mouse pegou
    /// o widget. Ao soltar, o controller cola na borda mais proxima.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                if dragAnchor == nil {
                    controller.beginDrag()
                    let origin = controller.currentOrigin
                    dragAnchor = CGSize(width: mouse.x - origin.x, height: mouse.y - origin.y)
                }
                guard let anchor = dragAnchor else { return }
                controller.moveTo(CGPoint(x: mouse.x - anchor.width, y: mouse.y - anchor.height))
            }
            .onEnded { _ in
                dragAnchor = nil
                controller.endDrag()
            }
    }

    @ViewBuilder
    private var menu: some View {
        Menu("Ancorar em") {
            Button("Esquerda") { controller.moveTo(edge: .left) }
            Button("Direita") { controller.moveTo(edge: .right) }
            Button("Topo") { controller.moveTo(edge: .top) }
            Button("Base") { controller.moveTo(edge: .bottom) }
        }
        Button("Recentralizar") { controller.resetPosition() }
        Button("Ocultar régua") { controller.toggle() }
        Divider()
        Button("Sair do Nook") { NSApplication.shared.terminate(nil) }
    }
}

/// Aba de repouso. Fica colada na borda com o rotulo na vertical quando a
/// ancoragem e lateral, e na horizontal quando e topo ou base.
struct TabHandle: View {
    let edge: RailEdge
    let layout: RailLayout
    let accent: Color

    private var label: some View {
        Text("Tokens usage")
            .font(.system(size: layout.tabLabelSize, weight: .medium))
            .kerning(0.4)
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1)
            .fixedSize()
    }

    /// Ponto de status: cor do medidor mais pressionado, pra dar o recado
    /// sem precisar revelar a regua.
    private var dot: some View {
        Circle()
            .fill(accent)
            .frame(width: layout.tabDot, height: layout.tabDot)
    }

    var body: some View {
        Group {
            if layout.axis == .vertical {
                VStack(spacing: 8) {
                    dot
                    // rotationEffect nao altera o espaco reservado, entao o
                    // rotulo girado precisa de um frame proprio.
                    label
                        .rotationEffect(.degrees(-90))
                        .frame(width: layout.tabLabelSize * 1.6,
                               height: layout.tabLength - layout.tabDot - 30)
                }
            } else {
                HStack(spacing: 8) {
                    dot
                    label
                }
            }
        }
        .frame(width: layout.tabSize.width, height: layout.tabSize.height)
        .background(
            Theme.edgeShape(edge, radius: layout.tabCornerRadius)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 3)
        )
    }
}

/// Um anel da regua: circulo escuro, arco colorido, icone no centro,
/// percentual embaixo.
struct RailItem: View {
    let provider: ProviderSummary
    let layout: RailLayout
    let highlighted: Bool

    var body: some View {
        VStack(spacing: layout.labelGap) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(highlighted ? 0.16 : 0.07))
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: layout.ringStroke)
                    .padding(layout.ringStroke / 2)
                Circle()
                    .trim(from: 0, to: max(0.004, provider.ratio))
                    .stroke(
                        Theme.tint(for: provider.ratio),
                        style: StrokeStyle(lineWidth: layout.ringStroke, lineCap: .round)
                    )
                    .padding(layout.ringStroke / 2)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: provider.ratio)

                Image(systemName: Theme.symbol(for: provider.kind))
                    .font(.system(size: layout.iconSize, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: layout.ringDiameter, height: layout.ringDiameter)
            .scaleEffect(highlighted ? 1.06 : 1)
            .animation(.easeOut(duration: 0.14), value: highlighted)

            Text("\(provider.percent)%")
                .font(.system(size: layout.labelSize, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white.opacity(highlighted ? 1 : 0.72))
                .animation(.easeOut(duration: 0.14), value: highlighted)
        }
    }
}

/// Bolha de detalhe. A ponta e irma do cartao, nao um overlay: como overlay
/// ela era desenhada fora dos limites do painel e o Window Server a recortava.
struct BubbleView: View {
    let provider: ProviderSummary
    let direction: BubbleDirection
    /// Deslocamento da ponta em coordenadas Cocoa (positivo = regua acima
    /// ou a direita do centro da bolha).
    let pointerOffset: CGFloat
    let layout: RailLayout

    var body: some View {
        switch direction {
        case .right: HStack(spacing: 0) { pointer; card }
        case .left:  HStack(spacing: 0) { card; pointer }
        case .up:    VStack(spacing: 0) { card; pointer }
        case .down:  VStack(spacing: 0) { pointer; card }
        }
    }

    private var pointer: some View {
        Pointer(direction: direction)
            .fill(Color.black)
            .frame(
                width: direction.isHorizontal ? layout.pointerDepth : layout.pointerBreadth,
                height: direction.isHorizontal ? layout.pointerBreadth : layout.pointerDepth
            )
            .offset(
                x: direction.isHorizontal ? 0 : pointerOffset,
                // Cocoa cresce pra cima, SwiftUI pra baixo.
                y: direction.isHorizontal ? -pointerOffset : 0
            )
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: Theme.symbol(for: provider.kind))
                    .font(.system(size: 15, weight: .medium))
                Text(provider.name)
                    .font(.system(size: 15, weight: .medium))
                Spacer(minLength: 0)
                Text("\(provider.percent)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.tint(for: provider.ratio))
            }
            .foregroundStyle(.white)

            ForEach(provider.meters) { MeterBlock(meter: $0) }

            if !provider.sessions.isEmpty {
                Divider().overlay(Color.white.opacity(0.12))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(provider.sessions.prefix(4)) { session in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Theme.statusColor(session.status))
                                .frame(width: 5, height: 5)
                            Text(session.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(Format.elapsed(since: session.updatedAt))
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }

            if let warning = provider.warning {
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: layout.bubbleWidth)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 4)
        )
    }
}

/// Bloco de um medidor dentro da bolha: titulo, reset, barra e percentual.
struct MeterBlock: View {
    let meter: Meter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(meter.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 6)
                if let footnote = meter.footnote {
                    Text(footnote)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(Theme.tint(for: meter.ratio))
                        .frame(width: max(4, geo.size.width * meter.ratio))
                        .animation(.easeOut(duration: 0.5), value: meter.ratio)
                }
            }
            .frame(height: 6)

            HStack(spacing: 5) {
                Text("\(meter.percent)% usado")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                Text("·").foregroundStyle(.white.opacity(0.3))
                Text(meter.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                if meter.estimated {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.35))
                        .help("Estimativa local. Teto vem de config.json, não da Anthropic.")
                }
            }
        }
    }
}

/// Ponta triangular da bolha, sempre virada pra regua.
struct Pointer: Shape {
    let direction: BubbleDirection

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch direction {
        case .right:  // bolha a direita da regua: ponta pra esquerda
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .left:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .up:     // bolha acima da regua: ponta pra baixo
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .down:
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}
