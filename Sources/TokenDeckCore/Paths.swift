import Foundation

public enum Paths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser

    public static var claudeRoot: URL { home.appending(path: ".claude") }
    public static var claudeSessions: URL { claudeRoot.appending(path: "sessions") }
    public static var claudeProjects: URL { claudeRoot.appending(path: "projects") }

    public static var openCodeDB: URL {
        home.appending(path: ".local/share/opencode/opencode.db")
    }

    /// Estado proprio do TokenDeck (offsets de leitura, historico agregado, config).
    public static var support: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "TokenDeck")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
