"""
NanoBK Proxy Suite — Shared Redaction Helper (v1.9.6)

Production-oriented redaction module for Bot/Web control planes.
Covers token/secret/password/private-key patterns AND address-class
sensitive data (IPv4, IPv6, domain, URL, workers.dev, subscription path).

This module is NOT yet wired into Bot/Web runtime.
Future integration will be staged: Bot first, then Web.

Usage:
    from lib.nanobk_redaction import redact_text, redact_json_obj, redact_json_text

Design reference: docs/design-v1.9.6-shared-redaction-helper.md
Contract reference: docs/audit-v1.9.5-redaction-layer-address-class.md
"""

from __future__ import annotations

import json
import re

# ── ANSI stripping ──────────────────────────────────────────────────────────

_ANSI_RE = re.compile(r'\x1b\[[0-9;?]*[ -/]*[@-~]')


def strip_ansi(text: str) -> str:
    """Remove ANSI escape codes (color, cursor, etc.)."""
    return _ANSI_RE.sub('', text)


# ── Replacement tokens ──────────────────────────────────────────────────────

REDACTED_IPV4 = "[REDACTED_IPV4]"
REDACTED_IPV6 = "[REDACTED_IPV6]"
REDACTED_DOMAIN = "[REDACTED_DOMAIN]"
REDACTED_URL = "[REDACTED_URL]"
REDACTED_WORKERS_DEV = "[REDACTED_WORKERS_DEV]"
REDACTED_SUBSCRIPTION_PATH = "[REDACTED_SUBSCRIPTION_PATH]"
REDACTED_ROUTE_URL = "[REDACTED_ROUTE_URL]"
REDACTED_TOKEN = "[REDACTED_TOKEN]"
REDACTED_SECRET = "[REDACTED_SECRET]"
REDACTED_PRIVATE_KEY = "[REDACTED_PRIVATE_KEY]"
REDACTED_B64 = "[REDACTED_B64]"
REDACTED = "[REDACTED]"

# ── Text redaction patterns ─────────────────────────────────────────────────
# ORDER MATTERS: more specific patterns before less specific ones.
#
# 1. URLs before domains (URLs contain domains)
# 2. workers.dev before generic domains
# 3. subscription paths before generic paths
# 4. IPv6 before IPv4
# 5. key=value secrets before generic long strings


def _build_text_patterns() -> list[tuple[re.Pattern, str | type]]:
    """Build ordered list of (pattern, replacement) for text redaction."""
    patterns: list[tuple[re.Pattern, str | type]] = []

    # 1. Full URLs (must come before domain matching)
    patterns.append((
        re.compile(r'https?://\S+'),
        REDACTED_URL,
    ))

    # 2. workers.dev-like hostnames (before generic domains)
    #    Matches full hostnames ending in .workers.dev
    patterns.append((
        re.compile(r'[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?\.workers\.dev'),
        REDACTED_WORKERS_DEV,
    ))

    # 3. Subscription paths like /sub/abc123
    patterns.append((
        re.compile(r'/sub/[a-zA-Z0-9_-]+'),
        REDACTED_SUBSCRIPTION_PATH,
    ))

    # 4. IPv6 addresses
    #    Full form: 8 groups of 4 hex digits separated by colons
    patterns.append((
        re.compile(r'(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}'),
        REDACTED_IPV6,
    ))
    #    Compressed form: hex:hex::... (e.g. 2001:db8::10)
    patterns.append((
        re.compile(r'[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4}){0,6}::'
                   r'(?:[0-9a-fA-F]{1,4}(?::[0-9a-fA-F]{1,4}){0,6})?'),
        REDACTED_IPV6,
    ))

    # 5. IPv4 addresses
    patterns.append((
        re.compile(r'(?:\d{1,3}\.){3}\d{1,3}'),
        REDACTED_IPV4,
    ))

    # 6. Domain-like hostnames
    #    Uses callable replacement to exclude file extensions from TLD matching.
    _domain_re = re.compile(
        r'[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.'
        r'(?:example\.invalid|example\.com|'
        r'invalid|local|localhost|'
        r'[a-zA-Z]{2,}(?:\.[a-zA-Z]{2,})*)'
    )
    patterns.append((_domain_re, _redact_domain_match))

    # 7. Telegram bot token format: 123456:ABC-DEF...
    patterns.append((
        re.compile(r'\b\d{6,}:[A-Za-z0-9_-]{20,}\b'),
        REDACTED_TOKEN,
    ))

    # 8. Key=value / key:value secrets (case insensitive)
    patterns.append((
        re.compile(
            r'(?i)(token|secret|password|private[_ -]?key|'
            r'admin[_ -]?token|api[_ -]?token)\s*[:=]\s*\S+'
        ),
        lambda m: f'{m.group(1)}=[REDACTED]',
    ))

    # 9. Long base64/hex strings (potential secrets, ≥40 chars)
    patterns.append((
        re.compile(r'[A-Za-z0-9+/]{40,}={0,2}'),
        REDACTED_B64,
    ))

    return patterns


