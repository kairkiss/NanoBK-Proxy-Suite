// NanoK — Primary Clash/Mihomo Subscription Worker
//
// Features:
//   - KV-backed profile storage (profile:main)
//   - Token-protected subscription endpoint
//   - Private admin read/update endpoints for VPS rotation script
//   - Strict YAML string quoting and control-character validation
//   - HTML status page at root
//
// Derived from: workers/nanok.kv-primary.worker.example.js
// No production tokens, UUIDs, passwords, keys, IPs, or IDs are included.

import {
  cleanString,
  optionalCleanString,
  yamlQuote,
  asPort,
  assertValidYamlText,
} from '../../shared/yaml-safe.js';

const PROFILE_KEY = 'profile:main';

const DEFAULT_SUB_PATH = '/jb';
const DEFAULT_EDGE_PATH = '/edge';
const DEFAULT_ADMIN_PATH = '/admin/update';
const DEFAULT_ADMIN_CURRENT_PATH = '/admin/current';
const DEFAULT_EDGE_SUB_URL = 'https://edge-subscription.example.com/sub?target=clash';
const DEFAULT_POETRY_NODE_NAME = 'Status placeholder';
const DEFAULT_RECOMMEND_NODE_NAME = 'Project placeholder';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function responseHeaders(type = 'text/plain; charset=utf-8') {
  return {
    'content-type': type,
    'cache-control': 'no-store, no-cache, must-revalidate, max-age=0',
    'x-robots-tag': 'noindex, nofollow',
  };
}

function notFound() {
  return new Response('Not Found', { status: 404, headers: responseHeaders() });
}

function errorResponse(status, message) {
  return new Response(message, { status, headers: responseHeaders() });
}

function normalizePath(value, fallback) {
  const raw = typeof value === 'string' && value.trim() ? value.trim() : fallback;
  const path = raw.startsWith('/') ? raw : `/${raw}`;
  if (path === '/') throw new Error('path must not be /');
  return path;
}

function getConfig(env) {
  const cfg = {
    subPath: normalizePath(env.SUB_PATH, DEFAULT_SUB_PATH),
    edgePath: normalizePath(env.EDGE_PATH, DEFAULT_EDGE_PATH),
    adminPath: normalizePath(env.ADMIN_PATH, DEFAULT_ADMIN_PATH),
    adminCurrentPath: normalizePath(env.ADMIN_CURRENT_PATH, DEFAULT_ADMIN_CURRENT_PATH),
    subToken: typeof env.SUB_TOKEN === 'string' ? env.SUB_TOKEN : '',
    adminToken: typeof env.ADMIN_TOKEN === 'string' ? env.ADMIN_TOKEN : '',
    edgeSubUrl: typeof env.EDGE_SUB_URL === 'string' && env.EDGE_SUB_URL.trim()
      ? env.EDGE_SUB_URL.trim()
      : DEFAULT_EDGE_SUB_URL,
    poetryNodeName: typeof env.POETRY_NODE_NAME === 'string' && env.POETRY_NODE_NAME.trim()
      ? env.POETRY_NODE_NAME
      : DEFAULT_POETRY_NODE_NAME,
    recommendNodeName: typeof env.RECOMMEND_NODE_NAME === 'string' && env.RECOMMEND_NODE_NAME.trim()
      ? env.RECOMMEND_NODE_NAME
      : DEFAULT_RECOMMEND_NODE_NAME,
  };

  const routePaths = [cfg.subPath, cfg.edgePath, cfg.adminPath, cfg.adminCurrentPath];
  if (new Set(routePaths).size !== routePaths.length) {
    throw new Error('route paths must be unique');
  }

  return cfg;
}

function checkSubToken(url, cfg) {
  if (!cfg.subToken) return true;
  return url.searchParams.get('token') === cfg.subToken;
}

function checkAdminToken(request, cfg) {
  if (!cfg.adminToken) return false;
  const expected = `Bearer ${cfg.adminToken}`;
  return request.headers.get('authorization') === expected;
}

function shortFingerprint(value) {
  const text = String(value || '');
  if (text.length <= 12) return `${text.slice(0, 3)}...${text.slice(-3)}`;
  return `${text.slice(0, 6)}...${text.slice(-6)}`;
}

// ---------------------------------------------------------------------------
// Profile validation
// ---------------------------------------------------------------------------

