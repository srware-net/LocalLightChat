<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

/**
 * Z-Image family (base + turbo) text-to-image workflows.
 *
 * Both supplied graphs use Lumina2/Qwen text encoding, AuraFlow model sampling,
 * an EmptySD3 latent and a KSampler. Base exposes a real negative-prompt
 * encoder while Turbo zeroes the positive conditioning for its negative branch.
 */
final class ZImageAdapter implements AdapterInterface
{
    public function id(): string { return 'z-image'; }

    public function inspect(WorkflowGraph $graph, string $action): ?array
    {
        if ($action !== 'generate') return null;
        if (!AdapterSupport::unetNameContains($graph, 'z_image')) return null;
        if (!AdapterSupport::clipTypeIs($graph, 'lumina2')) return null;

        $sampler = AdapterSupport::sampler($graph, ['KSampler']);
        $latent = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'EmptySD3LatentImage'
            && $graph->hasInputs($n, ['width','height','batch_size']));
        if (!$sampler || !$latent) return null;

        $positive = AdapterSupport::conditioningNode($graph, $sampler, 'positive');
        if (!$positive || (string)($positive[1]['class_type'] ?? '') !== 'CLIPTextEncode' || !$graph->hasInputs($positive[1], ['text'])) return null;

        $negative = AdapterSupport::conditioningNode($graph, $sampler, 'negative');
        $bindings = [
            AdapterSupport::nodeBinding('prompt', $positive, 'text', 'string'),
            AdapterSupport::nodeBinding('seed', $sampler, 'seed', 'int'),
            AdapterSupport::nodeBinding('steps', $sampler, 'steps', 'int'),
            AdapterSupport::nodeBinding('guidance', $sampler, 'cfg', 'float'),
            // Explicit width/height overrides intentionally replace a baked
            // ResolutionSelector link on Z-Image base. When no override/default
            // is applied, the original selector link remains untouched.
            AdapterSupport::nodeBinding('width', $latent, 'width', 'int'),
            AdapterSupport::nodeBinding('height', $latent, 'height', 'int'),
            AdapterSupport::nodeBinding('batch_size', $latent, 'batch_size', 'int'),
        ];

        // Base has a real negative CLIPTextEncode. Turbo routes its negative
        // conditioning through ConditioningZeroOut, so exposing a negative
        // prompt there would be misleading and is deliberately omitted.
        if ($negative && (string)($negative[1]['class_type'] ?? '') === 'CLIPTextEncode' && $graph->hasInputs($negative[1], ['text'])) {
            $bindings[] = AdapterSupport::nodeBinding('negative_prompt', $negative, 'text', 'string');
        }

        $isTurbo = AdapterSupport::unetNameContains($graph, 'z_image_turbo');
        return [
            'id' => $this->id() . ($isTurbo ? '-turbo' : '-base'),
            'bindings' => $bindings,
            'flags' => [
                'skip_generic_prompt'=>true,
                'skip_generic_seed_steps'=>true,
                'skip_generic_guidance'=>true,
                'skip_generic_size'=>true,
                'skip_generic_batch'=>true,
            ],
        ];
    }
}
