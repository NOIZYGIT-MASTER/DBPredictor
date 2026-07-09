const MAX_LIMIT = 500;
const DEFAULT_LIMIT = 50;
const DEFAULT_MAX_SYNC_BYTES = 1024 * 1024 * 1024;

export default {
  async fetch(request, env) {
    const requestId = request.headers.get('cf-ray') || globalThis.crypto.randomUUID();

    try {
      const authError = validateAuth(request, env, requestId);
      if (authError) {
        return authError;
      }

      const url = new URL(request.url);
      const path = url.pathname;

      if (request.method === 'POST' && path === '/api/assets/register') {
        return await registerAsset(request, env, requestId);
      }

      if (request.method === 'GET' && path === '/api/assets/search') {
        return await searchAssets(request, env, requestId);
      }

      if (request.method === 'PUT' && path === '/api/assets/sync') {
        return await syncAsset(request, env, requestId);
      }

      return errorResponse(requestId, 404, 'NOT_FOUND', 'Route not found.');
    } catch (error) {
      return errorResponse(
        requestId,
        500,
        'INTERNAL_ERROR',
        error instanceof Error ? error.message : 'Unknown worker error.'
      );
    }
  },
};

function validateAuth(request, env, requestId) {
  if (!env.API_AUTH_TOKEN) {
    return errorResponse(requestId, 500, 'AUTH_NOT_CONFIGURED', 'API_AUTH_TOKEN is not configured.');
  }

  const authHeader = request.headers.get('authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return errorResponse(requestId, 401, 'UNAUTHORIZED', 'Missing bearer token.');
  }

  const token = authHeader.slice(7);
  if (token !== env.API_AUTH_TOKEN) {
    return errorResponse(requestId, 403, 'FORBIDDEN', 'Invalid bearer token.');
  }

  return null;
}

async function registerAsset(request, env, requestId) {
  const body = await readJsonBody(request, requestId);
  if (body.errorResponse) {
    return body.errorResponse;
  }

  const input = body.value;
  const validation = validateRegisterInput(input);
  if (validation) {
    return errorResponse(requestId, 400, 'VALIDATION_ERROR', validation);
  }

  await env.DB.prepare(
    `INSERT INTO hvs_creator_assets
      (public_id, asset_name, app_category, app_name, file_type, r2_object_key, local_path_blueprint)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
     ON CONFLICT(public_id) DO UPDATE SET
       asset_name = excluded.asset_name,
       app_category = excluded.app_category,
       app_name = excluded.app_name,
       file_type = excluded.file_type,
       r2_object_key = excluded.r2_object_key,
       local_path_blueprint = excluded.local_path_blueprint`
  )
    .bind(
      input.public_id,
      input.asset_name,
      input.app_category,
      input.app_name,
      input.file_type,
      optionalString(input.r2_object_key),
      optionalString(input.local_path_blueprint)
    )
    .run();

  if (optionalString(input.content_sha256) || Number.isFinite(input.size_bytes)) {
    await env.DB.prepare(
      `INSERT INTO hvs_creator_asset_integrity
        (public_id, content_sha256, size_bytes, last_sync_status, last_synced_at)
       VALUES (?1, ?2, ?3, 'registered', CURRENT_TIMESTAMP)
       ON CONFLICT(public_id) DO UPDATE SET
         content_sha256 = COALESCE(excluded.content_sha256, hvs_creator_asset_integrity.content_sha256),
         size_bytes = COALESCE(excluded.size_bytes, hvs_creator_asset_integrity.size_bytes),
         last_sync_status = 'registered',
         last_synced_at = CURRENT_TIMESTAMP`
    )
      .bind(
        input.public_id,
        optionalString(input.content_sha256),
        optionalInteger(input.size_bytes)
      )
      .run();
  }

  return okResponse(requestId, {
    public_id: input.public_id,
    status: 'registered',
  });
}

async function searchAssets(request, env, requestId) {
  const url = new URL(request.url);
  const appName = optionalString(url.searchParams.get('app_name'));
  const fileType = optionalString(url.searchParams.get('file_type'));
  const publicId = optionalString(url.searchParams.get('public_id'));
  const limit = normalizeLimit(url.searchParams.get('limit'));
  const offset = normalizeOffset(url.searchParams.get('offset'));

  if (!appName && !fileType && !publicId) {
    return errorResponse(requestId, 400, 'VALIDATION_ERROR', 'Provide app_name, file_type, or public_id.');
  }

  let sql = `
    SELECT
      a.asset_id,
      a.public_id,
      a.asset_name,
      a.app_category,
      a.app_name,
      a.file_type,
      a.r2_object_key,
      a.local_path_blueprint,
      a.created_at,
      a.updated_at,
      i.content_sha256,
      i.size_bytes,
      i.last_sync_status,
      i.last_synced_at
    FROM hvs_creator_assets a
    LEFT JOIN hvs_creator_asset_integrity i
      ON i.public_id = a.public_id
    WHERE 1 = 1
  `;
  const binds = [];

  if (publicId) {
    sql += ' AND a.public_id = ?';
    binds.push(publicId);
  }

  if (appName) {
    sql += ' AND a.app_name = ?';
    binds.push(appName);
  }

  if (fileType) {
    sql += ' AND a.file_type = ?';
    binds.push(fileType);
  }

  sql += ' ORDER BY a.updated_at DESC LIMIT ? OFFSET ?';
  binds.push(limit, offset);

  const { results } = await env.DB.prepare(sql).bind(...binds).all();
  return okResponse(requestId, {
    count: results.length,
    limit,
    offset,
    results,
  });
}

