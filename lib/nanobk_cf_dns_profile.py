#!/usr/bin/env python3
"""
NanoBK DNS Profile Preview and Generate

Preview: builds and validates an in-memory DNS profile candidate (no file write).
Generate: writes DNS profile JSON to allowed temp/test output path only.
No Cloudflare calls. No DNS apply/check. No DNS mutation.

Usage:
    python3 lib/nanobk_cf_dns_profile.py preview --zone DOMAIN --node NODE --ipv4 VALUE [--ipv6 VALUE] [--json] [--allow-documentation-ips]
    python3 lib/nanobk_cf_dns_profile.py generate --zone DOMAIN --node NODE --ipv4 VALUE [--ipv6 VALUE] --output PATH --yes [--json] [--allow-documentation-ips]
"""

import argparse
import fcntl
import ipaddress
import json
import os
import re
import stat
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nanobk_cf_dns_targets import mask_domain


# ── Constants ───────────────────────────────────────────────────────────────

_DNS_LABEL_RE = re.compile(r"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$")

_IPV4_DOC_RANGES = [
    ipaddress.IPv4Network("192.0.2.0/24"),
    ipaddress.IPv4Network("198.51.100.0/24"),
    ipaddress.IPv4Network("203.0.113.0/24"),
]

_IPV6_DOC_RANGES = [
    ipaddress.IPv6Network("2001:db8::/32"),
]

_SECRET_SUBSTRINGS = ["token", "secret", "private", "password", "key", "cf_api_token"]
_ALLOWED_KEYS = {"zoneId"}


# ── Validation ──────────────────────────────────────────────────────────────

def validate_zone(zone):
    """Validate zone/domain. Returns error string or None."""
    if not zone:
        return "zone is required"
    if "://" in zone:
        return "zone must be a domain name, not a URL"
    if "/" in zone:
        return "zone must not contain slashes"
    if " " in zone:
        return "zone must not contain spaces"
    if "*" in zone:
        return "zone must not contain wildcards"
    if len(zone) > 253:
        return "zone is too long"
    labels = zone.split(".")
    if len(labels) < 2:
        return "zone must have at least two labels"
    for label in labels:
        if not label:
            return "zone must not have empty labels"
        if not _DNS_LABEL_RE.match(label):
            return "invalid zone label"
    return None


def validate_node(node):
    """Validate node prefix. Returns error string or None."""
    if not node:
        return "node is required"
    if "/" in node:
        return "node must not contain slashes"
    if " " in node:
        return "node must not contain spaces"
    if "*" in node:
        return "node must not contain wildcards"
    if "." in node:
        return "node must be a single label (no dots)"
    if len(node) > 63:
        return "node is too long"
    if not _DNS_LABEL_RE.match(node):
        return "invalid node label"
    return None


def validate_ipv4(addr, allow_docs=False):
    """Validate IPv4 address. Returns error string or None."""
    if not addr:
        return "ipv4 is required"
    try:
        parsed = ipaddress.IPv4Address(addr)
    except (ipaddress.AddressValueError, ValueError):
        return "invalid IPv4"
    if parsed.is_loopback:
        return "loopback IPv4 is not allowed"
    if parsed.is_multicast:
        return "multicast IPv4 is not allowed"
    if parsed.is_reserved:
        return "reserved IPv4 is not allowed"
    if parsed.is_link_local:
        return "link-local IPv4 is not allowed"
    if parsed.is_unspecified:
        return "unspecified IPv4 is not allowed"
    # Check documentation ranges
    for net in _IPV4_DOC_RANGES:
        if parsed in net:
            if not allow_docs:
                return "documentation IPv4 is allowed only in test mode (--allow-documentation-ips)"
            return None
    # Check private
    if parsed.is_private:
        return "private IPv4 is not allowed"
    return None


def validate_ipv6(addr, allow_docs=False):
    """Validate IPv6 address. Returns error string or None."""
    if not addr:
        return None  # IPv6 is optional
    try:
        parsed = ipaddress.IPv6Address(addr)
    except (ipaddress.AddressValueError, ValueError):
        return "invalid IPv6"
    if parsed.is_loopback:
        return "loopback IPv6 is not allowed"
    if parsed.is_multicast:
        return "multicast IPv6 is not allowed"
    if parsed.is_reserved:
        return "reserved IPv6 is not allowed"
    if parsed.is_link_local:
        return "link-local IPv6 is not allowed"
    if parsed.is_unspecified:
        return "unspecified IPv6 is not allowed"
    # Check documentation ranges
    for net in _IPV6_DOC_RANGES:
        if parsed in net:
            if not allow_docs:
                return "documentation IPv6 is allowed only in test mode (--allow-documentation-ips)"
            return None
    # Check ULA / private
    if parsed.is_private:
        return "private IPv6 is not allowed"
    return None


