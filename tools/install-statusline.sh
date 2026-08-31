#!/bin/bash
# Instala a ponte da statusline em ~/.claude/settings.json.
#
# Preserva a statusline existente: ela passa a ser chamada pela ponte, que so
# grava o JSON e repassa a entrada. Idempotente e reversível.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
BRIDGE="$(cd "$(dirname "$0")" && pwd)/nook-statusline.sh"

[ -f "$SETTINGS" ] || { echo "não encontrei $SETTINGS"; exit 1; }
[ -f "$BRIDGE" ] || { echo "não encontrei $BRIDGE"; exit 1; }

/usr/bin/python3 - "$SETTINGS" "$BRIDGE" <<'PY'
import json, shutil, sys, datetime, re, os

settings_path, bridge = sys.argv[1], sys.argv[2]
data = json.load(open(settings_path))
current = (data.get("statusLine") or {}).get("command", "")

ja_instalada = bridge in current

backup = f"{settings_path}.bak-{datetime.datetime.now():%Y%m%d%H%M%S}"

# Preserva o script atual como statusline interna, para nada parar de funcionar.
#
# Procura todos os caminhos .sh e fica com o primeiro que exista e não seja a
# própria ponte. Um regex ganancioso engolia o prefixo da variável de ambiente
# junto com o caminho, e a statusline anterior se perdia em silêncio.
inner = ""
candidatos = re.findall(r'"([^"]+\.sh)"', current) + re.findall(r'(?<![\"=])(/[^\s"]+\.sh)', current)
for c in candidatos:
    caminho = os.path.expanduser(c)
    if os.path.exists(caminho) and os.path.abspath(caminho) != os.path.abspath(bridge):
        inner = c
        break

comando = f'bash "{bridge}"'
if inner:
    comando = f'NOOK_INNER_STATUSLINE="{inner}" bash "{bridge}"'

# Reescreve mesmo se a ponte já estiver instalada: ela pode ter perdido a
# statusline interna, e nesse caso "já instalada" seria uma resposta errada.
if comando == current:
    print("ponte já instalada e correta")
    raise SystemExit(0)

shutil.copy2(settings_path, backup)
data["statusLine"] = {"type": "command", "command": comando}
json.dump(data, open(settings_path, "w"), indent=2, ensure_ascii=False)
print(f"{'atualizada' if ja_instalada else 'instalada'}. backup em {backup}")
print("statusline interna preservada:", inner or "(nenhuma)")
PY
