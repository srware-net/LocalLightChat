<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI;

final class BindingPlan
{
    public const SCHEMA_VERSION = 2;

    public static function fingerprint(array $workflow): string
    {
        $copy = self::sortRecursive($workflow);
        $json = json_encode($copy, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
        return hash('sha256', is_string($json) ? $json : '');
    }

    private static function sortRecursive($value)
    {
        if (!is_array($value)) return $value;
        if (array_is_list($value)) return array_map([self::class, 'sortRecursive'], $value);
        ksort($value, SORT_STRING);
        foreach ($value as $key => $child) $value[$key] = self::sortRecursive($child);
        return $value;
    }

    /**
     * BindingPlan v2 is a workflow-level bundle. One workflow can carry more
     * than one action (for example generate + edit) without duplicating the
     * profile or changing the execution format later.
     *
     * $actions shape:
     *   generate|edit => [detector, bindings, warnings]
     */
    public static function makeBundle(array $workflow, array $capabilities, array $actions): array
    {
        $caps = [];
        foreach ($capabilities as $capability) {
            $capability = (string)$capability;
            if (in_array($capability, ['generate','edit'], true) && !in_array($capability, $caps, true)) $caps[] = $capability;
        }
        if (!$caps) $caps = ['generate'];

        $normalizedActions = [];
        foreach ($actions as $action => $spec) {
            $action = (string)$action;
            if (!in_array($action, ['generate','edit'], true) || !is_array($spec)) continue;
            $normalizedActions[$action] = [
                'detector' => (string)($spec['detector'] ?? 'generic'),
                'bindings' => array_values(is_array($spec['bindings'] ?? null) ? $spec['bindings'] : []),
                'warnings' => array_values(is_array($spec['warnings'] ?? null) ? $spec['warnings'] : []),
            ];
        }

        return [
            'schema_version' => self::SCHEMA_VERSION,
            'media' => 'image',
            'provider' => 'comfyui',
            'workflow_fingerprint' => self::fingerprint($workflow),
            'capabilities' => $caps,
            'actions' => $normalizedActions,
        ];
    }

    public static function bindingsForAction(array $plan, string $action): array
    {
        $action = $action === 'edit' ? 'edit' : 'generate';
        $actions = $plan['actions'] ?? null;
        if (is_array($actions) && is_array($actions[$action] ?? null) && is_array($actions[$action]['bindings'] ?? null)) {
            return array_values($actions[$action]['bindings']);
        }

        // Compatibility with the short-lived action-scoped v2 prototype and
        // any imported hand-written plans using the same fields.
        if ((string)($plan['action'] ?? '') === $action && is_array($plan['bindings'] ?? null)) {
            return array_values($plan['bindings']);
        }
        return [];
    }

    public static function actionSpec(array $plan, string $action): ?array
    {
        $action = $action === 'edit' ? 'edit' : 'generate';
        $actions = $plan['actions'] ?? null;
        if (is_array($actions) && is_array($actions[$action] ?? null)) return $actions[$action];
        if ((string)($plan['action'] ?? '') === $action) {
            return [
                'detector'=>(string)($plan['detector'] ?? 'generic'),
                'bindings'=>array_values(is_array($plan['bindings'] ?? null) ? $plan['bindings'] : []),
                'warnings'=>array_values(is_array($plan['warnings'] ?? null) ? $plan['warnings'] : []),
            ];
        }
        return null;
    }
}
