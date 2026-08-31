#!/bin/bash
# Monta Nook.app a partir do executavel do SwiftPM.
# Sem Xcode project por enquanto: da pra fazer tudo pelo terminal ate o widget entrar.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/Nook.app"

# Ajustes de máquina ficam fora do versionamento. Copie .env.example para .env
# e edite lá; o repositório não carrega identificador nem identidade de ninguém.
[ -f "$ROOT/.env" ] && . "$ROOT/.env"

# O identificador entra no requisito designado da assinatura, junto do
# certificado. Trocá-lo faz o macOS tratar o app como novo e pedir todas as
# permissões de novo, então mantenha-o estável depois da primeira instalação.
BUNDLE_ID="${NOOK_BUNDLE_ID:-app.nook.widget}"
IDENTITY="${NOOK_SIGN_IDENTITY:-Nook Dev}"

swift build -c "$CONFIG" --product NookApp
BIN="$(swift build -c "$CONFIG" --product NookApp --show-bin-path)/NookApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Nook"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Nook</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>Nook</string>
    <key>CFBundleDisplayName</key><string>Nook</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- Sem icone no Dock: o app vive so no notch e na barra de menus. -->
    <key>LSUIElement</key><true/>
    <!-- Textos exibidos pelo macOS ao pedir cada permissao. Sem eles o
         sistema nega o acesso sem sequer perguntar. -->
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Mostrar seus próximos compromissos no painel do notch.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Ler o que está tocando no Spotify e no app Música.</string>
</dict>
</plist>
PLIST

# Assinar com identidade fixa mantem o requisito designado estavel entre
# builds, e com ele as permissoes ja concedidas (Calendario, Automacao,
# pastas protegidas). Ver tools/make-signing-identity.sh.
if security find-identity | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "aviso: identidade \"$IDENTITY\" ausente, caindo pra assinatura ad-hoc."
    echo "       o macOS vai repedir as permissoes a cada build."
    echo "       rode tools/make-signing-identity.sh para corrigir."
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "$APP"
