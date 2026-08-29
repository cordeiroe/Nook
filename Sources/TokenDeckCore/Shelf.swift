import AppKit
import Foundation

public struct ShelfItem: Sendable, Equatable, Identifiable, Codable {
    public enum Origin: String, Sendable, Codable {
        /// Detectada sozinha na pasta de capturas.
        case screenshot
        /// Arrastada pelo usuario pro painel.
        case dropped
    }

    public let id: String
    public let path: String
    public let addedAt: Date
    public let origin: Origin

    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { (path as NSString).lastPathComponent }
    public var exists: Bool { FileManager.default.fileExists(atPath: path) }

    public init(url: URL, addedAt: Date = Date(), origin: Origin) {
        self.id = url.path
        self.path = url.path
        self.addedAt = addedAt
        self.origin = origin
    }
}

/// Prateleira: capturas recentes detectadas sozinhas mais o que o usuario
/// larga no painel.
///
/// Guarda caminhos, nunca copias. Parar arquivo do usuario num diretorio
/// paralelo criaria duplicata silenciosa e ocuparia disco sem ele saber.
/// O custo e que mover ou apagar o original tira o item da prateleira, o que
/// e o comportamento esperado de uma prateleira temporaria.
public final class ShelfStore: @unchecked Sendable {
    /// Quanto tempo uma captura fica listada sozinha.
    public static let screenshotWindow: TimeInterval = 12 * 3600
    public static let maximum = 12

    private var items: [ShelfItem] = []
    private let lock = NSLock()
    private let file: URL
    private var watcher: DispatchSourceFileSystemObject?
    private var onChange: (@Sendable () -> Void)?

    public init() {
        file = Paths.support.appending(path: "shelf.json")
        load()
    }

    // MARK: - Pasta de capturas

    /// Onde o macOS salva as capturas. O padrao e a Mesa, mas e configuravel
    /// e neste Mac aponta pra Documentos.
    public static var screenshotDirectory: URL {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        if let raw = defaults?.string(forKey: "location"), !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop")
    }

    /// Erro tipico e a pasta ser protegida por TCC. Devolver o motivo deixa a
    /// UI explicar em vez de simplesmente nao mostrar nada.
    public enum Access: Sendable, Equatable {
        case ok
        case denied(String)
    }

    public static func checkAccess() -> Access {
        let dir = screenshotDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else {
            return .denied(dir.lastPathComponent)
        }
        // `contentsOfDirectory` devolve lista vazia em vez de erro em pastas
        // protegidas por TCC, entao "sem acesso" ficava indistinguivel de
        // "sem capturas". Abrir o diretorio falha com EPERM e nao mente.
        let fd = open(dir.path, O_RDONLY)
        guard fd >= 0 else { return .denied(dir.lastPathComponent) }
        close(fd)
        return .ok
    }

    // MARK: - Leitura

    public func refresh() {
        let found = recentScreenshots()
        lock.lock()
        // Capturas sao recalculadas a cada passada; os itens largados ficam.
        items.removeAll { $0.origin == .screenshot }
        items.append(contentsOf: found)
        items.removeAll { !$0.exists }
        items.sort { $0.addedAt > $1.addedAt }
        if items.count > Self.maximum { items = Array(items.prefix(Self.maximum)) }
        lock.unlock()
        save()
    }

    public var current: [ShelfItem] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    @discardableResult
    public func add(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        lock.lock()
        if !items.contains(where: { $0.path == url.path }) {
            items.insert(ShelfItem(url: url, origin: .dropped), at: 0)
            if items.count > Self.maximum { items = Array(items.prefix(Self.maximum)) }
        }
        lock.unlock()
        save()
        return true
    }

    public func remove(_ item: ShelfItem) {
        lock.lock()
        items.removeAll { $0.id == item.id }
        lock.unlock()
        save()
    }

    public func clearDropped() {
        lock.lock()
        items.removeAll { $0.origin == .dropped }
        lock.unlock()
        save()
    }

    // MARK: - Vigia da pasta

    /// Avisa assim que uma captura nova aparece, em vez de esperar o proximo
    /// ciclo de 15s: uma captura que demora a aparecer nao serve pra arrastar.
    public func startWatching(_ callback: @escaping @Sendable () -> Void) {
        onChange = callback
        let dir = Self.screenshotDirectory
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename], queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.refresh()
            self?.onChange?()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    public func stopWatching() {
        watcher?.cancel()
        watcher = nil
        onChange = nil
    }

    // MARK: - Privado

    private static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff"]

    private func recentScreenshots() -> [ShelfItem] {
        let dir = Self.screenshotDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-Self.screenshotWindow)
        return entries.compactMap { url -> ShelfItem? in
            guard Self.imageTypes.contains(url.pathExtension.lowercased()) else { return nil }
            guard let created = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  created >= cutoff else { return nil }
            return ShelfItem(url: url, addedAt: created, origin: .screenshot)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return }
        items = decoded.filter { $0.exists }
    }

    private func save() {
        lock.lock()
        let snapshot = items
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
