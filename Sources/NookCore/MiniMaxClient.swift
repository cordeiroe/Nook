import Foundation

/// Cota da MiniMax lida do endpoint de assinatura.
public struct MiniMaxQuota: Sendable, Equatable {
    public let modelName: String
    /// 0 a 1. Vem de 100 menos o percentual restante que a API informa.
    public let intervalUsed: Double
    public let intervalResetsAt: Date?
    public let weeklyUsed: Double
    public let weeklyResetsAt: Date?
    public let fetchedAt: Date
}

public enum MiniMaxError: Error, CustomStringConvertible {
    case noKey
    case http(Int)
    case api(Int, String)
    case emptyPlan
    case transport(String)

    public var description: String {
        switch self {
        case .noKey:            return "chave da MiniMax ausente no Keychain"
        case .http(let c):      return "HTTP \(c)"
        case .api(let c, let m): return "API \(c): \(m)"
        case .emptyPlan:        return "nenhum plano ativo na resposta"
        case .transport(let m): return m
        }
    }
}

/// Cliente do endpoint de cota. Guarda o ultimo resultado em memoria: o painel
/// atualiza a cada 15s e nao faz sentido bater na API nessa frequencia.
public actor MiniMaxClient {
    public static let shared = MiniMaxClient()

    private static let endpoint = URL(string: "https://www.minimax.io/v1/token_plan/remains")!
    private static let minimumInterval: TimeInterval = 90

    private var cached: MiniMaxQuota?
    private var lastAttempt: Date = .distantPast
    private var lastError: MiniMaxError?
    private var refresh: Task<Void, Never>?
    private var observers: [@Sendable () -> Void] = []

    public init() {}

    /// Avisa quem depende da cota assim que ela chega. Sem isto o painel
    /// mostraria o MiniMax incompleto ate o proximo ciclo de 15s.
    public func onUpdate(_ callback: @escaping @Sendable () -> Void) {
        observers.append(callback)
    }

    /// Devolve o que ja tem e dispara a atualizacao em segundo plano.
    /// Nao espera pela rede: o painel atualiza a cada 15s e travar o snapshot
    /// numa chamada HTTP deixaria a regua vazia enquanto ela nao volta.
    public func quota() async -> (value: MiniMaxQuota?, error: MiniMaxError?) {
        if refresh == nil, Date().timeIntervalSince(lastAttempt) >= Self.minimumInterval {
            startRefresh()
        }
        return (cached, cached == nil ? lastError : nil)
    }

    /// Espera a atualizacao terminar. So pra ferramenta de linha de comando,
    /// que e um processo curto e nao tem um segundo ciclo pra aproveitar.
    public func quotaBlocking() async -> (value: MiniMaxQuota?, error: MiniMaxError?) {
        if refresh == nil, Date().timeIntervalSince(lastAttempt) >= Self.minimumInterval {
            startRefresh()
        }
        await refresh?.value
        return (cached, cached == nil ? lastError : nil)
    }

    private func startRefresh() {
        lastAttempt = Date()
        refresh = Task { [weak self] in
            guard let self else { return }
            do {
                let fresh = try await self.fetch()
                await self.finish(value: fresh, error: nil)
            } catch let error as MiniMaxError {
                if case .http(401) = error { Secrets.invalidate(.minimax) }
                await self.finish(value: nil, error: error)
            } catch {
                await self.finish(value: nil, error: .transport(error.localizedDescription))
            }
        }
    }

    /// Falha nao apaga o ultimo valor bom: um blip de rede nao deve zerar o medidor.
    private func finish(value: MiniMaxQuota?, error: MiniMaxError?) {
        if let value { cached = value }
        lastError = error
        refresh = nil
        observers.forEach { $0() }
    }

    // MARK: - Rede

    private struct Response: Decodable {
        struct Entry: Decodable {
            let model_name: String?
            let end_time: Double?
            let weekly_end_time: Double?
            let current_interval_remaining_percent: Double?
            let current_weekly_remaining_percent: Double?
            let current_interval_status: Int?
        }
        struct Base: Decodable {
            let status_code: Int?
            let status_msg: String?
        }
        let model_remains: [Entry]?
        let base_resp: Base?
    }

    private func fetch() async throws -> MiniMaxQuota {
        guard let key = Secrets.read(.minimax) else { throw MiniMaxError.noKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MiniMaxError.http(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if let code = decoded.base_resp?.status_code, code != 0 {
            throw MiniMaxError.api(code, decoded.base_resp?.status_msg ?? "sem mensagem")
        }

        // "general" e o plano de texto. Entradas com status != 1 sao modalidades
        // fora do plano e vem sempre com 100% restante, o que falsearia o medidor.
        let entries = decoded.model_remains ?? []
        guard let entry = entries.first(where: { $0.model_name == "general" && $0.current_interval_status == 1 })
                ?? entries.first(where: { $0.current_interval_status == 1 })
        else { throw MiniMaxError.emptyPlan }

        return MiniMaxQuota(
            modelName: entry.model_name ?? "general",
            intervalUsed: used(entry.current_interval_remaining_percent),
            intervalResetsAt: date(entry.end_time),
            weeklyUsed: used(entry.current_weekly_remaining_percent),
            weeklyResetsAt: date(entry.weekly_end_time),
            fetchedAt: Date()
        )
    }

    private func used(_ remainingPercent: Double?) -> Double {
        guard let remaining = remainingPercent else { return 0 }
        return min(max((100 - remaining) / 100, 0), 1)
    }

    private func date(_ millis: Double?) -> Date? {
        guard let millis, millis > 0 else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }
}
