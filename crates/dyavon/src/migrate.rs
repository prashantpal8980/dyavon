//! One-time move from the pre-rename install (mouse-rs, `~/.mouse_share`) to Dyavon
//! (`~/.dyavon`), so a machine set up before the rename keeps its settings and pairings.
//!
//! Copies, never moves: the old folder stays as it was, so going back to the old build
//! still works. Runs at start, before anything reads the config. Does nothing once
//! `~/.dyavon/config.json` exists.

use std::path::{Path, PathBuf};

const LEGACY_DIR: &str = ".mouse_share";

/// What `run` did, for the log.
#[derive(Debug, PartialEq, Eq)]
pub enum Outcome {
    /// Nothing old to bring over, or already done.
    Nothing,
    /// Settings copied from this folder.
    Copied(PathBuf),
}

fn home() -> Option<PathBuf> {
    std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")).map(PathBuf::from)
}

/// Bring the old settings over if this machine has them and Dyavon has none yet.
pub fn run() -> Outcome {
    let Some(home) = home() else { return Outcome::Nothing };
    let new_cfg = dyavon_core::Config::default_path();
    match copy_legacy(&home.join(LEGACY_DIR), &new_cfg) {
        Ok(o) => o,
        Err(e) => {
            // The old folder is untouched, so the next start simply tries again.
            tracing::warn!("could not bring the mouse-rs settings over to Dyavon: {e}");
            Outcome::Nothing
        }
    }
}

fn copy_legacy(old_dir: &Path, new_cfg: &Path) -> std::io::Result<Outcome> {
    let old_cfg = old_dir.join("config.json");
    if new_cfg.exists() || !old_cfg.is_file() {
        return Ok(Outcome::Nothing);
    }
    let new_dir = new_cfg.parent().expect("the config path has a folder");
    std::fs::create_dir_all(new_dir)?;
    // Profiles first, the config last: a copy that stops part-way leaves no config.json,
    // so the next start tries again instead of running on half the settings.
    let profiles = old_dir.join("profiles");
    if profiles.is_dir() {
        let to = new_dir.join("profiles");
        std::fs::create_dir_all(&to)?;
        for entry in std::fs::read_dir(&profiles)? {
            let entry = entry?;
            if entry.file_type()?.is_file() {
                std::fs::copy(entry.path(), to.join(entry.file_name()))?;
            }
        }
    }
    // Other small files beside the config (the clipboard history). The cache (received
    // files) and other folders are not copied: the cache can be large and is rebuilt. The
    // log starts fresh under the new name.
    for entry in std::fs::read_dir(old_dir)? {
        let entry = entry?;
        let name = entry.file_name();
        let n = name.to_string_lossy();
        if !entry.file_type()?.is_file() || n == "config.json" || n.starts_with("mouse-rs.log") {
            continue;
        }
        std::fs::copy(entry.path(), new_dir.join(&name))?;
    }
    let text = std::fs::read_to_string(&old_cfg)?;
    let text = point_cache_at_new_default(&text, old_dir);
    let tmp = new_cfg.with_extension("json.part");
    std::fs::write(&tmp, text)?;
    // The config holds the pairing keys: owner-only, as `Config::save` keeps it.
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o600))?;
    }
    std::fs::rename(&tmp, new_cfg)?;
    Ok(Outcome::Copied(old_dir.to_path_buf()))
}

/// A `cache_dir` that names the old default folder is cleared, so the new default
/// (`~/.dyavon/cache`) applies. A folder the user chose stays as it was.
fn point_cache_at_new_default(text: &str, old_dir: &Path) -> String {
    let Ok(mut v) = serde_json::from_str::<serde_json::Value>(text) else {
        return text.to_string();
    };
    let old_cache = old_dir.join("cache");
    let is_old_default = v
        .get("cache_dir")
        .and_then(|c| c.as_str())
        .is_some_and(|c| !c.is_empty() && Path::new(c) == old_cache);
    if !is_old_default {
        return text.to_string();
    }
    v["cache_dir"] = serde_json::Value::String(String::new());
    serde_json::to_string_pretty(&v).unwrap_or_else(|_| text.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("dyavon-migrate-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn old_settings_and_pairings_are_copied_once_and_the_old_folder_is_kept() {
        let home = scratch("copy");
        let old = home.join(".mouse_share");
        std::fs::create_dir_all(old.join("profiles")).unwrap();
        let cfg = format!(
            r#"{{"name":"desk","paired":[{{"device":"abc","key":"k"}}],"cache_dir":"{}"}}"#,
            old.join("cache").display()
        );
        std::fs::write(old.join("config.json"), &cfg).unwrap();
        std::fs::write(old.join("profiles/travel.json"), "{}").unwrap();
        std::fs::write(old.join("history.json"), "[]").unwrap();
        std::fs::write(old.join("mouse-rs.log"), "old log").unwrap();
        std::fs::create_dir_all(old.join("cache/big")).unwrap();
        let new_cfg = home.join(".dyavon/config.json");

        assert_eq!(copy_legacy(&old, &new_cfg).unwrap(), Outcome::Copied(old.clone()));
        let got: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&new_cfg).unwrap()).unwrap();
        assert_eq!(got["name"], "desk");
        assert_eq!(got["paired"][0]["key"], "k");
        assert_eq!(got["cache_dir"], "", "the old default cache folder points at the new default");
        assert!(home.join(".dyavon/profiles/travel.json").is_file());
        assert!(home.join(".dyavon/history.json").is_file(), "the clipboard history comes along");
        assert!(!home.join(".dyavon/mouse-rs.log").exists(), "the old log does not");
        assert!(!home.join(".dyavon/cache").exists(), "nor does the cache");
        assert!(old.join("config.json").is_file(), "the old folder is left as it was");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(&new_cfg).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode, 0o600);
        }

        // A second start changes nothing, even if the old settings changed meanwhile.
        std::fs::write(old.join("config.json"), r#"{"name":"other"}"#).unwrap();
        assert_eq!(copy_legacy(&old, &new_cfg).unwrap(), Outcome::Nothing);
        assert!(std::fs::read_to_string(&new_cfg).unwrap().contains("desk"));
        let _ = std::fs::remove_dir_all(&home);
    }

    #[test]
    fn a_cache_folder_the_user_chose_is_kept_and_no_old_folder_means_nothing() {
        let home = scratch("keep");
        let old = home.join(".mouse_share");
        std::fs::create_dir_all(&old).unwrap();
        std::fs::write(old.join("config.json"), r#"{"cache_dir":"/data/received"}"#).unwrap();
        let new_cfg = home.join(".dyavon/config.json");
        copy_legacy(&old, &new_cfg).unwrap();
        assert!(std::fs::read_to_string(&new_cfg).unwrap().contains("/data/received"));

        let empty = scratch("none");
        assert_eq!(copy_legacy(&empty.join(".mouse_share"), &empty.join(".dyavon/config.json")).unwrap(), Outcome::Nothing);
        let _ = std::fs::remove_dir_all(&home);
        let _ = std::fs::remove_dir_all(&empty);
    }
}
