import Foundation

/// Um medidor pronto pra desenhar.
public struct Meter: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let ratio: Double
    /// Valor absoluto ja formatado, tipo "2.4M de 15.0M" ou "$12.30 de $50".
    public let detail: String
    public let footnote: String?
    /// Marca medidor cujo teto foi definido na mao, nao pelo provider.
    public let estimated: Bool
    /// Se este medidor pode mandar no anel da regua. Janelas informativas
    /// (dia, mes) ficam de fora: elas nao sao limite de verdade.
    public let countsForHeadline: Bool

    /// Se o denominador e uma cota de verdade. Quando falso, o percentual e
    /// so uma regua escolhida por nos e nao deve ser desenhado como limite.
    public let isQuota: Bool

    public var percent: Int { Int((ratio * 100).rounded()) }

    public init(id: String, title: String, ratio: Double, detail: String, footnote: String?, estimated: Bool, countsForHeadline: Bool, isQuota: Bool = true) {
        self.id = id
        self.title = title
        self.ratio = ratio
        self.detail = detail
        self.footnote = footnote
        self.estimated = estimated
        self.countsForHeadline = countsForHeadline
        self.isQuota = isQuota
    }
}

/// Um provider da regua: um anel, varios medidores na bolha.
public struct ProviderSummary: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case claude, minimax }

    public let kind: Kind
    public let name: String
    public let meters: [Meter]
    public let sessions: [LiveSession]
    public let warning: String?

    public var id: String { kind.rawValue }

    /// O anel mostra o medidor mais pressionado entre os que sao limite real.
    public var headline: Meter? {
        meters.filter(\.countsForHeadline).max { $0.ratio < $1.ratio } ?? meters.first
    }

    public var ratio: Double { headline?.ratio ?? 0 }
    public var percent: Int { headline?.percent ?? 0 }
    public var busyCount: Int { sessions.filter { $0.status == .busy }.count }

    public init(kind: Kind, name: String, meters: [Meter], sessions: [LiveSession], warning: String?) {
        self.kind = kind
        self.name = name
        self.meters = meters
        self.sessions = sessions
        self.warning = warning
    }
}

/// Tudo que o painel precisa, capturado num instante.
public struct DashboardSnapshot: Sendable, Equatable {
    public var providers: [ProviderSummary] = []
    public var nowPlaying: NowPlaying?
    public var shelf: [ShelfItem] = []
    public var clipboard: [ClipboardItem] = []
    public var agenda: [AgendaEvent] = []
    public var notionRecent: [NotionSavedItem] = []
    public var notionReady = false
    public var agendaAccess: AgendaAccess = .notDetermined
    public var shelfAccess: ShelfStore.Access = .ok
    public var capturedAt: Date = .distantPast
    public var errors: [String] = []

    public init() {}

    public var sessions: [LiveSession] { providers.flatMap(\.sessions) }
    public var busyCount: Int { sessions.filter { $0.status == .busy }.count }
    public var headline: Meter? { providers.compactMap(\.headline).max { $0.ratio < $1.ratio } }
}

/// Junta as fontes num snapshot. Nao toca em UI e nao guarda estado de view,
/// entao pode rodar inteiro fora da main thread.
public final class DashboardBuilder: @unchecked Sendable {
    /// Versao do formato do historico local. Mudou a retencao ou o parser,
    /// muda aqui e o cache e reconstruido do zero.
    private static let schemaVersion = 2

    private let claudeSessions = ClaudeSessionsReader()
    private let claudeUsage: ClaudeUsageReader
    private let store: UsageStore
    private let openCode = OpenCodeReader()
    private let miniMax = MiniMaxClient.shared
    private let music = NowPlayingReader()
    private let limits = ClaudeLimitsReader()
    public let shelf = ShelfStore()
    public let clipboard = ClipboardStore()
    private let agenda = AgendaReader()

    public init() {
        Self.migrateIfNeeded()
        claudeUsage = ClaudeUsageReader()
        store = UsageStore()
    }

