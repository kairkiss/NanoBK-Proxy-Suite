"""
NanoBK Proxy Suite — Cloudflare DNS Apply Helper

Applies DNS A/AAAA records to Cloudflare via API with idempotency.
Supports fake/mock transport for testing (never calls real Cloudflare in tests).

Usage:
    python3 lib/nanobk_cf_dns_apply.py --profile PATH --api-env PATH [--dry-run] [--check] [--yes] [--json]

Fake transport for tests:
    NANOBK_CF_DNS_FAKE_TRANSPORT=/path/to/fixture.json python3 lib/nanobk_cf_dns_apply.py ...
"""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from dataclasses import dataclass, field
from typing import Any, Callable

# Shared validation/model layer
from nanobk_cf_dns import (
    DnsPlan,
    _build_planned_records,
    _plan_from_profile,
    validate_profile,
)

# ── Constants ────────────────────────────────────────────────────────────────

CF_API_BASE = "https://api.cloudflare.com/client/v4"

# Allowlist for api-env keys — reject everything else
_API_ENV_ALLOWED_KEYS = {"CF_API_TOKEN", "CF_ZONE_ID", "CF_ZONE_NAME"}

# Ownership marker for managed records
_MANAGED_BY = "managed-by=nanobk"
_MANAGED_COMPONENT = "component=cf-dns-apply"

# Action names
ACTION_NOOP = "noop"
ACTION_CREATE = "create"
ACTION_UPDATE = "update"
ACTION_FAIL_CONFLICT = "fail_conflict"
ACTION_SKIP = "skip"


# ── Exceptions ───────────────────────────────────────────────────────────────

class ApplyError(Exception):
    """Base exception for apply errors."""
    pass


class ApiEnvError(ApplyError):
    """Error parsing or validating api-env file."""
    pass


class ConflictError(ApplyError):
    """Record conflict that prevents safe mutation."""
    pass


class ApiError(ApplyError):
    """Cloudflare API returned an error."""
    pass


# ── Data classes ─────────────────────────────────────────────────────────────

@dataclass
class ApiEnv:
    """Parsed Cloudflare API environment."""
    api_token: str
    zone_id: str
    zone_name: str


@dataclass
class RecordAction:
    """Result of idempotency check for one record type."""
    record_type: str       # "A" or "AAAA"
    name: str              # e.g. "node.example.com"
    planned_content: str   # e.g. "203.0.113.10"
    action: str            # ACTION_NOOP, ACTION_CREATE, etc.
    existing_id: str | None = None
    existing_content: str | None = None
    message: str = ""


@dataclass
class ApplyResult:
    """Result of applying one record action."""
    record_type: str
    name: str
    action: str
    success: bool
    message: str
    record_id: str | None = None


# ── API env parser ───────────────────────────────────────────────────────────

