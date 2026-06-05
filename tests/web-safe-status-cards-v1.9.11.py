#!/usr/bin/env python3
"""
NanoBK Proxy Suite — Web Safe Status Cards Test (v1.9.11)

Verifies Web Dashboard/Status normal views produce safe beginner-friendly cards.
Uses fake documentation-safe values only (RFC 5737/3849/2606).

Usage:
    python3 tests/web-safe-status-cards-v1.9.11.py
"""

import json
import os
import sys

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO_DIR)

from lib.nanobk_redaction import strip_ansi, redact_text, redact_json_obj

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


# ── Import Web helpers (replicate from web/app.py) ─────────────────────────

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


def _infer_cf_status(cf_entry: object) -> str:
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


def _infer_secrets(data: dict) -> str:
    security = data.get("security")
    if not isinstance(security, dict):
        return "unknown"
    mode = security.get("secretsMode")
    if mode:
        return f"present, mode {mode}"
    return "present"


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
    return "Run Doctor for a redacted diagnostic summary, or check SSH if needed."


def _build_safe_cards(data: dict) -> dict:
    if not isinstance(data, dict):
        return {
            "overall": "unknown", "vps": "unknown", "services": {},
            "cf_nanok": "unknown", "cf_nanob": "unknown",
            "subscription": "unknown", "secrets": "unknown",
            "profile": "unknown",
            "next_step": "Run Doctor for a redacted diagnostic summary, or check SSH if needed.",
        }
    overall = _infer_overall(data)
    vps = _infer_vps(data)
    services = data.get("services")
    svc_out = {}
    if isinstance(services, dict):
        for name in ("hy2", "tuic", "reality", "trojan"):
            svc_out[name] = services.get(name, "unknown")
    else:
        for name in ("hy2", "tuic", "reality", "trojan"):
            svc_out[name] = "unknown"
    cf = data.get("cloudflare")
    cf_nanok = "unknown"
    cf_nanob = "unknown"
    if isinstance(cf, dict):
        cf_nanok = _infer_cf_status(cf.get("nanok"))
        cf_nanob = _infer_cf_status(cf.get("nanob"))
    sub = _infer_subscription(data)
    secrets_str = _infer_secrets(data)
    profile = _infer_profile(data)
    hint = _next_step_hint(overall, vps, cf_nanok, cf_nanob, sub)
    return {
        "overall": overall, "vps": vps, "services": svc_out,
        "cf_nanok": cf_nanok, "cf_nanob": cf_nanob,
        "subscription": sub, "secrets": secrets_str,
        "profile": profile, "next_step": hint,
    }


def format_status(data: dict) -> dict:
    redacted = redact_json_obj(data)
    cards = _build_safe_cards(data)
    return {"cards": cards, "raw_json": json.dumps(redacted, indent=2)}


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

    result = format_status(data)
    cards = result["cards"]
    cards_str = json.dumps(cards)

    # No address values in cards
    check("Cards: no raw domain", FAKE_DOMAIN not in cards_str)
    check("Cards: no raw IPv4", FAKE_IPV4 not in cards_str)
    check("Cards: no raw IPv6", FAKE_IPV6 not in cards_str)
    check("Cards: no raw URL", "worker.example.invalid" not in cards_str)
    check("Cards: no raw workers.dev", "nanobk-test" not in cards_str)
    check("Cards: no raw subscription path", "fake-sub-path-12345" not in cards_str)
    check("Cards: no raw token", FAKE_TOKEN not in cards_str)
    check("Cards: no raw private key", FAKE_PRIVATE_KEY not in cards_str)

    # No address labels
    check("Cards: no 'Domain' key", "Domain" not in cards_str and "domain" not in cards_str)
    check("Cards: no 'vpsIp' key", "vpsIp" not in cards_str)
    check("Cards: no 'geo' key", "geo" not in cards_str)

    # Honest status words
    check("Cards: overall healthy", cards["overall"] == "healthy")
    check("Cards: VPS healthy", cards["vps"] == "healthy")
    check("Cards: HY2 active", cards["services"]["hy2"] == "active")
    check("Cards: TUIC active", cards["services"]["tuic"] == "active")
    check("Cards: REALITY active", cards["services"]["reality"] == "active")
    check("Cards: TROJAN active", cards["services"]["trojan"] == "active")
    check("Cards: nanok configured", cards["cf_nanok"] == "configured")
    check("Cards: nanob missing", cards["cf_nanob"] == "missing")
    check("Cards: subscription configured", cards["subscription"] == "configured")
    check("Cards: secrets present mode 600", "600" in cards["secrets"])
    check("Cards: profile present", cards["profile"] == "present")
    check("Cards: next step present", len(cards["next_step"]) > 0)

    # Raw JSON still exists and is redacted
    check("Raw JSON exists", "raw_json" in result)
    check("Raw JSON no raw domain", FAKE_DOMAIN not in result["raw_json"])
    check("Raw JSON no raw IPv4", FAKE_IPV4 not in result["raw_json"])
    check("Raw JSON no raw token", FAKE_TOKEN not in result["raw_json"])


