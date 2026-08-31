import EventKit
import Foundation

public struct AgendaEvent: Sendable, Equatable, Identifiable {
    public let id: String
    /// Identificador do EventKit, para abrir o evento no app Calendário.
    public let eventIdentifier: String?
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
        let brutos = store.events(matching: predicado)
            .filter { $0.endDate > agora }
            .filter { !$0.isAllDay || Calendar.current.isDateInToday($0.startDate) }
            .sorted { $0.startDate < $1.startDate }

        return Self.deduplicate(brutos)
            .prefix(limit)
            .map(Self.convert)
    }

    /// A mesma conta adicionada duas vezes em Contas de Internet, ou um convite
    /// que caiu em dois calendários, faz o EventKit devolver uma cópia por
    /// calendário. O app Calendário junta essas cópias; aqui é preciso fazer o
    /// mesmo, senão o compromisso aparece repetido.
    ///
    /// A chave junta o identificador externo, o iCalUID, com o horário de
    /// início. O iCalUID sozinho não serve: ele é idêntico em todas as
    /// ocorrências de um evento recorrente, e uma reunião diária perderia as
    /// próximas datas. Com o horário junto, duas cópias do mesmo compromisso
    /// colapsam e duas ocorrências diferentes continuam separadas.
    private static func deduplicate(_ eventos: [EKEvent]) -> [EKEvent] {
        var vistos = Set<String>()
        return eventos.filter { evento in
            let identidade = evento.calendarItemExternalIdentifier ?? evento.title ?? ""
            let chave = "\(identidade)|\(evento.startDate.timeIntervalSince1970)"
            return vistos.insert(chave).inserted
        }
    }

    private static func convert(_ event: EKEvent) -> AgendaEvent {
        var cor: (Double, Double, Double)?
        if let cg = event.calendar?.cgColor, let componentes = cg.components, componentes.count >= 3 {
            cor = (Double(componentes[0]), Double(componentes[1]), Double(componentes[2]))
        }
        return AgendaEvent(
            // Inclui o início: ForEach usa este id, e ocorrências da mesma
            // série compartilham o identificador externo.
            id: "\(event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString)|\(event.startDate.timeIntervalSince1970)",
            eventIdentifier: event.eventIdentifier,
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

        // Uma URL escrita no campo de localização é quase sempre o link da
        // chamada, mesmo em domínio próprio como zoom.suaempresa.com. Exigir
        // que ela batesse com uma lista de provedores escondia justamente as
        // reuniões de empresa, que são as que mais importam.
        if let local = event.location, let achado = firstLink(in: local) { return achado }

        if let notas = event.notes, let achado = firstLink(in: notas, apenasReuniao: true) {
            return achado
        }
        return event.url
    }

    private static let meetingHosts = [
        "meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com",
        "whereby.com", "meet.jit.si", "webex.com", "chime.aws", "around.co",
        "gather.town", "discord.gg", "meet.hey.com",
    ]

    /// Palavras que denunciam um link de chamada em domínio próprio.
    private static let meetingHints = ["zoom", "meet", "call", "webinar", "huddle", "conf"]

    private static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if meetingHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) { return true }
        return meetingHints.contains { host.contains($0) }
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func firstLink(in texto: String, apenasReuniao: Bool = false) -> URL? {
        guard let detector else { return nil }
        let range = NSRange(texto.startIndex..<texto.endIndex, in: texto)
        for match in detector.matches(in: texto, options: [], range: range) {
            guard let url = match.url, url.scheme?.hasPrefix("http") == true else { continue }
            if apenasReuniao && !isMeeting(url) { continue }
            return url
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
