# Client Import Guide

## Subscription URL

Your single subscription URL:

```
https://YOUR_NANOB_HOST/jb?token=YOUR_NANOB_TOKEN
```

Or if using nanok directly (without nanob):

```
https://YOUR_NANOK_HOST/jb?token=YOUR_SUB_TOKEN
```

## Supported Clients

### Clash / Mihomo (Desktop)

1. Open Clash or Mihomo.
2. Go to **Profiles** → **Import**.
3. Paste the subscription URL.
4. Click **Download**.
5. Select a proxy from the **Proxy** group.

### Shadowrocket (iOS)

1. Open Shadowrocket.
2. Tap **+** in the top right.
3. Select **Subscribe**.
4. Paste the subscription URL.
5. Tap **Done**.
6. Tap the subscription to update.
7. Select a node and connect.

### Clash for Android

1. Open Clash for Android.
2. Go to **Profiles**.
3. Tap **+** → **Import from URL**.
4. Paste the subscription URL.
5. Tap **Save**.
6. Select the profile and connect.

### Stash (iOS)

1. Open Stash.
2. Go to **Profiles**.
3. Tap **+** → **Remote**.
4. Paste the subscription URL.
5. Tap **Save**.
6. Select a proxy and connect.

## Node Types

The subscription includes these proxy types:

| Protocol | Port | Use Case |
|----------|------|----------|
| Hysteria2 | 443 (UDP) | High performance, QUIC-based |
| TUIC v5 | 9443 (UDP) | QUIC-based, congestion control |
| VLESS Reality | 8443 (TCP) | Stealth, anti-detection |
| Trojan TLS | 2443 (TCP) | Reliable fallback |

## After Key Rotation

When the server rotates keys:

1. The subscription URL does **NOT** change.
2. Your client will fetch new credentials on next update.
3. Force-refresh the subscription in your client if needed.

## Troubleshooting

- **"yaml: control characters are not allowed"**: This should not happen with the current Worker. If it does, report it.
- **Connection timeout**: Check if the VPS is running and ports are open.
- **404 error**: Wrong token or wrong URL. Double-check the subscription URL.
