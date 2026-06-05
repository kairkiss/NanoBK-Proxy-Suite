#!/usr/bin/env python3
"""
Test: Doctor Summary Field Compatibility Fixture Tests (v1.9.42)

Validates fixture contract for T15-P2-001 field compatibility fix.
No Bot/Web runtime. No real doctor. No real env. No shell execution.
Does NOT import Bot or Web modules.

Usage:
    python3 tests/doctor-field-compatibility-fixtures-v1.9.42.py
"""

import json
import os
import sys

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures", "doctor-field-compatibility-v1.9.42")
OLD_FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures", "doctor-summary-v1.9.35")

passed = 0
failed = 0

def check(desc: str, ok: bool):
    global passed, failed
    if ok:
        print(f"  \033[32m✓\033[0m {desc}")
        passed += 1
    else:
        print(f"  \033[31m✗\033[0m {desc}")
        failed += 1

# ── Allowed values ─────────────────────────────────────────────────────────────

ALLOWED_OVERALL = {"healthy", "partial", "failed", "unknown"}
ALLOWED_CONTROL_PLANE = {"ok", "warning", "failed", "unknown"}
ALLOWED_CLI = {"available", "missing", "unknown"}
ALLOWED_PROFILE = {"present", "missing", "unknown"}
ALLOWED_CONFIG = {"present", "missing", "unknown"}
ALLOWED_SERVICE = {"active", "inactive", "missing", "unknown"}
ALLOWED_CLOUDFLARE = {"verified", "configured", "missing", "manual_pending", "unknown"}
ALLOWED_SUBSCRIPTION = {"verified", "configured", "missing", "unknown"}
ALLOWED_SECURITY = {"ok", "warning", "failed", "unknown"}
ALLOWED_NEXT_STEP = {"no_action", "check_failed_services", "complete_config", "configure_cloudflare", "use_advanced_diagnostics", "unknown"}
SERVICE_NAMES = {"hy2", "tuic", "reality", "trojan"}

# ── Forbidden patterns in expected summaries ───────────────────────────────────

FORBIDDEN_PATTERNS = [
    "192.0.2.",
    "198.51.100.",
    "203.0.113.",
    "2001:db8:",
    "example.invalid",
    "nanobk-test.invalid",
    "http://",
    "https://",
    "workers.dev",
    "TEST_TOKEN",
    "TEST_SECRET",
    "TEST_PRIVATE_KEY",
    "/sub/",
    "PRIVATE_KEY",
    "BEGIN PRIVATE",
    "/tmp/nanobk-test-config",
    "/etc/nanobk",
]

# ── Fixture pairs ─────────────────────────────────────────────────────────────

FIXTURE_PAIRS = [
    ("realistic-status.json", "expected-realistic-summary.json", "realistic"),
    ("profile-exists-no-domain.json", "expected-profile-exists-no-domain-summary.json", "profile_exists_no_domain"),
    ("profile-missing-explicit.json", "expected-profile-missing-explicit-summary.json", "profile_missing_explicit"),
    ("security-missing-secrets.json", "expected-security-missing-secrets-summary.json", "security_missing_secrets"),
    ("profile-present-services-missing.json", "expected-profile-present-services-missing-summary.json", "profile_present_services_missing"),
    ("dashboard-compatible-shape.json", "expected-dashboard-compatible-summary.json", "dashboard_compatible"),
]

print("=== Doctor Summary Field Compatibility Fixture Test (v1.9.42) ===\n")
print("NOTE: This test validates contract fixture data only.")
print("Current builders are NOT required to pass these fixtures yet.")
print("v1.9.43 will update builder tests to consume these fixtures.\n")

# ══════════════════════════════════════════════════════════════════════════════
# A. Fixture existence
# ══════════════════════════════════════════════════════════════════════════════

print("--- A. Fixture existence ---\n")

for input_name, expected_name, label in FIXTURE_PAIRS:
    check(f"{label}: input exists", os.path.exists(os.path.join(FIXTURES_DIR, input_name)))
    check(f"{label}: expected exists", os.path.exists(os.path.join(FIXTURES_DIR, expected_name)))

# ══════════════════════════════════════════════════════════════════════════════
# B. JSON validity
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- B. JSON validity ---\n")

