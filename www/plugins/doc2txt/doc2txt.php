<?php
declare(strict_types=1);

// DOCX/ODT -> plaintext (zip/xml).
// - DOCX: w:p = paragraph (\n\n), w:br = \n, w:tab = \t
// - ODT:  text:p,text:h = paragraph (\n\n), text:line-break = \n, text:tab = \t, text:s = spaces

function llc_doc2txt_extract(string $filePath, string $ext): string {
  $ext = strtolower(trim($ext));
  if (!is_file($filePath)) throw new RuntimeException('doc2txt: file not found');
  if (!class_exists('ZipArchive')) throw new RuntimeException('doc2txt: ZipArchive missing');

  if ($ext === 'docx') return llc_doc2txt_docx($filePath);
  if ($ext === 'odt') return llc_doc2txt_odt($filePath);
  throw new RuntimeException('doc2txt: unsupported extension');
}

function llc_doc2txt_zip_read(string $filePath, string $entryName): string {
  $zip = new ZipArchive();
  $ok = $zip->open($filePath);
  if ($ok !== true) throw new RuntimeException('doc2txt: invalid zip container');
  $xml = $zip->getFromName($entryName);
  $zip->close();
  if (!is_string($xml) || $xml === '') throw new RuntimeException('doc2txt: missing ' . $entryName);
  return $xml;
}

function llc_doc2txt_cleanup(string $text): string {
  $text = html_entity_decode($text, ENT_QUOTES | ENT_HTML5, 'UTF-8');
  $text = str_replace("\r\n", "\n", $text);
  $text = str_replace("\r", "\n", $text);
  $text = preg_replace("~[ \t]+\n~", "\n", $text);
  $text = preg_replace("~\n{3,}~", "\n\n", $text);
  return trim((string)$text);
}

function llc_doc2txt_docx(string $filePath): string {
  $xml = llc_doc2txt_zip_read($filePath, 'word/document.xml');

  // Normalize important structure to plain tokens before stripping tags.
  $xml = preg_replace('~<w:tab\b[^>]*/>~i', "\t", $xml);
  $xml = preg_replace('~<w:br\b[^>]*/>~i', "\n", $xml);
  $xml = preg_replace('~</w:p\b[^>]*>~i', "\n\n", $xml);

  // Tables (best-effort)
  $xml = preg_replace('~</w:tc\b[^>]*>~i', "\t", $xml);
  $xml = preg_replace('~</w:tr\b[^>]*>~i', "\n", $xml);

  $text = strip_tags($xml);
  return llc_doc2txt_cleanup($text);
}

function llc_doc2txt_odt(string $filePath): string {
  $xml = llc_doc2txt_zip_read($filePath, 'content.xml');

  // text:s may have text:c="N" for repeated spaces.
  $xml = preg_replace_callback('~<text:s\b([^>]*)/>~i', function($m){
    $attrs = $m[1] ?? '';
    if (preg_match('~text:c\s*=\s*"(\d+)"~i', (string)$attrs, $mm)) {
      $n = (int)$mm[1];
      if ($n < 1) $n = 1;
      if ($n > 5000) $n = 5000; // sanity
      return str_repeat(' ', $n);
    }
    return ' ';
  }, $xml);

  $xml = preg_replace('~<text:tab\b[^>]*/>~i', "\t", $xml);
  $xml = preg_replace('~<text:line-break\b[^>]*/>~i', "\n", $xml);
  $xml = preg_replace('~</text:(p|h)\b[^>]*>~i', "\n\n", $xml);

  // Tables (best-effort)
  $xml = preg_replace('~</table:table-cell\b[^>]*>~i', "\t", $xml);
  $xml = preg_replace('~</table:table-row\b[^>]*>~i', "\n", $xml);

  $text = strip_tags($xml);
  return llc_doc2txt_cleanup($text);
}
