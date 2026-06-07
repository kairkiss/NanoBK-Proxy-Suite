#!/usr/bin/env python3
"""
NanoBK Cloudflare Read-Only Zone Discovery

Lists Cloudflare zones using a GET-only API call.
Read-only: no DNS mutation, no POST/PATCH/DELETE.

Usage:
    python3 lib/nanobk_cf_zones.py list --api-env /path/to/cloudflare-api.env [--json]

Test hook:
    NANOBK_CF_ZONES_FAKE_RESPONSE=/path/to/fixture.json
"""

import argparse
import json
import os
import stat
import sys
import urllib.request
import urllib.error


# ── Env parser ─────────────────────────────────────────────────────────────

ALLOWED_KEYS = {"CF_API_TOKEN", "CF_ZONE_ID", "CF_ZONE_NAME"}


def parse_env_file(path):
    """Parse a KEY=value env file. Returns dict of allowed keys only.

    Rules:
    - Only ALLOWED_KEYS are accepted.
    - File must be chmod 600 (owner read/write only).
    - No shell execution, no eval, no source.
    - Values are treated literally (no expansion).
    - Lines starting with # are comments.
    - Empty lines are skipped.
    """
    if not os.path.isfile(path):
        raise FileNotFoundError(f"Env file not found: {path}")

    # Check permissions
    st = os.stat(path)
    mode = stat.S_IMODE(st.st_mode)
    # Check: no group/other bits set (must be 0o600 or stricter like 0o400)
    if mode & 0o077:
        raise PermissionError(
            f"Insecure file permissions: {oct(mode)}. "
            f"Expected 0o600 (chmod 600)."
        )

    result = {}
    with open(path, "r") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip()
            # Strip surrounding quotes (literal, no shell eval)
            if len(value) >= 2 and (
                (value[0] == '"' and value[-1] == '"')
                or (value[0] == "'" and value[-1] == "'")
            ):
                value = value[1:-1]
            if key not in ALLOWED_KEYS:
                raise ValueError(
                    f"Unsupported key '{key}' at line {lineno}. "
                    f"Allowed: {', '.join(sorted(ALLOWED_KEYS))}"
                )
            result[key] = value

    if "CF_API_TOKEN" not in result:
        raise ValueError("Missing required key: CF_API_TOKEN")

    return result


# ── Redaction helpers ───────────────────────────────────────────────────────

def mask_domain(name):
    """Mask middle of domain for safe display.

    example.com -> ex***le.com
    """
    if not name or "." not in name:
        return "***"
    parts = name.split(".", 1)
    prefix = parts[0]
    suffix = parts[1]
    if len(prefix) <= 2:
        return f"{prefix[0]}***.{suffix}"
    return f"{prefix[:2]}***{prefix[-1]}.{suffix}"


def redact_id(zone_id):
    """Show first 4 and last 4 chars of zone ID."""
    if not zone_id or len(zone_id) <= 8:
        return "***"
    return f"{zone_id[:4]}…{zone_id[-4:]}"


# ── Transport ───────────────────────────────────────────────────────────────

def fetch_zones_real(token):
    """Fetch zones from Cloudflare API (GET-only)."""
    req = urllib.request.Request(
        "https://api.cloudflare.com/client/v4/zones?per_page=50",
        method="GET",
    )
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Cloudflare API error: HTTP {e.code}") from None
    except urllib.error.URLError as e:
        raise RuntimeError(f"Cloudflare API connection error: {e.reason}") from None

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        raise RuntimeError("Cloudflare API returned invalid JSON") from None

    if not data.get("success", False):
        errors = data.get("errors", [])
        msg = "; ".join(str(e.get("message", "unknown")) for e in errors) or "unknown error"
        raise RuntimeError(f"Cloudflare API error: {msg}")

    return data.get("result", [])


def fetch_zones_fake(fake_path):
    """Load fake response from fixture file."""
    with open(fake_path, "r") as f:
        data = json.load(f)
    if not data.get("success", False):
        errors = data.get("errors", [])
        msg = "; ".join(str(e.get("message", "unknown")) for e in errors) or "unknown error"
        raise RuntimeError(f"Cloudflare API error: {msg}")
    return data.get("result", [])


def fetch_zones(token):
    """Fetch zones using real or fake transport."""
    fake_path = os.environ.get("NANOBK_CF_ZONES_FAKE_RESPONSE")
    if fake_path:
        return fetch_zones_fake(fake_path)
    return fetch_zones_real(token)


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(zones):
    """Print beginner-safe text summary."""
    print()
    print(f"  Cloudflare zones discovered: {len(zones)}")
    print()
    if zones:
        for i, zone in enumerate(zones, 1):
            name = zone.get("name", "unknown")
            print(f"  {i}. {mask_domain(name)}")
        print()
    print("  Read-only discovery only. No DNS records were changed.")
    print()


def output_json(zones):
    """Print sanitized JSON summary."""
    result = {
        "ok": True,
        "count": len(zones),
        "zones": [
            {
                "name": mask_domain(z.get("name", "")),
                "id_redacted": redact_id(z.get("id", "")),
            }
            for z in zones
        ],
        "mutation": False,
    }
    print(json.dumps(result, indent=2))


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "mutation": False}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Cloudflare Read-Only Zone Discovery"
    )
    sub = parser.add_subparsers(dest="command")

    list_parser = sub.add_parser("list", help="List Cloudflare zones (read-only)")
    list_parser.add_argument("--api-env", required=True, help="Path to api-env file")
    list_parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.command != "list":
        parser.print_help()
        sys.exit(1)

    # Parse env
    try:
        env = parse_env_file(args.api_env)
    except (FileNotFoundError, PermissionError, ValueError) as e:
        output_error(str(e), args.json)
        sys.exit(1)

    token = env["CF_API_TOKEN"]

    # Fetch zones
    try:
        zones = fetch_zones(token)
    except RuntimeError as e:
        output_error(str(e), args.json)
        sys.exit(1)

    # Output
    if args.json:
        output_json(zones)
    else:
        output_text(zones)


if __name__ == "__main__":
    main()
