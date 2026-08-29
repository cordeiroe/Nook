import SwiftUI
import TokenDeckCore

enum Theme {
    static let panelWidth: CGFloat = 340

    /// Verde ate 50%, ambar ate 75%, vermelho depois.
    /// O olho le a cor antes do numero, entao o corte fica cedo de proposito.
    static func tint(for ratio: Double) -> Color {
        switch ratio {
        case ..<0.50: return Color(red: 0.20, green: 0.86, blue: 0.50)
        case ..<0.75: return Color(red: 0.98, green: 0.85, blue: 0.20)
        default:      return Color(red: 0.98, green: 0.32, blue: 0.16)
        }
    }

    /// Cor do arco de alerta no notch. Separada da escala geral porque ela
    /// so aparece acima de 80%, onde `tint` ja saturou em vermelho.
    static func alertTint(_ ratio: Double) -> Color {
        ratio < 0.92
            ? Color(red: 0.98, green: 0.72, blue: 0.20)
            : Color(red: 0.98, green: 0.32, blue: 0.16)
    }

    static func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .busy:    return Color(red: 0.98, green: 0.72, blue: 0.25)
        case .idle:    return Color(red: 0.20, green: 0.86, blue: 0.50)
        case .unknown: return .secondary
        }
    }

    static func symbol(for kind: ProviderSummary.Kind) -> String {
        switch kind {
        case .claude:  return "asterisk"
        case .minimax: return "hexagon"
        }
    }
}
