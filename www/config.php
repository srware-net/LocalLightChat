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

// If enabled, a fresh install starts with a couple of useful shared connections.
define('LLC_START_WITH_PRECONFIGURED_CONNECTIONS', 1);
