"""
NanoBK Proxy Suite — Protocol Link Export Helper

Reads a NanoBK profile JSON and builds protocol subscription links.
Used by `nanobk export link` and `nanobk export links`.

Protocol URI formats (v2.0.1):
  HY2:     hysteria2://PASSWORD@SERVER:PORT?sni=SNI#NAME
  TUIC:    tuic://UUID:PASSWORD@SERVER:PORT?sni=SNI&congestion_control=bbr&udp_relay_mode=native#NAME
  Reality: vless://UUID@SERVER:PORT?encryption=none&security=reality&sni=SERVERNAME&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp#NAME
  Trojan:  trojan://PASSWORD@SERVER:PORT?security=tls&sni=SNI&type=tcp#NAME

Usage:
    python3 lib/nanobk_export_links.py --profile /path/to/profile.json --protocol hy2
    python3 lib/nanobk_export_links.py --profile /path/to/profile.json --protocol all
    python3 lib/nanobk_export_links.py --profile /path/to/profile.json --protocol all --json
"""

from __future__ import annotations

import argparse
import json
import sys
from urllib.parse import quote


SUPPORTED_PROTOCOLS = ("hy2", "tuic", "reality", "trojan")


def _quote(value: str) -> str:
    """Percent-encode a value for use in URI components."""
    return quote(value, safe="")


def _build_hy2_link(profile: dict) -> str:
    """Build hysteria2:// link from HY2 profile section."""
    password = _quote(profile["password"])
    server = _quote(profile["server"])
    port = profile["port"]
    sni = _quote(profile.get("sni", ""))
    name = _quote(profile.get("name", "HY2"))
    return f"hysteria2://{password}@{server}:{port}?sni={sni}#{name}"


def _build_tuic_link(profile: dict) -> str:
    """Build tuic:// link from TUIC profile section."""
    uuid = _quote(profile["uuid"])
    password = _quote(profile["password"])
    server = _quote(profile["server"])
    port = profile["port"]
    sni = _quote(profile.get("sni", ""))
    name = _quote(profile.get("name", "TUIC"))
    return (
        f"tuic://{uuid}:{password}@{server}:{port}"
        f"?sni={sni}&congestion_control=bbr&udp_relay_mode=native"
        f"#{name}"
    )


def _build_reality_link(profile: dict) -> str:
    """Build vless:// (Reality) link from Reality profile section."""
    uuid = _quote(profile["uuid"])
    server = _quote(profile["server"])
    port = profile["port"]
    servername = _quote(profile.get("servername", ""))
    public_key = _quote(profile.get("publicKey", ""))
    short_id = _quote(profile.get("shortId", ""))
    name = _quote(profile.get("name", "Reality"))
    return (
        f"vless://{uuid}@{server}:{port}"
        f"?encryption=none&security=reality"
        f"&sni={servername}&fp=chrome&pbk={public_key}&sid={short_id}"
        f"&type=tcp"
        f"#{name}"
    )


def _build_trojan_link(profile: dict) -> str:
    """Build trojan:// link from Trojan profile section."""
    password = _quote(profile["password"])
    server = _quote(profile["server"])
    port = profile["port"]
    sni = _quote(profile.get("sni", ""))
    name = _quote(profile.get("name", "Trojan"))
    return (
        f"trojan://{password}@{server}:{port}"
        f"?security=tls&sni={sni}&type=tcp"
        f"#{name}"
    )


_BUILDERS = {
    "hy2": _build_hy2_link,
    "tuic": _build_tuic_link,
    "reality": _build_reality_link,
    "trojan": _build_trojan_link,
}


def build_link(protocol: str, profile_data: dict) -> str:
    """Build a single protocol link from profile data.

    Returns the link string, or empty string if the protocol section is missing.
    """
    section = profile_data.get(protocol)
    if not section:
        return ""
    return _BUILDERS[protocol](section)


def build_all_links(profile_data: dict) -> dict[str, str]:
    """Build links for all available protocols.

    Returns a dict of {protocol: link} for protocols present in the profile.
    """
    links = {}
    for protocol in SUPPORTED_PROTOCOLS:
        link = build_link(protocol, profile_data)
        if link:
            links[protocol] = link
    return links


def load_profile(path: str) -> dict:
    """Load and parse a profile JSON file.

    Exits with error message on failure.
    """
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"错误: 配置文件不存在: {path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"错误: 配置文件 JSON 解析失败: {e}", file=sys.stderr)
        sys.exit(1)
    except PermissionError:
        print(f"错误: 无法读取配置文件: {path}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="NanoBK protocol link exporter"
    )
    parser.add_argument(
        "--profile",
        required=True,
        help="Path to profile JSON file"
    )
    parser.add_argument(
        "--protocol",
        required=True,
        help="Protocol to export (hy2, tuic, reality, trojan, all)"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Output as JSON"
    )
    args = parser.parse_args()

    profile_data = load_profile(args.profile)
    protocol = args.protocol.lower()

    if protocol == "all":
        links = build_all_links(profile_data)
        if not links:
            print("错误: 配置文件中没有找到任何协议配置", file=sys.stderr)
            sys.exit(1)
        if args.json_output:
            print(json.dumps(links, indent=2))
        else:
            for proto, link in links.items():
                print(f"{proto}: {link}")
    elif protocol in SUPPORTED_PROTOCOLS:
        link = build_link(protocol, profile_data)
        if not link:
            print(
                f"错误: 配置文件中没有 {protocol} 协议配置",
                file=sys.stderr,
            )
            sys.exit(1)
        if args.json_output:
            print(json.dumps({protocol: link}, indent=2))
        else:
            print(link)
    else:
        print(
            f"错误: 不支持的协议: {protocol}。"
            f"支持的协议: {', '.join(SUPPORTED_PROTOCOLS)}",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
