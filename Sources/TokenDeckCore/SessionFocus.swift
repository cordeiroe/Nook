import AppKit
import Foundation

/// Traz para frente o terminal onde a sessão está rodando.
///
/// O processo do agente não é um aplicativo: ele é filho de um shell, que é
/// filho do terminal. Subir a árvore de processos até achar algo que o sistema
/// reconheça como aplicativo é o que permite ativá-lo.
///
/// Selecionar a aba certa depende do terminal. Terminal e iTerm2 expõem o TTY
/// de cada aba por AppleScript, então dá para acertar. Warp e a maioria dos
/// outros não expõem, e nesses o melhor possível é trazer a janela à frente.
public enum SessionFocus {
    public enum Result: Sendable, Equatable {
        case focusedTab(app: String)
        case focusedApp(String)
        case revealedFolder
        case failed
    }

    @discardableResult
    public static func focus(_ session: LiveSession) -> Result {
        guard let pid = session.pid, let app = owningApp(of: pid) else {
            return revealFolder(session)
        }

        app.activate()

        if let bundle = app.bundleIdentifier, let tty = tty(of: pid),
           selectTab(bundle: bundle, tty: tty) {
            return .focusedTab(app: app.localizedName ?? bundle)
        }
        return .focusedApp(app.localizedName ?? "terminal")
    }

    /// Sessão sem processo, como as do opencode: abrir a pasta é o mais perto
    /// de útil que dá para fazer.
    private static func revealFolder(_ session: LiveSession) -> Result {
        guard !session.directory.isEmpty,
              FileManager.default.fileExists(atPath: session.directory)
        else { return .failed }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.directory)
        return .revealedFolder
    }

    // MARK: - Árvore de processos

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var tamanho = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &tamanho, nil, 0) == 0, tamanho > 0 else { return nil }
        let pai = info.kp_eproc.e_ppid
        return pai > 1 ? pai : nil
    }

    private static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        var atual: pid_t? = pid
        var passos = 0
        while let p = atual, passos < 8 {
            passos += 1
            if let app = NSRunningApplication(processIdentifier: p),
               app.bundleIdentifier != nil,
               app.activationPolicy == .regular {
                return app
            }
            atual = parent(of: p)
        }
        return nil
    }

    private static func tty(of pid: pid_t) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try? p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let nome = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty, nome != "??" else { return nil }
        return nome.hasPrefix("/") ? nome : "/dev/\(nome)"
    }

    // MARK: - Seleção de aba

    private static func selectTab(bundle: String, tty: String) -> Bool {
        let script: String
        switch bundle {
        case "com.apple.Terminal":
            script = """
            tell application "Terminal"
                repeat with j in windows
                    repeat with t in tabs of j
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of j to 1
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            return ""
            """
        case "com.googlecode.iterm2":
            script = """
            tell application "iTerm2"
                repeat with j in windows
                    repeat with t in tabs of j
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select j
                                select t
                                select s
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return ""
            """
        default:
            // Warp, Ghostty, Alacritty e afins não expõem o TTY das abas.
            return false
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try? p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).contains("ok")
    }
}
