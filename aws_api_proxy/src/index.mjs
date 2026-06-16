import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';

const secretsClient = new SecretsManagerClient({});
let cachedConfig;

const jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

export async function handler(event) {
  const method = event.requestContext?.http?.method ?? event.httpMethod ?? 'GET';
  const rawPath = normalizePath(event.rawPath ?? event.path ?? '/');

  if (method === 'OPTIONS') {
    return respond(204, null);
  }

  try {
    const config = await loadConfig();
    const user = event.requestContext?.authorizer?.jwt?.claims?.sub ?? 'unknown';
    console.log(JSON.stringify({ route: rawPath, method, user }));

    if (rawPath === '/v1/llm/chat/completions' && method === 'POST') {
      return proxyLlm(event, config);
    }
    if (rawPath === '/v1/amap/regeo' && method === 'GET') {
      return proxyAmapRegeo(event, config);
    }
    if (rawPath === '/v1/amap/place/text' && method === 'GET') {
      return proxyAmapPlaceText(event, config);
    }
    if (rawPath === '/v1/replicate/predictions' && method === 'POST') {
      return proxyReplicateCreate(event, config);
    }
    const replicateMatch = rawPath.match(/^\/v1\/replicate\/predictions\/([A-Za-z0-9_-]+)$/);
    if (replicateMatch && method === 'GET') {
      return proxyReplicateGet(replicateMatch[1], config);
    }

    return respond(404, { error: 'route_not_found' });
  } catch (error) {
    console.error('proxy_error', sanitizeError(error));
    const status = Number.isInteger(error.statusCode) ? error.statusCode : 500;
    return respond(status, {
      error: status >= 500 ? 'upstream_proxy_error' : 'bad_request',
      message: status >= 500 ? undefined : error.message,
    });
  }
}

async function proxyLlm(event, config) {
  requireConfig(config, ['LLM_BASE_URL', 'LLM_API_KEY']);
  const body = readJsonBody(event);
  if (!body.model && config.LLM_MODEL) {
    body.model = config.LLM_MODEL;
  }
  if (!Array.isArray(body.messages) && !Array.isArray(body.input)) {
    throw httpError(400, 'LLM request must contain messages or input');
  }

  const response = await fetch(`${trimRight(config.LLM_BASE_URL, '/')}/chat/completions`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${config.LLM_API_KEY}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  return forwardJsonResponse(response);
}

async function proxyAmapRegeo(event, config) {
  requireConfig(config, ['AMAP_WEB_KEY']);
  const query = event.queryStringParameters ?? {};
  const location = requiredQuery(query, 'location');
  const uri = new URL('https://restapi.amap.com/v3/geocode/regeo');
  uri.searchParams.set('key', config.AMAP_WEB_KEY);
  uri.searchParams.set('location', location);
  uri.searchParams.set('extensions', query.extensions ?? 'base');
  uri.searchParams.set('coordsys', query.coordsys ?? 'gps');

  const response = await fetch(uri);
  return forwardJsonResponse(response);
}

async function proxyAmapPlaceText(event, config) {
  requireConfig(config, ['AMAP_WEB_KEY']);
  const query = event.queryStringParameters ?? {};
  const keywords = requiredQuery(query, 'keywords');
  const uri = new URL('https://restapi.amap.com/v3/place/text');
  uri.searchParams.set('key', config.AMAP_WEB_KEY);
  uri.searchParams.set('keywords', keywords);
  if (query.city) {
    uri.searchParams.set('city', query.city);
    uri.searchParams.set('citylimit', query.citylimit ?? 'true');
  }
  uri.searchParams.set('offset', query.offset ?? '5');
  uri.searchParams.set('page', query.page ?? '1');
  uri.searchParams.set('extensions', query.extensions ?? 'base');

  const response = await fetch(uri);
  return forwardJsonResponse(response);
}

async function proxyReplicateCreate(event, config) {
  requireConfig(config, ['REPLICATE_API_TOKEN']);
  const body = readJsonBody(event);
  if (!body.version || !body.input) {
    throw httpError(400, 'Replicate request must contain version and input');
  }
  const response = await fetch('https://api.replicate.com/v1/predictions', {
    method: 'POST',
    headers: {
      authorization: `Token ${config.REPLICATE_API_TOKEN}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  return forwardJsonResponse(response, response.status === 201 ? 201 : response.status);
}

async function proxyReplicateGet(id, config) {
  requireConfig(config, ['REPLICATE_API_TOKEN']);
  const response = await fetch(`https://api.replicate.com/v1/predictions/${encodeURIComponent(id)}`, {
    headers: {
      authorization: `Token ${config.REPLICATE_API_TOKEN}`,
    },
  });
  return forwardJsonResponse(response);
}

async function loadConfig() {
  if (cachedConfig) return cachedConfig;

  let secretConfig = {};
  const secretId = process.env.SECRET_ID?.trim();
  if (secretId) {
    const result = await secretsClient.send(new GetSecretValueCommand({ SecretId: secretId }));
    if (result.SecretString) {
      secretConfig = JSON.parse(result.SecretString);
    }
  }

  cachedConfig = {
    ...secretConfig,
    ...envConfig([
      'LLM_BASE_URL',
      'LLM_API_KEY',
      'LLM_MODEL',
      'AMAP_WEB_KEY',
      'REPLICATE_API_TOKEN',
      'ALLOWED_ORIGINS',
    ]),
  };
  return cachedConfig;
}

function envConfig(keys) {
  const values = {};
  for (const key of keys) {
    const value = process.env[key];
    if (value !== undefined && value !== '') {
      values[key] = value;
    }
  }
  return values;
}

function readJsonBody(event) {
  const raw = event.body ?? '{}';
  const text = event.isBase64Encoded ? Buffer.from(raw, 'base64').toString('utf8') : raw;
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('JSON body must be an object');
    }
    return parsed;
  } catch (error) {
    throw httpError(400, `Invalid JSON body: ${error.message}`);
  }
}

async function forwardJsonResponse(response, statusOverride) {
  const text = await response.text();
  const status = statusOverride ?? response.status;
  return {
    statusCode: status,
    headers: corsHeaders({ ...jsonHeaders }),
    body: text || '{}',
  };
}

function respond(statusCode, body) {
  return {
    statusCode,
    headers: corsHeaders(body == null ? {} : jsonHeaders),
    body: body == null ? '' : JSON.stringify(body),
  };
}

function corsHeaders(headers) {
  return {
    ...headers,
    'access-control-allow-origin': process.env.ALLOWED_ORIGINS || '*',
    'access-control-allow-headers': 'authorization,content-type',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
  };
}

function normalizePath(path) {
  if (!path || path === '/') return '/';
  return path.endsWith('/') && path.length > 1 ? path.slice(0, -1) : path;
}

function requiredQuery(query, key) {
  const value = query[key]?.trim();
  if (!value) throw httpError(400, `Missing query parameter: ${key}`);
  return value;
}

function requireConfig(config, keys) {
  const missing = keys.filter((key) => !config[key]);
  if (missing.length > 0) {
    throw httpError(500, `Missing server config: ${missing.join(', ')}`);
  }
}

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function trimRight(value, suffix) {
  return value.endsWith(suffix) ? value.slice(0, -suffix.length) : value;
}

function sanitizeError(error) {
  return {
    name: error?.name,
    message: error?.message,
    statusCode: error?.statusCode,
  };
}
