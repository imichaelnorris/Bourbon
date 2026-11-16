# Runtime

`build.sh` builds Bourbon's Wine runtime on your Mac and installs it into
`~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries`. Every input is downloaded from its
publisher and pinned by SHA-256 (see the top of `build.sh`):

- **Wine**: CodeWeavers' [CrossOver source](https://www.codeweavers.com/crossover/source) (LGPL-2.1+), plus `patches/`
- **x86_64 libraries** (freetype, gnutls, MoltenVK, …) **and Wine Gecko/Mono**: Gcenx's [WineHQ macOS build](https://github.com/Gcenx/macOS_Wine_builds)
- **DXVK**: [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS) 1.10.3 (zlib) · **winetricks** (LGPL-2.1)

`patches/` modifies Wine and is LGPL-2.1+ like Wine. The one patch so far adds `--in-process-gpu` when Steam
starts its Chromium web helper; without it the Steam window stays black on macOS.

Bourbon distributes no runtime binaries. It is not affiliated with CodeWeavers; CrossOver is their trademark.
