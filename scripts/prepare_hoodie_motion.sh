#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MOTION_TEMP=$(mktemp -d)
trap 'rm -rf "$MOTION_TEMP"' EXIT
swiftc -O -sdk "$(xcrun --show-sdk-path)" scripts/SpriteComponentCleanup.swift Sources/Pet/PetWalkAnimation.swift scripts/prepare_hoodie_rig.swift -o "$MOTION_TEMP/prepare-rig"
"$MOTION_TEMP/prepare-rig"