# File extensions that should NOT be treated as domain TLDs.
_FILE_EXTENSIONS: frozenset[str] = frozenset({
    'json', 'js', 'css', 'html', 'py', 'sh', 'env', 'txt',
    'yml', 'yaml', 'toml', 'xml', 'conf', 'cfg', 'log',
    'bak', 'tmp', 'old', 'new', 'orig', 'so', 'dll', 'exe',
    'bin', 'dat', 'db', 'sqlite', 'lock', 'pid', 'sock',
    'gz', 'tar', 'zip', 'bz2', 'xz', '7z', 'rar',
    'md', 'rst', 'tex', 'pdf', 'doc', 'docx', 'xls', 'xlsx',
    'ppt', 'pptx', 'csv', 'rtf', 'odt', 'ods', 'odp',
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico',
    'mp3', 'mp4', 'avi', 'mov', 'wav', 'flac',
})


def _redact_domain_match(m: re.Match) -> str:
    """Redact domain match only if TLD is not a file extension."""
    match = m.group()
    tld = match.rsplit('.', 1)[-1].lower()
    if tld in _FILE_EXTENSIONS:
        return match  # preserve file paths
    # Preserve bare workers.dev labels (handled by workers.dev pattern)
    if match == 'workers.dev':
        return match
    return REDACTED_DOMAIN


_TEXT_PATTERNS = _build_text_patterns()


def redact_text(text: str) -> str:
    """Redact all sensitive patterns from text.

    Covers: URLs, IPv4, IPv6, domains, workers.dev, subscription paths,
    token/secret/password/key-value pairs, long random strings.

    Ordering is important: more specific patterns are applied first to avoid
    partial matches by less specific patterns.
    """
    text = strip_ansi(text)
    for pattern, replacement in _TEXT_PATTERNS:
        if callable(replacement):
            text = pattern.sub(replacement, text)
        else:
            text = pattern.sub(replacement, text)
    return text


# ── Sensitive JSON key definitions ───────────────────────────────────────────
# Keys whose STRING values should be replaced with [REDACTED].
# Matching is done on normalized form (lowercase, no underscores/dashes).

_SENSITIVE_KEY_SUBSTRINGS: tuple[str, ...] = (
    "token",        # catches token, adminToken, apiToken, botToken
    "password",     # catches password
    "secret",       # catches secret (but NOT secretsMode — see _EXEMPT_KEYS)
    "private",      # catches privateKey, private_key, realityPrivateKey
    "privatekey",
)

# Keys that should NOT be redacted even though they match a substring.
# Compared in normalized form (lowercase, no underscores/dashes).
_EXEMPT_KEYS: frozenset[str] = frozenset({
    "secretsmode",    # security.secretsMode is a mode string, not a secret
    "currentpath",    # profile.currentPath is a file path, not a secret
})


def _is_sensitive_key(key: str) -> bool:
    """Check if a JSON key name indicates a sensitive value."""
    normalized = key.lower().replace("_", "").replace("-", "")
    if normalized in _EXEMPT_KEYS:
        return False
    return any(s in normalized for s in _SENSITIVE_KEY_SUBSTRINGS)


def redact_json_obj(obj: object) -> object:
    """Recursively redact sensitive values from a JSON-like object.

    - Preserves booleans, numbers, and non-sensitive state values.
    - Replaces sensitive key values with [REDACTED].
    - Applies address-class redaction to string values even for non-sensitive keys.
    - Keeps output JSON-serializable.
    """
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if _is_sensitive_key(k):
                # Replace string values for sensitive keys
                if isinstance(v, str):
                    out[k] = REDACTED
                else:
                    # For non-string sensitive values (rare), keep as-is
                    out[k] = v
            else:
                out[k] = redact_json_obj(v)
        return out
    if isinstance(obj, list):
        return [redact_json_obj(item) for item in obj]
    if isinstance(obj, str):
        return redact_text(obj)
    # booleans, numbers, None pass through unchanged
    return obj


def redact_json_text(text: str) -> str:
    """Parse JSON text, redact it, and return redacted JSON string.

    Falls back to redact_text() if input is not valid JSON.
    Returns JSON with sorted keys for deterministic output.
    """
    try:
        data = json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return redact_text(text)

    redacted = redact_json_obj(data)
    return json.dumps(redacted, indent=2, sort_keys=True, ensure_ascii=False)
