<?php
/**
 * Optional LocalLightAI integration for LLC.
 *
 * This file deliberately owns all communication with LocalLight Control. The
 * browser never receives the Control bearer token and never gets a generic
 * localhost proxy. When LLC_LOCALLIGHTAI_MODE is disabled, none of these
 * endpoints are reachable from the UI and the normal LLC code path stays
 * unchanged.
 */

declare(strict_types=1);

// Keep api.php and this integration library deployment-compatible.
// api.php uses this revision marker to report mixed/stale PHP files clearly
// instead of crashing with an undefined-function fatal error.
if (!defined('LLC_LOCALLIGHTAI_LIB_REV')) define('LLC_LOCALLIGHTAI_LIB_REV', 3);

function llc_locallightai_enabled(): bool {
  return defined('LLC_LOCALLIGHTAI_MODE') && (bool)LLC_LOCALLIGHTAI_MODE;
}

function llc_locallightai_admin_only(): bool {
  return !defined('LLC_LOCALLIGHTAI_CONTROL_ADMIN_ONLY') || (bool)LLC_LOCALLIGHTAI_CONTROL_ADMIN_ONLY;
}

function llc_locallightai_can_control(array $u): bool {
  if (!llc_locallightai_enabled()) return false;
  if (!llc_locallightai_admin_only()) return true;
  $role = (string)($u['role'] ?? 'user');
  return $role === 'admin' || $role === 'superadmin';
}

function llc_locallightai_public_state(array $u): array {
  return [
    'enabled' => llc_locallightai_enabled() ? 1 : 0,
    'can_control' => llc_locallightai_can_control($u) ? 1 : 0,
    'control_admin_only' => llc_locallightai_admin_only() ? 1 : 0,
  ];
}

function llc_locallightai_control_base(): string {
  $base = defined('LLC_LOCALLIGHTAI_CONTROL_BASE')
    ? trim((string)LLC_LOCALLIGHTAI_CONTROL_BASE)
    : 'http://127.0.0.1:32180';
  $base = rtrim($base, '/');

  $p = parse_url($base);
  if (!is_array($p) || strtolower((string)($p['scheme'] ?? '')) !== 'http') {
    throw new RuntimeException('LocalLight Control must use an http:// loopback URL.');
  }
  $host = strtolower((string)($p['host'] ?? ''));
  if (!in_array($host, ['127.0.0.1', 'localhost', '::1'], true)) {
    throw new RuntimeException('LocalLight Control must be bound to loopback.');
  }
  $path = (string)($p['path'] ?? '');
  if (($path !== '' && $path !== '/') || isset($p['user']) || isset($p['pass']) || isset($p['query']) || isset($p['fragment'])) {
    throw new RuntimeException('LocalLight Control base URL must contain only scheme, loopback host and port.');
  }
  return $base;
}

function llc_locallightai_control_token(): string {
  return defined('LLC_LOCALLIGHTAI_CONTROL_TOKEN')
    ? (string)LLC_LOCALLIGHTAI_CONTROL_TOKEN
    : 'locallight-local-control';
}

function llc_locallightai_timeout_ms(): int {
  $n = defined('LLC_LOCALLIGHTAI_CONTROL_TIMEOUT_MS')
    ? (int)LLC_LOCALLIGHTAI_CONTROL_TIMEOUT_MS
    : 5000;
  return max(500, min(60000, $n));
}

function llc_locallightai_require_access(): array {
  if (!llc_locallightai_enabled()) {
    llc_json(['error'=>'LocalLightAI mode is disabled'], 404);
  }
  $db = llc_db();
  $u = llc_require_user($db);
  if (!llc_locallightai_can_control($u)) {
    llc_json(['error'=>'Forbidden'], 403);
  }
  return $u;
}

/**
 * Small, fixed-purpose HTTP client for LocalLight Control.
 * Returns transport metadata without ever exposing the configured bearer token.
 */
