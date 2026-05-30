const EDGE_SUB_URL = 'https://edge-subscription.example.com/edge-sub';
const PROFILE_KEY = 'profile:main';

const DEFAULT_SUB_PATH = '/sub-kai';
const DEFAULT_EDGE_PATH = '/edge';
const DEFAULT_ADMIN_PATH = '/admin/update';
const DEFAULT_ADMIN_CURRENT_PATH = '/admin/current';
const DEFAULT_POETRY_NODE_NAME = 'example notice node';
const DEFAULT_RECOMMEND_NODE_NAME = 'example recommendation node';

// Fixed node example. Replace placeholders privately before deploy.
// Do not commit real UUIDs, public keys, short IDs, passwords, or private hosts.
const FIXED_BEIJING_REALITY = {
  name: 'beijing-fixed-reality-example',
  server: '203.0.113.10',
  port: 443,
  uuid: '00000000-0000-0000-0000-000000000000',
  servername: 'www.example.com',
  publicKey: 'REPLACE_WITH_REALITY_PUBLIC_KEY',
  shortId: 'REPLACE_WITH_REALITY_SHORT_ID',
};

function normalizePath(path, fallback) {
  const value = typeof path === 'string' ? path.trim() : '';
  const fallbackValue = typeof fallback === 'string' && fallback ? fallback : '/';
  const normalized = value || fallbackValue;
  return normalized.startsWith('/') ? normalized : `/${normalized}`;
}

function getConfig(env) {
  const subPath = normalizePath(env?.SUB_PATH, DEFAULT_SUB_PATH);
  const edgePath = normalizePath(env?.EDGE_PATH, DEFAULT_EDGE_PATH);
  const adminPath = normalizePath(env?.ADMIN_PATH, DEFAULT_ADMIN_PATH);
  const adminCurrentPath = normalizePath(env?.ADMIN_CURRENT_PATH, DEFAULT_ADMIN_CURRENT_PATH);
  const paths = [subPath, edgePath, adminPath, adminCurrentPath];

  return {
    routesValid: paths.every((path) => path !== '/') && new Set(paths).size === paths.length,
    subPath,
    edgePath,
    adminPath,
    adminCurrentPath,
    subToken: typeof env?.SUB_TOKEN === 'string' ? env.SUB_TOKEN : '',
    adminToken: typeof env?.ADMIN_TOKEN === 'string' ? env.ADMIN_TOKEN : '',
    poetryNodeName:
      typeof env?.POETRY_NODE_NAME === 'string' && env.POETRY_NODE_NAME
        ? env.POETRY_NODE_NAME
        : '',
    recommendNodeName:
      typeof env?.RECOMMEND_NODE_NAME === 'string' && env.RECOMMEND_NODE_NAME
        ? env.RECOMMEND_NODE_NAME
        : '',
  };
}

function responseHeaders(contentType = 'text/plain; charset=utf-8') {
  return {
    'content-type': contentType,
    'cache-control': 'no-store, no-cache, must-revalidate, max-age=0',
    'x-robots-tag': 'noindex, nofollow',
  };
}

function notFound() {
  return new Response('Not Found', {
    status: 404,
    headers: {
      'content-type': 'text/plain; charset=utf-8',
      'cache-control': 'no-store',
      'x-robots-tag': 'noindex, nofollow',
    },
  });
}

function genericError(message = 'missing required profile', status = 500) {
  return new Response(message, { status, headers: responseHeaders() });
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: responseHeaders('application/json; charset=utf-8'),
  });
}

function checkToken(url, cfg) {
  return !cfg.subToken || url.searchParams.get('token') === cfg.subToken;
}

function checkAdmin(request, cfg) {
  return !!cfg.adminToken && request.headers.get('authorization') === `Bearer ${cfg.adminToken}`;
}

