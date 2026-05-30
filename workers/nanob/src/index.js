// NanoB — Optional Aggregation Subscription Worker
//
// Merges nanok primary subscription with optional edgetunnel backup nodes.
//
// Key design:
//   - edgetunnel is OPTIONAL. Set EDGE_HOST + EDGETUNNEL_EXPORT_TOKEN to enable.
//   - edgetunnel fetch failure NEVER blocks the primary subscription.
//   - Geo labels from shared/geo.js enrich edgetunnel backup node names.
//   - All config comes from env vars — no source code editing needed.
//
// No production tokens, hosts, or IDs are included.

import { loadGeoMap, geoLabel } from '../../shared/geo.js';

// ---------------------------------------------------------------------------
// Configuration — all from env vars
// ---------------------------------------------------------------------------

function normalizePath(value, fallback) {
  const raw = typeof value === 'string' && value.trim() ? value.trim() : fallback;
  return raw.startsWith('/') ? raw : `/${raw}`;
}

function cleanHost(value) {
  // Accept "host.example.com" or "https://host.example.com" — return host only
  const text = String(value || '').trim();
  if (!text) return '';
  return text.replace(/^https?:\/\//, '').replace(/\/+$/, '');
}

function getConfig(env) {
  const nanokOrigin = typeof env.NANOK_ORIGIN === 'string' ? env.NANOK_ORIGIN.trim() : '';
  const nanobToken = typeof env.NANOB_TOKEN === 'string' ? env.NANOB_TOKEN : '';
  const nanokSubToken = typeof env.NANOK_SUB_TOKEN === 'string' ? env.NANOK_SUB_TOKEN : '';

  const nanokSubPath = normalizePath(env.NANOK_SUB_PATH, '/jb');
  const nanobPath = normalizePath(env.NANOB_PATH, '/jb');
  const edgeHost = cleanHost(env.EDGE_HOST);
  const edgeSubPath = typeof env.EDGE_SUB_PATH === 'string' && env.EDGE_SUB_PATH.trim()
    ? env.EDGE_SUB_PATH.trim()
    : '/sub?target=clash';
  const edgetunnelExportToken = typeof env.EDGETUNNEL_EXPORT_TOKEN === 'string'
    ? env.EDGETUNNEL_EXPORT_TOKEN
    : '';

  return {
    nanokOrigin,
    nanokSubPath,
    nanobPath,
    nanobToken,
    nanokSubToken,
    edgeHost,
    edgeSubPath,
    edgetunnelExportToken,
  };
}

function isEdgetunnelConfigured(cfg) {
  return Boolean(cfg.edgeHost && cfg.edgetunnelExportToken);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

function relayHeaders(request) {
  return {
    'user-agent': request.headers.get('user-agent') || 'Clash/Mihomo',
    accept: request.headers.get('accept') || '*/*',
  };
}

// ---------------------------------------------------------------------------
// YAML section parsing (for merging primary + edge subscriptions)
// ---------------------------------------------------------------------------

function nextTopLevel(lines, start) {
  for (let i = start; i < lines.length; i += 1) {
    if (/^[A-Za-z0-9_-]+:\s*(?:#.*)?$/.test(lines[i])) return i;
  }
  return lines.length;
}

function yamlSection(yaml, label) {
  const lines = String(yaml || '')
    .replace(/^﻿/, '')
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
    try { return JSON.parse(text); } catch { return text.slice(1, -1); }
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

// ---------------------------------------------------------------------------
// Request handler
// ---------------------------------------------------------------------------

export default {
  async fetch(request, env, ctx) {
    const cfg = getConfig(env);
    const url = new URL(request.url);

    // --- Validate config ---
    if (!cfg.nanokOrigin) {
      return errorResponse(500, 'NANOK_ORIGIN is not configured');
    }
    if (!cfg.nanobToken) {
      return errorResponse(500, 'NANOB_TOKEN is not configured');
    }
    if (!cfg.nanokSubToken) {
      return errorResponse(500, 'NANOK_SUB_TOKEN is not configured');
    }

    // --- Route matching ---
    if (request.method !== 'GET' || url.pathname !== cfg.nanobPath) {
      return errorResponse(404, 'Not Found');
    }

    // --- Token check ---
    if (url.searchParams.get('token') !== cfg.nanobToken) {
      return errorResponse(404, 'Not Found');
    }

    // --- Fetch primary subscription (always required) ---
    const primaryUrl = new URL(cfg.nanokSubPath, cfg.nanokOrigin);
    primaryUrl.searchParams.set('token', cfg.nanokSubToken);

    const requestHeaders = relayHeaders(request);

    let primaryResponse;
    try {
      primaryResponse = await fetch(primaryUrl, { headers: requestHeaders, redirect: 'follow' });
    } catch (fetchError) {
      return errorResponse(502, 'primary fetch failed');
    }

    if (!primaryResponse.ok) {
      return errorResponse(primaryResponse.status, 'primary subscription returned error');
    }

    // --- Read primary text early, before any body consumption ---
    const primaryText = await primaryResponse.text();

    // --- If edgetunnel is not configured, return primary only ---
    if (!isEdgetunnelConfigured(cfg)) {
      return new Response(primaryText, { headers: responseHeaders() });
    }

    // --- Try fetching edgetunnel, but never block primary on failure ---
    let edgeResponse;
    try {
      const edgeRequest = new Request(`https://${cfg.edgeHost}${cfg.edgeSubPath}`, {
        headers: {
          ...requestHeaders,
          'x-nanob-token': cfg.edgetunnelExportToken,
        },
      });
      edgeResponse = await fetch(edgeRequest, { redirect: 'follow' });
    } catch {
      // Edgetunnel fetch failed — return primary only
      return new Response(primaryText, { headers: responseHeaders() });
    }

    if (!edgeResponse.ok) {
      // Edgetunnel returned error — return primary only
      return new Response(primaryText, { headers: responseHeaders() });
    }

    // --- Try merging, but fall back to primary on any error ---
    try {
      const merged = await mergeSubscriptions(
        primaryText,
        await edgeResponse.text(),
        env,
        ctx,
      );
      return new Response(merged, { headers: responseHeaders() });
    } catch {
      // Merge failed — return primary only
      return new Response(primaryText, { headers: responseHeaders() });
    }
  },
};
