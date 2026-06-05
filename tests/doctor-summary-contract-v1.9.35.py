#!/usr/bin/env python3
"""
Test: Doctor Summary Contract / Fixture Tests (v1.9.35)

Validates fixture contract only. No runtime implementation.
No Bot/Web runtime. No real doctor. No real env. No shell execution.

Usage:
    python3 tests/doctor-summary-contract-v1.9.35.py
"""

import json
import os
import sys

FIXTURES_DIR = os.path.join(os.path.dirname(__file__), "fixtures", "doctor-summary-v1.9.35")

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
]

# ── Input fixtures ────────────────────────────────────────────────────────────

INPUT_FIXTURES = [
    "healthy-status.json",
    "partial-services-status.json",
    "missing-config-status.json",
    "cloudflare-missing-status.json",
    "failure-doctor-output.txt",
    "secret-containing-doctor-output.txt",
    "unknown-invalid-output.txt",
]

EXPECTED_FIXTURES = [
    "expected-healthy-summary.json",
    "expected-partial-services-summary.json",
    "expected-missing-config-summary.json",
    "expected-cloudflare-missing-summary.json",
    "expected-failure-summary.json",
    "expected-secret-redacted-summary.json",
    "expected-unknown-summary.json",
]

print("=== Doctor Summary Contract Test (v1.9.35) ===\n")

# ══════════════════════════════════════════════════════════════════════════════
# 1. Fixture existence
# ══════════════════════════════════════════════════════════════════════════════

print("--- Fixture existence ---\n")

for f in INPUT_FIXTURES + EXPECTED_FIXTURES:
    path = os.path.join(FIXTURES_DIR, f)
    check(f"Fixture exists: {f}", os.path.exists(path))

# ══════════════════════════════════════════════════════════════════════════════
# 2. JSON fixture validity
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- JSON fixture validity ---\n")

json_inputs = [f for f in INPUT_FIXTURES if f.endswith(".json")]
for f in json_inputs:
    path = os.path.join(FIXTURES_DIR, f)
    try:
        with open(path) as fh:
            data = json.load(fh)
        check(f"JSON valid: {f}", isinstance(data, dict))
    except (json.JSONDecodeError, FileNotFoundError) as e:
        check(f"JSON valid: {f}", False)

for f in EXPECTED_FIXTURES:
    path = os.path.join(FIXTURES_DIR, f)
    try:
        with open(path) as fh:
            data = json.load(fh)
        check(f"JSON valid: {f}", isinstance(data, dict))
    except (json.JSONDecodeError, FileNotFoundError) as e:
        check(f"JSON valid: {f}", False)

# ══════════════════════════════════════════════════════════════════════════════
# 3. Expected summary schema validation
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Expected summary schema ---\n")

REQUIRED_TOP_KEYS = {"overall", "control_plane", "cli", "profile", "config",
                     "services", "cloudflare", "subscription", "security",
                     "doctor", "next_step", "display_policy"}
REQUIRED_SERVICE_KEYS = SERVICE_NAMES
REQUIRED_DOCTOR_KEYS = {"errors", "warnings", "full_available"}
REQUIRED_DISPLAY_POLICY_KEYS = {"beginner_safe", "full_output_advanced_only", "redaction_required"}

