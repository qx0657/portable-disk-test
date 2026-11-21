# Third-party components

## smartmontools 7.5

The application bundles an unmodified `smartctl` executable, built from the official smartmontools 7.5 source distribution for the host architecture with `MACOSX_DEPLOYMENT_TARGET=14.0`.

- Copyright (C) 2002–2025 Bruce Allen, Christian Franke and contributors.
- License: GNU General Public License, version 2 or (at your option) any later version.
- Project: https://www.smartmontools.org/
- Corresponding source: `Contents/Resources/ThirdParty/smartmontools-7.5.tar.gz` in the application bundle.
- Complete license: `Contents/Resources/ThirdParty/smartmontools-COPYING.txt`.
- Upstream archive: https://downloads.sourceforge.net/project/smartmontools/smartmontools/7.5/smartmontools-7.5.tar.gz
- SHA-256: `690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e`.
- Reproduce the bundled executable with the configure and make commands in `scripts/build.sh`.

## AmorphousDiskMark

AmorphousDiskMark is a separate application by Katsura Shareware. It is not bundled, modified or redistributed by this project. The user opens it explicitly and may import the plain-text results they copy from it. This project has no affiliation with Katsura Shareware or Sandisk.

The app icon is original geometric artwork drawn by `scripts/make-icon.swift`; interface icons use system SF Symbols.

## Sandisk wordmarks

Unmodified official red and white Sandisk SVG wordmarks identify connected Sandisk-branded hardware. They are not used as this application's identity or to imply endorsement. SanDisk / SANDISK names and logos belong to their respective rights holders. Original source URLs and SHA-256 hashes are recorded in `Resources/Brands/provenance.json`, also bundled with the application.

## Manufacturer identification facts

The E82 family rule uses hardware identifiers verified against the product catalog shipped in SANDISK App 3.4.2 (2717) and the manufacturer's public product page. Only the small set of identification facts and provenance is retained in `Resources/ManufacturerCatalog.provenance.json`; the official application, its driver, and its full catalog are not redistributed. This rule corroborates a product family and does not read or manufacture a complete retail part number.

## Apple frameworks and symbols

AppKit, SwiftUI, IOKit, Vision, Core ML, ImageIO, CoreText, Charts, and SF Symbols are used through the system SDK and runtime. Apple framework binaries are not copied into the repository or application bundle by this project's build script.
