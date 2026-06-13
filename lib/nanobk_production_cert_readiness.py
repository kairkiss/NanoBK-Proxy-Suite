#!/usr/bin/env python3
"""
NanoBK Production Certificate Readiness Flow (v2.5.4)

Read-only certificate/TLS readiness check that:
1. Reads local setup profile for domain
2. Plans proxy.example.com cert domain
3. Checks certbot availability
4. Checks existing cert/key file existence (never reads content)
5. Maps four-protocol TLS requirements
6. Generates deployment command plan (preview only)
7. Optionally saves local cert plan

Read-only. No certificate request. No certbot execution.
No VPS deployment. No service reload/restart.

Usage:
    python3 lib/nanobk_production_cert_readiness.py [--json]
    python3 lib/nanobk_production_cert_readiness.py --zone DOMAIN --domain proxy.example.com [--json]
    python3 lib/nanobk_production_cert_readiness.py --save --zone DOMAIN --domain proxy.example.com --mode self-signed [--json]

Test hooks:
    NANOBK_CERT_READINESS_FAKE_TOOLS=/path/to/tools.json
"""

import argparse
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_profile import load_profile


# -- Constants ----------------------------------------------------------------

VERSION = "2.5.4"
MODE = "production_cert_readiness_v2_5"
PLAN_FILE_NAME = "production-cert-plan.json"
WORKER_PLAN_FILE_NAME = "production-worker-plan.json"

DEFAULT_PROXY_SUBDOMAIN = "proxy"

_VALID_MODES = {"existing", "self-signed", "letsencrypt", "unknown"}

# Dangerous CLI args that must be rejected
_DANGEROUS_ARGS = {"--issue", "--yes", "--apply", "--certbot"}

# Exact cert confirmation phrase
EXACT_PHRASE_CERT = "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"


# -- Tool detection ------------------------------------------------------------

def _check_tool(name):
    """Check if a tool is available on PATH. Returns 'present', 'missing', or 'unknown'."""
    fake_tools_path = os.environ.get("NANOBK_CERT_READINESS_FAKE_TOOLS")
    if fake_tools_path and os.path.isfile(fake_tools_path):
        try:
            with open(fake_tools_path) as f:
                fake = json.load(f)
            if name in fake:
                return fake[name]
        except (json.JSONDecodeError, OSError):
            pass

    result = shutil.which(name)
    if result:
        return "present"
    return "missing"


# -- File existence check (safe, never reads content) --------------------------

def _check_file_exists(path):
    """Check if a file exists. Never reads its content."""
    if not path:
        return False
    return os.path.isfile(path)


# -- Domain resolution ---------------------------------------------------------

def _resolve_zone(cli_zone):
    """Resolve zone from CLI arg, profile, or saved worker plan."""
    if cli_zone:
        return cli_zone

    # Try setup profile
    profile, profile_err = load_profile()
    if not profile_err:
        zone = profile.get("zone_name", "")
        if zone:
            return zone

    # Try saved worker plan
    plan_path = os.path.join(os.path.expanduser("~"), ".nanobk", WORKER_PLAN_FILE_NAME)
    if os.path.isfile(plan_path):
        try:
            with open(plan_path) as f:
                saved = json.load(f)
            zone = saved.get("zone_name", "")
            if zone:
                return zone
        except (json.JSONDecodeError, OSError):
            pass

    return None


def _resolve_proxy_subdomain():
    """Resolve proxy subdomain from saved worker plan or default."""
    plan_path = os.path.join(os.path.expanduser("~"), ".nanobk", WORKER_PLAN_FILE_NAME)
    if os.path.isfile(plan_path):
        try:
            with open(plan_path) as f:
                saved = json.load(f)
            # Worker plan uses nanok_subdomain for the proxy entry
            # but for cert we want the proxy subdomain specifically
            # Default is "proxy" unless overridden
        except (json.JSONDecodeError, OSError):
            pass
    return DEFAULT_PROXY_SUBDOMAIN


# -- Readiness check ------------------------------------------------------------

