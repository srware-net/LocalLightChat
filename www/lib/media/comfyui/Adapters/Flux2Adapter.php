<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class Flux2Adapter implements AdapterInterface
{
    public function id(): string { return 'flux2'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        $scheduler = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'Flux2Scheduler');
        if (!$scheduler || (!AdapterSupport::clipTypeIs($graph, 'flux2') && !AdapterSupport::unetNameContains($graph, 'flux2'))) return null;

        if ($action === 'generate') {
            // A Flux2 T2I graph has the same scheduler/noise/guidance family as
            // Flux2 edit, but no ReferenceLatent branch. Keep the Turbo-LoRA
            // step switch intact and update both scheduler + latent dimensions.
            $reference = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'ReferenceLatent');
            if ($reference) return null;

            $positive = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncode'
                && $graph->hasInputs($n, ['text'])
                && str_contains($graph->lower($graph->title($n)), 'positive'));
            if (!$positive) $positive = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncode' && $graph->hasInputs($n, ['text']));
            $noise = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'RandomNoise' && $graph->hasInputs($n, ['noise_seed']));
            $guidance = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'FluxGuidance' && $graph->hasInputs($n, ['guidance']));
            $latent = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'EmptyFlux2LatentImage' && $graph->hasInputs($n, ['width','height','batch_size']));
            if (!$positive || !$noise || !$latent) return null;

            $stepSource = null;
            $stepsLink = $scheduler[1]['inputs']['steps'] ?? null;
            $stepNode = $graph->linkedNode($stepsLink);
            if ($stepNode && (string)($stepNode[1]['class_type'] ?? '') === 'ComfySwitchNode') $stepSource = AdapterSupport::activeSwitchSource($graph, $stepNode[1]);

            $bindings = [
                AdapterSupport::nodeBinding('prompt', $positive, 'text', 'string'),
                AdapterSupport::nodeBinding('seed', $noise, 'noise_seed', 'int'),
            ];
            if ($guidance) $bindings[] = AdapterSupport::nodeBinding('guidance', $guidance, 'guidance', 'float');
            if ($stepSource && $graph->hasInputs($stepSource[1], ['value'])) $bindings[] = AdapterSupport::nodeBinding('steps', $stepSource, 'value', 'int');
            else if ($graph->hasInputs($scheduler[1], ['steps']) && !$graph->isLink($scheduler[1]['inputs']['steps'] ?? null)) $bindings[] = AdapterSupport::nodeBinding('steps', $scheduler, 'steps', 'int');

            // Flux2Scheduler uses the image dimensions when constructing sigmas,
            // while EmptyFlux2LatentImage creates the actual latent. Keep them in sync.
            if ($graph->hasInputs($scheduler[1], ['width','height'])) {
                $bindings[] = AdapterSupport::nodeBinding('width', $scheduler, 'width', 'int');
                $bindings[] = AdapterSupport::nodeBinding('height', $scheduler, 'height', 'int');
            }
            $bindings[] = AdapterSupport::nodeBinding('width', $latent, 'width', 'int');
            $bindings[] = AdapterSupport::nodeBinding('height', $latent, 'height', 'int');
            $bindings[] = AdapterSupport::nodeBinding('batch_size', $latent, 'batch_size', 'int');

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

        if ($action !== 'edit') return null;
        $reference = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'ReferenceLatent');
        if (!$reference) return null;

        $positive = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncode'
            && $graph->hasInputs($n, ['text'])
            && str_contains($graph->lower($graph->title($n)), 'positive'));
        if (!$positive) $positive = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncode' && $graph->hasInputs($n, ['text']));
        $noise = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'RandomNoise' && $graph->hasInputs($n, ['noise_seed']));
        $guidance = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'FluxGuidance' && $graph->hasInputs($n, ['guidance']));
        $latent = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'EmptyFlux2LatentImage' && $graph->hasInputs($n, ['batch_size']));
        $scale = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'ImageScaleToTotalPixels' && $graph->hasInputs($n, ['megapixels']));
        $imageBinding = AdapterSupport::imageBindingFromLink($graph, 'input_image', $reference[1]['inputs']['latent'] ?? null, true);
        if (!$positive || !$noise || !$imageBinding) return null;

        $stepSource = null;
        $stepsLink = $scheduler[1]['inputs']['steps'] ?? null;
        $stepNode = $graph->linkedNode($stepsLink);
        if ($stepNode && (string)($stepNode[1]['class_type'] ?? '') === 'ComfySwitchNode') $stepSource = AdapterSupport::activeSwitchSource($graph, $stepNode[1]);

        $bindings = [
            AdapterSupport::nodeBinding('prompt', $positive, 'text', 'string'),
            $imageBinding,
            AdapterSupport::nodeBinding('seed', $noise, 'noise_seed', 'int'),
        ];
        if ($guidance) $bindings[] = AdapterSupport::nodeBinding('guidance', $guidance, 'guidance', 'float');
        if ($stepSource && $graph->hasInputs($stepSource[1], ['value'])) $bindings[] = AdapterSupport::nodeBinding('steps', $stepSource, 'value', 'int');
        else if ($graph->hasInputs($scheduler[1], ['steps']) && !$graph->isLink($scheduler[1]['inputs']['steps'] ?? null)) $bindings[] = AdapterSupport::nodeBinding('steps', $scheduler, 'steps', 'int');
        if ($latent) $bindings[] = AdapterSupport::nodeBinding('batch_size', $latent, 'batch_size', 'int');
        if ($scale) $bindings[] = AdapterSupport::nodeBinding('megapixels', $scale, 'megapixels', 'float');

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