def validate_summary_schema(data: dict, label: str) -> bool:
    """Validate summary has all required keys and allowed values."""
    ok = True

    # Top-level keys
    for key in REQUIRED_TOP_KEYS:
        if key not in data:
            check(f"{label}: has key '{key}'", False)
            ok = False

    if not ok:
        return False

    # Overall
    check(f"{label}: overall in allowed set", data["overall"] in ALLOWED_OVERALL)
    if data["overall"] not in ALLOWED_OVERALL:
        ok = False

    # Control plane
    check(f"{label}: control_plane in allowed set", data["control_plane"] in ALLOWED_CONTROL_PLANE)
    if data["control_plane"] not in ALLOWED_CONTROL_PLANE:
        ok = False

    # CLI
    check(f"{label}: cli in allowed set", data["cli"] in ALLOWED_CLI)
    if data["cli"] not in ALLOWED_CLI:
        ok = False

    # Profile
    check(f"{label}: profile in allowed set", data["profile"] in ALLOWED_PROFILE)
    if data["profile"] not in ALLOWED_PROFILE:
        ok = False

    # Config
    check(f"{label}: config in allowed set", data["config"] in ALLOWED_CONFIG)
    if data["config"] not in ALLOWED_CONFIG:
        ok = False

    # Services
    if isinstance(data.get("services"), dict):
        for svc in SERVICE_NAMES:
            val = data["services"].get(svc)
            check(f"{label}: services.{svc} in allowed set", val in ALLOWED_SERVICE)
            if val not in ALLOWED_SERVICE:
                ok = False
    else:
        check(f"{label}: services is dict", False)
        ok = False

    # Cloudflare
    check(f"{label}: cloudflare in allowed set", data["cloudflare"] in ALLOWED_CLOUDFLARE)
    if data["cloudflare"] not in ALLOWED_CLOUDFLARE:
        ok = False

    # Subscription
    check(f"{label}: subscription in allowed set", data["subscription"] in ALLOWED_SUBSCRIPTION)
    if data["subscription"] not in ALLOWED_SUBSCRIPTION:
        ok = False

    # Security
    check(f"{label}: security in allowed set", data["security"] in ALLOWED_SECURITY)
    if data["security"] not in ALLOWED_SECURITY:
        ok = False

    # Doctor
    if isinstance(data.get("doctor"), dict):
        for key in REQUIRED_DOCTOR_KEYS:
            check(f"{label}: doctor has key '{key}'", key in data["doctor"])
    else:
        check(f"{label}: doctor is dict", False)
        ok = False

    # Next step
    check(f"{label}: next_step in allowed set", data["next_step"] in ALLOWED_NEXT_STEP)
    if data["next_step"] not in ALLOWED_NEXT_STEP:
        ok = False

    # Display policy
    if isinstance(data.get("display_policy"), dict):
        for key in REQUIRED_DISPLAY_POLICY_KEYS:
            check(f"{label}: display_policy has key '{key}'", key in data["display_policy"])
        check(f"{label}: display_policy.beginner_safe == True", data["display_policy"].get("beginner_safe") is True)
        check(f"{label}: display_policy.full_output_advanced_only == True", data["display_policy"].get("full_output_advanced_only") is True)
        check(f"{label}: display_policy.redaction_required == True", data["display_policy"].get("redaction_required") is True)
    else:
        check(f"{label}: display_policy is dict", False)
        ok = False

    return ok


for f in EXPECTED_FIXTURES:
    path = os.path.join(FIXTURES_DIR, f)
    try:
        with open(path) as fh:
            data = json.load(fh)
        validate_summary_schema(data, f)
    except Exception:
        check(f"{f}: schema validation", False)

# ══════════════════════════════════════════════════════════════════════════════
# 4. Forbidden pattern scan in expected summaries
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Forbidden pattern scan ---\n")

for f in EXPECTED_FIXTURES:
    path = os.path.join(FIXTURES_DIR, f)
    try:
        with open(path) as fh:
            content = fh.read()
        for pattern in FORBIDDEN_PATTERNS:
            check(f"{f}: no '{pattern}'", pattern not in content)
    except FileNotFoundError:
        check(f"{f}: readable", False)

# ══════════════════════════════════════════════════════════════════════════════
# 5. Honesty rules
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Honesty rules ---\n")

# Unknown stays unknown
path = os.path.join(FIXTURES_DIR, "expected-unknown-summary.json")
with open(path) as fh:
    unk = json.load(fh)
check("Unknown: overall == unknown", unk["overall"] == "unknown")
check("Unknown: control_plane == unknown", unk["control_plane"] == "unknown")
check("Unknown: cli == unknown", unk["cli"] == "unknown")
check("Unknown: profile == unknown", unk["profile"] == "unknown")
check("Unknown: config == unknown", unk["config"] == "unknown")
check("Unknown: all services == unknown", all(v == "unknown" for v in unk["services"].values()))
check("Unknown: cloudflare == unknown", unk["cloudflare"] == "unknown")
check("Unknown: subscription == unknown", unk["subscription"] == "unknown")
check("Unknown: security == unknown", unk["security"] == "unknown")
check("Unknown: next_step == unknown", unk["next_step"] == "unknown")
check("Unknown: full_available == False", unk["doctor"]["full_available"] is False)

