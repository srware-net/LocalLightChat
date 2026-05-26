<?php
declare(strict_types=1);

// XLSX/ODS/CSV -> plaintext (best-effort tables).
// Design goals:
// - “Vanilla” PHP: no external libraries/frameworks.
// - Prefer ext-zip (ZipArchive); fallback to system `unzip -p` if ZipArchive is missing.
// - Avoid XMLReader/DOM requirements; parse XML with careful regex + strip_tags.

// Output goals:
// - Make rows/columns explicit and stable for both humans + LLMs.
// - Preserve sheet boundaries and the active sheet (XLSX).
// - Keep output bounded for huge files (truncate with explicit notes).

// Defaults are deliberately LLM-sized, but still bounded so one upload cannot
// produce effectively infinite output. Define these constants earlier, e.g. in
// config.php, if a deployment needs smaller/larger extraction windows.
if (!defined('LLC_SHEET2TXT_MAX_SHEETS')) define('LLC_SHEET2TXT_MAX_SHEETS', 50);
if (!defined('LLC_SHEET2TXT_MAX_ROWS_PER_SHEET')) define('LLC_SHEET2TXT_MAX_ROWS_PER_SHEET', 5000);
if (!defined('LLC_SHEET2TXT_MAX_COLS_PER_SHEET')) define('LLC_SHEET2TXT_MAX_COLS_PER_SHEET', 200);
if (!defined('LLC_SHEET2TXT_MAX_CHARS_PER_CELL')) define('LLC_SHEET2TXT_MAX_CHARS_PER_CELL', 2000);
if (!defined('LLC_SHEET2TXT_MAX_TOTAL_CHARS')) define('LLC_SHEET2TXT_MAX_TOTAL_CHARS', 4000000);
if (!defined('LLC_SHEET2TXT_MAX_ADDRESS_PAIRS')) define('LLC_SHEET2TXT_MAX_ADDRESS_PAIRS', 100000);

function llc_sheet2txt_extract(string $filePath, string $ext): string {
  $ext = strtolower(trim($ext));
  if (!is_file($filePath)) throw new RuntimeException('sheet2txt: file not found');

  if ($ext === 'csv') return llc_sheet2txt_csv($filePath);
  if ($ext === 'xlsx') return llc_sheet2txt_xlsx($filePath);
  if ($ext === 'ods') return llc_sheet2txt_ods($filePath);

  throw new RuntimeException('sheet2txt: unsupported extension');
}

// ---------------- utils ----------------

function llc_sheet2txt_cleanup(string $text): string {
  $text = html_entity_decode($text, ENT_QUOTES | ENT_HTML5, 'UTF-8');
  $text = str_replace("\r\n", "\n", $text);
  $text = str_replace("\r", "\n", $text);
  $text = preg_replace("~[ \t]+\n~", "\n", (string)$text);
  $text = preg_replace("~\n{4,}~", "\n\n\n", (string)$text);
  return trim((string)$text);
}

function llc_sheet2txt_attr(string $attrs, string $name): string {
  if (preg_match('~\b' . preg_quote($name, '~') . '\s*=\s*"([^"]*)"~i', $attrs, $m)) return (string)$m[1];
  return '';
}

function llc_sheet2txt_col_to_index(string $col): int {
  // A -> 1, Z -> 26, AA -> 27
  $col = strtoupper(preg_replace('~[^A-Z]~', '', $col));
  if ($col === '') return 0;
  $n = 0;
  $len = strlen($col);
  for ($i = 0; $i < $len; $i++) {
    $c = ord($col[$i]);
    if ($c < 65 || $c > 90) continue;
    $n = $n * 26 + ($c - 64);
  }
  return $n;
}

function llc_sheet2txt_index_to_col(int $idx): string {
  // 1 -> A, 26 -> Z, 27 -> AA
  if ($idx <= 0) return '';
  $s = '';
  while ($idx > 0) {
    $idx--; // 0-based
    $s = chr(($idx % 26) + 65) . $s;
    $idx = intdiv($idx, 26);
  }
  return $s;
}

function llc_sheet2txt_range_str(int $minRow, int $minCol, int $maxRow, int $maxCol): string {
  if ($minRow <= 0 || $minCol <= 0 || $maxRow <= 0 || $maxCol <= 0) return '';
  return llc_sheet2txt_index_to_col($minCol) . $minRow . ':' . llc_sheet2txt_index_to_col($maxCol) . $maxRow;
}

function llc_sheet2txt_norm_cell(string $v): string {
  $v = (string)$v;
  $v = html_entity_decode($v, ENT_QUOTES | ENT_HTML5, 'UTF-8');
  $v = str_replace(["\r\n", "\r"], "\n", $v);
  $v = str_replace(["\t"], "\\t", $v);
  $v = str_replace(["\n"], "\\n", $v);
  $v = preg_replace('~[ \x{00A0}]+~u', ' ', $v);
  $v = trim((string)$v);
  if (strlen($v) > LLC_SHEET2TXT_MAX_CHARS_PER_CELL) {
    $v = substr($v, 0, LLC_SHEET2TXT_MAX_CHARS_PER_CELL) . '…';
  }
  return $v;
}

/**
 * Render a sparse grid (row=>[col=>val]) as a deterministic, LLM-friendly block.
 * Output contains BOTH:
 *  - A cell-address list (A1=..., B1=..., ...) which stays unambiguous even if whitespace collapses.
 *  - A markdown pipe table for human readability.
 * Returns [text, truncated(bool)].
 */
function llc_sheet2txt_render_sparse_block(array $cells, int $minRow, int $minCol, int $maxRow, int $maxCol, int $rowLimit, int $colLimit): array {
  $showRows = min($maxRow - $minRow + 1, $rowLimit);
  $showCols = min($maxCol - $minCol + 1, $colLimit);

  // 1) Address=value list (within the preview grid)
  $pairs = [];
  $pairCap = LLC_SHEET2TXT_MAX_ADDRESS_PAIRS; // safety cap to avoid absurdly long single sections
  $pairCount = 0;
  for ($rOff = 0; $rOff < $showRows; $rOff++) {
    $r = $minRow + $rOff;
    $rowMap = $cells[$r] ?? [];
    for ($cOff = 0; $cOff < $showCols; $cOff++) {
      $c = $minCol + $cOff;
      $addr = llc_sheet2txt_index_to_col($c) . (string)$r;
      $val = isset($rowMap[$c]) ? llc_sheet2txt_norm_cell((string)$rowMap[$c]) : '';
      // Keep empties explicit: "B2=" rather than omitting them.
      $pairs[] = $addr . '=' . $val;
      $pairCount++;
      if ($pairCount >= $pairCap) break 2;
    }
  }
  // Chunk into lines so UIs/LLMs don't choke on a single mega-line.
  $pairLines = [];
  $chunk = [];
  foreach ($pairs as $i => $p) {
    $chunk[] = $p;
    if (count($chunk) >= 40) { $pairLines[] = implode('; ', $chunk) . ';'; $chunk = []; }
  }
  if ($chunk) $pairLines[] = implode('; ', $chunk) . ';';

  // 2) Markdown pipe table
  $lines = [];
  $hdr = ['row'];
  for ($c = 0; $c < $showCols; $c++) $hdr[] = llc_sheet2txt_index_to_col($minCol + $c);
  $lines[] = '| ' . implode(' | ', $hdr) . ' |';
  $sep = array_fill(0, count($hdr), '---');
  $sep[0] = '---:'; // row numbers right-ish
  $lines[] = '| ' . implode(' | ', $sep) . ' |';

  for ($rOff = 0; $rOff < $showRows; $rOff++) {
    $r = $minRow + $rOff;
    $row = [(string)$r];
    $rowMap = $cells[$r] ?? [];
    for ($cOff = 0; $cOff < $showCols; $cOff++) {
      $c = $minCol + $cOff;
      $v = isset($rowMap[$c]) ? llc_sheet2txt_norm_cell((string)$rowMap[$c]) : '';
      // Escape pipes so markdown tables don't break.
      $v = str_replace('|', '\\|', $v);
      $row[] = $v;
    }
    $lines[] = '| ' . implode(' | ', $row) . ' |';
  }

  $truncated = ($maxRow - $minRow + 1) > $rowLimit || ($maxCol - $minCol + 1) > $colLimit;
  $out = [];
  $out[] = "Cells (address=value) within preview grid:";
  $out = array_merge($out, $pairLines);
  $out[] = '';
  $out[] = "Table (markdown):";
  $out = array_merge($out, $lines);
  return [implode("\n", $out), $truncated];
}