def parse_api_env(path: str) -> ApiEnv:
    """Parse a Cloudflare API env file safely (no sourcing).

    Checks file permissions (must be 600), required keys, and rejects
    any key not in the allowlist (CF_API_TOKEN, CF_ZONE_ID, CF_ZONE_NAME).
    """
    if not os.path.isfile(path):
        raise ApiEnvError(f"api-env file not found: {path}")

    # Check file permissions
    st = os.stat(path)
    mode = stat.S_IMODE(st.st_mode)
    # Check that owner has read/write and group/other have nothing
    # 0o600 = 0b1100000000 = owner rw only
    if mode != 0o600:
        mode_str = oct(mode)
        raise ApiEnvError(
            f"api-env file permissions must be 600, got {mode_str}. "
            f"Fix with: chmod 600 {path}"
        )

    # Parse key=value lines
    values: dict[str, str] = {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line_num, raw_line in enumerate(f, 1):
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    raise ApiEnvError(
                        f"invalid line {line_num} in api-env (no '=' found)"
                    )
                key, _, value = line.partition("=")
                key = key.strip()
                value = value.strip()
                # Strip optional quotes
                if len(value) >= 2 and (
                    (value[0] == '"' and value[-1] == '"')
                    or (value[0] == "'" and value[-1] == "'")
                ):
                    value = value[1:-1]
                values[key] = value
    except OSError as e:
        raise ApiEnvError(f"cannot read api-env file: {e}")

    # Allowlist check — reject any key not in the allowed set
    allowed = _API_ENV_ALLOWED_KEYS
    for key in values:
        if key not in allowed:
            raise ApiEnvError(
                f"unsupported key in api-env: '{key}'. "
                f"Allowed keys: {', '.join(sorted(allowed))}"
            )

    # Check required keys
    missing = []
    for required in ("CF_API_TOKEN", "CF_ZONE_ID", "CF_ZONE_NAME"):
        if required not in values or not values[required]:
            missing.append(required)
    if missing:
        raise ApiEnvError(
            f"api-env missing required keys: {', '.join(missing)}"
        )

    return ApiEnv(
        api_token=values["CF_API_TOKEN"],
        zone_id=values["CF_ZONE_ID"],
        zone_name=values["CF_ZONE_NAME"],
    )


def redact_token(text: str, token: str) -> str:
    """Redact a token value from text."""
    if token and token in text:
        text = text.replace(token, "[REDACTED]")
    return text


# ── Transport abstraction ────────────────────────────────────────────────────

# Transport function type: (method, endpoint, body|None, headers) -> (status, json_body)
TransportFn = Callable[[str, str, dict | None, dict[str, str]], tuple[int, dict[str, Any]]]


def _real_transport(
    method: str,
    endpoint: str,
    body: dict | None,
    headers: dict[str, str],
) -> tuple[int, dict[str, Any]]:
    """Real Cloudflare API transport using urllib."""
    import urllib.request
    import urllib.error

    url = f"{CF_API_BASE}{endpoint}"
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            status = resp.status
            raw = resp.read().decode("utf-8")
            try:
                resp_body = json.loads(raw)
            except (json.JSONDecodeError, ValueError):
                resp_body = {"success": False, "errors": [{"code": 0, "message": "invalid JSON in API response"}]}
            return (status, resp_body)
    except urllib.error.HTTPError as e:
        try:
            resp_body = json.loads(e.read().decode("utf-8"))
        except Exception:
            resp_body = {"success": False, "errors": [{"code": e.code, "message": str(e)}]}
        return (e.code, resp_body)
    except urllib.error.URLError as e:
        return (0, {"success": False, "errors": [{"code": 0, "message": f"connection error: {e.reason}"}]})
    except TimeoutError:
        return (0, {"success": False, "errors": [{"code": 0, "message": "request timed out"}]})
    except Exception as e:
        return (0, {"success": False, "errors": [{"code": 0, "message": f"unexpected error: {type(e).__name__}"}]})


def _make_fake_transport(fixture_path: str) -> TransportFn:
    """Create a fake transport from a JSON fixture file.

    The fixture maps request keys to response objects.
    Keys are like: "GET_A", "GET_AAAA", "GET_CNAME", "POST_A", "PATCH_A:{id}", "ERROR_401", etc.

    An optional "_calls_file" key specifies a file path to append call records to.
    """
    with open(fixture_path, "r", encoding="utf-8") as f:
        fixture = json.load(f)

    calls_file = fixture.pop("_calls_file", None)

    def _fake_transport(
        method: str,
        endpoint: str,
        body: dict | None,
        headers: dict[str, str],
    ) -> tuple[int, dict[str, Any]]:
        # Build request key from method and endpoint
        # Parse: /zones/{id}/dns_records?type=X&name=Y or /zones/{id}/dns_records/{record_id}
        parts = endpoint.strip("/").split("/")

        # Determine the key
        key = None
        if method == "GET" and "type" in endpoint:
            # Parse query params
            query = endpoint.split("?", 1)[1] if "?" in endpoint else ""
            params = dict(p.split("=", 1) for p in query.split("&") if "=" in p)
            rtype = params.get("type", "UNKNOWN")
            key = f"GET_{rtype}"
        elif method == "GET" and len(parts) >= 4 and parts[2] == "dns_records" and len(parts) > 3:
            # GET specific record: /zones/{id}/dns_records/{record_id}
            record_id = parts[3]
            key = f"GET_RECORD:{record_id}"
        elif method == "POST":
            key = "POST"
        elif method == "PATCH" and len(parts) >= 4:
            record_id = parts[3]
            key = f"PATCH:{record_id}"
        else:
            key = f"{method}_{endpoint}"

        # Check for generic error key first (e.g., ERROR_401)
        error_key = None
        for ek in fixture:
            if ek.startswith("ERROR_"):
                error_key = ek
                break

        # Look up response
        resp = fixture.get(key)
        if resp is None:
            # Try generic POST/PATCH
            if method == "POST":
                resp = fixture.get("POST")
            elif method == "PATCH":
                resp = fixture.get("PATCH")
        if resp is None and error_key:
            resp = fixture[error_key]
        if resp is None:
            resp = {"success": False, "errors": [{"code": 0, "message": f"unmatched key: {key}"}]}

        # Record the call
        if calls_file:
            call_record = {"method": method, "key": key, "endpoint": endpoint}
            try:
                existing = []
                if os.path.isfile(calls_file):
                    with open(calls_file, "r") as cf:
                        existing = json.load(cf)
                existing.append(call_record)
                with open(calls_file, "w") as cf:
                    json.dump(existing, cf)
            except OSError:
                pass

        status = resp.get("_status", 200)
        # Remove internal keys from response
        clean_resp = {k: v for k, v in resp.items() if not k.startswith("_")}
        return (status, clean_resp)

    return _fake_transport


def get_transport() -> TransportFn:
    """Get the appropriate transport (real or fake)."""
    fake_path = os.environ.get("NANOBK_CF_DNS_FAKE_TRANSPORT")
    if fake_path:
        return _make_fake_transport(fake_path)
    return _real_transport


# ── Cloudflare API client ────────────────────────────────────────────────────

class CloudflareDnsClient:
    """Client for Cloudflare DNS record operations."""

    def __init__(self, api_env: ApiEnv, transport: TransportFn | None = None):
        self.api_env = api_env
        self.transport = transport or get_transport()

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.api_env.api_token}",
            "Content-Type": "application/json",
        }

    def _request(
        self, method: str, endpoint: str, body: dict | None = None
    ) -> tuple[int, dict[str, Any]]:
        """Make an API request. Returns (status, response_body)."""
        return self.transport(method, endpoint, body, self._headers())

    def get_records(
        self, record_type: str, name: str
    ) -> tuple[list[dict[str, Any]], str | None]:
        """GET DNS records by type and name.

        Returns (records_list, error_message).
        error_message is None on success, a redacted string on failure.
        """
        endpoint = (
            f"/zones/{self.api_env.zone_id}/dns_records"
            f"?type={record_type}&name={name}"
        )
        status, body = self._request("GET", endpoint)

        if not body.get("success"):
            err = self._format_api_error(status, body)
            return ([], err)

        return (body.get("result", []), None)

    def get_cname_records(self, name: str) -> tuple[list[dict[str, Any]], str | None]:
        """Check for CNAME records at a name."""
        return self.get_records("CNAME", name)

    def create_record(
        self, record_type: str, name: str, content: str, comment: str
    ) -> tuple[dict[str, Any] | None, str | None]:
        """POST a new DNS record.

        Returns (created_record, error_message).
        """
        endpoint = f"/zones/{self.api_env.zone_id}/dns_records"
        body = {
            "type": record_type,
            "name": name,
            "content": content,
            "proxied": False,
            "comment": comment,
        }
        status, resp = self._request("POST", endpoint, body)

        if not resp.get("success"):
            err = self._format_api_error(status, resp)
            return (None, err)

        return (resp.get("result", {}), None)

    def update_record(
        self, record_id: str, record_type: str, name: str, content: str, comment: str
    ) -> tuple[dict[str, Any] | None, str | None]:
        """PATCH an existing DNS record.

        Returns (updated_record, error_message).
        """
        endpoint = f"/zones/{self.api_env.zone_id}/dns_records/{record_id}"
        body = {
            "type": record_type,
            "name": name,
            "content": content,
            "proxied": False,
            "comment": comment,
        }
        status, resp = self._request("PATCH", endpoint, body)

        if not resp.get("success"):
            err = self._format_api_error(status, resp)
            return (None, err)

        return (resp.get("result", {}), None)

    def _format_api_error(self, status: int, body: dict[str, Any]) -> str:
        """Format an API error response into a redacted, human-readable string."""
        errors = body.get("errors", [])
        messages = []
        for err in errors:
            msg = err.get("message", "unknown error")
            code = err.get("code", "")
            # Redact token if leaked
            msg = redact_token(msg, self.api_env.api_token)
            if code:
                messages.append(f"[{code}] {msg}")
            else:
                messages.append(msg)

        if status == 401:
            return "authentication failed (check CF_API_TOKEN)"
        elif status == 403:
            return "permission denied (check API token permissions)"
        elif status == 404:
            return "resource not found (check CF_ZONE_ID)"
        elif status == 429:
            return "rate limited by Cloudflare API (try again later)"
        elif status == 0:
            # Connection error
            return messages[0] if messages else "connection error"
        elif messages:
            return "; ".join(messages)
        else:
            return f"API error (HTTP {status})"


