#!/usr/bin/env python3
"""
NanoBK Home Status Renderer

Shared renderer for Web/Bot/CLI surfaces.
Produces redacted home summary text and compact JSON.

Usage:
    from nanobk_home_render import render_home_text, render_home_card, compact_home_status
"""

import json


# ── Text renderer ───────────────────────────────────────────────────────────

def render_home_text(home, target="cli"):
    """Render home status as human-readable text.

    Args:
        home: dict from run_home()
        target: "cli", "web", or "bot"
    """
    profile = home.get("profile", {})
    explanation = home.get("explanation", {})
    safety = home.get("safety", {})
    status = home.get("home_status", "unknown")

    lines = []

    if target == "bot":
        lines.append("NanoBK Home")
    else:
        lines.append("  NanoBK Home")

    # Profile section
    if target == "bot":
        lines.append("Profile: {}".format(profile.get("status", "unknown")))
    else:
        lines.append("  Profile:")
        lines.append("    Status: {}".format(profile.get("status", "unknown")))

    if profile.get("status") == "configured":
        zone = profile.get("zone_name", "***")
        nodes = ", ".join(profile.get("nodes", []))
        if target == "bot":
            lines.append("Zone: {}".format(zone))
            lines.append("Nodes: {}".format(nodes))
        else:
            lines.append("    Zone: {}".format(zone))
            lines.append("    Nodes: {}".format(nodes))

    # Setup status
    if status not in ("no_profile", "blocked_profile_permission", "blocked_malformed_profile"):
        if target == "bot":
            lines.append("Status: {}".format(status))
            lines.append("DNS changed: {}".format(str(safety.get("dns_changed", False)).lower()))
            lines.append("Production apply: {}".format(str(safety.get("production_apply_enabled", False)).lower()))
        else:
            lines.append("")
            lines.append("  Setup:")
            lines.append("    Status: {}".format(status))
            lines.append("    DNS changed: {}".format(str(safety.get("dns_changed", False)).lower()))
            lines.append("    Production apply enabled: {}".format(str(safety.get("production_apply_enabled", False)).lower()))

    # Explanation
    plain_status = explanation.get("plain_status", "")
    if plain_status:
        if target == "bot":
            lines.append("")
            lines.append(plain_status)
        else:
            lines.append("")
            lines.append("  What this means:")
            lines.append("    {}".format(plain_status))

    # Next actions
    actions = explanation.get("next_actions", [])
    if actions:
        if target == "bot":
            lines.append("")
            lines.append("Next:")
        else:
            lines.append("")
            lines.append("  Next actions:")
        for i, action in enumerate(actions, 1):
            label = action.get("label", "")
            command = action.get("command", "")
            if target == "bot":
                lines.append("{}. {}".format(i, command))
            else:
                lines.append("    {}. {}".format(i, label))
                lines.append("       {}".format(command))

    # Safety footer
    if target == "bot":
        lines.append("")
        lines.append("DNS changed: {}".format(str(safety.get("dns_changed", False)).lower()))
    else:
        lines.append("")
        lines.append("  Safety:")
        lines.append("    Cloudflare touched: {}".format(safety.get("cloudflare_touched", "false")))
        lines.append("    DNS changed: {}".format(str(safety.get("dns_changed", False)).lower()))
        lines.append("    Records created: {}".format(str(safety.get("records_created", False)).lower()))
        lines.append("    Records modified: {}".format(str(safety.get("records_modified", False)).lower()))
        lines.append("    Records deleted: {}".format(str(safety.get("records_deleted", False)).lower()))

    return "\n".join(lines)


# ── Card renderer (for Web dashboard) ───────────────────────────────────────

def render_home_card(home):
    """Render home status as a structured card dict for Web dashboard.

    Returns a dict suitable for template rendering.
    """
    profile = home.get("profile", {})
    explanation = home.get("explanation", {})
    safety = home.get("safety", {})
    status = home.get("home_status", "unknown")

    return {
        "title": "NanoBK Home",
        "home_status": status,
        "profile_status": profile.get("status", "unknown"),
        "zone_name": profile.get("zone_name"),
        "nodes": profile.get("nodes", []),
        "explanation_title": explanation.get("summary_title", ""),
        "plain_status": explanation.get("plain_status", ""),
        "next_actions": [
            {"label": a.get("label", ""), "command": a.get("command", "")}
            for a in explanation.get("next_actions", [])
        ],
        "safety": {
            "dns_changed": safety.get("dns_changed", False),
            "records_created": safety.get("records_created", False),
            "production_apply_enabled": safety.get("production_apply_enabled", False),
        },
        "requires_auth": True,
    }


# ── Compact JSON (for Bot/API) ─────────────────────────────────────────────

def compact_home_status(home):
    """Return a compact redacted JSON-safe dict for Bot/API consumption.

    Never includes token, credential path, profile path, zone ID, record ID,
    raw API URL, or raw API response.
    """
    profile = home.get("profile", {})
    explanation = home.get("explanation", {})
    safety = home.get("safety", {})
    status = home.get("home_status", "unknown")

    return {
        "ok": home.get("ok", False),
        "home_status": status,
        "profile": {
            "status": profile.get("status", "unknown"),
            "zone_name": profile.get("zone_name"),
            "nodes": profile.get("nodes", []),
            "api_env_configured": profile.get("api_env_configured", False),
            "api_env_path_printed": False,
            "profile_path_printed": False,
        },
        "explanation": {
            "summary_title": explanation.get("summary_title", ""),
            "plain_status": explanation.get("plain_status", ""),
            "next_actions": [
                {"label": a.get("label", ""), "command": a.get("command", "")}
                for a in explanation.get("next_actions", [])
            ],
        },
        "safety": {
            "read_only": True,
            "dns_changed": safety.get("dns_changed", False),
            "records_created": safety.get("records_created", False),
            "records_modified": safety.get("records_modified", False),
            "records_deleted": safety.get("records_deleted", False),
            "production_apply_enabled": safety.get("production_apply_enabled", False),
            "owner_smoke_create_executed": safety.get("owner_smoke_create_executed", False),
            "raw_api_response_printed": False,
        },
        "requires_auth": True,
    }
