import SwiftUI
import NookCore

@main
struct NookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = DashboardModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
                .task { model.start() }
        } label: {
            MenuBarLabel(snapshot: model.snapshot)
                .task { model.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Existe so pra criar o painel do notch, que e uma NSPanel e nao cabe
/// no modelo de Scene do SwiftUI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var current: AppDelegate?
    private(set) var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        Brand.registerFont()
        let model = DashboardModel.shared

        // O painel primeiro: qualquer coisa que dependa de permissao do sistema
        // pode demorar, e o widget nao pode ficar invisivel esperando por ela.
        let notch = NotchController(model: model)
        self.notch = notch
        if model.config.panelEnabled { notch.show() }

        model.start()
    }
}

/// O icone da barra mostra o medidor mais pressionado: e a unica coisa
/// visivel sem clicar, entao precisa ser o numero que importa.
struct MenuBarLabel: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if let headline = snapshot.headline {
                Text("\(headline.percent)%")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
    }

    private var symbol: String {
        if snapshot.busyCount > 0 { return "gauge.with.dots.needle.67percent" }
        guard let ratio = snapshot.headline?.ratio else { return "gauge.with.dots.needle.33percent" }
        return ratio >= 0.85 ? "gauge.with.dots.needle.100percent" : "gauge.with.dots.needle.33percent"
    }
}
