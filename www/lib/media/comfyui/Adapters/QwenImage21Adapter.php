<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class QwenImage21Adapter implements AdapterInterface
{
    public function id(): string { return 'qwen-image-2.1'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        $qwen = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'TextEncodeQwenImage21' && $graph->hasInputs($n, ['prompt']));
        if (!$qwen) return null;

        $bindings = [
            ['param'=>'prompt','selector'=>['class_type'=>'TextEncodeQwenImage21','has_inputs'=>['prompt']],'path'=>'inputs.prompt','cast'=>'string'],
        ];
        if ($graph->hasInputs($qwen[1], ['negative_prompt'])) {
            $bindings[] = ['param'=>'negative_prompt','selector'=>['class_type'=>'TextEncodeQwenImage21','has_inputs'=>['negative_prompt']],'path'=>'inputs.negative_prompt','cast'=>'string'];
        }

        if ($action === 'edit') {
            foreach ([['param'=>'input_image','field'=>'images.image_1'], ['param'=>'input_image_2','field'=>'images.image_2']] as $spec) {
                if (!$graph->hasInputs($qwen[1], [$spec['field']])) continue;
                $ln = $graph->linkedNode($qwen[1]['inputs'][$spec['field']] ?? null);
                if ($ln && (string)($ln[1]['class_type'] ?? '') === 'LoadImage' && $graph->hasInputs($ln[1], ['image'])) {
                    $bindings[] = ['param'=>$spec['param'],'selector'=>['id'=>$ln[0],'class_type'=>'LoadImage','has_inputs'=>['image']],'path'=>'inputs.image','cast'=>'string','required'=>($spec['param'] === 'input_image')];
                }
            }
        }

        return [
            'id' => $this->id(),
            'bindings' => $bindings,
            'flags' => [
                'skip_generic_prompt' => true,
                'skip_generic_images' => $action === 'edit',
                'allow_cfg_guidance' => true,
            ],
        ];
    }
}
