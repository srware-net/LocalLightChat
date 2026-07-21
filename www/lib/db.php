<?php
declare(strict_types=1);

/**
 * SQLite persistence + migrations.
 * This app is designed to run self-contained, so migrations happen automatically.
 */

function llc_db_path(): string {
  // Configurable via config.php:
  //   define('LLC_DB_PATH', '/absolute/path/to/locallightchat.sqlite');
  // or a directory:
  //   define('LLC_DB_PATH', __DIR__ . '/data');
  if (defined('LLC_DB_PATH')) {
    $cfg = trim((string)LLC_DB_PATH);
    if ($cfg !== '') {
      // If a directory is provided, append the default filename.
      $isDirHint = (substr($cfg, -1) === '/' || substr($cfg, -1) === '\\' || is_dir($cfg));
      if ($isDirHint) {
        $dir = rtrim($cfg, "/\\");
        if ($dir === '') $dir = __DIR__ . '/../data';
        if (!is_dir($dir)) mkdir($dir, 0775, true);
        return $dir . '/locallightchat.sqlite';
      }
      $dir = dirname($cfg);
      if ($dir && !is_dir($dir)) mkdir($dir, 0775, true);
      return $cfg;
    }
  }

  $dir = __DIR__ . '/../data';
  if (!is_dir($dir)) mkdir($dir, 0775, true);
  return $dir . '/locallightchat.sqlite';
}

function llc_db(): PDO {
  static $pdo = null;
  if ($pdo instanceof PDO) return $pdo;

  $dbFile = llc_db_path();
  $isNewDbFile = !is_file($dbFile);

  // SQLite: be tolerant to concurrent requests (e.g. long-running SSE + user clicks elsewhere).
  // - WAL allows readers + writers to coexist much better.
  // - busy_timeout makes SQLite wait instead of instantly throwing "database is locked".
  $pdo = new PDO('sqlite:' . $dbFile, null, null, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    // seconds
    PDO::ATTR_TIMEOUT => 5
  ]);
  // milliseconds
  $pdo->exec('PRAGMA busy_timeout = 5000;');
  // Use WAL when possible to reduce reader/writer contention.
  // (If it can't be enabled, SQLite will keep the current mode; that's fine.)
  try { $pdo->exec('PRAGMA journal_mode = WAL;'); } catch (Throwable $_) { /* noop */ }
  $pdo->exec('PRAGMA foreign_keys = ON;');
  llc_migrate($pdo);

  // Optional: seed preconfigured connections on first start (or if still empty).
  if ($isNewDbFile || llc_start_with_preconfigured_connections()) {
    llc_seed_preconfigured_connections($pdo);
  }

  return $pdo;
}



function llc_start_with_preconfigured_connections(): bool {
  if (!defined('LLC_START_WITH_PRECONFIGURED_CONNECTIONS')) return false;
  return ((int)LLC_START_WITH_PRECONFIGURED_CONNECTIONS !== 0);
}

function llc_seed_preconfigured_connections(PDO $db): void {
  if (!llc_start_with_preconfigured_connections()) return;

  // Only seed when the shared table is empty.
  try {
    $cnt = (int)($db->query("SELECT COUNT(*) FROM global_connections")->fetchColumn() ?? 0);
    if ($cnt > 0) return;
  } catch (Throwable $_) {
    return;
  }

  $now = time();
  $rows = [
    ['gc_openai', 'OpenAI', 'OpenAI', 'https://api.openai.com/v1'],
    ['gc_openrouter', 'OpenRouter', 'OR', 'https://openrouter.ai/api/v1'],
  ];

  $ins = $db->prepare("INSERT OR IGNORE INTO global_connections (id,label,prefix,base_url,api_key,headers,notes,enabled,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)");
  foreach ($rows as $r) {
    // These rows are templates only. They intentionally ship without API keys,
    // so they must not be active until an admin adds credentials and enables them.
    $ins->execute([(string)$r[0], (string)$r[1], (string)$r[2], (string)$r[3], '', null, '', 0, $now, $now]);
  }
}

