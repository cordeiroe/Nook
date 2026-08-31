import Foundation

/// Le incrementalmente os .jsonl de ~/.claude/projects, guardando offset por arquivo.
/// Nunca reprocessa o que ja leu, entao o custo por refresh e proporcional ao que chegou.
public final class ClaudeUsageReader: @unchecked Sendable {

    private struct Cursor: Codable {
        var offset: UInt64
        var inode: UInt64
    }

    private var cursors: [String: Cursor] = [:]
    private let cursorFile: URL
    private let iso: ISO8601DateFormatter

    public init() {
        cursorFile = Paths.support.appending(path: "cursors.json")
        iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        loadCursors()
    }

    // MARK: - Linha do jsonl

    private struct Line: Decodable {
        let type: String?
        let timestamp: String?
        let sessionId: String?
        let requestId: String?
        let message: Message?

        struct Message: Decodable {
            let model: String?
            let usage: Usage?
        }

        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_read_input_tokens: Int?
            let cache_creation_input_tokens: Int?
            let output_tokens_details: Details?

            struct Details: Decodable { let thinking_tokens: Int? }
        }
    }

    // MARK: - Leitura

    /// Devolve so os eventos novos desde a ultima chamada.
    public func readNewEvents() -> [UsageEvent] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: Paths.claudeProjects,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var events: [UsageEvent] = []

        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let project = dir.lastPathComponent
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                events.append(contentsOf: readDelta(of: file, project: project))
            }
        }

        saveCursors()
        return events
    }

    private func readDelta(of url: URL, project: String) -> [UsageEvent] {
        let key = url.path
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let attrs = try? FileManager.default.attributesOfItem(atPath: key)
        let inode = (attrs?[.systemFileNumber] as? UInt64) ?? 0
        let size = (attrs?[.size] as? UInt64) ?? 0

        var cursor = cursors[key] ?? Cursor(offset: 0, inode: inode)
        // Arquivo trocado ou truncado: recomeca do zero.
        if cursor.inode != inode || cursor.offset > size {
            cursor = Cursor(offset: 0, inode: inode)
        }
        guard cursor.offset < size else { return [] }

        try? handle.seek(toOffset: cursor.offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        // Para na ultima quebra de linha: o Claude Code pode estar escrevendo agora.
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return [] }
        let complete = data[data.startIndex...lastNewline]
        cursor.offset += UInt64(complete.count)
        cursors[key] = cursor

        return parse(complete, project: project)
    }

    private func parse(_ data: Data, project: String) -> [UsageEvent] {
        let decoder = JSONDecoder()
        var out: [UsageEvent] = []

        for chunk in data.split(separator: 0x0A) {
            // Filtro barato antes de pagar o custo do JSONDecoder.
            guard chunk.count > 40, chunk.contains(subsequence: Self.assistantMarker) else { continue }
            guard
                let line = try? decoder.decode(Line.self, from: Data(chunk)),
                line.type == "assistant",
                let usage = line.message?.usage,
                let ts = line.timestamp.flatMap({ iso.date(from: $0) })
            else { continue }

            let tokens = TokenTotals(
                input: usage.input_tokens ?? 0,
                output: usage.output_tokens ?? 0,
                cacheRead: usage.cache_read_input_tokens ?? 0,
                cacheWrite: usage.cache_creation_input_tokens ?? 0,
                reasoning: usage.output_tokens_details?.thinking_tokens ?? 0
            )
            guard tokens.total > 0 else { continue }

            out.append(UsageEvent(
                timestamp: ts,
                model: line.message?.model ?? "unknown",
                project: project,
                sessionID: line.sessionId ?? "",
                requestID: line.requestId,
                tokens: tokens
            ))
        }

        return out
    }

    private static let assistantMarker = Array("\"assistant\"".utf8)

    // MARK: - Persistencia dos offsets

    private func loadCursors() {
        guard
            let data = try? Data(contentsOf: cursorFile),
            let decoded = try? JSONDecoder().decode([String: Cursor].self, from: data)
        else { return }
        cursors = decoded
    }

    private func saveCursors() {
        guard let data = try? JSONEncoder().encode(cursors) else { return }
        try? data.write(to: cursorFile, options: .atomic)
    }

    /// Forca releitura completa na proxima chamada.
    public func reset() {
        cursors = [:]
        try? FileManager.default.removeItem(at: cursorFile)
    }
}

// Compartilhada com o leitor de sessoes: procurar o marcador antes de chamar
// o JSONDecoder evita decodificar milhares de linhas irrelevantes.
extension Data.SubSequence {
    func contains(subsequence needle: [UInt8]) -> Bool {
        guard needle.count <= count else { return false }
        return withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            let limit = count - needle.count
            var i = 0
            while i <= limit {
                if memcmp(base + i, needle, needle.count) == 0 { return true }
                i += 1
            }
            return false
        }
    }
}
