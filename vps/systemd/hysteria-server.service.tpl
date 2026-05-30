[Unit]
Description=Hysteria2 Server (NanoBK)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/hysteria server -c __HY2_CONFIG__
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
