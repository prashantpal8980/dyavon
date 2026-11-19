//! Installing Dyavon from the download, and removing it again (R50).
//!
//! The downloaded program installs itself, so there is one file to download and no separate
//! installer to build or trust. Nothing here needs administrator or root rights. Removing
//! asks for them only for the parts that were set up with them: the Windows firewall rules
//! and administrator login task, and the Linux login-screen service.
//!
//! * **Windows:** `%LOCALAPPDATA%\Programs\Dyavon`, Desktop and Start-menu shortcuts, and an
//!   entry in Settings › Apps whose Uninstall opens this program's removal screen.
//! * **Linux:** `~/.local/share/dyavon` (with the bundled `lib/`), an app-menu entry, and a
//!   desktop launcher.

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

/// What the install screen lets the user choose.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Options {
    pub desktop_shortcut: bool,
    pub menu_entry: bool,
    pub start_at_login: bool,
}

impl Default for Options {
    fn default() -> Self {
        Options { desktop_shortcut: true, menu_entry: true, start_at_login: false }
    }
}

/// The program file's name in the install folder.
pub const EXE_NAME: &str = if cfg!(windows) { "dyavon.exe" } else { "dyavon" };

/// The summary shown before installing and on the About page. It restates the licence's own
/// terms (Apache-2.0 sections 7 and 8) in plain words; the licence itself is what applies.
pub const LEGAL_SUMMARY: &str = "Dyavon is free, open-source software, released under the Apache License, Version 2.0.\n\n\
It is provided \"AS IS\", without warranties or conditions of any kind, either express or implied. \
You use it at your own risk. To the extent allowed by law, the authors and contributors are not \
liable for any damage, loss of data or other harm that comes from using it, or from not being \
able to use it.\n\n\
Dyavon lets a paired computer control this one with its keyboard and mouse, and exchange clipboard \
contents and files. Only pair computers you trust.\n\n\
Dyavon sends nothing about you anywhere. It checks GitHub for a new version when it starts \
(you can turn this off), and talks only to the computers you pair it with.";

/// Where the full licence can be read.
pub const LICENSE_URL: &str = "https://github.com/prashantpal8980/dyavon/blob/master/LICENSE";

#[cfg(not(windows))]
fn home() -> Option<PathBuf> {
    std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).map(PathBuf::from)
}

/// Where Dyavon installs for this user.
pub fn install_dir() -> Option<PathBuf> {
    #[cfg(windows)]
    {
        std::env::var_os("LOCALAPPDATA").map(|d| PathBuf::from(d).join("Programs").join("Dyavon"))
    }
    #[cfg(not(windows))]
    {
        Some(data_home()?.join("dyavon"))
    }
}

#[cfg(not(windows))]
fn data_home() -> Option<PathBuf> {
    match std::env::var_os("XDG_DATA_HOME") {
        Some(v) if !v.is_empty() => Some(PathBuf::from(v)),
        _ => Some(home()?.join(".local").join("share")),
    }
}

fn same_dir(a: &Path, b: &Path) -> bool {
    match (a.canonicalize(), b.canonicalize()) {
        (Ok(a), Ok(b)) => a == b,
        _ => a == b,
    }
}

/// This copy is the installed one.
pub fn is_installed_copy() -> bool {
    let (Ok(exe), Some(dir)) = (std::env::current_exe(), install_dir()) else { return false };
    exe.parent().is_some_and(|p| same_dir(p, &dir))
}

/// A build being run from its cargo `target/` folder: a developer's copy, which is never
/// offered an install.
pub fn is_dev_build() -> bool {
    std::env::current_exe()
        .map(|p| p.components().any(|c| c.as_os_str() == "target"))
        .unwrap_or(false)
}

/// Whether to show the install screen at start.
pub fn should_offer(declined: bool) -> bool {
    !declined && !is_installed_copy() && !is_dev_build() && install_dir().is_some()
}

