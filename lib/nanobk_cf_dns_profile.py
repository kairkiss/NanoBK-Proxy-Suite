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
import hashlib
import ipaddress
import json
import os
import re
import secrets
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
PRODUCTION_PROFILE_PATH = "/etc/nanobk/cloudflare-dns-profile.json"


def get_allowed_temp_root():
    """Get the allowed temp root directory."""
    env_tmpdir = os.environ.get("NANOBK_TEST_TMPDIR")
    if env_tmpdir:
        return os.path.realpath(env_tmpdir)
    return os.path.realpath(tempfile.gettempdir())


def classify_output_path(output_path):
    """Classify output path as temp, production, or forbidden.

    Returns (path_class, physical_path, error_string).
    path_class: "temp", "production", or "forbidden"
    physical_path: resolved actual path to write to
    error_string: error message if forbidden, else None

    Production class is ONLY selected for the exact logical path:
        /etc/nanobk/cloudflare-dns-profile.json
    All other /etc/nanobk/* paths are forbidden.
    """
    if not output_path:
        return "forbidden", None, "output path is required"

    if not os.path.isabs(output_path):
        return "forbidden", None, "output path must be absolute"

    # Strict production path check: only exact match
    is_production = False
    if output_path == PRODUCTION_PROFILE_PATH:
        is_production = True
    else:
        try:
            resolved = os.path.realpath(output_path)
            if resolved == PRODUCTION_PROFILE_PATH:
                is_production = True
        except (OSError, ValueError):
            pass

    if is_production:
        return "production", None, None

    # Not exact production path — check if it looks like a production path
    # but is not the exact one (e.g. /etc/nanobk/foo.json)
    try:
        resolved = os.path.realpath(output_path)
    except (OSError, ValueError):
        return "forbidden", None, "cannot resolve output path"

    # Block any /etc/nanobk/* path that isn't the exact production path
    if output_path.startswith("/etc/nanobk/") or resolved.startswith("/etc/nanobk/"):
        return "forbidden", None, "unsupported production output path"

    # Block other blocked prefixes
    for prefix in BLOCKED_PREFIXES:
        if output_path.startswith(prefix) or resolved.startswith(prefix):
            return "forbidden", None, "production profile path is not supported outside fake-root tests"

    # Check allowed temp root using commonpath for safety
    allowed_root = get_allowed_temp_root()
    try:
        common = os.path.commonpath([resolved, allowed_root])
        if common != allowed_root:
            return "forbidden", None, "output path must be under temp root"
    except ValueError:
        return "forbidden", None, "output path must be under temp root"

    return "temp", output_path, None


def resolve_production_physical_path():
    """Resolve the physical path for production output under fake-root.

    Returns (physical_path, error_string).
    """
    fake_root = os.environ.get("NANOBK_TEST_PRODUCTION_PROFILE_ROOT", "")
    allow_root = os.environ.get("NANOBK_TEST_ALLOW_PRODUCTION_ROOT", "")

    if not fake_root and not allow_root:
        return None, "production profile writes are not enabled outside fake-root tests"
    if not fake_root:
        return None, "production profile writes are not enabled outside fake-root tests"
    if allow_root != "1":
        return None, "production profile writes are not enabled outside fake-root tests"

    if not os.path.isabs(fake_root):
        return None, "fake-root must be absolute"

    if os.path.islink(fake_root):
        return None, "fake-root symlink is not allowed"

    # Fake root must be under temp root
    try:
        resolved_root = os.path.realpath(fake_root)
    except (OSError, ValueError):
        return None, "cannot resolve fake-root"

    allowed_temp = get_allowed_temp_root()
    try:
        common = os.path.commonpath([resolved_root, allowed_temp])
    except ValueError:
        return None, "fake-root must be under temp root"

    if common != allowed_temp:
        return None, "fake-root must be under temp root"

    # Map logical path to physical
    # /etc/nanobk/cloudflare-dns-profile.json -> $FAKE_ROOT/etc/nanobk/cloudflare-dns-profile.json
    rel_path = PRODUCTION_PROFILE_PATH.lstrip("/")
    physical = os.path.join(resolved_root, rel_path)
    return physical, None


def validate_production_parent(physical_path):
    """Validate production parent directory. Returns error string or None."""
    parent = os.path.dirname(physical_path)

    if not os.path.isdir(parent):
        return "production parent directory does not exist"

    if os.path.islink(parent):
        return "production parent symlink is not allowed"

    # Check parent mode is 0700
    try:
        st = os.stat(parent)
        mode = st.st_mode & 0o7777
        if mode != 0o700:
            return f"production parent mode must be 0700, got {oct(mode)}"
    except OSError:
        return "cannot stat production parent directory"

    return None


def validate_output_path(output_path, allow_production=False, confirm_hostname=None, zone=None, node=None):
    """Validate output path against allowlist. Returns (path_class, physical_path, error_string)."""
    path_class, physical, err = classify_output_path(output_path)

    if path_class == "forbidden":
        return "forbidden", None, err

    if path_class == "production":
        if not allow_production:
            return "forbidden", None, "--allow-production-output is required for production path"

        # Validate confirmation
        if not confirm_hostname:
            return "forbidden", None, "--confirm-hostname is required for production output"

        expected = f"{node}.{zone}"
        if confirm_hostname != expected:
            return "forbidden", None, "confirmation hostname does not match target"

        # Resolve physical path via fake-root
        physical, err = resolve_production_physical_path()
        if err:
            return "forbidden", None, err

        # Validate parent
        parent_err = validate_production_parent(physical)
        if parent_err:
            return "forbidden", None, parent_err

        # Check if file already exists
        if os.path.exists(physical):
            return "forbidden", None, "production profile already exists"

        # Check symlink
        if os.path.islink(physical):
            return "forbidden", None, "output path symlink is not allowed"

        return "production", physical, None

    # Temp class
    if os.path.islink(output_path):
        return "forbidden", None, "output path symlink is not allowed"

    parent = os.path.dirname(output_path)
    if os.path.islink(parent):
        return "forbidden", None, "output path parent symlink is not allowed"

    if os.path.exists(output_path):
        return "forbidden", None, "output file already exists"

    return "temp", output_path, None


def redact_output_path(output_path):
    """Redact output path for display."""
    # Never print physical paths
    if output_path == PRODUCTION_PROFILE_PATH or output_path.startswith("/etc/nanobk/"):
        return "[production]/cloudflare-dns-profile.json"
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
    """Write profile JSON atomically with no-overwrite guarantee.

    Uses hard-link finalization: temp file is written, fsynced, and chmod'd,
    then hard-linked to the final path. If the link fails (e.g. final exists),
    the temp file is cleaned up and an error is returned. No rename/replace
    fallback is used, so an existing final path is never overwritten.
    """
    parent_dir = os.path.dirname(output_path)

    # Create parent directory if needed (restrictive permissions)
    try:
        os.makedirs(parent_dir, mode=0o700, exist_ok=True)
    except OSError as e:
        return f"cannot create parent directory: {e}"

    # Serialize JSON
    profile_json = json.dumps(candidate, indent=2, sort_keys=True) + "\n"
    profile_bytes = profile_json.encode("utf-8")

    # Test-only hook: simulate finalization failure
    if os.environ.get("NANOBK_TEST_FORCE_PROFILE_FINALIZE_FAIL") == "1":
        return "atomic finalize failed (test hook)"

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

        # Test-only hook: simulate failure after write/chmod, before hard-link
        if os.environ.get("NANOBK_TEST_FORCE_PROFILE_FINALIZE_FAIL_AFTER_WRITE") == "1":
            if tmp_path and os.path.exists(tmp_path):
                os.unlink(tmp_path)
            return "atomic finalize failed (test hook)"

        # Hard-link to final path (no-overwrite: link fails if final exists)
        try:
            os.link(tmp_path, output_path)
            os.unlink(tmp_path)
            tmp_path = None
        except FileExistsError:
            # Final path already exists — clean temp, return error
            if tmp_path and os.path.exists(tmp_path):
                os.unlink(tmp_path)
            return "output file already exists"
        except OSError:
            # Other link failure — clean temp, return error
            if tmp_path and os.path.exists(tmp_path):
                os.unlink(tmp_path)
            return "atomic finalize failed"

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

