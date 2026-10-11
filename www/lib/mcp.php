<?php
declare(strict_types=1);

function llc_mcp_json_flags(): int {
  return JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE;
}

final class LlcMcpHttpException extends RuntimeException {
  public int $status;

  public function __construct(int $status, string $message) {
    parent::__construct($message);
    $this->status = $status;
  }
}

/**
 * MCP gateway sessions must outlive one PHP/SSE request if interactive terminal
 * work is expected to survive a browser/network reconnect. The active chat ID
 * scopes that durable binding so unrelated chats do not accidentally share one
 * stdio MCP child process.
 */
function &llc_mcp_request_scope(): array {
  static $scope = ['chat_id'=>''];
  return $scope;
}

function llc_mcp_set_chat_scope(string $chatId): void {
  $scope =& llc_mcp_request_scope();
  $chatId = trim($chatId);
  if ((string)($scope['chat_id'] ?? '') === $chatId) return;
  $scope['chat_id'] = $chatId;
  // A PHP worker may serve multiple requests over its lifetime. Never let a
  // process-local runtime created for one chat bleed into another chat.
  $cache =& llc_mcp_runtime_cache();
  $cache = [];
}

function llc_mcp_chat_scope(): string {
  $scope =& llc_mcp_request_scope();
  return trim((string)($scope['chat_id'] ?? ''));
}


/**
 * Remove inline MCP image Base64 from the JSON tool result and return the
 * decoded images separately. Tool JSON must stay textual and compact; images
 * are forwarded through the chat's multimodal image path instead.
 */
function llc_mcp_detach_inline_images(array $wrappedResult): array {
  $images = [];
  $result = $wrappedResult['result'] ?? null;
  if (!is_array($result)) return ['result'=>$wrappedResult, 'images'=>$images];
  $content = $result['content'] ?? null;
  if (!is_array($content)) return ['result'=>$wrappedResult, 'images'=>$images];

  $cleanContent = [];
  foreach ($content as $index => $item) {
    if (!is_array($item) || strtolower((string)($item['type'] ?? '')) !== 'image') {
      $cleanContent[] = $item;
      continue;
    }

    $mime = strtolower(trim((string)($item['mimeType'] ?? $item['mime_type'] ?? 'image/png')));
    if (!preg_match('#^image/(?:png|jpe?g|webp|gif)$#', $mime)) $mime = 'image/png';
    $b64 = preg_replace('/\s+/', '', (string)($item['data'] ?? '')) ?? '';
    $bytes = $b64 !== '' ? base64_decode($b64, true) : false;
    if (!is_string($bytes) || $bytes === '') {
      $cleanContent[] = ['type'=>'text','text'=>'[MCP image omitted: invalid Base64 payload]'];
      continue;
    }
    // Refuse pathological third-party MCP payloads before they reach storage or
    // the model. Lossless single-monitor PNG screenshots may legitimately be
    // several MiB. Keep a generous but finite generic client-side ceiling.
    if (strlen($bytes) > 16 * 1024 * 1024) {
      $cleanContent[] = ['type'=>'text','text'=>'[MCP image omitted: payload exceeds 16 MiB client limit]'];
      continue;
    }

    $images[] = [
      'mime'=>$mime,
      'bytes'=>$bytes,
      'base64'=>$b64,
      'index'=>(int)$index,
    ];
    $cleanContent[] = [
      'type'=>'text',
      'text'=>'[MCP image detached for multimodal processing: ' . $mime . ', ' . strlen($bytes) . ' bytes]',
    ];
  }

  $wrappedResult['result']['content'] = $cleanContent;
  return ['result'=>$wrappedResult, 'images'=>$images];
}

function llc_mcp_image_extension(string $mime): string {
  $mime = strtolower(trim($mime));
  if ($mime === 'image/jpeg' || $mime === 'image/jpg') return 'jpg';
  if ($mime === 'image/webp') return 'webp';
  if ($mime === 'image/gif') return 'gif';
  return 'png';
}

function llc_mcp_server_id(string $value, int $index = 0): string {
  $value = trim($value);
  if ($value === '') $value = 'server_' . ($index + 1);
  $value = preg_replace('/[^A-Za-z0-9_-]+/', '_', $value) ?? '';
  $value = trim($value, '_-');
  if ($value === '') $value = 'server_' . ($index + 1);
  return substr($value, 0, 40);
}

function llc_mcp_normalize_headers($raw): array {
  if (!is_array($raw)) return [];
  $out = [];
  foreach ($raw as $k => $v) {
    $name = '';
    $value = '';
    if (is_string($k) && trim($k) !== '' && (is_string($v) || is_numeric($v))) {
      $name = trim($k);
      $value = (string)$v;
    } elseif (is_string($v) && str_contains($v, ':')) {
      [$name, $value] = array_pad(explode(':', $v, 2), 2, '');
      $name = trim($name);
      $value = trim($value);
    }
    if ($name === '') continue;
    if (!preg_match("/^[A-Za-z0-9!#$%&'*+.^_`|~-]+$/", $name)) {
      throw new RuntimeException('Invalid MCP HTTP header name: ' . $name);
    }
    if (str_contains($value, "\r") || str_contains($value, "\n")) {
      throw new RuntimeException('Invalid newline in MCP HTTP header: ' . $name);
    }
    $out[$name] = $value;
  }
  return $out;
}

function llc_mcp_normalize_server(array $it, int $index = 0): array {
  $id = llc_mcp_server_id((string)($it['id'] ?? $it['name'] ?? ''), $index);
  $name = trim((string)($it['name'] ?? $it['title'] ?? $id));
  if ($name === '') $name = $id;
  $url = trim((string)($it['url'] ?? $it['endpoint'] ?? ''));
  if ($url === '') throw new RuntimeException('MCP server ' . $name . ': missing url');
  $timeout = (int)($it['timeout_sec'] ?? 3600);
  if ($timeout < 0) $timeout = 0;
  if ($timeout > 2592000) $timeout = 2592000;
  $maxResponse = max(65536, min(64 * 1024 * 1024, (int)($it['max_response_bytes'] ?? (32 * 1024 * 1024))));
  $followExecJobs = !array_key_exists('follow_exec_jobs', $it) || !empty($it['follow_exec_jobs']);
  $token = (string)($it['token'] ?? $it['bearer_token'] ?? '');
  if (str_contains($token, "\r") || str_contains($token, "\n")) throw new RuntimeException('MCP server ' . $name . ': invalid token');
  $protocolVersion = trim((string)($it['protocol_version'] ?? '2025-11-25'));
  if ($protocolVersion === '') $protocolVersion = '2025-11-25';
  return [
    'id' => $id,
    'name' => $name,
    'description' => trim((string)($it['description'] ?? '')),
    'url' => $url,
    'token' => $token,
    'headers' => llc_mcp_normalize_headers($it['headers'] ?? []),
    'allow_private' => !empty($it['allow_private']),
    'timeout_sec' => $timeout,
    'max_response_bytes' => $maxResponse,
    'follow_exec_jobs' => $followExecJobs,
    'protocol_version' => $protocolVersion,
  ];
}

