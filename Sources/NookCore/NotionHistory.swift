import Foundation

/// Últimos itens salvos no Notion. Serve só para dar retorno visual: a fonte
/// da verdade é o banco lá.
public final class NotionHistory: @unchecked Sendable {
    public static let shared = NotionHistory()

    private static let maximum = 8
    private var items: [NotionSavedItem] = []
    private let lock = NSLock()
    private let file = Paths.support.appending(path: "notion-recent.json")

    public init() {
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([NotionSavedItem].self, from: data) {
            items = decoded
        }
    }

    public var current: [NotionSavedItem] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    public func record(_ item: NotionSavedItem) {
        lock.lock()
        items.insert(item, at: 0)
        if items.count > Self.maximum { items = Array(items.prefix(Self.maximum)) }
        let snapshot = items
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
