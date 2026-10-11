<?php
// Optional config for LLC.
// Copy this file to config.php (same directory as api.php) and adjust as needed.

// Master switch
define('LLC_DEBUG', false);

// If LLC_DEBUG is true, this defaults to true.
define('LLC_DEBUG_LOG', false);

// Stream debug as UI status pills (only for streaming endpoints).
define('LLC_DEBUG_SSE', false);

// If true, tries to emit an SSE error+done on PHP fatals to avoid a "hung" UI.
define('LLC_DEBUG_FATAL_SSE', false);

// Log file for debug JSONL lines.
define('LLC_DEBUG_LOGFILE', __DIR__ . '/data/llc-debug.log');

// --- Persistence ---
// By default, LLC stores its SQLite DB at: <this folder>/data/locallightchat.sqlite
// You can override it with either a file path or a directory.
// Examples:
define('LLC_DB_PATH', __DIR__ . '/data/locallightchat.sqlite');

// --- File storage ---
// By default, LLC stores uploads/generated files at: <this folder>/uploads
// temporary export/job files at: <this folder>/tmp
// managed code workspaces at: <this folder>/workspaces
// and full MCP tool-result artifacts at: <this folder>/data/artifacts
// You can override these with absolute paths if needed. For public deployments,
// placing workspaces and artifacts outside the web root is strongly recommended.

//define('LLC_UPLOADS_DIR', __DIR__ . '/uploads');
//define('LLC_TMP_DIR', __DIR__ . '/tmp');
//define('LLC_WORKSPACES_DIR', __DIR__ . '/workspaces');
//define('LLC_ARTIFACTS_DIR', __DIR__ . '/data/artifacts');


// If enabled, a fresh install starts with a couple of useful shared connections.
define('LLC_START_WITH_PRECONFIGURED_CONNECTIONS', 1);

// --- Initial administrator ---
// Used only while the users table is empty. Once any user exists, this value
// never changes or resets an existing password.
//
// For an Internet-facing fresh install, set a strong value before first use:
//   define('LLC_INITIAL_ADMIN_PASSWORD', 'change-me-to-a-strong-password');
define('LLC_INITIAL_ADMIN_PASSWORD', '');

// If true, a fresh/empty installation will NOT fall back to admin/admin when
// LLC_INITIAL_ADMIN_PASSWORD is empty. The login screen will tell the operator
// to set LLC_INITIAL_ADMIN_PASSWORD in config.php and reload.
define('LLC_REQUIRE_INITIAL_ADMIN_PASSWORD', false);
