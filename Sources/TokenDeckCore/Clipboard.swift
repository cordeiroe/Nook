import AppKit
import Foundation

public struct ClipboardItem: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let text: String
    public let copiedAt: Date
    public let sourceApp: String?

    /// Primeira linha, para caber numa linha do painel.
    public var preview: String {
        let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
            ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 90 ? String(trimmed.prefix(90)) + "…" : trimmed
    }

    public var lineCount: Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}

/// Histórico da área de transferência.
///
/// Guardar tudo que o usuário copia é guardar senhas e tokens por acidente.
/// A defesa tem quatro camadas, porque nenhuma sozinha é suficiente:
///
/// 1. Marcadores do sistema: gerenciadores de senha anunciam "não guarde isto"
///    via tipos `org.nspasteboard.*`. Respeitá-los cobre o caso bem-comportado.
/// 2. Aplicativo de origem: cópias vindas de um gerenciador conhecido são
///    ignoradas mesmo sem marcador, porque nem todos marcam.
/// 3. Formato do conteúdo: chaves de API, tokens e blocos de chave privada têm
///    prefixos reconhecíveis. Cobre o segredo copiado de um editor de texto.
/// 4. Prazo de validade: o que escapar das três anteriores desaparece sozinho.
///
/// O que sobra em risco é o segredo sem marcador, de app desconhecido e sem
/// formato reconhecível. Por isso o prazo é curto por padrão e existe um botão
/// de limpar.
public final class ClipboardStore: @unchecked Sendable {
    private var items: [ClipboardItem] = []
    private let lock = NSLock()
    private let file: URL

    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    /// Colar de volta muda o changeCount; sem isto o histórico registraria a
    /// própria escrita e duplicaria o item a cada uso.
    private var ownChangeCount: Int = -1

    private var retention: TimeInterval = 8 * 3600
    private var maximum: Int = 40
    private var ignoredApps: Set<String> = []
    private var onImage: (@Sendable (Data) -> Void)?

    public init() {
        file = Paths.support.appending(path: "clipboard.json")
        lastChangeCount = NSPasteboard.general.changeCount
        load()
    }

    // MARK: - Captura

    /// - Parameter onImage: recebe imagens que passam pela area de
    ///   transferencia. Elas nao entram no historico de texto; quem decide o
    ///   que fazer com elas e quem chamou.
    public func start(retentionHours: Double, maxItems: Int, ignoredApps: [String],
                      onImage: (@Sendable (Data) -> Void)? = nil,
                      onChange: @escaping @Sendable () -> Void) {
        stop()
        self.onImage = onImage
        self.retention = max(60, retentionHours * 3600)
        self.maximum = max(1, maxItems)
        self.ignoredApps = Set(ignoredApps.map { $0.lowercased() })

        // A área de transferência não notifica ninguém: só resta comparar o
        // changeCount, que é uma leitura barata.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 0.6)
        timer.setEventHandler { [weak self] in
            guard let self, self.capture() else { return }
            onChange()
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        onImage = nil
    }

    /// Devolve true quando algo novo entrou no histórico.
    private func capture() -> Bool {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return false }
        lastChangeCount = count
        guard count != ownChangeCount else { return false }

        guard !isConcealed(pb) else { return false }

        let app = NSWorkspace.shared.frontmostApplication
        if let bundle = app?.bundleIdentifier?.lowercased(), ignoredApps.contains(bundle) {
            return false
        }

        // Imagem vem antes do texto: uma captura traz PNG e, as vezes, tambem
        // um caminho como string. Guardar o caminho seria inutil, porque o
        // arquivo temporario da captura some.
        if let handler = onImage,
           let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            handler(data)
            return true
        }

        guard let text = pb.string(forType: .string) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 20_000 else { return false }
        guard !Self.looksSecret(trimmed) else { return false }

        let item = ClipboardItem(
            id: UUID().uuidString,
            text: text,
            copiedAt: Date(),
            sourceApp: app?.localizedName
        )

        lock.lock()
        items.removeAll { $0.text == text }
        items.insert(item, at: 0)
        prune()
        lock.unlock()
        save()
        return true
    }

    /// Tipos que gerenciadores de senha colocam na área de transferência para
    /// pedir que ninguém guarde aquele conteúdo.
    private func isConcealed(_ pb: NSPasteboard) -> Bool {
        let markers: Set<String> = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType",
            "com.agilebits.onepassword",
            "de.petrs.CopyLess.NoCopy",
            "Pasteboard generator type",
        ]
        return (pb.types ?? []).contains { markers.contains($0.rawValue) }
    }

    // MARK: - Formato de segredo

    private static let secretPatterns: [String] = [
        #"\bsk-[A-Za-z0-9_\-]{16,}"#,          // OpenAI, Anthropic, MiniMax
        #"\bsk-ant-"#,
        #"\bgh[pousr]_[A-Za-z0-9]{16,}"#,      // GitHub
        #"\bgithub_pat_[A-Za-z0-9_]{20,}"#,
        #"\bxox[baprs]-[A-Za-z0-9\-]{10,}"#,   // Slack
        #"\bAKIA[0-9A-Z]{16}\b"#,              // AWS
        #"\bASIA[0-9A-Z]{16}\b"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]+"#,  // JWT
        #"\bglpat-[A-Za-z0-9_\-]{16,}"#,       // GitLab
        #"\bAIza[0-9A-Za-z_\-]{30,}"#,         // Google
    ]

    private static let secretRegexes: [NSRegularExpression] = secretPatterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }

    public static func looksSecret(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return secretRegexes.contains { $0.firstMatch(in: text, options: [], range: range) != nil }
    }

    // MARK: - Uso

    public var current: [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        prune()
        return items
    }

    /// Devolve o conteúdo para a área de transferência.
    public func copyBack(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        ownChangeCount = pb.changeCount
        lastChangeCount = pb.changeCount
    }

    public func remove(_ item: ClipboardItem) {
        lock.lock()
        items.removeAll { $0.id == item.id }
        lock.unlock()
        save()
    }

    public func clear() {
        lock.lock()
        items.removeAll()
        lock.unlock()
        save()
    }

    // MARK: - Privado

    private func prune() {
        let cutoff = Date().addingTimeInterval(-retention)
        items.removeAll { $0.copiedAt < cutoff }
        if items.count > maximum { items = Array(items.prefix(maximum)) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data)
        else { return }
        items = decoded
        prune()
    }

    /// Cria o arquivo já com 0600 antes de escrever: criar aberto e apertar
    /// depois deixaria uma janela em que o histórico fica legível por outros.
    private func save() {
        lock.lock()
        let snapshot = items
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        let fm = FileManager.default
        if !fm.fileExists(atPath: file.path) {
            _ = fm.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try? data.write(to: file, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
