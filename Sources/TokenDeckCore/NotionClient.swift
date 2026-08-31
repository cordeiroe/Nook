import Foundation

public struct NotionSavedItem: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let title: String
    public let url: String?
    public let kind: String
    public let savedAt: Date
}

public enum NotionError: Error, CustomStringConvertible, Equatable {
    case noToken
    case noDatabase
    case http(Int, String)
    case noTitleProperty
    case transport(String)

    public var description: String {
        switch self {
        case .noToken:          return "token do Notion ausente"
        case .noDatabase:       return "notionDatabaseID não configurado"
        case .http(let c, let m): return "HTTP \(c): \(m)"
        case .noTitleProperty:  return "o banco não tem propriedade de título"
        case .transport(let m): return m
        }
    }
}

/// Salva links no Notion.
///
/// O nome das propriedades muda de banco para banco, então em vez de exigir um
/// formato fixo o cliente lê o esquema e descobre onde cada coisa vai: a
/// propriedade do tipo `title` recebe o texto, a primeira `url` recebe o link,
/// e assim por diante. Um banco montado à mão pelo usuário funciona sem
/// precisar renomear nada.
public actor NotionClient {
    public static let shared = NotionClient()

    private static let version = "2022-06-28"
    private static let base = URL(string: "https://api.notion.com/v1/")!

    private var schema: [String: String]?   // nome da propriedade -> tipo
    private var schemaDatabase: String?

    public init() {}

    // MARK: - Esquema

    private struct DatabaseResponse: Decodable {
        struct Property: Decodable { let type: String }
        let properties: [String: Property]
    }

    private func loadSchema(database: String, token: String) async throws -> [String: String] {
        if let schema, schemaDatabase == database { return schema }

        let data = try await send(
            path: "databases/\(database)", method: "GET", body: nil, token: token
        )
        let decoded = try JSONDecoder().decode(DatabaseResponse.self, from: data)
        let mapa = decoded.properties.mapValues(\.type)
        schema = mapa
        schemaDatabase = database
        return mapa
    }

    /// Descarta o esquema em memória. Usar quando o usuário mexer no banco.
    public func forgetSchema() {
        schema = nil
        schemaDatabase = nil
    }

    // MARK: - Salvar

    @discardableResult
    public func save(title: String, url: String?, kind: String, notes: String?,
                     database: String) async throws -> NotionSavedItem {
        guard let token = Secrets.read(.notion) else { throw NotionError.noToken }
        let id = database.replacingOccurrences(of: "-", with: "")
        guard !id.isEmpty else { throw NotionError.noDatabase }

        let esquema = try await loadSchema(database: id, token: token)
        guard let tituloProp = esquema.first(where: { $0.value == "title" })?.key else {
            throw NotionError.noTitleProperty
        }

        var propriedades: [String: Any] = [
            tituloProp: ["title": [["text": ["content": String(title.prefix(1900))]]]]
        ]

        if let url, !url.isEmpty, let urlProp = propriedade(de: "url", em: esquema) {
            propriedades[urlProp] = ["url": url]
        }
        if let tipoProp = propriedade(de: "select", em: esquema, preferindo: ["tipo", "type", "categoria"]) {
            propriedades[tipoProp] = ["select": ["name": kind]]
        }
        if let notes, !notes.isEmpty,
           let notasProp = propriedade(de: "rich_text", em: esquema, preferindo: ["notas", "notes", "descrição", "description"]) {
            propriedades[notasProp] = ["rich_text": [["text": ["content": String(notes.prefix(1900))]]]]
        }
        if let dataProp = propriedade(de: "date", em: esquema) {
            propriedades[dataProp] = ["date": ["start": ISO8601DateFormatter().string(from: Date())]]
        }

        let corpo: [String: Any] = [
            "parent": ["database_id": id],
            "properties": propriedades,
        ]
        let json = try JSONSerialization.data(withJSONObject: corpo)
        let resposta = try await send(path: "pages", method: "POST", body: json, token: token)

        struct Criada: Decodable { let id: String }
        let criada = try? JSONDecoder().decode(Criada.self, from: resposta)

        return NotionSavedItem(
            id: criada?.id ?? UUID().uuidString,
            title: title, url: url, kind: kind, savedAt: Date()
        )
    }

    /// Procura uma propriedade do tipo pedido, preferindo nomes esperados
    /// quando o banco tiver mais de uma.
    private func propriedade(de tipo: String, em esquema: [String: String],
                             preferindo nomes: [String] = []) -> String? {
        let candidatas = esquema.filter { $0.value == tipo }.map(\.key)
        for nome in nomes {
            if let achada = candidatas.first(where: { $0.lowercased() == nome }) { return achada }
        }
        return candidatas.sorted().first
    }

    // MARK: - Rede

    private func send(path: String, method: String, body: Data?, token: String) async throws -> Data {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.version, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                if code == 401 { Secrets.invalidate(.notion) }
                struct Erro: Decodable { let message: String? }
                let mensagem = (try? JSONDecoder().decode(Erro.self, from: data))?.message
                    ?? String(decoding: data.prefix(200), as: UTF8.self)
                throw NotionError.http(code, mensagem)
            }
            return data
        } catch let erro as NotionError {
            throw erro
        } catch {
            throw NotionError.transport(error.localizedDescription)
        }
    }

    // MARK: - Classificação

    /// Deduz o tipo pelo domínio, para o usuário não precisar escolher a cada
    /// link salvo.
    public nonisolated static func classify(_ raw: String) -> String {
        guard let host = URL(string: raw)?.host?.lowercased() else { return "Nota" }
        switch true {
        case host.contains("youtube.") || host.contains("youtu.be") || host.contains("vimeo."):
            return "Vídeo"
        case host.contains("twitter.") || host.contains("x.com") || host.contains("bsky."):
            return "Tweet"
        case host.contains("github.") || host.contains("gitlab."):
            return "Repositório"
        case host.contains("reddit.") || host.contains("news.ycombinator"):
            return "Fórum"
        default:
            return "Artigo"
        }
    }
}
