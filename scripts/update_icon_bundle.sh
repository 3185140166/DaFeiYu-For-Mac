#!/bin/bash
# Package the generated PNG into a complete macOS icon family.
set -euo pipefail
cd "$(dirname "$0")/.."
ICON_TEMP=$(mktemp -d)
trap 'rm -rf "$ICON_TEMP"' EXIT
ICON_SET="$ICON_TEMP/AppIcon.iconset"
mkdir -p "$ICON_SET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" icon-src/AppIcon_1024.png --out "$ICON_SET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" icon-src/AppIcon_1024.png --out "$ICON_SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_SET" -o Sources/Resources/AppIcon.icns
