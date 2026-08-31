import Foundation

public struct NowPlaying: Sendable, Equatable {
    public let app: String
    public let title: String
    public let artist: String
    public let album: String
    public let artworkURL: URL?
    /// Em segundos.
    public let duration: TimeInterval
    /// Posicao no instante da captura, em segundos.
    public let position: TimeInterval
    public let isPlaying: Bool
    public let capturedAt: Date

    /// Posicao estimada agora. Avanca sozinha enquanto toca, entao a barra de
    /// progresso corre suave sem precisar consultar o Spotify a cada segundo.
    public func position(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return position }
        return min(duration, position + date.timeIntervalSince(capturedAt))
    }

    public func progress(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, position(at: date) / duration))
    }

    public static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Le e controla o que esta tocando, via AppleScript.
///
/// O caminho "oficial" seria o MediaRemote, mas ele virou privado e exige
/// entitlement que so a Apple concede. AppleScript cobre Spotify e Musica ao
/// custo de uma permissao de Automacao.
public struct NowPlayingReader: Sendable {
    private struct Player {
        let process: String
        let app: String
        let label: String
        /// O Spotify informa duracao em milissegundos; o app Musica, em segundos.
        let durationInMilliseconds: Bool
        /// Só o Spotify expõe `artwork url`.
        let hasArtworkURL: Bool
    }

    private static let players = [
        Player(process: "Spotify", app: "Spotify", label: "Spotify",
               durationInMilliseconds: true, hasArtworkURL: true),
        Player(process: "Music", app: "Music", label: "Música",
               durationInMilliseconds: false, hasArtworkURL: false),
    ]

    public init() {}

    public func read() -> NowPlaying? {
        for player in Self.players {
            // Consultar direto abriria o app se ele estivesse fechado.
            guard isRunning(player.process) else { continue }
            if let playing = query(player) { return playing }
        }
        return nil
    }

    // MARK: - Controle

    public enum Command: String, Sendable {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"
    }

    /// Aplica o comando ao player que estiver tocando.
    public func send(_ command: Command) {
        for player in Self.players where isRunning(player.process) {
            _ = runScript("tell application \"\(player.app)\" to \(command.rawValue)")
            return
        }
    }

    // MARK: - Privado

    private func isRunning(_ name: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", name]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private func query(_ player: Player) -> NowPlaying? {
        // `artwork url` não existe em toda faixa (podcast, arquivo local),
        // então a leitura dele vai isolada num try.
        let artwork = player.hasArtworkURL
            ? """
                set art to ""
                try
                    set art to artwork url of t
                end try
            """
            : "                set art to \"\""

        let script = """
        tell application "\(player.app)"
            if player state is stopped then return ""
            set t to current track
        \(artwork)
            return (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" & art ¬
                & "\\n" & (duration of t) & "\\n" & (player position) & "\\n" & (player state as text)
        end tell
        """

        guard let output = runScript(script) else { return nil }
        let parts = output.components(separatedBy: "\n")
        guard parts.count >= 7, !parts[0].isEmpty else { return nil }

        let rawDuration = Self.number(parts[4])
        return NowPlaying(
            app: player.label,
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            artworkURL: parts[3].isEmpty ? nil : URL(string: parts[3]),
            duration: player.durationInMilliseconds ? rawDuration / 1000 : rawDuration,
            position: Self.number(parts[5]),
            isPlaying: parts[6].lowercased().contains("playing"),
            capturedAt: Date()
        )
    }

    /// O AppleScript formata número no locale do sistema, então em pt-BR a
    /// posição volta como "61,645". `Double(_:)` devolveria nil e a barra de
    /// progresso ficaria parada no zero.
    private static func number(_ raw: String) -> TimeInterval {
        Double(raw.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func runScript(_ source: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try? p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