# ── Idempotency state machine ────────────────────────────────────────────────

def _is_managed_by_nanobk(record: dict[str, Any], hostname: str) -> bool:
    """Check if a record has our ownership marker with matching hostname."""
    comment = record.get("comment", "") or ""
    if _MANAGED_BY not in comment or _MANAGED_COMPONENT not in comment:
        return False
    # Also require hostname= to be present and match
    hostname_marker = f"hostname={hostname}"
    return hostname_marker in comment


def check_record(
    client: CloudflareDnsClient,
    record_type: str,
    name: str,
    planned_content: str,
) -> RecordAction:
    """Check one record type against the plan and determine action.

    Returns a RecordAction describing what should happen.
    """
    # Check for CNAME conflict
    cnames, cname_err = client.get_cname_records(name)
    if cname_err:
        return RecordAction(
            record_type=record_type,
            name=name,
            planned_content=planned_content,
            action=ACTION_FAIL_CONFLICT,
            message=f"failed to check CNAME records: {cname_err}",
        )
    if cnames:
        return RecordAction(
            record_type=record_type,
            name=name,
            planned_content=planned_content,
            action=ACTION_FAIL_CONFLICT,
            message=(
                f"CNAME record exists for {name}; "
                f"cannot create {record_type} alongside CNAME"
            ),
        )

    # Get existing records of this type
    existing, err = client.get_records(record_type, name)
    if err:
        return RecordAction(
            record_type=record_type,
            name=name,
            planned_content=planned_content,
            action=ACTION_FAIL_CONFLICT,
            message=f"failed to query existing {record_type} records: {err}",
        )

    # No existing record -> create
    if len(existing) == 0:
        return RecordAction(
            record_type=record_type,
            name=name,
            planned_content=planned_content,
            action=ACTION_CREATE,
            message=f"will create {record_type} {name} -> {planned_content}",
        )

    # Multiple existing records -> conflict
    if len(existing) > 1:
        return RecordAction(
            record_type=record_type,
            name=name,
            planned_content=planned_content,
            action=ACTION_FAIL_CONFLICT,
            message=(
                f"multiple {record_type} records exist for {name} "
                f"({len(existing)} found); resolve manually"
            ),
        )

    # Exactly one existing record
    record = existing[0]
    existing_content = record.get("content", "")
    existing_proxied = record.get("proxied", False)
    existing_id = record.get("id", "")

    # Proxied=true -> conflict
    if existing_proxied:
        return RecordAction(
            record_type=record_type,
            name=name,
            planned_content=planned_content,
            action=ACTION_FAIL_CONFLICT,
            existing_id=existing_id,
            existing_content=existing_content,
            message=(
                f"existing {record_type} record for {name} has proxied=true; "
                f"cannot safely convert to DNS-only"
            ),
        )

    # Same content, proxied=false -> noop
    if existing_content == planned_content:
        return RecordAction(
            record_type=record_type,
            name=name,
            planned_content=planned_content,
            action=ACTION_NOOP,
            existing_id=existing_id,
            existing_content=existing_content,
            message=f"{record_type} {name} already matches (no change needed)",
        )

    # Different content
    if _is_managed_by_nanobk(record, name):
        return RecordAction(
            record_type=record_type,
            name=name,
            planned_content=planned_content,
            action=ACTION_UPDATE,
            existing_id=existing_id,
            existing_content=existing_content,
            message=(
                f"will update {record_type} {name}: "
                f"{existing_content} -> {planned_content}"
            ),
        )
    else:
        return RecordAction(
            record_type=record_type,
            name=name,
            planned_content=planned_content,
            action=ACTION_FAIL_CONFLICT,
            existing_id=existing_id,
            existing_content=existing_content,
            message=(
                f"existing {record_type} record for {name} "
                f"(content={existing_content}) is not managed by nanobk; "
                f"resolve manually before applying"
            ),
        )


