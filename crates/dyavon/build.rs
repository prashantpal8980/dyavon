// Makes a bare `cargo build` link on a machine without `libxdo-dev`.
//
// The Linux GUI links `-lxdo`, which needs a `libxdo.so` dev symlink that a stock Kali
// install does not have. The repo carries one at `.buildlibs/libxdo.so`, pointing at the
// runtime library. Without this script the only way to build was to remember to export
// `RUSTFLAGS=-L .xdo-shim` first, and a plain `cargo build` failed with
// "unable to find library -lxdo". Adding the directory here means the link finds the
// shim whatever the caller's environment. When `libxdo-dev` is installed the shim is
// simply unused.
/// Kept equal to the list in `src/glibc_compat.rs`.
const GLIBC_COMPAT: [&str; 6] = ["atan2f", "acosf", "asinf", "acoshf", "sinhf", "coshf"];

fn main() {
    println!("cargo:rerun-if-changed=build.rs");

    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if os == "windows" {
        windows_resources();
        return;
    }
    if os != "linux" {
        return;
    }

    // Older Linux (B47): glibc 2.43 gave six float functions new versions, so a build on
    // Kali would not start on Ubuntu 24.04 / Mint 22 (glibc 2.39). Every call is routed to
    // the long-standing version instead; see src/glibc_compat.rs.
    for f in GLIBC_COMPAT {
        println!("cargo:rustc-link-arg-bins=-Wl,--wrap={f}");
    }

    // B78: find the libxdo bundled in `lib/` next to the binary, however it is started.
    // Before, only run.sh set LD_LIBRARY_PATH, so the start-at-login entry and an installed
    // copy (which run the binary directly) did not start on a machine without libxdo3.
    println!("cargo:rustc-link-arg-bins=-Wl,-rpath,$ORIGIN/lib");

    let manifest = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    // crates/dyavon/ -> repo root. `.buildlibs` is the tracked copy, so a fresh clone builds;
    // `.xdo-shim` is the older, untracked one some checkouts still have.
    let root = manifest.join("..").join("..");
    for dir in [".buildlibs", ".xdo-shim"] {
        let shim = root.join(dir);
        if shim.join("libxdo.so").exists() {
            println!("cargo:rustc-link-search=native={}", shim.display());
            return;
        }
    }
}

/// The icon Explorer, the taskbar and shortcuts show, and the name and version in the
/// exe's Properties. Compiled with the MinGW `windres` when it is there; a build without it
/// still works, it just has the default program icon.
fn windows_resources() {
    let manifest = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let icon = manifest.join("../../assets/icon/dyavon.ico");
    println!("cargo:rerun-if-changed={}", icon.display());
    println!("cargo:rerun-if-env-changed=DYAVON_VERSION");
    let version = std::env::var("DYAVON_VERSION").unwrap_or_else(|_| std::env::var("CARGO_PKG_VERSION").unwrap());
    let mut parts: Vec<u16> = version.split(|c: char| !c.is_ascii_digit()).filter_map(|p| p.parse().ok()).take(3).collect();
    parts.resize(4, 0);
    let commas = parts.iter().map(|p| p.to_string()).collect::<Vec<_>>().join(",");
    let out = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap());
    let rc = out.join("dyavon.rc");
    let icon_path = icon.display().to_string().replace('\\', "/");
    std::fs::write(
        &rc,
        format!(
            r#"1 ICON "{icon_path}"
1 VERSIONINFO
FILEVERSION {commas}
PRODUCTVERSION {commas}
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904B0"
    BEGIN
      VALUE "CompanyName", "Dyavon contributors"
      VALUE "FileDescription", "Dyavon - one mouse and keyboard for all your computers"
      VALUE "FileVersion", "{version}"
      VALUE "InternalName", "dyavon"
      VALUE "LegalCopyright", "Copyright 2026 Prashant Pal. Apache License 2.0"
      VALUE "OriginalFilename", "dyavon.exe"
      VALUE "ProductName", "Dyavon"
      VALUE "ProductVersion", "{version}"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x409, 1200
  END
END
"#
        ),
    )
    .unwrap();
    let obj = out.join("dyavon-res.o");
    let windres = ["x86_64-w64-mingw32-windres", "windres"]
        .into_iter()
        .find(|w| std::process::Command::new(w).arg("--version").output().is_ok_and(|o| o.status.success()));
    let Some(windres) = windres else {
        println!("cargo:warning=windres not found: dyavon.exe is built without its icon");
        return;
    };
    let ok = std::process::Command::new(windres)
        .args(["-O", "coff", "-i"])
        .arg(&rc)
        .arg("-o")
        .arg(&obj)
        .status()
        .is_ok_and(|s| s.success());
    if ok {
        println!("cargo:rustc-link-arg-bins={}", obj.display());
    } else {
        println!("cargo:warning=windres failed: dyavon.exe is built without its icon");
    }
}