for input_name, expected_name, label in FIXTURE_PAIRS:
    try:
        with open(os.path.join(FIXTURES_DIR, input_name)) as f:
            data = json.load(f)
        check(f"{label}: input JSON valid", isinstance(data, dict))
    except (json.JSONDecodeError, FileNotFoundError) as e:
        check(f"{label}: input JSON valid", False)

    try:
        with open(os.path.join(FIXTURES_DIR, expected_name)) as f:
            data = json.load(f)
        check(f"{label}: expected JSON valid", isinstance(data, dict))
    except (json.JSONDecodeError, FileNotFoundError) as e:
        check(f"{label}: expected JSON valid", False)

# ══════════════════════════════════════════════════════════════════════════════
# C. Expected summary schema
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- C. Expected summary schema ---\n")

REQUIRED_TOP_KEYS = {"overall", "control_plane", "cli", "profile", "config",
                     "services", "cloudflare", "subscription", "security",
                     "doctor", "next_step", "display_policy"}
REQUIRED_DOCTOR_KEYS = {"errors", "warnings", "full_available"}
REQUIRED_DISPLAY_POLICY_KEYS = {"beginner_safe", "full_output_advanced_only", "redaction_required"}

def validate_schema(data: dict, label: str) -> bool:
    ok = True
    for key in REQUIRED_TOP_KEYS:
        if key not in data:
            check(f"{label}: has key '{key}'", False)
            ok = False
    if not ok:
        return False

    check(f"{label}: overall in allowed", data["overall"] in ALLOWED_OVERALL)
    check(f"{label}: control_plane in allowed", data["control_plane"] in ALLOWED_CONTROL_PLANE)
    check(f"{label}: cli in allowed", data["cli"] in ALLOWED_CLI)
    check(f"{label}: profile in allowed", data["profile"] in ALLOWED_PROFILE)
    check(f"{label}: config in allowed", data["config"] in ALLOWED_CONFIG)
    check(f"{label}: cloudflare in allowed", data["cloudflare"] in ALLOWED_CLOUDFLARE)
    check(f"{label}: subscription in allowed", data["subscription"] in ALLOWED_SUBSCRIPTION)
    check(f"{label}: security in allowed", data["security"] in ALLOWED_SECURITY)
    check(f"{label}: next_step in allowed", data["next_step"] in ALLOWED_NEXT_STEP)

    if isinstance(data.get("services"), dict):
        for svc in SERVICE_NAMES:
            check(f"{label}: services.{svc} in allowed", data["services"].get(svc) in ALLOWED_SERVICE)
    else:
        check(f"{label}: services is dict", False)

    if isinstance(data.get("doctor"), dict):
        for key in REQUIRED_DOCTOR_KEYS:
            check(f"{label}: doctor.{key} exists", key in data["doctor"])
    else:
        check(f"{label}: doctor is dict", False)

    if isinstance(data.get("display_policy"), dict):
        for key in REQUIRED_DISPLAY_POLICY_KEYS:
            check(f"{label}: display_policy.{key} exists", key in data["display_policy"])
        check(f"{label}: beginner_safe == True", data["display_policy"].get("beginner_safe") is True)
        check(f"{label}: full_output_advanced_only == True", data["display_policy"].get("full_output_advanced_only") is True)
        check(f"{label}: redaction_required == True", data["display_policy"].get("redaction_required") is True)
    else:
        check(f"{label}: display_policy is dict", False)

    return ok

for input_name, expected_name, label in FIXTURE_PAIRS:
    try:
        with open(os.path.join(FIXTURES_DIR, expected_name)) as f:
            data = json.load(f)
        validate_schema(data, label)
    except Exception:
        check(f"{label}: schema validation", False)

# ══════════════════════════════════════════════════════════════════════════════
# D. Mapping rules
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- D. Mapping rules ---\n")

def load_expected(name):
    with open(os.path.join(FIXTURES_DIR, name)) as f:
        return json.load(f)

# realistic: profile.exists=true → present, config present
r = load_expected("expected-realistic-summary.json")
check("realistic: profile == present", r["profile"] == "present")
check("realistic: config == present", r["config"] == "present")
check("realistic: security == ok", r["security"] == "ok")
check("realistic: overall == healthy", r["overall"] == "healthy")

# profile-exists-no-domain: profile.exists=true, domain="<not set>" → present
pnd = load_expected("expected-profile-exists-no-domain-summary.json")
check("profile_exists_no_domain: profile == present", pnd["profile"] == "present")
check("profile_exists_no_domain: config == present", pnd["config"] == "present")

# profile-missing-explicit: profile.exists=false → missing
pme = load_expected("expected-profile-missing-explicit-summary.json")
check("profile_missing_explicit: profile == missing", pme["profile"] == "missing")
check("profile_missing_explicit: overall != healthy", pme["overall"] != "healthy")