function llc_migrate(PDO $db): void {
  $now = time();
  $adminId = 'u_admin';

  // --- Users + sessions ---
  $db->exec("
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL UNIQUE,
      email TEXT NULL UNIQUE,
      pass_hash TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'user',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ");

  $db->exec("
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
  ");

  // Ensure default admin/admin exists (first user)
  // IMPORTANT: The first built-in admin is also the superadmin.
  $st = $db->prepare("INSERT OR IGNORE INTO users (id,username,email,pass_hash,role,created_at,updated_at) VALUES (?,?,?,?,?,?,?)");
  $st->execute([$adminId, 'admin', null, password_hash('admin', PASSWORD_DEFAULT), 'superadmin', $now, $now]);

  // --- Core tables (new installs) ---
  $db->exec("
    CREATE TABLE IF NOT EXISTS chats (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL DEFAULT 'New chat',
      preview TEXT NOT NULL DEFAULT '',
      folder_id TEXT NULL,
      connection_id TEXT NULL,
      model TEXT NULL,
      messages_json TEXT NOT NULL DEFAULT '[]',
      meta_json TEXT NOT NULL DEFAULT '{}',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
  ");

  $db->exec("
    CREATE TABLE IF NOT EXISTS folders (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      parent_id TEXT NULL,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY(parent_id) REFERENCES folders(id) ON DELETE CASCADE
    );
  ");

  $db->exec("
    CREATE TABLE IF NOT EXISTS connections (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      label TEXT NOT NULL,
      prefix TEXT NOT NULL DEFAULT '',
      base_url TEXT NOT NULL,
      api_key TEXT NOT NULL DEFAULT '',
      headers TEXT NULL,
      notes TEXT NOT NULL DEFAULT '',
      enabled INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
  ");
  // Global connections (shared across all superadmins).
  $db->exec("
    CREATE TABLE IF NOT EXISTS global_connections (
      id TEXT PRIMARY KEY,
      label TEXT NOT NULL,
      prefix TEXT NOT NULL DEFAULT '',
      base_url TEXT NOT NULL,
      api_key TEXT NOT NULL DEFAULT '',
      headers TEXT NULL,
      notes TEXT NOT NULL DEFAULT '',
      enabled INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ");


  // Settings is now per-user: (user_id, k) → v
  $db->exec("
    CREATE TABLE IF NOT EXISTS settings (
      user_id TEXT NOT NULL,
      k TEXT NOT NULL,
      v TEXT NOT NULL,
      PRIMARY KEY(user_id, k),
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
  ");

  // Global settings (shared across all superadmins): (k) → v
  $db->exec("
    CREATE TABLE IF NOT EXISTS global_settings (
      k TEXT PRIMARY KEY,
      v TEXT NOT NULL
    );
  ");

  $db->exec("
    CREATE TABLE IF NOT EXISTS files (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      original_name TEXT NOT NULL,
      stored_name TEXT NOT NULL,
      mime TEXT NOT NULL,
      size INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
  ");

  // Chat templates (per user). Payload stores system prompt, advanced params and message history.
  $db->exec("
    CREATE TABLE IF NOT EXISTS templates (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      name TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
  ");

  // Managed code workspaces. Files live on disk under LLC_WORKSPACES_DIR/<id>/project.
  $db->exec("
    CREATE TABLE IF NOT EXISTS workspaces (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
    );
  ");
  $db->exec("CREATE INDEX IF NOT EXISTS idx_workspaces_user_updated ON workspaces(user_id, updated_at DESC);");

  // --- Migrations for existing DBs ---
  // Add missing columns when upgrading older installations.
  $colsChats = array_column($db->query("PRAGMA table_info(chats)")->fetchAll(), 'name');
  if (!in_array('user_id', $colsChats, true)) {
    $db->exec("ALTER TABLE chats ADD COLUMN user_id TEXT NOT NULL DEFAULT '$adminId'");
    $db->exec("UPDATE chats SET user_id='$adminId' WHERE user_id IS NULL OR user_id=''");
  }
  if (!in_array('connection_id', $colsChats, true)) {
    $db->exec("ALTER TABLE chats ADD COLUMN connection_id TEXT NULL");
  }

  $colsFolders = array_column($db->query("PRAGMA table_info(folders)")->fetchAll(), 'name');
  if (!in_array('user_id', $colsFolders, true)) {
    $db->exec("ALTER TABLE folders ADD COLUMN user_id TEXT NOT NULL DEFAULT '$adminId'");
    $db->exec("UPDATE folders SET user_id='$adminId' WHERE user_id IS NULL OR user_id=''");
  }

  $colsConn = array_column($db->query("PRAGMA table_info(connections)")->fetchAll(), 'name');
  if (!in_array('user_id', $colsConn, true)) {
    $db->exec("ALTER TABLE connections ADD COLUMN user_id TEXT NOT NULL DEFAULT '$adminId'");
    $db->exec("UPDATE connections SET user_id='$adminId' WHERE user_id IS NULL OR user_id=''");
  }
  if (!in_array('prefix', $colsConn, true)) {
    $db->exec("ALTER TABLE connections ADD COLUMN prefix TEXT NOT NULL DEFAULT ''");
  }
  if (!in_array('enabled', $colsConn, true)) {
    $db->exec("ALTER TABLE connections ADD COLUMN enabled INTEGER NOT NULL DEFAULT 1");
  }


  // Legacy compatibility:
  // Earlier versions treated "global connections" as rows in `connections` owned by superadmin(s).
  // We now store global connections in a shared `global_connections` table.
  $hasGlobalConns = (int)($db->query("SELECT COUNT(*) FROM global_connections")->fetchColumn() ?? 0);
  if ($hasGlobalConns === 0) {
    $legacy = $db->query("
      SELECT c.id,c.label,c.prefix,c.base_url,c.api_key,c.headers,c.notes,c.enabled,c.created_at,c.updated_at
      FROM connections c
      JOIN users u ON u.id=c.user_id
      WHERE u.role='superadmin'
      ORDER BY c.created_at ASC
    ")->fetchAll(PDO::FETCH_ASSOC);

    if ($legacy && count($legacy) > 0) {
      $ins = $db->prepare("INSERT OR IGNORE INTO global_connections (id,label,prefix,base_url,api_key,headers,notes,enabled,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)");
      foreach ($legacy as $r) {
        $ins->execute([
          (string)$r['id'],
          (string)$r['label'],
          (string)($r['prefix'] ?? ''),
          (string)$r['base_url'],
          (string)($r['api_key'] ?? ''),
          ($r['headers'] ?? null),
          (string)($r['notes'] ?? ''),
          (int)($r['enabled'] ?? 1),
          (int)($r['created_at'] ?? time()),
          (int)($r['updated_at'] ?? time())
  ]);
      }
      // Remove migrated legacy rows to avoid duplicates.
      $db->exec("DELETE FROM connections WHERE user_id IN (SELECT id FROM users WHERE role='superadmin')");
    }
  }


  $colsFiles = array_column($db->query("PRAGMA table_info(files)")->fetchAll(), 'name');
  if (!empty($colsFiles) && !in_array('user_id', $colsFiles, true)) {
    $db->exec("ALTER TABLE files ADD COLUMN user_id TEXT NOT NULL DEFAULT '$adminId'");
    $db->exec("UPDATE files SET user_id='$adminId' WHERE user_id IS NULL OR user_id=''");
  }

  // Settings table migration: old schema was (k PRIMARY KEY, v)
  $colsSettings = array_column($db->query("PRAGMA table_info(settings)")->fetchAll(), 'name');
  if (!in_array('user_id', $colsSettings, true)) {
    $db->exec("ALTER TABLE settings RENAME TO settings_old");
    $db->exec("
      CREATE TABLE settings (
        user_id TEXT NOT NULL,
        k TEXT NOT NULL,
        v TEXT NOT NULL,
        PRIMARY KEY(user_id, k),
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      );
    ");
    $st = $db->prepare("INSERT INTO settings (user_id,k,v) SELECT ?, k, v FROM settings_old");
    $st->execute([$adminId]);
    $db->exec("DROP TABLE settings_old");
  }

  // Per-user settings defaults (admin gets seeded; other users can be added later)
  llc_ensure_default_settings($db, $adminId);

  // Ensure shared global settings exist (seed from the oldest superadmin on first run / upgrade).
  llc_ensure_default_global_settings($db);

  // Ensure we always have at least one superadmin in older DBs.
  // If none exists, promote the built-in admin (u_admin).
  try {
    $cntSA = (int)$db->query("SELECT COUNT(*) AS c FROM users WHERE role='superadmin'")->fetch()['c'];
    if ($cntSA <= 0) {
      $db->exec("UPDATE users SET role='superadmin', updated_at=" . time() . " WHERE id='" . $adminId . "'");
    }
  } catch (Throwable $_) { /* noop */ }
}

function llc_get_global_setting(PDO $db, string $k): ?string {
  $st = $db->prepare("SELECT v FROM global_settings WHERE k=?");
  $st->execute([$k]);
  $r = $st->fetch();
  return $r ? (string)$r['v'] : null;
}

function llc_set_global_setting(PDO $db, string $k, string $v): void {
  $st = $db->prepare("INSERT INTO global_settings(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v");
  $st->execute([$k, $v]);
}

// Global settings default seeding.
// - We keep *one* shared config for Search/Image (future: Web/Voice).
// - Seed from the oldest superadmin (backstop to u_admin) so upgrades keep prior behavior.
function llc_ensure_default_global_settings(PDO $db, string $seedFromUserId = ''): void {
  // Determine seed user (oldest superadmin by created_at). Backstop to u_admin.
  if ($seedFromUserId === '') {
    try {
      $row = $db->query("SELECT id FROM users WHERE role='superadmin' ORDER BY created_at ASC LIMIT 1")->fetch();
      if ($row && !empty($row['id'])) $seedFromUserId = (string)$row['id'];
    } catch (Throwable $_) { /* noop */ }
  }
  if ($seedFromUserId === '') $seedFromUserId = 'u_admin';
  // These keys are considered "global" when users inherit Search/Image.
  $globalKeys = [
    // Search
    'search_provider','serper_api_key','brave_api_key','search_custom_url','search_custom_news_url','search_custom_allow_private','search_custom_api_key',
    'searchngx_url','searchngx_allow_private','searchngx_api_key','search_gl','search_hl','search_num',
    // Image (provider + defaults + ComfyUI)
    'image_provider','image_base_url','image_api_key','image_model','image_size','image_quality','image_background','image_output_format',
    'image_openrouter_base_url','image_openrouter_api_key','image_openrouter_model',
    'image_comfyui_url','image_comfyui_workflow_json','image_comfyui_bindings_json','image_comfyui_seed','image_comfyui_steps','image_comfyui_guidance',
    'image_comfyui_width','image_comfyui_height','image_comfyui_batch','image_comfyui_timeout_sec','image_comfyui_apply_defaults',
    // Voice (provider + key + TTS defaults)
    'voice_api_key','voice_tts_provider','voice_tts_voice','voice_tts_model',
    // Web (tool security + limits)
    'web_allow_private','web_fetch_max_chars','web_tool_max_chars',
    // General (server limits)
    'tool_max_iters'
  ];

  $hardDefaults = [
    'tool_max_iters' => '10',
  ];

  foreach ($globalKeys as $k) {
    if (llc_get_global_setting($db, $k) !== null) continue;
    $v = llc_get_setting($db, $seedFromUserId, $k);
    if ($v === null) {
      if (array_key_exists($k, $hardDefaults)) {
        $v = (string)$hardDefaults[$k];
      } else {
      // As a backstop, ensure defaults exist for the seed user and retry.
      if (function_exists('llc_ensure_default_settings')) llc_ensure_default_settings($db, $seedFromUserId);
      $v = llc_get_setting($db, $seedFromUserId, $k);
      }
    }
    if ($v === null) $v = '';
    llc_set_global_setting($db, $k, (string)$v);
  }
}

function llc_ensure_default_settings(PDO $db, string $userId): void {
  // Role-aware defaults (used for permissions)
  $role = 'user';
  try {
    $stR = $db->prepare("SELECT role FROM users WHERE id=? LIMIT 1");
    $stR->execute([$userId]);
    $r = $stR->fetch();
    if ($r && isset($r['role'])) $role = (string)$r['role'];
  } catch (Throwable $_) { /* noop */ }

  // Connection permissions
  // - inherit_global_connections: user can use global (superadmin) connections, but cannot edit or see secrets.
  // - allow_own_connections: user can create and manage their own connections.
  if (llc_get_setting($db, $userId, 'inherit_global_connections') === null) llc_set_setting($db, $userId, 'inherit_global_connections', '1');
  if (llc_get_setting($db, $userId, 'allow_own_connections') === null) {
    $allowOwn = ($role === 'user') ? '0' : '1';
    llc_set_setting($db, $userId, 'allow_own_connections', $allowOwn);
  }

  // Web permissions
  // - inherit_global_web: if enabled (typical for "user" role), web tool settings (allow_private + limits)
  //   are inherited from shared global_settings and are read-only for the user.
  if (llc_get_setting($db, $userId, 'inherit_global_web') === null) {
    $inheritWeb = ($role === 'user') ? '1' : '0';
    llc_set_setting($db, $userId, 'inherit_global_web', $inheritWeb);
  }

  // Search permissions
  // - inherit_global_search: if enabled (typical for "user" role), search settings (provider/keys/urls/locale) are inherited
  //   from shared global_settings and are read-only for the user.
  if (llc_get_setting($db, $userId, 'inherit_global_search') === null) {
    $inheritSearch = ($role === 'user') ? '1' : '0';
    llc_set_setting($db, $userId, 'inherit_global_search', $inheritSearch);
  }

  // Image permissions
  // - inherit_global_image: if enabled (typical for "user" role), image settings (provider/keys/defaults/ComfyUI)
  //   are inherited from shared global_settings and are read-only for the user.
  if (llc_get_setting($db, $userId, 'inherit_global_image') === null) {
    $inheritImg = ($role === 'user') ? '1' : '0';
    llc_set_setting($db, $userId, 'inherit_global_image', $inheritImg);
  }

  // Voice permissions
  // - inherit_global_voice: if enabled (typical for "user" role), voice settings (API key + TTS provider/model/voice)
  //   are inherited from shared global_settings and are read-only for the user.
  if (llc_get_setting($db, $userId, 'inherit_global_voice') === null) {
    $inheritVoice = ($role === 'user') ? '1' : '0';
    llc_set_setting($db, $userId, 'inherit_global_voice', $inheritVoice);
  }

  // Core UI state
  // IMPORTANT: llc_get_setting() returns strings like "0" which are falsy in PHP.
  // Defaults must only be applied when the key is missing (NULL), not when the stored value is "0".
  if (llc_get_setting($db, $userId, 'selected_model') === null) llc_set_setting($db, $userId, 'selected_model', '');
  if (llc_get_setting($db, $userId, 'selected_connection_id') === null) llc_set_setting($db, $userId, 'selected_connection_id', '');
  if (llc_get_setting($db, $userId, 'system_prompt') === null) llc_set_setting($db, $userId, 'system_prompt', '');

  // Web tools
  if (llc_get_setting($db, $userId, 'web_auto_enable') === null) llc_set_setting($db, $userId, 'web_auto_enable', '0');
  if (llc_get_setting($db, $userId, 'web_search_auto_enable') === null) llc_set_setting($db, $userId, 'web_search_auto_enable', '0');
  if (llc_get_setting($db, $userId, 'web_prefer_attachments') === null) llc_set_setting($db, $userId, 'web_prefer_attachments', '1');
  if (llc_get_setting($db, $userId, 'web_allow_private') === null) llc_set_setting($db, $userId, 'web_allow_private', '0');

  // Web extraction limits
  // 0 = unlimited
  if (llc_get_setting($db, $userId, 'web_fetch_max_chars') === null) llc_set_setting($db, $userId, 'web_fetch_max_chars', '20000');
  if (llc_get_setting($db, $userId, 'web_tool_max_chars') === null) llc_set_setting($db, $userId, 'web_tool_max_chars', '12000');

  // Search provider config
  if (llc_get_setting($db, $userId, 'search_provider') === null) llc_set_setting($db, $userId, 'search_provider', 'serper');
  if (llc_get_setting($db, $userId, 'serper_api_key') === null) llc_set_setting($db, $userId, 'serper_api_key', '');
  if (llc_get_setting($db, $userId, 'brave_api_key') === null) llc_set_setting($db, $userId, 'brave_api_key', '');
  if (llc_get_setting($db, $userId, 'search_custom_url') === null) llc_set_setting($db, $userId, 'search_custom_url', '');
  if (llc_get_setting($db, $userId, 'search_custom_news_url') === null) llc_set_setting($db, $userId, 'search_custom_news_url', '');
  if (llc_get_setting($db, $userId, 'search_custom_allow_private') === null) llc_set_setting($db, $userId, 'search_custom_allow_private', '0');
  if (llc_get_setting($db, $userId, 'search_custom_api_key') === null) llc_set_setting($db, $userId, 'search_custom_api_key', '');

  // SearchNGX / SearXNG instance
  if (llc_get_setting($db, $userId, 'searchngx_url') === null) llc_set_setting($db, $userId, 'searchngx_url', '');
  if (llc_get_setting($db, $userId, 'searchngx_allow_private') === null) llc_set_setting($db, $userId, 'searchngx_allow_private', '0');
  if (llc_get_setting($db, $userId, 'searchngx_api_key') === null) llc_set_setting($db, $userId, 'searchngx_api_key', '');

  if (llc_get_setting($db, $userId, 'search_gl') === null) llc_set_setting($db, $userId, 'search_gl', 'de');
  if (llc_get_setting($db, $userId, 'search_hl') === null) llc_set_setting($db, $userId, 'search_hl', 'de');
  if (llc_get_setting($db, $userId, 'search_num') === null) llc_set_setting($db, $userId, 'search_num', '10');

  // Image generation (OpenAI Images API)
  if (llc_get_setting($db, $userId, 'image_provider') === null) llc_set_setting($db, $userId, 'image_provider', 'openai');
  if (llc_get_setting($db, $userId, 'image_base_url') === null) llc_set_setting($db, $userId, 'image_base_url', 'https://api.openai.com/v1');
  if (llc_get_setting($db, $userId, 'image_api_key') === null) llc_set_setting($db, $userId, 'image_api_key', '');
  if (llc_get_setting($db, $userId, 'image_model') === null) llc_set_setting($db, $userId, 'image_model', 'gpt-image-2');
  if (llc_get_setting($db, $userId, 'image_auto_enable') === null) llc_set_setting($db, $userId, 'image_auto_enable', '0');
  if (llc_get_setting($db, $userId, 'vision_auto_attach_last_image') === null) llc_set_setting($db, $userId, 'vision_auto_attach_last_image', '1');
  if (llc_get_setting($db, $userId, 'image_size') === null) llc_set_setting($db, $userId, 'image_size', 'auto');
  if (llc_get_setting($db, $userId, 'image_quality') === null) llc_set_setting($db, $userId, 'image_quality', 'auto');
  if (llc_get_setting($db, $userId, 'image_background') === null) llc_set_setting($db, $userId, 'image_background', 'auto');
  if (llc_get_setting($db, $userId, 'image_output_format') === null) llc_set_setting($db, $userId, 'image_output_format', 'png');

  // OpenRouter image generation (separate from OpenAI Images API)
  if (llc_get_setting($db, $userId, 'image_openrouter_base_url') === null) llc_set_setting($db, $userId, 'image_openrouter_base_url', 'https://openrouter.ai/api/v1');
  if (llc_get_setting($db, $userId, 'image_openrouter_api_key') === null) llc_set_setting($db, $userId, 'image_openrouter_api_key', '');
  if (llc_get_setting($db, $userId, 'image_openrouter_model') === null) llc_set_setting($db, $userId, 'image_openrouter_model', 'google/gemini-3-pro-image-preview');

  // ComfyUI (optional)
  if (llc_get_setting($db, $userId, 'image_comfyui_url') === null) llc_set_setting($db, $userId, 'image_comfyui_url', '');
  if (llc_get_setting($db, $userId, 'image_comfyui_workflow_json') === null) llc_set_setting($db, $userId, 'image_comfyui_workflow_json', '');
  if (llc_get_setting($db, $userId, 'image_comfyui_bindings_json') === null) llc_set_setting($db, $userId, 'image_comfyui_bindings_json', '');
  if (llc_get_setting($db, $userId, 'image_comfyui_seed') === null) llc_set_setting($db, $userId, 'image_comfyui_seed', '-1');
  if (llc_get_setting($db, $userId, 'image_comfyui_steps') === null) llc_set_setting($db, $userId, 'image_comfyui_steps', '20');
  if (llc_get_setting($db, $userId, 'image_comfyui_guidance') === null) llc_set_setting($db, $userId, 'image_comfyui_guidance', '3.5');
  if (llc_get_setting($db, $userId, 'image_comfyui_width') === null) llc_set_setting($db, $userId, 'image_comfyui_width', '512');
  if (llc_get_setting($db, $userId, 'image_comfyui_height') === null) llc_set_setting($db, $userId, 'image_comfyui_height', '512');
  if (llc_get_setting($db, $userId, 'image_comfyui_batch') === null) llc_set_setting($db, $userId, 'image_comfyui_batch', '1');
  if (llc_get_setting($db, $userId, 'image_comfyui_timeout_sec') === null) llc_set_setting($db, $userId, 'image_comfyui_timeout_sec', '900');
  if (llc_get_setting($db, $userId, 'image_comfyui_apply_defaults') === null) llc_set_setting($db, $userId, 'image_comfyui_apply_defaults', '0');

  // Voice (OpenAI Transcribe/Realtime)
  if (llc_get_setting($db, $userId, 'voice_api_key') === null) llc_set_setting($db, $userId, 'voice_api_key', '');
  if (llc_get_setting($db, $userId, 'voice_auto_enable') === null) llc_set_setting($db, $userId, 'voice_auto_enable', '0');
  if (llc_get_setting($db, $userId, 'voice_auto_send') === null) llc_set_setting($db, $userId, 'voice_auto_send', '1');
  if (llc_get_setting($db, $userId, 'voice_tts_provider') === null) llc_set_setting($db, $userId, 'voice_tts_provider', 'browser');
  if (llc_get_setting($db, $userId, 'voice_tts_voice') === null) llc_set_setting($db, $userId, 'voice_tts_voice', 'marin');
  if (llc_get_setting($db, $userId, 'voice_tts_model') === null) llc_set_setting($db, $userId, 'voice_tts_model', 'gpt-4o-mini-tts');

  // Pricing rules (JSON list of {connection_id, model, prompt_price, gen_price})
  if (llc_get_setting($db, $userId, 'pricing_json') === null) llc_set_setting($db, $userId, 'pricing_json', '[]');

}

function llc_id(string $prefix=''): string { return $prefix . bin2hex(random_bytes(8)); }

function llc_get_setting(PDO $db, string $userId, string $k): ?string {
  $st = $db->prepare("SELECT v FROM settings WHERE user_id=? AND k=?");
  $st->execute([$userId, $k]);
  $r = $st->fetch();
  return $r ? (string)$r['v'] : null;
}

function llc_set_setting(PDO $db, string $userId, string $k, string $v): void {
  $st = $db->prepare("INSERT INTO settings(user_id,k,v) VALUES(?,?,?) ON CONFLICT(user_id,k) DO UPDATE SET v=excluded.v");
  $st->execute([$userId, $k, $v]);
}
