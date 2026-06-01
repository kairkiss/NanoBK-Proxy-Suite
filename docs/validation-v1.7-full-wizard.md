# NanoBK v1.7 Full Wizard Clean VPS Validation

## Important

- Real clean VPS Full Wizard validation must be executed by a human tester
- Claude Code / local tests cannot claim real VPS / Cloudflare validation passed
- dry-run does not prove real deployment works
- Do not paste tokens into chat, logs, or issues
- Do not `cat bot/.env` or `cat web/.env`
- Subscription URLs need to be redacted before sharing
- Bot/Web are control plane only — they do not mean VPS/Cloudflare is working

## Clean VPS Steps

```bash
# clean Ubuntu 24.04 VPS
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/bootstrap.sh)
cd /opt/NanoBK-Proxy-Suite
bash bin/nanobk --version

# dry-run preview
bash installer/install.sh --mode full --dry-run --defaults --lang zh

# real full wizard
bash installer/install.sh --mode full --lang zh

# verify
sudo bash /opt/nanobk/bin/healthcheck.sh
bash bin/nanobk status
bash bin/nanobk cf verify

# rotate check
sudo bash /opt/nanobk/bin/rotate-keys.sh --yes --protocol tuic
bash bin/nanobk status
```

## Pass Criteria

- VPS four protocols active (hy2, tuic, reality, trojan)
- Four ports listening (UDP 443, UDP 9443, TCP 8443, TCP 2443)
- profile.current.json exists and does not contain Reality private key
- nanok verified
- nanob verified
- Subscription YAML valid
- Bot .env mode 600
- Web .env mode 600
- rotate tuic + Cloudflare sync works
- Summary does not misreport status

## Fail Criteria

- Any stage exits non-zero
- Summary shows installed/verified but actually not verified
- Token leakage
- profile contains private key
- Cloudflare profile missing but shows configured
- Bot/Web failed but shows configured

## Data to Report Back

- Which phases passed / failed
- Error messages from failures
- `nanobk --json status` output (redact tokens)
- healthcheck output
- Do NOT paste real tokens or subscription URLs
