# NanoBK Web Panel — v1.2.1

Local-only Flask Web Panel for NanoBK Proxy Suite.

**The panel only calls `nanobk` CLI** — it never directly reads or writes secrets, profiles, configs, or systemd services.

## Security

- **Default bind: `127.0.0.1:8080`** — not exposed to the internet
- **Token-based login** — single shared token, no user system
- **Rotate requires confirmation** — 120-second expiry
- **Output redaction** — tokens, passwords, keys are stripped from responses
- **Dry-run mode** — rotate shows commands but doesn't execute

**Do NOT expose this directly to the public internet.** Use SSH tunnel or Cloudflare Access:

```bash
ssh -L 8080:127.0.0.1:8080 root@YOUR_VPS_IP
```

Then open `http://127.0.0.1:8080` in your browser.

## Prerequisites

- Python 3.8+
- Python venv support

On Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y python3-venv
```

## Quick Start

```bash
cd web
cp .env.example .env
nano .env    # Change NANOBK_WEB_TOKEN and NANOBK_WEB_SECRET_KEY
bash run.sh
```

## Configuration

Edit `web/.env`:

| Variable | Required | Description |
|----------|----------|-------------|
| `NANOBK_WEB_TOKEN` | **Yes** | Login token (change from default!) |
| `NANOBK_WEB_SECRET_KEY` | **Yes** | Flask session secret (change from default!) |
| `NANOBK_WEB_HOST` | No | Bind address (default: `127.0.0.1`) |
| `NANOBK_WEB_PORT` | No | Port (default: `8080`) |
| `NANOBK_CLI` | No | Path to nanobk CLI |
| `NANOBK_REPO_DIR` | No | Repo root for nanobk --repo-dir |
| `NANOBK_WEB_DRY_RUN` | No | `true` = rotate doesn't execute |
| `NANOBK_WEB_SECRET_KEY` | **Yes** | Flask session secret (change from default!) |

## Pages

| Page | Description |
|------|-------------|
| `/login` | Token login |
| `/` | Dashboard with quick status |
| `/status` | Full status (text + raw JSON) |
| `/api/status` | JSON API endpoint |
| `/doctor` | Run environment diagnostics |
| `/rotate` | Rotate keys with confirmation |
| `/healthz` | Health check (no auth required) |

## Security Features

- **Secret key validation**: Default `NANOBK_WEB_SECRET_KEY` rejected at startup
- **CSRF protection**: All POST forms include CSRF tokens
- **Logout via POST**: No GET-based logout (prevents CSRF logout attacks)
- **JSON redaction**: `/api/status` and raw JSON output redact sensitive keys
- **ANSI stripping**: Terminal color codes removed before display
- **No fallback secrets**: Flask won't start with insecure defaults

## Rotate Flow

1. Click **Rotate TUIC** (or other protocol)
2. Panel shows confirmation page
3. Click **Confirm Rotate TUIC**
4. If dry-run: shows command but doesn't execute
5. If live: executes `nanobk rotate tuic --yes`

Confirmation expires after 120 seconds.

## systemd Deployment

```bash
sudo cp web/systemd/nanobk-web-panel.service.example /etc/systemd/system/nanobk-web-panel.service
sudo nano /etc/systemd/system/nanobk-web-panel.service  # Edit paths
sudo systemctl daemon-reload
sudo systemctl enable --now nanobk-web-panel.service
```

## Self-Test

```bash
python3 web/app.py --self-test
```

Validates core logic without starting the Flask server.

## Current Limitations

- No multi-user support
- No database
- No OAuth
- No traffic monitoring
- No Cloudflare configuration wizard
- No real-time WebSocket
- No TLS (use SSH tunnel or Cloudflare Access)
- Not recommended for direct public internet exposure