function llc_sheet2txt_safe_repeat(int $n, int $cap): int {
  if ($n < 1) return 1;
  if ($n > $cap) return $cap;
  return $n;
}

function llc_sheet2txt_trim_trailing_empties(array $cells): array {
  for ($i = count($cells) - 1; $i >= 0; $i--) {
    if (trim((string)$cells[$i]) !== '') break;
    array_pop($cells);
  }
  return $cells;
}


function llc_sheet2txt_float_str(string $raw): string {
  $raw = trim($raw);
  if ($raw === '') return $raw;
  if (!is_numeric($raw)) return $raw;
  $f = (float)$raw;
  if (!is_finite($f)) return $raw;
  $s = rtrim(rtrim(sprintf('%.12F', $f), '0'), '.');
  if ($s === '-0') $s = '0';
  return $s;
}

function llc_sheet2txt_append_raw(string $display, string $raw): string {
  $display = trim($display);
  $raw = trim($raw);
  if ($raw === '' || $display === '') return $display;
  $rawNorm = llc_sheet2txt_float_str($raw);
  $dispNorm = llc_sheet2txt_float_str($display);
  if ($display === $raw || $dispNorm === $rawNorm) return $display;
  return $display . ' [raw: ' . $rawNorm . ']';
}

function llc_sheet2txt_decimal_places_from_format(string $formatCode): int {
  $fmt = html_entity_decode($formatCode, ENT_QUOTES | ENT_HTML5, 'UTF-8');
  $fmt = preg_replace('~"(?:[^"]|"")*"~', '', $fmt);
  $fmt = str_replace(chr(92), '', (string)$fmt);
  $fmt = preg_replace('~\[[^\]]*\]~', '', (string)$fmt);
  $fmt = preg_replace('~;.*$~', '', (string)$fmt);
  if (preg_match('~\.([0#?]+)~', (string)$fmt, $m)) return min(strlen((string)$m[1]), 8);
  return 0;
}

function llc_sheet2txt_number_format(float $value, int $decimals, bool $group, string $decimalSep='.', string $thousandSep=','): string {
  if (!is_finite($value)) return '';
  return number_format($value, max(0, $decimals), $decimalSep, $group ? $thousandSep : '');
}

// ---------------- zip read (ZipArchive or system unzip) ----------------

function llc_sheet2txt_unzip_path(): string {
  $unzip = trim((string)shell_exec('command -v unzip 2>/dev/null'));
  return is_string($unzip) ? $unzip : '';
}

function llc_sheet2txt_unzip_read_entry(string $zipPath, string $entryName): string {
  $unzip = llc_sheet2txt_unzip_path();
  if ($unzip === '') throw new RuntimeException('sheet2txt: ZipArchive missing and unzip not available');

  $cmd = $unzip . ' -p ' . escapeshellarg($zipPath) . ' ' . escapeshellarg($entryName);
  $spec = [1 => ['pipe','w'], 2 => ['pipe','w']];
  $proc = proc_open($cmd, $spec, $pipes);
  if (!is_resource($proc)) throw new RuntimeException('sheet2txt: failed to run unzip');
  $stdout = stream_get_contents($pipes[1]);
  $stderr = stream_get_contents($pipes[2]);
  fclose($pipes[1]);
  fclose($pipes[2]);
  $code = proc_close($proc);

  if (!is_string($stdout)) $stdout = '';
  if ($code !== 0 || $stdout === '') {
    $hint = is_string($stderr) ? trim($stderr) : '';
    if ($hint !== '') $hint = ' (' . substr($hint, 0, 160) . ')';
    throw new RuntimeException('sheet2txt: missing ' . $entryName . $hint);
  }
  return $stdout;
}

function llc_sheet2txt_zip_read(string $zipPath, ?ZipArchive $zip, string $entryName, bool $required=true): string {
  $data = '';
  if ($zip instanceof ZipArchive) {
    $tmp = $zip->getFromName($entryName);
    if (is_string($tmp)) $data = $tmp;
  } else {
    try {
      $data = llc_sheet2txt_unzip_read_entry($zipPath, $entryName);
    } catch (Throwable $e) {
      if ($required) throw $e;
      return '';
    }
  }
  if (!is_string($data) || $data === '') {
    if ($required) throw new RuntimeException('sheet2txt: missing ' . $entryName);
    return '';
  }
  return $data;
}

// ---------------- CSV ----------------

function llc_sheet2txt_csv_decode_to_utf8(string $raw): array {
  // Returns [utf8 string, detected encoding label]. Keeps CSV parsing in UTF-8.
  if (str_starts_with($raw, "\xEF\xBB\xBF")) return [substr($raw, 3), 'UTF-8 BOM'];
  if (str_starts_with($raw, "\xFF\xFE")) {
    $converted = function_exists('mb_convert_encoding') ? mb_convert_encoding(substr($raw, 2), 'UTF-8', 'UTF-16LE') : $raw;
    return [$converted, 'UTF-16LE BOM'];
  }
  if (str_starts_with($raw, "\xFE\xFF")) {
    $converted = function_exists('mb_convert_encoding') ? mb_convert_encoding(substr($raw, 2), 'UTF-8', 'UTF-16BE') : $raw;
    return [$converted, 'UTF-16BE BOM'];
  }

  if (function_exists('mb_detect_encoding') && function_exists('mb_convert_encoding')) {
    $enc = mb_detect_encoding($raw, ['UTF-8','Windows-1252','ISO-8859-1','ISO-8859-15'], true);
    if (is_string($enc) && $enc !== '') {
      if (strtoupper($enc) !== 'UTF-8') return [mb_convert_encoding($raw, 'UTF-8', $enc), $enc];
      return [$raw, 'UTF-8'];
    }
  }

  if (function_exists('iconv')) {
    // Common Excel/Windows fallback. //IGNORE avoids hard-failing on a few bad bytes.
    $converted = @iconv('Windows-1252', 'UTF-8//IGNORE', $raw);
    if (is_string($converted) && $converted !== '') return [$converted, 'Windows-1252 fallback'];
  }

  return [$raw, 'unknown/assumed UTF-8'];
}

function llc_sheet2txt_csv_guess_delim(string $sample): string {
  $cands = [',',';','\t','|'];
  $best = ',';
  $bestScore = -1;
  $lines = preg_split("~\r\n|\r|\n~", $sample);
  $lines = array_slice(array_filter($lines, fn($l)=>trim((string)$l)!==''), 0, 5);
  if (!$lines) return $best;
  foreach ($cands as $d) {
    $score = 0;
    foreach ($lines as $l) $score += substr_count((string)$l, $d);
    if ($score > $bestScore) { $bestScore = $score; $best = $d; }
  }
  return $best;
}

