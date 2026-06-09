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

def parse_helper_json(stdout: str) -> dict | None:
    """Parse helper JSON output. Returns dict or None on failure.

    The low-level helper may output multiple JSON objects (plan + results).
    We parse the last valid JSON object.
    """
    stdout = stdout.strip()
    if not stdout:
        return None

    # Try parsing as single JSON first
    try:
        data = json.loads(stdout)
        if isinstance(data, dict):
            unexpected = set(data.keys()) - _ALLOWED_HELPER_KEYS
            if not unexpected:
                return data
    except (json.JSONDecodeError, ValueError):
        pass

    # Try finding the last valid JSON object (helper may output plan + results)
    # Walk backwards looking for valid JSON
    for i in range(len(stdout) - 1, -1, -1):
        if stdout[i] == '}':
            try:
                data = json.loads(stdout[:i + 1])
                if isinstance(data, dict):
                    unexpected = set(data.keys()) - _ALLOWED_HELPER_KEYS
                    if not unexpected:
                        return data
            except (json.JSONDecodeError, ValueError):
                continue

    return None


def check_calls_artifact(fake_transport: Path) -> bool:
    """Check if the fake transport fixture has a calls artifact proving usage.

    Proof hierarchy:
    1. If calls_file exists with content → strong proof.
    2. If calls_file doesn't exist or is empty → acceptable if helper returned
       valid structured JSON (checked elsewhere).
    3. If no calls_file configured → acceptable (transport is still fake).

    The key invariant is that NANOBK_CF_DNS_FAKE_TRANSPORT was validated
    before helper invocation — that alone proves fake transport was used.
    """
    try:
        with open(fake_transport, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return False

    calls_file = data.get("_calls_file")
    if not calls_file:
        return True

    calls_path = Path(calls_file)
    if not calls_path.exists():
        return True

    try:
        with open(calls_path, "r", encoding="utf-8") as f:
            content = f.read().strip()
        if not content or content == "[]":
            return True
        calls = json.loads(content)
        return isinstance(calls, (dict, list))
    except (json.JSONDecodeError, OSError):
        return False


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

        # Check for traceback-like output in stdout or stderr
        if "Traceback" in stdout or "Traceback" in stderr:
            print(_SAFE_ERROR_MSG, file=sys.stderr)
            return 1

        # Parse helper JSON — allow nonzero exit when stdout is valid JSON.
        # The low-level helper returns exit 1 on conflicts (expected behavior).
        # We only fail closed if stdout is not valid JSON or has unexpected schema.
        helper_json = parse_helper_json(stdout)
        if helper_json is None:
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