function llc_mcp_normalize_servers_array(array $items): array {
  $out = [];
  $seen = [];
  foreach (array_values($items) as $i => $it) {
    if (!is_array($it)) continue;
    $server = llc_mcp_normalize_server($it, $i);
    $id = (string)$server['id'];
    if (isset($seen[$id])) throw new RuntimeException('Duplicate MCP server id: ' . $id);
    $seen[$id] = true;
    $out[] = $server;
  }
  return $out;
}

function llc_mcp_servers_config(PDO $db, array $u): array {
  $uid = (string)($u['id'] ?? '');
  if ($uid === '') return [];
  $raw = (string)(llc_get_setting($db, $uid, 'mcp_servers_json') ?? '[]');
  $items = json_decode($raw, true);
  if (!is_array($items)) return [];
  try { return llc_mcp_normalize_servers_array($items); }
  catch (Throwable $e) {
    llc_dbg_log('mcp_config_error', ['error'=>$e->getMessage()]);
    return [];
  }
}

function llc_mcp_server_by_id(PDO $db, array $u, string $serverId): ?array {
  $serverId = trim($serverId);
  if ($serverId === '') return null;
  foreach (llc_mcp_servers_config($db, $u) as $server) {
    if ((string)($server['id'] ?? '') === $serverId) return $server;
  }
  return null;
}

function &llc_mcp_runtime_cache(): array {
  static $cache = [];
  return $cache;
}

function llc_mcp_runtime_key(array $u, array $server): string {
  return (string)($u['id'] ?? '') . ':' . llc_mcp_chat_scope() . ':' . (string)$server['id'];
}

function llc_mcp_new_runtime(array $server): array {
  return [
    'next_id'=>1,
    'initialized'=>false,
    'resumed'=>false,
    'protocol_version'=>(string)$server['protocol_version'],
    'session_id'=>'',
    'server_info'=>[],
    'tools'=>null,
    'tool_map'=>[],
  ];
}

function llc_mcp_persisted_session_load(PDO $db, array $u, array $server): ?array {
  $uid = trim((string)($u['id'] ?? ''));
  $chatId = llc_mcp_chat_scope();
  $serverId = trim((string)($server['id'] ?? ''));
  if ($uid === '' || $chatId === '' || $serverId === '') return null;
  $st = $db->prepare('SELECT session_id,protocol_version FROM mcp_sessions WHERE user_id=? AND chat_id=? AND server_id=? LIMIT 1');
  $st->execute([$uid, $chatId, $serverId]);
  $row = $st->fetch();
  return is_array($row) ? $row : null;
}

function llc_mcp_persisted_session_save(PDO $db, array $u, array $server, array $runtime): void {
  $uid = trim((string)($u['id'] ?? ''));
  $chatId = llc_mcp_chat_scope();
  $serverId = trim((string)($server['id'] ?? ''));
  $sessionId = trim((string)($runtime['session_id'] ?? ''));
  if ($uid === '' || $chatId === '' || $serverId === '' || $sessionId === '') return;
  $protocolVersion = trim((string)($runtime['protocol_version'] ?? $server['protocol_version'] ?? ''));
  $now = time();
  llc_db_retry_busy(static function() use ($db, $uid, $chatId, $serverId, $sessionId, $protocolVersion, $now): void {
    $st = $db->prepare('INSERT INTO mcp_sessions (user_id,chat_id,server_id,session_id,protocol_version,created_at,updated_at) VALUES (?,?,?,?,?,?,?) ON CONFLICT(user_id,chat_id,server_id) DO UPDATE SET session_id=excluded.session_id, protocol_version=excluded.protocol_version, updated_at=excluded.updated_at');
    $st->execute([$uid, $chatId, $serverId, $sessionId, $protocolVersion, $now, $now]);
  });
}

function llc_mcp_persisted_session_delete(PDO $db, array $u, array $server): void {
  $uid = trim((string)($u['id'] ?? ''));
  $chatId = llc_mcp_chat_scope();
  $serverId = trim((string)($server['id'] ?? ''));
  if ($uid === '' || $chatId === '' || $serverId === '') return;
  $st = $db->prepare('DELETE FROM mcp_sessions WHERE user_id=? AND chat_id=? AND server_id=?');
  $st->execute([$uid, $chatId, $serverId]);
}

function llc_mcp_reset_runtime(PDO $db, array $u, array $server): void {
  llc_mcp_persisted_session_delete($db, $u, $server);
  $cache =& llc_mcp_runtime_cache();
  unset($cache[llc_mcp_runtime_key($u, $server)]);
}

function llc_mcp_session_missing_error(Throwable $e): bool {
  return $e instanceof LlcMcpHttpException && $e->status === 404;
}

function llc_mcp_parse_sse_json(string $body, $expectedId = null): ?array {
  $events = preg_split('/\r?\n\r?\n/', trim($body));
  if (!is_array($events)) return null;
  $firstJson = null;
  foreach ($events as $event) {
    $dataLines = [];
    foreach (preg_split('/\r?\n/', (string)$event) ?: [] as $line) {
      if (str_starts_with($line, 'data:')) $dataLines[] = ltrim(substr($line, 5));
    }
    if (!$dataLines) continue;
    $payload = implode("\n", $dataLines);
    if ($payload === '' || $payload === '[DONE]') continue;
    $decoded = json_decode($payload, true);
    if (!is_array($decoded)) continue;
    if ($firstJson === null) $firstJson = $decoded;
    if ($expectedId !== null && array_key_exists('id', $decoded) && (string)$decoded['id'] === (string)$expectedId) return $decoded;
  }
  return $firstJson;
}

