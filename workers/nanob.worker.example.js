const NANOK_ORIGIN = 'https://primary-subscription.example.com';
const EDGE_HOST = 'edge-subscription.example.com';
const EDGE_SUB_PATH = '/sub?target=clash';

const GEO_CACHE_TTL_SECONDS = 30 * 24 * 60 * 60;
const GEO_READ_CACHE_TTL_SECONDS = 60 * 60;
const GEO_LOOKUP_DELAY_MS = 1100;
const GEO_LOOKUP_TIMEOUT_MS = 2500;
const GEO_MAX_BACKGROUND_LOOKUPS = 24;

function responseHeaders(type) {
  return {
    'content-type': type || 'text/plain; charset=utf-8',
    'cache-control': 'no-store, no-cache, must-revalidate, max-age=0',
    'x-robots-tag': 'noindex, nofollow',
  };
}

function errorResponse(status, message) {
  return new Response(message, { status, headers: responseHeaders() });
}

function nextTopLevel(lines, start) {
  for (let i = start; i < lines.length; i += 1) {
    if (/^[A-Za-z0-9_-]+:\s*(?:#.*)?$/.test(lines[i])) return i;
  }
  return lines.length;
}

function yamlSection(yaml, label) {
  const lines = String(yaml || '')
    .replace(/^\uFEFF/, '')
    .replace(/\r\n/g, '\n')
    .split('\n');
  const start = lines.findIndex((line) => /^proxies:\s*(?:#.*)?$/.test(line));
  if (start < 0) throw new Error(`${label} has no proxies section`);
  const end = nextTopLevel(lines, start + 1);
  const body = lines.slice(start + 1, end);
  if (!body.some((line) => /^\s*-\s*(?:name:|\{)/.test(line))) {
    throw new Error(`${label} has no proxy entries`);
  }
  return { lines, start, end, body };
}

function yamlScalar(value) {
  const text = String(value || '').trim();
  if (!text) return text;
  if (text.startsWith('"') && text.endsWith('"')) {
    try {
      return JSON.parse(text);
    } catch {
      return text.slice(1, -1);
    }
  }
  if (text.startsWith("'") && text.endsWith("'")) {
    return text.slice(1, -1).replace(/''/g, "'");
  }
  return text;
}

function inlineField(line, field) {
  const match = String(line || '').match(new RegExp(`(?:\\{|,\\s*)${field}:\\s*([^,}]+)`));
  return match ? yamlScalar(match[1]) : '';
}

function ipFromProxyLine(line) {
  const server = inlineField(line, 'server').replace(/^\[|\]$/g, '').trim();
  if (/^(?:\d{1,3}\.){3}\d{1,3}$/.test(server)) return server;
  if (server.includes(':') && /^[0-9a-fA-F:]+$/.test(server)) return server;
  return '';
}

function uniqueEdgeIps(lines) {
  return [...new Set(lines.map(ipFromProxyLine).filter(Boolean))];
}

function cleanLabel(value) {
  return String(value || '')
    .replace(/[\[\]\r\n]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 64);
}

function geoLabel(geo) {
  if (!geo) return '';
  const country = cleanLabel(geo.country_code || geo.country);
  const region = cleanLabel(geo.region);
  if (country && region && region.toLowerCase() !== country.toLowerCase()) {
    return `${country} / ${region}`;
  }
  return country || region;
}

function geoNetworkKey(ip) {
  const parts = String(ip || '').split('.');
  if (parts.length === 4 && parts.every((part) => /^\d+$/.test(part))) {
    return `net4:${parts[0]}.${parts[1]}`;
  }
  return '';
}

async function cachedGeoKey(env, key) {
  if (!env.NANOB_GEO_CACHE || !key) return null;
  try {
    return await env.NANOB_GEO_CACHE.get(key, {
      type: 'json',
      cacheTtl: GEO_READ_CACHE_TTL_SECONDS,
    });
  } catch {
    return null;
  }
}

async function cachedGeo(env, ip) {
  return cachedGeoKey(env, `geo:${ip}`);
}

async function loadGeoMap(env, ips, ctx) {
  const map = new Map();
  if (!env.NANOB_GEO_CACHE || ips.length === 0) return map;

  const results = await Promise.all(ips.map(async (ip) => [ip, await cachedGeo(env, ip)]));
  const missing = [];

  for (const [ip, geo] of results) {
    if (geo && geo.ip === ip) map.set(ip, geo);
    else missing.push(ip);
  }

  const networkKeys = [...new Set(missing.map(geoNetworkKey).filter(Boolean))];
  const networkResults = await Promise.all(
    networkKeys.map(async (key) => [key, await cachedGeoKey(env, key)]),
  );
  const networkMap = new Map(networkResults.filter(([, geo]) => geo));

  const lookupIps = [];
  const lookupNetworks = new Set();
  for (const ip of missing) {
    const networkKey = geoNetworkKey(ip);
    const fallback = networkMap.get(networkKey);
    if (fallback) {
      map.set(ip, fallback);
      continue;
    }
    const lookupKey = networkKey || `ip:${ip}`;
    if (!lookupNetworks.has(lookupKey)) {
      lookupNetworks.add(lookupKey);
      lookupIps.push(ip);
    }
  }

  if (ctx && lookupIps.length > 0) {
    ctx.waitUntil(warmMissingGeo(env, lookupIps.slice(0, GEO_MAX_BACKGROUND_LOOKUPS)));
  }

  return map;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchGeo(ip) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), GEO_LOOKUP_TIMEOUT_MS);
  try {
    const response = await fetch(`https://ipwho.is/${encodeURIComponent(ip)}`, {
      signal: controller.signal,
      headers: { accept: 'application/json' },
    });
    if (!response.ok) return null;
    const data = await response.json();
    if (!data || data.success !== true || data.ip !== ip) return null;
    return {
      ip,
      country: cleanLabel(data.country),
      country_code: cleanLabel(data.country_code),
      region: cleanLabel(data.region),
      updated_at: new Date().toISOString(),
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function warmMissingGeo(env, ips) {
  if (!env.NANOB_GEO_CACHE) return;

  for (const ip of [...new Set(ips)]) {
    const existing = await cachedGeo(env, ip);
    if (!existing) {
      const geo = await fetchGeo(ip);
      if (geo) {
        const writes = [
          env.NANOB_GEO_CACHE.put(`geo:${ip}`, JSON.stringify(geo), {
            expirationTtl: GEO_CACHE_TTL_SECONDS,
          }),
        ];
        const networkKey = geoNetworkKey(ip);
        if (networkKey) {
          writes.push(
            env.NANOB_GEO_CACHE.put(networkKey, JSON.stringify(geo), {
              expirationTtl: GEO_CACHE_TTL_SECONDS,
            }),
          );
        }
        await Promise.all(writes);
      }
    }
    await sleep(GEO_LOOKUP_DELAY_MS);
  }
}

function geoPrefix(ip, geoMap) {
  const label = geoLabel(ip && geoMap.get(ip));
  return `${label ? `[${label}] ` : ''}[EDT backup] `;
}

function decorateEdgeLine(line, geoMap) {
  const prefix = geoPrefix(ipFromProxyLine(line), geoMap);

  const block = line.match(/^(\s*-\s*name:\s*)(.+?)\s*$/)
    || line.match(/^(\s+name:\s*)(.+?)\s*$/);
  if (block) {
    const value = yamlScalar(block[2]);
    return !value || value.includes('[EDT backup]')
      ? line
      : block[1] + JSON.stringify(prefix + value);
  }

  const inline = line.match(/^(\s*-\s*\{\s*name:\s*)([^,}]+)(.*)$/);
  if (!inline) return line;

  const value = yamlScalar(inline[2]);
  return !value || value.includes('[EDT backup]')
    ? line
    : inline[1] + JSON.stringify(prefix + value) + inline[3];
}

async function mergeSubscriptions(primaryYaml, edgeYaml, env, ctx) {
  const primary = yamlSection(primaryYaml, 'primary');
  const edge = yamlSection(edgeYaml, 'edgetunnel');
  const geoMap = await loadGeoMap(env, uniqueEdgeIps(edge.body), ctx);
  const edgeLines = edge.body.map((line) => decorateEdgeLine(line, geoMap));

  return primary.lines
    .slice(0, primary.start + 1)
    .concat(primary.body, '', '  # edgetunnel backup nodes', edgeLines, primary.lines.slice(primary.end))
    .join('\n');
}

function relayHeaders(request) {
  return {
    'user-agent': request.headers.get('user-agent') || 'Clash/Mihomo',
    accept: request.headers.get('accept') || '*/*',
  };
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method !== 'GET' || url.pathname !== '/jb') {
      return errorResponse(404, 'Not Found');
    }

    if (
      !env.NANOB_TOKEN
      || !env.NANOK_SUB_TOKEN
      || !env.EDGETUNNEL_EXPORT_TOKEN
    ) {
      return errorResponse(500, 'aggregator is missing required secrets');
    }

    if (url.searchParams.get('token') !== env.NANOB_TOKEN) {
      return errorResponse(404, 'Not Found');
    }

    const requestHeaders = relayHeaders(request);
    const primaryUrl = new URL('/jb', NANOK_ORIGIN);
    primaryUrl.searchParams.set('token', env.NANOK_SUB_TOKEN);

    const edgeRequest = new Request(`https://${EDGE_HOST}${EDGE_SUB_PATH}`, {
      headers: {
        ...requestHeaders,
        'x-nanob-token': env.EDGETUNNEL_EXPORT_TOKEN,
      },
    });

    let primaryResponse;
    let edgeResponse;
    try {
      [primaryResponse, edgeResponse] = await Promise.all([
        fetch(primaryUrl, { headers: requestHeaders, redirect: 'follow' }),
        fetch(edgeRequest, { redirect: 'follow' }),
      ]);
    } catch (fetchError) {
      return errorResponse(
        502,
        `upstream fetch failed: ${String(fetchError && fetchError.message || fetchError)}`,
      );
    }

    if (!primaryResponse.ok) {
      return new Response(primaryResponse.body, {
        status: primaryResponse.status,
        headers: responseHeaders(primaryResponse.headers.get('content-type')),
      });
    }

    if (!edgeResponse.ok) {
      return errorResponse(502, 'edgetunnel subscription fetch failed');
    }

    try {
      const merged = await mergeSubscriptions(
        await primaryResponse.text(),
        await edgeResponse.text(),
        env,
        ctx,
      );
      return new Response(merged, { headers: responseHeaders() });
    } catch (err) {
      return errorResponse(
        502,
        `subscription merge failed: ${String(err && err.message || err)}`,
      );
    }
  },
};

