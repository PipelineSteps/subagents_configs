#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CODEX_HOME=${CODEX_HOME:-"$HOME/.codex"}
export SCRIPT_DIR CODEX_HOME

python3 - <<'PY'
import base64
import atexit
import hashlib
import json
import os
import pathlib
import shutil
import tempfile
import time

try:
    import tomllib
except ImportError as exc:
    raise SystemExit("error: Python 3.11+ tomllib is required; no files were changed") from exc

src = pathlib.Path(os.environ["SCRIPT_DIR"])
home = pathlib.Path(os.environ["CODEX_HOME"]).expanduser()
agents_dir = home / "agents"
routing = home / "SUBAGENT_ROUTING.md"
global_agents = home / "AGENTS.md"
config = home / "config.toml"
state_file = home / ".subagents_configs-state.json"
transaction = {}
created_backups = []
transaction_committed = False

managed_begin = b"# BEGIN subagents_configs"
managed_end = b"# END subagents_configs"
config_begin = b"# BEGIN subagents_configs config"
config_end = b"# END subagents_configs config"
feature_table = (
    b"[features.multi_agent_v2]\n"
    b'hide_spawn_agent_metadata = false\n'
    b'tool_namespace = "agents"\n'
)
config_block = config_begin + b"\n" + feature_table + config_end + b"\n"


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
    created_backups.append(candidate)
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


def remember(path):
    if path in transaction:
        return
    if path.exists():
        transaction[path] = (path.read_bytes(), path.stat().st_mode)
    else:
        transaction[path] = None


def transactional_write(path, data, mode_from=None):
    remember(path)
    atomic_write(path, data, mode_from)


def transactional_copy(source, target):
    remember(target)
    atomic_write(target, source.read_bytes(), target if target.exists() else source)


def transactional_remove(path):
    remember(path)
    path.unlink(missing_ok=True)


def rollback_transaction():
    if transaction_committed:
        return
    for path, original in reversed(list(transaction.items())):
        try:
            if original is None:
                path.unlink(missing_ok=True)
            else:
                data, mode = original
                atomic_write(path, data)
                os.chmod(path, mode)
        except OSError as exc:
            print(f"error: rollback could not restore {path}: {exc}", file=sys.stderr)
    for path in created_backups:
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass


import sys
atexit.register(rollback_transaction)


def load_state():
    try:
        return json.loads(state_file.read_text())
    except FileNotFoundError:
        return {"files": {}}
    except json.JSONDecodeError as exc:
        raise SystemExit(f"error: installer state is invalid JSON ({exc}); no files were changed") from exc


def parse_toml_bytes(raw, label):
    try:
        return tomllib.loads(raw.decode("utf-8"))
    except UnicodeDecodeError as exc:
        raise SystemExit(f"error: {label} is not UTF-8; no files were changed") from exc
    except tomllib.TOMLDecodeError as exc:
        raise SystemExit(f"error: {label} is invalid TOML ({exc}); no files were changed") from exc


def feature_table_exists(raw):
    parsed = parse_toml_bytes(raw, "config.toml")
    features = parsed.get("features")
    return isinstance(features, dict) and "multi_agent_v2" in features


def replace_once(raw, old, new):
    count = raw.count(old)
    if count != 1:
        return None
    return raw.replace(old, new, 1)


def require_writable_dir(path):
    path.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".subagents_configs.preflight.", dir=str(path))
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(b"ok\n")
    finally:
        pathlib.Path(tmp_name).unlink(missing_ok=True)


# Validate all package-owned sources before touching destinations.
required = [
    src / "rules" / "SUBAGENT_ROUTING.md",
    src / "templates" / "AGENTS.md.template",
]
missing = [str(path) for path in required if not path.is_file()]
agent_sources = sorted((src / "agents").glob("*.toml"))
if not agent_sources:
    missing.append(str(src / "agents" / "*.toml"))
if missing:
    raise SystemExit("error: missing required source files: " + ", ".join(missing))

for path in agent_sources:
    with path.open("rb") as handle:
        tomllib.load(handle)
print("TOML validation passed")

old_state = load_state()

config_existed = config.exists()
config_raw = config.read_bytes() if config_existed else b""
config_updated = config_raw
config_state = old_state.get("config", {})
config_action = "unchanged"
config_backup = None

if config_existed:
    if config_block in config_raw:
        parse_toml_bytes(config_raw, "config.toml")
        config_action = "managed-existing"
    elif feature_table_exists(config_raw):
        old_exact = feature_table
        if config_state.get("ownership") in {"created", "appended"}:
            converted = replace_once(config_raw, old_exact, config_block)
            if converted is not None:
                config_updated = converted
                config_action = "upgraded-legacy-managed"
        elif config_raw == old_exact:
            config_updated = config_block
            config_action = "upgraded-legacy-created"
        else:
            config_action = "preserved-existing"
    else:
        suffix = b"" if not config_raw or config_raw.endswith(b"\n") else b"\n"
        config_updated = config_raw + suffix + config_block
        config_action = "appended"
