<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class ErnieImageAdapter implements AdapterInterface
{
    public function id(): string { return 'ernie-image'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        if ($action !== 'generate') return null;
        $ernie = $graph->first(function($id,$n) use ($graph) {
            if ((string)($n['class_type'] ?? '') !== 'UNETLoader' || !$graph->hasInputs($n, ['unet_name'])) return false;
            return str_contains($graph->lower((string)($n['inputs']['unet_name'] ?? '')), 'ernie-image');
        });
        if (!$ernie) return null;

        $placeholderSource = function(string $placeholder, string $inputName) use ($graph): ?array {
            $replacer = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'StringReplace'
                && $graph->hasInputs($n, ['find','replace'])
                && (string)($n['inputs']['find'] ?? '') === $placeholder);
            if (!$replacer) return null;
            $source = $graph->linkedNode($replacer[1]['inputs']['replace'] ?? null);
            return ($source && $graph->hasInputs($source[1], [$inputName])) ? $source : null;
        };

        $promptSource = $placeholderSource('{prompt}', 'value');
        if (!$promptSource) {
            $promptSource = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'PrimitiveStringMultiline'
                && $graph->hasInputs($n, ['value'])
                && str_contains($graph->lower($graph->title($n)), 'prompt'));
        }
        if (!$promptSource) return null;

        $bindings = [
            ['param'=>'prompt','selector'=>['id'=>$promptSource[0],'has_inputs'=>['value']],'path'=>'inputs.value','cast'=>'string'],
        ];

        $samplerWithNegative = $graph->first(function($id,$n) use ($graph) {
            $ct = $graph->lower((string)($n['class_type'] ?? ''));
            return str_contains($ct, 'ksampler') && $graph->hasInputs($n, ['negative']);
        });
        $negative = $samplerWithNegative ? $graph->linkedNode($samplerWithNegative[1]['inputs']['negative'] ?? null) : null;
        if ($negative && (string)($negative[1]['class_type'] ?? '') === 'CLIPTextEncode' && $graph->hasInputs($negative[1], ['text'])) {
            $bindings[] = ['param'=>'negative_prompt','selector'=>['id'=>$negative[0],'has_inputs'=>['text']],'path'=>'inputs.text','cast'=>'string'];
        }

        $widthSource = $placeholderSource('{width}', 'source');
        $heightSource = $placeholderSource('{height}', 'source');
        if ($widthSource) $bindings[] = ['param'=>'width','selector'=>['id'=>$widthSource[0],'has_inputs'=>['source']],'path'=>'inputs.source','cast'=>'int'];
        if ($heightSource) $bindings[] = ['param'=>'height','selector'=>['id'=>$heightSource[0],'has_inputs'=>['source']],'path'=>'inputs.source','cast'=>'int'];

        return [
            'id' => $this->id(),
            'bindings' => $bindings,
            'flags' => [
                'skip_generic_prompt' => true,
                'allow_cfg_guidance' => true,
            ],
        ];
    }
}
