import Foundation

/// Preferencias do usuario, em JSON pra poder editar na mao enquanto nao ha tela de ajustes.
public struct Config: Codable, Sendable, Equatable {
    /// Teto mensal em USD pro opencode. Vira o denominador do anel de gasto.
    public var openCodeMonthlyBudgetUSD: Double = 50

    /// Fallback pro caso do endpoint de cota do Claude nao responder:
    /// teto de tokens ponderados na janela de 5h, calibrado na mao.
    public var claudeFiveHourTokenCeiling: Int = 15_000_000

    /// Idem, pra janela semanal.
    public var claudeWeeklyTokenCeiling: Int = 90_000_000

    /// Tetos de referencia pras janelas de dia e mes. Nao sao limites da
    /// Anthropic, sao regua de consumo definida por ti.
    public var claudeDailyTokenCeiling: Int = 45_000_000
    public var claudeMonthlyTokenCeiling: Int = 350_000_000

    /// Intervalo de atualizacao do painel, em segundos.
    public var refreshInterval: Double = 15

    /// Modulos do cartao, na ordem em que aparecem. Ver `ModuleKind`.
    public var modules: [String] = [
        ModuleKind.usage.rawValue,
        ModuleKind.sessions.rawValue,
        ModuleKind.nowPlaying.rawValue,
        ModuleKind.clipboard.rawValue,
        ModuleKind.shelf.rawValue,
    ]

    /// Quanto tempo o histórico da área de transferência sobrevive. Curto de
    /// propósito: é a última defesa contra um segredo que escapou dos filtros.
    public var clipboardRetentionHours: Double = 8
    public var clipboardMaxItems: Int = 40

    /// Cópias vindas destes aplicativos nunca são guardadas, tenham marcador
    /// de conteúdo protegido ou não.
    public var clipboardIgnoredApps: [String] = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
        "me.proton.pass.electron",
    ]

    /// A partir de que fracao o notch acende o arco de alerta.
    public var alertThreshold: Double = 0.80

    /// Painel do notch ligado.
    public var panelEnabled: Bool = true

    /// CGDirectDisplayID do monitor que hospeda o painel.
    /// nil = a tela com notch fisico, ou a principal se nenhuma tiver.
    public var notchScreenNumber: Int? = nil

    public init() {}

    // MARK: - Decode tolerante
    //
    // O JSONDecoder ignora os defaults declarados acima e falha em keyNotFound.
    // Sem decodeIfPresent, qualquer campo novo invalidaria o config.json ja
    // gravado do usuario e as preferencias voltariam pro padrao sem aviso.

    private enum CodingKeys: String, CodingKey {
        case openCodeMonthlyBudgetUSD, claudeFiveHourTokenCeiling, claudeWeeklyTokenCeiling
        case claudeDailyTokenCeiling, claudeMonthlyTokenCeiling
        case refreshInterval, panelEnabled, notchScreenNumber, modules, alertThreshold
        case clipboardRetentionHours, clipboardMaxItems, clipboardIgnoredApps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Config()

        openCodeMonthlyBudgetUSD = try c.decodeIfPresent(Double.self, forKey: .openCodeMonthlyBudgetUSD) ?? fallback.openCodeMonthlyBudgetUSD
        claudeFiveHourTokenCeiling = try c.decodeIfPresent(Int.self, forKey: .claudeFiveHourTokenCeiling) ?? fallback.claudeFiveHourTokenCeiling
        claudeWeeklyTokenCeiling = try c.decodeIfPresent(Int.self, forKey: .claudeWeeklyTokenCeiling) ?? fallback.claudeWeeklyTokenCeiling
        claudeDailyTokenCeiling = try c.decodeIfPresent(Int.self, forKey: .claudeDailyTokenCeiling) ?? fallback.claudeDailyTokenCeiling
        claudeMonthlyTokenCeiling = try c.decodeIfPresent(Int.self, forKey: .claudeMonthlyTokenCeiling) ?? fallback.claudeMonthlyTokenCeiling
        refreshInterval = try c.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? fallback.refreshInterval
        panelEnabled = try c.decodeIfPresent(Bool.self, forKey: .panelEnabled) ?? fallback.panelEnabled
        modules = try c.decodeIfPresent([String].self, forKey: .modules) ?? fallback.modules
        alertThreshold = try c.decodeIfPresent(Double.self, forKey: .alertThreshold) ?? fallback.alertThreshold
        clipboardRetentionHours = try c.decodeIfPresent(Double.self, forKey: .clipboardRetentionHours) ?? fallback.clipboardRetentionHours
        clipboardMaxItems = try c.decodeIfPresent(Int.self, forKey: .clipboardMaxItems) ?? fallback.clipboardMaxItems
        clipboardIgnoredApps = try c.decodeIfPresent([String].self, forKey: .clipboardIgnoredApps) ?? fallback.clipboardIgnoredApps
        notchScreenNumber = try c.decodeIfPresent(Int.self, forKey: .notchScreenNumber)
    }

    // MARK: - Disco

    private static var url: URL { Paths.support.appending(path: "config.json") }

    public static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            // Config corrompido nao pode derrubar o app: cai no padrao e segue.
            FileHandle.standardError.write(Data("TokenDeck: config.json invalido (\(error)), usando padroes\n".utf8))
            return Config()
        }
    }

    public func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }
}
