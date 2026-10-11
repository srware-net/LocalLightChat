<?php
declare(strict_types=1);

/**
 * MCP artifact storage.
 *
 * Only MCP tool results are externalized. The full JSON result is kept on disk,
 * while the model receives each large result once in full. Only subsequent
 * agent rounds replace that already-consumed result with a bounded preview plus
 * artifact tools for selective reading/searching.
 */

function llc_artifacts_dir(): string {
  $dir = defined('LLC_ARTIFACTS_DIR') ? trim((string)LLC_ARTIFACTS_DIR) : '';
  if ($dir === '') $dir = __DIR__ . '/../artifacts';
  return rtrim($dir, "/\\");
}

function llc_artifact_token_estimate(string $text): int {
  if ($text === '') return 0;
  $chars = function_exists('mb_strlen') ? mb_strlen($text, 'UTF-8') : strlen($text);
  return max(1, (int)ceil($chars / 4));
}

function llc_mcp_artifact_settings(PDO $db, string $userId): array {
  $mode = strtolower(trim((string)(llc_get_setting($db, $userId, 'mcp_artifact_mode') ?? 'full')));
  if (!in_array($mode, ['full', 'externalize'], true)) $mode = 'full';

  $threshold = (int)(llc_get_setting($db, $userId, 'mcp_artifact_threshold_tokens') ?? '6000');
  if ($threshold < 250) $threshold = 250;
  if ($threshold > 1000000) $threshold = 1000000;

  $preview = (int)(llc_get_setting($db, $userId, 'mcp_artifact_preview_tokens') ?? '2500');
  if ($preview < 100) $preview = 100;
  if ($preview > 100000) $preview = 100000;

  $read = (int)(llc_get_setting($db, $userId, 'mcp_artifact_read_tokens') ?? '2500');
  if ($read < 100) $read = 100;
  if ($read > 100000) $read = 100000;

  return [
    'mode'=>$mode,
    'threshold_tokens'=>$threshold,
    'preview_tokens'=>$preview,
    'read_tokens'=>$read,
  ];
}

function llc_artifact_json_flags(bool $pretty = false): int {
  $flags = JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE;
  if ($pretty) $flags |= JSON_PRETTY_PRINT;
  return $flags;
}

function llc_artifact_encode($value, bool $pretty = false): string {
  $json = json_encode($value, llc_artifact_json_flags($pretty));
  if (!is_string($json)) throw new RuntimeException('Artifact content could not be encoded');
  return $json;
}

function llc_artifact_user_chat_exists(PDO $db, string $userId, string $chatId): bool {
  if ($userId === '' || $chatId === '') return false;
  $st = $db->prepare('SELECT 1 FROM chats WHERE id=? AND user_id=? LIMIT 1');
  $st->execute([$chatId, $userId]);
  return (bool)$st->fetchColumn();
}

function llc_artifact_safe_storage_name(string $artifactId, string $userId): string {
  // Artifact IDs are already random and filesystem-safe. Keep new artifacts as
  // ordinary JSON files directly in LLC_ARTIFACTS_DIR so the folder remains
  // easy to inspect, edit and back up. Existing bucketed paths in the database
  // continue to work unchanged.
  return $artifactId . '.json';
}

function llc_artifact_absolute_path(string $storedName): string {
  $storedName = str_replace('\\', '/', trim($storedName));
  if ($storedName === '' || str_contains($storedName, '..') || str_starts_with($storedName, '/')) {
    throw new RuntimeException('Invalid artifact storage path');
  }
  return llc_artifacts_dir() . '/' . $storedName;
}

