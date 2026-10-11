<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class Krea2TurboAdapter implements AdapterInterface
{
    public function id(): string { return 'krea2-turbo'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        if ($action !== 'generate') return null;
        if (!AdapterSupport::unetNameContains($graph, 'krea2_turbo') && !AdapterSupport::clipTypeIs($graph, 'krea2')) return null;

        $prompt = AdapterSupport::findByTitle($graph, 'PrimitiveStringMultiline', 'user prompt');
        $sampler = AdapterSupport::sampler($graph, ['KSampler']);
        $latent = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'EmptyLatentImage' && $graph->hasInputs($n, ['width','height','batch_size']));
        if (!$prompt || !$sampler || !$latent) return null;

        return [
            'id'=>$this->id(),
            'bindings'=>[
                AdapterSupport::nodeBinding('prompt', $prompt, 'value', 'string'),
                AdapterSupport::nodeBinding('seed', $sampler, 'seed', 'int'),
                AdapterSupport::nodeBinding('steps', $sampler, 'steps', 'int'),
                AdapterSupport::nodeBinding('guidance', $sampler, 'cfg', 'float'),
                AdapterSupport::nodeBinding('width', $latent, 'width', 'int'),
                AdapterSupport::nodeBinding('height', $latent, 'height', 'int'),
                AdapterSupport::nodeBinding('batch_size', $latent, 'batch_size', 'int'),
            ],
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
