# NanoBK Telegram Bot — v1.1.0

Control layer for NanoBK Proxy Suite via Telegram.

**The bot only calls `nanobk` CLI** — it never directly reads or writes secrets, profiles, configs, or systemd services.

## Quick Start

```bash
# 1. Get a bot token from @BotFather on Telegram
# 2. Find your Telegram user ID (send /start to @userinfobot)
# 3. Configure
cd bot
cp .env.example .env
nano .env

# 4. Run
bash run.sh
```

## Configuration

Edit `bot/.env`:

```env
TELEGRAM_BOT_TOKEN=123456:ABCdefGHIjklMNOpqrs
OWNER_TELEGRAM_ID=123456789
NANOBK_CLI=/usr/local/bin/nanobk
```

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Yes | Token from @BotFather |
| `OWNER_TELEGRAM_ID` | Yes | Your numeric Telegram user ID |
| `NANOBK_CLI` | No | Path to nanobk (default: `/usr/local/bin/nanobk`) |
| `NANOBK_REPO_DIR` | No | Repo root (auto-detected if nanobk is in repo) |
| `NANOBK_COMMAND_TIMEOUT` | No | Timeout for status/doctor (default: 120s) |
| `NANOBK_ROTATE_TIMEOUT` | No | Timeout for rotate (default: 300s) |
| `NANOBK_BOT_DRY_RUN` | No | `true` = rotate commands print but don't execute |

## Commands

| Command | Description |
|---------|-------------|
| `/start` | Welcome message |
| `/help` | List all commands |
| `/status` | VPS/CF status summary |
| `/status_json` | Raw JSON status |
| `/doctor` | Environment diagnostics |
| `/rotate_all` | Rotate ALL protocols (requires confirmation) |
| `/rotate_hy2` | Rotate HY2 only |
| `/rotate_tuic` | Rotate TUIC only |
| `/rotate_reality` | Rotate Reality only |
| `/rotate_trojan` | Rotate Trojan only |
| `/cancel` | Cancel pending rotation |

**Rotate commands require confirmation.** After `/rotate_tuic`, reply with `/confirm_rotate_tuic` to execute.

## Security

- **Owner-only access**: Only `OWNER_TELEGRAM_ID` can use the bot
- **No direct file access**: Bot never reads/writes `/etc/nanobk/` files
- **Confirmation required**: Rotate commands need explicit `/confirm_rotate_*`
- **Output redaction**: Tokens, passwords, keys are redacted from responses
- **Dry-run mode**: Set `NANOBK_BOT_DRY_RUN=true` to test without executing rotate
- **Timeout protection**: All commands have configurable timeouts

## systemd Deployment

```bash
# Edit paths in the example
sudo cp bot/systemd/nanobk-telegram-bot.service.example /etc/systemd/system/nanobk-telegram-bot.service
sudo nano /etc/systemd/system/nanobk-telegram-bot.service

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable --now nanobk-telegram-bot.service

# Check status
sudo systemctl status nanobk-telegram-bot.service
sudo journalctl -u nanobk-telegram-bot.service -f
```

## Self-Test

```bash
python3 bot/nanobk_bot.py --self-test
```

Validates core logic without connecting to Telegram.

## Current Limitations

- No Web Panel
- No multi-user support
- No button UI (text commands only)
- No traffic monitoring
- No database
- No Cloudflare configuration wizard
- Pending confirmations reset on bot restart