else:
    config_updated = config_block
    config_action = "created"

if config_updated:
    parse_toml_bytes(config_updated, "config.toml")

try:
    require_writable_dir(home)
    require_writable_dir(agents_dir)
except OSError as exc:
    raise SystemExit(f"error: CODEX_HOME is not writable ({exc}); no files were changed") from exc

current = {}


def install_file(source, target, key):
    target.parent.mkdir(parents=True, exist_ok=True)
    source_hash = sha256(source)
    prior = old_state.get("files", {}).get(key)
    ownership = "created"
    backup_path = None
    if target.exists():
        if sha256(target) == source_hash:
            ownership = prior.get("ownership", "preexisting") if prior else "preexisting"
            backup_path = prior.get("backup") if prior else None
            print("unchanged:", target)
        elif prior and sha256(target) == prior.get("installed_hash") and prior.get("ownership") in {"created", "replaced"}:
            ownership = prior["ownership"]
            backup_path = prior.get("backup")
            transactional_copy(source, target)
            print("updated managed:", target)
        else:
            ownership = "replaced"
            backup_path = backup(target)
            transactional_copy(source, target)
            print("installed:", target)
    else:
        transactional_copy(source, target)
        print("installed:", target)
    current[key] = {
        "target": str(target),
        "installed_hash": source_hash,
        "ownership": ownership,
        "backup": backup_path,
    }


for source in agent_sources:
    install_file(source, agents_dir / source.name, "agents/" + source.name)
install_file(src / "rules" / "SUBAGENT_ROUTING.md", routing, "routing")

if config_updated != config_raw:
    if config_existed:
        config_backup = backup(config)
    transactional_write(config, config_updated, config if config.exists() else None)
    print("updated:" if config_existed else "created:", config)
elif config_existed:
    print("unchanged:", config)
else:
    print("created:", config)

if config_action in {"created", "upgraded-legacy-created"}:
    config_ownership = "created"
elif config_action in {"appended", "upgraded-legacy-managed"}:
    config_ownership = "appended"
elif config_action == "managed-existing" and config_state.get("ownership") in {"created", "appended"}:
    config_ownership = config_state["ownership"]
else:
    config_ownership = None

if config_ownership:
    config_record = {
        "target": str(config),
        "block": config_block.decode("utf-8"),
        "ownership": config_ownership,
        "backup": config_backup or config_state.get("backup"),
    }
else:
    config_record = {"target": str(config), "ownership": "preserved-existing"}

# Remove package-owned files no longer present in this checkout, but never touch modified files.
for key, item in old_state.get("files", {}).items():
    if key in current:
        continue
    target = pathlib.Path(item["target"])
    if target.exists() and sha256(target) == item["installed_hash"]:
        if item["ownership"] == "created":
            transactional_remove(target)
            print("removed stale:", target)
        elif item["ownership"] == "replaced" and item.get("backup"):
            transactional_copy(pathlib.Path(item["backup"]), target)
            print("restored stale:", target)
    else:
        print("preserved stale modified/missing:", target)

block = managed_begin + b"\n@" + str(routing).encode("utf-8") + b"\n" + managed_end
old_global = global_agents.read_bytes() if global_agents.exists() else b""
start = old_global.find(managed_begin)
end = old_global.find(managed_end, start)
original_segment = old_global[start : end + len(managed_end)] if start >= 0 and end >= start else b""
if start >= 0 and end >= start:
    updated_global = old_global[:start] + block + old_global[end + len(managed_end) :]
else:
    updated_global = old_global + (b"\n\n" if old_global else b"") + block + b"\n"

prior_global = old_state.get("global", {})
global_record = {
    "target": str(global_agents),
    "block": block.decode("utf-8"),
    "before": base64.b64encode(old_global).decode("ascii"),
    "original_segment": base64.b64encode(original_segment).decode("ascii"),
    "ownership": "unchanged",
}
if prior_global.get("block") == block.decode("utf-8") and prior_global.get("ownership") == "managed":
    global_record = prior_global
if updated_global != old_global:
    global_record["ownership"] = "managed"
    global_record["backup"] = backup(global_agents) if global_agents.exists() else None
    transactional_write(global_agents, updated_global, global_agents if global_agents.exists() else None)
    print("updated:", global_agents)

state = {"files": current, "global": global_record, "config": config_record}
state_bytes = (json.dumps(state, indent=2, sort_keys=True) + "\n").encode("utf-8")
transactional_write(state_file, state_bytes, state_file if state_file.exists() else None)
transaction_committed = True
PY

echo "Codex subagents installed under $CODEX_HOME"
