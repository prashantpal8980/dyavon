//! The Dyavon icon, built into the binary so every copy carries it: the window and tray
//! use the raw pixels, and the Linux installer writes the PNG out for the app menu and
//! the desktop launcher. Windows takes its icon from the exe's resources (build.rs). Sources and the other concepts are in `assets/icon/`.

/// 64x64 and 32x32, 8-bit RGBA, rows top to bottom.
pub const ICON_64_RGBA: &[u8] = include_bytes!("../../../assets/icon/dyavon-64.rgba");
pub const ICON_32_RGBA: &[u8] = include_bytes!("../../../assets/icon/dyavon-32.rgba");

/// 256x256 PNG, written next to the installed program for the app-menu entry and the
/// desktop launcher (R50).
#[cfg(not(windows))]
pub const ICON_256_PNG: &[u8] = include_bytes!("../../../assets/icon/dyavon-256.png");

#[cfg(test)]
mod tests {
    #[test]
    fn the_raw_icons_are_whole_squares() {
        assert_eq!(super::ICON_64_RGBA.len(), 64 * 64 * 4);
        assert_eq!(super::ICON_32_RGBA.len(), 32 * 32 * 4);
    }
}