function validateProfile(profile, cfg) {
  if (!profile || typeof profile !== 'object') throw new Error('missing required profile');

  const cleaned = {
    updatedAt: optionalCleanString(profile.updatedAt, new Date().toISOString(), 'updatedAt'),
    hy2: {
      name: cleanString(profile.hy2?.name, 'hy2.name'),
      server: cleanString(profile.hy2?.server, 'hy2.server'),
      port: asPort(profile.hy2?.port, 'hy2.port'),
      password: cleanString(profile.hy2?.password, 'hy2.password'),
      sni: cleanString(profile.hy2?.sni, 'hy2.sni'),
    },
    tuic: {
      name: cleanString(profile.tuic?.name, 'tuic.name'),
      server: cleanString(profile.tuic?.server, 'tuic.server'),
      port: asPort(profile.tuic?.port, 'tuic.port'),
      uuid: cleanString(profile.tuic?.uuid, 'tuic.uuid'),
      password: cleanString(profile.tuic?.password, 'tuic.password'),
      sni: cleanString(profile.tuic?.sni, 'tuic.sni'),
    },
    reality: {
      name: cleanString(profile.reality?.name, 'reality.name'),
      server: cleanString(profile.reality?.server, 'reality.server'),
      port: asPort(profile.reality?.port, 'reality.port'),
      uuid: cleanString(profile.reality?.uuid, 'reality.uuid'),
      servername: cleanString(profile.reality?.servername, 'reality.servername'),
      publicKey: cleanString(profile.reality?.publicKey, 'reality.publicKey'),
      shortId: cleanString(profile.reality?.shortId, 'reality.shortId'),
    },
    trojan: {
      name: cleanString(profile.trojan?.name, 'trojan.name'),
      server: cleanString(profile.trojan?.server, 'trojan.server'),
      port: asPort(profile.trojan?.port, 'trojan.port'),
      password: cleanString(profile.trojan?.password, 'trojan.password'),
      sni: cleanString(profile.trojan?.sni, 'trojan.sni'),
    },
    extraNodes: {
      poetryNodeName: optionalCleanString(
        profile.extraNodes?.poetryNodeName,
        cfg.poetryNodeName,
        'extraNodes.poetryNodeName',
      ),
      recommendNodeName: optionalCleanString(
        profile.extraNodes?.recommendNodeName,
        cfg.recommendNodeName,
        'extraNodes.recommendNodeName',
      ),
    },
  };

  return cleaned;
}

// ---------------------------------------------------------------------------
// YAML generation
// ---------------------------------------------------------------------------

function buildSubYaml(profile, cfg) {
  const p = validateProfile(profile, cfg);
  const yaml = `
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
unified-delay: true

proxies:
  - name: ${yamlQuote(p.hy2.name, 'hy2.name')}
    type: hysteria2
    server: ${yamlQuote(p.hy2.server, 'hy2.server')}
    port: ${p.hy2.port}
    password: ${yamlQuote(p.hy2.password, 'hy2.password')}
    sni: ${yamlQuote(p.hy2.sni, 'hy2.sni')}
    skip-cert-verify: false
    udp: true

  - name: ${yamlQuote(p.tuic.name, 'tuic.name')}
    type: tuic
    server: ${yamlQuote(p.tuic.server, 'tuic.server')}
    port: ${p.tuic.port}
    uuid: ${yamlQuote(p.tuic.uuid, 'tuic.uuid')}
    password: ${yamlQuote(p.tuic.password, 'tuic.password')}
    sni: ${yamlQuote(p.tuic.sni, 'tuic.sni')}
    skip-cert-verify: false
    udp: true
    alpn:
      - h3
    congestion-controller: bbr
    udp-relay-mode: native

  - name: ${yamlQuote(p.reality.name, 'reality.name')}
    type: vless
    server: ${yamlQuote(p.reality.server, 'reality.server')}
    port: ${p.reality.port}
    uuid: ${yamlQuote(p.reality.uuid, 'reality.uuid')}
    encryption: none
    network: tcp
    tls: true
    udp: true
    servername: ${yamlQuote(p.reality.servername, 'reality.servername')}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${yamlQuote(p.reality.publicKey, 'reality.publicKey')}
      short-id: ${yamlQuote(p.reality.shortId, 'reality.shortId')}
    flow: xtls-rprx-vision

  - name: ${yamlQuote(p.trojan.name, 'trojan.name')}
    type: trojan
    server: ${yamlQuote(p.trojan.server, 'trojan.server')}
    port: ${p.trojan.port}
    password: ${yamlQuote(p.trojan.password, 'trojan.password')}
    sni: ${yamlQuote(p.trojan.sni, 'trojan.sni')}
    skip-cert-verify: false
    udp: true

  - name: ${yamlQuote(p.extraNodes.poetryNodeName, 'extraNodes.poetryNodeName')}
    type: http
    server: "127.0.0.0"
    port: 8888
    udp: false

  - name: ${yamlQuote(p.extraNodes.recommendNodeName, 'extraNodes.recommendNodeName')}
    type: http
    server: "127.0.0.0"
    port: 8889
    udp: false

proxy-groups:
  - name: "Proxy"
    type: select
    include-all-proxies: true
    proxies:
      - DIRECT

rules:
  - MATCH,Proxy
`.trim();

  assertValidYamlText(yaml);
  return yaml;
}

