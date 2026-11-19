#!/usr/bin/env bash
# One-time switch of this Linux machine from mouse-rs to Dyavon. Run as yourself, not root:
#
#     scripts/linux-rename.sh
#
# It asks for your sudo password once, for the login-screen part.
#   1. Stops the mouse-rs panel and starts the Dyavon one. On first start Dyavon copies the
#      settings and pairings from ~/.mouse_share to ~/.dyavon and swaps the start-at-login
#      entry. If Dyavon does not stay up, mouse-rs is started again.
#   2. If login-screen sharing was installed: installs the Dyavon service from ~/.dyavon,
#      checks it runs, then removes the mouse-rs service and its files.
# It leaves ~/.mouse_share as it was. It sends no keyboard or mouse input.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="$REPO_ROOT/target/release/dyavon"
OLD="$REPO_ROOT/target/release/mouse-rs"

say() { printf '  %s\n' "$*"; }
stop() { printf 'STOP: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Linux ] || stop "this is the Linux script"
[ "$(id -u)" != 0 ] || stop "run it as yourself; it uses sudo only where it must"
[ -x "$NEW" ] || stop "no Dyavon build at $NEW (build it first)"

echo "mouse-rs -> Dyavon on $(hostname)"

# --- 1. the panel ------------------------------------------------------------------------
# By exact process name and only this user's: the login-screen copy (root) is step 2's.
if pgrep -u "$USER" -x mouse-rs >/dev/null; then
  say "stopping the mouse-rs panel (pid $(pgrep -u "$USER" -x mouse-rs | tr '\n' ' '))"
  pkill -u "$USER" -x mouse-rs || true
  for _ in 1 2 3 4 5; do pgrep -u "$USER" -x mouse-rs >/dev/null || break; sleep 1; done
  pgrep -u "$USER" -x mouse-rs >/dev/null && stop "mouse-rs would not stop; nothing else was changed"
fi
pgrep -u "$USER" -x dyavon >/dev/null && stop "Dyavon is already running; nothing to do for the panel"

setsid nohup "$NEW" >/dev/null 2>&1 < /dev/null &
sleep 5
if ! pgrep -u "$USER" -x dyavon >/dev/null; then
  [ -x "$OLD" ] && { setsid nohup "$OLD" >/dev/null 2>&1 < /dev/null & say "started mouse-rs again"; }
  stop "Dyavon did not stay running; see ~/.dyavon/dyavon.log"
fi
say "Dyavon is running (pid $(pgrep -u "$USER" -x dyavon | tr '\n' ' '))"

[ -f "$HOME/.dyavon/config.json" ] && say "settings in place: ~/.dyavon/config.json" \
  || say "WARNING: ~/.dyavon/config.json is missing"
[ -e "$HOME/.config/autostart/mouse-rs.desktop" ] && say "WARNING: the old start-at-login entry is still there"
[ -e "$HOME/.config/autostart/dyavon.desktop" ] && say "start at login: on" || say "start at login: off"

# --- 2. the login screen -----------------------------------------------------------------
if [ ! -e /etc/systemd/system/mouse-rs-greeter.service ]; then
  say "login-screen sharing was not installed; nothing more to do"
  exit 0
fi
say "moving login-screen sharing to Dyavon (sudo)"
sudo "$NEW" greeter-install "$HOME/.dyavon/config.json"
sudo systemctl daemon-reload
sudo systemctl enable dyavon-greeter >/dev/null
# The old service holds the virtual keyboard; the new one starts once it is gone.
sudo systemctl disable --now mouse-rs-greeter >/dev/null 2>&1 || true
sudo systemctl restart dyavon-greeter
sleep 3
if ! systemctl is-active --quiet dyavon-greeter; then
  say "the Dyavon login-screen service did not start; putting the mouse-rs one back"
  sudo systemctl enable --now mouse-rs-greeter >/dev/null
  stop "see: sudo journalctl -u dyavon-greeter -n 50"
fi
say "login-screen service: dyavon-greeter is running"
sudo rm -f /etc/systemd/system/mouse-rs-greeter.service /usr/local/bin/mouse-rs \
           /etc/modules-load.d/mouse-rs-uinput.conf
sudo rm -rf /etc/mouse-rs /var/lib/mouse-rs
sudo systemctl daemon-reload
say "removed the mouse-rs login-screen files"
echo "Done: this machine now runs Dyavon. ~/.mouse_share is kept; delete it after a few days."
