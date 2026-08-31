import AppKit
import SwiftUI
import TokenDeckCore

/// Captura rápida para o Notion. Cole um link, aperte enter, acabou.
struct NotionBlock: View {
    let recent: [NotionSavedItem]
    let ready: Bool
    let onSave: (String) async -> String?

    @State private var texto = ""
    @State private var salvando = false
    @State private var erro: String?

    private var tipo: String { NotionClient.classify(texto) }
    private var pareceLink: Bool { texto.lowercased().hasPrefix("http") }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !ready {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Notion não configurado.", systemImage: "link.badge.plus")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Falta o token da integração e o notionDatabaseID em config.json.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.32))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            } else {
                HStack(spacing: 7) {
                    TextField("Cole um link ou escreva uma nota", text: $texto)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.9))
                        .onSubmit { salvar() }

                    if pareceLink {
                        Text(tipo)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }

                    Button(action: salvar) {
                        if salvando {
                            ProgressView().controlSize(.small).scaleEffect(0.6)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(texto.isEmpty ? 0.2 : 0.75))
                    .disabled(texto.isEmpty || salvando)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )

                if let erro {
                    Text(erro)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color(red: 0.98, green: 0.5, blue: 0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recent.prefix(4)) { item in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: 4, height: 4)
                            Text(item.title)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(item.kind) · \(Format.elapsed(since: item.savedAt))")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.28))
                        }
                    }
                }
            }
        }
    }

    private func salvar() {
        let conteudo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conteudo.isEmpty, !salvando else { return }
        salvando = true
        erro = nil
        Task {
            let falha = await onSave(conteudo)
            salvando = false
            if let falha {
                erro = falha
            } else {
                texto = ""
            }
        }
    }
}