def resolve_all(
    client: CloudflareDnsClient, plan: DnsPlan
) -> list[RecordAction]:
    """Check all planned records and return their actions."""
    planned = _build_planned_records(plan)
    actions = []
    for rec in planned:
        action = check_record(client, rec["type"], rec["name"], rec["content"])
        actions.append(action)
    return actions


def build_dry_actions(plan: DnsPlan) -> list[RecordAction]:
    """Build dry-run actions without any API calls.

    Shows what would be planned (assumes create needed) for display purposes.
    """
    planned = _build_planned_records(plan)
    actions = []
    for rec in planned:
        actions.append(RecordAction(
            record_type=rec["type"],
            name=rec["name"],
            planned_content=rec["content"],
            action=ACTION_CREATE,
            message=f"(dry-run) would check and apply {rec['type']} {rec['name']}",
        ))
    return actions


# ── Mutation execution ───────────────────────────────────────────────────────

def execute_action(
    client: CloudflareDnsClient, action: RecordAction, hostname: str
) -> ApplyResult:
    """Execute a single mutation action (create or update)."""
    comment = f"{_MANAGED_BY}; {_MANAGED_COMPONENT}; hostname={hostname}"

    if action.action == ACTION_CREATE:
        result, err = client.create_record(
            action.record_type, action.name, action.planned_content, comment
        )
        if err:
            return ApplyResult(
                record_type=action.record_type,
                name=action.name,
                action=action.action,
                success=False,
                message=f"create failed: {err}",
            )
        record_id = result.get("id", "") if result else ""
        return ApplyResult(
            record_type=action.record_type,
            name=action.name,
            action=action.action,
            success=True,
            message=f"created {action.record_type} {action.name}",
            record_id=record_id,
        )

    elif action.action == ACTION_UPDATE:
        if not action.existing_id:
            return ApplyResult(
                record_type=action.record_type,
                name=action.name,
                action=action.action,
                success=False,
                message="update failed: no existing record ID",
            )
        result, err = client.update_record(
            action.existing_id,
            action.record_type,
            action.name,
            action.planned_content,
            comment,
        )
        if err:
            return ApplyResult(
                record_type=action.record_type,
                name=action.name,
                action=action.action,
                success=False,
                message=f"update failed: {err}",
            )
        return ApplyResult(
            record_type=action.record_type,
            name=action.name,
            action=action.action,
            success=True,
            message=f"updated {action.record_type} {action.name}",
            record_id=action.existing_id,
        )

    elif action.action == ACTION_NOOP:
        return ApplyResult(
            record_type=action.record_type,
            name=action.name,
            action=action.action,
            success=True,
            message=action.message,
            record_id=action.existing_id,
        )

    else:
        return ApplyResult(
            record_type=action.record_type,
            name=action.name,
            action=action.action,
            success=False,
            message=action.message,
        )