function llc_sheet2txt_csv(string $filePath): string {
  $raw = file_get_contents($filePath);
  if (!is_string($raw)) throw new RuntimeException('sheet2txt: failed to read csv');
  [$raw, $detectedEncoding] = llc_sheet2txt_csv_decode_to_utf8($raw);

  $delim = llc_sheet2txt_csv_guess_delim(substr($raw, 0, 16*1024));
  $tmp = tmpfile();
  if ($tmp === false) throw new RuntimeException('sheet2txt: tmpfile failed');
  fwrite($tmp, $raw);
  rewind($tmp);

  $cells = [];
  $maxCol = 0;
  $rowIdx = 0;
  $hasMoreRows = false;
  while (($row = fgetcsv($tmp, 0, $delim)) !== false) {
    if (!is_array($row)) continue;
    $rowIdx++;
    if ($rowIdx > LLC_SHEET2TXT_MAX_ROWS_PER_SHEET + 1) { $hasMoreRows = true; break; }

    $colIdx = 0;
    foreach ($row as $v) {
      $colIdx++;
      if ($colIdx > LLC_SHEET2TXT_MAX_COLS_PER_SHEET + 1) break;
      $v = (string)$v;
      $v = str_replace(["\r\n","\r"], "\n", $v);
      $v = trim((string)$v);
      if ($v !== '') {
        $cells[$rowIdx][$colIdx] = $v;
        if ($colIdx > $maxCol) $maxCol = $colIdx;
      }
    }
    if ($colIdx > $maxCol) $maxCol = $colIdx;
  }
  fclose($tmp);

  $maxRowSeen = max(1, $rowIdx);
  [$block, $truncGrid] = llc_sheet2txt_render_sparse_block(
    $cells,
    1,
    1,
    $maxRowSeen,
    max(1, $maxCol),
    LLC_SHEET2TXT_MAX_ROWS_PER_SHEET,
    LLC_SHEET2TXT_MAX_COLS_PER_SHEET
  );

  $range = llc_sheet2txt_range_str(1, 1, $maxRowSeen, max(1, $maxCol));
  $meta = [];
  $meta[] = "== Spreadsheet: CSV ==";
  $meta[] = "Encoding detected: " . $detectedEncoding;
  $meta[] = "Delimiter guess: " . ($delim === "\t" ? "TAB" : $delim);
  $meta[] = "== Sheet 1/1: CSV ==";
  $meta[] = "Used range (best-effort): $range";
  $meta[] = "Encoding notes: output includes (1) a cell-address list like A1=... and (2) a markdown table with explicit row/column headers.";
  $meta[] = $block;

  $trunc = $truncGrid || $hasMoreRows;
  if ($trunc) {
    $meta[] = '';
    $meta[] = "[truncated: showing up to " . LLC_SHEET2TXT_MAX_ROWS_PER_SHEET . " rows and " . LLC_SHEET2TXT_MAX_COLS_PER_SHEET . " columns]";
  }

  return llc_sheet2txt_cleanup(implode("\n", $meta));
}

// ---------------- XLSX ----------------

function llc_sheet2txt_xlsx_shared_strings(string $zipPath, ?ZipArchive $zip): array {
  $xml = llc_sheet2txt_zip_read($zipPath, $zip, 'xl/sharedStrings.xml', false);
  if ($xml === '') return [];
  $out = [];
  if (preg_match_all('~<si\b[^>]*>(.*?)</si>~is', $xml, $m)) {
    foreach ($m[1] as $si) {
      $t = '';
      if (preg_match_all('~<t\b[^>]*>(.*?)</t>~is', (string)$si, $mm)) {
        foreach ($mm[1] as $part) $t .= (string)$part;
      }
      $out[] = html_entity_decode(strip_tags($t), ENT_QUOTES | ENT_HTML5, 'UTF-8');
    }
  }
  return $out;
}

function llc_sheet2txt_xlsx_sheet_map(string $zipPath, ?ZipArchive $zip): array {
  // Ordered list: [ ['name'=>..., 'path'=>...], ... ]
  $workbook = llc_sheet2txt_zip_read($zipPath, $zip, 'xl/workbook.xml', false);
  $rels = llc_sheet2txt_zip_read($zipPath, $zip, 'xl/_rels/workbook.xml.rels', false);
  if ($workbook === '' || $rels === '') return [];

  $ridToTarget = [];
  if (preg_match_all('~<Relationship\b([^>]*)/>~i', $rels, $rm, PREG_SET_ORDER)) {
    foreach ($rm as $rel) {
      $attrs = (string)($rel[1] ?? '');
      $id = llc_sheet2txt_attr($attrs, 'Id');
      $target = llc_sheet2txt_attr($attrs, 'Target');
      if ($id !== '' && $target !== '') {
        $target = ltrim($target, '/');
        if (!str_starts_with($target, 'xl/')) $target = 'xl/' . $target;
        $ridToTarget[$id] = $target;
      }
    }
  }

  $sheets = [];
  if (preg_match_all('~<sheet\b([^>]*)/>~i', $workbook, $sm, PREG_SET_ORDER)) {
    foreach ($sm as $sh) {
      $attrs = (string)($sh[1] ?? '');
      $name = llc_sheet2txt_attr($attrs, 'name');
      $rid  = llc_sheet2txt_attr($attrs, 'r:id');
      $path = ($rid !== '' && isset($ridToTarget[$rid])) ? $ridToTarget[$rid] : '';
      if ($path !== '') $sheets[] = ['name'=>($name !== '' ? $name : $path), 'path'=>$path];
    }
  }
  return $sheets;
}

function llc_sheet2txt_xlsx_active_tab(string $workbookXml): int {
  // 0-based activeTab index; default 0
  if (preg_match('~<workbookView\b[^>]*\bactiveTab\s*=\s*"(\d+)"~i', $workbookXml, $m)) {
    return (int)$m[1];
  }
  return 0;
}

function llc_sheet2txt_xlsx_parse_dimension(string $xml): array {
  // Returns [minRow,minCol,maxRow,maxCol] or [0,0,0,0]
  if (!preg_match('~<dimension\b[^>]*\bref\s*=\s*"([^"]+)"~i', $xml, $m)) return [0,0,0,0];
  $ref = (string)$m[1];
  $ref = trim($ref);
  if ($ref === '') return [0,0,0,0];
  // examples: A1, A1:D10
  $parts = explode(':', $ref);
  $a = $parts[0] ?? '';
  $b = $parts[1] ?? $a;
  if (!preg_match('~^([A-Z]+)(\d+)$~i', $a, $ma)) return [0,0,0,0];
  if (!preg_match('~^([A-Z]+)(\d+)$~i', $b, $mb)) return [0,0,0,0];
  $minCol = llc_sheet2txt_col_to_index((string)$ma[1]);
  $minRow = (int)$ma[2];
  $maxCol = llc_sheet2txt_col_to_index((string)$mb[1]);
  $maxRow = (int)$mb[2];
  if ($minRow <= 0 || $minCol <= 0 || $maxRow <= 0 || $maxCol <= 0) return [0,0,0,0];
  if ($maxRow < $minRow) { $t = $maxRow; $maxRow = $minRow; $minRow = $t; }
  if ($maxCol < $minCol) { $t = $maxCol; $maxCol = $minCol; $minCol = $t; }
  return [$minRow,$minCol,$maxRow,$maxCol];
}


function llc_sheet2txt_xlsx_parse_merged_cells(string $xml, array $cells): array {
  // Returns a bounded list of merge ranges with their top-left/anchor value when available.
  $merged = [];
  if (!preg_match_all('~<mergeCell\b[^>]*\bref\s*=\s*"([^"]+)"[^>]*/>~i', $xml, $mm)) return $merged;

  foreach ($mm[1] as $ref) {
    $ref = trim((string)$ref);
    if ($ref === '') continue;
    $anchor = '';
    $parts = explode(':', $ref);
    $a = $parts[0] ?? '';
    if (preg_match('~^([A-Z]+)(\d+)$~i', $a, $ma)) {
      $col = llc_sheet2txt_col_to_index((string)$ma[1]);
      $row = (int)$ma[2];
      $anchor = isset($cells[$row][$col]) ? llc_sheet2txt_norm_cell((string)$cells[$row][$col]) : '';
    }
    $merged[] = ['ref'=>$ref, 'anchor'=>$anchor];
    if (count($merged) >= 200) break;
  }
  return $merged;
}