def run_generate(zone, node, ipv4, ipv6, output_path, allow_docs,
                 allow_production=False, confirm_hostname=None):
    """Run profile generate. Returns result dict."""
    error_base = {"mutation": False, "local_file_mutation": False,
                  "dns_mutation": False, "cloudflare_mutation": False,
                  "dns_apply": False, "profile_written": False,
                  "production_profile_written": False,
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

    # Validate output path (handles both temp and production)
    path_class, physical_path, path_err = validate_output_path(
        output_path, allow_production, confirm_hostname, zone, node
    )
    if path_err:
        return {"ok": False, "error": path_err, **error_base}

    # Build and validate candidate
    candidate = build_profile_candidate(zone, node, ipv4, ipv6)
    valid, errors = validate_profile_candidate(candidate, allow_docs)
    if not valid:
        return {"ok": False, "error": "profile validation failed",
                "validation_errors": errors, **error_base}

    # Write atomically (uses physical path for production)
    write_err = write_profile_atomic(candidate, physical_path)
    if write_err:
        return {"ok": False, "error": write_err, **error_base}

    # Verify written file
    verify_err = verify_written_profile(physical_path)
    if verify_err:
        return {"ok": False, "error": verify_err, **error_base}

    is_production = (path_class == "production")

    result = {
        "ok": True,
        "mutation": False,
        "local_file_mutation": True,
        "dns_mutation": False,
        "cloudflare_mutation": False,
        "dns_apply": False,
        "profile_written": True,
        "production_profile_written": is_production,
        "profile_write_mode": "production" if is_production else "temp_output",
        "output_path_class": path_class,
        "output_path_redacted": redact_output_path(output_path),
        "file_mode": "600",
        "profile_valid": True,
        "validation_status": "passed",
        "backup_created": False,
        "test_mode": allow_docs,
    }

    if is_production:
        result["confirmation_required"] = True
        result["confirmation_matched"] = True
        result["production_fake_root"] = True

    return result


def output_generate_text(result):
    """Print human-readable generate result."""
    print()
    if result.get("profile_written"):
        if result.get("production_profile_written"):
            print("  Local production DNS profile was written under fake-root test mode.")
        else:
            print("  Local profile file written.")
        print("  Raw IP values were stored and intentionally not printed.")
        print("  DNS has not been applied.")
        print("  No DNS records were created, updated, or deleted.")
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


# ── Replace preview logic ───────────────────────────────────────────────────

def build_summary(profile_dict, zone=None):
    """Build a redacted summary from a profile dict."""
    summary = {}
    z = profile_dict.get("zoneName", zone or "")
    n = profile_dict.get("nodePrefix", "")
    summary["zone_redacted"] = mask_domain(z) if z else "***"
    summary["node"] = n if n else "***"
    summary["hostname_redacted"] = mask_hostname(n, z) if n and z else "***"

    ipv4 = profile_dict.get("ipv4")
    ipv6 = profile_dict.get("ipv6")
    if ipv4:
        summary["ipv4_redacted"] = mask_ipv4(ipv4)
    if ipv6:
        summary["ipv6_redacted"] = mask_ipv6(ipv6)

    # Stack mode
    has_ipv4 = bool(ipv4)
    has_ipv6 = bool(ipv6)
    if has_ipv4 and has_ipv6:
        summary["stack_mode"] = "dual_stack"
    elif has_ipv4:
        summary["stack_mode"] = "ipv4_only"
    elif has_ipv6:
        summary["stack_mode"] = "ipv6_only"
    else:
        summary["stack_mode"] = "none"

    # Record types
    record_types = []
    if ipv4:
        record_types.append("A")
    if ipv6:
        record_types.append("AAAA")
    summary["record_types"] = record_types

    summary["default_proxied"] = profile_dict.get("defaultProxied", False)
    return summary


def build_redacted_diff(old_summary, new_summary):
    """Build boolean diff between old and new summaries.

    Uses stable contract-friendly field names.
    """
    # Map summary keys to contract diff keys
    key_map = {
        "zone_redacted": "zone_changed",
        "node": "node_changed",
        "hostname_redacted": "hostname_changed",
        "ipv4_redacted": "ipv4_changed",
        "ipv6_redacted": "ipv6_changed",
        "stack_mode": "stack_mode_changed",
        "default_proxied": "default_proxied_changed",
    }
    diff = {}
    for summary_key, diff_key in key_map.items():
        old_val = old_summary.get(summary_key)
        new_val = new_summary.get(summary_key)
        diff[diff_key] = (old_val != new_val)

    # Record types diff
    old_types = set(old_summary.get("record_types", []))
    new_types = set(new_summary.get("record_types", []))
    diff["record_types_changed"] = (old_types != new_types)

    return diff


REPLACE_ERROR_BASE = {"mutation": False, "local_file_mutation": False,
                      "dns_mutation": False, "cloudflare_mutation": False,
                      "dns_apply": False, "replace_preview": True,
                      "backup_required": True, "backup_created": False,
                      "profile_replaced": False}


def run_replace_preview(zone, node, ipv4, ipv6, output_path, allow_docs,
                        allow_production, confirm_hostname):
    """Run replace preview. Returns result dict."""
    # Validate inputs
    zone_err = validate_zone(zone)
    if zone_err:
        return {"ok": False, "error": zone_err, **REPLACE_ERROR_BASE}

    node_err = validate_node(node)
    if node_err:
        return {"ok": False, "error": node_err, **REPLACE_ERROR_BASE}

    if not ipv4:
        return {"ok": False, "error": "ipv4 is required", **REPLACE_ERROR_BASE}

    ipv4_err = validate_ipv4(ipv4, allow_docs)
    if ipv4_err:
        return {"ok": False, "error": ipv4_err, **REPLACE_ERROR_BASE}

    if ipv6:
        ipv6_err = validate_ipv6(ipv6, allow_docs)
        if ipv6_err:
            return {"ok": False, "error": ipv6_err, **REPLACE_ERROR_BASE}

    # Validate confirmation
    if not confirm_hostname:
        return {"ok": False, "error": "confirm-hostname is required for replace preview",
                **REPLACE_ERROR_BASE}
    expected_hostname = f"{node}.{zone}"
    if confirm_hostname != expected_hostname:
        return {"ok": False, "error": "confirmation hostname does not match target",
                **REPLACE_ERROR_BASE}

    # Validate production path
    if not allow_production:
        return {"ok": False, "error": "--allow-production-output is required",
                **REPLACE_ERROR_BASE}

    path_class, _, path_err = classify_output_path(output_path)
    if path_class != "production":
        return {"ok": False, "error": path_err or "unsupported output path",
                **REPLACE_ERROR_BASE}

    # Resolve fake-root physical path
    physical_path, root_err = resolve_production_physical_path()
    if root_err:
        return {"ok": False, "error": root_err, **REPLACE_ERROR_BASE}

    # Validate parent
    parent_err = validate_production_parent(physical_path)
    if parent_err:
        return {"ok": False, "error": parent_err, **REPLACE_ERROR_BASE}

    # Read existing profile
    old_profile_status = "unknown"
    old_profile_data = None
    old_error = None

    if not os.path.exists(physical_path):
        old_profile_status = "missing"
        old_error = "existing profile is missing; use profile generate first"
    elif os.path.islink(physical_path):
        old_profile_status = "symlink_blocked"
        old_error = "existing profile symlink is blocked"
    elif not os.path.isfile(physical_path):
        old_profile_status = "non_regular_file"
        old_error = "existing profile is not a regular file"
    else:
        try:
            with open(physical_path, "r") as f:
                old_profile_data = json.load(f)
            old_profile_status = "valid"
        except json.JSONDecodeError:
            old_profile_status = "invalid_json"
            old_error = "existing profile is not valid JSON"
        except OSError:
            old_profile_status = "unreadable"
            old_error = "existing profile is unreadable"

    # Validate old profile schema if loaded
    if old_profile_status == "valid" and old_profile_data:
        # Must be a JSON object
        if not isinstance(old_profile_data, dict):
            old_profile_status = "unsupported_schema"
            old_error = "existing profile schema is unsupported"
        else:
            # Check for secret-like keys
            has_secret = False
            for key in old_profile_data:
                key_lower = key.lower()
                for secret in _SECRET_SUBSTRINGS:
                    if secret in key_lower and key not in _ALLOWED_KEYS:
                        has_secret = True
                        break
                if has_secret:
                    break
            if has_secret:
                old_profile_status = "unsupported_schema"
                old_error = "existing profile schema is unsupported"
            # Check required fields
            elif "zoneName" not in old_profile_data or "nodePrefix" not in old_profile_data:
                old_profile_status = "unsupported_schema"
                old_error = "existing profile schema is unsupported"
            # Validate zone/node/IP if present
            else:
                oz = old_profile_data.get("zoneName", "")
                on = old_profile_data.get("nodePrefix", "")
                if validate_zone(oz) or validate_node(on):
                    old_profile_status = "unsupported_schema"
                    old_error = "existing profile schema is unsupported"
                # Check IP validity
                oipv4 = old_profile_data.get("ipv4")
                oipv6 = old_profile_data.get("ipv6")
                if not oipv4 and not oipv6:
                    old_profile_status = "unsupported_schema"
                    old_error = "existing profile schema is unsupported"
                else:
                    if oipv4 and validate_ipv4(oipv4, True):
                        old_profile_status = "unsupported_schema"
                        old_error = "existing profile schema is unsupported"
                    if oipv6 and validate_ipv6(oipv6, True):
                        old_profile_status = "unsupported_schema"
                        old_error = "existing profile schema is unsupported"
                # Check defaultProxied
                if old_profile_status == "valid":
                    prox = old_profile_data.get("defaultProxied")
                    if prox is not None and prox is not False:
                        old_profile_status = "unsupported_schema"
                        old_error = "existing profile schema is unsupported"
                # Check for unknown keys
                if old_profile_status == "valid":
                    known_keys = {"zoneName", "nodePrefix", "ipv4", "ipv6",
                                  "defaultProxied", "zoneId", "reserved"}
                    for k in old_profile_data:
                        if k not in known_keys:
                            old_profile_status = "unsupported_schema"
                            old_error = "existing profile schema is unsupported"
                            break

    # Build new candidate
    new_candidate = build_profile_candidate(zone, node, ipv4, ipv6)
    new_valid, new_errors = validate_profile_candidate(new_candidate, allow_docs)

    # Honest ok: true only when old is valid AND new is valid
    ok = (old_profile_status == "valid") and new_valid

    # Build summaries only when safe
    old_summary = {}
    if old_profile_status == "valid" and old_profile_data:
        old_summary = build_summary(old_profile_data)

    new_summary = {}
    if new_valid:
        new_summary = build_summary(new_candidate, zone)

    # Build diff only when both summaries are available
    redacted_diff = {}
    if old_summary and new_summary:
        redacted_diff = build_redacted_diff(old_summary, new_summary)

    # Error message for non-ok cases
    error_msg = None
    if not ok:
        if old_error:
            error_msg = old_error
        elif not new_valid:
            error_msg = "new profile candidate is invalid"

    result = {
        "ok": ok,
        "mutation": False,
        "local_file_mutation": False,
        "dns_mutation": False,
        "cloudflare_mutation": False,
        "dns_apply": False,
        "replace_preview": True,
        "backup_required": True,
        "backup_created": False,
        "profile_replaced": False,
        "old_profile_status": old_profile_status,
        "new_profile_valid": new_valid,
        "replace_execute_ready": False,
        "replace_execute_blocked_reason": "rollback policy is not implemented",
        "confirmation_required": True,
        "confirmation_matched": True,
    }

    if error_msg:
        result["error"] = error_msg

    if old_summary:
        result["old_summary"] = old_summary
    if new_summary:
        result["new_summary"] = new_summary
    if redacted_diff:
        result["redacted_diff"] = redacted_diff

    if not new_valid:
        result["new_validation_errors"] = new_errors

    return result


def output_replace_preview_text(result):
    """Print human-readable replace preview."""
    print()
    print("  NanoBK DNS profile replace preview")
    print()
    print("  Replace preview only.")
    print("  No backup was created.")
    print("  No profile was replaced.")
    print("  DNS has not been applied.")
    print("  Cloudflare was not called.")
    print("  Replace execute is not implemented.")
    print()

    # Existing profile status
    old_status = result.get("old_profile_status", "unknown")
    print(f"  Existing profile status: {old_status}")

    # New profile validation
    new_valid = result.get("new_profile_valid", False)
    print(f"  New profile validation: {'passed' if new_valid else 'failed'}")
    print()

    # Redacted diff
    diff = result.get("redacted_diff")
    if diff:
        print("  Change summary (redacted):")
        changed_keys = [k for k, v in diff.items() if v]
        if changed_keys:
            for k in changed_keys:
                print(f"    {k}: true")
        else:
            print("    (no changes)")
        print()

    print("  Replace execute is not available.")
    print("  rollback policy is not implemented.")
    print()


def output_replace_preview_error(message, json_mode=False):
    """Print replace preview error message."""
    if json_mode:
        result = {
            "ok": False,
            "error": message,
            "mutation": False,
            "local_file_mutation": False,
            "dns_mutation": False,
            "cloudflare_mutation": False,
            "dns_apply": False,
            "replace_preview": True,
            "backup_required": True,
            "backup_created": False,
            "profile_replaced": False,
            "replace_execute_ready": False,
            "replace_execute_blocked_reason": "rollback policy is not implemented",
        }
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)

