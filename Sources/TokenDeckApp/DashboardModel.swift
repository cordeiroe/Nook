import Foundation
import SwiftUI
import TokenDeckCore

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
    }

    func addToShelf(_ urls: [URL]) {
        urls.forEach { builder.shelf.add($0) }
        Task { await refresh() }
    }

    func removeFromShelf(_ item: ShelfItem) {
        builder.shelf.remove(item)
        Task { await refresh() }
    }

    func refresh() async {
        isRefreshing = true
        let cfg = config
        let builder = self.builder
        // Le disco e SQLite fora da main thread pra nao travar o painel.
        let fresh = await Task.detached(priority: .utility) { await builder.build(config: cfg) }.value
        snapshot = fresh
        isRefreshing = false
    }
}
