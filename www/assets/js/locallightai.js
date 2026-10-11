const SERVICE_META = {
  llama: {
    domain: 'runtime',
    title: 'Inference Runtime',
    shortTitle: 'Runtime',
    backend: 'llama.cpp',
    description: 'Local inference backend / model router',
  },
  ragd: {
    domain: 'retrieval',
    title: 'Retrieval',
    shortTitle: 'Retrieval',
    backend: 'RAGd',
    description: 'Local retrieval and indexing service',
  },
  mcp: {
    domain: 'mcp',
    title: 'Agent Runtime',
    shortTitle: 'Agent',
    backend: 'Local Agent · MCP',
    description: 'Local agent execution runtime',
  },
};

const LLAMA_CACHE_TYPES = [
  ['', 'Engine default (f16)'],
  ['f32', 'f32'], ['f16', 'f16'], ['bf16', 'bf16'], ['q8_0', 'q8_0'],
  ['q4_0', 'q4_0'], ['q4_1', 'q4_1'], ['iq4_nl', 'iq4_nl'],
  ['q5_0', 'q5_0'], ['q5_1', 'q5_1'],
];

// Suggestions only. Nothing is applied while scanning or when a family name is
// detected; Apply is always an explicit user action.
const MODEL_RECOMMENDED_PRESETS = {
  // Keep Qwen intentionally simple: one standard thinking preset per materially
  // different generation family. Qwen3.5 and Qwen3.6 share the same general
  // thinking recommendation; Qwen3.8 and Qwen3.8 Flash share theirs as well.
  'qwen3-thinking': {label:'Qwen3 · Thinking', values:{temperature:0.6, top_k:20, top_p:0.95, min_p:0}},
  'qwen35-36-thinking': {label:'Qwen3.5 / Qwen3.6 · Thinking', values:{temperature:1.0, top_k:20, top_p:0.95, min_p:0, presence_penalty:1.5, repeat_penalty:1}},
  'qwen38-thinking': {label:'Qwen3.8 / Qwen3.8 Flash · Thinking', values:{temperature:1.0, top_k:20, top_p:0.95, min_p:0, presence_penalty:0, repeat_penalty:1}},

  'gemma3': {label:'Gemma 3', values:{top_k:64, top_p:0.95}},
  'gemma4': {label:'Gemma 4', values:{temperature:1.0, top_k:64, top_p:0.95}},
  'gpt-oss': {label:'GPT-OSS 20B / 120B', values:{temperature:1.0, top_p:1.0}},
  'nemotron3-super': {label:'NVIDIA Nemotron 3 Super', values:{temperature:1.0, top_p:0.95}},
  'nemotron3-nano-reasoning': {label:'NVIDIA Nemotron 3 Nano · Reasoning', values:{temperature:1.0, top_p:1.0}},
  'nemotron3-nano-tools': {label:'NVIDIA Nemotron 3 Nano · Tool calling', values:{temperature:0.6, top_p:0.95}},
  'muse-glimmer': {label:'Meta Muse Glimmer', values:{temperature:1.0, top_k:64, top_p:0.95}},
  'deepseek-v4': {label:'DeepSeek V4', values:{temperature:1.0, top_p:1.0}},
};

const PLACEHOLDER_COPY = {
  models: {
    title: 'Models',
    body: 'Installed and available local model artifacts will appear here.',
    tag: 'No model inventory available',
  },
  activity: {
    title: 'Activity',
    body: 'Downloads, installs, updates, indexing and other background tasks will appear here.',
    tag: 'No activity',
  },
};

function esc(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function boolText(value) {
  if (value === null || value === undefined) return 'n/a';
  return value ? 'yes' : 'no';
}

function displayValue(value, fallback = 'n/a') {
  if (value === null || value === undefined || value === '') return fallback;
  return String(value);
}

function loadStyles() {
  if (document.querySelector('link[data-llai-style]')) return;
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = 'assets/css/locallightai.css?v=3e2';
  link.dataset.llaiStyle = '1';
  document.head.appendChild(link);
}

function createModeSwitch() {
  const wrap = document.createElement('div');
  wrap.className = 'llai-mode-switch-wrap';
  wrap.innerHTML = `
    <div class="llai-mode-switch" role="group" aria-label="Workspace mode">
      <button type="button" class="llai-mode-btn active" data-llai-mode="chat" aria-pressed="true">
        <span class="llai-mode-icon" aria-hidden="true">▣</span><span>Chat</span>
      </button>
      <button type="button" class="llai-mode-btn" data-llai-mode="control" aria-pressed="false">
        <span class="llai-mode-icon" aria-hidden="true">⚙</span><span>Control</span>
      </button>
    </div>`;
  return wrap;
}

function placeholderPanel(id) {
  const copy = PLACEHOLDER_COPY[id];
  return `
    <div class="llai-tab-panel llai-placeholder" data-llai-panel="${id}" hidden>
      <h2>${esc(copy.title)}</h2>
      <p>${esc(copy.body)}</p>
      <div class="llai-placeholder-tag">${esc(copy.tag)}</div>
    </div>`;
}

function managedConfigCard(kind) {
  const retrieval = kind === 'retrieval';
  return `
    <section class="llai-config-card llai-config-card-wide">
      <div class="llai-config-card-head">
        <div>
          <h3>${retrieval ? 'RAGd configuration' : 'Agent Runtime configuration'}</h3>
          <p>${retrieval ? 'Server defaults, retrieval engine and embedding/reranker settings.' : 'Server, security, capabilities, limits and logging.'}</p>
        </div>
      </div>
      <div id="llai-${kind}-config-content" class="llai-config-content">
        <div class="llai-service-empty">Configuration has not been loaded yet.</div>
      </div>
    </section>`;
}

function managedConfigState(managed) {
  if (!managed) return 'Not queried';
  if (!managed.exists) return managed.error || 'Not found';
  if (!managed.readable) return managed.error || 'Not readable';
  return 'Loaded';
}

function checked(value) {
  return value ? ' checked' : '';
}

function field(label, path, value, options = {}) {
  const type = options.type || 'text';
  const min = options.min !== undefined ? ` min="${esc(options.min)}"` : '';
  const max = options.max !== undefined ? ` max="${esc(options.max)}"` : '';
  const step = options.step !== undefined ? ` step="${esc(options.step)}"` : '';
  const placeholder = options.placeholder ? ` placeholder="${esc(options.placeholder)}"` : '';
  return `
    <label class="llai-form-field">
      <span>${esc(label)}</span>
      <input type="${esc(type)}" data-config-path="${esc(path)}" value="${esc(displayValue(value, ''))}"${min}${max}${step}${placeholder}>
    </label>`;
}

function checkboxField(label, path, value) {
  return `
    <label class="llai-check-field">
      <input type="checkbox" data-config-path="${esc(path)}"${checked(!!value)}>
      <span>${esc(label)}</span>
    </label>`;
}

function selectField(label, path, value, values) {
  return `
    <label class="llai-form-field">
      <span>${esc(label)}</span>
      <select data-config-path="${esc(path)}">
        ${values.map(v => `<option value="${esc(v)}"${String(value) === String(v) ? ' selected' : ''}>${esc(v)}</option>`).join('')}
      </select>
    </label>`;
}

function textareaField(label, path, value, lines = false) {
  const text = Array.isArray(value) ? value.join('\n') : displayValue(value, '');
  return `
    <label class="llai-form-field llai-form-field-wide">
      <span>${esc(label)}</span>
      <textarea data-config-path="${esc(path)}"${lines ? ' data-lines="1"' : ''}>${esc(text)}</textarea>
    </label>`;
}

function secretField(label, path, currentValue, clearPath) {
  const configured = String(currentValue || '').includes('configured');
  return `
    <div class="llai-secret-field llai-form-field-wide">
      <label class="llai-form-field">
        <span>${esc(label)}</span>
        <input type="password" autocomplete="new-password" data-config-path="${esc(path)}" value="" placeholder="${configured ? 'Configured — enter a new value to replace' : 'Not configured'}">
      </label>
      ${configured ? checkboxField('Remove configured value', clearPath, false) : ''}
    </div>`;
}

function formSection(title, body, advanced = false) {
  if (advanced) {
    return `<details class="llai-form-details"><summary>${esc(title)}</summary><div class="llai-form-section-body">${body}</div></details>`;
  }
  return `<section class="llai-form-section"><h4>${esc(title)}</h4><div class="llai-form-section-body">${body}</div></section>`;
}

function formatBytes(value) {
  const n = Number(value || 0);
  if (!Number.isFinite(n) || n <= 0) return 'Size unknown';
  const units = ['B','KB','MB','GB','TB'];
  let v = n;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  return `${v >= 10 || i === 0 ? v.toFixed(0) : v.toFixed(1)} ${units[i]}`;
}

function modelField(label, path, value, options = {}) {
  const type = options.type || 'text';
  const min = options.min !== undefined ? ` min="${esc(options.min)}"` : '';
  const max = options.max !== undefined ? ` max="${esc(options.max)}"` : '';
  const step = options.step !== undefined ? ` step="${esc(options.step)}"` : '';
  const placeholder = options.placeholder ? ` placeholder="${esc(options.placeholder)}"` : '';
  const list = options.list ? ` list="${esc(options.list)}"` : '';
  const ro = options.readonly ? ' readonly' : '';
  const number = options.number ? ' data-model-number="1"' : '';
  const integer = options.integer ? ' data-model-integer="1"' : '';
  return `
    <label class="llai-form-field">
      <span>${esc(label)}</span>
      <input type="${esc(type)}" ${path ? `data-model-path="${esc(path)}"` : ''} value="${esc(displayValue(value, ''))}"${min}${max}${step}${placeholder}${list}${ro}${number}${integer}>
    </label>`;
}

function customSelectMarkup(inputAttrs, value, values, placeholder = 'Choose…') {
  const current = values.find(([v]) => String(v) === String(value ?? ''));
  const currentLabel = current ? current[1] : placeholder;
  return `
    <div class="llai-custom-select" data-llai-select>
      <input type="hidden" ${inputAttrs} value="${esc(value ?? '')}">
      <button type="button" class="llai-custom-select-button" data-llai-select-toggle aria-haspopup="listbox" aria-expanded="false">
        <span data-llai-select-label>${esc(currentLabel)}</span>
        <svg viewBox="0 0 12 12" aria-hidden="true"><path d="m3 4.5 3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"/></svg>
      </button>
      <div class="llai-custom-select-menu" data-llai-select-menu hidden role="listbox">
        ${values.map(([v,text]) => `<button type="button" class="llai-custom-select-option${String(v) === String(value ?? '') ? ' selected' : ''}" data-llai-select-option="${esc(v)}" role="option" aria-selected="${String(v) === String(value ?? '') ? 'true' : 'false'}">${esc(text)}</button>`).join('')}
      </div>
    </div>`;
}

function modelSelect(label, path, value, values) {
  return `
    <label class="llai-form-field">
      <span>${esc(label)}</span>
      ${customSelectMarkup(`data-model-path="${esc(path)}"`, value, values)}
    </label>`;
}

function modelCheckbox(label, path, value) {
  return `
    <label class="llai-check-field">
      <input type="checkbox" data-model-path="${esc(path)}"${checked(!!value)}>
      <span>${esc(label)}</span>
    </label>`;
}

function modelExtraParametersText(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return '';
  return Object.keys(value).sort((a,b)=>a.localeCompare(b)).map(key => `${key} = ${String(value[key] ?? '')}`).join('\n');
}

function modelExtraParametersField(value) {
  return `
    <label class="llai-form-field llai-form-field-wide">
      <span>Additional llama.cpp parameters</span>
      <textarea data-model-extra-parameters="1" spellcheck="false" placeholder="One parameter per line, without --\ne.g. batch-size = 1024\nubatch-size = 512">${esc(modelExtraParametersText(value))}</textarea>
      <small class="llai-form-help">Dedicated fields above take precedence and cannot be repeated here.</small>
    </label>`;
}

function artifactProfiles(catalog, artifactId) {
  const profiles = Array.isArray(catalog?.profiles) ? catalog.profiles : [];
  return profiles.filter(p => p?.artifact_id === artifactId);
}

function modelIdentityHaystack(profile, artifact) {
  const files = artifact?.artifact || {};
  return `${profileName(profile)} ${artifact?.name_hint || ''} ${files.model || files.directory || ''}`.toLowerCase();
}

function suggestedPresetKeys(profile, artifact) {
  const hay = modelIdentityHaystack(profile, artifact);
  if (/qwen[._ -]?3[._ -]?8/.test(hay)) return ['qwen38-thinking'];
  if (/qwen[._ -]?3[._ -]?[56]/.test(hay)) return ['qwen35-36-thinking'];
  if (/qwen[._ -]?3/.test(hay)) return ['qwen3-thinking'];
  if (/gemma[._ -]?4/.test(hay)) return ['gemma4'];
  if (/gemma[._ -]?3/.test(hay)) return ['gemma3'];
  if (/gpt[._ -]?oss/.test(hay)) return ['gpt-oss'];
  if (/nemotron[._ -]?3/.test(hay) && /super/.test(hay)) return ['nemotron3-super'];
  if (/nemotron[._ -]?3/.test(hay) && /nano/.test(hay)) return ['nemotron3-nano-reasoning','nemotron3-nano-tools'];
  if (/nemotron[._ -]?3/.test(hay)) return ['nemotron3-super','nemotron3-nano-reasoning','nemotron3-nano-tools'];
  if (/muse[._ -]?glimmer/.test(hay)) return ['muse-glimmer'];
  if (/deepseek[._ -]?v4/.test(hay)) return ['deepseek-v4'];
  return [];
}

function modelPresetControl(profile, artifact) {
  const suggested = suggestedPresetKeys(profile, artifact);
  const suggestedSet = new Set(suggested);
  const entries = Object.entries(MODEL_RECOMMENDED_PRESETS);
  // Matching families are placed first, but the labels stay clean. We never
  // inject a "Suggested" pseudo-name into a manufacturer preset.
  entries.sort(([a],[b]) => Number(suggestedSet.has(b)) - Number(suggestedSet.has(a)));
  const selected = suggested.length === 1 ? suggested[0] : '';
  const options = [['', 'Choose preset…'], ...entries.map(([key, preset]) => [key, preset.label])];
  const hint = selected
    ? 'Matching model family detected. Click Apply to use these values.'
    : 'Optional manufacturer-oriented generation defaults.';
  return `
    <div class="llai-model-preset-row llai-form-field-wide">
      <label class="llai-form-field">
        <span>Recommended preset</span>
        ${customSelectMarkup('data-model-preset', selected, options, 'Choose preset…')}
      </label>
      <button type="button" class="llai-button" data-model-apply-preset>Apply</button>
      <small class="llai-form-help">${esc(hint)}</small>
    </div>`;
}

function profileName(profile) {
  return String(profile?.name || profile?.api_name || profile?.display_name || '').trim();
}

function makeApiNameClient(value) {
  let out = String(value || '').trim().replace(/[^A-Za-z0-9._:-]+/g, '-').replace(/^-+|-+$/g, '');
  return out || 'local-model';
}

function artifactCapability(artifact) {
  const caps = Array.isArray(artifact?.capabilities) ? artifact.capabilities : [];
  return String(caps[0] || artifact?.capability || '').trim().toLowerCase();
}

function capabilityLabel(capability) {
  const cap = String(capability || '').toLowerCase();
  if (cap === 'embedding') return 'Embedding';
  if (cap === 'reranker') return 'Reranker';
  return '';
}

function fallbackCapabilityRuntime(artifact) {
  if (artifact?.engine !== 'llamacpp') return {};
  const cap = artifactCapability(artifact);
  const base = {n_gpu_layers:'auto', flash_attn:'auto', load_on_startup:false};
  if (cap === 'embedding') return {ctx_size:32768,batch_size:2048,ubatch_size:2048,embedding:true,pooling:'last',...base};
  if (cap === 'reranker') return {ctx_size:32768,batch_size:2048,ubatch_size:2048,embedding:true,reranking:true,pooling:'rank',...base};
  return {ctx_size:16184,...base};
}

function defaultNewProfile(artifact, catalog) {
  const files = artifact?.artifact || {};
  const baseDisplay = artifact?.name_hint || files.model || files.directory || 'Local model';
  const profiles = Array.isArray(catalog?.profiles) ? catalog.profiles : [];
  const used = new Set(profiles.map(p => profileName(p).toLowerCase()).filter(Boolean));
  const baseName = makeApiNameClient(baseDisplay);
  let name = baseName;
  let n = 2;
  while (used.has(name.toLowerCase())) name = `${baseName}-${n++}`;
  return {
    id:'', artifact_id:artifact.id,
    name,
    selected_mmproj:files.auto_mmproj || '',
    runtime: artifact.engine === 'llamacpp'
      ? JSON.parse(JSON.stringify(artifact.recommended_runtime || fallbackCapabilityRuntime(artifact)))
      : {},
    generation_defaults:{},
  };
}

function renderProfileEditor(profile, artifact, isNew = false) {
  if (!profile || !artifact) return '';
  const filesObj = artifact.artifact || {};
  const runtime = profile.runtime || {};
  const gen = profile.generation_defaults || {};
  const isLlama = artifact.engine === 'llamacpp';
  const datalistId = `llai-mmproj-${String(profile.id || artifact.id || '').replace(/[^a-z0-9_-]/gi, '')}`;
  const candidates = Array.isArray(filesObj.mmproj_candidates) ? filesObj.mmproj_candidates : [];
  const files = isLlama ? [
    modelField('GGUF model', '', filesObj.model, {readonly:true}),
    modelField('mmproj', 'selected_mmproj', profile.selected_mmproj || '', {placeholder:'None', list:datalistId}),
    `<datalist id="${esc(datalistId)}">${candidates.map(v=>`<option value="${esc(v)}"></option>`).join('')}</datalist>`,
  ].join('') : modelField('Model directory', '', filesObj.directory, {readonly:true});
  const cap = artifactCapability(artifact);
  const runtimeFields = isLlama ? [
    modelField('Context size', 'runtime.ctx_size', runtime.ctx_size ?? (isNew ? (artifact.recommended_runtime?.ctx_size ?? 16184) : ''), {type:'number', min:0, integer:true, placeholder:'Engine default'}),
    modelField('Batch size', 'runtime.batch_size', runtime.batch_size ?? '', {type:'number', min:1, integer:true, placeholder:'Engine default'}),
    modelField('uBatch size', 'runtime.ubatch_size', runtime.ubatch_size ?? '', {type:'number', min:1, integer:true, placeholder:'Engine default'}),
    modelCheckbox('Embedding mode', 'runtime.embedding', runtime.embedding),
    modelCheckbox('Reranking mode', 'runtime.reranking', runtime.reranking),
    modelSelect('Pooling', 'runtime.pooling', runtime.pooling || '', [['','Engine default'],['none','None'],['mean','Mean'],['cls','CLS'],['last','Last'],['rank','Rank']]),
    modelField('GPU layers', 'runtime.n_gpu_layers', runtime.n_gpu_layers ?? 'auto', {placeholder:'auto, all or number'}),
    modelSelect('Flash Attention', 'runtime.flash_attn', runtime.flash_attn || 'auto', [['auto','Auto'],['on','On'],['off','Off']]),
    modelSelect('KV cache K', 'runtime.cache_type_k', runtime.cache_type_k || '', LLAMA_CACHE_TYPES),
    modelSelect('KV cache V', 'runtime.cache_type_v', runtime.cache_type_v || '', LLAMA_CACHE_TYPES),
    modelCheckbox('Load on runtime startup', 'runtime.load_on_startup', runtime.load_on_startup),
    cap === 'embedding' || cap === 'reranker'
      ? `<div class="llai-form-help llai-form-field-wide">LocalLight retrieval defaults: ctx 32768 · batch 2048 · uBatch 2048${cap === 'embedding' ? ' · embedding · pooling last' : ' · embedding + reranking · pooling rank'}. These are editable and are not reapplied after the profile is saved.</div>`
      : '',
  ].join('') : '';
  const generation = [
    modelPresetControl(profile, artifact),
    modelField('Temperature', 'generation_defaults.temperature', gen.temperature ?? '', {type:'number', min:0, max:10, step:'0.01', number:true, placeholder:'Engine default'}),
    modelField('Top K', 'generation_defaults.top_k', gen.top_k ?? '', {type:'number', min:0, integer:true, placeholder:'Engine default'}),
    modelField('Top P', 'generation_defaults.top_p', gen.top_p ?? '', {type:'number', min:0, max:1, step:'0.01', number:true, placeholder:'Engine default'}),
    modelField('Min P', 'generation_defaults.min_p', gen.min_p ?? '', {type:'number', min:0, max:1, step:'0.01', number:true, placeholder:'Engine default'}),
    modelField('Presence penalty', 'generation_defaults.presence_penalty', gen.presence_penalty ?? '', {type:'number', min:-2, max:2, step:'0.05', number:true, placeholder:'Engine default'}),
    modelField('Repeat penalty', 'generation_defaults.repeat_penalty', gen.repeat_penalty ?? '', {type:'number', min:0, max:10, step:'0.01', number:true, placeholder:'Engine default'}),
  ].join('');
  const path = filesObj.model || filesObj.directory || '';
  return `
    <form class="llai-model-editor llai-managed-form" data-profile-editor="${esc(profile.id || '')}" data-artifact-id="${esc(artifact.id)}" data-new-profile="${isNew ? '1' : '0'}">
      <div class="llai-model-editor-head">
        <div><h3>${isNew ? 'Add profile' : 'Configure profile'}</h3><p>${esc(artifact.engine === 'llamacpp' ? 'llama.cpp · GGUF' : 'MLX')}${capabilityLabel(cap) ? ` · ${esc(capabilityLabel(cap))}` : ''} · one artifact may have multiple profiles</p></div>
        <span class="llai-model-status ${esc(artifact.status || 'detected')}">${esc(artifact.status || 'detected')}</span>
      </div>
      ${formSection('General', `
        ${modelField('Model name', 'name', profileName(profile))}
        <div class="llai-form-help llai-form-field-wide">Used both in LocalLight and as the API / llama.cpp preset name.</div>
      `)}
      ${formSection('Files', files)}
      ${runtimeFields ? formSection('Runtime', runtimeFields) : ''}
      ${isLlama ? formSection('Advanced runtime', modelExtraParametersField(runtime.extra_parameters), true) : ''}
      ${formSection('Generation defaults', generation)}
      <div class="llai-config-footer">
        <div class="llai-model-editor-actions">
          <button type="button" class="llai-button llai-primary" data-profile-save="${esc(profile.id || '')}" data-artifact-id="${esc(artifact.id)}">${isNew ? 'Add profile' : 'Save profile'}</button>
          <button type="button" class="llai-button" data-profile-cancel>Cancel</button>
        </div>
        <div class="llai-config-source"><span>${esc(artifact.engine)}</span><code>${esc(path)}</code></div>
      </div>
    </form>`;
}

function renderProfileRow(profile, artifact) {
  const runtime = profile?.runtime || {};
  const ctx = runtime.ctx_size === undefined || runtime.ctx_size === null ? 'engine ctx' : `${runtime.ctx_size} ctx`;
  const mm = profile?.selected_mmproj ? ' · mmproj' : '';
  return `
    <div class="llai-profile-row">
      <div class="llai-profile-main">
        <strong>${esc(profileName(profile) || 'Profile')}</strong>
        <span>${esc(ctx)}${mm}</span>
      </div>
      <div class="llai-profile-actions">
        <button type="button" class="llai-button" data-profile-open="${esc(profile.id)}">Configure</button>
        <button type="button" class="llai-button" data-profile-duplicate="${esc(profile.id)}">Duplicate</button>
        <button type="button" class="llai-button" data-profile-remove="${esc(profile.id)}">Remove</button>
      </div>
    </div>`;
}

function renderArtifactCard(artifact, catalog, deleteConfirmId = '', deleteBusyId = '') {
  const filesObj = artifact?.artifact || {};
  const status = String(artifact?.status || 'detected');
  const isLlama = artifact?.engine === 'llamacpp';
  const shardCount = Array.isArray(filesObj.shards) ? filesObj.shards.length : 0;
  const profiles = artifactProfiles(catalog, artifact.id);
  const mmprojCandidates = isLlama && Array.isArray(filesObj.mmproj_candidates)
    ? [...new Set(filesObj.mmproj_candidates.filter(Boolean).map(String))]
    : [];
  const cap = artifactCapability(artifact);
  const details = [isLlama ? 'GGUF artifact' : 'MLX artifact', capabilityLabel(cap), formatBytes(artifact?.size_bytes), `${profiles.length} profile${profiles.length === 1 ? '' : 's'}`].filter(Boolean);
  if (isLlama && shardCount > 1) details.splice(1, 0, `${shardCount} shards`);
  if (mmprojCandidates.length) details.push(`${mmprojCandidates.length} mmproj candidate${mmprojCandidates.length === 1 ? '' : 's'}`);
  const path = filesObj.model || filesObj.directory || '';
  const confirmingDelete = deleteConfirmId === artifact.id;
  const deleting = deleteBusyId === artifact.id;
  let artifactActions = '';

  if (deleting) {
    artifactActions = `<div class="llai-artifact-delete-confirm llai-artifact-delete-busy"><strong>Deleting from disk…</strong><span>Removing the selected GGUF files and updating the model catalog.</span></div>`;
  } else if (confirmingDelete) {
    const projectorNames = mmprojCandidates.map(p => p.split('/').pop() || p);
    artifactActions = `
      <div class="llai-artifact-delete-confirm">
        <strong>Permanently delete this model?</strong>
        <span>${shardCount > 1 ? `${shardCount} GGUF shards` : 'The GGUF file'} and ${profiles.length ? `${profiles.length} runtime profile${profiles.length === 1 ? '' : 's'}` : 'the catalog entry'} will be removed.</span>
        ${mmprojCandidates.length ? `
          <label class="llai-artifact-delete-projectors">
            <input type="checkbox" data-artifact-delete-projectors="${esc(artifact.id)}">
            <span>Also delete ${mmprojCandidates.length} associated projector file${mmprojCandidates.length === 1 ? '' : 's'}</span>
          </label>
          <div class="llai-artifact-delete-projector-list" title="${esc(mmprojCandidates.join('\n'))}">${projectorNames.slice(0, 3).map(esc).join(' · ')}${projectorNames.length > 3 ? ` · +${projectorNames.length - 3} more` : ''}</div>` : ''}
        <div class="llai-artifact-delete-actions">
          <button type="button" class="llai-button llai-danger" data-artifact-delete-confirm="${esc(artifact.id)}">Delete from disk</button>
          <button type="button" class="llai-button" data-artifact-delete-cancel="${esc(artifact.id)}">Cancel</button>
        </div>
        <span class="llai-artifact-delete-warning">This cannot be undone.</span>
      </div>`;
  } else {
    if (status !== 'ignored') artifactActions += `<button type="button" class="llai-button llai-primary llai-model-add" data-profile-add="${esc(artifact.id)}">+ Add profile</button>`;
    if (isLlama && status !== 'ignored' && status !== 'missing') {
      artifactActions += `<button type="button" class="llai-button llai-danger" data-artifact-delete-files="${esc(artifact.id)}">Delete GGUF…</button>`;
    }
    if (!profiles.length && (status === 'detected' || status === 'missing')) {
      artifactActions += `<button type="button" class="llai-button" data-artifact-ignore="${esc(artifact.id)}">Ignore</button>`;
      if (status === 'missing') artifactActions += `<button type="button" class="llai-button" data-artifact-remove="${esc(artifact.id)}">Remove from catalog</button>`;
    }
  }
  return `
    <article class="llai-model-card llai-artifact-card" data-artifact-card="${esc(artifact.id)}">
      <div class="llai-model-card-main">
        <div class="llai-model-card-title-row"><h3>${esc(artifact?.name_hint || path || 'Local artifact')}</h3><span class="llai-model-status ${esc(status)}">${esc(status)}</span></div>
        <div class="llai-model-meta-line">${details.map(esc).join(' · ')}</div>
        <code class="llai-model-path" title="${esc(path)}">${esc(path)}</code>
        <div class="llai-profile-list">${profiles.length ? profiles.map(p=>renderProfileRow(p, artifact)).join('') : '<div class="llai-profile-empty">No runtime profiles yet.</div>'}</div>
      </div>
      <div class="llai-model-actions llai-artifact-actions">${artifactActions}</div>
    </article>`;
}

function parseModelExtraParameters(text) {
  const out = {};
  const lines = String(text || '').split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i].trim();
    if (!raw || raw.startsWith('#') || raw.startsWith(';')) continue;
    const pos = raw.indexOf('=');
    if (pos <= 0) throw new Error(`Additional runtime parameters: line ${i + 1} must use name = value.`);
    const key = raw.slice(0, pos).trim();
    const value = raw.slice(pos + 1).trim();
    if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(key)) throw new Error(`Additional runtime parameters: invalid name on line ${i + 1}.`);
    if (!value) throw new Error(`Additional runtime parameters: empty value on line ${i + 1}.`);
    if (Object.prototype.hasOwnProperty.call(out, key)) throw new Error(`Additional runtime parameters: duplicate parameter ${key}.`);
    out[key] = value;
  }
  return out;
}