function llc_locallightai_control_request(string $method, string $path, ?int $timeoutMs = null, ?array $jsonBody = null): array {
  $method = strtoupper(trim($method));
  if (!in_array($method, ['GET', 'POST'], true)) {
    throw new RuntimeException('Unsupported Control method.');
  }

  $allowedExact = [
    '/api/v1/health',
    '/api/v1/info',
    '/api/v1/config',
    '/api/v1/services',
    '/api/v1/models',
    '/api/v1/models/scan',
    '/api/v1/models/ignored/restore',
    '/api/v1/models/upload/start',
    '/api/v1/models/upload/cancel',
    '/api/v1/models/huggingface/search',
    '/api/v1/models/huggingface/repository',
    '/api/v1/models/huggingface/settings',
    '/api/v1/models/huggingface/download',
    '/api/v1/models/huggingface/download/status',
    '/api/v1/models/huggingface/download/cancel',
  ];
  $allowedAction = preg_match('~^/api/v1/services/(llama|ragd|mcp)/(start|stop|restart)$~', $path) === 1;
  $allowedManagedConfig = preg_match('~^/api/v1/services/(ragd|mcp)/config$~', $path) === 1;
  $allowedArtifact = preg_match('~^/api/v1/models/artifacts/art_[a-z0-9_-]+/(?:profiles|ignore|remove|delete-files)$~i', $path) === 1;
  $allowedProfile = preg_match('~^/api/v1/models/profiles/prf_[a-z0-9_-]+(?:/(?:duplicate|remove))?$~i', $path) === 1;
  if (!in_array($path, $allowedExact, true) && !$allowedAction && !$allowedManagedConfig && !$allowedArtifact && !$allowedProfile) {
    throw new RuntimeException('Unsupported Control endpoint.');
  }

  if ($jsonBody !== null && $method !== 'POST') {
    throw new RuntimeException('Control request body is only supported for POST.');
  }

  $base = llc_locallightai_control_base();
  $token = llc_locallightai_control_token();
  $timeoutMs = $timeoutMs ?? llc_locallightai_timeout_ms();
  $timeoutMs = max(500, min(60000, (int)$timeoutMs));
  $url = $base . $path;

  $headers = ['Accept: application/json', 'Connection: close'];
  if ($token !== '') $headers[] = 'Authorization: Bearer ' . $token;

  $requestBody = '';
  if ($jsonBody !== null) {
    $requestBody = json_encode($jsonBody, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    if (!is_string($requestBody)) throw new RuntimeException('Control request body could not be serialized.');
    $headers[] = 'Content-Type: application/json; charset=utf-8';
  }

  $body = '';
  $status = 0;

  if (function_exists('curl_init')) {
    $ch = curl_init($url);
    curl_setopt_array($ch, [
      CURLOPT_RETURNTRANSFER => true,
      CURLOPT_CUSTOMREQUEST => $method,
      CURLOPT_HTTPHEADER => $headers,
      CURLOPT_CONNECTTIMEOUT_MS => min(1000, $timeoutMs),
      CURLOPT_TIMEOUT_MS => $timeoutMs,
      CURLOPT_NOSIGNAL => true,
    ]);
    if ($method === 'POST') curl_setopt($ch, CURLOPT_POSTFIELDS, $requestBody);
    $raw = curl_exec($ch);
    if ($raw === false) {
      $err = curl_error($ch);
      curl_close($ch);
      return ['ok'=>false, 'status'=>0, 'json'=>null, 'error'=>$err !== '' ? $err : 'Control request failed'];
    }
    $body = (string)$raw;
    $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
  } else {
    $opts = ['http' => [
      'method' => $method,
      'header' => implode("\r\n", $headers) . "\r\n",
      'ignore_errors' => true,
      'timeout' => max(1.0, $timeoutMs / 1000),
      'content' => $method === 'POST' ? $requestBody : null,
    ]];
    $raw = @file_get_contents($url, false, stream_context_create($opts));
    if ($raw === false && empty($http_response_header)) {
      return ['ok'=>false, 'status'=>0, 'json'=>null, 'error'=>'Control request failed'];
    }
    $body = $raw === false ? '' : (string)$raw;
    foreach (($http_response_header ?? []) as $line) {
      if (preg_match('~^HTTP/\S+\s+(\d{3})~', $line, $m)) {
        $status = (int)$m[1];
        break;
      }
    }
  }

  $json = json_decode($body, true);
  if (!is_array($json)) $json = null;

  $result = [
    'ok' => $status >= 200 && $status < 300,
    'status' => $status,
    'json' => $json,
  ];
  if (!$result['ok']) {
    $result['error'] = (string)($json['error'] ?? ($status > 0 ? ('Control HTTP ' . $status) : 'Control request failed'));
  }
  return $result;
}

function llc_locallightai_ini_bytes(string $value): int {
  $v = trim($value);
  if ($v === '') return 0;
  if (preg_match('~^(\\d+)\\s*([KMGTP]?)B?$~i', $v, $m) !== 1) return 0;
  $n = (int)$m[1];
  $unit = strtoupper($m[2] ?? '');
  $pow = [''=>0, 'K'=>1, 'M'=>2, 'G'=>3, 'T'=>4, 'P'=>5][$unit] ?? 0;
  for ($i = 0; $i < $pow; $i++) {
    if ($n > intdiv(PHP_INT_MAX, 1024)) return PHP_INT_MAX;
    $n *= 1024;
  }
  return $n;
}

function llc_locallightai_upload_bridge_chunk_size(int $controlMax): int {
  $controlMax = max(256 * 1024, $controlMax);
  $target = defined('LLC_LOCALLIGHTAI_UPLOAD_CHUNK_BYTES')
    ? (int)LLC_LOCALLIGHTAI_UPLOAD_CHUNK_BYTES
    : 64 * 1024 * 1024;
  $target = max(256 * 1024, min(64 * 1024 * 1024, $target));

  // Raw POST chunks still have to pass PHP/web-server request-body limits.
  // Leave some room below post_max_size instead of selecting its exact edge.
  $postMax = llc_locallightai_ini_bytes((string)ini_get('post_max_size'));
  if ($postMax > 0) {
    $margin = min(512 * 1024, max(64 * 1024, intdiv($postMax, 16)));
    $target = min($target, max(256 * 1024, $postMax - $margin));
  }
  return max(256 * 1024, min($controlMax, $target));
}

/**
 * Scoped upload transport used only by LLC/PHP. Unlike the normal Control
 * client this intentionally uses the per-upload bearer token and supports raw
 * PUT bodies. The browser never talks to Control directly.
 *
 * @param resource|null $input
 */
function llc_locallightai_control_upload_request(
  string $method,
  string $uploadId,
  string $uploadToken,
  ?string $contentRange = null,
  $input = null,
  int $contentLength = 0
): array {
  $method = strtoupper(trim($method));
  if (!in_array($method, ['GET', 'PUT', 'DELETE'], true)) {
    throw new RuntimeException('Unsupported upload bridge method.');
  }
  if (!preg_match('~^upl_[A-Za-z0-9_-]+$~', $uploadId)) {
    throw new RuntimeException('Invalid upload session id.');
  }
  if (!preg_match('~^upltok_[A-Za-z0-9_-]+$~', $uploadToken)) {
    throw new RuntimeException('Invalid upload session token.');
  }
  if ($method === 'PUT') {
    if (!is_resource($input) || $contentLength <= 0 || $contentRange === null || trim($contentRange) === '') {
      throw new RuntimeException('Upload chunk body metadata is incomplete.');
    }
  }

  $url = llc_locallightai_control_base() . '/api/v1/models/upload/' . rawurlencode($uploadId);
  if ($method === 'PUT' && $contentRange !== null &&
      preg_match('~^bytes\s+(\d+)-(\d+)/(\d+)$~i', trim($contentRange), $rm)) {
    // FPC 3.2.2 can fail to expose Content-Range after some PHP/web-server
    // relay combinations. Repeat the numeric range in private bridge query
    // parameters; Control still prefers the standard Content-Range header.
    $url .= '?llc_start=' . rawurlencode($rm[1])
      . '&llc_end=' . rawurlencode($rm[2])
      . '&llc_total=' . rawurlencode($rm[3]);
  }
  $timeoutMs = defined('LLC_LOCALLIGHTAI_UPLOAD_CHUNK_TIMEOUT_MS')
    ? (int)LLC_LOCALLIGHTAI_UPLOAD_CHUNK_TIMEOUT_MS
    : 300000;
  $timeoutMs = max(5000, min(30 * 60 * 1000, $timeoutMs));

  $headers = [
    'Accept: application/json',
    'Authorization: Bearer ' . $uploadToken,
    'Connection: close',
  ];
  if ($method === 'PUT') {
    $headers[] = 'Content-Type: application/octet-stream';
    $headers[] = 'Content-Range: ' . trim((string)$contentRange);
    $headers[] = 'Content-Length: ' . $contentLength;
    $headers[] = 'Expect:';
  }

  $body = '';
  $status = 0;

  if (function_exists('curl_init')) {
    $ch = curl_init($url);
    $opts = [
      CURLOPT_RETURNTRANSFER => true,
      CURLOPT_CUSTOMREQUEST => $method,
      CURLOPT_HTTPHEADER => $headers,
      CURLOPT_CONNECTTIMEOUT_MS => min(2000, $timeoutMs),
      CURLOPT_TIMEOUT_MS => $timeoutMs,
      CURLOPT_NOSIGNAL => true,
    ];
    if ($method === 'PUT') {
      $opts[CURLOPT_UPLOAD] = true;
      $opts[CURLOPT_INFILE] = $input;
      $opts[CURLOPT_INFILESIZE] = $contentLength;
    }
    curl_setopt_array($ch, $opts);
    $raw = curl_exec($ch);
    if ($raw === false) {
      $err = curl_error($ch);
      curl_close($ch);
      return ['ok'=>false, 'status'=>0, 'json'=>null, 'error'=>$err !== '' ? $err : 'Control upload bridge request failed'];
    }
    $body = (string)$raw;
    $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
  } else {
    $rawBody = '';
    if ($method === 'PUT') {
      $rawBody = stream_get_contents($input);
      if (!is_string($rawBody) || strlen($rawBody) !== $contentLength) {
        return ['ok'=>false, 'status'=>0, 'json'=>null, 'error'=>'Could not read the complete PHP upload chunk'];
      }
    }
    $opts = ['http' => [
      'method' => $method,
      'header' => implode("\r\n", $headers) . "\r\n",
      'ignore_errors' => true,
      'timeout' => max(5.0, $timeoutMs / 1000),
      'content' => $method === 'PUT' ? $rawBody : null,
    ]];
    $raw = @file_get_contents($url, false, stream_context_create($opts));
    if ($raw === false && empty($http_response_header)) {
      return ['ok'=>false, 'status'=>0, 'json'=>null, 'error'=>'Control upload bridge request failed'];
    }
    $body = $raw === false ? '' : (string)$raw;
    foreach (($http_response_header ?? []) as $line) {
      if (preg_match('~^HTTP/\\S+\\s+(\\d{3})~', $line, $m)) {
        $status = (int)$m[1];
        break;
      }
    }
  }

  $json = json_decode($body, true);
  if (!is_array($json)) $json = null;
  $result = ['ok'=>$status >= 200 && $status < 300, 'status'=>$status, 'json'=>$json];
  if (!$result['ok']) {
    $result['error'] = (string)($json['error'] ?? ($status > 0 ? ('Control upload HTTP ' . $status) : 'Control upload request failed'));
  }
  return $result;
}


/**
 * Managed subsystem configuration is owned by LocalLight Control. LLC/PHP
 * never opens RAGd or MCP files directly; this avoids web-server filesystem
 * permissions/namespaces becoming part of the bundle contract.
 */
function llc_locallightai_control_managed_raw(string $serviceId): array {
  $id = strtolower(trim($serviceId));
  if (!in_array($id, ['ragd', 'mcp'], true)) {
    throw new RuntimeException('Unsupported managed configuration service.');
  }
  $r = llc_locallightai_control_request('GET', '/api/v1/services/' . $id . '/config');
  if (!$r['ok'] || !is_array($r['json'])) {
    return [
      'ok' => false,
      'status' => (int)($r['status'] ?? 0),
      'error' => (string)($r['error'] ?? 'Managed configuration is unavailable.'),
    ];
  }
  $j = $r['json'];
  if (!array_key_exists('content', $j) || !is_string($j['content'])) {
    return [
      'ok' => false,
      'status' => (int)($r['status'] ?? 0),
      'error' => 'LocalLight Control returned invalid managed configuration data.',
    ];
  }
  return [
    'ok' => true,
    'status' => (int)($r['status'] ?? 200),
    'service' => $id,
    'source' => (string)($j['source'] ?? ''),
    'path' => (string)($j['path'] ?? ''),
    'format' => (string)($j['format'] ?? ''),
    'content' => $j['content'],
  ];
}

function llc_locallightai_control_write_managed_raw(string $serviceId, string $content): void {
  $id = strtolower(trim($serviceId));
  if (!in_array($id, ['ragd', 'mcp'], true)) {
    throw new RuntimeException('Unsupported managed configuration service.');
  }
  $r = llc_locallightai_control_request(
    'POST',
    '/api/v1/services/' . $id . '/config',
    null,
    ['content' => $content]
  );
  if (!$r['ok']) {
    throw new RuntimeException((string)($r['error'] ?? 'Managed configuration could not be saved.'));
  }
}

function llc_locallightai_is_secret_key(string $key): bool {
  return preg_match('~(?:token|api[_-]?key|password|secret)~i', $key) === 1;
}

function llc_locallightai_redact_config(mixed $value, string $key = ''): mixed {
  if ($key !== '' && llc_locallightai_is_secret_key($key)) {
    if ($value === null || $value === '' || $value === false) return 'not configured';
    return 'configured (hidden)';
  }
  if (!is_array($value)) return $value;
  $out = [];
  foreach ($value as $k => $v) {
    $out[$k] = llc_locallightai_redact_config($v, is_string($k) ? $k : '');
  }
  return $out;
}

function llc_locallightai_parse_scalar(string $value): mixed {
  $v = trim($value);
  $lower = strtolower($v);
  if ($lower === 'true') return true;
  if ($lower === 'false') return false;
  if ($lower === 'null') return null;
  if (preg_match('~^-?\d+$~', $v)) return (int)$v;
  if (preg_match('~^-?(?:\d+\.\d*|\d*\.\d+)$~', $v)) return (float)$v;
  return $v;
}

function llc_locallightai_read_ragd_config(): array {
  $raw = llc_locallightai_control_managed_raw('ragd');
  $result = [
    'source' => 'ragd/ragd.conf',
    'path' => (string)($raw['path'] ?? ''),
    'exists' => false,
    'readable' => false,
    'format' => 'key-value',
    'config' => [],
  ];
  if (!$raw['ok']) {
    $result['error'] = (string)($raw['error'] ?? 'RAGd configuration is unavailable.');
    return $result;
  }

  $cfg = [];
  $lines = preg_split('~\R~u', (string)$raw['content']) ?: [];
  foreach ($lines as $line) {
    $line = trim((string)$line);
    if ($line === '' || str_starts_with($line, '#') || str_starts_with($line, ';')) continue;
    $pos = strpos($line, '=');
    if ($pos === false) continue;
    $key = trim(substr($line, 0, $pos));
    if ($key === '') continue;
    $value = llc_locallightai_parse_scalar(substr($line, $pos + 1));
    $cfg[$key] = llc_locallightai_redact_config($value, $key);
  }

  $result['exists'] = true;
  $result['readable'] = true;
  $result['config'] = $cfg;
  return $result;
}

function llc_locallightai_read_mcp_config(): array {
  $raw = llc_locallightai_control_managed_raw('mcp');
  $result = [
    'source' => 'mcp/server/mcp-server.json',
    'path' => (string)($raw['path'] ?? ''),
    'exists' => false,
    'readable' => false,
    'format' => 'json',
    'config' => [],
  ];
  if (!$raw['ok']) {
    $result['error'] = (string)($raw['error'] ?? 'MCP configuration is unavailable.');
    return $result;
  }

  try {
    $cfg = json_decode((string)$raw['content'], true, 64, JSON_THROW_ON_ERROR);
  } catch (Throwable $e) {
    $result['exists'] = true;
    $result['error'] = 'Invalid JSON: ' . $e->getMessage();
    return $result;
  }
  if (!is_array($cfg)) {
    $result['exists'] = true;
    $result['error'] = 'MCP configuration must contain a JSON object';
    return $result;
  }

  $result['exists'] = true;
  $result['readable'] = true;
  $result['config'] = llc_locallightai_redact_config($cfg);
  return $result;
}

function llc_locallightai_managed_configs(): array {
  return [
    'retrieval' => llc_locallightai_read_ragd_config(),
    'mcp' => llc_locallightai_read_mcp_config(),
  ];
}

function llc_locallightai_managed_configs_action(): void {
  llc_locallightai_require_access();
  llc_json([
    'ok' => true,
    'configs' => llc_locallightai_managed_configs(),
  ]);
}


function llc_locallightai_int(mixed $value, string $name, int $min, int $max): int {
  if (is_string($value)) $value = trim($value);
  if ($value === '' || $value === null || filter_var($value, FILTER_VALIDATE_INT) === false) {
    throw new RuntimeException($name . ' must be an integer.');
  }
  $n = (int)$value;
  if ($n < $min || $n > $max) throw new RuntimeException($name . ' is outside the allowed range.');
  return $n;
}

function llc_locallightai_bool(mixed $value): bool {
  if (is_bool($value)) return $value;
  if (is_int($value)) return $value !== 0;
  $v = strtolower(trim((string)$value));
  return in_array($v, ['1', 'true', 'yes', 'on'], true);
}

function llc_locallightai_nonempty(mixed $value, string $name): string {
  $v = trim((string)$value);
  if ($v === '') throw new RuntimeException($name . ' must not be empty.');
  return $v;
}

function llc_locallightai_kv_string(mixed $value): string {
  if (is_bool($value)) return $value ? 'true' : 'false';
  if ($value === null) return '';
  return (string)$value;
}

function llc_locallightai_update_kv_text(string $raw, array $updates): string {
  $newline = str_contains($raw, "\r\n") ? "\r\n" : "\n";
  $lines = preg_split('~\R~u', $raw) ?: [];
  if ($lines && end($lines) === '') array_pop($lines);
  $seen = [];
  foreach ($lines as $i => $line) {
    $trim = ltrim((string)$line);
    if ($trim === '' || str_starts_with($trim, '#') || str_starts_with($trim, ';')) continue;
    $pos = strpos($line, '=');
    if ($pos === false) continue;
    $key = trim(substr($line, 0, $pos));
    if ($key === '' || !array_key_exists($key, $updates)) continue;
    $lines[$i] = $key . '=' . llc_locallightai_kv_string($updates[$key]);
    $seen[$key] = true;
  }
  foreach ($updates as $key => $value) {
    if (!isset($seen[$key])) $lines[] = $key . '=' . llc_locallightai_kv_string($value);
  }
  return implode($newline, $lines) . $newline;
}

function llc_locallightai_save_ragd_config(array $input): array {
  $managed = llc_locallightai_control_managed_raw('ragd');
  if (!$managed['ok']) throw new RuntimeException((string)($managed['error'] ?? 'RAGd configuration is unavailable.'));
  $raw = (string)$managed['content'];

  $chunk = llc_locallightai_int($input['chunk_chars'] ?? null, 'chunk_chars', 1, 10000000);
  $chunkMax = llc_locallightai_int($input['chunk_max_chars'] ?? null, 'chunk_max_chars', 1, 10000000);
  $overlap = llc_locallightai_int($input['chunk_overlap'] ?? null, 'chunk_overlap', 0, 10000000);
  if ($chunk > $chunkMax) throw new RuntimeException('chunk_chars must not exceed chunk_max_chars.');
  if ($overlap >= $chunkMax) throw new RuntimeException('chunk_overlap must be smaller than chunk_max_chars.');

  $defaultTopK = llc_locallightai_int($input['default_top_k'] ?? null, 'default_top_k', 1, 1000000);
  $maxTopK = llc_locallightai_int($input['max_top_k'] ?? null, 'max_top_k', 1, 1000000);
  if ($defaultTopK > $maxTopK) throw new RuntimeException('default_top_k must not exceed max_top_k.');

  $rerankerEnabled = llc_locallightai_bool($input['reranker_enabled'] ?? false);
  $updates = [
    'listen' => llc_locallightai_nonempty($input['listen'] ?? '', 'listen'),
    'port' => llc_locallightai_int($input['port'] ?? null, 'port', 1, 65535),
    'db' => llc_locallightai_nonempty($input['db'] ?? '', 'db'),
    'llama_url' => llc_locallightai_nonempty($input['llama_url'] ?? '', 'llama_url'),
    'embedding_model' => llc_locallightai_nonempty($input['embedding_model'] ?? '', 'embedding_model'),
    'chunk_chars' => $chunk,
    'chunk_max_chars' => $chunkMax,
    'chunk_overlap' => $overlap,
    'embedding_batch' => llc_locallightai_int($input['embedding_batch'] ?? null, 'embedding_batch', 1, 1000000),
    'default_top_k' => $defaultTopK,
    'max_top_k' => $maxTopK,
    'hybrid_dense_k' => llc_locallightai_int($input['hybrid_dense_k'] ?? null, 'hybrid_dense_k', 1, 1000000),
    'hybrid_bm25_k' => llc_locallightai_int($input['hybrid_bm25_k'] ?? null, 'hybrid_bm25_k', 1, 1000000),
    'hybrid_rrf_k' => llc_locallightai_int($input['hybrid_rrf_k'] ?? null, 'hybrid_rrf_k', 1, 1000000),
    'reranker_enabled' => $rerankerEnabled,
    'reranker_url' => trim((string)($input['reranker_url'] ?? '')),
    'reranker_model' => trim((string)($input['reranker_model'] ?? '')),
  ];
  if (array_key_exists('reranker_max_bytes', $input) && trim((string)$input['reranker_max_bytes']) !== '') {
    $updates['reranker_max_bytes'] = llc_locallightai_int($input['reranker_max_bytes'], 'reranker_max_bytes', 0, 4294967295);
  }
  if ($rerankerEnabled && $updates['reranker_url'] === '') throw new RuntimeException('reranker_url must not be empty while the reranker is enabled.');
  if ($rerankerEnabled && $updates['reranker_model'] === '') throw new RuntimeException('reranker_model must not be empty while the reranker is enabled.');

  // Upstream secrets are changed only when the user explicitly enters a new
  // value or asks to clear them. Blank secret fields otherwise preserve the
  // existing file value.
  foreach (['llama_api_key', 'reranker_api_key'] as $secretKey) {
    if (llc_locallightai_bool($input['clear_' . $secretKey] ?? false)) {
      $updates[$secretKey] = '';
    } else {
      $newSecret = (string)($input[$secretKey] ?? '');
      if ($newSecret !== '') $updates[$secretKey] = $newSecret;
    }
  }

  // Reserved for RAGd inbound authentication. These keys are only persisted
  // once they already exist in ragd.conf, so current RAGd builds are not given
  // unknown settings prematurely.
  $hasInboundAuth = preg_match('~^\s*auth_(?:enabled|bearer_token)\s*=~mi', $raw) === 1;
  if ($hasInboundAuth) {
    $updates['auth_enabled'] = llc_locallightai_bool($input['auth_enabled'] ?? false);
    if (llc_locallightai_bool($input['clear_auth_bearer_token'] ?? false)) {
      $updates['auth_bearer_token'] = '';
    } else {
      $newSecret = (string)($input['auth_bearer_token'] ?? '');
      if ($newSecret !== '') $updates['auth_bearer_token'] = $newSecret;
    }
  }

  $updated = llc_locallightai_update_kv_text($raw, $updates);
  llc_locallightai_control_write_managed_raw('ragd', $updated);
  return llc_locallightai_read_ragd_config();
}

function llc_locallightai_read_mcp_raw(): array {
  $managed = llc_locallightai_control_managed_raw('mcp');
  if (!$managed['ok']) throw new RuntimeException((string)($managed['error'] ?? 'MCP configuration is unavailable.'));
  try {
    $cfg = json_decode((string)$managed['content'], true, 64, JSON_THROW_ON_ERROR);
  } catch (Throwable $e) {
    throw new RuntimeException('Invalid MCP JSON: ' . $e->getMessage());
  }
  if (!is_array($cfg)) throw new RuntimeException('MCP configuration must contain a JSON object.');
  return $cfg;
}

function llc_locallightai_save_mcp_config(array $input): array {
  $cfg = llc_locallightai_read_mcp_raw();
  foreach (['server','authentication','cors','filesystem','processes','terminal','desktop','logging'] as $section) {
    if (!isset($cfg[$section]) || !is_array($cfg[$section])) $cfg[$section] = [];
  }
  if (!isset($cfg['desktop']['features']) || !is_array($cfg['desktop']['features'])) $cfg['desktop']['features'] = [];

  $server = is_array($input['server'] ?? null) ? $input['server'] : [];
  $cfg['server']['address'] = llc_locallightai_nonempty($server['address'] ?? '', 'server.address');
  $cfg['server']['port'] = llc_locallightai_int($server['port'] ?? null, 'server.port', 1, 65535);
  $endpoint = llc_locallightai_nonempty($server['endpoint'] ?? '', 'server.endpoint');
  if (!str_starts_with($endpoint, '/')) $endpoint = '/' . $endpoint;
  $cfg['server']['endpoint'] = $endpoint;
  $cfg['server']['maximum_request_bytes'] = llc_locallightai_int($server['maximum_request_bytes'] ?? null, 'server.maximum_request_bytes', 1, 4294967295);

  $auth = is_array($input['authentication'] ?? null) ? $input['authentication'] : [];
  if (llc_locallightai_bool($auth['clear_bearer_token'] ?? false)) {
    $cfg['authentication']['bearer_token'] = '';
  } else {
    $newToken = (string)($auth['bearer_token'] ?? '');
    if ($newToken !== '') $cfg['authentication']['bearer_token'] = $newToken;
  }

  $cors = is_array($input['cors'] ?? null) ? $input['cors'] : [];
  $cfg['cors']['enabled'] = llc_locallightai_bool($cors['enabled'] ?? false);
  $origins = $cors['allowed_origins'] ?? [];
  if (is_string($origins)) $origins = preg_split('~\R+~', $origins) ?: [];
  if (!is_array($origins)) $origins = [];
  $cfg['cors']['allowed_origins'] = array_values(array_unique(array_filter(array_map(static function($v): string {
    return rtrim(trim((string)$v), '/');
  }, $origins), static fn($v) => $v !== '')));

  $fs = is_array($input['filesystem'] ?? null) ? $input['filesystem'] : [];
  $cfg['filesystem']['enabled'] = llc_locallightai_bool($fs['enabled'] ?? false);
  $cfg['filesystem']['workspace_root'] = llc_locallightai_nonempty($fs['workspace_root'] ?? '', 'filesystem.workspace_root');
  $cfg['filesystem']['allow_delete'] = llc_locallightai_bool($fs['allow_delete'] ?? false);

  $proc = is_array($input['processes'] ?? null) ? $input['processes'] : [];
  foreach (['enabled','allow_process_exec','allow_shell_exec','allow_process_start','allow_shell_start','detach_from_terminal','mirror_output_to_console','detect_interactive_prompt_loops'] as $key) {
    $cfg['processes'][$key] = llc_locallightai_bool($proc[$key] ?? false);
  }
  $consoleMode = trim((string)($proc['console_output_mode'] ?? 'prefixed'));
  if (!in_array($consoleMode, ['prefixed','raw'], true)) throw new RuntimeException('processes.console_output_mode must be prefixed or raw.');
  $cfg['processes']['console_output_mode'] = $consoleMode;
  $procInts = [
    'default_timeout_ms'=>[0,4294967295], 'maximum_timeout_ms'=>[0,4294967295],
    'default_wait_ms'=>[0,4294967295], 'maximum_wait_ms'=>[1,4294967295],
    'maximum_tracked_jobs'=>[8,2147483647], 'default_idle_timeout_ms'=>[0,4294967295],
    'maximum_idle_timeout_ms'=>[0,4294967295], 'termination_grace_ms'=>[0,4294967295],
    'maximum_output_bytes'=>[1,4294967295], 'max_output_chars'=>[0,100000],
    'interactive_prompt_repeat_limit'=>[3,4294967295], 'interactive_prompt_window_ms'=>[100,4294967295],
    'interactive_prompt_max_chars'=>[4,1024],
  ];
  foreach ($procInts as $key => [$min,$max]) $cfg['processes'][$key] = llc_locallightai_int($proc[$key] ?? null, 'processes.' . $key, $min, $max);
  if ($cfg['processes']['maximum_timeout_ms'] > 0 && $cfg['processes']['default_timeout_ms'] > $cfg['processes']['maximum_timeout_ms']) throw new RuntimeException('processes.default_timeout_ms must not exceed maximum_timeout_ms.');
  if ($cfg['processes']['default_wait_ms'] > $cfg['processes']['maximum_wait_ms']) throw new RuntimeException('processes.default_wait_ms must not exceed maximum_wait_ms.');
  if ($cfg['processes']['maximum_idle_timeout_ms'] > 0 && $cfg['processes']['default_idle_timeout_ms'] > $cfg['processes']['maximum_idle_timeout_ms']) throw new RuntimeException('processes.default_idle_timeout_ms must not exceed maximum_idle_timeout_ms.');

  $terminal = is_array($input['terminal'] ?? null) ? $input['terminal'] : [];
  $cfg['terminal']['enabled'] = llc_locallightai_bool($terminal['enabled'] ?? false);
  foreach (['log_output','log_input','mirror_output_to_console','mirror_input_to_console'] as $key) $cfg['terminal'][$key] = llc_locallightai_bool($terminal[$key] ?? false);
  $termMode = trim((string)($terminal['console_output_mode'] ?? 'prefixed'));
  if (!in_array($termMode, ['prefixed','raw'], true)) throw new RuntimeException('terminal.console_output_mode must be prefixed or raw.');
  $cfg['terminal']['console_output_mode'] = $termMode;
  $termInts = [
    'maximum_sessions'=>[1,2147483647], 'maximum_output_bytes'=>[4096,2147483647],
    'maximum_read_bytes'=>[1,2147483647], 'maximum_observation_bytes'=>[1,2147483647],
    'observation_quiet_ms'=>[0,4294967295], 'observation_default_wait_ms'=>[0,4294967295],
    'maximum_scrollback_lines'=>[1,2147483647], 'maximum_write_bytes'=>[1,2147483647],
    'default_columns'=>[1,32767], 'default_rows'=>[1,32767],
    'maximum_read_wait_ms'=>[1,4294967295], 'termination_grace_ms'=>[0,4294967295],
  ];
  foreach ($termInts as $key => [$min,$max]) $cfg['terminal'][$key] = llc_locallightai_int($terminal[$key] ?? null, 'terminal.' . $key, $min, $max);

  $desktop = is_array($input['desktop'] ?? null) ? $input['desktop'] : [];
  $cfg['desktop']['enabled'] = llc_locallightai_bool($desktop['enabled'] ?? false);
  $cfg['desktop']['maximum_image_bytes'] = llc_locallightai_int($desktop['maximum_image_bytes'] ?? null, 'desktop.maximum_image_bytes', 32768, 4294967295);
  $features = is_array($desktop['features'] ?? null) ? $desktop['features'] : [];
  foreach (['window_management','screen_capture','input'] as $key) $cfg['desktop']['features'][$key] = llc_locallightai_bool($features[$key] ?? false);

  $logging = is_array($input['logging'] ?? null) ? $input['logging'] : [];
  $cfg['logging']['file'] = trim((string)($logging['file'] ?? ''));
  $cfg['logging']['log_process_commands'] = llc_locallightai_bool($logging['log_process_commands'] ?? false);
  $cfg['logging']['log_process_output'] = llc_locallightai_bool($logging['log_process_output'] ?? false);

  $json = json_encode($cfg, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
  if (!is_string($json)) throw new RuntimeException('MCP configuration could not be serialized.');
  llc_locallightai_control_write_managed_raw('mcp', $json . PHP_EOL);
  return llc_locallightai_read_mcp_config();
}

function llc_locallightai_save_managed_config_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  $kind = strtolower(trim((string)($j['kind'] ?? '')));
  $config = is_array($j['config'] ?? null) ? $j['config'] : [];
  try {
    if ($kind === 'retrieval') $result = llc_locallightai_save_ragd_config($config);
    elseif ($kind === 'mcp') $result = llc_locallightai_save_mcp_config($config);
    else llc_json(['error'=>'Unknown managed configuration'], 400);
  } catch (Throwable $e) {
    llc_json(['error'=>$e->getMessage()], 400);
  }
  llc_json(['ok'=>true, 'config'=>$result, 'restart_required'=>true]);
}


function llc_locallightai_artifact_id(mixed $value): string {
  $id = trim((string)$value);
  if (!preg_match('~^art_[a-z0-9_-]+$~i', $id)) throw new RuntimeException('Invalid artifact id.');
  return $id;
}

function llc_locallightai_profile_id(mixed $value): string {
  $id = trim((string)$value);
  if (!preg_match('~^prf_[a-z0-9_-]+$~i', $id)) throw new RuntimeException('Invalid profile id.');
  return $id;
}

function llc_locallightai_control_json_result(array $r, string $fallback): void {
  if (!$r['ok'] || !is_array($r['json'])) {
    $code = ($r['status'] ?? 0) >= 400 && ($r['status'] ?? 0) < 600 ? (int)$r['status'] : 502;
    llc_json(['ok'=>false, 'error'=>(string)($r['error'] ?? $fallback)], $code);
  }
  llc_json($r['json']);
}

function llc_locallightai_models_action(): void {
  llc_locallightai_require_access();
  llc_locallightai_control_json_result(
    llc_locallightai_control_request('GET', '/api/v1/models'),
    'Model catalog is unavailable.'
  );
}

function llc_locallightai_model_scan_action(): void {
  llc_locallightai_require_access();
  // Filesystem scanning remains strictly user-triggered. Merely opening the
  // Models tab reads only the small Control-owned catalog file.
  llc_locallightai_control_json_result(
    llc_locallightai_control_request('POST', '/api/v1/models/scan', 60000),
    'Model scan failed.'
  );
}

function llc_locallightai_model_restore_ignored_action(): void {
  llc_locallightai_require_access();
  // Restore checks only already-known ignored artifact paths; no recursive scan.
  llc_locallightai_control_json_result(
    llc_locallightai_control_request('POST', '/api/v1/models/ignored/restore'),
    'Ignored models could not be restored.'
  );
}

function llc_locallightai_model_upload_start_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  $filename = trim((string)($j['filename'] ?? ''));
  $size = $j['size_bytes'] ?? null;
  if ($filename === '' || !preg_match('~\.gguf$~i', $filename)) {
    llc_json(['error'=>'Select a .gguf model/projector file.'], 400);
  }
  if (!is_int($size) && !is_float($size) && !is_numeric($size)) {
    llc_json(['error'=>'Invalid upload file size.'], 400);
  }
  $size = (int)$size;
  if ($size <= 0) llc_json(['error'=>'Upload file is empty.'], 400);

  $r = llc_locallightai_control_request(
    'POST',
    '/api/v1/models/upload/start',
    10000,
    ['upload'=>['filename'=>$filename, 'size_bytes'=>$size]]
  );
  if (!$r['ok'] || !is_array($r['json'])) {
    llc_json(['error'=>(string)($r['error'] ?? 'Model upload could not be started.')], (int)($r['status'] ?: 502));
  }
  $out = $r['json'];
  $uploadId = trim((string)($out['upload_id'] ?? ''));
  $uploadToken = trim((string)($out['upload_token'] ?? ''));
  if (!preg_match('~^upl_[A-Za-z0-9_-]+$~', $uploadId) ||
      !preg_match('~^upltok_[A-Za-z0-9_-]+$~', $uploadToken)) {
    llc_json(['error'=>'Control returned an invalid upload session.'], 502);
  }

  $controlChunk = max(256 * 1024, (int)($out['chunk_size'] ?? (64 * 1024 * 1024)));
  $out['chunk_size'] = llc_locallightai_upload_bridge_chunk_size($controlChunk);
  $out['transport'] = 'php';
  unset($out['upload_path']);
  llc_json($out);
}

