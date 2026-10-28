#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MOTION_TEMP=$(mktemp -d)
trap 'rm -rf "$MOTION_TEMP"' EXIT
swift scripts/prepare_hoodie_motion.swift
swiftc -O -sdk "$(xcrun --show-sdk-path)" scripts/SpriteComponentCleanup.swift Sources/Pet/PetWalkAnimation.swift scripts/refine_hoodie_gait.swift -o "$MOTION_TEMP/refine-gait"
"$MOTION_TEMP/refine-gait"
