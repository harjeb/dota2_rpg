#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VSCRIPTS="$ROOT/game/scripts/vscripts"

LUA_BIN=""
LUAC_BIN=""
if command -v lua >/dev/null 2>&1; then LUA_BIN="lua"; elif command -v texlua >/dev/null 2>&1; then LUA_BIN="texlua"; fi
if command -v luac >/dev/null 2>&1; then LUAC_BIN="luac"; elif command -v texluac >/dev/null 2>&1; then LUAC_BIN="texluac"; fi

if [[ -z "$LUA_BIN" || -z "$LUAC_BIN" ]]; then
    echo "Lua interpreter/compiler not found." >&2
    exit 1
fi

while IFS= read -r -d '' file; do
    "$LUAC_BIN" -p "$file"
done < <(find "$ROOT" -name '*.lua' -print0)

if command -v node >/dev/null 2>&1; then
    while IFS= read -r -d '' file; do
        node --check "$file"
    done < <(find "$ROOT" -name '*.js' -print0)
fi

"$LUA_BIN" "$ROOT/tests/test_progression.lua" "$VSCRIPTS"
"$LUA_BIN" "$ROOT/tests/test_affix_generation.lua" "$VSCRIPTS"
"$LUA_BIN" "$ROOT/tests/test_target_selector.lua" "$VSCRIPTS"
"$LUA_BIN" "$ROOT/tests/test_rule_service.lua" "$VSCRIPTS"

echo "All demo checks passed."
