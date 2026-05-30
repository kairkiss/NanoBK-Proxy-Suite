[Unit]
Description=Xray Trojan Server port 2443 (NanoBK)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config __TROJAN_CONFIG__
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