def run_readiness(zone=None, cert_domain=None, cert_mode="unknown",
                  cert_file=None, key_file=None):
    """Run the full certificate readiness check. Returns result dict.

    Safe JSON only. Never includes:
    - private key content, CF_API_TOKEN, zone_id, api_env_path
    """
    # Step 1: Resolve zone
    zone_name = _resolve_zone(zone)

    if not zone_name:
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "mutation": False,
            "dangerous_actions_executed": False,
            "selected_domain": None,
            "cert_domain": None,
            "cert_mode": "unknown",
            "certificate": {},
            "tools": {},
            "protocol_tls": {},
            "commands": {"recommended": None, "cert_gate": None, "plan_only": None},
            "blocked": True,
            "next_step": "select_domain",
            "safety": "read_only",
            "profile_saved": False,
        }

    # Step 2: Resolve cert domain
    if not cert_domain:
        proxy_sub = _resolve_proxy_subdomain()
        cert_domain = f"{proxy_sub}.{zone_name}"

    # Step 3: Check tools
    certbot_status = _check_tool("certbot")

    # Step 4: Check certificate files
    cert_file_configured = bool(cert_file)
    key_file_configured = bool(key_file)
    cert_file_exists = _check_file_exists(cert_file) if cert_file else False
    key_file_exists = _check_file_exists(key_file) if key_file else False

    # Step 5: Determine blocked state and next_step
    blocked = False
    next_step = "review_vps_install"

    if cert_mode == "existing":
        if not cert_file_configured or not key_file_configured:
            blocked = True
            next_step = "configure_existing_cert"
        elif not cert_file_exists or not key_file_exists:
            blocked = True
            next_step = "configure_existing_cert"
    elif cert_mode == "letsencrypt":
        next_step = "review_cert_gate"
    elif cert_mode == "self-signed":
        next_step = "review_vps_install"
    else:
        # unknown mode — suggest choosing a mode
        next_step = "select_cert_mode"

    # Step 6: Build commands
    if cert_mode == "letsencrypt":
        recommended = "nanobk setup cert issue"
        cert_gate = f'nanobk setup cert issue --issue --confirm "{EXACT_PHRASE_CERT}"'
        plan_only = (
            f"bash installer/install-vps.sh --yes"
            f" --domain {cert_domain}"
            f" --cert-mode letsencrypt"
        )
    elif cert_mode == "existing":
        recommended = "nanobk install --mode vps"
        cert_gate = None
        plan_only = (
            f"bash installer/install-vps.sh --yes"
            f" --domain {cert_domain}"
            f" --cert-mode existing"
            f" --cert-file <configured>"
            f" --key-file <configured>"
        )
    elif cert_mode == "self-signed":
        recommended = "nanobk install --mode vps"
        cert_gate = None
        plan_only = (
            f"bash installer/install-vps.sh --yes"
            f" --domain {cert_domain}"
            f" --cert-mode self-signed"
        )
    else:
        recommended = None
        cert_gate = None
        plan_only = None

    # Step 7: Protocol TLS mapping
    protocol_tls = {
        "hy2": "uses_tls_cert",
        "tuic": "uses_tls_cert",
        "trojan": "uses_tls_cert",
        "reality": "uses_reality_servername",
    }

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "selected_domain": zone_name,
        "cert_domain": cert_domain,
        "cert_mode": cert_mode,
        "certificate": {
            "cert_file_configured": cert_file_configured,
            "key_file_configured": key_file_configured,
            "cert_file_exists": cert_file_exists,
            "key_file_exists": key_file_exists,
        },
        "tools": {
            "certbot": certbot_status,
        },
        "protocol_tls": protocol_tls,
        "commands": {
            "recommended": recommended,
            "cert_gate": cert_gate,
            "plan_only": plan_only,
        },
        "blocked": blocked,
        "next_step": next_step,
        "safety": "read_only",
        "profile_saved": False,
    }


# -- Save profile ---------------------------------------------------------------

def run_save(zone, cert_domain=None, cert_mode="unknown",
             cert_file=None, key_file=None):
    """Save local cert plan. Returns result dict.

    Only writes to local ~/.nanobk/production-cert-plan.json.
    Never writes private key content. Never writes to Cloudflare.
    """
    if not zone:
        return {"ok": False, "error": "zone is required", "mutation": False}

    if not cert_domain:
        proxy_sub = _resolve_proxy_subdomain()
        cert_domain = f"{proxy_sub}.{zone}"

    plan_dir = os.path.join(os.path.expanduser("~"), ".nanobk")
    plan_path = os.path.join(plan_dir, PLAN_FILE_NAME)

    plan = {
        "version": 1,
        "zone_name": zone,
        "cert_domain": cert_domain,
        "cert_mode": cert_mode,
        "cert_file_configured": bool(cert_file),
        "key_file_configured": bool(key_file),
        "created_by": "nanobk setup production cert --save",
    }

    try:
        os.makedirs(plan_dir, mode=0o700, exist_ok=True)
        with open(plan_path, "w") as f:
            json.dump(plan, f, indent=2, ensure_ascii=False)
        os.chmod(plan_path, 0o600)
    except OSError as e:
        return {"ok": False, "error": f"Failed to save plan: {e}", "mutation": False}

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "mutation": False,
        "zone_name": zone,
        "cert_domain": cert_domain,
        "cert_mode": cert_mode,
        "plan_path": plan_path,
        "profile_saved": True,
    }


# -- Text output ----------------------------------------------------------------

_MODE_LABELS = {
    "existing": "existing（使用已有证书）",
    "self-signed": "self-signed（自签名，测试用）",
    "letsencrypt": "letsencrypt（Let'\''s Encrypt 自动证书）",
    "unknown": "未选择",
}

_TLS_LABELS = {
    "uses_tls_cert": "需要 HTTPS 安全证书",
    "uses_reality_servername": "使用伪装域名，不一定使用此证书",
}