function llc_mcp_effective_http_timeout(array $server, array $payload): int {
  $base = (int)($server['timeout_sec'] ?? 3600);
  if ($base < 0) $base = 0;
  if ($base > 2592000) $base = 2592000;

  $method = (string)($payload['method'] ?? '');
  if ($method !== 'tools/call') return $base;

  $arguments = $payload['params']['arguments'] ?? null;
  $hasToolTimeout = is_array($arguments) && array_key_exists('timeout_ms', $arguments);
  $toolTimeoutMs = $hasToolTimeout ? $arguments['timeout_ms'] : null;

  // Explicit timeout_ms: 0 means the process itself is unlimited. The HTTP
  // request must then also remain open indefinitely, regardless of the
  // per-server finite default.
  if ($hasToolTimeout && is_numeric($toolTimeoutMs)) {
    $toolTimeoutMs = (int)$toolTimeoutMs;
    if ($toolTimeoutMs === 0) return 0;
    if ($toolTimeoutMs > 0) {
      $toolSeconds = (int)ceil($toolTimeoutMs / 1000) + 15;
      if ($base === 0) return 0;
      return max($base, $toolSeconds);
    }
  }

  // No explicit tool timeout: use the configured transport timeout. A finite
  // timeout gets a small reserve so the MCP server can return its structured
  // timeout result instead of cURL cutting the socket at the same boundary.
  if ($base === 0) return 0;
  return $base + 15;
}

function llc_mcp_http_post(array $server, array $payload, array &$runtime, bool $allowEmpty = false, ?callable $onWait = null, ?callable $onAbort = null): array {
  if (!function_exists('curl_init')) throw new RuntimeException('PHP extension ext-curl is required for MCP');
  llc_validate_public_http_url((string)$server['url'], 'MCP ' . (string)$server['name'], !empty($server['allow_private']));
  $json = json_encode($payload, llc_mcp_json_flags());
  if (!is_string($json)) throw new RuntimeException('MCP request could not be encoded');

  $responseHeaders = [];
  $responseBody = '';
  $tooLarge = false;
  $maxBytes = (int)$server['max_response_bytes'];
  $headers = [
    'Content-Type: application/json',
    'Accept: application/json, text/event-stream',
    'User-Agent: LocalLightChat-MCP/1',
  ];
  if ((string)($payload['method'] ?? '') !== 'initialize') {
    $headers[] = 'MCP-Protocol-Version: ' . (string)($runtime['protocol_version'] ?: $server['protocol_version']);
  }
  if ((string)$server['token'] !== '') $headers[] = 'Authorization: Bearer ' . (string)$server['token'];
  if ((string)($runtime['session_id'] ?? '') !== '') $headers[] = 'Mcp-Session-Id: ' . (string)$runtime['session_id'];
  foreach ((array)$server['headers'] as $k=>$v) $headers[] = $k . ': ' . $v;

  $httpTimeout = llc_mcp_effective_http_timeout($server, $payload);
  $ch = curl_init((string)$server['url']);
  if ($ch === false) throw new RuntimeException('Could not initialize cURL for MCP');
  $curlOptions = [
    CURLOPT_POST=>true,
    CURLOPT_POSTFIELDS=>$json,
    CURLOPT_HTTPHEADER=>$headers,
    CURLOPT_RETURNTRANSFER=>false,
    CURLOPT_HEADER=>false,
    CURLOPT_FOLLOWLOCATION=>false,
    CURLOPT_CONNECTTIMEOUT=>($httpTimeout === 0 ? 10 : min(10, $httpTimeout)),
    CURLOPT_TIMEOUT=>$httpTimeout,
    CURLOPT_ENCODING=>'',
    CURLOPT_HEADERFUNCTION=>static function($ch, string $line) use (&$responseHeaders): int {
      $len = strlen($line);
      $p = strpos($line, ':');
      if ($p !== false) {
        $name = strtolower(trim(substr($line,0,$p)));
        $value = trim(substr($line,$p+1));
        if ($name !== '') $responseHeaders[$name] = $value;
      }
      return $len;
    },
    CURLOPT_WRITEFUNCTION=>static function($ch, string $chunk) use (&$responseBody, &$tooLarge, $maxBytes): int {
      if ((strlen($responseBody)+strlen($chunk)) > $maxBytes) { $tooLarge = true; return 0; }
      $responseBody .= $chunk;
      return strlen($chunk);
    },
  ];
  $abortRequested = false;
  if ($onWait !== null || $onAbort !== null) {
    $lastHeartbeatAt = microtime(true);
    $progressCallback = static function($ch, $downloadTotal, $downloadNow, $uploadTotal, $uploadNow) use ($onWait, &$lastHeartbeatAt, &$abortRequested): int {
      if (connection_aborted()) {
        $abortRequested = true;
        return 1;
      }
      $now = microtime(true);
      if ($onWait !== null && ($now - $lastHeartbeatAt) >= 15.0) {
        $lastHeartbeatAt = $now;
        try { $onWait(); } catch (Throwable $_) { /* heartbeat must never abort the tool */ }
      }
      return 0;
    };

    // CURLOPT_XFERINFOFUNCTION is unavailable in some PHP/cURL builds.
    // Prefer it when present, otherwise use the older compatible callback.
    $progressOption = null;
    if (defined('CURLOPT_XFERINFOFUNCTION')) {
      $progressOption = constant('CURLOPT_XFERINFOFUNCTION');
    } elseif (defined('CURLOPT_PROGRESSFUNCTION')) {
      $progressOption = constant('CURLOPT_PROGRESSFUNCTION');
    }

    if ($progressOption !== null) {
      if (defined('CURLOPT_NOPROGRESS')) {
        $curlOptions[constant('CURLOPT_NOPROGRESS')] = false;
      }
      $curlOptions[$progressOption] = $progressCallback;
    } else {
      llc_dbg_log('mcp_curl_progress_unavailable', [
        'server'=>(string)($server['id'] ?? $server['name'] ?? ''),
      ]);
    }
  }
  curl_setopt_array($ch, $curlOptions);
  $started = microtime(true);
  $ok = curl_exec($ch);
  $errno = curl_errno($ch);
  $error = curl_error($ch);
  $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
  $contentType = strtolower((string)(curl_getinfo($ch, CURLINFO_CONTENT_TYPE) ?: ($responseHeaders['content-type'] ?? '')));
  curl_close($ch);
  $durationMs = (int)round((microtime(true)-$started)*1000);

  if ($abortRequested && $onAbort !== null) {
    try { $onAbort(); }
    catch (Throwable $abortError) {
      llc_dbg_log('mcp_cancel_after_disconnect_failed', ['error'=>$abortError->getMessage()]);
    }
  }

  if ($tooLarge) throw new RuntimeException('MCP response exceeded ' . $maxBytes . ' bytes');
  if ($ok === false || $errno !== 0) throw new RuntimeException('MCP connection failed: ' . ($error !== '' ? $error : ('cURL error ' . $errno)));
  if ($status < 200 || $status >= 300) {
    $snippet = trim(substr($responseBody,0,1000));
    throw new LlcMcpHttpException($status, 'MCP HTTP ' . $status . ($snippet !== '' ? ': ' . $snippet : ''));
  }
  $sessionId = trim((string)($responseHeaders['mcp-session-id'] ?? ''));
  if ($sessionId !== '') $runtime['session_id'] = $sessionId;
  if (trim($responseBody) === '') {
    if ($allowEmpty || $status === 202 || $status === 204) return ['status'=>$status,'headers'=>$responseHeaders,'body'=>null,'duration_ms'=>$durationMs];
    throw new RuntimeException('MCP returned an empty response');
  }
  $expectedId = $payload['id'] ?? null;
  $decoded = str_contains($contentType,'text/event-stream') ? llc_mcp_parse_sse_json($responseBody, $expectedId) : json_decode($responseBody,true);
  if (!is_array($decoded)) throw new RuntimeException('MCP returned invalid JSON');
  return ['status'=>$status,'headers'=>$responseHeaders,'body'=>$decoded,'duration_ms'=>$durationMs];
}

