<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class AdapterSupport
{
    public static function unetNameContains(WorkflowGraph $graph, string $needle): bool
    {
        $needle = $graph->lower($needle);
        return (bool)$graph->first(function($id, $node) use ($graph, $needle) {
            if ((string)($node['class_type'] ?? '') !== 'UNETLoader' || !$graph->hasInputs($node, ['unet_name'])) return false;
            return str_contains($graph->lower((string)($node['inputs']['unet_name'] ?? '')), $needle);
        });
    }

    public static function checkpointNameContains(WorkflowGraph $graph, string $needle): bool
    {
        $needle = $graph->lower($needle);
        return (bool)$graph->first(function($id, $node) use ($graph, $needle) {
            $ct = (string)($node['class_type'] ?? '');
            if (!in_array($ct, ['CheckpointLoaderSimple','UNETLoader'], true)) return false;
            $input = $ct === 'CheckpointLoaderSimple' ? 'ckpt_name' : 'unet_name';
            if (!$graph->hasInputs($node, [$input])) return false;
            return str_contains($graph->lower((string)($node['inputs'][$input] ?? '')), $needle);
        });
    }

    public static function clipTypeIs(WorkflowGraph $graph, string $type): bool
    {
        $type = $graph->lower($type);
        return (bool)$graph->first(function($id, $node) use ($graph, $type) {
            if ((string)($node['class_type'] ?? '') !== 'CLIPLoader' || !$graph->hasInputs($node, ['type'])) return false;
            return $graph->lower((string)($node['inputs']['type'] ?? '')) === $type;
        });
    }

    /** @return array{0:string,1:array<string,mixed>}|null */
    public static function sampler(WorkflowGraph $graph, array $preferredClasses = []): ?array
    {
        foreach ($preferredClasses as $classType) {
            $found = $graph->first(fn($id,$node) => (string)($node['class_type'] ?? '') === $classType);
            if ($found) return $found;
        }
        return $graph->first(function($id,$node) use ($graph) {
            $ct = $graph->lower((string)($node['class_type'] ?? ''));
            return str_contains($ct, 'sampler') && (str_contains($ct, 'ksampler') || str_contains($ct, 'samplercustom'));
        });
    }

    /** @return array{0:string,1:array<string,mixed>}|null */
    public static function conditioningNode(WorkflowGraph $graph, array $sampler, string $input): ?array
    {
        return $graph->linkedNode($sampler[1]['inputs'][$input] ?? null);
    }

    /** @return array{0:string,1:array<string,mixed>}|null */
    public static function upstreamLoadImage(WorkflowGraph $graph, $link): ?array
    {
        return $graph->upstreamFirst($link, fn($id,$node) => (string)($node['class_type'] ?? '') === 'LoadImage' && $graph->hasInputs($node, ['image']));
    }

    /** @return array{0:string,1:array<string,mixed>}|null */
    public static function activeSwitchSource(WorkflowGraph $graph, array $switchNode): ?array
    {
        if ((string)($switchNode['class_type'] ?? '') !== 'ComfySwitchNode') return null;
        $enabled = $graph->booleanFromLink($switchNode['inputs']['switch'] ?? null);
        if ($enabled === null) return null;
        $branch = $enabled ? 'on_true' : 'on_false';
        return $graph->linkedNode($switchNode['inputs'][$branch] ?? null);
    }

    public static function nodeBinding(string $param, array $nodeRef, string $input, string $cast, array $extra = []): array
    {
        [$id, $node] = $nodeRef;
        $binding = [
            'param' => $param,
            'selector' => [
                'id' => (string)$id,
                'class_type' => (string)($node['class_type'] ?? ''),
                'has_inputs' => [$input],
            ],
            'path' => ['inputs', $input],
            'cast' => $cast,
        ];
        return array_replace($binding, $extra);
    }

    public static function staticBinding(array $nodeRef, string $input, $value, string $cast = '', array $extra = []): array
    {
        [$id, $node] = $nodeRef;
        $binding = [
            'selector' => [
                'id' => (string)$id,
                'class_type' => (string)($node['class_type'] ?? ''),
                'has_inputs' => [$input],
            ],
            'path' => ['inputs', $input],
            'value' => $value,
        ];
        if ($cast !== '') $binding['cast'] = $cast;
        return array_replace($binding, $extra);
    }

    public static function imageBindingFromLink(WorkflowGraph $graph, string $param, $link, bool $required = true): ?array
    {
        $load = self::upstreamLoadImage($graph, $link);
        if (!$load) return null;
        return self::nodeBinding($param, $load, 'image', 'string', ['required'=>$required]);
    }

    public static function findByTitle(WorkflowGraph $graph, string $classType, string $needle): ?array
    {
        $needle = $graph->lower($needle);
        return $graph->first(fn($id,$node) => (string)($node['class_type'] ?? '') === $classType
            && str_contains($graph->lower($graph->title($node)), $needle));
    }
}
