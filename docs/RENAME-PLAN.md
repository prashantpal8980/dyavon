# Rename record: mouse-rs → Dyavon

*Started 19 Nov 2026. The requirement is R48 in `UI-REQUIREMENTS.md`.*

The owner is the only user (GitHub showed 1–2 downloads per 1.0.0 file), so this is a clean
rename, wire labels included. **Dyavon builds and mouse-rs builds do not connect to each
other: update both computers together.**

## Done (19 Nov)

- Crates `dyavon`, `dyavon-core`, `-engine`, `-input`, `-clipboard`; binary `dyavon` / `dyavon.exe`.
- Every name the user sees says Dyavon; files, commands and folders say `dyavon`.
- Settings folder `~/.dyavon`, log `dyavon.log`, env vars `DYAVON_*`, release signing key folder `~/.config/dyavon-release`.
- Handshake, pairing, PIN and log-upload labels and the TLS name now say `dyavon`. The pairing keys are unchanged, so existing pairings keep working once both sides run Dyavon.
- Firewall rule and admin task named `Dyavon`, `Dyavon (elevated)`, in `Program Files\dyavon`. The login-screen service is `dyavon-greeter`, files in `/etc/dyavon`, `/usr/local/bin/dyavon`.
- Update check and download page point at `github.com/prashantpal8980/dyavon` releases.
- `migrate.rs`: on first start, copies `~/.mouse_share` (config, pairings, profiles, clipboard history; not the cache or logs) to `~/.dyavon`, and swaps the start-at-login entry (Linux `.desktop`, Windows Run value). Tested on a sandboxed copy of the real Kali settings.
- One-time helpers: `scripts/linux-rename.sh` (panel + login-screen service, needs sudo) and `scripts/windows-rename.ps1` (served as `rename.txt`: exe, firewall, admin task, start, checks, report).
- README (name, slogan, pronunciation, meaning), CHANGELOG (Unreleased), NOTICE, current docs and test prompts. History (KNOWN-ISSUES, resume notes, postmortems, mockups) is left as written.

## Still to do

1. **Owner:** run the two helpers (see below) and check both machines.
2. **GitHub (owner's go-ahead needed):** rename the repo `mouse-rs` → `dyavon`, update the git remote, and decide what happens to the `v1.0.0` mouse-rs release.
3. Retake the user-guide screenshots (panel header and GitHub pages show the old name).
4. Register **dyavon.com**; search "Dyavon" on tmsearch.uspto.gov.

## The switch, per machine

- **Kali:** `scripts/linux-rename.sh`
- **Laptop**, in an elevated PowerShell, after `scripts/serve-windows.sh` on Kali: `irm http://192.168.137.2:8000/rename.txt | iex`