/// Copy this program into the install folder and set up what `opts` asks for. Returns the
/// installed program, which the caller starts before quitting this copy.
pub fn install(opts: Options) -> Result<PathBuf> {
    let src = std::env::current_exe().context("finding this program")?;
    let dir = install_dir().context("no home folder to install into")?;
    std::fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;
    // A copy already installed and running would hold the file on Windows.
    stop_other_copies();
    let exe = dir.join(EXE_NAME);
    copy_over(&src, &exe)?;
    copy_companions(&src, &dir)?;
    platform::install(&exe, &dir, opts)?;
    if opts.start_at_login {
        crate::autostart::enable_for(&exe).context("turning on start at login")?;
    }
    tracing::info!(exe = %exe.display(), ?opts, "installed");
    Ok(exe)
}

/// Write `to` from `from` through a temporary file, so a failed copy leaves no half file.
fn copy_over(from: &Path, to: &Path) -> Result<()> {
    if same_dir(from, to) {
        return Ok(());
    }
    let tmp = to.with_extension("new");
    std::fs::copy(from, &tmp).with_context(|| format!("copying Dyavon to {}", tmp.display()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o755))?;
    }
    std::fs::rename(&tmp, to).with_context(|| format!("putting Dyavon at {} (is it still running?)", to.display()))?;
    Ok(())
}

/// The licence files from the download, and on Linux the bundled `lib/`.
fn copy_companions(src: &Path, dir: &Path) -> Result<()> {
    let Some(from) = src.parent() else { return Ok(()) };
    if same_dir(from, dir) {
        return Ok(());
    }
    for name in ["LICENSE", "NOTICE", "THIRD-PARTY-LICENSES.txt", "README.txt"] {
        let f = from.join(name);
        if f.is_file() {
            std::fs::copy(&f, dir.join(name)).with_context(|| format!("copying {name}"))?;
        }
    }
    let lib = from.join("lib");
    if lib.is_dir() {
        let to = dir.join("lib");
        std::fs::create_dir_all(&to)?;
        for entry in std::fs::read_dir(&lib)? {
            let entry = entry?;
            if entry.file_type()?.is_file() {
                std::fs::copy(entry.path(), to.join(entry.file_name()))?;
            }
        }
    }
    Ok(())
}

/// Start the installed copy, detached, so this one can quit.
pub fn start(exe: &Path) -> Result<()> {
    let mut cmd = std::process::Command::new(exe);
    cmd.current_dir(exe.parent().unwrap_or(Path::new(".")))
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(platform::DETACHED_PROCESS);
    }
    cmd.spawn().with_context(|| format!("starting {}", exe.display()))?;
    Ok(())
}

/// One line of the removal summary.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Done {
    pub ok: bool,
    pub what: String,
}

fn done(ok: bool, what: impl Into<String>) -> Done {
    Done { ok, what: what.into() }
}

