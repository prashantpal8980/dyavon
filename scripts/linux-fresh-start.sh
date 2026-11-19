#!/usr/bin/env bash
# Reset this Linux machine so Dyavon can be installed as a brand-new user would: from GitHub,
# with first-run setup and pairing. Run as yourself:   scripts/linux-fresh-start.sh
#
# It stops the mouse-rs panel, removes its start-at-login entry, and RENAMES ~/.mouse_share to
# ~/.mouse_share.bak so Dyavon does not pick it up; nothing is deleted. With your sudo password
# it also removes the mouse-rs login-screen service (it would not work with Dyavon anyway).
# To undo: rename ~/.mouse_share.bak back and start mouse-rs again.
set -euo pipefail

say() { printf '  %s\n' "$*"; }
[ "$(uname -s)" = Linux ] || { echo "STOP: this is the Linux script"; exit 1; }
[ "$(id -u)" != 0 ] || { echo "STOP: run it as yourself; it uses sudo only where it must"; exit 1; }
echo "Fresh start for Dyavon on $(hostname)"

for name in mouse-rs dyavon; do
  if pgrep -u "$USER" -x "$name" >/dev/null; then
    pkill -u "$USER" -x "$name" || true
    for _ in 1 2 3 4 5; do pgrep -u "$USER" -x "$name" >/dev/null || break; sleep 1; done
    pgrep -u "$USER" -x "$name" >/dev/null && { echo "STOP: $name would not stop; nothing else changed"; exit 1; }
    say "stopped the $name panel"
  fi
done

AS="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
for f in mouse-rs.desktop mouse_share.desktop; do
  if [ -e "$AS/$f" ]; then rm -f "$AS/$f"; say "removed start-at-login entry $f"; fi
done

if [ -e "$HOME/.mouse_share" ]; then
  if [ -e "$HOME/.mouse_share.bak" ]; then
    say "STOP: ~/.mouse_share.bak already exists, so ~/.mouse_share was left in place"
  else
    mv "$HOME/.mouse_share" "$HOME/.mouse_share.bak" && say "settings kept as ~/.mouse_share.bak"
  fi
fi
if [ -e "$HOME/.dyavon" ]; then say "NOTE: ~/.dyavon exists from an earlier try; delete it for a truly fresh start"; fi

if [ -e /etc/systemd/system/mouse-rs-greeter.service ]; then
  say "removing the mouse-rs login-screen service (sudo)"
  sudo systemctl disable --now mouse-rs-greeter >/dev/null 2>&1 || true
  sudo rm -f /etc/systemd/system/mouse-rs-greeter.service /usr/local/bin/mouse-rs \
             /etc/modules-load.d/mouse-rs-uinput.conf
  sudo rm -rf /etc/mouse-rs /var/lib/mouse-rs
  sudo systemctl daemon-reload
  if systemctl is-active --quiet mouse-rs-greeter; then say "WARNING: the old login-screen service is still running"
  else say "mouse-rs login-screen service removed"; fi
fi
echo "Done. Now go to https://github.com/prashantpal8980/dyavon and install Dyavon like a new user."
