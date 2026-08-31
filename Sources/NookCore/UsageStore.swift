import Foundation

/// Historico rolante de eventos, com dedup por requestId e poda por idade.
/// Guarda 8 dias pra cobrir a janela semanal com folga.
public final class UsageStore: @unchecked Sendable {

    /// Guarda 35 dias: a janela mensal precisa disso e o arquivo fica
    /// na casa de poucos MB.
    public static let retention: TimeInterval = 35 * 24 * 3600

    private var events: [UsageEvent] = []
    private var seenRequestIDs: Set<String> = []
    private let file: URL
    private let lock = NSLock()

    public init() {
        file = Paths.support.appending(path: "usage-history.json")
        load()
    }

    public func ingest(_ new: [UsageEvent]) {
        lock.lock(); defer { lock.unlock() }
        for event in new {
            if let rid = event.requestID {
                guard seenRequestIDs.insert(rid).inserted else { continue }
            }
            events.append(event)
        }
        prune()
        save()
    }

    public func totals(since: Date, model: String? = nil) -> TokenTotals {
        lock.lock(); defer { lock.unlock() }
        var sum = TokenTotals()
        for e in events where e.timestamp >= since {
            if let model, !e.model.contains(model) { continue }
            sum += e.tokens
        }
        return sum
    }

    public func totalsByModel(since: Date) -> [String: TokenTotals] {
        lock.lock(); defer { lock.unlock() }
        var out: [String: TokenTotals] = [:]
        for e in events where e.timestamp >= since {
            out[e.model, default: TokenTotals()] += e.tokens
        }
        return out
    }

    public func totalsByProject(since: Date) -> [String: TokenTotals] {
        lock.lock(); defer { lock.unlock() }
        var out: [String: TokenTotals] = [:]
        for e in events where e.timestamp >= since {
            out[e.project, default: TokenTotals()] += e.tokens
        }
        return out
    }

    /// Instante do primeiro evento da janela de 5h em curso, que e o que define o reset.
    public func windowStart(hours: Double) -> Date? {
        lock.lock(); defer { lock.unlock() }
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        return events.filter { $0.timestamp >= cutoff }.map(\.timestamp).min()
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return events.count
    }

    public var oldest: Date? {
        lock.lock(); defer { lock.unlock() }
        return events.map(\.timestamp).min()
    }

    // MARK: - Privado

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.retention)
        events.removeAll { $0.timestamp < cutoff }
        seenRequestIDs = Set(events.compactMap(\.requestID))
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: file),
            let decoded = try? JSONDecoder().decode([UsageEvent].self, from: data)
        else { return }
        events = decoded
        seenRequestIDs = Set(decoded.compactMap(\.requestID))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
