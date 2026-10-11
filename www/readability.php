<?php
declare(strict_types=1);

// Simple Readability endpoint
// GET /readability.php?url=... [&format=json|txt] [&max_chars=20000]

require __DIR__ . '/plugins/readability_autoload.php';

use fivefilters\Readability\Configuration;
use fivefilters\Readability\ParseException;
use fivefilters\Readability\Readability;

function llc_fail(string $msg, int $code=400): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok'=>false,'error'=>$msg], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
    exit;
}

function llc_param(string $k): string {
    return isset($_GET[$k]) ? trim((string)$_GET[$k]) : '';
}

function llc_validate_url(string $url): string {
    $url = trim($url);
    if ($url === '') llc_fail('Missing url');
    if (strlen($url) > 2048) llc_fail('URL too long');
    $p = parse_url($url);
    if (!is_array($p) || empty($p['scheme']) || empty($p['host'])) llc_fail('Invalid URL');
    $scheme = strtolower((string)$p['scheme']);
    if (!in_array($scheme, ['http','https'], true)) llc_fail('Only http/https allowed');
    return $url;
}

function fetchResource(string $url): array {
    if (!function_exists('curl_init')) {
        $body = @file_get_contents($url);
        if ($body === false) {
            throw new RuntimeException("Konnte URL nicht laden (file_get_contents): $url");
        }
        $contentType = '';
        foreach (($http_response_header ?? []) as $headerLine) {
            if (stripos((string)$headerLine, 'Content-Type:') === 0) {
                $contentType = trim(substr((string)$headerLine, strlen('Content-Type:')));
            }
        }
        return ['body'=>(string)$body, 'content_type'=>$contentType, 'effective_url'=>$url];
    }

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS      => 8,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT        => 25,
        CURLOPT_ENCODING       => '',
        CURLOPT_USERAGENT      => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36',
        CURLOPT_HTTPHEADER     => [
            'Accept: text/html,application/xhtml+xml,application/json,text/plain,application/xml;q=0.9,text/*;q=0.8,*/*;q=0.7',
            'Accept-Language: de-DE,de;q=0.9,en;q=0.7',
        ],
    ]);

    $body = curl_exec($ch);
    if ($body === false) {
        $err = curl_error($ch);
        curl_close($ch);
        throw new RuntimeException("cURL Fehler: $err");
    }

    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $contentType = (string)(curl_getinfo($ch, CURLINFO_CONTENT_TYPE) ?: '');
    $effectiveUrl = (string)(curl_getinfo($ch, CURLINFO_EFFECTIVE_URL) ?: $url);
    curl_close($ch);

    if ($code >= 400) {
        throw new RuntimeException("HTTP Fehler $code bei $url");
    }

    return ['body'=>(string)$body, 'content_type'=>$contentType, 'effective_url'=>$effectiveUrl];
}

function httpMime(string $contentType): string {
    return strtolower(trim(explode(';', $contentType, 2)[0] ?? ''));
}

function httpCharset(string $contentType): string {
    if (preg_match('~(?:^|;)\s*charset\s*=\s*["\']?([^;"\'\s]+)~i', $contentType, $m)) {
        return trim((string)$m[1]);
    }
    return '';
}

function isHtmlMime(string $mime): bool {
    return $mime === 'text/html' || $mime === 'application/xhtml+xml';
}

function isTextMime(string $mime): bool {
    if ($mime === '') return false;
    if (str_starts_with($mime, 'text/')) return true;
    if ($mime === 'application/json' || str_ends_with($mime, '+json')) return true;
    if ($mime === 'application/xml' || str_ends_with($mime, '+xml')) return true;
    return in_array($mime, [
        'application/javascript',
        'application/x-javascript',
        'application/yaml',
        'application/x-yaml',
        'application/toml',
        'application/sql',
        'application/graphql',
    ], true);
}

function bodyLooksHtml(string $body): bool {
    $sample = ltrim(substr($body, 0, 8192), "\xEF\xBB\xBF\x00..\x20");
    return (bool)preg_match('~^(?:<!doctype\s+html\b|<html\b|<head\b|<body\b)~i', $sample);
}

function bodyLooksText(string $body): bool {
    if ($body === '') return true;
    if (str_starts_with($body, "\xFF\xFE") || str_starts_with($body, "\xFE\xFF") || str_starts_with($body, "\xEF\xBB\xBF")) return true;
    $sample = substr($body, 0, 8192);
    if (strpos($sample, "\0") !== false) return false;
    $len = strlen($sample);
    if ($len === 0) return true;
    $controls = 0;
    for ($i = 0; $i < $len; $i++) {
        $o = ord($sample[$i]);
        if ($o < 32 && $o !== 9 && $o !== 10 && $o !== 13) $controls++;
    }
    return ($controls / $len) < 0.02;
}

