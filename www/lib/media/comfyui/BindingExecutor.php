<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI;

final class BindingExecutor
{
    public static function apply(array $workflow, array $bindings, array $params): array
    {
        $graph = new WorkflowGraph($workflow);
        foreach ($bindings as $binding) {
            if (!is_array($binding)) continue;

            $whenAny = $binding['when_any_params'] ?? null;
            if (is_array($whenAny) && $whenAny) {
                $matched = false;
                foreach ($whenAny as $name) {
                    if (array_key_exists((string)$name, $params)) { $matched = true; break; }
                }
                if (!$matched) continue;
            }
            $whenAll = $binding['when_all_params'] ?? null;
            if (is_array($whenAll) && $whenAll) {
                $matched = true;
                foreach ($whenAll as $name) {
                    if (!array_key_exists((string)$name, $params)) { $matched = false; break; }
                }
                if (!$matched) continue;
            }

            $hasStaticValue = array_key_exists('value', $binding);
            if ($hasStaticValue) {
                $value = $binding['value'];
            } else {
                $param = (string)($binding['param'] ?? '');
                if ($param === '' || !array_key_exists($param, $params)) continue;
                $value = $params[$param];
            }

            $selector = $binding['selector'] ?? null;
            if (!is_array($selector)) continue;
            $path = $binding['path'] ?? null;
            if (!(is_string($path) || is_array($path))) continue;

            $id = $graph->findNodeId($selector);
            if ($id === null || !isset($workflow[$id]) || !is_array($workflow[$id])) continue;
            $value = self::cast($value, (string)($binding['cast'] ?? ''));
            self::setPathValue($workflow[$id], $path, $value);
        }
        return $workflow;
    }

    private static function cast($value, string $cast)
    {
        $cast = strtolower(trim($cast));
        if ($cast === 'int' || $cast === 'integer') return (int)$value;
        if ($cast === 'float' || $cast === 'number') return (float)$value;
        if ($cast === 'bool' || $cast === 'boolean') return (bool)$value;
        if ($cast === '') return $value;
        return (string)$value;
    }

    private static function setPathValue(array &$target, $path, $value): bool
    {
        if (is_array($path)) {
            $parts = array_values(array_filter(array_map(static fn($p) => (string)$p, $path), static fn($p) => $p !== ''));
        } else {
            $parts = array_values(array_filter(explode('.', (string)$path), static fn($p) => $p !== ''));
        }
        if (!$parts) return false;
        $ref =& $target;
        for ($i = 0; $i < count($parts) - 1; $i++) {
            $key = $parts[$i];
            if (!is_array($ref)) return false;
            if (!array_key_exists($key, $ref) || !is_array($ref[$key])) $ref[$key] = [];
            $ref =& $ref[$key];
        }
        if (!is_array($ref)) return false;
        $ref[$parts[count($parts)-1]] = $value;
        return true;
    }
}