function collectModelForm(form) {
  const out = {};
  for (const el of form.querySelectorAll('[data-model-path]')) {
    let value;
    if (el.type === 'checkbox') value = !!el.checked;
    else if (el.dataset.modelNumber === '1' || el.dataset.modelInteger === '1') {
      const raw = String(el.value || '').trim();
      value = raw === '' ? null : (el.dataset.modelInteger === '1' ? Number.parseInt(raw, 10) : Number(raw));
    } else value = el.value;
    setNested(out, el.dataset.modelPath, value);
  }
  const extra = form.querySelector('[data-model-extra-parameters]');
  if (extra) setNested(out, 'runtime.extra_parameters', parseModelExtraParameters(extra.value));
  return out;
}

function enhanceLocalNumberInputs(root) {
  if (!root) return;
  for (const input of root.querySelectorAll('.llai-managed-form input[type="number"]')) {
    if (input.dataset.llcNumberEnhanced === '1') continue;
    input.dataset.llcNumberEnhanced = '1';
    const wrap = document.createElement('div');
    wrap.className = 'llc-number-input-wrap';
    input.parentNode?.insertBefore(wrap, input);
    wrap.appendChild(input);
    const stepper = document.createElement('div');
    stepper.className = 'llc-number-stepper';
    stepper.innerHTML = `
      <button class="llc-number-step-btn" type="button" data-dir="up" tabindex="-1" aria-label="Increase value">
        <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M3 7.5 6 4.5l3 3" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"/></svg>
      </button>
      <button class="llc-number-step-btn" type="button" data-dir="down" tabindex="-1" aria-label="Decrease value">
        <svg viewBox="0 0 12 12" aria-hidden="true"><path d="m3 4.5 3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"/></svg>
      </button>`;
    wrap.appendChild(stepper);
    stepper.addEventListener('click', event => {
      const btn = event.target.closest('.llc-number-step-btn');
      if (!btn || input.disabled) return;
      event.preventDefault();
      try {
        if (btn.dataset.dir === 'up') input.stepUp();
        else input.stepDown();
      } catch (_) {
        const step = Number(input.step || 1) || 1;
        const current = Number(input.value || 0) || 0;
        input.value = String(current + (btn.dataset.dir === 'up' ? step : -step));
      }
      input.dispatchEvent(new Event('input', {bubbles:true}));
      input.dispatchEvent(new Event('change', {bubbles:true}));
    });
  }
}

function applyRecommendedPreset(form) {
  const select = form?.querySelector('[data-model-preset]');
  const preset = select ? MODEL_RECOMMENDED_PRESETS[select.value] : null;
  if (!preset) return false;
  for (const [key, value] of Object.entries(preset.values || {})) {
    const input = form.querySelector(`[data-model-path="generation_defaults.${key}"]`);
    if (!input) continue;
    input.value = String(value);
    input.dispatchEvent(new Event('input', {bubbles:true}));
    input.dispatchEvent(new Event('change', {bubbles:true}));
  }
  return true;
}

function renderRetrievalForm(managed) {
  const cfg = managed?.config || {};
  const hasInboundAuth = cfg.auth_enabled !== undefined || cfg.auth_bearer_token !== undefined;
  const source = managed?.source || 'ragd/ragd.conf';
  const path = managed?.path || source;
  const state = managedConfigState(managed);
  const error = managed?.error ? `<div class="llai-config-error">${esc(managed.error)}</div>` : '';
  if (!managed?.readable) {
    return `<div class="llai-config-file-state"><span>${esc(source)}</span><strong>${esc(state)}</strong><code title="${esc(path)}">${esc(path)}</code></div>${error}`;
  }

  const service = [
    field('Listen address', 'listen', cfg.listen),
    field('Port', 'port', cfg.port, {type:'number', min:1, max:65535}),
    field('Database', 'db', cfg.db),
  ].join('');
  const embedding = [
    field('Inference / embedding URL', 'llama_url', cfg.llama_url),
    field('Embedding model', 'embedding_model', cfg.embedding_model),
    field('Embedding batch', 'embedding_batch', cfg.embedding_batch, {type:'number', min:1}),
    secretField('Inference API key', 'llama_api_key', cfg.llama_api_key, 'clear_llama_api_key'),
  ].join('');
  const chunking = [
    field('Target chunk chars', 'chunk_chars', cfg.chunk_chars, {type:'number', min:1}),
    field('Maximum chunk chars', 'chunk_max_chars', cfg.chunk_max_chars, {type:'number', min:1}),
    field('Chunk overlap', 'chunk_overlap', cfg.chunk_overlap, {type:'number', min:0}),
  ].join('');
  const retrieval = [
    field('Default Top K', 'default_top_k', cfg.default_top_k, {type:'number', min:1}),
    field('Maximum Top K', 'max_top_k', cfg.max_top_k, {type:'number', min:1}),
    field('Hybrid dense K', 'hybrid_dense_k', cfg.hybrid_dense_k, {type:'number', min:1}),
    field('Hybrid BM25 K', 'hybrid_bm25_k', cfg.hybrid_bm25_k, {type:'number', min:1}),
    field('Hybrid RRF K', 'hybrid_rrf_k', cfg.hybrid_rrf_k, {type:'number', min:1}),
  ].join('');
  const reranker = [
    checkboxField('Enable reranker', 'reranker_enabled', cfg.reranker_enabled),
    field('Reranker URL', 'reranker_url', cfg.reranker_url),
    field('Reranker model', 'reranker_model', cfg.reranker_model),
    ...(cfg.reranker_max_bytes !== undefined ? [field('Reranker max bytes', 'reranker_max_bytes', cfg.reranker_max_bytes, {type:'number', min:0})] : []),
    secretField('Reranker API key', 'reranker_api_key', cfg.reranker_api_key, 'clear_reranker_api_key'),
  ].join('');
  const inbound = hasInboundAuth ? formSection('API authentication', [
    checkboxField('Require bearer authentication', 'auth_enabled', cfg.auth_enabled),
    secretField('Bearer token', 'auth_bearer_token', cfg.auth_bearer_token, 'clear_auth_bearer_token'),
  ].join('')) : '';

  return `
    <form class="llai-managed-form" data-managed-form="retrieval">
      ${formSection('Service', service)}
      ${formSection('Embedding', embedding)}
      ${formSection('Chunking', chunking)}
      ${formSection('Retrieval defaults & limits', retrieval)}
      ${formSection('Reranker', reranker)}
      ${inbound}
      <div class="llai-config-footer">
        <button type="button" class="llai-button llai-primary" data-config-save="retrieval">Save configuration</button>
        <div class="llai-config-source"><span>${esc(source)}</span><code title="${esc(path)}">${esc(path)}</code></div>
      </div>
    </form>`;
}