function hasYamlControlChars(str) {
  const text = String(str);
  for (const char of text) {
    const code = char.codePointAt(0);
    if (
      (code >= 0x00 && code <= 0x08)
      || code === 0x0b
      || code === 0x0c
      || (code >= 0x0e && code <= 0x1f)
      || code === 0x7f
      || (code >= 0x80 && code <= 0x9f)
    ) {
      return true;
    }
  }
  return false;
}

function cleanString(value, fieldName) {
  if (value === undefined || value === null) {
    throw new Error(`invalid string in ${fieldName}`);
  }

  const cleaned = String(value).normalize('NFC').trim();
  if (hasYamlControlChars(cleaned)) {
    throw new Error(`invalid control character in ${fieldName}`);
  }
  return cleaned;
}

function yamlQuote(value, fieldName) {
  return JSON.stringify(cleanString(value, fieldName));
}

function assertValidYamlText(yaml) {
  if (hasYamlControlChars(yaml)) {
    throw new Error('generated yaml contains invalid characters');
  }
  return yaml;
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function hasText(value) {
  return typeof value === 'string' && value.length > 0;
}

function hasPort(value) {
  return Number.isInteger(value) && value > 0 && value <= 65535;
}

function mask(value) {
  const text = String(value || '');
  if (text.length <= 12) return '***';
  return `${text.slice(0, 6)}...${text.slice(-6)}`;
}

function validateProfile(profile) {
  if (!isObject(profile)) throw new Error('invalid profile');

  const { hy2, tuic, reality, trojan, extraNodes } = profile;
  if (!isObject(hy2) || !isObject(tuic) || !isObject(reality) || !isObject(trojan) || !isObject(extraNodes)) {
    throw new Error('invalid profile');
  }
  if (!hasPort(hy2.port) || !hasPort(tuic.port) || !hasPort(reality.port) || !hasPort(trojan.port)) {
    throw new Error('invalid profile');
  }

  const cleaned = {
    updatedAt: hasText(profile.updatedAt)
      ? cleanString(profile.updatedAt, 'updatedAt')
      : new Date().toISOString(),
    hy2: {
      name: cleanString(hy2.name, 'hy2.name'),
      server: cleanString(hy2.server, 'hy2.server'),
      port: hy2.port,
      password: cleanString(hy2.password, 'hy2.password'),
      sni: cleanString(hy2.sni, 'hy2.sni'),
    },
    tuic: {
      name: cleanString(tuic.name, 'tuic.name'),
      server: cleanString(tuic.server, 'tuic.server'),
      port: tuic.port,
      uuid: cleanString(tuic.uuid, 'tuic.uuid'),
      password: cleanString(tuic.password, 'tuic.password'),
      sni: cleanString(tuic.sni, 'tuic.sni'),
    },
    reality: {
      name: cleanString(reality.name, 'reality.name'),
      server: cleanString(reality.server, 'reality.server'),
      port: reality.port,
      uuid: cleanString(reality.uuid, 'reality.uuid'),
      servername: cleanString(reality.servername, 'reality.servername'),
      publicKey: cleanString(reality.publicKey, 'reality.publicKey'),
      shortId: cleanString(reality.shortId, 'reality.shortId'),
    },
    trojan: {
      name: cleanString(trojan.name, 'trojan.name'),
      server: cleanString(trojan.server, 'trojan.server'),
      port: trojan.port,
      password: cleanString(trojan.password, 'trojan.password'),
      sni: cleanString(trojan.sni, 'trojan.sni'),
    },
    extraNodes: {
      poetryNodeName: cleanString(extraNodes.poetryNodeName, 'extraNodes.poetryNodeName'),
      recommendNodeName: cleanString(extraNodes.recommendNodeName, 'extraNodes.recommendNodeName'),
    },
  };

  for (const section of ['hy2', 'tuic', 'reality', 'trojan', 'extraNodes']) {
    for (const [key, value] of Object.entries(cleaned[section])) {
      if (key !== 'port' && !hasText(value)) throw new Error('invalid profile');
    }
  }
  return cleaned;
}

function normalizeProfile(input) {
  return {
    updatedAt: new Date().toISOString(),
    hy2: input.hy2,
    tuic: input.tuic,
    reality: input.reality,
    trojan: input.trojan,
    extraNodes: isObject(input.extraNodes) ? input.extraNodes : {},
  };
}

async function readProfile(env) {
  if (!env?.SUB_STORE) return null;
  return validateProfile(await env.SUB_STORE.get(PROFILE_KEY, 'json'));
}

function displayNames(profile, cfg) {
  return {
    poetryNodeName:
      cfg.poetryNodeName
      || profile.extraNodes?.poetryNodeName
      || DEFAULT_POETRY_NODE_NAME,
    recommendNodeName:
      cfg.recommendNodeName
      || profile.extraNodes?.recommendNodeName
      || DEFAULT_RECOMMEND_NODE_NAME,
  };
}

function buildSubYaml(profile, cfg) {
  const cleanedProfile = validateProfile(profile);
  const { hy2, tuic, reality, trojan } = cleanedProfile;
  const beijingReality = {
    name: cleanString(FIXED_BEIJING_REALITY.name, 'fixedReality.name'),
    server: cleanString(FIXED_BEIJING_REALITY.server, 'fixedReality.server'),
    port: FIXED_BEIJING_REALITY.port,
    uuid: cleanString(FIXED_BEIJING_REALITY.uuid, 'fixedReality.uuid'),
    servername: cleanString(FIXED_BEIJING_REALITY.servername, 'fixedReality.servername'),
    publicKey: cleanString(FIXED_BEIJING_REALITY.publicKey, 'fixedReality.publicKey'),
    shortId: cleanString(FIXED_BEIJING_REALITY.shortId, 'fixedReality.shortId'),
  };
  const names = displayNames(cleanedProfile, cfg);

  return assertValidYamlText(`
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
unified-delay: true

proxies:
  - name: ${yamlQuote(hy2.name, 'hy2.name')}
    type: hysteria2
    server: ${yamlQuote(hy2.server, 'hy2.server')}
    port: ${hy2.port}
    password: ${yamlQuote(hy2.password, 'hy2.password')}
    sni: ${yamlQuote(hy2.sni, 'hy2.sni')}
    skip-cert-verify: false
    udp: true

  - name: ${yamlQuote(tuic.name, 'tuic.name')}
    type: tuic
    server: ${yamlQuote(tuic.server, 'tuic.server')}
    port: ${tuic.port}
    uuid: ${yamlQuote(tuic.uuid, 'tuic.uuid')}
    password: ${yamlQuote(tuic.password, 'tuic.password')}
    sni: ${yamlQuote(tuic.sni, 'tuic.sni')}
    skip-cert-verify: false
    udp: true
    alpn:
      - h3
    congestion-controller: bbr
    udp-relay-mode: native

  - name: ${yamlQuote(reality.name, 'reality.name')}
    type: vless
    server: ${yamlQuote(reality.server, 'reality.server')}
    port: ${reality.port}
    uuid: ${yamlQuote(reality.uuid, 'reality.uuid')}
    encryption: none
    network: tcp
    tls: true
    udp: true
    servername: ${yamlQuote(reality.servername, 'reality.servername')}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${yamlQuote(reality.publicKey, 'reality.publicKey')}
      short-id: ${yamlQuote(reality.shortId, 'reality.shortId')}
    flow: xtls-rprx-vision

  - name: ${yamlQuote(trojan.name, 'trojan.name')}
    type: trojan
    server: ${yamlQuote(trojan.server, 'trojan.server')}
    port: ${trojan.port}
    password: ${yamlQuote(trojan.password, 'trojan.password')}
    sni: ${yamlQuote(trojan.sni, 'trojan.sni')}
    skip-cert-verify: false
    udp: true

  - name: ${yamlQuote(beijingReality.name, 'fixedReality.name')}
    type: vless
    server: ${yamlQuote(beijingReality.server, 'fixedReality.server')}
    port: ${beijingReality.port}
    uuid: ${yamlQuote(beijingReality.uuid, 'fixedReality.uuid')}
    encryption: none
    network: tcp
    tls: true
    udp: true
    servername: ${yamlQuote(beijingReality.servername, 'fixedReality.servername')}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${yamlQuote(beijingReality.publicKey, 'fixedReality.publicKey')}
      short-id: ${yamlQuote(beijingReality.shortId, 'fixedReality.shortId')}
    flow: xtls-rprx-vision

  - name: ${yamlQuote(names.poetryNodeName, 'extraNodes.poetryNodeName')}
    type: http
    server: "127.0.0.0"
    port: 8888
    udp: false

  - name: ${yamlQuote(names.recommendNodeName, 'extraNodes.recommendNodeName')}
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
`.trim());
}

function homeText(cfg, origin) {
  return [
    'Subscription Worker Online',
    '',
    'Subscription URL:',
    `${origin}${cfg.subPath}?token=*****`,
  ].join('\n');
}

function escapeHtml(str) {
  return String(str)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function adminResult(profile) {
  return {
    ok: true,
    updatedAt: profile.updatedAt,
    fingerprints: {
      hy2Password: mask(profile.hy2.password),
      tuicUuid: mask(profile.tuic.uuid),
      realityUuid: mask(profile.reality.uuid),
      realityPublicKey: mask(profile.reality.publicKey),
      trojanPassword: mask(profile.trojan.password),
    },
  };
}

export default {
  async fetch(request, env) {
    const cfg = getConfig(env);
    const url = new URL(request.url);

    if (url.pathname === '/') {
      return new Response(`<pre>${escapeHtml(homeText(cfg, url.origin))}</pre>`, {
        headers: {
          'content-type': 'text/html; charset=utf-8',
          'cache-control': 'no-store',
          'x-robots-tag': 'noindex, nofollow',
        },
      });
    }

    if (url.pathname === cfg.adminCurrentPath) {
      if (!cfg.routesValid || !checkAdmin(request, cfg)) return notFound();
      const raw = await env.SUB_STORE?.get(PROFILE_KEY);
      if (!raw) return genericError();
      return new Response(raw, { headers: responseHeaders('application/json; charset=utf-8') });
    }

    if (url.pathname === cfg.adminPath) {
      if (!cfg.routesValid || request.method !== 'POST' || !checkAdmin(request, cfg)) return notFound();

      let body;
      try {
        body = await request.json();
      } catch {
        return genericError();
      }

      let profile;
      try {
        profile = validateProfile(normalizeProfile(body));
      } catch {
        return genericError('invalid profile', 400);
      }

      await env.SUB_STORE.put(PROFILE_KEY, JSON.stringify(profile));
      return jsonResponse(adminResult(profile));
    }

    if (url.pathname === cfg.edgePath) {
      if (!cfg.routesValid || !checkToken(url, cfg)) return notFound();
      const upstream = await fetch(EDGE_SUB_URL, {
        headers: {
          'user-agent': request.headers.get('user-agent') || 'Mozilla/5.0',
          accept: request.headers.get('accept') || '*/*',
        },
        redirect: 'follow',
      });
      return new Response(upstream.body, {
        status: upstream.status,
        headers: responseHeaders(upstream.headers.get('content-type') || 'text/plain; charset=utf-8'),
      });
    }

    if (url.pathname === cfg.subPath) {
      if (!cfg.routesValid || !checkToken(url, cfg)) return notFound();

      let yaml;
      try {
        const profile = await readProfile(env);
        if (!profile) return genericError();
        yaml = buildSubYaml(profile, cfg);
      } catch (error) {
        if (String(error?.message || '') === 'generated yaml contains invalid characters') {
          return genericError('generated yaml contains invalid characters');
        }
        return genericError();
      }

      return new Response(yaml, { headers: responseHeaders() });
    }

    return notFound();
  },
};
