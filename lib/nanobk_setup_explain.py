#!/usr/bin/env python3
"""
NanoBK Setup Result Explanation Helper

Provides beginner-friendly explanations for setup wizard and DNS setup results.
Adds completed steps, not-done steps, blocked reasons, next actions, and fix hints.

Usage:
    from nanobk_setup_explain import explain_setup_result, format_explanation_text
"""

# ── Status-specific explanation builders ─────────────────────────────────────

def _explain_ready(zone):
    return {
        "summary_title": "Ready for owner review",
        "plain_status": "Your VPS IPs were detected and proxy/web DNS names look available.",
        "completed": [
            "Detected VPS public IP candidates",
            "Checked proxy/web DNS availability",
            "Generated a DNS plan",
            "Prepared a create preflight summary",
        ],
        "not_done": [
            "No DNS records were created",
            "No DNS records were modified",
            "No production proxy/web DNS apply was enabled",
        ],
        "why_blocked": [
            "Production DNS creation is still blocked by design.",
            "NanoBK requires an explicit owner-controlled create step before changing Cloudflare DNS.",
        ],
        "next_actions": [
            {
                "label": "Review current setup summary",
                "command": "nanobk setup dns",
                "safe": True,
            },
            {
                "label": "Run create preflight",
                "command": "nanobk cf dns create-preflight --zone {} --api-env <redacted>".format(zone),
                "safe": True,
            },
        ],
        "fix_hints": [],
    }


def _explain_no_ip():
    return {
        "summary_title": "No public IP detected",
        "plain_status": "NanoBK could not detect a public IPv4 or IPv6 address on this VPS.",
        "completed": [
            "Attempted VPS public IP detection",
        ],
        "not_done": [
            "No public IPv4 detected",
            "No public IPv6 detected",
            "No DNS plan generated",
            "No DNS records were created",
        ],
        "why_blocked": [
            "Without a public IP, NanoBK cannot prepare DNS A/AAAA records.",
        ],
        "next_actions": [
            {
                "label": "Check VPS network configuration",
                "command": "nanobk vps ip detect",
                "safe": True,
            },
        ],
        "fix_hints": [
            "Check that your VPS has a public IPv4 address.",
            "If behind NAT, ensure the public IP is reachable.",
            "Check if IPv6 is enabled on your VPS network interface.",
            "Run 'nanobk vps ip detect' to see detailed IP detection results.",
        ],
    }


def _explain_conflict(zone):
    return {
        "summary_title": "Subdomain conflict detected",
        "plain_status": "One or more target subdomains already have DNS records.",
        "completed": [
            "Detected VPS public IP candidates",
            "Checked proxy/web DNS availability",
        ],
        "not_done": [
            "No DNS plan generated due to conflict",
            "No DNS records were created",
            "No DNS records were modified",
        ],
        "why_blocked": [
            "NanoBK will not overwrite existing DNS records.",
            "Existing records must be reviewed before proceeding.",
        ],
        "next_actions": [
            {
                "label": "Review current setup summary",
                "command": "nanobk setup dns",
                "safe": True,
            },
            {
                "label": "Check subdomain availability",
                "command": "nanobk cf dns availability summary --zone {} --api-env <redacted>".format(zone),
                "safe": True,
            },
        ],
        "fix_hints": [
            "Review the existing DNS records in your Cloudflare dashboard.",
            "Do not overwrite production records.",
            "If the existing record is yours and correct, no action needed.",
            "If you need to replace it, do so manually with full understanding.",
        ],
    }


def _explain_manual_review(zone):
    return {
        "summary_title": "Manual review required",
        "plain_status": "A read-only Cloudflare check failed or returned unexpected results.",
        "completed": [
            "Attempted VPS public IP detection",
        ],
        "not_done": [
            "Subdomain availability check failed or incomplete",
            "No DNS plan generated",
            "No DNS records were created",
        ],
        "why_blocked": [
            "NanoBK could not verify the current DNS state.",
            "Automatic apply is not safe when the state is unknown.",
        ],
        "next_actions": [
            {
                "label": "Re-run setup assistant",
                "command": "nanobk setup dns",
                "safe": True,
            },
            {
                "label": "Run diagnostics",
                "command": "nanobk doctor",
                "safe": True,
            },
        ],
        "fix_hints": [
            "Check that your api-env file has the correct permissions (0600 or 0400).",
            "Check that the zone name matches the zone name in your api-env.",
            "Check your VPS network connectivity to Cloudflare API.",
            "Run 'nanobk doctor' for environment diagnostics.",
        ],
    }


