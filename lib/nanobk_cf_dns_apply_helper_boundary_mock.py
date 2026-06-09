#!/usr/bin/env python3
"""
NanoBK DNS Apply Helper Boundary Mock — Fake-only test prototype.

Hidden/test-only prototype proving the low-level DNS apply helper can be
invoked only after strict fake transport preflight.

NOT imported by bin/nanobk. NOT public CLI. NOT real DNS apply.
Requires NANOBK_CF_DNS_FAKE_TRANSPORT. Fails closed if missing.
Never calls Cloudflare. Never performs real DNS mutation.

Usage:
    NANOBK_CF_DNS_FAKE_TRANSPORT=/path/to/fixture.json \
      python3 lib/nanobk_cf_dns_apply_helper_boundary_mock.py

The module creates temp fake profile/api-env, invokes the low-level helper
via subprocess with sterile env, captures stdout/stderr, parses helper JSON,
and outputs only a beginner-safe masked summary.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

# ── Constants ────────────────────────────────────────────────────────────────

FAKE_TRANSPORT_ENV = "NANOBK_CF_DNS_FAKE_TRANSPORT"

_SAFE_ERROR_MSG = (
    "NanoBK DNS Apply helper boundary mock is fake-transport-only.\n"
    "A valid local fake transport fixture is required.\n"
    "No DNS changes were made."
)

# Allowed top-level keys in helper JSON output
_ALLOWED_HELPER_KEYS = {"ok", "dryRun", "checkMode", "actions", "results"}

# Allowed keys in action entries
_ALLOWED_ACTION_KEYS = {
    "recordType", "name", "plannedContent", "action", "message",
    "existingContent",
}

# Allowed keys in result entries
_ALLOWED_RESULT_KEYS = {
    "recordType", "name", "action", "success", "message", "recordId",
}

# Allowed action values
_ALLOWED_ACTIONS = {"noop", "create", "update", "fail_conflict", "skip"}

# Allowed record types
_ALLOWED_RECORD_TYPES = {"A", "AAAA"}

# Required keys in calls artifact entries
_CALLS_ENTRY_REQUIRED_KEYS = {"method", "key", "endpoint"}

# Status buckets
_STATUS_APPLIED = "applied"
_STATUS_UNCERTAIN = "uncertain"
_STATUS_PARTIAL = "partial"
_STATUS_FAILED = "failed"

# ── Fake transport preflight ─────────────────────────────────────────────────


def _safe_error() -> int:
    """Print safe error and return nonzero."""
    print(_SAFE_ERROR_MSG, file=sys.stderr)
    return 1


def validate_fake_transport() -> Path | None:
    """Validate fake transport env var and fixture. Returns Path or None."""
    val = os.environ.get(FAKE_TRANSPORT_ENV, "")
    if not val:
        return None

    path = Path(val)

    if not path.exists():
        return None

    if not path.is_file():
        return None

    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return None

    if not isinstance(data, dict):
        return None

    return path


# ── Temp fixture creation ────────────────────────────────────────────────────

_FAKE_PROFILE = {
    "zoneName": "example.com",
    "nodePrefix": "node",
    "ipv4": "203.0.113.10",
    "ipv6": "2001:db8::10",
    "defaultProxied": False,
}

_FAKE_API_ENV = (
    'CF_API_TOKEN="fake-token-do-not-use"\n'
    'CF_ZONE_ID="fake-zone-id-12345"\n'
    'CF_ZONE_NAME=example.com\n'
)


def create_temp_fixtures(tmpdir: Path) -> tuple[Path, Path]:
    """Create temp fake profile and api-env. Returns (profile_path, api_env_path)."""
    profile_path = tmpdir / "fake-profile.json"
    api_env_path = tmpdir / "fake-api.env"

    with open(profile_path, "w", encoding="utf-8") as f:
        json.dump(_FAKE_PROFILE, f, indent=2)

    with open(api_env_path, "w", encoding="utf-8") as f:
        f.write(_FAKE_API_ENV)
    os.chmod(api_env_path, 0o600)

    return profile_path, api_env_path


# ── Sterile env ──────────────────────────────────────────────────────────────

def build_sterile_env(fake_transport: Path) -> dict[str, str]:
    """Build a sterile environment for helper invocation."""
    return {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "LANG": "C",
        "LC_ALL": "C",
        "NANOBK_CF_DNS_FAKE_TRANSPORT": str(fake_transport),
        "NANOBK_TEST_TMPDIR": str(fake_transport.parent),
    }


# ── Helper invocation ────────────────────────────────────────────────────────

def run_helper(
    repo_root: Path,
    profile_path: Path,
    api_env_path: Path,
    fake_transport: Path,
    tmpdir: Path,
) -> tuple[int, str, str]:
    """Invoke the low-level helper via subprocess. Returns (returncode, stdout, stderr)."""
    helper_path = repo_root / "lib" / "nanobk_cf_dns_apply.py"

    cmd = [
        sys.executable,
        str(helper_path),
        "--profile", str(profile_path),
        "--api-env", str(api_env_path),
        "--yes",
        "--json",
    ]

    env = build_sterile_env(fake_transport)

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
            shell=False,
            cwd=str(tmpdir),
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "timeout"
    except OSError as e:
        return -1, "", f"os error: {type(e).__name__}"


# ── Output parsing ───────────────────────────────────────────────────────────

def _iter_json_objects(text: str) -> list[dict]:
    """Parse all complete JSON dict objects from text using raw_decode.

    Returns a list of valid dict objects that pass top-level key allowlist.
    Strict mode: rejects any trailing non-whitespace after the last object.
    Stops on first parse error or non-dict object.
    """
    decoder = json.JSONDecoder()
    idx = 0
    objs: list[dict] = []
    text = text.strip()

    while idx < len(text):
        # Skip whitespace between objects
        while idx < len(text) and text[idx].isspace():
            idx += 1
        if idx >= len(text):
            break

        try:
            obj, next_idx = decoder.raw_decode(text, idx)
        except json.JSONDecodeError:
            return []

        if not isinstance(obj, dict):
            return []

        # Top-level key allowlist
        if set(obj.keys()) - _ALLOWED_HELPER_KEYS:
            return []

        objs.append(obj)
        idx = next_idx

    # Strict: reject trailing non-whitespace
    # (idx should have consumed all non-whitespace text)
    remaining = text[idx:].strip()
    if remaining:
        return []

    return objs


def parse_helper_json(stdout: str) -> dict | None:
    """Parse helper JSON output. Returns dict or None on failure.

    The low-level helper may output multiple JSON objects (plan + results).
    We collect all valid JSON dict objects and prefer the last one that
    contains a non-empty results list (the final execution result).
    Falls back to the last valid object if none have results.
    """
    objs = _iter_json_objects(stdout)
    if not objs:
        return None

    # Prefer the last object with non-empty results (final execution result)
    for obj in reversed(objs):
        results = obj.get("results")
        if isinstance(results, list) and len(results) > 0:
            return obj

    # Fall back to last valid object
    return objs[-1]


def validate_helper_schema(data: dict) -> bool:
    """Validate helper JSON schema strictly.

    Top-level:
    - Only _ALLOWED_HELPER_KEYS.
    - actions, if present, must be list.
    - results, if present, must be list.

    Action entries:
    - Must be dict.
    - Keys subset of _ALLOWED_ACTION_KEYS.
    - recordType, if present, must be A or AAAA.
    - action, if present, must be in _ALLOWED_ACTIONS.

    Result entries:
    - Must be dict.
    - Keys subset of _ALLOWED_RESULT_KEYS.
    - recordType, if present, must be A or AAAA.
    - action, if present, must be in _ALLOWED_ACTIONS.
    - success, if present, must be bool.
    """
    # Top-level keys
    unexpected = set(data.keys()) - _ALLOWED_HELPER_KEYS
    if unexpected:
        return False

    # Validate actions
    actions = data.get("actions")
    if actions is not None:
        if not isinstance(actions, list):
            return False
        for entry in actions:
            if not isinstance(entry, dict):
                return False
            entry_keys = set(entry.keys())
            if not entry_keys.issubset(_ALLOWED_ACTION_KEYS):
                return False
            rtype = entry.get("recordType")
            if rtype is not None and rtype not in _ALLOWED_RECORD_TYPES:
                return False
            act = entry.get("action")
            if act is not None and act not in _ALLOWED_ACTIONS:
                return False

    # Validate results
    results = data.get("results")
    if results is not None:
        if not isinstance(results, list):
            return False
        for entry in results:
            if not isinstance(entry, dict):
                return False
            entry_keys = set(entry.keys())
            if not entry_keys.issubset(_ALLOWED_RESULT_KEYS):
                return False
            rtype = entry.get("recordType")
            if rtype is not None and rtype not in _ALLOWED_RECORD_TYPES:
                return False
            act = entry.get("action")
            if act is not None and act not in _ALLOWED_ACTIONS:
                return False
            success = entry.get("success")
            if success is not None and not isinstance(success, bool):
                return False

    return True


def check_calls_artifact(fake_transport: Path) -> bool:
    """Check if the fake transport fixture has a calls artifact proving usage.

    Requirements (all must pass):
    1. _calls_file must be configured in transport fixture.
    2. Calls file must exist.
    3. Calls file must parse as non-empty list.
    4. Each call entry must be a dict.
    5. At least one entry must have method/key/endpoint keys.
    6. method must be one of GET/POST/PATCH.
    7. key must be a non-empty string.

    Does not print calls file path or content.
    """
    try:
        with open(fake_transport, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return False

    calls_file = data.get("_calls_file")
    if not calls_file:
        return False

    calls_path = Path(calls_file)
    if not calls_path.exists():
        return False

    try:
        with open(calls_path, "r", encoding="utf-8") as f:
            content = f.read().strip()
    except OSError:
        return False

    if not content:
        return False

    try:
        calls = json.loads(content)
    except (json.JSONDecodeError, ValueError):
        return False

    if not isinstance(calls, list) or len(calls) == 0:
        return False

    # Validate at least one entry has required keys
    found_valid = False
    for entry in calls:
        if not isinstance(entry, dict):
            return False
        entry_keys = set(entry.keys())
        if _CALLS_ENTRY_REQUIRED_KEYS.issubset(entry_keys):
            method = entry.get("method", "")
            key = entry.get("key", "")
            if method in ("GET", "POST", "PATCH") and isinstance(key, str) and key:
                found_valid = True

    return found_valid


def derive_safe_summary(helper_json: dict) -> str:
    """Derive a beginner-safe summary from helper JSON."""
    actions = helper_json.get("actions", [])
    results = helper_json.get("results", [])

    # Count actions by type
    action_counts = {"create": 0, "update": 0, "noop": 0, "fail_conflict": 0, "skip": 0}
    record_types = {"A": 0, "AAAA": 0}

    for action in actions:
        act = action.get("action", "unknown")
        if act in action_counts:
            action_counts[act] += 1
        rtype = action.get("recordType", "")
        if rtype in record_types:
            record_types[rtype] += 1

    # Count results
    result_success = sum(1 for r in results if r.get("success"))
    result_failed = sum(1 for r in results if not r.get("success"))

    # Determine status
    has_conflicts = action_counts["fail_conflict"] > 0
    has_failures = result_failed > 0
    has_mutations = action_counts["create"] > 0 or action_counts["update"] > 0

    if has_conflicts:
        status = _STATUS_FAILED
    elif has_failures:
        status = _STATUS_PARTIAL
    elif has_mutations and result_success > 0:
        status = _STATUS_APPLIED
    elif has_mutations:
        status = _STATUS_UNCERTAIN
    else:
        status = _STATUS_APPLIED

    # Build output
    lines = [
        "NanoBK DNS Apply Helper Boundary — Fake-only Summary",
        f"Status: {status}",
        "",
        "Actions:",
        f"  Create: {action_counts['create']}",
        f"  Update: {action_counts['update']}",
        f"  No change: {action_counts['noop']}",
        f"  Conflict: {action_counts['fail_conflict']}",
        f"  Failed: {result_failed}",
        "",
        "Record types:",
        f"  A: {record_types['A']}",
        f"  AAAA: {record_types['AAAA']}",
        "",
        "Fake transport:",
        "  Used: yes",
        "",
        "Test mode: fake transport only.",
        "No live Cloudflare verification was performed.",
        "No DNS changes were made outside fake transport.",
    ]

    return "\n".join(lines) + "\n"


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    # Fake transport preflight
    fake_transport = validate_fake_transport()
    if fake_transport is None:
        return _safe_error()

    # Find repo root
    repo_root = Path(__file__).resolve().parents[1]

    # Create temp fixtures
    tmpdir = Path(tempfile.mkdtemp(prefix="nanobk-helper-boundary-"))
    try:
        profile_path, api_env_path = create_temp_fixtures(tmpdir)

        # Add calls artifact to fake transport
        calls_file = tmpdir / "fake-calls.json"
        try:
            with open(fake_transport, "r", encoding="utf-8") as f:
                transport_data = json.load(f)
            transport_data["_calls_file"] = str(calls_file)
            transport_with_calls = tmpdir / "transport-with-calls.json"
            with open(transport_with_calls, "w", encoding="utf-8") as f:
                json.dump(transport_data, f)
        except (json.JSONDecodeError, OSError):
            return _safe_error()

        # Invoke helper
        returncode, stdout, stderr = run_helper(
            repo_root, profile_path, api_env_path, transport_with_calls, tmpdir
        )

        # Check for timeout
        if returncode == -1:
            print(_SAFE_ERROR_MSG, file=sys.stderr)
            return 1

        # Strict stderr gate — fail closed if stderr is non-empty
        if stderr.strip():
            print(_SAFE_ERROR_MSG, file=sys.stderr)
            return 1

        # Parse helper JSON — allow nonzero exit when stdout is valid JSON.
        # The low-level helper returns exit 1 on conflicts (expected behavior).
        # We only fail closed if stdout is not valid JSON or has unexpected schema.
        helper_json = parse_helper_json(stdout)
        if helper_json is None:
            print(_SAFE_ERROR_MSG, file=sys.stderr)
            return 1

        # Strict schema validation — check actions[] and results[] internals
        if not validate_helper_schema(helper_json):
            print(_SAFE_ERROR_MSG, file=sys.stderr)
            return 1

        # Check calls artifact
        if not check_calls_artifact(transport_with_calls):
            print(_SAFE_ERROR_MSG, file=sys.stderr)
            return 1

        # Derive and print safe summary
        summary = derive_safe_summary(helper_json)
        print(summary, end="")
        return 0

    finally:
        # Cleanup temp dir
        import shutil
        shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
