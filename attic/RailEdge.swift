import AppKit
import SwiftUI

/// Borda da tela onde a regua fica ancorada.
/// Nas bordas laterais ela e uma coluna; no topo e na base, uma barra.
enum RailEdge: String, Codable, CaseIterable {
    case left, right, top, bottom

    var axis: Axis { (self == .left || self == .right) ? .vertical : .horizontal }

    /// De que lado da regua a bolha de detalhe abre.
    var bubbleDirection: BubbleDirection {
        switch self {
        case .left:   return .right
        case .right:  return .left
        case .top:    return .down
        case .bottom: return .up
        }
    }

    /// Centro do widget ao longo da borda. `fraction` vai de 0 a 1 e e sempre
    /// medida contra o tamanho da regua, nunca da aba: assim recolher e expandir
    /// mantem o mesmo centro em vez de fazer o widget saltar.
    func centerAlong(in area: CGRect, railSize: CGSize, fraction: Double) -> CGFloat {
        let f = min(max(fraction, 0), 1)
        let start = axis == .vertical ? area.minY : area.minX
        let extent = axis == .vertical ? railSize.height : railSize.width
        return start + travel(in: area, railSize: railSize) * f + extent / 2
    }

    /// Coloca um widget de tamanho `size` colado nesta borda, centrado em
    /// `centerAlong`, sem deixar nenhuma parte sair da area util.
    func frame(in area: CGRect, size: CGSize, centerAlong center: CGFloat) -> CGRect {
        let origin: CGPoint
        switch self {
        case .left:
            origin = CGPoint(x: area.minX, y: clamp(center - size.height / 2, area.minY, area.maxY - size.height))
        case .right:
            origin = CGPoint(x: area.maxX - size.width, y: clamp(center - size.height / 2, area.minY, area.maxY - size.height))
        case .bottom:
            origin = CGPoint(x: clamp(center - size.width / 2, area.minX, area.maxX - size.width), y: area.minY)
        case .top:
            origin = CGPoint(x: clamp(center - size.width / 2, area.minX, area.maxX - size.width), y: area.maxY - size.height)
        }
        return CGRect(origin: origin, size: size)
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), max(lo, hi))
    }

    /// Quanto a regua pode deslizar ao longo desta borda.
    func travel(in area: CGRect, railSize: CGSize) -> CGFloat {
        axis == .vertical
            ? max(0, area.height - railSize.height)
            : max(0, area.width - railSize.width)
    }

    /// Inverso de `centerAlong`: converte um centro em tela na fracao guardada.
    func fraction(centerAlong center: CGFloat, in area: CGRect, railSize: CGSize) -> Double {
        let total = travel(in: area, railSize: railSize)
        guard total > 0 else { return 0.5 }
        let start = axis == .vertical ? area.minY : area.minX
        let extent = axis == .vertical ? railSize.height : railSize.width
        return Double(min(max((center - extent / 2 - start) / total, 0), 1))
    }

    /// Centro de um retangulo ao longo desta borda.
    func center(of rect: CGRect) -> CGFloat {
        axis == .vertical ? rect.midY : rect.midX
    }

    /// Borda mais proxima, medida pela distancia de cada lado da regua
    /// ate o lado correspondente da area util.
    static func nearest(to rect: CGRect, in area: CGRect) -> RailEdge {
        let distances: [(RailEdge, CGFloat)] = [
            (.left,   rect.minX - area.minX),
            (.right,  area.maxX - rect.maxX),
            (.bottom, rect.minY - area.minY),
            (.top,    area.maxY - rect.maxY),
        ]
        return distances.min { $0.1 < $1.1 }?.0 ?? .right
    }
}

enum BubbleDirection {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
}