# ── backup-only start ──────────────────────────────────────────────────────

BACKUP_ERROR_BASE = {"mutation": False, "local_file_mutation": False,
                     "dns_mutation": False, "cloudflare_mutation": False,
                     "dns_apply": False, "backup_only": True,
                     "backup_created": False, "profile_replaced": False,
                     "rollback_performed": False}


def validate_source_profile(physical_path):
    """Validate source profile for backup. Returns (status, data, error)."""
    # Check symlink first (catches broken symlinks too)
    if os.path.islink(physical_path):
        return "source_symlink_blocked", None, "source profile symlink is blocked"
    if not os.path.exists(physical_path):
        return "source_missing", None, "source profile is missing"
    if not os.path.isfile(physical_path):
        return "source_non_regular_file", None, "source profile is not a regular file"

    # Check mode
    try:
        st = os.stat(physical_path)
        mode = stat.S_IMODE(st.st_mode)
        if mode != 0o600:
            return "source_mode_invalid", None, f"source profile mode must be 0600, got {oct(mode)}"
    except OSError:
        return "source_unreadable", None, "source profile is unreadable"

    # Read and parse
    try:
        with open(physical_path, "rb") as f:
            raw_bytes = f.read()
        data = json.loads(raw_bytes)
    except json.JSONDecodeError:
        return "source_invalid_json", None, "source profile is not valid JSON"
    except OSError:
        return "source_unreadable", None, "source profile is unreadable"

    # Schema validation
    if not isinstance(data, dict):
        return "source_unsupported_schema", None, "source profile schema is unsupported"

    # Check for secret-like keys
    for key in data:
        key_lower = key.lower()
        for secret in _SECRET_SUBSTRINGS:
            if secret in key_lower and key not in _ALLOWED_KEYS:
                return "source_unsupported_schema", None, "source profile schema is unsupported"

    # Required fields
    if "zoneName" not in data or "nodePrefix" not in data:
        return "source_unsupported_schema", None, "source profile schema is unsupported"

    # Validate zone/node
    if validate_zone(data.get("zoneName", "")):
        return "source_unsupported_schema", None, "source profile schema is unsupported"
    if validate_node(data.get("nodePrefix", "")):
        return "source_unsupported_schema", None, "source profile schema is unsupported"

    # Validate IPs
    ipv4 = data.get("ipv4")
    ipv6 = data.get("ipv6")
    if not ipv4 and not ipv6:
        return "source_unsupported_schema", None, "source profile schema is unsupported"
    if ipv4 and validate_ipv4(ipv4, True):
        return "source_unsupported_schema", None, "source profile schema is unsupported"
    if ipv6 and validate_ipv6(ipv6, True):
        return "source_unsupported_schema", None, "source profile schema is unsupported"

    # defaultProxied
    prox = data.get("defaultProxied")
    if prox is not None and prox is not False:
        return "source_unsupported_schema", None, "source profile schema is unsupported"

    # Unknown keys
    known_keys = {"zoneName", "nodePrefix", "ipv4", "ipv6",
                  "defaultProxied", "zoneId", "reserved"}
    for k in data:
        if k not in known_keys:
            return "source_unsupported_schema", None, "source profile schema is unsupported"

    return "valid", data, None


def create_backup_dir(backup_dir):
    """Create or validate backup directory. Returns error string or None."""
    if os.path.islink(backup_dir):
        return "backup directory symlink is not allowed"
    if os.path.exists(backup_dir):
        if not os.path.isdir(backup_dir):
            return "backup directory is not a directory"
        try:
            st = os.stat(backup_dir)
            mode = stat.S_IMODE(st.st_mode)
            if mode != 0o700:
                return f"backup directory mode must be 0700, got {oct(mode)}"
        except OSError:
            return "cannot stat backup directory"
        return None
    # Create with mode 0700
    try:
        os.makedirs(backup_dir, mode=0o700, exist_ok=True)
    except OSError:
        return "cannot create backup directory"
    return None