function renderMcpForm(managed) {
  const cfg = managed?.config || {};
  const source = managed?.source || 'mcp/server/mcp-server.json';
  const path = managed?.path || source;
  const state = managedConfigState(managed);
  const error = managed?.error ? `<div class="llai-config-error">${esc(managed.error)}</div>` : '';
  if (!managed?.readable) {
    return `<div class="llai-config-file-state"><span>${esc(source)}</span><strong>${esc(state)}</strong><code title="${esc(path)}">${esc(path)}</code></div>${error}`;
  }

  const server = cfg.server || {};
  const auth = cfg.authentication || {};
  const cors = cfg.cors || {};
  const fs = cfg.filesystem || {};
  const proc = cfg.processes || {};
  const terminal = cfg.terminal || {};
  const desktop = cfg.desktop || {};
  const features = desktop.features || {};
  const logging = cfg.logging || {};

  const serverFields = [
    field('Bind address', 'server.address', server.address),
    field('Port', 'server.port', server.port, {type:'number', min:1, max:65535}),
    field('HTTP endpoint', 'server.endpoint', server.endpoint),
    field('Maximum request bytes', 'server.maximum_request_bytes', server.maximum_request_bytes, {type:'number', min:1}),
  ].join('');
  const security = [
    secretField('Bearer token', 'authentication.bearer_token', auth.bearer_token, 'authentication.clear_bearer_token'),
    checkboxField('Enable CORS', 'cors.enabled', cors.enabled),
    textareaField('Allowed origins', 'cors.allowed_origins', cors.allowed_origins || [], true),
  ].join('');
  const filesystem = [
    checkboxField('Enable filesystem tools', 'filesystem.enabled', fs.enabled),
    field('Workspace root', 'filesystem.workspace_root', fs.workspace_root),
    checkboxField('Allow delete', 'filesystem.allow_delete', fs.allow_delete),
  ].join('');
  const processPermissions = [
    checkboxField('Enable process tools', 'processes.enabled', proc.enabled),
    checkboxField('Execute programs', 'processes.allow_process_exec', proc.allow_process_exec),
    checkboxField('Execute shell commands', 'processes.allow_shell_exec', proc.allow_shell_exec),
    checkboxField('Start programs', 'processes.allow_process_start', proc.allow_process_start),
    checkboxField('Start shell processes', 'processes.allow_shell_start', proc.allow_shell_start),
    checkboxField('Detach from terminal', 'processes.detach_from_terminal', proc.detach_from_terminal),
    checkboxField('Mirror output to console', 'processes.mirror_output_to_console', proc.mirror_output_to_console),
    selectField('Console output mode', 'processes.console_output_mode', proc.console_output_mode || 'prefixed', ['prefixed','raw']),
  ].join('');
  const processLimits = [
    field('Default runtime limit (ms)', 'processes.default_timeout_ms', proc.default_timeout_ms, {type:'number', min:0}),
    field('Maximum runtime limit (ms)', 'processes.maximum_timeout_ms', proc.maximum_timeout_ms, {type:'number', min:0}),
    field('Default wait (ms)', 'processes.default_wait_ms', proc.default_wait_ms, {type:'number', min:0}),
    field('Maximum wait (ms)', 'processes.maximum_wait_ms', proc.maximum_wait_ms, {type:'number', min:1}),
    field('Maximum tracked jobs', 'processes.maximum_tracked_jobs', proc.maximum_tracked_jobs, {type:'number', min:8}),
    field('Default idle timeout (ms)', 'processes.default_idle_timeout_ms', proc.default_idle_timeout_ms, {type:'number', min:0}),
    field('Maximum idle timeout (ms)', 'processes.maximum_idle_timeout_ms', proc.maximum_idle_timeout_ms, {type:'number', min:0}),
    field('Termination grace (ms)', 'processes.termination_grace_ms', proc.termination_grace_ms, {type:'number', min:0}),
    field('Maximum output bytes', 'processes.maximum_output_bytes', proc.maximum_output_bytes, {type:'number', min:1}),
    field('Default returned chars', 'processes.max_output_chars', proc.max_output_chars, {type:'number', min:0, max:100000}),
    checkboxField('Detect interactive prompt loops', 'processes.detect_interactive_prompt_loops', proc.detect_interactive_prompt_loops),
    field('Prompt repetition limit', 'processes.interactive_prompt_repeat_limit', proc.interactive_prompt_repeat_limit, {type:'number', min:3}),
    field('Prompt detection window (ms)', 'processes.interactive_prompt_window_ms', proc.interactive_prompt_window_ms, {type:'number', min:100}),
    field('Maximum prompt chars', 'processes.interactive_prompt_max_chars', proc.interactive_prompt_max_chars, {type:'number', min:4, max:1024}),
  ].join('');
  const terminalFields = [
    checkboxField('Enable interactive terminal tools', 'terminal.enabled', terminal.enabled),
    field('Maximum sessions', 'terminal.maximum_sessions', terminal.maximum_sessions, {type:'number', min:1}),
    field('Maximum output bytes', 'terminal.maximum_output_bytes', terminal.maximum_output_bytes, {type:'number', min:4096}),
    field('Maximum read bytes', 'terminal.maximum_read_bytes', terminal.maximum_read_bytes, {type:'number', min:1}),
    field('Maximum observation bytes', 'terminal.maximum_observation_bytes', terminal.maximum_observation_bytes, {type:'number', min:1}),
    field('Observation quiet (ms)', 'terminal.observation_quiet_ms', terminal.observation_quiet_ms, {type:'number', min:0}),
    field('Observation default wait (ms)', 'terminal.observation_default_wait_ms', terminal.observation_default_wait_ms, {type:'number', min:0}),
    field('Maximum scrollback lines', 'terminal.maximum_scrollback_lines', terminal.maximum_scrollback_lines, {type:'number', min:1}),
    field('Maximum write bytes', 'terminal.maximum_write_bytes', terminal.maximum_write_bytes, {type:'number', min:1}),
    field('Default columns', 'terminal.default_columns', terminal.default_columns, {type:'number', min:1, max:32767}),
    field('Default rows', 'terminal.default_rows', terminal.default_rows, {type:'number', min:1, max:32767}),
    field('Maximum read wait (ms)', 'terminal.maximum_read_wait_ms', terminal.maximum_read_wait_ms, {type:'number', min:1}),
    field('Termination grace (ms)', 'terminal.termination_grace_ms', terminal.termination_grace_ms, {type:'number', min:0}),
    checkboxField('Log terminal output', 'terminal.log_output', terminal.log_output),
    checkboxField('Log terminal input', 'terminal.log_input', terminal.log_input),
    checkboxField('Mirror output to console', 'terminal.mirror_output_to_console', terminal.mirror_output_to_console),
    checkboxField('Mirror input to console', 'terminal.mirror_input_to_console', terminal.mirror_input_to_console),
    selectField('Console output mode', 'terminal.console_output_mode', terminal.console_output_mode || 'prefixed', ['prefixed','raw']),
  ].join('');
  const desktopFields = [
    checkboxField('Enable desktop primitives', 'desktop.enabled', desktop.enabled),
    checkboxField('Window management', 'desktop.features.window_management', features.window_management),
    checkboxField('Screen capture', 'desktop.features.screen_capture', features.screen_capture),
    checkboxField('Keyboard input', 'desktop.features.input', features.input),
    field('Maximum image bytes', 'desktop.maximum_image_bytes', desktop.maximum_image_bytes, {type:'number', min:32768}),
  ].join('');
  const loggingFields = [
    field('Log file', 'logging.file', logging.file),
    checkboxField('Log process commands', 'logging.log_process_commands', logging.log_process_commands),
    checkboxField('Log process output', 'logging.log_process_output', logging.log_process_output),
  ].join('');

  return `
    <form class="llai-managed-form" data-managed-form="mcp">
      ${formSection('Server', serverFields)}
      ${formSection('Security & CORS', security)}
      ${formSection('Filesystem', filesystem)}
      ${formSection('Process permissions', processPermissions)}
      ${formSection('Desktop', desktopFields)}
      ${formSection('Process limits', processLimits, true)}
      ${formSection('Interactive terminal', terminalFields, true)}
      ${formSection('Logging', loggingFields, true)}
      <div class="llai-config-footer">
        <button type="button" class="llai-button llai-primary" data-config-save="mcp">Save configuration</button>
        <div class="llai-config-source"><span>${esc(source)}</span><code title="${esc(path)}">${esc(path)}</code></div>
      </div>
    </form>`;
}

function renderManagedConfig(kind, managed, root) {
  if (!root) return;
  root.innerHTML = kind === 'retrieval' ? renderRetrievalForm(managed) : renderMcpForm(managed);
  enhanceLocalNumberInputs(root);
}

function setNested(target, path, value) {
  const parts = String(path || '').split('.').filter(Boolean);
  if (!parts.length) return;
  let cur = target;
  for (let i = 0; i < parts.length - 1; i++) {
    const key = parts[i];
    if (!cur[key] || typeof cur[key] !== 'object' || Array.isArray(cur[key])) cur[key] = {};
    cur = cur[key];
  }
  cur[parts[parts.length - 1]] = value;
}

function collectManagedForm(form) {
  const out = {};
  for (const el of form.querySelectorAll('[data-config-path]')) {
    let value;
    if (el.type === 'checkbox') value = !!el.checked;
    else if (el.dataset.lines === '1') value = String(el.value || '').split(/\r?\n/).map(v => v.trim()).filter(Boolean);
    else value = el.value;
    setNested(out, el.dataset.configPath, value);
  }
  return out;
}

function renderDetailStatus(id, service) {
  const meta = SERVICE_META[id];
  if (!service) {
    return `<div class="llai-detail-status"><div><strong>${esc(meta.backend)}</strong><span>No status returned by Control.</span></div><span class="llai-service-state unknown">Unavailable</span></div>`;
  }
  const state = String(service.state || 'unknown');
  const health = service.health_state || (service.health_ready ? 'ready' : 'n/a');
  const endpoint = service.health_url || 'not configured';
  return `
    <div class="llai-detail-status">
      <div><strong>${esc(meta.backend)}</strong><span>Process ${esc(service.process_state || 'n/a')} · Health ${esc(health)} · ${esc(endpoint)}</span></div>
      <span class="llai-service-state ${serviceState(service)}">${esc(state)}</span>
    </div>`;
}

function createControlView() {
  const view = document.createElement('section');
  view.id = 'llai-control-view';
  view.className = 'llai-control-view';
  view.hidden = true;
  view.innerHTML = `
    <div class="llai-control-shell">
      <div class="llai-control-title-row">
        <div>
          <h1>Control Center</h1>
          <p>Local runtime, models and system services</p>
        </div>
        <div class="llai-overall-status unknown" id="llai-overall-status">
          <span class="llai-status-dot"></span>
          <span id="llai-overall-status-text">Not checked</span>
        </div>
      </div>

      <nav class="llai-tabs" aria-label="Control sections">
        <button type="button" class="llai-tab active" data-llai-tab="overview">Overview</button>
        <button type="button" class="llai-tab" data-llai-tab="runtime">Runtime</button>
        <button type="button" class="llai-tab" data-llai-tab="models">Models</button>
        <button type="button" class="llai-tab" data-llai-tab="retrieval">Retrieval</button>
        <button type="button" class="llai-tab" data-llai-tab="mcp">Agent</button>
        <button type="button" class="llai-tab" data-llai-tab="activity">Activity</button>
        <button type="button" class="llai-tab" data-llai-tab="system">System</button>
      </nav>

      <div class="llai-banner hidden" id="llai-banner" aria-live="polite"></div>

      <div class="llai-tab-panel" data-llai-panel="overview">
        <div class="llai-section-head">
          <div>
            <h2>Local stack</h2>
            <div class="llai-section-sub" id="llai-control-meta">Control has not been queried yet.</div>
          </div>
          <div class="llai-section-actions">
            <button type="button" class="llai-button" id="llai-refresh">Refresh</button>
            <button type="button" class="llai-button" id="llai-start-all">Start all</button>
            <button type="button" class="llai-button" id="llai-stop-all">Stop all</button>
          </div>
        </div>

        <div class="llai-overview-grid" id="llai-overview-grid"></div>

        <section class="llai-runtime-card">
          <div class="llai-runtime-title">LocalLight Control</div>
          <div class="llai-runtime-grid" id="llai-runtime-details">
            <div><span>Status</span><strong>Not checked</strong></div>
          </div>
        </section>
      </div>

      <div class="llai-tab-panel" data-llai-panel="runtime" hidden>
        <div class="llai-section-head">
          <div>
            <h2>Inference Runtime</h2>
            <div class="llai-section-sub">Active local inference backend and runtime status.</div>
          </div>
        </div>
        <div id="llai-runtime-status"></div>
      </div>

      <div class="llai-tab-panel" data-llai-panel="models" hidden>
        <div class="llai-section-head llai-model-section-head">
          <div>
            <h2>Models</h2>
            <div class="llai-section-sub">Local model catalog, direct GGUF uploads, runtime profiles and Hugging Face discovery.</div>
            <nav class="llai-model-source-tabs" aria-label="Model sources">
              <button type="button" class="llai-model-source-tab active" data-model-source="local" aria-pressed="true">Local</button>
              <button type="button" class="llai-model-source-tab" data-model-source="upload" aria-pressed="false">Upload</button>
              <button type="button" class="llai-model-source-tab" data-model-source="huggingface" aria-pressed="false">Hugging Face</button>
            </nav>
          </div>
          <div class="llai-section-actions" id="llai-model-local-actions">
            <button type="button" class="llai-button" id="llai-model-scan">Scan models</button>
            <button type="button" class="llai-button" id="llai-model-restore-ignored" hidden>Restore ignored</button>
          </div>
        </div>

        <div data-model-source-panel="local">
          <div id="llai-model-catalog-meta" class="llai-model-catalog-meta">Open this section to load the catalog. Use Scan models after adding files.</div>
          <div id="llai-model-editor-root" hidden></div>
          <div id="llai-model-list" class="llai-model-list"><div class="llai-service-empty">Model catalog has not been loaded yet.</div></div>
        </div>

        <div data-model-source-panel="upload" hidden>
          <section class="llai-upload-shell">
            <div class="llai-upload-drop" id="llai-upload-drop" tabindex="0" role="button" aria-label="Choose a GGUF file or drop it here">
              <input id="llai-upload-file" type="file" accept=".gguf,application/octet-stream" hidden>
              <div class="llai-upload-drop-icon">GGUF</div>
              <strong>Drop a GGUF file here</strong>
              <span>or choose it from this computer</span>
              <button type="button" class="llai-button" id="llai-upload-choose">Choose file</button>
            </div>

            <div class="llai-upload-card" id="llai-upload-card" hidden>
              <div class="llai-upload-file-head">
                <div>
                  <span>Selected file</span>
                  <strong id="llai-upload-file-name"></strong>
                  <small id="llai-upload-file-meta"></small>
                </div>
                <button type="button" class="llai-button" id="llai-upload-clear">Clear</button>
              </div>
              <label class="llai-upload-save-as" for="llai-upload-save-name">
                <span>Save as</span>
                <input id="llai-upload-save-name" type="text" autocomplete="off" spellcheck="false">
              </label>
              <div class="llai-upload-progress" id="llai-upload-progress" hidden>
                <div class="llai-hf-progress-track"><span id="llai-upload-progress-bar"></span></div>
                <div class="llai-upload-progress-meta">
                  <strong id="llai-upload-progress-text">0%</strong>
                  <span id="llai-upload-progress-detail"></span>
                </div>
              </div>
              <div class="llai-upload-actions">
                <button type="button" class="llai-button llai-primary" id="llai-upload-start">Upload</button>
                <button type="button" class="llai-button" id="llai-upload-resume" hidden>Resume</button>
                <button type="button" class="llai-button llai-danger" id="llai-upload-cancel" hidden>Cancel</button>
                <button type="button" class="llai-button" id="llai-upload-view-local" hidden>View in Local</button>
              </div>
              <div class="llai-upload-status" id="llai-upload-status">Ready to upload through LLC/PHP.</div>
            </div>
          </section>
          <div class="llai-upload-note">Uploads are sent in resumable chunks to LLC/PHP, which streams each chunk to loopback LocalLight Control. Completed files are stored under <code>models/uploads/</code> and scanned into Local automatically.</div>
        </div>

        <div data-model-source-panel="huggingface" hidden>
          <section class="llai-hf-auth" aria-label="Hugging Face authentication">
            <div class="llai-hf-auth-copy">
              <strong>Hugging Face access token</strong>
              <span id="llai-hf-token-status">Checking token status…</span>
            </div>
            <div class="llai-hf-auth-controls">
              <input id="llai-hf-token" type="password" autocomplete="new-password" spellcheck="false" placeholder="hf_…" aria-label="Hugging Face access token">
              <button type="button" class="llai-button" id="llai-hf-token-save">Save token</button>
              <button type="button" class="llai-button" id="llai-hf-token-clear" hidden>Clear</button>
            </div>
            <span class="llai-hf-auth-help">Stored by LocalLight Control and never returned to the browser. Used for search, repository inspection and downloads.</span>
          </section>
          <form class="llai-hf-search" id="llai-hf-search-form">
            <div class="llai-hf-search-field">
              <label for="llai-hf-query">Search Hugging Face</label>
              <div class="llai-hf-search-row">
                <input id="llai-hf-query" type="search" autocomplete="off" spellcheck="false" placeholder="Model, author or owner/repository">
                <button type="submit" class="llai-button llai-primary" id="llai-hf-search-button">Search</button>
              </div>
              <span>Searches Hugging Face repositories for GGUF models. Exact file metadata is inspected only when you open a result.</span>
            </div>
          </form>
          <div id="llai-hf-selection" class="llai-hf-selection" hidden></div>
          <div id="llai-hf-results" class="llai-hf-results">
            <div class="llai-model-empty"><strong>No Hugging Face search yet.</strong><span>Search for a model family, author, or exact repository. Quantizations are derived from the actual GGUF files, not just repository metadata.</span></div>
          </div>
        </div>
      </div>

      <div class="llai-tab-panel" data-llai-panel="retrieval" hidden>
        <div class="llai-section-head">
          <div>
            <h2>Retrieval</h2>
            <div class="llai-section-sub">RAGd server defaults, retrieval engine and model configuration.</div>
          </div>
        </div>
        <div id="llai-retrieval-status"></div>
        <div id="llai-retrieval-setup"></div>
        ${managedConfigCard('retrieval')}
      </div>

      <div class="llai-tab-panel" data-llai-panel="mcp" hidden>
        <div class="llai-section-head">
          <div>
            <h2>Agent Runtime</h2>
            <div class="llai-section-sub">Local agent execution environment, exposed over MCP.</div>
          </div>
        </div>
        <div id="llai-mcp-status"></div>
        ${managedConfigCard('mcp')}
      </div>

      ${placeholderPanel('activity')}

      <div class="llai-tab-panel" data-llai-panel="system" hidden>
        <div class="llai-section-head">
          <div>
            <h2>System</h2>
            <div class="llai-section-sub">Control, platform, paths and diagnostics.</div>
          </div>
        </div>
        <div class="llai-system-grid" id="llai-system-grid"></div>
      </div>
    </div>`;
  return view;
}

function normalizeServices(snapshot) {
  const map = {};
  for (const service of Array.isArray(snapshot?.services) ? snapshot.services : []) {
    if (service && SERVICE_META[service.id]) map[service.id] = service;
  }
  return map;
}

function serviceStatusClass(state) {
  const s = String(state || 'unknown').toLowerCase();
  return ['running', 'starting', 'stopping', 'stopped', 'error'].includes(s) ? s : 'unknown';
}

function serviceState(service) {
  return serviceStatusClass(service?.state || 'unknown');
}

