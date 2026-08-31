import Foundation

/// Avisa quando algo muda num diretorio.
///
/// Observa o diretorio, nunca o arquivo: escrita atomica troca o inode, e um
/// descritor aberto no arquivo antigo para de receber eventos para sempre.
/// Como o Nook tambem escreve na propria pasta de suporte, o alvo
/// opcional filtra por mtime e evita realimentacao.
public final class PathWatcher: @unchecked Sendable {
    private let directory: URL
    private let target: URL?
    private let minimumInterval: TimeInterval

    private var source: DispatchSourceFileSystemObject?
    /// mtime em nanossegundos desde a epoca.
    private var lastSeen: Int64?
    private var lastFired: Date = .distantPast
    private let lock = NSLock()

    /// - Parameters:
    ///   - directory: pasta observada.
    ///   - target: se informado, so dispara quando o mtime deste arquivo mudar.
    ///   - minimumInterval: janela minima entre dois avisos, pra agrupar rajadas.
    public init(directory: URL, watching target: URL? = nil, minimumInterval: TimeInterval = 1.0) {
        self.directory = directory
        self.target = target
        self.minimumInterval = minimumInterval
        self.lastSeen = target.flatMap(Self.modified)
    }

    public func start(_ onChange: @escaping @Sendable () -> Void) {
        stop()
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self, self.shouldFire() else { return }
            onChange()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    deinit { source?.cancel() }

    private func shouldFire() -> Bool {
        lock.lock(); defer { lock.unlock() }

        let now = Date()
        guard now.timeIntervalSince(lastFired) >= minimumInterval else { return false }

        if let target {
            let current = Self.modified(target)
            guard current != lastSeen else { return false }
            lastSeen = current
        }

        lastFired = now
        return true
    }

    /// `URL.resourceValues` guarda cache na instancia, entao a data congelava
    /// na primeira leitura e o filtro nunca mais via mudanca. E a resolucao de
    /// um segundo perderia escritas proximas: a statusline reescreve o arquivo
    /// varias vezes no mesmo segundo.
    private static func modified(_ url: URL) -> Int64? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
    }
}
