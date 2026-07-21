<?php
declare(strict_types=1);

// Optional per-install config. Create config.php next to api.php if you want to override defaults.
$__llc_cfg = __DIR__ . '/config.php';
if (is_file($__llc_cfg)) {
  require_once $__llc_cfg;
}
unset($__llc_cfg);

// Debug defaults (all optional; set in config.php)
if (!defined('LLC_DEBUG')) define('LLC_DEBUG', false);
// If LLC_DEBUG is on, log to file by default.
if (!defined('LLC_DEBUG_LOG')) define('LLC_DEBUG_LOG', (bool)LLC_DEBUG);
// Optional: emit debug info as SSE status pills (only for streaming endpoints).
if (!defined('LLC_DEBUG_SSE')) define('LLC_DEBUG_SSE', false);
// Optional: on fatal errors during SSE, try to emit an SSE error+done to avoid "hung" UI.
if (!defined('LLC_DEBUG_FATAL_SSE')) define('LLC_DEBUG_FATAL_SSE', (bool)LLC_DEBUG_SSE);
// Where debug logs go (JSONL)
if (!defined('LLC_DEBUG_LOGFILE')) define('LLC_DEBUG_LOGFILE', __DIR__ . '/data/llc-debug.log');
// Where uploaded/generated files are stored. Default: <this folder>/uploads
if (!defined('LLC_UPLOADS_DIR')) define('LLC_UPLOADS_DIR', __DIR__ . '/uploads');
// Where temporary export/job files are stored. Default: <this folder>/tmp
if (!defined('LLC_TMP_DIR')) define('LLC_TMP_DIR', __DIR__ . '/tmp');
// Where managed code workspaces are stored. Keep this path private from the web server.
if (!defined('LLC_WORKSPACES_DIR')) define('LLC_WORKSPACES_DIR', __DIR__ . '/workspaces');

function llc_uploads_dir(): string {
  $dir = trim((string)LLC_UPLOADS_DIR);
  if ($dir === '') $dir = __DIR__ . '/uploads';
  return rtrim($dir, "/\\");
}

function llc_tmp_dir(): string {
  $dir = trim((string)LLC_TMP_DIR);
  if ($dir === '') $dir = __DIR__ . '/tmp';
  return rtrim($dir, "/\\");
}

function llc_workspaces_dir(): string {
  $dir = trim((string)LLC_WORKSPACES_DIR);
  if ($dir === '') $dir = __DIR__ . '/workspaces';
  return rtrim($dir, "/\\");
}

require_once __DIR__ . '/lib/db.php';

header('X-Content-Type-Options: nosniff');

$action = $_GET['action'] ?? '';
if ($action === '') llc_json(['error'=>'Missing action'], 400);

try {
  switch ($action) {
    case 'bootstrap': llc_bootstrap(); break;

    case 'auth_me': llc_auth_me(); break;
    case 'auth_login': llc_auth_login(); break;
    case 'auth_logout': llc_auth_logout(); break;



    case 'user_list': llc_user_list(); break;
    case 'user_create': llc_user_create(); break;
    case 'user_update': llc_user_update(); break;
    case 'user_delete': llc_user_delete(); break;
    case 'user_self_update': llc_user_self_update(); break;

    case 'chat_create': llc_chat_create(); break;
    case 'chat_get': llc_chat_get(); break;
    case 'chat_save': llc_chat_save(); break;
    case 'chat_delete': llc_chat_delete(); break;
    case 'chat_rename': llc_chat_rename(); break;
    case 'chat_auto_rename': llc_chat_auto_rename(); break;
    case 'chat_clone': llc_chat_clone(); break;
    case 'chat_detach': llc_chat_detach(); break;
    case 'chat_compress_clone_sse': llc_chat_compress_clone_sse(); break;
    case 'chat_compress_clone': llc_chat_compress_clone(); break;
    case 'chat_move': llc_chat_move(); break;
    case 'chat_export': llc_chat_export(); break;
    case 'chats_export_all': llc_chats_export_all(); break;
    case 'folder_export': llc_folder_export(); break;
    case 'chat_import': llc_chat_import(); break;
    case 'chat_search': llc_chat_search(); break;

    case 'template_list': llc_template_list(); break;
    case 'template_get': llc_template_get(); break;
    case 'template_create': llc_template_create(); break;
    case 'template_rename': llc_template_rename(); break;
    case 'template_delete': llc_template_delete(); break;

    case 'folder_create': llc_folder_create(); break;
    case 'folder_move': llc_folder_move(); break;
    case 'folder_rename': llc_folder_rename(); break;
    case 'folder_delete': llc_folder_delete(); break;

    case 'conn_list': llc_conn_list(); break;
    case 'conn_save': llc_conn_save(); break;
    case 'conn_delete': llc_conn_delete(); break;
    case 'conn_set_enabled': llc_conn_set_enabled(); break;
    case 'conn_test': llc_conn_test(); break;

    case 'settings_save': llc_settings_save(); break;
    case 'models': llc_models(); break;
    case 'image_openrouter_models': llc_image_openrouter_models(); break;

    case 'file_upload': llc_file_upload(); break;
    case 'file_delete': llc_file_delete(); break;

    case 'workspace_list': llc_workspace_list(); break;
    case 'workspace_create': llc_workspace_create(); break;
    case 'workspace_import': llc_workspace_import(); break;
    case 'workspace_rename': llc_workspace_rename(); break;
    case 'workspace_files': llc_workspace_files(); break;
    case 'workspace_file_create': llc_workspace_file_create(); break;
    case 'workspace_file_upload': llc_workspace_file_upload(); break;
    case 'workspace_file_download': llc_workspace_file_download(); break;
    case 'workspace_file_delete': llc_workspace_file_delete(); break;
    case 'workspace_export': llc_workspace_export(); break;
    case 'workspace_delete': llc_workspace_delete(); break;

    case 'chat_stream': llc_chat_stream(); break;

    case 'voice_transcribe': llc_voice_transcribe(); break;
    case 'voice_speech': llc_voice_speech(); break;
    case 'voice_speech_stream': llc_voice_speech_stream(); break;

    default: llc_json(['error'=>'Unknown action'], 400);
  }
} catch (Throwable $e) {
  llc_json(['error'=>$e->getMessage()], 500);
}

// ---------- helpers ----------
function llc_dbg_enabled(): bool {
  return defined('LLC_DEBUG') && (bool)LLC_DEBUG;
}
function llc_dbg_log(string $tag, array $payload = []): void {
  if (!llc_dbg_enabled() || !defined('LLC_DEBUG_LOG') || !(bool)LLC_DEBUG_LOG) return;
  $line = '[' . gmdate('c') . '] ' . $tag . ' ' . json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
  $line .= "\n";
  $file = (defined('LLC_DEBUG_LOGFILE') ? (string)LLC_DEBUG_LOGFILE : (__DIR__ . '/data/llc-debug.log'));
  $dir = dirname($file);
  if (!is_dir($dir)) @mkdir($dir, 0777, true);
  @file_put_contents($file, $line, FILE_APPEND | LOCK_EX);
}
function llc_dbg_sse(string $tag, array $payload = []): void {
  if (!llc_dbg_enabled() || !defined('LLC_DEBUG_SSE') || !(bool)LLC_DEBUG_SSE) return;
  // Use the existing status pill UI to surface debug info only when explicitly enabled.
  $msg = '[dbg] ' . $tag;
  if (!empty($payload)) {
    $j = json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
    if (is_string($j) && $j !== '' && strlen($j) < 600) $msg .= ' ' . $j;
  }
  llc_sse_send(['type'=>'status','message'=>$msg]);
}


function llc_read_json(): array {
  $raw = file_get_contents('php://input');
  if ($raw === false || trim($raw)==='') return [];
  $j = json_decode($raw, true);
  if (!is_array($j)) throw new RuntimeException('Invalid JSON body');
  return $j;
}
function llc_json($data, int $code=200): void {
  http_response_code($code);
  header('Content-Type: application/json; charset=utf-8');
  echo json_encode($data, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
  exit;
}
function llc_require(array $a, string $k): mixed {
  if (!array_key_exists($k, $a)) throw new RuntimeException("Missing field: $k");
  return $a[$k];
}
function llc_now(): int { return time(); }

function llc_norm_base(string $u): string { return rtrim(trim($u), '/'); }

function llc_base_url(): string {
  $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
  $scheme = $https ? 'https' : 'http';
  $host = $_SERVER['HTTP_HOST'] ?? 'localhost';
  $script = $_SERVER['SCRIPT_NAME'] ?? '';
  $dir = rtrim(str_replace('\\','/', dirname($script)), '/');
  return $scheme . '://' . $host . ($dir ? $dir : '');
}

function llc_conn_by_id(PDO $db, array $u, string $id): ?array {
  return llc_conn_resolve($db, $u, $id);
}

// Some UI surfaces show models as "<prefix>.<model>" (e.g. "OpenAI.gpt-4o").
// Providers expect the raw model id. If a stored model accidentally includes the
// connection prefix, strip it safely.
function llc_strip_model_prefix(string $model, ?array $conn): string {
  $model = trim($model);
  if ($model === '' || !$conn) return $model;
  $p = trim((string)($conn['prefix'] ?? ''));
  if ($p !== '' && str_starts_with($model, $p . '.')) {
    return substr($model, strlen($p) + 1);
  }
  return $model;
}

// Best-effort: infer which connection a given model belongs to by looking at the
// per-user models cache (if present). This helps repair legacy chats that lost
// their connection_id field.
function llc_infer_conn_id_for_model(PDO $db, array $u, string $uid, string $model): string {
  $uid = (string)trim($uid);
  $model = trim($model);
  if ($uid === '' || $model === '') return '';

  $cache_json = llc_get_setting($db, $uid, 'models_cache_json') ?? '';
  if (!is_string($cache_json) || trim($cache_json) === '') return '';
  $cache = json_decode($cache_json, true);
  if (!is_array($cache)) return '';

  $alts = [$model];
  if (str_contains($model, '.')) {
    $pos = strrpos($model, '.');
    if ($pos !== false && $pos+1 < strlen($model)) $alts[] = substr($model, $pos+1);
  }

  $hits = [];
  foreach ($alts as $want) {
    $want = trim((string)$want);
    if ($want === '') continue;
    foreach ($cache as $m) {
      if (!is_array($m)) continue;
      $mid = (string)($m['id'] ?? '');
      $mlabel = (string)($m['label'] ?? '');
      $cid = trim((string)($m['connection_id'] ?? ''));
      if ($cid === '') continue;

      $match = false;
      if ($mid !== '' && $mid === $want) $match = true;
      if (!$match && $mlabel !== '' && ($mlabel === $want || str_ends_with($mlabel, '.' . $want))) $match = true;
      if ($match) $hits[$cid] = true;
    }
  }

  $cids = array_keys($hits);
  if (count($cids) !== 1) return '';
  $cid = (string)$cids[0];
  if (!llc_conn_accessible($db, $u, $cid)) return '';
  $conn = llc_conn_by_id($db, $u, $cid);
  if (!$conn) return '';
  if ((int)($conn['enabled'] ?? 1) !== 1) return '';
  return $cid;
}

function llc_custom_headers(string $raw): array {
  $hdrs = [];
  $raw = trim($raw);
  if ($raw === '') return $hdrs;
  $asJson = json_decode($raw, true);
  if (is_array($asJson)) {
    foreach ($asJson as $k=>$v){
      if (is_string($k) && (is_string($v) || is_numeric($v))) $hdrs[] = $k . ': ' . (string)$v;
    }
    return $hdrs;
  }
  $lines = preg_split('/\r?\n/', $raw);
  foreach ($lines as $line){
    $line = trim($line);
    if ($line !== '' && str_contains($line, ':')) $hdrs[] = $line;
  }
  return $hdrs;
}


// ---------- auth ----------
function llc_set_session_cookie(string $token, int $expiresAt): void {
  $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
  // PHP 7.3+ setcookie options array
  setcookie('llc_session', $token, [
    'expires' => $expiresAt,
    'path' => '/',
    'secure' => $https,
    'httponly' => true,
    'samesite' => 'Lax',
  ]);
}

function llc_clear_session_cookie(): void {
  $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
  setcookie('llc_session', '', [
    'expires' => time() - 3600,
    'path' => '/',
    'secure' => $https,
    'httponly' => true,
    'samesite' => 'Lax',
  ]);
}

function llc_session_user(PDO $db): ?array {
  $tok = $_COOKIE['llc_session'] ?? '';
  if (!is_string($tok) || $tok === '') return null;

  $hash = hash('sha256', $tok);
  $st = $db->prepare("SELECT u.id,u.username,u.email,u.role,s.expires_at FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? LIMIT 1");
  $st->execute([$hash]);
  $r = $st->fetch();
  if (!$r) return null;

  if ((int)$r['expires_at'] < time()) {
    $st2 = $db->prepare("DELETE FROM sessions WHERE token_hash=?");
    $st2->execute([$hash]);
    return null;
  }

  return [
    'id' => (string)$r['id'],
    'username' => (string)$r['username'],
    'email' => $r['email'] !== null ? (string)$r['email'] : null,
    'role' => (string)$r['role'],
  ];
}

function llc_require_user(PDO $db): array {
  $u = llc_session_user($db);
  if (!$u) llc_json(['error'=>'Unauthorized'], 401);
  return $u;
}

function llc_auth_me(): void {
  $db = llc_db();
  $u = llc_session_user($db);
  if (!$u) llc_json(['logged_in'=>false]);
  llc_json(['logged_in'=>true, 'user'=>$u]);
}

function llc_auth_login(): void {
  $db = llc_db();
  $j = llc_read_json();
  $identifier = trim((string)llc_require($j, 'identifier'));
  // Accept both legacy {password} and neutral {secret} to avoid browser password-manager heuristics.
  $password = '';
  if (isset($j['secret'])) $password = (string)$j['secret'];
  else if (isset($j['password'])) $password = (string)$j['password'];
  if ($password === '') {
    llc_json(['error'=>'Missing password'], 400);
  }

  $st = $db->prepare("SELECT id,username,email,pass_hash,role FROM users WHERE username=? OR email=? LIMIT 1");
  $st->execute([$identifier, $identifier]);
  $u = $st->fetch();
  if (!$u || !password_verify($password, (string)$u['pass_hash'])) {
    llc_json(['error'=>'Invalid credentials'], 401);
  }

  $token = bin2hex(random_bytes(32));
  $tokenHash = hash('sha256', $token);
  $expiresAt = time() + 60*60*24*30;

  $st2 = $db->prepare("INSERT INTO sessions (token_hash,user_id,created_at,expires_at) VALUES (?,?,?,?)");
  $st2->execute([$tokenHash, (string)$u['id'], time(), $expiresAt]);

  llc_set_session_cookie($token, $expiresAt);

  llc_json(['ok'=>true, 'user'=>[
    'id'=>(string)$u['id'],
    'username'=>(string)$u['username'],
    'email'=>$u['email'] !== null ? (string)$u['email'] : null,
    'role'=>(string)$u['role'],
  ]]);
}

function llc_auth_logout(): void {
  $db = llc_db();
  $tok = $_COOKIE['llc_session'] ?? '';
  if (is_string($tok) && $tok !== '') {
    $hash = hash('sha256', $tok);
    $st = $db->prepare("DELETE FROM sessions WHERE token_hash=?");
    $st->execute([$hash]);
  }
  llc_clear_session_cookie();
  llc_json(['ok'=>true]);
}

// ---------- users ----------
function llc_require_admin(PDO $db): array {
  $u = llc_require_user($db);
  $r = (string)($u['role'] ?? 'user');
  if ($r !== 'admin' && $r !== 'superadmin') llc_json(['error'=>'Forbidden'], 403);
  return $u;
}

function llc_require_superadmin(PDO $db): array {
  $u = llc_require_user($db);
  $r = (string)($u['role'] ?? 'user');
  if ($r !== 'superadmin') llc_json(['error'=>'Forbidden'], 403);
  return $u;
}

function llc_is_admin_user(array $u): bool {
  $r = (string)($u['role'] ?? 'user');
  return $r === 'admin' || $r === 'superadmin';
}

function llc_is_superadmin_user(array $u): bool {
  return (string)($u['role'] ?? 'user') === 'superadmin';
}


// When older code paths pass only a user id (string) instead of the full user array,
// we resolve a minimal user stub (id + role) so config helpers still work.
// This is a backwards-compatibility shim for mixed deployments.
function llc_user_stub_by_id(PDO $db, string $uid): ?array {
  $uid = trim($uid);
  if ($uid === '') return null;
  try {
    $st = $db->prepare("SELECT id, role FROM users WHERE id=? LIMIT 1");
    $st->execute([$uid]);
    $r = $st->fetch();
    if (!is_array($r)) return ['id'=>$uid,'role'=>'user'];
    $id = (string)($r['id'] ?? $uid);
    if ($id === '') $id = $uid;
    $role = (string)($r['role'] ?? 'user');
    if ($role === '') $role = 'user';
    return ['id'=>$id,'role'=>$role];
  } catch (Throwable $e) {
    return ['id'=>$uid,'role'=>'user'];
  }
}


function llc_user_bool_setting(PDO $db, string $uid, string $k, bool $default=false): bool {
  $v = llc_get_setting($db, $uid, $k);
  if ($v === null) return $default;
  return (string)$v === '1';
}

function llc_can_manage_own_connections(PDO $db, array $u): bool {
  if (llc_is_admin_user($u)) return true;
  $uid = (string)($u['id'] ?? '');
  if ($uid === '') return false;
  return llc_user_bool_setting($db, $uid, 'allow_own_connections', false);
}

function llc_inherit_global_connections(PDO $db, array $u): bool {
  if (llc_is_superadmin_user($u)) return false;
  $uid = (string)($u['id'] ?? '');
  if ($uid === '') return false;
  return llc_user_bool_setting($db, $uid, 'inherit_global_connections', true);
}

// Search permission flag:
// - inherit_global_search: if enabled (typical for "user" role), search settings (provider/keys/urls/locale)
//   are inherited from shared global_settings and are read-only for the user.
function llc_inherit_global_search(PDO $db, array $u): bool {
  $role = (string)($u['role'] ?? 'user');
  if ($role !== 'user') return false;
  $uid = (string)($u['id'] ?? '');
  if ($uid === '') return false;
  return llc_user_bool_setting($db, $uid, 'inherit_global_search', true);
}

function llc_use_global_search(PDO $db, array $u): bool {
  // Superadmins edit the shared global settings directly.
  return llc_is_superadmin_user($u) || llc_inherit_global_search($db, $u);
}

function llc_search_cfg_get(PDO $db, $u, string $k): ?string {
  // Newer code passes the full user array; older code sometimes passes just a user id.
  if (is_array($u)) {
    $uid = (string)($u['id'] ?? '');
    if ($uid === '') return null;
    if (function_exists('llc_use_global_search') && llc_use_global_search($db, $u)) return llc_get_global_setting($db, $k);
    return llc_get_setting($db, $uid, $k);
  }

  $uid = trim((string)$u);
  if ($uid === '') return null;
  $uu = llc_user_stub_by_id($db, $uid) ?? ['id'=>$uid,'role'=>'user'];

  if (function_exists('llc_use_global_search') && llc_use_global_search($db, $uu)) return llc_get_global_setting($db, $k);

  $v = llc_get_setting($db, $uid, $k);
  if ($v !== null) return $v;

  // Safe fallback: inherited global when present.
  return function_exists('llc_get_global_setting') ? llc_get_global_setting($db, $k) : null;
}

// Legacy: kept for compatibility with older code paths.
function llc_search_settings_owner_id(PDO $db, $u): string {
  if (is_array($u)) return (string)($u['id'] ?? '');
  return trim((string)$u);
}

// Image permission flag:
// - inherit_global_image: if enabled (typical for "user" role), image settings (provider/keys/defaults/ComfyUI)
//   are inherited from shared global_settings and are read-only for the user.
function llc_inherit_global_image(PDO $db, array $u): bool {
  $role = (string)($u['role'] ?? 'user');
  if ($role !== 'user') return false;
  $uid = (string)($u['id'] ?? '');
  if ($uid === '') return false;
  return llc_user_bool_setting($db, $uid, 'inherit_global_image', true);
}

function llc_use_global_image(PDO $db, array $u): bool {
  // Superadmins edit the shared global settings directly.
  return llc_is_superadmin_user($u) || llc_inherit_global_image($db, $u);
}

// Web permission flag:
// - inherit_global_web: if enabled (typical for "user" role), web tool settings (SSRF allow_private + limits)
//   are inherited from shared global_settings and are read-only for the user.
function llc_inherit_global_web(PDO $db, array $u): bool {
  $role = (string)($u['role'] ?? 'user');
  if ($role !== 'user') return false;
  $uid = (string)($u['id'] ?? '');
  if ($uid === '') return false;
  return llc_user_bool_setting($db, $uid, 'inherit_global_web', true);
}

function llc_use_global_web(PDO $db, array $u): bool {
  // Superadmins edit the shared global settings directly.
  return llc_is_superadmin_user($u) || llc_inherit_global_web($db, $u);
}

function llc_web_cfg_get(PDO $db, $u, string $k): ?string {
  if (is_array($u)) {
    $uid = (string)($u['id'] ?? '');
    if ($uid === '') return null;
    if (function_exists('llc_use_global_web') && llc_use_global_web($db, $u)) return llc_get_global_setting($db, $k);
    return llc_get_setting($db, $uid, $k);
  }

  $uid = trim((string)$u);
  if ($uid === '') return null;
  $uu = llc_user_stub_by_id($db, $uid) ?? ['id'=>$uid,'role'=>'user'];

  if (function_exists('llc_use_global_web') && llc_use_global_web($db, $uu)) return llc_get_global_setting($db, $k);

  $v = llc_get_setting($db, $uid, $k);
  if ($v !== null) return $v;

  return function_exists('llc_get_global_setting') ? llc_get_global_setting($db, $k) : null;
}



// Voice permission flag:
// - inherit_global_voice: if enabled (typical for "user" role), voice settings (API key + TTS provider/model/voice)
//   are inherited from shared global_settings and are read-only for the user.
function llc_inherit_global_voice(PDO $db, array $u): bool {
  $role = (string)($u['role'] ?? 'user');
  if ($role !== 'user') return false;
  $uid = (string)($u['id'] ?? '');
  if ($uid === '') return false;
  return llc_user_bool_setting($db, $uid, 'inherit_global_voice', true);
}

function llc_use_global_voice(PDO $db, array $u): bool {
  // Superadmins edit the shared global settings directly.
  return llc_is_superadmin_user($u) || llc_inherit_global_voice($db, $u);
}

function llc_voice_cfg_get(PDO $db, $u, string $k): ?string {
  if (is_array($u)) {
    $uid = (string)($u['id'] ?? '');
    if ($uid === '') return null;
    if (function_exists('llc_use_global_voice') && llc_use_global_voice($db, $u)) return llc_get_global_setting($db, $k);
    return llc_get_setting($db, $uid, $k);
  }

  $uid = trim((string)$u);
  if ($uid === '') return null;
  $uu = llc_user_stub_by_id($db, $uid) ?? ['id'=>$uid,'role'=>'user'];

  if (function_exists('llc_use_global_voice') && llc_use_global_voice($db, $uu)) return llc_get_global_setting($db, $k);

  $v = llc_get_setting($db, $uid, $k);
  if ($v !== null) return $v;

  return function_exists('llc_get_global_setting') ? llc_get_global_setting($db, $k) : null;
}

function llc_image_cfg_get(PDO $db, $u, string $k): ?string {
  if (is_array($u)) {
    $uid = (string)($u['id'] ?? '');
    if ($uid === '') return null;
    if (function_exists('llc_use_global_image') && llc_use_global_image($db, $u)) return llc_get_global_setting($db, $k);
    return llc_get_setting($db, $uid, $k);
  }

  $uid = trim((string)$u);
  if ($uid === '') return null;
  $uu = llc_user_stub_by_id($db, $uid) ?? ['id'=>$uid,'role'=>'user'];

  if (function_exists('llc_use_global_image') && llc_use_global_image($db, $uu)) return llc_get_global_setting($db, $k);

  $v = llc_get_setting($db, $uid, $k);
  if ($v !== null) return $v;

  return function_exists('llc_get_global_setting') ? llc_get_global_setting($db, $k) : null;
}

// Backwards-compatible aliases (older deployments used names without underscores).
if (!function_exists('llcimagecfg_get')) {
  function llcimagecfg_get(PDO $db, $u, string $k): ?string { return llc_image_cfg_get($db, $u, $k); }
}
if (!function_exists('llcwebcfg_get')) {
  function llcwebcfg_get(PDO $db, $u, string $k): ?string { return llc_web_cfg_get($db, $u, $k); }
}
if (!function_exists('llcsearchcfg_get')) {
  function llcsearchcfg_get(PDO $db, $u, string $k): ?string { return llc_search_cfg_get($db, $u, $k); }
}
if (!function_exists('llcvoicecfg_get')) {
  function llcvoicecfg_get(PDO $db, $u, string $k): ?string { return llc_voice_cfg_get($db, $u, $k); }
}



// Legacy: kept for compatibility with older code paths.
function llc_image_settings_owner_id(PDO $db, $u): string {
  if (is_array($u)) return (string)($u['id'] ?? '');
  return trim((string)$u);
}

function llc_superadmin_ids(PDO $db): array {
  $rows = $db->query("SELECT id FROM users WHERE role='superadmin' ORDER BY created_at ASC")->fetchAll();
  $ids = [];
  foreach ($rows as $r) {
    if (!empty($r['id'])) $ids[] = (string)$r['id'];
  }
  // Backstop: older DBs *should* always have u_admin.
  if (empty($ids)) $ids[] = 'u_admin';
  return $ids;
}

// List connections a user can see/use.
// - Global connections are stored in global_connections (shared across all superadmins).
// - Non-superadmins may inherit globals as read-only (no secrets, no edits).
// - Regular users may or may not be allowed to create/manage their own connections.
// NOTE: This is the public-facing connection list for the logged-in user.
// - For inherited/global connections we normally hide secrets (api_key/headers).
// - For internal server operations (e.g. calling remote /models), callers can pass
//   $includeSecretsForGlobal=true to keep secrets available while still returning
//   the same rows.
function llc_connections_for_user(PDO $db, array $u, bool $includeSecretsForEditable=true, bool $includeSecretsForGlobal=false): array {
  $uid = (string)($u['id'] ?? '');
  $out = [];

  $canOwn = llc_can_manage_own_connections($db, $u);
  $inheritGlobals = llc_inherit_global_connections($db, $u);
  $isSuper = llc_is_superadmin_user($u);

  // Global first (shared table).
  if ($inheritGlobals || $isSuper) {
    $rows = $db->query("SELECT id,label,prefix,base_url,enabled,api_key,headers,notes,created_at,updated_at FROM global_connections ORDER BY created_at ASC")->fetchAll();
    foreach ($rows as $r) {
      $r['readonly'] = $isSuper ? 0 : 1;

      // Only superadmins may view/edit secrets. Regular users/admins only get masked
      // copies unless the caller explicitly asks for secrets (internal usage).
      if ($isSuper) {
        if (!$includeSecretsForEditable) { $r['api_key'] = ''; $r['headers'] = ''; }
      } else {
        if (!$includeSecretsForGlobal) { $r['api_key'] = ''; $r['headers'] = ''; }
      }

      $out[] = $r;
    }
  }

  // Own connections
  if ($canOwn && $uid !== '') {
    $st = $db->prepare("SELECT id,label,prefix,base_url,enabled,api_key,headers,notes,created_at,updated_at,user_id FROM connections WHERE user_id=? ORDER BY created_at ASC");
    $st->execute([$uid]);
    $rows = $st->fetchAll();
    foreach ($rows as $r) {
      $r['readonly'] = 0;
      if (!$includeSecretsForEditable) { $r['api_key'] = ''; $r['headers'] = ''; }
      $out[] = $r;
    }
  }

  // De-dup by id and prefer writable / rows with secrets if needed.
  $dedup = [];
  $seen = [];
  foreach ($out as $row) {
    $id = (string)($row['id'] ?? '');
    if ($id === '') continue;

    if (!isset($seen[$id])) {
      $seen[$id] = count($dedup);
      $dedup[] = $row;
      continue;
    }

    $ix = $seen[$id];
    $cur = $dedup[$ix];

    // Prefer writable rows.
    $curRo = (int)($cur['readonly'] ?? 0);
    $newRo = (int)($row['readonly'] ?? 0);
    if ($curRo === 1 && $newRo === 0) {
      $dedup[$ix] = $row;
      continue;
    }

    // Prefer rows that still contain secrets (for internal callers).
    $curKey = trim((string)($cur['api_key'] ?? ''));
    $newKey = trim((string)($row['api_key'] ?? ''));
    $curHdr = trim((string)($cur['headers'] ?? ''));
    $newHdr = trim((string)($row['headers'] ?? ''));
    if (($curKey === '' && $newKey !== '') || ($curHdr === '' && $newHdr !== '')) {
      $dedup[$ix] = $row;
      continue;
    }
  }

  return $dedup;
}



function llc_conn_accessible(PDO $db, array $u, string $connId): bool {
  $connId = trim($connId);
  if ($connId === '') return false;
  $uid = (string)($u['id'] ?? '');

  // Own
  if (llc_can_manage_own_connections($db, $u) && $uid !== '') {
    $st = $db->prepare("SELECT 1 FROM connections WHERE id=? AND user_id=?");
    $st->execute([$connId, $uid]);
    if ($st->fetchColumn()) return true;
  }

  // Global (shared table).
  // NOTE: Since the global-connection refactor, shared connections live in `global_connections`.
  // The old implementation looked into `connections` for superadmin-owned rows, which breaks
  // selection + chat persistence (settings_save/chat_save silently drop connection_id).
  if (llc_inherit_global_connections($db, $u) || llc_is_superadmin_user($u)) {
    $st = $db->prepare("SELECT 1 FROM global_connections WHERE id=?");
    $st->execute([$connId]);
    if ($st->fetchColumn()) return true;

    // Backward-compat: older DBs may still store shared rows in `connections` under superadmins.
    // Keep this fallback so upgrades remain robust.
    try {
      $sa = llc_superadmin_ids($db);
      $ph = implode(',', array_fill(0, count($sa), '?'));
      $st2 = $db->prepare("SELECT 1 FROM connections WHERE id=? AND user_id IN ($ph)");
      $st2->execute(array_merge([$connId], $sa));
      if ($st2->fetchColumn()) return true;
    } catch (Throwable $_) {
      // ignore
    }
  }
  return false;
}

// Resolve a connection row with secrets for internal usage.
function llc_conn_resolve(PDO $db, array $u, string $connId): ?array {
  $connId = trim($connId);
  if ($connId === '') return null;
  $uid = (string)($u['id'] ?? '');

  // Own connection
  if (llc_can_manage_own_connections($db, $u) && $uid !== '') {
    $st = $db->prepare("SELECT * FROM connections WHERE id=? AND user_id=? LIMIT 1");
    $st->execute([$connId, $uid]);
    $r = $st->fetch();
    if ($r) return $r;
  }

  // Global connection (shared table)
  if (llc_inherit_global_connections($db, $u) || llc_is_superadmin_user($u)) {
    $st = $db->prepare("SELECT * FROM global_connections WHERE id=? LIMIT 1");
    $st->execute([$connId]);
    $r = $st->fetch();
    if ($r) return $r;
  }

  return null;
}



function llc_user_list(): void {
  $db = llc_db();
  llc_require_admin($db);
  $rows = $db->query("SELECT id,username,email,role,created_at,updated_at FROM users ORDER BY created_at ASC")->fetchAll();

  // Attach connection permission flags per user.
  foreach ($rows as &$r) {
    $uid = (string)($r['id'] ?? '');
    if ($uid !== '' && function_exists('llc_ensure_default_settings')) llc_ensure_default_settings($db, $uid);
    $role = (string)($r['role'] ?? 'user');
    $inherit = ($role === 'superadmin') ? 0 : (llc_user_bool_setting($db, $uid, 'inherit_global_connections', true) ? 1 : 0);
    $allowOwn = ($role === 'user') ? (llc_user_bool_setting($db, $uid, 'allow_own_connections', false) ? 1 : 0) : 1;
    $inheritWeb = ($role === 'user') ? (llc_user_bool_setting($db, $uid, 'inherit_global_web', true) ? 1 : 0) : 0;
    $inheritSearch = ($role === 'user') ? (llc_user_bool_setting($db, $uid, 'inherit_global_search', true) ? 1 : 0) : 0;
    $inheritImage = ($role === 'user') ? (llc_user_bool_setting($db, $uid, 'inherit_global_image', true) ? 1 : 0) : 0;
    $inheritVoice = ($role === 'user') ? (llc_user_bool_setting($db, $uid, 'inherit_global_voice', true) ? 1 : 0) : 0;
    $r['inherit_global_connections'] = $inherit;
    $r['allow_own_connections'] = $allowOwn;
    $r['inherit_global_web'] = $inheritWeb;
    $r['inherit_global_search'] = $inheritSearch;
    $r['inherit_global_image'] = $inheritImage;
    $r['inherit_global_voice'] = $inheritVoice;
  }
  unset($r);

  llc_json(['users'=>$rows]);
}

function llc_user_create(): void {
  $db = llc_db();
  $actor = llc_require_admin($db);
  $j = llc_read_json();

  $username = trim((string)llc_require($j, 'username'));
  $password = (string)llc_require($j, 'password');
  $email = array_key_exists('email', $j) ? trim((string)$j['email']) : '';
  $role = array_key_exists('role', $j) ? (string)$j['role'] : 'user';
  if ($username === '') llc_json(['error'=>'Username required'], 400);
  if ($password === '' || strlen($password) < 4) llc_json(['error'=>'Password too short'], 400);
  // Only superadmins can create superadmins.
  if ($role === 'superadmin') {
    if (!llc_is_superadmin_user($actor)) $role = 'user';
  } else if ($role === 'admin') {
    // ok
  } else {
    $role = 'user';
  }

  $inheritGlobals = array_key_exists('inherit_global_connections', $j) ? ((int)$j['inherit_global_connections'] !== 0) : true;
  $allowOwn = array_key_exists('allow_own_connections', $j) ? ((int)$j['allow_own_connections'] !== 0) : null;
  $inheritWeb = array_key_exists('inherit_global_web', $j) ? ((int)$j['inherit_global_web'] !== 0) : true;
  $inheritSearch = array_key_exists('inherit_global_search', $j) ? ((int)$j['inherit_global_search'] !== 0) : true;
  $inheritImage = array_key_exists('inherit_global_image', $j) ? ((int)$j['inherit_global_image'] !== 0) : true;
  $inheritVoice = array_key_exists('inherit_global_voice', $j) ? ((int)$j['inherit_global_voice'] !== 0) : true;

  $id = 'u_' . bin2hex(random_bytes(8));
  $now = time();

  $emailDb = null;
  if ($email !== '') {
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) llc_json(['error'=>'Invalid email'], 400);
    $emailDb = $email;
  }

  try {
    $st = $db->prepare("INSERT INTO users (id,username,email,pass_hash,role,created_at,updated_at) VALUES (?,?,?,?,?,?,?)");
    $st->execute([$id, $username, $emailDb, password_hash($password, PASSWORD_DEFAULT), $role, $now, $now]);
  } catch (Throwable $e) {
    // Most likely UNIQUE constraint
    llc_json(['error'=>'User already exists (username/email)'], 409);
  }

  // Seed per-user defaults
  if (function_exists('llc_ensure_default_settings')) {
    llc_ensure_default_settings($db, $id);
  }

  // Apply explicit connection permission flags (if provided)
  llc_set_setting($db, $id, 'inherit_global_connections', $inheritGlobals ? '1' : '0');
  if ($role === 'user') {
    if ($allowOwn !== null) llc_set_setting($db, $id, 'allow_own_connections', $allowOwn ? '1' : '0');
  } else {
    // Admin/superadmin always has own connections enabled.
    llc_set_setting($db, $id, 'allow_own_connections', '1');
  }

  // Apply web inheritance (if provided). Only "user" role can inherit global web settings.
  if ($role === 'user') {
    llc_set_setting($db, $id, 'inherit_global_web', $inheritWeb ? '1' : '0');
  } else {
    llc_set_setting($db, $id, 'inherit_global_web', '0');
  }

  // Apply search inheritance (if provided). Only "user" role can inherit global search.
  if ($role === 'user') {
    llc_set_setting($db, $id, 'inherit_global_search', $inheritSearch ? '1' : '0');
  } else {
    llc_set_setting($db, $id, 'inherit_global_search', '0');
  }

  // Apply image inheritance (if provided). Only "user" role can inherit global image settings.
  if ($role === 'user') {
    llc_set_setting($db, $id, 'inherit_global_image', $inheritImage ? '1' : '0');
  } else {
    llc_set_setting($db, $id, 'inherit_global_image', '0');
  }

  // Apply voice inheritance (if provided). Only \"user\" role can inherit global voice settings.
  if ($role === 'user') {
    llc_set_setting($db, $id, 'inherit_global_voice', $inheritVoice ? '1' : '0');
  } else {
    llc_set_setting($db, $id, 'inherit_global_voice', '0');
  }

  $u = $db->prepare("SELECT id,username,email,role,created_at,updated_at FROM users WHERE id=? LIMIT 1");
  $u->execute([$id]);
  llc_json(['ok'=>true, 'user'=>$u->fetch()]);
}

function llc_user_update(): void {
  $db = llc_db();
  $actor = llc_require_admin($db);
  $j = llc_read_json();
  $id = trim((string)llc_require($j, 'id'));
  if ($id === '') llc_json(['error'=>'Missing id'], 400);

  $st0 = $db->prepare("SELECT id,username,email,role FROM users WHERE id=? LIMIT 1");
  $st0->execute([$id]);
  $cur = $st0->fetch();
  if (!$cur) llc_json(['error'=>'User not found'], 404);

  // Only a superadmin may modify a superadmin account.
  if ((string)($cur['role'] ?? 'user') === 'superadmin' && !llc_is_superadmin_user($actor)) {
    llc_json(['error'=>'Forbidden'], 403);
  }

  $fields = [];
  $vals = [];
  $now = time();
  $roleAfter = (string)($cur['role'] ?? 'user');

  // email
  if (array_key_exists('email', $j)) {
    $email = trim((string)$j['email']);
    if ($email === '') {
      $fields[] = "email=NULL";
    } else {
      if (!filter_var($email, FILTER_VALIDATE_EMAIL)) llc_json(['error'=>'Invalid email'], 400);
      $fields[] = "email=?";
      $vals[] = $email;
    }
  }

  // role toggle (user/admin/superadmin)
  if (array_key_exists('role', $j)) {
    $req = (string)$j['role'];
    $newRole = 'user';
    if ($req === 'admin') $newRole = 'admin';
    else if ($req === 'superadmin' && llc_is_superadmin_user($actor)) $newRole = 'superadmin';

    $curRole = (string)($cur['role'] ?? 'user');
    $isCurAdminType = ($curRole === 'admin' || $curRole === 'superadmin');
    $isNewAdminType = ($newRole === 'admin' || $newRole === 'superadmin');

    // Prevent losing all admin access.
    if ($isCurAdminType && !$isNewAdminType) {
      $cnt = (int)$db->query("SELECT COUNT(*) AS c FROM users WHERE role IN ('admin','superadmin')")->fetch()['c'];
      if ($cnt <= 1) llc_json(['error'=>'Cannot remove last admin'], 409);
    }

    // Prevent removing the last superadmin.
    if ($curRole === 'superadmin' && $newRole !== 'superadmin') {
      $cntSA = (int)$db->query("SELECT COUNT(*) AS c FROM users WHERE role='superadmin'")->fetch()['c'];
      if ($cntSA <= 1) llc_json(['error'=>'Cannot remove last superadmin'], 409);
    }

    $fields[] = "role=?";
    $vals[] = $newRole;

    $roleAfter = $newRole;
  }

  // password reset
  if (array_key_exists('password', $j) && (string)$j['password'] !== '') {
    $pw = (string)$j['password'];
    if (strlen($pw) < 4) llc_json(['error'=>'Password too short'], 400);
    $fields[] = "pass_hash=?";
    $vals[] = password_hash($pw, PASSWORD_DEFAULT);
  }

  // Connection permission flags (stored in settings)
  $finalRole = $roleAfter;

  $wantInherit = array_key_exists('inherit_global_connections', $j) ? ((int)$j['inherit_global_connections'] !== 0) : null;
  $wantAllowOwn = array_key_exists('allow_own_connections', $j) ? ((int)$j['allow_own_connections'] !== 0) : null;
  $wantWebInherit = array_key_exists('inherit_global_web', $j) ? ((int)$j['inherit_global_web'] !== 0) : null;
  $wantSearchInherit = array_key_exists('inherit_global_search', $j) ? ((int)$j['inherit_global_search'] !== 0) : null;
  $wantImageInherit = array_key_exists('inherit_global_image', $j) ? ((int)$j['inherit_global_image'] !== 0) : null;
  $wantVoiceInherit = array_key_exists('inherit_global_voice', $j) ? ((int)$j['inherit_global_voice'] !== 0) : null;

  $settingChanges = ($wantInherit !== null) || ($wantAllowOwn !== null) || ($wantWebInherit !== null) || ($wantSearchInherit !== null) || ($wantImageInherit !== null) || ($wantVoiceInherit !== null);

  if (empty($fields) && !$settingChanges) llc_json(['ok'=>true]);

  $fields[] = "updated_at=?";
  $vals[] = $now;

  $vals[] = $id;
  $sql = "UPDATE users SET " . implode(",", $fields) . " WHERE id=?";
  try {
    $st = $db->prepare($sql);
    $st->execute($vals);
  } catch (Throwable $e) {
    llc_json(['error'=>'Update failed (maybe email already used)'], 409);
  }

  // Apply per-user connection permission settings.
  if ($settingChanges) {
    if ($wantInherit !== null) {
      // superadmin doesn't need to inherit (their connections are the global ones).
      if ($finalRole === 'superadmin') llc_set_setting($db, $id, 'inherit_global_connections', '0');
      else llc_set_setting($db, $id, 'inherit_global_connections', $wantInherit ? '1' : '0');
    }
    if ($wantAllowOwn !== null) {
      if ($finalRole === 'user') {
        llc_set_setting($db, $id, 'allow_own_connections', $wantAllowOwn ? '1' : '0');
      } else {
        // Admin/superadmin always has own connections.
        llc_set_setting($db, $id, 'allow_own_connections', '1');
      }

      // If own connections were just disabled, clear selection if it points to a private connection.
      if ($finalRole === 'user' && $wantAllowOwn === false) {
        $sel = llc_get_setting($db, $id, 'selected_connection_id') ?? '';
        if ($sel !== '') {
          $stC = $db->prepare("SELECT 1 FROM connections WHERE id=? AND user_id=? LIMIT 1");
          $stC->execute([$sel, $id]);
          if ($stC->fetchColumn()) llc_set_setting($db, $id, 'selected_connection_id', '');
        }
      }
    }

    // Web inheritance: only "user" role can inherit.
    if ($wantWebInherit !== null) {
      if ($finalRole === 'user') llc_set_setting($db, $id, 'inherit_global_web', $wantWebInherit ? '1' : '0');
      else llc_set_setting($db, $id, 'inherit_global_web', '0');
    } else {
      // If the role was changed away from "user", enforce non-inherit.
      if ($finalRole !== 'user') llc_set_setting($db, $id, 'inherit_global_web', '0');
    }

    // Search inheritance: only "user" role can inherit.
    if ($wantSearchInherit !== null) {
      if ($finalRole === 'user') llc_set_setting($db, $id, 'inherit_global_search', $wantSearchInherit ? '1' : '0');
      else llc_set_setting($db, $id, 'inherit_global_search', '0');
    } else {
      // If the role was changed away from "user", enforce non-inherit to avoid surprising admin accounts.
      if ($finalRole !== 'user') llc_set_setting($db, $id, 'inherit_global_search', '0');
    }

    // Image inheritance: only "user" role can inherit.
    if ($wantImageInherit !== null) {
      if ($finalRole === 'user') llc_set_setting($db, $id, 'inherit_global_image', $wantImageInherit ? '1' : '0');
      else llc_set_setting($db, $id, 'inherit_global_image', '0');
    } else {
      // If the role was changed away from "user", enforce non-inherit to avoid surprising admin accounts.
      if ($finalRole !== 'user') llc_set_setting($db, $id, 'inherit_global_image', '0');
    }

    // Voice inheritance: only "user" role can inherit.
    if ($wantVoiceInherit !== null) {
      if ($finalRole === 'user') llc_set_setting($db, $id, 'inherit_global_voice', $wantVoiceInherit ? '1' : '0');
      else llc_set_setting($db, $id, 'inherit_global_voice', '0');
    } else {
      if ($finalRole !== 'user') llc_set_setting($db, $id, 'inherit_global_voice', '0');
    }

  }

  $u = $db->prepare("SELECT id,username,email,role,created_at,updated_at FROM users WHERE id=? LIMIT 1");
  $u->execute([$id]);
  llc_json(['ok'=>true, 'user'=>$u->fetch()]);
}


function llc_user_delete(): void {
  $db = llc_db();
  $admin = llc_require_admin($db);
  $j = llc_read_json();
  $id = trim((string)llc_require($j, 'id'));
  if ($id === '') llc_json(['error'=>'Missing id'], 400);

  // Don't allow deleting yourself from the UI (avoids foot-guns)
  if (isset($admin['id']) && (string)$admin['id'] === $id) {
    llc_json(['error'=>'Cannot delete your own user'], 409);
  }

  $st0 = $db->prepare("SELECT id,username,role FROM users WHERE id=? LIMIT 1");
  $st0->execute([$id]);
  $cur = $st0->fetch();
  if (!$cur) llc_json(['error'=>'User not found'], 404);

  // Only superadmin may delete a superadmin.
  if ((string)($cur['role'] ?? 'user') === 'superadmin' && !llc_is_superadmin_user($admin)) {
    llc_json(['error'=>'Forbidden'], 403);
  }

  // Prevent deleting the last admin-type account.
  $curRole = (string)($cur['role'] ?? 'user');
  if ($curRole === 'admin' || $curRole === 'superadmin') {
    $cnt = (int)$db->query("SELECT COUNT(*) AS c FROM users WHERE role IN ('admin','superadmin')")->fetch()['c'];
    if ($cnt <= 1) llc_json(['error'=>'Cannot delete last admin'], 409);
  }

  // Prevent deleting the last superadmin.
  if ($curRole === 'superadmin') {
    $cntSA = (int)$db->query("SELECT COUNT(*) AS c FROM users WHERE role='superadmin'")->fetch()['c'];
    if ($cntSA <= 1) llc_json(['error'=>'Cannot delete last superadmin'], 409);
  }

  $workspaceIds = [];
  try {
    $stw = $db->prepare("SELECT id FROM workspaces WHERE user_id=?");
    $stw->execute([$id]);
    $workspaceIds = array_map(fn($r)=>(string)$r['id'], $stw->fetchAll(PDO::FETCH_ASSOC));
  } catch (Throwable $_) { /* older database during migration edge case */ }

  $st = $db->prepare("DELETE FROM users WHERE id=?");
  $st->execute([$id]);
  foreach ($workspaceIds as $workspaceId) {
    try { llc_workspace_remove_tree(llc_workspace_base_dir($workspaceId)); } catch (Throwable $_) { /* best effort */ }
  }

  llc_json(['ok'=>true]);
}

function llc_user_self_update(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];
  $j = llc_read_json();

  $fields = [];
  $vals = [];
  $now = time();

  // email
  if (array_key_exists('email', $j)) {
    $email = trim((string)$j['email']);
    if ($email === '') {
      $fields[] = "email=NULL";
    } else {
      if (!filter_var($email, FILTER_VALIDATE_EMAIL)) llc_json(['error'=>'Invalid email'], 400);
      $fields[] = "email=?";
      $vals[] = $email;
    }
  }

  // password change (requires current_password)
  if (array_key_exists('new_password', $j) && (string)$j['new_password'] !== '') {
    $curPw = (string)($j['current_password'] ?? '');
    if ($curPw === '') llc_json(['error'=>'Current password required'], 400);

    $st0 = $db->prepare("SELECT pass_hash FROM users WHERE id=? LIMIT 1");
    $st0->execute([$uid]);
    $row = $st0->fetch();
    if (!$row || !password_verify($curPw, (string)$row['pass_hash'])) {
      llc_json(['error'=>'Current password wrong'], 401);
    }

    $pw = (string)$j['new_password'];
    if (strlen($pw) < 4) llc_json(['error'=>'Password too short'], 400);
    $fields[] = "pass_hash=?";
    $vals[] = password_hash($pw, PASSWORD_DEFAULT);
  }

  if (empty($fields)) llc_json(['ok'=>true]);

  $fields[] = "updated_at=?";
  $vals[] = $now;

  $vals[] = $uid;
  $sql = "UPDATE users SET " . implode(",", $fields) . " WHERE id=?";
  try {
    $st = $db->prepare($sql);
    $st->execute($vals);
  } catch (Throwable $e) {
    llc_json(['error'=>'Update failed (maybe email already used)'], 409);
  }

  $u2 = $db->prepare("SELECT id,username,email,role,created_at,updated_at FROM users WHERE id=? LIMIT 1");
  $u2->execute([$uid]);
  llc_json(['ok'=>true, 'user'=>$u2->fetch()]);
}



// ---------- tool calling ----------
function llc_tools_enabled(array $j): bool {
  $wt = $j['webtools'] ?? null;
  if (!is_array($wt)) return false;
  // Tools can be enabled independently (web read, web search, image generation).
  // If we forget to include a toggle here, the tool loop never runs and the model
  // can only answer with text.
  return (!empty($wt['web']) || !empty($wt['search']) || !empty($wt['image']) || !empty($wt['document']) || !empty($wt['code_workspace']) || !empty($wt['custom_tools']));
}

function llc_tools_for_request(bool $enableWebRead, bool $enableWebSearch, bool $enableImage, bool $enableDocument = false, bool $enableWorkspace = false, string $workspaceAccess = 'read'): array {
  $tools = [];

  if ($enableWebRead) {
    $tools[] = [
      'type' => 'function',
      'function' => [
        'name' => 'web_read',
        'description' => 'Fetch a URL and extract the main article text (title, author, plaintext) using a readability parser. Use this when you need the content behind a link.',
        'parameters' => [
          'type' => 'object',
          'properties' => [
            'url' => ['type' => 'string', 'description' => 'HTTP(S) URL to read'],
            'max_chars' => ['type' => 'integer', 'description' => 'Maximum characters of extracted text to return (0 = unlimited; defaults to your Settings → Web limit)'],
          ],
          'required' => ['url']
        ]
      ]
    ];
  }

  if ($enableWebSearch) {
    $tools[] = [
      'type' => 'function',
      'function' => [
        'name' => 'web_search',
        'description' => 'Run a web search (Serper.dev or Serper-like custom API). Returns a compact list of results with titles, snippets and links. Use this when you need to find sources for a topic.',
        'parameters' => [
          'type' => 'object',
          'properties' => [
            'q' => ['type' => 'string', 'description' => 'Search query'],
            'type' => ['type' => 'string', 'description' => 'Either "search" (default) or "news"', 'enum' => ['search','news']],
            'gl' => ['type' => 'string', 'description' => 'Geo, e.g. de, us'],
            'hl' => ['type' => 'string', 'description' => 'Language, e.g. de, en'],
            'num' => ['type' => 'integer', 'description' => 'Number of results (1-20)'],
            'page' => ['type' => 'integer', 'description' => 'Page number (>=1)'],
            'autocorrect' => ['type' => 'boolean', 'description' => 'Allow autocorrect (default true)'],
          ],
          'required' => ['q']
        ]
      ]
    ];
  }


  if ($enableImage) {
    $tools[] = [
      'type' => 'function',
      'function' => [
        'name' => 'image_generate',
        'description' => 'Generate an image from a text prompt using the configured Image provider (Settings → Image). Always extract explicit user directives such as image size (e.g. 768x768), steps, seed, batch count, CFG/guidance, and negative prompt into the matching structured parameters instead of leaving them only in the prompt. Example: generate a cat, 5 steps, 768x768 must call image_generate with prompt=a cat, steps=5, size=768x768, width=768, height=768. The result will be attached as an image to the current assistant message.',
        'parameters' => [
          'type' => 'object',
          'properties' => [
            'prompt' => ['type' => 'string', 'description' => 'Describe the image content only. Do not include technical generation directives here if they can be represented by width/height/size/steps/seed/guidance/batch_size/negative_prompt.'],
            // ComfyUI FLUX/SD3 workflows can have separate text inputs.
            // If omitted, the backend falls back to `prompt`.
            'prompt_clip_l' => ['type' => 'string', 'description' => 'Prompt for CLIP-L (ComfyUI FLUX/SD3 only; optional)'],
            'prompt_t5xxl' => ['type' => 'string', 'description' => 'Prompt for T5-XXL (ComfyUI FLUX/SD3 only; optional)'],
            'n' => ['type' => 'integer', 'description' => 'How many images to generate (default 1)'],
            'size' => ['type' => 'string', 'description' => 'Image size (e.g., 768x768 or 1024x1024) or "auto"; for stable-diffusion.cpp this is also converted to width/height.'],
            'quality' => ['type' => 'string', 'description' => 'Image quality (auto/high/medium/low or hd/standard for DALL·E models)'],
            'background' => ['type' => 'string', 'description' => 'Background (auto/transparent/opaque) — GPT image models only'],
            'output_format' => ['type' => 'string', 'description' => 'Output format (png/jpeg/webp) — GPT image models only'],
            'seed' => ['type' => 'integer', 'description' => 'Seed (ComfyUI / stable-diffusion.cpp; -1 = random)'],
            'steps' => ['type' => 'integer', 'description' => 'Steps (ComfyUI / stable-diffusion.cpp)'],
            'guidance' => ['type' => 'number', 'description' => 'Guidance/CFG (ComfyUI / stable-diffusion.cpp)'],
            'cfg_scale' => ['type' => 'number', 'description' => 'CFG scale for stable-diffusion.cpp when explicitly requested'],
            'negative_prompt' => ['type' => 'string', 'description' => 'Negative prompt (stable-diffusion.cpp only; optional)'],
            'sampling_method' => ['type' => 'string', 'description' => 'Sampling method for stable-diffusion.cpp when explicitly requested'],
            'scheduler' => ['type' => 'string', 'description' => 'Scheduler for stable-diffusion.cpp when explicitly requested'],
            'flow_shift' => ['type' => 'number', 'description' => 'Flow shift for stable-diffusion.cpp when explicitly requested'],
            'width' => ['type' => 'integer', 'description' => 'Width (ComfyUI / stable-diffusion.cpp)'],
            'height' => ['type' => 'integer', 'description' => 'Height (ComfyUI / stable-diffusion.cpp)'],
            'batch_size' => ['type' => 'integer', 'description' => 'Batch size (ComfyUI / stable-diffusion.cpp)'],
          ],
          'required' => ['prompt']
        ]
      ]
    ];
  }

  if ($enableWorkspace) {
    $tools[] = [
      'type'=>'function',
      'function'=>[
        'name'=>'workspace_tree',
        'description'=>'List files and directories in the active code workspace. Start here to understand project structure instead of asking for the whole project context.',
        'parameters'=>[
          'type'=>'object',
          'properties'=>[
            'path'=>['type'=>'string','description'=>'Relative directory path; empty means workspace root'],
            'depth'=>['type'=>'integer','description'=>'Maximum recursive depth, 1-12'],
            'max_entries'=>['type'=>'integer','description'=>'Maximum returned entries, 1-1000'],
            'include_ignored'=>['type'=>'boolean','description'=>'Include dependency/cache directories such as .git, node_modules and vendor'],
          ]
        ]
      ]
    ];
    $tools[] = [
      'type'=>'function',
      'function'=>[
        'name'=>'workspace_search',
        'description'=>'Search text files in the active code workspace, similar to grep. Returns matching paths, line numbers and snippets without loading whole files into model context. Prefer this for locating identifiable text; read surrounding lines only when they are actually needed.',
        'parameters'=>[
          'type'=>'object',
          'properties'=>[
            'query'=>['type'=>'string','description'=>'Text or PCRE-compatible regular expression to search for'],
            'path'=>['type'=>'string','description'=>'Relative file or directory to search; empty means workspace root'],
            'regex'=>['type'=>'boolean','description'=>'Interpret query as regular expression'],
            'case_sensitive'=>['type'=>'boolean','description'=>'Use case-sensitive matching'],
            'include'=>['type'=>'string','description'=>'Optional relative glob, e.g. *.php or assets/**/*.js'],
            'max_matches'=>['type'=>'integer','description'=>'Maximum matches, 1-300'],
            'include_ignored'=>['type'=>'boolean','description'=>'Include dependency/cache directories such as .git, node_modules and vendor'],
          ],
          'required'=>['query']
        ]
      ]
    ];
    $tools[] = [
      'type'=>'function',
      'function'=>[
        'name'=>'workspace_read',
        'description'=>'Read a bounded line range from a text file in the active code workspace. Read the smallest useful range for local questions or edits; broader or complete reads are appropriate only when the task genuinely requires overall file understanding. Returns numbered lines and a SHA-256 hash for safe subsequent edits.',
        'parameters'=>[
          'type'=>'object',
          'properties'=>[
            'path'=>['type'=>'string','description'=>'Relative file path'],
            'start_line'=>['type'=>'integer','description'=>'First line, starting at 1'],
            'end_line'=>['type'=>'integer','description'=>'Last line; at most 1000 lines per call'],
          ],
          'required'=>['path']
        ]
      ]
    ];
    if ($workspaceAccess === 'write') {
      $tools[] = [
        'type'=>'function',
        'function'=>[
          'name'=>'workspace_write',
          'description'=>'Create a new text file or replace the complete contents of an existing text file. Prefer workspace_replace for small targeted edits. Supply expected_sha256 when overwriting a file previously read.',
          'parameters'=>[
            'type'=>'object',
            'properties'=>[
              'path'=>['type'=>'string','description'=>'Relative file path'],
              'content'=>['type'=>'string','description'=>'Complete new file content'],
              'expected_sha256'=>['type'=>'string','description'=>'Optional hash returned by workspace_read; edit fails if the file changed'],
              'create'=>['type'=>'boolean','description'=>'Allow creating a missing file; defaults to true'],
            ],
            'required'=>['path','content']
          ]
        ]
      ];
      $tools[] = [
        'type'=>'function',
        'function'=>[
          'name'=>'workspace_replace',
          'description'=>'Perform a precise literal or regular-expression replacement in one text file. Prefer this for local, unambiguous edits after obtaining the current hash with the smallest useful read. Do not read the whole file merely because an edit was requested. The edit is applied only when the match count equals expected_replacements, and a snapshot is created automatically.',
          'parameters'=>[
            'type'=>'object',
            'properties'=>[
              'path'=>['type'=>'string','description'=>'Relative file path'],
              'search'=>['type'=>'string','description'=>'Exact text or PCRE-compatible regular expression'],
              'replacement'=>['type'=>'string','description'=>'Replacement text; regex replacements may use $1 etc.'],
              'regex'=>['type'=>'boolean','description'=>'Interpret search as regular expression'],
              'expected_replacements'=>['type'=>'integer','description'=>'Exact number of replacements required'],
              'expected_sha256'=>['type'=>'string','description'=>'Required hash returned by workspace_read'],
              'dry_run'=>['type'=>'boolean','description'=>'Count matches without changing the file'],
            ],
            'required'=>['path','search','replacement','expected_replacements','expected_sha256']
          ]
        ]
      ];
      $tools[] = [
        'type'=>'function',
        'function'=>[
          'name'=>'workspace_delete',
          'description'=>'Delete one regular file from the active workspace. A snapshot is created automatically. Directories cannot be deleted in this version.',
          'parameters'=>[
            'type'=>'object',
            'properties'=>[
              'path'=>['type'=>'string','description'=>'Relative file path'],
              'expected_sha256'=>['type'=>'string','description'=>'Required hash returned by workspace_read'],
            ],
            'required'=>['path','expected_sha256']
          ]
        ]
      ];
      $tools[] = [
        'type'=>'function',
        'function'=>[
          'name'=>'workspace_restore',
          'description'=>'Restore one file from a snapshot_id returned by a previous workspace write, replace or delete operation.',
          'parameters'=>[
            'type'=>'object',
            'properties'=>[
              'path'=>['type'=>'string','description'=>'Relative file path stored in the snapshot'],
              'snapshot_id'=>['type'=>'string','description'=>'Snapshot id returned by a previous workspace tool'],
            ],
            'required'=>['path','snapshot_id']
          ]
        ]
      ];
    }
  }


  if ($enableDocument) {
    $tools[] = [
      'type' => 'function',
      'function' => [
        'name' => 'document_create',
        'description' => 'Create a new workspace document and make it active. Use this when the user asks to draft, write, create, open, or add another document/code file in Document mode.',
        'parameters' => [
          'type' => 'object',
          'properties' => [
            'title' => ['type' => 'string', 'description' => 'Document title or filename, e.g. README.md or landing-page.tsx'],
            'type' => ['type' => 'string', 'description' => 'Document type: markdown, text, javascript, php, html, css, json, etc.'],
            'content' => ['type' => 'string', 'description' => 'Full document content']
          ],
          'required' => ['title','content']
        ]
      ]
    ];
    $tools[] = [
      'type' => 'function',
      'function' => [
        'name' => 'document_update',
        'description' => 'Update a workspace document. If document_id is omitted, update the active document. Always return the full updated document content, not a diff. Use this when the user asks to edit, shorten, expand, refactor, or modify a document.',
        'parameters' => [
          'type' => 'object',
          'properties' => [
            'document_id' => ['type' => 'string', 'description' => 'ID of the document to update. Omit to update the active document.'],
            'title' => ['type' => 'string', 'description' => 'Updated title/filename; omit or keep same if unchanged'],
            'type' => ['type' => 'string', 'description' => 'Updated document type; omit or keep same if unchanged'],
            'content' => ['type' => 'string', 'description' => 'Full updated document content after applying the requested edit'],
            'summary' => ['type' => 'string', 'description' => 'Short human-readable summary of what changed']
          ],
          'required' => ['content']
        ]
      ]
    ];
    $tools[] = [
      'type' => 'function',
      'function' => [
        'name' => 'document_select',
        'description' => 'Make an existing workspace document active without changing its content.',
        'parameters' => [
          'type' => 'object',
          'properties' => [
            'document_id' => ['type' => 'string', 'description' => 'ID of the document to make active']
          ],
          'required' => ['document_id']
        ]
      ]
    ];
    $tools[] = [
      'type' => 'function',
      'function' => [
        'name' => 'document_list',
        'description' => 'List the workspace documents available in this chat.',
        'parameters' => [
          'type' => 'object',
          'properties' => new stdClass(),
        ]
      ]
    ];
    $tools[] = [
      'type' => 'function',
      'function' => [
        'name' => 'document_history',
        'description' => 'List saved versions for a workspace document without loading their full content. Use this before comparing or restoring old versions.',
        'parameters' => [
          'type' => 'object',
          'properties' => [
            'document_id' => ['type' => 'string', 'description' => 'ID of the document. Omit to use the active document.']
          ]
        ]
      ]
    ];
    $tools[] = [
      'type' => 'function',
      'function' => [
        'name' => 'document_get_version',
        'description' => 'Fetch the content of a specific saved version of a workspace document. Use only when the user asks to inspect, compare, or restore an older version.',
        'parameters' => [
          'type' => 'object',
          'properties' => [
            'document_id' => ['type' => 'string', 'description' => 'ID of the document. Omit to use the active document.'],
            'version' => ['type' => 'integer', 'description' => 'Version number to fetch']
          ],
          'required' => ['version']
        ]
      ]
    ];
    $tools[] = [
      'type' => 'function',
      'function' => [
        'name' => 'document_revert',
        'description' => 'Restore a saved old document version by creating a new latest version with the old content. This never deletes history.',
        'parameters' => [
          'type' => 'object',
          'properties' => [
            'document_id' => ['type' => 'string', 'description' => 'ID of the document. Omit to use the active document.'],
            'version' => ['type' => 'integer', 'description' => 'Version number to restore as a new latest version'],
            'summary' => ['type' => 'string', 'description' => 'Short human-readable summary of why this version was restored']
          ],
          'required' => ['version']
        ]
      ]
    ];
  }

  return $tools;
}

function llc_msg_content_to_text($content): string {
  if (is_string($content)) return $content;
  if (is_array($content)) {
    $out = '';
    foreach ($content as $p) {
      if (is_array($p) && isset($p['text']) && is_string($p['text'])) {
        $out .= ($out === '' ? '' : "\n") . $p['text'];
      }
    }
    return $out;
  }
  return '';
}

function llc_is_private_ip(string $ip): bool {
  // IPv4
  if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
    $long = ip2long($ip);
    if ($long === false) return true;
    $ranges = [
      ['0.0.0.0', '0.255.255.255'],
      ['10.0.0.0', '10.255.255.255'],
      ['127.0.0.0', '127.255.255.255'],
      ['169.254.0.0', '169.254.255.255'],
      ['172.16.0.0', '172.31.255.255'],
      ['192.168.0.0', '192.168.255.255'],
    ];
    foreach ($ranges as [$a,$b]) {
      $la = ip2long($a); $lb = ip2long($b);
      if ($la !== false && $lb !== false && $long >= $la && $long <= $lb) return true;
    }
    return false;
  }
  // IPv6 (basic checks)
  if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)) {
    $s = strtolower($ip);
    if ($s === '::1') return true;
    if (str_starts_with($s, 'fc') || str_starts_with($s, 'fd')) return true; // ULA fc00::/7
    if (str_starts_with($s, 'fe80')) return true; // link-local
    return false;
  }
  return true;
}

function llc_validate_public_http_url(string $url, string $label='url', bool $allowPrivate=false): void {
  $url = trim($url);
  if ($url === '') throw new RuntimeException($label . ': empty url');
  $p = parse_url($url);
  if (!is_array($p)) throw new RuntimeException($label . ': invalid url');
  $scheme = strtolower((string)($p['scheme'] ?? ''));
  if (!in_array($scheme, ['http','https'], true)) throw new RuntimeException($label . ': only http/https allowed');
  $host = (string)($p['host'] ?? '');
  if ($host === '') throw new RuntimeException($label . ': missing host');
  // If local endpoints are explicitly allowed, do not apply SSRF network-range checks.
  // (Still keep scheme + host sanity.)
  if ($allowPrivate) return;

  $h = strtolower($host);
  if ($h === 'localhost' || $h === '0.0.0.0') throw new RuntimeException($label . ': blocked host');
  // Resolve and block private ranges (basic SSRF protection).
  if (filter_var($host, FILTER_VALIDATE_IP)) {
    $ip = $host;
  } else {
    $ip = gethostbyname($host);
    if ($ip === $host) throw new RuntimeException($label . ': DNS resolution failed');
  }

  if (llc_is_private_ip($ip)) throw new RuntimeException($label . ': private network blocked');
}

function llc_fetch_html_public(string $url): string {
  // Small-ish defaults; providers can be slow, but we also don't want hanging.
  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_MAXREDIRS      => 8,
    CURLOPT_CONNECTTIMEOUT => 10,
    CURLOPT_TIMEOUT        => 35,
    CURLOPT_ENCODING       => '',
    CURLOPT_USERAGENT      => 'Mozilla/5.0',
    CURLOPT_HTTPHEADER     => [
      'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language: de-DE,de;q=0.9,en;q=0.7',
    ],
  ]);
  $html = curl_exec($ch);
  if ($html === false) {
    $err = curl_error($ch);
    curl_close($ch);
    throw new RuntimeException('web_read: cURL error: ' . $err);
  }
  $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
  curl_close($ch);
  if ($code >= 400) throw new RuntimeException('web_read: HTTP ' . $code);
  return (string)$html;
}

function llc_html_to_text(string $html): string {
  $html = preg_replace('~<\s*br\s*/?\s*>~i', "\n", $html);
  $html = preg_replace('~</\s*p\s*>~i', "\n\n", $html);
  $html = preg_replace('~</\s*div\s*>~i', "\n\n", $html);
  $html = preg_replace('~</\s*h[1-6]\s*>~i', "\n\n", $html);
  $html = preg_replace('~</\s*li\s*>~i', "\n", $html);
  $text = strip_tags($html);
  $text = html_entity_decode($text, ENT_QUOTES | ENT_HTML5, 'UTF-8');
  $text = str_replace("\r\n", "\n", $text);
  $text = str_replace("\r", "\n", $text);
  $text = preg_replace("~[ \t]+\n~", "\n", $text);
  $text = preg_replace("~\n{3,}~", "\n\n", $text);
  $text = preg_replace("~[ \t]{2,}~", " ", $text);
  return trim($text);
}

function llc_tool_web_read(PDO $db, array $u, string $url, int $maxChars = 0): array {
  $uid = (string)($u['id'] ?? '');
  if ($uid === '') throw new RuntimeException('web_read: missing user');
  $allowPrivate = ((int)(llc_web_cfg_get($db, $u, 'web_allow_private') ?? '0')) !== 0;
  llc_validate_public_http_url($url, 'web_read', $allowPrivate);
  $html = llc_fetch_html_public($url);

  require_once __DIR__ . '/plugins/readability_autoload.php';
  $config = new fivefilters\Readability\Configuration();
  $config->setOriginalURL($url);
  $config->setFixRelativeURLs(false);
  $config->setArticleByline(true);
  $readability = new fivefilters\Readability\Readability($config);
  $readability->parse($html);

  $title  = (string)($readability->getTitle() ?? '');
  $author = (string)($readability->getAuthor() ?? '');
  $contentHtml = (string)($readability->getContent() ?? '');
  $text = llc_html_to_text($contentHtml);

  // Apply per-user configured limits.
  // Settings:
  // - web_tool_max_chars: hard max for tool-calls (0 = unlimited)
  // Tool arg:
  // - max_chars: requested (0 or missing = use default)
  $cfgMax = (int)(llc_web_cfg_get($db, $u, 'web_tool_max_chars') ?? '12000');
  if ($cfgMax < 0) $cfgMax = 0;
  if ($maxChars < 0) $maxChars = 0;

  if ($cfgMax > 0) {
    // Configured limited: default to cfgMax, clamp requested.
    if ($maxChars === 0) $maxChars = $cfgMax;
    else $maxChars = min($maxChars, $cfgMax);
  } else {
    // Configured unlimited: allow requested smaller limit; 0 means unlimited.
    // (Leave $maxChars as-is.)
  }

  $truncated = false;
  if ($maxChars > 0 && mb_strlen($text, 'UTF-8') > $maxChars) {
    $text = mb_substr($text, 0, $maxChars, 'UTF-8');
    $truncated = true;
  }

  return [
    'ok' => true,
    'url' => $url,
    'title' => $title,
    'author' => $author,
    'content_text' => $text,
    'truncated' => $truncated,
  ];
}

function llc_http_post_json(string $url, array $hdrs, array $payload, int $timeoutSec = 20, int $connectTimeoutSec = 10): array {
  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => $hdrs,
    CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HEADER => false,
    // Enable transparent gzip/deflate/br decoding when servers send compressed responses.
    // Without this, some providers (e.g. Brave) can return gzipped JSON that fails json_decode().
    CURLOPT_ENCODING => '',
    CURLOPT_CONNECTTIMEOUT => $connectTimeoutSec,
    CURLOPT_TIMEOUT => $timeoutSec,
  ]);
  $body = curl_exec($ch);
  if ($body === false) {
    $err = curl_error($ch);
    curl_close($ch);
    throw new RuntimeException('HTTP error: ' . $err);
  }
  $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
  curl_close($ch);
  if ($code >= 400) throw new RuntimeException('HTTP ' . $code . ': ' . substr((string)$body, 0, 600));
  $j = json_decode((string)$body, true);
  if (!is_array($j)) throw new RuntimeException('Invalid JSON response');
  return $j;
}


function llc_http_get_json(string $url, array $hdrs, int $timeoutSec = 20, int $connectTimeoutSec = 10): array {
  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_HTTPGET => true,
    CURLOPT_HTTPHEADER => $hdrs,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HEADER => false,
    // Enable transparent gzip/deflate/br decoding when servers send compressed responses.
    CURLOPT_ENCODING => '',
    CURLOPT_CONNECTTIMEOUT => $connectTimeoutSec,
    CURLOPT_TIMEOUT => $timeoutSec,
  ]);
  $body = curl_exec($ch);
  if ($body === false) {
    $err = curl_error($ch);
    curl_close($ch);
    throw new RuntimeException('HTTP error: ' . $err);
  }
  $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
  curl_close($ch);
  if ($code >= 400) throw new RuntimeException('HTTP ' . $code . ': ' . substr((string)$body, 0, 600));
  $j = json_decode((string)$body, true);
  if (!is_array($j)) throw new RuntimeException('Invalid JSON response');
  return $j;
}

function llc_compact_search_response(array $raw, string $type, int $num): array {
  $num = max(1, min(20, $num));
  if ($type === 'news') {
    $items = [];
    $src = $raw['news'] ?? [];
    if (is_array($src)) {
      foreach (array_slice($src, 0, $num) as $it) {
        if (!is_array($it)) continue;
        $items[] = [
          'title' => (string)($it['title'] ?? ''),
          'link' => (string)($it['link'] ?? ''),
          'snippet' => (string)($it['snippet'] ?? ''),
          'date' => (string)($it['date'] ?? ''),
          'source' => (string)($it['source'] ?? ''),
        ];
      }
    }
    return [
      'ok' => true,
      'type' => 'news',
      'news' => $items,
      'raw_has_more' => (is_array($src) && count($src) > $num),
    ];
  }

  // search
  $items = [];
  $src = $raw['organic'] ?? [];
  if (is_array($src)) {
    foreach (array_slice($src, 0, $num) as $it) {
      if (!is_array($it)) continue;
      $items[] = [
        'title' => (string)($it['title'] ?? ''),
        'link' => (string)($it['link'] ?? ''),
        'snippet' => (string)($it['snippet'] ?? ''),
        'date' => (string)($it['date'] ?? ''),
        'position' => (int)($it['position'] ?? 0),
      ];
    }
  }

  $related = [];
  if (!empty($raw['relatedSearches']) && is_array($raw['relatedSearches'])) {
    foreach (array_slice($raw['relatedSearches'], 0, 8) as $r) {
      if (is_array($r) && isset($r['query'])) $related[] = (string)$r['query'];
    }
  }

  $paa = [];
  if (!empty($raw['peopleAlsoAsk']) && is_array($raw['peopleAlsoAsk'])) {
    foreach (array_slice($raw['peopleAlsoAsk'], 0, 4) as $r) {
      if (!is_array($r)) continue;
      $paa[] = [
        'question' => (string)($r['question'] ?? ''),
        'snippet' => (string)($r['snippet'] ?? ''),
        'title' => (string)($r['title'] ?? ''),
        'link' => (string)($r['link'] ?? ''),
      ];
    }
  }

  return [
    'ok' => true,
    'type' => 'search',
    'organic' => $items,
    'related' => $related,
    'people_also_ask' => $paa,
    'raw_has_more' => (is_array($src) && count($src) > $num),
  ];
}

function llc_url_looks_like_script(string $url): bool {
  $url = trim($url);
  if ($url === '') return false;
  $p = parse_url($url);
  if (!is_array($p)) return false;
  $path = (string)($p['path'] ?? '');
  return (bool)preg_match('~\.php$~i', $path);
}

/**
 * Returns [searchEndpoint, newsEndpoint].
 * - If $custom is a base URL, endpoints are {base}/search and {base}/news (after trimming /search|/news suffixes).
 * - If $custom looks like a script endpoint (.../index.php), it is used directly for search.
 *   News endpoint is either $customNews, or derived by replacing '/search' with '/news'.
 */
function llc_custom_search_endpoints(string $custom, string $customNews = ''): array {
  $custom = trim($custom);
  $customNews = trim($customNews);
  if ($custom === '') return ['', ''];

  $custom = rtrim($custom, '/');
  if (llc_url_looks_like_script($custom)) {
    $search = $custom;
    $news = $customNews !== '' ? rtrim($customNews, '/') : '';
    if ($news === '') {
      // try to derive /news from a /search endpoint
      $derived = preg_replace('~(/search)(/|$)~i', '/news$2', $search, 1, $count);
      if (is_string($derived) && $count === 1) $news = $derived;
    }
    // If we still have no usable news endpoint, return empty (caller can decide what to do).
    if ($news !== '' && $news === $search) {
      // This usually means we couldn't derive; keep it as-is, but the caller may reject for type=news.
    }
    return [$search, $news];
  }

  // Base URL mode
  $root = preg_replace('~/(search|news)$~i', '', $custom);
  if (!is_string($root) || $root === '') $root = $custom;

  $search = $root . '/search';
  $news = $customNews !== '' ? rtrim($customNews, '/') : ($root . '/news');
  return [$search, $news];
}

function llc_tool_web_search(PDO $db, array $u, string $q, string $type = 'search', ?string $gl = null, ?string $hl = null, ?int $num = null, ?int $page = null, ?bool $autocorrect = null): array {
  $q = trim($q);
  if ($q === '') throw new RuntimeException('web_search: empty query');
  $type = strtolower(trim($type));
  if (!in_array($type, ['search','news'], true)) $type = 'search';

  $provider = strtolower(trim((string)(llc_search_cfg_get($db, $u, 'search_provider') ?? 'serper')));
  if ($provider === '') $provider = 'serper';

  $gl = ($gl !== null && trim($gl) !== '') ? trim($gl) : (string)(llc_search_cfg_get($db, $u, 'search_gl') ?? 'de');
  $hl = ($hl !== null && trim($hl) !== '') ? trim($hl) : (string)(llc_search_cfg_get($db, $u, 'search_hl') ?? 'de');
  $num0 = (int)($num ?? (int)(llc_search_cfg_get($db, $u, 'search_num') ?? '10'));
  $num0 = max(1, min(20, $num0));
  $page0 = (int)($page ?? 1);
  if ($page0 < 1) $page0 = 1;
  $autocorrect0 = ($autocorrect === null) ? true : (bool)$autocorrect;

  $payload = [
    'q' => $q,
    'gl' => $gl,
    'hl' => $hl,
    'num' => $num0,
    'page' => $page0,
    'autocorrect' => $autocorrect0,
  ];

  if ($provider === 'custom') {
    $custom = trim((string)(llc_search_cfg_get($db, $u, 'search_custom_url') ?? ''));
    if ($custom === '') throw new RuntimeException('web_search: custom_url not configured');

    $customNews = trim((string)(llc_search_cfg_get($db, $u, 'search_custom_news_url') ?? ''));
    $allowPrivate = ((int)(llc_search_cfg_get($db, $u, 'search_custom_allow_private') ?? '0')) !== 0;

    // Support either a base URL (we call {base}/search and {base}/news)
    // or a full endpoint URL (e.g. /search/index.php). For endpoint URLs, a News URL override may be required.
    [$searchEndpoint, $newsEndpoint] = llc_custom_search_endpoints($custom, $customNews);
    $endpoint = ($type === 'news') ? $newsEndpoint : $searchEndpoint;
    if ($endpoint === '') {
      throw new RuntimeException('web_search: custom_news_url required for news searches');
    }

    llc_validate_public_http_url($endpoint, 'web_search', $allowPrivate);

    $hdrs = [
      'Content-Type: application/json',
      'Accept: application/json',
    ];
    $k = trim((string)(llc_search_cfg_get($db, $u, 'search_custom_api_key') ?? ''));
    if ($k !== '') $hdrs[] = 'X-API-KEY: ' . $k;

    $raw = llc_http_post_json($endpoint, $hdrs, $payload, 25, 12);
    $compact = llc_compact_search_response($raw, $type, $num0);
    $compact['q'] = $q;
    $compact['provider'] = 'custom';
    $compact['endpoint'] = $endpoint;
    return $compact;
  }

  if ($provider === 'brave') {
    $key = trim((string)(llc_search_cfg_get($db, $u, 'brave_api_key') ?? ''));
    if ($key === '') throw new RuntimeException('web_search: brave_api_key missing');

    $endpoint = ($type === 'news')
      ? 'https://api.search.brave.com/res/v1/news/search'
      : 'https://api.search.brave.com/res/v1/web/search';

    $country = strtoupper((string)$gl);
    $country = preg_replace('~[^A-Z]~', '', $country);
    if (!is_string($country) || $country === '') $country = 'US';
    if (strlen($country) > 2) $country = substr($country, 0, 2);

    $searchLang = strtolower((string)$hl);
    $searchLang = preg_replace('~[^a-z\-]~', '', $searchLang);
    if (!is_string($searchLang) || $searchLang === '') $searchLang = 'en';

    $uiLang = $searchLang;
    if (strpos($uiLang, '-') === false) $uiLang = $searchLang . '-' . $country;

    // Brave uses 0-based page index as offset, max 9.
    $offset = max(0, min(9, $page0 - 1));

    $qs = http_build_query([
      'q' => $q,
      'country' => $country,
      'search_lang' => $searchLang,
      'ui_lang' => $uiLang,
      'safesearch' => 'moderate',
      'count' => $num0,
      'offset' => $offset,
    ], '', '&', PHP_QUERY_RFC3986);

    $url = $endpoint . '?' . $qs;

    $hdrs = [
      'Accept: application/json',
      'Accept-Encoding: gzip',
      'X-Subscription-Token: ' . $key,
    ];

    $raw = llc_http_get_json($url, $hdrs, 25, 12);

    // Convert Brave JSON -> Serper-like structure used by llc_compact_search_response()
    $serperLike = [];
    $pickHost = function(string $u): string {
      $p = parse_url($u);
      if (!is_array($p)) return '';
      return (string)($p['host'] ?? '');
    };

    if ($type === 'news') {
      $src = [];
      if (isset($raw['news']) && is_array($raw['news']) && isset($raw['news']['results']) && is_array($raw['news']['results'])) {
        $src = $raw['news']['results'];
      } elseif (isset($raw['results']) && is_array($raw['results'])) {
        $src = $raw['results'];
      }

      $news = [];
      $i = 0;
      foreach ($src as $it) {
        if (!is_array($it)) continue;
        $i++;
        $link = (string)($it['url'] ?? $it['link'] ?? '');
        $host = ($link !== '') ? $pickHost($link) : '';
        $source = '';
        if (isset($it['source']) && is_string($it['source'])) $source = $it['source'];
        elseif (isset($it['source']) && is_array($it['source']) && isset($it['source']['name'])) $source = (string)$it['source']['name'];
        elseif (isset($it['publisher']) && is_string($it['publisher'])) $source = $it['publisher'];
        elseif (isset($it['meta_url']) && is_array($it['meta_url']) && isset($it['meta_url']['hostname'])) $source = (string)$it['meta_url']['hostname'];
        if ($source === '') $source = $host;

        $news[] = [
          'title' => (string)($it['title'] ?? $it['name'] ?? ''),
          'link' => $link,
          'snippet' => (string)($it['description'] ?? $it['snippet'] ?? $it['content'] ?? ''),
          'date' => (string)($it['age'] ?? $it['page_age'] ?? $it['published'] ?? $it['published_time'] ?? $it['date'] ?? ''),
          'source' => $source,
        ];
        if ($i >= $num0) break;
      }
      $serperLike['news'] = $news;
    } else {
      $src = [];
      if (isset($raw['web']) && is_array($raw['web']) && isset($raw['web']['results']) && is_array($raw['web']['results'])) {
        $src = $raw['web']['results'];
      } elseif (isset($raw['results']) && is_array($raw['results'])) {
        $src = $raw['results'];
      }

      $org = [];
      $i = 0;
      foreach ($src as $it) {
        if (!is_array($it)) continue;
        $i++;
        $link = (string)($it['url'] ?? $it['link'] ?? '');
        $org[] = [
          'title' => (string)($it['title'] ?? $it['name'] ?? ''),
          'link' => $link,
          'snippet' => (string)($it['description'] ?? $it['snippet'] ?? $it['content'] ?? ''),
          'date' => (string)($it['age'] ?? $it['page_age'] ?? $it['published'] ?? $it['published_time'] ?? $it['date'] ?? ''),
          'position' => $i,
        ];
        if ($i >= $num0) break;
      }
      $serperLike['organic'] = $org;
    }

    $compact = llc_compact_search_response($serperLike, $type, $num0);
    $compact['q'] = $q;
    $compact['provider'] = 'brave';
    $compact['endpoint'] = $endpoint;
    $compact['url'] = $url;
    return $compact;
  }

  if ($provider === 'searchngx') {
    $base = trim((string)(llc_search_cfg_get($db, $u, 'searchngx_url') ?? ''));
    if ($base === '') throw new RuntimeException('web_search: searchngx_url not configured');

    $allowPrivate = ((int)(llc_search_cfg_get($db, $u, 'searchngx_allow_private') ?? '0')) !== 0;

    $base = rtrim($base, '/');
    // Accept both base URLs and explicit /search endpoints.
    $endpoint = preg_match('~/(search)$~i', $base) ? $base : ($base . '/search');
    llc_validate_public_http_url($endpoint, 'web_search', $allowPrivate);

    $language = $hl;
    if (strpos($language, '-') === false) {
      // Heuristic: map hl=de + gl=de -> de-DE (SearXNG instances typically accept both, but this avoids surprises)
      $language = $hl . '-' . strtoupper($gl);
    }

    $categories = ($type === 'news') ? 'news' : 'general';

    $qs = http_build_query([
      'q' => $q,
      'categories' => $categories,
      'language' => $language,
      'safesearch' => 0,
      'format' => 'json',
      'pageno' => $page0,
    ], '', '&', PHP_QUERY_RFC3986);

    $url = $endpoint . '?' . $qs;

    $hdrs = [
      'Accept: application/json',
    ];
    $k = trim((string)(llc_search_cfg_get($db, $u, 'searchngx_api_key') ?? ''));
    if ($k !== '') $hdrs[] = 'X-API-KEY: ' . $k;

    $raw = llc_http_get_json($url, $hdrs, 25, 12);

    // Convert SearXNG JSON -> Serper-like structure used by llc_compact_search_response()
    $serperLike = [];
    $results = $raw['results'] ?? [];
    if (!is_array($results)) $results = [];

    if ($type === 'news') {
      $news = [];
      $i = 0;
      foreach ($results as $it) {
        if (!is_array($it)) continue;
        $i++;
        $eng = '';
        if (isset($it['engine']) && is_string($it['engine'])) $eng = $it['engine'];
        elseif (isset($it['engines']) && is_array($it['engines']) && isset($it['engines'][0])) $eng = (string)$it['engines'][0];
        $news[] = [
          'title' => (string)($it['title'] ?? ''),
          'link' => (string)($it['url'] ?? ''),
          'snippet' => (string)($it['content'] ?? ''),
          'date' => (string)($it['publishedDate'] ?? ''),
          'source' => $eng,
        ];
        if ($i >= $num0) break;
      }
      $serperLike['news'] = $news;
    } else {
      $org = [];
      $i = 0;
      foreach ($results as $it) {
        if (!is_array($it)) continue;
        $i++;
        $org[] = [
          'title' => (string)($it['title'] ?? ''),
          'link' => (string)($it['url'] ?? ''),
          'snippet' => (string)($it['content'] ?? ''),
          'date' => (string)($it['publishedDate'] ?? ''),
          'position' => $i,
        ];
        if ($i >= $num0) break;
      }
      $serperLike['organic'] = $org;
    }

    $compact = llc_compact_search_response($serperLike, $type, $num0);
    $compact['q'] = $q;
    $compact['provider'] = 'searchngx';
    $compact['endpoint'] = $endpoint;
    $compact['url'] = $url;
    return $compact;
  }



  // default: serper.dev
  $key = trim((string)(llc_search_cfg_get($db, $u, 'serper_api_key') ?? ''));
  if ($key === '') throw new RuntimeException('web_search: serper_api_key missing');

  $endpoint = ($type === 'news') ? 'https://google.serper.dev/news' : 'https://google.serper.dev/search';
  $hdrs = [
    'Content-Type: application/json',
    'Accept: application/json',
    'X-API-KEY: ' . $key,
  ];
  $raw = llc_http_post_json($endpoint, $hdrs, $payload, 25, 12);
  $compact = llc_compact_search_response($raw, $type, $num0);
  $compact['q'] = $q;
  $compact['provider'] = 'serper';
  $compact['endpoint'] = $endpoint;
  return $compact;
}



function llc_store_generated_file(PDO $db, string $uid, string $bytes, string $origName, string $mime): array {
  $dir = llc_uploads_dir();
  if (!is_dir($dir)) @mkdir($dir, 0755, true);

  $fileId = 'f_' . bin2hex(random_bytes(8));
  $ext = pathinfo($origName, PATHINFO_EXTENSION);
  if ($ext === '') {
    // simple mime to ext
    $ext = ($mime === 'image/jpeg') ? 'jpg' : (($mime === 'image/webp') ? 'webp' : 'png');
    $origName = $origName . '.' . $ext;
  }
  $stored = $fileId . '.' . $ext;
  $path = $dir . '/' . $stored;

  file_put_contents($path, $bytes);

  $size = strlen($bytes);
  $stmt = $db->prepare('INSERT INTO files (id,user_id,original_name,stored_name,mime,size,created_at) VALUES (?,?,?,?,?,?,?)');
  $stmt->execute([$fileId, $uid, $origName, $stored, $mime, $size, gmdate('c')]);

  return [
    'file_id' => $fileId,
    'name' => $origName,
    'mime' => $mime,
    'size' => $size,
    'url' => llc_base_url() . '/uploads/' . rawurlencode($stored)
  ];
}



// ---------- ComfyUI image generation helpers ----------
function llc_comfyui_base(string $url): string {
  $u = trim($url);
  if ($u === '') throw new RuntimeException('ComfyUI URL missing (Settings → Image).');
  // Allow http://... without /v1
  return rtrim($u, '/');
}

function llc_comfyui_http_json(string $method, string $url, array $payload = null, int $timeout = 120): array {
  $ch = curl_init($url);
  $hdrs = ['Accept: application/json'];
  $opts = [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => $timeout,
    CURLOPT_CONNECTTIMEOUT => 10,
  ];
  $m = strtoupper($method);
  if ($m === 'POST') {
    $hdrs[] = 'Content-Type: application/json';
    $opts[CURLOPT_POST] = true;
    if ($payload !== null) {
      $opts[CURLOPT_POSTFIELDS] = json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
    }
  }
  $opts[CURLOPT_HTTPHEADER] = $hdrs;
  curl_setopt_array($ch, $opts);
  $raw = curl_exec($ch);
  $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
  $err = curl_error($ch);
  curl_close($ch);

  if ($raw === false || $raw === null) {
    throw new RuntimeException('ComfyUI request failed: ' . ($err ?: 'unknown error') . ($code ? ' (HTTP ' . $code . ')' : ''));
  }
  $j = json_decode((string)$raw, true);
  if (!is_array($j)) {
    $snip = trim(substr((string)$raw, 0, 800));
    throw new RuntimeException('ComfyUI returned invalid JSON (HTTP ' . $code . '): ' . $snip);
  }
  if ($code !== 0 && ($code < 200 || $code >= 300)) {
    throw new RuntimeException('ComfyUI HTTP ' . $code . ': ' . json_encode($j, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
  }
  return $j;
}

function llc_comfyui_http_bytes(string $url, int $timeout = 120): array {
  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => $timeout,
    CURLOPT_CONNECTTIMEOUT => 10,
  ]);
  $bytes = curl_exec($ch);
  $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
  $ct = (string)curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
  $err = curl_error($ch);
  curl_close($ch);
  if ($bytes === false || $bytes === null) {
    throw new RuntimeException('ComfyUI download failed: ' . ($err ?: 'unknown error') . ($code ? ' (HTTP ' . $code . ')' : ''));
  }
  if ($code !== 0 && ($code < 200 || $code >= 300)) {
    throw new RuntimeException('ComfyUI download HTTP ' . $code);
  }
  return [(string)$bytes, $ct];
}

function llc_comfyui_title(array $node): string {
  $m = $node['_meta'] ?? null;
  if (!is_array($m)) return '';
  return (string)($m['title'] ?? '');
}

function llc_comfyui_has_inputs(array $node, array $keys): bool {
  $inp = $node['inputs'] ?? null;
  if (!is_array($inp)) return false;
  foreach ($keys as $k) {
    if (!array_key_exists($k, $inp)) return false;
  }
  return true;
}

function llc_comfyui_selector_match(string $id, array $node, array $selector): bool {
  if (isset($selector['id']) && (string)$selector['id'] !== '' && (string)$selector['id'] !== $id) return false;
  if (isset($selector['class_type']) && (string)$selector['class_type'] !== '') {
    if ((string)($node['class_type'] ?? '') !== (string)$selector['class_type']) return false;
  }
  if (isset($selector['meta_title_contains']) && (string)$selector['meta_title_contains'] !== '') {
    $t = mb_strtolower(llc_comfyui_title($node));
    $needle = mb_strtolower((string)$selector['meta_title_contains']);
    if ($needle !== '' && !str_contains($t, $needle)) return false;
  }
  if (isset($selector['has_inputs']) && is_array($selector['has_inputs'])) {
    if (!llc_comfyui_has_inputs($node, $selector['has_inputs'])) return false;
  }
  return true;
}

function llc_comfyui_find_node_id(array $workflow, array $selector): ?string {
  foreach ($workflow as $id => $node) {
    if (!is_array($node)) continue;
    if (llc_comfyui_selector_match((string)$id, $node, $selector)) return (string)$id;
  }
  return null;
}

function llc_set_path_value(array &$arr, string $path, $value): bool {
  $parts = array_values(array_filter(explode('.', $path), fn($p)=>$p!==''));
  if (!$parts) return false;
  $ref =& $arr;
  for ($i=0; $i<count($parts)-1; $i++) {
    $k = $parts[$i];
    if (!is_array($ref)) return false;
    if (!array_key_exists($k, $ref) || !is_array($ref[$k])) $ref[$k] = [];
    $ref =& $ref[$k];
  }
  $last = $parts[count($parts)-1];
  if (!is_array($ref)) return false;
  $ref[$last] = $value;
  return true;
}

function llc_comfyui_cast($v, string $cast) {
  $c = strtolower(trim($cast));
  if ($c === 'int' || $c === 'integer') return (int)$v;
  if ($c === 'float' || $c === 'number') return (float)$v;
  if ($c === 'bool' || $c === 'boolean') return (bool)$v;
  return (string)$v;
}

function llc_comfyui_default_bindings(array $workflow): array {
  // Mirrors the UI auto-detect. Works even if the user doesn't define bindings.
  $out = [];

  $first = function(callable $pred) use ($workflow): ?array {
    foreach ($workflow as $id => $node) {
      if (!is_array($node)) continue;
      try { if ($pred((string)$id, $node)) return [(string)$id, $node]; } catch (Throwable $e) { /* ignore */ }
    }
    return null;
  };

  // prompt
  // - Classic: CLIPTextEncode(text)
  // - FLUX/SD3: CLIPTextEncodeFlux(clip_l, t5xxl)
  //   Bind to prompt_clip_l / prompt_t5xxl so the backend can fall back to `prompt`
  //   while still allowing truly separate prompts.
  $h = $first(function($id,$n){
    return ((string)($n['class_type'] ?? '') === 'CLIPTextEncodeFlux')
      && (llc_comfyui_has_inputs($n,['clip_l']) || llc_comfyui_has_inputs($n,['t5xxl']));
  });
  if ($h) {
    if (llc_comfyui_has_inputs($h[1],['clip_l'])) {
      $out[] = ['param'=>'prompt_clip_l','selector'=>['class_type'=>'CLIPTextEncodeFlux','has_inputs'=>['clip_l']],'path'=>'inputs.clip_l','cast'=>'string'];
    }
    if (llc_comfyui_has_inputs($h[1],['t5xxl'])) {
      $out[] = ['param'=>'prompt_t5xxl','selector'=>['class_type'=>'CLIPTextEncodeFlux','has_inputs'=>['t5xxl']],'path'=>'inputs.t5xxl','cast'=>'string'];
    }
  } else {
    $usedPositive = false;
    $h = $first(function($id,$n){
      return ((string)($n['class_type'] ?? '') === 'CLIPTextEncode') && llc_comfyui_has_inputs($n,['text']) && str_contains(mb_strtolower(llc_comfyui_title($n)), 'positive');
    });
    if ($h) $usedPositive = true;
    if (!$h) $h = $first(function($id,$n){ return ((string)($n['class_type'] ?? '') === 'CLIPTextEncode') && llc_comfyui_has_inputs($n,['text']); });
    if ($h) {
      $sel = ['class_type'=>'CLIPTextEncode','has_inputs'=>['text']];
      if ($usedPositive) $sel['meta_title_contains'] = 'positive';
      $out[] = ['param'=>'prompt','selector'=>$sel,'path'=>'inputs.text','cast'=>'string'];
    }
  }

  // seed
  // Many modern workflows (SD3/FLUX) expose `seed` directly on KSampler.
  $h = $first(function($id,$n){
    $ct = mb_strtolower((string)($n['class_type'] ?? ''));
    return (str_contains($ct,'ksampler') || str_contains($ct,'sampler')) && llc_comfyui_has_inputs($n,['seed']);
  });
  if ($h) {
    $out[] = ['param'=>'seed','selector'=>['class_type'=>(string)($h[1]['class_type'] ?? 'KSampler'),'has_inputs'=>['seed']],'path'=>'inputs.seed','cast'=>'int'];
  } else {
    $h = $first(function($id,$n){ return ((string)($n['class_type'] ?? '') === 'RandomNoise') && llc_comfyui_has_inputs($n,['noise_seed']); });
    if ($h) $out[] = ['param'=>'seed','selector'=>['class_type'=>'RandomNoise','has_inputs'=>['noise_seed']],'path'=>'inputs.noise_seed','cast'=>'int'];
  }

  // steps
  // Prefer the actual sampler node (KSampler / *KSampler* variants) over any other node that might also have a `steps` input.
  $h = $first(function($id,$n){
    return ((string)($n['class_type'] ?? '') === 'KSampler') && llc_comfyui_has_inputs($n,['steps']);
  });
  if (!$h) $h = $first(function($id,$n){
    $ct = mb_strtolower((string)($n['class_type'] ?? ''));
    return llc_comfyui_has_inputs($n,['steps']) && str_contains($ct,'ksampler');
  });
  if (!$h) $h = $first(function($id,$n){
    $ct = mb_strtolower((string)($n['class_type'] ?? ''));
    return llc_comfyui_has_inputs($n,['steps']) && str_contains($ct,'scheduler');
  });
  if (!$h) $h = $first(function($id,$n){ return llc_comfyui_has_inputs($n,['steps']); });
  if ($h) {
    $sel = ['has_inputs'=>['steps']];
    $ct = (string)($h[1]['class_type'] ?? '');
    if ($ct !== '') $sel['class_type'] = $ct;
    $title = mb_strtolower(llc_comfyui_title($h[1]));
    if ($title !== '') {
      if (str_contains($title,'scheduler')) $sel['meta_title_contains'] = 'scheduler';
      else if (str_contains($title,'sampler')) $sel['meta_title_contains'] = 'sampler';
    }
    $out[] = ['param'=>'steps','selector'=>$sel,'path'=>'inputs.steps','cast'=>'int'];
  }

  // guidance
  // FLUX/SD3 uses guidance on CLIPTextEncodeFlux; prefer that over any other incidental `guidance` fields.
  $h = $first(function($id,$n){
    return ((string)($n['class_type'] ?? '') === 'CLIPTextEncodeFlux') && llc_comfyui_has_inputs($n,['guidance']);
  });
  if (!$h) $h = $first(function($id,$n){ return llc_comfyui_has_inputs($n,['guidance']); });
  if ($h) {
    $sel = ['has_inputs'=>['guidance']];
    $ct = (string)($h[1]['class_type'] ?? '');
    if ($ct !== '') $sel['class_type'] = $ct;
    $out[] = ['param'=>'guidance','selector'=>$sel,'path'=>'inputs.guidance','cast'=>'float'];
  }

  // width/height
  $h = $first(function($id,$n){ return llc_comfyui_has_inputs($n,['width','height']); });
  if ($h) {
    $out[] = ['param'=>'width','selector'=>['has_inputs'=>['width','height']],'path'=>'inputs.width','cast'=>'int'];
    $out[] = ['param'=>'height','selector'=>['has_inputs'=>['width','height']],'path'=>'inputs.height','cast'=>'int'];
  }

  // batch size
  $h = $first(function($id,$n){ return llc_comfyui_has_inputs($n,['batch_size']); });
  if ($h) $out[] = ['param'=>'batch_size','selector'=>['has_inputs'=>['batch_size']],'path'=>'inputs.batch_size','cast'=>'int'];

  return $out;
}

function llc_comfyui_apply_bindings(array $workflow, array $bindings, array $params): array {
  foreach ($bindings as $b) {
    if (!is_array($b)) continue;
    $param = (string)($b['param'] ?? '');
    if ($param === '' || !array_key_exists($param, $params)) continue;
    $selector = $b['selector'] ?? null;
    if (!is_array($selector)) continue;
    $path = (string)($b['path'] ?? '');
    if ($path === '') continue;
    $cast = (string)($b['cast'] ?? '');

    $id = llc_comfyui_find_node_id($workflow, $selector);
    if ($id === null || !isset($workflow[$id]) || !is_array($workflow[$id])) continue;

    $val = $params[$param];
    if ($cast !== '') $val = llc_comfyui_cast($val, $cast);
    llc_set_path_value($workflow[$id], $path, $val);
  }
  return $workflow;
}

function llc_tool_image_generate_comfyui(PDO $db, string $uid, array $u, array $args, callable $sendStatus): array {
  // ComfyUI runs can take minutes depending on GPU load/queue.
  // Remove PHP execution time limit for this request.
  @set_time_limit(0);
  @ini_set('max_execution_time', '0');

  $base = llc_comfyui_base((string)(llc_image_cfg_get($db, $u, 'image_comfyui_url') ?? ''));
  $wfRaw = (string)(llc_image_cfg_get($db, $u, 'image_comfyui_workflow_json') ?? '');
  if (trim($wfRaw) === '') return ['ok'=>false,'error'=>'ComfyUI workflow JSON is empty (Settings → Image).'];
  $workflow = json_decode($wfRaw, true);
  if (!is_array($workflow)) return ['ok'=>false,'error'=>'ComfyUI workflow JSON is invalid (Settings → Image).'];

  // Defaults (only applied when "Apply defaults" is enabled OR the tool call provides overrides)
  $seed_default = (int)((llc_image_cfg_get($db, $u, 'image_comfyui_seed') ?? '-1'));
  $steps_default = (int)((llc_image_cfg_get($db, $u, 'image_comfyui_steps') ?? '20'));
  $guidance_default = (float)((llc_image_cfg_get($db, $u, 'image_comfyui_guidance') ?? '3.5'));
  $width_default = (int)((llc_image_cfg_get($db, $u, 'image_comfyui_width') ?? '512'));
  $height_default = (int)((llc_image_cfg_get($db, $u, 'image_comfyui_height') ?? '512'));
  $batch_default = (int)((llc_image_cfg_get($db, $u, 'image_comfyui_batch') ?? '1'));
  $applyDefaults = (int)((llc_image_cfg_get($db, $u, 'image_comfyui_apply_defaults') ?? '0')) !== 0;

  // Tool args
  $prompt = (string)($args['prompt'] ?? '');
  if ($prompt === '') return ['ok'=>false,'error'=>'image_generate: missing prompt'];

  // Optional split prompts for FLUX/SD3 workflows (CLIP-L vs T5-XXL).
  // If not provided, fall back to the main `prompt` so legacy callers keep working.
  $prompt_clip_l = (string)($args['prompt_clip_l'] ?? '');
  $prompt_t5xxl  = (string)($args['prompt_t5xxl'] ?? '');
  if ($prompt_clip_l === '') $prompt_clip_l = $prompt;
  if ($prompt_t5xxl === '') $prompt_t5xxl = $prompt;

  // Start with defaults (used only when applyDefaults is enabled)
  $seed = $seed_default;
  $steps = $steps_default;
  $guidance = $guidance_default;
  $width = $width_default;
  $height = $height_default;
  $batch = $batch_default;

  // Detect overrides
  $seedProvided = array_key_exists('seed', $args);
  $stepsProvided = array_key_exists('steps', $args);
  $guidanceProvided = array_key_exists('guidance', $args);
  $widthProvided = array_key_exists('width', $args);
  $heightProvided = array_key_exists('height', $args);
  $batchProvided = array_key_exists('batch_size', $args);

  // Apply overrides
  if ($seedProvided) $seed = (int)$args['seed'];
  if ($stepsProvided) $steps = max(1, (int)$args['steps']);
  if ($guidanceProvided) $guidance = (float)$args['guidance'];
  if ($widthProvided) $width = max(64, (int)$args['width']);
  if ($heightProvided) $height = max(64, (int)$args['height']);
  if ($batchProvided) $batch = max(1, (int)$args['batch_size']);

  // Decide which params to inject into the workflow.
  // Default behavior: keep values from the workflow JSON unless user overrides.
  // If applyDefaults is enabled, defaults override the workflow.
  $params = [
    'prompt' => $prompt,           // classic workflows
    'prompt_clip_l' => $prompt_clip_l,
    'prompt_t5xxl' => $prompt_t5xxl,
  ];

  $shouldApplySeed = $seedProvided || $applyDefaults;
  if ($shouldApplySeed) {
    if (!$seedProvided && $seed_default < 0) {
      $seed = random_int(0, 2147483647);
    } else if ($seedProvided && $seed < 0) {
      $seed = random_int(0, 2147483647);
    }
    $params['seed'] = $seed;
  }

  if ($stepsProvided || $applyDefaults) $params['steps'] = $steps;
  if ($guidanceProvided || $applyDefaults) $params['guidance'] = $guidance;
  if ($widthProvided || $applyDefaults) $params['width'] = $width;
  if ($heightProvided || $applyDefaults) $params['height'] = $height;
  if ($batchProvided || $applyDefaults) $params['batch_size'] = $batch;

  // Bindings
  $bindingsRaw = (string)(llc_image_cfg_get($db, $u, 'image_comfyui_bindings_json') ?? '');
  $bindings = [];
  if (trim($bindingsRaw) !== '') {
    $tmp = json_decode($bindingsRaw, true);
    if (is_array($tmp)) $bindings = $tmp;
  }
  if (!$bindings) $bindings = llc_comfyui_default_bindings($workflow);

  $workflow2 = llc_comfyui_apply_bindings($workflow, $bindings, $params);

  $sendStatus('Queueing ComfyUI workflow…');
  $clientId = 'llc_' . bin2hex(random_bytes(6));
  $resp = llc_comfyui_http_json('POST', $base . '/prompt', ['prompt'=>$workflow2, 'client_id'=>$clientId], 30);
  $promptId = (string)($resp['prompt_id'] ?? '');
  if ($promptId === '') {
    // Some builds return number, keep robust
    $promptId = (string)($resp['number'] ?? '');
  }
  if ($promptId === '') return ['ok'=>false,'error'=>'ComfyUI: missing prompt_id in response'];

  // Poll history until outputs appear. ComfyUI can be queued for minutes.
  $timeoutSec = (int)(llc_image_cfg_get($db, $u, 'image_comfyui_timeout_sec') ?? '900');
  if ($timeoutSec < 30) $timeoutSec = 30;
  if ($timeoutSec > 3600) $timeoutSec = 3600;
  $deadline = microtime(true) + (float)$timeoutSec;
  $lastStatusAt = 0.0;
  $history = null;
  while (microtime(true) < $deadline) {
    if (connection_aborted()) exit;
    if (microtime(true) - $lastStatusAt > 2.5) {
      $sendStatus('Running ComfyUI…');
      $lastStatusAt = microtime(true);
    }
    try {
      $history = llc_comfyui_http_json('GET', $base . '/history/' . rawurlencode($promptId), null, 30);
    } catch (Throwable $e) {
      // ComfyUI might not have history immediately; just wait.
      usleep(400000);
      continue;
    }

    $entry = null;
    if (isset($history[$promptId]) && is_array($history[$promptId])) $entry = $history[$promptId];
    elseif (isset($history['outputs']) && is_array($history)) $entry = $history;
    else {
      // sometimes history is {id:{...}}
      $first = reset($history);
      if (is_array($first) && isset($first['outputs'])) $entry = $first;
    }

    if ($entry && isset($entry['outputs']) && is_array($entry['outputs'])) {
      // Wait until at least one image exists
      $hasImg = false;
      foreach ($entry['outputs'] as $nodeOut) {
        if (is_array($nodeOut) && isset($nodeOut['images']) && is_array($nodeOut['images']) && count($nodeOut['images'])>0) { $hasImg = true; break; }
      }
      if ($hasImg) { $history = $entry; break; }
    }

    usleep(400000);
  }

  if (!is_array($history) || !isset($history['outputs']) || !is_array($history['outputs'])) {
    return ['ok'=>false,'error'=>'ComfyUI: timeout waiting for outputs (' . $timeoutSec . 's)'];
  }

  $imgs = [];
  foreach ($history['outputs'] as $nodeId => $nodeOut) {
    if (!is_array($nodeOut)) continue;
    $arr = $nodeOut['images'] ?? null;
    if (!is_array($arr)) continue;
    foreach ($arr as $im) {
      if (!is_array($im)) continue;
      $fn = (string)($im['filename'] ?? '');
      if ($fn === '') continue;
      $imgs[] = [
        'filename' => $fn,
        'subfolder' => (string)($im['subfolder'] ?? ''),
        'type' => (string)($im['type'] ?? 'output'),
      ];
    }
  }

  if (!$imgs) return ['ok'=>false,'error'=>'ComfyUI: no images in outputs'];

  $out = [];
  $i = 0;
  foreach ($imgs as $im) {
    $i++;
    $q = http_build_query([
      'filename' => $im['filename'],
      'subfolder' => $im['subfolder'],
      'type' => $im['type'],
    ]);
    $sendStatus('Downloading image…');
    [$bytes, $ct] = llc_comfyui_http_bytes($base . '/view?' . $q, 120);
    if ($ct === '') {
      // infer from filename
      $ext = strtolower(pathinfo($im['filename'], PATHINFO_EXTENSION));
      $ct = ($ext === 'jpg' || $ext === 'jpeg') ? 'image/jpeg' : (($ext === 'webp') ? 'image/webp' : 'image/png');
    }

    $ext = strtolower(pathinfo($im['filename'], PATHINFO_EXTENSION));
    if ($ext === '') {
      $ext = (str_contains($ct,'jpeg')) ? 'jpg' : (str_contains($ct,'webp') ? 'webp' : 'png');
    }

    $name = 'comfyui-' . gmdate('Ymd-His') . '-' . $i . '.' . $ext;
    $file = llc_store_generated_file($db, $uid, $bytes, $name, $ct);

    $att = [
      'id' => 'att_' . bin2hex(random_bytes(5)),
      'type' => 'image',
      'name' => $file['name'],
      'mime' => $file['mime'],
      'size' => $file['size'],
      'url' => $file['url'],
      'file_id' => $file['file_id'],
      'generated' => true,
      'model' => 'comfyui',
      'meta' => [
        'prompt_id' => $promptId,
        'source_filename' => $im['filename'],
      ]
    ];
    llc_sse_send(['type'=>'attachment','attachment'=>$att]);
    $out[] = $att;
  }

  return [
    'ok' => true,
    'provider' => 'comfyui',
    'prompt_id' => $promptId,
    'count' => count($out),
    'attachments' => array_map(function($a){
      return [
        'file_id' => $a['file_id'],
        'name' => $a['name'],
        'mime' => $a['mime'],
        'size' => $a['size'],
        'url' => $a['url']
      ];
    }, $out),
    'note' => 'Image(s) attached to the assistant message.'
  ];
}

function llc_openrouter_image_cfg(PDO $db, array $u): array {
  $base = trim((string)(llc_image_cfg_get($db, $u, 'image_openrouter_base_url') ?? 'https://openrouter.ai/api/v1'));
  if ($base === '') $base = 'https://openrouter.ai/api/v1';
  return [
    'base' => rtrim($base, '/'),
    'key' => (string)(llc_image_cfg_get($db, $u, 'image_openrouter_api_key') ?? ''),
    'model' => (string)(llc_image_cfg_get($db, $u, 'image_openrouter_model') ?? 'google/gemini-3-pro-image-preview'),
  ];
}

function llc_openrouter_size_to_image_config(string $size): array {
  $size = trim($size);
  if ($size === '' || $size === 'auto') return [];

  $aspect = '';
  if (preg_match('/^(\d+)x(\d+)$/', $size, $m)) {
    $w = max(1, (int)$m[1]);
    $h = max(1, (int)$m[2]);
    $g = function_exists('gmp_gcd') ? (int)gmp_strval(gmp_gcd($w, $h)) : 0;
    if ($g <= 0) {
      $a=$w; $b=$h;
      while ($b !== 0) { $t=$a % $b; $a=$b; $b=$t; }
      $g=max(1,$a);
    }
    $aspect = (int)($w/$g) . ':' . (int)($h/$g);
  } elseif (preg_match('/^\d+:\d+$/', $size)) {
    $aspect = $size;
  }

  $cfg = [];
  if ($aspect !== '') $cfg['aspect_ratio'] = $aspect;

  // OpenRouter image_size is model dependent. Use conservative mapping only for common configured sizes.
  if (preg_match('/^(\d+)x(\d+)$/', $size, $m)) {
    $max = max((int)$m[1], (int)$m[2]);
    if ($max >= 3000) $cfg['image_size'] = '4K';
    elseif ($max >= 1400) $cfg['image_size'] = '2K';
    elseif ($max >= 700) $cfg['image_size'] = '1K';
  } elseif (in_array($size, ['0.5K','1K','2K','4K'], true)) {
    $cfg['image_size'] = $size;
  }

  return $cfg;
}

function llc_tool_image_generate_openrouter(PDO $db, string $uid, array $u, array $args, callable $sendStatus): array {
  $cfg = llc_openrouter_image_cfg($db, $u);
  $base = $cfg['base'];
  $key = $cfg['key'];
  if (trim($key) === '') {
    return ['ok'=>false,'error'=>'No OpenRouter API key configured (Settings → Image → OpenRouter).'];
  }

  $model = trim((string)($cfg['model'] ?: 'google/gemini-3-pro-image-preview'));
  if ($model === '') $model = 'google/gemini-3-pro-image-preview';

  $prompt = (string)($args['prompt'] ?? '');
  if (trim($prompt) === '') return ['ok'=>false,'error'=>'image_generate: missing prompt'];

  $size = (string)($args['size'] ?? (llc_image_cfg_get($db, $u, 'image_size') ?? 'auto'));
  $imageConfig = llc_openrouter_size_to_image_config($size);

  $payload = [
    'model' => $model,
    'messages' => [[ 'role' => 'user', 'content' => $prompt ]],
    'modalities' => ['image', 'text'],
    'stream' => false,
  ];
  if (!empty($imageConfig)) $payload['image_config'] = $imageConfig;

  $hdrs = [
    'Content-Type: application/json',
    'Accept: application/json',
    'Authorization: Bearer ' . $key,
    'X-OpenRouter-Title: LLC',
  ];
  if (!empty($_SERVER['HTTP_HOST'])) {
    $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    $hdrs[] = 'HTTP-Referer: ' . $scheme . '://' . (string)$_SERVER['HTTP_HOST'];
  }

  $sendStatus('Calling OpenRouter image model…');

  $callOpenRouter = function(array $pl) use ($base, $hdrs): array {
    $ch = curl_init($base . '/chat/completions');
    curl_setopt_array($ch, [
      CURLOPT_POST => true,
      CURLOPT_HTTPHEADER => $hdrs,
      CURLOPT_POSTFIELDS => json_encode($pl, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
      CURLOPT_RETURNTRANSFER => true,
      CURLOPT_TIMEOUT => 180,
      CURLOPT_CONNECTTIMEOUT => 20,
    ]);
    $raw = curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $err = curl_error($ch);
    curl_close($ch);
    return ['raw'=>$raw, 'code'=>$code, 'err'=>$err];
  };

  $resp = $callOpenRouter($payload);
  $raw = $resp['raw'];
  $code = (int)$resp['code'];
  $err = (string)$resp['err'];
  $j = null;
  $hadError = false;

  if ($raw === false || $raw === null) {
    $hadError = true;
  } else {
    $j = json_decode((string)$raw, true);
    if (!is_array($j) || isset($j['error']) || ($code !== 0 && ($code < 200 || $code >= 300))) $hadError = true;
  }

  // Some OpenRouter image-only models reject text output modality. Retry once with image-only.
  if ($hadError && ($payload['modalities'] ?? null) === ['image', 'text']) {
    $payload['modalities'] = ['image'];
    $resp = $callOpenRouter($payload);
    $raw = $resp['raw'];
    $code = (int)$resp['code'];
    $err = (string)$resp['err'];
    $j = is_string($raw) ? json_decode($raw, true) : null;
  }

  if ($raw === false || $raw === null) {
    $msg = $err ?: 'unknown cURL error';
    if ($code) $msg .= ' (HTTP ' . $code . ')';
    return ['ok'=>false,'error'=>'OpenRouter image request failed: ' . $msg];
  }

  if (!is_array($j)) {
    $snip = trim(substr((string)$raw, 0, 800));
    return ['ok'=>false,'error'=>'OpenRouter image: invalid JSON (HTTP ' . $code . ').' . ($snip !== '' ? ' Response: ' . $snip : '')];
  }
  if (isset($j['error'])) {
    $msg = is_array($j['error']) ? (string)($j['error']['message'] ?? 'error') : (string)$j['error'];
    return ['ok'=>false,'error'=>'OpenRouter image error (HTTP ' . $code . '): ' . $msg];
  }
  if ($code !== 0 && ($code < 200 || $code >= 300)) {
    return ['ok'=>false,'error'=>'OpenRouter image error (HTTP ' . $code . '): ' . json_encode($j, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES)];
  }

  $msg = $j['choices'][0]['message'] ?? [];
  $images = is_array($msg) ? ($msg['images'] ?? null) : null;
  if (!is_array($images) || count($images) === 0) {
    return ['ok'=>false,'error'=>'OpenRouter image: no images returned'];
  }

  $out = [];
  $i = 0;
  foreach ($images as $img) {
    if (!is_array($img)) continue;
    $i++;
    $dataUrl = '';
    if (isset($img['image_url']['url']) && is_string($img['image_url']['url'])) $dataUrl = $img['image_url']['url'];
    elseif (isset($img['imageUrl']['url']) && is_string($img['imageUrl']['url'])) $dataUrl = $img['imageUrl']['url'];
    elseif (isset($img['url']) && is_string($img['url'])) $dataUrl = $img['url'];

    $bytes = '';
    $mime = 'image/png';
    $ext = 'png';
    if (preg_match('#^data:(image/[^;]+);base64,(.+)$#s', $dataUrl, $m)) {
      $mime = strtolower($m[1]);
      $decoded = base64_decode($m[2], true);
      if ($decoded !== false) $bytes = $decoded;
    } elseif (preg_match('#^[A-Za-z0-9+/=\r\n]+$#', $dataUrl) && strlen($dataUrl) > 100) {
      $decoded = base64_decode($dataUrl, true);
      if ($decoded !== false) $bytes = $decoded;
    }

    if ($bytes === '') continue;
    if (str_contains($mime, 'jpeg') || str_contains($mime, 'jpg')) $ext = 'jpg';
    elseif (str_contains($mime, 'webp')) $ext = 'webp';

    $name = 'generated-openrouter-' . gmdate('Ymd-His') . '-' . $i . '.' . $ext;
    $sendStatus('Saving image…');
    $file = llc_store_generated_file($db, $uid, $bytes, $name, $mime);

    $att = [
      'id' => 'att_' . bin2hex(random_bytes(5)),
      'type' => 'image',
      'name' => $file['name'],
      'mime' => $file['mime'],
      'size' => $file['size'],
      'url' => $file['url'],
      'file_id' => $file['file_id'],
      'generated' => true,
      'model' => $model,
      'provider' => 'openrouter'
    ];
    llc_sse_send(['type'=>'attachment','attachment'=>$att]);
    $out[] = $att;
  }

  if (count($out) === 0) return ['ok'=>false,'error'=>'OpenRouter image: no decodable image returned'];

  return [
    'ok' => true,
    'provider' => 'openrouter',
    'model' => $model,
    'count' => count($out),
    'attachments' => array_map(function($a){ return [
      'file_id' => $a['file_id'], 'name' => $a['name'], 'mime' => $a['mime'], 'size' => $a['size'], 'url' => $a['url']
    ]; }, $out),
    'note' => 'Image(s) attached to the assistant message.'
  ];
}


function llc_sdcpp_arg_quote(string $v): string {
  $v = str_replace(["\\", "'", "\r", "\n"], ["\\\\", "'\\''", ' ', ' '], $v);
  return "'" . $v . "'";
}

function llc_sdcpp_append_arg(array &$parts, string $flag, $value, bool $quote = false): void {
  if ($value === null) return;
  $s = trim((string)$value);
  if ($s === '' || strtolower($s) === 'default' || strtolower($s) === 'auto') return;
  $parts[] = $flag;
  $parts[] = $quote ? llc_sdcpp_arg_quote($s) : $s;
}


function llc_sdcpp_parse_int($value, int $min, int $max): ?int {
  if ($value === null) return null;
  if (is_int($value) || is_float($value)) $n = (int)$value;
  else {
    $str = trim((string)$value);
    if ($str === '' || !preg_match('/^-?\d+$/', $str)) return null;
    $n = (int)$str;
  }
  if ($n < $min) $n = $min;
  if ($n > $max) $n = $max;
  return $n;
}

function llc_sdcpp_parse_float($value, float $min, float $max): ?float {
  if ($value === null) return null;
  if (is_int($value) || is_float($value)) $n = (float)$value;
  else {
    $str = trim(str_replace(',', '.', (string)$value));
    if ($str === '' || !is_numeric($str)) return null;
    $n = (float)$str;
  }
  if ($n < $min) $n = $min;
  if ($n > $max) $n = $max;
  return $n;
}

function llc_sdcpp_size_from_string(string $s): ?array {
  $s = trim($s);
  if ($s === '' || strtolower($s) === 'auto') return null;
  if (preg_match('/(?<!\d)(\d{2,4})\s*[x×]\s*(\d{2,4})(?!\d)/iu', $s, $m)) {
    $w = llc_sdcpp_parse_int($m[1], 64, 4096);
    $h = llc_sdcpp_parse_int($m[2], 64, 4096);
    if ($w !== null && $h !== null) return [$w, $h];
  }
  return null;
}

function llc_sdcpp_text_has_explicit_steps(string $text): bool {
  if (trim($text) === '') return false;
  return (bool)(
    preg_match('/(?:^|[\s,.;])(?:steps?|sampling\s+steps?)\s*[:=]?\s*\d{1,3}(?=$|[\s,.;])/iu', $text) ||
    preg_match('/(?:^|[\s,.;])\d{1,3}\s*(?:steps?|sampling\s+steps?)(?=$|[\s,.;])/iu', $text)
  );
}

function llc_sdcpp_args_with_prompt_overrides(array $args): array {
  // The LLM may invent parameters (notably 50 steps) even when the user did not
  // ask for them. For stable-diffusion.cpp, only trust steps when the user text
  // or prompt actually contains an explicit steps directive.
  $prompt = (string)($args['prompt'] ?? '');
  $context = (string)($args['__llc_context_text'] ?? '');
  $parseText = trim($prompt . "\n" . $context);

  if ((!isset($args['width']) || !isset($args['height']))) {
    $size = isset($args['size']) ? llc_sdcpp_size_from_string((string)$args['size']) : null;
    if (!$size) $size = llc_sdcpp_size_from_string($parseText);
    if ($size) {
      $args['width'] = $args['width'] ?? $size[0];
      $args['height'] = $args['height'] ?? $size[1];
      $args['__llc_sdcpp_size_explicit'] = true;
    }
  } elseif (isset($args['width'], $args['height'])) {
    $args['__llc_sdcpp_size_explicit'] = true;
  }

  $userExplicitSteps = llc_sdcpp_text_has_explicit_steps($parseText);
  if ($userExplicitSteps) {
    if (preg_match('/(?:^|[\s,.;])(?:steps?|sampling\s+steps?)\s*[:=]?\s*(\d{1,3})(?=$|[\s,.;])/iu', $parseText, $m) ||
        preg_match('/(?:^|[\s,.;])(\d{1,3})\s*(?:steps?|sampling\s+steps?)(?=$|[\s,.;])/iu', $parseText, $m)) {
      $v = llc_sdcpp_parse_int($m[1], 1, 250);
      if ($v !== null) $args['steps'] = $v;
    }
    $args['__llc_sdcpp_steps_explicit'] = true;
  } else {
    // If the model silently inserted steps without the user asking, drop them.
    unset($args['steps']);
  }

  if (!isset($args['seed'])) {
    if (preg_match('/(?:^|[\s,.;])seed\s*[:=]?\s*(-?\d{1,12})(?=$|[\s,.;])/iu', $parseText, $m)) {
      $v = llc_sdcpp_parse_int($m[1], -1, 2147483647); if ($v !== null) $args['seed'] = $v;
    }
  }

  if (!isset($args['n']) && !isset($args['batch_size'])) {
    if (preg_match('/(?:^|[\s,.;])(?:batch|batch\s*count|batch\s*size|n)\s*[:=]?\s*(\d{1,2})(?=$|[\s,.;])/iu', $parseText, $m)) {
      $v = llc_sdcpp_parse_int($m[1], 1, 16); if ($v !== null) $args['batch_size'] = $v;
    }
  }

  if (!isset($args['cfg_scale']) && !isset($args['guidance'])) {
    if (preg_match('/(?:^|[\s,.;])(?:cfg|cfg\s*scale)\s*[:=]?\s*(\d+(?:[\.,]\d+)?)(?=$|[\s,.;])/iu', $parseText, $m)) {
      $v = llc_sdcpp_parse_float($m[1], 0.0, 100.0); if ($v !== null) $args['cfg_scale'] = $v;
    }
  }

  if (!isset($args['guidance'])) {
    if (preg_match('/(?:^|[\s,.;])(?:distilled\s+guidance|guidance)\s*[:=]?\s*(\d+(?:[\.,]\d+)?)(?=$|[\s,.;])/iu', $parseText, $m)) {
      $v = llc_sdcpp_parse_float($m[1], 0.0, 100.0); if ($v !== null) $args['guidance'] = $v;
    }
  }

  return $args;
}

function llc_sdcpp_normalize_base_url(string $base): string {
  $base = trim($base);
  if ($base === '') $base = 'http://127.0.0.1:1234/v1';
  $base = rtrim($base, '/');
  // The OpenAI-compatible stable-diffusion.cpp endpoints live below /v1.
  // Let users paste either http://host:1234 or http://host:1234/v1.
  if (!preg_match('#/v1$#i', $base)) $base .= '/v1';
  return $base;
}

function llc_sdcpp_cfg(PDO $db, array $u): array {
  $base = (string)(llc_image_cfg_get($db, $u, 'image_sdcpp_base_url') ?? 'http://127.0.0.1:1234/v1');
  return [
    'base' => llc_sdcpp_normalize_base_url($base),
    'key' => (string)(llc_image_cfg_get($db, $u, 'image_sdcpp_api_key') ?? ''),
    'model' => (string)(llc_image_cfg_get($db, $u, 'image_sdcpp_model') ?? 'flux-2-klein-base-4b-Q8_0.gguf'),
  ];
}

function llc_tool_image_generate_sdcpp(PDO $db, string $uid, array $u, array $args, callable $sendStatus): array {
  $args = llc_sdcpp_args_with_prompt_overrides($args);
  $cfg = llc_sdcpp_cfg($db, $u);
  $base = $cfg['base'];
  $key = $cfg['key'];
  $model = trim((string)($cfg['model'] ?: 'flux-2-klein-base-4b-Q8_0.gguf'));
  if ($model === '') $model = 'flux-2-klein-base-4b-Q8_0.gguf';

  $prompt = trim((string)($args['prompt'] ?? ''));
  if ($prompt === '') return ['ok'=>false,'error'=>'image_generate: missing prompt'];

  $width = (int)($args['width'] ?? (llc_image_cfg_get($db, $u, 'image_sdcpp_width') ?? 512));
  $height = (int)($args['height'] ?? (llc_image_cfg_get($db, $u, 'image_sdcpp_height') ?? 512));
  $n = (int)($args['n'] ?? $args['batch_size'] ?? (llc_image_cfg_get($db, $u, 'image_sdcpp_batch') ?? 1));
  $seed = (int)($args['seed'] ?? (llc_image_cfg_get($db, $u, 'image_sdcpp_seed') ?? -1));
  $stepsExplicit = !empty($args['__llc_sdcpp_steps_explicit']);
  $steps = $stepsExplicit ? (int)$args['steps'] : null;
  $cfgScaleExplicit = array_key_exists('cfg_scale', $args);
  $guidanceExplicit = array_key_exists('guidance', $args);
  $cfgScale = (float)($args['cfg_scale'] ?? (llc_image_cfg_get($db, $u, 'image_sdcpp_cfg_scale') ?? 7));
  $guidance = (float)($args['guidance'] ?? (llc_image_cfg_get($db, $u, 'image_sdcpp_guidance') ?? 3.5));
  $negative = (string)($args['negative_prompt'] ?? (llc_image_cfg_get($db, $u, 'image_sdcpp_negative_prompt') ?? ''));
  $sampling = (string)($args['sampling_method'] ?? (llc_image_cfg_get($db, $u, 'image_sdcpp_sampling_method') ?? ''));
  $scheduler = (string)($args['scheduler'] ?? (llc_image_cfg_get($db, $u, 'image_sdcpp_scheduler') ?? ''));
  $flowShift = (string)($args['flow_shift'] ?? (llc_image_cfg_get($db, $u, 'image_sdcpp_flow_shift') ?? ''));
  $extraRaw = trim((string)(llc_image_cfg_get($db, $u, 'image_sdcpp_extra_args') ?? ''));
  $timeoutSec = (int)(llc_image_cfg_get($db, $u, 'image_sdcpp_timeout_sec') ?? '900');
  $autoVaeTiling = (int)(llc_image_cfg_get($db, $u, 'image_sdcpp_auto_vae_tiling_768') ?? '1') !== 0;

  if ($width < 64) $width = 64; if ($width > 4096) $width = 4096;
  if ($height < 64) $height = 64; if ($height > 4096) $height = 4096;
  if ($n < 1) $n = 1; if ($n > 16) $n = 16;
  if ($steps !== null) { if ($steps < 1) $steps = 1; if ($steps > 250) $steps = 250; }
  if ($timeoutSec < 30) $timeoutSec = 30; if ($timeoutSec > 3600) $timeoutSec = 3600;

  // OpenAI compatibility only knows prompt/n/size. Everything else must use the
  // native sdcpp schema inside <sd_cpp_extra_args>. Do not send legacy/direct keys
  // like steps/sample_steps/cfg_scale: they are not the documented schema and can
  // produce weird fallback/default behaviour on newer server builds.
  $extraObj = [
    'seed' => $seed,
    'width' => $width,
    'height' => $height,
    'batch_count' => $n,
  ];

  $sampleParams = [];
  if ($stepsExplicit && $steps !== null) $sampleParams['sample_steps'] = $steps;
  if (trim($sampling) !== '') $sampleParams['sample_method'] = trim($sampling);
  if (trim($scheduler) !== '') $sampleParams['scheduler'] = trim($scheduler);
  if (trim($flowShift) !== '') $sampleParams['flow_shift'] = is_numeric($flowShift) ? (float)$flowShift : trim($flowShift);
  if ($cfgScaleExplicit || $guidanceExplicit) {
    $sampleParams['guidance'] = [];
    if ($cfgScaleExplicit) $sampleParams['guidance']['txt_cfg'] = $cfgScale;
    if ($guidanceExplicit) $sampleParams['guidance']['distilled_guidance'] = $guidance;
  }
  if (!empty($sampleParams)) $extraObj['sample_params'] = $sampleParams;

  if (trim($negative) !== '') $extraObj['negative_prompt'] = $negative;

  // Flux2/Vulkan often finishes sampling and then dies in VAE decode at 768x768.
  // Native schema supports tiled VAE; enable it automatically for >=768px on either axis.
  // The user's Extra Args JSON below can still override/disable this.
  $vaeTilingAuto = $autoVaeTiling && ($width >= 768 || $height >= 768);
  if ($vaeTilingAuto) {
    $extraObj['vae_tiling_params'] = [
      'enabled' => true,
      'tile_size_x' => 0,
      'tile_size_y' => 0,
      'target_overlap' => 0.5,
      'rel_size_x' => 0.0,
      'rel_size_y' => 0.0,
    ];
  }

  if ($extraRaw !== '') {
    $decodedExtra = json_decode($extraRaw, true);
    if (is_array($decodedExtra)) {
      $extraObj = array_replace_recursive($extraObj, $decodedExtra);
    } else {
      // Last-resort compatibility for users who paste raw CLI-ish options.
      $prompt .= ' ' . $extraRaw;
    }
  }

  $extraJson = json_encode($extraObj, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
  if ($extraJson !== false && $extraJson !== '') {
    $prompt .= '<sd_cpp_extra_args>' . $extraJson . '</sd_cpp_extra_args>';
  }

  $payload = [
    'model' => $model,
    'prompt' => $prompt,
    'n' => $n,
    'size' => $width . 'x' . $height,
    'response_format' => 'b64_json',
  ];

  $stepsLabel = ($stepsExplicit && $steps !== null) ? (string)$steps : 'server default';
  $vaeLabel = (!empty($extraObj['vae_tiling_params']['enabled'])) ? ', vae tiling on' : ($autoVaeTiling ? ', vae tiling auto off for size' : ', vae tiling disabled');
  $sendStatus('stable-diffusion.cpp params sent: ' . $width . 'x' . $height . ', steps ' . $stepsLabel . ', seed ' . $seed . ', batch ' . $n . $vaeLabel . (isset($args['__llc_context_text']) ? ' (parsed user message)' : ''));

  $hdrs = ['Content-Type: application/json', 'Accept: application/json'];
  if (trim($key) !== '' && trim($key) !== '********') $hdrs[] = 'Authorization: Bearer ' . $key;

  $sendStatus('Calling stable-diffusion.cpp image server…');

  $ch = curl_init($base . '/images/generations');
  curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => $hdrs,
    CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => $timeoutSec,
    CURLOPT_CONNECTTIMEOUT => 20,
  ]);
  $raw = curl_exec($ch);
  $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
  $err = curl_error($ch);
  curl_close($ch);

  if ($raw === false || $raw === null) {
    $msg = $err ?: 'unknown cURL error';
    if ($code) $msg .= ' (HTTP ' . $code . ')';
    return ['ok'=>false,'error'=>'stable-diffusion.cpp request failed: ' . $msg];
  }

  $j = json_decode((string)$raw, true);
  if (!is_array($j)) {
    $snip = trim(substr((string)$raw, 0, 800));
    return ['ok'=>false,'error'=>'stable-diffusion.cpp: invalid JSON (HTTP ' . $code . ').' . ($snip !== '' ? ' Response: ' . $snip : '')];
  }
  if (isset($j['error'])) {
    $msg = is_array($j['error']) ? (string)($j['error']['message'] ?? 'error') : (string)$j['error'];
    return ['ok'=>false,'error'=>'stable-diffusion.cpp error (HTTP ' . $code . '): ' . $msg];
  }
  if ($code !== 0 && ($code < 200 || $code >= 300)) {
    return ['ok'=>false,'error'=>'stable-diffusion.cpp error (HTTP ' . $code . '): ' . json_encode($j, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES)];
  }

  $data = $j['data'] ?? null;
  if (!is_array($data) || count($data) === 0) return ['ok'=>false,'error'=>'stable-diffusion.cpp: empty result'];

  $out = [];
  $i = 0;
  foreach ($data as $item) {
    $i++;
    if (!is_array($item)) continue;
    $bytes = '';
    $mime = 'image/png';
    $ext = 'png';
    $b64 = isset($item['b64_json']) && is_string($item['b64_json']) ? $item['b64_json'] : '';
    if ($b64 !== '') {
      if (preg_match('#^data:(image/[^;]+);base64,(.+)$#s', $b64, $m)) { $mime = strtolower($m[1]); $b64 = $m[2]; }
      $decoded = base64_decode($b64, true);
      if ($decoded !== false) $bytes = $decoded;
    } elseif (isset($item['url']) && is_string($item['url']) && $item['url'] !== '') {
      $dl = curl_init($item['url']);
      curl_setopt_array($dl, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 120, CURLOPT_CONNECTTIMEOUT => 20]);
      $bytes = (string)curl_exec($dl);
      $ct = (string)curl_getinfo($dl, CURLINFO_CONTENT_TYPE);
      curl_close($dl);
      if ($ct) $mime = $ct;
    }
    if ($bytes === '') continue;
    if (str_contains($mime, 'jpeg') || str_contains($mime, 'jpg')) $ext = 'jpg';
    elseif (str_contains($mime, 'webp')) $ext = 'webp';

    $name = 'generated-sdcpp-' . gmdate('Ymd-His') . '-' . $i . '.' . $ext;
    $sendStatus('Saving image…');
    $file = llc_store_generated_file($db, $uid, $bytes, $name, $mime);
    $att = [
      'id' => 'att_' . bin2hex(random_bytes(5)),
      'type' => 'image',
      'name' => $file['name'],
      'mime' => $file['mime'],
      'size' => $file['size'],
      'url' => $file['url'],
      'file_id' => $file['file_id'],
      'generated' => true,
      'model' => $model,
      'provider' => 'sdcpp'
    ];
    llc_sse_send(['type'=>'attachment','attachment'=>$att]);
    $out[] = $att;
  }

  if (count($out) === 0) return ['ok'=>false,'error'=>'stable-diffusion.cpp: no decodable image returned'];

  return [
    'ok' => true,
    'provider' => 'sdcpp',
    'model' => $model,
    'count' => count($out),
    'attachments' => array_map(function($a){ return [
      'file_id' => $a['file_id'], 'name' => $a['name'], 'mime' => $a['mime'], 'size' => $a['size'], 'url' => $a['url']
    ]; }, $out),
    'note' => 'Image(s) attached to the assistant message.'
  ];
}

function llc_tool_image_generate(PDO $db, string $uid, array $u, array $args, callable $sendStatus): array {
  $provider = llc_image_cfg_get($db, $u, 'image_provider') ?? 'openai';
  if ($provider === 'comfyui') {
    return llc_tool_image_generate_comfyui($db, $uid, $u, $args, $sendStatus);
  }
  if ($provider === 'openrouter') {
    return llc_tool_image_generate_openrouter($db, $uid, $u, $args, $sendStatus);
  }
  if ($provider === 'sdcpp') {
    return llc_tool_image_generate_sdcpp($db, $uid, $u, $args, $sendStatus);
  }
  if ($provider !== 'openai') {
    return ['ok'=>false,'error'=>'Image provider not supported: ' . $provider];
  }

  $base = trim((string)(llc_image_cfg_get($db, $u, 'image_base_url') ?? 'https://api.openai.com/v1'));
  if ($base === '') $base = 'https://api.openai.com/v1';
  $base = rtrim($base, '/');

  $key = (string)(llc_image_cfg_get($db, $u, 'image_api_key') ?? '');
  if (trim($key) === '') {
    return ['ok'=>false,'error'=>'No API key configured (Settings → Image).'];
  }

  $model = (string)(llc_image_cfg_get($db, $u, 'image_model') ?? 'gpt-image-2');
  if ($model === '') $model = 'gpt-image-2';

  $prompt = (string)($args['prompt'] ?? '');
  $n = (int)($args['n'] ?? 1);
  if ($n < 1) $n = 1;
  if ($n > 4) $n = 4;

  $size = (string)($args['size'] ?? (llc_image_cfg_get($db, $u, 'image_size') ?? 'auto'));
  $quality = (string)($args['quality'] ?? (llc_image_cfg_get($db, $u, 'image_quality') ?? 'auto'));
  $background = (string)($args['background'] ?? (llc_image_cfg_get($db, $u, 'image_background') ?? 'auto'));
  $outFmt = (string)($args['output_format'] ?? (llc_image_cfg_get($db, $u, 'image_output_format') ?? 'png'));
  if ($outFmt === '') $outFmt = 'png';

  // DALL·E 3 supports only n=1.
  if (str_starts_with($model, 'dall-e-3')) $n = 1;

  $payload = [
    'model' => $model,
    'prompt' => $prompt,
    'n' => $n,
  ];

  $isGptImage = (str_starts_with($model, 'gpt-image') || str_starts_with($model, 'chatgpt-image'));
  $isDalle = str_starts_with($model, 'dall-e');
  $isDalle3 = str_starts_with($model, 'dall-e-3');
  $isDalle2 = str_starts_with($model, 'dall-e-2');

  // Validate size/quality per model family to avoid needless API errors.
  if ($size !== '' && $size !== 'auto') {
    $allowed = [];
    if ($isGptImage) $allowed = ['1024x1024','1536x1024','1024x1536'];
    elseif ($isDalle3) $allowed = ['1024x1024','1792x1024','1024x1792'];
    elseif ($isDalle2) $allowed = ['256x256','512x512','1024x1024'];
    if (!in_array($size, $allowed, true)) $size = 'auto';
  }

  if ($quality !== '' && $quality !== 'auto') {
    $allowedQ = [];
    if ($isGptImage) $allowedQ = ['high','medium','low'];
    elseif ($isDalle3) $allowedQ = ['hd','standard'];
    elseif ($isDalle2) $allowedQ = ['standard'];
    if (!in_array($quality, $allowedQ, true)) $quality = 'auto';
  }

  if ($size !== '' && $size !== 'auto') $payload['size'] = $size;
  if ($quality !== '' && $quality !== 'auto') $payload['quality'] = $quality;


  if ($isGptImage) {
    if ($background !== '' && $background !== 'auto' && in_array($background, ['transparent','opaque'], true)) $payload['background'] = $background;
    if ($outFmt !== '' && in_array($outFmt, ['png','jpeg','webp'], true)) $payload['output_format'] = $outFmt;
  } elseif ($isDalle) {
    // Prefer base64 to avoid expiring URLs.
    $payload['response_format'] = 'b64_json';
  }

  $url = $base . '/images/generations';

  $hdrs = [
    'Content-Type: application/json',
    'Authorization: Bearer ' . $key,
  ];

  $sendStatus('Calling images API…');

  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => $hdrs,
    CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 120,
    CURLOPT_CONNECTTIMEOUT => 20,
  ]);
  $raw = curl_exec($ch);
  $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
  $err = curl_error($ch);
  curl_close($ch);

  if ($raw === false || $raw === null) {
    $msg = $err ?: 'unknown cURL error';
    if ($code) $msg .= ' (HTTP ' . $code . ')';
    return ['ok'=>false,'error'=>'Images API request failed: ' . $msg];
  }

  // Try JSON either way so we can surface upstream errors.
  $j = json_decode((string)$raw, true);
  if (!is_array($j)) {
    $snip = trim(substr((string)$raw, 0, 800));
    if ($snip !== '') $snip = ' Response: ' . $snip;
    return ['ok'=>false,'error'=>'Images API: invalid JSON (HTTP ' . $code . ').' . $snip];
  }
  if (isset($j['error'])) {
    $msg = is_array($j['error']) ? (string)($j['error']['message'] ?? 'error') : (string)$j['error'];
    $type = (is_array($j['error']) && isset($j['error']['type'])) ? (string)$j['error']['type'] : '';
    $codeStr = (is_array($j['error']) && isset($j['error']['code'])) ? (string)$j['error']['code'] : '';
    $extra = [];
    if ($type !== '') $extra[] = "type={$type}";
    if ($codeStr !== '') $extra[] = "code={$codeStr}";
    $extraStr = $extra ? (' [' . implode(', ', $extra) . ']') : '';
    return ['ok'=>false,'error'=>'Images API error (HTTP ' . $code . '): ' . $msg . $extraStr];
  }

  if ($code !== 0 && ($code < 200 || $code >= 300)) {
    // Non-2xx with no `error` object. Surface the response compactly.
    return ['ok'=>false,'error'=>'Images API error (HTTP ' . $code . '): ' . json_encode($j, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES)];
  }

  $data = $j['data'] ?? null;
  if (!is_array($data) || count($data) === 0) {
    return ['ok'=>false,'error'=>'Images API: empty result'];
  }

  $mime = ($outFmt === 'jpeg' || $outFmt === 'jpg') ? 'image/jpeg' : (($outFmt === 'webp') ? 'image/webp' : 'image/png');
  $ext = ($mime === 'image/jpeg') ? 'jpg' : (($mime === 'image/webp') ? 'webp' : 'png');

  $out = [];
  $i = 0;
  foreach ($data as $item) {
    $i++;
    $bytes = '';
    $itemB64 = (is_array($item) && isset($item['b64_json']) && is_string($item['b64_json'])) ? $item['b64_json'] : '';
    if ($itemB64 !== '') {
      $decoded = base64_decode($itemB64, true);
      if ($decoded !== false) $bytes = $decoded;
    } elseif (is_array($item) && isset($item['url']) && is_string($item['url']) && $item['url'] !== '') {
      // Fallback: download the URL
      $dl = curl_init($item['url']);
      curl_setopt_array($dl, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 120,
        CURLOPT_CONNECTTIMEOUT => 20,
      ]);
      $bytes = (string)curl_exec($dl);
      $ct = (string)curl_getinfo($dl, CURLINFO_CONTENT_TYPE);
      curl_close($dl);
      if ($ct) {
        $mime = $ct;
        $ext = (str_contains($ct, 'jpeg')) ? 'jpg' : (str_contains($ct, 'webp') ? 'webp' : 'png');
      }
    }

    if ($bytes === '') continue;

    $name = 'generated-' . gmdate('Ymd-His') . '-' . $i . '.' . $ext;

    $sendStatus('Saving image…');
    $file = llc_store_generated_file($db, $uid, $bytes, $name, $mime);

    // Emit SSE attachment so the client can display the image immediately.
    $att = [
      'id' => 'att_' . bin2hex(random_bytes(5)),
      'type' => 'image',
      'name' => $file['name'],
      'mime' => $file['mime'],
      'size' => $file['size'],
      'url' => $file['url'],
      'file_id' => $file['file_id'],
      'generated' => true,
      'model' => $model
    ];
    llc_sse_send(['type'=>'attachment','attachment'=>$att]);

    $out[] = $att;
  }

  if (count($out) === 0) {
    return ['ok'=>false,'error'=>'Images API: no decodable image returned'];
  }

  return [
    'ok' => true,
    'model' => $model,
    'count' => count($out),
    'attachments' => array_map(function($a){
      return [
        'file_id' => $a['file_id'],
        'name' => $a['name'],
        'mime' => $a['mime'],
        'size' => $a['size'],
        'url' => $a['url']
      ];
    }, $out),
    'note' => 'Image(s) attached to the assistant message.'
  ];
}





function llc_http_post_json_keepalive(string $url, array $hdrs, array $payload, float $pingEverySec = 15.0): array {
  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => $hdrs,
    CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HEADER => false,
    CURLOPT_TIMEOUT => 0,
    CURLOPT_CONNECTTIMEOUT => 20,
  ]);

  $mh = curl_multi_init();
  curl_multi_add_handle($mh, $ch);
  $active = null;
  $lastPingAt = microtime(true);

  do {
    do {
      $mrc = curl_multi_exec($mh, $active);
    } while ($mrc === CURLM_CALL_MULTI_PERFORM);

    if (connection_aborted()) {
      curl_multi_remove_handle($mh, $ch);
      curl_multi_close($mh);
      curl_close($ch);
      exit;
    }

    $now = microtime(true);
    if (($now - $lastPingAt) >= $pingEverySec) {
      llc_sse_send(['type'=>'ping']);
  // Optional: if a fatal error happens mid-stream, try to emit an SSE error+done so the UI doesn't hang.
  if (llc_dbg_enabled() && defined('LLC_DEBUG_FATAL_SSE') && (bool)LLC_DEBUG_FATAL_SSE) {
    register_shutdown_function(function() use ($uid) {
      $err = error_get_last();
      if (!is_array($err)) return;
      $fatalTypes = [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR];
      if (!in_array((int)$err['type'], $fatalTypes, true)) return;
      llc_dbg_log('fatal', [
        'uid' => $uid,
        'type' => (int)$err['type'],
        'message' => (string)($err['message'] ?? ''),
        'file' => (string)($err['file'] ?? ''),
        'line' => (int)($err['line'] ?? 0),
      ]);
      if (connection_aborted()) return;
      $msg = 'Fatal: ' . (string)($err['message'] ?? 'unknown') . ' in ' . (string)($err['file'] ?? '') . ':' . (int)($err['line'] ?? 0);
      echo "data: " . json_encode(['type'=>'error','error'=>$msg], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES) . "\n\n";
      echo "data: " . json_encode(['type'=>'done'], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES) . "\n\n";
      @ob_flush(); @flush();
    });
  }

      $lastPingAt = $now;
    }

    if ($active) curl_multi_select($mh, 1.0);
  } while ($active && $mrc === CURLM_OK);

  $body = curl_multi_getcontent($ch);
  $curlErr = curl_error($ch);
  $curlErrNo = curl_errno($ch);
  $httpCode = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);

  curl_multi_remove_handle($mh, $ch);
  curl_multi_close($mh);
  curl_close($ch);

  if ($curlErrNo !== 0) throw new RuntimeException('Upstream error: ' . ($curlErr ?: ('cURL errno ' . $curlErrNo)));
  if ($httpCode !== 0 && ($httpCode < 200 || $httpCode >= 300)) throw new RuntimeException('Upstream HTTP ' . $httpCode . ': ' . substr((string)$body, 0, 600));

  $j = json_decode((string)$body, true);
  if (!is_array($j)) throw new RuntimeException('Upstream returned invalid JSON');
  return $j;
}

function llc_extract_tool_calls($assistantMsg): array {
  if (!is_array($assistantMsg)) return [];
  $tc = $assistantMsg['tool_calls'] ?? null;
  if (is_array($tc) && !empty($tc)) return $tc;
  // Legacy: function_call
  $fc = $assistantMsg['function_call'] ?? null;
  if (is_array($fc) && !empty($fc)) {
    return [[
      'id' => 'legacy_function_call',
      'type' => 'function',
      'function' => $fc
    ]];
  }
  return [];
}


function llc_custom_tools_config(PDO $db, array $u): array {
  $uid = (string)($u['id'] ?? '');
  if ($uid === '') return [];
  $raw = (string)(llc_get_setting($db, $uid, 'custom_tools_json') ?? '[]');
  $j = json_decode($raw, true);
  if (!is_array($j)) return [];
  $out = [];
  foreach ($j as $it) {
    if (!is_array($it)) continue;
    $name = trim((string)($it['name'] ?? ''));
    if ($name === '' || !preg_match('/^[A-Za-z_][A-Za-z0-9_]{0,63}$/', $name)) continue;
    $endpoint = trim((string)($it['endpoint'] ?? $it['url'] ?? ''));
    if ($endpoint === '') continue;
    $method = strtoupper(trim((string)($it['method'] ?? 'POST')));
    if (!in_array($method, ['GET','POST'], true)) $method = 'POST';
    $params = $it['parameters'] ?? null;
    if (!is_array($params)) {
      $params = ['type'=>'object','properties'=>new stdClass()];
    }
    if (($params['type'] ?? '') !== 'object') $params['type'] = 'object';
    if (!isset($params['properties']) || (!is_array($params['properties']) && !is_object($params['properties']))) $params['properties'] = new stdClass();
    $out[] = [
      'id' => trim((string)($it['id'] ?? $name)),
      'name' => $name,
      'title' => trim((string)($it['title'] ?? $name)),
      'description' => trim((string)($it['description'] ?? ('Custom tool: ' . $name))),
      'endpoint' => $endpoint,
      'method' => $method,
      'headers' => $it['headers'] ?? [],
      'allow_private' => !empty($it['allow_private']),
      'timeout_sec' => max(1, min(120, (int)($it['timeout_sec'] ?? 30))),
      'parameters' => $params,
      'body_template' => is_string($it['body_template'] ?? null) ? (string)$it['body_template'] : '',
    ];
  }
  return $out;
}

function llc_custom_tools_openai(PDO $db, array $u, array $enabledNames): array {
  $enabled = [];
  foreach ($enabledNames as $x) {
    $k = trim((string)$x);
    if ($k !== '') $enabled[$k] = true;
  }
  if (!$enabled) return [];
  $tools = [];
  foreach (llc_custom_tools_config($db, $u) as $ct) {
    $name = (string)$ct['name'];
    $id = (string)($ct['id'] ?? $name);
    if (empty($enabled[$name]) && empty($enabled[$id])) continue;
    $tools[] = [
      'type' => 'function',
      'function' => [
        'name' => $name,
        'description' => (string)$ct['description'],
        'parameters' => $ct['parameters'],
      ]
    ];
  }
  return $tools;
}

function llc_find_custom_tool(PDO $db, array $u, string $name): ?array {
  foreach (llc_custom_tools_config($db, $u) as $ct) {
    if ((string)$ct['name'] === $name) return $ct;
  }
  return null;
}

function llc_custom_tool_headers($raw): array {
  if (is_array($raw)) {
    $hdrs = [];
    foreach ($raw as $k=>$v) {
      if (is_string($k) && (is_string($v) || is_numeric($v))) $hdrs[] = $k . ': ' . (string)$v;
      elseif (is_string($v) && str_contains($v, ':')) $hdrs[] = $v;
    }
    return $hdrs;
  }
  return llc_custom_headers((string)$raw);
}

function llc_apply_custom_tool_template(string $tpl, array $args): string {
  return preg_replace_callback('/{{\s*([A-Za-z0-9_\.\-]+)\s*}}/', function($m) use ($args) {
    $key = (string)$m[1];
    $val = $args[$key] ?? '';
    if (is_array($val) || is_object($val)) return json_encode($val, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE) ?: '';
    return (string)$val;
  }, $tpl) ?? $tpl;
}

function llc_execute_custom_tool(PDO $db, array $u, string $name, array $args): array {
  $ct = llc_find_custom_tool($db, $u, $name);
  if (!$ct) throw new RuntimeException('unknown custom tool: ' . $name);
  $endpoint = (string)$ct['endpoint'];
  llc_validate_public_http_url($endpoint, 'custom_tool ' . $name, !empty($ct['allow_private']));
  $method = strtoupper((string)$ct['method']);
  $timeout = (int)$ct['timeout_sec'];
  $hdrs = llc_custom_tool_headers($ct['headers'] ?? []);
  $hasContentType = false;
  foreach ($hdrs as $h) if (stripos($h, 'Content-Type:') === 0) $hasContentType = true;
  if ($method === 'GET') {
    $sep = str_contains($endpoint, '?') ? '&' : '?';
    $url = $endpoint . ($args ? $sep . http_build_query($args) : '');
    return llc_http_get_json($url, $hdrs, $timeout, min(10, $timeout));
  }
  if (!$hasContentType) $hdrs[] = 'Content-Type: application/json';
  $tpl = (string)($ct['body_template'] ?? '');
  if (trim($tpl) !== '') {
    $body = llc_apply_custom_tool_template($tpl, $args);
    $decoded = json_decode($body, true);
    $payload = is_array($decoded) ? $decoded : ['body' => $body, 'arguments' => $args];
  } else {
    $payload = ['arguments' => $args];
  }
  return llc_http_post_json($endpoint, $hdrs, $payload, $timeout, min(10, $timeout));
}

function llc_document_state_normalize(?array &$documentState): void {
  if (!is_array($documentState)) $documentState = [];
  if (!isset($documentState['documents']) || !is_array($documentState['documents'])) $documentState['documents'] = [];
  if (empty($documentState['documents']) && isset($documentState['active']) && is_array($documentState['active'])) {
    $a = $documentState['active'];
    $aid = (string)($a['id'] ?? ('doc_' . bin2hex(random_bytes(6))));
    $a['id'] = $aid;
    $documentState['documents'][$aid] = $a;
    $documentState['active_id'] = (string)($documentState['active_id'] ?? $documentState['activeId'] ?? $aid);
    $documentState['activeId'] = (string)$documentState['active_id'];
    unset($documentState['active']);
  }
}

function llc_document_find(?array &$documentState, string $docIdArg = ''): array {
  llc_document_state_normalize($documentState);
  $docs = (isset($documentState['documents']) && is_array($documentState['documents'])) ? $documentState['documents'] : [];
  $activeId = (string)($documentState['active_id'] ?? $documentState['activeId'] ?? '');
  $docId = trim($docIdArg) !== '' ? trim($docIdArg) : $activeId;
  if ($docId === '' && !empty($docs)) $docId = (string)array_key_first($docs);
  if ($docId === '' || !isset($docs[$docId]) || !is_array($docs[$docId])) throw new RuntimeException('document: unknown document_id');
  return [$docId, $docs[$docId]];
}

function llc_document_versions(array $doc): array {
  $map = [];
  $add = function($v) use (&$map, $doc) {
    if (!is_array($v)) return;
    $ver = (int)($v['version'] ?? 0);
    if ($ver <= 0) return;
    $map[$ver] = [
      'id' => (string)($v['id'] ?? $doc['id'] ?? ''),
      'title' => (string)($v['title'] ?? $doc['title'] ?? 'Untitled document'),
      'type' => (string)($v['type'] ?? $doc['type'] ?? 'markdown'),
      'version' => $ver,
      'content' => (string)($v['content'] ?? ''),
      'updated_at' => (int)($v['updated_at'] ?? 0),
    ];
  };
  if (isset($doc['history']) && is_array($doc['history'])) foreach ($doc['history'] as $h) $add($h);
  $add($doc);
  ksort($map, SORT_NUMERIC);
  return array_values($map);
}

function llc_last_user_text_from_messages(array $messages): string {
  for ($i = count($messages) - 1; $i >= 0; $i--) {
    $m = $messages[$i] ?? null;
    if (!is_array($m)) continue;
    if ((string)($m['role'] ?? '') !== 'user') continue;
    $txt = trim(llc_msg_content_to_text($m['content'] ?? ''));
    if ($txt !== '') return $txt;
  }
  return '';
}

function llc_status_clip(string $value, int $max = 88): string {
  $value = trim((string)(preg_replace('/\s+/u', ' ', $value) ?? $value));
  if ($value === '' || $max < 4) return $value;
  if (function_exists('mb_strlen') && function_exists('mb_substr')) {
    return mb_strlen($value, 'UTF-8') > $max ? mb_substr($value, 0, $max - 1, 'UTF-8') . '…' : $value;
  }
  return strlen($value) > $max ? substr($value, 0, $max - 3) . '...' : $value;
}

function llc_status_bytes(int $bytes): string {
  if ($bytes < 1024) return $bytes . ' B';
  if ($bytes < 1024 * 1024) return round($bytes / 1024, 1) . ' KB';
  return round($bytes / (1024 * 1024), 1) . ' MB';
}

function llc_workspace_tool_start_status(string $name, array $args): string {
  $path = llc_status_clip((string)($args['path'] ?? ''), 100);
  if ($path === '') $path = '.';

  if ($name === 'workspace_tree') {
    $depth = max(1, min(12, (int)($args['depth'] ?? 4)));
    return 'Workspace · Reading tree in ' . $path . ' (depth ' . $depth . ')';
  }
  if ($name === 'workspace_search') {
    $query = llc_status_clip((string)($args['query'] ?? ''), 72);
    $kind = !empty($args['regex']) ? 'regex' : 'text';
    return 'Workspace · Searching ' . $kind . ' “' . $query . '” in ' . $path;
  }
  if ($name === 'workspace_read') {
    $start = max(1, (int)($args['start_line'] ?? 1));
    $end = max($start, (int)($args['end_line'] ?? ($start + 399)));
    return 'Workspace · Reading ' . $path . ' · lines ' . $start . '–' . $end;
  }
  if ($name === 'workspace_write') {
    return 'Workspace · Writing ' . $path;
  }
  if ($name === 'workspace_replace') {
    $count = max(1, (int)($args['expected_replacements'] ?? 1));
    $verb = !empty($args['dry_run']) ? 'Checking' : 'Applying';
    return 'Workspace · ' . $verb . ' ' . $count . ' replacement' . ($count === 1 ? '' : 's') . ' in ' . $path;
  }
  if ($name === 'workspace_delete') {
    return 'Workspace · Deleting ' . $path;
  }
  if ($name === 'workspace_restore') {
    return 'Workspace · Restoring ' . $path . ' from snapshot';
  }
  return 'Workspace · Running ' . $name;
}

function llc_workspace_tool_done_status(string $name, array $args, array $res): string {
  $path = llc_status_clip((string)($res['path'] ?? $args['path'] ?? ''), 100);
  if ($path === '') $path = '.';

  if ($name === 'workspace_tree') {
    $files = 0; $dirs = 0;
    foreach (($res['items'] ?? []) as $item) {
      if (!is_array($item)) continue;
      if (($item['type'] ?? '') === 'directory') $dirs++; else if (($item['type'] ?? '') === 'file') $files++;
    }
    $suffix = !empty($res['truncated']) ? ' (result truncated)' : '';
    return 'Workspace · Found ' . $files . ' file' . ($files === 1 ? '' : 's') . ' and ' . $dirs . ' folder' . ($dirs === 1 ? '' : 's') . ' in ' . $path . $suffix;
  }
  if ($name === 'workspace_search') {
    $matches = is_array($res['matches'] ?? null) ? $res['matches'] : [];
    $count = count($matches);
    $files = [];
    foreach ($matches as $match) if (is_array($match) && isset($match['path'])) $files[(string)$match['path']] = true;
    $fileCount = count($files);
    $query = llc_status_clip((string)($res['query'] ?? $args['query'] ?? ''), 60);
    $suffix = !empty($res['truncated']) ? ' (result truncated)' : '';
    return 'Workspace · ' . $count . ' match' . ($count === 1 ? '' : 'es') . ' in ' . $fileCount . ' file' . ($fileCount === 1 ? '' : 's') . ' for “' . $query . '”' . $suffix;
  }
  if ($name === 'workspace_read') {
    $start = (int)($res['start_line'] ?? $args['start_line'] ?? 1);
    $end = (int)($res['end_line'] ?? $start);
    $suffix = !empty($res['truncated']) ? ' (more available)' : '';
    return 'Workspace · Read ' . $path . ' · lines ' . $start . '–' . $end . $suffix;
  }
  if ($name === 'workspace_write') {
    $verb = !empty($res['created']) ? 'Created ' : 'Updated ';
    $size = isset($res['size']) ? ' · ' . llc_status_bytes((int)$res['size']) : '';
    return 'Workspace · ' . $verb . $path . $size;
  }
  if ($name === 'workspace_replace') {
    $count = (int)($res['replacements'] ?? 0);
    if (!empty($res['dry_run'])) return 'Workspace · Checked ' . $count . ' replacement' . ($count === 1 ? '' : 's') . ' in ' . $path . ' · no file changed';
    return 'Workspace · Replaced ' . $count . ' occurrence' . ($count === 1 ? '' : 's') . ' in ' . $path;
  }
  if ($name === 'workspace_delete') {
    return 'Workspace · Deleted ' . $path;
  }
  if ($name === 'workspace_restore') {
    return 'Workspace · Restored ' . $path . ' from ' . llc_status_clip((string)($res['restored_from'] ?? $args['snapshot_id'] ?? 'snapshot'), 60);
  }
  return 'Workspace · ' . $name . ' completed';
}

function llc_execute_tool_call(PDO $db, array $u, array $toolCall, bool $emitStatus = true, ?array &$documentState = null, array $contextMessages = [], ?array $workspaceContext = null): array {
  $uid = (string)($u['id'] ?? '');
  $id = (string)($toolCall['id'] ?? '');
  if ($id === '') $id = 'toolcall_' . bin2hex(random_bytes(6));
  $fn = $toolCall['function'] ?? null;
  $name = is_array($fn) ? (string)($fn['name'] ?? '') : '';
  $argsRaw = is_array($fn) ? ($fn['arguments'] ?? '') : '';

  $args = [];
  if (is_string($argsRaw) && trim($argsRaw) !== '') {
    $tmp = json_decode($argsRaw, true);
    if (is_array($tmp)) $args = $tmp;
  } elseif (is_array($argsRaw)) {
    $args = $argsRaw;
  }


$sendStatus = function(string $message, string $phase = '') use ($emitStatus) {
  if (!$emitStatus) return;
  if ($message === '') return;
  $payload = ['type'=>'status','message'=>$message];
  if ($phase !== '') $payload['phase'] = $phase;
  llc_sse_send($payload);
};

  try {
    if ($name === 'web_read') {
      $url = (string)($args['url'] ?? '');
      // 0 means "use default" (which is user-configurable) or "unlimited" when the setting is unlimited.
      $max = (int)($args['max_chars'] ?? 0);
      $uHost = parse_url($url, PHP_URL_HOST);

      $sendStatus('Fetching page… ' . ($uHost ? $uHost : $url));

      $res = llc_tool_web_read($db, $u, $url, $max);

      $sendStatus('Fetch done', 'done');
      return [
        'role' => 'tool',
        'tool_call_id' => $id,
        'content' => json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE),
      ];
    }

    if ($name === 'web_search') {
      $q = (string)($args['q'] ?? '');
      $type = (string)($args['type'] ?? 'search');
      $gl = isset($args['gl']) ? (string)$args['gl'] : null;
      $hl = isset($args['hl']) ? (string)$args['hl'] : null;
      $num = isset($args['num']) ? (int)$args['num'] : null;
      $page = isset($args['page']) ? (int)$args['page'] : null;
      $autocorrect = array_key_exists('autocorrect', $args) ? (bool)$args['autocorrect'] : null;

      $label = ($type === 'news') ? 'News search… ' : 'Web search… ';


      $sendStatus($label . $q);


      $res = llc_tool_web_search($db, $u, $q, $type, $gl, $hl, $num, $page, $autocorrect);


      $sendStatus('Search done', 'done');
      return [
        'role' => 'tool',
        'tool_call_id' => $id,
        'content' => json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE),
      ];
    }

    $customTool = llc_find_custom_tool($db, $u, $name);
    if (is_array($customTool)) {
      $sendStatus('Running custom tool… ' . $name);
      $res = llc_execute_custom_tool($db, $u, $name, $args);
      $sendStatus('Custom tool done', 'done');
      return [
        'role' => 'tool',
        'tool_call_id' => $id,
        'content' => json_encode(['ok'=>true, 'tool'=>$name, 'result'=>$res], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE),
      ];
    }

    if (str_starts_with($name, 'workspace_')) {
      $ctx = llc_workspace_require_context($workspaceContext, in_array($name, ['workspace_write','workspace_replace','workspace_delete','workspace_restore'], true));
      $sendStatus(llc_workspace_tool_start_status($name, $args));
      if ($name === 'workspace_tree') {
        $res = llc_workspace_tree_result($ctx, $args);
      } elseif ($name === 'workspace_search') {
        $res = llc_workspace_search_result($ctx, $args);
      } elseif ($name === 'workspace_read') {
        $res = llc_workspace_read_result($ctx, $args);
      } elseif ($name === 'workspace_write') {
        $res = llc_workspace_write_result($db, $ctx, $args);
      } elseif ($name === 'workspace_replace') {
        $res = llc_workspace_replace_result($db, $ctx, $args);
      } elseif ($name === 'workspace_delete') {
        $res = llc_workspace_delete_result($db, $ctx, $args);
      } elseif ($name === 'workspace_restore') {
        $res = llc_workspace_restore_result($db, $ctx, $args);
      } else {
        throw new RuntimeException('Unknown workspace tool: ' . $name);
      }
      $sendStatus(llc_workspace_tool_done_status($name, $args, $res), 'done');
      return [
        'role'=>'tool',
        'tool_call_id'=>$id,
        'content'=>json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE),
      ];
    }

    if ($name === 'document_list') {
      if (!is_array($documentState)) $documentState = [];
      $docs = (isset($documentState['documents']) && is_array($documentState['documents'])) ? $documentState['documents'] : [];
      if (empty($docs) && isset($documentState['active']) && is_array($documentState['active'])) {
        $a = $documentState['active'];
        $aid = (string)($a['id'] ?? ('doc_' . bin2hex(random_bytes(6))));
        $a['id'] = $aid;
        $docs[$aid] = $a;
        $documentState['documents'] = $docs;
        $documentState['active_id'] = $aid;
        unset($documentState['active']);
      }
      $items = [];
      foreach ($docs as $did => $d) {
        if (!is_array($d)) continue;
        $items[] = [
          'id' => (string)($d['id'] ?? $did),
          'title' => (string)($d['title'] ?? 'Untitled document'),
          'type' => (string)($d['type'] ?? 'markdown'),
          'version' => (int)($d['version'] ?? 1),
          'updated_at' => (int)($d['updated_at'] ?? 0),
        ];
      }
      $res = ['ok'=>true, 'active_id'=>(string)($documentState['active_id'] ?? $documentState['activeId'] ?? ''), 'documents'=>$items];
      return ['role'=>'tool','tool_call_id'=>$id,'content'=>json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE)];
    }

    if ($name === 'document_select') {
      if (!is_array($documentState)) $documentState = [];
      $docs = (isset($documentState['documents']) && is_array($documentState['documents'])) ? $documentState['documents'] : [];
      $docId = trim((string)($args['document_id'] ?? ''));
      if ($docId === '' || !isset($docs[$docId]) || !is_array($docs[$docId])) throw new RuntimeException('document_select: unknown document_id');
      $documentState['active_id'] = $docId;
      $documentState['activeId'] = $docId;
      llc_sse_send(['type'=>'document_update','document'=>$docs[$docId]]);
      $sendStatus('Document selected', 'done');
      $res = ['ok'=>true, 'document'=>$docs[$docId]];
      return ['role'=>'tool','tool_call_id'=>$id,'content'=>json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE)];
    }

    if ($name === 'document_history' || $name === 'document_get_version' || $name === 'document_revert') {
      llc_document_state_normalize($documentState);
      [$docId, $doc] = llc_document_find($documentState, (string)($args['document_id'] ?? ''));
      $versions = llc_document_versions($doc);

      if ($name === 'document_history') {
        $items = [];
        foreach ($versions as $v) {
          $items[] = [
            'version' => (int)$v['version'],
            'title' => (string)$v['title'],
            'type' => (string)$v['type'],
            'updated_at' => (int)$v['updated_at'],
            'size' => strlen((string)$v['content']),
            'is_current' => ((int)$v['version'] === (int)($doc['version'] ?? 0)),
          ];
        }
        $res = ['ok'=>true, 'document_id'=>$docId, 'current_version'=>(int)($doc['version'] ?? 0), 'versions'=>$items];
        return ['role'=>'tool','tool_call_id'=>$id,'content'=>json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE)];
      }

      $wantVer = (int)($args['version'] ?? 0);
      if ($wantVer <= 0) throw new RuntimeException($name . ': missing version');
      $snap = null;
      foreach ($versions as $v) {
        if ((int)$v['version'] === $wantVer) { $snap = $v; break; }
      }
      if (!$snap) throw new RuntimeException($name . ': version not found');

      if ($name === 'document_get_version') {
        $res = ['ok'=>true, 'document_id'=>$docId, 'version'=>(int)$snap['version'], 'title'=>(string)$snap['title'], 'type'=>(string)$snap['type'], 'updated_at'=>(int)$snap['updated_at'], 'content'=>(string)$snap['content']];
        return ['role'=>'tool','tool_call_id'=>$id,'content'=>json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE)];
      }

      $nowMs = (int)round(microtime(true) * 1000);
      $newVer = ((int)($doc['version'] ?? 0)) + 1;
      $hist = array_slice($versions, -49);
      $newDoc = [
        'id' => $docId,
        'title' => (string)($snap['title'] ?: ($doc['title'] ?? 'Untitled document')),
        'type' => (string)($snap['type'] ?: ($doc['type'] ?? 'markdown')),
        'content' => (string)$snap['content'],
        'version' => $newVer,
        'created_at' => (int)($doc['created_at'] ?? $nowMs),
        'updated_at' => $nowMs,
      ];
      $hist[] = ['id'=>$docId, 'title'=>$newDoc['title'], 'type'=>$newDoc['type'], 'version'=>$newDoc['version'], 'content'=>$newDoc['content'], 'updated_at'=>$newDoc['updated_at']];
      $newDoc['history'] = $hist;
      $documentState['documents'][$docId] = $newDoc;
      $documentState['active_id'] = $docId;
      $documentState['activeId'] = $docId;
      $sendStatus('Document version restored', 'done');
      llc_sse_send(['type'=>'document_update','document'=>$newDoc]);
      $res = ['ok'=>true, 'restored_from_version'=>$wantVer, 'document'=>$newDoc, 'summary'=>(string)($args['summary'] ?? '')];
      return ['role'=>'tool','tool_call_id'=>$id,'content'=>json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE)];
    }

    if ($name === 'document_create' || $name === 'document_update') {
      if (!is_array($documentState)) $documentState = [];
      if (!isset($documentState['documents']) || !is_array($documentState['documents'])) $documentState['documents'] = [];
      if (empty($documentState['documents']) && isset($documentState['active']) && is_array($documentState['active'])) {
        $a = $documentState['active'];
        $aid = (string)($a['id'] ?? ('doc_' . bin2hex(random_bytes(6))));
        $a['id'] = $aid;
        $documentState['documents'][$aid] = $a;
        $documentState['active_id'] = (string)($documentState['active_id'] ?? $documentState['activeId'] ?? $aid);
        unset($documentState['active']);
      }

      $docs =& $documentState['documents'];
      $activeId = (string)($documentState['active_id'] ?? $documentState['activeId'] ?? '');
      $docIdArg = trim((string)($args['document_id'] ?? ''));

      if ($name === 'document_create') {
        $docId = 'doc_' . bin2hex(random_bytes(6));
        $prev = [];
      } else {
        $docId = $docIdArg !== '' ? $docIdArg : $activeId;
        $prev = ($docId !== '' && isset($docs[$docId]) && is_array($docs[$docId])) ? $docs[$docId] : [];
        if ($docId === '') $docId = (string)($prev['id'] ?? ('doc_' . bin2hex(random_bytes(6))));
      }

      $title = trim((string)($args['title'] ?? ($prev['title'] ?? 'Untitled document')));
      if ($title === '') $title = 'Untitled document';
      $type = trim((string)($args['type'] ?? ($prev['type'] ?? 'markdown')));
      if ($type === '') $type = 'markdown';
      $content = (string)($args['content'] ?? ($prev['content'] ?? ''));
      $oldVer = isset($prev['version']) ? (int)$prev['version'] : 0;
      $nowMs = (int)round(microtime(true) * 1000);
      $hist = (isset($prev['history']) && is_array($prev['history'])) ? array_slice($prev['history'], -29) : [];
      $doc = [
        'id' => $docId,
        'title' => $title,
        'type' => $type,
        'content' => $content,
        'version' => $oldVer + 1,
        'created_at' => (int)($prev['created_at'] ?? $nowMs),
        'updated_at' => $nowMs,
      ];
      $hist[] = [
        'id' => $doc['id'], 'title' => $doc['title'], 'type' => $doc['type'],
        'version' => $doc['version'], 'content' => $doc['content'], 'updated_at' => $doc['updated_at']
      ];
      $doc['history'] = $hist;
      $docs[$docId] = $doc;
      $documentState['active_id'] = $docId;
      $documentState['activeId'] = $docId;
      $sendStatus(($name === 'document_create') ? 'Document created' : 'Document updated', 'done');
      llc_sse_send(['type'=>'document_update','document'=>$doc]);
      $res = ['ok'=>true, 'document'=>$doc, 'summary'=>(string)($args['summary'] ?? '')];
      return [
        'role' => 'tool',
        'tool_call_id' => $id,
        'content' => json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE),
      ];
    }


    if ($name === 'image_generate') {
      $prompt = (string)($args['prompt'] ?? '');
      if (trim($prompt) === '') throw new RuntimeException('image_generate: missing prompt');

      // Do not trust the model to preserve generation directives in tool args.
      // Keep the original user message available to the image provider parser so
      // "generate foo, 5 steps, 768x768" still becomes steps=5 / size=768x768
      // even if the tool call only contains prompt="foo".
      $ctxText = llc_last_user_text_from_messages($contextMessages);
      if ($ctxText !== '') $args['__llc_context_text'] = $ctxText;

      $sendStatus('Generating image…');
      if (function_exists('llc_ensure_default_settings')) llc_ensure_default_settings($db, $uid);
      $res = llc_tool_image_generate($db, $uid, $u, $args, $sendStatus);
      if (!empty($res['ok'])) {
        $sendStatus('Image done', 'done');
      } else {
        $errMsg = is_array($res) ? (string)($res['error'] ?? 'unknown error') : 'unknown error';
        $sendStatus('Image failed: ' . $errMsg, 'error');
      }
      return [
        'role' => 'tool',
        'tool_call_id' => $id,
        'content' => json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE),
      ];
    }


    $res = ['ok'=>false,'error'=>'Unknown tool: ' . $name];
    return [
      'role' => 'tool',
      'tool_call_id' => $id,
      'content' => json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE),
    ];
  } catch (Throwable $e) {
    if (str_starts_with($name, 'workspace_')) {
      $sendStatus('Workspace · Failed: ' . llc_status_clip($e->getMessage(), 140), 'error');
    }
    $res = ['ok'=>false,'error'=>$e->getMessage()];
    return [
      'role' => 'tool',
      'tool_call_id' => $id,
      'content' => json_encode($res, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE),
    ];
  }
}




/**
 * Stream an OpenAI-compatible chat/completions SSE response to the client as our own SSE events.
 * Expects caller already set Content-Type: text/event-stream etc.
 */
function llc_stream_upstream_sse(string $url, array $hdrs, array $payload): void {
  // Split inline <think>...</think> blocks out of normal content during streaming.
  $inThink = false;
  $thinkCarry = '';

  $ended = false;
  $lastPingAt = microtime(true);
  $lastUpstreamAt = microtime(true);

  $statsSent = false;

  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => $hdrs,
    CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    CURLOPT_RETURNTRANSFER => false,
    CURLOPT_HEADER => false,
    CURLOPT_TIMEOUT => 0,
    CURLOPT_CONNECTTIMEOUT => 20,
  ]);

  $buf = '';
  curl_setopt($ch, CURLOPT_WRITEFUNCTION, function($ch, $data) use (&$buf, &$inThink, &$thinkCarry, &$ended, &$lastUpstreamAt, &$statsSent) {
    if (connection_aborted()) return 0;
    $lastUpstreamAt = microtime(true);
    $buf .= $data;
    while (true) {
      $pos = strpos($buf, "\n");
      if ($pos === false) break;
      $line = trim(substr($buf, 0, $pos));
      $buf = substr($buf, $pos + 1);

      if ($line === '' || !str_starts_with($line, 'data:')) continue;
      $payload = trim(substr($line, 5));
      if ($payload === '[DONE]') {
        if ($thinkCarry !== '') {
          llc_sse_send(['type'=>($inThink?'reasoning':'content'),'delta'=>$thinkCarry]);
          $thinkCarry = '';
        }
        if (!$ended) {
          $ended = true;
          llc_sse_send(['type'=>'done']);
        }
        continue;
      }

      $j = json_decode($payload, true);
      if (!is_array($j)) continue;

      if (!$statsSent) {
        $stats = llc_extract_upstream_speed_stats($j);
        if (is_array($stats)) {
          $statsSent = true;
          llc_sse_send($stats);
        }
      }

      $choice0 = $j['choices'][0] ?? null;
      $delta = (is_array($choice0) ? ($choice0['delta'] ?? null) : null);
      $msg = (is_array($choice0) ? ($choice0['message'] ?? null) : null);
      if (!is_array($msg)) $msg = ($j['message'] ?? null);

      // Out-of-band reasoning fields (preferred)
      if (is_array($delta)) {
        foreach (['reasoning','reasoning_content'] as $rk) {
          if (isset($delta[$rk]) && is_string($delta[$rk]) && $delta[$rk] !== '') {
            llc_sse_send(['type'=>'reasoning','delta'=>$delta[$rk]]);
          }
        }
      }
      if (is_array($msg)) {
        foreach (['reasoning','reasoning_content'] as $rk) {
          if (isset($msg[$rk]) && is_string($msg[$rk]) && $msg[$rk] !== '') {
            llc_sse_send(['type'=>'reasoning','delta'=>$msg[$rk]]);
          }
        }
      }

      // In-band content may contain <think>...</think>
      $contentChunk = null;
      if (is_array($delta) && isset($delta['content']) && is_string($delta['content']) && $delta['content'] !== '') {
        $contentChunk = $delta['content'];
      } elseif (is_array($msg) && isset($msg['content']) && is_string($msg['content']) && $msg['content'] !== '') {
        $contentChunk = $msg['content'];
      }
      if (is_string($contentChunk) && $contentChunk !== '') {
        $parts = llc_split_think_stream($contentChunk, $inThink, $thinkCarry);
        if (!empty($parts['reasoning'])) llc_sse_send(['type'=>'reasoning','delta'=>$parts['reasoning']]);
        if (!empty($parts['content'])) llc_sse_send(['type'=>'content','delta'=>$parts['content']]);
      }
    }
    @ob_flush(); @flush();
    return strlen($data);
  });

  $mh = curl_multi_init();
  curl_multi_add_handle($mh, $ch);

  $active = null;
  do {
    do {
      $mrc = curl_multi_exec($mh, $active);
    } while ($mrc === CURLM_CALL_MULTI_PERFORM);

    $now = microtime(true);
    if (($now - $lastPingAt) >= 15.0) {
      llc_sse_send(['type'=>'ping']);
      $lastPingAt = $now;
    }

    if (connection_aborted()) {
      break;
    }

    if ($active) {
      curl_multi_select($mh, 1.0);
    }
  } while ($active && $mrc === CURLM_OK);

  $curlErr = curl_error($ch);
  $curlErrNo = curl_errno($ch);
  $httpCode = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);

  curl_multi_remove_handle($mh, $ch);
  curl_multi_close($mh);
  curl_close($ch);

  llc_dbg_log('stream_end', ['http'=>$httpCode,'curl_errno'=>$curlErrNo,'ended'=>$ended]);
  if (connection_aborted()) exit;

  if ($curlErrNo !== 0) llc_sse_error('Upstream error: ' . ($curlErr ?: ('cURL errno ' . $curlErrNo)));
  if ($httpCode !== 0 && ($httpCode < 200 || $httpCode >= 300)) llc_sse_error('Upstream HTTP ' . $httpCode);

  if ($thinkCarry !== '') {
    llc_sse_send(['type'=>($inThink?'reasoning':'content'),'delta'=>$thinkCarry]);
    $thinkCarry = '';
  }
  if (!$ended) llc_sse_send(['type'=>'done']);
  exit;
}

// ---------- bootstrap ----------
function llc_bootstrap(): void {
  $db = llc_db();
  $u = llc_session_user($db);
  if (!$u) {
    llc_json(['logged_in'=>false]);
  }
  $uid = (string)$u['id'];

  // If more users are introduced later, make sure defaults exist.
  if (function_exists('llc_ensure_default_settings')) llc_ensure_default_settings($db, $uid);

  $stF = $db->prepare("SELECT id,parent_id,name,created_at,updated_at FROM folders WHERE user_id=? ORDER BY name ASC");
  $stF->execute([$uid]);
  $folders = $stF->fetchAll();

  $stC = $db->prepare("SELECT id,title,preview,folder_id,connection_id,updated_at,model,meta_json FROM chats WHERE user_id=? ORDER BY updated_at DESC");
  $stC->execute([$uid]);
  $chats = $stC->fetchAll();
  foreach ($chats as &$c) {
    $meta = json_decode((string)($c['meta_json'] ?? '{}'), true);
    if (!is_array($meta)) $meta = [];
    $clone = $meta['clone'] ?? [];
    if (!is_array($clone)) $clone = [];
    $c['clone_attached'] = !empty($clone['attached']) ? 1 : 0;
    $c['clone_parent_id'] = (string)($clone['parent_id'] ?? '');
    $c['clone_root_id'] = (string)($clone['root_id'] ?? '');
    unset($c['meta_json']);
  }
  unset($c);

  $stT = $db->prepare("SELECT id,name,created_at,updated_at FROM templates WHERE user_id=? ORDER BY name COLLATE NOCASE ASC");
  $stT->execute([$uid]);
  $templates = $stT->fetchAll();

  $connections = llc_connections_for_user($db, $u, true);

  $selected_model = llc_get_setting($db, $uid, 'selected_model') ?? '';
  $selected_conn  = llc_get_setting($db, $uid, 'selected_connection_id') ?? '';

  // Ensure selected connection is visible/enabled; otherwise choose a fallback.
  $selOk = false;
  foreach ($connections as $c) {
    if ((string)($c['id'] ?? '') === (string)$selected_conn && (int)($c['enabled'] ?? 1) === 1) { $selOk = true; break; }
  }
  if (!$selOk) {
    $fallback = '';
    foreach ($connections as $c) {
      if ((int)($c['enabled'] ?? 1) === 1) { $fallback = (string)$c['id']; break; }
    }
    $selected_conn = $fallback;
    llc_set_setting($db, $uid, 'selected_connection_id', $selected_conn);
  }
  $system_prompt  = llc_get_setting($db, $uid, 'system_prompt') ?? '';

  // General UI settings
  $web_auto_enable = llc_get_setting($db, $uid, 'web_auto_enable');
  if ($web_auto_enable === null || $web_auto_enable === '') $web_auto_enable = '0';

  $web_search_auto_enable = llc_get_setting($db, $uid, 'web_search_auto_enable');
  if ($web_search_auto_enable === null || $web_search_auto_enable === '') $web_search_auto_enable = '0';

  $web_prefer_attachments = llc_get_setting($db, $uid, 'web_prefer_attachments');
  if ($web_prefer_attachments === null || $web_prefer_attachments === '') $web_prefer_attachments = '1';

  $media_image_inline = llc_get_setting($db, $uid, 'media_image_inline');
  if ($media_image_inline === null || $media_image_inline === '') $media_image_inline = '1';

  $media_audio_inline = llc_get_setting($db, $uid, 'media_audio_inline');
  if ($media_audio_inline === null || $media_audio_inline === '') $media_audio_inline = '1';

  $custom_tools_json = llc_get_setting($db, $uid, 'custom_tools_json') ?? '[]';
  if (trim((string)$custom_tools_json) === '') $custom_tools_json = '[]';

  $custom_tools_auto_enable = llc_get_setting($db, $uid, 'custom_tools_auto_enable');
  if ($custom_tools_auto_enable === null || $custom_tools_auto_enable === '') $custom_tools_auto_enable = '0';

  // Web settings (may be inherited from shared global settings)
  $inherit_global_web = llc_inherit_global_web($db, $u) ? 1 : 0;

  $web_allow_private = llc_web_cfg_get($db, $u, 'web_allow_private');
  if ($web_allow_private === null || $web_allow_private === '') $web_allow_private = '0';

  // Web extraction limits
  // 0 = unlimited
  $web_fetch_max_chars = llc_web_cfg_get($db, $u, 'web_fetch_max_chars');
  if ($web_fetch_max_chars === null || $web_fetch_max_chars === '') $web_fetch_max_chars = '20000';
  $web_tool_max_chars = llc_web_cfg_get($db, $u, 'web_tool_max_chars');
  if ($web_tool_max_chars === null || $web_tool_max_chars === '') $web_tool_max_chars = '12000';

  // General (server limits)
  $tool_max_iters = llc_get_global_setting($db, 'tool_max_iters');
  if ($tool_max_iters === null || $tool_max_iters === '') $tool_max_iters = '10';
  $tool_max_iters_n = (int)$tool_max_iters;
  if ($tool_max_iters_n < 1) $tool_max_iters_n = 1;
  if ($tool_max_iters_n > 50) $tool_max_iters_n = 50;

  $upload_hard_limit_mb = llc_upload_hard_limit_mb($db);
  $media_image_inline_limit_mb = llc_media_image_inline_limit_mb($db);
  $media_audio_inline_limit_mb = llc_media_audio_inline_limit_mb($db);

  // Search settings (may be inherited from shared global settings)
  $inherit_global_search = llc_inherit_global_search($db, $u) ? 1 : 0;

  $search_provider = llc_search_cfg_get($db, $u, 'search_provider') ?? 'serper';
  $serper_api_key = llc_search_cfg_get($db, $u, 'serper_api_key') ?? '';
  $brave_api_key = llc_search_cfg_get($db, $u, 'brave_api_key') ?? '';
  $search_custom_url = llc_search_cfg_get($db, $u, 'search_custom_url') ?? '';
  $search_custom_news_url = llc_search_cfg_get($db, $u, 'search_custom_news_url') ?? '';
  $search_custom_allow_private = llc_search_cfg_get($db, $u, 'search_custom_allow_private');
  if ($search_custom_allow_private === null || $search_custom_allow_private === '') $search_custom_allow_private = '0';
  $search_custom_api_key = llc_search_cfg_get($db, $u, 'search_custom_api_key') ?? '';
  $searchngx_url = llc_search_cfg_get($db, $u, 'searchngx_url') ?? '';
  $searchngx_allow_private = llc_search_cfg_get($db, $u, 'searchngx_allow_private');
  if ($searchngx_allow_private === null || $searchngx_allow_private === '') $searchngx_allow_private = '0';
  $searchngx_api_key = llc_search_cfg_get($db, $u, 'searchngx_api_key') ?? '';
  $search_gl = llc_search_cfg_get($db, $u, 'search_gl') ?? 'de';
  $search_hl = llc_search_cfg_get($db, $u, 'search_hl') ?? 'de';
  $search_num = llc_search_cfg_get($db, $u, 'search_num') ?? '10';

  // Never leak global search API keys to regular users.
  if ($inherit_global_search === 1) {
    if (trim($serper_api_key) !== '') $serper_api_key = '********';
    if (trim($brave_api_key) !== '') $brave_api_key = '********';
    if (trim($search_custom_api_key) !== '') $search_custom_api_key = '********';
    if (trim($searchngx_api_key) !== '') $searchngx_api_key = '********';
  }

  // Image settings (may be inherited from shared global settings)
  $inherit_global_image = llc_inherit_global_image($db, $u) ? 1 : 0;

  $image_provider = llc_image_cfg_get($db, $u, 'image_provider') ?? 'openai';
  $image_base_url = llc_image_cfg_get($db, $u, 'image_base_url') ?? 'https://api.openai.com/v1';
  $image_api_key = llc_image_cfg_get($db, $u, 'image_api_key') ?? '';
  $image_model = llc_image_cfg_get($db, $u, 'image_model') ?? 'gpt-image-2';
  $image_openrouter_base_url = llc_image_cfg_get($db, $u, 'image_openrouter_base_url') ?? 'https://openrouter.ai/api/v1';
  $image_openrouter_api_key = llc_image_cfg_get($db, $u, 'image_openrouter_api_key') ?? '';
  $image_openrouter_model = llc_image_cfg_get($db, $u, 'image_openrouter_model') ?? 'google/gemini-3-pro-image-preview';
  $image_sdcpp_base_url = llc_image_cfg_get($db, $u, 'image_sdcpp_base_url') ?? 'http://127.0.0.1:1234/v1';
  $image_sdcpp_api_key = llc_image_cfg_get($db, $u, 'image_sdcpp_api_key') ?? '';
  $image_sdcpp_model = llc_image_cfg_get($db, $u, 'image_sdcpp_model') ?? 'flux-2-klein-base-4b-Q8_0.gguf';
  $image_sdcpp_negative_prompt = llc_image_cfg_get($db, $u, 'image_sdcpp_negative_prompt') ?? '';
  $image_sdcpp_width = llc_image_cfg_get($db, $u, 'image_sdcpp_width') ?? '512';
  $image_sdcpp_height = llc_image_cfg_get($db, $u, 'image_sdcpp_height') ?? '512';
  $image_sdcpp_batch = llc_image_cfg_get($db, $u, 'image_sdcpp_batch') ?? '1';
  $image_sdcpp_seed = llc_image_cfg_get($db, $u, 'image_sdcpp_seed') ?? '-1';
  $image_sdcpp_steps = llc_image_cfg_get($db, $u, 'image_sdcpp_steps') ?? '20';
  $image_sdcpp_cfg_scale = llc_image_cfg_get($db, $u, 'image_sdcpp_cfg_scale') ?? '7';
  $image_sdcpp_guidance = llc_image_cfg_get($db, $u, 'image_sdcpp_guidance') ?? '3.5';
  $image_sdcpp_sampling_method = llc_image_cfg_get($db, $u, 'image_sdcpp_sampling_method') ?? '';
  $image_sdcpp_scheduler = llc_image_cfg_get($db, $u, 'image_sdcpp_scheduler') ?? '';
  $image_sdcpp_flow_shift = llc_image_cfg_get($db, $u, 'image_sdcpp_flow_shift') ?? '';
  $image_sdcpp_extra_args = llc_image_cfg_get($db, $u, 'image_sdcpp_extra_args') ?? '';
  $image_sdcpp_timeout_sec = llc_image_cfg_get($db, $u, 'image_sdcpp_timeout_sec') ?? '900';
  $image_sdcpp_auto_vae_tiling_768 = llc_image_cfg_get($db, $u, 'image_sdcpp_auto_vae_tiling_768');
  if ($image_sdcpp_auto_vae_tiling_768 === null || $image_sdcpp_auto_vae_tiling_768 === '') $image_sdcpp_auto_vae_tiling_768 = '1';

  // Per-user UI toggles (even when Image is inherited globally)
  $image_auto_enable = llc_get_setting($db, $uid, 'image_auto_enable');
  if ($image_auto_enable === null || $image_auto_enable === '') $image_auto_enable = '0';

  $vision_auto_attach_last_image = llc_get_setting($db, $uid, 'vision_auto_attach_last_image');
  if ($vision_auto_attach_last_image === null || $vision_auto_attach_last_image === '') $vision_auto_attach_last_image = '1';
  $image_size = llc_image_cfg_get($db, $u, 'image_size') ?? 'auto';
  $image_quality = llc_image_cfg_get($db, $u, 'image_quality') ?? 'auto';
  $image_background = llc_image_cfg_get($db, $u, 'image_background') ?? 'auto';
  $image_output_format = llc_image_cfg_get($db, $u, 'image_output_format') ?? 'png';

  // ComfyUI settings (optional)
  $image_comfyui_url = llc_image_cfg_get($db, $u, 'image_comfyui_url') ?? '';
  $image_comfyui_workflow_json = llc_image_cfg_get($db, $u, 'image_comfyui_workflow_json') ?? '';
  $image_comfyui_bindings_json = llc_image_cfg_get($db, $u, 'image_comfyui_bindings_json') ?? '';
  $image_comfyui_seed = llc_image_cfg_get($db, $u, 'image_comfyui_seed');
  if ($image_comfyui_seed === null || $image_comfyui_seed === '') $image_comfyui_seed = '-1';
  $image_comfyui_steps = llc_image_cfg_get($db, $u, 'image_comfyui_steps');
  if ($image_comfyui_steps === null || $image_comfyui_steps === '') $image_comfyui_steps = '20';
  $image_comfyui_guidance = llc_image_cfg_get($db, $u, 'image_comfyui_guidance');
  if ($image_comfyui_guidance === null || $image_comfyui_guidance === '') $image_comfyui_guidance = '3.5';
  $image_comfyui_width = llc_image_cfg_get($db, $u, 'image_comfyui_width');
  if ($image_comfyui_width === null || $image_comfyui_width === '') $image_comfyui_width = '512';
  $image_comfyui_height = llc_image_cfg_get($db, $u, 'image_comfyui_height');
  if ($image_comfyui_height === null || $image_comfyui_height === '') $image_comfyui_height = '512';
  $image_comfyui_batch = llc_image_cfg_get($db, $u, 'image_comfyui_batch');
  if ($image_comfyui_batch === null || $image_comfyui_batch === '') $image_comfyui_batch = '1';
  $image_comfyui_apply_defaults = llc_image_cfg_get($db, $u, 'image_comfyui_apply_defaults');
  if ($image_comfyui_apply_defaults === null || $image_comfyui_apply_defaults === '') $image_comfyui_apply_defaults = '0';
  $image_comfyui_timeout_sec = llc_image_cfg_get($db, $u, 'image_comfyui_timeout_sec');
  if ($image_comfyui_timeout_sec === null || $image_comfyui_timeout_sec === '') $image_comfyui_timeout_sec = '900';

  // Never leak global image API keys to regular users.
  if ($inherit_global_image === 1) {
    if (trim($image_api_key) !== '') $image_api_key = '********';
    if (trim($image_openrouter_api_key) !== '') $image_openrouter_api_key = '********';
    if (trim($image_sdcpp_api_key) !== '') $image_sdcpp_api_key = '********';
  }

  // Voice settings (may be inherited from shared global settings)
  $inherit_global_voice = llc_inherit_global_voice($db, $u) ? 1 : 0;

  $voice_api_key = llc_voice_cfg_get($db, $u, 'voice_api_key') ?? '';

  // Per-user UI toggles (even when Voice is inherited globally)
  $voice_auto_enable = llc_get_setting($db, $uid, 'voice_auto_enable');
  if ($voice_auto_enable === null || $voice_auto_enable === '') $voice_auto_enable = '0';

  $voice_auto_send = llc_get_setting($db, $uid, 'voice_auto_send');
  if ($voice_auto_send === null || $voice_auto_send === '') $voice_auto_send = '1';

  $voice_tts_provider = llc_voice_cfg_get($db, $u, 'voice_tts_provider') ?? 'browser';
  $voice_tts_voice = llc_voice_cfg_get($db, $u, 'voice_tts_voice') ?? 'marin';
  $voice_tts_model = llc_voice_cfg_get($db, $u, 'voice_tts_model') ?? 'gpt-4o-mini-tts';

  // Never leak global voice API keys to regular users.
  if ($inherit_global_voice === 1) {
    if (trim($voice_api_key) !== '') $voice_api_key = '********';
  }

  // Pricing rules (per user; JSON list)
  $pricing = [];
  try {
    $pricing_json = llc_get_setting($db, $uid, 'pricing_json') ?? '[]';
    $pricing_raw = json_decode((string)$pricing_json, true);
    if (is_array($pricing_raw)) {
      foreach ($pricing_raw as $r) {
        if (!is_array($r)) continue;
        $cid = trim((string)($r['connection_id'] ?? ''));
        $model = trim((string)($r['model'] ?? ''));
        if ($cid === '' || $model === '') continue;
        $pp = $r['prompt_price'] ?? '';
        $gp = $r['gen_price'] ?? '';
        $pp_out = '';
        $gp_out = '';
        if ($pp !== '' && $pp !== null) {
          $pp_f = (float)$pp;
          if ($pp_f >= 0) $pp_out = $pp_f;
        }
        if ($gp !== '' && $gp !== null) {
          $gp_f = (float)$gp;
          if ($gp_f >= 0) $gp_out = $gp_f;
        }
        $pricing[] = [
          'connection_id' => $cid,
          'model' => $model,
          'prompt_price' => $pp_out,
          'gen_price' => $gp_out
        ];
      }
    }
  } catch (Throwable $_) { /* noop */ }


  // Models cache is per-user too (safe default).
  $models_cache_json = llc_get_setting($db, $uid, 'models_cache_json') ?? '';
  $models_cache = [];
  if ($models_cache_json !== '') {
    $tmp = json_decode($models_cache_json, true);
    if (is_array($tmp)) $models_cache = $tmp;
  }
  $models_cache_at = llc_get_setting($db, $uid, 'models_cache_at') ?? '';

  llc_json([
    'logged_in'=>true,
    'user'=>$u,
    'folders'=>$folders,
    'chats'=>$chats,
    'templates'=>$templates,
    'connections'=>$connections,
    'can_create_connections'=> (llc_can_manage_own_connections($db, $u) || llc_is_superadmin_user($u)) ? 1 : 0,
    'inherit_global_connections'=> llc_inherit_global_connections($db, $u) ? 1 : 0,
    'inherit_global_web'=> (int)$inherit_global_web,
    'inherit_global_search'=> (int)$inherit_global_search,
    'inherit_global_image'=> (int)$inherit_global_image,
    'inherit_global_voice'=> (int)$inherit_global_voice,
    'models'=>$models_cache,
    'models_errors'=>[],
    'selected_model'=>$selected_model,
    'selected_connection_id'=>$selected_conn,
    'pricing'=>$pricing,
    'system_prompt'=>$system_prompt,
    'web_auto_enable'=>(int)$web_auto_enable,
    'web_search_auto_enable'=>(int)$web_search_auto_enable,
    'web_prefer_attachments'=>(int)$web_prefer_attachments,
    'media_image_inline'=>(int)$media_image_inline,
    'media_audio_inline'=>(int)$media_audio_inline,
    'web_allow_private'=>(int)$web_allow_private,
    'web_fetch_max_chars'=>(int)$web_fetch_max_chars,
    'web_tool_max_chars'=>(int)$web_tool_max_chars,
    'tool_max_iters'=>(int)$tool_max_iters_n,
    'upload_hard_limit_mb'=>(int)$upload_hard_limit_mb,
    'media_image_inline_limit_mb'=>(int)$media_image_inline_limit_mb,
    'media_audio_inline_limit_mb'=>(int)$media_audio_inline_limit_mb,
    'custom_tools_json'=>(string)$custom_tools_json,
    'custom_tools_auto_enable'=>(int)$custom_tools_auto_enable,
    'custom_tools'=>llc_custom_tools_config($db, $u),
    'search_provider'=>(string)$search_provider,
    'serper_api_key'=>(string)$serper_api_key,
    'brave_api_key'=>(string)$brave_api_key,
    'search_custom_url'=>(string)$search_custom_url,
    'search_custom_news_url'=>(string)$search_custom_news_url,
    'search_custom_allow_private'=>(int)$search_custom_allow_private,
    'search_custom_api_key'=>(string)$search_custom_api_key,
    'searchngx_url'=>(string)$searchngx_url,
    'searchngx_allow_private'=>(int)$searchngx_allow_private,
    'searchngx_api_key'=>(string)$searchngx_api_key,
    'search_gl'=>(string)$search_gl,
    'search_hl'=>(string)$search_hl,
    'search_num'=>(int)$search_num,
    'image_provider'=>(string)$image_provider,
    'image_base_url'=>(string)$image_base_url,
    'image_api_key'=>(string)$image_api_key,
    'image_model'=>(string)$image_model,
    'image_openrouter_base_url'=>(string)$image_openrouter_base_url,
    'image_openrouter_api_key'=>(string)$image_openrouter_api_key,
    'image_openrouter_model'=>(string)$image_openrouter_model,
    'image_sdcpp_base_url'=>(string)$image_sdcpp_base_url,
    'image_sdcpp_api_key'=>(string)$image_sdcpp_api_key,
    'image_sdcpp_model'=>(string)$image_sdcpp_model,
    'image_sdcpp_negative_prompt'=>(string)$image_sdcpp_negative_prompt,
    'image_sdcpp_width'=>(int)$image_sdcpp_width,
    'image_sdcpp_height'=>(int)$image_sdcpp_height,
    'image_sdcpp_batch'=>(int)$image_sdcpp_batch,
    'image_sdcpp_seed'=>(int)$image_sdcpp_seed,
    'image_sdcpp_steps'=>(int)$image_sdcpp_steps,
    'image_sdcpp_cfg_scale'=>(float)$image_sdcpp_cfg_scale,
    'image_sdcpp_guidance'=>(float)$image_sdcpp_guidance,
    'image_sdcpp_sampling_method'=>(string)$image_sdcpp_sampling_method,
    'image_sdcpp_scheduler'=>(string)$image_sdcpp_scheduler,
    'image_sdcpp_flow_shift'=>(string)$image_sdcpp_flow_shift,
    'image_sdcpp_extra_args'=>(string)$image_sdcpp_extra_args,
    'image_sdcpp_timeout_sec'=>(int)$image_sdcpp_timeout_sec,
    'image_sdcpp_auto_vae_tiling_768'=>(int)$image_sdcpp_auto_vae_tiling_768,
    'image_auto_enable'=>(int)$image_auto_enable,
    'vision_auto_attach_last_image'=>(int)$vision_auto_attach_last_image,
    'image_size'=>(string)$image_size,
    'image_quality'=>(string)$image_quality,
    'image_background'=>(string)$image_background,
    'image_output_format'=>(string)$image_output_format,
    'voice_api_key'=>(string)$voice_api_key,
    'voice_auto_enable'=>(int)$voice_auto_enable,
    'voice_auto_send'=>(int)$voice_auto_send,
    'voice_tts_provider'=>(string)$voice_tts_provider,
    'voice_tts_voice'=>(string)$voice_tts_voice,
    'voice_tts_model'=>(string)$voice_tts_model,
    'image_comfyui_url'=>(string)$image_comfyui_url,
    'image_comfyui_workflow_json'=>(string)$image_comfyui_workflow_json,
    'image_comfyui_bindings_json'=>(string)$image_comfyui_bindings_json,
    'image_comfyui_seed'=>(int)$image_comfyui_seed,
    'image_comfyui_steps'=>(int)$image_comfyui_steps,
    'image_comfyui_guidance'=>(float)$image_comfyui_guidance,
    'image_comfyui_width'=>(int)$image_comfyui_width,
    'image_comfyui_height'=>(int)$image_comfyui_height,
    'image_comfyui_batch'=>(int)$image_comfyui_batch,
    'image_comfyui_apply_defaults'=>(int)$image_comfyui_apply_defaults,
    'image_comfyui_timeout_sec'=>(int)$image_comfyui_timeout_sec,

    'models_cached_at'=>$models_cache_at
  ]);
}




function llc_image_openrouter_models(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  if (function_exists('llc_ensure_default_settings')) llc_ensure_default_settings($db, (string)$u['id']);

  $cfg = llc_openrouter_image_cfg($db, $u);
  $base = $cfg['base'];
  $key = $cfg['key'];

  $url = $base . '/models?output_modalities=image';
  $hdrs = [
    'Accept: application/json',
    'X-OpenRouter-Title: LLC',
  ];
  if (trim($key) !== '' && trim($key) !== '********') $hdrs[] = 'Authorization: Bearer ' . $key;

  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_HTTPGET => true,
    CURLOPT_HTTPHEADER => $hdrs,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 30,
    CURLOPT_CONNECTTIMEOUT => 10,
  ]);
  $raw = curl_exec($ch);
  $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
  $err = curl_error($ch);
  curl_close($ch);

  if ($raw === false || $raw === null) {
    llc_json(['error'=>'OpenRouter /models request failed: ' . ($err ?: 'unknown cURL error')], 502);
  }
  $j = json_decode((string)$raw, true);
  if (!is_array($j)) llc_json(['error'=>'OpenRouter /models returned invalid JSON'], 502);
  if (isset($j['error'])) {
    $msg = is_array($j['error']) ? (string)($j['error']['message'] ?? 'error') : (string)$j['error'];
    llc_json(['error'=>'OpenRouter /models error (HTTP ' . $code . '): ' . $msg], 502);
  }
  if ($code < 200 || $code >= 300) llc_json(['error'=>'OpenRouter /models HTTP ' . $code], 502);

  $data = $j['data'] ?? [];
  if (!is_array($data)) $data = [];

  $models = [];
  foreach ($data as $it) {
    if (!is_array($it)) continue;
    $id = trim((string)($it['id'] ?? ''));
    if ($id === '') continue;

    $outs = [];
    if (isset($it['output_modalities']) && is_array($it['output_modalities'])) $outs = $it['output_modalities'];
    elseif (isset($it['architecture']['output_modalities']) && is_array($it['architecture']['output_modalities'])) $outs = $it['architecture']['output_modalities'];
    elseif (isset($it['supported_output_modalities']) && is_array($it['supported_output_modalities'])) $outs = $it['supported_output_modalities'];
    $outsLower = array_map('strtolower', array_map('strval', $outs));
    // The query parameter should already filter, but keep a manual guard when the upstream ignores it.
    if (!empty($outsLower) && !in_array('image', $outsLower, true)) continue;

    $name = trim((string)($it['name'] ?? $id));
    $pricing = is_array($it['pricing'] ?? null) ? $it['pricing'] : [];
    $models[] = [
      'id' => $id,
      'name' => $name !== '' ? $name : $id,
      'context_length' => $it['context_length'] ?? null,
      'output_modalities' => $outsLower,
      'pricing' => $pricing,
    ];
  }

  usort($models, function($a, $b){ return strcasecmp((string)$a['name'], (string)$b['name']); });
  llc_json(['models'=>$models, 'count'=>count($models)]);
}

// ---------- settings ----------
function llc_settings_save(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  if (function_exists('llc_ensure_default_settings')) llc_ensure_default_settings($db, $uid);

  $j = llc_read_json();

  // Web tool settings may be inherited globally (read-only for regular users).
  // NOTE: Per-user UI toggles (web_auto_enable / web_search_auto_enable / web_prefer_attachments) remain editable.
  if (llc_inherit_global_web($db, $u)) {
    $blocked = [
      'web_allow_private','web_fetch_max_chars','web_tool_max_chars'
    ];
    foreach ($blocked as $bk) {
      if (array_key_exists($bk, $j)) {
        llc_json(['error'=>'Web settings are managed globally for this user'], 403);
      }
    }
  }

  // Search settings may be inherited globally (read-only for regular users).
  if (llc_inherit_global_search($db, $u)) {
    $blocked = [
      'search_provider','serper_api_key','brave_api_key','search_custom_url','search_custom_news_url','search_custom_allow_private','search_custom_api_key',
      'searchngx_url','searchngx_allow_private','searchngx_api_key','search_gl','search_hl','search_num'
    ];
    foreach ($blocked as $bk) {
      if (array_key_exists($bk, $j)) {
        llc_json(['error'=>'Search settings are managed globally for this user'], 403);
      }
    }
  }
  // Image settings may be inherited globally (read-only for regular users).
  if (llc_inherit_global_image($db, $u)) {
    $blocked = [
      'image_provider','image_base_url','image_api_key','image_model',
      'image_openrouter_base_url','image_openrouter_api_key','image_openrouter_model',
      'image_sdcpp_base_url','image_sdcpp_api_key','image_sdcpp_model','image_sdcpp_negative_prompt','image_sdcpp_width','image_sdcpp_height','image_sdcpp_batch','image_sdcpp_seed','image_sdcpp_steps','image_sdcpp_cfg_scale','image_sdcpp_guidance','image_sdcpp_sampling_method','image_sdcpp_scheduler','image_sdcpp_flow_shift','image_sdcpp_extra_args','image_sdcpp_timeout_sec','image_sdcpp_auto_vae_tiling_768',
      'image_size','image_quality','image_background','image_output_format',
      'image_comfyui_url','image_comfyui_workflow_json','image_comfyui_bindings_json','image_comfyui_seed','image_comfyui_steps','image_comfyui_guidance',
      'image_comfyui_width','image_comfyui_height','image_comfyui_batch','image_comfyui_apply_defaults','image_comfyui_timeout_sec'
    ];
    foreach ($blocked as $bk) {
      if (array_key_exists($bk, $j)) {
        llc_json(['error'=>'Image settings are managed globally for this user'], 403);
      }
    }
  }

  // Voice settings may be inherited globally (read-only for regular users).
  if (llc_inherit_global_voice($db, $u)) {
    $blocked = [
      'voice_api_key','voice_tts_provider','voice_tts_voice','voice_tts_model'
    ];
    foreach ($blocked as $bk) {
      if (array_key_exists($bk, $j)) {
        llc_json(['error'=>'Voice settings are managed globally for this user'], 403);
      }
    }
  }

  // General (global) settings are superadmin-only.
  $globalGeneralKeys = ['tool_max_iters','upload_hard_limit_mb','media_image_inline_limit_mb','media_audio_inline_limit_mb'];
  foreach ($globalGeneralKeys as $gk) {
    if (array_key_exists($gk, $j) && !llc_is_superadmin_user($u)) {
      llc_json(['error'=>'Only superadmins can change this setting'], 403);
    }
  }

  $isSuperadmin = llc_is_superadmin_user($u);
  $setSearchCfg = function(string $k, string $v) use ($db, $uid, $isSuperadmin): void {
    if ($isSuperadmin) llc_set_global_setting($db, $k, $v);
    else llc_set_setting($db, $uid, $k, $v);
  };
  $setWebCfg = function(string $k, string $v) use ($db, $uid, $isSuperadmin): void {
    if ($isSuperadmin) llc_set_global_setting($db, $k, $v);
    else llc_set_setting($db, $uid, $k, $v);
  };
  $setImageCfg = function(string $k, string $v) use ($db, $uid, $isSuperadmin): void {
    if ($isSuperadmin) llc_set_global_setting($db, $k, $v);
    else llc_set_setting($db, $uid, $k, $v);
  };
  $setVoiceCfg = function(string $k, string $v) use ($db, $uid, $isSuperadmin): void {
    if ($isSuperadmin) llc_set_global_setting($db, $k, $v);
    else llc_set_setting($db, $uid, $k, $v);
  };

  // Only update provided keys; otherwise preserve existing values.
  if (array_key_exists('selected_model', $j)) {
    llc_set_setting($db, $uid, 'selected_model', (string)($j['selected_model'] ?? ''));
  }
  if (array_key_exists('selected_connection_id', $j)) {
    $cid = trim((string)($j['selected_connection_id'] ?? ''));
    if ($cid !== '' && !llc_conn_accessible($db, $u, $cid)) $cid = '';
    llc_set_setting($db, $uid, 'selected_connection_id', $cid);
  }
  if (array_key_exists('system_prompt', $j)) {
    llc_set_setting($db, $uid, 'system_prompt', (string)($j['system_prompt'] ?? ''));
  }
  if (array_key_exists('tool_max_iters', $j) && $isSuperadmin) {
    $v = (int)($j['tool_max_iters'] ?? 10);
    if ($v < 1) $v = 1;
    if ($v > 50) $v = 50;
    llc_set_global_setting($db, 'tool_max_iters', (string)$v);
  }
  if (array_key_exists('upload_hard_limit_mb', $j) && $isSuperadmin) {
    $v = (int)($j['upload_hard_limit_mb'] ?? 25);
    if ($v < 1) $v = 1;
    if ($v > 1024) $v = 1024;
    llc_set_global_setting($db, 'upload_hard_limit_mb', (string)$v);
  }
  if (array_key_exists('media_image_inline_limit_mb', $j) && $isSuperadmin) {
    $v = (int)($j['media_image_inline_limit_mb'] ?? 8);
    if ($v < 0) $v = 0;
    if ($v > 1024) $v = 1024;
    llc_set_global_setting($db, 'media_image_inline_limit_mb', (string)$v);
  }
  if (array_key_exists('media_audio_inline_limit_mb', $j) && $isSuperadmin) {
    $v = (int)($j['media_audio_inline_limit_mb'] ?? 15);
    if ($v < 0) $v = 0;
    if ($v > 1024) $v = 1024;
    llc_set_global_setting($db, 'media_audio_inline_limit_mb', (string)$v);
  }
  if (array_key_exists('web_auto_enable', $j)) {
    $v = (int)$j['web_auto_enable'];
    llc_set_setting($db, $uid, 'web_auto_enable', (string)($v === 0 ? '0' : '1'));
  }
  if (array_key_exists('web_search_auto_enable', $j)) {
    $v = (int)$j['web_search_auto_enable'];
    llc_set_setting($db, $uid, 'web_search_auto_enable', (string)($v === 0 ? '0' : '1'));
  }
  if (array_key_exists('web_prefer_attachments', $j)) {
    $v = (int)$j['web_prefer_attachments'];
    llc_set_setting($db, $uid, 'web_prefer_attachments', (string)($v === 0 ? '0' : '1'));
  }
  if (array_key_exists('media_image_inline', $j)) {
    $v = (int)$j['media_image_inline'];
    llc_set_setting($db, $uid, 'media_image_inline', (string)($v === 0 ? '0' : '1'));
  }
  if (array_key_exists('media_audio_inline', $j)) {
    $v = (int)$j['media_audio_inline'];
    llc_set_setting($db, $uid, 'media_audio_inline', (string)($v === 0 ? '0' : '1'));
  }
  if (array_key_exists('custom_tools_auto_enable', $j)) {
    $v = (int)$j['custom_tools_auto_enable'];
    llc_set_setting($db, $uid, 'custom_tools_auto_enable', (string)($v === 0 ? '0' : '1'));
  }
  if (array_key_exists('custom_tools_json', $j)) {
    $raw = (string)($j['custom_tools_json'] ?? '[]');
    $tmp = json_decode($raw, true);
    if (!is_array($tmp)) llc_json(['error'=>'Custom tools JSON is invalid'], 400);
    llc_set_setting($db, $uid, 'custom_tools_json', json_encode($tmp, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE));
  }
  if (array_key_exists('web_allow_private', $j)) {
    $v = (int)$j['web_allow_private'];
    $setWebCfg('web_allow_private', (string)($v === 0 ? '0' : '1'));
  }

  // Web extraction limits (0 = unlimited)
  if (array_key_exists('web_fetch_max_chars', $j)) {
    $v = (int)($j['web_fetch_max_chars'] ?? 20000);
    if ($v < 0) $v = 0;
    $setWebCfg('web_fetch_max_chars', (string)$v);
  }
  if (array_key_exists('web_tool_max_chars', $j)) {
    $v = (int)($j['web_tool_max_chars'] ?? 12000);
    if ($v < 0) $v = 0;
    $setWebCfg('web_tool_max_chars', (string)$v);
  }

  if (array_key_exists('search_provider', $j)) {
    $setSearchCfg('search_provider', (string)($j['search_provider'] ?? 'serper'));
  }
  if (array_key_exists('serper_api_key', $j)) {
    $setSearchCfg('serper_api_key', (string)($j['serper_api_key'] ?? ''));
  }
  if (array_key_exists('brave_api_key', $j)) {
    $setSearchCfg('brave_api_key', (string)($j['brave_api_key'] ?? ''));
  }
  if (array_key_exists('search_custom_url', $j)) {
    $setSearchCfg('search_custom_url', (string)($j['search_custom_url'] ?? ''));
  }
  if (array_key_exists('search_custom_news_url', $j)) {
    $setSearchCfg('search_custom_news_url', (string)($j['search_custom_news_url'] ?? ''));
  }
  if (array_key_exists('search_custom_allow_private', $j)) {
    $v = (int)($j['search_custom_allow_private'] ?? 0);
    $setSearchCfg('search_custom_allow_private', (string)($v === 0 ? '0' : '1'));
  }
  if (array_key_exists('search_custom_api_key', $j)) {
    $setSearchCfg('search_custom_api_key', (string)($j['search_custom_api_key'] ?? ''));
  }

  // SearchNGX / SearXNG instance
  if (array_key_exists('searchngx_url', $j)) {
    $setSearchCfg('searchngx_url', (string)($j['searchngx_url'] ?? ''));
  }
  if (array_key_exists('searchngx_allow_private', $j)) {
    $v = (int)($j['searchngx_allow_private'] ?? 0);
    $setSearchCfg('searchngx_allow_private', (string)($v === 0 ? '0' : '1'));
  }
  if (array_key_exists('searchngx_api_key', $j)) {
    $setSearchCfg('searchngx_api_key', (string)($j['searchngx_api_key'] ?? ''));
  }

  if (array_key_exists('search_gl', $j)) {
    $setSearchCfg('search_gl', (string)($j['search_gl'] ?? 'de'));
  }
  if (array_key_exists('search_hl', $j)) {
    $setSearchCfg('search_hl', (string)($j['search_hl'] ?? 'de'));
  }
  if (array_key_exists('search_num', $j)) {
    $v = (int)($j['search_num'] ?? 10);
    if ($v < 1) $v = 1;
    if ($v > 20) $v = 20;
    $setSearchCfg('search_num', (string)$v);
  }

  // Image settings
  if (array_key_exists('image_provider', $j)) {
    $v = (string)($j['image_provider'] ?? 'openai');
    if ($v === '') $v = 'openai';
    $setImageCfg('image_provider', $v);
  }
  if (array_key_exists('image_base_url', $j)) {
    $v = (string)($j['image_base_url'] ?? 'https://api.openai.com/v1');
    if (trim($v) === '') $v = 'https://api.openai.com/v1';
    $setImageCfg('image_base_url', $v);
  }
  if (array_key_exists('image_api_key', $j)) {
    $setImageCfg('image_api_key', (string)($j['image_api_key'] ?? ''));
  }
  if (array_key_exists('image_model', $j)) {
    $v = (string)($j['image_model'] ?? 'gpt-image-2');
    if ($v === '') $v = 'gpt-image-2';
    $setImageCfg('image_model', $v);
  }
  if (array_key_exists('image_openrouter_base_url', $j)) {
    $v = (string)($j['image_openrouter_base_url'] ?? 'https://openrouter.ai/api/v1');
    if (trim($v) === '') $v = 'https://openrouter.ai/api/v1';
    $setImageCfg('image_openrouter_base_url', $v);
  }
  if (array_key_exists('image_openrouter_api_key', $j)) {
    $setImageCfg('image_openrouter_api_key', (string)($j['image_openrouter_api_key'] ?? ''));
  }
  if (array_key_exists('image_openrouter_model', $j)) {
    $v = (string)($j['image_openrouter_model'] ?? 'google/gemini-3-pro-image-preview');
    if ($v === '') $v = 'google/gemini-3-pro-image-preview';
    $setImageCfg('image_openrouter_model', $v);
  }
  if (array_key_exists('image_sdcpp_base_url', $j)) {
    $v = llc_sdcpp_normalize_base_url((string)($j['image_sdcpp_base_url'] ?? 'http://127.0.0.1:1234/v1'));
    $setImageCfg('image_sdcpp_base_url', $v);
  }
  if (array_key_exists('image_sdcpp_api_key', $j)) {
    $setImageCfg('image_sdcpp_api_key', (string)($j['image_sdcpp_api_key'] ?? ''));
  }
  if (array_key_exists('image_sdcpp_model', $j)) {
    $v = (string)($j['image_sdcpp_model'] ?? 'flux-2-klein-base-4b-Q8_0.gguf');
    if ($v === '') $v = 'flux-2-klein-base-4b-Q8_0.gguf';
    $setImageCfg('image_sdcpp_model', $v);
  }
  if (array_key_exists('image_sdcpp_negative_prompt', $j)) $setImageCfg('image_sdcpp_negative_prompt', (string)($j['image_sdcpp_negative_prompt'] ?? ''));
  if (array_key_exists('image_sdcpp_width', $j)) { $v=(int)($j['image_sdcpp_width'] ?? 512); if($v<64)$v=64; if($v>4096)$v=4096; $setImageCfg('image_sdcpp_width',(string)$v); }
  if (array_key_exists('image_sdcpp_height', $j)) { $v=(int)($j['image_sdcpp_height'] ?? 512); if($v<64)$v=64; if($v>4096)$v=4096; $setImageCfg('image_sdcpp_height',(string)$v); }
  if (array_key_exists('image_sdcpp_batch', $j)) { $v=(int)($j['image_sdcpp_batch'] ?? 1); if($v<1)$v=1; if($v>16)$v=16; $setImageCfg('image_sdcpp_batch',(string)$v); }
  if (array_key_exists('image_sdcpp_seed', $j)) $setImageCfg('image_sdcpp_seed', (string)((int)($j['image_sdcpp_seed'] ?? -1)));
  if (array_key_exists('image_sdcpp_steps', $j)) { $v=(int)($j['image_sdcpp_steps'] ?? 20); if($v<1)$v=1; if($v>250)$v=250; $setImageCfg('image_sdcpp_steps',(string)$v); }
  if (array_key_exists('image_sdcpp_cfg_scale', $j)) { $v=(float)($j['image_sdcpp_cfg_scale'] ?? 7); if(!is_finite($v))$v=7; $setImageCfg('image_sdcpp_cfg_scale',(string)$v); }
  if (array_key_exists('image_sdcpp_guidance', $j)) { $v=(float)($j['image_sdcpp_guidance'] ?? 3.5); if(!is_finite($v))$v=3.5; $setImageCfg('image_sdcpp_guidance',(string)$v); }
  if (array_key_exists('image_sdcpp_sampling_method', $j)) $setImageCfg('image_sdcpp_sampling_method', (string)($j['image_sdcpp_sampling_method'] ?? ''));
  if (array_key_exists('image_sdcpp_scheduler', $j)) $setImageCfg('image_sdcpp_scheduler', (string)($j['image_sdcpp_scheduler'] ?? ''));
  if (array_key_exists('image_sdcpp_flow_shift', $j)) $setImageCfg('image_sdcpp_flow_shift', (string)($j['image_sdcpp_flow_shift'] ?? ''));
  if (array_key_exists('image_sdcpp_extra_args', $j)) $setImageCfg('image_sdcpp_extra_args', (string)($j['image_sdcpp_extra_args'] ?? ''));
  if (array_key_exists('image_sdcpp_timeout_sec', $j)) { $v=(int)($j['image_sdcpp_timeout_sec'] ?? 900); if($v<30)$v=30; if($v>3600)$v=3600; $setImageCfg('image_sdcpp_timeout_sec',(string)$v); }
  if (array_key_exists('image_sdcpp_auto_vae_tiling_768', $j)) $setImageCfg('image_sdcpp_auto_vae_tiling_768', ((int)($j['image_sdcpp_auto_vae_tiling_768'] ?? 1) !== 0) ? '1' : '0');

  if (array_key_exists('image_auto_enable', $j)) {
    $v = (int)$j['image_auto_enable'];
    llc_set_setting($db, $uid, 'image_auto_enable', (string)($v === 0 ? '0' : '1'));
  }
  if (array_key_exists('vision_auto_attach_last_image', $j)) {
    $v = (int)$j['vision_auto_attach_last_image'];
    llc_set_setting($db, $uid, 'vision_auto_attach_last_image', (string)($v === 0 ? '0' : '1'));
  }
  if (array_key_exists('image_size', $j)) {
    $setImageCfg('image_size', (string)($j['image_size'] ?? 'auto'));
  }
  if (array_key_exists('image_quality', $j)) {
    $setImageCfg('image_quality', (string)($j['image_quality'] ?? 'auto'));
  }
  if (array_key_exists('image_background', $j)) {
    $setImageCfg('image_background', (string)($j['image_background'] ?? 'auto'));
  }
  if (array_key_exists('image_output_format', $j)) {
    $v = (string)($j['image_output_format'] ?? 'png');
    if ($v === '') $v = 'png';
    $setImageCfg('image_output_format', $v);
  }

  // Voice settings
  if (array_key_exists('voice_api_key', $j)) {
    $setVoiceCfg('voice_api_key', (string)($j['voice_api_key'] ?? ''));
  }
  if (array_key_exists('voice_auto_enable', $j)) {
    $v = (int)$j['voice_auto_enable'];
    llc_set_setting($db, $uid, 'voice_auto_enable', (string)($v === 0 ? '0' : '1'));
  }
  if (array_key_exists('voice_auto_send', $j)) {
    $v = (int)$j['voice_auto_send'];
    llc_set_setting($db, $uid, 'voice_auto_send', (string)($v === 0 ? '0' : '1'));
  }

  if (array_key_exists('voice_tts_provider', $j)) {
    $v = trim((string)($j['voice_tts_provider'] ?? 'browser'));
    if ($v === '') $v = 'browser';
    // Allowed: browser | openai
    if ($v !== 'openai') $v = 'browser';
      $setVoiceCfg('voice_tts_provider', $v);
  }
  if (array_key_exists('voice_tts_voice', $j)) {
    $v = trim((string)($j['voice_tts_voice'] ?? 'marin'));
    if ($v === '') $v = 'marin';
        $setVoiceCfg('voice_tts_voice', $v);
  }

  if (array_key_exists('voice_tts_model', $j)) {
    $v = trim((string)($j['voice_tts_model'] ?? 'gpt-4o-mini-tts'));
    if ($v === '') $v = 'gpt-4o-mini-tts';
    // Allow-list TTS models
    $allowedModels = ['gpt-4o-mini-tts'];
    if (!in_array($v, $allowedModels, true)) $v = 'gpt-4o-mini-tts';
        $setVoiceCfg('voice_tts_model', $v);
  }

  // ComfyUI image settings
  if (array_key_exists('image_comfyui_url', $j)) {
    $setImageCfg('image_comfyui_url', (string)($j['image_comfyui_url'] ?? ''));
  }
  if (array_key_exists('image_comfyui_workflow_json', $j)) {
    $setImageCfg('image_comfyui_workflow_json', (string)($j['image_comfyui_workflow_json'] ?? ''));
  }
  if (array_key_exists('image_comfyui_bindings_json', $j)) {
    $setImageCfg('image_comfyui_bindings_json', (string)($j['image_comfyui_bindings_json'] ?? ''));
  }
  if (array_key_exists('image_comfyui_seed', $j)) {
    $v = (int)($j['image_comfyui_seed'] ?? -1);
    $setImageCfg('image_comfyui_seed', (string)$v);
  }
  if (array_key_exists('image_comfyui_steps', $j)) {
    $v = (int)($j['image_comfyui_steps'] ?? 20);
    if ($v < 1) $v = 1;
    if ($v > 250) $v = 250;
    $setImageCfg('image_comfyui_steps', (string)$v);
  }
  if (array_key_exists('image_comfyui_guidance', $j)) {
    $v = (float)($j['image_comfyui_guidance'] ?? 3.5);
    if (!is_finite($v)) $v = 3.5;
    $setImageCfg('image_comfyui_guidance', (string)$v);
  }
  if (array_key_exists('image_comfyui_width', $j)) {
    $v = (int)($j['image_comfyui_width'] ?? 512);
    if ($v < 64) $v = 64;
    if ($v > 4096) $v = 4096;
    $setImageCfg('image_comfyui_width', (string)$v);
  }
  if (array_key_exists('image_comfyui_height', $j)) {
    $v = (int)($j['image_comfyui_height'] ?? 512);
    if ($v < 64) $v = 64;
    if ($v > 4096) $v = 4096;
    $setImageCfg('image_comfyui_height', (string)$v);
  }
  if (array_key_exists('image_comfyui_batch', $j)) {
    $v = (int)($j['image_comfyui_batch'] ?? 1);
    if ($v < 1) $v = 1;
    if ($v > 16) $v = 16;
    $setImageCfg('image_comfyui_batch', (string)$v);
  }

  if (array_key_exists('image_comfyui_apply_defaults', $j)) {
    $v = (int)($j['image_comfyui_apply_defaults'] ?? 0);
    $setImageCfg('image_comfyui_apply_defaults', (string)($v === 0 ? '0' : '1'));
  }

  if (array_key_exists('image_comfyui_timeout_sec', $j)) {
    $v = (int)($j['image_comfyui_timeout_sec'] ?? 900);
    if ($v < 30) $v = 30;
    if ($v > 3600) $v = 3600;
    $setImageCfg('image_comfyui_timeout_sec', (string)$v);
  }

  // Pricing rules (stored per user; not inherited)
  if (array_key_exists('pricing', $j)) {
    $rules = $j['pricing'];
    if (!is_array($rules)) $rules = [];
    $out = [];
    foreach ($rules as $r) {
      if (!is_array($r)) continue;
      $cid = trim((string)($r['connection_id'] ?? ''));
      $model = trim((string)($r['model'] ?? ''));
      if ($cid === '' || $model === '') continue;
      // Only allow pricing for accessible connections (prevents leaking global conn ids to non-owners)
      if (!llc_conn_accessible($db, $u, $cid)) continue;
      $pp = $r['prompt_price'] ?? '';
      $gp = $r['gen_price'] ?? '';
      $pp_out = '';
      $gp_out = '';
      if ($pp !== '' && $pp !== null) {
        $pp_f = (float)$pp;
        if ($pp_f >= 0) $pp_out = $pp_f;
      }
      if ($gp !== '' && $gp !== null) {
        $gp_f = (float)$gp;
        if ($gp_f >= 0) $gp_out = $gp_f;
      }
      $out[] = [
        'connection_id' => $cid,
        'model' => $model,
        'prompt_price' => $pp_out,
        'gen_price' => $gp_out
      ];
    }
    llc_set_setting($db, $uid, 'pricing_json', json_encode($out));
  }



  llc_json(['ok'=>true]);
}


// ---------- models (merge /models from all enabled connections) ----------
function llc_models(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  if (function_exists('llc_ensure_default_settings')) llc_ensure_default_settings($db, $uid);

  $payload = llc_collect_models($db, $u);

  // Cache models for fast bootstrap (avoid blocking UI when a provider is offline).
  llc_set_setting($db, $uid, 'models_cache_json', json_encode($payload['models'], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
  llc_set_setting($db, $uid, 'models_cache_at', (string)time());

  llc_json(['models'=>$payload['models'], 'errors'=>$payload['errors']]);
}


function llc_collect_models(PDO $db, array $u): array {
  $uid = (string)($u['id'] ?? '');
  // Internal call: we must keep global connection secrets available so the server
  // can query remote /models even for inherited users.
  $cons0 = llc_connections_for_user($db, $u, true, true);
  // Dedup connections defensively (superadmins can otherwise see the same row twice).
  $cons = [];
  $seenC = [];
  foreach ($cons0 as $c) {
    $cid = (string)($c['id'] ?? '');
    if ($cid === '' || isset($seenC[$cid])) continue;
    $seenC[$cid] = true;
    $cons[] = $c;
  }
  $models = [];
  $errors = [];

  $reqs = [];
  foreach ($cons as $c) {
    if ((int)($c['enabled'] ?? 1) !== 1) continue;
    $cid = (string)($c['id'] ?? '');
    if ($cid === '') continue;
    $label = trim((string)($c['label'] ?? ''));
    if ($label === '') $label = $cid;
    $base = llc_norm_base((string)($c['base_url'] ?? ''));
    if ($base === '') continue;

    // In some environments, the connection list may be returned without secrets
    // even for internal callers. Resolve the full row (with secrets) defensively.
    $key0 = trim((string)($c['api_key'] ?? ''));
    $hdr0 = trim((string)($c['headers'] ?? ''));
    if ($key0 === '' && $hdr0 === '') {
      $full = llc_conn_resolve($db, $u, $cid);
      if (is_array($full)) $c = $full;
    }

    $url = $base . '/models';
    $hdrs = ['Accept: application/json'];
    $key = (string)($c['api_key'] ?? '');
    if (trim($key) !== '') $hdrs[] = 'Authorization: Bearer ' . $key;
    if (!empty($c['headers'])) $hdrs = array_merge($hdrs, llc_custom_headers((string)$c['headers']));

    $ch = curl_init($url);
    curl_setopt_array($ch, [
      CURLOPT_HTTPGET => true,
      CURLOPT_HTTPHEADER => $hdrs,
      CURLOPT_RETURNTRANSFER => true,
      CURLOPT_CONNECTTIMEOUT => 2,
      CURLOPT_TIMEOUT => 5,
    ]);

    $reqs[] = [
      'cid' => $cid,
      'label' => $label,
      'prefix' => trim((string)($c['prefix'] ?? '')),
      'ch' => $ch
    ];
  }

  // Query all enabled connections concurrently; overall wall-clock stays low even if one is offline.
  if (!empty($reqs)) {
    $mh = curl_multi_init();
    foreach ($reqs as $r) curl_multi_add_handle($mh, $r['ch']);

    $start = microtime(true);
    $active = null;
    $mrc = CURLM_OK;

    // Allow more time for multiple endpoints without stalling the UI forever.
    // (Still bounded; individual handles already have CURLOPT_TIMEOUT.)
    $maxWall = 9.5;

    // Prime.
    do {
      $mrc = curl_multi_exec($mh, $active);
    } while ($mrc === CURLM_CALL_MULTI_PERFORM);

    while ($active && $mrc === CURLM_OK) {
      if ((microtime(true) - $start) >= $maxWall) break;

      $rc = curl_multi_select($mh, 0.5);
      // curl_multi_select may return -1 spuriously; avoid a tight loop.
      if ($rc === -1) usleep(100000);

      do {
        $mrc = curl_multi_exec($mh, $active);
      } while ($mrc === CURLM_CALL_MULTI_PERFORM);
    }

    foreach ($reqs as $r) {
      $ch = $r['ch'];
      $resp = curl_multi_getcontent($ch);
      $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
      $err  = curl_error($ch);
      $errno = curl_errno($ch);

      curl_multi_remove_handle($mh, $ch);
      curl_close($ch);

      if (!is_string($resp) || $code < 200 || $code >= 300) {
        $msg = $err ?: (($errno === CURLE_OPERATION_TIMEDOUT) ? 'Timeout' : ('HTTP ' . $code));
        $errors[] = ['connection_id'=>$r['cid'],'label'=>$r['label'],'error'=>$msg];
        continue;
      }

      $j = json_decode($resp, true);
      if (!is_array($j) || !isset($j['data']) || !is_array($j['data'])) {
        $errors[] = ['connection_id'=>$r['cid'],'label'=>$r['label'],'error'=>'Invalid /models response'];
        continue;
      }

      foreach ($j['data'] as $it) {
        if (!is_array($it) || !isset($it['id'])) continue;
        $mid = (string)$it['id'];
        if ($mid === '') continue;
        $display = ($r['prefix'] !== '') ? ($r['prefix'] . '.' . $mid) : $mid;
        $models[] = [
          'key' => $r['cid'] . '::' . $mid,
          'id' => $mid,
          'label' => $display,
          'connection_id' => $r['cid'],
          'connection_label' => $r['label'],
          'connection_prefix' => $r['prefix'],
        ];
      }
    }

    curl_multi_close($mh);
  }

  // Stable sort: group by connection label then model id
  usort($models, function($a,$b){
    $ca = (string)($a['connection_label'] ?? '');
    $cb = (string)($b['connection_label'] ?? '');
    if ($ca !== $cb) return strcasecmp($ca,$cb);
    return strcasecmp((string)$a['id'], (string)$b['id']);
  });

  // Dedup exact keys only
  $seen=[]; $out=[];
  foreach ($models as $m){
    $k=(string)($m['key']??'');
    if ($k==='' || isset($seen[$k])) continue;
    $seen[$k]=true; $out[]=$m;
  }

  return ['models'=>$out,'errors'=>$errors];
}


// ---------- chats ----------
function llc_chat_create(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $folder_id = $j['folder_id'] ?? null;
  if ($folder_id === '') $folder_id = null;

  if ($folder_id !== null) {
    $stF = $db->prepare("SELECT 1 FROM folders WHERE id=? AND user_id=?");
    $stF->execute([(string)$folder_id, $uid]);
    if (!$stF->fetchColumn()) throw new RuntimeException('Folder not found');
  }

  $id = llc_id('chat_');
  $now = llc_now();
  $model = llc_get_setting($db, $uid, 'selected_model') ?? '';
  $conn  = llc_get_setting($db, $uid, 'selected_connection_id') ?? '';

  $sys = llc_get_setting($db, $uid, 'system_prompt') ?? '';
  $meta = ['system_prompt'=>$sys,'params'=>[]];

  $st = $db->prepare("INSERT INTO chats (id,user_id,title,preview,folder_id,connection_id,model,messages_json,meta_json,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)");
  $st->execute([$id,$uid,'New chat','',$folder_id,($conn!==''?$conn:null),$model,'[]',json_encode($meta, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),$now,$now]);

  llc_json(['id'=>$id]);
}


function llc_chat_get(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');

  $st = $db->prepare("SELECT * FROM chats WHERE id=? AND user_id=?");
  $st->execute([$id, $uid]);
  $row = $st->fetch();
  if (!$row) llc_json(['error'=>'Chat not found'], 404);

  llc_json(['chat'=>[
    'id'=>$row['id'],
    'title'=>$row['title'],
    'preview'=>$row['preview'],
    'folder_id'=>$row['folder_id'],
    'connection_id'=>$row['connection_id'] ?? '',
    'model'=>$row['model'],
    'messages'=>json_decode($row['messages_json'], true) ?: [],
    'meta'=>json_decode($row['meta_json'], true) ?: [],
    'created_at'=>(int)$row['created_at'],
    'updated_at'=>(int)$row['updated_at'],
  ]]);
}


function llc_chat_save(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');

  $title = (string)($j['title'] ?? 'New chat');
  $preview = (string)($j['preview'] ?? '');
  $folder_id = $j['folder_id'] ?? null;
  if ($folder_id === '') $folder_id = null;
  $model = (string)($j['model'] ?? '');
  $connection_id = (string)($j['connection_id'] ?? '');
  if ($connection_id === '') $connection_id = null;
  if ($connection_id !== null) {
    if (!llc_conn_accessible($db, $u, (string)$connection_id)) $connection_id = null;
  }
  $messages = $j['messages'] ?? [];
  $meta = $j['meta'] ?? [];

  if (!is_array($messages)) throw new RuntimeException('messages must be array');
  if (!is_array($meta)) $meta = [];

  // Validate ownership
  $st0 = $db->prepare("SELECT 1 FROM chats WHERE id=? AND user_id=?");
  $st0->execute([$id, $uid]);
  if (!$st0->fetchColumn()) llc_json(['error'=>'Chat not found'], 404);

  if ($folder_id !== null) {
    $stF = $db->prepare("SELECT 1 FROM folders WHERE id=? AND user_id=?");
    $stF->execute([(string)$folder_id, $uid]);
    if (!$stF->fetchColumn()) throw new RuntimeException('Folder not found');
  }

  if ($connection_id !== null) {
    if (!llc_conn_accessible($db, $u, (string)$connection_id)) throw new RuntimeException('Connection not found');
  }

  $st = $db->prepare("UPDATE chats SET title=?, preview=?, folder_id=?, connection_id=?, model=?, messages_json=?, meta_json=?, updated_at=? WHERE id=? AND user_id=?");
  $st->execute([
    $title, $preview, $folder_id, $connection_id, $model,
    json_encode($messages, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    json_encode($meta, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    llc_now(), $id, $uid
  ]);
  llc_json(['ok'=>true]);
}


function llc_chat_delete(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');

  $st = $db->prepare("DELETE FROM chats WHERE id=? AND user_id=?");
  $st->execute([$id, $uid]);
  llc_json(['ok'=>true]);
}


function llc_chat_rename(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');
  $title = trim((string)llc_require($j,'title'));

  $st = $db->prepare("UPDATE chats SET title=?, updated_at=? WHERE id=? AND user_id=?");
  $st->execute([$title, llc_now(), $id, $uid]);
  llc_json(['ok'=>true]);
}



function llc_chat_auto_rename(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');

  $st = $db->prepare("SELECT * FROM chats WHERE id=? AND user_id=?");
  $st->execute([$id, $uid]);
  $row = $st->fetch();
  if (!$row) llc_json(['error'=>'Chat not found'], 404);

  // Optional overrides (useful for older chats that may have lost connection_id/model
  // due to a previous connection-accessibility bug).
  $reqConnId = trim((string)($j['connection_id'] ?? ''));
  if ($reqConnId !== '' && !llc_conn_accessible($db, $u, $reqConnId)) $reqConnId = '';
  $reqModel = trim((string)($j['model'] ?? ''));

  $msgs = json_decode((string)($row['messages_json'] ?? '[]'), true);
  if (!is_array($msgs)) $msgs = [];

  // Find first user message and the first assistant reply after it
  $firstUserIdx = null;
  for ($i=0; $i<count($msgs); $i++){
    $m = $msgs[$i];
    if (is_array($m) && (string)($m['role'] ?? '') === 'user') { $firstUserIdx = $i; break; }
  }
  if ($firstUserIdx === null) $firstUserIdx = 0;

  $firstAsstIdx = null;
  for ($i=$firstUserIdx+1; $i<count($msgs); $i++){
    $m = $msgs[$i];
    if (is_array($m) && (string)($m['role'] ?? '') === 'assistant') { $firstAsstIdx = $i; break; }
  }

  $msgToText = function($m): string {
    if (!is_array($m)) return '';
    $content = $m['content'] ?? '';
    if (is_string($content)) $txt = $content;
    elseif (is_null($content)) $txt = '';
    else $txt = json_encode($content, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);

    $atts = $m['attachments'] ?? [];
    if (is_array($atts) && count($atts) > 0) {
      $lines = [];
      foreach ($atts as $a) {
        if (!is_array($a)) continue;
        $type = (string)($a['type'] ?? 'file');
        $name = (string)($a['name'] ?? '');
        $mime = (string)($a['mime'] ?? '');
        $line = "[attachment: " . $type;
        if ($name !== '') $line .= " name=" . $name;
        if ($mime !== '') $line .= " mime=" . $mime;
        $line .= "]";
        $lines[] = $line;

        $t = $a['text'] ?? '';
        if (is_string($t) && trim($t) !== '') $lines[] = trim($t);
      }
      if (count($lines) > 0) $txt = rtrim((string)$txt) . "\n\n" . implode("\n", $lines);
    }
    return (string)$txt;
  };

  $u0 = $msgToText($msgs[$firstUserIdx] ?? []);
  $a0 = $firstAsstIdx !== null ? $msgToText($msgs[$firstAsstIdx] ?? []) : '';

  $truncate = function(string $s, int $maxChars): string {
    $s = (string)$s;
    if ($maxChars <= 0) $maxChars = 6000;
    if (function_exists('mb_strlen') && function_exists('mb_substr')) {
      if (mb_strlen($s, 'UTF-8') > $maxChars) $s = mb_substr($s, 0, $maxChars, 'UTF-8');
    } else {
      if (strlen($s) > $maxChars) $s = substr($s, 0, $maxChars);
    }
    return $s;
  };

  $u0 = $truncate($u0, 6000);
  $a0 = $truncate($a0, 6000);

  // Choose connection/model (prefer explicit request override, then chat settings, then user settings)
  $model = $reqModel !== '' ? $reqModel : (string)($row['model'] ?? (llc_get_setting($db, $uid, 'selected_model') ?? ''));
  if ($model === '') $model = 'gpt-4o-mini';

  $connId = $reqConnId !== '' ? $reqConnId : (string)($row['connection_id'] ?? (llc_get_setting($db, $uid, 'selected_connection_id') ?? ''));
  if (trim((string)$connId) === '' && $model !== '') {
    $inf = llc_infer_conn_id_for_model($db, $u, $uid, $model);
    if ($inf !== '') $connId = $inf;
  }
  $conn = ($connId ? llc_conn_by_id($db, $u, (string)$connId) : null);
  if (!$conn && $model !== '') {
    $inf = llc_infer_conn_id_for_model($db, $u, $uid, $model);
    if ($inf !== '' && $inf !== (string)$connId) {
      $connId = $inf;
      $conn = llc_conn_by_id($db, $u, $connId);
    }
  }
  if (!$conn) llc_json(['error'=>'No active connection. Add one in Settings → Connections.'], 400);

  $model = llc_strip_model_prefix($model, $conn);

  $sys = "You generate short chat titles for a sidebar.\n"
       . "Using ONLY the provided first user message and the first assistant reply, output exactly ONE line:\n"
       . "<emoji> <five words>\n\n"
       . "Rules:\n"
       . "- Start with a single emoji, then a space.\n"
       . "- Exactly 5 words after the emoji (5 tokens separated by single spaces).\n"
       . "- Same language as the user.\n"
       . "- Be specific (use real topic words), not generic.\n"
       . "- No quotes, no leading/trailing punctuation, no newline.\n";

  $user = "FIRST USER MESSAGE (first 6000 chars):\n" . $u0 . "\n\n"
        . "FIRST ASSISTANT MESSAGE (first 6000 chars):\n" . $a0 . "\n";

  $base = rtrim(trim((string)($conn['base_url'] ?? '')), '/');
  $url = $base . '/chat/completions';

  $hdrs = ['Content-Type: application/json', 'Accept: application/json'];
  $key = (string)($conn['api_key'] ?? '');
  if (trim($key) !== '') $hdrs[] = 'Authorization: Bearer ' . $key;
  if (!empty($conn['headers'])) $hdrs = array_merge($hdrs, llc_custom_headers((string)$conn['headers']));

  $payload = [
    'model' => $model,
    'messages' => [
      ['role'=>'system','content'=>$sys],
      ['role'=>'user','content'=>$user],
    ],
  ];

  $resp = llc_http_post_json($url, $hdrs, $payload, 0, 20);
  $title = (string)($resp['choices'][0]['message']['content'] ?? '');
  $title = trim($title);
  $title = preg_replace('/\s+/', ' ', (string)$title);
  $title = trim((string)$title, " \t\n\r\0\x0B\"'");

  if ($title === '') throw new RuntimeException('Auto rename produced empty title');

  // Normalize to "<emoji> <five words>"
  $parts = preg_split('/\s+/', $title);
  if (!$parts || !is_array($parts)) $parts = [];
  if (count($parts) >= 6) {
    $emoji = $parts[0];
    $words = array_slice($parts, 1, 5);
    $title = $emoji . ' ' . implode(' ', $words);
  } elseif (count($parts) === 5) {
    $title = "💬 " . implode(' ', $parts);
  }

  $st2 = $db->prepare("UPDATE chats SET title=?, updated_at=? WHERE id=? AND user_id=?");
  $st2->execute([$title, llc_now(), $id, $uid]);

  llc_json(['ok'=>true, 'title'=>$title]);
}


function llc_chat_move(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');
  $folder_id = $j['folder_id'] ?? null;
  if ($folder_id === '') $folder_id = null;

  if ($folder_id !== null) {
    $stF = $db->prepare("SELECT 1 FROM folders WHERE id=? AND user_id=?");
    $stF->execute([(string)$folder_id, $uid]);
    if (!$stF->fetchColumn()) throw new RuntimeException('Folder not found');
  }

  $st = $db->prepare("UPDATE chats SET folder_id=?, updated_at=? WHERE id=? AND user_id=?");
  $st->execute([$folder_id, llc_now(), $id, $uid]);
  llc_json(['ok'=>true]);
}


function llc_chat_clone(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');
  $attached = !empty($j['attached']);

  $st = $db->prepare("SELECT * FROM chats WHERE id=? AND user_id=?");
  $st->execute([$id, $uid]);
  $row = $st->fetch();
  if (!$row) llc_json(['error'=>'Chat not found'], 404);

  $newId = llc_id('chat_');
  $now = llc_now();
  $meta = json_decode((string)($row['meta_json'] ?? '{}'), true);
  if (!is_array($meta)) $meta = [];
  if ($attached) {
    $srcClone = $meta['clone'] ?? [];
    if (!is_array($srcClone)) $srcClone = [];
    $rootId = trim((string)($srcClone['root_id'] ?? ''));
    if ($rootId === '') $rootId = !empty($srcClone['attached']) && !empty($srcClone['parent_id']) ? (string)$srcClone['parent_id'] : $id;
    $meta['clone'] = [
      'attached' => true,
      'parent_id' => $id,
      'root_id' => $rootId,
      'created_at' => $now
    ];
  }
  $metaJson = json_encode($meta, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);

  $st2 = $db->prepare("INSERT INTO chats (id,user_id,title,preview,folder_id,connection_id,model,messages_json,meta_json,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)");
  $st2->execute([
    $newId,
    $uid,
    $row['title'].($attached ? ' (Variant)' : ' (Copy)'),
    $row['preview'],
    $row['folder_id'],
    $row['connection_id'],
    $row['model'],
    $row['messages_json'],
    $metaJson,
    $now,
    $now
  ]);
  llc_json(['id'=>$newId, 'attached'=>$attached]);
}


function llc_chat_detach(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j, 'id');

  $st = $db->prepare("SELECT meta_json FROM chats WHERE id=? AND user_id=?");
  $st->execute([$id, $uid]);
  $row = $st->fetch();
  if (!$row) llc_json(['error'=>'Chat not found'], 404);

  $meta = json_decode((string)($row['meta_json'] ?? '{}'), true);
  if (!is_array($meta)) $meta = [];

  if (isset($meta['clone'])) {
    unset($meta['clone']);
  }

  $st2 = $db->prepare("UPDATE chats SET meta_json=?, updated_at=? WHERE id=? AND user_id=?");
  $st2->execute([
    json_encode($meta, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    llc_now(),
    $id,
    $uid
  ]);

  llc_json(['ok'=>true, 'detached'=>true]);
}


function llc_chat_compress_clone(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j, 'id');
  $keep = (int)($j['keep'] ?? 0);
  if ($keep < 0) $keep = 0;

  // Optional overrides (useful for older chats that may have lost connection_id/model).
  $reqConnId = trim((string)($j['connection_id'] ?? ''));
  if ($reqConnId !== '' && !llc_conn_accessible($db, $u, $reqConnId)) $reqConnId = '';
  $reqModel = trim((string)($j['model'] ?? ''));

  $includeFirst = (int)($j['include_first'] ?? 1);
  $includeFirst = ($includeFirst !== 0);

// STORY SO FAR length (option 1–4)
$storyOpt = (int)($j['story_words'] ?? ($j['story_words_option'] ?? ($j['story_length'] ?? 1)));
if ($storyOpt < 1 || $storyOpt > 4) $storyOpt = 1;
$storyLabel = '~300 words';
$storyAbout = '{$storyAbout}';
$storyFinal = '~300 words (250–350), prose only (no bullets), human-readable, and add no new facts.';
if ($storyOpt === 2) { $storyLabel = '500–1000 words'; $storyAbout = 'Between 500 and 1000 words (aim ~750).'; $storyFinal = '500–1000 words, prose only (no bullets), human-readable, and add no new facts.'; }
if ($storyOpt === 3) { $storyLabel = '1000–2000 words'; $storyAbout = 'Between 1000 and 2000 words (aim ~1500).'; $storyFinal = '1000–2000 words, prose only (no bullets), human-readable, and add no new facts.'; }
if ($storyOpt === 4) { $storyLabel = '2000–3500 words'; $storyAbout = 'Between 2000 and 3500 words (aim ~2500–3000).'; $storyFinal = '2000–3500 words, prose only (no bullets), human-readable, and add no new facts.'; }


  $st = $db->prepare("SELECT * FROM chats WHERE id=? AND user_id=?");
  $st->execute([$id, $uid]);
  $row = $st->fetch();
  if (!$row) llc_json(['error'=>'Chat not found'], 404);

  $msgs = json_decode((string)($row['messages_json'] ?? '[]'), true);
  if (!is_array($msgs)) $msgs = [];
  $total = count($msgs);

  // Always carry over the FIRST user message (the initial prompt) and clearly mark it.
  // This helps when the story/case/problem statement was defined at the very beginning.
  $firstIdx = null;
  for ($i=0; $i<$total; $i++) {
    $m = $msgs[$i];
    if (is_array($m) && (string)($m['role'] ?? '') === 'user') { $firstIdx = $i; break; }
  }
  if ($firstIdx === null && $total > 0) $firstIdx = 0;
  // Mark the first user message we carry over (always in English for consistency)
  $startLabel = "=== START OF ORIGINAL CHAT (first user message) ===\n";

  // Build a marked "first user message" block (as plain text) to prepend ABOVE the continuation memory.
  // This prevents the model from mistaking the initial prompt as the most recent instruction.
  $firstBlock = '';
  if ($firstIdx !== null && $firstIdx >= 0 && $firstIdx < $total && isset($msgs[$firstIdx]) && is_array($msgs[$firstIdx])) {
    $m0 = $msgs[$firstIdx];
    $content0 = $m0['content'] ?? '';
    if (is_string($content0)) {
      $txt0 = $content0;
    } elseif (is_null($content0)) {
      $txt0 = '';
    } elseif (is_array($content0)) {
      $txt0 = json_encode($content0, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
    } else {
      $txt0 = json_encode($content0, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
    }

    $atts0 = $m0['attachments'] ?? [];
    if (is_array($atts0) && count($atts0) > 0) {
      $lines0 = [];
      foreach ($atts0 as $a0) {
        if (!is_array($a0)) continue;
        $type0 = (string)($a0['type'] ?? 'file');
        $name0 = (string)($a0['name'] ?? '');
        $url0  = (string)($a0['url'] ?? '');
        $mime0 = (string)($a0['mime'] ?? '');

        $line0 = "[attachment: " . $type0;
        if ($name0 !== '') $line0 .= " name=" . $name0;
        if ($mime0 !== '') $line0 .= " mime=" . $mime0;
        if ($url0  !== '') $line0 .= " url=" . $url0;
        $line0 .= "]";
        $lines0[] = $line0;

        $t0 = $a0['text'] ?? '';
        if (is_string($t0) && trim($t0) !== '') {
          $lines0[] = trim($t0);
        }
      }
      if (count($lines0) > 0) {
        $txt0 = rtrim((string)$txt0) . "\n\n" . implode("\n", $lines0);
      }
    }

    $firstBlock = rtrim($startLabel) . "\n" . rtrim((string)$txt0);
  }

  if (!$includeFirst) {
    $firstBlock = '';
  }

  // Tail messages to keep verbatim (exactly the last N messages, unchanged)
  $tail = [];
  $tailStart = 0;
  if ($keep > 0 && $total > 0) {
    $tailStart = max(0, $total - $keep);
    $tail = array_slice($msgs, $tailStart);
  }

  // Avoid duplicating the first user message in the tail (short chats)
  if ($includeFirst && $firstIdx !== null && $keep > 0 && $firstIdx >= $tailStart) {
    $idxInTail = $firstIdx - $tailStart;
    if (isset($tail[$idxInTail])) {
      unset($tail[$idxInTail]);
      $tail = array_values($tail);
    }
  }

  // Choose connection/model (prefer explicit request override, then chat settings, then user settings)
  $model = $reqModel !== '' ? $reqModel : (string)($row['model'] ?? (llc_get_setting($db, $uid, 'selected_model') ?? ''));
  if ($model === '') $model = 'gpt-4o-mini';

  $connId = $reqConnId !== '' ? $reqConnId : (string)($row['connection_id'] ?? (llc_get_setting($db, $uid, 'selected_connection_id') ?? ''));
  if (trim((string)$connId) === '' && $model !== '') {
    $inf = llc_infer_conn_id_for_model($db, $u, $uid, $model);
    if ($inf !== '') $connId = $inf;
  }
  $conn = ($connId ? llc_conn_by_id($db, $u, (string)$connId) : null);
  if (!$conn && $model !== '') {
    $inf = llc_infer_conn_id_for_model($db, $u, $uid, $model);
    if ($inf !== '' && $inf !== (string)$connId) {
      $connId = $inf;
      $conn = llc_conn_by_id($db, $u, $connId);
    }
  }
  if (!$conn) llc_json(['error'=>'No active connection. Add one in Settings → Connections.'], 400);

  $model = llc_strip_model_prefix($model, $conn);

  // Build FULL transcript (no truncation). Include attachments and any extracted text verbatim.
  $parts = [];
  foreach ($msgs as $m) {
    if (!is_array($m)) continue;

    $role = (string)($m['role'] ?? '');
    $label = ($role === 'assistant') ? 'Assistant' : (($role === 'system') ? 'System' : 'User');

    $content = $m['content'] ?? '';
    if (is_string($content)) {
      $txt = $content;
    } elseif (is_null($content)) {
      $txt = '';
    } elseif (is_array($content)) {
      $txt = json_encode($content, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
    } else {
      $txt = json_encode($content, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
    }

    $atts = $m['attachments'] ?? [];
    if (is_array($atts) && count($atts) > 0) {
      $lines = [];
      foreach ($atts as $a) {
        if (!is_array($a)) continue;
        $type = (string)($a['type'] ?? 'file');
        $name = (string)($a['name'] ?? '');
        $url  = (string)($a['url'] ?? '');
        $mime = (string)($a['mime'] ?? '');

        $line = "[attachment: " . $type;
        if ($name !== '') $line .= " name=" . $name;
        if ($mime !== '') $line .= " mime=" . $mime;
        if ($url  !== '') $line .= " url=" . $url;
        $line .= "]";
        $lines[] = $line;

        // Include extracted text verbatim if present
        $t = $a['text'] ?? '';
        if (is_string($t) && trim($t) !== '') {
          $lines[] = trim($t);
        }
      }
      if (count($lines) > 0) {
        $txt = rtrim($txt) . "\n\n" . implode("\n", $lines);
      }
    }

    $parts[] = $label . ":\n" . rtrim((string)$txt);
  }
  $transcript = implode("\n\n---\n\n", $parts);

  $sys = "You are a conversation compressor for a chat UI.\n\n"
       . "TASK\n"
       . "Given the full conversation transcript, produce a single compact \"Continuation Memory\" block that will be inserted as the FIRST USER MESSAGE of a NEW CLONED CHAT.\n"
       . "This memory must allow a fresh assistant instance to continue seamlessly, as if it had participated in the original chat.\n\n"
       . "LANGUAGE (CRITICAL)\n"
       . "- Write the ENTIRE output in the SAME language as the original conversation.\n"
       . "- If the conversation is mixed, use the language used by the user most recently.\n"
       . "- Translate headings and the continuation banner too.\n\n"
       . "CRITICAL REQUIREMENTS\n"
       . "1) This is NOT a generic summary. It is operational memory for continuation.\n"
       . "2) Goals can evolve: capture the CURRENT goal, and record past goals only if still relevant.\n"
       . "3) Preserve hard facts, decisions, constraints. Do not invent. If uncertain: mark as uncertain.\n"
       . "4) Be compact and information-dense (bullets preferred). No fluff.\n"
       . "5) Make explicit that this is a continuation of a previous chat (cloned continuation).\n\n"
       . "OUTPUT FORMAT (follow exactly, but translated into the correct language)\n"
       . "=== CONTINUATION MEMORY (CLONED CHAT) ===\n"
       . "Origin: continuation of earlier chat (cloned). Treat this as prior context and continue from here naturally. Continue in original language.\n\n"
       . "0) USED LANGUAGE(s) \n"
	   . "- bullets.\n\n"
	   . "1) CURRENT GOAL (latest)\n"
       . "- 1–2 sentences.\n\n"
       . "2) CONTEXT & GOAL EVOLUTION (only if relevant)\n"
       . "- bullets.\n\n"
       . "3) HARD FACTS & DECISIONS\n"
       . "- bullets.\n\n"
       . "4) CONSTRAINTS & PREFERENCES\n"
       . "- bullets.\n\n"
       . "5) OPEN QUESTIONS / TODO\n"
       . "- bullets.\n\n"
       . "6) ARTIFACTS / LINKS / FILES\n"
       . "- bullets.\n\n"
       . "7) DO NOT FORGET\n"
       . "- bullets.\n\n"
       . "8) STORY SO FAR (narrative recap, {$storyLabel})\n"
       . "- {$storyAbout} Flowing prose (NO bullets), like a human retelling. 1–3 short paragraphs.\n"
       . "- Chronological: what happened, key decisions/constraints/potential shifts, where things stand now.\n"
       . "- Strictly grounded in the transcript. Do NOT invent; if uncertain: mark as uncertain.\n\n"
       . "COMPRESSION RULES\n"
       . "- Prefer: user constraints, decisions already made, current plan, unresolved questions.\n"
       . "- Drop: small talk, repetition, acknowledgements.\n"
       . "- Preserve contradictions and note them.\n\n"
       . "FINAL CHECK\n"
       . "- CURRENT GOAL must reflect the latest state.\n"
       . "- OPEN QUESTIONS / TODO must be actionable.\n"
       . "- No invented details.\n"
       . "- STORY SO FAR: {$storyFinal}\n";

  $user = "TRANSCRIPT (chronological, complete):\n\n" . $transcript;

  $base = rtrim(trim((string)($conn['base_url'] ?? '')), '/');
  $url = $base . '/chat/completions';

  $hdrs = ['Content-Type: application/json', 'Accept: application/json'];
  $key = (string)($conn['api_key'] ?? '');
  if (trim($key) !== '') $hdrs[] = 'Authorization: Bearer ' . $key;
  if (!empty($conn['headers'])) $hdrs = array_merge($hdrs, llc_custom_headers((string)$conn['headers']));

  // IMPORTANT: keep the payload minimal for OpenAI-compatible endpoints that reject extra params.
  $payload = [
    'model' => $model,
    'messages' => [
      ['role'=>'system','content'=>$sys],
      ['role'=>'user','content'=>$user],
    ],
  ];

  // No hard timeout: large chats can take a long time.
  $resp = llc_http_post_json($url, $hdrs, $payload, 0, 20);
  $memory = (string)($resp['choices'][0]['message']['content'] ?? '');
  $memory = trim($memory);
  if ($memory === '') throw new RuntimeException('Compression produced empty result');

  $now = llc_now();
  $newId = llc_id('chat_');

  // Build new messages:
  // FIRST USER MESSAGE = [marked first user message] + [continuation memory]
  // Then kept tail (verbatim), then a placeholder assistant message.
  $combined = ($firstBlock !== '') ? (rtrim($firstBlock) . "\n\n" . $memory) : $memory;

  $newMsgs = [];
  $newMsgs[] = [
    'role' => 'user',
    'content' => $combined,
    'created_at' => $now,
  ];

  // The kept tail is context-only. Don't carry over usage/cost counters.
  $stripUsageFromMsg = function($m) {
    if (!is_array($m)) return $m;
    if ((string)($m['role'] ?? '') === 'assistant') {
      // Metrics contain token counts + price and would make the NEW compact chat
      // inherit counters from the original.
      if (array_key_exists('metrics', $m)) unset($m['metrics']);
    }
    return $m;
  };

  foreach ($tail as $m) {
    if (is_array($m)) $newMsgs[] = $stripUsageFromMsg($m);
  }
  $newMsgs[] = [
    'role' => 'assistant',
    'content' => 'press regenerate icon to continue discussion',
    'created_at' => $now,
    'model' => $model,
  ];

  $title = (string)($row['title'] ?? 'New chat');
  $suffix = ($keep > 0) ? (' (Compact+' . $keep . ')') : ' (Compact)';
  $newTitle = $title . $suffix;

  $preview = preg_replace('/\s+/', ' ', $memory);
  $preview = trim((string)$preview);

  $meta = json_decode((string)($row['meta_json'] ?? '{}'), true);
  if (!is_array($meta)) $meta = [];

  // Reset usage counters for the NEW chat (compact+clone only).
  foreach (['billed','last_prompt_tok','last_completion_tok','last_total_tok','last_elapsed_s','last_tps','total_gen_tok'] as $k) {
    if (array_key_exists($k, $meta)) unset($meta[$k]);
  }
  // Frontend hint: show zeroed usage until the first new generation in this chat.
  $meta['usage_reset'] = 1;
  $meta['compressed_from_chat_id'] = $id;
  $meta['compressed_at'] = $now;
  $meta['compression_keep_last'] = $keep;
  $meta['compression_include_first'] = $includeFirst ? 1 : 0;
  $meta['compression_kind'] = 'compress_clone';

  $st2 = $db->prepare("INSERT INTO chats (id,user_id,title,preview,folder_id,connection_id,model,messages_json,meta_json,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)");
  $st2->execute([
    $newId,
    $uid,
    $newTitle,
    $preview,
    $row['folder_id'],
    $row['connection_id'],
    $row['model'],
    json_encode($newMsgs, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    json_encode($meta, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    $now,
    $now
  ]);

  llc_json(['id'=>$newId]);
}


// SSE variant with keep-alive pings to prevent reverse-proxy/browser idle timeouts.
// GET params: id, keep
function llc_chat_compress_clone_sse(): void {
  $db = llc_db();
  $u = llc_session_user($db);
  if (!$u) llc_sse_error('Unauthorized');
  $uid = (string)$u['id'];

  $id = (string)($_GET['id'] ?? '');
  $keep = (int)($_GET['keep'] ?? 0);
  if ($keep < 0) $keep = 0;
  $includeFirst = (int)($_GET['include_first'] ?? 1);
  $includeFirst = ($includeFirst !== 0);

// STORY SO FAR length (option 1–4)
$storyOpt = (int)($_GET['story_words'] ?? ($_GET['story_words_option'] ?? ($_GET['story_length'] ?? 1)));
if ($storyOpt < 1 || $storyOpt > 4) $storyOpt = 1;
$storyLabel = '~300 words';
$storyAbout = '{$storyAbout}';
$storyFinal = '~300 words (250–350), prose only (no bullets), human-readable, and add no new facts.';
if ($storyOpt === 2) { $storyLabel = '500–1000 words'; $storyAbout = 'Between 500 and 1000 words (aim ~750).'; $storyFinal = '500–1000 words, prose only (no bullets), human-readable, and add no new facts.'; }
if ($storyOpt === 3) { $storyLabel = '1000–2000 words'; $storyAbout = 'Between 1000 and 2000 words (aim ~1500).'; $storyFinal = '1000–2000 words, prose only (no bullets), human-readable, and add no new facts.'; }
if ($storyOpt === 4) { $storyLabel = '2000–3500 words'; $storyAbout = 'Between 2000 and 3500 words (aim ~2500–3000).'; $storyFinal = '2000–3500 words, prose only (no bullets), human-readable, and add no new facts.'; }


  // Optional overrides (useful for older chats that may have lost connection_id/model).
  $reqConnId = trim((string)($_GET['connection_id'] ?? ''));
  if ($reqConnId !== '' && !llc_conn_accessible($db, $u, $reqConnId)) $reqConnId = '';
  $reqModel = trim((string)($_GET['model'] ?? ''));
  if ($id === '') llc_sse_error('missing id');

  header('Content-Type: text/event-stream; charset=utf-8');
  header('Cache-Control: no-cache');
  header('Connection: keep-alive');
  header('X-Accel-Buffering: no');

  // Send an initial byte immediately so browsers/proxies don't consider the connection idle.
  llc_sse_send(['type'=>'ping']);
  llc_sse_send(['type'=>'status','message'=>'Loading chat…']);

  try {
    $st = $db->prepare("SELECT * FROM chats WHERE id=? AND user_id=?");
    $st->execute([$id, $uid]);
    $row = $st->fetch();
    // Important for SQLite: don't keep a read cursor open during long-running upstream calls.
    // Otherwise other requests can end up hitting "database is locked".
    try { $st->closeCursor(); } catch (Throwable $_) { /* noop */ }
    $st = null;
    if (!$row) llc_sse_error('Chat not found');

    $msgs = json_decode((string)($row['messages_json'] ?? '[]'), true);
    if (!is_array($msgs)) $msgs = [];
    $total = count($msgs);

    // Always carry over the FIRST user message (the initial prompt) and clearly mark it.
    $firstIdx = null;
    for ($i=0; $i<$total; $i++) {
      $m = $msgs[$i];
      if (is_array($m) && (string)($m['role'] ?? '') === 'user') { $firstIdx = $i; break; }
    }
    if ($firstIdx === null && $total > 0) $firstIdx = 0;
  // Mark the first user message we carry over (always in English for consistency)
  $startLabel = "=== START OF ORIGINAL CHAT (first user message) ===\n";

    $firstBlock = '';
    if ($firstIdx !== null && $firstIdx >= 0 && $firstIdx < $total && isset($msgs[$firstIdx]) && is_array($msgs[$firstIdx])) {
      $m0 = $msgs[$firstIdx];
      $content0 = $m0['content'] ?? '';
      if (is_string($content0)) $txt0 = $content0;
      elseif (is_null($content0)) $txt0 = '';
      else $txt0 = json_encode($content0, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);

      $atts0 = $m0['attachments'] ?? [];
      if (is_array($atts0) && count($atts0) > 0) {
        $lines0 = [];
        foreach ($atts0 as $a0) {
          if (!is_array($a0)) continue;
          $type0 = (string)($a0['type'] ?? 'file');
          $name0 = (string)($a0['name'] ?? '');
          $url0  = (string)($a0['url'] ?? '');
          $mime0 = (string)($a0['mime'] ?? '');

          $line0 = "[attachment: " . $type0;
          if ($name0 !== '') $line0 .= " name=" . $name0;
          if ($mime0 !== '') $line0 .= " mime=" . $mime0;
          if ($url0  !== '') $line0 .= " url=" . $url0;
          $line0 .= "]";
          $lines0[] = $line0;

          $t0 = $a0['text'] ?? '';
          if (is_string($t0) && trim($t0) !== '') $lines0[] = trim($t0);
        }
        if (count($lines0) > 0) $txt0 = rtrim((string)$txt0) . "\n\n" . implode("\n", $lines0);
      }

      $firstBlock = rtrim($startLabel) . "\n" . rtrim((string)$txt0);
    }

    if (!$includeFirst) {
      $firstBlock = '';
    }

    // Tail messages to keep verbatim (exactly the last N messages, unchanged)
    $tail = [];
    $tailStart = 0;
    if ($keep > 0 && $total > 0) {
      $tailStart = max(0, $total - $keep);
      $tail = array_slice($msgs, $tailStart);
    }
    // Avoid duplicating the first user message in the tail (short chats)
    if ($includeFirst && $firstIdx !== null && $keep > 0 && $firstIdx >= $tailStart) {
      $idxInTail = $firstIdx - $tailStart;
      if (isset($tail[$idxInTail])) {
        unset($tail[$idxInTail]);
        $tail = array_values($tail);
      }
    }

    // Choose connection/model (prefer explicit request override, then chat settings, then user settings)
    $model = $reqModel !== '' ? $reqModel : (string)($row['model'] ?? (llc_get_setting($db, $uid, 'selected_model') ?? ''));
    if ($model === '') $model = 'gpt-4o-mini';

    $connId = $reqConnId !== '' ? $reqConnId : (string)($row['connection_id'] ?? (llc_get_setting($db, $uid, 'selected_connection_id') ?? ''));
    if (trim((string)$connId) === '' && $model !== '') {
      $inf = llc_infer_conn_id_for_model($db, $u, $uid, $model);
      if ($inf !== '') $connId = $inf;
    }
    $conn = ($connId ? llc_conn_by_id($db, $u, (string)$connId) : null);
    if (!$conn && $model !== '') {
      $inf = llc_infer_conn_id_for_model($db, $u, $uid, $model);
      if ($inf !== '' && $inf !== (string)$connId) {
        $connId = $inf;
        $conn = llc_conn_by_id($db, $u, $connId);
      }
    }
    if (!$conn) llc_sse_error('No active connection. Add one in Settings → Connections.');

    $model = llc_strip_model_prefix($model, $conn);

    llc_sse_send(['type'=>'status','message'=>'Building transcript…']);

    // Build FULL transcript (no truncation). Include attachments and any extracted text verbatim.
    $parts = [];
    foreach ($msgs as $m) {
      if (!is_array($m)) continue;
      $role = (string)($m['role'] ?? '');
      $label = ($role === 'assistant') ? 'Assistant' : (($role === 'system') ? 'System' : 'User');

      $content = $m['content'] ?? '';
      if (is_string($content)) $txt = $content;
      elseif (is_null($content)) $txt = '';
      else $txt = json_encode($content, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);

      $atts = $m['attachments'] ?? [];
      if (is_array($atts) && count($atts) > 0) {
        $lines = [];
        foreach ($atts as $a) {
          if (!is_array($a)) continue;
          $type = (string)($a['type'] ?? 'file');
          $name = (string)($a['name'] ?? '');
          $urlA  = (string)($a['url'] ?? '');
          $mime = (string)($a['mime'] ?? '');

          $line = "[attachment: " . $type;
          if ($name !== '') $line .= " name=" . $name;
          if ($mime !== '') $line .= " mime=" . $mime;
          if ($urlA  !== '') $line .= " url=" . $urlA;
          $line .= "]";
          $lines[] = $line;

          $t = $a['text'] ?? '';
          if (is_string($t) && trim($t) !== '') $lines[] = trim($t);
        }
        if (count($lines) > 0) $txt = rtrim((string)$txt) . "\n\n" . implode("\n", $lines);
      }

      $parts[] = $label . ":\n" . rtrim((string)$txt);
    }
    $transcript = implode("\n\n---\n\n", $parts);

    $sys = "You are a conversation compressor for a chat UI.\n\n"
         . "TASK\n"
         . "Given the full conversation transcript, produce a single compact \"Continuation Memory\" block that will be inserted as the FIRST USER MESSAGE of a NEW CLONED CHAT.\n"
         . "This memory must allow a fresh assistant instance to continue seamlessly, as if it had participated in the original chat.\n\n"
         . "LANGUAGE (CRITICAL)\n"
         . "- Write the ENTIRE output in the SAME language as the original conversation.\n"
         . "- If the conversation is mixed, use the language used by the user most recently.\n"
         . "- Translate headings and the continuation banner too.\n\n"
         . "CRITICAL REQUIREMENTS\n"
         . "1) This is NOT a generic summary. It is operational memory for continuation.\n"
         . "2) Goals can evolve: capture the CURRENT goal, and record past goals only if still relevant.\n"
         . "3) Preserve hard facts, decisions, constraints. Do not invent. If uncertain: mark as uncertain.\n"
         . "4) Be compact and information-dense (bullets preferred). No fluff.\n"
         . "5) Make explicit that this is a continuation of a previous chat (cloned continuation).\n\n"
         . "OUTPUT FORMAT (follow exactly, but translated into the correct language)\n"
         . "=== CONTINUATION MEMORY (CLONED CHAT) ===\n"
         . "Origin: continuation of earlier chat (cloned). Treat this as prior context and continue from here naturally. Continue in original language.\n\n"
         . "0) USED LANGUAGE(s) \n"
		 . "- bullets.\n\n"
		 . "1) CURRENT GOAL (latest)\n- 1–2 sentences.\n\n"
         . "2) CONTEXT & GOAL EVOLUTION (only if relevant)\n- bullets.\n\n"
         . "3) HARD FACTS & DECISIONS\n- bullets.\n\n"
         . "4) CONSTRAINTS & PREFERENCES\n- bullets.\n\n"
         . "5) OPEN QUESTIONS / TODO\n- bullets.\n\n"
         . "6) ARTIFACTS / LINKS / FILES\n- bullets.\n\n"
         . "7) DO NOT FORGET\n- bullets.\n\n"
         . "8) STORY SO FAR (narrative recap, {$storyLabel})\n- {$storyAbout} Flowing prose (NO bullets), like a human retelling. 1–3 short paragraphs.\n- Chronological: what happened, why goals shifted, key decisions/constraints, where things stand now.\n- Strictly grounded in the transcript. Do NOT invent; if uncertain: mark as uncertain.\n\n"
         . "COMPRESSION RULES\n"
         . "- Prefer: user constraints, decisions already made, current plan, unresolved questions.\n"
         . "- Drop: small talk, repetition, acknowledgements.\n"
         . "- Preserve contradictions and note them.\n\n"
         . "FINAL CHECK\n"
         . "- CURRENT GOAL must reflect the latest state.\n"
         . "- OPEN QUESTIONS / TODO must be actionable.\n"
         . "- No invented details.\n"
         . "- STORY SO FAR: {$storyFinal}\n";

    $user = "TRANSCRIPT (chronological, complete):\n\n" . $transcript;

    $base = rtrim(trim((string)($conn['base_url'] ?? '')), '/');
    $url = $base . '/chat/completions';

    $hdrs = ['Content-Type: application/json', 'Accept: application/json'];
    $key = (string)($conn['api_key'] ?? '');
    if (trim($key) !== '') $hdrs[] = 'Authorization: Bearer ' . $key;
    if (!empty($conn['headers'])) $hdrs = array_merge($hdrs, llc_custom_headers((string)$conn['headers']));

    $payload = [
      'model' => $model,
      'messages' => [
        ['role'=>'system','content'=>$sys],
        ['role'=>'user','content'=>$user],
      ],
    ];

    llc_sse_send(['type'=>'status','message'=>'Calling model to compress…']);
    // Keepalive pings during the long upstream request.
    $resp = llc_http_post_json_keepalive($url, $hdrs, $payload, 15.0);

    $memory = (string)($resp['choices'][0]['message']['content'] ?? '');
    $memory = trim($memory);
    if ($memory === '') throw new RuntimeException('Compression produced empty result');

    llc_sse_send(['type'=>'status','message'=>'Creating cloned chat…']);

    $now = llc_now();
    $newId = llc_id('chat_');
    $combined = ($firstBlock !== '') ? (rtrim($firstBlock) . "\n\n" . $memory) : $memory;

    $newMsgs = [];
    $newMsgs[] = ['role'=>'user','content'=>$combined,'created_at'=>$now];
    // The kept tail is context-only. Don't carry over usage/cost counters.
    $stripUsageFromMsg = function($m) {
      if (!is_array($m)) return $m;
      if ((string)($m['role'] ?? '') === 'assistant') {
        if (array_key_exists('metrics', $m)) unset($m['metrics']);
      }
      return $m;
    };

    foreach ($tail as $m) { if (is_array($m)) $newMsgs[] = $stripUsageFromMsg($m); }
    $newMsgs[] = ['role'=>'assistant','content'=>'press regenerate icon to continue discussion','created_at'=>$now,'model'=>$model];

    $title = (string)($row['title'] ?? 'New chat');
    $suffix = ($keep > 0) ? (' (Compact+' . $keep . ')') : ' (Compact)';
    $newTitle = $title . $suffix;

    $preview = preg_replace('/\s+/', ' ', $memory);
    $preview = trim((string)$preview);

    $meta = json_decode((string)($row['meta_json'] ?? '{}'), true);
    if (!is_array($meta)) $meta = [];

    // Reset usage counters for the NEW chat (compact+clone only).
    foreach (['billed','last_prompt_tok','last_completion_tok','last_total_tok','last_elapsed_s','last_tps','total_gen_tok'] as $k) {
      if (array_key_exists($k, $meta)) unset($meta[$k]);
    }
    // Frontend hint: show zeroed usage until the first new generation in this chat.
    $meta['usage_reset'] = 1;
    $meta['compressed_from_chat_id'] = $id;
    $meta['compressed_at'] = $now;
    $meta['compression_keep_last'] = $keep;
    $meta['compression_include_first'] = $includeFirst ? 1 : 0;
    $meta['compression_kind'] = 'compress_clone';

    $st2 = $db->prepare("INSERT INTO chats (id,user_id,title,preview,folder_id,connection_id,model,messages_json,meta_json,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)");
    $st2->execute([
      $newId,
      $uid,
      $newTitle,
      $preview,
      $row['folder_id'],
      $row['connection_id'],
      $row['model'],
      json_encode($newMsgs, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
      json_encode($meta, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
      $now,
      $now
    ]);

    llc_sse_send(['type'=>'result','id'=>$newId]);
    llc_sse_send(['type'=>'done']);
    exit;
  } catch (Throwable $e) {
    llc_sse_send(['type'=>'error','error'=>$e->getMessage()]);
    llc_sse_send(['type'=>'done']);
    exit;
  }
}




function llc_chat_export(): void {
  $db = llc_db();
  $u = llc_session_user($db);
  if (!$u) {
    http_response_code(401);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Unauthorized";
    exit;
  }
  $uid = (string)$u['id'];

  $id = $_GET['id'] ?? '';
  $format = (string)($_GET['format'] ?? 'json');
  $format = strtolower(trim($format));
  if (!in_array($format, ['json','txt','openai','openai_json','openai-json'], true)) $format = 'json';
  if ($id === '') { http_response_code(400); echo 'missing id'; exit; }

  $st = $db->prepare("SELECT * FROM chats WHERE id=? AND user_id=?");
  $st->execute([$id, $uid]);
  $row = $st->fetch();
  if (!$row) { http_response_code(404); echo 'not found'; exit; }

  $built = llc_build_chat_export_file($db, $uid, $row, $format);
  $fn = $built['filename'];
  $content = $built['content'];

  if ($format === 'txt') {
    header('Content-Type: text/plain; charset=utf-8');
  } else {
    header('Content-Type: application/json; charset=utf-8');
  }
  header('Content-Disposition: attachment; filename="'.$fn.'"');
  echo $content;
  exit;
}


// Export ALL chats as a ZIP.
// Writes individual files into ./tmp/<job>/ and then zips them for download.
function llc_chats_export_all(): void {
  $db = llc_db();
  $u = llc_session_user($db);
  if (!$u) {
    http_response_code(401);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Unauthorized";
    exit;
  }
  $uid = (string)$u['id'];

  $format = (string)($_GET['format'] ?? 'json');
  $format = strtolower(trim($format));
  if (!in_array($format, ['json','txt','openai','openai_json','openai-json'], true)) $format = 'json';

  if (!class_exists('ZipArchive')) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "ZipArchive is missing (php-zip). Please install/enable the extension.";
    exit;
  }

  @set_time_limit(0);
  @ignore_user_abort(true);

  $st = $db->prepare("SELECT * FROM chats WHERE user_id=? ORDER BY updated_at DESC");
  $st->execute([$uid]);
  $rows = $st->fetchAll();

  if (!$rows) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    echo "No chats to export.";
    exit;
  }

  $rootTmp = llc_tmp_dir();
  if (!is_dir($rootTmp)) @mkdir($rootTmp, 0775, true);

  $job = 'export_' . bin2hex(random_bytes(6));
  $jobDir = $rootTmp . '/' . $job;
  if (!is_dir($jobDir)) @mkdir($jobDir, 0775, true);

  $zipPath = $rootTmp . '/' . $job . '.zip';

  register_shutdown_function(function() use ($jobDir, $zipPath) {
    try { if (is_file($zipPath)) @unlink($zipPath); } catch (Throwable $e) {}
    try { llc_rrmdir($jobDir); } catch (Throwable $e) {}
  });

  $manifest = [
    'exported_at' => time(),
    'format' => $format,
    'count' => count($rows),
    'files' => []
  ];

  foreach ($rows as $row) {
    $built = llc_build_chat_export_file($db, $uid, $row, $format);
    $fn = $built['filename'];
    $content = $built['content'];
    $path = $jobDir . '/' . $fn;
    @file_put_contents($path, $content);
    $manifest['files'][] = [
      'chat_id' => (string)($row['id'] ?? ''),
      'title' => (string)($row['title'] ?? ''),
      'filename' => $fn,
      'updated_at' => (int)($row['updated_at'] ?? 0),
    ];
  }
  @file_put_contents($jobDir . '/manifest.json', json_encode($manifest, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_PRETTY_PRINT));

  $zip = new ZipArchive();
  if ($zip->open($zipPath, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Could not create ZIP.";
    exit;
  }
  $files = scandir($jobDir);
  foreach ($files as $f) {
    if ($f === '.' || $f === '..') continue;
    $p = $jobDir . '/' . $f;
    if (is_file($p)) $zip->addFile($p, $f);
  }
  $zip->close();

  header('Content-Type: application/zip');
  header('Content-Disposition: attachment; filename="chats_'.$format.'.zip"');
  header('Content-Length: ' . filesize($zipPath));
  readfile($zipPath);
  exit;
}


// Export chats inside a folder (including its subfolders) as a ZIP.
// Writes files into ./tmp/<job>/ and then zips them for download.
function llc_folder_export(): void {
  $db = llc_db();
  $u = llc_session_user($db);
  if (!$u) {
    http_response_code(401);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Unauthorized";
    exit;
  }
  $uid = (string)$u['id'];

  $folderId = (string)($_GET['id'] ?? '');
  if ($folderId === '') { http_response_code(400); header('Content-Type: text/plain; charset=utf-8'); echo 'missing id'; exit; }

  $format = (string)($_GET['format'] ?? 'json');
  $format = strtolower(trim($format));
  if (!in_array($format, ['json','txt','openai','openai_json','openai-json'], true)) $format = 'json';

  if (!class_exists('ZipArchive')) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "ZipArchive is missing (php-zip). Please install/enable the extension.";
    exit;
  }

  // Ensure folder exists and belongs to this user.
  $stF0 = $db->prepare('SELECT id,parent_id,name FROM folders WHERE id=? AND user_id=?');
  $stF0->execute([$folderId, $uid]);
  $rootFolder = $stF0->fetch();
  if (!$rootFolder) { http_response_code(404); header('Content-Type: text/plain; charset=utf-8'); echo 'Folder not found.'; exit; }
  $rootName = (string)($rootFolder['name'] ?? 'Folder');

  $safe_folder_name = function(string $name): string {
    return trim($name) === '' ? 'folder' : llc_safe_filename($name);
  };

  @set_time_limit(0);
  @ignore_user_abort(true);

  // Collect folder tree records (folder + descendants)
  $stTree = $db->prepare(
    "WITH RECURSIVE sub(id,parent_id,name) AS (\n".
    "  SELECT id,parent_id,name FROM folders WHERE id=? AND user_id=?\n".
    "  UNION ALL\n".
    "  SELECT f.id,f.parent_id,f.name FROM folders f JOIN sub s ON f.parent_id = s.id WHERE f.user_id=?\n".
    ") SELECT id,parent_id,name FROM sub"
  );
  $stTree->execute([$folderId, $uid, $uid]);
  $folderRows = $stTree->fetchAll();
  if (!$folderRows) $folderRows = [$rootFolder];

  $nameById = new ArrayObject();
  $parentById = new ArrayObject();
  foreach ($folderRows as $fr) {
    $fid = (string)($fr['id'] ?? '');
    if ($fid === '') continue;
    $nameById[$fid] = (string)($fr['name'] ?? 'Folder');
    $parentById[$fid] = ($fr['parent_id'] === null || $fr['parent_id'] === '') ? null : (string)$fr['parent_id'];
  }

  // Helper: folder-relative path inside the exported root folder.
  $relFolderPath = function(string $fid) use ($folderId, $nameById, $parentById, $safe_folder_name): string {
    $parts = [];
    $walk = $fid;
    $seen = [];
    while ($walk !== '' && $walk !== null && !isset($seen[$walk])) {
      $seen[$walk] = true;
      $parts[] = $safe_folder_name((string)($nameById[$walk] ?? 'Folder'));
      if ($walk === $folderId) break;
      $walk = $parentById[$walk] ?? null;
    }
    $parts = array_reverse($parts);
    // Drop the root folder itself.
    if (count($parts) > 0) array_shift($parts);
    $parts = array_values(array_filter($parts, fn($x)=>$x!==''));
    return implode('/', $parts);
  };

  // Query chats inside any folder in the subtree.
  $folderIds = [];
  foreach ($folderRows as $fr) {
    $fid = (string)($fr['id'] ?? '');
    if ($fid !== '') $folderIds[] = $fid;
  }
  $folderIds = array_values(array_unique($folderIds));
  if (!count($folderIds)) $folderIds = [$folderId];
  $ph = implode(',', array_fill(0, count($folderIds), '?'));
  $stC = $db->prepare("SELECT * FROM chats WHERE user_id=? AND folder_id IN ($ph) ORDER BY updated_at DESC");
  $stC->execute(array_merge([$uid], $folderIds));
  $rows = $stC->fetchAll();

  if (!$rows) {
    http_response_code(404);
    header('Content-Type: text/plain; charset=utf-8');
    echo "No chats to export in this folder.";
    exit;
  }

  $rootTmp = llc_tmp_dir();
  if (!is_dir($rootTmp)) @mkdir($rootTmp, 0775, true);

  $job = 'export_' . bin2hex(random_bytes(6));
  $jobDir = $rootTmp . '/' . $job;
  if (!is_dir($jobDir)) @mkdir($jobDir, 0775, true);

  $zipPath = $rootTmp . '/' . $job . '.zip';

  register_shutdown_function(function() use ($jobDir, $zipPath) {
    try { if (is_file($zipPath)) @unlink($zipPath); } catch (Throwable $e) {}
    try { llc_rrmdir($jobDir); } catch (Throwable $e) {}
  });

  $safeRootName = $safe_folder_name($rootName);
  $safeRootDir = ($safeRootName !== '' ? $safeRootName : 'folder') . '_' . llc_safe_filename($folderId);
  if (!is_dir($jobDir . '/' . $safeRootDir)) @mkdir($jobDir . '/' . $safeRootDir, 0775, true);

  $manifest = [
    'exported_at' => time(),
    'format' => $format,
    'folder' => [
      'id' => $folderId,
      'name' => $rootName,
    ],
    'count' => count($rows),
    'files' => []
  ];

  foreach ($rows as $row) {
    $built = llc_build_chat_export_file($db, $uid, $row, $format);
    $fn = $built['filename'];
    $content = $built['content'];

    $fid = (string)($row['folder_id'] ?? '');
    $rel = ($fid !== '' ? $relFolderPath($fid) : '');
    $dir = $jobDir . '/' . $safeRootDir . ($rel !== '' ? ('/' . $rel) : '');
    if (!is_dir($dir)) @mkdir($dir, 0775, true);
    $path = $dir . '/' . $fn;
    @file_put_contents($path, $content);

    $manifest['files'][] = [
      'chat_id' => (string)($row['id'] ?? ''),
      'title' => (string)($row['title'] ?? ''),
      'filename' => ($safeRootDir . ($rel !== '' ? ('/' . $rel) : '') . '/' . $fn),
      'folder_id' => $fid,
      'updated_at' => (int)($row['updated_at'] ?? 0),
    ];
  }
  @file_put_contents($jobDir . '/' . $safeRootDir . '/manifest.json', json_encode($manifest, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_PRETTY_PRINT));

  // Build ZIP (recursive)
  $zip = new ZipArchive();
  if ($zip->open($zipPath, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Could not create ZIP.";
    exit;
  }
  $it = new RecursiveIteratorIterator(
    new RecursiveDirectoryIterator($jobDir, FilesystemIterator::SKIP_DOTS),
    RecursiveIteratorIterator::LEAVES_ONLY
  );
  foreach ($it as $fileInfo) {
    if (!$fileInfo->isFile()) continue;
    $abs = $fileInfo->getPathname();
    $rel = ltrim(str_replace($jobDir, '', $abs), '/\\');
    $zip->addFile($abs, $rel);
  }
  $zip->close();

  $zipName = 'folder_' . ($safeRootName !== '' ? $safeRootName : 'folder') . '_' . $format . '.zip';
  header('Content-Type: application/zip');
  header('Content-Disposition: attachment; filename="' . $zipName . '"');
  header('Content-Length: ' . filesize($zipPath));
  readfile($zipPath);
  exit;
}


function llc_build_chat_export_file(PDO $db, string $uid, array $row, string $format): array {
  $chat = [
    'id'=>$row['id'],
    'title'=>$row['title'],
    'preview'=>$row['preview'],
    'folder_id'=>$row['folder_id'],
    'connection_id'=>$row['connection_id'] ?? '',
    'model'=>$row['model'],
    'messages'=>json_decode((string)($row['messages_json'] ?? '[]'), true) ?: [],
    'meta'=>json_decode((string)($row['meta_json'] ?? '{}'), true) ?: [],
    'created_at'=>(int)($row['created_at'] ?? 0),
    'updated_at'=>(int)($row['updated_at'] ?? 0),
  ];

  // Best-effort system prompt for exports.
  $sys = '';
  if (is_array($chat['meta']) && isset($chat['meta']['system_prompt'])) {
    $sys = (string)$chat['meta']['system_prompt'];
  }
  if ($sys === '') {
    try { $sys = (string)(llc_get_setting($db, $uid, 'system_prompt') ?? ''); } catch (Throwable $e) { $sys = ''; }
  }

  $msg_text = function($m): string {
    $c = $m['content'] ?? '';
    if (is_string($c)) return $c;
    if (is_null($c)) return '';
    if (is_array($c)) {
      $parts = [];
      foreach ($c as $p) {
        if (is_string($p)) { $parts[] = $p; continue; }
        if (!is_array($p)) continue;
        $t = (string)($p['type'] ?? '');
        if ($t === 'text' || $t === 'input_text') $parts[] = (string)($p['text'] ?? '');
      }
      return trim(implode("\n", array_filter($parts, fn($x)=>$x!=='')));
    }
    return json_encode($c, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
  };

  $safeTitle = llc_safe_filename((string)($chat['title'] ?? 'chat'));
  $id = (string)($chat['id'] ?? '');
  $suffix = $id !== '' ? ('_' . $id) : '';

  if ($format === 'openai' || $format === 'openai_json' || $format === 'openai-json') {
    $msgs = [];
    $hasSystem = false;
    foreach ($chat['messages'] as $m){
      if (($m['role'] ?? '') === 'system') { $hasSystem = true; break; }
    }
    if (!$hasSystem && trim($sys) !== '') $msgs[] = ['role'=>'system','content'=>$sys];
    foreach ($chat['messages'] as $m){
      $role = (string)($m['role'] ?? '');
      if ($role === '') continue;
      $msgs[] = ['role'=>$role,'content'=>$msg_text($m)];
    }
    $content = json_encode(['messages'=>$msgs], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_PRETTY_PRINT);
    return ['filename'=>($safeTitle ?: 'chat').$suffix.'_openai.json', 'content'=>$content];
  }

  if ($format === 'txt') {
    $out = "### SYSTEM\n".$sys."\n\n";
    foreach ($chat['messages'] as $m){
      $role = strtoupper((string)($m['role'] ?? ''));
      if ($role === '') continue;
      if ($role === 'SYSTEM') continue;
      $out .= "### ".$role."\n".$msg_text($m)."\n\n";
    }
    return ['filename'=>($safeTitle ?: 'chat').$suffix.'.txt', 'content'=>$out];
  }

  // Default: native JSON
  $content = json_encode($chat, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_PRETTY_PRINT);
  return ['filename'=>($safeTitle ?: 'chat').$suffix.'.json', 'content'=>$content];
}

function llc_safe_filename(string $s): string {
  $s = trim($s);
  if ($s === '') return 'chat';
  $s = preg_replace('/[^a-zA-Z0-9_\-]+/', '_', $s);
  $s = trim($s, '_');
  return $s === '' ? 'chat' : $s;
}

function llc_rrmdir(string $dir): void {
  if (!is_dir($dir)) return;
  $items = scandir($dir);
  if (!$items) { @rmdir($dir); return; }
  foreach ($items as $it) {
    if ($it === '.' || $it === '..') continue;
    $path = $dir . '/' . $it;
    if (is_dir($path)) llc_rrmdir($path);
    else @unlink($path);
  }
  @rmdir($dir);
}

function llc_chat_import(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  // Supports importing a single chat ({chat:{...}}) or multiple ({chats:[...]}).
  // Optional: {folder_id: "fld_..."} overrides the imported folder for all chats.

  $override_folder_id = $j['folder_id'] ?? null;
  if ($override_folder_id === '') $override_folder_id = null;
  if ($override_folder_id !== null && !llc_folder_exists($db, $uid, (string)$override_folder_id)) {
    $override_folder_id = null;
  }

  $chats = [];
  if (isset($j['chats']) && is_array($j['chats'])) {
    $chats = $j['chats'];
  } else {
    $one = $j['chat'] ?? null;
    if (!is_array($one)) throw new RuntimeException('chat missing');
    $chats = [$one];
  }

  $ids = [];
  foreach ($chats as $chat) {
    if (!is_array($chat)) continue;
    $ids[] = llc_import_one_chat($db, $u, $chat, $override_folder_id);
  }

  if (count($ids) === 1) llc_json(['id'=>$ids[0]]);
  llc_json(['ids'=>$ids]);
}


// Search chats by title and message content (naive LIKE over JSON blob).
// Intended for sidebar search; fast enough for small/medium personal DBs.
function llc_chat_search(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $q = trim((string)($j['q'] ?? ''));
  $limit = (int)($j['limit'] ?? 50);
  if ($limit <= 0 || $limit > 200) $limit = 50;

  if ($q === '') {
    llc_json(['q'=>'','results'=>[]]);
    return;
  }

  $qEsc = str_replace(['%','_'], ['\\%','\\_'], $q);
  $like = '%' . $qEsc . '%';

  $st = $db->prepare(
    "SELECT id,title,preview,folder_id,updated_at\n".
    "FROM chats\n".
    "WHERE user_id=? AND (\n".
    // NOTE: SQLite requires the ESCAPE expression to be a *single* character.
    // '\\' in SQL is two characters, which throws "ESCAPE expression must be a single character".
    // We want a single backslash as the escape char: ESCAPE '\\'.
    "      title LIKE ? ESCAPE '\\'\n".
    "   OR preview LIKE ? ESCAPE '\\'\n".
    "   OR messages_json LIKE ? ESCAPE '\\'\n".
    ")\n".
    "ORDER BY updated_at DESC\n".
    "LIMIT ?"
  );
  $st->execute([$uid,$like,$like,$like,$limit]);
  $rows = $st->fetchAll();
  llc_json(['q'=>$q,'results'=>$rows]);
}


// ---------- templates ----------
function llc_template_list(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $st = $db->prepare("SELECT id,name,created_at,updated_at FROM templates WHERE user_id=? ORDER BY name COLLATE NOCASE ASC");
  $st->execute([$uid]);
  $rows = $st->fetchAll();
  llc_json(['templates'=>$rows]);
}

function llc_template_get(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j, 'id');
  $st = $db->prepare("SELECT id,name,payload_json,created_at,updated_at FROM templates WHERE id=? AND user_id=? LIMIT 1");
  $st->execute([$id, $uid]);
  $r = $st->fetch();
  if (!$r) llc_json(['error'=>'Template not found'], 404);
  $payload = json_decode((string)($r['payload_json'] ?? ''), true);
  if (!is_array($payload)) $payload = [];
  llc_json(['template'=>[
    'id'=>(string)$r['id'],
    'name'=>(string)$r['name'],
    'payload'=>$payload,
    'created_at'=>(int)$r['created_at'],
    'updated_at'=>(int)$r['updated_at'],
  ]]);
}

function llc_template_create(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $name = trim((string)llc_require($j, 'name'));
  if ($name === '') throw new RuntimeException('name required');
  $payload = $j['payload'] ?? [];
  if (!is_array($payload)) throw new RuntimeException('payload must be an object');

  $id = llc_id('tpl_');
  $now = llc_now();
  $payload_json = json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
  if (!is_string($payload_json)) $payload_json = '{}';

  $st = $db->prepare("INSERT INTO templates (id,user_id,name,payload_json,created_at,updated_at) VALUES (?,?,?,?,?,?)");
  $st->execute([$id, $uid, $name, $payload_json, $now, $now]);
  llc_json(['id'=>$id]);
}

function llc_template_rename(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j, 'id');
  $name = trim((string)llc_require($j, 'name'));
  if ($name === '') throw new RuntimeException('name required');

  $st = $db->prepare("UPDATE templates SET name=?, updated_at=? WHERE id=? AND user_id=?");
  $st->execute([$name, llc_now(), $id, $uid]);
  if ($st->rowCount() <= 0) llc_json(['error'=>'Template not found'], 404);
  llc_json(['ok'=>true]);
}

function llc_template_delete(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j, 'id');
  $st = $db->prepare("DELETE FROM templates WHERE id=? AND user_id=?");
  $st->execute([$id, $uid]);
  if ($st->rowCount() <= 0) llc_json(['error'=>'Template not found'], 404);
  llc_json(['ok'=>true]);
}


function llc_folder_exists(PDO $db, string $uid, string $id): bool {
  $st = $db->prepare('SELECT 1 FROM folders WHERE id=? AND user_id=?');
  $st->execute([$id, $uid]);
  return (bool)$st->fetchColumn();
}

function llc_import_one_chat(PDO $db, array $u, array $chat, ?string $override_folder_id): string {
  $uid = (string)($u['id'] ?? '');
  $id = llc_id('chat_');
  $now = llc_now();

  $title = (string)($chat['title'] ?? 'Imported chat');
  $preview = (string)($chat['preview'] ?? '');
  $folder_id = $override_folder_id !== null ? $override_folder_id : ($chat['folder_id'] ?? null);
  if ($folder_id === '') $folder_id = null;
  if ($folder_id !== null && !llc_folder_exists($db, $uid, (string)$folder_id)) $folder_id = null;

  $connection_id = (string)($chat['connection_id'] ?? (llc_get_setting($db, $uid, 'selected_connection_id') ?? ''));
  if ($connection_id === '') $connection_id = null;

  if ($connection_id !== null && !llc_conn_accessible($db, $u, (string)$connection_id)) $connection_id = null;
  $model = (string)($chat['model'] ?? (llc_get_setting($db, $uid, 'selected_model') ?? ''));

  $messages = $chat['messages'] ?? [];
  if (!is_array($messages)) $messages = [];
  $meta = $chat['meta'] ?? [];
  if (!is_array($meta)) $meta = [];

  $st = $db->prepare("INSERT INTO chats (id,user_id,title,preview,folder_id,connection_id,model,messages_json,meta_json,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)");
  $st->execute([
    $id, $uid, $title, $preview, $folder_id, $connection_id, $model,
    json_encode($messages, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    json_encode($meta, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    $now, $now
  ]);

  return $id;
}

// ---------- folders ----------
function llc_folder_create(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $name = trim((string)llc_require($j,'name'));
  $parent_id = $j['parent_id'] ?? null;
  if ($parent_id === '') $parent_id = null;

  if ($parent_id !== null) {
    $stP = $db->prepare("SELECT 1 FROM folders WHERE id=? AND user_id=?");
    $stP->execute([(string)$parent_id, $uid]);
    if (!$stP->fetchColumn()) throw new RuntimeException('Parent folder not found');
  }

  $id = llc_id('fld_');
  $now = llc_now();
  $st = $db->prepare("INSERT INTO folders (id,user_id,parent_id,name,created_at,updated_at) VALUES (?,?,?,?,?,?)");
  $st->execute([$id, $uid, $parent_id, $name, $now, $now]);
  llc_json(['id'=>$id]);
}


function llc_folder_move(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');
  $parent_id = $j['parent_id'] ?? null;
  if ($parent_id === '') $parent_id = null;
  if ($parent_id !== null) $parent_id = (string)$parent_id;

  // Ensure folder exists and belongs to this user.
  $st0 = $db->prepare("SELECT parent_id FROM folders WHERE id=? AND user_id=?");
  $st0->execute([$id, $uid]);
  $curRow = $st0->fetch();
  if (!$curRow) throw new RuntimeException('Folder not found');

  if ($parent_id !== null) {
    if ($parent_id === $id) throw new RuntimeException('Cannot move a folder into itself');

    // Ensure parent exists.
    $stP = $db->prepare("SELECT parent_id FROM folders WHERE id=? AND user_id=?");
    $stP->execute([$parent_id, $uid]);
    $pRow = $stP->fetch();
    if (!$pRow) throw new RuntimeException('Parent folder not found');

    // Cycle check: walk up from new parent to root.
    $walk = $parent_id;
    while ($walk !== null && $walk !== '') {
      if ($walk === $id) throw new RuntimeException('Invalid move (would create a cycle)');
      $stW = $db->prepare("SELECT parent_id FROM folders WHERE id=? AND user_id=?");
      $stW->execute([$walk, $uid]);
      $rW = $stW->fetch();
      $walk = $rW ? ($rW['parent_id'] ?? null) : null;
      if ($walk === '') $walk = null;
    }
  }

  $st = $db->prepare("UPDATE folders SET parent_id=?, updated_at=? WHERE id=? AND user_id=?");
  $st->execute([$parent_id, llc_now(), $id, $uid]);
  llc_json(['ok'=>true]);
}


function llc_folder_rename(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');
  $name = trim((string)llc_require($j,'name'));

  $st = $db->prepare("UPDATE folders SET name=?, updated_at=? WHERE id=? AND user_id=?");
  $st->execute([$name, llc_now(), $id, $uid]);
  llc_json(['ok'=>true]);
}


function llc_folder_delete(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');

  $mode = (string)($j['mode'] ?? 'move_to_root');
  if ($mode !== 'delete_chats') $mode = 'move_to_root';

  // Collect folder ids in the subtree (folder + all descendants), restricted to this user
  $stTree = $db->prepare(
    "WITH RECURSIVE sub(id) AS (\n".
    "  SELECT id FROM folders WHERE id=? AND user_id=?\n".
    "  UNION ALL\n".
    "  SELECT f.id FROM folders f JOIN sub s ON f.parent_id = s.id WHERE f.user_id=?\n".
    ") SELECT id FROM sub"
  );
  $stTree->execute([$id, $uid, $uid]);
  $folderIds = array_map(fn($r)=>(string)$r['id'], $stTree->fetchAll());
  if (count($folderIds) === 0) $folderIds = [$id];

  $ph = implode(',', array_fill(0, count($folderIds), '?'));
  if ($mode === 'delete_chats') {
    $st = $db->prepare("DELETE FROM chats WHERE user_id=? AND folder_id IN ($ph)");
    $st->execute(array_merge([$uid], $folderIds));
  } else {
    $st = $db->prepare("UPDATE chats SET folder_id=NULL WHERE user_id=? AND folder_id IN ($ph)");
    $st->execute(array_merge([$uid], $folderIds));
  }

  // Delete folder row; subfolders are removed via ON DELETE CASCADE.
  $st2 = $db->prepare("DELETE FROM folders WHERE id=? AND user_id=?");
  $st2->execute([$id, $uid]);
  llc_json(['ok'=>true]);
}


// ---------- connections ----------
function llc_conn_list(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  if (function_exists('llc_ensure_default_settings')) llc_ensure_default_settings($db, $uid);

  $connections = llc_connections_for_user($db, $u, true);

  $selected = llc_get_setting($db, $uid, 'selected_connection_id') ?? '';
  $selectedOk = false;
  foreach ($connections as $c) {
    if ((string)($c['id'] ?? '') === (string)$selected && (int)($c['enabled'] ?? 1) === 1) { $selectedOk = true; break; }
  }
  if (!$selectedOk) {
    $fallback = '';
    foreach ($connections as $c) {
      if ((int)($c['enabled'] ?? 1) === 1) { $fallback = (string)$c['id']; break; }
    }
    $selected = $fallback;
    llc_set_setting($db, $uid, 'selected_connection_id', $selected);
  }

  llc_json([
    'connections'=>$connections,
    'selected_connection_id'=>$selected,
    'can_create_connections'=> (llc_can_manage_own_connections($db, $u) || llc_is_superadmin_user($u)) ? 1 : 0,
    'inherit_global_connections'=> llc_inherit_global_connections($db, $u) ? 1 : 0,
  ]);
}


function llc_conn_save(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();

  $id = trim((string)llc_require($j,'id'));
  $label = trim((string)llc_require($j,'label'));
  $prefix = trim((string)($j['prefix'] ?? ''));
  $base_url = llc_norm_base((string)llc_require($j,'base_url'));
  $enabled = (int)($j['enabled'] ?? 1);
  if ($enabled !== 0) $enabled = 1;
  $api_key = (string)($j['api_key'] ?? '');
  $headers = (string)($j['headers'] ?? '');
  $notes = (string)($j['notes'] ?? '');

  $now = time();

  // Superadmins edit the shared global table.
  if (llc_is_superadmin_user($u)) {
    $st = $db->prepare("
      INSERT INTO global_connections (id,label,prefix,base_url,enabled,api_key,headers,notes,created_at,updated_at)
      VALUES (?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        label=excluded.label,
        prefix=excluded.prefix,
        base_url=excluded.base_url,
        enabled=excluded.enabled,
        api_key=excluded.api_key,
        headers=excluded.headers,
        notes=excluded.notes,
        updated_at=excluded.updated_at
    ");
    $st->execute([$id,$label,$prefix,$base_url,$enabled,$api_key,$headers?:null,$notes,$now,$now]);

    // If no selected connection yet, pick the first enabled one.
    $sel = llc_get_setting($db, $uid, 'selected_connection_id') ?? '';
    if ($sel === '' && $enabled === 1) llc_set_setting($db, $uid, 'selected_connection_id', $id);
    llc_json(['ok'=>true]);
  }

  // Everyone else may only manage their own connections.
  if (!llc_can_manage_own_connections($db, $u)) llc_json(['error'=>'Forbidden'], 403);

  $st = $db->prepare("
    INSERT INTO connections (id,user_id,label,prefix,base_url,enabled,api_key,headers,notes,created_at,updated_at)
    VALUES (?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET
      label=excluded.label,
      prefix=excluded.prefix,
      base_url=excluded.base_url,
      enabled=excluded.enabled,
      api_key=excluded.api_key,
      headers=excluded.headers,
      notes=excluded.notes,
      updated_at=excluded.updated_at
  ");
  $st->execute([$id,$uid,$label,$prefix,$base_url,$enabled,$api_key,$headers?:null,$notes,$now,$now]);

  // If no selected connection yet, pick the first enabled one.
  $sel = llc_get_setting($db, $uid, 'selected_connection_id') ?? '';
  if ($sel === '' && $enabled === 1) llc_set_setting($db, $uid, 'selected_connection_id', $id);
  llc_json(['ok'=>true]);
}




function llc_conn_delete(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');

  // If it's a global connection, only superadmins may delete it.
  $stG = $db->prepare("SELECT 1 FROM global_connections WHERE id=?");
  $stG->execute([$id]);
  $isGlobal = (bool)$stG->fetchColumn();

  if ($isGlobal) {
    if (!llc_is_superadmin_user($u)) llc_json(['error'=>'Forbidden'], 403);

    $st = $db->prepare("DELETE FROM global_connections WHERE id=?");
    $st->execute([$id]);

    // Clear selected_connection_id for everyone who had this selected.
    $st2 = $db->prepare("UPDATE settings SET v='' WHERE k='selected_connection_id' AND v=?");
    $st2->execute([$id]);

    llc_json(['ok'=>true]);
  }

  // Otherwise it's an own connection.
  if (!llc_can_manage_own_connections($db, $u)) llc_json(['error'=>'Forbidden'], 403);

  $st0 = $db->prepare("SELECT 1 FROM connections WHERE id=? AND user_id=?");
  $st0->execute([$id, $uid]);
  if (!$st0->fetchColumn()) throw new RuntimeException('Connection not found');

  $st = $db->prepare("DELETE FROM connections WHERE id=? AND user_id=?");
  $st->execute([$id, $uid]);

  $sel = llc_get_setting($db, $uid, 'selected_connection_id') ?? '';
  if ($sel === $id) {
    llc_set_setting($db, $uid, 'selected_connection_id', '');
  }
  llc_json(['ok'=>true]);
}




function llc_conn_set_enabled(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)llc_require($j,'id');
  $enabled = (int)($j['enabled'] ?? 1);
  if ($enabled !== 0) $enabled = 1;

  $now = time();

  // Global?
  $stG = $db->prepare("SELECT 1 FROM global_connections WHERE id=?");
  $stG->execute([$id]);
  $isGlobal = (bool)$stG->fetchColumn();

  if ($isGlobal) {
    if (!llc_is_superadmin_user($u)) llc_json(['error'=>'Forbidden'], 403);
    $st = $db->prepare("UPDATE global_connections SET enabled=?, updated_at=? WHERE id=?");
    $st->execute([$enabled, $now, $id]);
  } else {
    if (!llc_can_manage_own_connections($db, $u)) llc_json(['error'=>'Forbidden'], 403);

    $st0 = $db->prepare("SELECT 1 FROM connections WHERE id=? AND user_id=?");
    $st0->execute([$id, $uid]);
    if (!$st0->fetchColumn()) throw new RuntimeException('Connection not found');

    $st = $db->prepare("UPDATE connections SET enabled=?, updated_at=? WHERE id=? AND user_id=?");
    $st->execute([$enabled, $now, $id, $uid]);
  }

  // If the selected connection gets disabled, pick another enabled one (or clear).
  $sel = llc_get_setting($db, $uid, 'selected_connection_id') ?? '';
  if ($enabled === 0 && $sel === $id) {
    $first = '';
    foreach (llc_connections_for_user($db, $u, false) as $c) {
      if ((int)($c['enabled'] ?? 1) === 1) { $first = (string)$c['id']; break; }
    }
    llc_set_setting($db, $uid, 'selected_connection_id', $first);
  }

  llc_json(['ok'=>true]);
}


function llc_conn_test(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)($u['id'] ?? '');

  // Only users who can manage connections (own or global) may run tests.
  if (!llc_can_manage_own_connections($db, $u) && !llc_is_superadmin_user($u)) {
    llc_json(['error'=>'Forbidden'], 403);
  }

  $j = llc_read_json();
  $id = trim((string)($j['id'] ?? ''));

  $base_url = trim((string)($j['base_url'] ?? ''));
  $api_key  = (string)($j['api_key'] ?? '');
  $headersRaw = (string)($j['headers'] ?? '');

  // If editing an existing connection, allow falling back to stored values
  // (but still let the caller override fields with unsaved edits).
  if ($id !== '') {
    $row = null;
    if (llc_is_superadmin_user($u)) {
      $stG = $db->prepare("SELECT * FROM global_connections WHERE id=? LIMIT 1");
      $stG->execute([$id]);
      $row = $stG->fetch();
      if (!$row) {
        // fallback: own connection if it exists
        $stO = $db->prepare("SELECT * FROM connections WHERE id=? AND user_id=? LIMIT 1");
        $stO->execute([$id, $uid]);
        $row = $stO->fetch();
      }
    } else {
      $st = $db->prepare("SELECT * FROM connections WHERE id=? AND user_id=? LIMIT 1");
      $st->execute([$id, $uid]);
      $row = $st->fetch();
    }
    if (is_array($row)) {
      if ($base_url === '') $base_url = (string)($row['base_url'] ?? '');
      if ($api_key === '')  $api_key  = (string)($row['api_key'] ?? '');
      if (trim($headersRaw) === '') $headersRaw = (string)($row['headers'] ?? '');
    }
  }

  $base_url = llc_norm_base($base_url);
  if ($base_url === '') {
    llc_json(['ok'=>false,'status'=>'invalid','error'=>'Base URL is missing.'], 200);
  }

  $warnings = [];
  $hints = [];

  // Detect whitespace in API keys (classic copy/paste bug).
  if ($api_key !== '' && preg_match('/\s/', $api_key)) {
    $warnings[] = 'API key contains whitespace (spaces/newlines). This very often leads to 401/403.';
    if ($api_key !== trim($api_key)) $warnings[] = 'API key has leading/trailing whitespace — trim it once.';
  }

  // Parse extra headers (JSON object or newline-separated).
  $extra = [];
  $hasAuth = false;
  $raw = trim($headersRaw);
  if ($raw !== '') {
    $asJson = json_decode($raw, true);
    if (is_array($asJson)) {
      foreach ($asJson as $k=>$v) {
        if (!is_string($k)) continue;
        if (!(is_string($v) || is_numeric($v))) continue;
        $name = trim($k);
        if ($name === '') continue;
        if (strtolower($name) === 'authorization') $hasAuth = true;
        $extra[] = $name . ': ' . (string)$v;
      }
    } else {
      $lines = preg_split('/\r?\n/', $raw);
      foreach ($lines as $line) {
        $line = trim((string)$line);
        if ($line === '' || !str_contains($line, ':')) continue;
        $p = strpos($line, ':');
        $name = strtolower(trim(substr($line, 0, $p)));
        if ($name === 'authorization') $hasAuth = true;
        $extra[] = $line;
      }
    }
  }

  $hdrs = [
    'Accept: application/json',
    'User-Agent: LLC/1.0',
  ];
  if (!$hasAuth && $api_key !== '') {
    $hdrs[] = 'Authorization: Bearer ' . $api_key;
  }
  if (!empty($extra)) $hdrs = array_merge($hdrs, $extra);

  $url = $base_url . '/models';

  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_HTTPGET => true,
    CURLOPT_HTTPHEADER => $hdrs,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HEADER => false,
    CURLOPT_CONNECTTIMEOUT => 10,
    CURLOPT_TIMEOUT => 20,
  ]);
  $body = curl_exec($ch);
  if ($body === false) {
    $err = curl_error($ch);
    curl_close($ch);
    llc_json([
      'ok'=>false,
      'status'=>'curl_error',
      'error'=>'HTTP error: ' . $err,
      'hints'=>[
        'Is the base URL reachable? (DNS/firewall/proxy)',
        'Is the protocol (https://) and the path (/v1) correct?',
      ]
    ], 200);
  }
  $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
  $ct = (string)curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
  curl_close($ch);

  $snippet = (string)$body;
  if (strlen($snippet) > 900) $snippet = substr($snippet, 0, 900) . '…';

  $statusText = '';
  if ($code >= 200 && $code < 300) $statusText = 'success';
  else if ($code === 401) $statusText = 'unauthorized';
  else if ($code === 403) $statusText = 'forbidden';
  else if ($code === 404) $statusText = 'not_found';
  else if ($code === 429) $statusText = 'rate_limited';
  else if ($code >= 500) $statusText = 'server_error';
  else $statusText = 'error';

  // Try to parse JSON error messages.
  $parsed = null;
  if (str_contains(strtolower($ct), 'application/json')) {
    $tmp = json_decode((string)$body, true);
    if (is_array($tmp)) $parsed = $tmp;
  } else {
    $tmp = json_decode((string)$body, true);
    if (is_array($tmp)) $parsed = $tmp;
  }

  if ($code < 200 || $code >= 300) {
    $msg = '';
    if (is_array($parsed)) {
      if (isset($parsed['error'])) {
        if (is_string($parsed['error'])) $msg = $parsed['error'];
        else if (is_array($parsed['error'])) $msg = (string)($parsed['error']['message'] ?? $parsed['error']['error'] ?? $parsed['error']['type'] ?? '');
      }
      if ($msg === '' && isset($parsed['message']) && is_string($parsed['message'])) $msg = $parsed['message'];
    }
    if ($msg === '') $msg = trim((string)$snippet);

    if ($code === 401 || $code === 403) {
      $hints[] = 'Check the API key (whitespace? wrong key? wrong project/account?).';
      $hints[] = 'Some providers require extra headers (e.g., OpenRouter: HTTP-Referer / X-Title).';
    }
    if ($code === 404) {
      $hints[] = 'Check base URL/path: many OpenAI-compatible endpoints expect .../v1 (and then /models).';
    }
    if ($code === 429) {
      $hints[] = 'Rate limit / quota — try again later or use a different key.';
    }

    llc_json([
      'ok'=>false,
      'url'=>$url,
      'http_code'=>$code,
      'status'=>$statusText,
      'error'=>$msg,
      'hints'=>array_values(array_filter(array_merge($warnings ? ['(Note) ' . implode(' | ', $warnings)] : [], $hints))),
      'body_snippet'=>$snippet,
    ], 200);
  }

  // Success path: parse models list.
  $modelsCount = null;
  $sample = [];
  if (is_array($parsed)) {
    if (isset($parsed['data']) && is_array($parsed['data'])) {
      $modelsCount = count($parsed['data']);
      foreach ($parsed['data'] as $it) {
        if (is_array($it) && isset($it['id']) && is_string($it['id'])) $sample[] = $it['id'];
        if (count($sample) >= 8) break;
      }
    } else if (isset($parsed['models']) && is_array($parsed['models'])) {
      $modelsCount = count($parsed['models']);
      foreach ($parsed['models'] as $it) {
        if (is_string($it)) $sample[] = $it;
        else if (is_array($it) && isset($it['id']) && is_string($it['id'])) $sample[] = $it['id'];
        if (count($sample) >= 8) break;
      }
    }
  }

  llc_json([
    'ok'=>true,
    'url'=>$url,
    'http_code'=>$code,
    'status'=>$statusText,
    'models_count'=>$modelsCount,
    'sample_models'=>$sample,
    'warnings'=>$warnings,
  ], 200);
}




// ---------- files ----------

function llc_global_int_setting(PDO $db, string $key, int $default, int $min, int $max): int {
  $raw = llc_get_global_setting($db, $key);
  if ($raw === null || $raw === '') $v = $default;
  else $v = (int)$raw;
  if ($v < $min) $v = $min;
  if ($v > $max) $v = $max;
  return $v;
}

function llc_upload_hard_limit_mb(PDO $db): int {
  return llc_global_int_setting($db, 'upload_hard_limit_mb', 25, 1, 1024);
}

function llc_upload_hard_limit_bytes(PDO $db): int {
  return llc_upload_hard_limit_mb($db) * 1024 * 1024;
}

function llc_media_image_inline_limit_mb(PDO $db): int {
  return llc_global_int_setting($db, 'media_image_inline_limit_mb', 8, 0, 1024);
}

function llc_media_audio_inline_limit_mb(PDO $db): int {
  return llc_global_int_setting($db, 'media_audio_inline_limit_mb', 15, 0, 1024);
}

// ---------- managed code workspaces ----------
function llc_workspace_safe_id(string $id): string {
  $id = trim($id);
  if (!preg_match('/^ws_[a-f0-9]{16}$/', $id)) throw new RuntimeException('Invalid workspace id');
  return $id;
}

function llc_workspace_base_dir(string $workspaceId): string {
  return llc_workspaces_dir() . '/' . llc_workspace_safe_id($workspaceId);
}

function llc_workspace_project_dir(string $workspaceId): string {
  return llc_workspace_base_dir($workspaceId) . '/project';
}

function llc_workspace_snapshots_dir(string $workspaceId): string {
  return llc_workspace_base_dir($workspaceId) . '/snapshots';
}

function llc_workspace_row(PDO $db, array $u, string $workspaceId): array {
  $workspaceId = llc_workspace_safe_id($workspaceId);
  $st = $db->prepare('SELECT id,name,created_at,updated_at FROM workspaces WHERE id=? AND user_id=? LIMIT 1');
  $st->execute([$workspaceId, (string)$u['id']]);
  $row = $st->fetch(PDO::FETCH_ASSOC);
  if (!$row) throw new RuntimeException('Workspace not found');
  return $row;
}

function llc_workspace_clean_name(string $name): string {
  $name = trim(preg_replace('/[\x00-\x1F\x7F]+/u', ' ', $name) ?? $name);
  $name = preg_replace('/\s+/u', ' ', $name) ?? $name;
  if ($name === '') $name = 'Untitled workspace';
  if (function_exists('mb_strlen') && function_exists('mb_substr')) {
    if (mb_strlen($name, 'UTF-8') > 120) $name = mb_substr($name, 0, 120, 'UTF-8');
  } elseif (strlen($name) > 120) {
    $name = substr($name, 0, 120);
  }
  return $name;
}

function llc_workspace_normalize_rel(string $path, bool $allowEmpty = false): string {
  if (str_contains($path, "\0")) throw new RuntimeException('Invalid path');
  $path = trim(str_replace('\\', '/', $path));
  $path = preg_replace('~/+~', '/', $path) ?? $path;
  if ($path === '' || $path === '.') {
    if ($allowEmpty) return '';
    throw new RuntimeException('Missing path');
  }
  if (str_starts_with($path, '/') || preg_match('/^[A-Za-z]:\//', $path)) throw new RuntimeException('Absolute paths are not allowed');
  $parts = [];
  foreach (explode('/', $path) as $part) {
    if ($part === '' || $part === '.') continue;
    if ($part === '..') throw new RuntimeException('Parent path segments are not allowed');
    if (preg_match('/[<>:"|?*\x00-\x1F]/u', $part)) throw new RuntimeException('Path contains characters that are not portable across Windows, macOS and Linux');
    if (str_ends_with($part, '.') || str_ends_with($part, ' ')) throw new RuntimeException('Path segments may not end with a dot or space');
    $baseUpper = strtoupper((string)preg_replace('/\..*$/', '', $part));
    if (preg_match('/^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$/', $baseUpper)) throw new RuntimeException('Path uses a reserved Windows filename');
    if (strlen($part) > 255) throw new RuntimeException('Path segment is too long');
    $parts[] = $part;
  }
  $rel = implode('/', $parts);
  if ($rel === '' && !$allowEmpty) throw new RuntimeException('Missing path');
  if (strlen($rel) > 1200) throw new RuntimeException('Path is too long');
  return $rel;
}

function llc_workspace_path(string $workspaceId, string $rel, bool $allowEmpty = false): string {
  $rel = llc_workspace_normalize_rel($rel, $allowEmpty);
  $root = llc_workspace_project_dir($workspaceId);
  return $rel === '' ? $root : ($root . '/' . $rel);
}

function llc_workspace_assert_no_symlink_path(string $workspaceId, string $rel, bool $includeLeaf = true): void {
  $rel = llc_workspace_normalize_rel($rel, true);
  if ($rel === '') return;
  $cur = llc_workspace_project_dir($workspaceId);
  $parts = explode('/', $rel);
  $last = count($parts) - 1;
  foreach ($parts as $i => $part) {
    if (!$includeLeaf && $i === $last) break;
    $cur .= '/' . $part;
    if (is_link($cur)) throw new RuntimeException('Symbolic links are not allowed in workspaces');
  }
}

function llc_workspace_mkdir_parent(string $workspaceId, string $rel): void {
  llc_workspace_assert_no_symlink_path($workspaceId, $rel, false);
  $dir = dirname(llc_workspace_path($workspaceId, $rel));
  if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) throw new RuntimeException('Could not create parent directory');
  llc_workspace_assert_no_symlink_path($workspaceId, dirname($rel), true);
}

function llc_workspace_remove_tree(string $path): void {
  if ($path === '' || !file_exists($path)) return;
  if (is_link($path) || is_file($path)) { @unlink($path); return; }
  $items = @scandir($path);
  if (is_array($items)) {
    foreach ($items as $item) {
      if ($item === '.' || $item === '..') continue;
      llc_workspace_remove_tree($path . '/' . $item);
    }
  }
  @rmdir($path);
}

function llc_workspace_touch(PDO $db, string $workspaceId): void {
  $st = $db->prepare('UPDATE workspaces SET updated_at=? WHERE id=?');
  $st->execute([llc_now(), $workspaceId]);
}

function llc_workspace_file_count(string $root, int $limit = 10000): int {
  if (!is_dir($root)) return 0;
  $count = 0;
  $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
  foreach ($it as $f) {
    if ($f->isLink() || !$f->isFile()) continue;
    $count++;
    if ($count >= $limit) break;
  }
  return $count;
}

function llc_workspace_list(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $st = $db->prepare('SELECT id,name,created_at,updated_at FROM workspaces WHERE user_id=? ORDER BY updated_at DESC, created_at DESC');
  $st->execute([(string)$u['id']]);
  $items = [];
  foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $row) {
    $id = (string)$row['id'];
    $items[] = [
      'id'=>$id,
      'name'=>(string)$row['name'],
      'created_at'=>(int)$row['created_at'],
      'updated_at'=>(int)$row['updated_at'],
      'file_count'=>llc_workspace_file_count(llc_workspace_project_dir($id), 10000),
    ];
  }
  llc_json(['ok'=>true, 'workspaces'=>$items]);
}

function llc_workspace_create(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $j = llc_read_json();
  $name = llc_workspace_clean_name((string)($j['name'] ?? 'Untitled workspace'));
  $id = llc_id('ws_');
  $base = llc_workspace_base_dir($id);
  $project = $base . '/project';
  $snapshots = $base . '/snapshots';
  if (!mkdir($project, 0775, true) && !is_dir($project)) llc_json(['error'=>'Could not create workspace directory'], 500);
  if (!mkdir($snapshots, 0775, true) && !is_dir($snapshots)) {
    llc_workspace_remove_tree($base);
    llc_json(['error'=>'Could not create workspace snapshot directory'], 500);
  }
  $now = llc_now();
  try {
    $st = $db->prepare('INSERT INTO workspaces(id,user_id,name,created_at,updated_at) VALUES(?,?,?,?,?)');
    $st->execute([$id, (string)$u['id'], $name, $now, $now]);
  } catch (Throwable $e) {
    llc_workspace_remove_tree($base);
    throw $e;
  }
  llc_json(['ok'=>true, 'workspace'=>['id'=>$id,'name'=>$name,'created_at'=>$now,'updated_at'=>$now,'file_count'=>0]]);
}

function llc_workspace_import(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  if (!class_exists('ZipArchive')) llc_json(['error'=>'ZIP support is unavailable in this PHP installation (ZipArchive missing)'], 501);
  if (!isset($_FILES['file']) || !is_array($_FILES['file'])) llc_json(['error'=>'Missing ZIP file'], 400);
  $f = $_FILES['file'];
  if (($f['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) llc_json(['error'=>'ZIP upload failed'], 400);
  $tmp = (string)($f['tmp_name'] ?? '');
  $orig = (string)($f['name'] ?? 'workspace.zip');
  $size = (int)($f['size'] ?? 0);
  if ($size <= 0 || !is_file($tmp)) llc_json(['error'=>'Invalid ZIP upload'], 400);
  if ($size > llc_upload_hard_limit_bytes($db)) llc_json(['error'=>'ZIP file too large'], 413);
  if (strtolower(pathinfo($orig, PATHINFO_EXTENSION)) !== 'zip') llc_json(['error'=>'Only ZIP archives can be imported'], 400);

  $name = llc_workspace_clean_name((string)($_POST['name'] ?? pathinfo($orig, PATHINFO_FILENAME)));
  $id = llc_id('ws_');
  $base = llc_workspace_base_dir($id);
  $project = $base . '/project';
  $snapshots = $base . '/snapshots';
  if (!mkdir($project, 0775, true) && !is_dir($project)) llc_json(['error'=>'Could not create workspace directory'], 500);
  if (!mkdir($snapshots, 0775, true) && !is_dir($snapshots)) {
    llc_workspace_remove_tree($base);
    llc_json(['error'=>'Could not create workspace snapshot directory'], 500);
  }

  $zip = new ZipArchive();
  $open = $zip->open($tmp);
  if ($open !== true) {
    llc_workspace_remove_tree($base);
    llc_json(['error'=>'Could not open ZIP archive'], 400);
  }

  $maxFiles = 5000;
  $maxBytes = 200 * 1024 * 1024;
  $entries = [];
  $totalBytes = 0;
  try {
    if ($zip->numFiles > $maxFiles) throw new RuntimeException('ZIP contains too many entries (5000 max)');
    for ($i=0; $i<$zip->numFiles; $i++) {
      $stat = $zip->statIndex($i);
      if (!is_array($stat)) continue;
      $rawName = (string)($stat['name'] ?? '');
      if ($rawName === '') continue;
      $isDir = str_ends_with(str_replace('\\','/',$rawName), '/');
      $rel = llc_workspace_normalize_rel($rawName, true);
      if ($rel === '') continue;
      $entrySize = max(0, (int)($stat['size'] ?? 0));
      $totalBytes += $entrySize;
      if ($totalBytes > $maxBytes) throw new RuntimeException('ZIP expands beyond the 200 MB workspace limit');
      $entries[] = ['index'=>$i,'name'=>$rawName,'path'=>$rel,'dir'=>$isDir,'size'=>$entrySize];
    }

    // Strip one common top-level directory, as produced by most project ZIP exports.
    $top = null;
    $canStrip = !empty($entries);
    $hasNestedEntry = false;
    foreach ($entries as $e) {
      $parts = explode('/', (string)$e['path']);
      if (count($parts) >= 2) $hasNestedEntry = true;
      if ($top === null) $top = $parts[0];
      elseif ($top !== $parts[0]) { $canStrip = false; break; }
    }
    $canStrip = $canStrip && $hasNestedEntry;
    if ($canStrip && is_string($top) && $top !== '') {
      foreach ($entries as &$e) $e['path'] = substr((string)$e['path'], strlen($top) + 1);
      unset($e);
    }

    $written = 0;
    $actualBytes = 0;
    foreach ($entries as $e) {
      $rel = llc_workspace_normalize_rel((string)$e['path'], true);
      if ($rel === '') continue;
      $dest = llc_workspace_path($id, $rel);
      if (!empty($e['dir'])) {
        if (!is_dir($dest) && !mkdir($dest, 0775, true) && !is_dir($dest)) throw new RuntimeException('Could not create directory: ' . $rel);
        continue;
      }
      llc_workspace_mkdir_parent($id, $rel);
      $in = $zip->getStream((string)$e['name']);
      if (!is_resource($in)) throw new RuntimeException('Could not read ZIP entry: ' . $rel);
      $out = @fopen($dest, 'wb');
      if (!is_resource($out)) { fclose($in); throw new RuntimeException('Could not create file: ' . $rel); }
      $copied = stream_copy_to_stream($in, $out, ($maxBytes - $actualBytes) + 1);
      fclose($in); fclose($out);
      if ($copied === false) throw new RuntimeException('Could not extract file: ' . $rel);
      $actualBytes += (int)$copied;
      if ($actualBytes > $maxBytes) throw new RuntimeException('ZIP expands beyond the 200 MB workspace limit');
      $written++;
    }
    $zip->close();

    $now = llc_now();
    $st = $db->prepare('INSERT INTO workspaces(id,user_id,name,created_at,updated_at) VALUES(?,?,?,?,?)');
    $st->execute([$id, (string)$u['id'], $name, $now, $now]);
    llc_json(['ok'=>true, 'workspace'=>['id'=>$id,'name'=>$name,'created_at'=>$now,'updated_at'=>$now,'file_count'=>$written]]);
  } catch (Throwable $e) {
    try { @$zip->close(); } catch (Throwable $_) { /* already closed */ }
    llc_workspace_remove_tree($base);
    llc_json(['error'=>$e->getMessage()], 400);
  }
}

function llc_workspace_rename(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $j = llc_read_json();
  $id = (string)($j['id'] ?? '');
  llc_workspace_row($db, $u, $id);
  $name = llc_workspace_clean_name((string)($j['name'] ?? ''));
  $now = llc_now();
  $st = $db->prepare('UPDATE workspaces SET name=?, updated_at=? WHERE id=? AND user_id=?');
  $st->execute([$name, $now, $id, (string)$u['id']]);
  llc_json(['ok'=>true, 'workspace'=>['id'=>$id,'name'=>$name,'updated_at'=>$now,'file_count'=>llc_workspace_file_count(llc_workspace_project_dir($id), 10000)]]);
}

function llc_workspace_files(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $id = (string)($_GET['id'] ?? '');
  $row = llc_workspace_row($db, $u, $id);
  $root = llc_workspace_project_dir($id);
  $items = [];
  $maxEntries = 5000;
  if (is_dir($root)) {
    $it = new RecursiveIteratorIterator(
      new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
      RecursiveIteratorIterator::SELF_FIRST
    );
    $rootNorm = rtrim(str_replace('\\','/',$root), '/');
    foreach ($it as $f) {
      if ($f->isLink()) continue;
      $abs = str_replace('\\','/',$f->getPathname());
      $rel = str_starts_with($abs, $rootNorm . '/') ? substr($abs, strlen($rootNorm) + 1) : $f->getFilename();
      $rel = llc_workspace_normalize_rel($rel, true);
      if ($rel === '') continue;
      if ($f->isDir()) {
        $items[] = ['path'=>$rel,'type'=>'directory'];
      } elseif ($f->isFile()) {
        $items[] = [
          'path'=>$rel,
          'type'=>'file',
          'size'=>(int)($f->getSize() ?: 0),
          'modified_at'=>(int)($f->getMTime() ?: 0),
        ];
      }
      if (count($items) >= $maxEntries) break;
    }
  }
  usort($items, static function(array $a, array $b): int {
    if (($a['type'] ?? '') !== ($b['type'] ?? '')) return ($a['type'] ?? '') === 'directory' ? -1 : 1;
    return strnatcasecmp((string)($a['path'] ?? ''), (string)($b['path'] ?? ''));
  });
  llc_json([
    'ok'=>true,
    'workspace'=>['id'=>(string)$row['id'],'name'=>(string)$row['name']],
    'items'=>$items,
    'truncated'=>count($items) >= $maxEntries,
  ]);
}

function llc_workspace_file_create(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $j = llc_read_json();
  $id = (string)($j['id'] ?? '');
  $row = llc_workspace_row($db, $u, $id);
  $rel = llc_workspace_normalize_rel((string)($j['path'] ?? ''));
  llc_workspace_assert_no_symlink_path($id, $rel, true);
  $file = llc_workspace_path($id, $rel);
  if (file_exists($file)) throw new RuntimeException('A file or directory already exists at that path');
  $ctx = ['id'=>$id,'name'=>(string)$row['name'],'access'=>'write','root'=>llc_workspace_project_dir($id)];
  $meta = llc_workspace_write_file($ctx, $rel, (string)($j['content'] ?? ''));
  llc_workspace_touch($db, $id);
  llc_json(['ok'=>true,'path'=>$rel,'created'=>true] + $meta);
}

function llc_workspace_uploaded_files(string $field): array {
  if (!isset($_FILES[$field]) || !is_array($_FILES[$field])) return [];
  $src = $_FILES[$field];
  $names = $src['name'] ?? [];
  if (!is_array($names)) {
    return [[
      'name'=>(string)($src['name'] ?? ''),
      'tmp_name'=>(string)($src['tmp_name'] ?? ''),
      'error'=>(int)($src['error'] ?? UPLOAD_ERR_NO_FILE),
      'size'=>(int)($src['size'] ?? 0),
    ]];
  }
  $out = [];
  foreach ($names as $i=>$name) {
    $out[] = [
      'name'=>(string)$name,
      'tmp_name'=>(string)($src['tmp_name'][$i] ?? ''),
      'error'=>(int)($src['error'][$i] ?? UPLOAD_ERR_NO_FILE),
      'size'=>(int)($src['size'][$i] ?? 0),
    ];
  }
  return $out;
}

function llc_workspace_zip_entry_is_symlink(ZipArchive $zip, int $index): bool {
  if (!method_exists($zip, 'getExternalAttributesIndex')) return false;
  $opsys = 0;
  $attr = 0;
  if (!$zip->getExternalAttributesIndex($index, $opsys, $attr)) return false;
  // Unix file type bits live in the upper 16 bits. 0120000 denotes a symlink.
  return (((int)$attr >> 16) & 0170000) === 0120000;
}

function llc_workspace_zip_entries(ZipArchive $zip): array {
  $entries = [];
  for ($i=0; $i<$zip->numFiles; $i++) {
    $stat = $zip->statIndex($i);
    if (!is_array($stat)) continue;
    $rawName = (string)($stat['name'] ?? '');
    if ($rawName === '') continue;
    if (llc_workspace_zip_entry_is_symlink($zip, $i)) throw new RuntimeException('ZIP archives containing symbolic links are not allowed');
    $normalizedRaw = str_replace('\\','/',$rawName);
    $isDir = str_ends_with($normalizedRaw, '/');
    $rel = llc_workspace_normalize_rel($normalizedRaw, true);
    if ($rel === '') continue;
    $entries[] = [
      'index'=>$i,
      'name'=>$rawName,
      'path'=>$rel,
      'dir'=>$isDir,
      'size'=>max(0, (int)($stat['size'] ?? 0)),
    ];
  }

  // Most project archives contain one wrapper directory. Strip it just as the
  // initial workspace ZIP importer does, so adding project.zip does not create
  // project/project-files unless the archive actually has multiple roots.
  $top = null;
  $canStrip = !empty($entries);
  $hasNestedEntry = false;
  foreach ($entries as $e) {
    $parts = explode('/', (string)$e['path']);
    if (count($parts) >= 2) $hasNestedEntry = true;
    if ($top === null) $top = $parts[0];
    elseif ($top !== $parts[0]) { $canStrip = false; break; }
  }
  $canStrip = $canStrip && $hasNestedEntry;
  if ($canStrip && is_string($top) && $top !== '') {
    foreach ($entries as &$e) $e['path'] = substr((string)$e['path'], strlen($top) + 1);
    unset($e);
  }
  return $entries;
}

function llc_workspace_file_upload(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $id = (string)($_POST['id'] ?? '');
  $row = llc_workspace_row($db, $u, $id);
  $targetDir = llc_workspace_normalize_rel((string)($_POST['target_dir'] ?? ''), true);
  $replace = !empty($_POST['replace']);
  $files = llc_workspace_uploaded_files('files');
  if (!$files) llc_json(['error'=>'No files selected'], 400);
  if (count($files) > 200) llc_json(['error'=>'Too many files selected (200 max)'], 400);

  $hardLimit = llc_upload_hard_limit_bytes($db);
  $maxEntries = 5000;
  $maxExpandedBytes = 200 * 1024 * 1024;
  $uploadedBytes = 0;
  $plannedBytes = 0;
  $archives = [];
  $plan = [];
  $plannedPaths = [];
  $plannedDirs = [];
  $archiveCount = 0;

  $joinTarget = static function(string $base, string $rel): string {
    return ltrim(($base !== '' ? $base . '/' : '') . $rel, '/');
  };
  $claimFile = static function(string $rel) use (&$plannedPaths, &$plannedDirs): void {
    $key = strtolower($rel);
    if (isset($plannedPaths[$key]) || isset($plannedDirs[$key])) throw new RuntimeException('Two selected items have the same destination: ' . $rel);
    foreach ($plannedDirs as $dirKey=>$dirPath) {
      if (str_starts_with($dirKey, $key . '/')) throw new RuntimeException('A file conflicts with a directory destination: ' . $dirPath);
    }
    $plannedPaths[$key] = $rel;
    $parts = explode('/', $rel);
    array_pop($parts);
    $cur = '';
    foreach ($parts as $part) {
      $cur = $cur === '' ? $part : ($cur . '/' . $part);
      $dirKey = strtolower($cur);
      if (isset($plannedPaths[$dirKey])) throw new RuntimeException('A file conflicts with a directory destination: ' . $cur);
      $plannedDirs[$dirKey] = $cur;
    }
  };
  $claimDir = static function(string $rel) use (&$plannedPaths, &$plannedDirs): void {
    if ($rel === '') return;
    $parts = explode('/', $rel);
    $cur = '';
    foreach ($parts as $part) {
      $cur = $cur === '' ? $part : ($cur . '/' . $part);
      $key = strtolower($cur);
      if (isset($plannedPaths[$key])) throw new RuntimeException('A directory conflicts with a file destination: ' . $cur);
      $plannedDirs[$key] = $cur;
    }
  };

  try {
    foreach ($files as $fileIndex=>$f) {
      if ((int)$f['error'] !== UPLOAD_ERR_OK) throw new RuntimeException('One of the uploads failed');
      $tmp = (string)$f['tmp_name'];
      $name = (string)$f['name'];
      $size = (int)$f['size'];
      if ($size < 0 || $size > $hardLimit || !is_uploaded_file($tmp)) throw new RuntimeException('Invalid or oversized uploaded file');
      $uploadedBytes += $size;
      if ($uploadedBytes > $maxExpandedBytes) throw new RuntimeException('Uploads exceed the 200 MB workspace limit');

      $isZip = strtolower(pathinfo($name, PATHINFO_EXTENSION)) === 'zip';
      if (!$isZip) {
        $baseName = llc_workspace_normalize_rel(basename(str_replace('\\','/',$name)));
        $rel = $joinTarget($targetDir, $baseName);
        $claimFile($rel);
        $plannedBytes += $size;
        if ($plannedBytes > $maxExpandedBytes) throw new RuntimeException('Uploads exceed the 200 MB workspace limit');
        $plan[] = ['kind'=>'upload','tmp'=>$tmp,'path'=>$rel,'size'=>$size];
        continue;
      }

      if (!class_exists('ZipArchive')) throw new RuntimeException('ZIP support is unavailable in this PHP installation (ZipArchive missing)');
      $zip = new ZipArchive();
      $opened = $zip->open($tmp);
      if ($opened !== true) throw new RuntimeException('Could not open ZIP archive: ' . $name);
      $archiveIndex = count($archives);
      $archives[] = $zip;
      $archiveCount++;
      $entries = llc_workspace_zip_entries($zip);
      foreach ($entries as $entry) {
        $entryPath = llc_workspace_normalize_rel((string)$entry['path'], true);
        if ($entryPath === '') continue;
        $rel = $joinTarget($targetDir, $entryPath);
        if (!empty($entry['dir'])) {
          $claimDir($rel);
          $plan[] = ['kind'=>'dir','path'=>$rel];
          continue;
        }
        $claimFile($rel);
        $entrySize = max(0, (int)($entry['size'] ?? 0));
        $plannedBytes += $entrySize;
        if ($plannedBytes > $maxExpandedBytes) throw new RuntimeException('ZIP contents expand beyond the 200 MB workspace limit');
        $plan[] = [
          'kind'=>'zip',
          'archive'=>$archiveIndex,
          'entry_name'=>(string)$entry['name'],
          'path'=>$rel,
          'size'=>$entrySize,
        ];
      }
      if (count($plan) > $maxEntries) throw new RuntimeException('Selected archives contain too many entries (5000 max)');
    }

    // Validate all destinations before changing the workspace.
    foreach ($plannedDirs as $dirPath) {
      llc_workspace_assert_no_symlink_path($id, $dirPath, true);
      $dest = llc_workspace_path($id, $dirPath);
      if (file_exists($dest) && !is_dir($dest)) throw new RuntimeException('Directory destination is occupied by a file: ' . $dirPath);
    }
    foreach ($plan as $item) {
      if (($item['kind'] ?? '') === 'dir') continue;
      $rel = (string)$item['path'];
      llc_workspace_assert_no_symlink_path($id, $rel, true);
      $dest = llc_workspace_path($id, $rel);
      if (file_exists($dest) && !is_file($dest)) throw new RuntimeException('Upload destination is not a regular file: ' . $rel);
      if (is_file($dest) && !$replace) throw new RuntimeException('File already exists: ' . $rel);
    }

    $written = [];
    $actualBytes = 0;
    $ctx = ['id'=>$id,'name'=>(string)$row['name'],'access'=>'write','root'=>llc_workspace_project_dir($id)];
    foreach ($plan as $item) {
      $kind = (string)($item['kind'] ?? '');
      $rel = (string)($item['path'] ?? '');
      if ($rel === '') continue;
      if ($kind === 'dir') {
        llc_workspace_assert_no_symlink_path($id, $rel, true);
        $destDir = llc_workspace_path($id, $rel);
        if (!is_dir($destDir) && !mkdir($destDir, 0775, true) && !is_dir($destDir)) throw new RuntimeException('Could not create directory: ' . $rel);
        continue;
      }

      llc_workspace_mkdir_parent($id, $rel);
      $dest = llc_workspace_path($id, $rel);
      $snapshotId = is_file($dest) ? llc_workspace_snapshot_file($ctx, $rel) : null;
      $tempDest = $dest . '.llc_upload_' . bin2hex(random_bytes(4));
      $out = @fopen($tempDest, 'wb');
      if (!is_resource($out)) throw new RuntimeException('Could not write uploaded file: ' . $rel);
      $in = null;
      try {
        if ($kind === 'upload') {
          $in = @fopen((string)$item['tmp'], 'rb');
        } elseif ($kind === 'zip') {
          $zip = $archives[(int)$item['archive']] ?? null;
          if (!$zip instanceof ZipArchive) throw new RuntimeException('ZIP archive is no longer available');
          $in = $zip->getStream((string)$item['entry_name']);
        }
        if (!is_resource($in)) throw new RuntimeException('Could not read uploaded content: ' . $rel);
        $copied = stream_copy_to_stream($in, $out, ($maxExpandedBytes - $actualBytes) + 1);
        if ($copied === false) throw new RuntimeException('Could not copy uploaded content: ' . $rel);
        $actualBytes += (int)$copied;
        if ($actualBytes > $maxExpandedBytes) throw new RuntimeException('Uploaded content exceeds the 200 MB workspace limit');
      } finally {
        if (is_resource($in)) fclose($in);
        fclose($out);
      }
      if (!@rename($tempDest, $dest)) {
        if (is_file($dest) && !@unlink($dest)) { @unlink($tempDest); throw new RuntimeException('Could not replace uploaded file: ' . $rel); }
        if (!@rename($tempDest, $dest)) { @unlink($tempDest); throw new RuntimeException('Could not finalize uploaded file: ' . $rel); }
      }
      $written[] = ['path'=>$rel,'size'=>(int)(@filesize($dest) ?: 0),'snapshot_id'=>$snapshotId];
    }

    foreach ($archives as $zip) { try { $zip->close(); } catch (Throwable $_) {} }
    llc_workspace_touch($db, $id);
    llc_json(['ok'=>true,'files'=>$written,'count'=>count($written),'archives'=>$archiveCount]);
  } catch (Throwable $e) {
    foreach ($archives as $zip) { try { $zip->close(); } catch (Throwable $_) {} }
    llc_json(['error'=>$e->getMessage()], 400);
  }
}

function llc_download_filename_headers(string $filename): void {
  $filename = trim(str_replace(["\r","\n"], '', $filename));
  if ($filename === '') $filename = 'download';
  $fallback = preg_replace('/[^A-Za-z0-9._-]+/', '_', $filename) ?: 'download';
  header('Content-Disposition: attachment; filename="' . $fallback . '"; filename*=UTF-8\'\'' . rawurlencode($filename));
}

function llc_workspace_prune_empty_parents(string $workspaceId, string $rel): void {
  $root = rtrim(llc_workspace_project_dir($workspaceId), '/\\');
  $dir = dirname(llc_workspace_path($workspaceId, $rel));
  while ($dir !== $root && str_starts_with(str_replace('\\','/',$dir) . '/', str_replace('\\','/',$root) . '/')) {
    if (is_link($dir) || !is_dir($dir)) break;
    $items = @scandir($dir);
    if (!is_array($items) || count(array_diff($items, ['.','..'])) > 0) break;
    if (!@rmdir($dir)) break;
    $dir = dirname($dir);
  }
}

function llc_workspace_file_delete(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $j = llc_read_json();
  $id = (string)($j['id'] ?? '');
  $row = llc_workspace_row($db, $u, $id);
  $rel = llc_workspace_normalize_rel((string)($j['path'] ?? ''));
  llc_workspace_assert_no_symlink_path($id, $rel, true);
  $file = llc_workspace_path($id, $rel);
  if (!is_file($file)) llc_json(['error'=>'File not found'], 404);
  $ctx = ['id'=>$id,'name'=>(string)$row['name'],'access'=>'write','root'=>llc_workspace_project_dir($id)];
  $snapshotId = llc_workspace_snapshot_file($ctx, $rel);
  if (!@unlink($file)) throw new RuntimeException('Could not delete file');
  llc_workspace_prune_empty_parents($id, $rel);
  llc_workspace_touch($db, $id);
  llc_json(['ok'=>true,'path'=>$rel,'deleted'=>true,'snapshot_id'=>$snapshotId]);
}

function llc_workspace_file_download(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $id = (string)($_GET['id'] ?? '');
  llc_workspace_row($db, $u, $id);
  $rel = llc_workspace_normalize_rel((string)($_GET['path'] ?? ''));
  llc_workspace_assert_no_symlink_path($id, $rel, true);
  $file = llc_workspace_path($id, $rel);
  if (!is_file($file)) llc_json(['error'=>'File not found'], 404);
  $mime = function_exists('mime_content_type') ? (string)(@mime_content_type($file) ?: '') : '';
  header('Content-Type: ' . ($mime !== '' ? $mime : 'application/octet-stream'));
  header('Content-Length: ' . (string)((int)(@filesize($file) ?: 0)));
  header('Cache-Control: private, no-store');
  llc_download_filename_headers(basename($rel));
  readfile($file);
  exit;
}

function llc_workspace_export(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $id = (string)($_GET['id'] ?? '');
  $row = llc_workspace_row($db, $u, $id);
  if (!class_exists('ZipArchive')) llc_json(['error'=>'ZIP export is unavailable in this PHP installation (ZipArchive missing)'], 501);
  $tmpDir = llc_tmp_dir();
  if (!is_dir($tmpDir) && !mkdir($tmpDir, 0775, true) && !is_dir($tmpDir)) throw new RuntimeException('Could not create temporary export directory');
  $zipPath = $tmpDir . '/workspace_' . bin2hex(random_bytes(8)) . '.zip';
  $zip = new ZipArchive();
  if ($zip->open($zipPath, ZipArchive::CREATE | ZipArchive::OVERWRITE) !== true) throw new RuntimeException('Could not create workspace ZIP');
  $root = llc_workspace_project_dir($id);
  $rootNorm = rtrim(str_replace('\\','/',$root), '/');
  $added = 0;
  try {
    if (is_dir($root)) {
      $it = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::SELF_FIRST
      );
      foreach ($it as $f) {
        if ($f->isLink()) continue;
        $abs = str_replace('\\','/',$f->getPathname());
        $rel = str_starts_with($abs, $rootNorm . '/') ? substr($abs, strlen($rootNorm) + 1) : $f->getFilename();
        $rel = llc_workspace_normalize_rel($rel, true);
        if ($rel === '') continue;
        if ($f->isDir()) $zip->addEmptyDir($rel);
        elseif ($f->isFile()) { if (!$zip->addFile($f->getPathname(), $rel)) throw new RuntimeException('Could not add file to ZIP: ' . $rel); $added++; }
      }
    }
    if (!$zip->close()) throw new RuntimeException('Could not finalize workspace ZIP');
  } catch (Throwable $e) {
    try { @$zip->close(); } catch (Throwable $_) {}
    @unlink($zipPath);
    throw $e;
  }
  $name = llc_workspace_clean_name((string)$row['name']);
  header('Content-Type: application/zip');
  header('Content-Length: ' . (string)((int)(@filesize($zipPath) ?: 0)));
  header('Cache-Control: private, no-store');
  llc_download_filename_headers($name . '.zip');
  readfile($zipPath);
  @unlink($zipPath);
  exit;
}

function llc_workspace_delete(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $j = llc_read_json();
  $id = (string)($j['id'] ?? '');
  llc_workspace_row($db, $u, $id);
  $st = $db->prepare('DELETE FROM workspaces WHERE id=? AND user_id=?');
  $st->execute([$id, (string)$u['id']]);
  llc_workspace_remove_tree(llc_workspace_base_dir($id));
  llc_json(['ok'=>true, 'id'=>$id]);
}

function llc_workspace_context_from_request(PDO $db, array $u, array $j): ?array {
  if (empty($j['webtools']['code_workspace'])) return null;
  $w = (isset($j['workspace']) && is_array($j['workspace'])) ? $j['workspace'] : [];
  $id = trim((string)($w['id'] ?? $j['webtools']['workspace_id'] ?? ''));
  if ($id === '') return null;
  $row = llc_workspace_row($db, $u, $id);
  $access = strtolower(trim((string)($w['access'] ?? $j['webtools']['workspace_access'] ?? 'read')));
  if (!in_array($access, ['read','write'], true)) $access = 'read';
  $strategy = strtolower(trim((string)($w['strategy'] ?? $j['webtools']['workspace_strategy'] ?? 'efficient')));
  if (!in_array($strategy, ['standard','efficient'], true)) $strategy = 'efficient';
  return [
    'id'=>(string)$row['id'],
    'name'=>(string)$row['name'],
    'access'=>$access,
    'strategy'=>$strategy,
    'root'=>llc_workspace_project_dir((string)$row['id']),
  ];
}

function llc_workspace_require_context(?array $ctx, bool $write = false): array {
  if (!$ctx || empty($ctx['id'])) throw new RuntimeException('No active code workspace');
  if ($write && (($ctx['access'] ?? 'read') !== 'write')) throw new RuntimeException('Workspace is read-only for this chat');
  return $ctx;
}

function llc_workspace_is_binary(string $path): bool {
  $h = @fopen($path, 'rb');
  if (!is_resource($h)) return false;
  $sample = fread($h, 4096);
  fclose($h);
  return is_string($sample) && str_contains($sample, "\0");
}

function llc_workspace_glob_match(string $pattern, string $path): bool {
  $pattern = trim(str_replace('\\','/',$pattern));
  if ($pattern === '') return true;
  $target = str_contains($pattern, '/') ? $path : basename($path);
  $rx = preg_quote($pattern, '~');
  $rx = str_replace(['\\*\\*','\\*','\\?'], ['.*','[^/]*','[^/]'], $rx);
  return (bool)preg_match('~^' . $rx . '$~i', $target);
}

function llc_workspace_is_ignored_dir(string $name): bool {
  return in_array(strtolower($name), ['.git','node_modules','vendor','.cache','__pycache__','.venv','venv'], true);
}

function llc_workspace_tree_result(array $ctx, array $args): array {
  $ctx = llc_workspace_require_context($ctx, false);
  $workspaceId = (string)$ctx['id'];
  $rel = llc_workspace_normalize_rel((string)($args['path'] ?? ''), true);
  $depth = max(1, min(12, (int)($args['depth'] ?? 4)));
  $maxEntries = max(1, min(1000, (int)($args['max_entries'] ?? 300)));
  $includeIgnored = !empty($args['include_ignored']);
  $start = llc_workspace_path($workspaceId, $rel, true);
  llc_workspace_assert_no_symlink_path($workspaceId, $rel, true);
  if (!is_dir($start)) throw new RuntimeException('Directory not found: ' . ($rel ?: '.'));
  $items = [];
  $walk = function(string $dir, string $baseRel, int $level) use (&$walk, &$items, $depth, $maxEntries, $includeIgnored): void {
    if ($level > $depth || count($items) >= $maxEntries) return;
    $names = @scandir($dir);
    if (!is_array($names)) return;
    $dirs = []; $files = [];
    foreach ($names as $name) {
      if ($name === '.' || $name === '..') continue;
      $abs = $dir . '/' . $name;
      if (is_link($abs)) continue;
      if (is_dir($abs)) {
        if (!$includeIgnored && llc_workspace_is_ignored_dir($name)) continue;
        $dirs[] = $name;
      } else if (is_file($abs)) $files[] = $name;
    }
    natcasesort($dirs); natcasesort($files);
    foreach (array_merge($dirs, $files) as $name) {
      if (count($items) >= $maxEntries) return;
      $abs = $dir . '/' . $name;
      $itemRel = ltrim($baseRel . '/' . $name, '/');
      if (is_dir($abs)) {
        $items[] = ['path'=>$itemRel,'type'=>'directory'];
        $walk($abs, $itemRel, $level + 1);
      } else {
        $items[] = ['path'=>$itemRel,'type'=>'file','size'=>(int)(@filesize($abs) ?: 0)];
      }
    }
  };
  $walk($start, $rel, 1);
  return ['ok'=>true,'workspace'=>['id'=>$ctx['id'],'name'=>$ctx['name'],'access'=>$ctx['access']], 'path'=>$rel, 'items'=>$items, 'truncated'=>count($items) >= $maxEntries];
}

function llc_workspace_search_result(array $ctx, array $args): array {
  $ctx = llc_workspace_require_context($ctx, false);
  $workspaceId = (string)$ctx['id'];
  $query = (string)($args['query'] ?? '');
  if ($query === '') throw new RuntimeException('workspace_search: missing query');
  $rel = llc_workspace_normalize_rel((string)($args['path'] ?? ''), true);
  $regex = !empty($args['regex']);
  $caseSensitive = !empty($args['case_sensitive']);
  $include = trim((string)($args['include'] ?? ''));
  $maxMatches = max(1, min(300, (int)($args['max_matches'] ?? 80)));
  $includeIgnored = !empty($args['include_ignored']);
  $root = llc_workspace_path($workspaceId, $rel, true);
  llc_workspace_assert_no_symlink_path($workspaceId, $rel, true);
  if (!is_dir($root) && !is_file($root)) throw new RuntimeException('Search path not found');
  $pattern = null;
  if ($regex) {
    $flags = 'u' . ($caseSensitive ? '' : 'i');
    $pattern = '~' . str_replace('~', '\\~', $query) . '~' . $flags;
    if (@preg_match($pattern, '') === false) throw new RuntimeException('Invalid regular expression');
  }
  $matches = [];
  $scanFile = function(string $file, string $fileRel) use (&$matches, $maxMatches, $query, $regex, $caseSensitive, $pattern, $include): void {
    if (count($matches) >= $maxMatches) return;
    if ($include !== '' && !llc_workspace_glob_match($include, $fileRel)) return;
    $size = (int)(@filesize($file) ?: 0);
    if ($size > 5 * 1024 * 1024 || llc_workspace_is_binary($file)) return;
    $h = @fopen($file, 'rb');
    if (!is_resource($h)) return;
    $lineNo = 0;
    while (($line = fgets($h)) !== false) {
      $lineNo++;
      $hit = $regex ? (bool)preg_match($pattern, $line) : ($caseSensitive ? str_contains($line, $query) : stripos($line, $query) !== false);
      if (!$hit) continue;
      $snippet = rtrim($line, "\r\n");
      if (strlen($snippet) > 1200) $snippet = substr($snippet, 0, 1200) . '…';
      $matches[] = ['path'=>$fileRel,'line'=>$lineNo,'text'=>$snippet];
      if (count($matches) >= $maxMatches) break;
    }
    fclose($h);
  };
  if (is_file($root)) {
    $scanFile($root, $rel);
  } else {
    $dirIt = new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS);
    $filterIt = new RecursiveCallbackFilterIterator($dirIt, function($current) use ($includeIgnored) {
      if ($current->isLink()) return false;
      if ($current->isDir() && !$includeIgnored && llc_workspace_is_ignored_dir($current->getFilename())) return false;
      return true;
    });
    $it = new RecursiveIteratorIterator($filterIt);
    $rootNorm = rtrim(str_replace('\\','/',$root), '/');
    foreach ($it as $f) {
      if (count($matches) >= $maxMatches) break;
      if ($f->isLink() || !$f->isFile()) continue;
      $abs = $f->getPathname();
      $absNorm = str_replace('\\','/',$abs);
      $subPath = str_starts_with($absNorm, $rootNorm . '/') ? substr($absNorm, strlen($rootNorm) + 1) : basename($absNorm);
      $fileRel = ltrim($rel . '/' . $subPath, '/');
      $scanFile($abs, $fileRel);
    }
  }
  return ['ok'=>true,'query'=>$query,'regex'=>$regex,'matches'=>$matches,'truncated'=>count($matches) >= $maxMatches];
}

function llc_workspace_read_result(array $ctx, array $args): array {
  $ctx = llc_workspace_require_context($ctx, false);
  $workspaceId = (string)$ctx['id'];
  $rel = llc_workspace_normalize_rel((string)($args['path'] ?? ''));
  llc_workspace_assert_no_symlink_path($workspaceId, $rel, true);
  $file = llc_workspace_path($workspaceId, $rel);
  if (!is_file($file)) throw new RuntimeException('File not found: ' . $rel);
  if (llc_workspace_is_binary($file)) throw new RuntimeException('Binary files cannot be read as text');
  $size = (int)(@filesize($file) ?: 0);
  if ($size > 5 * 1024 * 1024) throw new RuntimeException('File is too large to read (5 MB max)');
  $start = max(1, (int)($args['start_line'] ?? 1));
  $end = max($start, (int)($args['end_line'] ?? ($start + 399)));
  if (($end - $start + 1) > 1000) $end = $start + 999;
  $h = @fopen($file, 'rb');
  if (!is_resource($h)) throw new RuntimeException('Could not read file');
  $lineNo = 0; $lastReturned = 0; $out = []; $outBytes = 0; $truncated = false;
  while (($line = fgets($h)) !== false) {
    $lineNo++;
    if ($lineNo < $start) continue;
    if ($lineNo > $end) { $truncated = true; break; }
    $line = rtrim($line, "\r\n");
    if (strlen($line) > 12000) $line = substr($line, 0, 12000) . '…';
    $rendered = $lineNo . ': ' . $line;
    $out[] = $rendered;
    $outBytes += strlen($rendered) + 1;
    $lastReturned = $lineNo;
    if ($outBytes > 120000) { $truncated = true; break; }
  }
  fclose($h);
  return ['ok'=>true,'path'=>$rel,'start_line'=>$start,'end_line'=>$lastReturned,'sha256'=>hash_file('sha256',$file),'size'=>$size,'content'=>implode("\n",$out),'truncated'=>$truncated];
}

function llc_workspace_prune_snapshots(string $workspaceId, int $keep = 100): void {
  $dir = llc_workspace_snapshots_dir($workspaceId);
  $items = @scandir($dir);
  if (!is_array($items)) return;
  $snaps = [];
  foreach ($items as $item) {
    if (str_starts_with($item, 'snap_') && is_dir($dir . '/' . $item) && !is_link($dir . '/' . $item)) $snaps[] = $item;
  }
  rsort($snaps, SORT_STRING);
  foreach (array_slice($snaps, max(1, $keep)) as $old) llc_workspace_remove_tree($dir . '/' . $old);
}

function llc_workspace_snapshot_file(array $ctx, string $rel): ?string {
  $workspaceId = (string)$ctx['id'];
  $file = llc_workspace_path($workspaceId, $rel);
  if (!is_file($file)) return null;
  $snapId = 'snap_' . gmdate('Ymd_His') . '_' . bin2hex(random_bytes(4));
  $dest = llc_workspace_snapshots_dir($workspaceId) . '/' . $snapId . '/' . $rel;
  $dir = dirname($dest);
  if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) throw new RuntimeException('Could not create workspace snapshot');
  if (!copy($file, $dest)) throw new RuntimeException('Could not create workspace snapshot');
  llc_workspace_prune_snapshots($workspaceId, 100);
  return $snapId;
}

function llc_workspace_write_file(array $ctx, string $rel, string $content): array {
  $workspaceId = (string)$ctx['id'];
  if (strlen($content) > 5 * 1024 * 1024) throw new RuntimeException('Content exceeds the 5 MB file limit');
  llc_workspace_mkdir_parent($workspaceId, $rel);
  $file = llc_workspace_path($workspaceId, $rel);
  $tmp = $file . '.llc_tmp_' . bin2hex(random_bytes(4));
  if (file_put_contents($tmp, $content, LOCK_EX) === false) throw new RuntimeException('Could not write temporary file');
  if (!@rename($tmp, $file)) {
    if (is_file($file) && !@unlink($file)) { @unlink($tmp); throw new RuntimeException('Could not replace file'); }
    if (!@rename($tmp, $file)) { @unlink($tmp); throw new RuntimeException('Could not finalize file write'); }
  }
  return ['sha256'=>hash_file('sha256',$file),'size'=>(int)(@filesize($file) ?: 0)];
}

function llc_workspace_write_result(PDO $db, array $ctx, array $args): array {
  $ctx = llc_workspace_require_context($ctx, true);
  $rel = llc_workspace_normalize_rel((string)($args['path'] ?? ''));
  llc_workspace_assert_no_symlink_path((string)$ctx['id'], $rel, true);
  $file = llc_workspace_path((string)$ctx['id'], $rel);
  $exists = is_file($file);
  if (file_exists($file) && !$exists) throw new RuntimeException('Path is not a regular file');
  if (!$exists && array_key_exists('create', $args) && empty($args['create'])) throw new RuntimeException('File does not exist and create=false');
  $expected = trim((string)($args['expected_sha256'] ?? ''));
  if ($exists && $expected === '') throw new RuntimeException('Read the existing file first and supply expected_sha256 before overwriting it');
  if ($expected !== '') {
    if (!$exists) throw new RuntimeException('expected_sha256 was supplied but the file does not exist');
    $actual = hash_file('sha256',$file);
    if (!hash_equals(strtolower($expected), strtolower($actual))) throw new RuntimeException('File changed since it was read (SHA-256 mismatch)');
  }
  $snapshotId = $exists ? llc_workspace_snapshot_file($ctx, $rel) : null;
  $meta = llc_workspace_write_file($ctx, $rel, (string)($args['content'] ?? ''));
  llc_workspace_touch($db, (string)$ctx['id']);
  return ['ok'=>true,'path'=>$rel,'created'=>!$exists,'snapshot_id'=>$snapshotId] + $meta;
}

function llc_workspace_replace_result(PDO $db, array $ctx, array $args): array {
  $ctx = llc_workspace_require_context($ctx, true);
  $rel = llc_workspace_normalize_rel((string)($args['path'] ?? ''));
  llc_workspace_assert_no_symlink_path((string)$ctx['id'], $rel, true);
  $file = llc_workspace_path((string)$ctx['id'], $rel);
  if (!is_file($file)) throw new RuntimeException('File not found: ' . $rel);
  if (llc_workspace_is_binary($file)) throw new RuntimeException('Binary files cannot be edited as text');
  $size = (int)(@filesize($file) ?: 0);
  if ($size > 5 * 1024 * 1024) throw new RuntimeException('File is too large to edit (5 MB max)');
  $expectedHash = trim((string)($args['expected_sha256'] ?? ''));
  $actualHash = hash_file('sha256',$file);
  if ($expectedHash === '') throw new RuntimeException('Read the file first and supply expected_sha256 before editing it');
  if (!hash_equals(strtolower($expectedHash), strtolower($actualHash))) throw new RuntimeException('File changed since it was read (SHA-256 mismatch)');
  $search = (string)($args['search'] ?? '');
  if ($search === '') throw new RuntimeException('workspace_replace: missing search');
  $replacement = (string)($args['replacement'] ?? '');
  $regex = !empty($args['regex']);
  $expectedCount = (int)($args['expected_replacements'] ?? 0);
  if ($expectedCount < 1 || $expectedCount > 10000) throw new RuntimeException('expected_replacements must be between 1 and 10000');
  $content = file_get_contents($file);
  if (!is_string($content)) throw new RuntimeException('Could not read file');
  $count = 0;
  if ($regex) {
    $pattern = '~' . str_replace('~', '\\~', $search) . '~u';
    if (@preg_match($pattern, '') === false) throw new RuntimeException('Invalid regular expression');
    $next = preg_replace($pattern, $replacement, $content, -1, $count);
    if (!is_string($next)) throw new RuntimeException('Regular expression replacement failed');
  } else {
    $next = str_replace($search, $replacement, $content, $count);
  }
  if ($count !== $expectedCount) throw new RuntimeException('Replacement count mismatch: expected ' . $expectedCount . ', found ' . $count);
  if (!empty($args['dry_run'])) return ['ok'=>true,'path'=>$rel,'dry_run'=>true,'replacements'=>$count,'sha256'=>$actualHash];
  $snapshotId = llc_workspace_snapshot_file($ctx, $rel);
  $meta = llc_workspace_write_file($ctx, $rel, $next);
  llc_workspace_touch($db, (string)$ctx['id']);
  return ['ok'=>true,'path'=>$rel,'replacements'=>$count,'snapshot_id'=>$snapshotId] + $meta;
}

function llc_workspace_delete_result(PDO $db, array $ctx, array $args): array {
  $ctx = llc_workspace_require_context($ctx, true);
  $rel = llc_workspace_normalize_rel((string)($args['path'] ?? ''));
  llc_workspace_assert_no_symlink_path((string)$ctx['id'], $rel, true);
  $file = llc_workspace_path((string)$ctx['id'], $rel);
  if (!is_file($file)) throw new RuntimeException('Only regular files can be deleted in this version');
  $expected = trim((string)($args['expected_sha256'] ?? ''));
  $actual = hash_file('sha256',$file);
  if ($expected === '') throw new RuntimeException('Read the file first and supply expected_sha256 before deleting it');
  if (!hash_equals(strtolower($expected), strtolower($actual))) throw new RuntimeException('File changed since it was read (SHA-256 mismatch)');
  $snapshotId = llc_workspace_snapshot_file($ctx, $rel);
  if (!@unlink($file)) throw new RuntimeException('Could not delete file');
  llc_workspace_touch($db, (string)$ctx['id']);
  return ['ok'=>true,'path'=>$rel,'deleted'=>true,'snapshot_id'=>$snapshotId];
}

function llc_workspace_restore_result(PDO $db, array $ctx, array $args): array {
  $ctx = llc_workspace_require_context($ctx, true);
  $rel = llc_workspace_normalize_rel((string)($args['path'] ?? ''));
  $snapId = trim((string)($args['snapshot_id'] ?? ''));
  if (!preg_match('/^snap_[A-Za-z0-9_]+$/', $snapId)) throw new RuntimeException('Invalid snapshot id');
  $source = llc_workspace_snapshots_dir((string)$ctx['id']) . '/' . $snapId . '/' . $rel;
  if (!is_file($source) || is_link($source)) throw new RuntimeException('Snapshot file not found');
  $currentSnapshot = is_file(llc_workspace_path((string)$ctx['id'], $rel)) ? llc_workspace_snapshot_file($ctx, $rel) : null;
  $content = file_get_contents($source);
  if (!is_string($content)) throw new RuntimeException('Could not read snapshot');
  $meta = llc_workspace_write_file($ctx, $rel, $content);
  llc_workspace_touch($db, (string)$ctx['id']);
  return ['ok'=>true,'path'=>$rel,'restored_from'=>$snapId,'previous_snapshot_id'=>$currentSnapshot] + $meta;
}


function llc_file_upload(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  if (!isset($_FILES['file'])) llc_json(['error'=>'missing file'], 400);
  $f = $_FILES['file'];
  if (!is_array($f) || !isset($f['tmp_name'])) llc_json(['error'=>'invalid upload'], 400);
  if ($f['error'] !== UPLOAD_ERR_OK) llc_json(['error'=>'upload error'], 400);

  $orig = (string)$f['name'];
  $size = (int)$f['size'];
  $tmp = (string)$f['tmp_name'];
  $maxUploadMb = llc_upload_hard_limit_mb($db);
  if ($size > ($maxUploadMb * 1024 * 1024)) llc_json(['error'=>'file too large (' . $maxUploadMb . 'MB max)'], 413);

  $mime = mime_content_type($tmp) ?: 'application/octet-stream';
  $ext = preg_replace('/[^a-zA-Z0-9]/','', pathinfo($orig, PATHINFO_EXTENSION));
  $id = llc_id('f_');
  $stored = $id . ($ext ? '.'.strtolower($ext) : '');
  if (preg_match('/\.(php|phtml|phar)$/i', $stored)) $stored .= '.bin';

  $dir = llc_uploads_dir();
  if (!is_dir($dir)) mkdir($dir, 0775, true);

  $dest = $dir . '/' . $stored;
  if (!move_uploaded_file($tmp, $dest)) llc_json(['error'=>'failed to store file'], 500);

  $isImg = str_starts_with($mime,'image/');
  $isAudio = str_starts_with($mime,'audio/') || in_array(strtolower((string)$ext), ['mp3','wav','m4a','aac','ogg','oga','opus','flac','webm'], true);
  $isPdf = ($mime === 'application/pdf' || strtolower($ext) === 'pdf');
  $isDocx = ($mime === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' || strtolower($ext) === 'docx');
  $isOdt = ($mime === 'application/vnd.oasis.opendocument.text' || strtolower($ext) === 'odt');
  $isXlsx = ($mime === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' || strtolower($ext) === 'xlsx');
  $isOds = ($mime === 'application/vnd.oasis.opendocument.spreadsheet' || strtolower($ext) === 'ods');
  $isCsv = (str_starts_with($mime, 'text/') && strtolower($ext) === 'csv') || ($mime === 'text/csv' || strtolower($ext) === 'csv');

  $extractedText = '';
  $extractErr = '';
  $pdfDeleted = false;
  if ($isPdf) {
    try { $extractedText = llc_pdf_extract_text($dest); }
    catch (Throwable $e) { $extractErr = $e->getMessage(); }
  } elseif ($isDocx || $isOdt) {
    try {
      require_once __DIR__ . '/plugins/doc2txt/doc2txt.php';
      $eext = strtolower((string)$ext);
      if ($eext === '') $eext = $isDocx ? 'docx' : ($isOdt ? 'odt' : $eext);
      $extractedText = llc_doc2txt_extract($dest, $eext);
      // Keep paragraph breaks / line breaks. If the extraction ends up as one huge line,
      // reflow it gently so both UI preview and the model get readable structure.
      $extractedText = llc_text_reflow_if_single_line($extractedText);
    } catch (Throwable $e) {
      $extractErr = $e->getMessage();
    }
  } elseif ($isXlsx || $isOds || $isCsv) {
    try {
      require_once __DIR__ . '/plugins/sheet2txt/sheet2txt.php';
      $eext = strtolower((string)$ext);
      if ($eext === '') $eext = $isXlsx ? 'xlsx' : ($isOds ? 'ods' : ($isCsv ? 'csv' : $eext));
      $extractedText = llc_sheet2txt_extract($dest, $eext);
    } catch (Throwable $e) {
      $extractErr = $e->getMessage();
    }
  }

  $st = $db->prepare("INSERT INTO files (id,user_id,original_name,stored_name,mime,size,created_at) VALUES (?,?,?,?,?,?,?)");
  $st->execute([$id,$uid,$orig,$stored,$mime,$size,llc_now()]);
  $url = llc_base_url() . '/uploads/' . rawurlencode($stored);

  llc_json([
    'id'=>$id,
    'name'=>$orig,
    'stored'=>$stored,
    'mime'=>$mime,
    'size'=>$size,
    'url'=>$url,
    'is_image'=>$isImg,
    'is_audio'=>$isAudio,
    'is_pdf'=>$isPdf,
    'is_docx'=>$isDocx,
    'is_odt'=>$isOdt,
    'is_xlsx'=>$isXlsx,
    'is_ods'=>$isOds,
    'is_csv'=>$isCsv,
    'extracted_text'=>$extractedText,
    'extracted_truncated'=>false,
    'extract_error'=>$extractErr,
    'pdf_deleted'=>$pdfDeleted
  ]);
}



function llc_file_delete(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $j = llc_read_json();
  $id = (string)($j['id'] ?? '');
  if (trim($id) === '') llc_json(['error'=>'missing id'], 400);

  $st = $db->prepare("SELECT stored_name FROM files WHERE id=? AND user_id=?");
  $st->execute([$id, $uid]);
  $row = $st->fetch(PDO::FETCH_ASSOC);
  if (!$row) llc_json(['error'=>'file not found'], 404);

  $stored = (string)($row['stored_name'] ?? '');
  if (!preg_match('/^[a-zA-Z0-9_\-\.]+$/', $stored)) llc_json(['error'=>'invalid stored_name'], 400);

  $path = llc_uploads_dir() . '/' . $stored;
  $deleted = false;
  if (is_file($path)) $deleted = @unlink($path);
  else $deleted = true;

  $st2 = $db->prepare("DELETE FROM files WHERE id=? AND user_id=?");
  $st2->execute([$id, $uid]);

  llc_json(['ok'=>true,'deleted'=>$deleted,'id'=>$id]);
}


// ---------- PDF text extraction (Smalot/pdfparser) ----------
// PDFs frequently have *no real line breaks* in their text layer. To avoid the
// "everything glued together" effect we:
// - preserve any existing \n\n / \n
// - de-hyphenate line-break hyphenation
// - gently reflow single-line blobs with word-wrap (so UI preview + LLM have structure)
function llc_text_norm_keep_breaks(string $text): string {
  if (!is_string($text) || $text === '') return '';

  // Normalize line endings
  $text = str_replace("\r\n", "\n", $text);
  $text = str_replace("\r", "\n", $text);

  // Normalize common "invisible" whitespace
  $text = str_replace("\xC2\xA0", ' ', $text); // NBSP
  $text = preg_replace('/[\x{200B}-\x{200D}\x{FEFF}]/u', '', $text);

  // Fix hyphenation at line breaks: "Beispiel-\nwort" -> "Beispielwort"
  $text = preg_replace('/([[:alpha:]])-\n([[:alpha:]])/u', '$1$2', $text);

  // Trim trailing whitespace on lines
  $text = preg_replace("~[ \t]+\n~", "\n", $text);

  // Collapse huge empty gaps
  $text = preg_replace("~\n{3,}~", "\n\n", $text);

  return trim((string)$text);
}

function llc_text_reflow_if_single_line(string $text, int $width = 100): string {
  $t = llc_text_norm_keep_breaks($text);
  if ($t === '') return '';

  $nl = substr_count($t, "\n");
  // If it's basically one gigantic line, insert soft wraps.
  if ($nl === 0 && strlen($t) > ($width * 2)) {
    $t = wordwrap($t, $width, "\n", false);
    return llc_text_norm_keep_breaks($t);
  }

  // If there are line breaks but some lines are extremely long, wrap those lines.
  if ($nl > 0) {
    $lines = explode("\n", $t);
    $out = [];
    foreach ($lines as $ln) {
      $ln = (string)$ln;
      if (strlen($ln) > ($width * 2)) $out[] = wordwrap($ln, $width, "\n", false);
      else $out[] = $ln;
    }
    $t = implode("\n", $out);
    $t = llc_text_norm_keep_breaks($t);
  }

  return $t;
}

function llc_pdf_extract_text(string $filePath): string {
  // Strategy order (robustness > elegance):
  // 1) Smalot/pdfparser (pure PHP) if available and functioning
  // 2) pdftotext (poppler-utils) if available
  // 3) last-resort naive string scan (best-effort)

  $best = '';

  // 1) Smalot/pdfparser
  // Some environments don't have ext-xml; pdfparser needs xml_parser_create().
  if (function_exists('xml_parser_create')) {
    try {
      $autoload = __DIR__ . '/plugins/pdfparser/alt_autoload.php-dist';
      if (!class_exists('\\Smalot\\PdfParser\\Parser', false)) {
        if (is_file($autoload)) require_once $autoload;
      }
      if (class_exists('\\Smalot\\PdfParser\\Parser', false)) {
        $parser = new \Smalot\PdfParser\Parser();
        $pdf = $parser->parseFile($filePath);

        // Prefer per-page text (often has better implicit breaks) and add clear page separators.
        $pages = null;
        if (is_object($pdf) && method_exists($pdf, 'getPages')) {
          try { $pages = $pdf->getPages(); } catch (Throwable $_) { $pages = null; }
        }

        if (is_array($pages) && count($pages) > 0) {
          $out = [];
          $total = count($pages);
          foreach ($pages as $i => $p) {
            $pt = '';
            if (is_object($p) && method_exists($p, 'getText')) {
              try { $pt = (string)$p->getText(); } catch (Throwable $_) { $pt = ''; }
            }
            $pt = llc_text_reflow_if_single_line($pt);
            if ($pt === '') continue;
            if ($total > 1) {
              $out[] = "=== Page " . ($i+1) . "/" . $total . " ===\n" . $pt;
            } else {
              $out[] = $pt;
            }
          }
          if (count($out) > 0) {
            $best = llc_text_reflow_if_single_line(implode("\n\n", $out));
          }
        }

        if ($best === '' && is_object($pdf) && method_exists($pdf, 'getText')) {
          $t = $pdf->getText();
          if (!is_string($t)) $t = '';
          $t = llc_text_reflow_if_single_line($t);
          if ($t !== '') $best = $t;
        }
      }
    } catch (Throwable $_) {
      // ignore and fall through
    }
  }

  // 2) pdftotext fallback (often succeeds when PHP parsers fail)
  $t2 = llc_pdf_extract_pdftotext($filePath);
  if ($t2 !== '' && strlen($t2) > strlen($best)) $best = $t2;

  // 3) last-resort naive scan
  if ($best === '') {
    $t3 = llc_pdf_extract_naive_strings($filePath);
    if ($t3 !== '') $best = $t3;
  }

  return llc_text_reflow_if_single_line($best);
}

// Use poppler's pdftotext if present (no server config needed if binary exists).
function llc_pdf_extract_pdftotext(string $filePath): string {
  $bin = 'pdftotext';
  $which = @shell_exec('command -v ' . escapeshellarg($bin) . ' 2>/dev/null');
  if (!is_string($which) || trim($which) === '') return '';
  if (!is_file($filePath)) return '';

  $cmd = $bin . ' -layout -enc UTF-8 -nopgbrk ' . escapeshellarg($filePath) . ' -';
  $out = @shell_exec($cmd . ' 2>/dev/null');
  if (!is_string($out)) return '';
  $out = llc_text_norm_keep_breaks($out);
  return $out;
}

// Very naive, last-resort extraction: looks for Tj/TJ string operands and decodes escapes.
function llc_pdf_extract_naive_strings(string $filePath): string {
  if (!is_file($filePath)) return '';
  $bin = @file_get_contents($filePath);
  if (!is_string($bin) || $bin === '') return '';
  // Avoid huge memory spikes
  if (strlen($bin) > 12 * 1024 * 1024) $bin = substr($bin, 0, 12 * 1024 * 1024);

  $parts = [];
  // (....) Tj
  if (preg_match_all('/\(((?:\\\\.|[^\\)]){1,2000})\)\s*Tj/s', $bin, $m)) {
    foreach ($m[1] as $s) $parts[] = llc_pdf_unescape_string($s);
  }
  // [(....) 120 (....)] TJ
  if (preg_match_all('/\[((?:\s*\((?:\\\\.|[^\\)]){1,2000}\)\s*[-0-9.]+\s*)+)\]\s*TJ/s', $bin, $m2)) {
    foreach ($m2[1] as $arr) {
      if (preg_match_all('/\((?:\\\\.|[^\\)]){1,2000}\)/s', $arr, $sm)) {
        foreach ($sm[0] as $tok) {
          $tok = substr($tok, 1, -1);
          $parts[] = llc_pdf_unescape_string($tok);
        }
      }
    }
  }
  $txt = trim(implode("\n", array_filter($parts, fn($x) => trim((string)$x) !== '')));
  if ($txt === '') return '';
  return llc_text_norm_keep_breaks($txt);
}

function llc_pdf_unescape_string(string $s): string {
  // octal escapes
  $s = preg_replace_callback('/\\\\([0-7]{1,3})/', function($m){
    $v = intval($m[1], 8);
    return chr($v);
  }, $s);
  $map = [
    '\\\\n' => "\n",
    '\\\\r' => "\r",
    '\\\\t' => "\t",
    '\\\\b' => "\x08",
    '\\\\f' => "\x0C",
    '\\\\(' => '(',
    '\\\\)' => ')',
    '\\\\\\\\' => '\\',
  ];
  $s = strtr($s, $map);
  return $s;
}


// ---------- vision helpers ----------
function llc_mime_from_filename(string $name): string {
  $n = strtolower($name);
  if (str_ends_with($n, '.png')) return 'image/png';
  if (str_ends_with($n, '.jpg') || str_ends_with($n, '.jpeg')) return 'image/jpeg';
  if (str_ends_with($n, '.webp')) return 'image/webp';
  if (str_ends_with($n, '.gif')) return 'image/gif';
  if (str_ends_with($n, '.mp3')) return 'audio/mpeg';
  if (str_ends_with($n, '.wav')) return 'audio/wav';
  if (str_ends_with($n, '.m4a')) return 'audio/mp4';
  if (str_ends_with($n, '.aac')) return 'audio/aac';
  if (str_ends_with($n, '.ogg') || str_ends_with($n, '.oga')) return 'audio/ogg';
  if (str_ends_with($n, '.opus')) return 'audio/opus';
  if (str_ends_with($n, '.flac')) return 'audio/flac';
  if (str_ends_with($n, '.webm')) return 'audio/webm';
  return '';
}

function llc_try_data_url_from_attachment(array $a): string {
  if (!empty($a['data_url']) && is_string($a['data_url'])) return (string)$a['data_url'];
  $u = (!empty($a['url']) && is_string($a['url'])) ? (string)$a['url'] : '';
  if ($u === '') return '';
  $path = parse_url($u, PHP_URL_PATH);
  if (!is_string($path) || $path === '') return '';
  if (strpos($path, '/uploads/') === false) return '';
  $fname = basename($path);
  if ($fname === '') return '';
  $file = llc_uploads_dir() . '/' . $fname;
  if (!is_file($file)) return '';
  $sz = @filesize($file);
  if (!is_int($sz) || $sz <= 0) return '';
  // Uploaded images are capped by the configured hard limit; allow stored-only images to be re-encoded on demand.
  if ($sz > llc_upload_hard_limit_bytes(llc_db())) return '';
  $bin = @file_get_contents($file);
  if (!is_string($bin) || $bin === '') return '';
  $mime = '';
  if (!empty($a['mime']) && is_string($a['mime'])) $mime = (string)$a['mime'];
  if ($mime === '') $mime = llc_mime_from_filename($fname);
  if ($mime === '') $mime = 'image/png';
  return 'data:' . $mime . ';base64,' . base64_encode($bin);
}


function llc_audio_format_from_attachment(array $a, string $dataUrl = ''): string {
  $fmt = '';
  if (!empty($a['format']) && is_string($a['format'])) $fmt = strtolower((string)$a['format']);
  if ($fmt === '') {
    $name = strtolower((string)($a['name'] ?? ''));
    $ext = strtolower((string)pathinfo($name, PATHINFO_EXTENSION));
    if (in_array($ext, ['mp3','wav','m4a','aac','ogg','oga','opus','flac','webm'], true)) $fmt = ($ext === 'oga') ? 'ogg' : $ext;
  }
  if ($fmt === '') {
    $mime = strtolower((string)($a['mime'] ?? ''));
    if (str_contains($mime, 'mpeg') || str_contains($mime, 'mp3')) $fmt = 'mp3';
    elseif (str_contains($mime, 'wav')) $fmt = 'wav';
    elseif (str_contains($mime, 'mp4') || str_contains($mime, 'm4a')) $fmt = 'm4a';
    elseif (str_contains($mime, 'aac')) $fmt = 'aac';
    elseif (str_contains($mime, 'ogg')) $fmt = 'ogg';
    elseif (str_contains($mime, 'opus')) $fmt = 'opus';
    elseif (str_contains($mime, 'flac')) $fmt = 'flac';
    elseif (str_contains($mime, 'webm')) $fmt = 'webm';
  }
  if ($fmt === '' && preg_match('~^data:audio/([^;]+);base64,~i', $dataUrl, $m)) {
    $fmt = strtolower((string)$m[1]);
    if ($fmt === 'mpeg') $fmt = 'mp3';
    if ($fmt === 'mp4') $fmt = 'm4a';
  }
  return preg_replace('/[^a-z0-9_-]/', '', $fmt ?: 'mp3');
}

function llc_audio_base64_from_data_url(string $dataUrl): string {
  if (preg_match('~^data:audio/[^;]+;base64,(.*)$~is', $dataUrl, $m)) {
    return preg_replace('/\s+/', '', (string)$m[1]);
  }
  return '';
}

function llc_try_audio_data_url_from_attachment(array $a): string {
  if (!empty($a['data_url']) && is_string($a['data_url'])) return (string)$a['data_url'];
  $u = (!empty($a['url']) && is_string($a['url'])) ? (string)$a['url'] : '';
  if ($u === '') return '';
  $path = parse_url($u, PHP_URL_PATH);
  if (!is_string($path) || $path === '') return '';
  if (strpos($path, '/uploads/') === false) return '';
  $fname = basename($path);
  if ($fname === '') return '';
  $file = llc_uploads_dir() . '/' . $fname;
  if (!is_file($file)) return '';
  $sz = @filesize($file);
  if (!is_int($sz) || $sz <= 0) return '';
  // Uploaded audio is capped by the configured hard limit; allow stored-only audio to be re-encoded on demand.
  if ($sz > llc_upload_hard_limit_bytes(llc_db())) return '';
  $bin = @file_get_contents($file);
  if (!is_string($bin) || $bin === '') return '';
  $mime = '';
  if (!empty($a['mime']) && is_string($a['mime'])) $mime = (string)$a['mime'];
  if ($mime === '') $mime = llc_mime_from_filename($fname);
  if ($mime === '') $mime = 'audio/mpeg';
  return 'data:' . $mime . ';base64,' . base64_encode($bin);
}


/**
 * Convert message content into plain text for system-message merging.
 * OpenAI-compatible backends differ in how strict they are, and Qwen 3.5/3.6
 * rejects any system message that is not the first chat-template item. This
 * helper lets us safely fold all system instructions into a single leading
 * string message while leaving normal user/assistant/tool messages untouched.
 */
function llc_system_content_to_text($content): string {
  if (is_string($content)) return $content;
  if ($content === null) return '';
  if (is_array($content)) {
    $parts = [];
    foreach ($content as $part) {
      if (is_string($part)) { $parts[] = $part; continue; }
      if (!is_array($part)) continue;
      $type = (string)($part['type'] ?? '');
      if (($type === 'text' || $type === 'input_text') && isset($part['text'])) {
        $parts[] = (string)$part['text'];
      }
    }
    return trim(implode("\n", array_filter($parts, fn($x) => trim((string)$x) !== '')));
  }
  $json = json_encode($content, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
  return is_string($json) ? $json : '';
}

/**
 * Make messages compatible with strict chat templates (notably Qwen 3.5/3.6):
 * exactly one system message at index 0, never anywhere else. Any additional
 * system instructions are merged into that first message in their original
 * order. Non-system messages keep their relative order and content shape.
 */
function llc_messages_single_front_system(array $messages, string $extraSystem = ''): array {
  $systemParts = [];
  $out = [];

  foreach ($messages as $m) {
    if (!is_array($m)) continue;
    $role = (string)($m['role'] ?? '');
    if ($role === 'system') {
      $txt = trim(llc_system_content_to_text($m['content'] ?? ''));
      if ($txt !== '') $systemParts[] = $txt;
      continue;
    }
    if ($role === '') continue;
    $out[] = $m;
  }

  $extraSystem = trim($extraSystem);
  if ($extraSystem !== '') $systemParts[] = $extraSystem;

  if (!empty($systemParts)) {
    $merged = trim(implode("\n\n", $systemParts));
    if ($merged !== '') array_unshift($out, ['role'=>'system','content'=>$merged]);
  }

  return $out;
}

// ---------- SSE streaming proxy ----------
function llc_chat_stream(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];
  $j = llc_read_json();

  $toolsEnabled = llc_tools_enabled($j);

  // Long-running streaming request (model load + prompt processing can take minutes).
  // Prevent PHP timeouts and ensure streaming buffers are disabled.
  @ignore_user_abort(true);
  @set_time_limit(0);
  @ini_set('output_buffering', 'off');
  @ini_set('zlib.output_compression', '0');
  @ini_set('implicit_flush', '1');
  if (function_exists('apache_setenv')) {
    @apache_setenv('no-gzip', '1');
  }
  while (ob_get_level() > 0) { @ob_end_flush(); }
  @ob_implicit_flush(true);

  $connId = (string)($j['connection_id'] ?? (llc_get_setting($db, $uid, 'selected_connection_id') ?? ''));
  $conn = $connId ? llc_conn_by_id($db, $u, $connId) : null;
  if (!$conn) { llc_sse_error('No active connection. Add one in Settings → Connections.'); return; }

  $model = (string)($j['model'] ?? (llc_get_setting($db, $uid, 'selected_model') ?? ''));
  if ($model === '') $model = 'gpt-4o-mini';
  $model = llc_strip_model_prefix($model, $conn);

  $system = (string)($j['system_prompt'] ?? '');
  $params = $j['params'] ?? [];
  if (!is_array($params)) $params = [];

  $messages = $j['messages'] ?? [];
  if (!is_array($messages)) $messages = [];
  $documentState = $j['document'] ?? [];
  if (!is_array($documentState)) $documentState = [];
  $documentMode = (!empty($j['webtools']['document']) || (($documentState['mode'] ?? '') === 'document'));
  $workspaceContext = null;
  $workspaceError = '';
  if (!empty($j['webtools']['code_workspace'])) {
    try { $workspaceContext = llc_workspace_context_from_request($db, $u, $j); }
    catch (Throwable $e) { $workspaceError = $e->getMessage(); }
  }


  // IMPORTANT: Attachments must stay bound to the message they were uploaded/generated with.
  // We do NOT auto-attach images from elsewhere in the thread to other messages.

  // Split inline <think>...</think> blocks out of normal content during streaming.
  // Some providers embed thinking in-band.
  $inThink = false;
  $thinkCarry = '';

  // Build OpenAI messages + multimodal parts for images
  $anyImageInHistory = false;
  $hasLastImage = false;
  $lastMsgIndex = is_array($messages) ? (count($messages) - 1) : -1;
  $oa = [];
  if (trim($system) !== '') $oa[] = ['role'=>'system','content'=>$system];

  foreach ($messages as $mi=>$m){
    if (!is_array($m)) continue;
    $role = (string)($m['role'] ?? '');
    if (!in_array($role, ['user','assistant','system'], true)) continue;

    $content = $m['content'] ?? '';
    $atts = $m['attachments'] ?? [];
    if (!is_array($atts)) $atts = [];

    // Debug / introspection: track whether there are images anywhere in the chat history.
    $hasImgHere = false;
    foreach ($atts as $__aa) {
      if (is_array($__aa) && ((string)($__aa['type'] ?? '')) === 'image') { $hasImgHere = true; break; }
    }
    if ($hasImgHere) {
      $anyImageInHistory = true;
      if ($mi === $lastMsgIndex) $hasLastImage = true;
    }


    // Build multimodal parts whenever this message has attachments.
    // Keep the original role; images belong to the message they were attached to.
    if ($role !== 'system' && count($atts) > 0) {
      $parts = [];
      if (is_string($content) && trim($content) !== '') $parts[] = ['type'=>'text','text'=>$content];
      foreach ($atts as $a){
        if (!is_array($a)) continue;
        $type = (string)($a['type'] ?? '');
        if ($type === 'image') {
          // IMPORTANT: do NOT clobber the authenticated user context variable ($u).
          // llc_chat_stream() uses $u (array) for user settings / tool execution. If we
          // overwrite it with a string URL here, tool calls will crash only when images
          // exist anywhere in the message history.
          $imgUrl = '';
          if (!empty($a['data_url']) && is_string($a['data_url'])) $imgUrl = $a['data_url'];
          else {
            $du = llc_try_data_url_from_attachment($a);
            if ($du !== '') $imgUrl = $du;
            elseif (!empty($a['url']) && is_string($a['url'])) $imgUrl = $a['url'];
          }
          if ($imgUrl !== '') $parts[] = ['type'=>'image_url','image_url'=>['url'=>(string)$imgUrl]];
        }
        elseif ($type === 'audio') {
          $audioUrl = '';
          if (!empty($a['data_url']) && is_string($a['data_url'])) $audioUrl = (string)$a['data_url'];
          else {
            $du = llc_try_audio_data_url_from_attachment($a);
            if ($du !== '') $audioUrl = $du;
            elseif (!empty($a['url']) && is_string($a['url'])) $audioUrl = (string)$a['url'];
          }

          if ($audioUrl !== '') {
            $b64 = llc_audio_base64_from_data_url($audioUrl);
            if ($b64 !== '') {
              // OpenAI-compatible native audio input. vLLM and recent multimodal servers understand this;
              // current llama.cpp/libmtmd builds route audio through their OpenAI-compatible multimodal path.
              $parts[] = ['type'=>'input_audio','input_audio'=>[
                'data'=>$b64,
                'format'=>llc_audio_format_from_attachment($a, $audioUrl)
              ]];
            } else {
              $parts[] = ['type'=>'audio_url','audio_url'=>['url'=>$audioUrl]];
            }
          } elseif (!empty($a['name'])) {
            $parts[] = ['type'=>'text','text'=>'Audio attached: ' . (string)$a['name'] . ' (not processed)'];
          }
        }
        elseif (in_array($type, ['text','textfile','file_text'], true) && !empty($a['text']) && is_string($a['text'])) {
          $name = (string)($a['name'] ?? 'text');
          $mime = (string)($a['mime'] ?? 'text/plain');
          $txt = (string)$a['text'];
          $src = (!empty($a['url']) && is_string($a['url'])) ? (string)$a['url'] : '';
          $prefix = "File: {$name} ({$mime})" . ($src!=='' ? "\nSource: {$src}" : '') . "\n\n";
          $parts[] = ['type'=>'text','text'=>$prefix . $txt];
        }
        elseif ($type === 'url' && !empty($a['url'])) $parts[] = ['type'=>'text','text'=>"Link: " . (string)$a['url']];
        elseif ($type === 'note' && !empty($a['text'])) $parts[] = ['type'=>'text','text'=>"Note: " . (string)$a['text']];
        elseif (($type === 'file' || $type === 'image' || $type === 'audio') && !empty($a['name'])) {
          $name = (string)$a['name'];
          $mime = (string)($a['mime'] ?? '');
          // If it's a PDF/binary placeholder, be explicit.
          if ($mime === 'application/pdf' || str_ends_with(strtolower($name), '.pdf')) {
            $parts[] = ['type'=>'text','text'=>"PDF attached: {$name} (not processed yet)"];
          } else {
            $parts[] = ['type'=>'text','text'=>"Attachment: {$name} (not processed)"];
          }
        }
      }
      if (count($parts) === 0) $parts[] = ['type'=>'text','text'=>'(empty)'];
      $oa[] = ['role'=>$role,'content'=>$parts];
    } else {
      $oa[] = ['role'=>$role,'content'=>$content];
    }
  }
  if ($documentMode) {
    if (!isset($documentState['documents']) || !is_array($documentState['documents'])) $documentState['documents'] = [];
    if (empty($documentState['documents']) && isset($documentState['active']) && is_array($documentState['active'])) {
      $a = $documentState['active'];
      $aid = (string)($a['id'] ?? 'active');
      $a['id'] = $aid;
      $documentState['documents'][$aid] = $a;
      $documentState['active_id'] = (string)($documentState['active_id'] ?? $documentState['activeId'] ?? $aid);
    }
    $activeId = (string)($documentState['active_id'] ?? $documentState['activeId'] ?? '');
    $docs = $documentState['documents'];
    $activeDoc = ($activeId !== '' && isset($docs[$activeId]) && is_array($docs[$activeId])) ? $docs[$activeId] : null;
    if (!$activeDoc && !empty($docs)) {
      $firstKey = array_key_first($docs);
      $activeId = (string)$firstKey;
      $activeDoc = is_array($docs[$firstKey]) ? $docs[$firstKey] : null;
    }
    $docLines = [];
    foreach ($docs as $did => $d) {
      if (!is_array($d)) continue;
      $mark = ((string)($d['id'] ?? $did) === $activeId) ? '*' : '-';
      $docLines[] = $mark . ' id=' . (string)($d['id'] ?? $did) . ', title=' . (string)($d['title'] ?? 'Untitled document') . ', type=' . (string)($d['type'] ?? 'markdown') . ', version=' . (string)($d['version'] ?? '1');
    }
    $docListText = empty($docLines) ? 'none' : implode("\n", $docLines);
    $docTitle = $activeDoc ? (string)($activeDoc['title'] ?? 'Untitled document') : 'none';
    $docType = $activeDoc ? (string)($activeDoc['type'] ?? 'markdown') : 'markdown';
    $docVer = $activeDoc ? (string)($activeDoc['version'] ?? '0') : '0';
    $docContent = $activeDoc ? (string)($activeDoc['content'] ?? '') : '';
    if (strlen($docContent) > 60000) $docContent = substr($docContent, -60000);
    $docInstruction = "Document mode is active. You can manage multiple persistent documents in this chat. Use document_create for every new file/document. Use document_update with document_id when editing a specific existing document, or omit document_id to edit the active document. Use document_select when the user asks to switch the active document. Do not paste the full document into the chat unless the user asks for it.\n\nDOCUMENTS:\n{$docListText}\n\nACTIVE_DOCUMENT: id={$activeId}, title={$docTitle}, type={$docType}, version={$docVer}.\n\nACTIVE_DOCUMENT_CONTENT:\n" . $docContent;
    $oa[] = ['role'=>'system','content'=>$docInstruction];
  }
  if (!empty($j['webtools']['code_workspace'])) {
    if ($workspaceContext) {
      $wsName = (string)($workspaceContext['name'] ?? 'Workspace');
      $wsAccess = (string)($workspaceContext['access'] ?? 'read');
      $wsStrategy = (string)($workspaceContext['strategy'] ?? 'efficient');
      $wsInstruction = "A managed code workspace is active: {$wsName}. Access: {$wsAccess}. The project files are not included in the prompt. Inspect them step by step with workspace_tree, workspace_search and workspace_read. Do not claim to have inspected or changed files unless the corresponding tool succeeded. For targeted edits prefer workspace_replace; use workspace_write mainly for new files or complete rewrites.";
      if ($wsStrategy === 'efficient') {
        $wsInstruction .= "\n\nTOOL STRATEGY: EFFICIENT\nUse as little workspace context as possible, but as much as is needed for a reliable result. Choose the smallest reliable sequence of tool calls rather than following a rigid rule.\n\nWhen the request concerns identifiable text, an HTML tag, a function or class, a variable, a configuration key, a filename, or an error message, normally use workspace_search first. Do not read a complete file merely to locate something that search can find.\n\nFor a local, unambiguous change, inspect only enough context to make the edit safely. If the file and exact old text are already known, a narrow workspace_read may be used to obtain the current hash, followed by workspace_replace. If the target is not yet known, search first, then read only the smallest useful range if context or a current hash is needed. A request to modify a file is not by itself a reason to read the whole file.\n\nUse broader reads, including a complete file when appropriate, if the file is small or the task genuinely requires understanding its overall structure, syntax, interactions, or behavior. After editing, verify the result from the tool response or with a narrow search/read. Do not inspect unrelated files, and stop once the user's request has been completed.";
      }
      $oa[] = ['role'=>'system','content'=>$wsInstruction];
    } else {
      $oa[] = ['role'=>'system','content'=>'Code workspace was enabled but is unavailable: ' . ($workspaceError !== '' ? $workspaceError : 'no workspace selected')];
    }
  }

  // Qwen 3.5/3.6 and other strict templates require system messages to appear
  // only at the beginning. Normalize once after importing chat history so any
  // system messages stored in the conversation cannot break downstream calls.
  $oa = llc_messages_single_front_system($oa);

$payload = array_merge([
    'model'=>$model,
    'messages'=>$oa,
    'stream'=>true,
    'stream_options'=>['include_usage'=>true]
  ], $params);

  $url = llc_norm_base((string)$conn['base_url']) . '/chat/completions';

  $hdrs = [
    'Content-Type: application/json',
    'Accept: text/event-stream',
  ];
  $key = (string)($conn['api_key'] ?? '');
  if (trim($key) !== '') $hdrs[] = 'Authorization: Bearer ' . $key;
  if (!empty($conn['headers'])) $hdrs = array_merge($hdrs, llc_custom_headers((string)$conn['headers']));

  header('Content-Type: text/event-stream; charset=utf-8');
  header('Cache-Control: no-cache');
  header('Connection: keep-alive');
  header('X-Accel-Buffering: no');

  // Send an initial byte immediately so browsers/proxies don't consider the connection idle.
  llc_sse_send(['type'=>'ping']);

  // ---------- tool calling path (non-stream upstream + SSE to client) ----------
  if ($toolsEnabled) {
    $tools = llc_tools_for_request(!empty($j['webtools']['web']), !empty($j['webtools']['search']), !empty($j['webtools']['image']), !empty($j['webtools']['document']), !empty($j['webtools']['code_workspace']), (string)($workspaceContext['access'] ?? 'read'));
    $customEnabled = (isset($j['webtools']['custom_tools']) && is_array($j['webtools']['custom_tools'])) ? $j['webtools']['custom_tools'] : [];
    $customTools = llc_custom_tools_openai($db, $u, $customEnabled);
    if (!empty($customTools)) $tools = array_merge($tools, $customTools);

    // Use JSON responses for tool-loop upstream calls.
    $hdrsJson = [];
    foreach ($hdrs as $h) {
      if (stripos($h, 'Accept:') === 0) continue;
      $hdrsJson[] = $h;
    }
    $hdrsJson[] = 'Accept: application/json';

    // Light hint so the model actually uses the tool when needed.
    $hintParts = [];
    if (!empty($j['webtools']['search'])) $hintParts[] = "For finding sources, call web_search({q, type}).";
    if (!empty($j['webtools']['web'])) $hintParts[] = "For reading the content behind a link, call web_read({url}).";
    if (!empty($j['webtools']['document'])) $hintParts[] = "In Document mode, call document_create({title,type,content}) for new documents and document_update({document_id,title,type,content,summary}) for edits. The document_update content must be the full updated document, not a diff. Use document_select({document_id}) to switch active documents. Use document_history, document_get_version, and document_revert when the user wants to inspect, compare, undo, or restore old document versions.";
    if (!empty($j['webtools']['code_workspace'])) {
      if (($workspaceContext['strategy'] ?? 'efficient') === 'efficient') {
        $hintParts[] = "A code workspace is active in efficient mode. Use the smallest reliable tool sequence: as little context as possible, but as much as needed for correctness. Search to locate identifiable text; use narrow reads for local context or the current file hash; read more broadly only when the task genuinely requires whole-file understanding. A requested edit alone is not a reason to read the entire file.";
      } else {
        $hintParts[] = "A code workspace is active. Navigate it incrementally with workspace_tree, workspace_search and workspace_read. Use write tools only when needed and report which files were actually changed.";
      }
    }
    if (!empty($customTools)) $hintParts[] = "Custom tools are enabled in this chat. Use them when they directly match the user's request.";
    if (!empty($j['webtools']['image'])) {
      $imgProvider = (string)(llc_image_cfg_get($db, $u, 'image_provider') ?? 'openai');
      if ($imgProvider === 'comfyui') {
        $hintParts[] = "If the user asks for an image, call image_generate({prompt}). For ComfyUI: only pass steps/guidance/seed/width/height/batch_size if the user explicitly requested them. Do NOT pass size/quality/background/output_format for ComfyUI.";
      } elseif ($imgProvider === 'sdcpp' || $imgProvider === 'stable-diffusion.cpp' || $imgProvider === 'stable_diffusion_cpp') {
        $hintParts[] = "If the user asks for an image, call image_generate. For stable-diffusion.cpp, if the user asks for image generation, call image_generate. You MUST pass explicit generation directives as structured args: 768x768 -> size:'768x768' plus width:768,height:768; '5 steps' -> steps:5; seed -> seed; CFG/guidance -> guidance or cfg_scale; batch/n -> batch_size or n; negative prompt -> negative_prompt. Do not leave these directives only in prompt.";
      } else {
        $hintParts[] = "If the user asks for an image, call image_generate({prompt}).";
      }
    }
    $toolHint = "Use tools when helpful. " . implode(' ', $hintParts) . " If a tool returns {ok:false}, you must show the exact error message to the user (do not replace it with vague statements).";
    $workMessages = llc_messages_single_front_system($oa, $toolHint);

    $maxIters = 10;
    try {
      $mi = llc_get_global_setting($db, 'tool_max_iters');
      $miN = (int)($mi === null || $mi === '' ? 10 : $mi);
      if ($miN < 1) $miN = 1;
      if ($miN > 50) $miN = 50;
      $maxIters = $miN;
    } catch (Throwable $_) { /* noop */ }
    for ($iter=0; $iter<$maxIters; $iter++) {
      $p = array_merge([
        'model' => $model,
        'messages' => $workMessages,
        'stream' => false,
        'tools' => $tools,
        'tool_choice' => 'auto',
      ], $params);

      try {
        if (llc_dbg_enabled()) {
          $payloadBytes = 0;
          $enc = json_encode($p, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
          if (is_string($enc)) $payloadBytes = strlen($enc);
          $anyImg = false;
          foreach (($p['messages'] ?? []) as $__mm) {
            if (is_array($__mm) && is_array($__mm['content'] ?? null)) {
              foreach (($__mm['content'] ?? []) as $__pp) {
                if (is_array($__pp) && (($__pp['type'] ?? '') === 'image_url')) { $anyImg = true; break 2; }
              }
            }
          }
          llc_dbg_log('tool_iter', [
            'iter' => $iter,
            'url' => $url,
            'model' => $model,
            'messages' => is_array($p['messages'] ?? null) ? count($p['messages']) : 0,
            'any_image' => $anyImg,
            'payload_bytes' => $payloadBytes,
          ]);
          unset($enc, $payloadBytes, $anyImg);
        }

        $resp = llc_http_post_json_keepalive($url, $hdrsJson, $p, 15.0);
      } catch (Throwable $e) {
        llc_sse_error($e->getMessage());
        return;
      }

      $choice0 = $resp['choices'][0] ?? null;
      $msg = (is_array($choice0) ? ($choice0['message'] ?? null) : null);
      if (!is_array($msg)) {
        llc_sse_error('Upstream returned no message');
        return;
      }

      $toolCalls = llc_extract_tool_calls($msg);
      if (llc_dbg_enabled()) {
        $finish = is_array($choice0) ? (string)($choice0['finish_reason'] ?? '') : '';
        $names = [];
        foreach ($toolCalls as $__tc) {
          if (is_array($__tc)) {
            $fnx = $__tc['function'] ?? null;
            if (is_array($fnx) && !empty($fnx['name'])) $names[] = (string)$fnx['name'];
          }
        }
        $hasContent = (!empty($msg['content']) && is_string($msg['content']));
        llc_dbg_log('tool_model_reply', [
          'iter' => $iter,
          'finish_reason' => $finish,
          'tool_calls' => $names,
          'assistant_has_content' => $hasContent,
        ]);
        unset($finish, $names, $hasContent);
      }
      if (!empty($toolCalls)) {
        // Append assistant tool-call message.
        $workMessages[] = $msg;
        foreach ($toolCalls as $tc) {
          if (!is_array($tc)) continue;
          try {
            $workMessages[] = llc_execute_tool_call($db, $u, $tc, true, $documentState, $workMessages, $workspaceContext);
          } catch (Throwable $e) {
            llc_dbg_log('tool_exec_error', ['iter'=>$iter, 'error'=>$e->getMessage()]);
            llc_sse_error('Tool execution failed: ' . $e->getMessage());
            return;
          }
        }
        continue;
      }

      // No tool calls: do the *final* answer as a real streaming request.
      // This keeps UX consistent (token streaming), while still allowing tool-usage upfront.
      $finalMessages = llc_messages_single_front_system($workMessages, 'Now answer the user. Do not call tools.');

      $finalPayload = array_merge([
        'model' => $model,
        'messages' => $finalMessages,
        'stream' => true,
        'stream_options' => ['include_usage' => true],
      ], $params);

      // Important: omit tools here for maximum compatibility across OpenAI-compatible backends.
      llc_stream_upstream_to_sse($url, $hdrs, $finalPayload);
      exit;
    }

    llc_sse_error('Tool loop exceeded max iterations');
    return;
  }

  // Normal path: stream upstream directly.
  llc_stream_upstream_to_sse($url, $hdrs, $payload);
  exit;
}

/**
 * Stream an OpenAI-compatible upstream SSE response and forward it to our client SSE format.
 * Also keeps the client connection alive with pings.
 */
function llc_stream_upstream_to_sse(string $url, array $hdrs, array $payload): void {
  // Split inline <think>...</think> blocks out of normal content during streaming.
  $inThink = false;
  $thinkCarry = '';

  // Track whether we already emitted a terminal 'done' event.
  $ended = false;
  $lastPingAt = microtime(true);
  $lastUpstreamAt = microtime(true);

  // We emit these once per assistant message (typically from the final upstream chunk).
  $statsSent = false;

  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => $hdrs,
    CURLOPT_POSTFIELDS => json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES),
    CURLOPT_RETURNTRANSFER => false,
    CURLOPT_HEADER => false,
    CURLOPT_TIMEOUT => 0,
    CURLOPT_CONNECTTIMEOUT => 20,
  ]);

  $buf = '';
  curl_setopt($ch, CURLOPT_WRITEFUNCTION, function($ch, $data) use (&$buf, &$inThink, &$thinkCarry, &$ended, &$lastUpstreamAt, &$statsSent) {
    if (connection_aborted()) return 0;
    $lastUpstreamAt = microtime(true);
    $buf .= $data;

    while (true) {
      $pos = strpos($buf, "\n");
      if ($pos === false) break;
      $line = trim(substr($buf, 0, $pos));
      $buf = substr($buf, $pos + 1);

      if ($line === '' || !str_starts_with($line, 'data:')) continue;
      $payload = trim(substr($line, 5));
      if ($payload === '[DONE]') {
        if ($thinkCarry !== '') {
          llc_sse_send(['type'=>($inThink?'reasoning':'content'),'delta'=>$thinkCarry]);
          $thinkCarry = '';
        }
        if (!$ended) {
          $ended = true;
          llc_sse_send(['type'=>'done']);
        }
        continue;
      }

      $j = json_decode($payload, true);
      if (!is_array($j)) continue;

      // Forward upstream usage/timings (llama.cpp etc.) once we see them.
      // Many backends only provide these in the *final* chunk.
      if (!$statsSent) {
        $stats = llc_extract_upstream_speed_stats($j);
        if (is_array($stats)) {
          $statsSent = true;
          llc_sse_send($stats);
        }
      }

      $choice0 = $j['choices'][0] ?? null;
      $delta = (is_array($choice0) ? ($choice0['delta'] ?? null) : null);
      $msg = (is_array($choice0) ? ($choice0['message'] ?? null) : null);
      if (!is_array($msg)) $msg = ($j['message'] ?? null);

      if (is_array($delta)) {
        foreach (['reasoning','reasoning_content'] as $rk) {
          if (isset($delta[$rk]) && is_string($delta[$rk]) && $delta[$rk] !== '') {
            llc_sse_send(['type'=>'reasoning','delta'=>$delta[$rk]]);
          }
        }
      }
      if (is_array($msg)) {
        foreach (['reasoning','reasoning_content'] as $rk) {
          if (isset($msg[$rk]) && is_string($msg[$rk]) && $msg[$rk] !== '') {
            llc_sse_send(['type'=>'reasoning','delta'=>$msg[$rk]]);
          }
        }
      }

      $contentChunk = null;
      if (is_array($delta) && isset($delta['content']) && is_string($delta['content']) && $delta['content'] !== '') {
        $contentChunk = $delta['content'];
      } elseif (is_array($msg) && isset($msg['content']) && is_string($msg['content']) && $msg['content'] !== '') {
        $contentChunk = $msg['content'];
      }

      if (is_string($contentChunk) && $contentChunk !== '') {
        $parts = llc_split_think_stream($contentChunk, $inThink, $thinkCarry);
        if (!empty($parts['reasoning'])) llc_sse_send(['type'=>'reasoning','delta'=>$parts['reasoning']]);
        if (!empty($parts['content'])) llc_sse_send(['type'=>'content','delta'=>$parts['content']]);
      }
    }

    @ob_flush(); @flush();
    return strlen($data);
  });

  $mh = curl_multi_init();
  curl_multi_add_handle($mh, $ch);
  $active = null;

  do {
    do {
      $mrc = curl_multi_exec($mh, $active);
    } while ($mrc === CURLM_CALL_MULTI_PERFORM);

    $now = microtime(true);
    if (($now - $lastPingAt) >= 15.0) {
      llc_sse_send(['type'=>'ping']);
      $lastPingAt = $now;
    }

    if (connection_aborted()) {
      break;
    }

    if ($active) curl_multi_select($mh, 1.0);
  } while ($active && $mrc === CURLM_OK);

  $curlErr = curl_error($ch);
  $curlErrNo = curl_errno($ch);
  $httpCode = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);

  curl_multi_remove_handle($mh, $ch);
  curl_multi_close($mh);
  curl_close($ch);

  if (connection_aborted()) exit;

  if ($curlErrNo !== 0) llc_sse_error('Upstream error: ' . ($curlErr ?: ('cURL errno ' . $curlErrNo)));
  if ($httpCode !== 0 && ($httpCode < 200 || $httpCode >= 300)) llc_sse_error('Upstream HTTP ' . $httpCode);

  if ($thinkCarry !== '') {
    llc_sse_send(['type'=>($inThink?'reasoning':'content'),'delta'=>$thinkCarry]);
    $thinkCarry = '';
  }
  if (!$ended) llc_sse_send(['type'=>'done']);
}

function llc_sse_send(array $obj): void {
  $payload = json_encode($obj, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
  if ($payload === false) $payload = '{"type":"error","error":"json_encode failed"}';

  // Use explicit \n to avoid platform-specific line endings in the SSE framing.
  echo "data: " . $payload . "\n\n";

  // Some reverse proxies buffer tiny chunks (especially before the main token stream starts).
  // Send a comment padding line for status/ping so the UI gets immediate feedback.
  $t = (string)($obj['type'] ?? '');
  if ($t === 'status' || $t === 'ping' || $t === 'attachment') {
    echo ":" . str_repeat(' ', 2048) . "\n\n";
  }

  @ob_flush(); @flush();
}



/**
 * Extract prompt/generation speed stats from various OpenAI-compatible backends.
 * - llama.cpp typically returns {timings:{prompt_per_second,predicted_per_second,prompt_n,prompt_ms,predicted_n,predicted_ms}}
 * - Some servers only return token counts (usage / completion_token, etc.)
 *
 * Returns an SSE payload: {type:"stats", prompt_tps?, gen_tps?, prompt_tokens?, completion_tokens?, total_tokens?}
 */
function llc_extract_upstream_speed_stats(array $j): ?array {
  $tim = (isset($j['timings']) && is_array($j['timings'])) ? $j['timings'] : null;

  // llama.cpp sometimes exposes the same fields top-level (not nested under "timings").
  // Example keys: prompt_n, prompt_ms, prompt_per_second, predicted_n, predicted_ms, predicted_per_second.
  if ($tim === null) {
    $maybe = [];
    foreach (['prompt_n','prompt_ms','prompt_per_second','predicted_n','predicted_ms','predicted_per_second'] as $k) {
      if (array_key_exists($k, $j)) $maybe[$k] = $j[$k];
    }
    if (!empty($maybe)) $tim = $maybe;
  }

  $usage = null;
  if (isset($j['usage']) && is_array($j['usage'])) $usage = $j['usage'];

  // Normalize token counts
  $pt = null; $ct = null; $tt = null;

  $pickInt = function($arr, array $keys) {
    foreach ($keys as $k) {
      if (is_array($arr) && isset($arr[$k]) && is_numeric($arr[$k])) return (int)$arr[$k];
    }
    return null;
  };

  if (is_array($usage)) {
    $pt = $pickInt($usage, ['prompt_tokens','prompt_token','input_tokens','input_token']);
    $ct = $pickInt($usage, ['completion_tokens','completion_token','output_tokens','output_token','completion_token_count','output_token_count']);
    $tt = $pickInt($usage, ['total_tokens','total_token']);
    if ($tt === null && $pt !== null && $ct !== null) $tt = $pt + $ct;
  } else {
    $pt = $pickInt($j, ['prompt_tokens','prompt_token','input_tokens','input_token']);
    $ct = $pickInt($j, ['completion_tokens','completion_token','output_tokens','output_token','completion_token_count','output_token_count']);
    $tt = $pickInt($j, ['total_tokens','total_token']);
    if ($tt === null && $pt !== null && $ct !== null) $tt = $pt + $ct;
  }

  // If usage is missing, llama.cpp may expose counts top-level too.
  if ($pt === null && isset($j['prompt_n']) && is_numeric($j['prompt_n'])) $pt = (int)$j['prompt_n'];
  if ($ct === null && isset($j['predicted_n']) && is_numeric($j['predicted_n'])) $ct = (int)$j['predicted_n'];
  if ($tt === null && $pt !== null && $ct !== null) $tt = $pt + $ct;

  // Normalize timings into tok/s
  $promptTps = null; $genTps = null;
  if (is_array($tim)) {
    if (isset($tim['prompt_per_second']) && is_numeric($tim['prompt_per_second'])) {
      $promptTps = (float)$tim['prompt_per_second'];
    } elseif (isset($tim['prompt_n'], $tim['prompt_ms']) && is_numeric($tim['prompt_n']) && is_numeric($tim['prompt_ms']) && (float)$tim['prompt_ms'] > 0) {
      $promptTps = ((float)$tim['prompt_n']) / (((float)$tim['prompt_ms']) / 1000.0);
    }

    if (isset($tim['predicted_per_second']) && is_numeric($tim['predicted_per_second'])) {
      $genTps = (float)$tim['predicted_per_second'];
    } elseif (isset($tim['predicted_n'], $tim['predicted_ms']) && is_numeric($tim['predicted_n']) && is_numeric($tim['predicted_ms']) && (float)$tim['predicted_ms'] > 0) {
      $genTps = ((float)$tim['predicted_n']) / (((float)$tim['predicted_ms']) / 1000.0);
    }

    // If usage didn't include counts, llama.cpp timings can.
    if ($pt === null && isset($tim['prompt_n']) && is_numeric($tim['prompt_n'])) $pt = (int)$tim['prompt_n'];
    if ($ct === null && isset($tim['predicted_n']) && is_numeric($tim['predicted_n'])) $ct = (int)$tim['predicted_n'];
    if ($tt === null && $pt !== null && $ct !== null) $tt = $pt + $ct;
  }

  if ($promptTps === null && $genTps === null && $pt === null && $ct === null && $tt === null) return null;

  $out = ['type' => 'stats'];
  if ($promptTps !== null) $out['prompt_tps'] = $promptTps;
  if ($genTps !== null) $out['gen_tps'] = $genTps;
  if ($pt !== null) $out['prompt_tokens'] = $pt;
  if ($ct !== null) $out['completion_tokens'] = $ct;
  if ($tt !== null) $out['total_tokens'] = $tt;

  return $out;
}

/**
 * Streaming-safe splitter for inline <think>...</think> blocks.
 * Returns ['content'=>string,'reasoning'=>string]. Keeps state across calls.
 */
function llc_split_think_stream(string $chunk, bool &$inThink, string &$carry): array {
  $open = '<think>';
  $close = '</think>';
  $s = $carry . $chunk;
  $carry = '';

  $outC = '';
  $outR = '';
  $i = 0;
  $n = strlen($s);
  $openKeep = max(0, strlen($open) - 1);
  $closeKeep = max(0, strlen($close) - 1);

  while ($i < $n) {
    if (!$inThink) {
      $pos = strpos($s, $open, $i);
      if ($pos === false) {
        $tail = substr($s, $i);
        [$emit, $carryPart] = llc_utf8_split_keep($tail, $openKeep);
        $outC .= $emit;
        $carry = $carryPart;
        break;
      }
      $outC .= substr($s, $i, $pos - $i);
      $i = $pos + strlen($open);
      $inThink = true;
    } else {
      $pos = strpos($s, $close, $i);
      if ($pos === false) {
        $tail = substr($s, $i);
        [$emit, $carryPart] = llc_utf8_split_keep($tail, $closeKeep);
        $outR .= $emit;
        $carry = $carryPart;
        break;
      }
      $outR .= substr($s, $i, $pos - $i);
      $i = $pos + strlen($close);
      $inThink = false;
    }
  }

  return ['content'=>$outC, 'reasoning'=>$outR];
}


/**
 * Split a string into [emit, carry] keeping at most $keep bytes in carry,
 * but never starting carry on a UTF-8 continuation byte (prevents invalid UTF-8 chunks).
 */
function llc_utf8_split_keep(string $s, int $keep): array {
  if ($keep <= 0) return [$s, ''];
  $len = strlen($s);
  if ($len <= $keep) return ['', $s];
  $cut = $len - $keep;
  // Move cut backward until we land on a UTF-8 leading byte (or ASCII).
  while ($cut > 0) {
    $b = ord($s[$cut]);
    if (($b & 0xC0) !== 0x80) break; // not a continuation byte
    $cut--;
  }
  if ($cut <= 0) return ['', $s];
  return [substr($s, 0, $cut), substr($s, $cut)];
}

function llc_sse_error(string $msg): void {
  llc_dbg_log('sse_error', ['error'=>$msg]);
  header('Content-Type: text/event-stream; charset=utf-8');
  header('Cache-Control: no-cache');
  echo "data: " . json_encode(['type'=>'error','error'=>$msg], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES) . "\n\n";
  echo "data: " . json_encode(['type'=>'done'], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES) . "\n\n";
  @ob_flush(); @flush();
  exit;
}


// ---------- voice ----------
function llc_voice_transcribe(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $key = llc_voice_cfg_get($db, $u, 'voice_api_key') ?? '';
  if (trim($key) === '') llc_json(['error'=>'Voice API key missing (Settings → Voice)'], 400);

  if (empty($_FILES) || !isset($_FILES['audio'])) llc_json(['error'=>'Missing audio file'], 400);
  $f = $_FILES['audio'];
  if (!is_array($f) || ($f['error'] ?? UPLOAD_ERR_OK) !== UPLOAD_ERR_OK) {
    $code = is_array($f) ? (int)($f['error'] ?? 0) : 0;
    llc_json(['error'=>'Upload failed (code '.$code.')'], 400);
  }
  $size = (int)($f['size'] ?? 0);
  if ($size <= 0) llc_json(['error'=>'Empty audio'], 400);
  // Keep it sane: 25MB
  if ($size > 25*1024*1024) llc_json(['error'=>'Audio too large (max 25MB)'], 413);
  $tmp = (string)($f['tmp_name'] ?? '');
  if ($tmp === '' || !is_uploaded_file($tmp)) llc_json(['error'=>'Invalid upload'], 400);
  $name = (string)($f['name'] ?? 'audio');
  $mime = (string)($f['type'] ?? 'application/octet-stream');

  $url = 'https://api.openai.com/v1/audio/transcriptions';
  $ch = curl_init($url);
  $post = [
    'model' => 'whisper-1',
    'response_format' => 'json',
    'file' => new CURLFile($tmp, $mime, $name)
  ];
  curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POSTFIELDS => $post,
    CURLOPT_HTTPHEADER => [
      'Authorization: Bearer ' . $key
    ],
    CURLOPT_TIMEOUT => 120,
  ]);
  $raw = curl_exec($ch);
  $err = curl_error($ch);
  $errno = curl_errno($ch);
  $http = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
  curl_close($ch);
  if ($errno !== 0) llc_json(['error'=>'Upstream error: '.($err?:('cURL '.$errno))], 502);
  if ($http < 200 || $http >= 300) {
    $msg = 'Upstream HTTP ' . $http;
    if (is_string($raw) && $raw !== '') {
      $j = json_decode($raw, true);
      if (is_array($j) && isset($j['error']['message'])) $msg .= ' — ' . (string)$j['error']['message'];
    }
    llc_json(['error'=>$msg], 502);
  }
  $j = json_decode((string)$raw, true);
  if (!is_array($j)) llc_json(['error'=>'Invalid upstream response'], 502);
  $text = (string)($j['text'] ?? '');
  llc_json(['text'=>$text]);
}

function llc_voice_speech(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $key = llc_voice_cfg_get($db, $u, 'voice_api_key') ?? '';
  if (trim($key) === '') llc_json(['error'=>'Voice API key missing (Settings → Voice)'], 400);

  $j = llc_read_json();
  $input = trim((string)($j['input'] ?? ''));
  if ($input === '') llc_json(['error'=>'Missing field: input'], 400);

  // OpenAI Speech endpoint limit is 4096 characters.
  if (strlen($input) > 4096) llc_json(['error'=>'Text too long for speech (max 4096 chars).'], 400);

  $voice = trim((string)($j['voice'] ?? ''));
  if ($voice === '') {
    $voice = llc_voice_cfg_get($db, $u, 'voice_tts_voice') ?? 'marin';
  }

  // Allow-list built-in voices (custom voice objects are not supported in this simple endpoint).
  $allowed = ['alloy','ash','ballad','coral','echo','fable','nova','onyx','sage','shimmer','verse','marin','cedar'];
  if (!in_array($voice, $allowed, true)) $voice = 'marin';


  $model = trim((string)($j['model'] ?? ''));
  if ($model === '') {
    $model = llc_voice_cfg_get($db, $u, 'voice_tts_model') ?? 'gpt-4o-mini-tts';
  }
  $allowedModels = ['gpt-4o-mini-tts','gpt-4o-mini-tts-2025-12-15','tts-1','tts-1-hd'];
  if (!in_array($model, $allowedModels, true)) $model = 'gpt-4o-mini-tts';

  $payload = json_encode([
    'model' => $model,
    'input' => $input,
    'voice' => $voice,
    'response_format' => 'mp3',
  ], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);

  $url = 'https://api.openai.com/v1/audio/speech';
  $ch = curl_init($url);
  curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POSTFIELDS => $payload,
    CURLOPT_HTTPHEADER => [
      'Authorization: Bearer ' . $key,
      'Content-Type: application/json',
      'Accept: audio/mpeg',
    ],
    CURLOPT_TIMEOUT => 120,
  ]);

  $raw = curl_exec($ch);
  $err = curl_error($ch);
  $errno = curl_errno($ch);
  $http = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
  curl_close($ch);

  if ($errno !== 0) llc_json(['error'=>'Upstream error: '.($err?:('cURL '.$errno))], 502);
  if ($http < 200 || $http >= 300) {
    $msg = 'Upstream HTTP ' . $http;
    if (is_string($raw) && $raw !== '') {
      $jj = json_decode($raw, true);
      if (is_array($jj) && isset($jj['error']['message'])) $msg .= ' — ' . (string)$jj['error']['message'];
    }
    llc_json(['error'=>$msg], 502);
  }

  // Successful: return raw audio
  http_response_code(200);
  header('Content-Type: audio/mpeg');
  header('Cache-Control: no-store');
  echo $raw;
  exit;
}


function llc_voice_speech_stream(): void {
  $db = llc_db();
  $u = llc_require_user($db);
  $uid = (string)$u['id'];

  $key = llc_voice_cfg_get($db, $u, 'voice_api_key') ?? '';
  if (trim($key) === '') llc_json(['error'=>'Voice API key missing (Settings → Voice)'], 400);

  $j = llc_read_json();
  $input = trim((string)($j['input'] ?? ''));
  if ($input === '') llc_json(['error'=>'Missing field: input'], 400);

  // OpenAI Speech endpoint limit is 4096 characters.
  if (strlen($input) > 4096) llc_json(['error'=>'Text too long for speech (max 4096 chars).'], 400);

  $voice = trim((string)($j['voice'] ?? ''));
  if ($voice === '') {
    $voice = llc_voice_cfg_get($db, $u, 'voice_tts_voice') ?? 'marin';
  }
  $allowedVoices = ['alloy','ash','ballad','coral','echo','fable','nova','onyx','sage','shimmer','verse','marin','cedar'];
  if (!in_array($voice, $allowedVoices, true)) $voice = 'marin';

  $model = trim((string)($j['model'] ?? ''));
  if ($model === '') {
    $model = llc_voice_cfg_get($db, $u, 'voice_tts_model') ?? 'gpt-4o-mini-tts';
  }
  $allowedModels = ['gpt-4o-mini-tts','gpt-4o-mini-tts-2025-12-15','tts-1','tts-1-hd'];
  if (!in_array($model, $allowedModels, true)) $model = 'gpt-4o-mini-tts';

  $payload = json_encode([
    'model' => $model,
    'input' => $input,
    'voice' => $voice,
    'response_format' => 'mp3',
    // Ask for audio streaming (chunked). See API docs: stream_format defaults to "audio".
    'stream_format' => 'audio',
  ], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);

  // Make sure PHP doesn't buffer output.
  @ini_set('output_buffering', 'off');
  @ini_set('zlib.output_compression', '0');
  while (ob_get_level() > 0) { @ob_end_flush(); }
  @ob_implicit_flush(true);

  $url = 'https://api.openai.com/v1/audio/speech';
  $ch = curl_init($url);

  $httpCode = 0;
  $sentHeaders = false;
  $errBody = '';

  curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_RETURNTRANSFER => false,
    CURLOPT_POSTFIELDS => $payload,
    CURLOPT_HTTPHEADER => [
      'Authorization: Bearer ' . $key,
      'Content-Type: application/json',
      'Accept: audio/mpeg',
    ],
    CURLOPT_TIMEOUT => 120,
    CURLOPT_BUFFERSIZE => 16384,
    CURLOPT_HEADERFUNCTION => function($ch, $headerLine) use (&$httpCode, &$sentHeaders) {
      $line = trim((string)$headerLine);
      if ($line !== '' && str_starts_with($line, 'HTTP/')) {
        $parts = explode(' ', $line);
        if (count($parts) >= 2) {
          $code = (int)$parts[1];
          $httpCode = $code;
          // Defer sending headers until we know it's a success.
          if (!$sentHeaders && $code >= 200 && $code < 300) {
            http_response_code(200);
            header('Content-Type: audio/mpeg');
            header('Cache-Control: no-store');
            header('X-Accel-Buffering: no');
            $sentHeaders = true;
          }
        }
      }
      return strlen((string)$headerLine);
    },
    CURLOPT_WRITEFUNCTION => function($ch, $data) use (&$httpCode, &$sentHeaders, &$errBody) {
      $len = strlen($data);
      if ($httpCode >= 200 && $httpCode < 300) {
        if (!$sentHeaders) {
          // Extremely defensive: if headers weren't sent yet, send them now.
          http_response_code(200);
          header('Content-Type: audio/mpeg');
          header('Cache-Control: no-store');
          header('X-Accel-Buffering: no');
          $sentHeaders = true;
        }
        echo $data;
        @flush();
        return $len;
      }
      // Upstream error: buffer body for a JSON message.
      $errBody .= $data;
      return $len;
    },
  ]);

  $ok = curl_exec($ch);
  $err = curl_error($ch);
  $errno = curl_errno($ch);

  if ($errno !== 0) {
    curl_close($ch);
    llc_json(['error'=>'Upstream error: '.($err?:('cURL '.$errno))], 502);
  }

  $finalHttp = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
  curl_close($ch);

  if ($finalHttp < 200 || $finalHttp >= 300) {
    // We haven't sent audio headers in this branch; respond with JSON.
    $msg = 'Upstream HTTP ' . $finalHttp;
    $raw = trim((string)$errBody);
    if ($raw !== '') {
      $jj = json_decode($raw, true);
      if (is_array($jj) && isset($jj['error']['message'])) $msg .= ' — ' . (string)$jj['error']['message'];
    }
    llc_json(['error'=>$msg], 502);
  }

  // Success: streaming already happened.
  exit;
}


