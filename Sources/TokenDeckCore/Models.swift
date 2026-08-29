import Foundation

/// Contagem de tokens agregada, comum a Claude e opencode.
public struct TokenTotals: Sendable, Equatable, Codable {
    public var input: Int = 0
    public var output: Int = 0
    public var cacheRead: Int = 0
    public var cacheWrite: Int = 0
    public var reasoning: Int = 0

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, reasoning: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
    }

    /// Soma bruta. Cache read entra aqui, mas custa uma fracao do input normal.
    public var total: Int { input + output + cacheRead + cacheWrite }

    /// Aproximacao do que efetivamente pesa na cota: cache read sai barato.
    public var weighted: Int { input + output + cacheWrite + cacheRead / 10 }

    public static func + (lhs: TokenTotals, rhs: TokenTotals) -> TokenTotals {
        TokenTotals(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }

    public static func += (lhs: inout TokenTotals, rhs: TokenTotals) { lhs = lhs + rhs }
}

/// Um turno de assistant ja parseado, a unidade minima do historico.
public struct UsageEvent: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let model: String
    public let project: String
    public let sessionID: String
    public let requestID: String?
    public let tokens: TokenTotals

    public init(timestamp: Date, model: String, project: String, sessionID: String, requestID: String?, tokens: TokenTotals) {
        self.timestamp = timestamp
        self.model = model
        self.project = project
        self.sessionID = sessionID
        self.requestID = requestID
        self.tokens = tokens
    }
}

public enum SessionStatus: String, Sendable, Codable {
    case idle, busy, unknown

    public init(raw: String?) {
        switch raw {
        case "idle": self = .idle
        case "busy": self = .busy
        default: self = .unknown
        }
    }
}

/// Sessao viva de qualquer provider, ja normalizada pra UI.
public struct LiveSession: Sendable, Equatable, Identifiable {
    public enum Provider: String, Sendable { case claude, opencode }

    public let id: String
    public let provider: Provider
    public let name: String
    /// Titulo gerado pela propria IA, quando existe. Bem mais legivel que o
    /// nome derivado do diretorio.
    public let title: String?
    public let directory: String
    public let status: SessionStatus
    public let startedAt: Date?
    public let updatedAt: Date
    /// Desde quando esta neste status. Da o "ocupada ha 12min".
    public let statusSince: Date?
    public let model: String?
    public let pid: Int32?

    public init(id: String, provider: Provider, name: String, title: String? = nil, directory: String, status: SessionStatus, startedAt: Date?, updatedAt: Date, statusSince: Date? = nil, model: String?, pid: Int32?) {
        self.id = id
        self.provider = provider
        self.name = name
        self.title = title
        self.directory = directory
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.statusSince = statusSince
        self.model = model
        self.pid = pid
    }

    /// O que mostrar na tela.
    public var label: String { title ?? name }

    /// Ultimo componente do path, pra caber no menu bar.
    public var shortDirectory: String {
        (directory as NSString).lastPathComponent
    }
}
