#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -sdk "$(xcrun --show-sdk-path)" Sources/App/AppSettings.swift Sources/Pet/PetSkin.swift Sources/Pet/PetBitmap.swift Sources/Pet/PetWalkAnimation.swift Sources/Pet/PetView.swift scripts/SpriteComponentCleanup.swift Tests/SkinTests.swift -o "$TEST_DIR/skin-tests"
"$TEST_DIR/skin-tests" "$PWD/BaifanYu.app/Contents/Resources/BaifanYu_BaifanYu.bundle"
