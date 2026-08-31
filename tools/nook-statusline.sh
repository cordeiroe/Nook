#!/bin/bash
# Ponte entre a statusline do Claude Code e o Nook.
#
# O Claude Code manda um JSON na stdin da statusline a cada render, e nele vem
# `rate_limits`, com o percentual REAL das janelas de 5h, 7d e dos créditos.
# Essa é a única fonte oficial desses números para planos Pro e Max: a Admin
# API de usage cobre organizações de API, não claude.ai.
#
# Este script grava o JSON e repassa a entrada, intacta, para a statusline
# original. Ele nunca deve falhar de forma visível: se algo der errado, a
# statusline do usuário tem que continuar funcionando.
#
# Instalação em ~/.claude/settings.json:
#   "statusLine": { "type": "command",
#                   "command": "bash \"<caminho>/nook-statusline.sh\"" }

OUT="$HOME/Library/Application Support/Nook/claude-limits.json"

# Statusline original, executada depois da captura. Vazio = não repassa nada.
# O install-statusline.sh preenche esta variável com o que já estava
# configurado, para nenhuma statusline existente parar de funcionar.
ORIGINAL="${NOOK_INNER_STATUSLINE:-}"

INPUT=$(cat)

# Escrita atômica: a statusline roda a cada tecla e o Nook lê a qualquer
# momento. Sem o mv, ele leria JSON pela metade.
if [ -n "$INPUT" ]; then
    DIR=$(dirname "$OUT")
    mkdir -p "$DIR" 2>/dev/null
    TMP="$OUT.$$"
    # O payload traz caminhos de projeto, nome da sessão e o transcript_path.
    # Nada disso é segredo, mas também não precisa ser legível por qualquer
    # processo da máquina.
    ( umask 077; printf '%s' "$INPUT" > "$TMP" ) 2>/dev/null &&
        mv -f "$TMP" "$OUT" 2>/dev/null || rm -f "$TMP" 2>/dev/null
fi

if [ -n "$ORIGINAL" ] && [ -f "$ORIGINAL" ]; then
    printf '%s' "$INPUT" | bash "$ORIGINAL"
fi
exit 0
