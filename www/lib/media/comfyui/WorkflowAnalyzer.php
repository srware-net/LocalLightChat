<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI;

use LLC\Media\ComfyUI\Adapters\AdapterInterface;
use LLC\Media\ComfyUI\Adapters\AdapterRegistry;

final class WorkflowAnalyzer
{
    /** @var AdapterInterface[] */
    private array $adapters;

    public function __construct(?array $adapters = null)
    {
        $this->adapters = $adapters ?? AdapterRegistry::defaults();
    }

    public function analyze(array $workflow, string $action): array
    {
        $action = $action === 'edit' ? 'edit' : 'generate';
        $graph = new WorkflowGraph($workflow);
        $capabilities = $this->inferCapabilities($graph, $action);
        $actions = [$action => $this->analyzeAction($graph, $action)];

        // Explicit dual-mode workflows (for example a real Generate/Edit switch)
        // are analyzed for both actions immediately. This lets one stored profile
        // carry both plans later without changing the plan format again.
        foreach ($capabilities as $capability) {
            if ($capability === $action || !in_array($capability, ['generate','edit'], true)) continue;
            $actions[$capability] = $this->analyzeAction($graph, $capability);
        }

        return BindingPlan::makeBundle($workflow, $capabilities, $actions);
    }

    private function analyzeAction(WorkflowGraph $graph, string $action): array
    {
        $bindings = [];
        $flags = [];
        $detectors = [];
        $warnings = [];

        foreach ($this->adapters as $adapter) {
            $result = $adapter->inspect($graph, $action);
            if (!is_array($result)) continue;
            $detectors[] = (string)($result['id'] ?? $adapter->id());
            foreach (($result['bindings'] ?? []) as $binding) if (is_array($binding)) $bindings[] = $binding;
            foreach (($result['flags'] ?? []) as $key => $value) $flags[(string)$key] = $value;
            foreach (($result['warnings'] ?? []) as $warning) if ((string)$warning !== '') $warnings[] = (string)$warning;
            break;
        }

        if ($action === 'edit') $bindings = array_merge($bindings, $this->analyzeEditGeneric($graph, $flags));
        else $bindings = array_merge($bindings, $this->analyzeGenerateGeneric($graph, $flags));

        return [
            'detector' => $detectors ? implode('+', $detectors) . '+generic' : 'generic',
            'bindings' => $this->dedupeBindings($bindings),
            'warnings' => $warnings,
        ];
    }

