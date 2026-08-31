# Nook por dentro

Detalhes de implementação, permissões do macOS e as armadilhas já pagas. Para
saber o que o Nook faz, veja o [README](README.md).

## Requisitos

- macOS 14 ou superior
- Xcode 15 ou superior (usa apenas SwiftPM, sem projeto Xcode)

## De onde vêm os dados

Tudo é lido localmente. Só existem duas requisições de saída: a consulta de cota
à MiniMax e o download da capa do álbum no CDN do Spotify.

| Dado | Origem |
|---|---|
| Limites do plano Claude (5h, semana, créditos) | JSON que o Claude Code entrega à statusline |
| Consumo por janela e por projeto | `~/.claude/projects/*/*.jsonl` |
| Sessões vivas do Claude Code | `~/.claude/sessions/<pid>.json` |
| Sessões, custo e tokens do opencode | `~/.local/share/opencode/opencode.db`, somente leitura |
| Cota da MiniMax | `GET /v1/token_plan/remains` |
| Agenda | EventKit, que enxerga iCloud, Google e Exchange do sistema |
| Tocando agora | AppleScript no Spotify e no app Música |
| Capturas recentes | pasta de capturas e imagens na área de transferência |
| Área de transferência | `NSPasteboard`, consultada a cada 0,6s |
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

```
ad-hoc:       designated => cdhash H"0775836e…"
certificado:  designated => identifier "app.nook.widget"
                            and certificate leaf = H"9ade6343…"
```

Não precisa de `sudo` nem de confiar no certificado: o `codesign` só precisa da
chave privada. Isso não substitui uma conta Apple Developer, necessária apenas
para distribuir a terceiros com notarização.

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
decidir nada: numa medição real ela apontava 36% quando o consumo verdadeiro da
janela de 5 horas era 100%.

### 5. Chave da MiniMax, se você usa

```bash
printf %s "$SUA_CHAVE" | ./.build/debug/nookauth set minimax
```

Lê de stdin para a chave não aparecer em `argv` nem no histórico do shell.
Guarda em `credentials.json` com modo `0600`. Use `--keychain` para preferir o
chaveiro.

### 6. Notion, se você usa

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
funciona sem renomear nada.

## Configuração

`~/Library/Application Support/Nook/config.json`

```jsonc
{
  "modules": ["usage", "calendar", "sessions", "nowPlaying", "clipboard", "shelf", "notion"],
  "selectedModule": "usage",         // aba aberta
  "alertThreshold": 0.80,            // quando o arco do notch acende
  "openCodeMonthlyBudgetUSD": 50,    // denominador do gasto MiniMax
  "refreshInterval": 15,             // ciclo de fundo, em segundos
  "clipboardRetentionHours": 8,      // idade máxima de um item copiado
  "clipboardMaxItems": 40,
  "clipboardIgnoredApps": ["com.1password.1password", "..."],
  "shelfCapturesPastedImages": true,
  "notionDatabaseID": ""
}
```

Campos ausentes voltam ao padrão sem invalidar o resto do arquivo. O
`JSONDecoder` não aplica valores default de propriedade: sem `decodeIfPresent`,
acrescentar um campo novo invalidaria o arquivo inteiro e todas as preferências
voltariam ao padrão em silêncio.

## Atualização

Duas fontes atualizam por evento, não por ciclo:

| Fonte | Quando atualiza |
|---|---|
| Limites do plano Claude | ~50ms após a statusline escrever |
| Status das sessões | por evento na pasta de sessões |
| Capturas na prateleira | por evento na pasta de capturas |
| Cota da MiniMax | no máximo a cada 90s |
| Tocando agora, opencode, contagem local | ciclo de 15s |

O `PathWatcher` observa o diretório, nunca o arquivo: escrita atômica troca o
inode e um descritor aberto no arquivo antigo nunca mais recebe evento. O mtime
vem de `stat()`, não de `URL.resourceValues`, que guarda cache na instância e
congelaria a data na primeira leitura.

## Ferramentas

| Comando | Para quê |
|---|---|
| `./.build/debug/nookprobe` | Imprime tudo que o painel mostraria, em texto |
| `./.build/debug/nookauth status` | Onde cada credencial está guardada |
| `./tools/install-statusline.sh` | Instala a ponte da statusline |
| `./tools/make-signing-identity.sh` | Cria a identidade de assinatura |

## Área de transferência

Guardar tudo que você copia é guardar senhas e tokens por acidente. A defesa
tem quatro camadas, porque nenhuma sozinha basta:

