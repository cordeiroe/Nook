import Foundation
import SwiftUI
import NookCore

@MainActor
final class DashboardModel: ObservableObject {
    /// A regua vive numa NSPanel criada pelo AppDelegate e o painel da barra
    /// vive numa Scene. Os dois precisam do mesmo estado, entao ele e unico.
    static let shared = DashboardModel()

    @Published private(set) var snapshot = DashboardSnapshot()
    @Published private(set) var isRefreshing = false
    @Published var config = Config.load() {
        didSet { config.save() }
    }

    /// Modulos ligados, na ordem da config, filtrando os ainda nao implementados.
    var enabledModules: [ModuleKind] {
        config.modules.compactMap(ModuleKind.init(rawValue:)).filter(\.isImplemented)
    }

    private let builder = DashboardBuilder()
    private var pump: Task<Void, Never>?

    /// Vigias que tornam a atualizacao imediata em vez de esperar o ciclo.
    private var refreshPending = false
    private var limitsWatcher: PathWatcher?
    private var sessionsWatcher: PathWatcher?

    func start() {
        guard pump == nil else { return }

        // A cota da MiniMax chega fora do ciclo, entao ela puxa um refresh
        // proprio em vez de esperar os proximos 15s.
        // Uma captura nova precisa aparecer na hora: esperar o proximo ciclo
        // de 15s tornaria a prateleira inutil pra arrastar o que acabou de sair.
        //
        // Fora da main thread de proposito: a pasta de capturas e protegida por
        // TCC e abri-la pode disparar um pedido de permissao que bloqueia quem
        // chamou. Na main thread isso congelava o app antes do painel existir.
        let shelf = builder.shelf
        DispatchQueue.global(qos: .utility).async {
            shelf.startWatching {
                Task { @MainActor in await DashboardModel.shared.refresh() }
            }
        }

        // A área de transferência não notifica ninguém: o store compara o
        // changeCount num timer próprio e avisa só quando algo entra.
        if config.modules.contains(ModuleKind.clipboard.rawValue) {
            let shelf = builder.shelf
            let guardarImagens = config.shelfCapturesPastedImages
                && config.modules.contains(ModuleKind.shelf.rawValue)

            // Tipo explícito: sem ele o closure herdaria o Bool de addImage.
            var aoReceberImagem: (@Sendable (Data) -> Void)?
            if guardarImagens {
                aoReceberImagem = { data in _ = shelf.addImage(data) }
            }

            builder.clipboard.start(
                retentionHours: config.clipboardRetentionHours,
                maxItems: config.clipboardMaxItems,
                ignoredApps: config.clipboardIgnoredApps,
                onImage: aoReceberImagem
            ) {
                Task { @MainActor in await DashboardModel.shared.refresh() }
            }
        }

        // Os limites reais do plano sao reescritos pela statusline a cada
        // render do Claude Code. Esperar o ciclo de 15s desperdicaria a fonte
        // mais fresca que temos, justamente no numero que mais importa.
        //
        // O alvo filtra por mtime porque o proprio app escreve nesta pasta:
        // sem isso, gravar o historico dispararia um refresh que gravaria o
        // historico de novo.
        let limits = PathWatcher(
            directory: Paths.support,
            watching: ClaudeLimitsReader().file,
            minimumInterval: 1
        )
        limits.start { Task { @MainActor in await DashboardModel.shared.refresh() } }
        limitsWatcher = limits

        // Sessoes entrando e saindo de "ocupada" tambem valem em tempo real.
        let sessions = PathWatcher(directory: Paths.claudeSessions, minimumInterval: 1)
        sessions.start { Task { @MainActor in await DashboardModel.shared.refresh() } }
        sessionsWatcher = sessions

        Task {
            await MiniMaxClient.shared.onUpdate {
                Task { @MainActor in await DashboardModel.shared.refresh() }
            }
        }

        pump = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let seconds = await self?.config.refreshInterval ?? 15
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        builder.clipboard.stop()
        limitsWatcher?.stop()
        sessionsWatcher?.stop()
        limitsWatcher = nil
        sessionsWatcher = nil
    }

    func addToShelf(_ urls: [URL]) {
        urls.forEach { builder.shelf.add($0) }
        Task { await refresh() }
    }

    /// Manda o comando e relê logo em seguida: esperar o ciclo faria o botão
    /// de play parecer travado por até 15 segundos.
    func mediaCommand(_ command: NowPlayingReader.Command) {
        Task.detached(priority: .userInitiated) {
            NowPlayingReader().send(command)
            try? await Task.sleep(for: .milliseconds(300))
            await DashboardModel.shared.refresh()
        }
    }

    /// Salva no Notion e devolve a mensagem de erro, ou nil em caso de sucesso.
    func saveToNotion(_ texto: String) async -> String? {
        let database = config.notionDatabaseID
        let ehLink = texto.lowercased().hasPrefix("http")
        do {
            let item = try await NotionClient.shared.save(
                title: texto,
                url: ehLink ? texto : nil,
                kind: ehLink ? NotionClient.classify(texto) : "Nota",
                notes: nil,
                database: database
            )
            NotionHistory.shared.record(item)
            await refresh()
            return nil
        } catch let erro as NotionError {
            return erro.description
        } catch {
            return error.localizedDescription
        }
    }

    /// Traz o terminal da sessão para frente. Fora da main thread porque sobe a
    /// árvore de processos e pode chamar AppleScript.
    func focusSession(_ session: LiveSession) {
        Task.detached(priority: .userInitiated) {
            SessionFocus.focus(session)
        }
    }

    func copyBack(_ item: ClipboardItem) {
        builder.clipboard.copyBack(item)
    }

    func removeFromClipboard(_ item: ClipboardItem) {
        builder.clipboard.remove(item)
        Task { await refresh() }
    }

    func clearClipboard() {
        builder.clipboard.clear()
        Task { await refresh() }
    }

    func removeFromShelf(_ item: ShelfItem) {
        builder.shelf.remove(item)
        Task { await refresh() }
    }

    func refresh() async {
        // Vigia e ciclo podem coincidir. Descartar o evento perderia a
        // atualizacao ate o proximo ciclo, entao ele fica pendente e roda
        // assim que a leitura corrente termina.
        if isRefreshing {
            refreshPending = true
            return
        }
        isRefreshing = true
        let cfg = config
        let builder = self.builder
        // Le disco e SQLite fora da main thread pra nao travar o painel.
        let fresh = await Task.detached(priority: .utility) { await builder.build(config: cfg) }.value
        snapshot = fresh
        isRefreshing = false

        if refreshPending {
            refreshPending = false
            await refresh()
        }
    }
}
