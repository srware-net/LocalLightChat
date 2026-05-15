<?php
declare(strict_types=1);

/**
 * Autoloader nur für:
 * - fivefilters/readability.php
 * - masterminds/html5-php
 * - psr/log
 *
 * Erwartete Struktur:
 * /projektroot/plugins/
 *   readability.php/
 *   html5-php/
 *   log/
 *   readability_autoload.php
 */
spl_autoload_register(function (string $class): void {
    $base = __DIR__;

    // only these namespaces
    if (str_starts_with($class, 'fivefilters\\Readability\\')) {
        $rel = substr($class, strlen('fivefilters\\Readability\\'));
        $file = $base . '/readability.php/src/' . str_replace('\\', '/', $rel) . '.php';
        if (is_file($file)) require $file;
        return;
    }

    if (str_starts_with($class, 'Masterminds\\')) {
        $rel = substr($class, strlen('Masterminds\\'));
        $file = $base . '/html5-php/src/' . str_replace('\\', '/', $rel) . '.php';
        if (is_file($file)) require $file;
        return;
    }

    if (str_starts_with($class, 'Psr\\Log\\')) {
        $rel = substr($class, strlen('Psr\\Log\\'));
        $file = $base . '/log/src/' . str_replace('\\', '/', $rel) . '.php';
        if (is_file($file)) require $file;
        return;
    }

    // Optional: league/uri nur wenn du FixRelativeURLs=true willst
    /*
    if (str_starts_with($class, 'League\\Uri\\')) {
        $rel = substr($class, strlen('League\\Uri\\'));
        $file = $base . '/league-uri/src/' . str_replace('\\', '/', $rel) . '.php';
        if (is_file($file)) require $file;
        return;
    }
    */
});