function llc_artifact_write_file(string $storedName, string $content): void {
  $path = llc_artifact_absolute_path($storedName);
  $dir = dirname($path);
  if (!is_dir($dir) && !@mkdir($dir, 0775, true) && !is_dir($dir)) {
    throw new RuntimeException('Could not create artifact directory: ' . $dir);
  }
  $tmp = $path . '.tmp-' . bin2hex(random_bytes(6));
  $written = @file_put_contents($tmp, $content, LOCK_EX);
  if ($written === false || $written !== strlen($content)) {
    @unlink($tmp);
    throw new RuntimeException('Could not write artifact file');
  }
  // Do not apply special restrictive permissions. The file uses the normal
  // process umask, just like the application's other data folders.
  if (!@rename($tmp, $path)) {
    @unlink($tmp);
    throw new RuntimeException('Could not finalize artifact file');
  }
}

function llc_artifact_line_count(string $text): int {
  if ($text === '') return 0;
  return substr_count(str_replace("\r\n", "\n", str_replace("\r", "\n", $text)), "\n") + 1;
}

function llc_artifact_create(
  PDO $db,
  string $userId,
  string $chatId,
  string $toolCallId,
  string $sourceTool,
  string $serverId,
  string $remoteTool,
  string $content,
  int $originalTokens,
  int $contextTokens
): array {
  if (!llc_artifact_user_chat_exists($db, $userId, $chatId)) {
    throw new RuntimeException('Cannot store MCP artifact: chat not found');
  }

  $artifactId = llc_id('art_');
  $storedName = llc_artifact_safe_storage_name($artifactId, $userId);
  llc_artifact_write_file($storedName, $content);

  $size = strlen($content);
  $lineCount = llc_artifact_line_count($content);
  $sha256 = hash('sha256', $content);
  try {
    $st = $db->prepare('INSERT INTO artifacts (id,user_id,chat_id,tool_call_id,source_tool,server_id,remote_tool,mime_type,stored_name,size_bytes,line_count,sha256,original_tokens,context_tokens,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
    $st->execute([
      $artifactId, $userId, $chatId, $toolCallId, $sourceTool, $serverId, $remoteTool,
      'application/json', $storedName, $size, $lineCount, $sha256,
      $originalTokens, $contextTokens, time(),
    ]);
  } catch (Throwable $e) {
    @unlink(llc_artifact_absolute_path($storedName));
    throw $e;
  }

  return [
    'id'=>$artifactId,
    'mime_type'=>'application/json',
    'size_bytes'=>$size,
    'line_count'=>$lineCount,
    'sha256'=>$sha256,
    'original_tokens'=>$originalTokens,
    'context_tokens'=>$contextTokens,
    'saved_tokens'=>max(0, $originalTokens - $contextTokens),
  ];
}

function llc_artifact_result_text(array $mcpResult): string {
  $parts = [];
  $result = is_array($mcpResult['result'] ?? null) ? $mcpResult['result'] : [];
  $structured = is_array($result['structuredContent'] ?? null) ? $result['structuredContent'] : [];

  $append = static function(array &$parts, string $label, $value): void {
    if (!is_string($value) && !is_numeric($value)) return;
    $text = trim((string)$value);
    if ($text === '') return;
    $parts[] = ($label !== '' ? '[' . $label . "]\n" : '') . $text;
  };

  $append($parts, 'error', $structured['error'] ?? '');
  $append($parts, 'stderr', $structured['stderr'] ?? '');
  $append($parts, 'stdout', $structured['stdout'] ?? '');
  $append($parts, 'text', $structured['text'] ?? '');
  $append($parts, 'content', $structured['content'] ?? '');

  foreach ((array)($result['content'] ?? []) as $item) {
    if (!is_array($item)) continue;
    if (($item['type'] ?? '') === 'text') $append($parts, 'MCP content', $item['text'] ?? '');
  }

  $parts = array_values(array_unique($parts));
  if ($parts) return implode("\n\n", $parts);
  return llc_artifact_encode($mcpResult, true);
}

function llc_artifact_preview(string $text, int $maxTokens): string {
  $maxChars = max(400, $maxTokens * 4);
  $text = str_replace("\r\n", "\n", str_replace("\r", "\n", $text));
  if (function_exists('mb_strlen') ? mb_strlen($text, 'UTF-8') <= $maxChars : strlen($text) <= $maxChars) return $text;

  $lines = explode("\n", $text);
  if (count($lines) <= 1) {
    $headChars = (int)floor($maxChars * 0.58);
    $tailChars = max(0, $maxChars - $headChars - 80);
    $head = function_exists('mb_substr') ? mb_substr($text, 0, $headChars, 'UTF-8') : substr($text, 0, $headChars);
    $tail = function_exists('mb_substr') ? mb_substr($text, -$tailChars, null, 'UTF-8') : substr($text, -$tailChars);
    return rtrim($head) . "\n\n… [middle omitted; full result is in the artifact] …\n\n" . ltrim($tail);
  }

  $selected = [];
  $count = count($lines);
  foreach (range(0, min(29, $count - 1)) as $i) $selected[$i] = true;

  $errorPattern = '/\b(error|fatal|failed|failure|exception|traceback|undefined reference|not found|permission denied|denied|timeout|timed out|cancelled|warning)\b/i';
  foreach ($lines as $i => $line) {
    if (!preg_match($errorPattern, $line)) continue;
    for ($j = max(0, $i - 2); $j <= min($count - 1, $i + 2); $j++) $selected[$j] = true;
  }
  for ($i = max(0, $count - 100); $i < $count; $i++) $selected[$i] = true;
  ksort($selected, SORT_NUMERIC);

  $out = [];
  $used = 0;
  $previous = -2;
  foreach (array_keys($selected) as $idx) {
    $line = (string)$lines[$idx];
    if ($previous >= 0 && $idx > $previous + 1) {
      $gap = '… [' . ($idx - $previous - 1) . ' line(s) omitted] …';
      if ($used + strlen($gap) + 1 > $maxChars) break;
      $out[] = $gap;
      $used += strlen($gap) + 1;
    }
    $lineChars = function_exists('mb_strlen') ? mb_strlen($line, 'UTF-8') : strlen($line);
    if ($used + $lineChars + 1 > $maxChars) break;
    $out[] = $line;
    $used += $lineChars + 1;
    $previous = $idx;
  }

  $preview = implode("\n", $out);
  if ($preview === '') {
    return function_exists('mb_substr') ? mb_substr($text, 0, $maxChars, 'UTF-8') : substr($text, 0, $maxChars);
  }
  return $preview;
}

function llc_artifact_compact_value($value, string $artifactId, int $depth = 0) {
  if ($depth > 4) return '[see artifact ' . $artifactId . ']';
  if (is_string($value)) {
    $chars = function_exists('mb_strlen') ? mb_strlen($value, 'UTF-8') : strlen($value);
    if ($chars <= 500) return $value;
    return '[large text stored in artifact ' . $artifactId . '; ' . $chars . ' characters]';
  }
  if (!is_array($value)) return $value;
  if (count($value) > 40) {
    return ['_artifact'=>$artifactId, '_omitted_items'=>count($value)];
  }
  $out = [];
  foreach ($value as $k => $v) $out[$k] = llc_artifact_compact_value($v, $artifactId, $depth + 1);
  return $out;
}

function llc_artifact_compact_mcp_result(array $mcpResult, string $artifactId, string $preview, int $originalTokens): array {
  $result = is_array($mcpResult['result'] ?? null) ? $mcpResult['result'] : [];
  $structured = is_array($result['structuredContent'] ?? null) ? $result['structuredContent'] : [];
  $structuredSummary = llc_artifact_compact_value($structured, $artifactId);
  if (!is_array($structuredSummary)) $structuredSummary = [];
  $structuredSummary['artifact_id'] = $artifactId;
  $structuredSummary['full_result_available'] = true;
  $structuredSummary['original_result_tokens'] = $originalTokens;

  $notice = "This MCP result was provided to you in full in the immediately preceding model turn.\n"
    . "It has now been compacted for subsequent turns and stored as artifact {$artifactId}.\n"
    . "Use artifact_info, artifact_search, or artifact_read only when you need to inspect the original again in bounded chunks.\n"
    . "Do not claim that the preview is the complete result and do not assume omitted sections are empty.\n\n"
    . "Preview for later reference:\n" . $preview;

  $compact = $mcpResult;
  $compact['artifact'] = [
    'id'=>$artifactId,
    'full_result_available'=>true,
    'original_tokens'=>$originalTokens,
  ];
  $compact['result'] = [
    'isError'=>!empty($result['isError']),
    'content'=>[['type'=>'text','text'=>$notice]],
    'structuredContent'=>$structuredSummary,
  ];
  if (isset($result['outcome'])) $compact['result']['outcome'] = llc_artifact_compact_value($result['outcome'], $artifactId);
  return $compact;
}

/**
 * Store a large MCP result and prepare its later compact representation. The
 * caller must still send the original result to the model once before using the
 * returned compact_result in any subsequent agent round.
 */
function llc_mcp_externalize_result(
  PDO $db,
  array $user,
  string $chatId,
  string $toolCallId,
  string $sourceTool,
  string $serverId,
  string $remoteTool,
  array $mcpResult
): array {
  $userId = (string)($user['id'] ?? '');
  $settings = llc_mcp_artifact_settings($db, $userId);
  if ($settings['mode'] !== 'externalize') return ['result'=>$mcpResult, 'compact_result'=>null, 'artifact'=>null];
  if (!llc_artifact_user_chat_exists($db, $userId, $chatId)) return ['result'=>$mcpResult, 'compact_result'=>null, 'artifact'=>null];

  $fullJson = llc_artifact_encode($mcpResult, true);
  $originalTokens = llc_artifact_token_estimate($fullJson);
  if ($originalTokens <= (int)$settings['threshold_tokens']) return ['result'=>$mcpResult, 'compact_result'=>null, 'artifact'=>null];

  $artifactId = llc_id('art_');
  $previewSource = llc_artifact_result_text($mcpResult);
  $preview = llc_artifact_preview($previewSource, (int)$settings['preview_tokens']);
  $compact = llc_artifact_compact_mcp_result($mcpResult, $artifactId, $preview, $originalTokens);

  // The token metadata itself becomes part of the compact model result. Calculate
  // it twice so the stored number describes the final payload instead of the
  // preliminary preview without its own accounting fields.
  $contextTokens = llc_artifact_token_estimate(llc_artifact_encode($compact, false));
  for ($pass = 0; $pass < 2; $pass++) {
    $savedTokens = max(0, $originalTokens - $contextTokens);
    $compact['artifact'] = array_merge((array)($compact['artifact'] ?? []), [
      'context_tokens'=>$contextTokens,
      'saved_tokens'=>$savedTokens,
    ]);
    if (isset($compact['result']['structuredContent']) && is_array($compact['result']['structuredContent'])) {
      $compact['result']['structuredContent']['context_result_tokens'] = $contextTokens;
      $compact['result']['structuredContent']['saved_tokens'] = $savedTokens;
    }
    $contextTokens = llc_artifact_token_estimate(llc_artifact_encode($compact, false));
  }

  // Store using the pre-generated ID so it is already present in the compact result.
  $storedName = llc_artifact_safe_storage_name($artifactId, $userId);
  llc_artifact_write_file($storedName, $fullJson);
  $size = strlen($fullJson);
  $lineCount = llc_artifact_line_count($fullJson);
  $sha256 = hash('sha256', $fullJson);
  try {
    $st = $db->prepare('INSERT INTO artifacts (id,user_id,chat_id,tool_call_id,source_tool,server_id,remote_tool,mime_type,stored_name,size_bytes,line_count,sha256,original_tokens,context_tokens,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)');
    $st->execute([
      $artifactId, $userId, $chatId, $toolCallId, $sourceTool, $serverId, $remoteTool,
      'application/json', $storedName, $size, $lineCount, $sha256,
      $originalTokens, $contextTokens, time(),
    ]);
  } catch (Throwable $e) {
    @unlink(llc_artifact_absolute_path($storedName));
    throw $e;
  }

  $artifact = [
    'id'=>$artifactId,
    'mime_type'=>'application/json',
    'size_bytes'=>$size,
    'line_count'=>$lineCount,
    'sha256'=>$sha256,
    'original_tokens'=>$originalTokens,
    'context_tokens'=>$contextTokens,
    'saved_tokens'=>max(0, $originalTokens - $contextTokens),
  ];
  // Finalize the values after the fixed-point pass above.
  $compact['artifact'] = array_merge((array)$compact['artifact'], [
    'context_tokens'=>$contextTokens,
    'saved_tokens'=>$artifact['saved_tokens'],
  ]);
  if (isset($compact['result']['structuredContent']) && is_array($compact['result']['structuredContent'])) {
    $compact['result']['structuredContent']['context_result_tokens'] = $contextTokens;
    $compact['result']['structuredContent']['saved_tokens'] = $artifact['saved_tokens'];
  }

  return ['result'=>$mcpResult, 'compact_result'=>$compact, 'artifact'=>$artifact];
}

function llc_artifact_row(PDO $db, string $userId, string $artifactId, ?string $chatId = null): ?array {
  $artifactId = trim($artifactId);
  if ($artifactId === '') return null;
  if ($chatId !== null && $chatId !== '') {
    $st = $db->prepare('SELECT * FROM artifacts WHERE id=? AND user_id=? AND chat_id=? LIMIT 1');
    $st->execute([$artifactId, $userId, $chatId]);
  } else {
    $st = $db->prepare('SELECT * FROM artifacts WHERE id=? AND user_id=? LIMIT 1');
    $st->execute([$artifactId, $userId]);
  }
  $row = $st->fetch();
  return is_array($row) ? $row : null;
}

function llc_artifact_content_from_row(array $row): string {
  $path = llc_artifact_absolute_path((string)($row['stored_name'] ?? ''));
  $content = @file_get_contents($path);
  if (!is_string($content)) throw new RuntimeException('Artifact file is missing');
  return $content;
}

function llc_artifact_public_meta(array $row): array {
  return [
    'id'=>(string)$row['id'],
    'chat_id'=>(string)$row['chat_id'],
    'source_tool'=>(string)$row['source_tool'],
    'server_id'=>(string)$row['server_id'],
    'remote_tool'=>(string)$row['remote_tool'],
    'mime_type'=>(string)$row['mime_type'],
    'size_bytes'=>(int)$row['size_bytes'],
    'line_count'=>(int)$row['line_count'],
    'sha256'=>(string)$row['sha256'],
    'original_tokens'=>(int)$row['original_tokens'],
    'context_tokens'=>(int)$row['context_tokens'],
    'saved_tokens'=>max(0, (int)$row['original_tokens'] - (int)$row['context_tokens']),
    'created_at'=>(int)$row['created_at'],
  ];
}

function llc_artifact_info_result(PDO $db, string $userId, string $chatId, string $artifactId): array {
  $row = llc_artifact_row($db, $userId, $artifactId, $chatId);
  if (!$row) throw new RuntimeException('Artifact not found in this chat');
  return ['ok'=>true, 'artifact'=>llc_artifact_public_meta($row)];
}

function llc_artifact_read_result(PDO $db, string $userId, string $chatId, string $artifactId, int $startLine, int $lineCount, int $maxTokens): array {
  $row = llc_artifact_row($db, $userId, $artifactId, $chatId);
  if (!$row) throw new RuntimeException('Artifact not found in this chat');
  $content = str_replace("\r\n", "\n", str_replace("\r", "\n", llc_artifact_content_from_row($row)));
  $lines = $content === '' ? [] : explode("\n", $content);
  $total = count($lines);
  $startLine = max(1, $startLine);
  $lineCount = max(1, min(2000, $lineCount));
  if ($total > 0 && $startLine > $total) throw new RuntimeException('artifact_read: start_line is outside the artifact');
  $slice = array_slice($lines, $startLine - 1, $lineCount);
  $text = implode("\n", $slice);
  $maxChars = max(400, $maxTokens * 4);
  $truncatedByTokens = false;
  $charLen = function_exists('mb_strlen') ? mb_strlen($text, 'UTF-8') : strlen($text);
  if ($charLen > $maxChars) {
    $text = function_exists('mb_substr') ? mb_substr($text, 0, $maxChars, 'UTF-8') : substr($text, 0, $maxChars);
    $truncatedByTokens = true;
  }
  $returnedLines = $text === '' ? 0 : substr_count($text, "\n") + 1;
  $endLine = $returnedLines > 0 ? $startLine + $returnedLines - 1 : $startLine - 1;
  return [
    'ok'=>true,
    'artifact'=>llc_artifact_public_meta($row),
    'start_line'=>$startLine,
    'end_line'=>$endLine,
    'requested_line_count'=>$lineCount,
    'content'=>$text,
    'truncated'=>($endLine < $total) || $truncatedByTokens,
    'truncated_by_token_limit'=>$truncatedByTokens,
  ];
}

function llc_artifact_search_result(PDO $db, string $userId, string $chatId, string $artifactId, string $query, bool $caseSensitive, bool $regex, int $contextLines, int $maxMatches, int $maxTokens): array {
  $row = llc_artifact_row($db, $userId, $artifactId, $chatId);
  if (!$row) throw new RuntimeException('Artifact not found in this chat');
  if ($query === '') throw new RuntimeException('artifact_search: query must not be empty');
  $content = str_replace("\r\n", "\n", str_replace("\r", "\n", llc_artifact_content_from_row($row)));
  $lines = $content === '' ? [] : explode("\n", $content);
  $contextLines = max(0, min(10, $contextLines));
  $maxMatches = max(1, min(100, $maxMatches));
  $maxChars = max(400, $maxTokens * 4);
  $matches = [];
  $usedChars = 0;
  $truncated = false;

  $pattern = null;
  if ($regex) {
    $pattern = '~' . str_replace('~', '\\~', $query) . '~' . ($caseSensitive ? 'u' : 'iu');
    if (@preg_match($pattern, '') === false) throw new RuntimeException('artifact_search: invalid regular expression');
  }

  foreach ($lines as $i => $line) {
    $found = $regex
      ? (preg_match((string)$pattern, $line) === 1)
      : ($caseSensitive ? str_contains($line, $query) : (stripos($line, $query) !== false));
    if (!$found) continue;
    if (count($matches) >= $maxMatches) { $truncated = true; break; }
    $from = max(0, $i - $contextLines);
    $to = min(count($lines) - 1, $i + $contextLines);
    $excerptLines = array_slice($lines, $from, $to - $from + 1);
    $excerpt = implode("\n", $excerptLines);
    $cost = (function_exists('mb_strlen') ? mb_strlen($excerpt, 'UTF-8') : strlen($excerpt)) + 80;
    if ($usedChars + $cost > $maxChars) { $truncated = true; break; }
    $usedChars += $cost;
    $matches[] = [
      'line'=>$i + 1,
      'context_start_line'=>$from + 1,
      'context_end_line'=>$to + 1,
      'excerpt'=>$excerpt,
    ];
  }

  return [
    'ok'=>true,
    'artifact'=>llc_artifact_public_meta($row),
    'query'=>$query,
    'regex'=>$regex,
    'case_sensitive'=>$caseSensitive,
    'matches'=>$matches,
    'returned'=>count($matches),
    'truncated'=>$truncated,
  ];
}

function llc_artifact_openai_tools(): array {
  return [
    ['type'=>'function','function'=>[
      'name'=>'artifact_info',
      'description'=>'Inspect metadata for a full MCP result that was externalized to save context tokens.',
      'parameters'=>[
        'type'=>'object',
        'properties'=>['artifact_id'=>['type'=>'string','description'=>'Artifact ID returned by a previous MCP tool result']],
        'required'=>['artifact_id'],
        'additionalProperties'=>false,
      ],
    ]],
    ['type'=>'function','function'=>[
      'name'=>'artifact_read',
      'description'=>'Read a bounded line range from a full externalized MCP result. Never request the entire artifact at once; read only the useful range.',
      'parameters'=>[
        'type'=>'object',
        'properties'=>[
          'artifact_id'=>['type'=>'string'],
          'start_line'=>['type'=>'integer','minimum'=>1,'description'=>'First line, 1-based'],
          'line_count'=>['type'=>'integer','minimum'=>1,'maximum'=>2000,'description'=>'Number of lines; output is also capped by the configured MCP artifact lookup token limit'],
        ],
        'required'=>['artifact_id'],
        'additionalProperties'=>false,
      ],
    ]],
    ['type'=>'function','function'=>[
      'name'=>'artifact_search',
      'description'=>'Search within a full externalized MCP result and return bounded matching excerpts with line numbers.',
      'parameters'=>[
        'type'=>'object',
        'properties'=>[
          'artifact_id'=>['type'=>'string'],
          'query'=>['type'=>'string'],
          'regex'=>['type'=>'boolean','description'=>'Treat query as a regular expression'],
          'case_sensitive'=>['type'=>'boolean'],
          'context_lines'=>['type'=>'integer','minimum'=>0,'maximum'=>10],
          'max_matches'=>['type'=>'integer','minimum'=>1,'maximum'=>100],
        ],
        'required'=>['artifact_id','query'],
        'additionalProperties'=>false,
      ],
    ]],
  ];
}

function llc_execute_artifact_tool(PDO $db, array $user, string $chatId, string $name, array $args): array {
  $userId = (string)($user['id'] ?? '');
  $settings = llc_mcp_artifact_settings($db, $userId);
  $maxTokens = (int)$settings['read_tokens'];
  $artifactId = trim((string)($args['artifact_id'] ?? ''));
  if ($artifactId === '') throw new RuntimeException($name . ': artifact_id is required');

  if ($name === 'artifact_info') return llc_artifact_info_result($db, $userId, $chatId, $artifactId);
  if ($name === 'artifact_read') {
    return llc_artifact_read_result(
      $db, $userId, $chatId, $artifactId,
      (int)($args['start_line'] ?? 1),
      (int)($args['line_count'] ?? 200),
      $maxTokens
    );
  }
  if ($name === 'artifact_search') {
    return llc_artifact_search_result(
      $db, $userId, $chatId, $artifactId,
      (string)($args['query'] ?? ''),
      !empty($args['case_sensitive']),
      !empty($args['regex']),
      (int)($args['context_lines'] ?? 2),
      (int)($args['max_matches'] ?? 20),
      $maxTokens
    );
  }
  throw new RuntimeException('Unknown artifact tool: ' . $name);
}

function llc_artifact_delete_chat_files(PDO $db, string $userId, string $chatId): void {
  $st = $db->prepare('SELECT stored_name FROM artifacts WHERE user_id=? AND chat_id=?');
  $st->execute([$userId, $chatId]);
  foreach ($st->fetchAll() as $row) {
    if (!is_array($row)) continue;
    try { @unlink(llc_artifact_absolute_path((string)($row['stored_name'] ?? ''))); }
    catch (Throwable $_) { /* DB cascade still removes metadata */ }
  }
}

function llc_artifact_get(): void {
  $db = llc_db();
  $user = llc_require_user($db);
  $j = llc_read_json();
  $artifactId = trim((string)($j['artifact_id'] ?? ''));
  if ($artifactId === '') llc_json(['error'=>'Missing artifact_id'], 400);
  $row = llc_artifact_row($db, (string)$user['id'], $artifactId, null);
  if (!$row) llc_json(['error'=>'Artifact not found'], 404);
  $content = llc_artifact_content_from_row($row);
  llc_json(['ok'=>true, 'artifact'=>llc_artifact_public_meta($row), 'content'=>$content]);
}