def create_backup_file(source_path, backup_path):
    """Copy source to backup atomically. Returns (sha256_hex, error_string)."""
    try:
        with open(source_path, "rb") as f:
            source_bytes = f.read()
    except OSError:
        return None, "cannot read source profile"

    source_sha = hashlib.sha256(source_bytes).hexdigest()

    # Write with exclusive creation
    tmp_fd = None
    tmp_path = None
    try:
        tmp_fd, tmp_path = tempfile.mkstemp(
            dir=os.path.dirname(backup_path),
            prefix=".nanobk-backup-",
            suffix=".tmp"
        )
        os.write(tmp_fd, source_bytes)
        os.fsync(tmp_fd)
        os.close(tmp_fd)
        tmp_fd = None
        os.chmod(tmp_path, 0o600)

        # Hard-link to final path (no-overwrite)
        try:
            os.link(tmp_path, backup_path)
            os.unlink(tmp_path)
            tmp_path = None
        except FileExistsError:
            if tmp_path and os.path.exists(tmp_path):
                os.unlink(tmp_path)
            return None, "backup file already exists"
        except OSError:
            if tmp_path and os.path.exists(tmp_path):
                os.unlink(tmp_path)
            return None, "atomic backup finalize failed"

    except OSError as e:
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
        return None, "backup write failed"

    # Verify backup
    try:
        st = os.stat(backup_path)
        if stat.S_IMODE(st.st_mode) != 0o600:
            return source_sha, "backup file mode verification failed"
        if st.st_size != len(source_bytes):
            return source_sha, "backup file size mismatch"

        with open(backup_path, "rb") as f:
            backup_bytes = f.read()
        if hashlib.sha256(backup_bytes).hexdigest() != source_sha:
            return source_sha, "backup sha256 mismatch"

        # Verify JSON parses
        json.loads(backup_bytes)
    except (OSError, json.JSONDecodeError):
        return source_sha, "backup verification failed"

    return source_sha, None


def redact_backup_path(path):
    """Redact backup path for display."""
    if "/etc/nanobk/backups/" in path or path.startswith("/etc/nanobk/"):
        filename = os.path.basename(path)
        return f"[production]/backups/{filename}"
    return "[production]/backups/..."


def run_backup(profile_path, allow_production, confirm_hostname):
    """Run profile backup. Returns result dict."""
    # Validate production path
    if not allow_production:
        return {"ok": False, "error": "--allow-production-output is required",
                **BACKUP_ERROR_BASE}

    path_class, _, path_err = classify_output_path(profile_path)
    if path_class != "production":
        return {"ok": False, "error": path_err or "unsupported profile path",
                **BACKUP_ERROR_BASE}

    # Resolve fake-root
    physical_source, root_err = resolve_production_physical_path()
    if root_err:
        return {"ok": False, "error": root_err, **BACKUP_ERROR_BASE}

    # Validate parent
    parent_err = validate_production_parent(physical_source)
    if parent_err:
        return {"ok": False, "error": parent_err, **BACKUP_ERROR_BASE}

    # Validate source profile
    source_status, source_data, source_err = validate_source_profile(physical_source)
    if source_err:
        return {"ok": False, "error": source_err,
                "source_profile_status": source_status, **BACKUP_ERROR_BASE}

    # Confirmation
    if not confirm_hostname:
        return {"ok": False, "error": "confirm-hostname is required for profile backup",
                **BACKUP_ERROR_BASE}
    node = source_data.get("nodePrefix", "")
    zone = source_data.get("zoneName", "")
    expected_hostname = f"{node}.{zone}"
    if confirm_hostname != expected_hostname:
        return {"ok": False, "error": "confirmation hostname does not match source profile",
                **BACKUP_ERROR_BASE}

    # Create backup directory
    backup_dir = os.path.join(os.path.dirname(physical_source), "backups")
    dir_err = create_backup_dir(backup_dir)
    if dir_err:
        return {"ok": False, "error": dir_err, **BACKUP_ERROR_BASE}

    # Generate backup filename
    from datetime import datetime, timezone
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    rand = secrets.token_hex(4)
    backup_filename = f"cloudflare-dns-profile.json.{ts}.{rand}.bak"
    backup_path = os.path.join(backup_dir, backup_filename)

    # Create backup
    sha_hex, backup_err = create_backup_file(physical_source, backup_path)
    if backup_err:
        return {"ok": False, "error": backup_err,
                "source_profile_status": "valid", **BACKUP_ERROR_BASE}

    # Get backup dir mode (normalized to 3-digit octal string)
    try:
        dir_mode = format(stat.S_IMODE(os.stat(backup_dir).st_mode), "03o")
    except OSError:
        dir_mode = "unknown"

    return {
        "ok": True,
        "mutation": False,
        "local_file_mutation": True,
        "dns_mutation": False,
        "cloudflare_mutation": False,
        "dns_apply": False,
        "backup_only": True,
        "backup_created": True,
        "profile_replaced": False,
        "rollback_performed": False,
        "source_profile_status": "valid",
        "backup_path_redacted": redact_backup_path(backup_path),
        "backup_mode": "600",
        "backup_dir_mode": dir_mode,
        "backup_sha256_computed": True,
        "production_fake_root": True,
        "confirmation_required": True,
        "confirmation_matched": True,
    }


def output_backup_text(result):
    """Print human-readable backup result."""
    print()
    if result.get("backup_created"):
        print("  Backup created under fake-root test mode.")
        print("  Source profile was copied byte-for-byte.")
        print(f"  Backup mode: {result.get('backup_mode', '600')}.")
        print("  DNS has not been applied.")
        print("  No DNS records were created, updated, or deleted.")
        print("  No profile was replaced.")
        print("  Rollback was not performed.")
        print("  Raw profile content and raw IP values were intentionally not printed.")
    else:
        print("  No backup was created.")
        error = result.get("error")
        if error:
            print(f"  Error: {error}")
    print()


def output_backup_error(message, json_mode=False):
    """Print backup error message."""
    if json_mode:
        result = {
            "ok": False, "error": message,
            "mutation": False, "local_file_mutation": False,
            "dns_mutation": False, "cloudflare_mutation": False,
            "dns_apply": False, "backup_only": True,
            "backup_created": False, "profile_replaced": False,
            "rollback_performed": False,
        }
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)

# ── backup-only end ────────────────────────────────────────────────────────

# ── rollback-preview start ─────────────────────────────────────────────────

ROLLBACK_PREVIEW_ERROR_BASE = {
    "mutation": False, "local_file_mutation": False,
    "dns_mutation": False, "cloudflare_mutation": False,
    "dns_apply": False, "rollback_preview": True,
    "rollback_performed": False, "profile_replaced": False,
    "pre_rollback_backup_created": False,
}

_BACKUP_ID_RE = re.compile(
    r"^cloudflare-dns-profile\.json\.\d{8}-\d{6}\.[0-9a-f]{8}\.bak$"
)


def validate_backup_id(backup_id):
    """Validate backup ID. Returns error string or None."""
    if not backup_id:
        return "backup-id is required"
    if "/" in backup_id or "\\" in backup_id:
        return "backup-id must not contain path separators"
    if ".." in backup_id:
        return "backup-id must not contain traversal"
    if not _BACKUP_ID_RE.match(backup_id):
        return "backup-id format is invalid"
    return None


def load_and_validate_profile(path, label="profile"):
    """Load and validate a profile file. Returns (status, data, error)."""
    if os.path.islink(path):
        return "symlink_blocked", None, f"{label} symlink is blocked"
    if not os.path.exists(path):
        return "missing", None, f"{label} is missing"
    if not os.path.isfile(path):
        return "non_regular_file", None, f"{label} is not a regular file"

    try:
        st = os.stat(path)
        mode = stat.S_IMODE(st.st_mode)
        if mode != 0o600:
            return "mode_invalid", None, f"{label} mode must be 0600, got {format(mode, '03o')}"
    except OSError:
        return "unreadable", None, f"{label} is unreadable"

    try:
        with open(path, "rb") as f:
            raw_bytes = f.read()
        data = json.loads(raw_bytes)
    except json.JSONDecodeError:
        return "invalid_json", None, f"{label} is not valid JSON"
    except OSError:
        return "unreadable", None, f"{label} is unreadable"

    if not isinstance(data, dict):
        return "unsupported_schema", None, f"{label} schema is unsupported"

    for key in data:
        key_lower = key.lower()
        for secret in _SECRET_SUBSTRINGS:
            if secret in key_lower and key not in _ALLOWED_KEYS:
                return "unsupported_schema", None, f"{label} schema is unsupported"

    if "zoneName" not in data or "nodePrefix" not in data:
        return "unsupported_schema", None, f"{label} schema is unsupported"

    if validate_zone(data.get("zoneName", "")):
        return "unsupported_schema", None, f"{label} schema is unsupported"
    if validate_node(data.get("nodePrefix", "")):
        return "unsupported_schema", None, f"{label} schema is unsupported"

    ipv4 = data.get("ipv4")
    ipv6 = data.get("ipv6")
    if not ipv4 and not ipv6:
        return "unsupported_schema", None, f"{label} schema is unsupported"
    if ipv4 and validate_ipv4(ipv4, True):
        return "unsupported_schema", None, f"{label} schema is unsupported"
    if ipv6 and validate_ipv6(ipv6, True):
        return "unsupported_schema", None, f"{label} schema is unsupported"

    prox = data.get("defaultProxied")
    if prox is not None and prox is not False:
        return "unsupported_schema", None, f"{label} schema is unsupported"

    known_keys = {"zoneName", "nodePrefix", "ipv4", "ipv6",
                  "defaultProxied", "zoneId", "reserved"}
    for k in data:
        if k not in known_keys:
            return "unsupported_schema", None, f"{label} schema is unsupported"

    return "valid", data, None


