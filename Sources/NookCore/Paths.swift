import Foundation

public enum Paths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser

    public static var claudeRoot: URL { home.appending(path: ".claude") }
    public static var claudeSessions: URL { claudeRoot.appending(path: "sessions") }
    public static var claudeProjects: URL { claudeRoot.appending(path: "projects") }

    public static var openCodeDB: URL {
        home.appending(path: ".local/share/opencode/opencode.db")
    }

    /// Estado proprio do Nook (offsets de leitura, historico agregado, config).
    public static var support: URL {
        let base = applicationSupport.appending(path: "Nook")
        migrateOnce(to: base)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static let migrationLock = NSLock()
    private static var migrated = false

    /// O produto se chamava TokenDeck. Renomear a pasta sem mover o conteudo
    /// abandonaria config, historico de consumo, credenciais e prateleira, e o
    /// usuario reencontraria um app zerado sem entender por que.
    ///
    /// A migracao e por arquivo, nao pela pasta inteira: a ponte da statusline
    /// escreve na pasta nova antes do app abrir, entao exigir que ela nao
    /// exista faria a migracao nunca acontecer.
    private static func migrateOnce(to base: URL) {
        migrationLock.lock()
        defer { migrationLock.unlock() }
        guard !migrated else { return }
        migrated = true

        let fm = FileManager.default
        let marcador = base.appending(path: ".migrated-from-tokendeck")
        guard !fm.fileExists(atPath: marcador.path) else { return }

        let antiga = applicationSupport.appending(path: "TokenDeck")
        guard fm.fileExists(atPath: antiga.path) else { return }
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)

        for nome in (try? fm.contentsOfDirectory(atPath: antiga.path)) ?? [] {
            // A ponte e dona deste arquivo e o reescreve a cada render, entao
            // a copia dela e sempre mais nova que a herdada.
            if nome == "claude-limits.json", fm.fileExists(atPath: base.appending(path: nome).path) {
                continue
            }
            let destino = base.appending(path: nome)
            try? fm.removeItem(at: destino)
            try? fm.moveItem(at: antiga.appending(path: nome), to: destino)
        }

        renameCredentialKeys(in: base.appending(path: "credentials.json"))
        try? fm.removeItem(at: antiga)
        try? Data().write(to: marcador)
    }

    /// As chaves do arquivo de credenciais carregam o nome antigo do produto,
    /// entao mover a pasta nao basta: sem isto, o token existiria no disco e o
    /// app o consideraria ausente.
    private static func renameCredentialKeys(in file: URL) {
        guard let data = try? Data(contentsOf: file),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }

        var renomeado: [String: String] = [:]
        for (chave, valor) in dict {
            renomeado[chave.replacingOccurrences(of: "TokenDeck-", with: "Nook-")] = valor
        }
        guard renomeado != dict,
              let novo = try? JSONEncoder().encode(renomeado)
        else { return }
        try? novo.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