// ---------------------------------------------------------------------------
// HTML home page
// ---------------------------------------------------------------------------

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function buildHomeHtml(cfg, origin) {
  const text = `
NanoK Subscription Online

Subscription URL:
${origin}${cfg.subPath}?token=*****

Notes:
1. Private use only.
2. Node names may change.
3. Use a Clash/Mihomo-compatible client.
`.trim();

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>NanoK</title>
  <style>
    body { margin: 0; padding: 40px 20px; font-family: Arial, sans-serif; background: #0b1020; color: #e8eefc; }
    .card { max-width: 760px; margin: 0 auto; background: #121a31; border: 1px solid #26304d; border-radius: 16px; padding: 24px; }
    .sub { color: #9fb0d8; margin-bottom: 18px; }
    pre { white-space: pre-wrap; word-break: break-word; background: #0a1328; border-radius: 12px; padding: 16px; border: 1px solid #223055; line-height: 1.6; }
  </style>
</head>
<body>
  <div class="card">
    <h1>NanoK</h1>
    <div class="sub">Cloudflare Worker Subscription</div>
    <pre>${escapeHtml(text)}</pre>
  </div>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// KV operations
// ---------------------------------------------------------------------------

async function readProfile(env) {
  if (!env.SUB_STORE) throw new Error('missing SUB_STORE binding');
  const profile = await env.SUB_STORE.get(PROFILE_KEY, { type: 'json' });
  if (!profile) throw new Error('missing required profile');
  return profile;
}

function fingerprints(profile) {
  return {
    hy2Password: shortFingerprint(profile.hy2?.password),
    tuicUuid: shortFingerprint(profile.tuic?.uuid),
    tuicPassword: shortFingerprint(profile.tuic?.password),
    realityUuid: shortFingerprint(profile.reality?.uuid),
    realityPublicKey: shortFingerprint(profile.reality?.publicKey),
    realityShortId: shortFingerprint(profile.reality?.shortId),
    trojanPassword: shortFingerprint(profile.trojan?.password),
  };
}

async function updateProfile(request, env, cfg) {
  let body;
  try {
    body = await request.json();
    body.updatedAt = cleanString(body.updatedAt || new Date().toISOString(), 'updatedAt');
    const cleaned = validateProfile(body, cfg);
    await env.SUB_STORE.put(PROFILE_KEY, JSON.stringify(cleaned));
    return new Response(JSON.stringify({
      ok: true,
      updatedAt: cleaned.updatedAt,
      fingerprints: fingerprints(cleaned),
    }), { headers: responseHeaders('application/json; charset=utf-8') });
  } catch {
    return errorResponse(400, 'invalid profile');
  }
}

// ---------------------------------------------------------------------------
// Request handler
// ---------------------------------------------------------------------------

export default {
  async fetch(request, env) {
    let cfg;
    let url;
    try {
      cfg = getConfig(env || {});
      url = new URL(request.url);
    } catch {
      return errorResponse(500, 'worker configuration error');
    }

    // Root — HTML status page
    if (request.method === 'GET' && url.pathname === '/') {
      return new Response(buildHomeHtml(cfg, url.origin), {
        headers: responseHeaders('text/html; charset=utf-8'),
      });
    }

    // Subscription endpoint
    if (request.method === 'GET' && url.pathname === cfg.subPath) {
      if (!checkSubToken(url, cfg)) return notFound();
      try {
        const profile = await readProfile(env);
        return new Response(buildSubYaml(profile, cfg), { headers: responseHeaders() });
      } catch {
        return errorResponse(500, 'missing required profile');
      }
    }

    // Edge proxy passthrough
    if (request.method === 'GET' && url.pathname === cfg.edgePath) {
      if (!checkSubToken(url, cfg)) return notFound();
      const upstream = await fetch(cfg.edgeSubUrl, {
        headers: {
          'user-agent': request.headers.get('user-agent') || 'Clash/Mihomo',
          accept: request.headers.get('accept') || '*/*',
        },
        redirect: 'follow',
      });
      return new Response(upstream.body, {
        status: upstream.status,
        headers: responseHeaders(upstream.headers.get('content-type') || 'text/plain; charset=utf-8'),
      });
    }

    // Admin — read current profile
    if (request.method === 'GET' && url.pathname === cfg.adminCurrentPath) {
      if (!checkAdminToken(request, cfg)) return notFound();
      try {
        const profile = validateProfile(await readProfile(env), cfg);
        return new Response(JSON.stringify(profile, null, 2), {
          headers: responseHeaders('application/json; charset=utf-8'),
        });
      } catch {
        return errorResponse(500, 'missing required profile');
      }
    }

    // Admin — update profile
    if (request.method === 'POST' && url.pathname === cfg.adminPath) {
      if (!checkAdminToken(request, cfg)) return notFound();
      return updateProfile(request, env, cfg);
    }

    return notFound();
  },
};