# Missing config does not produce healthy
path = os.path.join(FIXTURES_DIR, "expected-missing-config-summary.json")
with open(path) as fh:
    mc = json.load(fh)
check("Missing config: overall != healthy", mc["overall"] != "healthy")
check("Missing config: config == missing", mc["config"] == "missing")
check("Missing config: profile == missing", mc["profile"] == "missing")

# Partial services produce partial
path = os.path.join(FIXTURES_DIR, "expected-partial-services-summary.json")
with open(path) as fh:
    ps = json.load(fh)
check("Partial services: overall == partial", ps["overall"] == "partial")
check("Partial services: tuic == inactive", ps["services"]["tuic"] == "inactive")
check("Partial services: trojan == inactive", ps["services"]["trojan"] == "inactive")

# Cloudflare missing does not produce verified
path = os.path.join(FIXTURES_DIR, "expected-cloudflare-missing-summary.json")
with open(path) as fh:
    cm = json.load(fh)
check("CF missing: overall != healthy", cm["overall"] != "healthy")
check("CF missing: cloudflare == missing", cm["cloudflare"] == "missing")
check("CF missing: cloudflare != verified", cm["cloudflare"] != "verified")

# Failed doctor output produces failed
path = os.path.join(FIXTURES_DIR, "expected-failure-summary.json")
with open(path) as fh:
    fl = json.load(fh)
check("Failure: overall == failed", fl["overall"] == "failed")
check("Failure: errors > 0", fl["doctor"]["errors"] > 0)
check("Failure: next_step == check_failed_services", fl["next_step"] == "check_failed_services")

# Secret-containing output expected summary is safe
path = os.path.join(FIXTURES_DIR, "expected-secret-redacted-summary.json")
with open(path) as fh:
    sr = json.load(fh)
content = open(path).read()
for pattern in FORBIDDEN_PATTERNS:
    check(f"Secret redacted: no '{pattern}' in summary", pattern not in content)

# Full diagnostic text does not appear in expected summary
for f in EXPECTED_FIXTURES:
    path = os.path.join(FIXTURES_DIR, f)
    content = open(path).read()
    check(f"{f}: no 'System Info' in summary", "System Info" not in content)
    check(f"{f}: no 'Required Tools' in summary", "Required Tools" not in content)
    check(f"{f}: no 'Port Listening' in summary", "Port Listening" not in content)

# ══════════════════════════════════════════════════════════════════════════════
# 6. Input fixtures may contain secrets (for redaction testing)
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Input fixtures contain test secrets (expected) ---\n")

path = os.path.join(FIXTURES_DIR, "secret-containing-doctor-output.txt")
content = open(path).read()
check("Secret input: contains TEST_TOKEN (for redaction test)", "TEST_TOKEN" in content)
check("Secret input: contains TEST_SECRET (for redaction test)", "TEST_SECRET" in content)
check("Secret input: contains TEST_PRIVATE_KEY (for redaction test)", "TEST_PRIVATE_KEY" in content)
check("Secret input: contains example.invalid (for redaction test)", "example.invalid" in content)

# ══════════════════════════════════════════════════════════════════════════════
# 7. No runtime execution
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- No runtime execution ---\n")

# Verify test does not import Bot/Web runtime
check("No Bot runtime import", "nanobk_bot" not in sys.modules)
check("No Web runtime import", "web.app" not in sys.modules)

# Verify no dangerous imports in test
check("No subprocess import in test", "subprocess" not in sys.modules)
check("No shlex import in test", "shlex" not in sys.modules)
check("No shutil import in test", "shutil" not in sys.modules)

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mContract test FAIL.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mContract test PASS: Doctor Summary fixtures are valid and safe.\033[0m")
