[Unit]
Description=TUIC v5 Server (port 9443)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/tuic-server -c /etc/proxy-stack/tuic-v5-9443/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
