#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -sdk "$(xcrun --show-sdk-path)" Sources/Agent/AgentRuntimeInstaller.swift Tests/RuntimeInstallerTests.swift -o "$TEST_DIR/runtime-tests"
"$TEST_DIR/runtime-tests" "$@"