    /// Uma mudanca de retencao so vale se o historico for relido, porque os
    /// offsets ja passaram do trecho antigo dos jsonl.
    private static func migrateIfNeeded() {
        let marker = Paths.support.appending(path: "schema")
        let current = (try? String(contentsOf: marker, encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard current != schemaVersion else { return }

        for name in ["cursors.json", "usage-history.json"] {
            try? FileManager.default.removeItem(at: Paths.support.appending(path: name))
        }
        try? "\(schemaVersion)".write(to: marker, atomically: true, encoding: .utf8)
    }

    public func build(config: Config) async -> DashboardSnapshot {
        var snap = DashboardSnapshot()
        let now = Date()

        store.ingest(claudeUsage.readNewEvents())

        let liveClaude = claudeSessions.read()
        var liveOpenCode: [LiveSession] = []
        if openCode.isAvailable {
            liveOpenCode = (try? openCode.liveSessions()) ?? []
        }

        snap.providers = [
            claudeProvider(config: config, now: now, sessions: liveClaude),
            await miniMaxProvider(config: config, now: now, sessions: liveOpenCode),
        ]
        if config.modules.contains(ModuleKind.nowPlaying.rawValue) {
            snap.nowPlaying = music.read()
        }

        if config.modules.contains(ModuleKind.notion.rawValue) {
            snap.notionReady = Secrets.read(.notion) != nil && !config.notionDatabaseID.isEmpty
            snap.notionRecent = NotionHistory.shared.current
        }

        if config.modules.contains(ModuleKind.calendar.rawValue) {
            // Pede permissão aqui de propósito: `build` já roda fora da main
            // thread, e o diálogo do sistema bloqueia quem chamou.
            agenda.requestAccessIfNeeded()
            snap.agendaAccess = agenda.access
            snap.agenda = agenda.upcoming()
        }

        if config.modules.contains(ModuleKind.clipboard.rawValue) {
            snap.clipboard = clipboard.current
        }

        if config.modules.contains(ModuleKind.shelf.rawValue) {
            snap.shelfAccess = ShelfStore.checkAccess()
            if case .ok = snap.shelfAccess {
                shelf.refresh()
                snap.shelf = shelf.current
            }
        }

        snap.capturedAt = now
        return snap
    }

    // MARK: - Claude

    private func claudeProvider(config: Config, now: Date, sessions: [LiveSession]) -> ProviderSummary {
        let real = limits.read()

        // Janelas de referencia, sempre calculadas localmente. Sao consumo, nao
        // cota: os tetos sao regua nossa.
        let reference: [(id: String, title: String, hours: Double, ceiling: Int)] = [
            ("dia", "Dia", 24, config.claudeDailyTokenCeiling),
            ("mes", "Mês", 720, config.claudeMonthlyTokenCeiling),
        ]

        var meters: [Meter] = []
        var warning: String?

        if let real {
            meters.append(contentsOf: realMeters(real))
            if real.age > 900 {
                warning = "Limites capturados há \(Format.elapsed(since: real.capturedAt)). Abra uma sessão do Claude Code para atualizar."
            }
        } else {
            meters.append(contentsOf: estimatedMeters(config: config, now: now))
            warning = "Estimativa local: os limites reais chegam pela statusline do Claude Code. Rode tools/install-statusline.sh."
        }

        meters.append(contentsOf: reference.map { w in
            let totals = store.totals(since: now.addingTimeInterval(-w.hours * 3600))
            return Meter(
                id: "claude-\(w.id)",
                title: w.title,
                ratio: clamp(Double(totals.weighted) / Double(max(1, w.ceiling))),
                detail: "\(Format.compact(totals.weighted)) / \(Format.compact(w.ceiling))",
                footnote: nil,
                estimated: true,
                countsForHeadline: false,
                isQuota: false
            )
        })

        return ProviderSummary(
            kind: .claude,
            name: "Claude",
            meters: meters,
            sessions: sessions,
            warning: warning
        )
    }

    /// Numeros oficiais do plano, vindos da statusline.
    private func realMeters(_ limits: ClaudeLimits) -> [Meter] {
        let janelas: [(id: String, title: String, window: ClaudeLimitWindow?)] = [
            ("sessao", "Sessão (5h)", limits.fiveHour),
            ("semana", "Semana", limits.sevenDay),
            ("creditos", "Créditos", limits.spend),
        ]

        return janelas.compactMap { j in
            guard let w = j.window else { return nil }
            // Janela virada: o percentual guardado descreve um ciclo que ja acabou.
            let ratio = w.rolledOver ? 0 : w.used
            // Reset a mais de um dia precisa do dia junto: "reseta 14:00" numa
            // janela que vira daqui a seis dias induz a erro.
            let footnote = w.rolledOver
                ? "janela virou"
                : w.resetsAt.map { reset in
                    let distante = reset.timeIntervalSinceNow > 20 * 3600
                    return "reseta \(distante ? Format.day(reset) : Format.clock(reset))"
                }
            return Meter(
                id: "claude-\(j.id)",
                title: j.title,
                ratio: ratio,
                detail: "\(Int(ratio * 100))% do plano",
                footnote: footnote,
                estimated: false,
                countsForHeadline: true,
                isQuota: true
            )
        }
    }

    /// Reserva para quando a statusline ainda nao esta instalada.
    private func estimatedMeters(config: Config, now: Date) -> [Meter] {
        let windows: [(id: String, title: String, hours: Double, ceiling: Int, headline: Bool)] = [
            ("sessao", "Sessão (5h)", 5, config.claudeFiveHourTokenCeiling, true),
            ("semana", "Semana", 168, config.claudeWeeklyTokenCeiling, true),
        ]

        return windows.map { w -> Meter in
            let totals = store.totals(since: now.addingTimeInterval(-w.hours * 3600))
            return Meter(
                id: "claude-\(w.id)",
                title: w.title,
                ratio: clamp(Double(totals.weighted) / Double(max(1, w.ceiling))),
                detail: "\(Format.compact(totals.weighted)) / \(Format.compact(w.ceiling))",
                footnote: w.id == "sessao" ? resetFootnote() : nil,
                estimated: true,
                countsForHeadline: w.headline,
                // Dia e Mes nao correspondem a nenhuma janela de cota da
                // Anthropic: sao consumo, e o teto e regua definida na mao.
                isQuota: w.headline
            )
        }

    }

    private func resetFootnote() -> String {
        guard let start = store.windowStart(hours: 5) else { return "janela ociosa" }
        return "reseta \(Format.clock(start.addingTimeInterval(5 * 3600)))"
    }

    // MARK: - MiniMax

    private func miniMaxProvider(config: Config, now: Date, sessions: [LiveSession]) async -> ProviderSummary {
        var meters: [Meter] = []
        var warning: String?

        let (quota, error) = await miniMax.quota()

        if let quota {
            meters.append(Meter(
                id: "minimax-intervalo",
                title: "Intervalo atual",
                ratio: quota.intervalUsed,
                detail: "\(Int((1 - quota.intervalUsed) * 100))% restante",
                footnote: quota.intervalResetsAt.map { "reseta \(Format.clock($0))" },
                estimated: false,
                countsForHeadline: true,
                isQuota: true
            ))
            meters.append(Meter(
                id: "minimax-semana",
                title: "Semana",
                ratio: quota.weeklyUsed,
                detail: "\(Int((1 - quota.weeklyUsed) * 100))% restante",
                footnote: quota.weeklyResetsAt.map { "reseta \(Format.day($0))" },
                estimated: false,
                countsForHeadline: true,
                isQuota: true
            ))
        } else if let error {
            warning = "Cota indisponível: \(error)"
        }

        // Gasto vem do opencode.db, que e a fonte local de custo por mensagem.
        if openCode.isAvailable, let month = try? openCode.spendThisMonth() {
            meters.append(Meter(
                id: "minimax-mes",
                title: "Gasto do mês",
                ratio: clamp(month / max(0.01, config.openCodeMonthlyBudgetUSD)),
                detail: "\(Format.usd(month)) / \(Format.usd(config.openCodeMonthlyBudgetUSD))",
                footnote: Format.monthName(now),
                estimated: true,
                countsForHeadline: false,
                isQuota: false
            ))
        }

        if meters.isEmpty {
            meters.append(Meter(
                id: "minimax-vazio", title: "Sem dados", ratio: 0,
                detail: "—", footnote: nil, estimated: true,
                countsForHeadline: false, isQuota: false
            ))
        }

        return ProviderSummary(
            kind: .minimax,
            name: "MiniMax",
            meters: meters,
            sessions: sessions,
            warning: warning ?? "Orçamento mensal definido em config.json."
        )
    }

    private func clamp(_ v: Double) -> Double {
        v.isFinite ? max(0, min(1, v)) : 0
    }
}

public enum Format {
    public static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.0fk", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }

    public static func usd(_ v: Double) -> String {
        v >= 100 ? String(format: "$%.0f", v) : String(format: "$%.2f", v)
    }

    public static func clock(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }

    public static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEE HH:mm"
        return f.string(from: d).capitalized
    }

    public static func monthName(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "MMMM"
        return f.string(from: d).capitalized
    }

    public static func elapsed(since: Date) -> String {
        let s = Int(Date().timeIntervalSince(since))
        switch s {
        case ..<60:    return "agora"
        case ..<3600:  return "\(s / 60)min"
        case ..<86400: return "\(s / 3600)h"
        default:       return "\(s / 86400)d"
        }
    }
}