def mask_ipv4(addr):
    """Mask IPv4: 203.0.113.10 -> 203.0.113.xxx"""
    parts = addr.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.{parts[2]}.xxx"
    return "xxx.xxx.xxx.xxx"


def mask_ipv6(addr):
    """Mask IPv6: 2001:db8::10 -> 2001:db8:…"""
    try:
        parsed = ipaddress.IPv6Address(addr)
        compressed = parsed.compressed
        if "::" in compressed:
            leading = compressed.split("::")[0]
        else:
            leading = compressed
        groups = [g for g in leading.split(":") if g]
        if len(groups) >= 2:
            return f"{groups[0]}:{groups[1]}:…"
        elif len(groups) == 1:
            return f"{groups[0]}:…"
        else:
            return "…"
    except (ipaddress.AddressValueError, ValueError):
        return "…"


def mask_hostname(node, zone):
    """Mask full hostname: proxy.example.com -> proxy.ex***e.com"""
    return f"{node}.{mask_domain(zone)}"


# ── Profile preview logic ───────────────────────────────────────────────────

def build_profile_candidate(zone, node, ipv4, ipv6=None):
    """Build an in-memory profile candidate dict."""
    candidate = {
        "zoneName": zone,
        "nodePrefix": node,
        "defaultProxied": False,
        "reserved": {
            "panelPrefix": "panel",
            "nanokPrefix": "nanok",
            "nanobPrefix": "nanob",
        },
    }
    if ipv4:
        candidate["ipv4"] = ipv4
    if ipv6:
        candidate["ipv6"] = ipv6
    return candidate


def validate_profile_candidate(candidate, allow_docs=False):
    """Validate profile candidate. Returns (ok, errors_list)."""
    errors = []

    zone = candidate.get("zoneName", "")
    zone_err = validate_zone(zone)
    if zone_err:
        errors.append(zone_err)

    node = candidate.get("nodePrefix", "")
    node_err = validate_node(node)
    if node_err:
        errors.append(node_err)

    ipv4 = candidate.get("ipv4")
    ipv6 = candidate.get("ipv6")

    if not ipv4 and not ipv6:
        errors.append("at least one of ipv4 or ipv6 is required")
    else:
        if ipv4:
            ipv4_err = validate_ipv4(ipv4, allow_docs)
            if ipv4_err:
                errors.append(ipv4_err)
        if ipv6:
            ipv6_err = validate_ipv6(ipv6, allow_docs)
            if ipv6_err:
                errors.append(ipv6_err)

    proxied = candidate.get("defaultProxied")
    if proxied is not None and proxied is not False:
        errors.append("defaultProxied must be false or omitted")

    # Check for secret-like keys
    for key in candidate:
        key_lower = key.lower()
        for secret in _SECRET_SUBSTRINGS:
            if secret in key_lower and key not in _ALLOWED_KEYS:
                errors.append(f"secret-like field rejected: {key}")
                break

    return len(errors) == 0, errors


