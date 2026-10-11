# Media subsystem

`lib/media` owns media-reference handling and provider-specific execution/analyzer code. `api.php` should orchestrate requests, not learn model-specific ComfyUI node layouts.

## ComfyUI workflow analysis

`comfyui/WorkflowAnalyzer.php` produces a persisted `BindingPlan` from an API-format workflow. Runtime execution normally consumes that stored plan; analysis is not repeated on every render.

A workflow plan can expose multiple actions (`generate`, `edit`). This is how dual-mode workflows such as HiDream O1 are represented without inventing a third tool.

### Family adapters

Model/workflow-specific semantics live in `comfyui/Adapters/`. An adapter should only claim a workflow when it has a strong signature (custom encoder, checkpoint/UNET family, explicit mode node, etc.). The adapter returns exact semantic bindings plus flags telling the generic analyzer which categories it already owns.

Current adapters include Qwen Image 2.1, ERNIE Image, Boogu Image, Krea2 Turbo, Lens Turbo, SDXL Turbo, JoyAI Image Edit, MageFlow Edit, FireRed Image Edit, Z-Image base/turbo, Flux2 generation/edit and HiDream O1.

Important examples:

- Prompt enhancers: bind the user-facing prompt source before the enhancer rather than replacing the final CLIP text.
- Switch-controlled steps/CFG: bind the currently active primitive source and preserve the sampler/scheduler link.
- Shared dimensions: bind an upstream source used by every relevant consumer instead of disconnecting one downstream node.
- Dual-mode workflows: add an unconditional static binding that puts the workflow in the action's mode.

### Binding format

Classic parameter binding:

```json
{
  "param": "steps",
  "selector": {"id": "12", "class_type": "KSampler", "has_inputs": ["steps"]},
  "path": ["inputs", "steps"],
  "cast": "int"
}
```

`path` may be a string for legacy plans or an array. Array paths are preferred when a ComfyUI input name itself contains dots, e.g. `resize_type.megapixels`.

Static action binding:

```json
{
  "selector": {"id": "154", "class_type": "PrimitiveBoolean", "has_inputs": ["value"]},
  "path": ["inputs", "value"],
  "value": true,
  "cast": "bool"
}
```

A static binding can be conditional on explicit tool parameters with `when_any_params` or `when_all_params`. MageFlow uses this so an explicit width/height override disables its baked `Match Input Size` switch, while normal runs preserve the workflow setting.

## Regression fixtures

`comfyui/tests/run.php` covers current production workflows and the supplied model-family fixtures. When adding an adapter, add semantic assertions that prove the intended upstream control is changed and downstream graph links stay intact.

### ComfyUI live execution

`ComfyUI\Runner` keeps `/history/{prompt_id}` as the authoritative output/completion fallback, but also opens `/ws?clientId=…` before queueing a workflow. Live WebSocket events are normalized into the existing Agent Activity stream:

- `executing` → current workflow node (`_meta.title`, then `class_type` fallback)
- `progress` / `progress_state` → current node plus real `value / max` progress when meaningful
- `execution_error` → immediate node-specific failure instead of waiting for the workflow timeout
- `execution_interrupted` → cancellation
- `execution_success` → finalization while `/history` supplies the actual output descriptors

Binary preview frames are deliberately consumed but ignored for now.

Each queued prompt gets an opaque, user-scoped cancellation token. The browser never receives the ComfyUI base URL. `comfyui_cancel` resolves that token server-side and prefers ComfyUI's atomic `POST /api/jobs/{prompt_id}/cancel`; older servers fall back to verified `/queue` deletion or `/interrupt` for the matching running prompt.
