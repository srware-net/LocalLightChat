<?php
declare(strict_types=1);

namespace LLC\Media\ComfyUI\Adapters;

use LLC\Media\ComfyUI\WorkflowGraph;

interface AdapterInterface
{
    public function id(): string;
    public function inspect(WorkflowGraph $graph, string $action): ?array;
}
