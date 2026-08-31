# Regras do projeto

Nook é uma central de controle no notch do macOS. Leia o [README](README.md)
para o que ele faz e o [TECHNICAL.md](TECHNICAL.md) para como funciona.

## Segurança

Estas regras vêm antes de qualquer outra coisa. O Nook lê a máquina inteira do
usuário: conversas com IA, agenda, área de transferência, arquivos. Um deslize
aqui é diferente de um bug de layout.

### Segredos

- **Nenhum segredo entra no repositório.** Credenciais vivem em
  `~/Library/Application Support/Nook/credentials.json`, modo `0600`, criado
  com a permissão certa **antes** de escrever. Criar aberto e apertar depois
  deixa uma janela em que o segredo fica legível.
- **Nunca receba uma chave por argumento de linha de comando.** `argv` é
  visível para outros processos e fica no histórico do shell. O `nookauth` lê
  de stdin, e qualquer ferramenta nova deve fazer o mesmo.
- **Nunca imprima um segredo**, nem em log, nem em mensagem de erro, nem
  truncado. Ao diagnosticar, compare tamanho ou hash, nunca o valor.
- Ao adicionar um provedor, acrescente um `Secrets.Slot`. Não invente um
  caminho paralelo de armazenamento.

### Dados do usuário

- **A área de transferência tem quatro camadas de defesa** (marcadores do
  sistema, aplicativo de origem, formato do conteúdo, prazo de validade).
  Nenhuma delas é redundante. Não enfraqueça nem remova nenhuma, e ao mexer no
  módulo rode os casos de teste de detecção antes de considerar pronto.
- **A prateleira guarda caminhos, não cópias.** A única exceção são imagens
  vindas da área de transferência, que não têm original para apontar. Arquivo
  do usuário nunca é apagado; só as cópias que o próprio app criou.
- **Arquivos com dado sensível nascem `0600`**: `credentials.json`,
  `clipboard.json` e `claude-limits.json`. Este último carrega caminhos de
  projeto, nome de sessão e `transcript_path`.
- **O banco do opencode é aberto somente para leitura** (`mode=ro`) e a conexão
  nunca é mantida aberta entre consultas: ele roda em WAL e uma conexão viva
  atrapalha o checkpoint dele.
- Nunca escreva em `~/.claude` nem em `~/.local/share/opencode`. São dados de
  outras ferramentas.

### Rede

- **Toda requisição de saída precisa de aprovação explícita do usuário.** Hoje
  existem exatamente três: cota da MiniMax, capa do álbum no CDN do Spotify, e
  o que o usuário manda para o Notion. Acrescentar uma quarta é decisão de
  produto, não de implementação.
- Não existe servidor do Nook. Não introduza telemetria, nem anônima.

### Permissões do macOS

- **Não mude o identificador do bundle** (`app.nook.widget`). Ele entra no
  requisito designado da assinatura, e trocá-lo zera Calendário, Automação e
  acesso a pastas.
- **Não rode `tools/make-signing-identity.sh` de novo.** Um certificado novo
  tem o mesmo efeito.
- Chamada que pode disparar diálogo de permissão **nunca vai na main thread**:
  ela bloqueia quem chamou até o usuário responder. Já derrubou o app inteiro
  uma vez, que subia sem janela nenhuma.

## Arquitetura

- `Sources/NookCore` lê dados e não importa SwiftUI. `Sources/NookApp` desenha.
  Não misture.
- **Cada módulo do cartão é independente.** Se a fonte falhar, o bloco mostra
  seu próprio estado vazio e o resto continua. Um módulo nunca derruba outro.
- Módulos novos entram em `ModuleKind`, com `isImplemented` e um ícone, e são
  ligados por `config.modules`. Nada de condicional espalhada pela view.
- Configuração usa `decodeIfPresent` em todo campo. O `JSONDecoder` não aplica
  valores default de propriedade: sem isso, um campo novo invalida o arquivo
  inteiro e todas as preferências do usuário voltam ao padrão em silêncio.

## Verificação

Este projeto acumulou uma coleção de bugs que só apareceram porque alguém foi
medir. A regra vale mais que qualquer convenção de estilo:

- **Meça, não conclua.** A estimativa local de consumo dizia 36% quando o real
  era 100%. O custo do opencode por período estava 26 vezes maior. Os dois
  passaram porque pareciam plausíveis.
- **Confira o que a interface desenha, não só o que o código calcula.** Vários
  defeitos da marca só apareceram renderizando a view fora da tela e olhando.
  `tools/export-brand.sh` faz isso para a marca.
- **Desconfie de resultado que bate com a expectativa cedo demais.** A
  deduplicação da agenda pareceu certa até a altura do painel não fechar com o
  número de eventos.
- Ao afirmar que algo funciona, diga como foi verificado. Se não deu para
  verificar, diga isso em vez de deixar implícito.

## Estilo

- Comentários em português, explicando **por que**, não o que. Comentário que
  repete o código em prosa é ruído.
- Documente a armadilha, não a função. `// soma os tokens` não ajuda ninguém;
  `// cache read entra aqui, mas custa uma fração do input normal` ajuda.
- Nomes em português no domínio, em inglês nas APIs do sistema. Não traduza
  `NSPasteboard`.
- Sem travessão em texto corrido, nem em comentário nem em documentação.

## Comandos

```bash
./make-app.sh && open dist/Nook.app   # compila e abre
./.build/debug/nookprobe              # imprime o que o painel mostraria
./.build/debug/nookauth status        # onde cada credencial está
./tools/export-brand.sh               # regera a arte do README
```

O `nookprobe` é a forma mais rápida de conferir a camada de dados sem depender
da interface.
