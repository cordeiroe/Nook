import Foundation
import Security

/// Segredos do TokenDeck.
///
/// Duas fontes, nesta ordem:
///
/// 1. `credentials.json` em Application Support, modo 0600. Leitura instantanea
///    e sem prompt. E o padrao.
/// 2. Keychain do usuario. Mais protegido, mas o macOS reavalia a ACL sempre que
///    a assinatura do binario muda, e num app assinado ad-hoc isso significa um
///    prompt de senha a cada rebuild.
///
/// O arquivo fica legivel por qualquer processo rodando como o usuario. Numa
/// maquina pessoal com FileVault isso e o mesmo nivel de protecao que
/// `~/.aws/credentials` ou o `auth.json` do proprio opencode. Se preferir o
/// Keychain, use `tdauth set <slot> --keychain`.
public enum Secrets {
    public enum Slot: String, CaseIterable, Sendable, Codable {
        case minimax = "TokenDeck-minimax"

        public var short: String {
            rawValue.replacingOccurrences(of: "TokenDeck-", with: "")
        }

        public var label: String {
            switch self {
            case .minimax: return "MiniMax API key"
            }
        }
    }

    public enum Store: String, Sendable {
        case file, keychain
    }

    private static let account = "tokendeck"
    private static let lock = NSLock()
    private static var cache: [Slot: String] = [:]

    private static var fileURL: URL {
        Paths.support.appending(path: "credentials.json")
    }

    // MARK: - Leitura

    public static func read(_ slot: Slot) -> String? {
        lock.lock()
        if let hit = cache[slot] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let value = readFile(slot) ?? readKeychain(slot)
        guard let value else { return nil }

        lock.lock()
        cache[slot] = value
        lock.unlock()
        return value
    }

    public static func location(_ slot: Slot) -> Store? {
        if readFile(slot) != nil { return .file }
        if readKeychain(slot) != nil { return .keychain }
        return nil
    }

    /// Descarta o valor em memoria. Usar quando a API rejeitar a credencial:
    /// pode ser que ela tenha sido trocada por fora.
    public static func invalidate(_ slot: Slot) {
        lock.lock()
        cache[slot] = nil
        lock.unlock()
    }

    // MARK: - Escrita

    @discardableResult
    public static func write(_ slot: Slot, value: String, to store: Store = .file) -> Bool {
        invalidate(slot)
        switch store {
        case .file:     return writeFile(slot, value: value)
        case .keychain: return writeKeychain(slot, value: value)
        }
    }

    @discardableResult
    public static func delete(_ slot: Slot, from store: Store? = nil) -> Bool {
        invalidate(slot)
        var ok = true
        if store == nil || store == .file { ok = deleteFile(slot) && ok }
        if store == nil || store == .keychain { ok = deleteKeychain(slot) && ok }
        return ok
    }

    // MARK: - Arquivo

    private static func loadFile() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private static func readFile(_ slot: Slot) -> String? {
        let value = loadFile()[slot.rawValue]
        return (value?.isEmpty == false) ? value : nil
    }

    private static func writeFile(_ slot: Slot, value: String) -> Bool {
        var dict = loadFile()
        dict[slot.rawValue] = value
        return saveFile(dict)
    }

    private static func deleteFile(_ slot: Slot) -> Bool {
        var dict = loadFile()
        guard dict.removeValue(forKey: slot.rawValue) != nil else { return true }
        return saveFile(dict)
    }

    /// Cria o arquivo ja com 0600 antes de escrever: criar aberto e apertar
    /// depois deixaria uma janela em que o segredo fica legivel por outros.
    private static func saveFile(_ dict: [String: String]) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(dict) else { return false }

        let fm = FileManager.default
        let path = fileURL.path
        if !fm.fileExists(atPath: path) {
            guard fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                return false
            }
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)

        do {
            try data.write(to: fileURL, options: [.atomic])
            // A escrita atomica troca o inode, entao a permissao precisa voltar.
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Keychain

    private static func baseQuery(_ slot: Slot) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: slot.rawValue,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readKeychain(_ slot: Slot) -> String? {
        var query = baseQuery(slot)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    private static func writeKeychain(_ slot: Slot, value: String) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(slot)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrLabel as String] = slot.label
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteKeychain(_ slot: Slot) -> Bool {
        let status = SecItemDelete(baseQuery(slot) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