function decodeHttpText(string $body, string $contentType): string {
    if ($body === '') return '';

    $sourceEncoding = httpCharset($contentType);
    if (str_starts_with($body, "\xEF\xBB\xBF")) {
        $body = substr($body, 3);
        $sourceEncoding = 'UTF-8';
    } elseif (str_starts_with($body, "\xFF\xFE")) {
        $body = substr($body, 2);
        $sourceEncoding = 'UTF-16LE';
    } elseif (str_starts_with($body, "\xFE\xFF")) {
        $body = substr($body, 2);
        $sourceEncoding = 'UTF-16BE';
    }

    $isUtf8 = static function(string $s): bool {
        if (function_exists('mb_check_encoding')) return mb_check_encoding($s, 'UTF-8');
        return preg_match('//u', $s) === 1;
    };
    $convert = static function(string $s, string $from): ?string {
        $from = trim($from);
        if ($from === '') return null;
        if (function_exists('mb_convert_encoding')) {
            try { return mb_convert_encoding($s, 'UTF-8', $from); } catch (Throwable $e) { /* try iconv */ }
        }
        if (function_exists('iconv')) {
            $v = @iconv($from, 'UTF-8//IGNORE', $s);
            if ($v !== false) return $v;
        }
        return null;
    };

    if ($sourceEncoding !== '') {
        $norm = strtolower(str_replace(['_', ' '], '-', $sourceEncoding));
        if (!in_array($norm, ['utf-8', 'utf8'], true)) {
            $converted = $convert($body, $sourceEncoding);
            if ($converted !== null) return $converted;
        }
    }
    if ($isUtf8($body)) return $body;

    $converted = $convert($body, 'Windows-1252');
    if ($converted !== null) return $converted;
    $converted = $convert($body, 'ISO-8859-1');
    if ($converted !== null) return $converted;
    return preg_replace('/[\x80-\xFF]+/', '', $body) ?? $body;
}

/**
 * Convert HTML to readable plaintext.
 */
function htmlToText(string $html): string {
    $html = preg_replace('~<\s*br\s*/?\s*>~i', "\n", $html);
    $html = preg_replace('~</\s*p\s*>~i', "\n\n", $html);
    $html = preg_replace('~</\s*div\s*>~i', "\n\n", $html);
    $html = preg_replace('~</\s*h[1-6]\s*>~i', "\n\n", $html);
    $html = preg_replace('~</\s*li\s*>~i', "\n", $html);

    $text = strip_tags((string)$html);
    $text = html_entity_decode($text, ENT_QUOTES | ENT_HTML5, 'UTF-8');

    $text = str_replace("\r\n", "\n", $text);
    $text = str_replace("\r", "\n", $text);

    $text = preg_replace("~[ \t]+\n~", "\n", $text);
    $text = preg_replace("~\n{3,}~", "\n\n", $text);
    $text = preg_replace("~[ \t]{2,}~", " ", $text);

    return trim((string)$text);
}

$url = llc_validate_url(llc_param('url'));
$format = strtolower(llc_param('format'));
$rawMax = llc_param('max_chars');
// 0 = unlimited
$maxChars = (int)($rawMax !== '' ? $rawMax : '20000');
if ($maxChars < 0) $maxChars = 0;

try {
    $response = fetchResource($url);
    $body = (string)($response['body'] ?? '');
    $contentType = (string)($response['content_type'] ?? '');
    $effectiveUrl = (string)($response['effective_url'] ?? $url);
    $mime = httpMime($contentType);

    $title = '';
    $author = '';
    if (isHtmlMime($mime) || ($mime === '' && bodyLooksHtml($body)) || ($mime === 'application/octet-stream' && bodyLooksHtml($body))) {
        $config = new Configuration();
        $config->setOriginalURL($effectiveUrl);
        $config->setFixRelativeURLs(false);
        $config->setArticleByline(true);

        $readability = new Readability($config);
        $readability->parse($body);

        $title  = $readability->getTitle() ?? '';
        $author = $readability->getAuthor() ?? '';
        $text   = htmlToText($readability->getContent() ?? '');
    } elseif (isTextMime($mime) || (($mime === '' || $mime === 'application/octet-stream') && bodyLooksText($body))) {
        $text = decodeHttpText($body, $contentType);
        $text = str_replace("\r\n", "\n", $text);
        $text = str_replace("\r", "\n", $text);
        $text = trim($text);
    } else {
        $shownMime = $mime !== '' ? $mime : 'unknown content type';
        throw new RuntimeException('Unsupported binary content (' . $shownMime . ')');
    }

    $truncated = false;
    if ($maxChars > 0 && mb_strlen($text, 'UTF-8') > $maxChars) {
        $text = mb_substr($text, 0, $maxChars, 'UTF-8');
        $truncated = true;
    }

    $wantTxt = ($format === 'txt');
    $accept = $_SERVER['HTTP_ACCEPT'] ?? '';
    if (!$wantTxt && is_string($accept) && str_contains($accept, 'text/plain')) $wantTxt = true;

    if ($wantTxt) {
        header('Content-Type: text/plain; charset=utf-8');
        if ($title !== '') {
            echo $title . "\n";
            echo str_repeat('=', (int)mb_strlen($title, 'UTF-8')) . "\n\n";
        }
        if ($author !== '') {
            echo "By: " . $author . "\n\n";
        }
        echo "URL: " . $url . "\n\n";
        echo $text . "\n";
        exit;
    }

    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'ok' => true,
        'url' => $url,
        'title' => $title,
        'author' => $author,
        'content_text' => $text,
        'truncated' => $truncated,
        'max_chars' => $maxChars,
    ], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_INVALID_UTF8_SUBSTITUTE);
    exit;

} catch (ParseException $e) {
    llc_fail('ParseException: ' . $e->getMessage(), 422);
} catch (Throwable $e) {
    llc_fail('Fehler: ' . $e->getMessage(), 500);
}
