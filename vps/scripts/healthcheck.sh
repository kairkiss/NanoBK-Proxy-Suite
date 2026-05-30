#!/usr/bin/env bash
# NanoBK Proxy Suite — Health Check
#
# Quick read-only check of VPS proxy services and ports.
#
# Usage:
#   sudo bash vps/scripts/healthcheck.sh

set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SERVICES=(
  "hysteria-server.service:443:udp:HY2"
  "tuic-v5-9443.service:9443:udp:TUIC"
  "xray-reality-8443.service:8443:tcp:Reality"
  "xray-trojan-2443.service:2443:tcp:Trojan"
)

ERRORS=0

for entry in "${SERVICES[@]}"; do
  IFS=':' read -r svc port proto name <<< "$entry"

  # Check service
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    svc_status="${GREEN}active${NC}"
  else
    svc_status="${RED}inactive${NC}"
    ERRORS=$((ERRORS + 1))
  fi

  # Check port
  if [[ "$proto" == "udp" ]]; then
    if ss -ulnp 2>/dev/null | grep -q ":${port} "; then
      port_status="${GREEN}listening${NC}"
    else
      port_status="${RED}not listening${NC}"
      ERRORS=$((ERRORS + 1))
    fi
  else
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
      port_status="${GREEN}listening${NC}"
    else
      port_status="${RED}not listening${NC}"
      ERRORS=$((ERRORS + 1))
    fi
  fi

  printf "%-12s  service: %-20b  port :%-5s (%-3s): %b\n" \
    "$name" "$svc_status" "$port" "$proto" "$port_status"
done

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}All services healthy.${NC}"
else
  echo -e "${RED}${ERRORS} issue(s) detected.${NC}"
  exit 1
fi