def execute_all(
    client: CloudflareDnsClient,
    actions: list[RecordAction],
    hostname: str,
) -> list[ApplyResult]:
    """Execute all actions that require mutation."""
    results = []
    for action in actions:
        if action.action in (ACTION_CREATE, ACTION_UPDATE, ACTION_NOOP):
            result = execute_action(client, action, hostname)
            results.append(result)
        else:
            results.append(
                ApplyResult(
                    record_type=action.record_type,
                    name=action.name,
                    action=action.action,
                    success=False,
                    message=action.message,
                )
            )
    return results


# ── Output formatting ────────────────────────────────────────────────────────

def _format_apply_text(
    actions: list[RecordAction],
    dry_run: bool,
    check_mode: bool,
    yes: bool,
) -> str:
    """Format apply plan/results as human-readable text."""
    lines: list[str] = []
    lines.append("")
    lines.append("Cloudflare DNS apply")
    lines.append("")

    if dry_run:
        lines.append("  mode: --dry-run (no API calls)")
    elif check_mode:
        lines.append("  mode: --check (GET only, no mutation)")
    elif not yes:
        lines.append("  mode: plan only (--yes required for mutation)")
    else:
        lines.append("  mode: apply")
    lines.append("")

    has_conflicts = False
    has_mutations = False

    for action in actions:
        icon = {
            ACTION_NOOP: "  [ok]    ",
            ACTION_CREATE: "  [create]",
            ACTION_UPDATE: "  [update]",
            ACTION_FAIL_CONFLICT: "  [conflict]",
            ACTION_SKIP: "  [skip]  ",
        }.get(action.action, "  [?]     ")

        lines.append(f"{icon} {action.record_type} {action.name} -> {action.planned_content}")
        if action.message:
            lines.append(f"           {action.message}")

        if action.action == ACTION_FAIL_CONFLICT:
            has_conflicts = True
        elif action.action in (ACTION_CREATE, ACTION_UPDATE):
            has_mutations = True

    lines.append("")

    if has_conflicts:
        lines.append("  Conflicts detected. Resolve manually before applying.")
    elif has_mutations and not yes and not dry_run and not check_mode:
        lines.append("  Review the plan above. Add --yes to apply changes.")
    elif has_mutations and (dry_run or check_mode):
        lines.append("  No mutation performed (read-only mode).")
    else:
        lines.append("  All records match. No changes needed.")

    lines.append("")
    return "\n".join(lines)


