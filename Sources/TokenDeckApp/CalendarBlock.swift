import AppKit
import SwiftUI
import TokenDeckCore

/// Próximos compromissos. O que está acontecendo agora ou começa em breve
/// ganha destaque, porque é o único que exige ação imediata.
struct CalendarBlock: View {
    let events: [AgendaEvent]
    let access: AgendaAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch access {
            case .notDetermined:
                Placeholder(text: "Pedindo acesso ao Calendário…", loading: true)

            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Sem acesso ao Calendário.", systemImage: "lock")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                    Button("Abrir Privacidade e Segurança") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.vertical, 2)

            case .granted:
                if events.isEmpty {
                    Placeholder(text: "Nada nas próximas 36 horas.")
                } else {
                    ForEach(events) { EventRow(event: $0) }
                }
            }
        }
    }
}

struct EventRow: View {
    let event: AgendaEvent

    @State private var hovering = false

    private var accent: Color {
        guard let c = event.calendarColor else { return .white.opacity(0.35) }
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3)
                .opacity(event.isNow ? 1 : 0.6)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: event.isNow || event.startsSoon ? .medium : .regular))
                    .foregroundStyle(.white.opacity(event.isNow ? 0.95 : 0.82))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(quando)
                        .foregroundStyle(destaque ? accent : .white.opacity(0.4))
                    if let local = event.location, event.meetingURL == nil {
                        Text("· \(local)")
                            .foregroundStyle(.white.opacity(0.3))
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 9.5))
            }

            Spacer(minLength: 4)

            if let url = event.meetingURL {
                Button("Entrar") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(destaque ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.white.opacity(destaque ? 0.18 : (hovering ? 0.12 : 0.07)))
                    )
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var destaque: Bool { event.isNow || event.startsSoon }

    /// "agora", "em 12min" e "14:00" dizem mais que uma data completa para algo
    /// que está prestes a acontecer.
    private var quando: String {
        if event.isAllDay { return "dia inteiro" }
        if event.isNow {
            let falta = Int(event.end.timeIntervalSinceNow / 60)
            return falta > 0 ? "agora · termina em \(falta)min" : "agora"
        }
        let falta = event.start.timeIntervalSinceNow
        let hora = event.start.formatted(date: .omitted, time: .shortened)
        if falta < 60 * 60 {
            return "em \(max(1, Int(falta / 60)))min · \(hora)"
        }
        if Calendar.current.isDateInToday(event.start) { return hora }
        if Calendar.current.isDateInTomorrow(event.start) { return "amanhã \(hora)" }
        return event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