function llc_locallightai_model_upload_status_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  $uploadId = trim((string)($j['upload_id'] ?? ''));
  $uploadToken = trim((string)($j['upload_token'] ?? ''));
  try {
    $r = llc_locallightai_control_upload_request('GET', $uploadId, $uploadToken);
  } catch (Throwable $e) {
    llc_json(['error'=>$e->getMessage()], 400);
  }
  if (!$r['ok'] || !is_array($r['json'])) {
    llc_json(['error'=>(string)($r['error'] ?? 'Upload status is unavailable.')], (int)($r['status'] ?: 502));
  }
  llc_json($r['json']);
}

function llc_locallightai_model_upload_chunk_action(): void {
  llc_locallightai_require_access();
  if (strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'POST')) !== 'POST') {
    llc_json(['error'=>'Upload chunk endpoint requires POST.'], 405);
  }

  $uploadId = trim((string)($_SERVER['HTTP_X_LLC_UPLOAD_ID'] ?? ''));
  $uploadToken = trim((string)($_SERVER['HTTP_X_LLC_UPLOAD_TOKEN'] ?? ''));
  $range = trim((string)($_SERVER['HTTP_CONTENT_RANGE'] ?? ''));
  $length = (int)($_SERVER['CONTENT_LENGTH'] ?? 0);

  if (!preg_match('~^bytes\s+(\d+)-(\d+)/(\d+)$~i', $range, $m)) {
    llc_json(['error'=>'Missing or invalid Content-Range for upload chunk.'], 400);
  }
  $start = (int)$m[1];
  $end = (int)$m[2];
  $total = (int)$m[3];
  $expected = $end >= $start ? ($end - $start + 1) : 0;
  if ($expected <= 0 || $length !== $expected || $total <= $end) {
    llc_json(['error'=>'Upload chunk length does not match Content-Range.'], 400);
  }
  if ($length > 64 * 1024 * 1024) {
    llc_json(['error'=>'Upload chunk exceeds the 64 MiB Control limit.'], 413);
  }

  @set_time_limit(0);
  @ignore_user_abort(true);
  $input = fopen('php://input', 'rb');
  if (!is_resource($input)) llc_json(['error'=>'Could not open PHP upload input stream.'], 500);

  try {
    $r = llc_locallightai_control_upload_request(
      'PUT',
      $uploadId,
      $uploadToken,
      $range,
      $input,
      $length
    );
  } catch (Throwable $e) {
    fclose($input);
    llc_json(['error'=>$e->getMessage()], 400);
  }
  fclose($input);

  if (!$r['ok'] || !is_array($r['json'])) {
    llc_json(['error'=>(string)($r['error'] ?? 'Upload chunk could not be forwarded to Control.')], (int)($r['status'] ?: 502));
  }
  llc_json($r['json']);
}

