#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -sdk "$(xcrun --show-sdk-path)" Sources/Chat/ChatStore.swift Sources/Chat/DeepSeekBalance.swift Tests/BalanceTests.swift -o "$TEST_DIR/balance-tests"
"$TEST_DIR/balance-tests"
