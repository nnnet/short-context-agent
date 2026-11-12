#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE_SOURCE="${CODEX_MARKETPLACE_SOURCE:-$ROOT}"
MARKETPLACE_REF="${CODEX_MARKETPLACE_REF:-}"
command -v codex >/dev/null || { echo "codex is required" >&2; exit 1; }
command -v bwrap >/dev/null || { echo "bwrap is required for isolated installation" >&2; exit 1; }

STATE="$(mktemp -d /tmp/short-context-codex-install.XXXXXX)"
CONFIG="$STATE/codex"
WORKSPACE="$STATE/workspace"
USER_DIR="$(python3 -c 'import os,pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
CODEX_CONFIG="$USER_DIR/.codex"
NODE_CODEX="$(npm root -g)/@openai/codex/bin/codex.js"
if test -f "$NODE_CODEX"; then
  CODEX_COMMAND=(node "$NODE_CODEX")
else
  CODEX_COMMAND=(codex)
fi
mkdir -p "$CONFIG" "$WORKSPACE/.claude"
trap 'rm -rf "$STATE"' EXIT

codex_isolated() {
  bwrap \
    --bind / / \
    --bind "$CONFIG" "$CODEX_CONFIG" \
    -- "${CODEX_COMMAND[@]}" "$@"
}

MARKETPLACE_ARGS=(plugin marketplace add "$MARKETPLACE_SOURCE")
if test -n "$MARKETPLACE_REF"; then
  MARKETPLACE_ARGS+=(--ref "$MARKETPLACE_REF")
fi
MARKETPLACE_ARGS+=(--json)
codex_isolated "${MARKETPLACE_ARGS[@]}" >/dev/null
codex_isolated plugin add short-context-agent@short-context-agent --json >/dev/null

PLUGIN_MANIFEST="$(find "$CONFIG/plugins/cache" -path '*/.codex-plugin/plugin.json' -print -quit)"
test -n "$PLUGIN_MANIFEST"
PLUGIN_ROOT="$(dirname "$(dirname "$PLUGIN_MANIFEST")")"
test -f "$PLUGIN_ROOT/skills/short-context-agent/SKILL.md"
test -f "$PLUGIN_ROOT/.codex-plugin/hooks.json"
python3 - "$PLUGIN_MANIFEST" <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
assert manifest["name"] == "short-context-agent"
assert manifest["skills"] == "./skills/"
assert manifest["hooks"] == "./.codex-plugin/hooks.json"
PY
echo "ok   codex installed skill and hook"

MARKER="codex-install-check-8817"
printf '# Handoff brief\n\n%s\n' "$MARKER" > "$WORKSPACE/.claude/handoff.md"
HOOK_COMMAND="$(python3 - "$PLUGIN_ROOT/.codex-plugin/hooks.json" <<'PY'
import json
import sys

hooks = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]
print(hooks["SessionStart"][0]["hooks"][0]["command"])
PY
)"
python3 - "$WORKSPACE" <<'PY' \
  | PLUGIN_ROOT="$PLUGIN_ROOT" bash -c "$HOOK_COMMAND" \
  > "$STATE/hook-output.json"
import json
import sys

print(json.dumps({
    "hook_event_name": "SessionStart",
    "source": "compact",
    "cwd": sys.argv[1],
}))
PY
python3 - "$STATE/hook-output.json" "$MARKER" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
output = payload["hookSpecificOutput"]
assert output["hookEventName"] == "SessionStart"
assert sys.argv[2] in output["additionalContext"]
PY
echo "ok   codex hook injected handoff brief"

codex_isolated plugin remove short-context-agent@short-context-agent --json >/dev/null
codex_isolated plugin marketplace remove short-context-agent --json >/dev/null
echo "ok   codex removed plugin and marketplace"
