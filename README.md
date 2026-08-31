# Nook

Central de controle no notch do macOS. Consumo de IA, agenda, sessões em
andamento, música, área de transferência e uma prateleira de arquivos, tudo
num recanto da tela que você já não usava.

Em repouso, nada é desenhado: o próprio recorte da tela é o alvo do mouse. Ao
passar o cursor, um cartão desce com abas, uma por módulo, e mostra um de cada
vez. Quando um limite passa de 80%, um arco fino acende na borda inferior do
notch.

Em telas sem notch físico o recorte é desenhado, com os mesmos 220pt de largura
e cantos inferiores arredondados. Sem isso o painel flutuaria solto no meio da
barra de menus e perderia a ideia de sair de algum lugar.

## Requisitos

- macOS 14 ou superior
- Xcode 15 ou superior (usa apenas SwiftPM, sem projeto Xcode)

## De onde vêm os dados

Tudo é lido localmente. O app não envia nada para lugar nenhum, com uma única
exceção: a consulta de cota da MiniMax, que vai para a API deles.

| Dado | Origem |
|---|---|
| Limites do plano Claude (5h, semana, créditos) | JSON que o Claude Code entrega à statusline |
| Consumo por janela e por projeto | `~/.claude/projects/*/*.jsonl` |
| Sessões vivas do Claude Code | `~/.claude/sessions/<pid>.json` |
| Sessões, custo e tokens do opencode | `~/.local/share/opencode/opencode.db` (somente leitura) |
| Cota da MiniMax | `GET /v1/token_plan/remains` |
| Tocando agora | AppleScript no Spotify e no app Música; capa vinda do CDN do Spotify |
| Capturas recentes | pasta de capturas e imagens na área de transferência |
| Área de transferência | `NSPasteboard`, consultada a cada 0,6s |
| Agenda | EventKit, que enxerga iCloud, Google e Exchange do sistema |
| Notion | `POST /v1/pages` na API do Notion |

## Instalação

### 1. Identidade de assinatura

```bash
./tools/make-signing-identity.sh
```

Cria um certificado local autoassinado. Sem ele o app é assinado ad-hoc, e o
requisito designado passa a ser o hash do binário, que muda a cada build: o
macOS trata cada build como um app diferente e repete todos os pedidos de
permissão. Com o certificado, o requisito vira o identificador do bundle mais o
certificado, e as autorizações sobrevivem às atualizações.

Não precisa de `sudo` nem de confiar no certificado, e não substitui uma conta
Apple Developer, necessária apenas para distribuir a terceiros com notarização.

Rode uma vez só: recriar o certificado zera as permissões já concedidas.

Na primeira assinatura o macOS pede autorização para o `codesign` usar a chave.
Escolha **Sempre Permitir**: com "Permitir", ele volta a perguntar a cada build,
e enquanto o diálogo estiver aberto qualquer `codesign` fica travado esperando.

### 2. Ajustes de máquina

```bash
cp .env.example .env
```

O identificador do bundle entra no requisito designado. Escolha um e não mude
depois da primeira instalação.

### 3. Build

```bash
./make-app.sh && open dist/Nook.app
```

### 4. Limites reais do plano Claude

```bash
./tools/install-statusline.sh
```

O Claude Code entrega um JSON à statusline a cada render, e nele vêm os
percentuais reais das janelas de 5 horas, 7 dias e dos créditos. Esta é a única
fonte oficial desses números para planos Pro e Max: a Admin API de usage cobre
organizações de API, não contas do claude.ai.

O instalador preserva a statusline que já existia, que passa a ser chamada pela
ponte, e guarda um backup do `settings.json`.

Sem esse passo o app cai numa estimativa local calculada a partir dos `.jsonl`.
Ela é grosseira e o cartão avisa quando está nesse modo. Não confie nela para
decidir nada.

### 5. Chave da MiniMax, se você usa

```bash
printf %s "$SUA_CHAVE" | ./.build/debug/nookauth set minimax
```

Lê de stdin para a chave não aparecer em `argv` nem no histórico do shell.
Guarda em `credentials.json` com modo `0600`. Use `--keychain` para preferir o
chaveiro.

## Sessões

Clicar numa sessão traz o terminal dela para frente.

O processo do agente não é um aplicativo: ele é filho de um shell, que é filho
do terminal. O app sobe a árvore de processos até achar algo que o sistema
reconheça como aplicativo, e ativa.

Selecionar a aba certa depende do terminal. Terminal e iTerm2 expõem o TTY de
cada aba por AppleScript, e nesses o app acerta a aba. Warp, Ghostty e a
maioria dos outros não expõem, e ali o melhor possível é trazer a janela à
frente.

Sessão do opencode não tem processo associado, então o clique abre a pasta de
trabalho no Finder.

## Notion

Para salvar links no Notion:

1. Crie uma integração interna em <https://www.notion.so/my-integrations>
2. Compartilhe o banco de dados com ela, pelo menu de três pontos da página
3. Guarde o token e aponte o banco:

```bash
printf %s "$TOKEN" | ./.build/debug/nookauth set notion
```

```jsonc
{ "notionDatabaseID": "id que aparece na URL do banco" }
```

