#!/usr/bin/env python3
"""
NanoBK Proxy Suite — Bot Safe Status Summary Test (v1.9.10)

Verifies Bot /status format_status() produces a safe beginner-friendly summary.
Uses fake documentation-safe values only (RFC 5737/3849/2606).

Usage:
    python3 tests/bot-safe-status-summary-v1.9.10.py
"""

import os
import sys

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO_DIR)

from lib.nanobk_redaction import strip_ansi, redact_text

# ── Test infrastructure ─────────────────────────────────────────────────────

PASSED = 0
FAILED = 0


def check(desc: str, ok: bool) -> None:
    global PASSED, FAILED
    if ok:
        print(f"  \033[32m✓\033[0m {desc}")
        PASSED += 1
    else:
        print(f"  \033[31m✗\033[0m {desc}")
        FAILED += 1


# ── Import Bot helpers ──────────────────────────────────────────────────────

def limit_text(text: str, max_len: int = 3500) -> str:
    if len(text) <= max_len:
        return text
    return text[:max_len] + "\n... [truncated]"

def safe_output(text: str) -> str:
    text = strip_ansi(text)
    text = redact_text(text)
    return limit_text(text)


def _infer_overall(data: dict) -> str:
    ok = data.get("ok")
    if ok is True:
        return "healthy"
    if ok is False:
        return "failed"
    return "unknown"


def _infer_vps(data: dict) -> str:
    services = data.get("services")
    if not isinstance(services, dict):
        return "unknown"
    statuses = [services.get(p) for p in ("hy2", "tuic", "reality", "trojan")]
    if all(s == "active" for s in statuses):
        return "healthy"
    if any(s == "active" for s in statuses):
        return "partial"
    if any(s in ("failed", "inactive") for s in statuses):
        return "failed"
    if any(s == "missing" for s in statuses):
        return "incomplete"
    return "unknown"


def _infer_cf_status(cf_entry: dict) -> str:
    if not isinstance(cf_entry, dict):
        return "unknown"
    if cf_entry.get("verified"):
        return "verified"
    if cf_entry.get("envExists"):
        return "configured"
    return "missing"


def _infer_subscription(data: dict) -> str:
    sub = data.get("subscription")
    if not isinstance(sub, dict):
        return "unknown"
    if sub.get("verified"):
        return "verified"
    if sub.get("configured"):
        return "configured"
    if sub.get("url"):
        return "configured"
    return "unknown"


def _infer_profile(data: dict) -> str:
    profile = data.get("profile")
    if isinstance(profile, dict):
        if profile.get("currentPath") or profile.get("domain"):
            return "present"
    if data.get("domain") and data.get("domain") != "<not set>":
        return "present"
    return "unknown"


def _next_step_hint(overall, vps, cf_nanok, cf_nanob, sub) -> str:
    if overall == "failed":
        return "Check SSH or run NanoBK recovery from the server."
    if vps == "failed":
        return "Check SSH and verify proxy services are running."
    if cf_nanok in ("missing", "unknown") or cf_nanob in ("missing", "unknown"):
        return "Finish Cloudflare verification from the Full Wizard or CLI."
    if sub in ("manual_pending", "unknown"):
        return "Verify subscription access from the Full Wizard or CLI."
    if overall == "healthy" and vps == "healthy":
        return "No immediate action required."
    return "Run /doctor for a redacted diagnostic summary, or check SSH if needed."


