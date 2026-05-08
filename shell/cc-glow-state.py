#!/usr/bin/env python3
"""Persist cc-glow agent state and emit WezTerm user-var signals."""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


VISIBLE_STATUSES = {"running", "done", "waiting", "ended"}
ATTENTION_STATUSES = {"done", "waiting"}


def now_seconds() -> int:
    override = os.environ.get("CC_GLOW_NOW")
    if override:
        try:
            return int(float(override))
        except ValueError:
            pass
    return int(time.time())


def state_dir() -> Path:
    xdg_state = os.environ.get("XDG_STATE_HOME")
    if xdg_state:
        return Path(xdg_state).expanduser() / "cc-glow"
    return Path.home() / ".local" / "state" / "cc-glow"


def state_path() -> Path:
    override = os.environ.get("CC_GLOW_STATE_PATH")
    if override:
        return Path(override).expanduser()
    return state_dir() / "state.json"


def read_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"version": 1, "updated_at": 0, "sessions": {}}
    try:
        with path.open("r", encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {"version": 1, "updated_at": 0, "sessions": {}}
    if not isinstance(state, dict):
        return {"version": 1, "updated_at": 0, "sessions": {}}
    sessions = state.get("sessions")
    if not isinstance(sessions, dict):
        state["sessions"] = {}
    state["version"] = 1
    return state


def write_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
    )
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(state, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp_path, path)
    finally:
        if tmp_path.exists():
            try:
                tmp_path.unlink()
            except OSError:
                pass


def current_workspace() -> str:
    for key in ("CC_GLOW_WORKSPACE", "WEZTERM_WORKSPACE"):
        value = os.environ.get(key, "").strip()
        if value:
            return value
    return "unknown"


def current_cwd() -> str | None:
    value = os.environ.get("PWD", "").strip()
    return value or None


def current_session_id() -> str | None:
    for key in ("CLAUDE_SESSION_ID", "OPENCODE_SESSION_ID", "CC_GLOW_SESSION_ID"):
        value = os.environ.get(key, "").strip()
        if value:
            return value
    return None


def current_pid() -> int | None:
    for key in (
        "CC_GLOW_AGENT_PID",
        "CMUX_CLAUDE_PID",
        "CMUX_OPENCODE_PID",
        "CLAUDE_PID",
        "OPENCODE_PID",
    ):
        raw = os.environ.get(key, "").strip()
        if raw:
            try:
                pid = int(raw)
            except ValueError:
                continue
            if pid > 0:
                return pid
    parent = os.getppid()
    return parent if parent > 1 else None


def is_process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def clean_sessions(sessions: dict[str, Any], now: int) -> None:
    for key, entry in list(sessions.items()):
        if not isinstance(entry, dict):
            sessions.pop(key, None)
            continue
        status = entry.get("status")
        updated_at = entry.get("updated_at")
        try:
            age = now - int(updated_at)
        except (TypeError, ValueError):
            age = 0
        if status == "ended" and age > 10 * 60:
            sessions.pop(key, None)
            continue
        if status in ATTENTION_STATUSES and age > 24 * 60 * 60:
            sessions.pop(key, None)
            continue
        pid = entry.get("pid")
        if status == "running" and isinstance(pid, int) and not is_process_alive(pid):
            entry["status"] = "ended"
            entry["updated_at"] = now


def upsert_session(
    state: dict[str, Any], status: str, agent: str, pane_id: str, workspace: str, now: int
) -> None:
    sessions = state.setdefault("sessions", {})
    if not isinstance(sessions, dict):
        sessions = {}
        state["sessions"] = sessions
    key = f"{workspace}:{pane_id}"
    existing = sessions.get(key)
    if not isinstance(existing, dict):
        existing = {}
    started_at = existing.get("started_at") or now
    entry: dict[str, Any] = {
        "workspace": workspace,
        "pane_id": pane_id,
        "agent": agent,
        "status": status,
        "started_at": started_at,
        "updated_at": now,
    }
    cwd = current_cwd()
    if cwd:
        entry["cwd"] = cwd
    session_id = current_session_id()
    if session_id:
        entry["session_id"] = session_id
    pid = current_pid()
    if pid:
        entry["pid"] = pid
    sessions[key] = entry
    clean_sessions(sessions, now)
    state["version"] = 1
    state["updated_at"] = now


def set_user_var_sequence(name: str, value: str) -> str:
    encoded = base64.b64encode(value.encode("utf-8")).decode("ascii")
    return f"\033]1337;SetUserVar={name}={encoded}\007"


def visible_status(status: str) -> str:
    if status == "waiting":
        return "waiting"
    if status == "ended":
        return ""
    return status


def emit_user_vars(status: str, now: int) -> None:
    visible = visible_status(status)
    if visible:
        sys.stdout.write(set_user_var_sequence("AI_RING", visible))
    elif status == "ended":
        sys.stdout.write(set_user_var_sequence("AI_RING", ""))
    sys.stdout.write(set_user_var_sequence("CC_GLOW_STATE_VERSION", str(now)))
    sys.stdout.flush()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Persist cc-glow agent state")
    parser.add_argument("status", choices=sorted(VISIBLE_STATUSES))
    parser.add_argument("agent", nargs="?", default="agent")
    args = parser.parse_args(argv)

    pane_id = os.environ.get("WEZTERM_PANE", "").strip()
    if not pane_id:
        return 0

    now = now_seconds()
    path = state_path()
    state = read_state(path)
    upsert_session(state, args.status, args.agent, pane_id, current_workspace(), now)
    write_state(path, state)
    emit_user_vars(args.status, now)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
