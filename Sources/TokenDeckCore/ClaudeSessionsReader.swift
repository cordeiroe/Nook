import Foundation

/// Le ~/.claude/sessions/<pid>.json, que o Claude Code mantem por processo vivo.
public final class ClaudeSessionsReader: @unchecked Sendable {
    /// Titulos ja lidos, com o mtime do arquivo em que estavam. Sem isto
    /// cada refresh reabriria os jsonl das sessoes vivas so pra reler o titulo.
    private var titleCache: [String: (title: String, mtime: Date)] = [:]
    private let lock = NSLock()

    public init() {}

    private struct Record: Decodable {
        let pid: Int32
        let sessionId: String
        let cwd: String
        let startedAt: Double?
        let name: String?
        let status: String?
        let updatedAt: Double?
        let statusUpdatedAt: Double?
        let version: String?
        let kind: String?
    }

    public func read() -> [LiveSession] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: Paths.claudeSessions,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let decoder = JSONDecoder()
        var out: [LiveSession] = []

        for url in entries where url.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: url),
                let rec = try? decoder.decode(Record.self, from: data),
                isRunning(pid: rec.pid)
            else { continue }

            out.append(LiveSession(
                id: rec.sessionId,
                provider: .claude,
                name: rec.name ?? (rec.cwd as NSString).lastPathComponent,
                title: aiTitle(sessionID: rec.sessionId),
                directory: rec.cwd,
                status: SessionStatus(raw: rec.status),
                startedAt: rec.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                updatedAt: Date(timeIntervalSince1970: (rec.updatedAt ?? 0) / 1000),
                statusSince: rec.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                model: nil,
                pid: rec.pid
            ))
        }

        return out.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Arquivo de sessao sobrevive a crash, entao o PID e a fonte de verdade.
    private func isRunning(pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Ultimo `ai-title` do jsonl da sessao. Le so o arquivo daquela sessao,
    /// nao a pasta toda, e reusa o valor enquanto o arquivo nao mudar.
    private func aiTitle(sessionID: String) -> String? {
        guard let url = locate(sessionID: sessionID) else { return nil }
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil

        lock.lock()
        if let hit = titleCache[sessionID], hit.mtime == mtime {
            lock.unlock()
            return hit.title
        }
        lock.unlock()

        guard let title = lastTitle(in: url) else { return nil }
        lock.lock()
        titleCache[sessionID] = (title, mtime ?? .distantPast)
        lock.unlock()
        return title
    }

    private func locate(sessionID: String) -> URL? {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: Paths.claudeProjects, includingPropertiesForKeys: nil) else {
            return nil
        }
        for dir in dirs {
            let candidate = dir.appending(path: "\(sessionID).jsonl")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private struct TitleLine: Decodable {
        let type: String?
        let aiTitle: String?
    }

    private func lastTitle(in url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let decoder = JSONDecoder()
        var found: String?
        // Varre do inicio ao fim e guarda o ultimo: o titulo e reescrito
        // conforme a conversa evolui.
        for line in data.split(separator: 0x0A) {
            guard line.count > 20, line.contains(subsequence: Self.marker) else { continue }
            if let decoded = try? decoder.decode(TitleLine.self, from: Data(line)),
               decoded.type == "ai-title",
               let title = decoded.aiTitle, !title.isEmpty {
                found = title
            }
        }
        return found
    }

    private static let marker = Array("\"ai-title\"".utf8)
}
