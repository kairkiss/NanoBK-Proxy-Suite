[Unit]
Description=TUIC v5 Server port 9443 (NanoBK)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/tuic-server -c __TUIC_CONFIG__
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