/// Remove Dyavon from this computer. Every step is attempted, whatever happened before it,
/// and reported. On Windows the files this program still holds open (itself, its log) are
/// deleted by a short helper that waits for this process to exit.
pub fn uninstall(keep_settings: bool, cache_dir: &str) -> Vec<Done> {
    let mut out = Vec::new();

    match crate::autostart::disable() {
        Ok(()) => out.push(done(true, "Start at login turned off")),
        Err(e) => out.push(done(false, format!("Start at login: {e:#}"))),
    }
    platform::uninstall_privileged(&mut out);
    platform::remove_shortcuts(&mut out);

    stop_other_copies();
    let settings_dir = dyavon_core::Config::default_path().parent().map(Path::to_path_buf);
    let default_cache = settings_dir.as_ref().map(|d| d.join("cache"));
    let mut later: Vec<PathBuf> = Vec::new();

    // Received files and the clipboard cache. A cache folder the user chose may hold other
    // things, so it is named instead of deleted.
    let custom = (!cache_dir.trim().is_empty()).then(|| PathBuf::from(cache_dir.trim()));
    match (&custom, &default_cache) {
        (Some(c), Some(d)) if !same_dir(c, d) => {
            out.push(done(true, format!("Left in place, because you chose it: the received-files folder {}", c.display())))
        }
        _ => {}
    }
    if let Some(d) = &default_cache {
        if d.exists() {
            match std::fs::remove_dir_all(d) {
                Ok(()) => out.push(done(true, "Received files and the clipboard cache deleted")),
                Err(_) if cfg!(windows) => later.push(d.clone()),
                Err(e) => out.push(done(false, format!("Could not delete {}: {e}", d.display()))),
            }
        }
    }

    if let Some(d) = settings_dir.filter(|d| d.exists()) {
        if keep_settings {
            out.push(done(true, format!("Settings and pairings kept in {}", d.display())));
        } else if cfg!(windows) {
            // The log in it is open in this process.
            later.push(d.clone());
            out.push(done(true, format!("Settings and pairings: deleted when Dyavon closes ({})", d.display())));
        } else {
            match std::fs::remove_dir_all(&d) {
                Ok(()) => out.push(done(true, "Settings and pairings deleted")),
                Err(e) => out.push(done(false, format!("Could not delete {}: {e}", d.display()))),
            }
        }
    }

    // The program.
    let running_installed = is_installed_copy();
    if let Some(dir) = install_dir().filter(|d| d.exists()) {
        if running_installed && cfg!(windows) {
            later.push(dir.clone());
            out.push(done(true, "The program: deleted when Dyavon closes"));
        } else {
            match std::fs::remove_dir_all(&dir) {
                Ok(()) => out.push(done(true, format!("The program deleted ({})", dir.display()))),
                Err(_) if cfg!(windows) => {
                    later.push(dir.clone());
                    out.push(done(true, "The program: deleted when Dyavon closes"));
                }
                Err(e) => out.push(done(false, format!("Could not delete {}: {e}", dir.display()))),
            }
        }
    }
    if !running_installed {
        if let Some(folder) = std::env::current_exe().ok().and_then(|p| p.parent().map(Path::to_path_buf)) {
            out.push(done(
                true,
                format!("This copy was run without installing. Delete its folder yourself when Dyavon has closed: {}", folder.display()),
            ));
        }
    }
    if !later.is_empty() {
        platform::delete_after_exit(&later, &mut out);
    }
    tracing::info!(keep_settings, steps = ?out, "removed Dyavon");
    out
}

/// End any other Dyavon panel this user is running, so its files can be replaced or
/// deleted. The login-screen service (Linux, root) and the administrator copy (Windows)
/// are not this user's and are handled by their own removal.
fn stop_other_copies() {
    platform::stop_other_copies();
}

// ------------------------------------------------- Windows scripts (built on every OS)
//
// Built outside the Windows module so the Linux tests can run them through PowerShell's
// parser: a Windows-only test would compile here and never run.

#[cfg_attr(not(windows), allow(dead_code))]
const WIN_UNINSTALL_KEY: &str = r"HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Dyavon";

/// A PowerShell single-quoted string.
#[cfg_attr(not(windows), allow(dead_code))]
pub(crate) fn q(s: &str) -> String {
    format!("'{}'", s.replace('\'', "''"))
}

