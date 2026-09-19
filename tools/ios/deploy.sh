#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IOS_DIR="$ROOT/build/ios"
PROJECT="$IOS_DIR/politropia.xcodeproj"
TEAM="${DEVELOPMENT_TEAM:-NN2XF448XH}"
BUNDLE="${BUNDLE_ID:-com.tomasleggire.politropia}"
GODOT="${GODOT:-}"

if [[ -z "$GODOT" ]]; then
  for candidate in \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
  do
    if [[ -x "$candidate" ]]; then
      GODOT="$candidate"
      break
    fi
  done
fi

if [[ -z "$GODOT" || ! -x "$GODOT" ]]; then
  echo "No encontré Godot. Definí GODOT=/ruta/al/binario." >&2
  exit 1
fi

pick_device() {
  local preferred="${DEVICE_ID:-00008140-0018509010E3C01C}"
  local devices
  devices="$(xcrun devicectl list devices 2>/dev/null || true)"
  if [[ -n "$preferred" ]] && echo "$devices" | grep -q "$preferred"; then
    echo "$preferred"
    return
  fi
  echo "$devices" | awk '
    /iPhone/ && /(available|connected)/ && /physical/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9A-Fa-f-]{25,}$/) {
          gsub(/^\(/, "", $i)
          gsub(/\)$/, "", $i)
          print $i
          exit
        }
      }
    }'
}

echo "==> Export iOS (Godot)"
mkdir -p "$IOS_DIR"
"$GODOT" --headless --path "$ROOT" --export-debug "iOS" "$IOS_DIR/politropia.ipa"

echo "==> Preparar Xcode"
ruby "$ROOT/tools/ios/prepare_xcode.rb"

echo "==> Compilar"
xcodebuild \
  -project "$PROJECT" \
  -scheme politropia \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic \
  build

APP="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*Index.noindex*" -prune -o -path "*/Build/Products/Debug-iphoneos/politropia.app" -print -quit)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "No encontré politropia.app compilada." >&2
  exit 1
fi

DEVICE="$(pick_device)"
if [[ -z "$DEVICE" ]]; then
  echo "No hay iPhone conectado. Conectalo y desbloquealo." >&2
  exit 1
fi

echo "==> Instalar en $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "==> Abrir la app"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE"
echo "Listo en el celular."
