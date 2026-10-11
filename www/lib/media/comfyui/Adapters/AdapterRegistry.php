<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

final class AdapterRegistry
{
    /** @return AdapterInterface[] */
    public static function defaults(): array
    {
        // Most-specific workflow families first. Each analyzer pass selects at
        // most one family adapter, then adds only the generic categories that
        // adapter did not explicitly claim.
        return [
            new HiDreamO1Adapter(),
            new FireRedImageEditAdapter(),
            new MageFlowEditAdapter(),
            new JoyAIImageEditAdapter(),
            new BooguImageAdapter(),
            new Krea2TurboAdapter(),
            new LensTurboAdapter(),
            new SDXLTurboAdapter(),
            new ZImageAdapter(),
            new Flux2Adapter(),
            new QwenImage21Adapter(),
            new ErnieImageAdapter(),
        ];
    }
}