def run_rollback_preview(backup_id, allow_production, confirm_hostname):
    """Run rollback preview. Returns result dict."""
    # Validate backup ID first (before any filesystem access)
    id_err = validate_backup_id(backup_id)
    if id_err:
        return {"ok": False, "error": id_err, **ROLLBACK_PREVIEW_ERROR_BASE}

    # Validate production path
    if not allow_production:
        return {"ok": False, "error": "--allow-production-output is required",
                **ROLLBACK_PREVIEW_ERROR_BASE}

    # Resolve fake-root
    physical_source, root_err = resolve_production_physical_path()
    if root_err:
        return {"ok": False, "error": root_err, **ROLLBACK_PREVIEW_ERROR_BASE}

    # Validate parent
    parent_err = validate_production_parent(physical_source)
    if parent_err:
        return {"ok": False, "error": parent_err, **ROLLBACK_PREVIEW_ERROR_BASE}

    # Validate current profile
    current_status, current_data, current_err = load_and_validate_profile(
        physical_source, "current profile"
    )

    # Validate backup dir
    backup_dir = os.path.join(os.path.dirname(physical_source), "backups")
    if os.path.islink(backup_dir):
        return {"ok": False, "error": "backup directory symlink is not allowed",
                "current_profile_status": current_status, **ROLLBACK_PREVIEW_ERROR_BASE}
    if not os.path.exists(backup_dir):
        return {"ok": False, "error": "backup directory does not exist",
                "current_profile_status": current_status, **ROLLBACK_PREVIEW_ERROR_BASE}
    if not os.path.isdir(backup_dir):
        return {"ok": False, "error": "backup directory is not a directory",
                "current_profile_status": current_status, **ROLLBACK_PREVIEW_ERROR_BASE}
    try:
        dir_mode = stat.S_IMODE(os.stat(backup_dir).st_mode)
        if dir_mode != 0o700:
            return {"ok": False, "error": "backup directory mode must be 0700",
                    "current_profile_status": current_status, **ROLLBACK_PREVIEW_ERROR_BASE}
    except OSError:
        return {"ok": False, "error": "cannot stat backup directory",
                "current_profile_status": current_status, **ROLLBACK_PREVIEW_ERROR_BASE}

    # Validate backup file
    backup_path = os.path.join(backup_dir, backup_id)
    backup_status, backup_data, backup_err = load_and_validate_profile(
        backup_path, "backup profile"
    )

    # Confirmation validation
    if not confirm_hostname:
        return {"ok": False, "error": "confirm-hostname is required for rollback preview",
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": False,
                **ROLLBACK_PREVIEW_ERROR_BASE}

    # Compute hostnames if both profiles are valid
    if current_status == "valid" and backup_status == "valid":
        current_node = current_data.get("nodePrefix", "")
        current_zone = current_data.get("zoneName", "")
        current_hostname = f"{current_node}.{current_zone}"

        backup_node = backup_data.get("nodePrefix", "")
        backup_zone = backup_data.get("zoneName", "")
        backup_hostname = f"{backup_node}.{backup_zone}"

        if current_hostname != backup_hostname:
            return {"ok": False, "error": "current and backup hostnames do not match",
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": False,
                    **ROLLBACK_PREVIEW_ERROR_BASE}

        if confirm_hostname != current_hostname:
            return {"ok": False, "error": "confirmation hostname does not match rollback target",
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": False,
                    **ROLLBACK_PREVIEW_ERROR_BASE}

    # Determine overall ok
    ok = (current_status == "valid" and backup_status == "valid")

    # Build summaries
    current_summary = {}
    if current_status == "valid" and current_data:
        current_summary = build_summary(current_data)

    backup_summary = {}
    if backup_status == "valid" and backup_data:
        backup_summary = build_summary(backup_data)

    # Build diff
    redacted_diff = {}
    if current_summary and backup_summary:
        redacted_diff = build_redacted_diff(current_summary, backup_summary)

    # Error message for non-ok cases
    error_msg = None
    if not ok:
        if current_err:
            error_msg = current_err
        elif backup_err:
            error_msg = backup_err

    result = {
        "ok": ok,
        "mutation": False,
        "local_file_mutation": False,
        "dns_mutation": False,
        "cloudflare_mutation": False,
        "dns_apply": False,
        "rollback_preview": True,
        "rollback_performed": False,
        "profile_replaced": False,
        "pre_rollback_backup_created": False,
        "current_profile_status": current_status,
        "backup_profile_status": backup_status,
        "backup_id_redacted": backup_id,
        "rollback_execute_ready": False,
        "rollback_execute_blocked_reason": "rollback execute is not implemented",
        "confirmation_required": True,
        "confirmation_matched": ok,
    }

    if error_msg:
        result["error"] = error_msg
    if current_summary:
        result["current_summary"] = current_summary
    if backup_summary:
        result["backup_summary"] = backup_summary
    if redacted_diff:
        result["redacted_diff"] = redacted_diff

    return result


def output_rollback_preview_text(result):
    """Print human-readable rollback preview."""
    print()
    print("  NanoBK DNS profile rollback preview")
    print()
    print("  Rollback preview only.")
    print("  No profile was changed.")
    print("  No pre-rollback backup was created.")
    print("  Rollback execute is not implemented.")
    print("  DNS has not been applied.")
    print("  Cloudflare was not called.")
    print()
    print(f"  Current profile status: {result.get('current_profile_status', 'unknown')}")
    print(f"  Backup profile status: {result.get('backup_profile_status', 'unknown')}")
    print()

    diff = result.get("redacted_diff")
    if diff:
        print("  Change summary (redacted):")
        changed = [k for k, v in diff.items() if v]
        if changed:
            for k in changed:
                print(f"    {k}: true")
        else:
            print("    (no changes)")
        print()

    print("  Rollback execute is not available.")
    print("  Raw profile and backup content intentionally not printed.")
    print()


def output_rollback_preview_error(message, json_mode=False):
    """Print rollback preview error message."""
    if json_mode:
        result = {
            "ok": False, "error": message,
            "mutation": False, "local_file_mutation": False,
            "dns_mutation": False, "cloudflare_mutation": False,
            "dns_apply": False, "rollback_preview": True,
            "rollback_performed": False, "profile_replaced": False,
            "pre_rollback_backup_created": False,
            "rollback_execute_ready": False,
            "rollback_execute_blocked_reason": "rollback execute is not implemented",
        }
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)

# ── rollback-preview end ───────────────────────────────────────────────────

# ── rollback-execute start ────────────────────────────────────────────────

ROLLBACK_EXECUTE_ERROR_BASE = {
    "mutation": False, "local_file_mutation": False,
    "dns_mutation": False, "cloudflare_mutation": False,
    "dns_apply": False, "rollback_execute": True,
    "rollback_performed": False, "profile_replaced": False,
    "pre_rollback_backup_created": False,
    "manual_recovery_required": False,
}

_PRE_ROLLBACK_BACKUP_ID_RE = re.compile(
    r"^cloudflare-dns-profile\.json\.pre-rollback\.\d{8}-\d{6}\.[0-9a-f]{8}\.bak$"
)


def _redact_pre_rollback_backup_id(backup_filename):
    """Redact pre-rollback backup filename for display."""
    if not backup_filename:
        return "***"
    parts = backup_filename.split(".")
    if len(parts) >= 7:
        ts = parts[4] if len(parts) > 4 else "***"
        hex8 = parts[5] if len(parts) > 5 else "***"
        return f"cloudflare-dns-profile.json.pre-rollback.{ts}.{hex8}.bak"
    return "***"


def _compute_sha256_hex(data_bytes):
    """Compute sha256 hex digest of bytes."""
    return hashlib.sha256(data_bytes).hexdigest()