function llc_locallightai_model_upload_cancel_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  $uploadId = trim((string)($j['upload_id'] ?? ''));
  if (!preg_match('~^upl_[A-Za-z0-9_-]+$~', $uploadId)) {
    llc_json(['error'=>'Invalid upload session id.'], 400);
  }
  $r = llc_locallightai_control_request(
    'POST',
    '/api/v1/models/upload/cancel',
    10000,
    ['cancel'=>['upload_id'=>$uploadId]]
  );
  if (!$r['ok'] || !is_array($r['json'])) {
    llc_json(['error'=>(string)($r['error'] ?? 'Model upload could not be cancelled.')], (int)($r['status'] ?: 502));
  }
  llc_json($r['json']);
}

function llc_locallightai_hf_search_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  $query = trim((string)($j['query'] ?? ''));
  $queryLength = function_exists('mb_strlen') ? mb_strlen($query, 'UTF-8') : strlen($query);
  if ($queryLength < 2) llc_json(['error'=>'Search query must contain at least 2 characters.'], 400);
  $limit = (int)($j['limit'] ?? 20);
  $limit = max(1, min(30, $limit));
  llc_locallightai_control_json_result(
    llc_locallightai_control_request(
      'POST',
      '/api/v1/models/huggingface/search',
      30000,
      ['search'=>['query'=>$query, 'limit'=>$limit]]
    ),
    'Hugging Face search failed.'
  );
}

