<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class HiDreamO1Adapter implements AdapterInterface
{
    public function id(): string { return 'hidream-o1'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        $reference = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'HiDreamO1ReferenceImages');
        $modeSwitch = AdapterSupport::findByTitle($graph, 'PrimitiveBoolean', 'switch to image edit');
        if (!$reference || !$modeSwitch) return null;

        $prompt = AdapterSupport::findByTitle($graph, 'PrimitiveStringMultiline', 'user prompt');
        $sampler = AdapterSupport::sampler($graph, ['SamplerCustom']);
        $scheduler = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'BasicScheduler' && $graph->hasInputs($n, ['steps']));
        $negative = $graph->linkedNode($reference[1]['inputs']['negative'] ?? null);
        if (!$prompt || !$sampler || !$scheduler) return null;

        $bindings = [
            AdapterSupport::staticBinding($modeSwitch, 'value', $action === 'edit', 'bool'),
            AdapterSupport::nodeBinding('prompt', $prompt, 'value', 'string'),
            AdapterSupport::nodeBinding('seed', $sampler, 'noise_seed', 'int'),
            AdapterSupport::nodeBinding('steps', $scheduler, 'steps', 'int'),
            AdapterSupport::nodeBinding('guidance', $sampler, 'cfg', 'float'),
        ];
        if ($negative && (string)($negative[1]['class_type'] ?? '') === 'CLIPTextEncode' && $graph->hasInputs($negative[1], ['text'])) {
            $bindings[] = AdapterSupport::nodeBinding('negative_prompt', $negative, 'text', 'string');
        }

        if ($action === 'edit') {
            $imageBinding = AdapterSupport::imageBindingFromLink($graph, 'input_image', $reference[1]['inputs']['images.image_1'] ?? null, true);
            if (!$imageBinding) return null;
            $bindings[] = $imageBinding;
            $editLatent = $graph->first(function($id,$n) use ($graph) {
                if ((string)($n['class_type'] ?? '') !== 'EmptyHiDreamO1LatentImage' || !$graph->hasInputs($n, ['width','height','batch_size'])) return false;
                return $graph->isLink($n['inputs']['width'] ?? null) || $graph->isLink($n['inputs']['height'] ?? null);
            });
            if ($editLatent) $bindings[] = AdapterSupport::nodeBinding('batch_size', $editLatent, 'batch_size', 'int');
        } else {
            $genLatent = $graph->first(function($id,$n) use ($graph) {
                if ((string)($n['class_type'] ?? '') !== 'EmptyHiDreamO1LatentImage' || !$graph->hasInputs($n, ['width','height','batch_size'])) return false;
                return !$graph->isLink($n['inputs']['width'] ?? null) && !$graph->isLink($n['inputs']['height'] ?? null);
            });
            if ($genLatent) {
                $bindings[] = AdapterSupport::nodeBinding('width', $genLatent, 'width', 'int');
                $bindings[] = AdapterSupport::nodeBinding('height', $genLatent, 'height', 'int');
                $bindings[] = AdapterSupport::nodeBinding('batch_size', $genLatent, 'batch_size', 'int');
            }
        }

        return [
            'id'=>$this->id(),
            'bindings'=>$bindings,
            'flags'=>[
                'skip_generic_prompt'=>true,
                'skip_generic_images'=>$action === 'edit',
                'skip_generic_seed_steps'=>true,
                'skip_generic_guidance'=>true,
                'skip_generic_size'=>true,
                'skip_generic_batch'=>true,
                'skip_generic_megapixels'=>true,
            ],
        ];
    }
}