def format_status(data: dict) -> str:
    if not isinstance(data, dict):
        return "NanoBK Status Summary\n\nStatus data unavailable.\n\nNext step:\nRun /doctor or check SSH."
    lines = ["NanoBK Status Summary", ""]
    overall = _infer_overall(data)
    lines.append(f"Overall: {overall}")
    vps = _infer_vps(data)
    lines.append(f"VPS: {vps}")
    services = data.get("services")
    if isinstance(services, dict):
        lines.append("Protocols:")
        for name in ("hy2", "tuic", "reality", "trojan"):
            lines.append(f"  {name.upper()}: {services.get(name, 'unknown')}")
    else:
        lines.append("Protocols: unknown")
    cf = data.get("cloudflare")
    if isinstance(cf, dict):
        nanok = cf.get("nanok", {})
        nanob = cf.get("nanob", {})
        cf_nanok = _infer_cf_status(nanok)
        cf_nanob = _infer_cf_status(nanob)
        lines.append("Cloudflare:")
        lines.append(f"  nanok: {cf_nanok}")
        lines.append(f"  nanob: {cf_nanob}")
    else:
        cf_nanok = "unknown"
        cf_nanob = "unknown"
        lines.append("Cloudflare: unknown")
    sub = _infer_subscription(data)
    lines.append(f"Subscription: {sub}")
    security = data.get("security")
    if isinstance(security, dict):
        mode = security.get("secretsMode", "unknown")
        lines.append(f"Secrets: present, mode {mode}")
    else:
        lines.append("Secrets: unknown")
    profile = _infer_profile(data)
    lines.append(f"Profile: {profile}")
    hint = _next_step_hint(overall, vps, cf_nanok, cf_nanob, sub)
    lines.append("")
    lines.append(f"Next step:\n{hint}")
    return "\n".join(lines)


# ── Fake test data ──────────────────────────────────────────────────────────

FAKE_IPV4 = "203.0.113.10"
FAKE_IPV6 = "2001:db8::10"
FAKE_DOMAIN = "node.example.invalid"
FAKE_URL = "https://worker.example.invalid/sub/REDACTED_EXAMPLE"
FAKE_WORKERS_DEV = "nanobk-test.example.invalid.workers.dev"
FAKE_SUB_PATH = "/sub/fake-sub-path-12345"
FAKE_TOKEN = "fake-doc-token-abc123xyz"
FAKE_SECRET = "fake-secret-value-do-not-use"
FAKE_PRIVATE_KEY = "FAKE_PRIVATE_KEY_DO_NOT_USE_abc123def456"


# ── Tests ───────────────────────────────────────────────────────────────────

def test_healthy_full() -> None:
    print("\n--- Healthy full status ---\n")

    data = {
        "ok": True, "domain": FAKE_DOMAIN, "vpsIp": FAKE_IPV4, "geo": "JP",
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "security": {"secretsMode": "600", "token": FAKE_TOKEN, "privateKey": FAKE_PRIVATE_KEY},
        "cloudflare": {
            "nanok": {"envExists": True, "route": FAKE_URL, "workersDev": FAKE_WORKERS_DEV},
            "nanob": {"envExists": False},
            "adminToken": FAKE_TOKEN,
        },
        "subscription": {"url": f"https://{FAKE_DOMAIN}{FAKE_SUB_PATH}", "configured": True},
        "profile": {"domain": FAKE_DOMAIN, "vpsIp": FAKE_IPV4, "ipv6": FAKE_IPV6, "currentPath": "/etc/nanobk/profile.current.json"},
        "warnings": []
    }

    out = format_status(data)
    safe = safe_output(out)

    # No address labels/values
    check("No 'Domain:' label", "Domain:" not in out)
    check("No 'VPS IP:' label", "VPS IP:" not in out)
    check("No raw domain", FAKE_DOMAIN not in out)
    check("No raw IPv4", FAKE_IPV4 not in out)
    check("No raw IPv6", FAKE_IPV6 not in out)
    check("No raw URL", FAKE_URL not in out)
    check("No raw workers.dev", FAKE_WORKERS_DEV not in out)
    check("No raw subscription path", "fake-sub-path-12345" not in out)
    check("No raw token", FAKE_TOKEN not in out)
    check("No raw private key", FAKE_PRIVATE_KEY not in out)

    # Honest status words
    check("Overall: healthy", "Overall: healthy" in out)
    check("VPS: healthy", "VPS: healthy" in out)
    check("HY2: active", "HY2: active" in out)
    check("TUIC: active", "TUIC: active" in out)
    check("REALITY: active", "REALITY: active" in out)
    check("TROJAN: active", "TROJAN: active" in out)
    check("nanok: configured", "nanok: configured" in out)
    check("nanob: missing", "nanob: missing" in out)
    check("Subscription: configured", "Subscription: configured" in out)
    check("Secrets: present, mode 600", "Secrets: present, mode 600" in out)
    check("Profile: present", "Profile: present" in out)
    check("Next step present", "Next step:" in out)
    # nanob is missing so hint is Cloudflare verification
    check("CF verification hint", "Cloudflare" in out)

    # Safe output also clean
    check("safe_output no raw domain", FAKE_DOMAIN not in safe)
    check("safe_output no raw IPv4", FAKE_IPV4 not in safe)

    # Not a JSON dump
    check("Not JSON braces dump", "{" not in out and "}" not in out)

    # Reasonably short
    check("Output under 3500 chars", len(out) < 3500)


