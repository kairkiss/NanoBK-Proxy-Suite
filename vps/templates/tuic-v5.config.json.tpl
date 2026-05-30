{
  "server": "[::]:9443",
  "users": {
    "REPLACE_WITH_TUIC_UUID": "REPLACE_WITH_TUIC_PASSWORD"
  },
  "certificate": "/etc/proxy-stack/tuic-v5-9443/cert.pem",
  "private_key": "/etc/proxy-stack/tuic-v5-9443/key.pem",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "udp_relay_mode": "native",
  "gc_interval": 3,
  "gc_lifetime": 15
}