function llc_mcp_params_value(array $params) {
  // MCP method parameters are objects. PHP encodes an empty array as [],
  // which strict SDK transports reject as an invalid MCP message. Preserve
  // non-empty associative parameter maps, but serialize the empty case as {}.
  return $params === [] ? new stdClass() : $params;
}

function llc_mcp_tool_arguments_value(array $arguments) {
  // MCP CallToolRequest.arguments is an object when present. PHP uses [] for
  // both an empty map and an empty list, so force the empty argument map to {}.
  if ($arguments === []) return new stdClass();
  if (array_is_list($arguments)) {
    throw new RuntimeException('MCP tool arguments must be a JSON object');
  }
  return $arguments;
}

/**
 * Restore JSON-Schema object semantics lost by json_decode(..., true).
 *
 * PHP represents both an empty JSON object ({}) and an empty JSON array ([])
 * as the same value: []. MCP tool schemas legitimately contain empty objects
 * (most visibly `properties: {}` for parameterless tools). If those arrays are
 * forwarded unchanged, strict OpenAI/Azure function-schema validation sees
 * `properties: []` and rejects the complete tool list.
 *
 * Only keywords whose JSON-Schema value is itself a schema object or an object
 * map are coerced. Real schema arrays such as `required`, `enum`, `anyOf`, etc.
 * remain arrays.
 */
function llc_mcp_normalize_json_schema($schema) {
  if (is_object($schema)) return $schema;
  if (!is_array($schema)) return $schema;

  // At a schema-object position, [] can only be the associative representation
  // of {}. A non-empty list is left as a list for legacy tuple-style schemas.
  if ($schema === []) return new stdClass();
  if (array_is_list($schema)) {
    $out = [];
    foreach ($schema as $item) $out[] = llc_mcp_normalize_json_schema($item);
    return $out;
  }

  $objectMapKeywords = [
    'properties'=>true,
    'patternProperties'=>true,
    '$defs'=>true,
    'definitions'=>true,
    'dependentSchemas'=>true,
  ];
  $singleSchemaKeywords = [
    'items'=>true,
    'additionalItems'=>true,
    'contains'=>true,
    'additionalProperties'=>true,
    'unevaluatedProperties'=>true,
    'unevaluatedItems'=>true,
    'propertyNames'=>true,
    'not'=>true,
    'if'=>true,
    'then'=>true,
    'else'=>true,
    'contentSchema'=>true,
  ];
  $schemaArrayKeywords = [
    'allOf'=>true,
    'anyOf'=>true,
    'oneOf'=>true,
    'prefixItems'=>true,
  ];

  $out = $schema;
  foreach ($out as $key => $value) {
    if (isset($objectMapKeywords[$key])) {
      if ($value === []) {
        $out[$key] = new stdClass();
        continue;
      }
      if (is_array($value) && !array_is_list($value)) {
        $map = [];
        foreach ($value as $name => $childSchema) {
          $map[$name] = llc_mcp_normalize_json_schema($childSchema);
        }
        $out[$key] = $map;
      }
      continue;
    }

    if (isset($singleSchemaKeywords[$key])) {
      $out[$key] = llc_mcp_normalize_json_schema($value);
      continue;
    }

    if (isset($schemaArrayKeywords[$key]) && is_array($value)) {
      $items = [];
      foreach ($value as $childSchema) $items[] = llc_mcp_normalize_json_schema($childSchema);
      $out[$key] = $items;
    }
  }
  return $out;
}

/** Build a provider-safe object schema for OpenAI-compatible function tools. */
function llc_mcp_openai_parameters_schema($rawSchema): array {
  $schema = is_array($rawSchema) ? $rawSchema : [];
  if ($schema === [] || array_is_list($schema)) $schema = [];

  $normalized = llc_mcp_normalize_json_schema($schema);
  if (is_object($normalized)) $schema = [];
  elseif (is_array($normalized)) $schema = $normalized;
  else $schema = [];

  // MCP inputSchema should already be an object schema, but force the contract
  // expected by OpenAI-compatible function calling instead of forwarding an
  // invalid top-level type from a third-party server.
  $schema['type'] = 'object';

  $properties = $schema['properties'] ?? null;
  if ($properties === [] || $properties === null) {
    $schema['properties'] = new stdClass();
  } elseif (!is_array($properties) && !is_object($properties)) {
    $schema['properties'] = new stdClass();
  } elseif (is_array($properties) && array_is_list($properties)) {
    // A non-empty JSON array cannot be a JSON-Schema `properties` object.
    $schema['properties'] = new stdClass();
  }

  return $schema;
}

function llc_mcp_request(array $server, array &$runtime, string $method, array $params = [], ?callable $onWait = null, ?callable $onAbort = null): array {
  $id = (int)$runtime['next_id'];
  $runtime['next_id'] = $id + 1;
  $response = llc_mcp_http_post($server, ['jsonrpc'=>'2.0','id'=>$id,'method'=>$method,'params'=>llc_mcp_params_value($params)], $runtime, false, $onWait, $onAbort);
  $body = $response['body'] ?? null;
  if (!is_array($body)) throw new RuntimeException('MCP returned no JSON-RPC response');
  if (isset($body['error']) && is_array($body['error'])) {
    $message = (string)($body['error']['message'] ?? 'Unknown MCP error');
    $code = isset($body['error']['code']) ? ' (' . (string)$body['error']['code'] . ')' : '';
    throw new RuntimeException($message . $code);
  }
  if (!array_key_exists('result',$body)) throw new RuntimeException('MCP response has no result');
  return ['result'=>$body['result'],'duration_ms'=>(int)$response['duration_ms']];
}

