#!/usr/bin/env python3
"""
NanoBK DNS Subdomain Availability Check

GET-only, read-only check for whether a hostname already has DNS records.
No DNS mutation. No Cloudflare POST/PATCH/DELETE. No profile writes.

Usage:
    python3 lib/nanobk_cf_dns_availability.py check --zone DOMAIN --node NODE --api-env PATH [--json]

Test hook:
    NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE=/path/to/fixture.json
"""

import argparse
import json
import os
import re
import stat
import sys
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nanobk_cf_zones import parse_env_file, mask_domain
from nanobk_ip_detect import mask_ipv4, mask_ipv6


# ── Validation ──────────────────────────────────────────────────────────────

_DNS_LABEL_RE = re.compile(r"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$")
_NANOBK_MARKER = "managed-by=nanobk"


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


# ── Content masking ─────────────────────────────────────────────────────────

def mask_content(record_type, content):
    """Mask record content based on type."""
    if record_type == "A":
        return mask_ipv4(content)
    elif record_type == "AAAA":
        return mask_ipv6(content)
    elif record_type == "CNAME":
        return mask_domain(content.rstrip(".")) + ("." if content.endswith(".") else "")
    else:
        return "[redacted]"


def mask_name(name, zone):
    """Mask record name relative to zone."""
    if name == zone:
        return mask_domain(name)
    if name.endswith("." + zone):
        prefix = name[:-(len(zone) + 1)]
        return f"{prefix}.{mask_domain(zone)}"
    return mask_domain(name)


# ── Ownership detection ─────────────────────────────────────────────────────

def is_nanobk_owned(record):
    """Check if a record has NanoBK ownership marker in comment."""
    comment = record.get("comment", "") or ""
    return _NANOBK_MARKER in comment


# ── Transport ───────────────────────────────────────────────────────────────

def fetch_records_real(token, zone_id, hostname):
    """Fetch DNS records from Cloudflare API (GET-only)."""
    url = (f"https://api.cloudflare.com/client/v4/zones/{zone_id}"
           f"/dns_records?name={hostname}&per_page=100")
    req = urllib.request.Request(url, method="GET")
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


def fetch_records_fake(fake_path):
    """Load fake response from fixture file."""
    try:
        with open(fake_path, "r") as f:
            data = json.load(f)
    except FileNotFoundError:
        raise RuntimeError(f"Fake response file not found: {fake_path}") from None
    except json.JSONDecodeError:
        raise RuntimeError("Fake response contains invalid JSON") from None
    except OSError as e:
        raise RuntimeError(f"Cannot read fake response file: {e}") from None

    if not data.get("success", False):
        errors = data.get("errors", [])
        msg = "; ".join(str(e.get("message", "unknown")) for e in errors) or "unknown error"
        raise RuntimeError(f"Cloudflare API error: {msg}")

    return data.get("result", [])


def fetch_records(token, zone_id, hostname):
    """Fetch records using real or fake transport."""
    fake_path = os.environ.get("NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE")
    if fake_path:
        return fetch_records_fake(fake_path)
    return fetch_records_real(token, zone_id, hostname)


def fetch_records_for_node(node, zone, zone_id, token, fake_map=None):
    """Fetch records for a single node, using fake map if provided."""
    hostname = f"{node}.{zone}"
    if fake_map is not None:
        if node in fake_map:
            node_response = fake_map[node]
            if not node_response.get("success", False):
                errors = node_response.get("errors", [])
                msg = "; ".join(str(e.get("message", "unknown")) for e in errors) or "unknown error"
                raise RuntimeError(f"Cloudflare API error: {msg}")
            return node_response.get("result", [])
        else:
            raise RuntimeError(f"Node '{node}' not found in fake response map")
    return fetch_records(token, zone_id, hostname)


def load_fake_map():
    """Load fake response map if env var is set. Returns dict or None."""
    map_path = os.environ.get("NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP")
    if not map_path:
        return None
    try:
        with open(map_path, "r") as f:
            data = json.load(f)
    except FileNotFoundError:
        raise RuntimeError(f"Fake response map not found: {map_path}") from None
    except json.JSONDecodeError:
        raise RuntimeError("Fake response map contains invalid JSON") from None
    except OSError as e:
        raise RuntimeError(f"Cannot read fake response map: {e}") from None
    if not isinstance(data, dict):
        raise RuntimeError("Fake response map must be a JSON object")
    return data


# ── Availability logic ──────────────────────────────────────────────────────