function renderOverviewCard(id, service, busy = false) {
  const meta = SERVICE_META[id];
  const tab = meta.domain;
  if (!service) {
    return `
      <article class="llai-overview-card" data-service="${id}">
        <div class="llai-overview-card-head">
          <div><h3>${esc(meta.title)}</h3><p>${esc(meta.backend)}</p></div>
          <span class="llai-service-state unknown">Unavailable</span>
        </div>
        <div class="llai-overview-summary">No status returned by Control.</div>
        <div class="llai-overview-actions">
          <button type="button" class="llai-button llai-start" disabled>Start</button>
          <button type="button" class="llai-button llai-stop" disabled>Stop</button>
          <button type="button" class="llai-button" disabled>Restart</button>
          <button type="button" class="llai-overview-link" data-llai-open-tab="${tab}">Open ${esc(meta.shortTitle)}</button>
        </div>
      </article>`;
  }

  const state = String(service.state || 'unknown');
  const stateClass = serviceState(service);
  const health = service.health_state || (service.health_ready ? 'ready' : 'n/a');
  let summary = `Health: ${health}`;
  if (service.health_http_status) summary += ` · HTTP ${service.health_http_status}`;
  if (id !== 'llama' && service.pid) summary += ` · PID ${service.pid}`;
  const command = String(service.command_in_progress || '').trim();
  const actionBusy = busy || command !== '';

  return `
    <article class="llai-overview-card" data-service="${id}">
      <div class="llai-overview-card-head">
        <div><h3>${esc(meta.title)}</h3><p>${esc(meta.backend)}</p></div>
        <span class="llai-service-state ${stateClass}">${esc(state)}</span>
      </div>
      <div class="llai-overview-summary">${esc(summary)}</div>
      ${service.last_error ? `<div class="llai-overview-error">${esc(service.last_error)}</div>` : ''}
      <div class="llai-overview-actions">
        <button type="button" class="llai-button llai-start" data-service-action="start" data-service-id="${id}" ${actionBusy || stateClass === 'running' || stateClass === 'starting' ? 'disabled' : ''}>Start</button>
        <button type="button" class="llai-button llai-stop" data-service-action="stop" data-service-id="${id}" ${actionBusy || stateClass === 'stopped' || stateClass === 'stopping' ? 'disabled' : ''}>Stop</button>
        <button type="button" class="llai-button" data-service-action="restart" data-service-id="${id}" ${actionBusy ? 'disabled' : ''}>Restart</button>
        <button type="button" class="llai-overview-link" data-llai-open-tab="${tab}">Open ${esc(meta.shortTitle)}</button>
        ${command ? `<span class="llai-action-note">${esc(command)}…</span>` : ''}
      </div>
    </article>`;
}

function renderOverall(snapshot, services, statusEl, statusTextEl) {
  statusEl.className = 'llai-overall-status';
  if (!snapshot || !snapshot.reachable) {
    statusEl.classList.add('error');
    statusTextEl.textContent = 'Control unavailable';
    return;
  }
  const list = Object.values(services);
  if (!list.length) {
    statusEl.classList.add('unknown');
    statusTextEl.textContent = 'Control connected';
    return;
  }
  if (list.some(s => String(s.state) === 'error')) {
    statusEl.classList.add('error');
    statusTextEl.textContent = 'Service error';
    return;
  }
  const running = list.filter(s => String(s.state) === 'running').length;
  if (running === list.length) {
    statusEl.classList.add('running');
    statusTextEl.textContent = 'All systems operational';
  } else if (list.some(s => ['starting', 'stopping'].includes(String(s.state)))) {
    statusEl.classList.add('working');
    statusTextEl.textContent = 'Runtime changing state';
  } else {
    statusEl.classList.add('unknown');
    statusTextEl.textContent = `${running} of ${list.length} services running`;
  }
}

function renderControlSummary(snapshot, root) {
  const info = snapshot?.info || {};
  const cfg = snapshot?.config || {};
  root.innerHTML = `
    <div><span>Status</span><strong>${snapshot?.reachable ? 'Connected' : 'Unavailable'}</strong></div>
    <div><span>Version</span><strong>${esc(info.version || 'n/a')}</strong></div>
    <div><span>Platform</span><strong>${esc(info.platform || 'n/a')} / ${esc(info.cpu || 'n/a')}</strong></div>
    <div><span>Listen</span><strong>${esc(info.listen || cfg.listen || 'n/a')}:${esc(info.port || cfg.port || 'n/a')}</strong></div>
    <div><span>Polling</span><strong>${esc(cfg.status_poll_interval_ms || 'n/a')}${cfg.status_poll_interval_ms ? ' ms' : ''}</strong></div>
    <div><span>Auth</span><strong>${cfg.auth_enabled === undefined ? 'n/a' : boolText(cfg.auth_enabled)}</strong></div>`;
}

function systemCard(title, rows) {
  return `
    <section class="llai-system-card">
      <h3>${esc(title)}</h3>
      <dl class="llai-system-kv">
        ${rows.map(([key, value, path = false]) => `<dt>${esc(key)}</dt><dd${path ? ' class="llai-path"' : ''} title="${esc(displayValue(value))}">${esc(displayValue(value))}</dd>`).join('')}
      </dl>
    </section>`;
}

function renderSystem(snapshot, root) {
  if (!snapshot?.reachable) {
    root.innerHTML = `<section class="llai-system-card"><h3>LocalLight Control</h3><p class="llai-system-empty">Control is unavailable. Open Overview and refresh after the local Control process is running.</p></section>`;
    return;
  }

  const info = snapshot.info || {};
  const cfg = snapshot.config || {};
  const paths = cfg.paths || {};
  root.innerHTML = [
    systemCard('Control', [
      ['Version', info.version],
      ['Platform', `${displayValue(info.platform)} / ${displayValue(info.cpu)}`],
      ['Listen', `${displayValue(info.listen || cfg.listen)}:${displayValue(info.port || cfg.port)}`],
      ['Config file', cfg.config_file, true],
      ['Request timeout', cfg.client_request_timeout_ms ? `${cfg.client_request_timeout_ms} ms` : null],
      ['Status polling', cfg.status_poll_interval_ms ? `${cfg.status_poll_interval_ms} ms` : null],
      ['Authentication', cfg.auth_enabled === undefined ? null : boolText(cfg.auth_enabled)],
    ]),
    systemCard('Component paths', [
      ['Inference', paths.llama_server, true],
      ['RAGd', paths.ragd, true],
      ['Agent Runtime', paths.mcp_server, true],
      ['Models', paths.models_root, true],
      ['Model catalog', paths.model_catalog, true],
      ['llama presets', paths.llama_models_preset, true],
    ]),
    systemCard('Diagnostics & logs', [
      ['Debug trace', cfg.debug_enabled === undefined ? null : boolText(cfg.debug_enabled)],
      ['Debug log', cfg.debug_log_file, true],
      ['Child output', 'Not captured by Control'],
    ]),
  ].join('');
}