function llc_mcp_notify(array $server, array &$runtime, string $method, array $params = []): void {
  llc_mcp_http_post($server, ['jsonrpc'=>'2.0','method'=>$method,'params'=>llc_mcp_params_value($params)], $runtime, true);
}

function &llc_mcp_runtime(PDO $db, array $u, array $server): array {
  $cache =& llc_mcp_runtime_cache();
  $key = llc_mcp_runtime_key($u,$server);
  if (!isset($cache[$key])) {
    $cache[$key] = llc_mcp_new_runtime($server);
    $persisted = llc_mcp_persisted_session_load($db, $u, $server);
    if (is_array($persisted)) {
      $persistedSessionId = trim((string)($persisted['session_id'] ?? ''));
      if ($persistedSessionId !== '') {
        $cache[$key]['session_id'] = $persistedSessionId;
        $persistedProtocol = trim((string)($persisted['protocol_version'] ?? ''));
        if ($persistedProtocol !== '') $cache[$key]['protocol_version'] = $persistedProtocol;
        // The gateway session was initialized by an earlier PHP request. Do not
        // send initialize again; MCP explicitly rejects re-initializing a live session.
        $cache[$key]['initialized'] = true;
        $cache[$key]['resumed'] = true;
      }
    }
  }
  $runtime =& $cache[$key];
  if (empty($runtime['initialized'])) {
    $init = llc_mcp_request($server,$runtime,'initialize',[
      'protocolVersion'=>(string)$server['protocol_version'],
      'capabilities'=>new stdClass(),
      'clientInfo'=>['name'=>'LocalLightChat','version'=>'mcp-draft-1'],
    ]);
    $result = is_array($init['result']) ? $init['result'] : [];
    $negotiated = trim((string)($result['protocolVersion'] ?? ''));
    if ($negotiated !== '') $runtime['protocol_version'] = $negotiated;
    $runtime['server_info'] = is_array($result['serverInfo'] ?? null) ? $result['serverInfo'] : [];
    llc_mcp_notify($server,$runtime,'notifications/initialized',[]);
    $runtime['initialized'] = true;
    $runtime['resumed'] = false;
    llc_mcp_persisted_session_save($db, $u, $server, $runtime);
  }
  return $runtime;
}

function llc_mcp_list_tools(PDO $db, array $u, array $server, bool $force = false, bool $allowSessionRecovery = true): array {
  $runtime =& llc_mcp_runtime($db,$u,$server);
  if (!$force && is_array($runtime['tools'])) return $runtime['tools'];
  $all=[]; $cursor=null;
  try {
    for ($page=0;$page<20;$page++) {
      $response = llc_mcp_request($server,$runtime,'tools/list',$cursor===null?[]:['cursor'=>$cursor]);
      $result = is_array($response['result']) ? $response['result'] : [];
      foreach ((array)($result['tools'] ?? []) as $tool) if (is_array($tool)) $all[]=$tool;
      $next = trim((string)($result['nextCursor'] ?? ''));
      if ($next==='') break;
      $cursor=$next;
    }
  } catch (Throwable $e) {
    // A persisted session can legitimately disappear after gateway restart or
    // idle expiry. 404 means the request was not forwarded to the old child, so
    // discarding the stale binding and initializing one fresh session is safe.
    if ($allowSessionRecovery && llc_mcp_session_missing_error($e)) {
      llc_mcp_reset_runtime($db, $u, $server);
      return llc_mcp_list_tools($db, $u, $server, $force, false);
    }
    throw $e;
  }
  $runtime['tools']=$all;
  return $all;
}

function llc_mcp_safe_openai_tool_name(string $serverId, string $remoteName): string {
  $sid = preg_replace('/[^A-Za-z0-9_]+/','_',$serverId) ?? 'server';
  $rname = preg_replace('/[^A-Za-z0-9_]+/','_',$remoteName) ?? 'tool';
  $base = 'mcp_' . trim($sid,'_') . '__' . trim($rname,'_');
  if ($base==='mcp___') $base='mcp_tool';
  if (strlen($base)<=64) return $base;
  return substr($base,0,54) . '_' . substr(hash('sha256',$serverId."\0".$remoteName),0,9);
}

function llc_mcp_tool_meta(array $remote): array {
  $meta = $remote['_meta'] ?? [];
  return is_array($meta) ? $meta : [];
}

function llc_mcp_tool_required_modalities(array $remote): array {
  $meta = llc_mcp_tool_meta($remote);
  $requirements = $meta['com.locallightai/modelRequirements'] ?? [];
  if (!is_array($requirements)) return [];
  $mods = $requirements['inputModalities'] ?? [];
  if (!is_array($mods)) return [];
  $out = [];
  foreach ($mods as $modality) {
    $m = strtolower(trim((string)$modality));
    if ($m !== '') $out[$m] = true;
  }
  return array_keys($out);
}

function llc_mcp_tool_image_handling(array $remote): string {
  $meta = llc_mcp_tool_meta($remote);
  $handling = $meta['com.locallightai/outputHandling'] ?? [];
  if (!is_array($handling)) return 'both';
  $mode = strtolower(trim((string)($handling['image'] ?? 'both')));
  return in_array($mode, ['model_context','user_visible','both'], true) ? $mode : 'both';
}

function llc_mcp_tool_allowed_for_capabilities(array $remote, array $capabilities): bool {
  foreach (llc_mcp_tool_required_modalities($remote) as $modality) {
    if (array_key_exists($modality, $capabilities) && $capabilities[$modality] === false) return false;
  }
  return true;
}

function llc_mcp_filter_openai_tools_for_capabilities(array $tools, array $capabilities): array {
  if (!$tools) return [];
  $out = [];
  foreach ($tools as $tool) {
    $name = is_array($tool) && is_array($tool['function'] ?? null) ? (string)($tool['function']['name'] ?? '') : '';
    if ($name !== '' && str_starts_with($name, 'mcp_')) {
      $mapping = llc_mcp_find_tool_mapping($name);
      if (is_array($mapping) && !llc_mcp_tool_allowed_for_capabilities((array)($mapping['remote'] ?? []), $capabilities)) continue;
    }
    $out[] = $tool;
  }
  return $out;
}

