#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -sdk "$(xcrun --show-sdk-path)" Sources/Chat/ChatStore.swift Tests/CredentialTests.swift -o "$TEST_DIR/credential-tests"
"$TEST_DIR/credential-tests"
