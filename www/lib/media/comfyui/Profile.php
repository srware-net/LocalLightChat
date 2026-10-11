<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI;

final class Profile
{
    public static function normalizeGeneration(array $profile, int $index = 0): array
    {
        return self::normalize($profile, $index, false);
    }

    public static function normalizeEdit(array $profile, int $index = 0): array
    {
        return self::normalize($profile, $index, true);
    }

    public static function decodeGeneration(string $raw): array
    {
        return self::decode($raw, false);
    }

    public static function decodeEdit(string $raw): array
    {
        return self::decode($raw, true);
    }

    private static function normalize(array $p, int $index, bool $edit): array
    {
        $id = trim((string)($p['id'] ?? ''));
        $id = preg_replace('/[^A-Za-z0-9_.:-]+/', '_', $id) ?? '';
        $id = trim($id, '_');
        if ($id === '') $id = ($edit ? 'comfy_edit_' : 'comfy_') . ($index + 1);
        if (strlen($id) > 100) $id = substr($id, 0, 100);

        $name = trim((string)($p['name'] ?? ''));
        if ($name === '') $name = ($edit ? 'ComfyUI Edit ' : 'ComfyUI ') . ($index + 1);
        if (strlen($name) > 240) $name = substr($name, 0, 240);

        $url = trim((string)($p['url'] ?? ''));
        if (strlen($url) > 2048) $url = substr($url, 0, 2048);

        $seed = (int)($p['seed'] ?? -1);
        $steps = max(1, min(250, (int)($p['steps'] ?? 20)));
        $guidance = (float)($p['guidance'] ?? 3.5);
        if (!is_finite($guidance)) $guidance = 3.5;
        $width = max(64, min(4096, (int)($p['width'] ?? ($edit ? 1024 : 512))));
        $height = max(64, min(4096, (int)($p['height'] ?? ($edit ? 1024 : 512))));
        $batch = max(1, min(16, (int)($p['batch'] ?? 1)));
        $timeout = max(30, min(3600, (int)($p['timeout_sec'] ?? 900)));
        $applyRaw = $p['apply_defaults'] ?? 0;
        $applyDefaults = ($applyRaw === true || $applyRaw === 1 || $applyRaw === '1');

        $out = [
            'id' => $id,
            'name' => $name,
            'url' => $url,
            'workflow_json' => (string)($p['workflow_json'] ?? ''),
            'bindings_json' => (string)($p['bindings_json'] ?? ''),
            'binding_plan_json' => (string)($p['binding_plan_json'] ?? ''),
            'seed' => $seed,
            'steps' => $steps,
            'guidance' => $guidance,
            'width' => $width,
            'height' => $height,
            'batch' => $batch,
            'timeout_sec' => $timeout,
            'apply_defaults' => $applyDefaults ? 1 : 0,
        ];
        if ($edit) {
            $megapixels = (float)($p['megapixels'] ?? 1);
            if (!is_finite($megapixels) || $megapixels <= 0) $megapixels = 1;
            if ($megapixels > 64) $megapixels = 64;
            $out['megapixels'] = $megapixels;
        }
        return $out;
    }

    private static function decode(string $raw, bool $edit): array
    {
        if (trim($raw) === '') return [];
        $decoded = json_decode($raw, true);
        if (!is_array($decoded)) return [];
        $out = [];
        $seen = [];
        $i = 0;
        foreach ($decoded as $profile) {
            if (!is_array($profile)) continue;
            if ($i >= 50) break;
            $normalized = self::normalize($profile, $i, $edit);
            $baseId = $normalized['id'];
            $id = $baseId;
            $suffix = 2;
            while (isset($seen[$id])) {
                $id = substr($baseId, 0, 90) . '_' . $suffix;
                $suffix++;
            }
            $normalized['id'] = $id;
            $seen[$id] = true;
            $out[] = $normalized;
            $i++;
        }
        return $out;
    }
}
