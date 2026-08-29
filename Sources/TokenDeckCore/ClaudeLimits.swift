import Foundation

public struct ClaudeLimitWindow: Sendable, Equatable {
    /// 0 a 1.
    public let used: Double
    public let resetsAt: Date?

    /// A janela ja virou depois da ultima captura, entao o percentual guardado
    /// nao vale mais nada.
    public var rolledOver: Bool {
        guard let resetsAt else { return false }
        return resetsAt < Date()
    }
}

/// Limites reais do plano, capturados da statusline do Claude Code.
///
/// Esta e a unica fonte oficial desses numeros para planos Pro e Max. A Admin
/// API de usage cobre organizacoes de API, nao contas do claude.ai, e nao
/// existe endpoint publico para o consumo de um plano individual.
///
/// Depende do script `tools/tokendeck-statusline.sh` estar instalado como
/// statusline. Sem nenhuma sessao do Claude Code aberta o arquivo envelhece,
/// entao `capturedAt` precisa aparecer na interface.
public struct ClaudeLimits: Sendable, Equatable {
    public let fiveHour: ClaudeLimitWindow?
    public let sevenDay: ClaudeLimitWindow?
    public let spend: ClaudeLimitWindow?
    public let capturedAt: Date

    public var age: TimeInterval { Date().timeIntervalSince(capturedAt) }
}

public struct ClaudeLimitsReader: Sendable {
    private struct Payload: Decodable {
        struct Window: Decodable {
            let used_percentage: Double?
            let resets_at: Double?
        }
        struct Limits: Decodable {
            let five_hour: Window?
            let seven_day: Window?
            let spend_limit: Window?
        }
        let rate_limits: Limits?
    }

    public init() {}

    public var file: URL { Paths.support.appending(path: "claude-limits.json") }

    public var isInstalled: Bool {
        FileManager.default.fileExists(atPath: file.path)
    }

    public func read() -> ClaudeLimits? {
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data),
              let limits = decoded.rate_limits
        else { return nil }

        // O payload nao carrega horario, entao a idade vem do arquivo.
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        return ClaudeLimits(
            fiveHour: window(limits.five_hour),
            sevenDay: window(limits.seven_day),
            spend: window(limits.spend_limit),
            capturedAt: mtime
        )
    }

    private func window(_ raw: Payload.Window?) -> ClaudeLimitWindow? {
        guard let raw, let percent = raw.used_percentage else { return nil }
        return ClaudeLimitWindow(
            used: min(max(percent / 100, 0), 1),
            resetsAt: raw.resets_at.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