def run_preview(zone, node, ipv4, ipv6, allow_docs):
    """Run profile preview. Returns result dict."""
    # Validate inputs
    zone_err = validate_zone(zone)
    if zone_err:
        return {"ok": False, "error": zone_err, "mutation": False,
                "profile_written": False, "profile_write_mode": "preview",
                "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}

    node_err = validate_node(node)
    if node_err:
        return {"ok": False, "error": node_err, "mutation": False,
                "profile_written": False, "profile_write_mode": "preview",
                "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}

    if not ipv4:
        return {"ok": False, "error": "ipv4 is required", "mutation": False,
                "profile_written": False, "profile_write_mode": "preview",
                "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}

    # Validate IPs
    ipv4_err = validate_ipv4(ipv4, allow_docs)
    if ipv4_err:
        return {"ok": False, "error": ipv4_err, "mutation": False,
                "profile_written": False, "profile_write_mode": "preview",
                "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}

    if ipv6:
        ipv6_err = validate_ipv6(ipv6, allow_docs)
        if ipv6_err:
            return {"ok": False, "error": ipv6_err, "mutation": False,
                    "profile_written": False, "profile_write_mode": "preview",
                    "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}

    # Build candidate
    candidate = build_profile_candidate(zone, node, ipv4, ipv6)

    # Validate candidate
    valid, errors = validate_profile_candidate(candidate, allow_docs)

    # Build record preview
    record_preview = []
    if ipv4:
        record_preview.append({
            "type": "A",
            "value_redacted": mask_ipv4(ipv4),
            "proxied": False,
        })
    if ipv6:
        record_preview.append({
            "type": "AAAA",
            "value_redacted": mask_ipv6(ipv6),
            "proxied": False,
        })

    # Build IP preview
    ip_preview = {}
    if ipv4:
        ip_preview["ipv4_redacted"] = mask_ipv4(ipv4)
    if ipv6:
        ip_preview["ipv6_redacted"] = mask_ipv6(ipv6)

    return {
        "ok": True,
        "mutation": False,
        "profile_written": False,
        "profile_write_mode": "preview",
        "dns_mutation": False,
        "cloudflare_mutation": False,
        "dns_apply": False,
        "zone_redacted": mask_domain(zone),
        "node": node,
        "hostname_redacted": mask_hostname(node, zone),
        "ip_preview": ip_preview,
        "profile_valid": valid,
        "validation_status": "passed" if valid else "failed",
        "validation_errors": errors if errors else [],
        "record_preview": record_preview,
        "test_mode": allow_docs,
    }


# ── Output path validation ──────────────────────────────────────────────────

BLOCKED_PREFIXES = ["/etc", "/root", "/home"]


def get_allowed_temp_root():
    """Get the allowed temp root directory."""
    env_tmpdir = os.environ.get("NANOBK_TEST_TMPDIR")
    if env_tmpdir:
        return os.path.realpath(env_tmpdir)
    return os.path.realpath(tempfile.gettempdir())


def validate_output_path(output_path):
    """Validate output path against allowlist. Returns error string or None."""
    if not output_path:
        return "output path is required"

    # Must be absolute
    if not os.path.isabs(output_path):
        return "output path must be absolute"

    # Check blocked prefixes on both original and resolved paths
    # (macOS /etc resolves to /private/etc)
    try:
        resolved = os.path.realpath(output_path)
    except (OSError, ValueError):
        return "cannot resolve output path"

    for prefix in BLOCKED_PREFIXES:
        if output_path.startswith(prefix) or resolved.startswith(prefix):
            return "production profile path is not supported in v2.1.15"

    # Check allowed temp root
    allowed_root = get_allowed_temp_root()
    if not resolved.startswith(allowed_root):
        return "output path must be under temp root"

    # Check if final path is a symlink
    if os.path.islink(output_path):
        return "output path symlink is not allowed"

    # Check if parent is a symlink
    parent = os.path.dirname(output_path)
    if os.path.islink(parent):
        return "output path parent symlink is not allowed"

    # Check if file already exists
    if os.path.exists(output_path):
        return "output file already exists"

    return None


def redact_output_path(output_path):
    """Redact output path for display."""
    allowed_root = get_allowed_temp_root()
    try:
        resolved = os.path.realpath(output_path)
        if resolved.startswith(allowed_root):
            rel = resolved[len(allowed_root):].lstrip("/")
            return f"[temp]/{rel}"
    except (OSError, ValueError):
        pass
    return "[temp]/profile.json"


# ── Atomic file write ───────────────────────────────────────────────────────

def write_profile_atomic(candidate, output_path):
    """Write profile JSON atomically. Returns error string or None."""
    parent_dir = os.path.dirname(output_path)

    # Create parent directory if needed (restrictive permissions)
    try:
        os.makedirs(parent_dir, mode=0o700, exist_ok=True)
    except OSError as e:
        return f"cannot create parent directory: {e}"

    # Serialize JSON
    profile_json = json.dumps(candidate, indent=2, sort_keys=True) + "\n"
    profile_bytes = profile_json.encode("utf-8")

    # Write to temp file with exclusive creation
    tmp_fd = None
    tmp_path = None
    try:
        tmp_fd, tmp_path = tempfile.mkstemp(
            dir=parent_dir, prefix=".nanobk-profile-", suffix=".tmp"
        )
        os.write(tmp_fd, profile_bytes)
        os.fsync(tmp_fd)
        os.close(tmp_fd)
        tmp_fd = None

        # chmod 600
        os.chmod(tmp_path, 0o600)

        # Hard-link to final path (avoids overwrite)
        try:
            os.link(tmp_path, output_path)
            os.unlink(tmp_path)
            tmp_path = None
        except OSError:
            # Hard link not supported; fall back (but we already checked existence)
            os.rename(tmp_path, output_path)
            tmp_path = None

    except OSError as e:
        # Clean up on failure
        if tmp_fd is not None:
            try:
                os.close(tmp_fd)
            except OSError:
                pass
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        return f"write failed: {e}"

    return None


def verify_written_profile(output_path):
    """Verify written profile file. Returns error string or None."""
    # Check mode
    try:
        st = os.stat(output_path)
        mode = stat.S_IMODE(st.st_mode)
        if mode != 0o600:
            return f"unexpected file mode: {oct(mode)}"
    except OSError as e:
        return f"cannot stat output file: {e}"

    # Re-read and validate
    try:
        with open(output_path, "r") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        return f"written file is not valid JSON: {e}"

    # Basic validation
    if not isinstance(data, dict):
        return "written file is not a JSON object"
    if "zoneName" not in data:
        return "written file missing zoneName"
    if "nodePrefix" not in data:
        return "written file missing nodePrefix"

    return None


# ── Generate logic ──────────────────────────────────────────────────────────

def run_generate(zone, node, ipv4, ipv6, output_path, allow_docs):
    """Run profile generate. Returns result dict."""
    error_base = {"mutation": False, "local_file_mutation": False,
                  "dns_mutation": False, "cloudflare_mutation": False,
                  "dns_apply": False, "profile_written": False,
                  "profile_write_mode": "temp_output"}

    # Validate inputs
    zone_err = validate_zone(zone)
    if zone_err:
        return {"ok": False, "error": zone_err, **error_base}

    node_err = validate_node(node)
    if node_err:
        return {"ok": False, "error": node_err, **error_base}

    if not ipv4:
        return {"ok": False, "error": "ipv4 is required", **error_base}

    # Validate IPs
    ipv4_err = validate_ipv4(ipv4, allow_docs)
    if ipv4_err:
        return {"ok": False, "error": ipv4_err, **error_base}

    if ipv6:
        ipv6_err = validate_ipv6(ipv6, allow_docs)
        if ipv6_err:
            return {"ok": False, "error": ipv6_err, **error_base}

    # Validate output path
    path_err = validate_output_path(output_path)
    if path_err:
        return {"ok": False, "error": path_err, **error_base}

    # Build and validate candidate
    candidate = build_profile_candidate(zone, node, ipv4, ipv6)
    valid, errors = validate_profile_candidate(candidate, allow_docs)
    if not valid:
        return {"ok": False, "error": "profile validation failed",
                "validation_errors": errors, **error_base}

    # Write atomically
    write_err = write_profile_atomic(candidate, output_path)
    if write_err:
        return {"ok": False, "error": write_err, **error_base}

    # Verify written file
    verify_err = verify_written_profile(output_path)
    if verify_err:
        return {"ok": False, "error": verify_err, **error_base}

    return {
        "ok": True,
        "mutation": False,
        "local_file_mutation": True,
        "dns_mutation": False,
        "cloudflare_mutation": False,
        "dns_apply": False,
        "profile_written": True,
        "profile_write_mode": "temp_output",
        "output_path_class": "temp",
        "output_path_redacted": redact_output_path(output_path),
        "file_mode": "600",
        "profile_valid": True,
        "validation_status": "passed",
        "backup_created": False,
        "test_mode": allow_docs,
    }


def output_generate_text(result):
    """Print human-readable generate result."""
    print()
    if result.get("profile_written"):
        print("  Local profile file written.")
        print("  Raw IP values were written to the profile file and intentionally not printed.")
        print("  No DNS records were changed.")
    else:
        print("  No profile file was written.")
    print()


def output_generate_error(message, json_mode=False):
    """Print generate error message."""
    if json_mode:
        result = {"ok": False, "error": message, "mutation": False,
                  "local_file_mutation": False, "dns_mutation": False,
                  "cloudflare_mutation": False, "dns_apply": False,
                  "profile_written": False, "profile_write_mode": "temp_output"}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)

def output_text(result):
    """Print human-readable preview."""
    print()
    print("  NanoBK DNS profile preview")
    print()

    print("  Target:")
    print(f"    {result.get('hostname_redacted', '***')}")
    print()

    print("  Profile:")
    zone_r = result.get("zone_redacted", "***")
    node = result.get("node", "***")
    ip_preview = result.get("ip_preview", {})
    ipv4_r = ip_preview.get("ipv4_redacted", "not set")
    ipv6_r = ip_preview.get("ipv6_redacted", "not set")
    print(f"    zone: {zone_r}")
    print(f"    node: {node}")
    print(f"    ipv4: {ipv4_r}")
    print(f"    ipv6: {ipv6_r}")
    print()

    print("  Validation:")
    print(f"    profile_valid: {str(result.get('profile_valid', False)).lower()}")
    print(f"    validation_status: {result.get('validation_status', 'unknown')}")
    if result.get("test_mode"):
        print(f"    test_mode: true")
    print()

    print("  Safety:")
    print(f"    profile_written: false")
    print(f"    profile_write_mode: preview")
    print(f"    dns_mutation: false")
    print(f"    cloudflare_mutation: false")
    print(f"    dns_apply: false")
    print()

    # Record preview
    records = result.get("record_preview", [])
    if records:
        print("  Record preview:")
        for rec in records:
            rtype = rec.get("type", "?")
            val = rec.get("value_redacted", "***")
            proxied = rec.get("proxied", False)
            print(f"    {rtype:6s} {val}  proxied={str(proxied).lower()}")
        print()

    print("  No DNS profile was written.")
    print("  No DNS records were created, updated, or deleted.")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "mutation": False,
                  "profile_written": False, "profile_write_mode": "preview",
                  "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK DNS Profile (preview / generate)"
    )
    sub = parser.add_subparsers(dest="command")

    # preview subcommand
    preview_parser = sub.add_parser("preview", help="Preview-only DNS profile validation (no file write)")
    preview_parser.add_argument("--zone", help="Domain zone (e.g. example.com)")
    preview_parser.add_argument("--node", help="Node prefix (e.g. proxy)")
    preview_parser.add_argument("--ipv4", help="IPv4 address for A record")
    preview_parser.add_argument("--ipv6", help="IPv6 address for AAAA record (optional)")
    preview_parser.add_argument("--json", action="store_true", help="JSON output")
    preview_parser.add_argument("--allow-documentation-ips", action="store_true",
                                help="Allow documentation IP ranges (tests/examples only)")

    # generate subcommand
    generate_parser = sub.add_parser("generate", help="Write DNS profile to temp output path (temp-only in v2.1.15)")
    generate_parser.add_argument("--zone", help="Domain zone (e.g. example.com)")
    generate_parser.add_argument("--node", help="Node prefix (e.g. proxy)")
    generate_parser.add_argument("--ipv4", help="IPv4 address for A record")
    generate_parser.add_argument("--ipv6", help="IPv6 address for AAAA record (optional)")
    generate_parser.add_argument("--output", help="Output file path (must be under temp root)")
    generate_parser.add_argument("--yes", action="store_true", help="Confirm file write")
    generate_parser.add_argument("--json", action="store_true", help="JSON output")
    generate_parser.add_argument("--allow-documentation-ips", action="store_true",
                                 help="Allow documentation IP ranges (tests/examples only)")

    args = parser.parse_args()

    if args.command == "preview":
        # Manual required-field validation (clean JSON errors)
        if not args.zone:
            output_error("zone is required", args.json)
            sys.exit(1)
        if not args.node:
            output_error("node is required", args.json)
            sys.exit(1)
        if not args.ipv4:
            output_error("ipv4 is required", args.json)
            sys.exit(1)

        result = run_preview(args.zone, args.node, args.ipv4, args.ipv6,
                             args.allow_documentation_ips)

        if not result.get("ok", False):
            output_error(result.get("error", "unknown error"), args.json)
            sys.exit(1)

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            output_text(result)

    elif args.command == "generate":
        # Manual required-field validation (clean JSON errors)
        if not args.zone:
            output_generate_error("zone is required", args.json)
            sys.exit(1)
        if not args.node:
            output_generate_error("node is required", args.json)
            sys.exit(1)
        if not args.ipv4:
            output_generate_error("ipv4 is required", args.json)
            sys.exit(1)
        if not args.output:
            output_generate_error("output path is required", args.json)
            sys.exit(1)
        if not args.yes:
            output_generate_error("this command writes a local profile file; --yes is required", args.json)
            sys.exit(1)

        result = run_generate(args.zone, args.node, args.ipv4, args.ipv6,
                              args.output, args.allow_documentation_ips)

        if not result.get("ok", False):
            output_generate_error(result.get("error", "unknown error"), args.json)
            sys.exit(1)

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            output_generate_text(result)

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
