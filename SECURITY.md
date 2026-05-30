# Security Notes

Do not commit real values for:

- Cloudflare API tokens.
- Worker secrets.
- Subscription tokens.
- UUIDs used as node credentials.
- Private hostnames if they should not be public.
- KV namespace IDs if they are considered sensitive in your environment.

The example Worker is intentionally configured with placeholder domains and environment variables.