function llc_locallightai_hf_repository_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  $repoId = trim((string)($j['repo_id'] ?? ''));
  if (!preg_match('~^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$~', $repoId)) {
    llc_json(['error'=>'Invalid Hugging Face repository id.'], 400);
  }
  llc_locallightai_control_json_result(
    llc_locallightai_control_request(
      'POST',
      '/api/v1/models/huggingface/repository',
      30000,
      ['repository'=>['repo_id'=>$repoId]]
    ),
    'Hugging Face repository could not be inspected.'
  );
}


function llc_locallightai_hf_settings_action(): void {
  llc_locallightai_require_access();
  llc_locallightai_control_json_result(
    llc_locallightai_control_request('GET', '/api/v1/models/huggingface/settings'),
    'Hugging Face settings are unavailable.'
  );
}

function llc_locallightai_hf_settings_save_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  $clear = !empty($j['clear_token']);
  $token = trim((string)($j['token'] ?? ''));
  if (!$clear && $token === '') llc_json(['error'=>'Enter a Hugging Face access token.'], 400);
  if (strlen($token) > 4096 || str_contains($token, "\0") || str_contains($token, "\r") || str_contains($token, "\n")) {
    llc_json(['error'=>'Invalid Hugging Face access token.'], 400);
  }
  $settings = $clear ? ['clear_token'=>true] : ['token'=>$token, 'clear_token'=>false];
  llc_locallightai_control_json_result(
    llc_locallightai_control_request('POST', '/api/v1/models/huggingface/settings', 10000, ['settings'=>$settings]),
    'Hugging Face settings could not be saved.'
  );
}