#[cfg_attr(not(windows), allow(dead_code))]
pub(crate) fn install_script(exe: &Path, dir: &Path, opts: Options, version: &str, size_kb: u64) -> String {
    let (exe, dir) = (q(&exe.display().to_string()), q(&dir.display().to_string()));
    let mut s = format!(
        "$ErrorActionPreference='Stop'\n\
         $exe={exe}; $dir={dir}\n\
         function Lnk($path) {{ $l=(New-Object -ComObject WScript.Shell).CreateShortcut($path); $l.TargetPath=$exe; \
         $l.WorkingDirectory=$dir; $l.IconLocation=\"$exe,0\"; $l.Description='One mouse and keyboard for all your computers'; $l.Save() }}\n"
    );
    if opts.desktop_shortcut {
        s += "Lnk (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Dyavon.lnk')\n";
    }
    if opts.menu_entry {
        s += "Lnk (Join-Path ([Environment]::GetFolderPath('Programs')) 'Dyavon.lnk')\n";
    }
    s += &format!(
        "$k={key}\n\
         New-Item -Path $k -Force | Out-Null\n\
         Set-ItemProperty $k DisplayName 'Dyavon'\n\
         Set-ItemProperty $k DisplayVersion {ver}\n\
         Set-ItemProperty $k Publisher 'Dyavon contributors'\n\
         Set-ItemProperty $k DisplayIcon \"$exe,0\"\n\
         Set-ItemProperty $k InstallLocation $dir\n\
         Set-ItemProperty $k UninstallString ('\"' + $exe + '\" uninstall')\n\
         Set-ItemProperty $k URLInfoAbout 'https://github.com/prashantpal8980/dyavon'\n\
         Set-ItemProperty $k HelpLink 'https://prashantpal8980.github.io/dyavon/user-guide/'\n\
         New-ItemProperty $k NoModify -Value 1 -PropertyType DWord -Force | Out-Null\n\
         New-ItemProperty $k NoRepair -Value 1 -PropertyType DWord -Force | Out-Null\n\
         New-ItemProperty $k EstimatedSize -Value {size_kb} -PropertyType DWord -Force | Out-Null\n",
        key = q(WIN_UNINSTALL_KEY),
        ver = q(version),
    );
    s
}

#[cfg_attr(not(windows), allow(dead_code))]
pub(crate) fn remove_shortcuts_script() -> String {
    format!(
        "foreach ($f in @('Desktop','Programs')) {{ $p=Join-Path ([Environment]::GetFolderPath($f)) 'Dyavon.lnk'; \
         if (Test-Path $p) {{ Remove-Item $p -Force }} }}\n\
         if (Test-Path {key}) {{ Remove-Item {key} -Recurse -Force }}",
        key = q(WIN_UNINSTALL_KEY)
    )
}

// ------------------------------------------------------------------------------ Linux

#[cfg(not(windows))]
mod platform {
    use super::*;

    const ENTRY_FILE: &str = "dyavon.desktop";