1. **Marcadores do sistema.** Gerenciadores de senha anunciam "não guarde isto"
   pelos tipos `org.nspasteboard.ConcealedType`, `TransientType` e
   `AutoGeneratedType`.
2. **Aplicativo de origem.** Cópias vindas de um gerenciador conhecido são
   ignoradas mesmo sem marcador, porque nem todos marcam. A lista está em
   `clipboardIgnoredApps`.
3. **Formato do conteúdo.** Chaves da OpenAI, Anthropic, MiniMax, GitHub,
   GitLab, Slack, AWS e Google, além de JWT e blocos de chave privada.
4. **Prazo de validade.** O que escapar das três anteriores desaparece sozinho
   em `clipboardRetentionHours`, oito horas por padrão.

O que resta em risco é o segredo sem marcador, vindo de um app desconhecido e
sem formato reconhecível. Por isso o prazo é curto e existe o botão de limpar.

Só texto é guardado, no máximo 20 KB por item, em `clipboard.json` com modo
`0600`.

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

## Privacidade

Nada é versionado nem transmitido, fora duas requisições de saída: a consulta
de cota à MiniMax e o download da capa do álbum no CDN do Spotify.

- `credentials.json`, `claude-limits.json` e `clipboard.json` são gravados com
  modo `0600`
- A prateleira guarda caminhos, nunca cópias, com uma exceção: imagens vindas
  da área de transferência, que não têm original para apontar
- O banco do opencode é aberto somente para leitura, e a conexão nunca é
  mantida aberta entre consultas, para não atrapalhar o checkpoint do WAL dele
- `.env` está no `.gitignore`

## Limitações conhecidas

- Os limites reais só chegam enquanto o Claude Code está aberto, porque é ele
  que executa a statusline. Sem sessão o dado envelhece, e o cartão mostra há
  quanto tempo foi capturado.
- As janelas de Dia e Mês são referência, não cota: o teto é escolhido por
  você. Elas aparecem com barra apagada, sem cor de limite.
- `spend_limit` nem sempre vem no payload. Quando vier, o medidor de créditos
  aparece sozinho.
- A agenda usa EventKit, então só enxerga contas configuradas em Ajustes do
  Sistema > Contas de Internet. Calendário aberto apenas no navegador não
  aparece.
- A capa do álbum vem de `artwork url`, que só o Spotify expõe. No app Música
  o bloco aparece sem capa.
- A pasta de capturas costuma ser protegida por TCC. O bloco da prateleira tem
  um atalho para o painel de autorização.
- Com Cmd+Shift+5, o macOS segura o arquivo numa pasta temporária enquanto a
  miniatura flutuante está na tela, e só o move para o destino quando ela
  expira. Quem arrasta ou cola a miniatura antes disso consome o arquivo de lá,
  e nada chega à pasta de capturas. Por isso a prateleira também guarda imagens
  que passam pela área de transferência. Desligue em
  `shelfCapturesPastedImages`.

## Marca

A marca é a palavra `nook` com um sorriso por baixo do `oo`. O arco tem a mesma
largura e espessura do traço de alerta, e por isso ele **é** o traço: passando
de 80%, o sorriso acende em laranja em vez de aparecer um elemento novo. Laranja
não é usado em mais nada, para não perder o significado de aviso.

Só aparece no recorte virtual. Num MacBook o recorte é a câmera e não existem
pixels ali para desenhar.

O arco não é uma parábola. O CSS do desenho pede `border-radius: 0 0 26px 26px`
numa caixa de 26x8, e o navegador encolhe raios que não cabem: o raio real vira
8, e o traço fica reto no meio com as pontas viradas para cima. Desenhar uma
parábola no lugar produzia um U que abraçava a palavra inteira. Na largura do
desenho as pontas ainda subiam dentro do `n` e do `k`, então o arco foi
estreitado para caber sob o `oo`, que é o que o desenho descreve em texto.

A fonte é Bricolage Grotesque SemiBold, empacotada em `Resources/` sob a SIL
Open Font License e registrada em tempo de execução com
`CTFontManagerRegisterFontsForURL`. Ela não vai como recurso do SwiftPM porque
isso geraria um bundle separado que o `make-app.sh` teria de copiar de qualquer
forma. Se o registro falhar, a marca cai numa fonte do sistema em vez de
desaparecer.

## Estrutura

```
Sources/NookCore/    leitura de dados, sem UI
Sources/NookApp/     painel do notch e barra de menus
Sources/nookprobe/   diagnóstico em linha de comando
Sources/nookauth/    gerência de credenciais
Resources/           fonte da marca, empacotada no app
tools/               assinatura e ponte da statusline
attic/               régua de borda, substituída pelo modo notch
```
