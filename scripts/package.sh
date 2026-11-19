#!/usr/bin/env bash
# Package dyavon into distributable artifacts:
#   dist/dyavon-<ver>-windows-x86_64.zip   (GUI exe; also runs server/client)
#   dist/dyavon-<ver>-linux-x86_64.tar.gz  (GUI + slim headless + bundled libxdo)
#   dist/SHA256SUMS
#
# Run from anywhere; paths resolve to the repo root. Builds release for both the
# host (x86_64-unknown-linux-gnu) and Windows (x86_64-pc-windows-gnu).
#
# The Linux GUI build links libxdo (via the tray's libappindicator). If the linker
# can't find `libxdo.so` (no `libxdo-dev`), this script auto-creates a shim symlink
# to the runtime `libxdo.so.3` so the build still succeeds — no root needed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck disable=SC1090
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

WIN_TARGET="x86_64-pc-windows-gnu"
VER="$(grep -m1 '^version' Cargo.toml | sed -E 's/.*"([^"]+)".*/\1/')"
DIST="$REPO_ROOT/dist"
STAGE="$REPO_ROOT/target/dist-staging"

echo "==> packaging dyavon v$VER"
rm -rf "$DIST" "$STAGE"
mkdir -p "$DIST" "$STAGE"

# --- locate + shim libxdo so the Linux GUI build links without libxdo-dev ---
LIBXDO="$(ldconfig -p 2>/dev/null | sed -nE 's/.*=> (.*libxdo\.so\.[0-9]+)$/\1/p' | head -1 || true)"
[ -z "$LIBXDO" ] && [ -f /usr/lib/x86_64-linux-gnu/libxdo.so.3 ] && LIBXDO=/usr/lib/x86_64-linux-gnu/libxdo.so.3
RUSTFLAGS_GUI=""
if [ -n "$LIBXDO" ]; then
  SHIM="$REPO_ROOT/.xdo-shim"
  mkdir -p "$SHIM"
  ln -sf "$LIBXDO" "$SHIM/libxdo.so"
  RUSTFLAGS_GUI="-L $SHIM"
  echo "==> using libxdo: $LIBXDO"
else
  echo "!! libxdo.so.3 not found — Linux GUI build may fail; install xdotool/libxdo3" >&2
fi

# --- build everything ---
# The two host variants share target/release/dyavon, so build each then immediately
# copy it to its own staged name before the next build overwrites it.
echo "==> building Linux headless (release, --no-default-features)"
cargo build --release -p dyavon --no-default-features
HEADLESS_LINUX="$STAGE/dyavon-headless"
cp target/release/dyavon "$HEADLESS_LINUX"

echo "==> building Linux GUI (release)"
RUSTFLAGS="$RUSTFLAGS_GUI" cargo build --release -p dyavon
cp target/release/dyavon "$STAGE/dyavon"

echo "==> building Windows GUI (release)"
cargo build --release -p dyavon --target "$WIN_TARGET"
cp "target/$WIN_TARGET/release/dyavon.exe" "$STAGE/dyavon.exe"

# ---------------- Linux tarball ----------------
echo "==> staging Linux tarball"
LX="$STAGE/dyavon-$VER-linux-x86_64"
mkdir -p "$LX/lib"
cp "$STAGE/dyavon" "$LX/dyavon"
cp "$HEADLESS_LINUX" "$LX/dyavon-headless"
cp config.example.json "$LX/config.example.json"
[ -n "$LIBXDO" ] && cp -L "$LIBXDO" "$LX/lib/libxdo.so.3"

cat > "$LX/run-gui.sh" <<'EOF'
#!/usr/bin/env bash
# Launch the GUI using the bundled libxdo (so you don't need the libxdo3 package).
# gtk3 + libayatana-appindicator are still required from the system (see README).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$DIR/lib:${LD_LIBRARY_PATH:-}"
exec "$DIR/dyavon" "$@"
EOF
chmod +x "$LX/run-gui.sh" "$LX/dyavon" "$LX/dyavon-headless"

cat > "$LX/README.txt" <<EOF
Dyavon v$VER — Linux (x86_64)

Share one keyboard/mouse between this machine and another over the LAN.
Requires an X11 session (not Wayland) on Linux.

WHAT'S HERE
  dyavon-headless   Slim, fully self-contained binary (no GUI). RECOMMENDED for a
                      dedicated server/client. No extra packages needed.
  dyavon            The same tool plus the iced control panel + system tray.
  run-gui.sh          Launches dyavon with the bundled libxdo on LD_LIBRARY_PATH.
  lib/libxdo.so.3     Bundled (only the GUI needs it).
  config.example.json Sample config.

QUICK START (headless)
  1. Copy the sample config and edit it:
       mkdir -p ~/.dyavon
       cp config.example.json ~/.dyavon/config.json
       \$EDITOR ~/.dyavon/config.json
     Set a long 'shared_secret' (IDENTICAL on both machines), the role, and on the
     client set 'server_host' to the server's LAN IP.
  2. On the machine with the keyboard/mouse:   ./dyavon-headless server
     On the other machine:                     ./dyavon-headless client

GUI
  ./run-gui.sh          (uses the bundled libxdo)
  It still needs gtk3 + the appindicator tray library from your distro:
       sudo apt install libgtk-3-0 libayatana-appindicator3-1
  (Or install libxdo3 too and just run ./dyavon directly.)

Move the mouse to the configured edge to cross to the other screen. Press the
return hotkey (default Scroll Lock, or the 'return_hotkey' combo) to come back.
EOF

tar -C "$STAGE" -czf "$DIST/dyavon-$VER-linux-x86_64.tar.gz" "dyavon-$VER-linux-x86_64"

# ---------------- Windows zip ----------------
echo "==> staging Windows zip"
WX="$STAGE/dyavon-$VER-windows-x86_64"
mkdir -p "$WX"
cp "$STAGE/dyavon.exe" "$WX/dyavon.exe"
cp config.example.json "$WX/config.example.json"

cat > "$WX/README.txt" <<EOF
Dyavon v$VER — Windows (x86_64)

Share one keyboard/mouse between this machine and another over the LAN.
dyavon.exe is self-contained (only standard Win32 DLLs).

RUN
  Double-click dyavon.exe to open the control panel (edit config, Start/Stop).
  Or from a terminal (PowerShell / cmd):
       dyavon.exe server      (this machine has the keyboard/mouse)
       dyavon.exe client      (this machine receives input)

CONFIG  %USERPROFILE%\\.dyavon\\config.json
  Copy config.example.json there and edit it. Set a long 'shared_secret' that is
  IDENTICAL on both machines; on the client set 'server_host' to the server's LAN IP.
  'return_hotkey' (e.g. ctrl+win+alt+esc) hands control back; it is matched on the
  SERVER, so set it in the server's config.

NOTES
  - SmartScreen may warn on first run (unsigned binary): More info -> Run anyway.
  - The client auto-reconnects if the server restarts ('reconnect': true).
EOF

if command -v zip >/dev/null 2>&1; then
  ( cd "$STAGE" && zip -qr "$DIST/dyavon-$VER-windows-x86_64.zip" "dyavon-$VER-windows-x86_64" )
else
  ( cd "$STAGE" && python3 -c "import shutil,sys; shutil.make_archive(sys.argv[1],'zip','.',sys.argv[2])" \
      "$DIST/dyavon-$VER-windows-x86_64" "dyavon-$VER-windows-x86_64" )
fi

# ---------------- checksums ----------------
( cd "$DIST" && sha256sum ./*.zip ./*.tar.gz > SHA256SUMS )

echo "==> done. artifacts in dist/:"
ls -lh "$DIST"
cat "$DIST/SHA256SUMS"
