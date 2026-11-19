#!/usr/bin/env bash
# Rebuild every icon size from one SVG (R50).
#
#   scripts/make-icons.sh [assets/icon/concepts/a-crossing.svg]
#
# With an argument, that SVG becomes assets/icon/dyavon.svg first. Writes the PNGs
# (16-512), the Windows .ico (embedded into dyavon.exe by build.rs) and the raw RGBA the
# window and tray use. Renders with headless Chromium for faithful SVG, ImageMagick for
# the rest. Rebuild the app afterwards.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$REPO_ROOT/assets/icon"
[ -n "${1:-}" ] && cp "$1" "$ICON/dyavon.svg"
command -v chromium >/dev/null && command -v convert >/dev/null || { echo "needs chromium and ImageMagick" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for s in 16 24 32 48 64 128 256 512; do
  printf "<html><body style='margin:0;background:transparent'><img src='file://%s' width=%s height=%s style='display:block'></body></html>" \
    "$ICON/dyavon.svg" "$s" "$s" > "$TMP/one.html"
  chromium --headless=new --no-first-run --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --default-background-color=00000000 --user-data-dir="$TMP/profile" --window-size=600,600 \
    --virtual-time-budget=1000 --screenshot="$TMP/one.png" "file://$TMP/one.html" >/dev/null 2>&1
  convert "$TMP/one.png" -crop "${s}x${s}+0+0" +repage "PNG32:$ICON/dyavon-$s.png"
done
( cd "$ICON" && convert dyavon-16.png dyavon-24.png dyavon-32.png dyavon-48.png dyavon-64.png dyavon-128.png dyavon-256.png dyavon.ico )
convert "$ICON/dyavon-64.png" -depth 8 "rgba:$ICON/dyavon-64.rgba"
convert "$ICON/dyavon-32.png" -depth 8 "rgba:$ICON/dyavon-32.rgba"
echo "icons rebuilt from $ICON/dyavon.svg"