function llc_sheet2txt_render_merged_cells(array $merged): string {
  if (!$merged) return '';
  $lines = ['Merged cells:'];
  foreach ($merged as $m) {
    $ref = (string)($m['ref'] ?? '');
    if ($ref === '') continue;
    $anchor = (string)($m['anchor'] ?? '');
    $lines[] = '- ' . $ref . ($anchor !== '' ? '="' . str_replace('"', '\\"', $anchor) . '"' : '');
  }
  return implode("\n", $lines);
}

function llc_sheet2txt_xlsx_builtin_date_numfmt_ids(): array {
  // Built-in Excel/OpenXML number formats that represent dates/times.
  // 14-22 are the common date/time formats; 27-36 and 50-58 are localized
  // date formats; 45-47 are elapsed/time formats.
  return array_fill_keys([
    14,15,16,17,18,19,20,21,22,
    27,28,29,30,31,32,33,34,35,36,
    45,46,47,
    50,51,52,53,54,55,56,57,58
  ], true);
}

function llc_sheet2txt_xlsx_numfmt_looks_like_date(string $formatCode): bool {
  $fmt = strtolower(html_entity_decode($formatCode, ENT_QUOTES | ENT_HTML5, 'UTF-8'));
  if ($fmt === '') return false;

  // Strip quoted literals, escaped chars, bracket annotations, underscores and
  // fill markers so tokens like d/m/y/h/s can be detected without noise.
  $fmt = preg_replace('~"(?:[^"]|"")*"~', '', $fmt);
  $fmt = str_replace(chr(92), '', (string)$fmt);
  $fmt = preg_replace('~\[[^\]]*\]~', '', (string)$fmt);
  $fmt = preg_replace('~_.|\*.~', '', (string)$fmt);
  $fmt = preg_replace('~;.*$~', '', (string)$fmt); // inspect the positive section
  $fmt = (string)$fmt;

  // Date formats have y/d tokens. Time-only formats have h/s tokens and often m.
  return (bool)preg_match('~[dy]|h{1,2}|s{1,2}|am/pm|a/p~i', $fmt);
}

function llc_sheet2txt_xlsx_builtin_numfmt(int $numFmtId): string {
  $map = [
    1=>'0', 2=>'0.00', 3=>'#,##0', 4=>'#,##0.00',
    5=>'$#,##0_);($#,##0)', 6=>'$#,##0_);[Red]($#,##0)',
    7=>'$#,##0.00_);($#,##0.00)', 8=>'$#,##0.00_);[Red]($#,##0.00)',
    9=>'0%', 10=>'0.00%', 11=>'0.00E+00', 12=>'# ?/?', 13=>'# ??/??',
    37=>'#,##0;(#,##0)', 38=>'#,##0;[Red](#,##0)',
    39=>'#,##0.00;(#,##0.00)', 40=>'#,##0.00;[Red](#,##0.00)',
    44=>'_($* #,##0.00_);_($* (#,##0.00);_($* "-"??_);_(@_)'
  ];
  return $map[$numFmtId] ?? '';
}

function llc_sheet2txt_xlsx_extract_currency_symbol(string $formatCode): string {
  $fmt = html_entity_decode($formatCode, ENT_QUOTES | ENT_HTML5, 'UTF-8');
  if (preg_match('~\[\$([^\]-]+)(?:-[0-9A-Fa-f]+)?\]~u', $fmt, $m)) return trim((string)$m[1]);
  if (preg_match('~[€£¥₹₽₩₪₫₴₺₦₱₲฿₡₵₸₼₭₮₾₿]\s*|\$~u', $fmt, $m)) return trim((string)$m[0]);
  if (preg_match('~"\s*([^"0#?,.\s]{1,5})\s*"~u', $fmt, $m)) return trim((string)$m[1]);
  return '';
}

function llc_sheet2txt_xlsx_analyze_numfmt(int $numFmtId, string $formatCode): array {
  if ($formatCode === '') $formatCode = llc_sheet2txt_xlsx_builtin_numfmt($numFmtId);
  $fmt = html_entity_decode($formatCode, ENT_QUOTES | ENT_HTML5, 'UTF-8');
  $fmtLower = strtolower($fmt);
  $fmtNoLit = preg_replace('~"(?:[^"]|"")*"~', '', $fmtLower);
  $fmtNoLit = str_replace(chr(92), '', (string)$fmtNoLit);
  $fmtNoLit = preg_replace('~\[[^\]]*\]~', '', (string)$fmtNoLit);
  $fmtNoLit = preg_replace('~_.|\*.~', '', (string)$fmtNoLit);
  $positive = preg_replace('~;.*$~', '', (string)$fmtNoLit);

  $isPercent = strpos((string)$positive, '%') !== false;
  $currency = llc_sheet2txt_xlsx_extract_currency_symbol($fmt);
  $isCurrency = $currency !== '' || in_array($numFmtId, [5,6,7,8,44], true);
  if ($currency === '' && in_array($numFmtId, [5,6,7,8,44], true)) $currency = '$';
  $hasGroup = strpos((string)$positive, '#,##') !== false || strpos((string)$positive, '0,') !== false;
  $decimals = llc_sheet2txt_decimal_places_from_format($fmt);
  $isNumber = $isPercent || $isCurrency || $hasGroup || in_array($numFmtId, [1,2,3,4,37,38,39,40], true);

  return [
    'format'=>$formatCode,
    'is_percent'=>$isPercent,
    'is_currency'=>$isCurrency,
    'currency_symbol'=>$currency,
    'has_group'=>$hasGroup,
    'decimals'=>$decimals,
    'is_number_format'=>$isNumber,
  ];
}

function llc_sheet2txt_xlsx_parse_styles(string $zipPath, ?ZipArchive $zip): array {
  // Returns: style index => ['is_date'=>bool, 'format'=>string, plus numeric-format hints]
  $xml = llc_sheet2txt_zip_read($zipPath, $zip, 'xl/styles.xml', false);
  if ($xml === '') return [];

  $custom = [];
  if (preg_match_all('~<numFmt\b([^>]*)/>~is', $xml, $nm, PREG_SET_ORDER)) {
    foreach ($nm as $n) {
      $attrs = (string)($n[1] ?? '');
      $id = (int)llc_sheet2txt_attr($attrs, 'numFmtId');
      $fmt = llc_sheet2txt_attr($attrs, 'formatCode');
      if ($id > 0 && $fmt !== '') $custom[$id] = $fmt;
    }
  }

  $builtinDateIds = llc_sheet2txt_xlsx_builtin_date_numfmt_ids();
  $styles = [];
  if (preg_match('~<cellXfs\b[^>]*>(.*?)</cellXfs>~is', $xml, $xm)) {
    $body = (string)$xm[1];
    if (preg_match_all('~<xf\b([^>]*)/?>~is', $body, $xfm, PREG_SET_ORDER)) {
      foreach ($xfm as $xf) {
        $attrs = (string)($xf[1] ?? '');
        $numFmtId = (int)llc_sheet2txt_attr($attrs, 'numFmtId');
        $fmt = $custom[$numFmtId] ?? llc_sheet2txt_xlsx_builtin_numfmt($numFmtId);
        $isDate = isset($builtinDateIds[$numFmtId]) || ($fmt !== '' && llc_sheet2txt_xlsx_numfmt_looks_like_date($fmt));
        $num = llc_sheet2txt_xlsx_analyze_numfmt($numFmtId, $fmt);
        $styles[] = array_merge(['is_date'=>$isDate, 'format'=>$fmt, 'numFmtId'=>$numFmtId], $num);
      }
    }
  }
  return $styles;
}

