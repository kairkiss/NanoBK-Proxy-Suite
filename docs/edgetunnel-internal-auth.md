# Edgetunnel Internal Authorization

The aggregator should not depend on the public edgetunnel import URL or on a readable edgetunnel `KEY` secret.

Instead, add a minimal internal authorization path to edgetunnel's subscription branch:

```js
const requestToken = url.searchParams.get('token');
const fromAggregator =
  env.NANOB_TOKEN
  && request.headers.get('x-nanob-token') === env.NANOB_TOKEN;
const userSubscription = requestToken === subscriptionToken || fromAggregator;
```

Then keep the original edgetunnel condition structure:

```js
if (userSubscription || converterSubscription || bestSubGenerator) {
  // existing edgetunnel subscription generation
}
```

## Required Secret

Bind the same random shared secret value in both Workers:

| Worker | Secret |
| --- | --- |
| `edgetunnel` | `NANOB_TOKEN` |
| `nanob` | `EDGETUNNEL_EXPORT_TOKEN` |

The aggregator sends:

```http
x-nanob-token: <EDGETUNNEL_EXPORT_TOKEN>
```

The edgetunnel Worker compares it against its own internal secret.

## Update Warning

If edgetunnel is later fully replaced with upstream source, re-apply this internal authorization patch. Otherwise the aggregator can no longer fetch edgetunnel backup nodes without the public edgetunnel subscription token.