    fn desktop_dir() -> Option<PathBuf> {
        let asked = std::process::Command::new("xdg-user-dir")
            .arg("DESKTOP")
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| PathBuf::from(String::from_utf8_lossy(&o.stdout).trim()))
            .filter(|p| p.is_absolute() && p.is_dir());
        asked.or_else(|| home().map(|h| h.join("Desktop")).filter(|p| p.is_dir()))
    }

    fn menu_file() -> Option<PathBuf> {
        Some(data_home()?.join("applications").join(ENTRY_FILE))
    }

    pub(super) fn entry_text(exe: &Path, icon: &Path) -> String {
        format!(
            "[Desktop Entry]\n\
             Type=Application\n\
             Name=Dyavon\n\
             GenericName=Mouse and keyboard sharing\n\
             Comment=One mouse and keyboard for all your computers\n\
             Exec=\"{}\"\n\
             Icon={}\n\
             Terminal=false\n\
             Categories=Utility;Network;\n\
             Keywords=mouse;keyboard;kvm;share;clipboard;\n\
             StartupWMClass=dyavon\n",
            exe.display(),
            icon.display()
        )
    }

    pub(super) fn install(exe: &Path, dir: &Path, opts: Options) -> Result<()> {
        let icon = dir.join("dyavon.png");
        std::fs::write(&icon, crate::brand::ICON_256_PNG).context("writing the icon")?;
        let text = entry_text(exe, &icon);
        if opts.menu_entry {
            let f = menu_file().context("no app-menu folder")?;
            std::fs::create_dir_all(f.parent().unwrap())?;
            std::fs::write(&f, &text).with_context(|| format!("writing {}", f.display()))?;
        }
        if opts.desktop_shortcut {
            if let Some(d) = desktop_dir() {
                let f = d.join(ENTRY_FILE);
                std::fs::write(&f, &text).with_context(|| format!("writing {}", f.display()))?;
                use std::os::unix::fs::PermissionsExt;
                std::fs::set_permissions(&f, std::fs::Permissions::from_mode(0o755))?;
                // GNOME, Xfce and others only run a desktop launcher they were told to trust.
                let _ = std::process::Command::new("gio")
                    .args(["set", &f.to_string_lossy(), "metadata::trusted", "true"])
                    .stderr(std::process::Stdio::null())
                    .status();
            }
        }
        Ok(())
    }

    pub(super) fn remove_shortcuts(out: &mut Vec<Done>) {
        let mut removed = 0;
        for f in [menu_file(), desktop_dir().map(|d| d.join(ENTRY_FILE))].into_iter().flatten() {
            if f.is_file() && std::fs::remove_file(&f).is_ok() {
                removed += 1;
            }
        }
        if removed > 0 {
            out.push(done(true, "App-menu entry and desktop launcher removed"));
        }
    }

    pub(super) fn uninstall_privileged(out: &mut Vec<Done>) {
        #[cfg(target_os = "linux")]
        if crate::greeter::state().installed {
            match crate::greeter::set_enabled(false) {
                Ok(()) => out.push(done(true, "Login-screen sharing removed")),
                Err(e) => out.push(done(false, format!("Login-screen sharing is still installed ({e:#}). Remove it with: sudo dyavon greeter-uninstall"))),
            }
        }
        let _ = out;
    }

    pub(super) fn stop_other_copies() {
        let me = std::process::id();
        let uid = std::fs::read_to_string("/proc/self/status").ok().and_then(|s| status_uid(&s));
        let Ok(procs) = std::fs::read_dir("/proc") else { return };
        for p in procs.flatten() {
            let Ok(pid) = p.file_name().to_string_lossy().parse::<u32>() else { continue };
            if pid == me {
                continue;
            }
            let comm = std::fs::read_to_string(p.path().join("comm")).unwrap_or_default();
            let theirs = std::fs::read_to_string(p.path().join("status")).ok().and_then(|s| status_uid(&s));
            if comm.trim() == "dyavon" && theirs.is_some() && theirs == uid {
                let _ = std::process::Command::new("kill").arg(pid.to_string()).status();
            }
        }
    }

    fn status_uid(status: &str) -> Option<u32> {
        status.lines().find_map(|l| l.strip_prefix("Uid:")).and_then(|r| r.split_whitespace().next()?.parse().ok())
    }

    pub(super) fn delete_after_exit(dirs: &[PathBuf], out: &mut Vec<Done>) {
        for d in dirs {
            if std::fs::remove_dir_all(d).is_err() {
                out.push(done(false, format!("Could not delete {}", d.display())));
            }
        }
    }
}

// ---------------------------------------------------------------------------- Windows

#[cfg(windows)]
mod platform {
    use super::*;
    use std::os::windows::process::CommandExt;
    use super::q;

