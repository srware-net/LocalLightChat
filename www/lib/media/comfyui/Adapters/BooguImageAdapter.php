<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class BooguImageAdapter implements AdapterInterface
{
    public function id(): string { return 'boogu-image'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        if ($action === 'generate') {
            if (!AdapterSupport::unetNameContains($graph, 'boogu_image_turbo')) return null;
            $sampler = AdapterSupport::sampler($graph, ['KSampler']);
            $prompt = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncode' && $graph->hasInputs($n, ['text']));
            $latent = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'EmptyLatentImage' && $graph->hasInputs($n, ['width','height','batch_size']));
            if (!$sampler || !$prompt || !$latent) return null;

            $bindings = [
                AdapterSupport::nodeBinding('prompt', $prompt, 'text', 'string'),
                AdapterSupport::nodeBinding('seed', $sampler, 'seed', 'int'),
                AdapterSupport::nodeBinding('steps', $sampler, 'steps', 'int'),
                AdapterSupport::nodeBinding('guidance', $sampler, 'cfg', 'float'),
                AdapterSupport::nodeBinding('width', $latent, 'width', 'int'),
                AdapterSupport::nodeBinding('height', $latent, 'height', 'int'),
                AdapterSupport::nodeBinding('batch_size', $latent, 'batch_size', 'int'),
            ];
            return [
                'id'=>$this->id() . '-generate',
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

        $encoder = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'TextEncodeBooguEdit' && $graph->hasInputs($n, ['prompt','negative_prompt']));
        if (!$encoder) return null;
        $sampler = AdapterSupport::sampler($graph, ['SamplerCustom']);
        $scheduler = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'BasicScheduler' && $graph->hasInputs($n, ['steps']));
        $imageBinding = AdapterSupport::imageBindingFromLink($graph, 'input_image', $encoder[1]['inputs']['images.image_1'] ?? null, true);
        $resize = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'ResizeImageMaskNode' && $graph->hasInputs($n, ['resize_type.megapixels']));
        $latent = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'EmptyLatentImage' && $graph->hasInputs($n, ['batch_size']));
        if (!$sampler || !$scheduler || !$imageBinding) return null;

        $bindings = [
            AdapterSupport::nodeBinding('prompt', $encoder, 'prompt', 'string'),
            AdapterSupport::nodeBinding('negative_prompt', $encoder, 'negative_prompt', 'string'),
            $imageBinding,
            AdapterSupport::nodeBinding('seed', $sampler, 'noise_seed', 'int'),
            AdapterSupport::nodeBinding('guidance', $sampler, 'cfg', 'float'),
            AdapterSupport::nodeBinding('steps', $scheduler, 'steps', 'int'),
        ];
        if ($resize) $bindings[] = AdapterSupport::nodeBinding('megapixels', $resize, 'resize_type.megapixels', 'float');
        if ($latent) $bindings[] = AdapterSupport::nodeBinding('batch_size', $latent, 'batch_size', 'int');

        return [
            'id'=>$this->id() . '-edit',
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
