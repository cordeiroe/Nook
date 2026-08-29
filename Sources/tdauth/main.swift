import Foundation
import TokenDeckCore

// Gerencia credenciais lendo de stdin, pra chave nunca aparecer em argv nem no
// historico do shell.
//
//   printf %s "$KEY" | tdauth set minimax              # arquivo 0600 (padrao)
//   printf %s "$KEY" | tdauth set minimax --keychain   # Keychain
//   tdauth status
//   tdauth migrate minimax                             # Keychain -> arquivo
//   tdauth delete minimax

func usage() -> Never {
    let slots = Secrets.Slot.allCases.map(\.short).joined(separator: ", ")
    FileHandle.standardError.write(Data("""
    uso:
      printf %s "$KEY" | tdauth set <slot> [--keychain]
      tdauth status
      tdauth migrate <slot>     move do Keychain pro arquivo (sem mais prompts)
      tdauth delete <slot> [--keychain|--file]

    slots: \(slots)

    """.utf8))
    exit(2)
}

func slot(_ name: String) -> Secrets.Slot {
    guard let s = Secrets.Slot(rawValue: "TokenDeck-\(name)") else {
        FileHandle.standardError.write(Data("slot desconhecido: \(name)\n".utf8))
        exit(2)
    }
    return s
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

func masked(_ v: String) -> String {
    v.count > 12 ? "\(v.prefix(6))…\(v.suffix(4))" : "…"
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }

switch command {
case "set":
    guard args.count >= 2 else { usage() }
    let target = slot(args[1])
    let store: Secrets.Store = args.contains("--keychain") ? .keychain : .file

    let input = FileHandle.standardInput.readDataToEndOfFile()
    let value = String(decoding: input, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { fail("nada recebido em stdin") }
    guard Secrets.write(target, value: value, to: store) else { fail("falha ao gravar em \(store.rawValue)") }
    print("\(target.label): gravado em \(store.rawValue) (\(value.count) caracteres)")

case "status":
    for s in Secrets.Slot.allCases {
        guard let where_ = Secrets.location(s), let v = Secrets.read(s) else {
            print("\(s.label): ausente")
            continue
        }
        let note = where_ == .file ? "arquivo 0600, sem prompt" : "Keychain, pede senha a cada rebuild"
        print("\(s.label): \(masked(v))  \(v.count) caracteres  [\(note)]")
    }

case "migrate":
    guard args.count == 2 else { usage() }
    let target = slot(args[1])
    guard Secrets.location(target) == .keychain else {
        print("\(target.label): nada a migrar (já está no arquivo ou ausente)")
        exit(0)
    }
    guard let value = Secrets.read(target) else { fail("não consegui ler do Keychain") }
    guard Secrets.write(target, value: value, to: .file) else { fail("falha ao gravar no arquivo") }
    _ = Secrets.delete(target, from: .keychain)
    print("\(target.label): movido pro arquivo 0600, removido do Keychain")

case "delete":
    guard args.count >= 2 else { usage() }
    let target = slot(args[1])
    let store: Secrets.Store? = args.contains("--keychain") ? .keychain
        : (args.contains("--file") ? .file : nil)
    _ = Secrets.delete(target, from: store)
    print("\(target.label): removido de \(store?.rawValue ?? "arquivo e Keychain")")

default:
    usage()
}
