import SwiftUI
import NookCore

/// Painel do menu bar. Mostra tudo de uma vez, sem hover: e o lugar pra
/// conferir os numeros com calma, enquanto a regua e a vigia de canto de olho.
struct PanelView: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)

            ForEach(model.snapshot.providers) { provider in
                providerSection(provider)
                Divider().opacity(0.5)
            }

            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .foregroundStyle(.tint)
            Text("Nook")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
            if model.snapshot.capturedAt != .distantPast {
                Text(Format.elapsed(since: model.snapshot.capturedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func providerSection(_ provider: ProviderSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: Theme.symbol(for: provider.kind))
                    .font(.system(size: 12, weight: .medium))
                Text(provider.name)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(provider.percent)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.tint(for: provider.ratio))
            }

            ForEach(provider.meters) { meter in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(meter.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        Text(meter.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        if meter.estimated {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.10))
                            Capsule()
                                .fill(Theme.tint(for: meter.ratio))
                                .frame(width: max(3, geo.size.width * meter.ratio))
                        }
                    }
                    .frame(height: 4)
                }
            }

            if !provider.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(provider.sessions.prefix(4)) { session in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Theme.statusColor(session.status))
                                .frame(width: 5, height: 5)
                            Text(session.name)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text(Format.elapsed(since: session.updatedAt))
                                .font(.system(size: 9.5))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Atualizar") { Task { await model.refresh() } }
            Button("Ajustes") { NSWorkspace.shared.open(Paths.support) }
            if NSScreen.screens.count > 1 {
                Button("Trocar tela") { AppDelegate.current?.notch?.cycleScreen() }
            }
            Button(model.config.panelEnabled ? "Ocultar painel" : "Mostrar painel") {
                AppDelegate.current?.notch?.toggleEnabled()
            }
            Spacer()
            Button("Sair") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
