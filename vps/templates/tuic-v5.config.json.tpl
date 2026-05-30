{
  "server": "[::]:__TUIC_PORT__",
  "users": {
    "__TUIC_UUID__": "__TUIC_PASSWORD__"
  },
  "certificate": "__CERT_FILE__",
  "private_key": "__KEY_FILE__",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "udp_relay_mode": "native",
  "gc_interval": 3,
  "gc_lifetime": 15
}