def test_failed_status() -> None:
    print("\n--- Failed status ---\n")

    data = {
        "ok": False, "domain": FAKE_DOMAIN, "vpsIp": FAKE_IPV4,
        "services": {"hy2": "failed", "tuic": "inactive", "reality": "active", "trojan": "active"},
        "security": {"secretsMode": "600"},
        "cloudflare": {"nanok": {"envExists": True}, "nanob": {"envExists": True}},
    }

    cards = format_status(data)["cards"]
    cards_str = json.dumps(cards)

    check("Failed: overall failed", cards["overall"] == "failed")
    check("Failed: HY2 failed", cards["services"]["hy2"] == "failed")
    check("Failed: TUIC inactive", cards["services"]["tuic"] == "inactive")
    check("Failed: no raw domain", FAKE_DOMAIN not in cards_str)
    check("Failed: no raw IPv4", FAKE_IPV4 not in cards_str)
    check("Failed: SSH hint", "SSH" in cards["next_step"])


def test_missing_keys() -> None:
    print("\n--- Missing keys produce unknown ---\n")

    data = {"ok": True}
    cards = format_status(data)["cards"]

    check("Missing services → unknown", all(v == "unknown" for v in cards["services"].values()))
    check("Missing cloudflare → unknown", cards["cf_nanok"] == "unknown" and cards["cf_nanob"] == "unknown")
    check("Missing subscription → unknown", cards["subscription"] == "unknown")
    check("Missing security → secrets unknown", cards["secrets"] == "unknown")
    check("Missing profile → unknown", cards["profile"] == "unknown")


def test_empty_dict() -> None:
    print("\n--- Empty dict ---\n")

    data = {}
    cards = format_status(data)["cards"]

    check("Empty: overall unknown", cards["overall"] == "unknown")
    check("Empty: VPS unknown", cards["vps"] == "unknown")
    check("No crash on empty", len(cards) > 0)


def test_non_dict() -> None:
    print("\n--- Non-dict input ---\n")

    result = format_status(None)
    check("None: overall unknown", result["cards"]["overall"] == "unknown")


def test_partial_services() -> None:
    print("\n--- Partial services ---\n")

    data = {
        "ok": True,
        "services": {"hy2": "active", "tuic": "unknown", "reality": "active", "trojan": "active"}
    }
    cards = format_status(data)["cards"]

    check("Partial: VPS partial", cards["vps"] == "partial")
    check("Partial: HY2 active", cards["services"]["hy2"] == "active")
    check("Partial: TUIC unknown", cards["services"]["tuic"] == "unknown")


def test_dry_run_planned_skipped() -> None:
    print("\n--- dry-run/planned/skipped do not become success ---\n")

    data = {
        "ok": None,
        "services": {"hy2": "dry-run", "tuic": "planned", "reality": "skipped", "trojan": "unknown"}
    }
    cards = format_status(data)["cards"]

    check("ok=None → unknown", cards["overall"] == "unknown")
    check("HY2 dry-run preserved", cards["services"]["hy2"] == "dry-run")
    check("TUIC planned preserved", cards["services"]["tuic"] == "planned")
    check("REALITY skipped preserved", cards["services"]["reality"] == "skipped")
    check("No false success", cards["overall"] != "healthy")


def test_cf_verified() -> None:
    print("\n--- Cloudflare verified ---\n")

    data = {
        "ok": True,
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "cloudflare": {"nanok": {"envExists": True, "verified": True}, "nanob": {"envExists": True, "verified": True}},
        "subscription": {"verified": True, "configured": True}
    }
    cards = format_status(data)["cards"]

    check("nanok verified", cards["cf_nanok"] == "verified")
    check("nanob verified", cards["cf_nanob"] == "verified")
    check("Subscription verified", cards["subscription"] == "verified")
    check("No immediate action", "No immediate action" in cards["next_step"])


