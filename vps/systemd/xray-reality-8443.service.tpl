[Unit]
Description=Xray Reality Server (port 8443)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config /etc/proxy-stack/xray-reality-8443/config.json
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
