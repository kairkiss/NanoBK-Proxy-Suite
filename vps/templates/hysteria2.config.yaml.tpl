# Hysteria2 Server Configuration Template
# Replace all REPLACE_WITH_* placeholders before use.

listen: :443

tls:
  cert: /etc/hysteria/cert.pem
  key: /etc/hysteria/key.pem

auth:
  type: password
  password: "REPLACE_WITH_HY2_PASSWORD"

masquerade:
  type: proxy
  proxy:
    url: https://REPLACE_WITH_MASQUERADE_URL
    rewriteHost: true
