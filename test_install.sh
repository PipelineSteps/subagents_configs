#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TMP_ROOT=${TMPDIR:-/tmp}
WORKDIR=$(mktemp -d "$TMP_ROOT/subagents configs test.XXXXXX")
trap 'rm -rf "$WORKDIR"' EXIT HUP INT TERM

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required command: $1" >&2
    exit 1
  }
}

assert_file() {
  [ -f "$1" ] || {
    echo "error: expected file missing: $1" >&2
    exit 1
  }
}

assert_absent() {
  [ ! -e "$1" ] || {
    echo "error: expected path to be absent: $1" >&2
    exit 1
  }
}

assert_count() {
  file=$1
  pattern=$2
  expected=$3
  actual=$(grep -c "$pattern" "$file" || true)
  [ "$actual" = "$expected" ] || {
    echo "error: expected $expected occurrences of '$pattern' in $file, found $actual" >&2
    exit 1
  }
}

require python3

python3 - "$ROOT" <<'PY'
import pathlib
import sys
import tomllib

root = pathlib.Path(sys.argv[1])
for path in sorted((root / "agents").glob("*.toml")):
    with path.open("rb") as handle:
        tomllib.load(handle)
print("agent TOML validation passed")
PY

sh -n "$ROOT/install.sh"
sh -n "$ROOT/uninstall.sh"
sh -n "$ROOT/test_install.sh"

CODEX_HOME="$WORKDIR/empty home" "$ROOT/install.sh"
assert_file "$WORKDIR/empty home/agents/code-explorer.toml"
assert_file "$WORKDIR/empty home/agents/quick-implementer.toml"
assert_file "$WORKDIR/empty home/agents/implementer.toml"
assert_file "$WORKDIR/empty home/agents/code-reviewer.toml"
assert_file "$WORKDIR/empty home/agents/commit-pusher.toml"
assert_file "$WORKDIR/empty home/SUBAGENT_ROUTING.md"
assert_file "$WORKDIR/empty home/AGENTS.md"
assert_file "$WORKDIR/empty home/config.toml"
assert_file "$WORKDIR/empty home/.subagents_configs-state.json"
assert_count "$WORKDIR/empty home/AGENTS.md" "# BEGIN subagents_configs" 1
assert_count "$WORKDIR/empty home/config.toml" "# BEGIN subagents_configs config" 1

CODEX_HOME="$WORKDIR/empty home" "$ROOT/install.sh"
assert_count "$WORKDIR/empty home/AGENTS.md" "# BEGIN subagents_configs" 1
assert_count "$WORKDIR/empty home/config.toml" "# BEGIN subagents_configs config" 1

UPGRADE_REPO="$WORKDIR/upgrade repo"
cp -R "$ROOT" "$UPGRADE_REPO"
printf '\n# upgrade fixture\n' >> "$UPGRADE_REPO/rules/SUBAGENT_ROUTING.md"
CODEX_HOME="$WORKDIR/empty home" "$UPGRADE_REPO/install.sh"
grep -F '# upgrade fixture' "$WORKDIR/empty home/SUBAGENT_ROUTING.md" >/dev/null
CODEX_HOME="$WORKDIR/empty home" "$ROOT/uninstall.sh"
assert_absent "$WORKDIR/empty home/config.toml"
assert_absent "$WORKDIR/empty home/agents/code-explorer.toml"
assert_absent "$WORKDIR/empty home/SUBAGENT_ROUTING.md"

CUSTOM="$WORKDIR/custom home"
mkdir -p "$CUSTOM"
printf 'user note before\n' > "$CUSTOM/AGENTS.md"
printf '[sandbox]\nmode = "workspace-write"\n' > "$CUSTOM/config.toml"
cp "$CUSTOM/AGENTS.md" "$CUSTOM/AGENTS.original"
cp "$CUSTOM/config.toml" "$CUSTOM/config.original"
CODEX_HOME="$CUSTOM" "$ROOT/install.sh"
python3 - "$CUSTOM" <<'PY'
import pathlib
import sys

