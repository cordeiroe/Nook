import AppKit
import SwiftUI

/// Dimensoes da regua derivadas da tela e da borda em que ela esta.
/// Nada aqui e constante: um monitor 4K e um MacBook 13" pedem reguas de
/// tamanhos diferentes, e a orientacao muda conforme a borda ancorada.
struct RailLayout: Equatable {
    var axis: Axis = .vertical
    var scale: CGFloat = 1

    var ringDiameter: CGFloat = 50
    var ringStroke: CGFloat = 3
    var iconSize: CGFloat = 17
    var labelSize: CGFloat = 13
    var labelGap: CGFloat = 5
    var itemSpacing: CGFloat = 18
    var padding: CGFloat = 17
    var cornerRadius: CGFloat = 26

    var bubbleWidth: CGFloat = 316
    var gap: CGFloat = 10
    /// Folga entre a ponta da bolha e a regua. Menor que `gap` porque a ponta
    /// ja avanca nessa direcao e precisa parecer encostada.
    var bubbleGap: CGFloat = 4
    var pointerDepth: CGFloat = 9
    var pointerBreadth: CGFloat = 16
    var railSize: CGSize = CGSize(width: 84, height: 289)

    /// Aba de repouso: fica colada na borda e revela a regua no hover.
    var tabThickness: CGFloat = 22
    var tabLength: CGFloat = 112
    var tabCornerRadius: CGFloat = 11
    var tabLabelSize: CGFloat = 10
    var tabDot: CGFloat = 5

    var tabSize: CGSize {
        axis == .vertical
            ? CGSize(width: tabThickness, height: tabLength)
            : CGSize(width: tabLength, height: tabThickness)
    }

    /// Resolucao de referencia: MacBook 15" em pontos logicos.
    private static let reference = CGSize(width: 1512, height: 945)

    /// Fracao maxima do eixo principal que a regua pode ocupar. Acima disso
    /// ela vira uma barra lateral e atrapalha em vez de informar.
    private static let maxFraction: CGFloat = 0.62

    static func fit(itemCount: Int, on screen: NSScreen?, axis: Axis) -> RailLayout {
        let area = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(origin: .zero, size: reference)
        return fit(itemCount: itemCount, area: area, axis: axis)
    }

    /// Separado do NSScreen pra poder ser exercitado com areas sinteticas.
    static func fit(itemCount: Int, area: CGRect, axis: Axis) -> RailLayout {
        let count = max(1, itemCount)
        let raw = min(area.width / reference.width, area.height / reference.height)
        var scale = min(max(raw, 0.80), 1.30)

        var layout = build(scale: scale, count: count, area: area, axis: axis)
        let ceiling = (axis == .vertical ? area.height : area.width) * maxFraction
        let main = axis == .vertical ? layout.railSize.height : layout.railSize.width
        if main > ceiling {
            scale = max(scale * ceiling / main, 0.50)
            layout = build(scale: scale, count: count, area: area, axis: axis)
        }
        return layout
    }

    private static func build(scale: CGFloat, count: Int, area: CGRect, axis: Axis) -> RailLayout {
        var l = RailLayout()
        l.axis = axis
        l.scale = scale
        l.ringDiameter = (50 * scale).rounded()
        l.ringStroke = max(2, (3 * scale).rounded(.toNearestOrEven))
        l.iconSize = (17 * scale).rounded()
        l.labelSize = max(9, (13 * scale).rounded())
        l.labelGap = (5 * scale).rounded()
        l.itemSpacing = (18 * scale).rounded()
        l.padding = (17 * scale).rounded()
        l.cornerRadius = (26 * scale).rounded()
        l.gap = (10 * scale).rounded()
        l.bubbleGap = max(3, (4 * scale).rounded())
        l.pointerDepth = max(7, (9 * scale).rounded())
        l.pointerBreadth = max(12, (16 * scale).rounded())
        l.bubbleWidth = min(max(area.width * 0.22, 260), 400).rounded()

        let labelHeight = (l.labelSize * 1.35).rounded()
        let stacked = l.ringDiameter + l.labelGap + labelHeight   // anel com o rotulo embaixo
        // Rotulo pode ser mais largo que o anel quando chega a "100%".
        let labelWidth = (l.labelSize * 2.9).rounded()

        let itemMain = axis == .vertical ? stacked : max(l.ringDiameter, labelWidth)
        let itemCross = axis == .vertical ? l.ringDiameter : stacked

        let main = l.padding * 2 + CGFloat(count) * itemMain + CGFloat(max(0, count - 1)) * l.itemSpacing
        let cross = l.padding * 2 + itemCross

        l.railSize = axis == .vertical
            ? CGSize(width: cross.rounded(), height: main.rounded())
            : CGSize(width: main.rounded(), height: cross.rounded())

        l.tabThickness = (22 * scale).rounded()
        l.tabCornerRadius = (l.tabThickness / 2).rounded()
        l.tabLabelSize = max(8, (10 * scale).rounded())
        l.tabDot = max(4, (5 * scale).rounded())
        // Comprimento do rotulo mais o ponto de status e as folgas.
        l.tabLength = (l.tabLabelSize * 7.4 + l.tabDot + 26 * scale).rounded()
        return l
    }
}
