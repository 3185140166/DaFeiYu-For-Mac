#!/bin/bash
# Compatibility entry point: native first-use setup no longer requires Python/Node/npm.
set -euo pipefail
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
if [[ "$SCRIPT_DIR" == */Contents/Resources/AgentRuntime ]]; then
  APP_PATH=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
else
  APP_PATH="$SCRIPT_DIR/../BaifanYu.app"
fi
if [ ! -d "$APP_PATH" ]; then
  echo 'Build DaFeiYu first with bash build.sh.' >&2
  exit 1
fi
open "$APP_PATH" --args --tasks
printf '%s\n' '在大肥鱼气泡中点击「启用工作能力」，会自动下载并校验所需后台。'
