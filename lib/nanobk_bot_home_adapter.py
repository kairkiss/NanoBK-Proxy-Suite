#!/usr/bin/env python3
"""
NanoBK Bot Home Adapter

Provides a read-only home/status bridge for the Telegram Bot.
Calls run_home() and renders via shared renderer.

This adapter is the single integration point between the Bot handler
and the NanoBK home/status system. It ensures:

- Read-only access only
- No DNS mutation
- No Cloudflare mutation
- No token/credential/profile path leakage
- Auth gate contract (requires_auth=True in compact output)
- Safe text for Telegram message rendering

Usage:
    from nanobk_bot_home_adapter import get_home_text, get_home_compact

Bot integration example:
    async def cmd_home(update, context):
        text = get_home_text()
        await update.message.reply_text(text)

    async def cmd_home_json(update, context):
        data = get_home_compact()
        await update.message.reply_json(data)

Safety contract:
    - get_home_text() returns redacted text, never includes secrets
    - get_home_compact() returns requires_auth=True
    - Both fail closed on errors
    - Both never print token, credential path, profile path,
      zone ID, record ID, raw API URL, or raw API response
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_status import run_home
from nanobk_home_render import render_home_text, compact_home_status


def get_home_text():
    """Get home status as Bot-friendly text.

    Returns a redacted text summary suitable for Telegram message.
    Never includes token, credential path, profile path, zone ID,
    record ID, raw API URL, or raw API response.

    Returns plain text with newlines, no markdown.
    """
    try:
        home = run_home()
    except Exception:
        return "NanoBK Home\\nStatus: unknown\\nAn error occurred during home status check."
    return render_home_text(home, target="bot")


def get_home_compact():
    """Get home status as compact dict for Bot JSON output.

    Returns a redacted dict suitable for /home --json style output.
    Always includes requires_auth=True for auth gate contract.

    Never includes token, credential path, profile path, zone ID,
    record ID, raw API URL, or raw API response.
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