    private function analyzeGenerateGeneric(WorkflowGraph $graph, array $flags): array
    {
        $out = [];
        $skipPrompt = !empty($flags['skip_generic_prompt']);

        if (!$skipPrompt) {
            $flux = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncodeFlux'
                && ($graph->hasInputs($n, ['clip_l']) || $graph->hasInputs($n, ['t5xxl'])));
            if ($flux) {
                if ($graph->hasInputs($flux[1], ['clip_l'])) $out[] = ['param'=>'prompt_clip_l','selector'=>['class_type'=>'CLIPTextEncodeFlux','has_inputs'=>['clip_l']],'path'=>'inputs.clip_l','cast'=>'string'];
                if ($graph->hasInputs($flux[1], ['t5xxl'])) $out[] = ['param'=>'prompt_t5xxl','selector'=>['class_type'=>'CLIPTextEncodeFlux','has_inputs'=>['t5xxl']],'path'=>'inputs.t5xxl','cast'=>'string'];
            } else {
                $positive = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncode'
                    && $graph->hasInputs($n, ['text'])
                    && str_contains($graph->lower($graph->title($n)), 'positive'));
                $usedPositive = (bool)$positive;
                if (!$positive) $positive = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncode' && $graph->hasInputs($n, ['text']));
                if ($positive) {
                    $selector = ['class_type'=>'CLIPTextEncode','has_inputs'=>['text']];
                    if ($usedPositive) $selector['meta_title_contains'] = 'positive';
                    $out[] = ['param'=>'prompt','selector'=>$selector,'path'=>'inputs.text','cast'=>'string'];
                }
            }
        }

        if (empty($flags['skip_generic_seed_steps'])) $out = array_merge($out, $this->commonSeedSteps($graph));

        // Generation guidance preserves the previous semantics: cfg is only used
        // by explicit family adapters (Qwen/ERNIE). Legacy classic workflows do
        // not suddenly get their KSampler cfg rewritten.
        if (empty($flags['skip_generic_guidance'])) {
            $guidance = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncodeFlux' && $graph->hasInputs($n, ['guidance']));
            $guidancePath = 'inputs.guidance';
            $guidanceInput = 'guidance';
            if (!$guidance && !empty($flags['allow_cfg_guidance'])) {
                $guidance = $graph->first(function($id,$n) use ($graph) {
                    $ct = $graph->lower((string)($n['class_type'] ?? ''));
                    return (str_contains($ct, 'ksampler') || str_contains($ct, 'sampler')) && $graph->hasInputs($n, ['cfg']);
                });
                if ($guidance) {
                    $guidancePath = 'inputs.cfg';
                    $guidanceInput = 'cfg';
                }
            }
            if (!$guidance) $guidance = $graph->first(fn($id,$n) => $graph->hasInputs($n, ['guidance']));
            if ($guidance) {
                $selector = ['has_inputs'=>[$guidanceInput]];
                $ct = (string)($guidance[1]['class_type'] ?? '');
                if ($ct !== '') $selector['class_type'] = $ct;
                $out[] = ['param'=>'guidance','selector'=>$selector,'path'=>$guidancePath,'cast'=>'float'];
            }
        }

        if (empty($flags['skip_generic_size'])) {
            $size = $graph->first(fn($id,$n) => $graph->hasInputs($n, ['width','height']));
            if ($size) {
                $out[] = ['param'=>'width','selector'=>['has_inputs'=>['width','height']],'path'=>'inputs.width','cast'=>'int'];
                $out[] = ['param'=>'height','selector'=>['has_inputs'=>['width','height']],'path'=>'inputs.height','cast'=>'int'];
            }
        }

        if (empty($flags['skip_generic_batch'])) {
            $batch = $graph->first(fn($id,$n) => $graph->hasInputs($n, ['batch_size']));
            if ($batch) $out[] = ['param'=>'batch_size','selector'=>['has_inputs'=>['batch_size']],'path'=>'inputs.batch_size','cast'=>'int'];
        }

        return $out;
    }

    private function analyzeEditGeneric(WorkflowGraph $graph, array $flags): array
    {
        $out = [];
        $skipPrompt = !empty($flags['skip_generic_prompt']);
        if (!$skipPrompt) {
            $positive = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncode'
                && $graph->hasInputs($n, ['text'])
                && str_contains($graph->lower($graph->title($n)), 'positive'));
            $usedPositive = (bool)$positive;
            if (!$positive) $positive = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncode' && $graph->hasInputs($n, ['text']));
            if ($positive) {
                $selector = ['class_type'=>'CLIPTextEncode','has_inputs'=>['text']];
                if ($usedPositive) $selector['meta_title_contains'] = 'positive';
                $out[] = ['param'=>'prompt','selector'=>$selector,'path'=>'inputs.text','cast'=>'string'];
            }
            $negative = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CLIPTextEncode'
                && $graph->hasInputs($n, ['text'])
                && str_contains($graph->lower($graph->title($n)), 'negative'));
            if ($negative) $out[] = ['param'=>'negative_prompt','selector'=>['id'=>$negative[0],'class_type'=>'CLIPTextEncode','has_inputs'=>['text']],'path'=>'inputs.text','cast'=>'string'];
        }

        if (empty($flags['skip_generic_images'])) {
            $refs = $graph->referencedNodeIds();
            $loadImages = [];
            foreach ($graph->nodes() as $id => $node) {
                if ((string)($node['class_type'] ?? '') === 'LoadImage' && $graph->hasInputs($node, ['image']) && isset($refs[$id])) $loadImages[] = [$id, $node];
            }
            if ($loadImages) {
                $out[] = ['param'=>'input_image','selector'=>['id'=>$loadImages[0][0],'class_type'=>'LoadImage','has_inputs'=>['image']],'path'=>'inputs.image','cast'=>'string','required'=>true];
                if (count($loadImages) > 1) $out[] = ['param'=>'input_image_2','selector'=>['id'=>$loadImages[1][0],'class_type'=>'LoadImage','has_inputs'=>['image']],'path'=>'inputs.image','cast'=>'string','required'=>false];
            }
        }

        if (empty($flags['skip_generic_seed_steps'])) $out = array_merge($out, $this->editSeedSteps($graph));

        if (empty($flags['skip_generic_guidance'])) {
            $guidance = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'CFGGuider' && $graph->hasInputs($n, ['cfg']));
            if ($guidance) {
                $out[] = ['param'=>'guidance','selector'=>['id'=>$guidance[0],'class_type'=>'CFGGuider','has_inputs'=>['cfg']],'path'=>'inputs.cfg','cast'=>'float'];
            } else {
                $guidance = $graph->first(function($id,$n) use ($graph) {
                    $ct = $graph->lower((string)($n['class_type'] ?? ''));
                    return (str_contains($ct, 'ksampler') || str_contains($ct, 'sampler')) && $graph->hasInputs($n, ['cfg']);
                });
                if ($guidance) {
                    $out[] = ['param'=>'guidance','selector'=>['id'=>$guidance[0],'class_type'=>(string)($guidance[1]['class_type'] ?? ''),'has_inputs'=>['cfg']],'path'=>'inputs.cfg','cast'=>'float'];
                } else {
                    $guidance = $graph->first(fn($id,$n) => $graph->hasInputs($n, ['guidance']));
                    if ($guidance) $out[] = ['param'=>'guidance','selector'=>['id'=>$guidance[0],'class_type'=>(string)($guidance[1]['class_type'] ?? ''),'has_inputs'=>['guidance']],'path'=>'inputs.guidance','cast'=>'float'];
                }
            }
        }

        if (empty($flags['skip_generic_size'])) {
            $size = $graph->first(fn($id,$n) => $graph->hasInputs($n, ['width','height']));
            if ($size) {
                $out[] = ['param'=>'width','selector'=>['id'=>$size[0],'class_type'=>(string)($size[1]['class_type'] ?? ''),'has_inputs'=>['width','height']],'path'=>'inputs.width','cast'=>'int'];
                $out[] = ['param'=>'height','selector'=>['id'=>$size[0],'class_type'=>(string)($size[1]['class_type'] ?? ''),'has_inputs'=>['width','height']],'path'=>'inputs.height','cast'=>'int'];
            }
        }
        if (empty($flags['skip_generic_batch'])) {
            $batch = $graph->first(fn($id,$n) => $graph->hasInputs($n, ['batch_size']));
            if ($batch) $out[] = ['param'=>'batch_size','selector'=>['id'=>$batch[0],'class_type'=>(string)($batch[1]['class_type'] ?? ''),'has_inputs'=>['batch_size']],'path'=>'inputs.batch_size','cast'=>'int'];
        }
        if (empty($flags['skip_generic_megapixels'])) {
            $mp = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'ImageScaleToTotalPixels' && $graph->hasInputs($n, ['megapixels']));
            if ($mp) $out[] = ['param'=>'megapixels','selector'=>['id'=>$mp[0],'class_type'=>'ImageScaleToTotalPixels','has_inputs'=>['megapixels']],'path'=>'inputs.megapixels','cast'=>'float'];
        }

        return $out;
    }

    private function editSeedSteps(WorkflowGraph $graph): array
    {
        $out = [];
        $seed = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'KSampler' && $graph->hasInputs($n, ['seed']));
        if ($seed) {
            $out[] = ['param'=>'seed','selector'=>['id'=>$seed[0],'class_type'=>(string)($seed[1]['class_type'] ?? 'KSampler'),'has_inputs'=>['seed']],'path'=>'inputs.seed','cast'=>'int'];
        } else {
            $seed = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'RandomNoise' && $graph->hasInputs($n, ['noise_seed']));
            if ($seed) $out[] = ['param'=>'seed','selector'=>['id'=>$seed[0],'class_type'=>'RandomNoise','has_inputs'=>['noise_seed']],'path'=>'inputs.noise_seed','cast'=>'int'];
        }

        $steps = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'KSampler' && $graph->hasInputs($n, ['steps']));
        if (!$steps) $steps = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'Flux2Scheduler' && $graph->hasInputs($n, ['steps']));
        if (!$steps) $steps = $graph->first(function($id,$n) use ($graph) {
            $ct = $graph->lower((string)($n['class_type'] ?? ''));
            return $graph->hasInputs($n, ['steps']) && (str_contains($ct, 'ksampler') || str_contains($ct, 'scheduler'));
        });
        if ($steps) $out[] = ['param'=>'steps','selector'=>['id'=>$steps[0],'class_type'=>(string)($steps[1]['class_type'] ?? ''),'has_inputs'=>['steps']],'path'=>'inputs.steps','cast'=>'int'];
        return $out;
    }

    private function commonSeedSteps(WorkflowGraph $graph): array
    {
        $out = [];
        $seed = $graph->first(function($id,$n) use ($graph) {
            $ct = $graph->lower((string)($n['class_type'] ?? ''));
            return (str_contains($ct, 'ksampler') || str_contains($ct, 'sampler')) && $graph->hasInputs($n, ['seed']);
        });
        if ($seed) {
            $out[] = ['param'=>'seed','selector'=>['class_type'=>(string)($seed[1]['class_type'] ?? 'KSampler'),'has_inputs'=>['seed']],'path'=>'inputs.seed','cast'=>'int'];
        } else {
            $seed = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'RandomNoise' && $graph->hasInputs($n, ['noise_seed']));
            if ($seed) $out[] = ['param'=>'seed','selector'=>['class_type'=>'RandomNoise','has_inputs'=>['noise_seed']],'path'=>'inputs.noise_seed','cast'=>'int'];
        }

        $steps = $graph->first(fn($id,$n) => (string)($n['class_type'] ?? '') === 'KSampler' && $graph->hasInputs($n, ['steps']));
        if (!$steps) $steps = $graph->first(function($id,$n) use ($graph) {
            $ct = $graph->lower((string)($n['class_type'] ?? ''));
            return $graph->hasInputs($n, ['steps']) && str_contains($ct, 'ksampler');
        });
        if (!$steps) $steps = $graph->first(function($id,$n) use ($graph) {
            $ct = $graph->lower((string)($n['class_type'] ?? ''));
            return $graph->hasInputs($n, ['steps']) && str_contains($ct, 'scheduler');
        });
        if (!$steps) $steps = $graph->first(fn($id,$n) => $graph->hasInputs($n, ['steps']));
        if ($steps) {
            $selector = ['has_inputs'=>['steps']];
            $ct = (string)($steps[1]['class_type'] ?? '');
            if ($ct !== '') $selector['class_type'] = $ct;
            $title = $graph->lower($graph->title($steps[1]));
            if ($title !== '') {
                if (str_contains($title, 'scheduler')) $selector['meta_title_contains'] = 'scheduler';
                else if (str_contains($title, 'sampler')) $selector['meta_title_contains'] = 'sampler';
            }
            $out[] = ['param'=>'steps','selector'=>$selector,'path'=>'inputs.steps','cast'=>'int'];
        }
        return $out;
    }

    private function inferCapabilities(WorkflowGraph $graph, string $action): array
    {
        // Keep capability inference conservative. The action the user is
        // configuring is always supported. A workflow is marked dual-mode only
        // when it exposes an explicit switch whose title says Image Edit.
        $caps = [$action];
        $switch = $graph->first(function($id,$n) use ($graph) {
            $title = $graph->lower($graph->title($n));
            return str_contains($title, 'switch to image edit') || str_contains($title, 'image edit switch');
        });
        if ($switch) $caps = ['generate','edit'];
        return $caps;
    }

    private function dedupeBindings(array $bindings): array
    {
        $out = [];
        $seen = [];
        foreach ($bindings as $binding) {
            if (!is_array($binding)) continue;
            $key = json_encode([
                $binding['param'] ?? null,
                $binding['selector'] ?? null,
                $binding['path'] ?? null,
                array_key_exists('value', $binding) ? $binding['value'] : null,
                $binding['when_any_params'] ?? null,
                $binding['when_all_params'] ?? null,
            ], JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);
            if (isset($seen[$key])) continue;
            $seen[$key] = true;
            $out[] = $binding;
        }
        return $out;
    }
}
