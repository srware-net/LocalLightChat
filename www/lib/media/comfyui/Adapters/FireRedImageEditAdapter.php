<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

final class FireRedImageEditAdapter implements AdapterInterface
{
    public function id(): string { return 'firered-image-edit'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        if ($action !== 'edit') return null;
        $encoderAny = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'TextEncodeQwenImageEditPlus');
        if (!$encoderAny && !AdapterSupport::unetNameContains($graph, 'firered-image-edit')) return null;

        $sampler = AdapterSupport::sampler($graph, ['KSampler']);
        if (!$sampler) return null;
        $positive = AdapterSupport::conditioningNode($graph, $sampler, 'positive');
        $negative = AdapterSupport::conditioningNode($graph, $sampler, 'negative');
        if (!$positive || (string)($positive[1]['class_type'] ?? '') !== 'TextEncodeQwenImageEditPlus') return null;

        $imageBinding = AdapterSupport::imageBindingFromLink($graph, 'input_image', $positive[1]['inputs']['image1'] ?? null, true);
        if (!$imageBinding) return null;

        $stepSwitch = $graph->linkedNode($sampler[1]['inputs']['steps'] ?? null);
        $cfgSwitch = $graph->linkedNode($sampler[1]['inputs']['cfg'] ?? null);
        $activeSteps = $stepSwitch ? AdapterSupport::activeSwitchSource($graph, $stepSwitch[1]) : null;
        $activeCfg = $cfgSwitch ? AdapterSupport::activeSwitchSource($graph, $cfgSwitch[1]) : null;
        $resize = $graph->upstreamFirst($positive[1]['inputs']['image1'] ?? null, fn($id,$n) => (string)($n['class_type'] ?? '') === 'ResizeImageMaskNode' && $graph->hasInputs($n, ['resize_type.megapixels']));

        $bindings = [
            AdapterSupport::nodeBinding('prompt', $positive, 'prompt', 'string'),
            $imageBinding,
            AdapterSupport::nodeBinding('seed', $sampler, 'seed', 'int'),
        ];
        if ($negative && (string)($negative[1]['class_type'] ?? '') === 'TextEncodeQwenImageEditPlus' && $graph->hasInputs($negative[1], ['prompt'])) {
            $bindings[] = AdapterSupport::nodeBinding('negative_prompt', $negative, 'prompt', 'string');
        }
        if ($activeSteps && $graph->hasInputs($activeSteps[1], ['value'])) $bindings[] = AdapterSupport::nodeBinding('steps', $activeSteps, 'value', 'int');
        if ($activeCfg && $graph->hasInputs($activeCfg[1], ['value'])) $bindings[] = AdapterSupport::nodeBinding('guidance', $activeCfg, 'value', 'float');
        if ($resize) $bindings[] = AdapterSupport::nodeBinding('megapixels', $resize, 'resize_type.megapixels', 'float');

        $warnings = [];
        if (!$activeSteps || !$activeCfg) $warnings[] = 'FireRed switch controls could not be resolved; workflow steps/CFG remain baked in.';

        return [
            'id'=>$this->id(),
            'bindings'=>$bindings,
            'warnings'=>$warnings,
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