home = pathlib.Path(sys.argv[1])
assert (home / "AGENTS.md").read_bytes().startswith((home / "AGENTS.original").read_bytes())
assert (home / "config.toml").read_bytes().startswith((home / "config.original").read_bytes())
PY
CODEX_HOME="$CUSTOM" "$ROOT/install.sh"
assert_count "$CUSTOM/AGENTS.md" "# BEGIN subagents_configs" 1
assert_count "$CUSTOM/config.toml" "# BEGIN subagents_configs config" 1

LEGACY="$WORKDIR/legacy home"
mkdir -p "$LEGACY/agents"
printf '# BEGIN subagents_configs\n@/old/path/SUBAGENT_ROUTING.md\n# END subagents_configs\n' > "$LEGACY/AGENTS.md"
printf '[features.multi_agent_v2]\nhide_spawn_agent_metadata = false\ntool_namespace = "agents"\n' > "$LEGACY/config.toml"
CODEX_HOME="$LEGACY" "$ROOT/install.sh"
assert_count "$LEGACY/AGENTS.md" "# BEGIN subagents_configs" 1
assert_count "$LEGACY/config.toml" "# BEGIN subagents_configs config" 1

CODEX_HOME="$CUSTOM" "$ROOT/uninstall.sh"
grep -F 'user note before' "$CUSTOM/AGENTS.md" >/dev/null
grep -F '[sandbox]' "$CUSTOM/config.toml" >/dev/null
grep -F 'mode = "workspace-write"' "$CUSTOM/config.toml" >/dev/null
cmp "$CUSTOM/AGENTS.original" "$CUSTOM/AGENTS.md"
cmp "$CUSTOM/config.original" "$CUSTOM/config.toml"
if grep -F '# BEGIN subagents_configs' "$CUSTOM/AGENTS.md" >/dev/null; then
  echo "error: managed AGENTS block survived uninstall" >&2
  exit 1
fi
if grep -F '# BEGIN subagents_configs config' "$CUSTOM/config.toml" >/dev/null; then
  echo "error: managed config block survived uninstall" >&2
  exit 1
fi
assert_absent "$CUSTOM/agents/code-explorer.toml"

CODEX_HOME="$LEGACY" "$ROOT/uninstall.sh"
assert_absent "$LEGACY/config.toml"

BAD="$WORKDIR/bad home"
mkdir -p "$BAD"
printf '[broken\n' > "$BAD/config.toml"
if CODEX_HOME="$BAD" "$ROOT/install.sh"; then
  echo "error: malformed config.toml install unexpectedly succeeded" >&2
  exit 1
fi
if [ -e "$BAD/agents" ] || [ -e "$BAD/AGENTS.md" ]; then
  echo "error: installer modified files after malformed config.toml" >&2
  exit 1
fi

UNWRITABLE="$WORKDIR/unwritable home"
mkdir -p "$UNWRITABLE"
printf '[sandbox]\nmode = "workspace-write"\n' > "$UNWRITABLE/config.toml"
chmod 500 "$UNWRITABLE"
if CODEX_HOME="$UNWRITABLE" "$ROOT/install.sh"; then
  chmod 700 "$UNWRITABLE"
  echo "error: unwritable CODEX_HOME install unexpectedly succeeded" >&2
  exit 1
fi
chmod 700 "$UNWRITABLE"
assert_absent "$UNWRITABLE/agents"
assert_absent "$UNWRITABLE/AGENTS.md"

ROLLBACK="$WORKDIR/rollback home"
mkdir -p "$ROLLBACK/agents"
printf 'original explorer\n' > "$ROLLBACK/agents/code-explorer.toml"
mkdir "$ROLLBACK/AGENTS.md"
if CODEX_HOME="$ROLLBACK" "$ROOT/install.sh"; then
  echo "error: forced partial-install failure unexpectedly succeeded" >&2
  exit 1
fi
grep -Fx 'original explorer' "$ROLLBACK/agents/code-explorer.toml" >/dev/null
assert_absent "$ROLLBACK/agents/code-reviewer.toml"
assert_absent "$ROLLBACK/SUBAGENT_ROUTING.md"
assert_absent "$ROLLBACK/config.toml"
assert_absent "$ROLLBACK/.subagents_configs-state.json"
if find "$ROLLBACK" -name '*.subagents_configs.bak-*' -print -quit | grep . >/dev/null; then
  echo "error: failed install left transaction backups behind" >&2
  exit 1
fi

echo "install/uninstall validation passed in $WORKDIR"