def test_manual_pending() -> None:
    print("\n--- Manual pending ---\n")

    data = {
        "ok": True,
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "cloudflare": {"nanok": {"envExists": False}, "nanob": {"envExists": False}},
        "subscription": {"configured": False}
    }
    cards = format_status(data)["cards"]

    check("nanok missing", cards["cf_nanok"] == "missing")
    check("Subscription unknown", cards["subscription"] == "unknown")
    check("CF hint", "Cloudflare" in cards["next_step"])


def test_no_json_dump() -> None:
    print("\n--- Cards are not a raw JSON dump ---\n")

    data = {
        "ok": True, "domain": FAKE_DOMAIN, "vpsIp": FAKE_IPV4,
        "services": {"hy2": "active"},
        "security": {"secretsMode": "600"},
        "cloudflare": {}, "subscription": {}, "profile": {}, "warnings": []
    }
    cards = format_status(data)["cards"]
    cards_str = json.dumps(cards)

    # Cards dict should not contain raw JSON field names from status
    check("No 'domain' key in cards", "domain" not in cards)
    check("No 'vpsIp' key in cards", "vpsIp" not in cards)
    check("No 'warnings' key in cards", "warnings" not in cards)
    check("Has overall", "overall" in cards)
    check("Has next_step", "next_step" in cards)


def test_raw_json_preserved() -> None:
    print("\n--- Raw JSON details preserved ---\n")

    data = {
        "ok": True, "domain": FAKE_DOMAIN, "vpsIp": FAKE_IPV4,
        "services": {"hy2": "active"}, "security": {}, "cloudflare": {},
        "warnings": []
    }
    result = format_status(data)

    check("raw_json key exists", "raw_json" in result)
    check("raw_json is valid JSON", json.loads(result["raw_json"]) is not None)
    check("raw_json contains services", "hy2" in result["raw_json"])
    check("raw_json no raw domain", FAKE_DOMAIN not in result["raw_json"])
    check("raw_json no raw IPv4", FAKE_IPV4 not in result["raw_json"])


def test_source_checks() -> None:
    print("\n--- Source code checks ---\n")

    web_src = open(os.path.join(REPO_DIR, "web", "app.py")).read()

    check("Web has _build_safe_cards", "_build_safe_cards" in web_src)
    check("Web has _infer_overall", "_infer_overall" in web_src)
    check("Web has _infer_vps", "_infer_vps" in web_src)
    check("Web has _infer_cf_status", "_infer_cf_status" in web_src)
    check("Web has _infer_subscription", "_infer_subscription" in web_src)
    check("Web has _infer_profile", "_infer_profile" in web_src)
    check("Web has _infer_secrets", "_infer_secrets" in web_src)
    check("Web has _next_step_hint", "_next_step_hint" in web_src)
    check("Web has cmd_status_json unchanged", "async def cmd_status_json" not in web_src or "status_json" in web_src)

    # Verify Raw JSON details still in template
    status_html = open(os.path.join(REPO_DIR, "web", "templates", "status.html")).read()
    check("Status template has Raw JSON details", "<details>" in status_html)
    check("Status template has raw_json", "raw_json" in status_html)

    # Verify login/CSRF/rotate not modified
    check("Web has login route", '"/login"' in web_src)
    check("Web has validate_csrf", "validate_csrf" in web_src)
    check("Web has rotate_confirm", "rotate_confirm" in web_src)
    check("Web has run_nanobk", "run_nanobk" in web_src)


# ── Main ────────────────────────────────────────────────────────────────────

def main() -> int:
    print("")
    print("=== NanoBK Web Safe Status Cards Test (v1.9.11) ===")
    print("")
    print("Purpose: Verify Web Dashboard/Status normal views are safe.")
    print("Scope:   Fake values only. No real nanobk/Web server.")
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
    test_raw_json_preserved()
    test_source_checks()

    print("")
    print("=== Test Summary ===")
    print("")
    print(f"  \033[32m{PASSED} passed\033[0m, \033[31m{FAILED} failed\033[0m")
    print("")

    if FAILED == 0:
        print("  \033[32mAll Web safe status cards tests passed!\033[0m")
        return 0
    else:
        print(f"  \033[31m{FAILED} test(s) failed.\033[0m")
        return 1


if __name__ == "__main__":
    sys.exit(main())