function llc_locallightai_hf_download_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  $repoId = trim((string)($j['repo_id'] ?? ''));
  $variantKey = trim((string)($j['variant_key'] ?? ''));
  $projectorPath = trim((string)($j['projector_path'] ?? ''));
  if (!preg_match('~^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$~', $repoId)) {
    llc_json(['error'=>'Invalid Hugging Face repository id.'], 400);
  }
  if (($variantKey === '') === ($projectorPath === '')) {
    llc_json(['error'=>'Select exactly one GGUF variant or projector file.'], 400);
  }
  $download = ['repo_id'=>$repoId];
  if ($variantKey !== '') {
    if (strlen($variantKey) > 1024) llc_json(['error'=>'Invalid GGUF variant key.'], 400);
    $download['variant_key'] = $variantKey;
  } else {
    if (strlen($projectorPath) > 2048 || str_contains($projectorPath, "\0")) {
      llc_json(['error'=>'Invalid projector path.'], 400);
    }
    $download['projector_path'] = $projectorPath;
  }
  llc_locallightai_control_json_result(
    llc_locallightai_control_request(
      'POST',
      '/api/v1/models/huggingface/download',
      30000,
      ['download'=>$download]
    ),
    'Hugging Face download could not be started.'
  );
}

function llc_locallightai_hf_download_status_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  $jobId = trim((string)($j['job_id'] ?? ''));
  if (!preg_match('~^hf_[A-Za-z0-9_-]{4,80}$~', $jobId)) {
    llc_json(['error'=>'Invalid Hugging Face download job id.'], 400);
  }
  llc_locallightai_control_json_result(
    llc_locallightai_control_request(
      'POST',
      '/api/v1/models/huggingface/download/status',
      10000,
      ['status'=>['job_id'=>$jobId]]
    ),
    'Hugging Face download status is unavailable.'
  );
}

