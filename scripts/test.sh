#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/module-cache"
swift test --package-path "$PROJECT_ROOT" --disable-sandbox \
    --cache-path "$PROJECT_ROOT/.build/cache" \
    --config-path "$PROJECT_ROOT/.build/config" \
    --security-path "$PROJECT_ROOT/.build/security"
