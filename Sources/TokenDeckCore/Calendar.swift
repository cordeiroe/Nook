import EventKit
import Foundation

public struct AgendaEvent: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarName: String
    /// Cor do calendário de origem, em componentes RGB de 0 a 1.
    public let calendarColor: (red: Double, green: Double, blue: Double)?
    public let location: String?
    /// Link de videochamada, quando existe.
    public let meetingURL: URL?

    public var isNow: Bool {
        let agora = Date()
        return start <= agora && agora < end
    }

    public var startsSoon: Bool {
        let falta = start.timeIntervalSinceNow
        return falta > 0 && falta <= 15 * 60
    }

    public static func == (a: AgendaEvent, b: AgendaEvent) -> Bool {
        a.id == b.id && a.title == b.title && a.start == b.start && a.end == b.end
    }
}

public enum AgendaAccess: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}

/// Próximos compromissos, lidos do EventKit.
///
/// EventKit enxerga tudo que estiver em Ajustes do Sistema > Contas de
/// Internet: iCloud, Google, Exchange. Por isso não há credencial nenhuma aqui,
/// e nenhuma requisição de rede: quem sincroniza é o sistema.
public final class AgendaReader: @unchecked Sendable {
    private let store = EKEventStore()
    private var requested = false
    private let lock = NSLock()

    public init() {}

    public var access: AgendaAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Pede acesso uma vez por execução. Chamado fora da main thread: o
    /// diálogo do sistema bloqueia quem chamou até o usuário responder.
    public func requestAccessIfNeeded() {
        lock.lock()
        let jaPediu = requested
        requested = true
        lock.unlock()
        guard !jaPediu, access == .notDetermined else { return }

        let semaforo = DispatchSemaphore(value: 0)
        store.requestFullAccessToEvents { _, _ in semaforo.signal() }
        _ = semaforo.wait(timeout: .now() + 60)
    }

    public func upcoming(within hours: Double = 36, limit: Int = 6) -> [AgendaEvent] {
        guard access == .granted else { return [] }

        let agora = Date()
        // Começa uma hora atrás para o compromisso em andamento continuar
        // aparecendo: é justamente o que mais importa saber.
        let inicio = agora.addingTimeInterval(-3600)
        let fim = agora.addingTimeInterval(hours * 3600)

        let calendarios = store.calendars(for: .event)
        guard !calendarios.isEmpty else { return [] }

        let predicado = store.predicateForEvents(withStart: inicio, end: fim, calendars: calendarios)
        return store.events(matching: predicado)
            .filter { $0.endDate > agora }
            .filter { !$0.isAllDay || Calendar.current.isDateInToday($0.startDate) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map(Self.convert)
    }

    private static func convert(_ event: EKEvent) -> AgendaEvent {
        var cor: (Double, Double, Double)?
        if let cg = event.calendar?.cgColor, let componentes = cg.components, componentes.count >= 3 {
            cor = (Double(componentes[0]), Double(componentes[1]), Double(componentes[2]))
        }
        return AgendaEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "(sem título)",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarName: event.calendar?.title ?? "",
            calendarColor: cor,
            location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            meetingURL: meetingURL(in: event)
        )
    }

    /// O link da chamada raramente está no campo `url`. Google Meet e Zoom
    /// costumam deixá-lo na localização ou no corpo da descrição.
    private static func meetingURL(in event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url) { return url }
        for campo in [event.location, event.notes] {
            guard let campo, let achado = firstMeetingLink(in: campo) else { continue }
            return achado
        }
        return event.url
    }

    private static let meetingHosts = [
        "meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com",
        "whereby.com", "meet.jit.si", "webex.com", "chime.aws", "around.co",
    ]

    private static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func firstMeetingLink(in texto: String) -> URL? {
        guard let detector else { return nil }
        let range = NSRange(texto.startIndex..<texto.endIndex, in: texto)
        for match in detector.matches(in: texto, options: [], range: range) {
            if let url = match.url, isMeeting(url) { return url }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
