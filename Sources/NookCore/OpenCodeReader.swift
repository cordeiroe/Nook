import Foundation
import SQLite3

/// Sessao do opencode. Os campos de token e custo aqui sao acumulados desde a criacao
/// da sessao, entao servem pra ranking historico, nunca pra gasto de um periodo.
public struct OpenCodeSession: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let directory: String
    public let modelID: String
    public let providerID: String
    public let agent: String?
    public let lifetimeCost: Double
    public let lifetimeTokens: TokenTotals
    public let createdAt: Date
    public let updatedAt: Date
    public let archived: Bool

    public init(id: String, title: String, directory: String, modelID: String, providerID: String, agent: String?, lifetimeCost: Double, lifetimeTokens: TokenTotals, createdAt: Date, updatedAt: Date, archived: Bool) {
        self.id = id
        self.title = title
        self.directory = directory
        self.modelID = modelID
        self.providerID = providerID
        self.agent = agent
        self.lifetimeCost = lifetimeCost
        self.lifetimeTokens = lifetimeTokens
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archived = archived
    }
}

/// Consumo agregado num intervalo. Vem da tabela `message`, onde cada turno
/// carrega o proprio custo, e nao dos totais da sessao.
public struct OpenCodeUsage: Sendable, Equatable {
    public var cost: Double = 0
    public var tokens: TokenTotals = TokenTotals()
    public var messages: Int = 0

    public init(cost: Double = 0, tokens: TokenTotals = TokenTotals(), messages: Int = 0) {
        self.cost = cost
        self.tokens = tokens
        self.messages = messages
    }
}

public enum OpenCodeError: Error, CustomStringConvertible {
    case cannotOpen(String)
    case query(String)

    public var description: String {
        switch self {
        case .cannotOpen(let m): return "nao consegui abrir opencode.db: \(m)"
        case .query(let m): return "query falhou: \(m)"
        }
    }
}

/// Abre o opencode.db em read-only. Nunca escreve e nunca segura a conexao entre
/// chamadas: o opencode roda em WAL e uma conexao viva atrapalha o checkpoint dele.
public struct OpenCodeReader: Sendable {
    public let dbPath: URL

