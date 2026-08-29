#!/bin/bash
# Instala a ponte da statusline em ~/.claude/settings.json.
#
# Preserva a statusline existente: ela passa a ser chamada pela ponte, que so
# grava o JSON e repassa a entrada. Idempotente e reversível.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
BRIDGE="$(cd "$(dirname "$0")" && pwd)/tokendeck-statusline.sh"

[ -f "$SETTINGS" ] || { echo "não encontrei $SETTINGS"; exit 1; }
[ -f "$BRIDGE" ] || { echo "não encontrei $BRIDGE"; exit 1; }

/usr/bin/python3 - "$SETTINGS" "$BRIDGE" <<'PY'
import json, shutil, sys, datetime, re, os

settings_path, bridge = sys.argv[1], sys.argv[2]
data = json.load(open(settings_path))
current = (data.get("statusLine") or {}).get("command", "")

if bridge in current:
    print("ponte já instalada")
    raise SystemExit(0)

backup = f"{settings_path}.bak-{datetime.datetime.now():%Y%m%d%H%M%S}"
shutil.copy2(settings_path, backup)

# Preserva o script atual como statusline interna, para nada parar de funcionar.
inner = ""
found = re.search(r'"([^"]+\.sh)"|(\S+\.sh)', current)
if found:
    inner = found.group(1) or found.group(2)

data["statusLine"] = {
    "type": "command",
    "command": f'bash "{bridge}"',
}
if inner and os.path.exists(os.path.expanduser(inner)):
    data["statusLine"]["command"] = (
        f'TOKENDECK_INNER_STATUSLINE="{inner}" bash "{bridge}"'
    )

json.dump(data, open(settings_path, "w"), indent=2, ensure_ascii=False)
print(f"instalada. backup em {backup}")
print("statusline interna preservada:", inner or "(nenhuma)")
PY