def analyze_records(records, zone):
    """Analyze records and return availability status."""
    if not records:
        return {
            "status": "available",
            "available": True,
            "manual_review_required": False,
            "records_found": 0,
            "records": [],
        }

    sanitized = []
    all_nanobk = True
    has_conflict = False

    for rec in records:
        rtype = rec.get("type", "UNKNOWN")
        name = rec.get("name", "")
        content = rec.get("content", "")
        proxied = rec.get("proxied", False)
        owned = is_nanobk_owned(rec)

        if not owned:
            all_nanobk = False

        # Determine if this record is a conflict
        if rtype in ("A", "AAAA"):
            if proxied:
                has_conflict = True
            elif not owned:
                has_conflict = True
        elif rtype == "CNAME":
            has_conflict = True
        else:
            # MX, TXT, NS, etc.
            has_conflict = True

        sanitized.append({
            "type": rtype,
            "name_redacted": mask_name(name, zone),
            "content_redacted": mask_content(rtype, content),
            "proxied": proxied,
            "owned_by_nanobk": owned,
        })

    records_found = len(records)

    if all_nanobk and not has_conflict:
        return {
            "status": "nanobk_owned",
            "available": False,
            "owned_by_nanobk": True,
            "manual_review_required": False,
            "records_found": records_found,
            "records": sanitized,
        }

    if has_conflict:
        return {
            "status": "conflict",
            "available": False,
            "manual_review_required": True,
            "records_found": records_found,
            "records": sanitized,
        }

    # Fallback
    return {
        "status": "manual_review",
        "available": False,
        "manual_review_required": True,
        "records_found": records_found,
        "records": sanitized,
    }