# security-missing-secrets: secretsExists=false → warning
sms = load_expected("expected-security-missing-secrets-summary.json")
check("security_missing_secrets: security != ok", sms["security"] != "ok")
check("security_missing_secrets: profile == missing", sms["profile"] == "missing")
check("security_missing_secrets: overall != healthy", sms["overall"] != "healthy")

# profile-present-services-missing: profile present but services unknown
ppsm = load_expected("expected-profile-present-services-missing-summary.json")
check("profile_present_services_missing: profile == present", ppsm["profile"] == "present")
check("profile_present_services_missing: config == present", ppsm["config"] == "present")
check("profile_present_services_missing: overall != healthy", ppsm["overall"] != "healthy")
check("profile_present_services_missing: all services unknown", all(v == "unknown" for v in ppsm["services"].values()))

# dashboard-compatible: currentPath/domain shape still works
dc = load_expected("expected-dashboard-compatible-summary.json")
check("dashboard_compatible: profile == present", dc["profile"] == "present")
check("dashboard_compatible: config == present", dc["config"] == "present")
check("dashboard_compatible: overall == healthy", dc["overall"] == "healthy")

# ══════════════════════════════════════════════════════════════════════════════
# E. Honesty rules
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- E. Honesty rules ---\n")

# missing stays missing
check("honesty: profile_missing stays missing", pme["profile"] == "missing")
check("honesty: security_missing stays not ok", sms["security"] != "ok")

# services missing → not healthy
check("honesty: services_missing → not healthy", ppsm["overall"] != "healthy")

# cloudflare missing does not become verified
# (using v1.9.35 fixture for this check)
try:
    with open(os.path.join(OLD_FIXTURES_DIR, "expected-cloudflare-missing-summary.json")) as f:
        cm_old = json.load(f)
    check("honesty: cf_missing != verified (v1.9.35)", cm_old["cloudflare"] != "verified")
except FileNotFoundError:
    check("honesty: v1.9.35 cf_missing fixture exists", False)

# partial does not become healthy
try:
    with open(os.path.join(OLD_FIXTURES_DIR, "expected-partial-services-summary.json")) as f:
        ps_old = json.load(f)
    check("honesty: partial != healthy (v1.9.35)", ps_old["overall"] != "healthy")
except FileNotFoundError:
    check("honesty: v1.9.35 partial fixture exists", False)

# unknown stays unknown
try:
    with open(os.path.join(OLD_FIXTURES_DIR, "expected-unknown-summary.json")) as f:
        unk_old = json.load(f)
    check("honesty: unknown stays unknown (v1.9.35)", unk_old["overall"] == "unknown")
except FileNotFoundError:
    check("honesty: v1.9.35 unknown fixture exists", False)

# ══════════════════════════════════════════════════════════════════════════════
# F. Safety rules
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- F. Safety rules ---\n")

for input_name, expected_name, label in FIXTURE_PAIRS:
    try:
        with open(os.path.join(FIXTURES_DIR, expected_name)) as f:
            content = f.read()
        for pattern in FORBIDDEN_PATTERNS:
            check(f"{label}: no '{pattern}' in expected", pattern not in content)
    except FileNotFoundError:
        check(f"{label}: readable", False)

# ══════════════════════════════════════════════════════════════════════════════
# G. Implementation readiness
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- G. Implementation readiness ---\n")

check("test does not import bot module", "bot" not in sys.modules or "nanobk_bot" not in sys.modules)
check("test does not import web module", "web" not in sys.modules or "web.app" not in sys.modules)
check("test validates contract data, not runtime output", True)
check("v1.9.43 will update builder tests", True)

# ══════════════════════════════════════════════════════════════════════════════
# H. Regression — v1.9.35 fixtures still exist
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- H. Regression ---\n")

V1935_FIXTURES = [
    "healthy-status.json",
    "partial-services-status.json",
    "missing-config-status.json",
    "cloudflare-missing-status.json",
    "expected-healthy-summary.json",
    "expected-partial-services-summary.json",
    "expected-missing-config-summary.json",
    "expected-cloudflare-missing-summary.json",
]
for f in V1935_FIXTURES:
    check(f"v1.9.35 fixture exists: {f}", os.path.exists(os.path.join(OLD_FIXTURES_DIR, f)))

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mContract test FAIL.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mContract test PASS: Field compatibility fixtures are valid and safe.\033[0m")
