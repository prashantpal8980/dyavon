//! The Dyavon icon ("H · Crossing", R51), built into the binary so every copy carries it.
//! There is one set per colour theme and the icon follows the theme: the window and tray
//! use the raw pixels, and the installer writes the theme's PNG (Linux app menu and
//! desktop launcher) or a .ico made from its PNGs (Windows shortcuts and Apps entry).
//! The exe's own icon is always Amber (build.rs). Sources: `assets/icon/`, rebuilt by
//! `scripts/make-icons.sh`.

/// One theme's icon.
pub struct Icon {
    /// 64x64 and 32x32, 8-bit RGBA, rows top to bottom.
    pub rgba64: &'static [u8],
    pub rgba32: &'static [u8],
    /// PNGs at 16, 32, 48 and 256 px, for the .ico.
    pub pngs: [(u32, &'static [u8]); 4],
}

impl Icon {
    /// The 256 px PNG.
    pub fn png256(&self) -> &'static [u8] {
        self.pngs[3].1
    }
}

macro_rules! icon {
    ($t:literal) => {
        Icon {
            rgba64: include_bytes!(concat!("../../../assets/icon/themes/", $t, "/dyavon-64.rgba")),
            rgba32: include_bytes!(concat!("../../../assets/icon/themes/", $t, "/dyavon-32.rgba")),
            pngs: [
                (16, include_bytes!(concat!("../../../assets/icon/themes/", $t, "/dyavon-16.png"))),
                (32, include_bytes!(concat!("../../../assets/icon/themes/", $t, "/dyavon-32.png"))),
                (48, include_bytes!(concat!("../../../assets/icon/themes/", $t, "/dyavon-48.png"))),
                (256, include_bytes!(concat!("../../../assets/icon/themes/", $t, "/dyavon-256.png"))),
            ],
        }
    };
}

static EMBER: Icon = icon!("ember");
static GRAPHITE: Icon = icon!("graphite");
static PLUM: Icon = icon!("plum");
static FOREST: Icon = icon!("forest");
static SLATE: Icon = icon!("slate");
static PORCELAIN: Icon = icon!("porcelain");
static CORAL: Icon = icon!("coral");
static LIME: Icon = icon!("lime");
static SAFFRON: Icon = icon!("saffron");
static VIOLET: Icon = icon!("violet");

/// The icon for a theme's config key (`ui_theme::Theme6::key`); anything else gets
/// Amber, the default.
pub fn for_theme(key: &str) -> &'static Icon {
    match key {
        "graphite" => &GRAPHITE,
        "plum" => &PLUM,
        "forest" => &FOREST,
        "slate" => &SLATE,
        "porcelain" => &PORCELAIN,
        "coral" => &CORAL,
        "lime" => &LIME,
        "saffron" => &SAFFRON,
        "violet" => &VIOLET,
        _ => &EMBER,
    }
}

/// A Windows .ico holding the icon's PNGs (PNG entries work on Vista and later).
#[cfg_attr(not(windows), allow(dead_code))]
pub fn ico(icon: &Icon) -> Vec<u8> {
    let n = icon.pngs.len() as u16;
    let mut out = Vec::new();
    out.extend_from_slice(&[0, 0, 1, 0]);
    out.extend_from_slice(&n.to_le_bytes());
    let mut offset = 6 + 16 * n as u32;
    for (size, png) in icon.pngs {
        let side = if size >= 256 { 0 } else { size as u8 };
        out.extend_from_slice(&[side, side, 0, 0]);
        out.extend_from_slice(&1u16.to_le_bytes()); // colour planes
        out.extend_from_slice(&32u16.to_le_bytes()); // bits per pixel
        out.extend_from_slice(&(png.len() as u32).to_le_bytes());
        out.extend_from_slice(&offset.to_le_bytes());
        offset += png.len() as u32;
    }
    for (_, png) in icon.pngs {
        out.extend_from_slice(png);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEYS: [&str; 10] =
        ["ember", "graphite", "plum", "forest", "slate", "porcelain", "coral", "lime", "saffron", "violet"];

    #[test]
    fn every_theme_has_whole_square_icons() {
        for k in KEYS {
            let i = for_theme(k);
            assert_eq!(i.rgba64.len(), 64 * 64 * 4, "{k}");
            assert_eq!(i.rgba32.len(), 32 * 32 * 4, "{k}");
            for (_, png) in i.pngs {
                assert_eq!(&png[1..4], b"PNG", "{k}");
            }
        }
    }

    #[test]
    fn each_theme_has_its_own_colours_and_unknown_is_amber() {
        for (a, b) in KEYS.iter().zip(KEYS.iter().skip(1)) {
            assert_ne!(for_theme(a).rgba64, for_theme(b).rgba64, "{a} vs {b}");
        }
        assert!(std::ptr::eq(for_theme("midnight"), for_theme("ember")));
    }

    #[cfg(feature = "gui")]
    #[test]
    fn every_app_theme_has_an_icon() {
        for t in crate::ui_theme::Theme6::ALL {
            assert!(KEYS.contains(&t.key()), "{} has no icon", t.key());
        }
    }

    #[test]
    fn the_ico_directory_points_at_each_png() {
        let i = for_theme("ember");
        let ico = ico(i);
        assert_eq!(&ico[..6], &[0, 0, 1, 0, 4, 0]);
        for (n, (size, png)) in i.pngs.iter().enumerate() {
            let e = &ico[6 + 16 * n..6 + 16 * (n + 1)];
            assert_eq!(e[0], if *size >= 256 { 0 } else { *size as u8 });
            let len = u32::from_le_bytes(e[8..12].try_into().unwrap()) as usize;
            let off = u32::from_le_bytes(e[12..16].try_into().unwrap()) as usize;
            assert_eq!(&ico[off..off + len], *png);
        }
    }
}
