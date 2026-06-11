#!/usr/bin/env python3
"""
NanoBK Saved DNS Setup Profile

Manages a local setup profile for the beginner DNS setup assistant.
Saves zone, api-env path, and nodes so the user doesn't have to re-enter them.

Usage:
    python3 lib/nanobk_setup_profile.py save --zone DOMAIN --api-env PATH [--nodes proxy,web] [--json]
    python3 lib/nanobk_setup_profile.py show [--json]
    python3 lib/nanobk_setup_profile.py clear [--json]

Profile location: ~/.nanobk/setup-profile.json
"""

import argparse
import json
import os
import stat
import sys


# ── Constants ───────────────────────────────────────────────────────────────

_PROFILE_DIR_NAME = ".nanobk"
_PROFILE_FILE_NAME = "setup-profile.json"
_PROFILE_VERSION = 1


# ── Path helpers ────────────────────────────────────────────────────────────

def default_profile_dir():
    """Return the default profile directory path."""
    return os.path.join(os.path.expanduser("~"), _PROFILE_DIR_NAME)


def default_profile_path():
    """Return the default profile file path."""
    return os.path.join(default_profile_dir(), _PROFILE_FILE_NAME)


# ── Directory helpers ───────────────────────────────────────────────────────

def ensure_profile_dir():
    """Ensure the profile directory exists with correct permissions."""
    profile_dir = default_profile_dir()
    if not os.path.isdir(profile_dir):
        os.makedirs(profile_dir, mode=0o700, exist_ok=True)
        # Ensure permissions even if umask interfered
        try:
            os.chmod(profile_dir, 0o700)
        except OSError:
            pass
    return profile_dir


# ── Profile operations ──────────────────────────────────────────────────────

def save_profile(zone, api_env_path, nodes):
    """Save a setup profile. Returns result dict."""
    if not zone:
        return {"ok": False, "error": "zone is required"}
    if not api_env_path:
        return {"ok": False, "error": "api-env path is required"}

    ensure_profile_dir()
    profile_path = default_profile_path()

    profile = {
        "version": 1,
        "zone_name": zone,
        "api_env_path": api_env_path,
        "nodes": nodes if isinstance(nodes, list) else [n.strip() for n in nodes.split(",")],
        "created_by": "nanobk setup profile save",
    }

    try:
        with open(profile_path, "w", encoding="utf-8") as f:
            json.dump(profile, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.chmod(profile_path, 0o600)
    except OSError as e:
        return {"ok": False, "error": "failed to write profile"}

    return {
        "ok": True,
        "status": "saved",
        "zone_name": zone,
        "nodes": profile["nodes"],
        "api_env_configured": True,
        "api_env_path_printed": False,
        "profile_path_printed": False,
    }


def load_profile():
    """Load the saved profile. Returns (profile_dict, error_string)."""
    profile_path = default_profile_path()

    if not os.path.isfile(profile_path):
        return None, "no profile found"

    # Check permissions
    try:
        st = os.stat(profile_path)
        mode = stat.S_IMODE(st.st_mode)
        if mode & 0o077:
            return None, "insecure profile permissions (expected 0600)"
    except OSError:
        return None, "cannot read profile permissions"

    try:
        with open(profile_path, "r", encoding="utf-8") as f:
            profile = json.load(f)
    except (json.JSONDecodeError, OSError):
        return None, "malformed profile (invalid JSON)"

    if not isinstance(profile, dict):
        return None, "malformed profile (not a JSON object)"

    return profile, None


def clear_profile():
    """Clear the saved profile. Returns result dict."""
    profile_path = default_profile_path()

    if not os.path.isfile(profile_path):
        return {"ok": True, "status": "already_cleared", "message": "no profile found"}

    try:
        os.remove(profile_path)
    except OSError:
        return {"ok": False, "error": "failed to delete profile"}

    return {"ok": True, "status": "cleared"}


def redacted_profile_summary():
    """Return a redacted summary of the saved profile. Returns result dict."""
    profile, err = load_profile()
    if err:
        return {"ok": False, "error": err}

    return {
        "ok": True,
        "zone_name": profile.get("zone_name", ""),
        "nodes": profile.get("nodes", []),
        "api_env_configured": bool(profile.get("api_env_path")),
        "api_env_path_printed": False,
        "profile_path_printed": False,
    }


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable result."""
    status = result.get("status", "")

    if status == "saved":
        print()
        print("  Setup profile saved.")
        print("  Zone: {}".format(result.get("zone_name", "***")))
        print("  Nodes: {}".format(", ".join(result.get("nodes", []))))
        print("  API env: configured")
        print("  Profile path: configured")
        print()

    elif status == "cleared":
        print()
        print("  Setup profile cleared.")
        print()

    elif status == "already_cleared":
        print()
        print("  No setup profile found. Already cleared.")
        print()

    elif result.get("ok") and "zone_name" in result and "api_env_configured" in result:
        # show profile
        print()
        print("  NanoBK setup profile")
        print("  Zone: {}".format(result.get("zone_name", "***")))
        print("  Nodes: {}".format(", ".join(result.get("nodes", []))))
        print("  API env: {}".format("configured" if result.get("api_env_configured") else "not configured"))
        print("  Profile path: configured")
        print()

    else:
        error = result.get("error", "unknown error")
        print("  Error: {}".format(error), file=sys.stderr)


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        print(json.dumps({"ok": False, "error": message}, indent=2))
    else:
        print("  Error: {}".format(message), file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Saved DNS Setup Profile"
    )
    sub = parser.add_subparsers(dest="command")

    # save
    save_parser = sub.add_parser("save", help="Save setup profile")
    save_parser.add_argument("--zone", help="Domain zone")
    save_parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    save_parser.add_argument("--nodes", default="proxy,web", help="Comma-separated node labels")
    save_parser.add_argument("--json", action="store_true", help="JSON output")

    # show
    show_parser = sub.add_parser("show", help="Show saved profile")
    show_parser.add_argument("--json", action="store_true", help="JSON output")

    # clear
    clear_parser = sub.add_parser("clear", help="Clear saved profile")
    clear_parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.command == "save":
        if not args.zone:
            output_error("zone is required", args.json)
            sys.exit(1)
        if not args.api_env:
            output_error("api-env is required", args.json)
            sys.exit(1)

        nodes = [n.strip() for n in args.nodes.split(",") if n.strip()]
        result = save_profile(args.zone, args.api_env, nodes)

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            output_text(result)

        if not result.get("ok", False):
            sys.exit(1)

    elif args.command == "show":
        result = redacted_profile_summary()

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            output_text(result)

        if not result.get("ok", False):
            sys.exit(1)

    elif args.command == "clear":
        result = clear_profile()

        if args.json:
            print(json.dumps(result, indent=2))
        else:
            output_text(result)

        if not result.get("ok", False):
            sys.exit(1)

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