    fn powershell(script: &str) -> Result<()> {
        let out = std::process::Command::new("powershell.exe")
            .args(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script])
            .creation_flags(CREATE_NO_WINDOW)
            .output()
            .context("running PowerShell")?;
        if !out.status.success() {
            anyhow::bail!("{}", String::from_utf8_lossy(&out.stderr).trim());
        }
        Ok(())
    }

    pub(super) const DETACHED_PROCESS: u32 = 0x0000_0008;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    pub(super) fn install(exe: &Path, dir: &Path, opts: Options) -> Result<()> {
        let size_kb = std::fs::metadata(exe).map(|m| m.len() / 1024).unwrap_or(0);
        powershell(&super::install_script(exe, dir, opts, crate::update::VERSION, size_kb))
            .context("creating the shortcuts and the Settings › Apps entry")
    }

    pub(super) fn remove_shortcuts(out: &mut Vec<Done>) {
        match powershell(&super::remove_shortcuts_script()) {
            Ok(()) => out.push(done(true, "Shortcuts and the Settings › Apps entry removed")),
            Err(e) => out.push(done(false, format!("Shortcuts and the Apps entry: {e:#}"))),
        }
    }

    pub(super) fn uninstall_privileged(out: &mut Vec<Done>) {
        let needed = crate::autostart::firewall_rule_exists() || crate::autostart::elevated_is_enabled();
        if !needed {
            return;
        }
        match crate::autostart::remove_elevated_via_prompt() {
            Ok(true) => out.push(done(true, "Firewall rules and the administrator login task removed")),
            Ok(false) => out.push(done(
                false,
                "Windows did not give permission, so the Dyavon firewall rules (and the administrator login task, if it was on) are still there",
            )),
            Err(e) => out.push(done(false, format!("Firewall rules: {e:#}"))),
        }
    }

    pub(super) fn stop_other_copies() {
        let script = format!(
            "Get-Process dyavon -ErrorAction SilentlyContinue | Where-Object {{ $_.Id -ne {} }} | Stop-Process -Force -ErrorAction SilentlyContinue",
            std::process::id()
        );
        let _ = powershell(&script);
    }

    pub(super) fn delete_after_exit(dirs: &[PathBuf], out: &mut Vec<Done>) {
        let list = dirs.iter().map(|d| q(&d.display().to_string())).collect::<Vec<_>>().join(",");
        let script = format!(
            "Wait-Process -Id {} -Timeout 600 -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 700; \
             foreach ($d in @({list})) {{ Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }}",
            std::process::id()
        );
        let spawned = std::process::Command::new("powershell.exe")
            .args(["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-Command", &script])
            .creation_flags(CREATE_NO_WINDOW | DETACHED_PROCESS)
            .spawn();
        if let Err(e) = spawned {
            out.push(done(false, format!("Could not arrange to delete the remaining files ({e}); delete them by hand")));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_legal_summary_says_as_is_and_not_liable() {
        assert!(LEGAL_SUMMARY.contains("Apache License, Version 2.0"));
        assert!(LEGAL_SUMMARY.contains("\"AS IS\""));
        assert!(LEGAL_SUMMARY.contains("not liable"));
    }

    #[test]
    fn a_build_in_target_is_never_offered_an_install() {
        // The test binary itself lives under target/.
        assert!(is_dev_build());
        assert!(!should_offer(false));
    }

    /// The Windows scripts must at least parse. Runs where `pwsh` is installed.
    #[test]
    fn the_windows_scripts_parse_in_powershell() {
        let Ok(out) = std::process::Command::new("pwsh").arg("-v").output() else { return };
        if !out.status.success() {
            return;
        }
        let exe = Path::new(r"C:\Users\O'Brien\AppData\Local\Programs\Dyavon\dyavon.exe");
        let dir = Path::new(r"C:\Users\O'Brien\AppData\Local\Programs\Dyavon");
        let all = Options { desktop_shortcut: true, menu_entry: true, start_at_login: true };
        for (name, script) in [
            ("install", install_script(exe, dir, all, "1.0.0", 12345)),
            ("remove", remove_shortcuts_script()),
        ] {
            let check = format!(
                "$e=$null; [System.Management.Automation.Language.Parser]::ParseInput({}, [ref]$null, [ref]$e) | Out-Null; if ($e) {{ $e | % {{ $_.ToString() }}; exit 1 }}",
                q(&script)
            );
            let out = std::process::Command::new("pwsh").args(["-NoProfile", "-Command", &check]).output().unwrap();
            assert!(out.status.success(), "{name} script does not parse:\n{}\n{script}", String::from_utf8_lossy(&out.stdout));
        }
        // A quote in the user's name is doubled, not left to end the string.
        assert!(install_script(exe, dir, all, "1.0.0", 1).contains("O''Brien"));
    }

    #[cfg(not(windows))]
    #[test]
    fn the_menu_entry_quotes_the_path_and_names_the_icon() {
        let t = platform::entry_text(Path::new("/home/a b/.local/share/dyavon/dyavon"), Path::new("/x/dyavon.png"));
        assert!(t.contains("Exec=\"/home/a b/.local/share/dyavon/dyavon\"\n"));
        assert!(t.contains("Icon=/x/dyavon.png\n"));
        assert!(t.starts_with("[Desktop Entry]\nType=Application\nName=Dyavon\n"));
    }
}
