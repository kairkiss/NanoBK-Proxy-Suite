#!/usr/bin/env python3
"""
NanoBK Web Home Adapter

Provides a read-only home/status bridge for the Web dashboard.
Calls run_home() and renders via shared renderer.

This adapter is the single integration point between the Web dashboard
and the NanoBK home/status system. It ensures:

- Read-only access only
- No DNS mutation
- No Cloudflare mutation
- No token/credential/profile path leakage
- Auth gate contract (requires_auth=True)
- Safe JSON for template rendering

Usage:
    from nanobk_web_home_adapter import get_home_json, get_home_card

Web integration example:
    @app.route("/api/home")
    @login_required
    def api_home():
        return get_home_json()

    @app.route("/")
    @login_required
    def dashboard():
        card = get_home_card()
        return render_template("home.html", card=card)

Safety contract:
    - get_home_json() returns requires_auth=True
    - get_home_card() returns requires_auth=True
    - Both never print token, credential path, profile path,
      zone ID, record ID, raw API URL, or raw API response
    - Both fail closed on errors
"""

import json
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_status import run_home
from nanobk_home_render import render_home_card, compact_home_status


def get_home_json():
    """Get home status as JSON-serializable dict for Web API.

    Returns a redacted dict. Never includes token, credential path,
    profile path, zone ID, record ID, raw API URL, or raw API response.

    The returned dict always contains:
    - ok: bool
    - home_status: str
    - profile: dict with status, zone_name, nodes, api_env_configured,
               api_env_path_printed=False, profile_path_printed=False
    - explanation: dict with summary_title, plain_status, next_actions
    - safety: dict with read_only=True, dns_changed, production_apply_enabled, etc.
    - requires_auth: True (always)
    """
    try:
        home = run_home()
    except Exception:
        return {
            "ok": False,
            "home_status": "unknown",
            "error": "home status check failed",
            "safety": {
                "read_only": True,
                "dns_changed": False,
                "production_apply_enabled": False,
            },
            "requires_auth": True,
        }
    return compact_home_status(home)


def get_home_card():
    """Get home status as a structured card dict for Web dashboard templates.

    Returns a dict with:
    - title: "NanoBK Home"
    - home_status: str
    - profile_status: str
    - zone_name: str or None
    - nodes: list
    - explanation_title: str
    - plain_status: str
    - next_actions: list of {label, command}
    - safety: dict
    - requires_auth: True (always)

    Safe for template rendering. Never includes secrets.
    """
    try:
        home = run_home()
    except Exception:
        return {
            "title": "NanoBK Home",
            "home_status": "unknown",
            "profile_status": "unknown",
            "explanation_title": "Status check failed",
            "plain_status": "An error occurred during home status check.",
            "next_actions": [],
            "safety": {"dns_changed": False, "production_apply_enabled": False},
            "requires_auth": True,
        }
    return render_home_card(home)
