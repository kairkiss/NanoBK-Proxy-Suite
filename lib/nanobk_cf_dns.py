"""
NanoBK Proxy Suite — Cloudflare DNS Dry-Run Plan Helper

Local-only dry-run DNS planning layer.
Validates input and prints a human-readable or JSON plan for Cloudflare
DNS A/AAAA records. Does NOT call the Cloudflare API, does NOT create
DNS records, does NOT deploy Workers, does NOT request certificates,
does NOT create Tunnels or Access apps.

Usage:
    python3 lib/nanobk_cf_dns.py plan --zone example.com --node node --ipv4 203.0.113.10 --ipv6 2001:db8::10
    python3 lib/nanobk_cf_dns.py plan --profile tests/fixtures/cf-dns-profile.example.json
    python3 lib/nanobk_cf_dns.py plan --profile tests/fixtures/cf-dns-profile.example.json --json
    python3 lib/nanobk_cf_dns.py validate-profile --profile tests/fixtures/cf-dns-profile.example.json
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import re
import sys
from dataclasses import dataclass, field
from typing import Any

# ── Constants ────────────────────────────────────────────────────────────────

# DNS label: 1-63 chars, alphanumeric + hyphen, no leading/trailing hyphen
_DNS_LABEL_RE = re.compile(r"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$")

# Secret-like substrings (case-insensitive) that must not appear in profile keys
_SECRET_SUBSTRINGS = [
    "token",
    "secret",
    "private",
    "password",
    "key",
    "cf_api_token",
]

# Keys that are allowed even though they match a secret substring
_ALLOWED_KEYS = {"zoneId"}

# Top-level profile fields that are recognized
_KNOWN_PROFILE_FIELDS = {
    "zoneName",
    "zoneId",
    "nodePrefix",
    "ipv4",
    "ipv6",
    "defaultProxied",
    "reserved",
}

# Known reserved sub-fields
_KNOWN_RESERVED_FIELDS = {"panelPrefix", "nanokPrefix", "nanobPrefix"}


# ── Data classes ─────────────────────────────────────────────────────────────

@dataclass
class DnsPlan:
    """Result of a dry-run DNS plan."""
    zone: str
    node_prefix: str
    ipv4: str | None = None
    ipv6: str | None = None
    default_proxied: bool = False
    reserved_panel: str = "panel"
    reserved_nanok: str = "nanok"
    reserved_nanob: str = "nanob"

    @property
    def node_hostname(self) -> str:
        return f"{self.node_prefix}.{self.zone}"

    @property
    def panel_hostname(self) -> str:
        return f"{self.reserved_panel}.{self.zone}"

    @property
    def nanok_hostname(self) -> str:
        return f"{self.reserved_nanok}.{self.zone}"

    @property
    def nanob_hostname(self) -> str:
        return f"{self.reserved_nanob}.{self.zone}"


# ── Validation helpers ───────────────────────────────────────────────────────

def _is_plausible_dns_name(name: str) -> bool:
    """Check if a string looks like a valid DNS domain name."""
    if not name or len(name) > 253:
        return False
    labels = name.split(".")
    if len(labels) < 2:
        return False
    for label in labels:
        if not _DNS_LABEL_RE.match(label):
            return False
    return True


def _is_dns_label_safe(prefix: str) -> bool:
    """Check if a string is a valid DNS label (single label, no dots)."""
    if not prefix or len(prefix) > 63:
        return False
    return bool(_DNS_LABEL_RE.match(prefix))


def _is_valid_ipv4(addr: str) -> bool:
    """Check if a string is a valid IPv4 address."""
    try:
        parsed = ipaddress.IPv4Address(addr)
        return not parsed.is_loopback and not parsed.is_multicast
    except (ipaddress.AddressValueError, ValueError):
        return False


def _is_valid_ipv6(addr: str) -> bool:
    """Check if a string is a valid IPv6 address."""
    try:
        parsed = ipaddress.IPv6Address(addr)
        return not parsed.is_loopback and not parsed.is_multicast
    except (ipaddress.AddressValueError, ValueError):
        return False


def _check_secret_keys(obj: Any, path: str = "") -> list[str]:
    """Recursively check for secret-like keys in a JSON object.

    Returns a list of error messages for forbidden keys found.
    """
    errors: list[str] = []
    if isinstance(obj, dict):
        for key, value in obj.items():
            full_path = f"{path}.{key}" if path else key
            # Check if key is in allowed list
            if key in _ALLOWED_KEYS:
                # Still recurse into its value
                errors.extend(_check_secret_keys(value, full_path))
                continue
            # Check secret substrings (case-insensitive)
            key_lower = key.lower()
            for substring in _SECRET_SUBSTRINGS:
                if substring in key_lower:
                    errors.append(
                        f"forbidden secret-like key found: '{full_path}' "
                        f"(contains '{substring}')"
                    )
                    break
            # Recurse into nested objects
            errors.extend(_check_secret_keys(value, full_path))
    elif isinstance(obj, list):
        for i, item in enumerate(obj):
            errors.extend(_check_secret_keys(item, f"{path}[{i}]"))
    return errors


def _check_unknown_profile_fields(profile: dict) -> list[str]:
    """Check for unknown top-level fields that might be secrets or mistakes.

    Returns a list of warning/error messages.
    """
    errors: list[str] = []
    for key in profile:
        if key not in _KNOWN_PROFILE_FIELDS:
            errors.append(f"unknown profile field: '{key}'")
    # Check reserved sub-fields
    reserved = profile.get("reserved", {})
    if isinstance(reserved, dict):
        for key in reserved:
            if key not in _KNOWN_RESERVED_FIELDS:
                errors.append(f"unknown reserved field: 'reserved.{key}'")
    return errors


# ── Profile validation ──────────────────────────────────────────────────────

def validate_profile(profile: dict) -> list[str]:
    """Validate a DNS profile. Returns a list of error messages (empty = valid)."""
    errors: list[str] = []

    # Check for secret-like keys
    secret_errors = _check_secret_keys(profile)
    errors.extend(secret_errors)

    # Check for unknown fields
    unknown_errors = _check_unknown_profile_fields(profile)
    errors.extend(unknown_errors)

    # zoneName
    zone = profile.get("zoneName")
    if not zone:
        errors.append("missing required field: 'zoneName'")
    elif not isinstance(zone, str) or not _is_plausible_dns_name(zone):
        errors.append(f"invalid zoneName: '{zone}' (must be a plausible DNS name)")

    # nodePrefix
    node = profile.get("nodePrefix")
    if not node:
        errors.append("missing required field: 'nodePrefix'")
    elif not isinstance(node, str) or not _is_dns_label_safe(node):
        errors.append(f"invalid nodePrefix: '{node}' (must be a DNS-label-safe prefix)")

    # ipv4
    ipv4 = profile.get("ipv4")
    if ipv4 is not None:
        if not isinstance(ipv4, str) or not _is_valid_ipv4(ipv4):
            errors.append(f"invalid ipv4: '{ipv4}'")

    # ipv6
    ipv6 = profile.get("ipv6")
    if ipv6 is not None:
        if not isinstance(ipv6, str) or not _is_valid_ipv6(ipv6):
            errors.append(f"invalid ipv6: '{ipv6}'")

    # At least one IP required
    if ipv4 is None and ipv6 is None:
        errors.append("at least one of 'ipv4' or 'ipv6' must be provided")

    # defaultProxied: must be exactly false (bool) or omitted
    if "defaultProxied" in profile:
        proxied = profile["defaultProxied"]
        if proxied is not False:
            errors.append(
                "defaultProxied must be false or omitted — "
                "proxy protocol records (HY2/TUIC/Reality/Trojan) must be DNS-only"
            )

    # Reserved prefixes
    reserved = profile.get("reserved", {})
    if isinstance(reserved, dict):
        for prefix_name in ("panelPrefix", "nanokPrefix", "nanobPrefix"):
            val = reserved.get(prefix_name)
            if val is not None:
                if not isinstance(val, str) or not _is_dns_label_safe(val):
                    errors.append(
                        f"invalid reserved.{prefix_name}: '{val}' "
                        f"(must be DNS-label-safe)"
                    )

    return errors


def _validate_direct_args(args: argparse.Namespace) -> list[str]:
    """Validate direct CLI arguments. Returns a list of error messages."""
    errors: list[str] = []

    if not args.zone:
        errors.append("--zone is required (or use --profile)")
    elif not _is_plausible_dns_name(args.zone):
        errors.append(f"invalid --zone: '{args.zone}' (must be a plausible DNS name)")

    if not args.node:
        errors.append("--node is required (or use --profile)")
    elif not _is_dns_label_safe(args.node):
        errors.append(f"invalid --node: '{args.node}' (must be a DNS-label-safe prefix)")

    if args.ipv4 and not _is_valid_ipv4(args.ipv4):
        errors.append(f"invalid --ipv4: '{args.ipv4}'")

    if args.ipv6 and not _is_valid_ipv6(args.ipv6):
        errors.append(f"invalid --ipv6: '{args.ipv6}'")

    if not args.ipv4 and not args.ipv6:
        errors.append("at least one of --ipv4 or --ipv6 must be provided")

    return errors


# ── Plan generation ──────────────────────────────────────────────────────────

def _build_plan(
    zone: str,
    node: str,
    ipv4: str | None,
    ipv6: str | None,
    proxied: bool = False,
    panel: str = "panel",
    nanok: str = "nanok",
    nanob: str = "nanob",
) -> DnsPlan:
    """Build a DnsPlan from validated parameters."""
    return DnsPlan(
        zone=zone,
        node_prefix=node,
        ipv4=ipv4,
        ipv6=ipv6,
        default_proxied=proxied,
        reserved_panel=panel,
        reserved_nanok=nanok,
        reserved_nanob=nanob,
    )


def _plan_from_profile(profile: dict) -> DnsPlan:
    """Build a DnsPlan from a validated profile dict."""
    reserved = profile.get("reserved", {})
    return _build_plan(
        zone=profile["zoneName"],
        node=profile["nodePrefix"],
        ipv4=profile.get("ipv4"),
        ipv6=profile.get("ipv6"),
        proxied=profile.get("defaultProxied", False),
        panel=reserved.get("panelPrefix", "panel"),
        nanok=reserved.get("nanokPrefix", "nanok"),
        nanob=reserved.get("nanobPrefix", "nanob"),
    )


def _plan_from_args(args: argparse.Namespace) -> DnsPlan:
    """Build a DnsPlan from CLI arguments."""
    return _build_plan(
        zone=args.zone,
        node=args.node,
        ipv4=args.ipv4,
        ipv6=args.ipv6,
    )


def _build_planned_records(plan: DnsPlan) -> list[dict[str, Any]]:
    """Build the list of planned DNS records."""
    records: list[dict[str, Any]] = []
    if plan.ipv4:
        records.append({
            "type": "A",
            "name": plan.node_hostname,
            "content": plan.ipv4,
            "proxied": False,
        })
    if plan.ipv6:
        records.append({
            "type": "AAAA",
            "name": plan.node_hostname,
            "content": plan.ipv6,
            "proxied": False,
        })
    return records


# ── Output formatters ────────────────────────────────────────────────────────

def _format_text(plan: DnsPlan) -> str:
    """Format the plan as human-readable text."""
    lines: list[str] = []
    lines.append("")
    lines.append("Cloudflare DNS dry-run plan")
    lines.append("")
    lines.append(f"  zone: {plan.zone}")
    lines.append(f"  node hostname: {plan.node_hostname}")
    lines.append("")
    lines.append("  planned records:")

    if plan.ipv4:
        lines.append(f"    A     {plan.node_hostname} -> {plan.ipv4}  proxied=false")
    if plan.ipv6:
        lines.append(f"    AAAA  {plan.node_hostname} -> {plan.ipv6}  proxied=false")

    lines.append("")
    lines.append("  reserved future hostnames:")
    lines.append(f"    {plan.panel_hostname}  for future Cloudflare Tunnel, not created")
    lines.append(f"    {plan.nanok_hostname}  for future Worker custom domain, not created")
    lines.append(f"    {plan.nanob_hostname}  for future Worker custom domain, not created")
    lines.append("")
    lines.append("  no mutation performed")
    lines.append("")
    lines.append("  security notes:")
    lines.append("    proxy protocol records must remain DNS-only")
    lines.append("    Web Tunnel/Access are not created by this command")
    lines.append("    no Cloudflare API call was made")
    lines.append("")
    lines.append("  next step:")
    lines.append("    Future command will be 'nanobk cf dns apply', but it is not implemented yet.")
    lines.append("")
    return "\n".join(lines)


def _format_json(plan: DnsPlan) -> str:
    """Format the plan as JSON."""
    result = {
        "ok": True,
        "noMutation": True,
        "zone": plan.zone,
        "nodeHostname": plan.node_hostname,
        "plannedRecords": _build_planned_records(plan),
        "reservedHostnames": {
            "panel": plan.panel_hostname,
            "nanok": plan.nanok_hostname,
            "nanob": plan.nanob_hostname,
        },
        "notes": [
            "no mutation performed",
            "Cloudflare API was not called",
        ],
    }
    return json.dumps(result, indent=2)


# ── Command handlers ─────────────────────────────────────────────────────────

def _handle_validate_profile(args: argparse.Namespace) -> None:
    """Handle the validate-profile subcommand."""
    profile = _load_profile(args.profile)
    errors = validate_profile(profile)
    if errors:
        for err in errors:
            print(f"error: {err}", file=sys.stderr)
        sys.exit(1)
    print("profile is valid")


def _handle_plan(args: argparse.Namespace) -> None:
    """Handle the plan subcommand."""
    if args.profile:
        # Reject mixed mode: --profile combined with direct fields
        direct_fields = []
        if args.zone:
            direct_fields.append("--zone")
        if args.node:
            direct_fields.append("--node")
        if args.ipv4:
            direct_fields.append("--ipv4")
        if args.ipv6:
            direct_fields.append("--ipv6")
        if direct_fields:
            print(
                f"error: --profile cannot be combined with "
                f"{'/'.join(direct_fields)}",
                file=sys.stderr,
            )
            sys.exit(1)

        profile = _load_profile(args.profile)
        errors = validate_profile(profile)
        if errors:
            for err in errors:
                print(f"error: {err}", file=sys.stderr)
            sys.exit(1)
        plan = _plan_from_profile(profile)
    else:
        errors = _validate_direct_args(args)
        if errors:
            for err in errors:
                print(f"error: {err}", file=sys.stderr)
            sys.exit(1)
        plan = _plan_from_args(args)

    if args.json_output:
        print(_format_json(plan))
    else:
        print(_format_text(plan))


def _load_profile(path: str) -> dict:
    """Load and parse a profile JSON file."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"error: profile file not found: {path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"error: invalid JSON in profile: {e}", file=sys.stderr)
        sys.exit(1)
    except PermissionError:
        print(f"error: cannot read profile file: {path}", file=sys.stderr)
        sys.exit(1)


# ── CLI entry point ──────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="NanoBK Cloudflare DNS dry-run plan helper"
    )
    subparsers = parser.add_subparsers(dest="command")

    # plan subcommand
    plan_parser = subparsers.add_parser(
        "plan",
        help="Generate a dry-run DNS plan",
    )
    plan_parser.add_argument(
        "--profile",
        help="Path to DNS profile JSON file",
    )
    plan_parser.add_argument(
        "--zone",
        help="Cloudflare zone name (e.g. example.com)",
    )
    plan_parser.add_argument(
        "--node",
        help="Node hostname prefix (e.g. node)",
    )
    plan_parser.add_argument(
        "--ipv4",
        help="IPv4 address for the node",
    )
    plan_parser.add_argument(
        "--ipv6",
        help="IPv6 address for the node",
    )
    plan_parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Output as JSON",
    )

    # validate-profile subcommand
    validate_parser = subparsers.add_parser(
        "validate-profile",
        help="Validate a DNS profile file",
    )
    validate_parser.add_argument(
        "--profile",
        required=True,
        help="Path to DNS profile JSON file",
    )

    args = parser.parse_args()

    if args.command == "plan":
        _handle_plan(args)
    elif args.command == "validate-profile":
        _handle_validate_profile(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