export function initLocalLightAI({ config, api }) {
  if (!config?.enabled || !config?.can_control || typeof api !== 'function') return;
  if (document.body.dataset.llaiInitialized === '1') return;
  document.body.dataset.llaiInitialized = '1';
  document.body.classList.add('locallightai-mode');
  loadStyles();

  const header = document.querySelector('.header');
  const main = document.querySelector('.main-content');
  const chatArea = document.querySelector('.chat-area');
  const inputSection = document.querySelector('.input-section');
  if (!header || !main || !chatArea || !inputSection) return;

  const switcher = createModeSwitch();
  const controlView = createControlView();
  const headerActions = header.querySelector('.header-actions');
  if (headerActions) header.insertBefore(switcher, headerActions);
  else header.appendChild(switcher);
  main.insertBefore(controlView, chatArea);

  const statusEl = controlView.querySelector('#llai-overall-status');
  const statusTextEl = controlView.querySelector('#llai-overall-status-text');
  const overviewGrid = controlView.querySelector('#llai-overview-grid');
  const banner = controlView.querySelector('#llai-banner');
  const meta = controlView.querySelector('#llai-control-meta');
  const runtimeDetails = controlView.querySelector('#llai-runtime-details');
  const systemGrid = controlView.querySelector('#llai-system-grid');
  const retrievalConfigRoot = controlView.querySelector('#llai-retrieval-config-content');
  const retrievalSetupRoot = controlView.querySelector('#llai-retrieval-setup');
  const mcpConfigRoot = controlView.querySelector('#llai-mcp-config-content');
  const modelListRoot = controlView.querySelector('#llai-model-list');
  const modelEditorRoot = controlView.querySelector('#llai-model-editor-root');
  const modelCatalogMeta = controlView.querySelector('#llai-model-catalog-meta');
  const modelScanBtn = controlView.querySelector('#llai-model-scan');
  const modelRestoreIgnoredBtn = controlView.querySelector('#llai-model-restore-ignored');
  const modelLocalActions = controlView.querySelector('#llai-model-local-actions');
  const uploadDrop = controlView.querySelector('#llai-upload-drop');
  const uploadFileInput = controlView.querySelector('#llai-upload-file');
  const uploadChooseBtn = controlView.querySelector('#llai-upload-choose');
  const uploadCard = controlView.querySelector('#llai-upload-card');
  const uploadFileName = controlView.querySelector('#llai-upload-file-name');
  const uploadFileMeta = controlView.querySelector('#llai-upload-file-meta');
  const uploadSaveName = controlView.querySelector('#llai-upload-save-name');
  const uploadClearBtn = controlView.querySelector('#llai-upload-clear');
  const uploadStartBtn = controlView.querySelector('#llai-upload-start');
  const uploadResumeBtn = controlView.querySelector('#llai-upload-resume');
  const uploadCancelBtn = controlView.querySelector('#llai-upload-cancel');
  const uploadViewLocalBtn = controlView.querySelector('#llai-upload-view-local');
  const uploadProgress = controlView.querySelector('#llai-upload-progress');
  const uploadProgressBar = controlView.querySelector('#llai-upload-progress-bar');
  const uploadProgressText = controlView.querySelector('#llai-upload-progress-text');
  const uploadProgressDetail = controlView.querySelector('#llai-upload-progress-detail');
  const uploadStatus = controlView.querySelector('#llai-upload-status');
  const hfSearchForm = controlView.querySelector('#llai-hf-search-form');
  const hfQueryInput = controlView.querySelector('#llai-hf-query');
  const hfSearchButton = controlView.querySelector('#llai-hf-search-button');
  const hfResultsRoot = controlView.querySelector('#llai-hf-results');
  const hfSelectionRoot = controlView.querySelector('#llai-hf-selection');
  const hfTokenInput = controlView.querySelector('#llai-hf-token');
  const hfTokenStatus = controlView.querySelector('#llai-hf-token-status');
  const hfTokenSaveBtn = controlView.querySelector('#llai-hf-token-save');
  const hfTokenClearBtn = controlView.querySelector('#llai-hf-token-clear');
  const refreshBtn = controlView.querySelector('#llai-refresh');
  const startAllBtn = controlView.querySelector('#llai-start-all');
  const stopAllBtn = controlView.querySelector('#llai-stop-all');

  const detailStatusRoots = {
    runtime: controlView.querySelector('#llai-runtime-status'),
    retrieval: controlView.querySelector('#llai-retrieval-status'),
    mcp: controlView.querySelector('#llai-mcp-status'),
  };

  const state = {
    mode: 'chat',
    tab: 'overview',
    snapshot: null,
    services: {},
    managedConfigs: null,
    modelCatalog: null,
    editingProfileId: '',
    creatingProfileArtifactId: '',
    modelsLoading: false,
    modelsScanning: false,
    modelsRestoringIgnored: false,
    artifactDeleteConfirmId: '',
    artifactDeleteBusyId: '',
    modelSource: 'local',
    uploadFile: null,
    uploadSession: null,
    uploadOffset: 0,
    uploadInflightLoaded: 0,
    uploadBusy: false,
    uploadPaused: false,
    uploadCancelled: false,
    uploadXhr: null,
    uploadStartedAt: 0,
    hfSettings: null,
    hfSettingsBusy: false,
    hfQuery: '',
    hfResults: [],
    hfSearching: false,
    hfExpandedRepoId: '',
    hfRepositoryDetails: new Map(),
    hfRepositoryLoading: new Set(),
    hfSelection: null,
    hfDownloadJob: null,
    hfDownloadPollTimer: null,
    hfDownloadStatusBusy: false,
    hfDownloadCatalogSyncedJobId: '',
    retrievalSetupBusy: false,
    retrievalSetupMessage: '',
    retrievalSetupError: '',
    retrievalSetupCurrentJobId: '',
    retrievalSetupManual: false,
    busy: new Set(),
    pollTimer: null,
    pollMs: 1000,
    refreshing: false,
  };

  function setBanner(message = '', kind = '') {
    banner.textContent = message;
    banner.className = 'llai-banner';
    if (!message) banner.classList.add('hidden');
    else if (kind) banner.classList.add(kind);
  }

  function setTab(id) {
    const tab = controlView.querySelector(`[data-llai-tab="${id}"]`);
    const panel = controlView.querySelector(`[data-llai-panel="${id}"]`);
    if (!tab || !panel) return;
    state.tab = id;
    for (const btn of controlView.querySelectorAll('[data-llai-tab]')) btn.classList.toggle('active', btn === tab);
    for (const item of controlView.querySelectorAll('[data-llai-panel]')) item.hidden = item !== panel;
    if (id === 'models' && state.modelSource === 'local' && state.modelCatalog === null && !state.modelsLoading) loadModels(false);
    if (id === 'retrieval') {
      if (state.modelCatalog === null && !state.modelsLoading) loadModels(false);
      renderRetrievalSetup();
    }
  }

  function setModelSource(source) {
    const next = source === 'huggingface' ? 'huggingface' : (source === 'upload' ? 'upload' : 'local');
    state.modelSource = next;
    for (const btn of controlView.querySelectorAll('[data-model-source]')) {
      const active = btn.dataset.modelSource === next;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-pressed', active ? 'true' : 'false');
    }
    for (const panel of controlView.querySelectorAll('[data-model-source-panel]')) {
      panel.hidden = panel.dataset.modelSourcePanel !== next;
    }
    modelLocalActions.hidden = next !== 'local';
    if (next === 'local' && state.modelCatalog === null && !state.modelsLoading) loadModels(false);
    if (next === 'huggingface') {
      if (state.hfSettings === null && !state.hfSettingsBusy) loadHFSettings(false);
      setTimeout(() => hfQueryInput?.focus(), 0);
    }
  }

  function formatCount(value) {
    const n = Number(value || 0);
    if (!Number.isFinite(n) || n <= 0) return '0';
    return new Intl.NumberFormat(undefined, {notation:'compact', maximumFractionDigits:1}).format(n);
  }

  function isProjectorUploadName(name) {
    return String(name || '').toLowerCase().includes('mmproj');
  }

  function uploadPercent(bytes, total) {
    if (!total) return 0;
    return Math.max(0, Math.min(100, bytes * 100 / total));
  }

  function renderUploadState() {
    const file = state.uploadFile;
    const session = state.uploadSession;
    const hasFile = !!file;
    uploadDrop.hidden = hasFile;
    uploadCard.hidden = !hasFile;
    if (!hasFile) return;

    const selectedName = String(file.name || 'model.gguf');
    uploadFileName.textContent = selectedName;
    const projector = isProjectorUploadName(uploadSaveName.value || selectedName);
    uploadFileMeta.textContent = `${formatBytes(file.size)} · ${projector ? 'projector detected' : 'GGUF model'}`;

    const terminal = session?.state === 'completed';
    const active = state.uploadBusy && !terminal;
    uploadSaveName.disabled = !!session || active;
    uploadClearBtn.hidden = !!session && !terminal;
    uploadStartBtn.hidden = !!session || terminal;
    uploadStartBtn.disabled = active;
    uploadResumeBtn.hidden = !state.uploadPaused || terminal;
    uploadCancelBtn.hidden = !session || terminal;
    uploadCancelBtn.disabled = state.uploadCancelled;
    uploadViewLocalBtn.hidden = !terminal;
    uploadProgress.hidden = !session;

    const confirmed = Math.max(0, Math.min(Number(file.size || 0), Number(state.uploadOffset || 0)));
    const inflight = Math.max(0, Number(state.uploadInflightLoaded || 0));
    const bytes = Math.max(0, Math.min(Number(file.size || 0), confirmed + inflight));
    const pct = uploadPercent(bytes, file.size);
    uploadProgressBar.style.width = `${pct.toFixed(2)}%`;
    uploadProgressText.textContent = `${pct.toFixed(pct >= 10 ? 1 : 2)}%`;
    const elapsed = state.uploadStartedAt ? Math.max(0.001, (performance.now() - state.uploadStartedAt) / 1000) : 0;
    const confirmedRate = elapsed > 0 ? confirmed / elapsed : 0;
    const sentText = inflight > 0 ? `${formatBytes(bytes)} sent · ${formatBytes(confirmed)} confirmed` : formatBytes(confirmed);
    uploadProgressDetail.textContent = `${sentText} / ${formatBytes(file.size)}${active && confirmedRate > 0 ? ` · ${formatBytes(confirmedRate)}/s confirmed` : ''}`;
  }

  function resetUploadSelection() {
    if (state.uploadXhr) {
      try { state.uploadXhr.abort(); } catch {}
    }
    state.uploadFile = null;
    state.uploadSession = null;
    state.uploadOffset = 0;
    state.uploadInflightLoaded = 0;
    state.uploadBusy = false;
    state.uploadPaused = false;
    state.uploadCancelled = false;
    state.uploadXhr = null;
    state.uploadStartedAt = 0;
    if (uploadFileInput) uploadFileInput.value = '';
    if (uploadSaveName) uploadSaveName.value = '';
    setUploadStatus('Ready to upload through LLC/PHP.');
    renderUploadState();
  }

  function selectUploadFile(file) {
    if (!file) return;
    if (!/\.gguf$/i.test(String(file.name || ''))) {
      setBanner('Only .gguf model/projector files can be uploaded.', 'error');
      return;
    }
    if (!Number(file.size || 0)) {
      setBanner('The selected GGUF file is empty.', 'error');
      return;
    }
    if (state.uploadSession && state.uploadSession.state !== 'completed') {
      setBanner('Cancel the current upload before selecting another file.', 'error');
      return;
    }
    resetUploadSelection();
    state.uploadFile = file;
    uploadSaveName.value = file.name;
    setUploadStatus(isProjectorUploadName(file.name)
      ? 'Detected as projector. It will be stored with the other local GGUF files.'
      : 'Ready to upload through LLC/PHP.');
    renderUploadState();
  }

  function parseUploadBridgeJson(xhr) {
    let data = null;
    try { data = JSON.parse(xhr.responseText || '{}'); } catch {}
    return data && typeof data === 'object' ? data : {};
  }

  function setUploadStatus(message, kind = '') {
    if (!uploadStatus) return;
    uploadStatus.textContent = message;
    uploadStatus.classList.toggle('error', kind === 'error');
    uploadStatus.classList.toggle('ok', kind === 'ok');
  }

  function uploadBridgeChunkRequest(session, body, contentRange, onProgress = null) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      state.uploadXhr = xhr;
      xhr.open('POST', 'api.php?action=locallightai_model_upload_chunk', true);
      xhr.responseType = 'text';
      xhr.setRequestHeader('Content-Type', 'application/octet-stream');
      xhr.setRequestHeader('Content-Range', contentRange);
      xhr.setRequestHeader('X-LLC-Upload-Id', String(session.upload_id || ''));
      xhr.setRequestHeader('X-LLC-Upload-Token', String(session.upload_token || ''));
      if (onProgress) xhr.upload.onprogress = onProgress;
      xhr.onload = () => {
        if (state.uploadXhr === xhr) state.uploadXhr = null;
        const data = parseUploadBridgeJson(xhr);
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve(data);
          return;
        }
        let message = data.error || `Upload bridge HTTP ${xhr.status || 0}`;
        if (xhr.status === 413) {
          message += ' The LLC web server/PHP request-body limit is smaller than the current upload chunk. Reduce LLC_LOCALLIGHTAI_UPLOAD_CHUNK_BYTES or raise the web-server/PHP body limit.';
        }
        const err = new Error(message);
        err.code = `HTTP_${xhr.status || 0}`;
        err.status = xhr.status || 0;
        reject(err);
      };
      xhr.onerror = () => {
        if (state.uploadXhr === xhr) state.uploadXhr = null;
        const err = new Error('Could not reach the LLC/PHP upload bridge.');
        err.code = 'BRIDGE_UNREACHABLE';
        reject(err);
      };
      xhr.onabort = () => {
        if (state.uploadXhr === xhr) state.uploadXhr = null;
        const err = new Error('Upload request aborted.');
        err.code = 'ABORTED';
        reject(err);
      };
      xhr.send(body);
    });
  }

  async function cancelUploadViaLLC(session, attempts = 3) {
    if (!session?.upload_id) return true;
    let lastError = null;
    for (let attempt = 0; attempt < attempts; attempt++) {
      try {
        await api('locallightai_model_upload_cancel', {upload_id:session.upload_id});
        return true;
      } catch (err) {
        lastError = err;
        if (err?.status === 404) return true;
        if (attempt + 1 < attempts) await new Promise(resolve => setTimeout(resolve, 250 * (attempt + 1)));
      }
    }
    if (lastError) console.warn('Upload cleanup failed:', lastError);
    return false;
  }

  async function queryUploadOffset() {
    const session = state.uploadSession;
    if (!session) throw new Error('Upload session is missing.');
    const status = await api('locallightai_model_upload_status', {
      upload_id:session.upload_id,
      upload_token:session.upload_token,
    });
    const received = Number(status.received_bytes || 0);
    if (!Number.isFinite(received) || received < 0 || received > state.uploadFile.size) {
      throw new Error('Control returned an invalid upload offset.');
    }
    state.uploadOffset = received;
    state.uploadInflightLoaded = 0;
    return status;
  }

  async function cleanupFailedUpload(session, err) {
    state.uploadInflightLoaded = 0;
    setUploadStatus(`${err?.message || 'Upload failed.'} Cleaning partial upload…`, 'error');
    const cleaned = await cancelUploadViaLLC(session, 3);
    if (cleaned) {
      state.uploadSession = null;
      state.uploadOffset = 0;
      state.uploadPaused = false;
      state.uploadCancelled = false;
      state.uploadStartedAt = 0;
      const message = `${err?.message || 'Upload failed.'} The partial upload was removed; you can press Upload to retry.`;
      setUploadStatus(message, 'error');
      setBanner(err?.message || 'Model upload failed.', 'error');
      return true;
    }
    state.uploadPaused = true;
    const message = `${err?.message || 'Upload interrupted.'} Automatic cleanup could not confirm removal. Use Cancel to retry cleanup or Resume to recover the confirmed Control offset.`;
    setUploadStatus(message, 'error');
    setBanner(err?.message || 'Model upload interrupted.', 'error');
    return false;
  }

  async function runUploadChunks() {
    const file = state.uploadFile;
    const session = state.uploadSession;
    if (!file || !session || state.uploadBusy) return;
    state.uploadBusy = true;
    state.uploadPaused = false;
    state.uploadCancelled = false;
    state.uploadInflightLoaded = 0;
    if (!state.uploadStartedAt) state.uploadStartedAt = performance.now();
    setUploadStatus('Uploading through LLC/PHP to LocalLight Control…');
    renderUploadState();

    try {
      while (state.uploadOffset < file.size) {
        if (state.uploadCancelled) throw Object.assign(new Error('Upload cancelled.'), {code:'ABORTED'});
        const start = state.uploadOffset;
        const chunkSize = Math.max(256 * 1024, Number(session.chunk_size || 64 * 1024 * 1024));
        const endExclusive = Math.min(file.size, start + chunkSize);
        const blob = file.slice(start, endExclusive);
        const range = `bytes ${start}-${endExclusive - 1}/${file.size}`;
        let response = null;
        let lastError = null;

        for (let attempt = 0; attempt < 3; attempt++) {
          state.uploadInflightLoaded = 0;
          try {
            response = await uploadBridgeChunkRequest(session, blob, range, event => {
              if (!event.lengthComputable) return;
              state.uploadInflightLoaded = Math.min(blob.size, Number(event.loaded || 0));
              renderUploadState();
            });
            state.uploadInflightLoaded = 0;
            break;
          } catch (err) {
            state.uploadInflightLoaded = 0;
            lastError = err;
            if (state.uploadCancelled || err?.code === 'ABORTED') throw err;

            // The browser may lose the PHP response after PHP/Control committed
            // the chunk. Ask Control through PHP for the authoritative offset
            // before retransmitting the same range.
            try {
              await queryUploadOffset();
              if (state.uploadOffset >= endExclusive) {
                response = {received_bytes:state.uploadOffset, completed:state.uploadOffset >= file.size};
                break;
              }
              if (state.uploadOffset !== start) {
                throw new Error(`Control confirmed an unexpected upload offset (${state.uploadOffset}).`);
              }
            } catch (statusErr) {
              lastError = statusErr?.message ? statusErr : lastError;
            }
            if (attempt < 2) await new Promise(resolve => setTimeout(resolve, 500 * (attempt + 1)));
          }
        }

        if (!response) throw lastError || new Error('Upload chunk failed.');
        const received = Number(response.received_bytes ?? endExclusive);
        if (!Number.isFinite(received) || received < start || received > file.size) {
          throw new Error('Control returned an invalid upload offset.');
        }
        state.uploadOffset = received;
        state.uploadInflightLoaded = 0;
        renderUploadState();

        if (response.completed || response.state === 'completed') {
          state.uploadOffset = file.size;
          state.uploadSession = {...session, ...response, state:'completed'};
          state.uploadPaused = false;
          setUploadStatus(response.catalog_scan_ok === false
            ? `Upload completed, but the automatic model scan failed: ${response.catalog_scan_error || 'unknown error'}`
            : 'Upload completed and scanned into the local model catalog.', response.catalog_scan_ok === false ? 'error' : 'ok');
          setBanner(`Uploaded ${file.name} to LocalLight Control.`, 'ok');
          await loadModels(false);
          renderUploadState();
          return;
        }
      }
    } catch (err) {
      if (!state.uploadCancelled) await cleanupFailedUpload(session, err);
    } finally {
      state.uploadBusy = false;
      state.uploadInflightLoaded = 0;
      renderUploadState();
    }
  }

  async function startModelUpload() {
    const file = state.uploadFile;
    if (!file || state.uploadBusy) return;
    const saveName = String(uploadSaveName.value || '').trim();
    if (!/\.gguf$/i.test(saveName) || /[\\/]/.test(saveName)) {
      setBanner('Save as must be a GGUF filename without folders.', 'error');
      uploadSaveName.focus();
      return;
    }
    state.uploadBusy = true;
    state.uploadStartedAt = performance.now();
    state.uploadInflightLoaded = 0;
    setUploadStatus('Creating upload session…');
    renderUploadState();
    try {
      const session = await api('locallightai_model_upload_start', {filename:saveName, size_bytes:file.size});
      if (!session?.upload_token || !session?.upload_id) {
        throw new Error('Control returned an incomplete upload session.');
      }
      state.uploadSession = session;
      state.uploadOffset = Number(session.received_bytes || 0);
      state.uploadBusy = false;
      renderUploadState();

      // Always confirm the Control-side offset through PHP. This also recovers
      // a session created by an earlier interrupted browser request.
      await queryUploadOffset();
      if (session.resumed_existing && state.uploadOffset > 0) {
        setUploadStatus(`Recovered an existing upload session at ${formatBytes(state.uploadOffset)}. Resuming through LLC/PHP…`);
      }
      await runUploadChunks();
    } catch (err) {
      state.uploadBusy = false;
      state.uploadInflightLoaded = 0;
      const session = state.uploadSession;
      if (session && session.state !== 'completed') {
        await cleanupFailedUpload(session, err);
      } else {
        state.uploadStartedAt = 0;
        setUploadStatus(err?.message || 'Model upload could not be started.', 'error');
        setBanner(err?.message || 'Model upload could not be started.', 'error');
      }
      renderUploadState();
    }
  }

  async function resumeModelUpload() {
    if (!state.uploadSession || !state.uploadFile || state.uploadBusy) return;
    try {
      setUploadStatus('Checking confirmed Control offset through LLC/PHP…');
      await queryUploadOffset();
      state.uploadPaused = false;
      renderUploadState();
      await runUploadChunks();
    } catch (err) {
      await cleanupFailedUpload(state.uploadSession, err);
      renderUploadState();
    }
  }

  async function cancelModelUpload() {
    const session = state.uploadSession;
    if (!session || session.state === 'completed') return;
    state.uploadCancelled = true;
    state.uploadPaused = false;
    state.uploadInflightLoaded = 0;
    if (state.uploadXhr) {
      try { state.uploadXhr.abort(); } catch {}
      state.uploadXhr = null;
    }
    setUploadStatus('Cancelling upload and removing partial data…');
    renderUploadState();

    const cancelled = await cancelUploadViaLLC(session, 4);
    state.uploadBusy = false;
    if (cancelled) {
      setBanner('Model upload cancelled. Partial data was removed.', 'ok');
      resetUploadSelection();
    } else {
      state.uploadCancelled = false;
      state.uploadPaused = true;
      setUploadStatus('Upload cancellation could not be confirmed. Resume will re-read Control\'s offset; Cancel can be retried without creating another session.', 'error');
      setBanner('Model upload could not be cancelled cleanly.', 'error');
      renderUploadState();
    }
  }

  function hfGateLabel(value) {
    const v = String(value ?? 'false').toLowerCase();
    if (!v || v === 'false' || v === 'none') return '';
    if (v === 'manual') return 'Gated · manual approval';
    if (v === 'auto' || v === 'true') return 'Gated';
    return `Gated · ${v}`;
  }

  function hfTokenConfigured() {
    return !!state.hfSettings?.token_configured;
  }

  function updateHFSettingsUI() {
    const configured = hfTokenConfigured();
    if (hfTokenStatus) {
      hfTokenStatus.textContent = state.hfSettings === null
        ? 'Token status not loaded'
        : (configured ? 'Configured · authenticated Hub requests enabled' : 'Not configured · public repositories only');
    }
    if (hfTokenClearBtn) hfTokenClearBtn.hidden = !configured;
    if (hfTokenSaveBtn) hfTokenSaveBtn.disabled = state.hfSettingsBusy;
    if (hfTokenClearBtn) hfTokenClearBtn.disabled = state.hfSettingsBusy;
    if (hfTokenInput) hfTokenInput.disabled = state.hfSettingsBusy;
  }

  async function loadHFSettings(showError = true) {
    if (state.hfSettingsBusy) return;
    state.hfSettingsBusy = true;
    updateHFSettingsUI();
    try {
      state.hfSettings = await api('locallightai_hf_settings');
    } catch (err) {
      state.hfSettings = {token_configured:false};
      if (showError) setBanner(err?.message || 'Hugging Face settings could not be loaded.', 'error');
    } finally {
      state.hfSettingsBusy = false;
      updateHFSettingsUI();
      renderHFResults();
    }
  }

  async function saveHFToken(clear = false) {
    if (state.hfSettingsBusy) return;
    const token = String(hfTokenInput?.value || '').trim();
    if (!clear && !token) {
      setBanner('Enter a Hugging Face access token first.', 'error');
      hfTokenInput?.focus();
      return;
    }
    state.hfSettingsBusy = true;
    updateHFSettingsUI();
    try {
      state.hfSettings = await api('locallightai_hf_settings_save', clear ? {clear_token:true} : {token});
      if (hfTokenInput) hfTokenInput.value = '';
      setBanner(clear ? 'Hugging Face access token removed.' : 'Hugging Face access token saved in LocalLight Control.', 'ok');
      renderHFResults();
    } catch (err) {
      setBanner(err?.message || 'Hugging Face access token could not be saved.', 'error');
    } finally {
      state.hfSettingsBusy = false;
      updateHFSettingsUI();
    }
  }

  function renderHFInlineAction(selected, blocked) {
    if (!selected) return '';
    const activeJob = state.hfDownloadJob && ['queued', 'downloading'].includes(String(state.hfDownloadJob.state || ''));
    if (activeJob) {
      return `<button type="button" class="llai-button llai-primary llai-hf-inline-download" disabled>Downloading…</button>`;
    }
    const title = blocked ? 'This repository requires Hugging Face authentication. Configure an access token above.' : 'Download this selection';
    return `<button type="button" class="llai-button llai-primary llai-hf-inline-download" data-hf-download-start ${blocked ? 'disabled' : ''} title="${esc(title)}">${blocked ? 'Auth required' : 'Download'}</button>`;
  }

  function renderHFVariant(repoId, variant) {
    const selected = state.hfSelection?.kind === 'model' && state.hfSelection?.repoId === repoId && state.hfSelection?.key === variant.key;
    const detail = state.hfRepositoryDetails.get(repoId) || {};
    const blocked = (!!detail?.private || !!hfGateLabel(detail?.gated)) && !hfTokenConfigured();
    const size = variant.size_known ? formatBytes(variant.size_bytes) : 'Size unknown';
    const fileCount = Number(variant.file_count || 0);
    const fileLabel = variant.sharded ? `${fileCount} shards` : `${fileCount || 1} file`;
    const detected = !!variant.quantization_detected;
    const files = Array.isArray(variant.files) ? variant.files : [];
    const fileLines = files.map(file => `<code title="${esc(file.path || '')}">${esc(file.path || '')}${file.size_known ? ` · ${esc(formatBytes(file.size_bytes))}` : ''}</code>`).join('');
    return `
      <div class="llai-hf-variant${selected ? ' selected' : ''}">
        <div class="llai-hf-variant-row">
          <label class="llai-hf-variant-select">
            <input type="radio" name="llai-hf-download-item" data-hf-variant-repo="${esc(repoId)}" data-hf-variant-key="${esc(variant.key || '')}" ${selected ? 'checked' : ''}>
            <span class="llai-hf-variant-main">
              <span class="llai-hf-variant-title-row">
                <strong>${esc(variant.label || 'GGUF')}</strong>
                <span class="llai-model-status ${detected ? 'available' : 'detected'}">${detected ? 'QUANT' : 'UNLABELED'}</span>
              </span>
              <span>${esc(size)} · ${esc(fileLabel)}</span>
              <code title="${esc(variant.primary_file || '')}">${esc(variant.primary_file || '')}</code>
            </span>
          </label>
          ${renderHFInlineAction(selected, blocked)}
        </div>
        ${files.length > 1 ? `<details class="llai-hf-files"><summary>${files.length} files in this variant</summary><div>${fileLines}</div></details>` : ''}
      </div>`;
  }

  function renderHFProjector(repoId, projector) {
    const path = String(projector?.path || '');
    const selected = state.hfSelection?.kind === 'projector' && state.hfSelection?.repoId === repoId && state.hfSelection?.path === path;
    const detail = state.hfRepositoryDetails.get(repoId) || {};
    const blocked = (!!detail?.private || !!hfGateLabel(detail?.gated)) && !hfTokenConfigured();
    const size = projector?.size_known ? formatBytes(projector.size_bytes) : 'Size unknown';
    const sourceName = String(projector?.filename || path.split('/').pop() || 'mmproj.gguf');
    const localName = String(projector?.local_filename || sourceName);
    return `
      <div class="llai-hf-variant llai-hf-projector${selected ? ' selected' : ''}">
        <div class="llai-hf-variant-row">
          <label class="llai-hf-variant-select">
            <input type="radio" name="llai-hf-download-item" data-hf-projector-repo="${esc(repoId)}" data-hf-projector-path="${esc(path)}" ${selected ? 'checked' : ''}>
            <span class="llai-hf-variant-main">
              <span class="llai-hf-variant-title-row">
                <strong>${esc(sourceName)}</strong>
                <span class="llai-model-status detected">PROJECTOR</span>
              </span>
              <span>${esc(size)} · saved locally as</span>
              <code title="${esc(localName)}">${esc(localName)}</code>
              ${path !== sourceName ? `<code class="llai-hf-source-path" title="${esc(path)}">HF: ${esc(path)}</code>` : ''}
            </span>
          </label>
          ${renderHFInlineAction(selected, blocked)}
        </div>
      </div>`;
  }

  function renderHFRepositoryDetails(repoId, detail) {
    if (!detail) return '';
    const variants = Array.isArray(detail.variants) ? [...detail.variants] : [];
    variants.sort((a,b) => {
      const ak = a?.size_known ? Number(a.size_bytes || 0) : Number.MAX_SAFE_INTEGER;
      const bk = b?.size_known ? Number(b.size_bytes || 0) : Number.MAX_SAFE_INTEGER;
      return ak - bk || String(a?.label || '').localeCompare(String(b?.label || ''));
    });
    const projectors = Array.isArray(detail.projector_files) ? [...detail.projector_files] : [];
    projectors.sort((a,b) => {
      const ak = a?.size_known ? Number(a.size_bytes || 0) : Number.MAX_SAFE_INTEGER;
      const bk = b?.size_known ? Number(b.size_bytes || 0) : Number.MAX_SAFE_INTEGER;
      return ak - bk || String(a?.filename || a?.path || '').localeCompare(String(b?.filename || b?.path || ''));
    });
    if (!variants.length && !projectors.length) {
      return `<div class="llai-hf-detail-empty"><strong>No GGUF files found.</strong><span>The repository may be mislabeled, empty, or private.</span></div>`;
    }
    return `
      ${variants.length ? `
        <div class="llai-hf-detail-head">
          <div><strong>Select a GGUF variant</strong><span>Quantization labels are inferred from file paths when possible. Unlabeled files remain selectable as exact files.</span></div>
          <span>${variants.length} variant${variants.length === 1 ? '' : 's'}</span>
        </div>
        <div class="llai-hf-variants">${variants.map(v => renderHFVariant(repoId, v)).join('')}</div>` : `
        <div class="llai-hf-detail-empty"><strong>No model GGUF files found.</strong><span>This repository may only contain projector files.</span></div>`}
      ${projectors.length ? `
        <div class="llai-hf-projector-section">
          <div class="llai-hf-detail-head">
            <div><strong>Projectors</strong><span>Projectors are independent downloads. Pick the one you want; no model-quantization matching is imposed.</span></div>
            <span>${projectors.length} file${projectors.length === 1 ? '' : 's'}</span>
          </div>
          <div class="llai-hf-variants">${projectors.map(p => renderHFProjector(repoId, p)).join('')}</div>
        </div>` : ''}`;
  }

  function renderHFSelection() {
    const selection = state.hfSelection;
    const job = state.hfDownloadJob;
    const activeJob = job && ['queued', 'downloading'].includes(String(job.state || ''));
    if (job) {
      const downloaded = Number(job.bytes_downloaded || 0);
      const total = Number(job.bytes_total || 0);
      const totalKnown = !!job.bytes_total_known && total > 0;
      const pct = totalKnown ? Math.max(0, Math.min(100, (downloaded / total) * 100)) : 0;
      const fileCount = Number(job.file_count || 0);
      const filesDone = Number(job.files_done || 0);
      const stateName = String(job.state || 'queued');
      const stateLabel = stateName === 'completed' ? 'Downloaded'
        : stateName === 'failed' ? 'Download failed'
        : stateName === 'cancelled' ? 'Download cancelled'
        : stateName === 'queued' ? 'Queued'
        : 'Downloading';
      const bytesText = totalKnown
        ? `${formatBytes(downloaded)} / ${formatBytes(total)} · ${pct.toFixed(pct >= 10 ? 0 : 1)}%`
        : `${formatBytes(downloaded)} downloaded`;
      const isProjectorJob = String(job.kind || '') === 'projector';
      const fileText = isProjectorJob ? (fileCount ? `${filesDone}/${fileCount} projector` : '') : (fileCount > 1 ? `${filesDone}/${fileCount} shards` : (fileCount ? `${filesDone}/${fileCount} file` : ''));
      const backendText = job.backend === 'hfget'
        ? (job.transport === 'xet' ? 'Xet · hfget' : (job.transport === 'http' ? 'HTTP · hfget' : 'hfget'))
        : (job.backend === 'native' ? 'native fallback' : '');
      const transferText = [backendText, fileText].filter(Boolean).join(' · ');
      hfSelectionRoot.hidden = false;
      hfSelectionRoot.innerHTML = `
        <div class="llai-hf-download-main">
          <span>${esc(stateLabel)}</span>
          <strong>${esc(job.repo_id || '')} · ${esc(job.label || 'GGUF')}</strong>
          ${job.current_file ? `<code title="${esc(job.current_file)}">${esc(job.current_file)}</code>` : `<code>${esc(job.destination_rel || '')}</code>`}
          ${activeJob ? `<div class="llai-hf-download-progress${totalKnown ? '' : ' unknown'}"><span style="width:${totalKnown ? pct : 0}%"></span></div>` : ''}
          ${job.error ? `<div class="llai-hf-download-error">${esc(job.error)}</div>` : ''}
        </div>
        <div class="llai-hf-selection-meta">
          <strong>${esc(bytesText)}</strong>
          ${transferText ? `<span>${esc(transferText)}</span>` : ''}
          ${activeJob
            ? `<button type="button" class="llai-button" data-hf-download-cancel="${esc(job.id || '')}" ${job.cancel_requested ? 'disabled' : ''}>${job.cancel_requested ? 'Cancelling…' : 'Cancel'}</button>`
            : `<span>${stateName === 'completed' ? (isProjectorJob ? 'Projector saved in the local model folder.' : 'Saved in the local model folder.') : 'Select a model or projector to continue.'}</span>`}
        </div>`;
      return;
    }

    // Selection is acted on in-place next to the chosen quant/projector.
    // Keep this top strip exclusively for an actual download job/progress state.
    hfSelectionRoot.hidden = true;
    hfSelectionRoot.innerHTML = '';
  }

  function renderHFResults() {
    renderHFSelection();
    if (state.hfSearching) {
      hfResultsRoot.innerHTML = '<div class="llai-model-empty"><strong>Searching Hugging Face…</strong><span>Looking for GGUF repositories and recovering file-based matches where metadata is incomplete.</span></div>';
      return;
    }
    const results = Array.isArray(state.hfResults) ? state.hfResults : [];
    if (!state.hfQuery) {
      hfResultsRoot.innerHTML = '<div class="llai-model-empty"><strong>No Hugging Face search yet.</strong><span>Search for a model family, author, or exact repository. Quantizations are derived from the actual GGUF files, not just repository metadata.</span></div>';
      return;
    }
    if (!results.length) {
      hfResultsRoot.innerHTML = `<div class="llai-model-empty"><strong>No GGUF repositories found for “${esc(state.hfQuery)}”.</strong><span>Try a shorter model name or an exact owner/repository id.</span></div>`;
      return;
    }
    hfResultsRoot.innerHTML = results.map(item => {
      const repoId = String(item?.id || '');
      const expanded = state.hfExpandedRepoId === repoId;
      const loading = state.hfRepositoryLoading.has(repoId);
      const detail = state.hfRepositoryDetails.get(repoId) || null;
      const gate = hfGateLabel(item?.gated);
      const ggufCount = Number(item?.gguf_files || 0);
      const meta = [
        capabilityLabel(item?.capability || ''),
        item?.pipeline_tag || '',
        `${formatCount(item?.downloads)} downloads`,
        `${formatCount(item?.likes)} likes`,
        ggufCount > 0 ? `${ggufCount} GGUF file${ggufCount === 1 ? '' : 's'}` : (item?.gguf_declared ? 'GGUF metadata' : 'GGUF match'),
        gate,
      ].filter(Boolean);
      return `
        <article class="llai-hf-card${expanded ? ' expanded' : ''}">
          <div class="llai-hf-card-top">
            <div class="llai-hf-card-main">
              <div class="llai-model-card-title-row"><h3 title="${esc(repoId)}">${esc(repoId)}</h3>${gate ? '<span class="llai-model-status detected">GATED</span>' : ''}</div>
              <div class="llai-hf-card-meta">${meta.map(v => `<span>${esc(v)}</span>`).join('<span class="llai-hf-dot">·</span>')}</div>
              ${item?.last_modified ? `<span class="llai-hf-updated">Updated ${esc(item.last_modified)}</span>` : ''}
            </div>
            <div class="llai-hf-card-actions">
              <a class="llai-button" href="${esc(item?.web_url || `https://huggingface.co/${repoId}`)}" target="_blank" rel="noopener noreferrer">Open on HF</a>
              <button type="button" class="llai-button" data-hf-inspect="${esc(repoId)}" ${loading ? 'disabled' : ''}>${loading ? 'Loading…' : (expanded ? 'Hide files' : 'Show GGUFs')}</button>
            </div>
          </div>
          <div class="llai-hf-repo-detail" ${expanded ? '' : 'hidden'}>${expanded ? renderHFRepositoryDetails(repoId, detail) : ''}</div>
        </article>`;
    }).join('');
  }

  async function searchHuggingFace() {
    const query = String(hfQueryInput?.value || '').trim();
    if (query.length < 2) {
      setBanner('Enter at least 2 characters for the Hugging Face search.', 'error');
      hfQueryInput?.focus();
      return;
    }
    if (state.hfSearching) return;
    state.hfSearching = true;
    state.hfQuery = query;
    state.hfExpandedRepoId = '';
    state.hfRepositoryDetails.clear();
    state.hfRepositoryLoading.clear();
    state.hfSelection = null;
    hfSearchButton.disabled = true;
    hfSearchButton.textContent = 'Searching…';
    setBanner('');
    renderHFResults();
    try {
      const result = await api('locallightai_hf_search', {query, limit:20});
      state.hfResults = Array.isArray(result?.results) ? result.results : [];
    } catch (err) {
      state.hfResults = [];
      setBanner(err?.message || 'Hugging Face search failed.', 'error');
    } finally {
      state.hfSearching = false;
      hfSearchButton.disabled = false;
      hfSearchButton.textContent = 'Search';
      renderHFResults();
    }
  }

  async function inspectHFRepository(repoId) {
    if (!repoId || state.hfRepositoryLoading.has(repoId)) return;
    if (state.hfExpandedRepoId === repoId) {
      state.hfExpandedRepoId = '';
      renderHFResults();
      return;
    }
    state.hfExpandedRepoId = repoId;
    if (state.hfRepositoryDetails.has(repoId)) {
      renderHFResults();
      return;
    }
    state.hfRepositoryLoading.add(repoId);
    renderHFResults();
    try {
      const detail = await api('locallightai_hf_repository', {repo_id:repoId});
      state.hfRepositoryDetails.set(repoId, detail || {});
    } catch (err) {
      state.hfExpandedRepoId = '';
      setBanner(err?.message || 'Hugging Face repository could not be inspected.', 'error');
    } finally {
      state.hfRepositoryLoading.delete(repoId);
      renderHFResults();
    }
  }

  function selectHFVariant(repoId, key) {
    const running = state.hfDownloadJob && ['queued', 'downloading'].includes(String(state.hfDownloadJob.state || ''));
    if (running) {
      setBanner('A Hugging Face download is already running. Cancel it or wait for it to finish before selecting another model or projector.', 'error');
      return;
    }
    if (state.hfDownloadJob) state.hfDownloadJob = null;
    const detail = state.hfRepositoryDetails.get(repoId);
    const variant = Array.isArray(detail?.variants) ? detail.variants.find(v => String(v?.key || '') === String(key || '')) : null;
    if (!variant) return;
    state.hfSelection = {
      kind: 'model',
      repoId,
      key: variant.key || '',
      label: variant.label || 'GGUF',
      primary_file: variant.primary_file || '',
      size_bytes: Number(variant.size_bytes || 0),
      size_known: !!variant.size_known,
      file_count: Number(variant.file_count || 0),
      files: Array.isArray(variant.files) ? variant.files : [],
      gated: detail?.gated ?? 'false',
      private: !!detail?.private,
    };
    setBanner('');
    renderHFResults();
  }

  function selectHFProjector(repoId, path) {
    const running = state.hfDownloadJob && ['queued', 'downloading'].includes(String(state.hfDownloadJob.state || ''));
    if (running) {
      setBanner('A Hugging Face download is already running. Cancel it or wait for it to finish before selecting another model or projector.', 'error');
      return;
    }
    if (state.hfDownloadJob) state.hfDownloadJob = null;
    const detail = state.hfRepositoryDetails.get(repoId);
    const projector = Array.isArray(detail?.projector_files) ? detail.projector_files.find(p => String(p?.path || '') === String(path || '')) : null;
    if (!projector) return;
    state.hfSelection = {
      kind: 'projector',
      repoId,
      path: projector.path || '',
      label: projector.filename || projector.path || 'Projector',
      local_filename: projector.local_filename || projector.filename || '',
      size_bytes: Number(projector.size_bytes || 0),
      size_known: !!projector.size_known,
      file_count: 1,
      gated: detail?.gated ?? 'false',
      private: !!detail?.private,
    };
    setBanner('');
    renderHFResults();
  }

  function queueHFDownloadPoll(delay = 800) {
    if (state.hfDownloadPollTimer) clearTimeout(state.hfDownloadPollTimer);
    state.hfDownloadPollTimer = setTimeout(() => {
      state.hfDownloadPollTimer = null;
      pollHFDownload();
    }, delay);
  }

  async function syncLocalCatalogAfterHFDownload(job) {
    const id = String(job?.id || '');
    if (!id || state.hfDownloadCatalogSyncedJobId === id) return;
    try {
      state.modelCatalog = await api('locallightai_model_scan');
      state.hfDownloadCatalogSyncedJobId = id;
      renderModels();
      setBanner(job?.kind === 'projector' ? 'Hugging Face projector downloaded. The local model catalog was updated.' : 'Hugging Face model downloaded. The local model catalog was updated.', 'ok');
    } catch (err) {
      setBanner(`Download completed, but the local model scan failed: ${err?.message || 'unknown error'}`, 'error');
    }
  }

  async function pollHFDownload() {
    const id = String(state.hfDownloadJob?.id || '');
    if (!id || state.hfDownloadStatusBusy) return;
    state.hfDownloadStatusBusy = true;
    try {
      const result = await api('locallightai_hf_download_status', {job_id:id});
      if (result?.job) state.hfDownloadJob = result.job;
      renderHFSelection();
      const status = String(state.hfDownloadJob?.state || '');
      if (status === 'queued' || status === 'downloading') {
        queueHFDownloadPoll(800);
      } else if (status === 'completed') {
        await syncLocalCatalogAfterHFDownload(state.hfDownloadJob);
        renderHFResults();
      } else if (status === 'failed') {
        setBanner(state.hfDownloadJob?.error || 'Hugging Face download failed.', 'error');
        renderHFResults();
      } else if (status === 'cancelled') {
        setBanner('Hugging Face download cancelled.');
        renderHFResults();
      }
    } catch (err) {
      setBanner(err?.message || 'Could not read Hugging Face download status.', 'error');
      if (state.hfDownloadJob && ['queued', 'downloading'].includes(String(state.hfDownloadJob.state || ''))) {
        queueHFDownloadPoll(2000);
      }
    } finally {
      state.hfDownloadStatusBusy = false;
    }
  }

  async function startHFDownload() {
    const selection = state.hfSelection;
    if (!selection || state.hfDownloadStatusBusy) return;
    const gate = hfGateLabel(selection.gated);
    if ((selection.private || gate) && !hfTokenConfigured()) {
      setBanner('This repository requires Hugging Face authentication. Configure an access token above.', 'error');
      hfTokenInput?.focus();
      return;
    }
    state.hfDownloadStatusBusy = true;
    setBanner('');
    try {
      const payload = {repo_id: selection.repoId};
      if (selection.kind === 'projector') payload.projector_path = selection.path;
      else payload.variant_key = selection.key;
      const result = await api('locallightai_hf_download', payload);
      state.hfDownloadJob = result?.job || null;
      renderHFResults();
      if (state.hfDownloadJob?.id) queueHFDownloadPoll(250);
    } catch (err) {
      setBanner(err?.message || 'Hugging Face download could not be started.', 'error');
    } finally {
      state.hfDownloadStatusBusy = false;
    }
  }

  async function cancelHFDownload(jobId) {
    const id = String(jobId || state.hfDownloadJob?.id || '');
    if (!id || state.hfDownloadStatusBusy) return;
    state.hfDownloadStatusBusy = true;
    try {
      const result = await api('locallightai_hf_download_cancel', {job_id:id});
      if (result?.job) state.hfDownloadJob = result.job;
      renderHFResults();
      queueHFDownloadPoll(150);
    } catch (err) {
      setBanner(err?.message || 'Hugging Face download could not be cancelled.', 'error');
    } finally {
      state.hfDownloadStatusBusy = false;
    }
  }

  function updateViews() {
    overviewGrid.innerHTML = Object.keys(SERVICE_META)
      .map(id => renderOverviewCard(id, state.services[id], state.busy.has(id)))
      .join('');

    detailStatusRoots.runtime.innerHTML = renderDetailStatus('llama', state.services.llama);
    detailStatusRoots.retrieval.innerHTML = renderDetailStatus('ragd', state.services.ragd);
    detailStatusRoots.mcp.innerHTML = renderDetailStatus('mcp', state.services.mcp);

    renderOverall(state.snapshot, state.services, statusEl, statusTextEl);
    renderControlSummary(state.snapshot, runtimeDetails);
    renderSystem(state.snapshot, systemGrid);
    renderRetrievalSetup();

    const info = state.snapshot?.info || {};
    if (state.snapshot?.reachable) {
      meta.textContent = `Control ${info.version || ''}${info.platform ? ` · ${info.platform}` : ''}`.trim();
    } else {
      meta.textContent = 'LocalLight Control is not reachable.';
    }
  }


  function catalogArtifacts() {
    return Array.isArray(state.modelCatalog?.artifacts) ? state.modelCatalog.artifacts : [];
  }

  function catalogProfiles() {
    return Array.isArray(state.modelCatalog?.profiles) ? state.modelCatalog.profiles : [];
  }

  function findArtifact(id) {
    return catalogArtifacts().find(a => a?.id === id) || null;
  }

  function findProfile(id) {
    return catalogProfiles().find(p => p?.id === id) || null;
  }

  const RETRIEVAL_RECOMMENDED = [
    {
      capability:'embedding',
      repo:'Qwen/Qwen3-Embedding-0.6B-GGUF',
      quant:'Q8_0',
      label:'Qwen3-Embedding-0.6B-Q8_0',
    },
    {
      capability:'reranker',
      repo:'ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF',
      quant:'Q8_0',
      label:'Qwen3-Reranker-0.6B-Q8_0',
    },
  ];

  function artifactSourceRepo(artifact) {
    return String(artifact?.source?.repo_id || '').trim();
  }

  function artifactPathText(artifact) {
    const files = artifact?.artifact || {};
    return `${artifact?.name_hint || ''} ${files.model || files.directory || ''}`.toLowerCase();
  }

  function findRecommendedArtifact(spec) {
    const exact = catalogArtifacts().find(a =>
      a?.status !== 'missing' && a?.status !== 'ignored' &&
      artifactSourceRepo(a).toLowerCase() === spec.repo.toLowerCase());
    if (exact) return exact;
    const repoName = spec.repo.split('/').pop().toLowerCase().replace(/-gguf$/i, '');
    return catalogArtifacts().find(a =>
      a?.status !== 'missing' && a?.status !== 'ignored' &&
      artifactCapability(a) === spec.capability &&
      artifactPathText(a).includes(repoName)) || null;
  }

  function profilesForArtifact(artifact) {
    if (!artifact) return [];
    return catalogProfiles().filter(p => p?.artifact_id === artifact.id);
  }

  function findConfiguredProfile(name, capability) {
    const wanted = String(name || '').trim().toLowerCase();
    if (!wanted) return null;
    return catalogProfiles().find(p => {
      if (profileName(p).toLowerCase() !== wanted) return false;
      const artifact = findArtifact(p.artifact_id);
      return artifact && artifact?.status === 'available' &&
        (!capability || artifactCapability(artifact) === capability);
    }) || null;
  }

  function retrievalSetupState() {
    const cfg = state.managedConfigs?.retrieval?.config || {};
    const embeddingProfile = findConfiguredProfile(cfg.embedding_model, 'embedding');
    const rerankerProfile = findConfiguredProfile(cfg.reranker_model, 'reranker');
    const recommended = RETRIEVAL_RECOMMENDED.map(spec => {
      const artifact = findRecommendedArtifact(spec);
      const profiles = profilesForArtifact(artifact);
      return {spec, artifact, profile:profiles[0] || null};
    });
    return {
      cfg,
      embeddingProfile,
      rerankerProfile,
      ready:!!embeddingProfile && !!rerankerProfile && !!cfg.reranker_enabled,
      recommended,
    };
  }

  function renderRetrievalSetup() {
    if (!retrievalSetupRoot) return;
    const managed = state.managedConfigs?.retrieval;
    if (!managed?.readable) {
      retrievalSetupRoot.innerHTML = '';
      return;
    }
    if (state.retrievalSetupManual) {
      retrievalSetupRoot.innerHTML = `
        <section class="llai-retrieval-setup compact">
          <div>
            <strong>Manual retrieval model selection</strong>
            <span>Use the Embedding and Reranker fields below. LocalLight will not replace your choices.</span>
          </div>
          <button type="button" class="llai-button" data-retrieval-setup-show>Show recommended setup</button>
        </section>`;
      return;
    }

    if (!state.modelCatalog) {
      retrievalSetupRoot.innerHTML = `
        <section class="llai-retrieval-setup">
          <div><strong>Retrieval model setup</strong><span>Loading the local model catalog…</span></div>
        </section>`;
      return;
    }

    const info = retrievalSetupState();
    if (info.ready && !state.retrievalSetupBusy) {
      retrievalSetupRoot.innerHTML = `
        <section class="llai-retrieval-setup ready">
          <div class="llai-retrieval-setup-title">
            <div><strong>Retrieval models ready</strong><span>RAGd is configured to use local embedding and reranker profiles.</span></div>
            <span class="llai-model-status available">READY</span>
          </div>
          <div class="llai-retrieval-model-grid">
            <div><span>Embedding</span><strong>${esc(profileName(info.embeddingProfile))}</strong></div>
            <div><span>Reranker</span><strong>${esc(profileName(info.rerankerProfile))}</strong></div>
          </div>
        </section>`;
      return;
    }

    const rows = info.recommended.map(({spec, artifact, profile}) => {
      const status = profile ? `Local profile · ${profileName(profile)}` : artifact ? 'Downloaded · profile needed' : 'Not installed';
      const capLabel = capabilityLabel(spec.capability);
      return `
        <div class="llai-retrieval-model-row">
          <div><span>${esc(capLabel)}</span><strong>${esc(spec.label)}</strong><code>${esc(spec.repo)}</code></div>
          <span class="llai-model-status ${profile ? 'available' : artifact ? 'detected' : 'missing'}">${esc(status)}</span>
        </div>`;
    }).join('');

    const message = state.retrievalSetupError
      ? `<div class="llai-config-error">${esc(state.retrievalSetupError)}</div>`
      : state.retrievalSetupMessage
        ? `<div class="llai-retrieval-setup-message">${esc(state.retrievalSetupMessage)}</div>`
        : '';

    retrievalSetupRoot.innerHTML = `
      <section class="llai-retrieval-setup">
        <div class="llai-retrieval-setup-title">
          <div>
            <strong>Recommended Retrieval Setup</strong>
            <span>LocalLight can download and configure a known-good embedding + reranker pair.</span>
          </div>
          <span class="llai-model-status detected">SETUP</span>
        </div>
        <div class="llai-retrieval-model-list">${rows}</div>
        <div class="llai-retrieval-runtime-note">
          llama.cpp profiles are created with <code>ctx 32768</code> · <code>batch 2048</code> · <code>uBatch 2048</code>.
          Embedding uses <code>embedding=true</code> + <code>pooling=last</code>; reranking uses
          <code>embedding=true</code> + <code>reranking=true</code> + <code>pooling=rank</code>.
        </div>
        ${message}
        <div class="llai-retrieval-setup-actions">
          <button type="button" class="llai-button llai-primary" data-retrieval-setup-start ${state.retrievalSetupBusy ? 'disabled' : ''}>${state.retrievalSetupBusy ? 'Setting up…' : 'Download & configure'}</button>
          ${state.retrievalSetupBusy && state.retrievalSetupCurrentJobId ? '<button type="button" class="llai-button llai-danger" data-retrieval-setup-cancel>Cancel download</button>' : ''}
          <button type="button" class="llai-button" data-retrieval-setup-manual ${state.retrievalSetupBusy ? 'disabled' : ''}>I’ll choose models myself</button>
        </div>
      </section>`;
  }

  function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  function q8Variant(repository, quant = 'Q8_0') {
    const variants = Array.isArray(repository?.variants) ? repository.variants : [];
    const q = quant.toLowerCase();
    return variants.find(v => String(v?.quantization || '').toLowerCase() === q)
      || variants.find(v => String(v?.label || '').toLowerCase() === q)
      || variants.find(v => String(v?.primary_file || '').toLowerCase().includes(q.toLowerCase()))
      || null;
  }

  async function downloadRetrievalRecommendation(spec) {
    state.retrievalSetupMessage = `Inspecting ${spec.repo}…`;
    state.retrievalSetupError = '';
    renderRetrievalSetup();

    const repository = await api('locallightai_hf_repository', {repo_id:spec.repo});
    const variant = q8Variant(repository, spec.quant);
    if (!variant) throw new Error(`${spec.repo} does not currently expose the expected ${spec.quant} GGUF variant.`);

    const started = await api('locallightai_hf_download', {repo_id:spec.repo, variant_key:variant.key});
    let job = started?.job;
    if (!job?.id) throw new Error(`Control did not return a download job for ${spec.repo}.`);
    state.hfDownloadJob = job;
    state.retrievalSetupCurrentJobId = job.id;
    renderHFResults();

    while (['queued','downloading'].includes(String(job.state || ''))) {
      const done = Number(job.bytes_downloaded || 0);
      const total = Number(job.bytes_total || 0);
      const pct = total > 0 ? Math.max(0, Math.min(100, done / total * 100)) : 0;
      state.retrievalSetupMessage = total > 0
        ? `Downloading ${spec.label} · ${pct.toFixed(pct >= 10 ? 0 : 1)}% · ${formatBytes(done)} / ${formatBytes(total)}`
        : `Downloading ${spec.label} · ${formatBytes(done)}`;
      renderRetrievalSetup();
      await sleep(350);
      const status = await api('locallightai_hf_download_status', {job_id:job.id});
      job = status?.job || job;
      state.hfDownloadJob = job;
      renderHFResults();
    }

    state.retrievalSetupCurrentJobId = '';
    if (job.state !== 'completed') {
      throw new Error(job.error || `${spec.label} download ${job.state || 'failed'}.`);
    }
  }

  async function ensureRecommendedRetrievalProfile(spec) {
    let artifact = findRecommendedArtifact(spec);
    let existingProfiles = profilesForArtifact(artifact);
    if (existingProfiles.length) return existingProfiles[0];

    if (!artifact) {
      await downloadRetrievalRecommendation(spec);
      state.retrievalSetupMessage = `Scanning ${spec.label} into the local model catalog…`;
      renderRetrievalSetup();
      state.modelCatalog = await api('locallightai_model_scan');
      renderModels();
      artifact = findRecommendedArtifact(spec);
      if (!artifact) throw new Error(`${spec.label} downloaded, but the local model scan could not identify it.`);
    }

    existingProfiles = profilesForArtifact(artifact);
    if (existingProfiles.length) return existingProfiles[0];

    state.retrievalSetupMessage = `Creating optimized ${capabilityLabel(spec.capability).toLowerCase()} runtime profile…`;
    renderRetrievalSetup();
    const profile = defaultNewProfile(artifact, state.modelCatalog);
    state.modelCatalog = await api('locallightai_profile_create', {
      artifact_id:artifact.id,
      profile,
    });
    renderModels();
    const created = profilesForArtifact(findArtifact(artifact.id))[0] || null;
    if (!created) throw new Error(`The ${capabilityLabel(spec.capability).toLowerCase()} profile could not be found after creation.`);
    return created;
  }

  async function startRecommendedRetrievalSetup() {
    if (state.retrievalSetupBusy) return;
    state.retrievalSetupBusy = true;
    state.retrievalSetupError = '';
    state.retrievalSetupMessage = 'Checking local retrieval models…';
    state.retrievalSetupManual = false;
    if (state.hfDownloadPollTimer) {
      clearTimeout(state.hfDownloadPollTimer);
      state.hfDownloadPollTimer = null;
    }
    renderRetrievalSetup();

    try {
      state.modelCatalog = await api('locallightai_model_scan');
      renderModels();

      const embeddingProfile = await ensureRecommendedRetrievalProfile(RETRIEVAL_RECOMMENDED[0]);
      const rerankerProfile = await ensureRecommendedRetrievalProfile(RETRIEVAL_RECOMMENDED[1]);

      const managed = state.managedConfigs?.retrieval;
      if (!managed?.readable) throw new Error('RAGd configuration is not available.');
      const cfg = {...(managed.config || {})};
      cfg.llama_url = String(cfg.llama_url || '').trim() || 'http://127.0.0.1:8080';
      cfg.reranker_url = String(cfg.reranker_url || '').trim() || cfg.llama_url;
      cfg.embedding_model = profileName(embeddingProfile);
      cfg.reranker_model = profileName(rerankerProfile);
      cfg.reranker_enabled = true;

      state.retrievalSetupMessage = 'Saving RAGd model configuration…';
      renderRetrievalSetup();
      const result = await api('locallightai_save_managed_config', {kind:'retrieval', config:cfg});
      if (result?.config) {
        if (!state.managedConfigs) state.managedConfigs = {};
        state.managedConfigs.retrieval = result.config;
        renderManagedConfig('retrieval', result.config, retrievalConfigRoot);
      }

      state.retrievalSetupMessage = 'Retrieval models configured. Restart Runtime and RAGd to apply the new profiles.';
      setBanner('Recommended retrieval models downloaded and configured. Restart Runtime and RAGd to apply them.', 'ok');
    } catch (err) {
      state.retrievalSetupError = err?.message || 'Recommended Retrieval Setup failed.';
      setBanner(state.retrievalSetupError, 'error');
    } finally {
      state.retrievalSetupBusy = false;
      state.retrievalSetupCurrentJobId = '';
      renderRetrievalSetup();
    }
  }

  async function cancelRecommendedRetrievalSetup() {
    const jobId = String(state.retrievalSetupCurrentJobId || '');
    if (!jobId) return;
    try {
      state.retrievalSetupMessage = 'Cancelling retrieval model download…';
      renderRetrievalSetup();
      await api('locallightai_hf_download_cancel', {job_id:jobId});
    } catch (err) {
      state.retrievalSetupError = err?.message || 'Download cancellation failed.';
      renderRetrievalSetup();
    }
  }

  function renderModels() {
    renderRetrievalSetup();
    const artifacts = catalogArtifacts();
    const profiles = catalogProfiles();
    if (!state.modelCatalog) {
      modelCatalogMeta.textContent = 'Use Scan models after adding local model files.';
      modelListRoot.innerHTML = '<div class="llai-service-empty">Model catalog has not been loaded yet.</div>';
      modelEditorRoot.hidden = true;
      modelRestoreIgnoredBtn.hidden = true;
      return;
    }

    const ignoredCount = Number(state.modelCatalog.ignored_count ?? artifacts.filter(a => a?.status === 'ignored').length) || 0;
    const visibleArtifacts = artifacts.filter(a => a?.status !== 'ignored');
    modelRestoreIgnoredBtn.hidden = ignoredCount <= 0;
    modelRestoreIgnoredBtn.textContent = ignoredCount > 0 ? `Restore ignored (${ignoredCount})` : 'Restore ignored';
    const lastScan = state.modelCatalog.last_scan_at || 'never';
    modelCatalogMeta.innerHTML = `<span>Models folder <code title="${esc(state.modelCatalog.models_root || '')}">${esc(state.modelCatalog.models_root || 'n/a')}</code></span><span>Last scan <strong>${esc(lastScan)}</strong></span><span>${visibleArtifacts.length} artifact${visibleArtifacts.length === 1 ? '' : 's'} · ${profiles.length} profile${profiles.length === 1 ? '' : 's'}</span>`;

    if (!visibleArtifacts.length) {
      modelListRoot.innerHTML = ignoredCount > 0
        ? '<div class="llai-model-empty"><strong>No visible model artifacts.</strong><span>Ignored artifacts stay hidden until you restore them.</span></div>'
        : '<div class="llai-model-empty"><strong>No model artifacts in the catalog.</strong><span>Copy models into the models folder and click Scan models.</span></div>';
    } else {
      const order = {detected:0, available:1, missing:2};
      const sorted = [...visibleArtifacts].sort((a,b) => {
        const statusDelta = (order[a.status] ?? 9) - (order[b.status] ?? 9);
        if (statusDelta) return statusDelta;
        if (a.status === 'detected' && b.status === 'detected') {
          const mtimeDelta = String(b.mtime || '').localeCompare(String(a.mtime || ''));
          if (mtimeDelta) return mtimeDelta;
        }
        return String(a.name_hint || '').localeCompare(String(b.name_hint || ''));
      });
      modelListRoot.innerHTML = sorted.map(a => renderArtifactCard(a, state.modelCatalog, state.artifactDeleteConfirmId, state.artifactDeleteBusyId)).join('');
    }

    let editorHtml = '';
    if (state.editingProfileId) {
      const profile = findProfile(state.editingProfileId);
      const artifact = profile ? findArtifact(profile.artifact_id) : null;
      if (profile && artifact && artifact.status !== 'ignored') editorHtml = renderProfileEditor(profile, artifact, false);
      else state.editingProfileId = '';
    } else if (state.creatingProfileArtifactId) {
      const artifact = findArtifact(state.creatingProfileArtifactId);
      if (artifact && artifact.status !== 'ignored') editorHtml = renderProfileEditor(defaultNewProfile(artifact, state.modelCatalog), artifact, true);
      else state.creatingProfileArtifactId = '';
    }

    if (editorHtml) {
      modelEditorRoot.innerHTML = editorHtml;
      modelEditorRoot.hidden = false;
      enhanceLocalNumberInputs(modelEditorRoot);
    } else {
      modelEditorRoot.hidden = true;
      modelEditorRoot.innerHTML = '';
    }
  }

  async function loadModels(showError = true) {
    if (state.modelsLoading) return;
    state.modelsLoading = true;
    try {
      state.modelCatalog = await api('locallightai_models');
      renderModels();
    } catch (err) {
      if (showError) setBanner(err?.message || 'Model catalog could not be loaded.', 'error');
      modelListRoot.innerHTML = `<div class="llai-service-error">${esc(err?.message || 'Model catalog could not be loaded.')}</div>`;
    } finally {
      state.modelsLoading = false;
    }
  }

  async function scanModels() {
    if (state.modelsScanning) return;
    state.modelsScanning = true;
    const original = modelScanBtn.textContent;
    modelScanBtn.disabled = true;
    modelScanBtn.textContent = 'Scanning…';
    setBanner('Scanning the local models folder…');
    try {
      state.modelCatalog = await api('locallightai_model_scan');
      state.editingProfileId = '';
      state.creatingProfileArtifactId = '';
      renderModels();
      const count = catalogArtifacts().filter(a => a?.status !== 'ignored').length;
      setBanner(`Model scan complete. ${count} artifact${count === 1 ? '' : 's'} found in the catalog.`, 'ok');
    } catch (err) {
      setBanner(err?.message || 'Model scan failed.', 'error');
    } finally {
      state.modelsScanning = false;
      modelScanBtn.disabled = false;
      modelScanBtn.textContent = original;
    }
  }

  async function restoreIgnoredModels() {
    if (state.modelsRestoringIgnored) return;
    state.modelsRestoringIgnored = true;
    const original = modelRestoreIgnoredBtn.textContent;
    modelRestoreIgnoredBtn.disabled = true;
    modelRestoreIgnoredBtn.textContent = 'Restoring…';
    try {
      state.modelCatalog = await api('locallightai_model_restore_ignored');
      state.editingProfileId = '';
      state.creatingProfileArtifactId = '';
      renderModels();
      setBanner('Ignored artifacts restored to the catalog view. No filesystem scan was run.', 'ok');
    } catch (err) {
      setBanner(err?.message || 'Ignored artifacts could not be restored.', 'error');
    } finally {
      state.modelsRestoringIgnored = false;
      if (modelRestoreIgnoredBtn.isConnected) {
        modelRestoreIgnoredBtn.disabled = false;
        if (!modelRestoreIgnoredBtn.hidden) modelRestoreIgnoredBtn.textContent = original;
      }
    }
  }

  function openProfileEditor(id) {
    const profile = findProfile(id);
    if (!profile || !findArtifact(profile.artifact_id)) return;
    state.creatingProfileArtifactId = '';
    state.editingProfileId = id;
    renderModels();
    modelEditorRoot.scrollIntoView({block:'nearest', behavior:'smooth'});
  }

  function openNewProfileEditor(artifactId) {
    const artifact = findArtifact(artifactId);
    if (!artifact || artifact.status === 'ignored') return;
    state.editingProfileId = '';
    state.creatingProfileArtifactId = artifactId;
    renderModels();
    modelEditorRoot.scrollIntoView({block:'nearest', behavior:'smooth'});
  }

  async function saveProfile(profileId, artifactId, button) {
    const form = modelEditorRoot.querySelector('[data-profile-editor]');
    if (!form) return;
    const isNew = !profileId;
    const original = button?.textContent || (isNew ? 'Add profile' : 'Save profile');
    if (button) { button.disabled = true; button.textContent = 'Saving…'; }
    try {
      const data = collectModelForm(form);
      state.modelCatalog = isNew
        ? await api('locallightai_profile_create', {artifact_id:artifactId, profile:data})
        : await api('locallightai_profile_save', {profile_id:profileId, profile:data});
      state.editingProfileId = '';
      state.creatingProfileArtifactId = '';
      renderModels();
      setBanner(`Profile ${isNew ? 'added' : 'saved'} and llama.cpp presets regenerated.`, 'ok');
    } catch (err) {
      setBanner(err?.message || 'Profile could not be saved.', 'error');
    } finally {
      if (button?.isConnected) { button.disabled = false; button.textContent = original; }
    }
  }

  async function profileCommand(profileId, command) {
    const oldIds = new Set(catalogProfiles().map(p => p?.id).filter(Boolean));
    try {
      state.modelCatalog = await api('locallightai_profile_command', {profile_id:profileId, command});
      state.creatingProfileArtifactId = '';
      if (command === 'duplicate') {
        const added = catalogProfiles().find(p => p?.id && !oldIds.has(p.id));
        state.editingProfileId = added?.id || '';
        renderModels();
        setBanner('Profile duplicated. Adjust the copy and save when ready.', 'ok');
        if (state.editingProfileId) modelEditorRoot.scrollIntoView({block:'nearest', behavior:'smooth'});
      } else {
        if (state.editingProfileId === profileId) state.editingProfileId = '';
        renderModels();
        setBanner('Profile removed. Model files were not deleted.', 'ok');
      }
    } catch (err) {
      setBanner(err?.message || 'Profile action failed.', 'error');
    }
  }

  async function artifactCommand(artifactId, command, options = {}) {
    const deletingFiles = command === 'delete-files';
    if (deletingFiles) {
      if (state.artifactDeleteBusyId) return;
      state.artifactDeleteBusyId = artifactId;
      setBanner('Deleting GGUF files from disk…');
      renderModels();
    }
    try {
      const payload = {artifact_id:artifactId, command};
      if (deletingFiles) payload.delete_projectors = !!options.deleteProjectors;
      const result = await api('locallightai_artifact_command', payload);
      state.modelCatalog = result;
      if (state.creatingProfileArtifactId === artifactId) state.creatingProfileArtifactId = '';
      const profile = state.editingProfileId ? findProfile(state.editingProfileId) : null;
      if (profile?.artifact_id === artifactId || deletingFiles) state.editingProfileId = '';
      if (deletingFiles) state.artifactDeleteConfirmId = '';
      renderModels();
      if (command === 'ignore') {
        setBanner('Artifact ignored. Use Restore ignored to show it again.', 'ok');
      } else if (deletingFiles) {
        const fileCount = Number(result?.deleted_file_count || 0);
        const projectorCount = Number(result?.deleted_projector_count || 0);
        const profileCount = Number(result?.deleted_profile_count || 0);
        const freed = Number(result?.deleted_bytes || 0);
        const parts = [`Deleted ${fileCount || 1} model GGUF file${fileCount === 1 ? '' : 's'} from disk`];
        if (projectorCount > 0) parts.push(`${projectorCount} projector file${projectorCount === 1 ? '' : 's'} deleted`);
        else if (options.deleteProjectors) parts.push('associated projector files were already missing');
        else parts.push('projector files kept');
        if (freed > 0) parts.push(`${formatBytes(freed)} freed`);
        if (profileCount > 0) parts.push(`${profileCount} profile${profileCount === 1 ? '' : 's'} removed`);
        setBanner(parts.join(' · ') + '.', 'ok');
      } else {
        setBanner('Artifact removed from the catalog. Model files were not deleted.', 'ok');
      }
    } catch (err) {
      setBanner(err?.message || 'Artifact action failed.', 'error');
    } finally {
      if (deletingFiles) {
        state.artifactDeleteBusyId = '';
        renderModels();
      }
    }
  }


  function schedulePoll(delay = null) {
    if (state.pollTimer) clearTimeout(state.pollTimer);
    state.pollTimer = null;
    if (state.mode !== 'control' || document.hidden) return;
    const wait = delay == null ? state.pollMs : delay;
    state.pollTimer = setTimeout(async () => {
      await refresh(false);
      schedulePoll();
    }, Math.max(500, wait));
  }

  async function refresh(showError = true, reloadManagedConfigs = false) {
    if (state.refreshing) return;
    state.refreshing = true;
    refreshBtn.disabled = true;
    try {
      const [snap, managed] = await Promise.all([
        api('locallightai_snapshot'),
        reloadManagedConfigs || state.managedConfigs === null
          ? api('locallightai_managed_configs').catch(err => ({ ok: false, error: err?.message || 'Managed config read failed' }))
          : Promise.resolve(null),
      ]);
      state.snapshot = snap || { reachable: false };
      state.services = normalizeServices(snap);
      if (managed?.configs) {
        state.managedConfigs = managed.configs;
        renderManagedConfig('retrieval', state.managedConfigs.retrieval, retrievalConfigRoot);
        renderManagedConfig('mcp', state.managedConfigs.mcp, mcpConfigRoot);
      }
      const configuredPoll = Number(snap?.config?.status_poll_interval_ms || 1000);
      state.pollMs = Number.isFinite(configuredPoll) ? Math.max(500, Math.min(10000, configuredPoll)) : 1000;
      if (!snap?.reachable) {
        setBanner(snap?.error || 'LocalLight Control is unavailable.', 'error');
      } else if (Array.isArray(snap?.errors) && snap.errors.length) {
        setBanner(snap.errors.join(' · '), 'error');
      } else {
        setBanner('');
      }
      updateViews();
    } catch (err) {
      state.snapshot = { reachable: false };
      state.services = {};
      if (showError) setBanner(err?.message || 'LocalLight Control request failed.', 'error');
      updateViews();
    } finally {
      state.refreshing = false;
      refreshBtn.disabled = false;
    }
  }

  async function saveManagedConfig(kind, button) {
    const form = controlView.querySelector(`[data-managed-form="${kind}"]`);
    if (!form || !['retrieval', 'mcp'].includes(kind)) return;
    const original = button?.textContent || 'Save configuration';
    if (button) {
      button.disabled = true;
      button.textContent = 'Saving…';
    }
    try {
      const result = await api('locallightai_save_managed_config', {
        kind,
        config: collectManagedForm(form),
      });
      if (result?.config) {
        if (!state.managedConfigs) state.managedConfigs = {};
        state.managedConfigs[kind] = result.config;
        renderManagedConfig(kind, result.config, kind === 'retrieval' ? retrievalConfigRoot : mcpConfigRoot);
        if (kind === 'retrieval') renderRetrievalSetup();
      }
      const label = kind === 'retrieval' ? 'RAGd' : 'Agent Runtime';
      setBanner(`${label} configuration saved. Restart ${label} from Overview to apply the changes.`, 'ok');
    } catch (err) {
      setBanner(err?.message || 'Configuration could not be saved.', 'error');
    } finally {
      if (button && button.isConnected) {
        button.disabled = false;
        button.textContent = original;
      }
    }
  }

  async function runAction(id, command, quiet = false) {
    if (!SERVICE_META[id] || state.busy.has(id)) return false;
    state.busy.add(id);
    updateViews();
    try {
      await api('locallightai_service_action', { id, command });
      if (!quiet) setBanner(`${SERVICE_META[id].title}: ${command} accepted.`, 'ok');
      setTimeout(() => refresh(false), 120);
      setTimeout(() => refresh(false), 650);
      return true;
    } catch (err) {
      setBanner(`${SERVICE_META[id].title}: ${err?.message || 'Control action failed.'}`, 'error');
      return false;
    } finally {
      state.busy.delete(id);
      updateViews();
      schedulePoll(850);
    }
  }

  async function runAll(command) {
    startAllBtn.disabled = true;
    stopAllBtn.disabled = true;
    setBanner(`${command === 'start' ? 'Starting' : 'Stopping'} LocalLight services…`);
    const ids = Object.keys(SERVICE_META);
    const results = await Promise.allSettled(ids.map(id => runAction(id, command, true)));
    const failed = results.filter(r => r.status === 'rejected' || r.value === false).length;
    if (failed) setBanner(`${failed} service command${failed === 1 ? '' : 's'} failed.`, 'error');
    else setBanner(`${command === 'start' ? 'Start' : 'Stop'} commands accepted.`, 'ok');
    startAllBtn.disabled = false;
    stopAllBtn.disabled = false;
    setTimeout(() => refresh(false), 700);
  }

  function setMode(mode) {
    state.mode = mode === 'control' ? 'control' : 'chat';
    for (const btn of switcher.querySelectorAll('[data-llai-mode]')) {
      const active = btn.dataset.llaiMode === state.mode;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-pressed', active ? 'true' : 'false');
    }
    const control = state.mode === 'control';
    controlView.hidden = !control;
    chatArea.classList.toggle('llai-chat-hidden', control);
    inputSection.classList.toggle('llai-chat-hidden', control);
    document.body.classList.toggle('llai-control-active', control);

    if (control) {
      refresh(false, state.managedConfigs === null).finally(() => schedulePoll());
    } else if (state.pollTimer) {
      clearTimeout(state.pollTimer);
      state.pollTimer = null;
    }
  }

  uploadFileInput?.addEventListener('change', () => selectUploadFile(uploadFileInput.files?.[0] || null));
  uploadDrop?.addEventListener('click', event => {
    if (event.target === uploadChooseBtn || event.target === uploadFileInput) return;
    if (!state.uploadFile) uploadFileInput?.click();
  });
  uploadSaveName?.addEventListener('input', () => renderUploadState());
  uploadDrop?.addEventListener('keydown', event => {
    if ((event.key === 'Enter' || event.key === ' ') && !state.uploadFile) {
      event.preventDefault();
      uploadFileInput?.click();
    }
  });
  for (const name of ['dragenter','dragover']) {
    uploadDrop?.addEventListener(name, event => {
      event.preventDefault();
      if (!state.uploadFile) uploadDrop.classList.add('dragging');
    });
  }
  for (const name of ['dragleave','drop']) {
    uploadDrop?.addEventListener(name, event => {
      event.preventDefault();
      uploadDrop.classList.remove('dragging');
    });
  }
  uploadDrop?.addEventListener('drop', event => {
    const file = event.dataTransfer?.files?.[0];
    if (file) selectUploadFile(file);
  });

  switcher.addEventListener('click', event => {
    const btn = event.target.closest('[data-llai-mode]');
    if (btn) setMode(btn.dataset.llaiMode);
  });

  controlView.addEventListener('click', event => {
    const modelSource = event.target.closest('[data-model-source]');
    if (modelSource) {
      setModelSource(modelSource.dataset.modelSource);
      return;
    }

    const retrievalSetupStart = event.target.closest('[data-retrieval-setup-start]');
    if (retrievalSetupStart) {
      startRecommendedRetrievalSetup();
      return;
    }

    const retrievalSetupCancel = event.target.closest('[data-retrieval-setup-cancel]');
    if (retrievalSetupCancel) {
      cancelRecommendedRetrievalSetup();
      return;
    }

    const retrievalSetupManual = event.target.closest('[data-retrieval-setup-manual]');
    if (retrievalSetupManual) {
      state.retrievalSetupManual = true;
      state.retrievalSetupError = '';
      state.retrievalSetupMessage = '';
      renderRetrievalSetup();
      retrievalConfigRoot?.scrollIntoView({block:'nearest', behavior:'smooth'});
      return;
    }

    const retrievalSetupShow = event.target.closest('[data-retrieval-setup-show]');
    if (retrievalSetupShow) {
      state.retrievalSetupManual = false;
      renderRetrievalSetup();
      return;
    }

    if (event.target === uploadChooseBtn) {
      if (!state.uploadFile) uploadFileInput?.click();
      return;
    }

    if (event.target === uploadStartBtn) {
      startModelUpload();
      return;
    }

    if (event.target === uploadResumeBtn) {
      resumeModelUpload();
      return;
    }

    if (event.target === uploadCancelBtn) {
      cancelModelUpload();
      return;
    }

    if (event.target === uploadClearBtn) {
      resetUploadSelection();
      return;
    }

    if (event.target === uploadViewLocalBtn) {
      setModelSource('local');
      return;
    }

    if (event.target === hfTokenSaveBtn) {
      saveHFToken(false);
      return;
    }

    if (event.target === hfTokenClearBtn) {
      saveHFToken(true);
      return;
    }

    const hfDownloadStart = event.target.closest('[data-hf-download-start]');
    if (hfDownloadStart) {
      startHFDownload();
      return;
    }

    const hfDownloadCancel = event.target.closest('[data-hf-download-cancel]');
    if (hfDownloadCancel) {
      cancelHFDownload(hfDownloadCancel.dataset.hfDownloadCancel);
      return;
    }

    const hfInspect = event.target.closest('[data-hf-inspect]');
    if (hfInspect) {
      inspectHFRepository(hfInspect.dataset.hfInspect);
      return;
    }

    const hfProjector = event.target.closest('[data-hf-projector-path]');
    if (hfProjector) {
      selectHFProjector(hfProjector.dataset.hfProjectorRepo, hfProjector.dataset.hfProjectorPath);
      return;
    }

    const hfVariant = event.target.closest('[data-hf-variant-key]');
    if (hfVariant) {
      selectHFVariant(hfVariant.dataset.hfVariantRepo, hfVariant.dataset.hfVariantKey);
      return;
    }

    const action = event.target.closest('[data-service-action]');
    if (action) {
      runAction(action.dataset.serviceId, action.dataset.serviceAction);
      return;
    }

    const saveConfig = event.target.closest('[data-config-save]');
    if (saveConfig) {
      saveManagedConfig(saveConfig.dataset.configSave, saveConfig);
      return;
    }

    const selectOption = event.target.closest('[data-llai-select-option]');
    if (selectOption) {
      const select = selectOption.closest('[data-llai-select]');
      const input = select?.querySelector('input[type="hidden"]');
      const label = select?.querySelector('[data-llai-select-label]');
      const menu = select?.querySelector('[data-llai-select-menu]');
      const toggle = select?.querySelector('[data-llai-select-toggle]');
      if (select && input) {
        input.value = selectOption.dataset.llaiSelectOption ?? '';
        if (label) label.textContent = selectOption.textContent || '';
        for (const option of select.querySelectorAll('[data-llai-select-option]')) {
          const active = option === selectOption;
          option.classList.toggle('selected', active);
          option.setAttribute('aria-selected', active ? 'true' : 'false');
        }
        if (menu) menu.hidden = true;
        if (toggle) toggle.setAttribute('aria-expanded', 'false');
        select.classList.remove('open');
        input.dispatchEvent(new Event('input', {bubbles:true}));
        input.dispatchEvent(new Event('change', {bubbles:true}));
      }
      return;
    }

    const selectToggle = event.target.closest('[data-llai-select-toggle]');
    if (selectToggle) {
      const select = selectToggle.closest('[data-llai-select]');
      if (!select) return;
      const menu = select.querySelector('[data-llai-select-menu]');
      const opening = !!menu?.hidden;
      for (const other of controlView.querySelectorAll('[data-llai-select].open')) {
        if (other === select) continue;
        other.classList.remove('open');
        const otherMenu = other.querySelector('[data-llai-select-menu]');
        const otherToggle = other.querySelector('[data-llai-select-toggle]');
        if (otherMenu) otherMenu.hidden = true;
        if (otherToggle) otherToggle.setAttribute('aria-expanded', 'false');
      }
      if (menu) menu.hidden = !opening;
      select.classList.toggle('open', opening);
      selectToggle.setAttribute('aria-expanded', opening ? 'true' : 'false');
      return;
    }

    const profileOpen = event.target.closest('[data-profile-open]');
    if (profileOpen) {
      openProfileEditor(profileOpen.dataset.profileOpen);
      return;
    }

    const profileAdd = event.target.closest('[data-profile-add]');
    if (profileAdd) {
      openNewProfileEditor(profileAdd.dataset.profileAdd);
      return;
    }

    const profileSave = event.target.closest('[data-profile-save]');
    if (profileSave) {
      saveProfile(profileSave.dataset.profileSave || '', profileSave.dataset.artifactId || '', profileSave);
      return;
    }

    const modelApplyPreset = event.target.closest('[data-model-apply-preset]');
    if (modelApplyPreset) {
      const form = modelApplyPreset.closest('[data-profile-editor]');
      if (applyRecommendedPreset(form)) setBanner('Recommended sampling preset applied. Save the profile to persist it.', 'ok');
      else setBanner('Choose a recommended preset first.', 'error');
      return;
    }

    if (event.target.closest('[data-profile-cancel]')) {
      state.editingProfileId = '';
      state.creatingProfileArtifactId = '';
      renderModels();
      return;
    }

    const profileDuplicate = event.target.closest('[data-profile-duplicate]');
    if (profileDuplicate) {
      profileCommand(profileDuplicate.dataset.profileDuplicate, 'duplicate');
      return;
    }

    const profileRemove = event.target.closest('[data-profile-remove]');
    if (profileRemove) {
      profileCommand(profileRemove.dataset.profileRemove, 'remove');
      return;
    }

    const artifactDeleteFiles = event.target.closest('[data-artifact-delete-files]');
    if (artifactDeleteFiles) {
      const artifactId = artifactDeleteFiles.dataset.artifactDeleteFiles;
      if (!findArtifact(artifactId) || state.artifactDeleteBusyId) return;
      state.artifactDeleteConfirmId = artifactId;
      renderModels();
      controlView.querySelector(`[data-artifact-card="${artifactId}"]`)?.scrollIntoView({block:'nearest', behavior:'smooth'});
      return;
    }

    const artifactDeleteCancel = event.target.closest('[data-artifact-delete-cancel]');
    if (artifactDeleteCancel) {
      if (state.artifactDeleteConfirmId === artifactDeleteCancel.dataset.artifactDeleteCancel) {
        state.artifactDeleteConfirmId = '';
        renderModels();
      }
      return;
    }

    const artifactDeleteConfirm = event.target.closest('[data-artifact-delete-confirm]');
    if (artifactDeleteConfirm) {
      const artifactId = artifactDeleteConfirm.dataset.artifactDeleteConfirm;
      const checkbox = controlView.querySelector(`[data-artifact-delete-projectors="${artifactId}"]`);
      artifactCommand(artifactId, 'delete-files', {deleteProjectors: !!checkbox?.checked});
      return;
    }

    const artifactIgnore = event.target.closest('[data-artifact-ignore]');
    if (artifactIgnore) {
      artifactCommand(artifactIgnore.dataset.artifactIgnore, 'ignore');
      return;
    }

    const artifactRemove = event.target.closest('[data-artifact-remove]');
    if (artifactRemove) {
      artifactCommand(artifactRemove.dataset.artifactRemove, 'remove');
      return;
    }

    const openTab = event.target.closest('[data-llai-open-tab]');
    if (openTab) {
      setTab(openTab.dataset.llaiOpenTab);
      return;
    }

    const tab = event.target.closest('[data-llai-tab]');
    if (tab) setTab(tab.dataset.llaiTab);
  });

  hfSearchForm.addEventListener('submit', event => {
    event.preventDefault();
    searchHuggingFace();
  });
  modelScanBtn.addEventListener('click', scanModels);
  modelRestoreIgnoredBtn.addEventListener('click', restoreIgnoredModels);
  refreshBtn.addEventListener('click', () => refresh(true, true).finally(() => schedulePoll()));
  startAllBtn.addEventListener('click', () => runAll('start'));
  stopAllBtn.addEventListener('click', () => runAll('stop'));

  document.addEventListener('click', event => {
    if (event.target.closest?.('[data-llai-select]')) return;
    for (const select of controlView.querySelectorAll('[data-llai-select].open')) {
      select.classList.remove('open');
      const menu = select.querySelector('[data-llai-select-menu]');
      const toggle = select.querySelector('[data-llai-select-toggle]');
      if (menu) menu.hidden = true;
      if (toggle) toggle.setAttribute('aria-expanded', 'false');
    }
  });

  document.addEventListener('visibilitychange', () => {
    if (!document.hidden && state.mode === 'control') refresh(false).finally(() => schedulePoll());
    else if (document.hidden && state.pollTimer) {
      clearTimeout(state.pollTimer);
      state.pollTimer = null;
    }
  });

  // LocalLightAI stays fully docked: Control is not contacted until the user
  // explicitly opens the Control workspace, and standalone LLC never imports
  // this module at all.
  updateViews();
}
