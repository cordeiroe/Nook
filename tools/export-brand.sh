#!/bin/bash
# Regera a arte do README a partir do código da marca.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# O Brand.swift depende de Theme.alertTint; um recorte basta para o exportador.
cat > "$TMP/theme.swift" <<'SWIFT'
import SwiftUI
enum Theme {
    static func alertTint(_ ratio: Double) -> Color {
        ratio < 0.92 ? Color(red: 0.98, green: 0.72, blue: 0.20)
                     : Color(red: 0.98, green: 0.32, blue: 0.16)
    }
}
SWIFT

cat "$TMP/theme.swift" "$ROOT/Sources/NookApp/Brand.swift" "$ROOT/tools/export-brand.swift" > "$TMP/main.swift"
swift "$TMP/main.swift"
