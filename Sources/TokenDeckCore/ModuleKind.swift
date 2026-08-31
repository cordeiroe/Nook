import Foundation

/// Blocos que o cartao do notch pode mostrar, na ordem definida em config.
/// Cada um e independente: se a fonte falhar, o bloco some e o resto fica.
public enum ModuleKind: String, Codable, Sendable, CaseIterable {
    case usage
    case sessions
    case nowPlaying
    case calendar
    case clipboard
    case shelf
    case notion

    public var label: String {
        switch self {
        case .usage:      return "Consumo"
        case .sessions:   return "Sessões"
        case .nowPlaying: return "Tocando"
        case .calendar:   return "Agenda"
        case .clipboard:  return "Transferência"
        case .shelf:      return "Prateleira"
        case .notion:     return "Notion"
        }
    }

    /// Modulos ainda nao implementados aparecem na config mas nao desenham nada.
    public var isImplemented: Bool {
        switch self {
        case .usage, .sessions, .nowPlaying, .shelf, .clipboard: return true
        case .calendar, .notion: return false
        }
    }
}