def output_text(result):
    """Print beginner-friendly certificate readiness summary in Chinese."""
    print()
    print("  NanoBK HTTPS 安全证书准备")
    print("  ─────────────────────────────────────────────")
    print()
    print("  当前不会申请证书，不会重启服务。")
    print()

    cert_domain = result.get("cert_domain")
    cert_mode = result.get("cert_mode", "unknown")

    if cert_domain:
        print("  准备用于：")
        print(f"    代理域名：{cert_domain}")
        print()

    mode_label = _MODE_LABELS.get(cert_mode, cert_mode)
    print(f"  证书模式：{mode_label}")
    print()

    # Protocol TLS mapping
    protocol_tls = result.get("protocol_tls", {})
    if protocol_tls:
        print("  四个代理通道：")
        for proto, tls_status in protocol_tls.items():
            label = _TLS_LABELS.get(tls_status, tls_status)
            print(f"    {proto.upper()}：{label}")
        print()

    # Certificate file status
    cert_info = result.get("certificate", {})
    if cert_mode == "existing":
        print("  证书文件：")
        if cert_info.get("cert_file_configured"):
            exists_label = "已找到" if cert_info.get("cert_file_exists") else "未找到"
            print(f"    证书文件：{exists_label}")
        else:
            print("    证书文件：未配置")
        if cert_info.get("key_file_configured"):
            exists_label = "已找到" if cert_info.get("key_file_exists") else "未找到"
            print(f"    密钥文件：{exists_label}")
        else:
            print("    密钥文件：未配置")
        print()

    # Tools
    tools = result.get("tools", {})
    if cert_mode == "letsencrypt" and tools.get("certbot"):
        label = "已安装" if tools["certbot"] == "present" else "未安装"
        print(f"  certbot：{label}")
        print()

    # Commands
    commands = result.get("commands", {})
    if commands.get("recommended"):
        print("  推荐下一步：")
        print(f"    {commands['recommended']}")
        if commands.get("cert_gate"):
            print(f"    或：{commands['cert_gate']}")
        print()

    # Blocked state
    blocked = result.get("blocked", False)
    next_step = result.get("next_step", "")

    if blocked:
        print("  状态：需要先完成前置准备")
        if next_step == "select_domain":
            print("  请先选择域名：nanobk setup production dns --zone your-domain.com")
        elif next_step == "configure_existing_cert":
            print("  请先配置证书文件路径")
        elif next_step == "select_cert_mode":
            print("  请选择证书模式：--mode existing|self-signed|letsencrypt")
    else:
        print("  状态：准备就绪（预览模式，不会自动申请证书）")

    print()
    print("  安全说明：")
    print("    这一步只生成计划，不会申请证书。")
    print("    真正申请证书需要进入 cert gate。")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {
            "ok": False,
            "error": message,
            "mode": MODE,
            "version": VERSION,
            "mutation": False,
        }
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(f"  错误：{message}", file=sys.stderr)


# -- CLI -------------------------------------------------------------------------

def main():
    # Check for dangerous args before argparse
    use_json = "--json" in sys.argv
    for arg in sys.argv[1:]:
        if arg in _DANGEROUS_ARGS:
            msg = f"选项 {arg} 不支持。此命令仅用于预览，不会申请证书。"
            output_error(msg, use_json)
            sys.exit(1)

    parser = argparse.ArgumentParser(
        description="NanoBK Production Certificate Readiness Flow"
    )
    parser.add_argument("--zone", help="Domain zone to use")
    parser.add_argument("--domain", help="Full cert domain (e.g. proxy.example.com)")
    parser.add_argument("--mode", choices=["existing", "self-signed", "letsencrypt"],
                        default="unknown", help="Certificate mode")
    parser.add_argument("--cert-file", help="Path to existing certificate file")
    parser.add_argument("--key-file", help="Path to existing private key file")
    parser.add_argument("--save", action="store_true", help="Save local cert plan")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.save:
        result = run_save(
            zone=args.zone,
            cert_domain=args.domain,
            cert_mode=args.mode,
            cert_file=args.cert_file,
            key_file=args.key_file,
        )
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            if result.get("ok"):
                print()
                print("  已保存证书计划。")
                print(f"  域名：{result.get('zone_name', '***')}")
                print(f"  证书域名：{result.get('cert_domain', '***')}")
                print(f"  模式：{result.get('cert_mode', '***')}")
                print()
            else:
                output_error(result.get("error", "unknown error"), False)
                sys.exit(1)
    else:
        result = run_readiness(
            zone=args.zone,
            cert_domain=args.domain,
            cert_mode=args.mode,
            cert_file=args.cert_file,
            key_file=args.key_file,
        )
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            if result.get("ok"):
                output_text(result)
            else:
                output_error(result.get("error", "unknown error"), False)
                sys.exit(1)


if __name__ == "__main__":
    main()