function llc_locallightai_hf_download_cancel_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  $jobId = trim((string)($j['job_id'] ?? ''));
  if (!preg_match('~^hf_[A-Za-z0-9_-]{4,80}$~', $jobId)) {
    llc_json(['error'=>'Invalid Hugging Face download job id.'], 400);
  }
  llc_locallightai_control_json_result(
    llc_locallightai_control_request(
      'POST',
      '/api/v1/models/huggingface/download/cancel',
      10000,
      ['cancel'=>['job_id'=>$jobId]]
    ),
    'Hugging Face download could not be cancelled.'
  );
}

function llc_locallightai_profile_create_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  try { $id = llc_locallightai_artifact_id($j['artifact_id'] ?? ''); }
  catch (Throwable $e) { llc_json(['error'=>$e->getMessage()], 400); }
  $profile = $j['profile'] ?? null;
  if (!is_array($profile)) llc_json(['error'=>'profile must be an object'], 400);
  llc_locallightai_control_json_result(
    llc_locallightai_control_request('POST', '/api/v1/models/artifacts/' . $id . '/profiles', null, ['profile'=>$profile]),
    'Profile could not be created.'
  );
}

function llc_locallightai_profile_save_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  try { $id = llc_locallightai_profile_id($j['profile_id'] ?? ''); }
  catch (Throwable $e) { llc_json(['error'=>$e->getMessage()], 400); }
  $profile = $j['profile'] ?? null;
  if (!is_array($profile)) llc_json(['error'=>'profile must be an object'], 400);
  llc_locallightai_control_json_result(
    llc_locallightai_control_request('POST', '/api/v1/models/profiles/' . $id, null, ['profile'=>$profile]),
    'Profile could not be saved.'
  );
}