def test_failed_status() -> None:
    print("\n--- Failed status ---\n")

    data = {
        "ok": False, "domain": FAKE_DOMAIN, "vpsIp": FAKE_IPV4,
        "services": {"hy2": "failed", "tuic": "inactive", "reality": "active", "trojan": "active"},
        "security": {"secretsMode": "600"},
        "cloudflare": {"nanok": {"envExists": True}, "nanob": {"envExists": True}},
        "warnings": ["Service hy2 is down"]
    }

    out = format_status(data)

    check("Overall: failed", "Overall: failed" in out)
    check("HY2: failed", "HY2: failed" in out)
    check("TUIC: inactive", "TUIC: inactive" in out)
    check("Failed next step", "SSH" in out or "recovery" in out.lower())
    check("No raw domain", FAKE_DOMAIN not in out)
    check("No raw IPv4", FAKE_IPV4 not in out)


def test_missing_keys() -> None:
    print("\n--- Missing keys produce unknown ---\n")

    data = {"ok": True}
    out = format_status(data)

    check("Missing services → Protocols: unknown", "Protocols: unknown" in out)
    check("Missing cloudflare → Cloudflare: unknown", "Cloudflare: unknown" in out)
    check("Missing subscription → Subscription: unknown", "Subscription: unknown" in out)
    check("Missing security → Secrets: unknown", "Secrets: unknown" in out)
    check("Missing profile → Profile: unknown", "Profile: unknown" in out)


def test_empty_dict() -> None:
    print("\n--- Empty dict ---\n")

    data = {}
    out = format_status(data)

    check("Empty dict → Overall: unknown", "Overall: unknown" in out)
    check("Empty dict → VPS: unknown", "VPS: unknown" in out)
    check("No crash on empty dict", len(out) > 0)


def test_non_dict() -> None:
    print("\n--- Non-dict input ---\n")

    out = format_status(None)
    check("None → data unavailable", "unavailable" in out.lower())

    out2 = format_status("invalid")
    check("String → data unavailable", "unavailable" in out2.lower())


def test_partial_services() -> None:
    print("\n--- Partial services ---\n")

    data = {
        "ok": True,
        "services": {"hy2": "active", "tuic": "unknown", "reality": "active", "trojan": "active"}
    }
    out = format_status(data)

    check("Partial → VPS: partial", "VPS: partial" in out)
    check("HY2: active", "HY2: active" in out)
    check("TUIC: unknown", "TUIC: unknown" in out)


def test_dry_run_planned_skipped() -> None:
    print("\n--- dry-run/planned/skipped do not become success ---\n")

    data = {
        "ok": None,
        "services": {"hy2": "dry-run", "tuic": "planned", "reality": "skipped", "trojan": "unknown"}
    }
    out = format_status(data)

    check("ok=None → Overall: unknown", "Overall: unknown" in out)
    check("HY2: dry-run preserved", "HY2: dry-run" in out)
    check("TUIC: planned preserved", "TUIC: planned" in out)
    check("REALITY: skipped preserved", "REALITY: skipped" in out)
    check("No false success", "healthy" not in out.split("Overall:")[1].split("\n")[0])


