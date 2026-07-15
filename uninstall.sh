#!/bin/sh
set -eu

CODEX_HOME=${CODEX_HOME:-"$HOME/.codex"}
export CODEX_HOME

python3 - <<'PY'
import base64
import hashlib
import json
import os
import pathlib
import shutil
import tempfile
import time

home = pathlib.Path(os.environ["CODEX_HOME"]).expanduser()
state_file = home / ".subagents_configs-state.json"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def backup(path):
    stamp = time.strftime("%Y%m%d%H%M%S")
    candidate = path.with_name(path.name + ".subagents_configs.bak-" + stamp)
    index = 1
    while candidate.exists():
        candidate = path.with_name(path.name + ".subagents_configs.bak-" + stamp + f"-{index}")
        index += 1
    shutil.copy2(path, candidate)
    print("backup:", candidate)
    return str(candidate)


def atomic_write(path, data, mode_from=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix="." + path.name + ".", dir=str(path.parent))
    tmp = pathlib.Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        if mode_from and mode_from.exists():
            shutil.copymode(mode_from, tmp)
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()


try:
    state = json.loads(state_file.read_text())
except FileNotFoundError:
    print("No installer state; nothing removed safely")
    raise SystemExit
except json.JSONDecodeError as exc:
    raise SystemExit(f"error: installer state is invalid JSON ({exc}); nothing removed")

for item in state.get("files", {}).values():
    path = pathlib.Path(item["target"])
    if not path.exists() or sha256(path) != item["installed_hash"]:
        print("preserved modified/missing:", path)
        continue
    if item["ownership"] == "created":
        path.unlink()
        print("removed:", path)
    elif item["ownership"] == "replaced" and item.get("backup"):
        shutil.copy2(item["backup"], path)
        print("restored:", path)
    else:
        print("preserved pre-existing:", path)

global_state = state.get("global", {})
agents_path = pathlib.Path(global_state["target"]) if global_state.get("target") else None
if agents_path and agents_path.exists() and global_state.get("ownership") == "managed":
    block = global_state["block"].encode("utf-8")
    data = agents_path.read_bytes()
    pos = data.find(block)
    if pos >= 0:
        backup(agents_path)
        before = base64.b64decode(global_state.get("before", ""))
        begin = block[: len(b"# BEGIN subagents_configs")]
        start = before.find(begin)
        end = before.find(b"# END subagents_configs", start)
        if start >= 0 and end >= start:
            expected = before[:start] + block + before[end + len(b"# END subagents_configs") :]
        else:
            expected = before + (b"\n\n" if before else b"") + block + b"\n"
        original = base64.b64decode(global_state.get("original_segment", ""))
        restored = before if before and data == expected else data[:pos] + original + data[pos + len(block) :]
        atomic_write(agents_path, restored, agents_path)
        print("removed exact managed block:", agents_path)
    else:
        print("preserved AGENTS.md: managed block changed or missing")

config_state = state.get("config", {})
config_path = pathlib.Path(config_state["target"]) if config_state.get("target") else None
if config_path and config_path.exists() and config_state.get("ownership") in {"created", "appended"}:
    block = config_state.get("block", "").encode("utf-8")
    data = config_path.read_bytes()
    pos = data.find(block)
    if pos < 0:
        print("preserved config.toml: managed block changed or missing")
    elif config_state["ownership"] == "created" and data.strip() == block.strip():
        backup(config_path)
        config_path.unlink()
        print("removed managed config.toml:", config_path)
    else:
        backup(config_path)
        new_data = data[:pos] + data[pos + len(block) :]
        while b"\n\n\n" in new_data:
            new_data = new_data.replace(b"\n\n\n", b"\n\n")
        atomic_write(config_path, new_data, config_path)
        print("removed managed config block:", config_path)
elif config_path:
    print("preserved config.toml")

state_file.unlink(missing_ok=True)
PY

echo "Codex subagents uninstalled from $CODEX_HOME"