function llc_sheet2txt_xlsx_date1904(string $workbookXml): bool {
  return (bool)preg_match('~<workbookPr\b[^>]*\bdate1904\s*=\s*"(?:1|true)"~i', $workbookXml);
}


function llc_sheet2txt_xlsx_date_php_format(string $formatCode): string {
  $fmt = strtolower(html_entity_decode($formatCode, ENT_QUOTES | ENT_HTML5, 'UTF-8'));
  if ($fmt === '') return '';
  $fmt = preg_replace('~;.*$~', '', $fmt);
  $fmt = preg_replace('~"(?:[^"]|"")*"~', '', (string)$fmt);
  $fmt = preg_replace('~\\\\(.)~', '$1', (string)$fmt);
  $fmt = preg_replace('~\[[^\]]*\]~', '', (string)$fmt);
  $fmt = preg_replace('~_.|\*.~', '', (string)$fmt);
  $fmt = trim((string)$fmt);
  if ($fmt === '') return '';

  // Keep only common date separators/tokens. Month names are intentionally
  // rendered in English by PHP when formats use mmm/mmmm; numeric dates stay numeric.
  $out = '';
  $len = strlen($fmt);
  for ($i = 0; $i < $len; ) {
    $ch = $fmt[$i];
    if ($ch === 'y') {
      $n = strspn($fmt, 'y', $i);
      $out .= ($n >= 4) ? 'Y' : 'y';
      $i += $n;
    } elseif ($ch === 'd') {
      $n = strspn($fmt, 'd', $i);
      $out .= ($n >= 4) ? 'l' : (($n === 3) ? 'D' : (($n === 2) ? 'd' : 'j'));
      $i += $n;
    } elseif ($ch === 'm') {
      $n = strspn($fmt, 'm', $i);
      $out .= ($n >= 4) ? 'F' : (($n === 3) ? 'M' : (($n === 2) ? 'm' : 'n'));
      $i += $n;
    } elseif (strpos('./- ', $ch) !== false) {
      $out .= $ch;
      $i++;
    } else {
      // Unknown date-format tokens are ignored instead of leaking Excel syntax.
      $i++;
    }
  }
  $out = trim($out);
  return preg_match('~[YymndjDFMl]~', $out) ? $out : '';
}


function llc_sheet2txt_xlsx_format_number(string $raw, array $style): string {
  $raw = trim($raw);
  if ($raw === '' || !is_numeric($raw)) return $raw;
  if (empty($style['is_number_format'])) return $raw;

  $value = (float)$raw;
  $decimals = isset($style['decimals']) ? (int)$style['decimals'] : 0;
  $group = !empty($style['has_group']) || !empty($style['is_currency']);

  if (!empty($style['is_percent'])) {
    $display = llc_sheet2txt_number_format($value * 100.0, $decimals, $group, '.', ',') . '%';
    return llc_sheet2txt_append_raw($display, $raw);
  }

  if (!empty($style['is_currency'])) {
    $symbol = trim((string)($style['currency_symbol'] ?? ''));
    $isEuro = ($symbol === '€' || stripos($symbol, 'eur') !== false);
    $displayNumber = $isEuro
      ? llc_sheet2txt_number_format($value, $decimals, true, ',', '.')
      : llc_sheet2txt_number_format($value, $decimals, true, '.', ',');
    if ($symbol === '') $symbol = '¤';
    $display = $isEuro ? ($displayNumber . ' ' . $symbol) : ($symbol . $displayNumber);
    return llc_sheet2txt_append_raw($display, $raw);
  }

  if ($group || $decimals > 0) {
    $display = llc_sheet2txt_number_format($value, $decimals, $group, '.', ',');
    return llc_sheet2txt_append_raw($display, $raw);
  }

  return $raw;
}

function llc_sheet2txt_xlsx_format_serial_date(string $raw, bool $date1904, string $formatCode=''): string {
  $raw = trim($raw);
  if ($raw === '' || !is_numeric($raw)) return $raw;

  $serial = (float)$raw;
  if (!is_finite($serial)) return $raw;

  $whole = (int)floor($serial);
  $frac = $serial - $whole;
  if ($frac < 0) $frac = 0.0;

  try {
    $base = new DateTimeImmutable($date1904 ? '1904-01-01 00:00:00' : '1899-12-30 00:00:00', new DateTimeZone('UTC'));
    $seconds = (int)round($frac * 86400);
    $dt = $base->modify(($whole >= 0 ? '+' : '') . $whole . ' days')->modify('+' . $seconds . ' seconds');
    if (!$dt) return $raw;
  } catch (Throwable $e) {
    return $raw;
  }

  $fmt = strtolower(html_entity_decode($formatCode, ENT_QUOTES | ENT_HTML5, 'UTF-8'));
  $fmtNoLit = preg_replace('~"(?:[^"]|"")*"~', '', $fmt);
  $fmtNoLit = str_replace(chr(92), '', (string)$fmtNoLit);
  $fmtNoLit = preg_replace('~\[[^\]]*\]~', '', (string)$fmtNoLit);
  $hasDate = (bool)preg_match('~[dy]~', (string)$fmtNoLit);
  $hasTime = (bool)preg_match('~h{1,2}|s{1,2}|am/pm|a/p~', (string)$fmtNoLit);

  if (!$hasDate && $hasTime) return $dt->format('H:i:s');
  if ($hasDate && $hasTime) return $dt->format('Y-m-d H:i:s');

  $phpFmt = llc_sheet2txt_xlsx_date_php_format($formatCode);
  if ($phpFmt !== '') return $dt->format($phpFmt);
  return $dt->format('d.m.Y');
}

