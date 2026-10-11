<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI;

final class WorkflowGraph
{
    /** @var array<string,array<string,mixed>> */
    private array $nodes = [];

    public function __construct(array $workflow)
    {
        foreach ($workflow as $id => $node) {
            if (!is_array($node)) continue;
            $this->nodes[(string)$id] = $node;
        }
    }

    /** @return array<string,array<string,mixed>> */
    public function nodes(): array
    {
        return $this->nodes;
    }

    public function node(string $id): ?array
    {
        $node = $this->nodes[$id] ?? null;
        return is_array($node) ? $node : null;
    }


    public function lower(string $value): string
    {
        return function_exists('mb_strtolower') ? \mb_strtolower($value) : strtolower($value);
    }

    public function title(array $node): string
    {
        $meta = $node['_meta'] ?? null;
        return is_array($meta) ? (string)($meta['title'] ?? '') : '';
    }

    public function hasInputs(array $node, array $keys): bool
    {
        $inputs = $node['inputs'] ?? null;
        if (!is_array($inputs)) return false;
        foreach ($keys as $key) {
            if (!array_key_exists((string)$key, $inputs)) return false;
        }
        return true;
    }

    /** @return array{0:string,1:array<string,mixed>}|null */
    public function first(callable $predicate): ?array
    {
        foreach ($this->nodes as $id => $node) {
            $sid = (string)$id;
            try {
                if ($predicate($sid, $node)) return [$sid, $node];
            } catch (\Throwable $e) {
                // Detector predicates are intentionally best-effort.
            }
        }
        return null;
    }


    /** @return array<int,array{0:string,1:array<string,mixed>}> */
    public function all(callable $predicate): array
    {
        $out = [];
        foreach ($this->nodes as $id => $node) {
            $sid = (string)$id;
            try {
                if ($predicate($sid, $node)) $out[] = [$sid, $node];
            } catch (\Throwable $e) {
                // Best-effort graph queries must not make analysis fatal.
            }
        }
        return $out;
    }

    public function isLink($value): bool
    {
        return is_array($value)
            && array_is_list($value)
            && count($value) >= 2
            && (is_string($value[0]) || is_int($value[0]))
            && is_int($value[1]);
    }

    /** @return array{0:string,1:array<string,mixed>}|null */
    public function upstreamFirst($link, callable $predicate, int $maxDepth = 12): ?array
    {
        if (!$this->isLink($link)) return null;
        $queue = [[(string)$link[0], 0]];
        $seen = [];
        while ($queue) {
            [$id, $depth] = array_shift($queue);
            if (isset($seen[$id]) || $depth > $maxDepth) continue;
            $seen[$id] = true;
            $node = $this->node($id);
            if ($node === null) continue;
            try {
                if ($predicate($id, $node)) return [$id, $node];
            } catch (\Throwable $e) {
                // Keep tracing.
            }
            if ($depth === $maxDepth) continue;
            foreach (($node['inputs'] ?? []) as $value) {
                if ($this->isLink($value)) $queue[] = [(string)$value[0], $depth + 1];
            }
        }
        return null;
    }

    public function valueFromLink($link)
    {
        $node = $this->linkedNode($link);
        if (!$node) return null;
        $inputs = $node[1]['inputs'] ?? null;
        if (!is_array($inputs) || !array_key_exists('value', $inputs)) return null;
        $value = $inputs['value'];
        return $this->isLink($value) ? null : $value;
    }

    public function booleanFromLink($link): ?bool
    {
        $value = $this->valueFromLink($link);
        if (is_bool($value)) return $value;
        if ($value === 1 || $value === '1' || $value === 'true') return true;
        if ($value === 0 || $value === '0' || $value === 'false') return false;
        return null;
    }

    /** @return array{0:string,1:array<string,mixed>}|null */
    public function linkedNode($link): ?array
    {
        if (!is_array($link) || count($link) < 1) return null;
        $id = (string)$link[0];
        $node = $this->node($id);
        return $node === null ? null : [$id, $node];
    }

    public function selectorMatch(string $id, array $node, array $selector): bool
    {
        if (isset($selector['id']) && (string)$selector['id'] !== '' && (string)$selector['id'] !== $id) return false;
        if (isset($selector['class_type']) && (string)$selector['class_type'] !== '' && (string)($node['class_type'] ?? '') !== (string)$selector['class_type']) return false;
        if (isset($selector['meta_title_contains']) && (string)$selector['meta_title_contains'] !== '') {
            $title = $this->lower($this->title($node));
            $needle = $this->lower((string)$selector['meta_title_contains']);
            if ($needle !== '' && !str_contains($title, $needle)) return false;
        }
        if (isset($selector['has_inputs']) && is_array($selector['has_inputs']) && !$this->hasInputs($node, $selector['has_inputs'])) return false;
        return true;
    }

    public function findNodeId(array $selector): ?string
    {
        foreach ($this->nodes as $id => $node) {
            $sid = (string)$id;
            if ($this->selectorMatch($sid, $node, $selector)) return $sid;
        }
        return null;
    }

    /** @return array<string,bool> */
    public function referencedNodeIds(): array
    {
        $refs = [];
        $walk = function($value) use (&$walk, &$refs): void {
            if (!is_array($value)) return;
            if (array_is_list($value) && count($value) >= 2 && (is_string($value[0]) || is_int($value[0])) && is_int($value[1])) {
                $refs[(string)$value[0]] = true;
                return;
            }
            foreach ($value as $child) $walk($child);
        };
        foreach ($this->nodes as $node) $walk($node['inputs'] ?? []);
        return $refs;
    }
}
