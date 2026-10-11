<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI;

final class Client
{
    public static function base(string $url): string
    {
        $url = trim($url);
        if ($url === '') throw new \RuntimeException('ComfyUI URL missing (Settings → Image).');
        return rtrim($url, '/');
    }

    public static function json(string $method, string $url, ?array $payload = null, int $timeout = 120): array
    {
        $ch = curl_init($url);
        $headers = ['Accept: application/json'];
        $opts = [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $timeout,
            CURLOPT_CONNECTTIMEOUT => 10,
        ];
        if (strtoupper($method) === 'POST') {
            $headers[] = 'Content-Type: application/json';
            $opts[CURLOPT_POST] = true;
            if ($payload !== null) $opts[CURLOPT_POSTFIELDS] = json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
        }
        $opts[CURLOPT_HTTPHEADER] = $headers;
        curl_setopt_array($ch, $opts);
        $raw = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $err = curl_error($ch);
        curl_close($ch);

        if ($raw === false || $raw === null) {
            throw new \RuntimeException('ComfyUI request failed: ' . ($err ?: 'unknown error') . ($code ? ' (HTTP ' . $code . ')' : ''));
        }
        $decoded = json_decode((string)$raw, true);
        if (!is_array($decoded)) {
            $snippet = trim(substr((string)$raw, 0, 800));
            throw new \RuntimeException('ComfyUI returned invalid JSON (HTTP ' . $code . '): ' . $snippet);
        }
        if ($code !== 0 && ($code < 200 || $code >= 300)) {
            throw new \RuntimeException('ComfyUI HTTP ' . $code . ': ' . json_encode($decoded, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
        }
        return $decoded;
    }


    /**
     * Best-effort cancellation for one ComfyUI prompt/job.
     * Uses the modern atomic job endpoint first, then falls back to the legacy
     * queue/interrupt API after verifying the specific prompt id.
     *
     * @return array{ok:bool,cancelled:bool,mode:string}
     */
    public static function cancelJob(string $base, string $promptId, int $timeout = 15): array
    {
        $base = rtrim($base, '/');
        $promptId = trim($promptId);
        if ($promptId === '') throw new \RuntimeException('ComfyUI cancel: missing prompt_id');

        try {
            $modern = self::json('POST', $base . '/api/jobs/' . rawurlencode($promptId) . '/cancel', [], $timeout);
            return [
                'ok' => true,
                'cancelled' => !empty($modern['cancelled']),
                'mode' => 'jobs',
            ];
        } catch (\Throwable $modernError) {
            // Older ComfyUI versions do not expose /api/jobs/{id}/cancel.
        }

        $queue = self::json('GET', $base . '/queue', null, $timeout);
        $pending = self::queueContainsPrompt($queue['queue_pending'] ?? null, $promptId);
        if ($pending) {
            self::requestAllowEmpty('POST', $base . '/queue', ['delete'=>[$promptId]], $timeout);
            return ['ok'=>true, 'cancelled'=>true, 'mode'=>'queue'];
        }

        $running = self::queueContainsPrompt($queue['queue_running'] ?? null, $promptId);
        if ($running) {
            // Newer legacy servers accept prompt_id; older ones ignore the body and
            // interrupt the current job. We only call this after confirming that the
            // requested prompt is the current running prompt.
            self::requestAllowEmpty('POST', $base . '/interrupt', ['prompt_id'=>$promptId], $timeout);
            return ['ok'=>true, 'cancelled'=>true, 'mode'=>'interrupt'];
        }

        return ['ok'=>true, 'cancelled'=>false, 'mode'=>'not_running'];
    }

    private static function queueContainsPrompt($items, string $promptId): bool
    {
        if (!is_array($items)) return false;
        foreach ($items as $item) {
            if (!is_array($item) || count($item) < 2) continue;
            if ((string)($item[1] ?? '') === $promptId) return true;
        }
        return false;
    }

    /** @return array<string,mixed> */
    private static function requestAllowEmpty(string $method, string $url, ?array $payload, int $timeout): array
    {
        $ch = curl_init($url);
        $headers = ['Accept: application/json'];
        $opts = [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $timeout,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_CUSTOMREQUEST => strtoupper($method),
        ];
        if ($payload !== null) {
            $headers[] = 'Content-Type: application/json';
            $opts[CURLOPT_POSTFIELDS] = json_encode($payload, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
        }
        $opts[CURLOPT_HTTPHEADER] = $headers;
        curl_setopt_array($ch, $opts);
        $raw = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $err = curl_error($ch);
        curl_close($ch);
        if ($raw === false || $raw === null) {
            throw new \RuntimeException('ComfyUI request failed: ' . ($err ?: 'unknown error') . ($code ? ' (HTTP ' . $code . ')' : ''));
        }
        if ($code !== 0 && ($code < 200 || $code >= 300)) {
            throw new \RuntimeException('ComfyUI HTTP ' . $code . ': ' . trim(substr((string)$raw, 0, 800)));
        }
        if (trim((string)$raw) === '') return [];
        $decoded = json_decode((string)$raw, true);
        return is_array($decoded) ? $decoded : [];
    }

    public static function uploadImageFile(string $base, string $path, string $mime, string $name, int $timeout = 120): string
    {
        $ch = curl_init(rtrim($base, '/') . '/upload/image');
        $file = curl_file_create($path, $mime, $name);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $timeout,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => [
                'image' => $file,
                'overwrite' => 'false',
                'type' => 'input',
            ],
        ]);
        $raw = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $err = curl_error($ch);
        curl_close($ch);
        if ($raw === false || $raw === null) throw new \RuntimeException('ComfyUI upload failed: ' . ($err ?: 'unknown error') . ($code ? ' (HTTP ' . $code . ')' : ''));
        $decoded = json_decode((string)$raw, true);
        if (!is_array($decoded)) {
            $snippet = trim(substr((string)$raw, 0, 500));
            throw new \RuntimeException('ComfyUI upload returned invalid JSON (HTTP ' . $code . '): ' . $snippet);
        }
        if ($code !== 0 && ($code < 200 || $code >= 300)) {
            throw new \RuntimeException('ComfyUI upload HTTP ' . $code . ': ' . json_encode($decoded, JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES));
        }
        $uploaded = trim((string)($decoded['name'] ?? ''));
        if ($uploaded === '') throw new \RuntimeException('ComfyUI upload returned no image name');
        $subfolder = trim((string)($decoded['subfolder'] ?? ''));
        return $subfolder !== '' ? trim($subfolder, '/\\') . '/' . $uploaded : $uploaded;
    }

    /** @return array{0:string,1:string} */
    public static function bytes(string $url, int $timeout = 120): array
    {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $timeout,
            CURLOPT_CONNECTTIMEOUT => 10,
        ]);
        $bytes = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        $contentType = (string)curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
        $err = curl_error($ch);
        curl_close($ch);
        if ($bytes === false || $bytes === null) {
            throw new \RuntimeException('ComfyUI download failed: ' . ($err ?: 'unknown error') . ($code ? ' (HTTP ' . $code . ')' : ''));
        }
        if ($code !== 0 && ($code < 200 || $code >= 300)) throw new \RuntimeException('ComfyUI download HTTP ' . $code);
        return [(string)$bytes, $contentType];
    }
}
