<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class SDXLTurboAdapter implements AdapterInterface
{
    public function id(): string { return 'sdxl-turbo'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        if ($action !== 'generate') return null;
        $scheduler = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'SDTurboScheduler' && $graph->hasInputs($n, ['steps']));
        if (!$scheduler && !AdapterSupport::checkpointNameContains($graph, 'sd_xl_turbo')) return null;
        if (!$scheduler) return null;

        $sampler = AdapterSupport::sampler($graph, ['SamplerCustom']);
        $latent = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'EmptyLatentImage' && $graph->hasInputs($n, ['width','height','batch_size']));
        if (!$sampler || !$latent) return null;
        $positive = AdapterSupport::conditioningNode($graph, $sampler, 'positive');
        $negative = AdapterSupport::conditioningNode($graph, $sampler, 'negative');
        if (!$positive || (string)($positive[1]['class_type'] ?? '') !== 'CLIPTextEncode') return null;

        $bindings = [
            AdapterSupport::nodeBinding('prompt', $positive, 'text', 'string'),
            AdapterSupport::nodeBinding('seed', $sampler, 'noise_seed', 'int'),
            AdapterSupport::nodeBinding('guidance', $sampler, 'cfg', 'float'),
            AdapterSupport::nodeBinding('steps', $scheduler, 'steps', 'int'),
            AdapterSupport::nodeBinding('width', $latent, 'width', 'int'),
            AdapterSupport::nodeBinding('height', $latent, 'height', 'int'),
            AdapterSupport::nodeBinding('batch_size', $latent, 'batch_size', 'int'),
        ];
        if ($negative && (string)($negative[1]['class_type'] ?? '') === 'CLIPTextEncode') $bindings[] = AdapterSupport::nodeBinding('negative_prompt', $negative, 'text', 'string');

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