function llc_mcp_openai_tools(PDO $db, array $u, array $enabledServerIds, array &$warnings = [], array $modelCapabilities = []): array {
  $enabled=[];
  foreach ($enabledServerIds as $id) { $id=trim((string)$id); if ($id!=='') $enabled[$id]=true; }
  if (!$enabled) return [];
  $tools=[]; $used=[];
  foreach (llc_mcp_servers_config($db,$u) as $server) {
    $serverId=(string)$server['id'];
    if (empty($enabled[$serverId])) continue;
    try {
      $remoteTools=llc_mcp_list_tools($db,$u,$server);
      $runtime =& llc_mcp_runtime($db,$u,$server);
      foreach ($remoteTools as $remote) {
        $remoteName=trim((string)($remote['name'] ?? ''));
        if ($remoteName==='') continue;
        if (!llc_mcp_tool_allowed_for_capabilities($remote, $modelCapabilities)) continue;
        $openaiName=llc_mcp_safe_openai_tool_name($serverId,$remoteName);
        if (isset($used[$openaiName])) $openaiName=substr($openaiName,0,54).'_'.substr(hash('sha256',$remoteName),0,9);
        $used[$openaiName]=true;
        $schema=llc_mcp_openai_parameters_schema($remote['inputSchema'] ?? null);
        $description=trim((string)($remote['description'] ?? ''));
        $tools[]=['type'=>'function','function'=>[
          'name'=>$openaiName,
          'description'=>'[MCP: '.(string)$server['name'].'] '.($description!==''?$description:$remoteName),
          'parameters'=>$schema,
        ]];
        $runtime['tool_map'][$openaiName]=['server'=>$server,'remote_name'=>$remoteName,'remote'=>$remote];
      }
    } catch (Throwable $e) {
      $warnings[]=(string)$server['name'].': '.$e->getMessage();
      llc_dbg_log('mcp_discovery_error',['server'=>$serverId,'error'=>$e->getMessage()]);
    }
  }
  return $tools;
}

function llc_mcp_find_tool_mapping(string $openaiName): ?array {
  $cache =& llc_mcp_runtime_cache();
  foreach ($cache as $runtime) {
    if (isset($runtime['tool_map'][$openaiName]) && is_array($runtime['tool_map'][$openaiName])) return $runtime['tool_map'][$openaiName];
  }
  return null;
}


function llc_mcp_process_result_is_running(array $result): bool {
  $structured = is_array($result['structuredContent'] ?? null) ? $result['structuredContent'] : [];
  $status = strtolower(trim((string)($structured['status'] ?? '')));
  return !empty($structured['running']) || in_array($status, ['running','starting'], true);
}

function llc_mcp_process_result_job_id(array $result): string {
  $structured = is_array($result['structuredContent'] ?? null) ? $result['structuredContent'] : [];
  return trim((string)($structured['job_id'] ?? ''));
}

/**
 * Live process activity is intentionally more generous than persisted chat
 * activity. About 8k tokens at the same cheap 4 chars/token approximation is
 * enough to watch compilers and other CLI tools without feeding unbounded
 * stdout/stderr through SSE or the browser DOM.
 */
function llc_mcp_process_live_preview_max_chars(): int {
  return 8000 * 4;
}

/**
 * Fetch a bounded stdout/stderr snapshot for UI progress only. process_wait
 * deliberately omits output while a job is running, whereas process_status
 * exposes the current capture tail. Failure to obtain a preview must never
 * fail the underlying tool call.
 */
function llc_mcp_emit_process_progress(array $server, array &$runtime,
  string $jobId, ?callable $onProgress, ?callable $onWait = null,
  ?callable $onAbort = null): void {
  if ($onProgress === null || $jobId === '') return;
  try {
    $statusResponse = llc_mcp_request($server, $runtime, 'tools/call', [
      'name'=>'process_status',
      'arguments'=>[
        'job_id'=>$jobId,
        'include_output'=>true,
        // The server applies this separately to stdout and stderr. The UI
        // callback applies one final combined 8k-token tail afterwards.
        'max_output_chars'=>llc_mcp_process_live_preview_max_chars(),
      ],
    ], $onWait, $onAbort);
    $statusResult = is_array($statusResponse['result'] ?? null) ? $statusResponse['result'] : [];
    $structured = is_array($statusResult['structuredContent'] ?? null)
      ? $statusResult['structuredContent'] : [];
    if ($structured) $onProgress($structured);
  } catch (Throwable $_) {
    // Preview telemetry is best-effort; process execution remains authoritative.
  }
}

/**
 * Follow a finite managed process without exposing intermediate polling to the
 * model. process_wait remains the authoritative completion poll; while the job
 * is running we may additionally sample bounded process_status output for the
 * browser activity stream. The final process_wait response remains unchanged
 * and still carries the complete server-captured output for model context.
 */
function llc_mcp_follow_exec_job(array $server, array &$runtime, array $initialResponse,
  array $execArguments = [], ?callable $onWait = null,
  ?callable $onAbort = null, ?callable $onProgress = null): array {
  if (array_key_exists('follow_exec_jobs', $server) && empty($server['follow_exec_jobs'])) {
    return $initialResponse;
  }

  $result = is_array($initialResponse['result'] ?? null) ? $initialResponse['result'] : [];
  $jobId = llc_mcp_process_result_job_id($result);
  if ($jobId === '') return $initialResponse;

  $durationMs = max(0, (int)($initialResponse['duration_ms'] ?? 0));
  $pollWaitMs = max(250, min(60000, (int)($server['exec_follow_poll_ms'] ?? 5000)));
  // When a browser is watching process output, refresh roughly once per second.
  // Without a progress consumer keep the historical polling cadence unchanged.
  if ($onProgress !== null) $pollWaitMs = min($pollWaitMs, 1000);
  $lifetimeTimeoutMs = max(0, (int)($execArguments['timeout_ms'] ?? 0));
  $watchdogGraceMs = max(5000, $pollWaitMs + 2000);

  if (llc_mcp_process_result_is_running($result)) {
    llc_mcp_emit_process_progress($server, $runtime, $jobId, $onProgress, $onWait, $onAbort);
  }

  while (llc_mcp_process_result_is_running($result)) {
    // The MCP server owns the real process timeout. This is only a client-side
    // fail-safe so a buggy/older server cannot keep the browser activity open
    // forever after the caller supplied a finite lifetime timeout.
    if ($lifetimeTimeoutMs > 0 && $durationMs >= ($lifetimeTimeoutMs + $watchdogGraceMs)) {
      try {
        llc_mcp_request($server, $runtime, 'tools/call', [
          'name'=>'process_cancel',
          'arguments'=>['job_id'=>$jobId],
        ], $onWait, $onAbort);
      } catch (Throwable $_) {
        // Keep producing a truthful synthetic timeout result below even if the
        // emergency cancellation request itself failed.
      }
      $structured = is_array($result['structuredContent'] ?? null)
        ? $result['structuredContent'] : [];
      $structured['job_id'] = $jobId;
      $structured['status'] = 'timeout';
      $structured['success'] = false;
      $structured['running'] = false;
      $structured['continuation_required'] = false;
      $structured['timed_out'] = true;
      $structured['client_timeout_watchdog'] = true;
      $structured['requested_timeout_ms'] = $lifetimeTimeoutMs;
      $result['structuredContent'] = $structured;
      $result['isError'] = true;
      $result['content'] = [[
        'type'=>'text',
        'text'=>'PROCESS STOPPED BY CLIENT TIMEOUT WATCHDOG. The MCP server did not finalize the managed job within the requested lifetime timeout plus a short termination grace period. An emergency process_cancel was sent.',
      ]];
      break;
    }
    $waitResponse = llc_mcp_request($server, $runtime, 'tools/call', [
      'name'=>'process_wait',
      'arguments'=>[
        'job_id'=>$jobId,
        'wait_ms'=>$pollWaitMs,
        'include_output'=>true,
        'max_output_chars'=>0,
      ],
    ], $onWait, $onAbort);
    $durationMs += max(0, (int)($waitResponse['duration_ms'] ?? 0));
    $result = is_array($waitResponse['result'] ?? null) ? $waitResponse['result'] : [];
    if (llc_mcp_process_result_is_running($result)) {
      llc_mcp_emit_process_progress($server, $runtime, $jobId, $onProgress, $onWait, $onAbort);
    }
    if ($onWait !== null) {
      try { $onWait(); } catch (Throwable $_) { /* heartbeat only */ }
    }
  }

  return ['result'=>$result, 'duration_ms'=>$durationMs];
}