function llc_sheet2txt_xlsx_parse_sheet_sparse(string $xml, array $sharedStrings, array $styles=[], bool $date1904=false): array {
  // Returns [cells,minRow,minCol,maxRow,maxCol]. Formula cells keep their displayed/cache value and add [formula: =...].
  $cells = [];
  $minRow = PHP_INT_MAX;
  $minCol = PHP_INT_MAX;
  $maxRow = 0;
  $maxCol = 0;

  // Parse all cells (sparse). XLSX often contains empty self-closing cells
  // like <c r="C1"/> between real cells. A plain <c ...>(.*?)</c> regex
  // accidentally treats those as opening tags and steals the next real cell's
  // value, shifting dates/numbers into the wrong column. Match self-closing
  // cells separately so they can be ignored without swallowing following cells.
  if (preg_match_all('~<c\b([^>]*)/>\s*|<c\b([^>]*)>(.*?)</c>~is', $xml, $cm, PREG_SET_ORDER)) {
    foreach ($cm as $c) {
      $isSelfClosing = isset($c[1]) && trim((string)$c[1]) !== '';
      $attrs = $isSelfClosing ? (string)($c[1] ?? '') : (string)($c[2] ?? '');
      $body  = $isSelfClosing ? '' : (string)($c[3] ?? '');

      $ref = llc_sheet2txt_attr($attrs, 'r');
      if (!preg_match('~^([A-Z]+)(\d+)$~i', (string)$ref, $rm)) continue;
      $col = llc_sheet2txt_col_to_index((string)$rm[1]);
      $row = (int)$rm[2];
      if ($row <= 0 || $col <= 0) continue;

      $t = strtolower(llc_sheet2txt_attr($attrs, 't'));
      $styleIdxRaw = llc_sheet2txt_attr($attrs, 's');
      $styleIdx = ($styleIdxRaw !== '' && ctype_digit($styleIdxRaw)) ? (int)$styleIdxRaw : -1;
      $style = ($styleIdx >= 0 && isset($styles[$styleIdx]) && is_array($styles[$styleIdx])) ? $styles[$styleIdx] : [];
      $formula = '';
      if (preg_match('~<f\b[^>]*>(.*?)</f>~is', $body, $fm)) {
        $formula = trim(html_entity_decode(strip_tags((string)$fm[1]), ENT_QUOTES | ENT_HTML5, 'UTF-8'));
        if ($formula !== '' && $formula[0] !== '=') $formula = '=' . $formula;
      } else if (preg_match('~<f\b([^>]*)/>~is', $body, $fm)) {
        // Shared/array formulas can appear as a self-closing <f .../> with only attributes.
        // We cannot reconstruct the formula body without the shared master here, but marking it is better than silently dropping it.
        $ftype = strtolower(llc_sheet2txt_attr((string)$fm[1], 't'));
        if ($ftype !== '') $formula = '[' . $ftype . ' formula]';
      }
      $v = '';

      if ($t === 'inlinestr') {
        if (preg_match_all('~<t\b[^>]*>(.*?)</t>~is', $body, $tm)) {
          foreach ($tm[1] as $part) $v .= (string)$part;
        }
        $v = html_entity_decode(strip_tags($v), ENT_QUOTES | ENT_HTML5, 'UTF-8');
      } else {
        $vv = '';
        if (preg_match('~<v\b[^>]*>(.*?)</v>~is', $body, $vm)) $vv = (string)$vm[1];
        $vv = html_entity_decode(strip_tags($vv), ENT_QUOTES | ENT_HTML5, 'UTF-8');

        if ($t === 's') {
          $si = (int)$vv;
          $v = $sharedStrings[$si] ?? '';
        } else if ($t === 'b') {
          $v = ($vv === '1') ? 'TRUE' : (($vv === '0') ? 'FALSE' : $vv);
        } else if ($t === 'd') {
          $v = $vv;
        } else {
          // n (default), str, e -> keep raw unless the cell style marks an Excel date/time serial.
          $v = $vv;
          if (($t === '' || $t === 'n') && !empty($style['is_date'])) {
            $v = llc_sheet2txt_xlsx_format_serial_date($vv, $date1904, (string)($style['format'] ?? ''));
          } else if (($t === '' || $t === 'n') && !empty($style['is_number_format'])) {
            $v = llc_sheet2txt_xlsx_format_number($vv, $style);
          }
          if ($v === '' && preg_match('~<f\b[^>]*>(.*?)</f>~is', $body, $fm)) {
            $f = html_entity_decode(strip_tags((string)$fm[1]), ENT_QUOTES | ENT_HTML5, 'UTF-8');
            if (trim($f) !== '') $v = '=' . trim($f);
          }
        }
      }

      $v = trim((string)$v);
      if ($formula !== '') {
        if ($v === '') {
          $v = $formula;
        } else if ($v !== $formula) {
          $v .= ' [formula: ' . $formula . ']';
        }
      }
      if ($v === '') continue;

      $cells[$row][$col] = $v;
      if ($row < $minRow) $minRow = $row;
      if ($col < $minCol) $minCol = $col;
      if ($row > $maxRow) $maxRow = $row;
      if ($col > $maxCol) $maxCol = $col;
    }
  }

  if ($maxRow === 0 || $maxCol === 0 || $minRow === PHP_INT_MAX || $minCol === PHP_INT_MAX) {
    // No non-empty cells found.
    return [[], 0, 0, 0, 0];
  }
  return [$cells, $minRow, $minCol, $maxRow, $maxCol];
}

function llc_sheet2txt_xlsx(string $filePath): string {
  $zip = class_exists('ZipArchive') ? new ZipArchive() : null;
  if ($zip instanceof ZipArchive) {
    $ok = $zip->open($filePath);
    if ($ok !== true) throw new RuntimeException('sheet2txt: invalid zip container');
  } else {
    // will be read via system unzip; validate availability early
    if (llc_sheet2txt_unzip_path() === '') throw new RuntimeException('sheet2txt: ZipArchive missing and unzip not available');
  }

  try {
    $shared = llc_sheet2txt_xlsx_shared_strings($filePath, $zip);
    $workbookXml = llc_sheet2txt_zip_read($filePath, $zip, 'xl/workbook.xml', false);
    $activeTab = ($workbookXml !== '') ? llc_sheet2txt_xlsx_active_tab($workbookXml) : 0;
    $date1904 = ($workbookXml !== '') ? llc_sheet2txt_xlsx_date1904($workbookXml) : false;
    $styles = llc_sheet2txt_xlsx_parse_styles($filePath, $zip);
    $sheetMap = llc_sheet2txt_xlsx_sheet_map($filePath, $zip);

    // fallback: list worksheets directly (works with ZipArchive only)
    if (!$sheetMap && $zip instanceof ZipArchive) {
      $paths = [];
      for ($i = 0; $i < $zip->numFiles; $i++) {
        $st = $zip->statIndex($i);
        $name = is_array($st) ? (string)($st['name'] ?? '') : '';
        if ($name !== '' && str_starts_with($name, 'xl/worksheets/') && preg_match('~\.xml$~i', $name)) $paths[] = $name;
      }
      natsort($paths);
      foreach ($paths as $p) $sheetMap[] = ['name'=>basename((string)$p), 'path'=>(string)$p];
    }

    $out = [];
    $out[] = "== Spreadsheet: XLSX ==";
    $out[] = "Sheets: " . count($sheetMap) . "; activeTab (0-based): " . $activeTab;
    $out[] = "Encoding notes: output includes (1) a cell-address list like A1=... and (2) a markdown table with explicit row/column headers.";
    $out[] = '';

    $sheetCount = 0;
    $totalChars = 0;
    foreach ($sheetMap as $i => $sh) {
      if ($sheetCount >= LLC_SHEET2TXT_MAX_SHEETS) {
        $out[] = "[truncated: showing first " . LLC_SHEET2TXT_MAX_SHEETS . " sheets]";
        break;
      }

      $name = (string)($sh['name'] ?? '');
      $path = (string)($sh['path'] ?? '');
      if ($path === '') continue;
      $xml = llc_sheet2txt_zip_read($filePath, $zip, $path, false);
      if ($xml === '') continue;

      [$cells, $minRow, $minCol, $maxRow, $maxCol] = llc_sheet2txt_xlsx_parse_sheet_sparse($xml, $shared, $styles, $date1904);
      if (!$cells) continue;

      // Report (but don't expand to) the worksheet dimension, because it often includes huge empty areas.
      [$dMinRow,$dMinCol,$dMaxRow,$dMaxCol] = llc_sheet2txt_xlsx_parse_dimension($xml);
      $dimRange = ($dMaxRow > 0 && $dMaxCol > 0) ? llc_sheet2txt_range_str($dMinRow,$dMinCol,$dMaxRow,$dMaxCol) : '';

      $sheetCount++;
      $isActive = ((int)$i === (int)$activeTab);
      $title = "== Sheet " . ($i + 1) . "/" . count($sheetMap) . ": " . ($name !== '' ? $name : basename($path)) . ($isActive ? " (active)" : "") . " ==";
      $out[] = $title;
      $out[] = "Used range (non-empty cells): " . llc_sheet2txt_range_str($minRow, $minCol, $maxRow, $maxCol);
      if ($dimRange !== '' && $dimRange !== llc_sheet2txt_range_str($minRow, $minCol, $maxRow, $maxCol)) {
        $out[] = "Worksheet dimension: " . $dimRange;
      }
      $mergedText = llc_sheet2txt_render_merged_cells(llc_sheet2txt_xlsx_parse_merged_cells($xml, $cells));
      if ($mergedText !== '') $out[] = $mergedText;

      [$block, $truncGrid] = llc_sheet2txt_render_sparse_block(
        $cells,
        $minRow,
        $minCol,
        $maxRow,
        $maxCol,
        LLC_SHEET2TXT_MAX_ROWS_PER_SHEET,
        LLC_SHEET2TXT_MAX_COLS_PER_SHEET
      );
      $out[] = $block;
      if ($truncGrid) $out[] = "[truncated: showing up to " . LLC_SHEET2TXT_MAX_ROWS_PER_SHEET . " rows and " . LLC_SHEET2TXT_MAX_COLS_PER_SHEET . " columns]";
      $out[] = '';

      $totalChars += strlen($block);
      if ($totalChars > LLC_SHEET2TXT_MAX_TOTAL_CHARS) {
        $out[] = "[truncated: output capped at ~" . LLC_SHEET2TXT_MAX_TOTAL_CHARS . " chars]";
        break;
      }
    }

    return llc_sheet2txt_cleanup(implode("\n", $out));
  } finally {
    if ($zip instanceof ZipArchive) $zip->close();
  }
}