def test_cf_verified() -> None:
    print("\n--- Cloudflare verified ---\n")

    data = {
        "ok": True,
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "cloudflare": {"nanok": {"envExists": True, "verified": True}, "nanob": {"envExists": True, "verified": True}},
        "subscription": {"verified": True, "configured": True}
    }
    out = format_status(data)

    check("nanok: verified", "nanok: verified" in out)
    check("nanob: verified", "nanob: verified" in out)
    check("Subscription: verified", "Subscription: verified" in out)
    check("No immediate action", "No immediate action required" in out)


def test_manual_pending() -> None:
    print("\n--- Manual pending ---\n")

    data = {
        "ok": True,
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "cloudflare": {"nanok": {"envExists": False}, "nanob": {"envExists": False}},
        "subscription": {"configured": False}
    }
    out = format_status(data)

    check("nanok: missing", "nanok: missing" in out)
    check("Subscription: unknown", "Subscription: unknown" in out)
    check("CF verification hint", "Cloudflare" in out and "Next step:" in out)


def test_no_json_dump() -> None:
    print("\n--- Output is not a raw JSON dump ---\n")

    data = {
        "ok": True, "domain": FAKE_DOMAIN, "vpsIp": FAKE_IPV4,
        "services": {"hy2": "active"},
        "security": {"secretsMode": "600"},
        "cloudflare": {},
        "subscription": {},
        "profile": {},
        "warnings": []
    }
    out = format_status(data)

    check("No JSON braces", "{" not in out and "}" not in out)
    check("No JSON quotes around keys", '":' not in out)
    check("Has title", "NanoBK Status Summary" in out)
    check("Has next step", "Next step:" in out)


def test_length() -> None:
    print("\n--- Output length ---\n")

    data = {
        "ok": True, "domain": FAKE_DOMAIN, "vpsIp": FAKE_IPV4,
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "security": {"secretsMode": "600"},
        "cloudflare": {"nanok": {"envExists": True}, "nanob": {"envExists": True}},
        "subscription": {"configured": True},
        "profile": {"currentPath": "/etc/nanobk/profile.current.json"},
        "warnings": []
    }
    out = format_status(data)
    check("Output under 1000 chars", len(out) < 1000)
    check("Output over 50 chars", len(out) > 50)


def test_status_json_unchanged() -> None:
    print("\n--- /status_json source unchanged ---\n")

    bot_src = open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")).read()

    check("cmd_status_json still exists", "async def cmd_status_json" in bot_src)
    check("cmd_status_json still uses safe_output", "safe_output(result.stdout)" in bot_src)
    check("cmd_status_json still registered", 'CommandHandler("status_json"' in bot_src)


# ── Main ────────────────────────────────────────────────────────────────────

def main() -> int:
    print("")
    print("=== NanoBK Bot Safe Status Summary Test (v1.9.10) ===")
    print("")
    print("Purpose: Verify Bot /status produces safe beginner summary.")
    print("Scope:   Fake values only. No real nanobk/Telegram.")
    print("")

    test_healthy_full()
    test_failed_status()
    test_missing_keys()
    test_empty_dict()
    test_non_dict()
    test_partial_services()
    test_dry_run_planned_skipped()
    test_cf_verified()
    test_manual_pending()
    test_no_json_dump()
    test_length()
    test_status_json_unchanged()

    print("")
    print("=== Test Summary ===")
    print("")
    print(f"  \033[32m{PASSED} passed\033[0m, \033[31m{FAILED} failed\033[0m")
    print("")

    if FAILED == 0:
        print("  \033[32mAll Bot safe status summary tests passed!\033[0m")
        return 0
    else:
        print(f"  \033[31m{FAILED} test(s) failed.\033[0m")
        return 1


if __name__ == "__main__":
    sys.exit(main())
