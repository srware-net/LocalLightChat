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

const LLC_SHEET2TXT_MAX_SHEETS = 20;
const LLC_SHEET2TXT_MAX_ROWS_PER_SHEET = 200;
const LLC_SHEET2TXT_MAX_COLS_PER_SHEET = 50;
const LLC_SHEET2TXT_MAX_CHARS_PER_CELL = 500;
const LLC_SHEET2TXT_MAX_TOTAL_CHARS = 220000;

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
  $pairCap = 4000; // safety cap to avoid absurdly long single sections
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
  if (str_starts_with($raw, "\xEF\xBB\xBF")) $raw = substr($raw, 3); // UTF-8 BOM

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

function llc_sheet2txt_xlsx_parse_sheet_sparse(string $xml, array $sharedStrings): array {
  // Returns [cells,minRow,minCol,maxRow,maxCol]
  $cells = [];
  $minRow = PHP_INT_MAX;
  $minCol = PHP_INT_MAX;
  $maxRow = 0;
  $maxCol = 0;

  // Parse all cells (sparse); ignore empty self-closing cells.
  if (preg_match_all('~<c\b([^>]*)>(.*?)</c>~is', $xml, $cm, PREG_SET_ORDER)) {
    foreach ($cm as $c) {
      $attrs = (string)($c[1] ?? '');
      $body  = (string)($c[2] ?? '');

      $ref = llc_sheet2txt_attr($attrs, 'r');
      if (!preg_match('~^([A-Z]+)(\d+)$~i', (string)$ref, $rm)) continue;
      $col = llc_sheet2txt_col_to_index((string)$rm[1]);
      $row = (int)$rm[2];
      if ($row <= 0 || $col <= 0) continue;

      $t = strtolower(llc_sheet2txt_attr($attrs, 't'));
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
        } else {
          // n (default), str, e, d -> keep raw
          $v = $vv;
          if ($v === '' && preg_match('~<f\b[^>]*>(.*?)</f>~is', $body, $fm)) {
            $f = html_entity_decode(strip_tags((string)$fm[1]), ENT_QUOTES | ENT_HTML5, 'UTF-8');
            if (trim($f) !== '') $v = '=' . trim($f);
          }
        }
      }

      $v = trim((string)$v);
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

      [$cells, $minRow, $minCol, $maxRow, $maxCol] = llc_sheet2txt_xlsx_parse_sheet_sparse($xml, $shared);
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
  // Returns [cells,minRow,minCol,maxRow,maxCol,truncated]
  $cellsMap = [];
  $rowIdx = 0;
  $maxCol = 0;
  $truncated = false;

  if (!preg_match_all('~<table:table-row\b([^>]*)>(.*?)</table:table-row>~is', $tableXml, $rm, PREG_SET_ORDER)) {
    return [[],0,0,0,0,false];
  }

  foreach ($rm as $rowMatch) {
    $rowAttrs = (string)($rowMatch[1] ?? '');
    $rowBody  = (string)($rowMatch[2] ?? '');
    $rowRepeat = (int)llc_sheet2txt_attr($rowAttrs, 'table:number-rows-repeated');
    $rowRepeat = llc_sheet2txt_safe_repeat($rowRepeat, 2000);

    // Build one logical row, then repeat.
    $rowCells = [];
    if (preg_match_all('~<table:(table-cell|covered-table-cell)\b([^>]*)>(.*?)</table:\1>|<table:(table-cell|covered-table-cell)\b([^>]*)/>~is', $rowBody, $cm, PREG_SET_ORDER)) {
      foreach ($cm as $c) {
        $kind  = (string)($c[1] !== '' ? $c[1] : ($c[4] ?? ''));
        $attrs = (string)($c[2] !== '' ? $c[2] : ($c[5] ?? ''));
        $body  = (string)($c[3] ?? '');

        $colRepeat = (int)llc_sheet2txt_attr($attrs, 'table:number-columns-repeated');
        $colRepeat = llc_sheet2txt_safe_repeat($colRepeat, 2000);

        $val = '';
        if ($kind !== 'covered-table-cell') {
          $val = llc_sheet2txt_ods_cell_text($body);
          if ($val === '') {
            $vt = llc_sheet2txt_attr($attrs, 'office:value-type');
            if ($vt === 'float' || $vt === 'currency' || $vt === 'percentage') {
              $val = llc_sheet2txt_attr($attrs, 'office:value');
            } else if ($vt === 'date') {
              $val = llc_sheet2txt_attr($attrs, 'office:date-value');
            } else if ($vt === 'boolean') {
              $val = llc_sheet2txt_attr($attrs, 'office:boolean-value');
            }
          }
        }

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
    if ($logicalMaxCol > $maxCol) $maxCol = $logicalMaxCol;

    for ($rr = 0; $rr < $rowRepeat; $rr++) {
      $rowIdx++;
      if ($rowIdx > LLC_SHEET2TXT_MAX_ROWS_PER_SHEET + 1) { $truncated = true; break 2; }
      for ($c = 1; $c <= $logicalMaxCol; $c++) {
        $v = trim((string)($rowCells[$c-1] ?? ''));
        if ($v !== '') $cellsMap[$rowIdx][$c] = $v;
      }
    }
  }

  if ($rowIdx <= 0) return [[],0,0,0,0,$truncated];
  return [$cellsMap, 1, 1, max(1,$rowIdx), max(1,$maxCol), $truncated];
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
      $out[] = "Used range (best-effort): " . llc_sheet2txt_range_str(1, 1, $maxRow > 0 ? $maxRow : 1, $maxCol > 0 ? $maxCol : 1);

      [$block, $truncGrid] = llc_sheet2txt_render_sparse_block(
        $cells,
        1,
        1,
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