async function syncAsset(request, env, requestId) {
  const url = new URL(request.url);
  const publicId = optionalString(url.searchParams.get('public_id'));
  const objectKey = optionalString(url.searchParams.get('object_key'));
  const appName = optionalString(url.searchParams.get('app_name'));
  const appCategory = optionalString(url.searchParams.get('app_category'));
  const assetName = optionalString(url.searchParams.get('asset_name'));
  const fileType = optionalString(url.searchParams.get('file_type'));
  const localPathBlueprint = optionalString(url.searchParams.get('local_path_blueprint'));
  const contentSha256 = optionalString(request.headers.get('x-content-sha256'));
  const contentLength = optionalInteger(request.headers.get('content-length'));
  const maxSyncBytes = optionalInteger(env.MAX_SYNC_BYTES) || DEFAULT_MAX_SYNC_BYTES;

  if (!publicId || !objectKey) {
    return errorResponse(requestId, 400, 'VALIDATION_ERROR', 'public_id and object_key are required.');
  }

  if (!request.body) {
    return errorResponse(requestId, 400, 'VALIDATION_ERROR', 'Request body is required.');
  }

  if (contentLength !== null && contentLength > maxSyncBytes) {
    return errorResponse(
      requestId,
      413,
      'PAYLOAD_TOO_LARGE',
      `Payload exceeds MAX_SYNC_BYTES (${maxSyncBytes}).`
    );
  }

  await env.ASSETS.put(objectKey, request.body, {
    httpMetadata: {
      contentType: request.headers.get('content-type') || 'application/octet-stream',
    },
    customMetadata: {
      public_id: publicId,
      content_sha256: contentSha256 || '',
    },
  });

  await env.DB.prepare(
    `INSERT INTO hvs_creator_assets
      (public_id, asset_name, app_category, app_name, file_type, r2_object_key, local_path_blueprint)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
     ON CONFLICT(public_id) DO UPDATE SET
       r2_object_key = excluded.r2_object_key,
       local_path_blueprint = COALESCE(excluded.local_path_blueprint, hvs_creator_assets.local_path_blueprint),
       asset_name = COALESCE(excluded.asset_name, hvs_creator_assets.asset_name),
       app_category = COALESCE(excluded.app_category, hvs_creator_assets.app_category),
       app_name = COALESCE(excluded.app_name, hvs_creator_assets.app_name),
       file_type = COALESCE(excluded.file_type, hvs_creator_assets.file_type)`
  )
    .bind(
      publicId,
      assetName || objectKey,
      appCategory || 'Uncategorized',
      appName || 'Unknown App',
      fileType || inferFileType(objectKey),
      objectKey,
      localPathBlueprint
    )
    .run();

  await env.DB.prepare(
    `INSERT INTO hvs_creator_asset_integrity
      (public_id, content_sha256, size_bytes, last_sync_status, last_synced_at)
     VALUES (?1, ?2, ?3, 'synced', CURRENT_TIMESTAMP)
     ON CONFLICT(public_id) DO UPDATE SET
       content_sha256 = COALESCE(excluded.content_sha256, hvs_creator_asset_integrity.content_sha256),
       size_bytes = COALESCE(excluded.size_bytes, hvs_creator_asset_integrity.size_bytes),
       last_sync_status = 'synced',
       last_synced_at = CURRENT_TIMESTAMP`
  )
    .bind(publicId, contentSha256, contentLength)
    .run();

  return okResponse(requestId, {
    public_id: publicId,
    object_key: objectKey,
    checksum: contentSha256 || null,
    size_bytes: contentLength,
    status: 'synced',
  });
}

async function readJsonBody(request, requestId) {
  try {
    return { value: await request.json() };
  } catch {
    return {
      errorResponse: errorResponse(requestId, 400, 'INVALID_JSON', 'Request body must be valid JSON.'),
    };
  }
}

function validateRegisterInput(input) {
  const required = ['public_id', 'asset_name', 'app_category', 'app_name', 'file_type'];
  for (const key of required) {
    if (!optionalString(input[key])) {
      return `Missing required field: ${key}`;
    }
  }

  if (optionalString(input.reason) && String(input.reason).length > 1000) {
    return 'reason exceeds 1000 characters.';
  }

  if (String(input.file_type).length > 32) {
    return 'file_type exceeds 32 characters.';
  }

  return null;
}

function inferFileType(objectKey) {
  const index = objectKey.lastIndexOf('.');
  if (index < 0 || index === objectKey.length - 1) {
    return '.bin';
  }

  return objectKey.slice(index).toLowerCase();
}

function optionalString(value) {
  if (value === null || value === undefined) {
    return null;
  }

  const trimmed = String(value).trim();
  return trimmed.length ? trimmed : null;
}

function optionalInteger(value) {
  if (value === null || value === undefined || value === '') {
    return null;
  }

  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return null;
  }

  return Math.trunc(parsed);
}

function normalizeLimit(value) {
  const n = optionalInteger(value);
  if (n === null) {
    return DEFAULT_LIMIT;
  }

  if (n < 1) {
    return 1;
  }

  if (n > MAX_LIMIT) {
    return MAX_LIMIT;
  }

  return n;
}

function normalizeOffset(value) {
  const n = optionalInteger(value);
  if (n === null || n < 0) {
    return 0;
  }

  return n;
}

function okResponse(requestId, data, status = 200) {
  return jsonResponse(
    {
      ok: true,
      request_id: requestId,
      data,
    },
    status
  );
}

function errorResponse(requestId, status, code, message) {
  return jsonResponse(
    {
      ok: false,
      request_id: requestId,
      error: {
        code,
        message,
      },
    },
    status
  );
}

function jsonResponse(payload, status) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}
