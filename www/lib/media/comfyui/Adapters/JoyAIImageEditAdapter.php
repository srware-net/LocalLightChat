<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class JoyAIImageEditAdapter implements AdapterInterface
{
    public function id(): string { return 'joyai-image-edit'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        if ($action !== 'edit') return null;
        $encoderAny = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'TextEncodeJoyImageEdit');
        if (!$encoderAny && !AdapterSupport::unetNameContains($graph, 'joyai_image_edit')) return null;

        $sampler = AdapterSupport::sampler($graph, ['KSampler']);
        if (!$sampler) return null;
        $positive = AdapterSupport::conditioningNode($graph, $sampler, 'positive');
        $negative = AdapterSupport::conditioningNode($graph, $sampler, 'negative');
        if (!$positive || (string)($positive[1]['class_type'] ?? '') !== 'TextEncodeJoyImageEdit') return null;

        $imageBinding = AdapterSupport::imageBindingFromLink($graph, 'input_image', $positive[1]['inputs']['images.image0'] ?? null, true);
        if (!$imageBinding) return null;
        $scale = $graph->upstreamFirst($positive[1]['inputs']['images.image0'] ?? null, fn($id,$n) => (string)($n['class_type'] ?? '') === 'ImageScaleToTotalPixels' && $graph->hasInputs($n, ['megapixels']));
        $latent = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'EmptySD3LatentImage' && $graph->hasInputs($n, ['batch_size']));

        $bindings = [
            AdapterSupport::nodeBinding('prompt', $positive, 'prompt', 'string'),
            $imageBinding,
            AdapterSupport::nodeBinding('seed', $sampler, 'seed', 'int'),
            AdapterSupport::nodeBinding('steps', $sampler, 'steps', 'int'),
            AdapterSupport::nodeBinding('guidance', $sampler, 'cfg', 'float'),
        ];
        if ($negative && (string)($negative[1]['class_type'] ?? '') === 'TextEncodeJoyImageEdit' && $graph->hasInputs($negative[1], ['prompt'])) {
            $bindings[] = AdapterSupport::nodeBinding('negative_prompt', $negative, 'prompt', 'string');
        }
        if ($scale) $bindings[] = AdapterSupport::nodeBinding('megapixels', $scale, 'megapixels', 'float');
        if ($latent) $bindings[] = AdapterSupport::nodeBinding('batch_size', $latent, 'batch_size', 'int');

        return [
            'id'=>$this->id(),
            'bindings'=>$bindings,
            'flags'=>[
                'skip_generic_prompt'=>true,
                'skip_generic_images'=>true,
                'skip_generic_seed_steps'=>true,
                'skip_generic_guidance'=>true,
                'skip_generic_size'=>true,
                'skip_generic_batch'=>true,
                'skip_generic_megapixels'=>true,
            ],
        ];
    }
}
