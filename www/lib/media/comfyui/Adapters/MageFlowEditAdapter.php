<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class MageFlowEditAdapter implements AdapterInterface
{
    public function id(): string { return 'mage-flow-edit'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        if ($action !== 'edit') return null;
        $encoder = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'TextEncodeMageFlowEdit' && $graph->hasInputs($n, ['prompt','negative_prompt']));
        if (!$encoder) return null;
        $sampler = AdapterSupport::sampler($graph, ['KSampler']);
        $imageBinding = AdapterSupport::imageBindingFromLink($graph, 'input_image', $encoder[1]['inputs']['images.image_1'] ?? null, true);
        if (!$sampler || !$imageBinding) return null;

        $widthSource = AdapterSupport::findByTitle($graph, 'PrimitiveInt', 'width');
        $heightSource = AdapterSupport::findByTitle($graph, 'PrimitiveInt', 'height');
        $matchSize = AdapterSupport::findByTitle($graph, 'PrimitiveBoolean', 'match input size');
        $scale = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'ImageScaleToTotalPixels' && $graph->hasInputs($n, ['megapixels']));

        $bindings = [
            AdapterSupport::nodeBinding('prompt', $encoder, 'prompt', 'string'),
            AdapterSupport::nodeBinding('negative_prompt', $encoder, 'negative_prompt', 'string'),
            $imageBinding,
            AdapterSupport::nodeBinding('seed', $sampler, 'seed', 'int'),
            AdapterSupport::nodeBinding('steps', $sampler, 'steps', 'int'),
            AdapterSupport::nodeBinding('guidance', $sampler, 'cfg', 'float'),
            AdapterSupport::nodeBinding('batch_size', $encoder, 'batch_size', 'int'),
        ];
        if ($widthSource && $graph->hasInputs($widthSource[1], ['value'])) $bindings[] = AdapterSupport::nodeBinding('width', $widthSource, 'value', 'int');
        if ($heightSource && $graph->hasInputs($heightSource[1], ['value'])) $bindings[] = AdapterSupport::nodeBinding('height', $heightSource, 'value', 'int');
        if ($matchSize && $graph->hasInputs($matchSize[1], ['value'])) {
            $bindings[] = AdapterSupport::staticBinding($matchSize, 'value', false, 'bool', ['when_any_params'=>['width','height']]);
        }
        if ($scale) $bindings[] = AdapterSupport::nodeBinding('megapixels', $scale, 'megapixels', 'float');

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
