#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
mkdir -p work outputs Resources/ThirdParty
source_archive=work/smartmontools-7.5.tar.gz
expected_sha=690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e
if [ ! -f "$source_archive" ]; then
  curl -4 --fail --location --retry 2 --max-time 120 \
    https://downloads.sourceforge.net/project/smartmontools/smartmontools/7.5/smartmontools-7.5.tar.gz -o "$source_archive"
fi
actual_sha="$(shasum -a 256 "$source_archive" | cut -d ' ' -f 1)"
if [ "$actual_sha" != "$expected_sha" ]; then
  printf 'smartmontools source checksum mismatch\n' >&2
  exit 1
fi
if [ ! -x work/smartmontools-7.5/smartctl ]; then
  tar -xzf "$source_archive" -C work
  (
    cd work/smartmontools-7.5
    MACOSX_DEPLOYMENT_TARGET=14.0 ./configure --without-libsystemd --without-libcap-ng > ../smartmontools-configure.log 2>&1
    MACOSX_DEPLOYMENT_TARGET=14.0 make -j 6 smartctl > ../smartmontools-build.log 2>&1
  )
fi
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app="$project_root/outputs/移动硬盘测试.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/ThirdParty"
cp "$binary_dir/PortableDiskTest" "$app/Contents/MacOS/PortableDiskTest"
cp work/smartmontools-7.5/smartctl "$app/Contents/MacOS/smartctl"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.provenance.json "$app/Contents/Resources/"
cp Resources/ManufacturerCatalog.provenance.json "$app/Contents/Resources/"
ditto Resources/Brands "$app/Contents/Resources/Brands"
cp work/smartmontools-7.5/COPYING "$app/Contents/Resources/ThirdParty/smartmontools-COPYING.txt"
cp "$source_archive" "$app/Contents/Resources/ThirdParty/"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/ThirdParty/"
swift scripts/make-icon.swift work/AppIcon.iconset
iconutil -c icns work/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
chmod 755 "$app/Contents/MacOS/PortableDiskTest" "$app/Contents/MacOS/smartctl"
codesign --force --sign - "$app/Contents/MacOS/smartctl"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
printf '\nBuilt: %s\n' "$app"
if [ "${1:-}" = "--install" ]; then
  destination="$HOME/Applications/移动硬盘测试.app"
  if [ -e "$destination" ]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$destination/Contents/Info.plist")"
    if [ "$existing_id" != com.glow.portabledisktest ]; then
      printf 'Refusing to replace a different application: %s\n' "$destination" >&2
      exit 1
    fi
  fi
  mkdir -p "$HOME/Applications"
  ditto "$app" "$destination"
  printf 'Installed: %s\n' "$destination"
fi
