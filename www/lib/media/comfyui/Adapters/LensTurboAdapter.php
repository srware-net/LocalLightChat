<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class LensTurboAdapter implements AdapterInterface
{
    public function id(): string { return 'lens-turbo'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        if ($action !== 'generate') return null;
        if (!AdapterSupport::unetNameContains($graph, 'lens_turbo') && !AdapterSupport::clipTypeIs($graph, 'lens')) return null;

        $sampler = AdapterSupport::sampler($graph, ['SamplerCustom']);
        $scheduler = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'BasicScheduler' && $graph->hasInputs($n, ['steps']));
        $latent = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'EmptyLatentImage' && $graph->hasInputs($n, ['batch_size']));
        if (!$sampler || !$scheduler || !$latent) return null;

        $positive = AdapterSupport::conditioningNode($graph, $sampler, 'positive');
        $negative = AdapterSupport::conditioningNode($graph, $sampler, 'negative');
        if (!$positive || (string)($positive[1]['class_type'] ?? '') !== 'CLIPTextEncode') return null;

        $widthMath = $graph->upstreamFirst($latent[1]['inputs']['width'] ?? null, fn($id,$n) => (string)($n['class_type'] ?? '') === 'ComfyMathExpression' && $graph->hasInputs($n, ['values.a']));
        $heightMath = $graph->upstreamFirst($latent[1]['inputs']['height'] ?? null, fn($id,$n) => (string)($n['class_type'] ?? '') === 'ComfyMathExpression' && $graph->hasInputs($n, ['values.a']));
        $widthSource = $widthMath ? $graph->linkedNode($widthMath[1]['inputs']['values.a'] ?? null) : null;
        $heightSource = $heightMath ? $graph->linkedNode($heightMath[1]['inputs']['values.a'] ?? null) : null;

        $bindings = [
            AdapterSupport::nodeBinding('prompt', $positive, 'text', 'string'),
            AdapterSupport::nodeBinding('seed', $sampler, 'noise_seed', 'int'),
            AdapterSupport::nodeBinding('guidance', $sampler, 'cfg', 'float'),
            AdapterSupport::nodeBinding('steps', $scheduler, 'steps', 'int'),
            AdapterSupport::nodeBinding('batch_size', $latent, 'batch_size', 'int'),
        ];
        if ($negative && (string)($negative[1]['class_type'] ?? '') === 'CLIPTextEncode') $bindings[] = AdapterSupport::nodeBinding('negative_prompt', $negative, 'text', 'string');
        if ($widthSource && $graph->hasInputs($widthSource[1], ['value'])) $bindings[] = AdapterSupport::nodeBinding('width', $widthSource, 'value', 'int');
        if ($heightSource && $graph->hasInputs($heightSource[1], ['value'])) $bindings[] = AdapterSupport::nodeBinding('height', $heightSource, 'value', 'int');

        return [
            'id'=>$this->id(),
            'bindings'=>$bindings,
            'flags'=>[
                'skip_generic_prompt'=>true,
                'skip_generic_seed_steps'=>true,
                'skip_generic_guidance'=>true,
                'skip_generic_size'=>true,
                'skip_generic_batch'=>true,
            ],
        ];
    }
}
