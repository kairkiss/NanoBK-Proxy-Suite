#!/usr/bin/env bash
# Sanitized one-command VPS proxy credential rotation example.
#
# This script is intentionally written as a template. Review and adapt CONFIG_* paths
# for your own server before running. It contains no production secrets.
#
# Expected private env file:
#   /root/.nanok-cf-admin.env
#
# Required variables in that file:
#   ADMIN_TOKEN='<cloudflare-worker-admin-token>'
#   ADMIN_CURRENT_URL='https://primary-subscription.example.com/admin/current'
#   ADMIN_UPDATE_URL='https://primary-subscription.example.com/admin/update'

set -Eeuo pipefail

ENV_FILE="/root/.nanok-cf-admin.env"
BACKUP_ROOT="/root"
LATEST_PRIVATE_RECORD="/root/proxy-key-rotation-latest.private.md"
SERVER_NOTES="/root/server-proxy-notes.md"

HY2_SERVICE="hysteria-server.service"
TUIC_SERVICE="tuic-v5-9443.service"
REALITY_SERVICE="xray-reality-8443.service"
TROJAN_SERVICE="xray-trojan-2443.service"

# Set these paths for your installation.
HY2_CONFIG="/etc/hysteria/config.yaml"
TUIC_CONFIG="/etc/proxy-stack/tuic-v5-9443/config.json"
REALITY_CONFIG="/etc/proxy-stack/xray-reality-8443/config.json"
TROJAN_CONFIG="/etc/proxy-stack/xray-trojan-2443/config.json"

# Static profile fields. Keep placeholders sanitized in this repository.
HY2_NAME="JP-TYO-01 | HY2 | 443 | Primary"
HY2_SERVER="hy2.example.com"
HY2_PORT=443
HY2_SNI="hy2.example.com"

TUIC_NAME="JP-TYO-02 | TUIC V5 | 9443 | Speed"
TUIC_SERVER="tuic.example.com"
TUIC_PORT=9443
TUIC_SNI="tuic.example.com"

REALITY_NAME="JP-TYO-03 | Reality | 8443 | Stealth"
REALITY_SERVER="203.0.113.10"
REALITY_PORT=8443
REALITY_SERVERNAME="www.example-front.com"

TROJAN_NAME="JP-TYO-04 | Trojan | 2443 | Fallback"
TROJAN_SERVER="trojan.example.com"
TROJAN_PORT=2443
TROJAN_SNI="trojan.example.com"

POETRY_NODE_NAME="Status placeholder"
RECOMMEND_NODE_NAME="Project placeholder"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

fail() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

