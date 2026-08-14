#!/usr/bin/env python3
"""FA hardware monitoring agent — collect SEL / dmesg / SDR and push to center.

Runs once per invocation; schedule via systemd timer (e.g. every 5 minutes).
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

import requests

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SERVER_ID = "Node-01"
CENTER_URL = "http://127.0.0.1:8000/api/collect"
LAST_ID_FILE = "/opt/fa-agent/last_id.txt"

_CMD_TIMEOUT = 10
_HTTP_TIMEOUT = 5

# SEL line starts with decimal record id, e.g. "100 | 07/15/2026 | ..."
_SEL_ID_RE = re.compile(r"^(\d+)\s*\|")


def log(msg: str) -> None:
    """Print to stdout for systemd journal capture."""
    print(msg, flush=True)


def run_cmd(cmd: str) -> str:
    """Run a shell command; return stdout or empty string on failure/timeout."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=_CMD_TIMEOUT,
        )
        if result.returncode != 0 and result.stderr:
            log(f"[warn] command exit {result.returncode}: {cmd!r} — {result.stderr.strip()[:200]}")
        return (result.stdout or "").strip()
    except subprocess.TimeoutExpired:
        log(f"[warn] command timeout ({_CMD_TIMEOUT}s), skipped: {cmd!r}")
        return ""
    except Exception as exc:
        log(f"[warn] command failed: {cmd!r} — {exc}")
        return ""


def read_last_record_id(path: str) -> int:
    try:
        text = Path(path).read_text(encoding="utf-8").strip()
        return int(text) if text else 0
    except FileNotFoundError:
        return 0
    except (ValueError, OSError) as exc:
        log(f"[warn] cannot read LAST_ID_FILE {path}: {exc}; using 0")
        return 0


def write_last_record_id(path: str, record_id: int) -> None:
    try:
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(str(record_id), encoding="utf-8")
    except OSError as exc:
        log(f"[error] cannot write LAST_ID_FILE {path}: {exc}")


def parse_sel_lines(sel_text: str) -> list[tuple[int, str]]:
    """Return list of (record_id, line) for parseable SEL rows."""
    rows: list[tuple[int, str]] = []
    for line in sel_text.splitlines():
        line = line.strip()
        if not line:
            continue
        m = _SEL_ID_RE.match(line)
        if not m:
            continue
        rows.append((int(m.group(1)), line))
    return rows


def filter_incremental_sel(
    rows: list[tuple[int, str]],
    last_id: int,
) -> tuple[list[str], int, int]:
    """Filter rows with id > last_id.

    Returns (new_lines, new_last_id, max_id_in_batch).
    If max_id < last_id (SEL cleared), reset last_id to 0 and include all rows.
    """
    if not rows:
        return [], last_id, last_id

    max_id = max(rid for rid, _ in rows)

    effective_last = last_id
    if max_id < last_id:
        log(
            f"[info] SEL max id {max_id} < LAST_RECORD_ID {last_id} "
            "(possible sel clear); resetting LAST_RECORD_ID to 0"
        )
        effective_last = 0

    new_lines = [line for rid, line in rows if rid > effective_last]
    new_last = max((rid for rid, _ in rows if rid > effective_last), default=effective_last)
    if new_lines:
        new_last = max(rid for rid, _ in rows if rid > effective_last)

    return new_lines, new_last, max_id


def collect_and_push() -> int:
    log(f"[info] FA agent start server_id={SERVER_ID}")

    # --- Collection ---
    dmesg_hw = run_cmd('dmesg | grep -i "Hardware Error"')
    sel_raw = run_cmd("ipmitool sel elist")
    sdr_temp = run_cmd("ipmitool sdr type Temperature")
    sdr_fan = run_cmd("ipmitool sdr type Fan")
    sdr_volt = run_cmd("ipmitool sdr type Voltage")
    server_model = run_cmd("dmidecode -s system-product-name") or "Unknown"

    # --- Incremental SEL ---
    last_id = read_last_record_id(LAST_ID_FILE)
    rows = parse_sel_lines(sel_raw)
    new_sel, new_last_id, max_id = filter_incremental_sel(rows, last_id)
    log(
        f"[info] SEL last_id={last_id} parsed={len(rows)} "
        f"new={len(new_sel)} max_id={max_id}"
    )

    # Bundle context logs with new SEL lines for the center
    sel_logs: list[str] = []
    if dmesg_hw:
        sel_logs.extend(dmesg_hw.splitlines())
    sel_logs.extend(new_sel)
    for block, label in (
        (sdr_temp, "SDR Temperature"),
        (sdr_fan, "SDR Fan"),
        (sdr_volt, "SDR Voltage"),
    ):
        if block:
            sel_logs.append(f"### {label}")
            sel_logs.extend(block.splitlines())

    if not sel_logs:
        log("[info] nothing new to push; exit")
        return 0

    payload = {
        "server_id": SERVER_ID,
        "server_model": server_model,
        "sel_logs": sel_logs,
    }

    try:
        resp = requests.post(CENTER_URL, json=payload, timeout=_HTTP_TIMEOUT)
        resp.raise_for_status()
        log(f"[info] push ok status={resp.status_code} lines={len(sel_logs)}")
    except requests.RequestException as exc:
        log(f"[error] push failed: {exc}")
        return 1

    # Persist cursor only after successful push, and only when SEL advanced
    if new_sel or (max_id < last_id and rows):
        # After clear+full re-read, advance to current max
        write_last_record_id(LAST_ID_FILE, new_last_id if new_sel else max_id)
        log(f"[info] updated LAST_RECORD_ID -> {new_last_id if new_sel else max_id}")

    log("[info] FA agent done")
    return 0


def main() -> None:
    try:
        sys.exit(collect_and_push())
    except Exception as exc:
        log(f"[fatal] unhandled error: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