def run_rollback_execute(backup_id, allow_production, confirm_hostname,
                         confirm_rollback_phrase, yes_flag):
    """Run rollback execute. Returns result dict."""
    base_err = dict(ROLLBACK_EXECUTE_ERROR_BASE)

    # ── Step 0: Validate yes flag ──
    if not yes_flag:
        return {"ok": False, "error": "--yes is required for rollback execute",
                **base_err}

    # ── Step 1: Validate fake-root ──
    if not allow_production:
        return {"ok": False, "error": "--allow-production-output is required",
                **base_err}

    physical_source, root_err = resolve_production_physical_path()
    if root_err:
        return {"ok": False, "error": root_err, **base_err}

    # ── Step 2: Validate current parent ──
    parent_err = validate_production_parent(physical_source)
    if parent_err:
        return {"ok": False, "error": parent_err, **base_err}

    # ── Step 3: Validate backup dir ──
    backup_dir = os.path.join(os.path.dirname(physical_source), "backups")
    if os.path.islink(backup_dir):
        return {"ok": False, "error": "backup directory symlink is not allowed",
                **base_err}
    if not os.path.exists(backup_dir):
        # Create under fake-root only
        try:
            os.makedirs(backup_dir, mode=0o700, exist_ok=True)
        except OSError:
            return {"ok": False, "error": "cannot create backup directory",
                    **base_err}
    if not os.path.isdir(backup_dir):
        return {"ok": False, "error": "backup directory is not a directory",
                **base_err}
    try:
        dir_mode = stat.S_IMODE(os.stat(backup_dir).st_mode)
        if dir_mode != 0o700:
            return {"ok": False, "error": "backup directory mode must be 0700",
                    **base_err}
    except OSError:
        return {"ok": False, "error": "cannot stat backup directory", **base_err}

    # ── Step 4: Validate backup ID ──
    id_err = validate_backup_id(backup_id)
    if id_err:
        return {"ok": False, "error": id_err, **base_err}

    # ── Step 5: Validate current profile ──
    current_status, current_data, current_err = load_and_validate_profile(
        physical_source, "current profile"
    )
    if current_err:
        return {"ok": False, "error": current_err,
                "current_profile_status": current_status, **base_err}

    # ── Step 6: Validate backup profile ──
    backup_path = os.path.join(backup_dir, backup_id)
    backup_status, backup_data, backup_err = load_and_validate_profile(
        backup_path, "backup profile"
    )
    if backup_err:
        return {"ok": False, "error": backup_err,
                "current_profile_status": current_status,
                "backup_profile_status": backup_status, **base_err}

    # ── Step 7: Validate hostname match ──
    current_node = current_data.get("nodePrefix", "")
    current_zone = current_data.get("zoneName", "")
    current_hostname = f"{current_node}.{current_zone}"

    backup_node = backup_data.get("nodePrefix", "")
    backup_zone = backup_data.get("zoneName", "")
    backup_hostname = f"{backup_node}.{backup_zone}"

    if current_hostname != backup_hostname:
        return {"ok": False, "error": "current and backup hostnames do not match",
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": False,
                **base_err}

    # ── Step 8: Validate confirm-hostname ──
    if not confirm_hostname:
        return {"ok": False, "error": "confirm-hostname is required for rollback execute",
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": False,
                **base_err}
    if confirm_hostname != current_hostname:
        return {"ok": False, "error": "confirmation hostname does not match rollback target",
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": False,
                **base_err}

    # ── Step 9: Validate rollback phrase ──
    if not confirm_rollback_phrase:
        return {"ok": False, "error": "confirm-rollback-profile is required for rollback execute",
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": True,
                "rollback_phrase_required": True, "rollback_phrase_matched": False,
                **base_err}
    if confirm_rollback_phrase != "rollback profile":
        return {"ok": False, "error": "rollback phrase does not match",
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": True,
                "rollback_phrase_required": True, "rollback_phrase_matched": False,
                **base_err}

    # ── Step 10: Read selected backup bytes ──
    try:
        with open(backup_path, "rb") as f:
            backup_bytes = f.read()
    except OSError:
        return {"ok": False, "error": "cannot read backup profile",
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": True,
                "rollback_phrase_required": True, "rollback_phrase_matched": True,
                **base_err}

    # ── Step 11: Capture current identity ──
    try:
        with open(physical_source, "rb") as f:
            current_bytes = f.read()
        current_sha = _compute_sha256_hex(current_bytes)
        current_stat = os.stat(physical_source)
        current_inode = current_stat.st_ino
        current_mtime = current_stat.st_mtime_ns
        current_size = current_stat.st_size
    except OSError:
        return {"ok": False, "error": "cannot read current profile for identity check",
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": True,
                "rollback_phrase_required": True, "rollback_phrase_matched": True,
                **base_err}

    # ── Test hook: PREBACKUP_FAIL ──
    if os.environ.get("NANOBK_TEST_FORCE_ROLLBACK_PREBACKUP_FAIL") == "1":
        return {"ok": False, "error": "pre-rollback backup failed (test hook)",
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": True,
                "rollback_phrase_required": True, "rollback_phrase_matched": True,
                "current_identity_checked": True,
                **base_err}

    # ── Step 12: Create pre-rollback backup ──
    from datetime import datetime, timezone
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    rand = secrets.token_hex(4)
    pre_backup_filename = f"cloudflare-dns-profile.json.pre-rollback.{ts}.{rand}.bak"
    pre_backup_path = os.path.join(backup_dir, pre_backup_filename)

    pre_backup_created = False
    try:
        tmp_fd, tmp_path = tempfile.mkstemp(
            dir=backup_dir, prefix=".nanobk-pre-rollback-", suffix=".tmp"
        )
        os.write(tmp_fd, current_bytes)
        os.fsync(tmp_fd)
        os.close(tmp_fd)
        tmp_fd = None
        os.chmod(tmp_path, 0o600)

        # Hard-link to final path
        try:
            os.link(tmp_path, pre_backup_path)
            os.unlink(tmp_path)
            tmp_path = None
        except (FileExistsError, OSError):
            if tmp_path and os.path.exists(tmp_path):
                os.unlink(tmp_path)
            return {"ok": False, "error": "pre-rollback backup finalize failed",
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    **base_err}

        # Verify pre-backup
        pre_st = os.stat(pre_backup_path)
        if stat.S_IMODE(pre_st.st_mode) != 0o600:
            return {"ok": False, "error": "pre-rollback backup mode verification failed",
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    **base_err}
        if pre_st.st_size != len(current_bytes):
            return {"ok": False, "error": "pre-rollback backup size mismatch",
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    **base_err}

        with open(pre_backup_path, "rb") as f:
            verify_bytes = f.read()
        if _compute_sha256_hex(verify_bytes) != current_sha:
            return {"ok": False, "error": "pre-rollback backup sha256 mismatch",
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    **base_err}

        # Verify JSON parses
        json.loads(verify_bytes)
        pre_backup_created = True

    except (OSError, json.JSONDecodeError) as e:
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
        return {"ok": False, "error": "pre-rollback backup failed",
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": True,
                "rollback_phrase_required": True, "rollback_phrase_matched": True,
                "current_identity_checked": True,
                **base_err}

    # ── Test hook: AFTER_PREBACKUP_FAIL ──
    if os.environ.get("NANOBK_TEST_FORCE_ROLLBACK_AFTER_PREBACKUP_FAIL") == "1":
        return {"ok": False, "error": "rollback aborted after pre-backup (test hook)",
                "local_file_mutation": True,
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": True,
                "rollback_phrase_required": True, "rollback_phrase_matched": True,
                "current_identity_checked": True,
                "pre_rollback_backup_created": True,
                "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename),
                "manual_recovery_required": False,
                "mutation": False,
                "dns_mutation": False,
                "cloudflare_mutation": False,
                "dns_apply": False,
                "rollback_execute": True,
                "rollback_performed": False,
                "profile_replaced": False,
            }

    # ── Step 13: Re-check current identity ──
    try:
        re_stat = os.stat(physical_source)
        re_inode = re_stat.st_ino
        re_mtime = re_stat.st_mtime_ns
        re_size = re_stat.st_size
        if re_inode != current_inode or re_mtime != current_mtime or re_size != current_size:
            return {**base_err, "ok": False, "error": "current profile changed before rollback",
                    "local_file_mutation": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename)}

        with open(physical_source, "rb") as f:
            re_bytes = f.read()
        if _compute_sha256_hex(re_bytes) != current_sha:
            return {**base_err, "ok": False, "error": "current profile changed before rollback",
                    "local_file_mutation": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename)}
    except OSError:
        return {**base_err, "ok": False, "error": "cannot re-check current profile identity",
                "local_file_mutation": True,
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": True,
                "rollback_phrase_required": True, "rollback_phrase_matched": True,
                "current_identity_checked": True,
                "pre_rollback_backup_created": True,
                "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename)}

    # ── Step 14: Create temp file ──
    parent_dir = os.path.dirname(physical_source)
    tmp_replace_fd = None
    tmp_replace_path = None

    try:
        tmp_replace_fd, tmp_replace_path = tempfile.mkstemp(
            dir=parent_dir, prefix=".nanobk-rollback-", suffix=".tmp"
        )

        # ── Test hook: TEMP_WRITE_FAIL ──
        if os.environ.get("NANOBK_TEST_FORCE_ROLLBACK_TEMP_WRITE_FAIL") == "1":
            os.close(tmp_replace_fd)
            tmp_replace_fd = None
            if tmp_replace_path and os.path.exists(tmp_replace_path):
                os.unlink(tmp_replace_path)
                tmp_replace_path = None
            return {**base_err, "ok": False, "error": "temp write failed (test hook)",
                    "local_file_mutation": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename)}

        os.write(tmp_replace_fd, backup_bytes)
        os.fsync(tmp_replace_fd)
        os.close(tmp_replace_fd)
        tmp_replace_fd = None
        os.chmod(tmp_replace_path, 0o600)

        # ── Step 15: Validate temp ──
        try:
            with open(tmp_replace_path, "rb") as f:
                tmp_bytes = f.read()
            json.loads(tmp_bytes)
        except (json.JSONDecodeError, OSError):
            if tmp_replace_path and os.path.exists(tmp_replace_path):
                os.unlink(tmp_replace_path)
            return {**base_err, "ok": False, "error": "temp file validation failed",
                    "local_file_mutation": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename)}

        # ── Test hook: AFTER_TEMP_WRITE_FAIL ──
        if os.environ.get("NANOBK_TEST_FORCE_ROLLBACK_AFTER_TEMP_WRITE_FAIL") == "1":
            if tmp_replace_path and os.path.exists(tmp_replace_path):
                os.unlink(tmp_replace_path)
                tmp_replace_path = None
            return {**base_err, "ok": False, "error": "temp write validation failed (test hook)",
                    "local_file_mutation": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename)}

        # ── Test hook: CHANGE_BEFORE_REPLACE ──
        if os.environ.get("NANOBK_TEST_FORCE_ROLLBACK_CHANGE_BEFORE_REPLACE") == "1":
            # Simulate current profile changing after temp validation
            try:
                modified_data = dict(current_data)
                modified_data["_hook_marker"] = "changed"
                modified_bytes = json.dumps(modified_data, indent=2, sort_keys=True).encode("utf-8") + b"\n"
                with open(physical_source, "wb") as f:
                    f.write(modified_bytes)
                    f.flush()
                    os.fsync(f.fileno())
                os.chmod(physical_source, 0o600)
            except OSError:
                pass

        # ── Step 16: Re-stat current immediately before replace ──
        try:
            final_pre_stat = os.stat(physical_source)
        except OSError:
            if tmp_replace_path and os.path.exists(tmp_replace_path):
                os.unlink(tmp_replace_path)
            return {**base_err, "ok": False, "error": "cannot stat current profile before replace",
                    "local_file_mutation": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename)}

        # ── Step 16b: Final pre-replace identity guard ──
        if (final_pre_stat.st_ino != current_inode or
                final_pre_stat.st_mtime_ns != current_mtime or
                final_pre_stat.st_size != current_size):
            if tmp_replace_path and os.path.exists(tmp_replace_path):
                os.unlink(tmp_replace_path)
            return {**base_err, "ok": False, "error": "current profile changed before rollback",
                    "local_file_mutation": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename)}

        try:
            with open(physical_source, "rb") as f:
                final_pre_bytes = f.read()
            if _compute_sha256_hex(final_pre_bytes) != current_sha:
                if tmp_replace_path and os.path.exists(tmp_replace_path):
                    os.unlink(tmp_replace_path)
                return {**base_err, "ok": False, "error": "current profile changed before rollback",
                        "local_file_mutation": True,
                        "current_profile_status": current_status,
                        "backup_profile_status": backup_status,
                        "confirmation_required": True, "confirmation_matched": True,
                        "rollback_phrase_required": True, "rollback_phrase_matched": True,
                        "current_identity_checked": True,
                        "pre_rollback_backup_created": True,
                        "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename)}
        except OSError:
            if tmp_replace_path and os.path.exists(tmp_replace_path):
                os.unlink(tmp_replace_path)
            return {**base_err, "ok": False, "error": "cannot read current profile for final identity check",
                    "local_file_mutation": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename)}

        # ── Step 17: rollback-execute marker block ──
        # rollback-execute start
        os.replace(tmp_replace_path, physical_source)
        tmp_replace_path = None  # consumed by replace
        dir_fd = None
        try:
            dir_fd = os.open(parent_dir, os.O_RDONLY)
            os.fsync(dir_fd)
        except OSError:
            pass  # best-effort fsync
        finally:
            if dir_fd is not None:
                try:
                    os.close(dir_fd)
                except OSError:
                    pass
        # rollback-execute end

        # ── Step 18: Re-read final profile ──
        try:
            with open(physical_source, "rb") as f:
                final_bytes = f.read()
        except OSError:
            return {**base_err, "ok": False, "error": "cannot read final profile after replace",
                    "local_file_mutation": True,
                    "profile_replaced": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "final_profile_status": "unreadable",
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename),
                    "manual_recovery_required": True}

        # ── Step 19: Validate final profile ──
        try:
            final_data = json.loads(final_bytes)
        except json.JSONDecodeError:
            return {**base_err, "ok": False, "error": "final profile is not valid JSON after replace",
                    "local_file_mutation": True,
                    "profile_replaced": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "final_profile_status": "invalid_json",
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename),
                    "manual_recovery_required": True}

        if not isinstance(final_data, dict):
            final_status = "unsupported_schema"
        elif "zoneName" not in final_data or "nodePrefix" not in final_data:
            final_status = "unsupported_schema"
        else:
            final_status = "valid"

        # ── Test hook: AFTER_REPLACE_VALIDATE_FAIL ──
        if os.environ.get("NANOBK_TEST_FORCE_ROLLBACK_AFTER_REPLACE_VALIDATE_FAIL") == "1":
            return {**base_err, "ok": False, "error": "post-replace validation failed (test hook)",
                    "local_file_mutation": True,
                    "profile_replaced": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "final_profile_status": final_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename),
                    "manual_recovery_required": True}

        # ── Step 20: Compare final to selected backup ──
        final_sha = _compute_sha256_hex(final_bytes)
        backup_sha = _compute_sha256_hex(backup_bytes)
        bytes_match = (final_sha == backup_sha)

        if not bytes_match:
            return {**base_err, "ok": False, "error": "final profile does not match selected backup",
                    "local_file_mutation": True,
                    "profile_replaced": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "final_profile_status": final_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename),
                    "manual_recovery_required": True}

        if final_status != "valid":
            return {**base_err, "ok": False, "error": "final profile validation failed",
                    "local_file_mutation": True,
                    "profile_replaced": True,
                    "current_profile_status": current_status,
                    "backup_profile_status": backup_status,
                    "final_profile_status": final_status,
                    "confirmation_required": True, "confirmation_matched": True,
                    "rollback_phrase_required": True, "rollback_phrase_matched": True,
                    "current_identity_checked": True,
                    "pre_rollback_backup_created": True,
                    "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename),
                    "manual_recovery_required": True}

        # ── Step 21: Success ──
        try:
            dir_mode = format(stat.S_IMODE(os.stat(backup_dir).st_mode), "03o")
        except OSError:
            dir_mode = "unknown"

        return {
            "ok": True,
            "mutation": False,
            "local_file_mutation": True,
            "dns_mutation": False,
            "cloudflare_mutation": False,
            "dns_apply": False,
            "rollback_execute": True,
            "rollback_performed": True,
            "profile_replaced": True,
            "pre_rollback_backup_created": True,
            "current_profile_status_before": current_status,
            "backup_profile_status": backup_status,
            "final_profile_status": "valid",
            "backup_id_redacted": backup_id,
            "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename),
            "confirmation_required": True,
            "confirmation_matched": True,
            "rollback_phrase_required": True,
            "rollback_phrase_matched": True,
            "current_identity_checked": True,
            "production_fake_root": True,
            "manual_recovery_required": False,
        }

    except OSError as e:
        # Clean up temp on failure
        if tmp_replace_fd is not None:
            try:
                os.close(tmp_replace_fd)
            except OSError:
                pass
        if tmp_replace_path and os.path.exists(tmp_replace_path):
            try:
                os.unlink(tmp_replace_path)
            except OSError:
                pass
        return {**base_err, "ok": False, "error": "rollback execute failed",
                "local_file_mutation": True,
                "current_profile_status": current_status,
                "backup_profile_status": backup_status,
                "confirmation_required": True, "confirmation_matched": True,
                "rollback_phrase_required": True, "rollback_phrase_matched": True,
                "current_identity_checked": True,
                "pre_rollback_backup_created": pre_backup_created,
                "pre_rollback_backup_id_redacted": _redact_pre_rollback_backup_id(pre_backup_filename) if pre_backup_created else "***"}