def _format_apply_result_text(results: list[ApplyResult]) -> str:
    """Format mutation results as human-readable text."""
    lines: list[str] = []
    lines.append("")
    lines.append("Cloudflare DNS apply results")
    lines.append("")

    all_ok = True
    for result in results:
        icon = "[ok]" if result.success else "[fail]"
        lines.append(f"  {icon} {result.record_type} {result.name}: {result.message}")
        if not result.success:
            all_ok = False

    lines.append("")
    if all_ok:
        lines.append("  All operations succeeded.")
    else:
        lines.append("  Some operations failed. Check output above.")
    lines.append("")
    return "\n".join(lines)


def _format_apply_json(
    actions: list[RecordAction],
    results: list[ApplyResult] | None,
    dry_run: bool,
    check_mode: bool,
    yes: bool,
    api_token: str,
) -> str:
    """Format apply plan/results as redacted JSON."""
    output: dict[str, Any] = {
        "ok": True,
        "dryRun": dry_run,
        "checkMode": check_mode,
        "actions": [],
        "results": [],
    }

    has_conflicts = False
    for action in actions:
        action_obj: dict[str, Any] = {
            "recordType": action.record_type,
            "name": action.name,
            "plannedContent": action.planned_content,
            "action": action.action,
            "message": redact_token(action.message, api_token),
        }
        if action.existing_content:
            action_obj["existingContent"] = action.existing_content
        output["actions"].append(action_obj)
        if action.action == ACTION_FAIL_CONFLICT:
            has_conflicts = True
            output["ok"] = False

    if results:
        all_ok = True
        for result in results:
            result_obj: dict[str, Any] = {
                "recordType": result.record_type,
                "name": result.name,
                "action": result.action,
                "success": result.success,
                "message": redact_token(result.message, api_token),
            }
            if result.record_id:
                result_obj["recordId"] = result.record_id
            output["results"].append(result_obj)
            if not result.success:
                all_ok = False
                output["ok"] = False

    if has_conflicts:
        output["ok"] = False

    return json.dumps(output, indent=2)


