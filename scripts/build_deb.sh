#!/usr/bin/env bash
# Membuat installer .deb. Jalankan dari root proyek:  bash scripts/build_deb.sh
set -euo pipefail
cd "$(dirname "$0")/.."

V=$(grep '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')
PKG="dynamic-island_${V}_amd64"
OUT="build/deb/$PKG"

flutter build linux --release

rm -rf "build/deb"
mkdir -p "$OUT/DEBIAN" "$OUT/opt/dynamic-island" "$OUT/usr/bin" \
         "$OUT/usr/share/applications" "$OUT/usr/share/pixmaps"
cp -r build/linux/x64/release/bundle/* "$OUT/opt/dynamic-island/"
ln -s /opt/dynamic-island/dynamic_island "$OUT/usr/bin/dynamic-island"
cp assets/icons/app_icon.png "$OUT/usr/share/pixmaps/dynamic-island.png"

cat > "$OUT/DEBIAN/control" <<CTRL
Package: dynamic-island
Version: $V
Section: utils
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libayatana-appindicator3-1
Recommends: xdotool
Maintainer: AjarHer08 <noreply@github.com>
Homepage: https://github.com/AjarHer08/dynamic-island
Description: Dynamic Island untuk desktop Linux
 Overlay ala Dynamic Island: musik, notifikasi, baterai, performa,
 dengan efek Liquid Glass.
CTRL

cat > "$OUT/usr/share/applications/dynamic-island.desktop" <<DESK
[Desktop Entry]
Name=Dynamic Island
Comment=Dynamic Island untuk desktop
Exec=/opt/dynamic-island/dynamic_island
Icon=dynamic-island
Type=Application
Categories=Utility;
DESK

mkdir -p dist
dpkg-deb --build --root-owner-group "$OUT" "dist/$PKG.deb"
echo "Selesai: dist/$PKG.deb"