def run_check(zone, node, api_env_path):
    """Run availability check. Returns result dict."""
    # Validate inputs
    zone_err = validate_zone(zone)
    if zone_err:
        return {"ok": False, "error": zone_err, "mutation": False,
                "profile_write": False, "status": "failed",
                "available": False, "manual_review_required": True}

    node_err = validate_node(node)
    if node_err:
        return {"ok": False, "error": node_err, "mutation": False,
                "profile_write": False, "status": "failed",
                "available": False, "manual_review_required": True}

    hostname = f"{node}.{zone}"

    # Parse api-env
    try:
        env = parse_env_file(api_env_path)
    except FileNotFoundError:
        return {"ok": False, "error": "api-env file not found", "mutation": False,
                "profile_write": False, "status": "failed",
                "available": False, "manual_review_required": True}
    except PermissionError as e:
        return {"ok": False, "error": str(e), "mutation": False,
                "profile_write": False, "status": "failed",
                "available": False, "manual_review_required": True}
    except ValueError as e:
        return {"ok": False, "error": str(e), "mutation": False,
                "profile_write": False, "status": "failed",
                "available": False, "manual_review_required": True}

    # Require full zone binding
    token = env.get("CF_API_TOKEN")
    zone_id = env.get("CF_ZONE_ID")
    zone_name = env.get("CF_ZONE_NAME")

    if not token:
        return {"ok": False, "error": "CF_API_TOKEN is required", "mutation": False,
                "profile_write": False, "status": "failed",
                "available": False, "manual_review_required": True}
    if not zone_id:
        return {"ok": False, "error": "CF_ZONE_ID is required for availability check", "mutation": False,
                "profile_write": False, "status": "failed",
                "available": False, "manual_review_required": True}
    if not zone_name:
        return {"ok": False, "error": "CF_ZONE_NAME is required for availability check", "mutation": False,
                "profile_write": False, "status": "failed",
                "available": False, "manual_review_required": True}

    # Zone mismatch check
    if zone.lower() != zone_name.lower():
        return {"ok": False, "error": "zone mismatch: --zone does not match CF_ZONE_NAME in api-env",
                "mutation": False, "profile_write": False, "status": "failed",
                "available": False, "manual_review_required": True}

    # Fetch records
    try:
        records = fetch_records(token, zone_id, hostname)
    except RuntimeError as e:
        return {"ok": False, "error": str(e), "mutation": False,
                "profile_write": False, "status": "failed",
                "available": False, "manual_review_required": True}

    # Analyze
    result = analyze_records(records, zone)
    result["ok"] = True
    result["mutation"] = False
    result["profile_write"] = False
    result["hostname_redacted"] = f"{node}.{mask_domain(zone)}"
    return result


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable availability report."""
    print()
    print("  NanoBK DNS availability check")
    print()

    print("  Hostname:")
    print(f"    {result.get('hostname_redacted', '***')}")
    print()

    print("  Result:")
    print(f"    status: {result.get('status', 'unknown')}")
    print(f"    available: {str(result.get('available', False)).lower()}")
    print(f"    records_found: {result.get('records_found', 0)}")
    print(f"    manual_review_required: {str(result.get('manual_review_required', True)).lower()}")

    records = result.get("records", [])
    if records:
        print()
        print("  Records:")
        for rec in records:
            rtype = rec.get("type", "?")
            name = rec.get("name_redacted", "***")
            content = rec.get("content_redacted", "***")
            proxied = rec.get("proxied", False)
            owned = rec.get("owned_by_nanobk", False)
            print(f"    {rtype:6s} {name}  {content}  proxied={str(proxied).lower()}  owned_by_nanobk={str(owned).lower()}")

    print()
    print("  No DNS records were created, updated, or deleted.")
    print("  No DNS profile was written.")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "mutation": False,
                  "profile_write": False, "status": "failed",
                  "available": False, "manual_review_required": True,
                  "hostname_redacted": "***", "records_found": 0, "records": []}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Summary logic ───────────────────────────────────────────────────────────

def parse_nodes(nodes_str):
    """Parse comma-separated node labels. Returns (nodes_list, error_string)."""
    if not nodes_str:
        return ["proxy", "web"], None
    nodes = [n.strip() for n in nodes_str.split(",") if n.strip()]
    if not nodes:
        return None, "no valid nodes provided"
    # Validate each node
    for node in nodes:
        err = validate_node(node)
        if err:
            return None, err
    # Check duplicates
    if len(nodes) != len(set(nodes)):
        return None, "duplicate nodes are not allowed"
    return nodes, None


def validate_env_for_summary(api_env_path, zone):
    """Validate api-env for summary. Returns (env_dict, error_string)."""
    try:
        env = parse_env_file(api_env_path)
    except FileNotFoundError:
        return None, "api-env file not found"
    except PermissionError as e:
        return None, str(e)
    except ValueError as e:
        return None, str(e)

    token = env.get("CF_API_TOKEN")
    zone_id = env.get("CF_ZONE_ID")
    zone_name = env.get("CF_ZONE_NAME")

    if not token:
        return None, "CF_API_TOKEN is required"
    if not zone_id:
        return None, "CF_ZONE_ID is required for availability check"
    if not zone_name:
        return None, "CF_ZONE_NAME is required for availability check"

    if zone.lower() != zone_name.lower():
        return None, "zone mismatch: --zone does not match CF_ZONE_NAME in api-env"

    return env, None


def run_summary(zone, nodes, api_env_path):
    """Run multi-host availability summary. Returns result dict."""
    # Validate zone
    zone_err = validate_zone(zone)
    if zone_err:
        return {"ok": False, "error": zone_err, "mutation": False,
                "profile_write": False, "overall_status": "failed",
                "all_available": False, "any_conflict": False,
                "manual_review_required": True}

    # Validate nodes
    nodes_list, nodes_err = parse_nodes(",".join(nodes))
    if nodes_err:
        return {"ok": False, "error": nodes_err, "mutation": False,
                "profile_write": False, "overall_status": "failed",
                "all_available": False, "any_conflict": False,
                "manual_review_required": True}

    # Validate env
    env, env_err = validate_env_for_summary(api_env_path, zone)
    if env_err:
        return {"ok": False, "error": env_err, "mutation": False,
                "profile_write": False, "overall_status": "failed",
                "all_available": False, "any_conflict": False,
                "manual_review_required": True}

    token = env["CF_API_TOKEN"]
    zone_id = env["CF_ZONE_ID"]

    # Load fake map if available
    try:
        fake_map = load_fake_map()
    except RuntimeError as e:
        return {"ok": False, "error": str(e), "mutation": False,
                "profile_write": False, "overall_status": "failed",
                "all_available": False, "any_conflict": False,
                "manual_review_required": True}

    # Check each node
    hosts = []
    any_failed = False
    any_conflict = False
    any_manual = False
    any_owned = False
    all_available = True

    for node in nodes_list:
        try:
            records = fetch_records_for_node(node, zone, zone_id, token, fake_map)
        except RuntimeError as e:
            hosts.append({
                "node": node,
                "hostname_redacted": f"{node}.{mask_domain(zone)}",
                "status": "failed",
                "available": False,
                "records_found": 0,
                "manual_review_required": True,
                "error": str(e),
            })
            any_failed = True
            all_available = False
            continue

        analysis = analyze_records(records, zone)
        host_result = {
            "node": node,
            "hostname_redacted": f"{node}.{mask_domain(zone)}",
            "status": analysis["status"],
            "available": analysis["available"],
            "records_found": analysis["records_found"],
            "manual_review_required": analysis["manual_review_required"],
        }
        hosts.append(host_result)

        if analysis["status"] == "failed":
            any_failed = True
            all_available = False
        elif analysis["status"] == "conflict":
            any_conflict = True
            all_available = False
        elif analysis["status"] == "manual_review":
            any_manual = True
            all_available = False
        elif analysis["status"] == "nanobk_owned":
            any_owned = True
            all_available = False
        elif not analysis["available"]:
            all_available = False

    # Compute overall status
    if any_failed:
        overall_status = "failed"
        ok = False
        manual_review_required = True
        # Propagate first failure error
        first_failure = next((h for h in hosts if h.get("status") == "failed"), None)
        error_msg = first_failure.get("error", "unknown error") if first_failure else "unknown error"
    elif any_conflict or any_manual:
        overall_status = "manual_review"
        ok = True
        manual_review_required = True
    elif all_available:
        overall_status = "available"
        ok = True
        manual_review_required = False
    elif any_owned and not any_conflict:
        overall_status = "partially_owned"
        ok = True
        manual_review_required = False
    else:
        overall_status = "manual_review"
        ok = True
        manual_review_required = True

    result = {
        "ok": ok,
        "mutation": False,
        "profile_write": False,
        "zone_redacted": mask_domain(zone),
        "nodes": nodes_list,
        "overall_status": overall_status,
        "all_available": all_available and not any_failed,
        "any_conflict": any_conflict,
        "manual_review_required": manual_review_required,
        "hosts": hosts,
    }
    if any_failed:
        result["error"] = error_msg
    return result


def output_summary_text(result):
    """Print human-readable summary report."""
    print()
    print("  NanoBK DNS availability summary")
    print()

    print("  Zone:")
    print(f"    {result.get('zone_redacted', '***')}")
    print()

    hosts = result.get("hosts", [])
    if hosts:
        print("  Hosts:")
        for h in hosts:
            hostname = h.get("hostname_redacted", "***")
            status = h.get("status", "unknown")
            records = h.get("records_found", 0)
            manual = str(h.get("manual_review_required", True)).lower()
            print(f"    {hostname:30s} {status:16s} records={records}  manual_review={manual}")
        print()

    print("  Overall:")
    print(f"    status: {result.get('overall_status', 'unknown')}")
    print(f"    all_available: {str(result.get('all_available', False)).lower()}")
    print(f"    any_conflict: {str(result.get('any_conflict', False)).lower()}")
    print(f"    manual_review_required: {str(result.get('manual_review_required', True)).lower()}")
    print(f"    mutation: false")
    print(f"    profile_write: false")
    print()
    print("  No DNS records were created, updated, or deleted.")
    print("  No DNS profile was written.")
    print()


def output_summary_error(message, json_mode=False):
    """Print summary error message."""
    if json_mode:
        result = {"ok": False, "error": message, "mutation": False,
                  "profile_write": False, "overall_status": "failed",
                  "all_available": False, "any_conflict": False,
                  "manual_review_required": True,
                  "zone_redacted": "***", "nodes": [], "hosts": []}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK DNS Subdomain Availability (GET-only, read-only)"
    )
    sub = parser.add_subparsers(dest="command")

    # check subcommand
    check_parser = sub.add_parser("check", help="Check one hostname availability")
    check_parser.add_argument("--zone", help="Domain zone (e.g. example.com)")
    check_parser.add_argument("--node", help="Node prefix (e.g. proxy)")
    check_parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    check_parser.add_argument("--json", action="store_true", help="JSON output")

    # summary subcommand
    summary_parser = sub.add_parser("summary", help="Summarize multi-host availability")
    summary_parser.add_argument("--zone", help="Domain zone (e.g. example.com)")
    summary_parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    summary_parser.add_argument("--nodes", default="proxy,web", help="Comma-separated node labels (default: proxy,web)")
    summary_parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.command == "check":
        if not args.zone:
            output_error("zone is required", args.json)
            sys.exit(1)
        if not args.node:
            output_error("node is required", args.json)
            sys.exit(1)
        if not args.api_env:
            output_error("api-env is required", args.json)
            sys.exit(1)

        result = run_check(args.zone, args.node, args.api_env)
        if not result.get("ok", False):
            output_error(result.get("error", "unknown error"), args.json)
            sys.exit(1)

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            output_text(result)

    elif args.command == "summary":
        if not args.zone:
            output_summary_error("zone is required", args.json)
            sys.exit(1)
        if not args.api_env:
            output_summary_error("api-env is required", args.json)
            sys.exit(1)

        nodes = [n.strip() for n in args.nodes.split(",") if n.strip()]
        result = run_summary(args.zone, nodes, args.api_env)
        if not result.get("ok", False):
            output_summary_error(result.get("error", "unknown error"), args.json)
            sys.exit(1)

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            output_summary_text(result)

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