# ── CLI entry point ──────────────────────────────────────────────────────────

def _handle_apply(args: argparse.Namespace) -> None:
    """Handle the apply subcommand."""
    # --force is reserved
    if args.force:
        print("error: --force is reserved for a future version and is not implemented yet", file=sys.stderr)
        sys.exit(1)

    # Load and validate profile
    try:
        with open(args.profile, "r", encoding="utf-8") as f:
            profile = json.load(f)
    except FileNotFoundError:
        print(f"error: profile not found: {args.profile}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"error: invalid JSON in profile: {e}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"error: cannot read profile: {e}", file=sys.stderr)
        sys.exit(1)

    errors = validate_profile(profile)
    if errors:
        for err in errors:
            print(f"error: {err}", file=sys.stderr)
        sys.exit(1)

    plan = _plan_from_profile(profile)

    # Parse api-env
    try:
        api_env = parse_api_env(args.api_env)
    except ApiEnvError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)

    # Create client (used for check and apply modes, not dry-run)
    transport = get_transport()
    client = CloudflareDnsClient(api_env, transport)

    # Resolve actions
    if args.dry_run:
        # --dry-run: no API calls at all, validate only
        actions = build_dry_actions(plan)
    else:
        # --check or --yes or default: query existing records via GET
        actions = resolve_all(client, plan)

    # Determine state
    has_conflicts = any(a.action == ACTION_FAIL_CONFLICT for a in actions)
    has_mutations = any(a.action in (ACTION_CREATE, ACTION_UPDATE) for a in actions)

    # Format and show plan
    if args.json_output:
        print(_format_apply_json(actions, None, args.dry_run, args.check, args.yes, api_env.api_token))
    else:
        print(_format_apply_text(actions, args.dry_run, args.check, args.yes))

    # Handle conflicts
    if has_conflicts:
        sys.exit(1)

    # Handle no mutations needed
    if not has_mutations:
        sys.exit(0)

    # Handle read-only modes
    if args.dry_run or args.check or not args.yes:
        sys.exit(2)

    # Execute mutations
    results = execute_all(client, actions, plan.node_hostname)

    # Show results
    if args.json_output:
        print(_format_apply_json(actions, results, False, False, True, api_env.api_token))
    else:
        print(_format_apply_result_text(results))

    all_ok = all(r.success for r in results)
    sys.exit(0 if all_ok else 1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="NanoBK Cloudflare DNS apply helper"
    )
    parser.add_argument(
        "--profile",
        required=True,
        help="Path to DNS profile JSON file",
    )
    parser.add_argument(
        "--api-env",
        required=True,
        help="Path to Cloudflare API env file (CF_API_TOKEN, CF_ZONE_ID, CF_ZONE_NAME)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        dest="dry_run",
        help="Validate only, no API calls",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        dest="check",
        help="GET-only mode, no mutation",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        dest="yes",
        help="Required for POST/PATCH mutation",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Output as JSON",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        dest="force",
        help="Reserved for future use",
    )

    args = parser.parse_args()
    _handle_apply(args)


if __name__ == "__main__":
    main()