// ---------------- ODS ----------------



function llc_sheet2txt_ods_duration_to_time(string $duration): string {
  $duration = trim($duration);
  if ($duration === '') return '';
  // ODF uses XML Schema durations such as PT13H45M00S.
  if (!preg_match('~^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$~i', $duration, $m)) return $duration;
  $days = isset($m[1]) && $m[1] !== '' ? (int)$m[1] : 0;
  $h = isset($m[2]) && $m[2] !== '' ? (int)$m[2] : 0;
  $min = isset($m[3]) && $m[3] !== '' ? (int)$m[3] : 0;
  $sec = isset($m[4]) && $m[4] !== '' ? (int)round((float)$m[4]) : 0;
  $h += $days * 24;
  return sprintf('%02d:%02d:%02d', $h, $min, $sec);
}

function llc_sheet2txt_ods_typed_display(string $attrs, string $bodyText): string {
  $vt = strtolower(llc_sheet2txt_attr($attrs, 'office:value-type'));
  $bodyText = trim($bodyText);
  if ($vt === '') return $bodyText;

  if ($vt === 'float') {
    $raw = llc_sheet2txt_attr($attrs, 'office:value');
    return $bodyText !== '' ? llc_sheet2txt_append_raw($bodyText, $raw) : llc_sheet2txt_float_str($raw);
  }

  if ($vt === 'percentage') {
    $raw = llc_sheet2txt_attr($attrs, 'office:value');
    $display = $bodyText;
    if ($display === '' && is_numeric($raw)) $display = llc_sheet2txt_float_str((string)((float)$raw * 100.0)) . '%';
    return llc_sheet2txt_append_raw($display, $raw);
  }

  if ($vt === 'currency') {
    $raw = llc_sheet2txt_attr($attrs, 'office:value');
    $currency = llc_sheet2txt_attr($attrs, 'office:currency');
    $display = $bodyText;
    if ($display === '' && $raw !== '') $display = llc_sheet2txt_float_str($raw) . ($currency !== '' ? ' ' . $currency : '');
    return llc_sheet2txt_append_raw($display, $raw);
  }

  if ($vt === 'boolean') {
    $raw = strtolower(llc_sheet2txt_attr($attrs, 'office:boolean-value'));
    $display = $bodyText !== '' ? $bodyText : (($raw === 'true' || $raw === '1') ? 'TRUE' : (($raw === 'false' || $raw === '0') ? 'FALSE' : $raw));
    return $display;
  }

  if ($vt === 'date') {
    $raw = llc_sheet2txt_attr($attrs, 'office:date-value');
    return $bodyText !== '' ? $bodyText : $raw;
  }

  if ($vt === 'time') {
    $raw = llc_sheet2txt_attr($attrs, 'office:time-value');
    $display = $bodyText !== '' ? $bodyText : llc_sheet2txt_ods_duration_to_time($raw);
    return $display;
  }

  if ($vt === 'string') return $bodyText;
  return $bodyText;
}

function llc_sheet2txt_ods_formula_text(string $attrs): string {
  $f = llc_sheet2txt_attr($attrs, 'table:formula');
  if ($f === '') return '';
  $f = html_entity_decode($f, ENT_QUOTES | ENT_HTML5, 'UTF-8');
  $f = trim((string)$f);

  // ODF formulas are commonly prefixed with "of:" and use bracketed refs,
  // e.g. of:=SUM([.A1:.B1]). Keep semantics but make it read like a normal formula.
  if (stripos($f, 'of:') === 0) $f = substr($f, 3);
  if ($f !== '' && $f[0] !== '=') $f = '=' . $f;
  $f = preg_replace('~\[\.([^\]]+)\]~', '$1', $f);
  $f = preg_replace('~\[([^\]]+)\]~', '$1', (string)$f);
  // ODF uses leading dots for relative cell refs, e.g. .A1, and sheet refs
  // like $Sheet.A1 / $'Sheet Name'.A1. Make these readable without damaging
  // decimal numbers or dots inside sheet names.
  $f = preg_replace("~\\$'([^']+)'\.~", "'$1'!", (string)$f);
  $f = preg_replace('~\\$([A-Za-z0-9_ -]+)\.~', '$1!', (string)$f);
  $f = preg_replace('~(?<![A-Za-z0-9_])\.((?:\\$)?[A-Za-z]{1,3}(?:\\$)?\d+)~', '$1', (string)$f);
  return trim((string)$f);
}

function llc_sheet2txt_ods_cell_text(string $cellXml): string {
  // Expand text:s (repeated spaces)
  $cellXml = preg_replace_callback('~<text:s\b([^>]*)/>~i', function($m){
    $attrs = $m[1] ?? '';
    if (preg_match('~text:c\s*=\s*"(\d+)"~i', (string)$attrs, $mm)) {
      $n = llc_sheet2txt_safe_repeat((int)$mm[1], 5000);
      return str_repeat(' ', $n);
    }
    return ' ';
  }, $cellXml);

  $cellXml = preg_replace('~<text:tab\b[^>]*/>~i', "\t", $cellXml);
  $cellXml = preg_replace('~<text:line-break\b[^>]*/>~i', "\n", $cellXml);
  $cellXml = preg_replace('~</text:(p|h)\b[^>]*>~i', "\n", $cellXml);

  $t = trim(strip_tags($cellXml));
  $t = html_entity_decode($t, ENT_QUOTES | ENT_HTML5, 'UTF-8');
  $t = preg_replace('~[ \t]+~', ' ', (string)$t);
  $t = preg_replace('~\n{2,}~', "\n", (string)$t);
  return trim((string)$t);
}

