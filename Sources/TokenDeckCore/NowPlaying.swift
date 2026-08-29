import Foundation

public struct NowPlaying: Sendable, Equatable {
    public let app: String
    public let title: String
    public let artist: String
    public let isPlaying: Bool
}

/// Le o que esta tocando via AppleScript.
///
/// O caminho "oficial" seria o MediaRemote, mas ele virou privado e exige
/// entitlement que so a Apple concede. AppleScript cobre Spotify e Musica,
/// que e o que esta instalado aqui, ao custo de uma permissao de Automacao.
public struct NowPlayingReader: Sendable {
    private struct Player {
        let process: String
        let app: String
        let label: String
    }

    private static let players = [
        Player(process: "Spotify", app: "Spotify", label: "Spotify"),
        Player(process: "Music", app: "Music", label: "Música"),
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
        let script = """
        tell application "\(player.app)"
            if player state is stopped then return ""
            return (name of current track) & "\\n" & (artist of current track) & "\\n" & (player state as text)
        end tell
        """
        guard let output = runScript(script) else { return nil }
        let parts = output.components(separatedBy: "\n")
        guard parts.count >= 3, !parts[0].isEmpty else { return nil }
        return NowPlaying(
            app: player.label,
            title: parts[0],
            artist: parts[1],
            isPlaying: parts[2].lowercased().contains("playing")
        )
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