function llc_locallightai_profile_command_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  try { $id = llc_locallightai_profile_id($j['profile_id'] ?? ''); }
  catch (Throwable $e) { llc_json(['error'=>$e->getMessage()], 400); }
  $command = strtolower(trim((string)($j['command'] ?? '')));
  if (!in_array($command, ['duplicate','remove'], true)) llc_json(['error'=>'Unknown profile action'], 400);
  llc_locallightai_control_json_result(
    llc_locallightai_control_request('POST', '/api/v1/models/profiles/' . $id . '/' . $command),
    'Profile action failed.'
  );
}

function llc_locallightai_artifact_command_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  try { $id = llc_locallightai_artifact_id($j['artifact_id'] ?? ''); }
  catch (Throwable $e) { llc_json(['error'=>$e->getMessage()], 400); }
  $command = strtolower(trim((string)($j['command'] ?? '')));
  if (!in_array($command, ['ignore','remove','delete-files'], true)) llc_json(['error'=>'Unknown artifact action'], 400);
  $body = null;
  if ($command === 'delete-files') {
    $body = ['delete'=>['delete_projectors'=>!empty($j['delete_projectors'])]];
  }
  llc_locallightai_control_json_result(
    llc_locallightai_control_request('POST', '/api/v1/models/artifacts/' . $id . '/' . $command, null, $body),
    'Artifact action failed.'
  );
}

function llc_locallightai_snapshot(): void {
  llc_locallightai_require_access();

  // First perform one cheap reachability check. If Control is down, avoid
  // serially waiting for info/config/services timeouts as well.
  $health = llc_locallightai_control_request('GET', '/api/v1/health', min(1200, llc_locallightai_timeout_ms()));
  if (!$health['ok']) {
    llc_json([
      'ok'=>false,
      'reachable'=>false,
      'error'=>(string)($health['error'] ?? 'LocalLight Control is unavailable'),
      'services'=>[],
    ]);
  }

  $info = llc_locallightai_control_request('GET', '/api/v1/info');
  $config = llc_locallightai_control_request('GET', '/api/v1/config');
  $services = llc_locallightai_control_request('GET', '/api/v1/services');

  $svcList = [];
  if ($services['ok'] && is_array($services['json'])) {
    $svcList = $services['json']['services'] ?? [];
    if (!is_array($svcList)) $svcList = [];
  }

  llc_json([
    'ok' => $info['ok'] && $config['ok'] && $services['ok'],
    'reachable' => true,
    'health' => $health['json'],
    'info' => $info['json'],
    'config' => $config['json'],
    'services' => $svcList,
    'errors' => array_values(array_filter([
      $info['ok'] ? null : ($info['error'] ?? 'Info request failed'),
      $config['ok'] ? null : ($config['error'] ?? 'Config request failed'),
      $services['ok'] ? null : ($services['error'] ?? 'Services request failed'),
    ])),
  ]);
}

function llc_locallightai_service_action(): void {
  llc_locallightai_require_access();
  $j = llc_read_json();
  $id = strtolower(trim((string)($j['id'] ?? '')));
  $action = strtolower(trim((string)($j['command'] ?? $j['action'] ?? '')));

  if (!in_array($id, ['llama', 'ragd', 'mcp'], true)) {
    llc_json(['error'=>'Unknown LocalLight service'], 400);
  }
  if (!in_array($action, ['start', 'stop', 'restart'], true)) {
    llc_json(['error'=>'Unknown LocalLight service action'], 400);
  }

  $r = llc_locallightai_control_request('POST', '/api/v1/services/' . $id . '/' . $action);
  if (!$r['ok']) {
    $code = $r['status'] >= 400 && $r['status'] < 600 ? (int)$r['status'] : 502;
    llc_json([
      'ok'=>false,
      'error'=>(string)($r['error'] ?? 'Control action failed'),
      'control_status'=>(int)$r['status'],
    ], $code);
  }

  llc_json([
    'ok'=>true,
    'accepted'=>$action,
    'service'=>$id,
    'control_status'=>(int)$r['status'],
    'control'=>$r['json'],
  ]);
}