function llc_sheet2txt_ods_parse_table_sparse(string $tableXml): array {
  // Returns [cells,minRow,minCol,maxRow,maxCol,truncated].
  // Important ODS detail: empty rows/cells are often stored as huge repeats
  // (e.g. table:number-rows-repeated="1048569"). Those repeats are real sheet
  // coordinates, but they must not inflate the preview/used range. We therefore
  // advance the logical row counter for address correctness, while bounds are
  // computed only from non-empty cells.
  $cellsMap = [];
  $rowIdx = 0;
  $minRow = PHP_INT_MAX;
  $minCol = PHP_INT_MAX;
  $maxRow = 0;
  $maxCol = 0;
  $nonEmptyRowsSeen = 0;
  $truncated = false;

  if (!preg_match_all('~<table:table-row\b([^>]*)>(.*?)</table:table-row>~is', $tableXml, $rm, PREG_SET_ORDER)) {
    return [[],0,0,0,0,false];
  }

  foreach ($rm as $rowMatch) {
    $rowAttrs = (string)($rowMatch[1] ?? '');
    $rowBody  = (string)($rowMatch[2] ?? '');
    $rowRepeatRaw = (int)llc_sheet2txt_attr($rowAttrs, 'table:number-rows-repeated');
    $rowRepeat = $rowRepeatRaw > 0 ? $rowRepeatRaw : 1;

    // Build one logical row. Empty repeated cells are allowed as positional
    // padding before a later non-empty cell, but trailing empty repeats are
    // trimmed before bounds/output are calculated.
    $rowCells = [];
    if (preg_match_all('~<table:(table-cell|covered-table-cell)\b([^>]*?)/>|<table:(table-cell|covered-table-cell)\b([^>]*)>(.*?)</table:\3>~is', $rowBody, $cm, PREG_SET_ORDER)) {
      foreach ($cm as $c) {
        $kind  = (string)(($c[1] ?? '') !== '' ? $c[1] : ($c[3] ?? ''));
        $attrs = (string)(($c[1] ?? '') !== '' ? ($c[2] ?? '') : ($c[4] ?? ''));
        $body  = (string)(($c[1] ?? '') !== '' ? '' : ($c[5] ?? ''));

        $colRepeatRaw = (int)llc_sheet2txt_attr($attrs, 'table:number-columns-repeated');
        $colRepeat = $colRepeatRaw > 0 ? $colRepeatRaw : 1;

        $val = '';
        if ($kind !== 'covered-table-cell') {
          $val = llc_sheet2txt_ods_typed_display($attrs, llc_sheet2txt_ods_cell_text($body));

          $formula = llc_sheet2txt_ods_formula_text($attrs);
          if ($formula !== '') {
            $val = trim((string)$val);
            if ($val === '') {
              $val = $formula;
            } else if ($val !== $formula) {
              $val .= ' [formula: ' . $formula . ']';
            }
          }
        }

        // Do not let a massive repeated empty-cell run allocate thousands of
        // array entries. If it is empty, it is only positional padding; cap it
        // to the preview column window. Non-empty repeated values are real data
        // and are still bounded by the configured column limit.
        $repeatCap = trim((string)$val) === '' ? (LLC_SHEET2TXT_MAX_COLS_PER_SHEET + 1) : LLC_SHEET2TXT_MAX_COLS_PER_SHEET;
        $colRepeat = llc_sheet2txt_safe_repeat($colRepeat, $repeatCap);

        for ($i = 0; $i < $colRepeat; $i++) {
          $rowCells[] = $val;
          if (count($rowCells) > LLC_SHEET2TXT_MAX_COLS_PER_SHEET + 1) {
            $truncated = true;
            break 2;
          }
        }
      }
    }

    $rowCells = llc_sheet2txt_trim_trailing_empties($rowCells);
    $logicalMaxCol = count($rowCells);
    $rowHasData = false;
    for ($c = 1; $c <= $logicalMaxCol; $c++) {
      if (trim((string)($rowCells[$c-1] ?? '')) !== '') { $rowHasData = true; break; }
    }

    if (!$rowHasData) {
      // Preserve coordinates for any later non-empty rows, but never expand or
      // render empty repeated rows.
      $rowIdx += $rowRepeat;
      continue;
    }

    $repeatToMaterialize = min($rowRepeat, max(1, LLC_SHEET2TXT_MAX_ROWS_PER_SHEET - $nonEmptyRowsSeen));
    for ($rr = 0; $rr < $repeatToMaterialize; $rr++) {
      $actualRow = $rowIdx + 1 + $rr;
      $wrote = false;
      for ($c = 1; $c <= $logicalMaxCol; $c++) {
        $v = trim((string)($rowCells[$c-1] ?? ''));
        if ($v === '') continue;
        $cellsMap[$actualRow][$c] = $v;
        if ($actualRow < $minRow) $minRow = $actualRow;
        if ($c < $minCol) $minCol = $c;
        if ($actualRow > $maxRow) $maxRow = $actualRow;
        if ($c > $maxCol) $maxCol = $c;
        $wrote = true;
      }
      if ($wrote) $nonEmptyRowsSeen++;
    }
    if ($rowRepeat > $repeatToMaterialize) $truncated = true;
    $rowIdx += $rowRepeat;
  }

  if (!$cellsMap) return [[],0,0,0,0,$truncated];
  return [$cellsMap, $minRow, $minCol, $maxRow, $maxCol, $truncated];
}

function llc_sheet2txt_ods(string $filePath): string {
  $zip = class_exists('ZipArchive') ? new ZipArchive() : null;
  if ($zip instanceof ZipArchive) {
    $ok = $zip->open($filePath);
    if ($ok !== true) throw new RuntimeException('sheet2txt: invalid zip container');
  } else {
    if (llc_sheet2txt_unzip_path() === '') throw new RuntimeException('sheet2txt: ZipArchive missing and unzip not available');
  }

  try {
    $xml = llc_sheet2txt_zip_read($filePath, $zip, 'content.xml', true);
    $out = [];

    $tables = [];
    if (preg_match_all('~<table:table\b([^>]*)>(.*?)</table:table>~is', $xml, $tm, PREG_SET_ORDER)) {
      foreach ($tm as $t) {
        $attrs = (string)($t[1] ?? '');
        $body  = (string)($t[2] ?? '');
        $name  = llc_sheet2txt_attr($attrs, 'table:name');
        $tables[] = ['name'=>$name, 'body'=>$body];
      }
    }

    $out[] = "== Spreadsheet: ODS ==";
    $out[] = "Sheets: " . count($tables);
    $out[] = "Encoding notes: output includes (1) a cell-address list like A1=... and (2) a markdown table with explicit row/column headers.";
    $out[] = '';

    $sheetCount = 0;
    $totalChars = 0;
    foreach ($tables as $i => $tbl) {
      if ($sheetCount >= LLC_SHEET2TXT_MAX_SHEETS) {
        $out[] = "[truncated: showing first " . LLC_SHEET2TXT_MAX_SHEETS . " sheets]";
        break;
      }
      $sheetCount++;

      $name = (string)($tbl['name'] ?? '');
      $body = (string)($tbl['body'] ?? '');
      [$cells, $minRow, $minCol, $maxRow, $maxCol, $truncParse] = llc_sheet2txt_ods_parse_table_sparse($body);
      if (!$cells && !$truncParse) continue;

      $title = "== Sheet " . ($i + 1) . "/" . count($tables) . ": " . ($name !== '' ? $name : ('Table ' . ($i + 1))) . " ==";
      $out[] = $title;
      $out[] = "Used range (non-empty cells): " . llc_sheet2txt_range_str($minRow, $minCol, $maxRow, $maxCol);

      [$block, $truncGrid] = llc_sheet2txt_render_sparse_block(
        $cells,
        $minRow > 0 ? $minRow : 1,
        $minCol > 0 ? $minCol : 1,
        $maxRow > 0 ? $maxRow : 1,
        $maxCol > 0 ? $maxCol : 1,
        LLC_SHEET2TXT_MAX_ROWS_PER_SHEET,
        LLC_SHEET2TXT_MAX_COLS_PER_SHEET
      );
      $out[] = $block;
      if ($truncGrid || $truncParse) $out[] = "[truncated: showing up to " . LLC_SHEET2TXT_MAX_ROWS_PER_SHEET . " rows and " . LLC_SHEET2TXT_MAX_COLS_PER_SHEET . " columns]";
      $out[] = '';

      $totalChars += strlen($block);
      if ($totalChars > LLC_SHEET2TXT_MAX_TOTAL_CHARS) {
        $out[] = "[truncated: output capped at ~" . LLC_SHEET2TXT_MAX_TOTAL_CHARS . " chars]";
        break;
      }
    }

    // ultra-rough fallback if no tables found or completely empty
    if (count($tables) === 0) {
      $fallback = $xml;
      $fallback = preg_replace('~</table:table-cell\b[^>]*>~i', "\t", $fallback);
      $fallback = preg_replace('~</table:table-row\b[^>]*>~i', "\n", $fallback);
      $fallback = preg_replace('~</table:table\b[^>]*>~i', "\n\n", $fallback);
      $fallback = strip_tags($fallback);
      $out[] = $fallback;
    }

    return llc_sheet2txt_cleanup(implode("\n", $out));
  } finally {
    if ($zip instanceof ZipArchive) $zip->close();
  }
}