O nome das propriedades muda de banco para banco, então o cliente lê o esquema
e descobre onde cada coisa vai: a propriedade do tipo `title` recebe o texto, a
primeira `url` recebe o link, e assim por diante. Um banco montado à mão
funciona sem renomear nada. As colunas úteis são título, URL, um `select` para
o tipo, um `rich_text` para notas e uma data.

O tipo é deduzido do domínio: YouTube e Vimeo viram Vídeo; X e Bluesky, Tweet;
GitHub e GitLab, Repositório; Hacker News e Reddit, Fórum; o resto, Artigo.
Texto sem link vira Nota.

## Configuração

`~/Library/Application Support/Nook/config.json`

```jsonc
{
  "modules": ["usage", "calendar", "sessions", "nowPlaying", "clipboard", "shelf", "notion"],
  "selectedModule": "usage",         // aba aberta
  "alertThreshold": 0.80,          // quando o arco do notch acende
  "openCodeMonthlyBudgetUSD": 50,  // denominador do gasto MiniMax
  "refreshInterval": 15,           // ciclo de fundo, em segundos
  "clipboardRetentionHours": 8,    // idade máxima de um item copiado
  "clipboardMaxItems": 40,
  "clipboardIgnoredApps": ["com.1password.1password", "..."]
}
```

Campos ausentes voltam ao padrão sem invalidar o resto do arquivo.

## Ferramentas

| Comando | Para quê |
|---|---|
| `./.build/debug/nookprobe` | Imprime tudo que o painel mostraria, em texto |
| `./.build/debug/nookauth status` | Onde cada credencial está guardada |
| `./tools/install-statusline.sh` | Instala a ponte da statusline |

## Área de transferência

Guardar tudo que você copia é guardar senhas e tokens por acidente. A defesa
tem quatro camadas, porque nenhuma sozinha basta:

1. **Marcadores do sistema.** Gerenciadores de senha anunciam "não guarde isto"
   pelos tipos `org.nspasteboard.ConcealedType`, `TransientType` e
   `AutoGeneratedType`. Cobre o caso bem-comportado.
2. **Aplicativo de origem.** Cópias vindas de um gerenciador conhecido são
   ignoradas mesmo sem marcador, porque nem todos marcam. A lista está em
   `clipboardIgnoredApps`.
3. **Formato do conteúdo.** Chaves da OpenAI, Anthropic, MiniMax, GitHub,
   GitLab, Slack, AWS e Google, além de JWT e blocos de chave privada, têm
   prefixos reconhecíveis. Cobre o segredo copiado de um editor de texto.
4. **Prazo de validade.** O que escapar das três anteriores desaparece sozinho
   em `clipboardRetentionHours`, oito horas por padrão.

O que resta em risco é o segredo sem marcador, vindo de um app desconhecido e
sem formato reconhecível. Por isso o prazo é curto e existe o botão de limpar.

Só texto é guardado, no máximo 20 KB por item, em `clipboard.json` com modo
`0600`.

## Privacidade

Nada é versionado nem transmitido, fora duas requisições de saída: a consulta
de cota à MiniMax e o download da capa do álbum no CDN do Spotify.

- `credentials.json`, `claude-limits.json` e `clipboard.json` são gravados com
  modo `0600`
- A prateleira guarda caminhos, nunca cópias dos seus arquivos
- O banco do opencode é aberto somente para leitura, e a conexão nunca é
  mantida aberta entre consultas, para não atrapalhar o checkpoint do WAL dele
- `.env` está no `.gitignore`

## Limitações conhecidas

- Os limites reais só chegam enquanto o Claude Code está aberto, porque é ele
  que executa a statusline. Sem sessão o dado envelhece, e o cartão mostra há
  quanto tempo foi capturado.
- As janelas de Dia e Mês são referência, não cota: o teto é escolhido por
  você. Elas aparecem com barra apagada, sem cor de limite.
- A agenda usa EventKit, então só enxerga contas configuradas em Ajustes do
  Sistema > Contas de Internet. Calendário aberto apenas no navegador não
  aparece.
- A capa do álbum vem de `artwork url`, que só o Spotify expõe. No app Música
  o bloco aparece sem capa.
- `spend_limit` nem sempre vem no payload. Quando vier, o medidor de créditos
  aparece sozinho.
- A pasta de capturas costuma ser protegida por TCC. O bloco da prateleira tem
  um atalho para o painel de autorização.
- Com Cmd+Shift+5, o macOS segura o arquivo numa pasta temporária enquanto a
  miniatura flutuante está na tela, e só o move para o destino quando ela
  expira. Quem arrasta ou cola a miniatura antes disso consome o arquivo de lá,
  e nada chega à pasta de capturas. Por isso a prateleira também guarda imagens
  que passam pela área de transferência: é o que pega esse fluxo. Essas são a
  única exceção à regra de guardar caminhos, porque não existe original para
  apontar. Desligue em `shelfCapturesPastedImages`.

## Estrutura

```
Sources/NookCore/   leitura de dados, sem UI
Sources/NookApp/    painel do notch e barra de menus
Sources/nookprobe/         diagnóstico em linha de comando
Sources/nookauth/          gerência de credenciais
tools/                   assinatura e ponte da statusline
attic/                   régua de borda, substituída pelo modo notch
```

## Licença

MIT. Veja [LICENSE](LICENSE).