def _explain_credential_blocked():
    return {
        "summary_title": "Credential issue detected",
        "plain_status": "The Cloudflare API credential file has a permission or content problem.",
        "completed": [],
        "not_done": [
            "No IP detection performed",
            "No availability check performed",
            "No DNS plan generated",
            "No DNS records were created",
        ],
        "why_blocked": [
            "NanoBK requires a secure credential file before making any Cloudflare API calls.",
        ],
        "next_actions": [
            {
                "label": "Fix credential file permissions",
                "command": "chmod 600 /path/to/cloudflare.env",
                "safe": True,
            },
            {
                "label": "Re-run setup assistant",
                "command": "nanobk setup dns",
                "safe": True,
            },
        ],
        "fix_hints": [
            "Set credential file permissions to 0600: chmod 600 /path/to/cloudflare.env",
            "Ensure the file contains the required Cloudflare API keys.",
            "Do not share or print your credential file contents.",
        ],
    }


def _explain_cancelled():
    return {
        "summary_title": "Wizard cancelled",
        "plain_status": "You cancelled the setup wizard. No changes were made.",
        "completed": [],
        "not_done": [
            "No setup profile saved",
            "No DNS check performed",
            "No DNS records were created",
        ],
        "why_blocked": [
            "The wizard was cancelled by user choice.",
        ],
        "next_actions": [
            {
                "label": "Re-run setup wizard",
                "command": "nanobk setup wizard",
                "safe": True,
            },
        ],
        "fix_hints": [],
    }


def _explain_unknown():
    return {
        "summary_title": "Unknown status",
        "plain_status": "NanoBK could not determine the setup state.",
        "completed": [],
        "not_done": [
            "Setup state unknown",
            "No DNS records were created",
        ],
        "why_blocked": [
            "The setup process did not complete successfully.",
        ],
        "next_actions": [
            {
                "label": "Run diagnostics",
                "command": "nanobk doctor",
                "safe": True,
            },
            {
                "label": "Re-run setup assistant",
                "command": "nanobk setup dns",
                "safe": True,
            },
        ],
        "fix_hints": [
            "Run 'nanobk doctor' for environment diagnostics.",
            "Check the error output above for specific issues.",
        ],
    }


# ── Main API ────────────────────────────────────────────────────────────────

_STATUS_BUILDERS = {
    "ready_for_owner_review": _explain_ready,
    "incomplete_no_ip": lambda z: _explain_no_ip(),
    "blocked_subdomain_conflict": _explain_conflict,
    "manual_review_required": _explain_manual_review,
    "blocked_credential": lambda z: _explain_credential_blocked(),
    "cancelled": lambda z: _explain_cancelled(),
    "blocked_invalid_input": lambda z: _explain_unknown(),
    "blocked": lambda z: _explain_unknown(),
}


def explain_setup_result(result, zone=""):
    """Add explanation to a setup result dict. Returns enriched result."""
    status = result.get("setup_status") or result.get("wizard_status") or "unknown"

    # Add saved profile step if profile was saved
    base = _STATUS_BUILDERS.get(status, lambda z: _explain_unknown())(zone)
    if result.get("profile", {}).get("saved"):
        base["completed"].insert(0, "Saved local setup profile")

    # Build safety from result
    safety = result.get("safety", {})
    explanation = {
        "summary_title": base["summary_title"],
        "plain_status": base["plain_status"],
        "completed": base["completed"],
        "not_done": base["not_done"],
        "why_blocked": base["why_blocked"],
        "next_actions": base["next_actions"],
        "fix_hints": base["fix_hints"],
        "safety": {
            "dns_changed": safety.get("dns_changed", False),
            "records_created": safety.get("records_created", False),
            "records_modified": safety.get("records_modified", False),
            "records_deleted": safety.get("records_deleted", False),
            "production_apply_enabled": safety.get("production_apply_enabled", False),
        },
    }

    result["explanation"] = explanation
    return result


def format_explanation_text(explanation):
    """Format explanation dict as human-readable text block."""
    lines = []
    lines.append("  What this means:")
    lines.append("    {}".format(explanation.get("plain_status", "")))
    lines.append("")

    completed = explanation.get("completed", [])
    if completed:
        lines.append("  Completed:")
        for item in completed:
            lines.append("    - {}".format(item))
        lines.append("")

    not_done = explanation.get("not_done", [])
    if not_done:
        lines.append("  Not done:")
        for item in not_done:
            lines.append("    - {}".format(item))
        lines.append("")

    why = explanation.get("why_blocked", [])
    if why:
        lines.append("  Why NanoBK stopped here:")
        for item in why:
            lines.append("    - {}".format(item))
        lines.append("")

    actions = explanation.get("next_actions", [])
    if actions:
        lines.append("  Next actions:")
        for i, action in enumerate(actions, 1):
            lines.append("    {}. {}".format(i, action.get("label", "")))
            lines.append("       {}".format(action.get("command", "")))
        lines.append("")

    hints = explanation.get("fix_hints", [])
    if hints:
        lines.append("  How to fix:")
        for hint in hints:
            lines.append("    - {}".format(hint))
        lines.append("")

    return "\n".join(lines)