fingerprint() {
  python3 - "$1" <<'PY'
import sys
s = sys.argv[1]
if len(s) <= 12:
    print(f"{s[:3]}...{s[-3:]}")
else:
    print(f"{s[:6]}...{s[-6:]}")
PY
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

service_active() {
  systemctl is-active --quiet "$1"
}

check_tools() {
  require_cmd curl
  require_cmd jq
  require_cmd python3
  require_cmd openssl
  require_cmd uuidgen
  require_cmd xray
  require_cmd systemctl
  require_cmd ss
}

load_env() {
  require_file "$ENV_FILE"
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  [[ -n "${ADMIN_TOKEN:-}" ]] || fail "ADMIN_TOKEN is missing"
  [[ -n "${ADMIN_CURRENT_URL:-}" ]] || fail "ADMIN_CURRENT_URL is missing"
  [[ -n "${ADMIN_UPDATE_URL:-}" ]] || fail "ADMIN_UPDATE_URL is missing"
  log "ADMIN_TOKEN fingerprint: $(fingerprint "$ADMIN_TOKEN")"
}

fetch_cf_profile() {
  local output="$1"
  curl -fsS \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${ADMIN_CURRENT_URL}" \
    -o "$output"
  jq -e 'has("hy2") and has("tuic") and has("reality") and has("trojan")' "$output" >/dev/null
}

make_backup() {
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  BACKUP_DIR="${BACKUP_ROOT}/proxy-key-rotation-backup-${stamp}"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"

  cp -a "$HY2_CONFIG" "$BACKUP_DIR/hy2.config.bak"
  cp -a "$TUIC_CONFIG" "$BACKUP_DIR/tuic.config.bak"
  cp -a "$REALITY_CONFIG" "$BACKUP_DIR/reality.config.bak"
  cp -a "$TROJAN_CONFIG" "$BACKUP_DIR/trojan.config.bak"

  for svc in "$HY2_SERVICE" "$TUIC_SERVICE" "$REALITY_SERVICE" "$TROJAN_SERVICE"; do
    local svc_path="/etc/systemd/system/${svc}"
    if [[ -f "$svc_path" ]]; then
      cp -a "$svc_path" "$BACKUP_DIR/${svc}.bak"
    fi
  done

  if [[ -f "$SERVER_NOTES" ]]; then
    cp -a "$SERVER_NOTES" "$BACKUP_DIR/server-proxy-notes.md.bak"
  fi

  fetch_cf_profile "$BACKUP_DIR/cf-profile-old.json"
  log "backup directory: $BACKUP_DIR"
}

generate_keys() {
  HY2_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"
  TUIC_UUID="$(uuidgen)"
  TUIC_PASSWORD="$(openssl rand -hex 32 | tr -d '\n')"
  TROJAN_PASSWORD="$(openssl rand -base64 24 | tr -d '\n')"
  REALITY_UUID="$(uuidgen)"
  REALITY_SHORT_ID="$(openssl rand -hex 8 | tr -d '\n')"

  local keypair
  keypair="$(xray x25519)"
  REALITY_PRIVATE_KEY="$(printf '%s\n' "$keypair" | awk -F': ' '/Private key/ {print $2}' | tr -d '\r\n')"
  REALITY_PUBLIC_KEY="$(printf '%s\n' "$keypair" | awk -F': ' '/Public key/ {print $2}' | tr -d '\r\n')"

  [[ -n "$REALITY_PRIVATE_KEY" ]] || fail "failed to generate Reality private key"
  [[ -n "$REALITY_PUBLIC_KEY" ]] || fail "failed to generate Reality public key"

  log "generated new credential fingerprints"
  log "HY2 password: $(fingerprint "$HY2_PASSWORD")"
  log "TUIC UUID: $(fingerprint "$TUIC_UUID")"
  log "TUIC password: $(fingerprint "$TUIC_PASSWORD")"
  log "Reality UUID: $(fingerprint "$REALITY_UUID")"
  log "Reality publicKey: $(fingerprint "$REALITY_PUBLIC_KEY")"
  log "Reality shortId: $(fingerprint "$REALITY_SHORT_ID")"
  log "Trojan password: $(fingerprint "$TROJAN_PASSWORD")"
}

validate_no_control_chars() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json, sys
bad = []
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

def has_bad(s):
    return any((ord(c) < 32 and c not in '\t\n\r') or ord(c) == 127 or 0x80 <= ord(c) <= 0x9f for c in s)

def walk(value, p):
    if isinstance(value, str):
        if has_bad(value):
            bad.append(p)
    elif isinstance(value, dict):
        for k, v in value.items():
            walk(v, f'{p}.{k}' if p else str(k))
    elif isinstance(value, list):
        for i, v in enumerate(value):
            walk(v, f'{p}[{i}]')

walk(data, '')
if bad:
    print('invalid control characters in fields:', ', '.join(bad), file=sys.stderr)
    sys.exit(1)
PY
}

patch_configs() {
  # These examples assume HY2 YAML and TUIC/Xray JSON structures commonly used in simple deployments.
  # If your files differ, adapt the Python patch functions and keep structured parsing.

  python3 - "$HY2_CONFIG" "$HY2_PASSWORD" <<'PY'
import sys
path, password = sys.argv[1], sys.argv[2]
text = open(path, encoding='utf-8').read().splitlines()
out = []
changed = False
for line in text:
    stripped = line.lstrip()
    indent = line[:len(line)-len(stripped)]
    if stripped.startswith('password:'):
        out.append(f'{indent}password: "{password}"')
        changed = True
    else:
        out.append(line)
if not changed:
    raise SystemExit('HY2 password field was not found')
open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PY

  python3 - "$TUIC_CONFIG" "$TUIC_UUID" "$TUIC_PASSWORD" <<'PY'
import json, sys
path, uuid, password = sys.argv[1:4]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
# Common TUIC v5 server config shape: users: { uuid: password }
if isinstance(data.get('users'), dict):
    data['users'] = {uuid: password}
elif isinstance(data.get('users'), list):
    data['users'] = [{'uuid': uuid, 'password': password}]
else:
    raise SystemExit('unsupported TUIC users structure')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY

  python3 - "$REALITY_CONFIG" "$REALITY_UUID" "$REALITY_PRIVATE_KEY" "$REALITY_SHORT_ID" <<'PY'
import json, sys
path, uuid, private_key, short_id = sys.argv[1:5]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
changed_client = changed_private = changed_short = False
for inbound in data.get('inbounds', []):
    if inbound.get('protocol') != 'vless':
        continue
    settings = inbound.get('settings', {})
    clients = settings.get('clients', [])
    if clients:
        clients[0]['id'] = uuid
        changed_client = True
    reality = inbound.get('streamSettings', {}).get('realitySettings', {})
    if 'privateKey' in reality:
        reality['privateKey'] = private_key
        changed_private = True
    if 'shortIds' in reality and isinstance(reality['shortIds'], list):
        reality['shortIds'] = [short_id]
        changed_short = True
if not (changed_client and changed_private and changed_short):
    raise SystemExit('failed to patch expected Reality fields')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY

  python3 - "$TROJAN_CONFIG" "$TROJAN_PASSWORD" <<'PY'
import json, sys
path, password = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
changed = False
for inbound in data.get('inbounds', []):
    if inbound.get('protocol') != 'trojan':
        continue
    clients = inbound.get('settings', {}).get('clients', [])
    if clients:
        clients[0]['password'] = password
        changed = True
if not changed:
    raise SystemExit('failed to patch expected Trojan password field')
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
}

