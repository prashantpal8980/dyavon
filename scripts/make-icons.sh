#!/usr/bin/env bash
# Rebuild every icon from assets/icon/dyavon-template.svg (R51): one set per colour theme.
#
#   scripts/make-icons.sh
#
# For each theme it fills the template's colours and writes assets/icon/themes/<theme>/:
# dyavon.svg, PNGs 16-512, and the raw 32/64 RGBA the window and tray use. The app
# embeds those (brand.rs) and switches icon with the theme. The Amber set is also copied
# to assets/icon/ (dyavon.svg, PNGs, dyavon.ico), which build.rs puts into dyavon.exe.
# Renders with headless Chromium for faithful SVG, ImageMagick for the rest. Rebuild the
# app afterwards.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON="$REPO_ROOT/assets/icon"
command -v chromium >/dev/null && command -v convert >/dev/null || { echo "needs chromium and ImageMagick" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# theme  tile  letter(left half)  river(right half)  edge
THEMES="
ember     #17120E #F5EDE3 #F59E0B #17120E
graphite  #16171A #E9EAEC #6CC4D6 #16171A
plum      #2B1D30 #F6EEF5 #E2B1DF #2B1D30
forest    #18302A #EAF4EE #8FDCB4 #18302A
slate     #1F2836 #F1ECE3 #9CC3EC #1F2836
porcelain #F7F7F5 #1B1C1E #B86A1F #D6D4CF
coral     #FBF3E8 #1F1A17 #EF5B35 #E2D6C6
lime      #1C1E22 #F4F4F2 #BEF264 #1C1E22
saffron   #F5A524 #1A1A1E #FFF6E5 #F5A524
violet    #F1EEFF #2E1F7A #12A594 #D6D0EC
"

render() { # svg size out.png
  printf "<html><body style='margin:0;background:transparent'><img src='file://%s' width=%s height=%s style='display:block'></body></html>" \
    "$1" "$2" "$2" > "$TMP/one.html"
  chromium --headless=new --no-first-run --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --default-background-color=00000000 --user-data-dir="$TMP/profile" --window-size=600,600 \
    --virtual-time-budget=1000 --screenshot="$TMP/one.png" "file://$TMP/one.html" >/dev/null 2>&1
  convert "$TMP/one.png" -crop "${2}x${2}+0+0" +repage "PNG32:$3"
}

echo "$THEMES" | while read -r name bg letter river edge; do
  [ -n "$name" ] || continue
  out="$ICON/themes/$name"; mkdir -p "$out"
  sed -e "s/\"BG\"/\"$bg\"/g" -e "s/\"LETTER\"/\"$letter\"/g" -e "s/\"RIVER\"/\"$river\"/g" -e "s/\"EDGE\"/\"$edge\"/g" \
    "$ICON/dyavon-template.svg" > "$out/dyavon.svg"
  for s in 16 24 32 48 64 128 256 512; do render "$out/dyavon.svg" "$s" "$out/dyavon-$s.png"; done
  convert "$out/dyavon-64.png" -depth 8 "rgba:$out/dyavon-64.rgba"
  convert "$out/dyavon-32.png" -depth 8 "rgba:$out/dyavon-32.rgba"
  echo "  $name"
done

# Amber is the default: it is the exe's icon and the one in the README.
cp "$ICON/themes/ember/dyavon.svg" "$ICON/dyavon.svg"
for s in 16 24 32 48 64 128 256 512; do cp "$ICON/themes/ember/dyavon-$s.png" "$ICON/dyavon-$s.png"; done
( cd "$ICON" && convert dyavon-16.png dyavon-24.png dyavon-32.png dyavon-48.png dyavon-64.png dyavon-128.png dyavon-256.png dyavon.ico )
echo "icons rebuilt from $ICON/dyavon-template.svg"