def output_rollback_execute_text(result):
    """Print human-readable rollback execute result."""
    print()
    if result.get("ok"):
        print("  Rollback executed under fake-root test mode.")
        print("  Current profile was replaced with selected backup profile.")
        print("  Pre-rollback backup was created.")
        print("  DNS has not been applied.")
        print("  Cloudflare was not called.")
        print("  Raw profile and backup content were intentionally not printed.")
    else:
        print("  Rollback execute failed.")
        error = result.get("error")
        if error:
            print(f"  Error: {error}")
        if result.get("pre_rollback_backup_created"):
            print("  Pre-rollback backup was created.")
        if result.get("profile_replaced"):
            print("  Profile was replaced.")
        if result.get("manual_recovery_required"):
            print("  Manual recovery may be required.")
    print()


def output_rollback_execute_error(message, json_mode=False):
    """Print rollback execute error message."""
    if json_mode:
        result = {
            "ok": False, "error": message,
            "mutation": False, "local_file_mutation": False,
            "dns_mutation": False, "cloudflare_mutation": False,
            "dns_apply": False, "rollback_execute": True,
            "rollback_performed": False, "profile_replaced": False,
            "pre_rollback_backup_created": False,
            "manual_recovery_required": False,
        }
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)

# ── rollback-execute end ──────────────────────────────────────────────────


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
        description="NanoBK DNS Profile (preview / generate / replace preview / backup)"
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
    generate_parser = sub.add_parser("generate", help="Write DNS profile to output path")
    generate_parser.add_argument("--zone", help="Domain zone (e.g. example.com)")
    generate_parser.add_argument("--node", help="Node prefix (e.g. proxy)")
    generate_parser.add_argument("--ipv4", help="IPv4 address for A record")
    generate_parser.add_argument("--ipv6", help="IPv6 address for AAAA record (optional)")
    generate_parser.add_argument("--output", help="Output file path")
    generate_parser.add_argument("--yes", action="store_true", help="Confirm file write")
    generate_parser.add_argument("--allow-production-output", action="store_true",
                                 help="Allow production /etc/nanobk output path")
    generate_parser.add_argument("--confirm-hostname",
                                 help="Exact hostname confirmation for production output")
    generate_parser.add_argument("--json", action="store_true", help="JSON output")
    generate_parser.add_argument("--allow-documentation-ips", action="store_true",
                                 help="Allow documentation IP ranges (tests/examples only)")

    # replace subcommand (with preview sub-subcommand)
    replace_parser = sub.add_parser("replace", help="Profile replacement operations")
    replace_sub = replace_parser.add_subparsers(dest="replace_command")

    replace_preview_parser = replace_sub.add_parser("preview", help="Read-only replace preview (fake-root only)")
    replace_preview_parser.add_argument("--zone", help="Domain zone (e.g. example.com)")
    replace_preview_parser.add_argument("--node", help="Node prefix (e.g. proxy)")
    replace_preview_parser.add_argument("--ipv4", help="IPv4 address for A record")
    replace_preview_parser.add_argument("--ipv6", help="IPv6 address for AAAA record (optional)")
    replace_preview_parser.add_argument("--output", help="Production output path")
    replace_preview_parser.add_argument("--allow-production-output", action="store_true",
                                        help="Allow production /etc/nanobk output path")
    replace_preview_parser.add_argument("--confirm-hostname",
                                        help="Exact hostname confirmation")
    replace_preview_parser.add_argument("--json", action="store_true", help="JSON output")
    replace_preview_parser.add_argument("--allow-documentation-ips", action="store_true",
                                        help="Allow documentation IP ranges (tests/examples only)")

    # backup subcommand
    backup_parser = sub.add_parser("backup", help="Backup existing fake-root production profile")
    backup_parser.add_argument("--profile", help="Source profile path (exact /etc/nanobk/cloudflare-dns-profile.json)")
    backup_parser.add_argument("--allow-production-output", action="store_true",
                               help="Allow production /etc/nanobk path")
    backup_parser.add_argument("--confirm-hostname",
                               help="Exact hostname confirmation from source profile")
    backup_parser.add_argument("--yes", action="store_true", help="Confirm backup write")
    backup_parser.add_argument("--json", action="store_true", help="JSON output")

    # rollback subcommand (with preview sub-subcommand)
    rollback_parser = sub.add_parser("rollback", help="Rollback operations")
    rollback_sub = rollback_parser.add_subparsers(dest="rollback_command")

    rollback_preview_parser = rollback_sub.add_parser("preview", help="Read-only rollback preview (fake-root only)")
    rollback_preview_parser.add_argument("--backup-id", help="Backup filename (e.g. cloudflare-dns-profile.json.TIMESTAMP.HEX.bak)")
    rollback_preview_parser.add_argument("--allow-production-output", action="store_true",
                                         help="Allow production /etc/nanobk path")
    rollback_preview_parser.add_argument("--confirm-hostname",
                                         help="Exact hostname confirmation")
    rollback_preview_parser.add_argument("--json", action="store_true", help="JSON output")

    rollback_execute_parser = rollback_sub.add_parser("execute", help="Execute rollback (fake-root only)")
    rollback_execute_parser.add_argument("--backup-id", help="Backup filename")
    rollback_execute_parser.add_argument("--allow-production-output", action="store_true",
                                         help="Allow production /etc/nanobk path")
    rollback_execute_parser.add_argument("--confirm-hostname",
                                         help="Exact hostname confirmation")
    rollback_execute_parser.add_argument("--confirm-rollback-profile",
                                         help='Exact rollback phrase (must be "rollback profile")')
    rollback_execute_parser.add_argument("--yes", action="store_true",
                                         help="Confirm rollback execution")
    rollback_execute_parser.add_argument("--json", action="store_true", help="JSON output")

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
                              args.output, args.allow_documentation_ips,
                              args.allow_production_output, args.confirm_hostname)

        if not result.get("ok", False):
            output_generate_error(result.get("error", "unknown error"), args.json)
            sys.exit(1)

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            output_generate_text(result)

    elif args.command == "replace":
        sub_cmd = getattr(args, "replace_command", None)
        if sub_cmd == "preview":
            if not args.zone:
                output_replace_preview_error("zone is required", args.json)
                sys.exit(1)
            if not args.node:
                output_replace_preview_error("node is required", args.json)
                sys.exit(1)
            if not args.ipv4:
                output_replace_preview_error("ipv4 is required", args.json)
                sys.exit(1)
            if not args.output:
                output_replace_preview_error("output path is required", args.json)
                sys.exit(1)
            if not args.allow_production_output:
                output_replace_preview_error("--allow-production-output is required", args.json)
                sys.exit(1)
            if not args.confirm_hostname:
                output_replace_preview_error("confirm-hostname is required for replace preview", args.json)
                sys.exit(1)

            result = run_replace_preview(
                args.zone, args.node, args.ipv4, args.ipv6,
                args.output, args.allow_documentation_ips,
                args.allow_production_output, args.confirm_hostname
            )

            # Always output full result (including status fields on failure)
            if args.json:
                print(json.dumps(result, indent=2))
            else:
                if result.get("ok"):
                    output_replace_preview_text(result)
                else:
                    output_replace_preview_text(result)

            if not result.get("ok", False):
                sys.exit(1)
        else:
            parser.print_help()
            sys.exit(1)

    elif args.command == "backup":
        if not args.profile:
            output_backup_error("profile path is required", args.json)
            sys.exit(1)
        if not args.allow_production_output:
            output_backup_error("--allow-production-output is required", args.json)
            sys.exit(1)
        if not args.confirm_hostname:
            output_backup_error("confirm-hostname is required for profile backup", args.json)
            sys.exit(1)
        if not args.yes:
            output_backup_error("this command writes a backup file; --yes is required", args.json)
            sys.exit(1)

        result = run_backup(args.profile, args.allow_production_output,
                            args.confirm_hostname)

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            if result.get("ok"):
                output_backup_text(result)
            else:
                output_backup_text(result)

        if not result.get("ok", False):
            sys.exit(1)

    elif args.command == "rollback":
        sub_cmd = getattr(args, "rollback_command", None)
        if sub_cmd == "preview":
            if not args.backup_id:
                output_rollback_preview_error("backup-id is required", args.json)
                sys.exit(1)
            if not args.allow_production_output:
                output_rollback_preview_error("--allow-production-output is required", args.json)
                sys.exit(1)

            result = run_rollback_preview(
                args.backup_id, args.allow_production_output, args.confirm_hostname
            )

            if args.json:
                print(json.dumps(result, indent=2))
            else:
                if result.get("ok"):
                    output_rollback_preview_text(result)
                else:
                    output_rollback_preview_text(result)

            if not result.get("ok", False):
                sys.exit(1)
        elif sub_cmd == "execute":
            if not args.backup_id:
                output_rollback_execute_error("backup-id is required", args.json)
                sys.exit(1)
            if not args.allow_production_output:
                output_rollback_execute_error("--allow-production-output is required", args.json)
                sys.exit(1)
            if not args.yes:
                output_rollback_execute_error("--yes is required for rollback execute", args.json)
                sys.exit(1)

            result = run_rollback_execute(
                args.backup_id, args.allow_production_output,
                args.confirm_hostname, args.confirm_rollback_profile,
                args.yes
            )

            if args.json:
                print(json.dumps(result, indent=2))
            else:
                output_rollback_execute_text(result)

            if not result.get("ok", False):
                sys.exit(1)
        else:
            parser.print_help()
            sys.exit(1)

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
