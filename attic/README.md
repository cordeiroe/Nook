# Código aposentado

Estes arquivos implementavam a régua ancorada nas bordas da tela: aba de repouso
com rótulo vertical, arrasto livre com snap na borda mais próxima, orientação
horizontal no topo e na base, e a bolha por provider em painel separado.

Foram substituídos pelo modo notch em 2026-08-29, a pedido do usuário.

Ficam fora de `Sources/` porque o SwiftPM compila tudo que está lá dentro.
Para reativar, mover de volta para `Sources/NookApp/`.