    public init(dbPath: URL = Paths.openCodeDB) {
        self.dbPath = dbPath
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: dbPath.path)
    }

    // MARK: - Consumo por periodo

    private static let usageColumns = """
        COALESCE(SUM(json_extract(data,'$.cost')), 0),
        COALESCE(SUM(json_extract(data,'$.tokens.input')), 0),
        COALESCE(SUM(json_extract(data,'$.tokens.output')), 0),
        COALESCE(SUM(json_extract(data,'$.tokens.reasoning')), 0),
        COALESCE(SUM(json_extract(data,'$.tokens.cache.read')), 0),
        COALESCE(SUM(json_extract(data,'$.tokens.cache.write')), 0),
        COUNT(*)
        """

    public func usage(since: Date) throws -> OpenCodeUsage {
        let sql = """
        SELECT \(Self.usageColumns)
        FROM message
        WHERE time_created >= ? AND json_extract(data,'$.role') = 'assistant'
        """
        return try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, Self.millis(since))
            guard sqlite3_step(stmt) == SQLITE_ROW else { return OpenCodeUsage() }
            return Self.usage(from: stmt, offset: 0)
        }
    }

    public func usageByModel(since: Date) throws -> [String: OpenCodeUsage] {
        let sql = """
        SELECT json_extract(data,'$.providerID') || '/' || json_extract(data,'$.modelID'),
               \(Self.usageColumns)
        FROM message
        WHERE time_created >= ? AND json_extract(data,'$.role') = 'assistant'
        GROUP BY 1
        """
        return try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, Self.millis(since))
            var out: [String: OpenCodeUsage] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let key = Self.text(stmt, 0) ?? "desconhecido"
                out[key] = Self.usage(from: stmt, offset: 1)
            }
            return out
        }
    }

    /// Atalho pro anel de orcamento.
    public func spend(since: Date) throws -> Double {
        try usage(since: since).cost
    }

    /// Gasto do mes corrente, no fuso local, que e como a fatura conta.
    public func spendThisMonth(calendar: Calendar = .current) throws -> Double {
        let start = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        return try spend(since: start)
    }

    // MARK: - Sessoes

    public func sessions(updatedSince: Date, limit: Int = 200) throws -> [OpenCodeSession] {
        let sql = """
        SELECT id, title, directory, model, agent, cost,
               tokens_input, tokens_output, tokens_reasoning,
               tokens_cache_read, tokens_cache_write,
               time_created, time_updated, time_archived
        FROM session
        WHERE time_updated >= ?
        ORDER BY time_updated DESC
        LIMIT ?
        """
        return try withStatement(sql) { stmt in
            sqlite3_bind_int64(stmt, 1, Self.millis(updatedSince))
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var out: [OpenCodeSession] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let (modelID, providerID) = Self.parseModel(Self.text(stmt, 3) ?? "")
                out.append(OpenCodeSession(
                    id: Self.text(stmt, 0) ?? "",
                    title: Self.text(stmt, 1) ?? "(sem titulo)",
                    directory: Self.text(stmt, 2) ?? "",
                    modelID: modelID,
                    providerID: providerID,
                    agent: Self.text(stmt, 4),
                    lifetimeCost: sqlite3_column_double(stmt, 5),
                    lifetimeTokens: TokenTotals(
                        input: Int(sqlite3_column_int64(stmt, 6)),
                        output: Int(sqlite3_column_int64(stmt, 7)),
                        cacheRead: Int(sqlite3_column_int64(stmt, 9)),
                        cacheWrite: Int(sqlite3_column_int64(stmt, 10)),
                        reasoning: Int(sqlite3_column_int64(stmt, 8))
                    ),
                    createdAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 11)) / 1000),
                    updatedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 12)) / 1000),
                    archived: sqlite3_column_type(stmt, 13) != SQLITE_NULL
                ))
            }
            return out
        }
    }

    /// O opencode nao grava status de sessao. Processo vivo + recencia e o melhor sinal.
    public func liveSessions(idleWindow: TimeInterval = 900) throws -> [LiveSession] {
        guard Self.openCodeIsRunning() else { return [] }
        let recent = try sessions(updatedSince: Date().addingTimeInterval(-idleWindow), limit: 20)
        return recent.filter { !$0.archived }.map { s in
            LiveSession(
                id: s.id,
                provider: .opencode,
                name: s.title,
                directory: s.directory,
                status: Date().timeIntervalSince(s.updatedAt) < 45 ? .busy : .idle,
                startedAt: s.createdAt,
                updatedAt: s.updatedAt,
                model: s.modelID,
                pid: nil
            )
        }
    }

    // MARK: - Conexao

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer?) throws -> T) throws -> T {
        var db: OpaquePointer?
        let uri = "file:\(dbPath.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "erro desconhecido"
            sqlite3_close_v2(db)
            throw OpenCodeError.cannotOpen(msg)
        }
        defer { sqlite3_close_v2(db) }
        sqlite3_busy_timeout(db, 2000)

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw OpenCodeError.query(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        return try body(stmt)
    }

    // MARK: - Helpers

    private static func millis(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: c)
    }

    private static func usage(from stmt: OpaquePointer?, offset: Int32) -> OpenCodeUsage {
        OpenCodeUsage(
            cost: sqlite3_column_double(stmt, offset),
            tokens: TokenTotals(
                input: Int(sqlite3_column_int64(stmt, offset + 1)),
                output: Int(sqlite3_column_int64(stmt, offset + 2)),
                cacheRead: Int(sqlite3_column_int64(stmt, offset + 4)),
                cacheWrite: Int(sqlite3_column_int64(stmt, offset + 5)),
                reasoning: Int(sqlite3_column_int64(stmt, offset + 3))
            ),
            messages: Int(sqlite3_column_int64(stmt, offset + 6))
        )
    }

    /// A coluna `model` guarda JSON: {"id":"MiniMax-M3","providerID":"minimax","variant":"..."}
    private static func parseModel(_ json: String) -> (String, String) {
        guard
            let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (json, "") }
        return (obj["id"] as? String ?? "", obj["providerID"] as? String ?? "")
    }

    private static func openCodeIsRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", "opencode"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
