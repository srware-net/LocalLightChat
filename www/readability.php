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

function fetchHtml(string $url): string {
    if (!function_exists('curl_init')) {
        $html = @file_get_contents($url);
        if ($html === false) {
            throw new RuntimeException("Konnte URL nicht laden (file_get_contents): $url");
        }
        return $html;
    }

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS      => 8,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT        => 25,
        CURLOPT_ENCODING       => '',
        CURLOPT_USERAGENT      => 'Mozilla/5.0 (LocalLightChat; Readability)',
        CURLOPT_HTTPHEADER     => [
            'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language: de-DE,de;q=0.9,en;q=0.7',
        ],
    ]);

    $html = curl_exec($ch);
    if ($html === false) {
        $err = curl_error($ch);
        curl_close($ch);
        throw new RuntimeException("cURL Fehler: $err");
    }

    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($code >= 400) {
        throw new RuntimeException("HTTP Fehler $code bei $url");
    }

    return $html;
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
    $html = fetchHtml($url);

    $config = new Configuration();
    $config->setOriginalURL($url);
    $config->setFixRelativeURLs(false);
    $config->setArticleByline(true);

    $readability = new Readability($config);
    $readability->parse($html);

    $title  = $readability->getTitle() ?? '';
    $author = $readability->getAuthor() ?? '';
    $text   = htmlToText($readability->getContent() ?? '');

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