build_new_cf_profile() {
  CF_NEW_PROFILE="$BACKUP_DIR/cf-profile-new.json"
  python3 - "$BACKUP_DIR/cf-profile-old.json" "$CF_NEW_PROFILE" <<PY
import json, sys
old_path, new_path = sys.argv[1], sys.argv[2]
with open(old_path, encoding='utf-8') as f:
    old = json.load(f)
profile = old.copy()
profile['updatedAt'] = __import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat()
profile['hy2'] = dict(profile.get('hy2', {}), name='$HY2_NAME', server='$HY2_SERVER', port=$HY2_PORT, password='$HY2_PASSWORD', sni='$HY2_SNI')
profile['tuic'] = dict(profile.get('tuic', {}), name='$TUIC_NAME', server='$TUIC_SERVER', port=$TUIC_PORT, uuid='$TUIC_UUID', password='$TUIC_PASSWORD', sni='$TUIC_SNI')
profile['reality'] = dict(profile.get('reality', {}), name='$REALITY_NAME', server='$REALITY_SERVER', port=$REALITY_PORT, uuid='$REALITY_UUID', servername='$REALITY_SERVERNAME', publicKey='$REALITY_PUBLIC_KEY', shortId='$REALITY_SHORT_ID')
profile['trojan'] = dict(profile.get('trojan', {}), name='$TROJAN_NAME', server='$TROJAN_SERVER', port=$TROJAN_PORT, password='$TROJAN_PASSWORD', sni='$TROJAN_SNI')
profile['extraNodes'] = dict(profile.get('extraNodes', {}), poetryNodeName='$POETRY_NODE_NAME', recommendNodeName='$RECOMMEND_NODE_NAME')
with open(new_path, 'w', encoding='utf-8') as f:
    json.dump(profile, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
  validate_no_control_chars "$CF_NEW_PROFILE"
}

check_configs() {
  xray -test -config "$REALITY_CONFIG" >/dev/null
  xray -test -config "$TROJAN_CONFIG" >/dev/null
}

restart_and_verify() {
  local svc="$1"
  systemctl restart "$svc"
  sleep 1
  service_active "$svc" || fail "service failed: $svc"
  journalctl -u "$svc" -n 20 --no-pager >/dev/null || true
}

verify_ports() {
  ss -ulnp | grep ':443' >/dev/null || fail 'HY2 UDP 443 is not listening'
  ss -ulnp | grep ':9443' >/dev/null || fail 'TUIC UDP 9443 is not listening'
  ss -tulpn | grep ':8443' >/dev/null || fail 'Reality TCP 8443 is not listening'
  ss -tulpn | grep ':2443' >/dev/null || fail 'Trojan TCP 2443 is not listening'
}

post_cf_profile() {
  curl -fsS -X POST "$ADMIN_UPDATE_URL" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H 'Content-Type: application/json' \
    --data-binary "@$CF_NEW_PROFILE" \
    -o "$BACKUP_DIR/cf-update-response.json"
  jq -e '.ok == true' "$BACKUP_DIR/cf-update-response.json" >/dev/null
}

verify_cf_profile() {
  fetch_cf_profile "$BACKUP_DIR/cf-profile-after.json"
  jq -e --arg v "$TUIC_UUID" '.tuic.uuid == $v' "$BACKUP_DIR/cf-profile-after.json" >/dev/null
  jq -e --arg v "$REALITY_PUBLIC_KEY" '.reality.publicKey == $v' "$BACKUP_DIR/cf-profile-after.json" >/dev/null
}

write_private_record() {
  cat > "$LATEST_PRIVATE_RECORD" <<EOF
# Latest Proxy Key Rotation Private Record

Generated: $(date -Is)

## Fingerprints

- HY2 password: $(fingerprint "$HY2_PASSWORD")
- TUIC UUID: $(fingerprint "$TUIC_UUID")
- TUIC password: $(fingerprint "$TUIC_PASSWORD")
- Reality UUID: $(fingerprint "$REALITY_UUID")
- Reality publicKey: $(fingerprint "$REALITY_PUBLIC_KEY")
- Reality shortId: $(fingerprint "$REALITY_SHORT_ID")
- Trojan password: $(fingerprint "$TROJAN_PASSWORD")

## Full Values

Keep this file private and never commit it to Git.

- HY2_PASSWORD=$HY2_PASSWORD
- TUIC_UUID=$TUIC_UUID
- TUIC_PASSWORD=$TUIC_PASSWORD
- REALITY_UUID=$REALITY_UUID
- REALITY_PRIVATE_KEY=$REALITY_PRIVATE_KEY
- REALITY_PUBLIC_KEY=$REALITY_PUBLIC_KEY
- REALITY_SHORT_ID=$REALITY_SHORT_ID
- TROJAN_PASSWORD=$TROJAN_PASSWORD
EOF
  chmod 600 "$LATEST_PRIVATE_RECORD"
}

write_notes() {
  cat >> "$SERVER_NOTES" <<EOF

## Proxy key rotation

- Time: $(date -Is)
- HY2 service: $HY2_SERVICE, port $HY2_PORT, host $HY2_SERVER
- TUIC service: $TUIC_SERVICE, port $TUIC_PORT, host $TUIC_SERVER
- Reality service: $REALITY_SERVICE, port $REALITY_PORT
- Trojan service: $TROJAN_SERVICE, port $TROJAN_PORT, host $TROJAN_SERVER
- Full values are stored only in $LATEST_PRIVATE_RECORD
EOF
}

create_rollback() {
  ROLLBACK_SCRIPT="${BACKUP_DIR}/rollback.sh"
  cat > "$ROLLBACK_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
cp -a '$BACKUP_DIR/hy2.config.bak' '$HY2_CONFIG'
cp -a '$BACKUP_DIR/tuic.config.bak' '$TUIC_CONFIG'
cp -a '$BACKUP_DIR/reality.config.bak' '$REALITY_CONFIG'
cp -a '$BACKUP_DIR/trojan.config.bak' '$TROJAN_CONFIG'
systemctl restart '$REALITY_SERVICE'
systemctl restart '$TROJAN_SERVICE'
systemctl restart '$TUIC_SERVICE'
systemctl restart '$HY2_SERVICE'
echo 'VPS configs rolled back. Restore Cloudflare profile manually from $BACKUP_DIR/cf-profile-old.json if needed.'
EOF
  chmod 700 "$ROLLBACK_SCRIPT"
}

rollback_local() {
  if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
    log "rolling back local VPS configs"
    bash "$BACKUP_DIR/rollback.sh" || true
  fi
}

main() {
  [[ $EUID -eq 0 ]] || fail 'run as root'
  load_env
  check_tools

  for file in "$HY2_CONFIG" "$TUIC_CONFIG" "$REALITY_CONFIG" "$TROJAN_CONFIG"; do
    require_file "$file"
  done

  for svc in "$HY2_SERVICE" "$TUIC_SERVICE" "$REALITY_SERVICE" "$TROJAN_SERVICE"; do
    service_active "$svc" || fail "service is not active before rotation: $svc"
  done

  make_backup
  create_rollback
  generate_keys
  patch_configs
  build_new_cf_profile
  check_configs

  restart_and_verify "$REALITY_SERVICE"
  restart_and_verify "$TROJAN_SERVICE"
  restart_and_verify "$TUIC_SERVICE"
  restart_and_verify "$HY2_SERVICE"
  verify_ports

  if ! post_cf_profile; then
    rollback_local
    fail 'Cloudflare profile update failed; local configs rolled back'
  fi

  if ! verify_cf_profile; then
    rollback_local
    curl -fsS -X POST "$ADMIN_UPDATE_URL" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H 'Content-Type: application/json' \
      --data-binary "@$BACKUP_DIR/cf-profile-old.json" >/dev/null || true
    fail 'Cloudflare profile verification failed; attempted full rollback'
  fi

  write_private_record
  write_notes

  log 'rotation completed successfully'
  log "private record: $LATEST_PRIVATE_RECORD"
  log "rollback script: $ROLLBACK_SCRIPT"
}

main "$@"