function llc_mcp_call_openai_tool(PDO $db, array $u, string $openaiName, array $arguments, ?callable $onWait = null, ?callable $onAbort = null, ?callable $onProgress = null): array {
  $mapping=llc_mcp_find_tool_mapping($openaiName);
  if (!$mapping) throw new RuntimeException('Unknown or undiscovered MCP tool: '.$openaiName);
  $server=$mapping['server'];
  $remoteName=(string)$mapping['remote_name'];
  // Image-producing MCP tools can contain large Base64 payloads. Tool metadata
  // may request special image handling, so reserve enough response room before
  // detaching the binary payload from the textual tool result.
  if (llc_mcp_tool_image_handling((array)($mapping['remote'] ?? [])) !== 'both' ||
      in_array('image', llc_mcp_tool_required_modalities((array)($mapping['remote'] ?? [])), true)) {
    $server['max_response_bytes'] = max((int)($server['max_response_bytes'] ?? 0), 32 * 1024 * 1024);
  }
  // Finite exec jobs return their complete captured output in the completion
  // response. Allow the largest response size supported by this client config.
  if (in_array($remoteName, ['process_exec','shell_exec'], true)) {
    $server['max_response_bytes'] = max((int)($server['max_response_bytes'] ?? 0), 64 * 1024 * 1024);
  }
  $runtime =& llc_mcp_runtime($db,$u,$server);
  static $runningProcessCommands = [];

  $processCommandKey = '';
  if (in_array($remoteName, ['process_exec','process_start','shell_exec','shell_start'], true)) {
    if (str_starts_with($remoteName, 'process_')) {
      $processCommandKey = (string)$server['id'] . '|direct|' . json_encode([
        'executable'=>(string)($arguments['executable'] ?? ''),
        'arguments'=>array_values(is_array($arguments['arguments'] ?? null) ? $arguments['arguments'] : []),
        'cwd'=>(string)($arguments['cwd'] ?? '.'),
      ], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
    } else {
      $processCommandKey = (string)$server['id'] . '|shell|' . json_encode([
        'command'=>(string)($arguments['command'] ?? ''),
        'shell'=>(string)($arguments['shell'] ?? 'auto'),
        'cwd'=>(string)($arguments['cwd'] ?? '.'),
      ], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
    }
    if ($processCommandKey !== '' && isset($runningProcessCommands[$processCommandKey])) {
      $existingJobId = (string)$runningProcessCommands[$processCommandKey];
      $message = 'Duplicate process launch suppressed. The identical command is already running as job ' . $existingJobId . '. Do not launch it again; use process_wait or process_status with this job_id.';
      return [
        'ok'=>true,'provider'=>'mcp','server_id'=>(string)$server['id'],
        'server'=>(string)$server['name'],'tool'=>$remoteName,'duration_ms'=>0,
        'result'=>['content'=>[['type'=>'text','text'=>$message]],
          'structuredContent'=>['job_id'=>$existingJobId,'status'=>'running','running'=>true,'success'=>true,'duplicate_suppressed'=>true],
          'isError'=>false],
      ];
    }
  }


  try {
    $response=llc_mcp_request($server,$runtime,'tools/call',['name'=>$remoteName,'arguments'=>llc_mcp_tool_arguments_value($arguments)],$onWait,$onAbort);
  } catch (Throwable $e) {
    // Retry only the unambiguous "session does not exist" case. The gateway
    // returns 404 before forwarding the tool call, so this cannot duplicate a
    // command that may already have executed. Network errors are intentionally
    // not retried because their execution state is unknowable.
    if (!llc_mcp_session_missing_error($e)) throw $e;
    llc_mcp_reset_runtime($db, $u, $server);
    $runtime =& llc_mcp_runtime($db, $u, $server);
    $response=llc_mcp_request($server,$runtime,'tools/call',['name'=>$remoteName,'arguments'=>llc_mcp_tool_arguments_value($arguments)],$onWait,$onAbort);
  }
  if (in_array($remoteName, ['process_exec','shell_exec'], true)) {
    $response = llc_mcp_follow_exec_job($server, $runtime, $response,
      $arguments, $onWait, $onAbort, $onProgress);
  }
  $result=is_array($response['result']) ? $response['result'] : ['content'=>$response['result']];
  if ($processCommandKey !== '') {
    $processStructured = is_array($result['structuredContent'] ?? null) ? $result['structuredContent'] : [];
    if (!empty($processStructured['running']) || in_array((string)($processStructured['status'] ?? ''), ['running','starting'], true)) {
      $runningJobId = trim((string)($processStructured['job_id'] ?? $arguments['job_id'] ?? ''));
      if ($runningJobId !== '') $runningProcessCommands[$processCommandKey] = $runningJobId;
    }
  }

  // Do not trust every MCP server to set isError correctly for process
  // cancellation, timeouts, or non-zero exit codes. Normalize those outcomes
  // before the result is returned to the model.
  if (in_array($remoteName, ['process_exec','shell_exec','process_start','shell_start','process_status','process_wait'], true)) {
    $structured=is_array($result['structuredContent'] ?? null) ? $result['structuredContent'] : [];
    $cancelled=!empty($structured['cancelled']) || (($structured['status'] ?? '') === 'cancelled');
    $idleTimedOut=!empty($structured['idle_timed_out']) || (($structured['status'] ?? '') === 'idle_timeout');
    $timedOut=!empty($structured['timed_out']) || (($structured['status'] ?? '') === 'timeout');
    $hasExit=array_key_exists('exit_code',$structured) && $structured['exit_code'] !== null;
    $exitCode=$hasExit ? (int)$structured['exit_code'] : 0;
    $executionError=trim((string)($structured['error'] ?? ''));
    $failedStatus=in_array((string)($structured['status'] ?? ''), ['failed','error'], true);
    $failed=$cancelled || $idleTimedOut || $timedOut || $failedStatus ||
      $executionError!=='' || ($hasExit && $exitCode!==0) ||
      (array_key_exists('success',$structured) && empty($structured['success']));

    if ($failed) {
      $result['isError']=true;
      $kind=$cancelled ? 'cancelled' : ($idleTimedOut ? 'idle_timeout' : ($timedOut ? 'timeout' : 'failed'));
      $message=match($kind) {
        'cancelled' => 'PROCESS CANCELLED BY THE USER. The command did not complete and must not be reported as successful. Partial side effects may remain; verify the system state before retrying.',
        'idle_timeout' => 'PROCESS STOPPED BY IDLE TIMEOUT. The command did not complete and must not be reported as successful.',
        'timeout' => 'PROCESS STOPPED BY TOTAL TIMEOUT. The command did not complete and must not be reported as successful.',
        default => ($executionError!==''
          ? 'PROCESS EXECUTION FAILED: '.$executionError
          : 'PROCESS FAILED'.($hasExit ? ' WITH EXIT CODE '.$exitCode : '').'. The command did not complete successfully.'),
      };

      $existingContent=is_array($result['content'] ?? null) ? $result['content'] : [];
      $firstText='';
      if (isset($existingContent[0]) && is_array($existingContent[0])) {
        $firstText=trim((string)($existingContent[0]['text'] ?? ''));
      }
      if ($firstText==='' || !str_starts_with($firstText,'PROCESS ')) {
        array_unshift($existingContent,['type'=>'text','text'=>$message]);
      }
      $result['content']=$existingContent;
      $result['outcome']=['status'=>$kind,'success'=>false,'message'=>$message];
    }
  }

  return [
    'ok'=>empty($result['isError']),
    'provider'=>'mcp',
    'server_id'=>(string)$server['id'],
    'server'=>(string)$server['name'],
    'tool'=>$remoteName,
    'duration_ms'=>(int)$response['duration_ms'],
    'result'=>$result,
  ];
}

function llc_mcp_cancel_job(PDO $db, array $u, string $serverId, string $jobId): array {
  $server = llc_mcp_server_by_id($db, $u, $serverId);
  if (!$server) throw new RuntimeException('Unknown MCP server: ' . $serverId);
  $jobId = trim($jobId);
  if ($jobId === '') throw new RuntimeException('Missing MCP job_id');

  // Cancellation is expected to be fast even when the normal server timeout is
  // unlimited. Keep this out-of-band request finite.
  $cancelServer = $server;
  $cancelServer['timeout_sec'] = 15;
  $runtime =& llc_mcp_runtime($db, $u, $cancelServer);
  $response = llc_mcp_request($cancelServer, $runtime, 'tools/call', [
    'name'=>'process_cancel',
    'arguments'=>['job_id'=>$jobId],
  ]);
  $result = is_array($response['result'] ?? null) ? $response['result'] : [];
  $structured = is_array($result['structuredContent'] ?? null) ? $result['structuredContent'] : [];
  return [
    'ok'=>empty($result['isError']),
    'server_id'=>$serverId,
    'job_id'=>$jobId,
    'result'=>$structured ?: $result,
  ];
}

function llc_mcp_cancel(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $j = llc_read_json();
  llc_mcp_set_chat_scope(trim((string)($j['chat_id'] ?? '')));
  $serverId = trim((string)($j['server_id'] ?? ''));
  $jobId = trim((string)($j['job_id'] ?? ''));
  if ($serverId === '' || $jobId === '') llc_json(['error'=>'Missing server_id or job_id'], 400);
  try {
    llc_json(llc_mcp_cancel_job($db, $u, $serverId, $jobId));
  } catch (Throwable $e) {
    llc_json(['error'=>$e->getMessage()], 500);
  }
}

function llc_mcp_test(): void {
  $db=llc_db();
  $u=llc_require_user($db);
  $j=llc_read_json();
  $serverRaw=$j['server'] ?? null;
  if (!is_array($serverRaw)) llc_json(['error'=>'Missing MCP server configuration'],400);
  try {
    $server=llc_mcp_normalize_server($serverRaw,0);
    $runtime=llc_mcp_new_runtime($server);
    $init=llc_mcp_request($server,$runtime,'initialize',[
      'protocolVersion'=>(string)$server['protocol_version'],
      'capabilities'=>new stdClass(),
      'clientInfo'=>['name'=>'LocalLightChat MCP test','version'=>'mcp-draft-1'],
    ]);
    $initResult=is_array($init['result']) ? $init['result'] : [];
    $negotiated=trim((string)($initResult['protocolVersion'] ?? ''));
    if ($negotiated!=='') $runtime['protocol_version']=$negotiated;
    llc_mcp_notify($server,$runtime,'notifications/initialized',[]);
    $list=llc_mcp_request($server,$runtime,'tools/list',[]);
    $listResult=is_array($list['result']) ? $list['result'] : [];
    $tools=array_values(array_filter((array)($listResult['tools'] ?? []),'is_array'));
    llc_json([
      'ok'=>true,
      'server'=>$server['name'],
      'protocol_version'=>$runtime['protocol_version'],
      'session_id'=>(string)($runtime['session_id'] ?? ''),
      'server_info'=>$initResult['serverInfo'] ?? new stdClass(),
      'tool_count'=>count($tools),
      'tools'=>array_map(static fn(array $tool): array => ['name'=>(string)($tool['name'] ?? ''),'description'=>(string)($tool['description'] ?? '')],$tools),
      'duration_ms'=>(int)$init['duration_ms']+(int)$list['duration_ms'],
    ]);
  } catch (Throwable $e) {
    llc_json(['error'=>$e->getMessage()],400);
  }
}
