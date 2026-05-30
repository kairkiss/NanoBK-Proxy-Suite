// Geo lookup module using ipwho.is (free, no API key required).
//
// Features:
//   - Per-IP cache in Cloudflare KV with configurable TTL
//   - IPv4 /24 network-prefix learning for cache efficiency
//   - Background warming via ctx.waitUntil
//   - Failure-safe: lookup errors never block subscription output
//
// KV binding: accepts either GEO_CACHE or NANOB_GEO_CACHE.
//
// Usage:
//   import { loadGeoMap, geoLabel } from '../shared/geo.js';
//   const geoMap = await loadGeoMap(env, ipList, ctx);
//   const label = geoLabel(geoMap.get(ip));

const GEO_CACHE_TTL_SECONDS = 30 * 24 * 60 * 60;   // 30 days KV write TTL
const GEO_READ_CACHE_TTL_SECONDS = 60 * 60;          // 1 hour KV read cache
const GEO_LOOKUP_TIMEOUT_MS = 2500;
const GEO_LOOKUP_DELAY_MS = 1100;                     // rate-limit ipwho.is
const GEO_MAX_BACKGROUND_LOOKUPS = 24;

// ---------------------------------------------------------------------------
// KV binding helper — accepts GEO_CACHE or NANOB_GEO_CACHE
// ---------------------------------------------------------------------------

function getGeoCache(env) {
  return env.GEO_CACHE || env.NANOB_GEO_CACHE || null;
}

// ---------------------------------------------------------------------------
// Label helpers
// ---------------------------------------------------------------------------

function cleanLabel(value) {
  return String(value || '')
    .replace(/[\[\]\r\n]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 64);
}

export function geoLabel(geo) {
  if (!geo) return '';
  const country = cleanLabel(geo.country_code || geo.country);
  const region = cleanLabel(geo.region);
  if (country && region && region.toLowerCase() !== country.toLowerCase()) {
    return `${country} / ${region}`;
  }
  return country || region;
}

export function geoNetworkKey(ip) {
  const parts = String(ip || '').split('.');
  if (parts.length === 4 && parts.every((part) => /^\d+$/.test(part))) {
    return `net4:${parts[0]}.${parts[1]}`;
  }
  return '';
}

// ---------------------------------------------------------------------------
// KV read helpers
// ---------------------------------------------------------------------------

async function cachedGeoKey(env, key) {
  const cache = getGeoCache(env);
  if (!cache || !key) return null;
  try {
    return await cache.get(key, {
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

// ---------------------------------------------------------------------------
// GeoIP fetch
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Background warming
// ---------------------------------------------------------------------------

async function warmMissingGeo(env, ips) {
  const cache = getGeoCache(env);
  if (!cache) return;
  for (const ip of [...new Set(ips)]) {
    const existing = await cachedGeo(env, ip);
    if (!existing) {
      const geo = await fetchGeo(ip);
      if (geo) {
        const writes = [
          cache.put(`geo:${ip}`, JSON.stringify(geo), {
            expirationTtl: GEO_CACHE_TTL_SECONDS,
          }),
        ];
        const networkKey = geoNetworkKey(ip);
        if (networkKey) {
          writes.push(
            cache.put(networkKey, JSON.stringify(geo), {
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

// ---------------------------------------------------------------------------
// Main export: load geo map for a list of IPs
// ---------------------------------------------------------------------------

export async function loadGeoMap(env, ips, ctx) {
  const map = new Map();
  const cache = getGeoCache(env);
  if (!cache || ips.length === 0) return map;

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
