document.addEventListener('DOMContentLoaded', () => {
  const $  = (s, c=document) => c.querySelector(s);
  const $$ = (s, c=document) => Array.from(c.querySelectorAll(s));
  const on = (ev, sel, fn) => document.addEventListener(ev, e => {
    const el = e.target.closest(sel);
    if (el) fn(e, el);
  });

  // ---------- Mobile viewport height fix (address bar + keyboard)
  // CSS uses: height:calc(var(--vh, 1vh) * 100)
  let lastViewportHeight = 0;
  const setVh = () => {
    const vv = window.visualViewport;
    const h = (vv && vv.height) ? vv.height : window.innerHeight;
    if (!h || Math.abs(h - lastViewportHeight) < 0.5) return;
    lastViewportHeight = h;
    document.documentElement.style.setProperty('--vh', `${h * 0.01}px`);
  };
  setVh();
  window.addEventListener('resize', setVh, { passive: true });
  window.addEventListener('orientationchange', setVh, { passive: true });
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', setVh, { passive: true });
    window.visualViewport.addEventListener('scroll', setVh, { passive: true });
  }


  // ---------- MathML feature detection (for CSS fallbacks)
  // If the browser can't layout MathML, we add a class so CSS can draw boxed fallbacks.
  const _hasMathML = (()=>{
    try{
      const ns = 'http://www.w3.org/1998/Math/MathML';
      const m = document.createElementNS(ns, 'math');
      m.innerHTML = '<mrow><mi>x</mi><mn>2</mn></mrow>';
      m.style.position = 'absolute';
      m.style.visibility = 'hidden';
      m.style.fontSize = '32px';
      document.body.appendChild(m);
      const ok = m.getBoundingClientRect().height > 0 && m.getBoundingClientRect().width > 0;
      m.remove();
      return ok;
    }catch(e){
      return false;
    }
  })();
  if (!_hasMathML) document.documentElement.classList.add('no-mathml');

  // Some engines can layout basic MathML but don't support <menclose> (used for \boxed).
  // Detect that specifically so we can enable a CSS fallback without double-boxing.
  const _hasMenclose = (()=>{
    if (!_hasMathML) return false;
    try{
      const ns = 'http://www.w3.org/1998/Math/MathML';
      const mBox = document.createElementNS(ns, 'math');
      const mPlain = document.createElementNS(ns, 'math');
      mBox.innerHTML = '<menclose notation="box"><mi>x</mi></menclose>';
      mPlain.innerHTML = '<mi>x</mi>';

      for (const el of [mBox, mPlain]){
        el.style.position = 'absolute';
        el.style.visibility = 'hidden';
        el.style.fontSize = '32px';
        el.style.left = '-9999px';
        el.style.top = '-9999px';
      }
      document.body.appendChild(mBox);
      document.body.appendChild(mPlain);
      const b1 = mBox.getBoundingClientRect();
      const b2 = mPlain.getBoundingClientRect();
      mBox.remove();
      mPlain.remove();

      // If <menclose> works, it should add noticeable extra size compared to plain <mi>.
      // Use a small threshold to avoid false positives.
      return (b1.width - b2.width) > 1.5 && (b1.height - b2.height) > 1.5;
    }catch(e){
      return false;
    }
  })();
  if (_hasMathML && !_hasMenclose) document.documentElement.classList.add('no-menclose');

  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
// ---------- MathML rendering (no external libs) ----------
// This is a pragmatic TeX → MathML converter for the subset we actually use in chat.
// Supported (best-effort): \frac, \sqrt (incl. \sqrt[n]{x}), ^, _, \sum, \prod, \int,
// \begin{matrix|pmatrix|bmatrix|vmatrix|Vmatrix} ... \end{...}, greek letters, and basic operators.
const _mathmlCache = new Map();

const _escXml = (s)=> String(s ?? '').replace(/[&<>]/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[m]));
const _mml = (tag, attrs, children)=>{
  const a = attrs
    ? Object.entries(attrs)
        .filter(([,v])=> v !== null && v !== undefined && v !== '')
        .map(([k,v])=>` ${k}="${String(v).replace(/"/g,'&quot;')}"`).join('')
    : '';
  return `<${tag}${a}>${children ?? ''}</${tag}>`;
};

const _TEX_SYMBOLS = {
  // Greek + common symbols
  alpha:'α', beta:'β', gamma:'γ', delta:'δ', epsilon:'ϵ', varepsilon:'ε', zeta:'ζ', eta:'η', theta:'θ', vartheta:'ϑ',
  iota:'ι', kappa:'κ', lambda:'λ', mu:'μ', nu:'ν', xi:'ξ', pi:'π', varpi:'ϖ', rho:'ρ', varrho:'ϱ', sigma:'σ', varsigma:'ς',
  tau:'τ', upsilon:'υ', phi:'φ', varphi:'ϕ', chi:'χ', psi:'ψ', omega:'ω',
  Gamma:'Γ', Delta:'Δ', Theta:'Θ', Lambda:'Λ', Xi:'Ξ', Pi:'Π', Sigma:'Σ', Upsilon:'Υ', Phi:'Φ', Psi:'Ψ', Omega:'Ω',
  // operators / relations
  cdot:'·', times:'×', pm:'±', leq:'≤', geq:'≥', neq:'≠', approx:'≈', infty:'∞',

  // arrows. Keep common TeX aliases together so equivalent commands never
  // fall through to the generic "unknown command = identifier" fallback.
  to:'→', rightarrow:'→', longrightarrow:'⟶', xrarr:'⟶',
  leftarrow:'←', longleftarrow:'⟵',
  leftrightarrow:'↔', longleftrightarrow:'⟷',
  Rightarrow:'⇒', Longrightarrow:'⟹',
  Leftarrow:'⇐', Longleftarrow:'⟸',
  Leftrightarrow:'⇔', Longleftrightarrow:'⟺',
  mapsto:'↦', longmapsto:'⟼',
  hookrightarrow:'↪', hookleftarrow:'↩',
  uparrow:'↑', downarrow:'↓', updownarrow:'↕',
  Uparrow:'⇑', Downarrow:'⇓', Updownarrow:'⇕',
  nearrow:'↗', searrow:'↘', swarrow:'↙', nwarrow:'↖'
};

// Commands that should be rendered as <mo> operators/relations (spacing matters)
const _TEX_OPS = new Set([
  'cdot','cdotp','times','pm','mp','div',
  'leq','geq','neq','approx','sim','equiv',
  'to','rightarrow','longrightarrow','xrarr',
  'leftarrow','longleftarrow','leftrightarrow','longleftrightarrow',
  'Rightarrow','Longrightarrow','Leftarrow','Longleftarrow','Leftrightarrow','Longleftrightarrow',
  'mapsto','longmapsto','hookrightarrow','hookleftarrow',
  'uparrow','downarrow','updownarrow','Uparrow','Downarrow','Updownarrow',
  'nearrow','searrow','swarrow','nwarrow',
  'in','notin','subset','subseteq','supset','supseteq'
]);


function _texTokenize(input){
  const s = String(input ?? '');
  const t = [];
  let i = 0;
  const push = (type, value)=> t.push({type, value});
  while (i < s.length){
    const ch = s[i];
    if (/\s/.test(ch)){ i++; continue; }

    if (ch === '\\'){
      const next = s[i+1] || '';
      if (next === '\\'){ push('cmd', '\\\\'); i += 2; continue; }

      // Non-letter command like \{, \}, \_, \^, \$, \\, \, etc
      if (!/[A-Za-z]/.test(next)){
        push('cmd', next); // store the single escaped char, WITHOUT the backslash
        i += 2;
        continue;
      }

      let j = i + 1;
      while (j < s.length && /[A-Za-z]/.test(s[j])) j++;
      const name = s.slice(i+1, j); // store WITHOUT the backslash
      // Be forgiving for common TeX accent shorthand like "\\veca" (missing space/braces).
      if (name.startsWith('vec') && name.length > 3){
        push('cmd', 'vec');
        push('ident', name.slice(3));
      } else {
        push('cmd', name);
      }
      i = j;
      continue;
    }

    if ('{}[]()_^&'.includes(ch)){ push('sym', ch); i++; continue; }

    if (/[0-9]/.test(ch)){
      let j = i;
      while (j < s.length && /[0-9.]/.test(s[j])) j++;
      push('num', s.slice(i, j));
      i = j;
      continue;
    }

    if (/[A-Za-z]/.test(ch)){
      let j = i;
      while (j < s.length && /[A-Za-z]/.test(s[j])) j++;
      push('ident', s.slice(i, j));
      i = j;
      continue;
    }

    // everything else as operator char
    push('op', ch);
    i++;
  }
  return t;
}

function _texParser(tokens){
  let i = 0;
  const peek = ()=> tokens[i];
  const next = ()=> tokens[i++];
  const eof  = ()=> i >= tokens.length;

  const node = (mml, meta={})=> ({ mml, ...meta });

  const row = (nodes)=>{
    const parts = nodes.filter(n => n && n.mml !== undefined).map(n => n.mml).filter(Boolean);
    if (!parts.length) return node(_mml('mrow', null, ''));
    if (parts.length === 1) return node(parts[0], nodes[0] || {});
    return node(_mml('mrow', null, parts.join('')));
  };

  const mi = (txt)=> node(_mml('mi', null, _escXml(txt)));
  const mn = (txt)=> node(_mml('mn', null, _escXml(txt)));
  const mo = (txt, meta={})=> node(_mml('mo', null, _escXml(txt)), meta);

  const parseExpression = (stopSym=null)=>{
    const nodes = [];
    while(!eof()){
      const tok = peek();
      if (!tok) break;
      if (stopSym && tok.type==='sym' && tok.value===stopSym) break;
      if (tok.type==='sym' && tok.value==='}') break;
      nodes.push(parsePrimary());
    }
    return row(nodes);
  };

  const parseGroup = ()=>{
    const tok = peek();
    if (tok && tok.type==='sym' && tok.value==='{'){
      next(); // {
      const expr = parseExpression('}');
      if (peek() && peek().type==='sym' && peek().value==='}') next();
      return expr;
    }
    // If braces are missing, accept a single atom.
    return parsePrimary();
  };

  const parseRawTextGroup = ()=>{
    // Consume { ... } into a plain string (used for \text{...})
    let out = '';
    const tok = peek();
    if (!(tok && tok.type==='sym' && tok.value==='{')) return out;
    next(); // {
    let depth = 1;
    while(!eof() && depth > 0){
      const t0 = next();
      if (t0.type==='sym' && t0.value==='{'){ depth++; out += '{'; continue; }
      if (t0.type==='sym' && t0.value==='}'){ depth--; if (depth===0) break; out += '}'; continue; }
      if (t0.type==='cmd'){
        if (t0.value === '\\\\'){ out += '\n'; continue; }
        out += (t0.value.length===1 ? t0.value : ('\\' + t0.value));
        continue;
      }
      out += t0.value;
    }
    return out;
  };

  const parseScriptArg = ()=>{
    const tok = peek();
    if (!tok) return node(_mml('mrow', null, ''));
    if (tok.type==='sym' && tok.value==='{') return parseGroup();
    return parsePrimary();
  };

  const parseMatrixEnv = (name)=>{
    const rows = [];
    let curRow = [];
    let curCell = [];
    let depth = 0;

    const flushCell = ()=>{
      curRow.push(curCell);
      curCell = [];
    };
    const flushRow = ()=>{
      flushCell();
      rows.push(curRow);
      curRow = [];
    };

    while(!eof()){
      const tok = peek();

      // End environment? \end{name}
      if (depth === 0 && tok.type==='cmd' && tok.value==='end'){
        next(); // end
        // expect {name}
        if (peek() && peek().type==='sym' && peek().value==='{'){
          next();
          let envName = '';
          while(!eof()){
            const tt = next();
            if (tt.type==='sym' && tt.value==='}') break;
            envName += tt.value;
          }
          if (envName.trim() === name) break;
        }
        break;
      }

      // Track group depth so we don't split inside {...}
      if (tok.type==='sym' && tok.value==='{') depth++;
      if (tok.type==='sym' && tok.value==='}') depth = Math.max(0, depth-1);

      // Row separator: \\ at depth 0
      if (depth === 0 && tok.type==='cmd' && tok.value==='\\\\'){
        next();
        flushRow();
        continue;
      }

      // Column separator: & at depth 0
      if (depth === 0 && tok.type==='sym' && tok.value==='&'){
        next();
        flushCell();
        continue;
      }

      curCell.push(next());
    }

    if (curCell.length || curRow.length) flushRow();

    const mtrs = rows.map(r=>{
      const mtds = r.map(cellToks=>{
        const p2 = _texParser(cellToks);
        const cellExpr = p2.parseExpression();
        return _mml('mtd', null, cellExpr.mml);
      }).join('');
      return _mml('mtr', null, mtds);
    }).join('');

    // Spacing: browsers vary a bit in how tightly they pack mtable rows.
    // Use slightly roomier defaults so vectors/matrices don't look cramped.
    const table = _mml('mtable', { rowspacing:'0.45em', columnspacing:'0.75em' }, mtrs);

    const fences = {
      matrix: null,
      pmatrix: ['(', ')'],
      bmatrix: ['[', ']'],
      vmatrix: ['|', '|'],
      Vmatrix: ['‖', '‖'],
    };
    const f = fences[name] || null;
    if (!f) return node(table);
    return node(_mml('mrow', null, _mml('mo', null, _escXml(f[0])) + table + _mml('mo', null, _escXml(f[1]))));
  };
  const parseCasesEnv = ()=>{
    // Parses \begin{cases} ... \end{cases}
    // Split rows on \\ and columns on & at top-level (depth 0)
    const rows = [];
    let curRow = [];
    let curCell = [];
    let depth = 0;

    const flushCell = ()=>{
      curRow.push(curCell);
      curCell = [];
    };
    const flushRow = ()=>{
      flushCell();
      rows.push(curRow);
      curRow = [];
    };

    while(!eof()){
      const tok = peek();

      // End environment? \end{cases}
      if (depth === 0 && tok.type==='cmd' && tok.value==='end'){
        next(); // end
        if (peek() && peek().type==='sym' && peek().value==='{'){
          next();
          let envName = '';
          while(!eof()){
            const tt = next();
            if (tt.type==='sym' && tt.value==='}') break;
            envName += tt.value;
          }
          if (envName.trim() === 'cases') break;
        }
        break;
      }

      // Track group depth so we don't split inside {...}
      if (tok.type==='sym' && tok.value==='{'){ depth++; curCell.push(next()); continue; }
      if (tok.type==='sym' && tok.value==='}'){ depth = Math.max(0, depth-1); curCell.push(next()); continue; }

      // Column separator
      if (depth === 0 && tok.type==='sym' && tok.value==='&'){
        next();
        flushCell();
        continue;
      }

      // Row separator
      if (depth === 0 && tok.type==='cmd' && tok.value==='\\\\'){
        next();
        flushRow();
        continue;
      }

      curCell.push(next());
    }

    if (curCell.length || curRow.length) flushRow();

    const mtrs = rows.map(r=>{
      // Ensure 2 columns for cases: expr & condition
      const r2 = (r.length < 2) ? (r.concat([[]]).slice(0,2)) : r.slice(0,2);
      const mtds = r2.map(cellToks=>{
        const p2 = _texParser(cellToks);
        const cellExpr = p2.parseExpression();
        return _mml('mtd', null, cellExpr.mml);
      }).join('');
      return _mml('mtr', null, mtds);
    }).join('');

    const table = _mml('mtable', {
      columnalign: 'left left',
      rowspacing: '0.35em',
      columnspacing: '0.9em'
    }, mtrs);

    // Left curly brace + a little gap before the table
    const brace = _mml('mo', {fence:'true', stretchy:'true'}, _escXml('{'));
    const gap = _mml('mspace', {width:'0.25em'}, '');
    return node(_mml('mrow', null, brace + gap + table));
  };


  const parseAtom = ()=>{
    const tok = peek();
    if (!tok) return node(_mml('mrow', null, ''));

    // group
    if (tok.type==='sym' && tok.value==='{') return parseGroup();

    // numbers / identifiers
    if (tok.type==='num'){ next(); return mn(tok.value); }
    if (tok.type==='ident'){ next(); return mi(tok.value); }

    // delimiters
    if (tok.type==='sym' && '[]()'.includes(tok.value)){ next(); return mo(tok.value); }

    // raw operator char
    if (tok.type==='op'){ next(); return mo(tok.value); }

    // commands
    if (tok.type==='cmd'){
      next();

      // line breaks in non-matrix math: treat as space
      if (tok.value === '\\\\') return node('');

      // spacing commands (\, \; \! etc) show as nothing
      if (tok.value === ',' || tok.value === ';' || tok.value === '!' || tok.value === ' ' || tok.value === 'quad' || tok.value === 'qquad'){
        return node('');
      }

      // escaped special chars like \{, \}, \_, etc are stored as single-char cmd
      if (tok.value.length === 1 && '{}_^%$#&'.includes(tok.value)){
        return mo(tok.value);
      }

      // \left / \right: ignore (next token will be the delimiter)
      if (tok.value === 'left' || tok.value === 'right'){
        return node('');
      }

      if (tok.value === 'frac'){
        const num = parseGroup();
        const den = parseGroup();
        return node(_mml('mfrac', null, num.mml + den.mml));
      }

      if (tok.value === 'sqrt'){
        // optional root index: \sqrt[n]{x}
        if (peek() && peek().type==='sym' && peek().value==='['){
          next(); // [
          const idxExpr = parseExpression(']');
          if (peek() && peek().type==='sym' && peek().value===']') next();
          const rad = parseGroup();
          return node(_mml('mroot', null, rad.mml + idxExpr.mml));
        }
        const rad = parseGroup();
        return node(_mml('msqrt', null, rad.mml));
      }

      if (tok.value === 'text'){
        const txt = parseRawTextGroup();
        // Tokenizer strips whitespace, so add a small inter-word space after text blocks
        // (works well for typical cases like \text{wenn } x \ge 0).
        const t = _mml('mtext', null, _escXml(txt));
        const sp = _mml('mspace', {width:'0.2em'}, '');
        return node(_mml('mrow', null, t + sp));
      }

      // \boxed{...}
      // We intentionally *do not* rely on MathML <menclose> here because support is spotty
      // (and CSS borders on MathML nodes can clip badly). Boxing is handled at the
      // HTML wrapper level in the markdown renderer.
      if (tok.value === 'boxed'){
        const arg = (peek() && peek().type==='sym' && peek().value==='{') ? parseGroup() : parseAtom();
        return arg;
      }

      // Blackboard bold:

      // Blackboard bold: \mathbb{R}, \mathbb{D}_f, etc.
      // Render via MathML mathvariant="double-struck" (no external libs).
      if (tok.value === 'mathbb'){
        const arg = (peek() && peek().type==='sym' && peek().value==='{') ? parseGroup() : parseAtom();
        return node(_mml('mstyle', {mathvariant:'double-struck'}, arg.mml));
      }

      if (tok.value === 'begin'){
        // expect {envName}
        let envName = '';
        if (peek() && peek().type==='sym' && peek().value==='{'){
          next();
          while(!eof()){
            const tt = next();
            if (tt.type==='sym' && tt.value==='}') break;
            envName += tt.value;
          }
        }
        envName = envName.trim();
        if (['matrix','pmatrix','bmatrix','vmatrix','Vmatrix'].includes(envName)){
          return parseMatrixEnv(envName);
        }
        if (envName === 'cases'){
          return parseCasesEnv();
        }
        return mi(envName || '');
      }

      // big operators
      if (tok.value === 'sum')  return mo('∑', { bigop:'sum' });
      if (tok.value === 'prod') return mo('∏', { bigop:'prod' });
      if (tok.value === 'int')  return mo('∫', { bigop:'int' });

      // accents
      if (tok.value === 'vec'){
        const arg = (peek() && peek().type==='sym' && peek().value==='{') ? parseGroup() : parseAtom();
        const accent = _mml('mo', {accent:'true'}, _escXml('⃗'));
        return node(_mml('mover', {accent:'true'}, arg.mml + accent));
      }

      // mapped symbols
      if (_TEX_SYMBOLS[tok.value]){
        const ch = _TEX_SYMBOLS[tok.value];
        return _TEX_OPS.has(tok.value) ? mo(ch) : mi(ch);
      }

      // default: treat unknown command as identifier (best effort)
      return mi(tok.value);
    }

    next();
    return mi(tok.value || '');
  };

  const applyScripts = (base)=>{
    let sub = null, sup = null;

    while(!eof()){
      const tok = peek();
      if (!tok || tok.type!=='sym' || (tok.value!=='_' && tok.value!=='^')) break;
      next(); // _ or ^
      const arg = parseScriptArg();
      if (tok.value === '_') sub = arg;
      else sup = arg;
    }

    if (!sub && !sup) return base;

    if (sub && sup){
      if (base.bigop === 'sum' || base.bigop === 'prod') return node(_mml('munderover', null, base.mml + sub.mml + sup.mml));
      return node(_mml('msubsup', null, base.mml + sub.mml + sup.mml));
    }
    if (sub){
      if (base.bigop === 'sum' || base.bigop === 'prod') return node(_mml('munder', null, base.mml + sub.mml));
      return node(_mml('msub', null, base.mml + sub.mml));
    }
    if (sup){
      if (base.bigop === 'sum' || base.bigop === 'prod') return node(_mml('mover', null, base.mml + sup.mml));
      return node(_mml('msup', null, base.mml + sup.mml));
    }
    return base;
  };

  const parsePrimary = ()=> applyScripts(parseAtom());

  return { parseExpression };
}

const texToMathML = (tex, display=false)=>{
  const raw = String(tex ?? '');
  const key = (display ? 'B|' : 'I|') + raw;
  if (_mathmlCache.has(key)) return _mathmlCache.get(key);

  let out = '';
  try{
    const tokens = _texTokenize(raw);
    const p = _texParser(tokens);
    const expr = p.parseExpression();
    const body = _mml('mstyle', {displaystyle: display ? 'true' : 'false'}, expr.mml);
    out = display ? _mml('math', {display:'block'}, body) : _mml('math', null, body);
  }catch(_e){
    out = `<code>${esc(raw)}</code>`;
  }

  _mathmlCache.set(key, out);
  return out;
};

  const now = () => Date.now();
  const fmt = (ts) => new Date(ts||Date.now()).toLocaleString(undefined,{weekday:'short',hour:'2-digit',minute:'2-digit'});

  // ---------- lightweight, dismissible work panel (for long operations)
  let jobPanel = null;
  let jobDismissed = false;
  const ensureJobPanel = ()=>{
    if (jobPanel) return jobPanel;
    const el = document.createElement('div');
    el.id = 'llc-job-panel';
    el.className = 'llc-job-panel hidden';
    el.innerHTML = `
      <div class="llc-job-panel-head">
        <div class="llc-job-panel-title">Working…</div>
        <button class="llc-job-panel-close" type="button" title="Hide">×</button>
      </div>
      <div class="llc-job-panel-body"></div>
    `;
    document.body.appendChild(el);
    el.querySelector('.llc-job-panel-close')?.addEventListener('click', ()=>{
      jobDismissed = true;
      el.classList.add('hidden');
    });
    jobPanel = el;
    return el;
  };
  const showJob = (title, body='')=>{
    const el = ensureJobPanel();
    if (jobDismissed) return;
    el.querySelector('.llc-job-panel-title').textContent = title || 'Working…';
    el.querySelector('.llc-job-panel-body').textContent = body || '';
    el.classList.remove('hidden');
  };
  const hideJob = ()=>{
    const el = ensureJobPanel();
    el.classList.add('hidden');
  };

  async function api(action, data=null, options={}){
    const url = `api.php?action=${encodeURIComponent(action)}`;
    const init = { method: data==null ? 'GET':'POST', headers:{} };
    if (options && options.signal) init.signal = options.signal;
    if (data!=null){
      init.headers['Content-Type']='application/json';
      init.body = JSON.stringify(data);
    }
    const res = await fetch(url, init);
    const ct = res.headers.get('content-type') || '';
    if (!res.ok){
      let msg = `${res.status} ${res.statusText}`;
      let errData = null;
      try{
        if (ct.includes('application/json')) {
          errData = await res.json();
          msg = errData?.error || msg;
        } else {
          msg = await res.text();
        }
      }catch(_){}
      if (res.status===401 && typeof window.llcShowLogin==='function'){
        window.llcShowLogin(msg || 'Unauthorized');
      }
      const err = new Error(msg);
      err.status = res.status;
      err.data = errData;
      throw err;
    }
    return ct.includes('application/json') ? res.json() : res.text();
  }

  let localLightAIInitPromise = null;
  function initLocalLightAI(config){
    if (!config || !config.enabled || !config.can_control) return;
    if (localLightAIInitPromise) return;
    localLightAIInitPromise = import('./locallightai.js?v=3e2')
      .then(mod => mod.initLocalLightAI({ config, api }))
      .catch(err => console.error('LocalLightAI integration failed to initialize:', err));
  }

  async function deleteStoredFileWithForce(id){
    try {
      return await api('file_delete', {id:String(id || '')});
    } catch (err) {
      if (!err?.data?.can_force_delete) throw err;
      const detail = String(err?.data?.rag_error || err?.message || 'The RAG index could not be deleted.');
      const ok = confirm(`The RAG index could not be deleted:

${detail}

Delete the local file anyway? A stale index may remain in ragd.`);
      if (!ok) {
        const cancelled = new Error('Deletion cancelled');
        cancelled.cancelled = true;
        throw cancelled;
      }
      return api('file_delete', {id:String(id || ''), force:true});
    }
  }

  
  // ---------- Login ----------
  function setupLogin(){
    const modal = document.getElementById('login-modal');
    if (!modal) return;
    const form = modal.querySelector('form');
    // Avoid Chrome password-manager heuristics by not keying off name="password" fields.
    const ident = modal.querySelector('#login-identifier');
    const pass  = modal.querySelector('#login-password');
    const err = modal.querySelector('.login-error');
    const btn = modal.querySelector('button[type="submit"]');
    const hint = modal.querySelector('#login-hint');
    let setupRequired = false;

    const applyAuthState = (auth={})=>{
      setupRequired = !!auth?.initial_admin_setup_required;
      const showDefault = !!auth?.show_default_admin_hint;

      if (ident) ident.disabled = setupRequired;
      if (pass) pass.disabled = setupRequired;
      if (btn) btn.disabled = setupRequired;

      if (hint){
        if (setupRequired){
          hint.textContent = 'Initial administrator password required. Set LLC_INITIAL_ADMIN_PASSWORD in config.php and reload.';
          hint.classList.remove('hidden');
        } else if (showDefault){
          hint.innerHTML = 'Default: <b>admin</b> / <b>admin</b>';
          hint.classList.remove('hidden');
        } else {
          hint.textContent = '';
          hint.classList.add('hidden');
        }
      }
    };

    const show = (msg='')=>{
      modal.classList.remove('hidden');
      if (err) err.textContent = msg || '';
      if (ident) ident.focus();
    };
    const hide = ()=>{
      modal.classList.add('hidden');
      if (pass) pass.value = '';
      if (err) err.textContent = '';
    };

    window.llcShowLogin = show;
    window.llcHideLogin = hide;
    window.llcSetAuthState = applyAuthState;

    form?.addEventListener('submit', async (e)=>{
      e.preventDefault();
      if (setupRequired) return;
      const identifier = String(ident?.value || '').trim();
      const password = String(pass?.value || '');
      if (!identifier || !password){
        if (err) err.textContent = 'Please enter username/email and password.';
        return;
      }
      if (btn) btn.disabled = true;
      if (err) err.textContent = '';
      try{
        // Use a neutral field name; backend accepts both {password} and {secret}.
        await api('auth_login', { identifier, secret: password });
        location.reload();
      }catch(ex){
        if (err) err.textContent = ex?.message || 'Login fehlgeschlagen';
      }finally{
        if (btn) btn.disabled = setupRequired;
      }
    });
  }

  const state = {
    folders: [],
    chats: [],
    templates: [],
    currentChat: null,
    connections: [],
    users: [],
    user: null,
    models: [],
    ui: { model:'', connectionId:'', systemPrompt:'', ragAvailable:false, ragAutoEnable:false, ragUrl:'', ragTopK:8, ragTimeoutSec:180, ragDefaultMode:'hybrid', webPreferAttachments:false, mediaImageInline:true, mediaAudioInline:false, uploadHardLimitMb:50, mediaImageInlineLimitMb:8, mediaAudioInlineLimitMb:15, pdfMemorySaving:false, agentActivityMode:'tail', agentActivityMaxTokens:1000, agentCompactAboveTokens:100000, agentCompactKeepToolRounds:6, agentCompactEmergencyEnabled:false, agentCompactModelKey:'__current__', agentCompactReasoningNone:true, webAutoEnable:false, webSearchAutoEnable:false, webAllowPrivate:false, webFetchMaxChars:50000, webToolMaxChars:60000, searchProvider:'serper', serperApiKey:'', braveApiKey:'', exaApiKey:'', searchCustomUrl:'', searchCustomNewsUrl:'', searchCustomAllowPrivate:false, searchCustomApiKey:'', searchNgxUrl:'', searchNgxAllowPrivate:false, searchNgxApiKey:'', searchGl:'us', searchHl:'en', searchNum:10, imageProvider:'openai', imageBaseUrl:'https://api.openai.com/v1', imageApiKey:'', imageModel:'gpt-image-2', imageOpenaiModels:[], imageOpenaiModelsBusy:false, imageOpenaiModelsError:'', imageOpenrouterBaseUrl:'https://openrouter.ai/api/v1', imageOpenrouterApiKey:'', imageOpenrouterModel:'google/gemini-3-pro-image-preview', imageOpenrouterModels:[], imageOpenrouterModelsBusy:false, imageComfyProfiles:[], imageComfyProfileId:'', imageSettingsMode:'generation', imageEditComfyProfiles:[], imageEditComfyProfileId:'', imageEditComfyUrl:'', imageEditComfyWorkflow:'', imageEditComfyBindings:'', imageEditComfySeed:-1, imageEditComfySteps:20, imageEditComfyGuidance:3.5, imageEditComfyWidth:1024, imageEditComfyHeight:1024, imageEditComfyBatch:1, imageEditComfyMegapixels:1, imageEditComfyTimeout:900, imageEditComfyApplyDefaults:false, imageAutoEnable:false, imageSize:'auto', imageQuality:'auto', imageBackground:'auto', imageOutputFormat:'png', visionAutoAttachLastImage:true, voiceApiKey:'', voiceAutoEnable:false, voiceAutoSend:true, voiceTtsProvider:'browser', voiceTtsModel:'gpt-4o-mini-tts', voiceTtsVoice:'marin', usersShowAll:false, pricing: [], customTools: [], customToolsJson: '[]', customToolsAutoEnable:false, mcpServers: [], mcpServersJson: '[]', mcpServersAutoEnable:false, mcpContextMode:'externalize', mcpExternalizeAboveTokens:6000, mcpPreviewMaxTokens:2500, mcpFullFirstPassMaxTokens:32000, modelCapabilityOverrides:{} },
    defaults: { systemPrompt:'' },
    loadingChat: false,
    attachments: [],
    webtools: { web: false, search: false, rag: false, rag_mode: 'default', image: false, document: false, code_workspace: false, workspace_id: '', workspace_name: '', workspace_access: 'write', workspace_strategy: 'efficient', workspace_offer_download: true, custom_tools: [], mcp_servers: [] },
    ragActivity: null,
    ragCapabilities: new Map(), // chat_id -> lazy /v1/status capability snapshot; no polling
    ragCapabilityPending: new Map(),
    workspaces: [],
    webFetchBusy: false,
    autoscroll: true,
    // Streaming state is per-chat. Multiple chats may stream in parallel.
    streams: new Map(), // chat_id -> { controller, assistantIdx, startedAt, promptTok, statsT0 }
    chatCache: new Map(), // chat_id -> full chat object (keeps unsaved/streaming tokens safe)
    sidebarSearch: { q:'', results:null, loading:false, nonce:0 },
    sidebarSelection: { ids: new Set(), anchorId: null },
    modelFilter: '',
    modelPickTarget: null, // e.g. { type:'pricing', idx:n }
    perms: { canCreateConnections: true, inheritGlobalConnections: true, inheritGlobalWeb: false, inheritGlobalSearch: false, inheritGlobalImage: false, inheritGlobalVoice: false },
  };

  const routerDismissedLoads = new Set();
  let routerModelsRefreshTimer = null;
  let routerEventSource = null;
  let routerEventConnectionId = '';
  let routerEventReady = false;
  const routerEventDisabled = new Set();
  const routerEventReadyWaiters = new Set();

  // Persist per-chat settings (system prompt + sampling params)
  let scheduleMetaSave = () => {};


  // ---------- DOM ----------
  const chatList = $('#chat-list');
  const chatMsgs = $('#chat-messages');
  const emptyChatMsg = $('#chat-empty');
  const newChatBtn = $('#new-chat') || $('.new-chat-btn');
  const newChatDdBtn = $('#new-chat-dd');
  const newChatMenu = $('#new-chat-menu');
  const templateMenuList = $('#template-menu-list');
  const templateMenuEmpty = $('#template-menu-empty');
  const newFolderBtn = $('#new-folder') || $('.new-folder-btn');
  const sidebarSearch = $('#sidebar-search');
  const sidebarSearchClear = $('#sidebar-search-clear');

  // ---------- Mobile: off-canvas sidebar toggle
  const sidebarEl = $('.sidebar');
  const sidebarToggleBtn = $('#sidebar-toggle');
  const sidebarBackdrop = $('#sidebar-backdrop');
  const isMobile = () => window.matchMedia && window.matchMedia('(max-width:768px)').matches;
  const openSidebar = () => {
    if (!sidebarEl) return;
    sidebarEl.classList.add('open');
    sidebarBackdrop?.classList.add('show');
    sidebarToggleBtn?.setAttribute('aria-expanded', 'true');
  };
  const closeSidebar = () => {
    if (!sidebarEl) return;
    sidebarEl.classList.remove('open');
    sidebarBackdrop?.classList.remove('show');
    sidebarToggleBtn?.setAttribute('aria-expanded', 'false');
  };
  const toggleSidebar = () => {
    if (!sidebarEl) return;
    sidebarEl.classList.contains('open') ? closeSidebar() : openSidebar();
  };

  sidebarToggleBtn?.addEventListener('click', (e)=>{ e.preventDefault(); toggleSidebar(); });
  sidebarBackdrop?.addEventListener('click', ()=> closeSidebar());
  document.addEventListener('keydown', (e)=>{ if (e.key === 'Escape') closeSidebar(); });
  window.addEventListener('resize', ()=>{ if (!isMobile()) closeSidebar(); }, { passive:true });

  // Auto-close sidebar after selecting something (mobile)
  on('click', '.chat-item', (e)=>{ if (isMobile() && !(e.ctrlKey||e.metaKey||e.shiftKey)) closeSidebar(); });
  on('click', '#new-chat, #new-chat-dd, #new-folder', ()=>{ if (isMobile()) closeSidebar(); });

  const textarea = $('.input-textarea');
  const stopBtn = $('.stop-btn');
  const sendBtn = $('.send-btn');
  const voiceBtn = $('#voice-btn');
  const chatArea = $('.chat-area');

  // Chromium can focus overflow scrollers when PageUp/PageDown, ArrowUp/ArrowDown
  // or Home/End is used. On very large chats that native path may trigger an
  // expensive focus/scroll repaint loop (visible as a white focus ring around
  // the chat viewport). Handle vertical chat navigation ourselves when the
  // page/chat viewport owns the key so the browser never enters that path.
  // Form controls and nested scroll areas keep their native keyboard behaviour.
  document.addEventListener('keydown', (e)=>{
    const isPageKey = e.key === 'PageUp' || e.key === 'PageDown';
    const isArrowKey = e.key === 'ArrowUp' || e.key === 'ArrowDown';
    const isEdgeKey = e.key === 'Home' || e.key === 'End';
    if (e.defaultPrevented || (!isPageKey && !isArrowKey && !isEdgeKey)) return;
    if (e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return;
    if (!chatArea || chatArea.scrollHeight <= chatArea.clientHeight + 1) return;

    const active = document.activeElement;
    const target = e.target;
    const ownsChatNavKey =
      active === document.body || active === document.documentElement || active === chatArea ||
      target === document.body || target === document.documentElement || target === chatArea;
    if (!ownsChatNavKey) return;

    // Don't move the background conversation while a modal/drawer is open.
    if (document.querySelector('.modal.open, .drawer.open')) return;

    e.preventDefault();
    if (active === chatArea) chatArea.blur();

    const maxScrollTop = Math.max(0, chatArea.scrollHeight - chatArea.clientHeight);
    if (isEdgeKey) {
      chatArea.scrollTop = e.key === 'Home' ? 0 : maxScrollTop;
      return;
    }

    const distance = isPageKey
      ? Math.max(80, Math.floor(chatArea.clientHeight * 0.88))
      : 48;
    const down = e.key === 'PageDown' || e.key === 'ArrowDown';
    const delta = down ? distance : -distance;
    chatArea.scrollTop = Math.max(0, Math.min(
      maxScrollTop,
      chatArea.scrollTop + delta
    ));
  }, {capture:true});

  const modelBtn = $('#model-btn');
  const modelMenu = $('#model-menu');
  const modelList = $('#model-list');
  const modelSearch = $('#model-search');
  const modelSearchClear = $('#model-search-clear');
  const modelImageCapability = $('#model-image-capability');
  const modelImageCapabilityDetected = $('#model-image-capability-detected');

  const kebabBtn = $('#header-kebab');
  const kebabMenu = $('#header-kebab-menu');

  const settingsModal = $('#settings-modal');
  const settingsBackdrop = $('#settings-backdrop');
  const settingsClose = $('#settings-close');

  const settingPdfMemorySaving = $('#setting-pdf-memory-saving');
const settingToolSimpleMaxIters = $('#setting-tool-simple-max-iters');
const settingToolAgenticMaxIters = $('#setting-tool-agentic-max-iters');
const settingAgentActivityMode = $('#setting-agent-activity-mode');
const settingAgentActivityMaxTokens = $('#setting-agent-activity-max-tokens');
const settingAgentCompactAboveTokens = $('#setting-agent-compact-above-tokens');
const settingAgentCompactKeepToolRounds = $('#setting-agent-compact-keep-tool-rounds');
const settingAgentCompactEmergencyEnabled = $('#setting-agent-compact-emergency-enabled');
const settingAgentCompactModel = $('#setting-agent-compact-model');
const settingAgentCompactReasoningNone = $('#setting-agent-compact-reasoning-none');
const settingAgentSupervisorEveryToolCalls = $('#setting-agent-supervisor-every-tool-calls');
const settingAgentSupervisorModel = $('#setting-agent-supervisor-model');
const settingUploadHardLimitMb = $('#setting-upload-hard-limit-mb');
const settingMediaImageInlineLimitMb = $('#setting-media-image-inline-limit-mb');
const settingMediaAudioInlineLimitMb = $('#setting-media-audio-inline-limit-mb');
const archiveOldRootDays = $('#archive-old-root-days');
const archiveOldRootBtn = $('#archive-old-root-btn');
const archiveOldRootStatus = $('#archive-old-root-status');
const settingCustomToolsJson = $('#setting-custom-tools-json');
const settingCustomToolsAutoEnable = $('#setting-custom-tools-auto-enable');
const settingCustomToolsFormat = $('#setting-custom-tools-format');
const settingCustomToolsStatus = $('#setting-custom-tools-status');
const customToolAddBtn = $('#custom-tool-add-btn');
const customToolsList = $('#custom-tools-list');
const customToolsEmpty = $('#custom-tools-empty');
const customToolEditorModal = $('#custom-tool-editor-modal');
const customToolEditorClose = $('#custom-tool-editor-close');
const customToolEditorCancel = $('#custom-tool-editor-cancel');
const customToolEditorApply = $('#custom-tool-editor-apply');
const customToolEditorResult = $('#custom-tool-editor-result');
const customToolEditIndex = $('#custom-tool-edit-index');
const customToolEditTitle = $('#custom-tool-edit-title');
const customToolEditName = $('#custom-tool-edit-name');
const customToolEditDescription = $('#custom-tool-edit-description');
const customToolEditMethod = $('#custom-tool-edit-method');
const customToolEditEndpoint = $('#custom-tool-edit-endpoint');
const customToolEditAllowPrivate = $('#custom-tool-edit-allow-private');
const customToolHeaderAdd = $('#custom-tool-header-add');
const customToolHeaderList = $('#custom-tool-header-list');
const customToolNoHeaders = $('#custom-tool-no-headers');
const customToolParameterAdd = $('#custom-tool-parameter-add');
const customToolParameterList = $('#custom-tool-parameter-list');
const customToolNoParameters = $('#custom-tool-no-parameters');
const customToolBodyCard = $('#custom-tool-body-card');
const customToolEditBodyMode = $('#custom-tool-edit-body-mode');
const customToolBodyModeHint = $('#custom-tool-body-mode-hint');
const customToolBodyTemplateWrap = $('#custom-tool-body-template-wrap');
const customToolEditBodyTemplate = $('#custom-tool-edit-body-template');
const customToolEditId = $('#custom-tool-edit-id');
const customToolEditTimeout = $('#custom-tool-edit-timeout');
const settingMcpServersJson = $('#setting-mcp-servers-json');
const settingMcpServersAutoEnable = $('#setting-mcp-servers-auto-enable');
const settingMcpServersFormat = $('#setting-mcp-servers-format');
const settingMcpServersTest = $('#setting-mcp-servers-test');
const settingMcpServersStatus = $('#setting-mcp-servers-status');
const settingMcpContextMode = $('#setting-mcp-context-mode');
const settingMcpExternalizeAbove = $('#setting-mcp-externalize-above');
const settingMcpPreviewMax = $('#setting-mcp-preview-max');
const settingMcpFullPassMax = $('#setting-mcp-full-pass-max');
const settingMcpContextStatus = $('#setting-mcp-context-status');
const mcpContextLimits = $('#mcp-context-limits');
const mcpAddBtn = $('#mcp-add-btn');
const mcpList = $('#mcp-list');
const mcpEmpty = $('#mcp-empty');
const mcpEditorModal = $('#mcp-editor-modal');
const mcpEditorClose = $('#mcp-editor-close');
const mcpEditorCancel = $('#mcp-editor-cancel');
const mcpEditorSave = $('#mcp-editor-save');
const mcpEditorTest = $('#mcp-editor-test');
const mcpEditorResult = $('#mcp-editor-result');
const mcpEditIndex = $('#mcp-edit-index');
const mcpEditName = $('#mcp-edit-name');
const mcpEditId = $('#mcp-edit-id');
const mcpEditUrl = $('#mcp-edit-url');
const mcpEditDescription = $('#mcp-edit-description');
const mcpEditAuthEnabled = $('#mcp-edit-auth-enabled');
const mcpEditTokenWrap = $('#mcp-edit-token-wrap');
const mcpEditToken = $('#mcp-edit-token');
const mcpTokenReveal = $('#mcp-token-reveal');
const mcpEditAllowPrivate = $('#mcp-edit-allow-private');
const mcpHeaderAdd = $('#mcp-header-add');
const mcpHeaderList = $('#mcp-header-list');
const mcpNoHeaders = $('#mcp-no-headers');
const mcpEditProtocol = $('#mcp-edit-protocol');
const mcpEditTimeout = $('#mcp-edit-timeout');
const mcpEditMaxResponse = $('#mcp-edit-max-response');
const mcpEditFollowExecJobs = $('#mcp-edit-follow-exec-jobs');
const generalSuperNote = $('#general-superadmin-note');
const settingWebAutoEnable = $('#setting-web-auto-enable');
const settingWebSearchAutoEnable = $('#setting-websearch-auto-enable');
const settingWebAllowPrivate = $('#setting-web-allow-private');
const settingWebPreferAtt = $('#setting-web-prefer-attachments');
const settingMediaImageInline = $('#setting-media-image-inline');
const settingMediaAudioInline = $('#setting-media-audio-inline');
const settingWebFetchMaxChars = $('#setting-web-fetch-max-chars');
const settingWebToolMaxChars = $('#setting-web-tool-max-chars');
const webInheritNote = $('#web-inherit-note');

// Search settings (Settings → Search)
const settingSearchProvider = $('#setting-search-provider');
const searchInheritNote = $('#search-inherit-note');
const settingSerperKey = $('#setting-serper-api-key');
const settingBraveKey = $('#setting-brave-api-key');
const settingExaKey = $('#setting-exa-api-key');
const settingSearchCustomUrl = $('#setting-search-custom-url');
const settingSearchCustomNewsUrl = $('#setting-search-custom-news-url');
const searchCustomNewsWrap = $('#search-custom-news-wrap');
const settingSearchCustomAllowPrivate = $('#setting-search-custom-allow-private');
const settingSearchCustomKey = $('#setting-search-custom-api-key');
const settingSearchNgxUrl = $('#setting-searchngx-url');
const settingSearchNgxAllowPrivate = $('#setting-searchngx-allow-private');
const settingSearchNgxKey = $('#setting-searchngx-api-key');
const settingSearchGl = $('#setting-search-gl');
const settingSearchHl = $('#setting-search-hl');
const settingSearchNum = $('#setting-search-num');
const searchCustomHint = $('#search-custom-hint');
const searchSerperFields = $('#search-serper-fields');
const searchBraveFields = $('#search-brave-fields');
const searchExaFields = $('#search-exa-fields');
const searchCustomFields = $('#search-custom-fields');
const searchNgxFields = $('#search-searchngx-fields');

// RAG settings (Settings → RAG)
const ragSuperNote = $('#rag-superadmin-note');
const settingRagAutoEnable = $('#setting-rag-auto-enable');
const settingRagUrl = $('#setting-rag-url');
const settingRagTopK = $('#setting-rag-top-k');
const settingRagTimeoutSec = $('#setting-rag-timeout-sec');
const settingRagDefaultMode = $('#setting-rag-default-mode');
const settingRagTest = $('#setting-rag-test');
const settingRagStatus = $('#setting-rag-status');

// Image settings (Settings → Image)
const settingImageAutoEnable = $('#setting-image-auto-enable');
const settingVisionAutoAttachLastImage = $('#setting-vision-auto-attach-last-image');
const settingImageProvider = $('#setting-image-provider');
const settingImageBaseUrl = $('#setting-image-base-url');
const settingImageApiKey = $('#setting-image-api-key');
const settingImageModel = $('#setting-image-model');
const settingImageModelsRefresh = $('#setting-image-models-refresh');
const settingImageModelsStatus = $('#setting-image-models-status');
const settingImageOpenrouterBaseUrl = $('#setting-image-openrouter-base-url');
const settingImageOpenrouterApiKey = $('#setting-image-openrouter-api-key');
const settingImageOpenrouterModel = $('#setting-image-openrouter-model');
const settingImageOpenrouterModelsRefresh = $('#setting-image-openrouter-models-refresh');
const settingImageOpenrouterModelsStatus = $('#setting-image-openrouter-models-status');
const imageSdCppFields = $('#image-sdcpp-fields');
const settingImageSdCppBaseUrl = $('#setting-image-sdcpp-base-url');
const settingImageSdCppApiKey = $('#setting-image-sdcpp-api-key');
const settingImageSdCppModel = $('#setting-image-sdcpp-model');
const settingImageSdCppNegativePrompt = $('#setting-image-sdcpp-negative-prompt');
const settingImageSdCppWidth = $('#setting-image-sdcpp-width');
const settingImageSdCppHeight = $('#setting-image-sdcpp-height');
const settingImageSdCppBatch = $('#setting-image-sdcpp-batch');
const settingImageSdCppSeed = $('#setting-image-sdcpp-seed');
const settingImageSdCppSteps = $('#setting-image-sdcpp-steps');
const settingImageSdCppCfgScale = $('#setting-image-sdcpp-cfg-scale');
const settingImageSdCppGuidance = $('#setting-image-sdcpp-guidance');
const settingImageSdCppSamplingMethod = $('#setting-image-sdcpp-sampling-method');
const settingImageSdCppScheduler = $('#setting-image-sdcpp-scheduler');
const settingImageSdCppFlowShift = $('#setting-image-sdcpp-flow-shift');
const settingImageSdCppExtraArgs = $('#setting-image-sdcpp-extra-args');
const settingImageSdCppTimeout = $('#setting-image-sdcpp-timeout');
const settingImageSdCppAutoVaeTiling768 = $('#setting-image-sdcpp-auto-vae-tiling-768');
const settingImageSize = $('#setting-image-size');
const settingImageQuality = $('#setting-image-quality');
const settingImageBackground = $('#setting-image-background');
const settingImageOutputFormat = $('#setting-image-output-format');
const imageInheritNote = $('#image-inherit-note');

// Voice settings
const voiceInheritNote = $('#voice-inherit-note');
const settingVoiceApiKey = $('#setting-voice-api-key');
const settingVoiceAutoEnable = $('#setting-voice-auto-enable');
const settingVoiceAutoSend = $('#setting-voice-auto-send');

// Voice TTS (read aloud) settings
const settingVoiceTtsProvider = $('#setting-voice-tts-provider');
const settingVoiceTtsModel = $('#setting-voice-tts-model');
const settingVoiceTtsVoice = $('#setting-voice-tts-voice');
const voiceTtsOpenaiFields = $('#voice-tts-openai-fields');


// ComfyUI image settings (Settings → Image)
const imageOpenaiFields = $('#image-openai-fields');
const imageOpenrouterFields = $('#image-openrouter-fields');
const imageComfyFields = $('#image-comfyui-fields');
const settingImageComfyProfile = $('#setting-image-comfyui-profile');
const settingImageComfyProfileNew = $('#setting-image-comfyui-profile-new');
const settingImageComfyProfileDuplicate = $('#setting-image-comfyui-profile-duplicate');
const settingImageComfyProfileRename = $('#setting-image-comfyui-profile-rename');
const settingImageComfyProfileDelete = $('#setting-image-comfyui-profile-delete');
const settingImageComfyUrl = $('#setting-image-comfyui-url');
const settingImageComfyWorkflow = $('#setting-image-comfyui-workflow');
const settingImageComfyBindings = $('#setting-image-comfyui-bindings');
const settingImageComfyAutodetect = $('#setting-image-comfyui-autodetect');
const settingImageComfySeed = $('#setting-image-comfyui-seed');
const settingImageComfySteps = $('#setting-image-comfyui-steps');
const settingImageComfyGuidance = $('#setting-image-comfyui-guidance');
const settingImageComfyWidth = $('#setting-image-comfyui-width');
const settingImageComfyHeight = $('#setting-image-comfyui-height');
const settingImageComfyBatch = $('#setting-image-comfyui-batch');
const settingImageComfyTimeout = $('#setting-image-comfyui-timeout');
const settingImageComfyApplyDefaults = $('#setting-image-comfyui-apply-defaults');
const imageGenerationSettings = $('#image-generation-settings');
const imageEditingSettings = $('#image-editing-settings');
const settingImageModeGeneration = $('#setting-image-mode-generation');
const settingImageModeEditing = $('#setting-image-mode-editing');
const settingImageEditComfyProfile = $('#setting-image-edit-comfyui-profile');
const settingImageEditComfyProfileNew = $('#setting-image-edit-comfyui-profile-new');
const settingImageEditComfyProfileDuplicate = $('#setting-image-edit-comfyui-profile-duplicate');
const settingImageEditComfyProfileRename = $('#setting-image-edit-comfyui-profile-rename');
const settingImageEditComfyProfileDelete = $('#setting-image-edit-comfyui-profile-delete');
const settingImageEditComfyUrl = $('#setting-image-edit-comfyui-url');
const settingImageEditComfyWorkflow = $('#setting-image-edit-comfyui-workflow');
const settingImageEditComfyBindings = $('#setting-image-edit-comfyui-bindings');
const settingImageEditComfyAutodetect = $('#setting-image-edit-comfyui-autodetect');
const settingImageEditComfySeed = $('#setting-image-edit-comfyui-seed');
const settingImageEditComfySteps = $('#setting-image-edit-comfyui-steps');
const settingImageEditComfyGuidance = $('#setting-image-edit-comfyui-guidance');
const settingImageEditComfyWidth = $('#setting-image-edit-comfyui-width');
const settingImageEditComfyHeight = $('#setting-image-edit-comfyui-height');
const settingImageEditComfyBatch = $('#setting-image-edit-comfyui-batch');
const settingImageEditComfyMegapixels = $('#setting-image-edit-comfyui-megapixels');
const settingImageEditComfyTimeout = $('#setting-image-edit-comfyui-timeout');
const settingImageEditComfyApplyDefaults = $('#setting-image-edit-comfyui-apply-defaults');


  const connList = $('#conn-list');
  const connEmpty = $('#conn-empty');
  const connAddBtn = $('#conn-add-btn');
  const connForm = $('#conn-form');
  const connId = $('#conn-id');
  const connLabel = $('#conn-label');
  const connUrl = $('#conn-url');
  const connPrefix = $('#conn-prefix');
  const connKey = $('#conn-key');
  const connHeaders = $('#conn-headers');
  const connNotes = $('#conn-notes');
  const connCancel = $('#conn-cancel-btn');
  const connTestBtn = $('#conn-test-btn');
  const connTestResult = $('#conn-test-result');
  const connSaveBtn = $('#conn-save-btn');

  // Pricing (Settings → Pricing)
  const pricingListEl = $('#pricing-list');
  const pricingAddBtn = $('#pricing-add');


// Users (Settings → Users)
const userSelfUsername = $('#user-self-username');
const userSelfRole = $('#user-self-role');
const userSelfEmail = $('#user-self-email');
const userSelfSaveEmail = $('#user-self-save-email');
const userSelfCurPw = $('#user-self-current-password');
const userSelfNewPw = $('#user-self-new-password');
const userSelfNewPw2 = $('#user-self-new-password2');
const userSelfSavePw = $('#user-self-save-password');
const userSelfMsg = $('#user-self-msg');

const usersAdminWrap = $('#users-admin-wrap');
const usersList = $('#users-list');
const usersEmpty = $('#users-empty');
const userCreateBtn = $('#user-create-btn');
const userCreateForm = $('#user-create-form');
const userCreateUsername = $('#user-create-username');
const userCreateEmail = $('#user-create-email');
const userCreatePassword = $('#user-create-password');
const userCreateAdmin = $('#user-create-admin');
const userCreateInherit = $('#user-create-inherit');
const userCreateSearchInherit = $('#user-create-search-inherit');
const userCreateWebInherit = $('#user-create-web-inherit');
const userCreateImageInherit = $('#user-create-image-inherit');
const userCreateVoiceInherit = $('#user-create-voice-inherit');
const userCreateOwn = $('#user-create-own');
const userCreateSave = $('#user-create-save');
const userCreateCancel = $('#user-create-cancel');
const userCreateMsg = $('#user-create-msg');

  const drawer = $('#controls-drawer');
  const drawerOpen = $('#controls-open');
  const drawerClose = $('#controls-close');
  const drawerBackdrop = $('#drawer-backdrop');

  const systemPromptEl = $('.accordion textarea');

  // Status bar (token metrics)
  const statusPromptTokEl = $('#status-tokens-prompt');
  const statusCompletionTokEl = $('#status-tokens-completion');
  const statusContextEl = $('#status-context-window');
  const statusCostEl = $('#status-cost');
  const statusSpeedEl = $('#status-speed');

  // Pricing is user-configurable (Settings → Pricing) and differs by provider/model.
  // We intentionally do NOT fall back to a heuristic when no price is configured.
  const estTok = (s)=> Math.ceil(String(s||'').length / 4);
  const estTokFromContent = (content)=>{
    if (typeof content === 'string') return estTok(content);
    if (Array.isArray(content)) {
      let t = 0;
      for (const p of content) {
        if (!p) continue;
        if (typeof p === 'string') { t += estTok(p); continue; }

        // Common structured parts (OpenAI/Anthropic-style)
        if (typeof p.text === 'string') { t += estTok(p.text); continue; }
        if (typeof p.url === 'string')  { t += estTok(p.url);  continue; }

        // Some payloads nest content again
        if (typeof p.content === 'string') { t += estTok(p.content); continue; }
        if (Array.isArray(p.content)) { t += estTokFromContent(p.content); continue; }

        // images are ignored; urls/text counted roughly via length/4
      }
      return t;
    }
    return 0;
  };
  const estTokFromAttachments = (atts)=>{
    if (!Array.isArray(atts) || atts.length===0) return 0;
    let t = 0;
    for (const a of atts) {
      if (!a || typeof a !== 'object') continue;
      const type = String(a.type || '');
      if (type === 'image') {
        // Images: don't estimate tokens (varies wildly by backend and encoding)
        continue;
      }
      else if (type === 'text') {
        const name = String(a.name || 'text');
        const mime = String(a.mime || 'text/plain');
        const src = String(a.url || '');
        const prefix = `File: ${name} (${mime})${src?`\nSource: ${src}`:''}\n\n`;
        t += estTok(prefix) + estTok(String(a.text || ''));
      }
      else if (type === 'url') {
        const u = String(a.url || '');
        if (u.trim()) t += estTok(`Link: ${u}`);
      }
      else if (type === 'note') {
        const n = String(a.text || '');
        if (n.trim()) t += estTok(`Note: ${n}`);
      }
      else if ((type === 'file') && a.name) {
        const name = String(a.name || '');
        const mime = String(a.mime || '');
        // Image files: ignore token estimation entirely.
        const isImg = (mime.startsWith('image/') || /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(name));
        if (isImg) continue;
        const label = (mime==='application/pdf' || name.toLowerCase().endsWith('.pdf')) ? 'PDF attached' : 'Attachment';
        t += estTok(`${label}: ${name} (not processed yet)`);
      }
    }
    return t;
  };

  const fmtUsd = (usd)=>{
    const v = Number(usd) || 0;
    if (!isFinite(v)) return '0.0000';
    const a = Math.abs(v);
    if (a < 0.01) return v.toFixed(4);
    if (a < 0.1) return v.toFixed(3);
    return v.toFixed(2);
  };

  const pricingKey = (cid, mid)=> `${String(cid||'')}::${String(mid||'')}`;
  const getPricing = (cid, mid)=>{
    const c = String(cid||'').trim();
    const m = String(mid||'').trim();
    if (!c || !m) return null;
    const list = Array.isArray(state.ui?.pricing) ? state.ui.pricing : [];
    for (const r of list){
      if (!r || typeof r !== 'object') continue;
      if (String(r.connection_id||'') === c && String(r.model||'') === m){
        const pp = Number(r.prompt_price);
        const gp = Number(r.gen_price);
        if (!Number.isFinite(pp) || !Number.isFinite(gp)) return null;
        if (pp < 0 || gp < 0) return null;
        return { prompt_price: pp, gen_price: gp };
      }
    }
    return null;
  };

  const calcPrice = (promptTok, completionTok, cid, mid)=>{
    const pr = getPricing(cid, mid);
    if (!pr) return null;
    const pt = Number(promptTok) || 0;
    const ct = Number(completionTok) || 0;
    const usd = (pt * pr.prompt_price + ct * pr.gen_price) / 1_000_000;
    if (!isFinite(usd)) return null;
    return usd;
  };

  // ---- Real usage aggregation (prefer backend stats over rough estimates) ----
  const msgUsage = (m)=>{
    if (!m || m.role !== 'assistant') return null;
    const met = (m.metrics && typeof m.metrics === 'object') ? m.metrics : null;
    const ptRaw = met && Number.isFinite(Number(met.prompt_tokens)) ? Number(met.prompt_tokens) : null;
    const ctRaw = met && Number.isFinite(Number(met.completion_tokens)) ? Number(met.completion_tokens) : null;
    const ttRaw = met && Number.isFinite(Number(met.total_tokens)) ? Number(met.total_tokens) : null;
    if (ptRaw === null && ctRaw === null && ttRaw === null) return null;
    const prompt = (ptRaw !== null) ? ptRaw : 0;
    const completion = (ctRaw !== null) ? ctRaw : 0;
    const total = (ttRaw !== null) ? ttRaw : (prompt + completion);
    return { prompt, completion, total, hasPrompt: (ptRaw !== null) };
  };

  // Sum completion/total tokens across the whole chat, but treat prompt tokens as the
  // *current/last* prompt (not "billed prompt"). This keeps P meaningful even with Regenerate.
  const sumChatUsage = (chat, opts={})=>{
    const excludeIdx = (opts && opts.excludeIdx != null) ? Number(opts.excludeIdx) : null;
    let lastP = null;
    let C = 0, T = 0, any = false;
    const msgs = chat?.messages || [];
    for (let i=0; i<msgs.length; i++){
      if (excludeIdx != null && i === excludeIdx) continue;
      const u = msgUsage(msgs[i]);
      if (!u) continue;
      any = true;
      C += u.completion;
      T += u.total;
      if (u.hasPrompt) lastP = u.prompt;
    }
    const P = (lastP != null) ? lastP : 0;
    return { P, C, T, any };
  };


  // Sum "ever generated" tokens (completion tokens) across the chat, including
  // previous Regenerate runs stored in metrics.runs. This is chat-level and does
  // NOT decrease when messages are replaced.
  // Optionally exclude the *current* assistant idx's live completion_tokens (to avoid double-counting
  // during a just-finished generation) while still counting its historical runs.
  const sumChatEverGen = (chat, opts={})=>{
    const excludeIdx = (opts && opts.excludeIdx != null) ? Number(opts.excludeIdx) : null;
    let total = 0;
    let any = false;
    const msgs = chat?.messages || [];
    for (let i=0; i<msgs.length; i++){
      const m = msgs[i];
      if (!m || m.role !== 'assistant') continue;
      const met = (m.metrics && typeof m.metrics === 'object') ? m.metrics : null;
      if (!met) continue;

      const runs = Array.isArray(met.runs) ? met.runs : null;
      if (runs && runs.length){
        // Historical runs always count, even if this message is the excluded idx.
        for (const r of runs){
          if (!r || typeof r !== 'object') continue;
          const ct = Number(r.completion_tokens);
          if (!Number.isFinite(ct)) continue;
          any = true;
          total += ct;
        }
        continue;
      }

      // No run history: count the message's completion_tokens unless it's the excluded idx.
      if (excludeIdx != null && i === excludeIdx) continue;
      const ct = Number.isFinite(Number(met.completion_tokens)) ? Number(met.completion_tokens) : null;
      if (ct == null) continue;
      any = true;
      total += ct;
    }
    return { total, any };
  };

  const msgCost = (m, fallbackChat=null)=>{
    if (!m || m.role !== 'assistant') return null;
    const met = (m.metrics && typeof m.metrics === 'object') ? m.metrics : null;

    // If we have a run history, $ is the billed sum of all finalized runs.
    // This makes Regenerate accumulate spend instead of overwriting it.
    const runs = (met && Array.isArray(met.runs)) ? met.runs : null;
    if (runs && runs.length) {
      let sum = 0;
      let any = false;
      for (const r of runs) {
        if (!r || typeof r !== 'object') continue;
        let p = Number(r.price);
        if (!Number.isFinite(p)) {
          // If price wasn't stored (e.g. pricing added later), try to compute it now
          // from that run's model + token counts.
          const pt = Number(r.prompt_tokens);
          const ct = Number(r.completion_tokens);
          if (Number.isFinite(pt) || Number.isFinite(ct)) {
            const cid = String(r.connection_id || m.connection_id || fallbackChat?.connection_id || state.ui.connectionId || '').trim();
            const mid = String(r.model || m.model || fallbackChat?.model || '').trim();
            const usd = calcPrice(Number.isFinite(pt) ? pt : 0, Number.isFinite(ct) ? ct : 0, cid, mid);
            if (usd != null) p = usd;
          }
        }
        if (!Number.isFinite(p)) continue;
        any = true;
        sum += p;
      }
      // If at least one run had a configured price, return the billed sum.
      // Otherwise fall back to legacy behavior below.
      if (any) return sum;
    }
    const direct = met && Number.isFinite(Number(met.price)) ? Number(met.price) : null;
    if (direct != null) return direct;

    const pt = met && Number.isFinite(Number(met.prompt_tokens)) ? Number(met.prompt_tokens) : null;
    const ct = met && Number.isFinite(Number(met.completion_tokens)) ? Number(met.completion_tokens) : null;
    if (pt == null && ct == null) return null;

    const cid = String(m.connection_id || fallbackChat?.connection_id || state.ui.connectionId || '').trim();
    const mid = String(m.model || fallbackChat?.model || '').trim();
    if (!cid || !mid) return null;
    const usd = calcPrice(pt || 0, ct || 0, cid, mid);
    return (usd != null) ? usd : null;
  };

  const sumChatCost = (chat, opts={})=>{
    const excludeIdx = (opts && opts.excludeIdx != null) ? Number(opts.excludeIdx) : null;
    let usd = 0;
    let any = false;
    const msgs = chat?.messages || [];
    for (let i=0; i<msgs.length; i++){
      if (excludeIdx != null && i === excludeIdx) continue;
      const c = msgCost(msgs[i], chat);
      if (c == null) continue;
      any = true;
      usd += c;
    }
    return { usd, any };
  };

  const ensureChatBilled = (chat)=>{
    if (!chat) return null;
    chat.meta = chat.meta || {};
    if (!chat.meta.billed || typeof chat.meta.billed !== 'object') {
      chat.meta.billed = { usd: 0, any: false, runs: 0 };
    }
    const b = chat.meta.billed;
    const u = Number(b.usd);
    b.usd = Number.isFinite(u) ? u : 0;
    if (typeof b.any !== 'boolean') b.any = false;
    const r = Number(b.runs);
    b.runs = Number.isFinite(r) ? r : 0;
    return b;
  };

  // Billed spend must survive Regenerate (which truncates / replaces messages).
  // So we keep a chat-level accumulator in chat.meta.billed.
  const getChatBilledCost = (chat)=>{
    if (!chat) return { usd: 0, any: false };
    const b = (chat.meta && chat.meta.billed && typeof chat.meta.billed === 'object') ? chat.meta.billed : null;
    if (b && Number.isFinite(Number(b.usd))) return { usd: Number(b.usd), any: !!b.any };
    return sumChatCost(chat);
  };

  const chatIdKey = (id)=> String(id ?? '');
  const isChatStreaming = (id)=> {
    const k = chatIdKey(id);
    if (!k) return false;
    return state.streams.has(k);
  };
  const isCurrentChatStreaming = ()=> isChatStreaming(state.currentChat?.id);

  const computePromptTokNext = (chat)=>{
    if (!chat) return 0;
    const sp = (chat.meta?.system_prompt ?? state.defaults?.systemPrompt ?? state.ui?.systemPrompt ?? '');
    let t = estTok(sp);
    const msgs = chat.messages || [];
    for (const m of msgs) {
      if (!m || !m.role) continue;
      if (!['user','assistant','system'].includes(m.role)) continue;
      // Never count stored reasoning toward prompt tokens.
      t += estTokFromContent(m.content);
      t += estTokFromAttachments(m.attachments);
    }
    // If the last message is a placeholder assistant (empty), ignore.
    const last = msgs[msgs.length-1];
    if (last && last.role === 'assistant' && !String(last.content||'').trim() && !String(last.reasoning||'').trim()) {
      // estTokFromContent('') is 0, but keep this here for clarity.
    }
    return t;
  };

  const computeCompletionTokLast = (chat)=>{
    if (!chat) return 0;
    const msgs = chat.messages || [];
    for (let i = msgs.length - 1; i >= 0; i--) {
      const m = msgs[i];
      if (!m || m.role !== 'assistant') continue;
      const has = String(m.content||'').trim() || String(m.reasoning||'').trim();
      if (!has) continue;
      return estTok(m.content) + estTok(m.reasoning);
    }
    return 0;
  };

  const sumChatCompletionEst = (chat)=>{
    if (!chat) return 0;
    let t = 0;
    const msgs = chat.messages || [];
    for (const m of msgs){
      if (!m || m.role !== 'assistant') continue;
      const has = String(m.content||'').trim() || String(m.reasoning||'').trim();
      if (!has) continue;
      t += estTok(m.content) + estTok(m.reasoning);
    }
    return t;
  };

  // C reflects completion usage represented by the current assistant messages.
  // Prefer real completion_tokens when present (agent messages may aggregate several
  // internal model turns); fall back to a rough visible-text estimate for messages
  // that predate metrics or were imported/edited.
  const sumChatCompletionCurrent = (chat, opts={})=>{
    if (!chat) return 0;
    const excludeIdx = (opts && opts.excludeIdx != null) ? Number(opts.excludeIdx) : null;
    let t = 0;
    const msgs = chat.messages || [];
    for (let i=0; i<msgs.length; i++){
      if (excludeIdx != null && i === excludeIdx) continue;
      const m = msgs[i];
      if (!m || m.role !== 'assistant') continue;
      const met = (m.metrics && typeof m.metrics === 'object') ? m.metrics : null;
      const ct = met && Number.isFinite(Number(met.completion_tokens)) ? Number(met.completion_tokens) : null;
      if (ct != null) { t += ct; continue; }
      // Fallback: estimate from current content (keeps C responsive when deleting messages
      // that don't have stored token stats).
      const has = String(m.content||'').trim() || String(m.reasoning||'').trim();
      if (!has) continue;
      t += estTok(m.content) + estTok(m.reasoning);
    }
    return t;
  };

  const getLastRunTokens = (chat)=>{
    let pt = null, ct = null;
    const meta = chat?.meta && typeof chat.meta === 'object' ? chat.meta : null;
    if (meta){
      const p = Number(meta.last_prompt_tok);
      const c = Number(meta.last_completion_tok);
      if (Number.isFinite(p)) pt = p;
      if (Number.isFinite(c)) ct = c;
    }
    const msgs = chat?.messages || [];
    if (pt == null || ct == null){
      for (let i = msgs.length - 1; i >= 0; i--){
        const m = msgs[i];
        if (!m || m.role !== 'assistant') continue;
        const met = (m.metrics && typeof m.metrics === 'object') ? m.metrics : null;
        if (!met) continue;
        if (pt == null){
          const p = Number(met.prompt_tokens);
          if (Number.isFinite(p)) pt = p;
        }
        if (ct == null){
          const c = Number(met.completion_tokens);
          if (Number.isFinite(c)) ct = c;
        }
        if (pt != null && ct != null) break;
      }
    }
    if (pt == null) pt = 0;
    if (ct == null) ct = 0;
    return { pt, ct };
  };

    const updateTokenBarIdle = ()=>{
    if (isCurrentChatStreaming()) return;

    const chat = state.currentChat;
    if (!chat){
      if (statusPromptTokEl) statusPromptTokEl.textContent = `P 0`;
      if (statusCompletionTokEl) statusCompletionTokEl.textContent = `C 0`;
      renderContextWindow();
      if (statusCostEl) statusCostEl.textContent = '';
      if (statusSpeedEl) statusSpeedEl.textContent = `0.0s • 0 tok/s`;
      return;
    }

    const usageReset = !!chat?.meta?.usage_reset;
    const draftText = (textarea?.value || '');
    const hasDraft = (String(draftText).trim().length > 0) || (Array.isArray(state.attachments) && state.attachments.length > 0);

    // C = completion tokens across current (visible) assistant messages.
    // Recompute from the current message list so deletions immediately reflect.
    const C = usageReset ? 0 : sumChatCompletionCurrent(chat);

    // P = last prompt tokens + last generation tokens (i.e., what the next prompt starts from),
    // plus any draft the user is currently composing.
    let P = 0;
    if (usageReset) {
      // New compact+clone chat: start from zero, but show a live estimate while typing.
      if (hasDraft) P = computePromptTokNext(chat) + estTok(draftText) + estTokFromAttachments(state.attachments);
      else P = 0;
    } else {
      const last = getLastRunTokens(chat);
      P = (last.pt + last.ct);
      // If we don't have real stats yet, fall back to a content-length estimate.
      if (!(P > 0)) P = computePromptTokNext(chat);
      if (hasDraft) P += estTok(draftText) + estTokFromAttachments(state.attachments);
    }

    if (statusPromptTokEl) statusPromptTokEl.textContent = `P ${Math.round(P)}`;
    if (statusCompletionTokEl) statusCompletionTokEl.textContent = `C ${Math.round(C)}`;
    renderContextWindow();

    const costSum = getChatBilledCost(chat);
    if (statusCostEl) statusCostEl.textContent = costSum.any ? `$${fmtUsd(costSum.usd)}` : '';

    const elapsed = chat?.meta?.last_elapsed_s;
    const tps = chat?.meta?.last_tps;
    if (statusSpeedEl) {
      if (elapsed != null && tps != null) statusSpeedEl.textContent = `${Number(elapsed).toFixed(1)}s • ${Number(tps)} tok/s`;
      else statusSpeedEl.textContent = `0.0s • 0 tok/s`;
    }
  };


  const attachBtn = $('#attach-btn');
  const attachMenu = $('#attach-menu');
  const fileInput = $('#file-input');
  const attachmentsBar = $('#attachments');

  // Web tools (Web / Web search)
  const webToolsBtn = $('#webtools-btn');
  const webToolsMenu = $('#webtools-menu');
  const webToolsCustomList = $('#webtools-custom-list');
  const webToolsMcpList = $('#webtools-mcp-list');
  const webToolsRagList = $('#webtools-rag-list');
  const webToolsWorkspaceList = $('#webtools-workspace-list');
  const documentPanel = $('#document-panel');
  const documentTitleEl = $('#document-title');
  const documentVersionEl = $('#document-version');
  const documentVersionSelectEl = $('#document-version-select');
  const documentRestoreVersionBtn = $('#document-restore-version');
  const documentPreviewEl = $('#document-preview');
  const documentCollapseBtn = $('#document-collapse');
  const documentRestoreBtn = $('#document-restore');
  const documentSelectEl = $('#document-select');
  const documentCopyBtn = $('#document-copy');
  const documentDownloadBtn = $('#document-download');
  const documentDeleteBtn = $('#document-delete');
  const documentMaximizeBtn = $('#document-maximize');
  const documentViewPreviewBtn = $('#document-view-preview');
  const documentViewRawBtn = $('#document-view-raw');

  // ---------- Extraction viewer modal ----------
  const extractModal = (()=> {
    const modal = document.createElement('div');
    modal.className = 'modal modal-above-modal';
    modal.id = 'extract-modal';
    modal.setAttribute('role','dialog');
    modal.setAttribute('aria-modal','true');
    modal.setAttribute('aria-hidden','true');
    modal.innerHTML = `
      <div class="modal-backdrop" id="extract-backdrop"></div>
      <div class="modal-panel" role="document">
        <div class="modal-header">
          <span id="extract-title">Extraction</span>
          <div style="display:flex;gap:8px;align-items:center;">
            <button class="btn tiny" id="extract-copy" title="Copy">Copy</button>
            <button class="icon-btn" id="extract-close" aria-label="Close">${iconSvg('x')}</button>
          </div>
        </div>
        <div class="extract-body">
          <pre class="extract-pre" id="extract-pre"></pre>
        </div>
      </div>
    `;
    document.body.appendChild(modal);

    const titleEl = modal.querySelector('#extract-title');
    const preEl = modal.querySelector('#extract-pre');
    const closeBtn = modal.querySelector('#extract-close');
    const backdrop = modal.querySelector('#extract-backdrop');
    const copyBtn = modal.querySelector('#extract-copy');

    const close = ()=>{
      modal.classList.remove('open');
      modal.setAttribute('aria-hidden','true');
      preEl.textContent = '';
      titleEl.textContent = 'Extraction';
    };

    closeBtn?.addEventListener('click', close);
    backdrop?.addEventListener('click', close);
    document.addEventListener('keydown', (e)=>{ if (e.key==='Escape' && modal.classList.contains('open')) close(); });

    copyBtn?.addEventListener('click', async ()=>{
      const txt = preEl.textContent || '';
      if (!txt) return;
      try { await navigator.clipboard.writeText(txt); }
      catch(_) {
        const ta=document.createElement('textarea'); ta.value=txt;
        document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove();
      }
      const old = copyBtn.textContent;
      copyBtn.textContent='✓';
      setTimeout(()=>{ copyBtn.textContent = old; }, 800);
    });

    const open = (title, text)=>{
      titleEl.textContent = String(title || 'Extraction');
      preEl.textContent = String(text || '');
      modal.classList.add('open');
      modal.setAttribute('aria-hidden','false');
    };

    return { open, close };
  })();


  // ---------- HTML preview modal (iframe preview) ----------
  const previewModal = (()=> {
    const modal = document.createElement('div');
    modal.className = 'modal';
    modal.id = 'preview-modal';
    modal.setAttribute('role','dialog');
    modal.setAttribute('aria-modal','true');
    modal.setAttribute('aria-hidden','true');
    modal.innerHTML = `
      <div class="modal-backdrop" id="preview-backdrop"></div>
      <div class="modal-panel preview-panel" id="preview-panel" role="document">
        <div class="modal-header preview-header" id="preview-header">
          <span id="preview-title" class="preview-title">Preview</span>
          <div style="display:flex;gap:8px;align-items:center;">
            <span class="preview-size" id="preview-size" title="Current viewport size"></span>
            <button class="btn tiny" id="preview-open" title="Open in new tab">Open</button>
            <button class="btn tiny" id="preview-copy" title="Copy HTML">Copy</button>
            <button class="icon-btn" id="preview-max" title="Maximize / Restore" aria-label="Maximize">${iconSvg('maximize')}</button>
            <button class="icon-btn" id="preview-close" aria-label="Close">${iconSvg('x')}</button>
          </div>
        </div>
        <div class="preview-body">
          <div class="preview-hint">Preview (scripts enabled). Resize/drag the window to test different viewports.</div>
          <iframe class="preview-iframe" id="preview-iframe" sandbox="allow-scripts allow-forms allow-modals allow-popups" referrerpolicy="no-referrer"></iframe>
        </div>
      </div>
    `;
    document.body.appendChild(modal);

    const titleEl = modal.querySelector('#preview-title');
    let iframeEl = modal.querySelector('#preview-iframe');
    const closeBtn = modal.querySelector('#preview-close');
    const backdrop = modal.querySelector('#preview-backdrop');
    const copyBtn = modal.querySelector('#preview-copy');
    const openBtn = modal.querySelector('#preview-open');
    const maxBtn = modal.querySelector('#preview-max');
    const panelEl = modal.querySelector('#preview-panel');
    const headerEl = modal.querySelector('#preview-header');
    const sizeEl = modal.querySelector('#preview-size');

    let lastDoc = '';
    let previewObjectUrl = '';
    let previewOpenSeq = 0;
    let isMax = false;
    let restoreRect = null; // { left, top, width, height }

    const revokePreviewUrl = ()=>{
      if (!previewObjectUrl) return;
      try { URL.revokeObjectURL(previewObjectUrl); } catch(_) {}
      previewObjectUrl = '';
    };

    const freshIframe = ()=>{
      revokePreviewUrl();
      if (!iframeEl) return null;
      const next = document.createElement('iframe');
      next.className = iframeEl.className || 'preview-iframe';
      next.id = 'preview-iframe';
      next.setAttribute('sandbox', 'allow-scripts allow-forms allow-modals allow-popups');
      next.setAttribute('referrerpolicy', 'no-referrer');
      iframeEl.replaceWith(next);
      iframeEl = next;
      return iframeEl;
    };

    const close = ()=>{
      previewOpenSeq++;
      modal.classList.remove('open');
      modal.setAttribute('aria-hidden','true');
      titleEl.textContent = 'Preview';
      lastDoc = '';
      isMax = false;
      restoreRect = null;
      if (panelEl){
        panelEl.classList.remove('max');
        panelEl.style.left = '';
        panelEl.style.top = '';
        panelEl.style.width = '';
        panelEl.style.height = '';
        panelEl.style.transform = '';
      }
      // Reset by replacing the iframe, not just clearing srcdoc. Some browsers
      // occasionally keep a stale blank render tree after repeated srcdoc loads.
      freshIframe();
    };

    closeBtn?.addEventListener('click', close);
    backdrop?.addEventListener('click', close);
    document.addEventListener('keydown', (e)=>{ if (e.key==='Escape' && modal.classList.contains('open')) close(); });

    copyBtn?.addEventListener('click', async ()=>{
      const txt = lastDoc || '';
      if (!txt) return;
      try { await navigator.clipboard.writeText(txt); }
      catch(_) {
        const ta=document.createElement('textarea'); ta.value=txt;
        document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove();
      }
      const old = copyBtn.textContent;
      copyBtn.textContent='✓';
      setTimeout(()=>{ copyBtn.textContent = old; }, 800);
    });

    openBtn?.addEventListener('click', ()=>{
      if (!lastDoc) return;
      try{
        const blob = new Blob([lastDoc], { type: 'text/html;charset=utf-8' });
        const url = URL.createObjectURL(blob);
        window.open(url, '_blank', 'noopener');
        // Let it live a bit; then revoke
        setTimeout(()=>{ try{ URL.revokeObjectURL(url); }catch(_){} }, 30_000);
      }catch(_){}
    });

    const syncSize = ()=>{
      if (!panelEl || !sizeEl) return;
      // Use iframe client size as a proxy for viewport.
      const r = iframeEl ? iframeEl.getBoundingClientRect() : panelEl.getBoundingClientRect();
      const w = Math.max(0, Math.round(r.width));
      const h = Math.max(0, Math.round(r.height));
      sizeEl.textContent = w && h ? `${w}×${h}` : '';
    };

    const clampRect = (rect)=>{
      if (!rect) return rect;
      const margin = 8;
      const vw = window.innerWidth || 0;
      const vh = window.innerHeight || 0;
      const w0 = Math.max(320, Math.round(rect.width || 0));
      const h0 = Math.max(260, Math.round(rect.height || 0));
      const w = Math.min(w0, Math.max(320, vw - 2*margin) || w0);
      const h = Math.min(h0, Math.max(260, vh - 2*margin) || h0);
      const maxLeft = Math.max(margin, vw - margin - w);
      const maxTop  = Math.max(margin, vh - margin - h);
      const left = Math.min(Math.max(margin, Math.round(rect.left || 0)), maxLeft);
      const top  = Math.min(Math.max(margin, Math.round(rect.top  || 0)), maxTop);
      return { left, top, width: w, height: h };
    };

    const ensureAbsolutePanel = (rectOverride)=>{
      if (!panelEl) return;
      // Convert from centered transform to absolute positioning (needed for drag/resize/max).
      const cs = getComputedStyle(panelEl);
      const hasTransform = cs.transform && cs.transform !== 'none';
      if (!hasTransform && !rectOverride) return;

      const r = rectOverride || panelEl.getBoundingClientRect();
      // The base modal CSS animates transform on open. Switching to absolute while that
      // transition is active can cause a jump, so kill transitions for this element.
      panelEl.style.transition = 'none';
      panelEl.style.left = `${Math.round(r.left)}px`;
      panelEl.style.top  = `${Math.round(r.top)}px`;
      // Preserve current size when switching modes; otherwise restore/max can get weird.
      if (!panelEl.style.width)  panelEl.style.width  = `${Math.round(r.width)}px`;
      if (!panelEl.style.height) panelEl.style.height = `${Math.round(r.height)}px`;
      panelEl.style.transform = 'none';
      // Force reflow to apply transition:none immediately
      void panelEl.offsetHeight;
    };

    const setPanelRect = (rect)=>{
      if (!panelEl || !rect) return;
      const r = clampRect(rect);
      panelEl.style.transition = 'none';
      panelEl.style.left = `${r.left}px`;
      panelEl.style.top = `${r.top}px`;
      panelEl.style.width = `${r.width}px`;
      panelEl.style.height = `${r.height}px`;
      panelEl.style.transform = 'none';
      void panelEl.offsetHeight;
    };

    const toggleMax = ()=>{
      if (!panelEl) return;
      if (!isMax){
        // Snapshot current rect (even if still centered via transform)
        const r0 = panelEl.getBoundingClientRect();
        ensureAbsolutePanel(r0);
        const r = panelEl.getBoundingClientRect();
        restoreRect = clampRect({ left: r.left, top: r.top, width: r.width, height: r.height });
        panelEl.classList.add('max');
        isMax = true;
      } else {
        panelEl.classList.remove('max');
        isMax = false;
        if (restoreRect) setPanelRect(restoreRect);
      }
      // Swap icon
      if (maxBtn){
        maxBtn.innerHTML = iconSvg(isMax ? 'minimize' : 'maximize');
        maxBtn.setAttribute('aria-label', isMax ? 'Restore' : 'Maximize');
      }
      setTimeout(syncSize, 0);
    };

    maxBtn?.addEventListener('click', toggleMax);

    // Drag the panel by its header (unless maximized)
    // Important: don't switch to absolute on simple clicks (otherwise it can jump during the open animation).
    let dragState = null; // { pointerId, startX, startY, rect, active }
    const DRAG_THRESHOLD = 3;

    headerEl?.addEventListener('pointerdown', (e)=>{
      if (!panelEl || isMax) return;
      // Don't drag when interacting with buttons
      if (e.target && e.target.closest && e.target.closest('button')) return;
      dragState = {
        pointerId: e.pointerId,
        startX: e.clientX,
        startY: e.clientY,
        rect: panelEl.getBoundingClientRect(),
        active: false
      };
      headerEl.setPointerCapture?.(e.pointerId);
      e.preventDefault();
    });

    headerEl?.addEventListener('pointermove', (e)=>{
      if (!dragState || !panelEl || isMax) return;
      const dx = e.clientX - dragState.startX;
      const dy = e.clientY - dragState.startY;
      if (!dragState.active){
        if (Math.abs(dx) + Math.abs(dy) < DRAG_THRESHOLD) return;
        // Activate drag: lock current rect into absolute positioning without transitions
        ensureAbsolutePanel(dragState.rect);
        dragState.active = true;
      }
      const base = dragState.rect;
      const left = Math.max(8, Math.min(window.innerWidth - 120, base.left + dx));
      const top  = Math.max(8, Math.min(window.innerHeight - 80, base.top + dy));
      panelEl.style.transition = 'none';
      panelEl.style.left = `${Math.round(left)}px`;
      panelEl.style.top  = `${Math.round(top)}px`;
      panelEl.style.transform = 'none';
    });

    const endDrag = ()=>{ dragState = null; };
    headerEl?.addEventListener('pointerup', endDrag);
    headerEl?.addEventListener('pointercancel', endDrag);

    // Keep size label updated
    const ro = (window.ResizeObserver && panelEl) ? new ResizeObserver(()=>syncSize()) : null;
    ro?.observe(panelEl);
    window.addEventListener('resize', ()=>{ if (modal.classList.contains('open')) syncSize(); });

    const open = (title, htmlDoc)=>{
      const seq = ++previewOpenSeq;
      titleEl.textContent = String(title || 'Preview');
      lastDoc = String(htmlDoc || '');
      isMax = false;
      restoreRect = null;

      // Reset max button and panel geometry each time. This also prevents a
      // half-restored draggable panel from affecting the next iframe paint.
      if (maxBtn){
        maxBtn.innerHTML = iconSvg('maximize');
        maxBtn.setAttribute('aria-label','Maximize');
      }
      if (panelEl){
        panelEl.classList.remove('max');
        panelEl.style.left = '';
        panelEl.style.top = '';
        panelEl.style.width = '';
        panelEl.style.height = '';
        panelEl.style.transform = '';
      }

      // Use a brand-new iframe for every open. Reusing the same iframe with
      // srcdoc sometimes leaves WebKit/Chromium on a white first paint until a
      // full page reload or a second open. A Blob URL plus iframe replacement is
      // much more deterministic.
      const frame = freshIframe();
      modal.classList.add('open');
      modal.setAttribute('aria-hidden','false');

      const loadDoc = ()=>{
        if (seq !== previewOpenSeq || !modal.classList.contains('open') || !frame) return;
        frame.onload = ()=>{
          if (seq !== previewOpenSeq) return;
          try { frame.contentWindow?.dispatchEvent(new Event('resize')); } catch(_) {}
          // A second tick forces layout after script-created content as well.
          requestAnimationFrame(syncSize);
        };
        frame.onerror = ()=> syncSize();
        try{
          previewObjectUrl = URL.createObjectURL(new Blob([lastDoc], { type: 'text/html;charset=utf-8' }));
          frame.src = previewObjectUrl;
        }catch(_){
          // Very old browser fallback. Still safe because the iframe is fresh.
          frame.srcdoc = lastDoc;
        }
        syncSize();
      };

      // Wait until the now-visible modal has a real box before rendering preview.
      requestAnimationFrame(()=> requestAnimationFrame(loadDoc));
      setTimeout(()=>{ if (seq === previewOpenSeq) syncSize(); }, 80);
    };

    return { open, close };
  })();

  function buildHtmlPreviewDoc(html, css){
    const rawHtml = String(html || '');
    const rawCss  = String(css  || '');

    // NOTE: Scripts are allowed in the preview iframe.
    let h = rawHtml;

    // If user only pasted a fragment, wrap it.
    const hasDoc = /<!doctype|<html[\s>]/i.test(h);
    if (!hasDoc){
      return `<!doctype html>
<html>
<head>
<meta charset="utf-8">
${rawCss ? `<style>\n${rawCss}\n</style>\n` : ''}</head>
<body>
${h}
</body>
</html>`;
    }

    // If it's a full document, inject CSS into <head> if possible.
    if (rawCss.trim()){
      if (/<\/head>/i.test(h)) h = h.replace(/<\/head>/i, `<style>\n${rawCss}\n</style>\n</head>`);
      else h = `<style>\n${rawCss}\n</style>\n` + h;
    }
    return h;
  }

  const inputContainer = $('#input-container');
  const runtimeActivity = $('#runtime-activity');
  const runtimeActivityTitle = $('#runtime-activity-title');
  const runtimeActivityDetail = $('#runtime-activity-detail');
  const runtimeActivityProgress = $('#runtime-activity-progress');
  const runtimeActivityProgressFill = $('#runtime-activity-progress-fill');
  const runtimeActivityClose = $('#runtime-activity-close');

  // Allow PDFs + common text/code formats + images/audio in the file picker.
  // Drag & drop is handled by addFileAttachment() anyway.
  if (fileInput) {
    fileInput.accept = [
      'application/pdf',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.oasis.opendocument.text',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.oasis.opendocument.spreadsheet',
      'text/*',
      'image/*',
      'audio/*',
      '.docx','.odt','.xlsx','.ods',
      '.txt','.md','.markdown','.rst','.csv','.tsv','.json','.jsonl','.xml','.yaml','.yml','.toml','.ini','.conf','.log',
      '.html','.htm','.css','.js','.ts','.jsx','.tsx','.py','.php','.java','.c','.h','.cpp','.hpp','.rs','.go','.rb',
      '.sh','.bash','.zsh','.sql',
      '.mp3','.wav','.m4a','.aac','.ogg','.oga','.opus','.flac','.webm'
    ].join(',');
  }

  // submenus (rendered into <body>, but referenced by global click handler)
  let submenuExport, submenuCompress, submenuRename, submenuClone, submenuTemplate;

  // ---------- UI bits ----------
  function closeMenus(){
    $$('.chat-dropdown.show,.folder-dropdown.show,.submenu.show,.model-menu.show,.attach-menu.show,.webtools-menu.show,.dropdown.show').forEach(el=>el.classList.remove('show'));
    kebabMenu?.classList.remove('show');
  }

  // Templates dropdown ("New" button)
  function renderTemplatesMenu(){
    if (!templateMenuList || !templateMenuEmpty) return;
    const arr = Array.isArray(state.templates) ? state.templates : [];
    templateMenuList.innerHTML = '';
    if (arr.length === 0){
      templateMenuEmpty.classList.remove('hidden');
      return;
    }
    templateMenuEmpty.classList.add('hidden');
    const sorted = [...arr].sort((a,b)=>String(a.name||'').localeCompare(String(b.name||'')));
    for (const t of sorted){
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'dropdown-item tpl-item';
      btn.dataset.tplId = String(t.id || '');
      btn.innerHTML = `${esc(t.name||'Template')} <span class="muted" style="float:right;opacity:.65">▸</span>`;
      templateMenuList.appendChild(btn);
    }
  }

  async function reloadTemplates(){
    try{
      const r = await api('template_list', {});
      state.templates = r?.templates || [];
    }catch(_){
      // ignore
    }
    renderTemplatesMenu();
  }

  // Drawer
  const toggleDrawer = (open) => {
    const will = (typeof open==='boolean') ? open : !drawer.classList.contains('open');
    drawer.classList.toggle('open', will);
    drawer.setAttribute('aria-hidden', (!will).toString());
  };
  drawerOpen?.addEventListener('click', ()=>toggleDrawer(true));
  drawerClose?.addEventListener('click', ()=>toggleDrawer(false));
  drawerBackdrop?.addEventListener('click', ()=>toggleDrawer(false));

  // Header kebab
  kebabBtn?.addEventListener('click', (e)=>{ e.stopPropagation(); kebabMenu.classList.toggle('show'); });
  kebabMenu?.addEventListener('click', async (e)=>{
    const btn = e.target.closest('[data-action]');
    if (!btn) return;
    const action = btn.dataset.action;
    kebabMenu.classList.remove('show');
    if (action==='signout'){
      try{ await api('auth_logout', {}); }catch(_){}
      location.reload();
      return;
    }
  });
  document.addEventListener('click', (e)=>{
    if (!e.target.closest('#header-kebab') && !e.target.closest('#header-kebab-menu')) kebabMenu?.classList.remove('show');
    // NOTE: the export submenu is rendered into <body> (not inside .chat-dropdown),
    // so clicks inside it must NOT close the originating chat dropdown.
    if (!e.target.closest('.chat-menu-btn') && !e.target.closest('.chat-dropdown') && !e.target.closest('.submenu')) {
      $$('.chat-dropdown').forEach(d=>d.classList.remove('show'));
    }
    if (!e.target.closest('.folder-menu-btn') && !e.target.closest('.folder-dropdown')) $$('.folder-dropdown').forEach(d=>d.classList.remove('show'));
    if (!e.target.closest('#model-btn') && !e.target.closest('#model-menu')) modelMenu?.classList.remove('show');
    if (!e.target.closest('#attach-btn') && !e.target.closest('#attach-menu')) attachMenu?.classList.remove('show');
    // Webtools menu is deliberately sticky: only the globe button toggles it.
    // Do not close it from document-level outside clicks, because users may toggle
    // several tools in one pass.
    if (!e.target.closest('#new-chat') && !e.target.closest('#new-chat-dd') && !e.target.closest('#new-chat-menu')) {
      newChatMenu?.classList.remove('show');
      newChatDdBtn?.setAttribute('aria-expanded', 'false');
    }
    // hide any submenu when clicking anywhere outside it or a submenu trigger
    if (!e.target.closest('.submenu') && !e.target.closest('.chat-dropdown .has-submenu')) {
      document.querySelectorAll('.submenu.show').forEach(s=>s.classList.remove('show'));
    }

    // Close per-message stats popovers when clicking outside.
    if (!e.target.closest('.msg-metrics')) {
      document.querySelectorAll('.msg-metrics.open').forEach(el=>el.classList.remove('open'));
    }
});

  on('click', '#header-kebab-menu .dropdown-item', async (e, el)=>{
    kebabMenu.classList.remove('show');
    if (el.dataset.action === 'settings') openSettings(true);
    if (el.dataset.action === 'export'){
      const n = Array.isArray(state.chats) ? state.chats.length : 0;
      if (n <= 0) { alert('No chats to export.'); return; }
      const ok = confirm(`Export all ${n} Chats as ZIP? (Can take a while depending on the amount)`);
      if (!ok) return;

      // Ask for export format (same as folder export).
      const choice = prompt('Export format?\n\n1. OpenAI-JSON\n2. JSON\n3. TXT', '2');
      const c = String(choice||'').trim();
      // Cancel = abort.
      if (choice === null) return;
      const fmt = (c==='1') ? 'openai' : (c==='3' ? 'txt' : 'json');
      closeMenus();
      window.location = `api.php?action=chats_export_all&format=${encodeURIComponent(fmt)}`;
    }
    if (el.dataset.action === 'import') openImport();
    if (el.dataset.action === 'shortcuts'){ window.open('https://www.promptinjection.net/','_blank','noopener'); }
    if (el.dataset.action === 'docs'){ window.open('https://www.locallightai.com/llc/doc/','_blank','noopener'); }
    if (el.dataset.action === 'donate'){ window.open('https://www.locallightai.com/llc/#donate','_blank','noopener'); }
  });

  // llama.cpp router runtime -------------------------------------------------
  function modelByKey(key){
    return (state.models || []).find(m=>m && m.key===key) || null;
  }

  function currentModelEntry(){
    const key = currentModelKey();
    return key ? modelByKey(key) : null;
  }

  // Model context window ----------------------------------------------------
  // Non-llama providers expose this directly through /models.context_length.
  // llama.cpp is different: the useful value is the effective runtime n_ctx
  // from /props, not the model's theoretical/train-time context length.
  const modelContextRequests = new Map();

  function modelContextWindow(connectionId, modelId){
    const key = `${String(connectionId || '')}::${String(modelId || '')}`;
    const m = modelByKey(key);
    const n = Number(m?.context_window);
    return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
  }

  function formatContextWindow(value){
    const n = Number(value);
    if (!Number.isFinite(n) || n <= 0) return '–';
    const fixed = (v, digits) => {
      const s = v.toFixed(digits);
      return digits > 0 ? s.replace(/\.?0+$/, '') : s;
    };
    if (n >= 1_000_000) {
      const v = n / 1_000_000;
      return `${fixed(v, v >= 10 ? 1 : 2)}m`;
    }
    if (n >= 1_000) {
      const v = n / 1_000;
      const digits = v >= 100 ? 0 : (v >= 10 ? 1 : 2);
      return `${fixed(v, digits)}k`;
    }
    return String(Math.round(n));
  }

  function renderContextWindow(connectionId=state.ui.connectionId, modelId=state.ui.model){
    if (!statusContextEl) return;
    const n = modelContextWindow(connectionId, modelId);
    if (n == null) {
      statusContextEl.textContent = 'CTX –';
      statusContextEl.title = 'Maximum context window unavailable';
      return;
    }
    statusContextEl.textContent = `CTX ${formatContextWindow(n)}`;
    statusContextEl.title = `Maximum context window: ${n.toLocaleString()} tokens`;
  }

  async function ensureModelContext(model=currentModelEntry()){
    if (!model || String(model?.backend?.type || '') !== 'llamacpp') return;
    const existing = Number(model.context_window);
    if (Number.isFinite(existing) && existing > 0) return;
    if (model._context_window_checked) return;

    const key = String(model.key || `${model.connection_id || ''}::${model.id || ''}`);
    if (!key || !model.connection_id || !model.id) return;
    if (modelContextRequests.has(key)) return modelContextRequests.get(key);

    const request = (async()=>{
      try {
        const r = await api('model_context', {
          connection_id: String(model.connection_id || ''),
          model: String(model.id || '')
        });
        const live = modelByKey(key);
        if (!live) return;
        const n = Number(r?.context_window);
        live._context_window_checked = true;
        live.context_window = (Number.isFinite(n) && n > 0) ? Math.round(n) : null;
        if (key === currentModelKey()) renderContextWindow();
      } catch (_) {
        // Leave it unchecked so a later model refresh/selection can retry.
      } finally {
        modelContextRequests.delete(key);
      }
    })();
    modelContextRequests.set(key, request);
    return request;
  }

  function syncCurrentModelContext(){
    renderContextWindow();
    ensureModelContext();
  }

  function isLlamaRouterModel(model){
    return !!(model && model.management && model.management.type === 'llamacpp_router');
  }

  function routerStatusValue(model){
    return String(model?.management?.status?.value || '').toLowerCase();
  }

  function routerProgress(model){
    const p = model?.management?.status?.progress;
    return (p && typeof p === 'object') ? p : null;
  }

  function routerModelNorm(value){
    let s = String(value || '').trim().replaceAll('\\','/').toLowerCase();
    s = s.replace(/[?#].*$/, '').replace(/^file:\/\/+/, '').replace(/^\/+|\/+$/g, '');
    return s;
  }

  function routerModelShort(value){
    const s = routerModelNorm(value);
    let out = s.split('/').pop() || s;
    if (out.endsWith('.gguf')) out = out.slice(0, -5);
    return out;
  }

  function routerModelMatches(a, b){
    const na = routerModelNorm(a);
    const nb = routerModelNorm(b);
    if (!na || !nb) return false;
    if (na === nb) return true;
    const sa = routerModelShort(na);
    const sb = routerModelShort(nb);
    if (sa && sb && sa === sb) return true;
    return !!(sa && sb && (na.endsWith('/'+sb) || nb.endsWith('/'+sa)));
  }

  function routerModelForEvent(connectionId, eventModel){
    const candidates = (state.models || []).filter(m=>
      m && String(m.connection_id || '') === String(connectionId || '') && isLlamaRouterModel(m)
    );
    return candidates.find(m=>routerModelMatches(m.id, eventModel)) || null;
  }

  function patchRouterStatus(connectionId, modelId, status, progress=null){
    const m = routerModelForEvent(connectionId, modelId) || modelByKey(`${connectionId}::${modelId}`);
    if (!m || !isLlamaRouterModel(m)) return null;
    const prev = routerStatusValue(m);
    const next = String(status || '').toLowerCase();
    m.management.status = m.management.status || {};
    m.management.status.value = next;
    if (next === 'loading' && progress && typeof progress === 'object') {
      m.management.status.progress = progress;
    } else if (next !== 'loading' || !progress) {
      delete m.management.status.progress;
    }
    if (prev === 'loading' && next !== 'loading') routerDismissedLoads.delete(m.key);
    return {model:m, previous:prev, current:next};
  }

  function currentRuntimeStream(){
    const chatId = String(state.currentChat?.id || '');
    return chatId ? (state.streams.get(chatId) || null) : null;
  }

  function runtimeTokenCount(value){
    const n = Number(value);
    if (!Number.isFinite(n)) return '0';
    return Math.max(0, Math.round(n)).toLocaleString();
  }

  function normalizePromptProgress(obj){
    const totalRaw = Number(obj?.total);
    const cacheRaw = Number(obj?.cache);
    const processedRaw = Number(obj?.processed);
    if (!Number.isFinite(totalRaw) || !Number.isFinite(cacheRaw) || !Number.isFinite(processedRaw)) return null;

    const total = Math.max(0, Math.round(totalRaw));
    const cache = Math.max(0, Math.min(total, Math.round(cacheRaw)));
    const processed = Math.max(0, Math.min(total, Math.round(processedRaw)));
    const timeRaw = Number(obj?.time_ms);
    return {
      total,
      cache,
      processed,
      time_ms: Number.isFinite(timeRaw) ? Math.max(0, timeRaw) : null
    };
  }

  function setPromptProgressForChat(chatId, obj){
    const rec = state.streams.get(String(chatId || ''));
    if (!rec) return;
    const progress = normalizePromptProgress(obj);
    if (!progress) return;
    rec.promptProgress = progress;
    if (state.currentChat?.id === chatId) renderRuntimeActivity();
  }

  function clearPromptProgressForChat(chatId){
    const rec = state.streams.get(String(chatId || ''));
    if (!rec || !rec.promptProgress) return;
    rec.promptProgress = null;
    if (state.currentChat?.id === chatId) renderRuntimeActivity();
  }

  function setRagRetrievalProgressForChat(chatId, obj){
    const rec = state.streams.get(String(chatId || ''));
    if (!rec) return;
    rec.ragRetrievalProgress = {
      mode: String(obj?.mode || ''),
      title: String(obj?.title || 'RAG retrieval'),
      detail: String(obj?.detail || '')
    };
    if (state.currentChat?.id === chatId) renderRuntimeActivity();
  }

  function clearRagRetrievalProgressForChat(chatId){
    const rec = state.streams.get(String(chatId || ''));
    if (!rec || !rec.ragRetrievalProgress) return;
    rec.ragRetrievalProgress = null;
    if (state.currentChat?.id === chatId) renderRuntimeActivity();
  }

  function setRagRuntimeActivity(next){
    state.ragActivity = next ? { dismissed:false, ...next } : null;
    renderRuntimeActivity();
  }

  function updateRagRuntimeActivity(patch={}){
    if (!state.ragActivity) state.ragActivity = { dismissed:false };
    Object.assign(state.ragActivity, patch || {});
    renderRuntimeActivity();
  }

  function clearRagRuntimeActivity(delay=0){
    const clear = ()=>{
      state.ragActivity = null;
      renderRuntimeActivity();
    };
    if (delay > 0) setTimeout(clear, delay); else clear();
  }

  function renderRuntimeActivity(){
    if (!runtimeActivity) return;

    const streamRec = currentRuntimeStream();
    const requestDismissed = !!streamRec?.runtimeActivityDismissed;
    const m = currentModelEntry();
    const key = currentModelKey();
    const status = routerStatusValue(m);

    const ragActivity = state.ragActivity;
    if (ragActivity && !ragActivity.dismissed) {
      const title = String(ragActivity.title || 'Preparing RAG document');
      const detail = String(ragActivity.detail || '');
      const pctRaw = Number(ragActivity.percent);
      const pct = Number.isFinite(pctRaw) ? Math.max(0, Math.min(100, Math.round(pctRaw))) : null;
      if (runtimeActivityTitle) runtimeActivityTitle.textContent = title;
      if (runtimeActivityDetail) {
        runtimeActivityDetail.textContent = detail;
        runtimeActivityDetail.title = detail;
      }
      if (runtimeActivityProgress && runtimeActivityProgressFill) {
        runtimeActivityProgress.classList.toggle('indeterminate', pct == null);
        runtimeActivityProgressFill.style.width = pct == null ? '' : `${pct}%`;
      }
      runtimeActivity.classList.remove('hidden');
      return;
    }

    const ragRetrieval = streamRec?.ragRetrievalProgress;
    if (!requestDismissed && ragRetrieval) {
      const title = String(ragRetrieval.title || 'RAG retrieval');
      const detail = String(ragRetrieval.detail || '');
      if (runtimeActivityTitle) runtimeActivityTitle.textContent = title;
      if (runtimeActivityDetail) {
        runtimeActivityDetail.textContent = detail;
        runtimeActivityDetail.title = detail;
      }
      if (runtimeActivityProgress && runtimeActivityProgressFill) {
        runtimeActivityProgress.classList.add('indeterminate');
        runtimeActivityProgressFill.style.width = '';
      }
      runtimeActivity.classList.remove('hidden');
      return;
    }

    // Model loading has priority because prompt evaluation cannot meaningfully
    // begin until the selected router model is ready.
    if (!requestDismissed && m && isLlamaRouterModel(m) && status === 'loading' && !routerDismissedLoads.has(key)) {
      const p = routerProgress(m);
      const stage = String(p?.current || '').trim();
      const raw = Number(p?.value);
      const hasValue = Number.isFinite(raw);
      const pct = hasValue ? Math.max(0, Math.min(100, Math.round(raw * 100))) : null;
      const label = String(m.label || m.id || 'Model');

      if (runtimeActivityTitle) runtimeActivityTitle.textContent = 'Loading model';
      if (runtimeActivityDetail) {
        const bits = [label];
        if (stage) bits.push(stage);
        if (pct != null) bits.push(`${pct}%`);
        runtimeActivityDetail.textContent = bits.join(' · ');
        runtimeActivityDetail.title = bits.join(' · ');
      }
      if (runtimeActivityProgress && runtimeActivityProgressFill) {
        runtimeActivityProgress.classList.toggle('indeterminate', pct == null);
        runtimeActivityProgressFill.style.width = pct == null ? '' : `${pct}%`;
      }
      runtimeActivity.classList.remove('hidden');
      return;
    }

    const pp = streamRec?.promptProgress;
    if (!requestDismissed && pp) {
      const total = Math.max(0, Number(pp.total) || 0);
      const cache = Math.max(0, Math.min(total, Number(pp.cache) || 0));
      const processed = Math.max(0, Math.min(total, Number(pp.processed) || 0));
      const actualTotal = Math.max(0, total - cache);
      const actualDone = Math.max(0, Math.min(actualTotal, processed - cache));
      const pct = actualTotal > 0 ? Math.max(0, Math.min(100, Math.round((actualDone / actualTotal) * 100))) : 100;

      if (runtimeActivityTitle) runtimeActivityTitle.textContent = 'Processing prompt';
      if (runtimeActivityDetail) {
        const bits = [];
        if (actualTotal > 0) bits.push(`${runtimeTokenCount(actualDone)} / ${runtimeTokenCount(actualTotal)} tokens`);
        else bits.push(`${runtimeTokenCount(total)} tokens`);
        bits.push(`${pct}%`);
        if (cache > 0) bits.push(`${runtimeTokenCount(cache)} cached`);
        runtimeActivityDetail.textContent = bits.join(' · ');
        runtimeActivityDetail.title = bits.join(' · ');
      }
      if (runtimeActivityProgress && runtimeActivityProgressFill) {
        runtimeActivityProgress.classList.remove('indeterminate');
        runtimeActivityProgressFill.style.width = `${pct}%`;
      }
      runtimeActivity.classList.remove('hidden');
      return;
    }

    runtimeActivity.classList.add('hidden');
  }

  function scheduleRouterModelsRefresh(delay=250){
    if (routerModelsRefreshTimer) clearTimeout(routerModelsRefreshTimer);
    routerModelsRefreshTimer = setTimeout(()=>{
      routerModelsRefreshTimer = null;
      refreshModels();
    }, Math.max(0, Number(delay)||0));
  }

  function settleRouterReadyWaiters(connectionId, ready){
    for (const waiter of Array.from(routerEventReadyWaiters)){
      if (waiter.connectionId !== connectionId) continue;
      routerEventReadyWaiters.delete(waiter);
      clearTimeout(waiter.timer);
      waiter.resolve(!!ready);
    }
  }

  function applyRouterEvent(obj){
    const cid = String(obj?.connection_id || routerEventConnectionId || '');
    if (!cid || obj?.type !== 'model_event') return;
    const event = String(obj.event || '');

    if (event === 'models_reload' || event === 'model_remove') {
      scheduleRouterModelsRefresh(100);
      return;
    }

    // llama.cpp currently uses model_status for the initial loading state and
    // status_change for the subsequent progress + terminal state. Its own UI
    // also accepts status_update, so keep the same compatibility set here.
    if (!['status_change','model_status','status_update'].includes(event)) return;

    const eventModel = String(obj.model || '');
    const status = String(obj?.data?.status || '').toLowerCase();
    if (!eventModel || !status) return;

    const progress = (obj?.data?.progress && typeof obj.data.progress === 'object')
      ? obj.data.progress
      : null;
    const patched = patchRouterStatus(cid, eventModel, status, progress);
    if (!patched) {
      // A models_reload can add aliases/presets at runtime. Refresh if the
      // event refers to a model not present in our current list.
      scheduleRouterModelsRefresh(100);
      return;
    }

    // The picker only needs rebuilding when the state itself changes
    // (e.g. loading -> loaded makes Eject appear). Progress-only events update
    // the activity card without rebuilding the hidden model list every tick.
    if (patched.previous !== patched.current) renderModels();
    renderRuntimeActivity();

    if (patched.current === 'loaded' || patched.current === 'unloaded' ||
        patched.current === 'sleeping' || patched.current === 'failed') {
      scheduleRouterModelsRefresh(1200);
    }
  }

  function closeRouterEventStream(){
    const cid = routerEventConnectionId;
    try{ routerEventSource?.close?.(); }catch(_){ }
    routerEventSource = null;
    routerEventConnectionId = '';
    routerEventReady = false;
    if (cid) settleRouterReadyWaiters(cid, false);
  }

  function syncRouterEventStream(){
    const m = currentModelEntry();
    const cid = String(state.ui.connectionId || '');

    if (!cid || !m || !isLlamaRouterModel(m) || routerEventDisabled.has(cid)) {
      closeRouterEventStream();
      renderRuntimeActivity();
      return;
    }

    if (routerEventSource && routerEventConnectionId === cid) {
      renderRuntimeActivity();
      return;
    }

    closeRouterEventStream();
    routerEventConnectionId = cid;
    routerEventReady = false;

    const es = new EventSource(`api.php?action=model_events&connection_id=${encodeURIComponent(cid)}`);
    routerEventSource = es;

    es.onmessage = (ev)=>{
      let obj = null;
      try{ obj = JSON.parse(ev.data || '{}'); }catch(_){ return; }

      if (obj?.type === 'ready') {
        if (routerEventConnectionId !== cid) return;
        routerEventReady = true;
        settleRouterReadyWaiters(cid, true);
        return;
      }

      if (obj?.type === 'error') {
        if (obj?.fatal) {
          routerEventDisabled.add(cid);
          settleRouterReadyWaiters(cid, false);
          if (routerEventConnectionId === cid) closeRouterEventStream();
        }
        return;
      }

      applyRouterEvent(obj);
    };

    es.onerror = ()=>{
      // EventSource reconnects automatically. Until the proxy has re-established
      // the upstream /models/sse connection, don't consider the feed armed.
      if (routerEventConnectionId === cid) routerEventReady = false;
    };

    renderRuntimeActivity();
  }

  async function ensureRouterEventStreamReady(connectionId, timeoutMs=1800){
    const cid = String(connectionId || '');
    if (!cid) return false;

    const selected = currentModelEntry();
    if (!selected || !isLlamaRouterModel(selected) || String(selected.connection_id || '') !== cid) {
      return false;
    }

    syncRouterEventStream();
    if (routerEventSource && routerEventConnectionId === cid && routerEventReady) return true;
    if (routerEventDisabled.has(cid)) return false;

    return await new Promise(resolve=>{
      const waiter = {connectionId:cid, resolve, timer:null};
      waiter.timer = setTimeout(()=>{
        routerEventReadyWaiters.delete(waiter);
        resolve(false);
      }, Math.max(250, Number(timeoutMs)||1800));
      routerEventReadyWaiters.add(waiter);
    });
  }

  runtimeActivityClose?.addEventListener('click', (e)=>{
    e.preventDefault();
    if (state.ragActivity && !state.ragActivity.dismissed) {
      state.ragActivity.dismissed = true;
      runtimeActivity?.classList.add('hidden');
      return;
    }
    const streamRec = currentRuntimeStream();
    if (streamRec) streamRec.runtimeActivityDismissed = true;
    const m = currentModelEntry();
    const key = currentModelKey();
    if (key && m && isLlamaRouterModel(m) && routerStatusValue(m) === 'loading') routerDismissedLoads.add(key);
    runtimeActivity?.classList.add('hidden');
  });

  // Model menu
  modelBtn?.addEventListener('click', (e)=>{
    e.stopPropagation();
    modelMenu.classList.toggle('show');
    if (modelMenu.classList.contains('show')) {
      // Rebuild on open so router load/unload events that happened while the
      // picker was closed are reflected by the eject controls immediately.
      renderModels();
      renderModelCapabilityControl();
      // Focus search for fast filtering
      setTimeout(()=>{ modelSearch?.focus(); modelSearch?.select?.(); }, 0);
    }
  });

  modelSearch?.addEventListener('input', ()=>{
    state.modelFilter = (modelSearch.value || '').trim();
    modelSearchClear?.classList.toggle('hidden', !state.modelFilter);
    renderModels();
  });
  modelSearch?.addEventListener('keydown', (e)=>{
    if (e.key === 'Escape'){
      e.preventDefault();
      state.modelFilter = '';
      if (modelSearch) modelSearch.value = '';
      modelSearchClear?.classList.add('hidden');
      modelMenu.classList.remove('show');
    }
    if (e.key === 'Enter'){
      // pick first visible model
      const first = modelList?.querySelector?.('.model-item-btn[data-key]');
      if (first) first.click();
    }
  });
  modelSearchClear?.addEventListener('click', (e)=>{
    e.preventDefault();
    state.modelFilter = '';
    if (modelSearch) modelSearch.value = '';
    modelSearchClear.classList.add('hidden');
    renderModels();
    modelSearch?.focus();
  });
  modelImageCapability?.addEventListener('change', async ()=>{
    const key = currentModelKey();
    if (!key) return;
    const value = String(modelImageCapability.value || 'auto');
    const next = {...(state.ui.modelCapabilityOverrides || {})};
    if (value === 'auto') delete next[key];
    else next[key] = {image:value};
    state.ui.modelCapabilityOverrides = next;
    try { await api('settings_save', {model_capability_overrides: next}); } catch(err) { console.warn(err); }
    renderModelCapabilityControl();
  });
  on('click', '.model-item-btn', async (e, btn)=>{
    // Ignore clicks from the Pricing model picker (it has its own handler).
    if (btn.closest('#pricing-model-modal')) return;
    const key = btn.dataset.key;
    if (!key) return;

    // Reuse the model-picker UI for other places (e.g. Pricing).
    if (state.modelPickTarget && state.modelPickTarget.type === 'pricing') {
      const idx = Number(state.modelPickTarget.idx);
      state.modelPickTarget = null;

      if (key === '__custom__'){
        const name = prompt('Model name (exact):', '')
        if (!name || !name.trim()) { modelMenu.classList.remove('show'); return; }
        const model = name.trim();
        // Choose a connection: keep current if enabled, otherwise first enabled.
        const enabledCons = (state.connections||[]).filter(c=>Number(c.enabled ?? 1)===1);
        const connId = (enabledCons.find(c=>c.id===state.ui.connectionId)?.id) || (enabledCons[0]?.id) || '';
        setPricingModel(idx, connId, model);
        modelMenu.classList.remove('show');
        return;
      }
      const m = (state.models||[]).find(x=>x.key===key);
      if (m) setPricingModel(idx, m.connection_id, m.id);
      modelMenu.classList.remove('show');
      return;
    }
    if (key === '__custom__'){
      const name = prompt('Model name (exact):', state.ui.model || '');
      if (!name || !name.trim()) return;
      const model = name.trim();
      // Choose a connection for custom models: keep current if enabled, otherwise first enabled.
      const enabledCons = (state.connections||[]).filter(c=>Number(c.enabled ?? 1)===1);
      const connId = (enabledCons.find(c=>c.id===state.ui.connectionId)?.id) || (enabledCons[0]?.id) || '';
      await setModelPair(connId, model);
      return;
    }
    const m = (state.models||[]).find(x=>x.key===key);
    if (!m) return;
    await setModelPair(m.connection_id, m.id);
  });

  on('click', '.model-eject-btn', async (e, btn)=>{
    e.preventDefault();
    e.stopPropagation();
    const key = String(btn.dataset.key || '');
    const m = modelByKey(key);
    if (!m || !isLlamaRouterModel(m) || Number(m.management?.can_unload || 0) !== 1) return;
    if (routerStatusValue(m) !== 'loaded') return;
    btn.disabled = true;
    try{
      // The router endpoint acknowledges before the child is necessarily gone.
      // Keep the current state until /models/sse reports unloaded; refresh is a
      // fallback for deployments that buffer/drop SSE.
      await api('model_unload', {connection_id:m.connection_id, model:m.id});
      routerDismissedLoads.delete(key);
      scheduleRouterModelsRefresh(1200);
    }catch(err){
      alert('Could not unload model: ' + (err?.message || String(err)));
      btn.disabled = false;
    }
  });

  function headerModelText(){
    const mid = state.ui.model || '';
    const cid = state.ui.connectionId || '';
    if (!mid) return 'Model';
    const key = cid && mid ? (cid + '::' + mid) : '';
    const m = key ? (state.models||[]).find(x=>x.key===key) : null;
    if (m && m.label) return m.label;
    const prefix = (state.connections||[]).find(x=>x.id===cid)?.prefix || '';
    return prefix ? `${prefix}.${mid}` : mid;
  }

  function currentModelKey(){
    const cid = state.ui.connectionId || '';
    const mid = state.ui.model || '';
    return cid && mid ? `${cid}::${mid}` : '';
  }

  function renderModelCapabilityControl(){
    if (!modelImageCapability) return;
    const key = currentModelKey();
    const overrides = state.ui.modelCapabilityOverrides || {};
    const entry = key ? overrides[key] : null;
    const override = (entry && typeof entry === 'object') ? String(entry.image || 'auto') : String(entry || 'auto');
    modelImageCapability.value = ['supported','unsupported'].includes(override) ? override : 'auto';
    modelImageCapability.disabled = !key;
    if (!modelImageCapabilityDetected) return;
    const model = key ? (state.models||[]).find(x=>x.key===key) : null;
    const cap = model?.capabilities || {};
    const image = cap.image;
    const source = String(cap.source || 'unknown');
    const detected = image === true ? 'supported' : (image === false ? 'not supported' : 'unknown');
    modelImageCapabilityDetected.textContent = key ? `Detected: ${detected}${source && source!=='unknown' ? ` (${source})` : ''}` : '';
  }

  function renderModels(){
    modelList.innerHTML = '';
    let models = state.models || [];

    // Filter
    const q = String(state.modelFilter || '').trim().toLowerCase();
    if (q){
      models = models.filter(m=>{
        const hay = `${m.label||''} ${m.id||''} ${m.connection_label||''} ${m.connection_id||''}`.toLowerCase();
        return hay.includes(q);
      });
    }

    const canEjectModel = (m)=>isLlamaRouterModel(m) && routerStatusValue(m)==='loaded' && Number(m.management?.can_unload || 0)===1;
    const appendModelRow = (m)=>{
      const active = (m.id===state.ui.model) && (m.connection_id===state.ui.connectionId);
      const li = document.createElement('li');
      const canEject = canEjectModel(m);
      li.innerHTML = `
        <div class="model-item-row">
          <button class="model-item-btn" data-key="${esc(m.key)}">
            <span>${esc(m.label||m.id)}</span>
            <span style="display:flex;gap:6px;align-items:center;">
              <span class="model-badge">${esc(m.connection_label||'')}</span>
              ${active?'<span class="model-badge">active</span>':''}
            </span>
          </button>
          ${canEject ? `<button class="model-eject-btn" type="button" data-key="${esc(m.key)}" title="Unload model from VRAM" aria-label="Unload ${esc(m.label||m.id)} from VRAM">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4l6 9H6z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M6 18h12" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>
          </button>` : ''}
        </div>`;
      modelList.appendChild(li);
    };

    if (!models.length){
      const li = document.createElement('li');
      li.innerHTML = q
        ? `<div class="muted" style="padding:10px 12px;">No matches.</div>`
        : `<div class="muted" style="padding:10px 12px;">No models loaded. (Connections → Enable + check key/URL)</div>`;
      modelList.appendChild(li);
    } else {
      // Keep loaded llama.cpp Router models easy to reach without changing the
      // normal connection-grouped picker below. These rows are intentionally
      // duplicated and use the exact same eject eligibility as the regular list.
      const activeRouterModels = models.filter(canEjectModel);
      if (activeRouterModels.length){
        const liH = document.createElement('li');
        liH.className = 'model-group';
        liH.innerHTML = `<div class="model-group-title">Active</div>`;
        modelList.appendChild(liH);
        for (const m of activeRouterModels) appendModelRow(m);
      }

      const groups = new Map();
      for (const m of models){
        const gl = m.connection_label || m.connection_id || 'Connection';
        if (!groups.has(gl)) groups.set(gl, []);
        groups.get(gl).push(m);
      }
      for (const [gl, arr] of groups){
        const liH = document.createElement('li');
        liH.className = 'model-group';
        liH.innerHTML = `<div class="model-group-title">${esc(gl)}</div>`;
        modelList.appendChild(liH);
        for (const m of arr) appendModelRow(m);
      }
    }

    const li = document.createElement('li');
    li.innerHTML = `<button class="model-item-btn" data-key="__custom__">Custom…</button>`;
    modelList.appendChild(li);
  }

  async function setModelPair(connectionId, modelId){
    state.ui.connectionId = connectionId || '';
    state.ui.model = modelId || '';
    modelBtn.firstChild.textContent = headerModelText() + ' ';
    modelMenu.classList.remove('show');
    syncCurrentModelContext();
    // Start listening before the selection persistence round-trips complete.
    // If the user sends immediately, this minimizes the chance of missing the
    // first model-loading progress event.
    syncRouterEventStream();
    await api('settings_save', { selected_model: state.ui.model || '', selected_connection_id: state.ui.connectionId || '' });
    if (state.currentChat){
      state.currentChat.model = state.ui.model;
      state.currentChat.connection_id = state.ui.connectionId;
      await saveChat();
      await reloadSidebar();
    }
    renderModels();
    renderModelCapabilityControl();
    syncRouterEventStream();
  }

  // Settings modal tabs
  const tabBtns = $$('.nav-item', settingsModal);
  const tabPanels = $$('.tab-panel', settingsModal);
  function activateTab(name){
    tabBtns.forEach(b=>{
      const a = b.dataset.tab===name;
      b.classList.toggle('active', a);
      b.setAttribute('aria-selected', a?'true':'false');
    });
    tabPanels.forEach(p=>p.classList.toggle('active', p.dataset.panel===name));

    // Lazy-load Connections content when the tab is actually shown
    if (name === 'connections') {
      renderConnections();
    }
    // Lazy-load Users tab
    if (name === 'users') {
      renderUsers();
    }

    // Pricing tab
    if (name === 'pricing') {
      renderPricingSettingsUI();
    }
    if (name === 'custom-tools') {
      renderCustomToolsSettingsUI();
    }
    enhanceSettingsNumberInputs();
  }
  tabBtns.forEach(b=>b.addEventListener('click', ()=>activateTab(b.dataset.tab)));

  function openSettings(open){
    const will = (typeof open==='boolean') ? open : !settingsModal.classList.contains('open');
    settingsModal.classList.toggle('open', will);
    settingsModal.setAttribute('aria-hidden', (!will).toString());
    if (will){
      // Always start with the first tab (so reordering tabs in HTML stays correct)
      const firstBtn = Array.from(tabBtns).find(b=>!b.classList.contains('hidden')) || tabBtns[0];
      const first = firstBtn?.dataset?.tab || 'general';
      activateTab(first);
    }
  }
  settingsBackdrop?.addEventListener('click', ()=>openSettings(false));
  settingsClose?.addEventListener('click', ()=>openSettings(false));
  document.addEventListener('keydown', (e)=>{
    if(e.key==='Escape'){
      // Close Pricing model picker first (so Escape doesn't instantly close the whole Settings modal).
      try{
        if (pricingModelModal && pricingModelModal.classList.contains('open')){
          e.preventDefault();
          closePricingModelPicker();
          return;
        }
      }catch(_){/* ignore */}
      openSettings(false);
      toggleDrawer(false);
    }
  });


  // ---------- Pricing settings ----------
  let pricingSaveTimer = null;
  const schedulePricingSave = ()=>{
    if (pricingSaveTimer) clearTimeout(pricingSaveTimer);
    pricingSaveTimer = setTimeout(async ()=>{
      try{
        await api('settings_save', { pricing: Array.isArray(state.ui.pricing) ? state.ui.pricing : [] });
      }catch(_){/* noop */}
      // Updating prices should immediately reflect in status bar.
      updateTokenBarIdle();
    }, 250);
  };

  const pricingDisplayLabel = (cid, mid)=>{
    const c = String(cid||'');
    const m = String(mid||'');
    const key = pricingKey(c, m);
    const found = (state.models||[]).find(x=>x.key===key);
    if (found) return found.label || found.id || m;
    const prefix = (state.connections||[]).find(x=>x.id===c)?.prefix || '';
    return prefix ? `${prefix}.${m}` : m;
  };

  function setPricingModel(idx, connectionId, modelId){
    const i = Number(idx);
    if (!Number.isFinite(i) || i < 0) return;
    state.ui.pricing = Array.isArray(state.ui.pricing) ? state.ui.pricing : [];
    if (!state.ui.pricing[i]) state.ui.pricing[i] = { connection_id:'', model:'', prompt_price:'', gen_price:'' };
    state.ui.pricing[i].connection_id = String(connectionId || '');
    state.ui.pricing[i].model = String(modelId || '');
    renderPricingSettingsUI();
    schedulePricingSave();
  }

  function renderPricingSettingsUI(){
    if (!pricingListEl) return;
    const list = Array.isArray(state.ui.pricing) ? state.ui.pricing : [];
    if (!list.length){
      pricingListEl.innerHTML = `<div class="muted" style="padding:8px 0;">No pricing rules. (+ Add)</div>`;
      return;
    }
    const out = [];
    for (let i=0; i<list.length; i++){
      const r = list[i] || {};
      const cid = String(r.connection_id||'');
      const mid = String(r.model||'');
      const label = (cid && mid) ? pricingDisplayLabel(cid, mid) : 'Select model…';
      const connLabel = (state.connections||[]).find(x=>x.id===cid)?.label || cid || '—';
      const pp = (r.prompt_price==null) ? '' : String(r.prompt_price);
      const gp = (r.gen_price==null) ? '' : String(r.gen_price);

      out.push(`
        <div class="conn-card" data-pricing-idx="${i}">
          <div class="conn-card-head">
            <div>
              <div class="conn-title">${esc(label)}</div>
              <div class="muted" style="margin-top:2px;">${esc(connLabel)}</div>
            </div>
            <div class="conn-actions">
              <button class="btn tiny" type="button" data-cmd="pick" data-idx="${i}">Select model</button>
              <button class="btn tiny btn-ghost" type="button" data-cmd="remove" data-idx="${i}">Remove</button>
            </div>
          </div>
          <div class="conn-card-body">
            <div class="form-grid" style="grid-template-columns: 1fr 1fr;">
              <div class="form-field">
                <label>Prompt $ / 1M tok</label>
                <input class="pricing-input" data-idx="${i}" data-field="prompt_price" type="number" min="0" step="0.01" placeholder="0" value="${esc(pp)}" />
              </div>
              <div class="form-field">
                <label>Generation $ / 1M tok</label>
                <input class="pricing-input" data-idx="${i}" data-field="gen_price" type="number" min="0" step="0.01" placeholder="0" value="${esc(gp)}" />
              </div>
            </div>
          </div>
        </div>
      `);
    }
    pricingListEl.innerHTML = out.join('\n');
  }

  // Open the global model picker for a specific Pricing row.
  // IMPORTANT: Models can be heavy/slow depending on provider, so we only refresh them on-demand
  // when the user explicitly tries to pick a model here.
  
// Dedicated, lazy-loaded model picker for Pricing (must NOT affect the chat/header model selection).
let pricingModelModal = null;
let pricingModelSearch = null;
let pricingModelClear = null;
let pricingModelList = null;
let pricingModelPickIdx = null;
let pricingModelFilter = '';
let pricingModelLoading = false;

function ensurePricingModelModal(){
  if (pricingModelModal) return;
  const wrap = document.createElement('div');
  wrap.className = 'modal';
  wrap.id = 'pricing-model-modal';
  wrap.setAttribute('aria-hidden', 'true');
  wrap.innerHTML = `
    <div class="modal-backdrop" data-close="1"></div>
    <div class="modal-panel" style="width:760px; max-width:92vw;">
      <div class="modal-header">
        <div>Select a model</div>
        <button class="btn tiny btn-ghost" type="button" data-close="1">✕</button>
      </div>
      <div style="padding:10px 12px; border-bottom:1px solid var(--border); display:flex; gap:8px; align-items:center;">
        <input id="pricing-model-search" type="text" placeholder="Search…" style="flex:1; min-width:0; background:var(--bg-secondary); border:1px solid var(--border); color:var(--text-primary); border-radius:8px; padding:7px 10px; font-size:12px; outline:none;" />
        <button class="btn tiny btn-ghost hidden" id="pricing-model-search-clear" type="button" title="Clear" style="width:34px; height:30px; display:grid; place-items:center;">✕</button>
        <button class="btn tiny" id="pricing-model-refresh" type="button" title="Refresh models">↻</button>
      </div>
      <div style="overflow:auto; padding:6px 6px 10px; max-height:60vh;">
        <ul class="model-list" id="pricing-model-list"></ul>
      </div>
    </div>
  `;
  document.body.appendChild(wrap);

  pricingModelModal = wrap;
  pricingModelSearch = wrap.querySelector('#pricing-model-search');
  pricingModelClear = wrap.querySelector('#pricing-model-search-clear');
  pricingModelList = wrap.querySelector('#pricing-model-list');
  const refreshBtn = wrap.querySelector('#pricing-model-refresh');

  // Close handlers
  wrap.addEventListener('click', (e)=>{
    const t = e.target;
    if (t && t.closest && t.closest('[data-close="1"]')) closePricingModelPicker();
  });

  pricingModelSearch?.addEventListener('input', ()=>{
    pricingModelFilter = (pricingModelSearch.value || '').trim();
    pricingModelClear?.classList.toggle('hidden', !pricingModelFilter);
    renderPricingModelPickerList();
  });
  pricingModelSearch?.addEventListener('keydown', (e)=>{
    if (e.key === 'Escape'){
      e.preventDefault();
      closePricingModelPicker();
      return;
    }
    if (e.key === 'Enter'){
      const first = pricingModelList?.querySelector?.('.pricing-model-item-btn[data-key]');
      if (first) first.click();
    }
  });
  pricingModelClear?.addEventListener('click', (e)=>{
    e.preventDefault();
    pricingModelFilter = '';
    if (pricingModelSearch) pricingModelSearch.value = '';
    pricingModelClear?.classList.add('hidden');
    renderPricingModelPickerList();
    pricingModelSearch?.focus();
  });

  refreshBtn?.addEventListener('click', async ()=>{
    pricingModelLoading = true;
    renderPricingModelPickerList();
    await refreshModels();
    pricingModelLoading = false;
    renderPricingModelPickerList();
  });

  // Selection handler (Pricing only)
  wrap.addEventListener('click', (e)=>{
    const btn = e.target.closest('.pricing-model-item-btn');
    if (!btn) return;
    const key = btn.dataset.key;
    if (!key) return;

    const idx = Number(pricingModelPickIdx);
    if (!Number.isFinite(idx)) return;

    if (key === '__custom__'){
      const name = prompt('Model name (exact):', '');
      if (!name || !name.trim()) return;
      const model = name.trim();
      const enabledCons = (state.connections||[]).filter(c=>Number(c.enabled ?? 1)===1);
      const connId = (enabledCons[0]?.id) || '';
      setPricingModel(idx, connId, model);
      closePricingModelPicker();
      return;
    }

    const m = (state.models||[]).find(x=>x.key===key);
    if (m){
      setPricingModel(idx, m.connection_id, m.id);
      closePricingModelPicker();
    }
  });
}

function renderPricingModelPickerList(){
  if (!pricingModelList) return;

  const q = String(pricingModelFilter || '').trim().toLowerCase();
  let models = Array.isArray(state.models) ? state.models.slice() : [];
  if (q){
    models = models.filter(m=>{
      const hay = `${m.label||''} ${m.id||''} ${m.connection_label||''} ${m.connection_id||''}`.toLowerCase();
      return hay.includes(q);
    });
  }

  pricingModelList.innerHTML = '';

  if (pricingModelLoading){
    const li = document.createElement('li');
    li.innerHTML = `<div class="muted" style="padding:10px 12px;">Loading models…</div>`;
    pricingModelList.appendChild(li);
  } else if (!models.length){
    const li = document.createElement('li');
    li.innerHTML = q
      ? `<div class="muted" style="padding:10px 12px;">No matches.</div>`
      : `<div class="muted" style="padding:10px 12px;">No models loaded. (Connections → Enable + check key/URL)</div>`;
    pricingModelList.appendChild(li);
  } else {
    const groups = new Map();
    for (const m of models){
      const gl = m.connection_label || m.connection_id || 'Connection';
      if (!groups.has(gl)) groups.set(gl, []);
      groups.get(gl).push(m);
    }
    for (const [gl, arr] of groups){
      const liH = document.createElement('li');
      liH.className = 'model-group';
      liH.innerHTML = `<div class="model-group-title">${esc(gl)}</div>`;
      pricingModelList.appendChild(liH);

      for (const m of arr){
        const li = document.createElement('li');
        li.innerHTML = `
          <button class="model-item-btn pricing-model-item-btn" data-key="${esc(m.key)}">
            <span>${esc(m.label||m.id)}</span>
            <span style="display:flex;gap:6px;align-items:center;">
              <span class="model-badge">${esc(m.connection_label||'')}</span>
            </span>
          </button>`;
        pricingModelList.appendChild(li);
      }
    }
  }

  const liC = document.createElement('li');
  liC.innerHTML = `<button class="model-item-btn pricing-model-item-btn" data-key="__custom__">Custom…</button>`;
  pricingModelList.appendChild(liC);
}

function openPricingModelPicker(idx){
  ensurePricingModelModal();
  pricingModelPickIdx = idx;

  pricingModelFilter = '';
  if (pricingModelSearch) pricingModelSearch.value = '';
  pricingModelClear?.classList.add('hidden');

  pricingModelModal.classList.add('open');
  pricingModelModal.setAttribute('aria-hidden', 'false');

  // Lazy-load models only when needed.
  if (!Array.isArray(state.models) || state.models.length === 0){
    pricingModelLoading = true;
    renderPricingModelPickerList();
    refreshModels().then(()=>{
      pricingModelLoading = false;
      renderPricingModelPickerList();
    }).catch(()=>{ pricingModelLoading = false; renderPricingModelPickerList(); });
  } else {
    pricingModelLoading = false;
    renderPricingModelPickerList();
  }

  setTimeout(()=>{ pricingModelSearch?.focus(); pricingModelSearch?.select?.(); }, 0);
}

function closePricingModelPicker(){
  if (!pricingModelModal) return;
  pricingModelModal.classList.remove('open');
  pricingModelModal.setAttribute('aria-hidden', 'true');
  pricingModelPickIdx = null;
}

  pricingAddBtn?.addEventListener('click', ()=>{
    state.ui.pricing = Array.isArray(state.ui.pricing) ? state.ui.pricing : [];
    // Do NOT default to the currently selected model; users often mix models inside a chat.
    // Instead we add an empty rule and immediately open a picker (lazy-loaded).
    state.ui.pricing.push({
      connection_id: '',
      model: '',
      prompt_price: '',
      gen_price: ''
    });
    renderPricingSettingsUI();
    schedulePricingSave();

    // Immediately prompt for a model choice.
    const idx = state.ui.pricing.length - 1;
    openPricingModelPicker(idx);
  });

  on('click', '#pricing-list [data-cmd]', (e, btn)=>{
    const cmd = btn.dataset.cmd;
    const idx = Number(btn.dataset.idx);
    if (!Number.isFinite(idx)) return;
    if (cmd === 'remove'){
      state.ui.pricing = Array.isArray(state.ui.pricing) ? state.ui.pricing : [];
      state.ui.pricing.splice(idx, 1);
      renderPricingSettingsUI();
      schedulePricingSave();
      return;
    }
    if (cmd === 'pick'){
      openPricingModelPicker(idx);
      return;
    }
  });

  on('input', '#pricing-list .pricing-input', (e, el)=>{
    const idx = Number(el.dataset.idx);
    const field = String(el.dataset.field || '');
    if (!Number.isFinite(idx) || !field) return;
    state.ui.pricing = Array.isArray(state.ui.pricing) ? state.ui.pricing : [];
    if (!state.ui.pricing[idx]) state.ui.pricing[idx] = { connection_id:'', model:'', prompt_price:'', gen_price:'' };
    const raw = String(el.value || '').trim();
    state.ui.pricing[idx][field] = raw === '' ? '' : Number(raw);
    schedulePricingSave();
  });


// Replace browser-native number spinners with a compact control that matches
// the rest of the settings UI. This is intentionally generic so every numeric
// settings field gets the same treatment.
function enhanceSettingsNumberInputs(){
  const inputs = $$('.settings-body input[type="number"]');
  inputs.forEach(input=>{
    if (!input || input.dataset.llcNumberEnhanced === '1') return;
    input.dataset.llcNumberEnhanced = '1';

    const wrap = document.createElement('div');
    wrap.className = 'llc-number-input-wrap';
    input.parentNode?.insertBefore(wrap, input);
    wrap.appendChild(input);

    const stepper = document.createElement('div');
    stepper.className = 'llc-number-stepper';
    stepper.setAttribute('aria-hidden', 'false');
    stepper.innerHTML = `
      <button class="llc-number-step-btn" type="button" data-dir="up" tabindex="-1" aria-label="Increase value">
        <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M3 7.5 6 4.5l3 3" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"/></svg>
      </button>
      <button class="llc-number-step-btn" type="button" data-dir="down" tabindex="-1" aria-label="Decrease value">
        <svg viewBox="0 0 12 12" aria-hidden="true"><path d="m3 4.5 3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"/></svg>
      </button>`;
    wrap.appendChild(stepper);

    const buttons = Array.from(stepper.querySelectorAll('.llc-number-step-btn'));
    const syncDisabled = ()=> buttons.forEach(btn=>{ btn.disabled = !!input.disabled; });
    syncDisabled();
    try{ new MutationObserver(syncDisabled).observe(input, {attributes:true, attributeFilter:['disabled']}); }catch(_){ }

    stepper.addEventListener('click', (e)=>{
      const btn = e.target?.closest?.('.llc-number-step-btn');
      if (!btn || input.disabled) return;
      e.preventDefault();
      try{
        if (btn.dataset.dir === 'up') input.stepUp();
        else input.stepDown();
      }catch(_){
        const step = Number(input.step || 1) || 1;
        const cur = Number(input.value || 0) || 0;
        input.value = String(cur + (btn.dataset.dir === 'up' ? step : -step));
      }
      input.dispatchEvent(new Event('input', {bubbles:true}));
      input.dispatchEvent(new Event('change', {bubbles:true}));
    });
  });
}
enhanceSettingsNumberInputs();

// General settings
settingWebAutoEnable?.addEventListener('change', async ()=>{
  state.ui.webAutoEnable = !!settingWebAutoEnable.checked;
  try {
    await api('settings_save', { web_auto_enable: state.ui.webAutoEnable ? 1 : 0 });
  } catch(_){ /* ignore */ }

  // If the current chat has no explicit override, apply the new default immediately.
  const hasOverride = !!(state.currentChat?.meta && state.currentChat.meta.webtools);
  if (!hasOverride) {
    state.webtools.web = !!state.ui.webAutoEnable;
    renderWebTools();
  }
});

settingWebSearchAutoEnable?.addEventListener('change', async ()=>{
  state.ui.webSearchAutoEnable = !!settingWebSearchAutoEnable.checked;
  try {
    await api('settings_save', { web_search_auto_enable: state.ui.webSearchAutoEnable ? 1 : 0 });
  } catch(_){ /* ignore */ }

  const hasOverride = !!(state.currentChat?.meta && state.currentChat.meta.webtools);
  if (!hasOverride) {
    state.webtools.search = !!state.ui.webSearchAutoEnable;
    renderWebTools();
  }
});

settingWebAllowPrivate?.addEventListener('change', async ()=>{
  if (state.perms.inheritGlobalWeb && String(state.user?.role || 'user') === 'user') { renderWebSettingsUI(); return; }
  state.ui.webAllowPrivate = !!settingWebAllowPrivate.checked;
  try {
    await api('settings_save', { web_allow_private: state.ui.webAllowPrivate ? 1 : 0 });
  } catch(_){ /* ignore */ }
});

settingWebPreferAtt?.addEventListener('change', async ()=>{
  state.ui.webPreferAttachments = !!settingWebPreferAtt.checked;
  try {
    await api('settings_save', { web_prefer_attachments: state.ui.webPreferAttachments ? 1 : 0 });
  } catch(_){ /* ignore */ }
});

settingMediaImageInline?.addEventListener('change', async ()=>{
  state.ui.mediaImageInline = !!settingMediaImageInline.checked;
  try {
    await api('settings_save', { media_image_inline: state.ui.mediaImageInline ? 1 : 0 });
  } catch(_){ /* ignore */ }
});

settingMediaAudioInline?.addEventListener('change', async ()=>{
  state.ui.mediaAudioInline = !!settingMediaAudioInline.checked;
  try {
    await api('settings_save', { media_audio_inline: state.ui.mediaAudioInline ? 1 : 0 });
  } catch(_){ /* ignore */ }
});

const normalizeWebLimit = (val, fallback)=>{
  const n = parseInt(String(val ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  return (n < 0) ? 0 : n;
};

const normalizeToolRoundLimit = (val, fallback)=>{
  const n = parseInt(String(val ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  if (n < 0) return 0;
  if (n > 1000000) return 1000000;
  return n;
};

const normalizeAgentActivityMode = (val)=> String(val ?? '').toLowerCase() === 'full' ? 'full' : 'tail';
const normalizeAgentActivityMaxTokens = (val, fallback=1000)=>{
  const n = parseInt(String(val ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  if (n < 1) return 1;
  if (n > 1000000) return 1000000;
  return n;
};

const normalizeAgentCompactAboveTokens = (val, fallback=100000)=>{
  const n = parseInt(String(val ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  if (n < 0) return 0;
  if (n > 10000000) return 10000000;
  return n;
};
const normalizeAgentCompactKeepToolRounds = (val, fallback=6)=>{
  const n = parseInt(String(val ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  if (n < 0) return 0;
  if (n > 1000) return 1000;
  return n;
};
const normalizeAgentSupervisorEveryToolCalls = (val, fallback=0)=>{
  const n = parseInt(String(val ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  if (n < 0) return 0;
  if (n > 1000000) return 1000000;
  return n;
};

function renderAgentCompactModelOptions(){
  if (!settingAgentCompactModel) return;
  const selected = String(state.ui.agentCompactModelKey || '__current__');
  settingAgentCompactModel.innerHTML = '';
  const current = document.createElement('option');
  current.value = '__current__';
  current.textContent = 'Current agent model';
  settingAgentCompactModel.appendChild(current);

  const groups = new Map();
  for (const m of (Array.isArray(state.models) ? state.models : [])) {
    if (!m || !m.key || !m.id) continue;
    const group = String(m.connection_label || m.connection_id || 'Connection');
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group).push(m);
  }
  for (const [label, entries] of groups) {
    const optgroup = document.createElement('optgroup');
    optgroup.label = label;
    for (const m of entries) {
      const option = document.createElement('option');
      option.value = String(m.key);
      option.textContent = String(m.label || m.id);
      optgroup.appendChild(option);
    }
    settingAgentCompactModel.appendChild(optgroup);
  }
  if (selected !== '__current__' && !Array.from(settingAgentCompactModel.options).some(o=>o.value===selected)) {
    const unavailable = document.createElement('option');
    unavailable.value = selected;
    unavailable.textContent = `${selected.split('::').slice(1).join('::') || selected} (saved, currently unavailable)`;
    settingAgentCompactModel.appendChild(unavailable);
  }
  settingAgentCompactModel.value = selected;
  if (settingAgentCompactModel.value !== selected) settingAgentCompactModel.value = '__current__';
}

function renderAgentSupervisorModelOptions(){
  if (!settingAgentSupervisorModel) return;
  const selected = String(state.ui.agentSupervisorModelKey || '__current__');
  settingAgentSupervisorModel.innerHTML = '';
  const current = document.createElement('option');
  current.value = '__current__';
  current.textContent = 'Current agent model';
  settingAgentSupervisorModel.appendChild(current);

  const groups = new Map();
  for (const m of (Array.isArray(state.models) ? state.models : [])) {
    if (!m || !m.key || !m.id) continue;
    const group = String(m.connection_label || m.connection_id || 'Connection');
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group).push(m);
  }
  for (const [label, entries] of groups) {
    const optgroup = document.createElement('optgroup');
    optgroup.label = label;
    for (const m of entries) {
      const option = document.createElement('option');
      option.value = String(m.key);
      option.textContent = String(m.label || m.id);
      optgroup.appendChild(option);
    }
    settingAgentSupervisorModel.appendChild(optgroup);
  }
  if (selected !== '__current__' && !Array.from(settingAgentSupervisorModel.options).some(o=>o.value===selected)) {
    const unavailable = document.createElement('option');
    unavailable.value = selected;
    unavailable.textContent = `${selected.split('::').slice(1).join('::') || selected} (saved, currently unavailable)`;
    settingAgentSupervisorModel.appendChild(unavailable);
  }
  settingAgentSupervisorModel.value = selected;
  if (settingAgentSupervisorModel.value !== selected) settingAgentSupervisorModel.value = '__current__';
}

const normalizeMbLimit = (val, fallback, min=0, max=1024)=>{
  const n = parseInt(String(val ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  if (n < min) return min;
  if (n > max) return max;
  return n;
};

const renderGeneralSettingsUI = ()=>{
  const isSuper = String(state.user?.role || 'user') === 'superadmin';
  if (generalSuperNote) generalSuperNote.classList.toggle('hidden', !isSuper);
  [settingToolSimpleMaxIters, settingToolAgenticMaxIters, settingAgentActivityMode, settingUploadHardLimitMb, settingMediaImageInlineLimitMb, settingMediaAudioInlineLimitMb, settingPdfMemorySaving].forEach(el=>{
    try{ if (el) el.disabled = !isSuper; }catch(_){}
  });
  try {
    if (settingAgentActivityMaxTokens) settingAgentActivityMaxTokens.disabled = !isSuper || normalizeAgentActivityMode(state.ui.agentActivityMode) === 'full';
  } catch(_) {}
};

settingToolSimpleMaxIters?.addEventListener('change', async ()=>{
  const isSuper = String(state.user?.role || 'user') === 'superadmin';
  if (!isSuper) { renderGeneralSettingsUI(); return; }
  state.ui.toolSimpleMaxIters = normalizeToolRoundLimit(settingToolSimpleMaxIters.value, 20);
  if (settingToolSimpleMaxIters) settingToolSimpleMaxIters.value = String(state.ui.toolSimpleMaxIters);
  try { await api('settings_save', { tool_simple_max_iters: state.ui.toolSimpleMaxIters }); } catch(_){ /* ignore */ }
});

settingToolAgenticMaxIters?.addEventListener('change', async ()=>{
  const isSuper = String(state.user?.role || 'user') === 'superadmin';
  if (!isSuper) { renderGeneralSettingsUI(); return; }
  state.ui.toolAgenticMaxIters = normalizeToolRoundLimit(settingToolAgenticMaxIters.value, 200);
  if (settingToolAgenticMaxIters) settingToolAgenticMaxIters.value = String(state.ui.toolAgenticMaxIters);
  try { await api('settings_save', { tool_agentic_max_iters: state.ui.toolAgenticMaxIters }); } catch(_){ /* ignore */ }
});


settingAgentActivityMode?.addEventListener('change', async ()=>{
  const isSuper = String(state.user?.role || 'user') === 'superadmin';
  if (!isSuper) { renderGeneralSettingsUI(); return; }
  state.ui.agentActivityMode = normalizeAgentActivityMode(settingAgentActivityMode.value);
  if (settingAgentActivityMode) settingAgentActivityMode.value = state.ui.agentActivityMode;
  renderGeneralSettingsUI();
  try { await api('settings_save', { agent_activity_mode: state.ui.agentActivityMode }); } catch(_){ /* ignore */ }
});

settingAgentActivityMaxTokens?.addEventListener('change', async ()=>{
  const isSuper = String(state.user?.role || 'user') === 'superadmin';
  if (!isSuper) { renderGeneralSettingsUI(); return; }
  state.ui.agentActivityMaxTokens = normalizeAgentActivityMaxTokens(settingAgentActivityMaxTokens.value, 1000);
  if (settingAgentActivityMaxTokens) settingAgentActivityMaxTokens.value = String(state.ui.agentActivityMaxTokens);
  try { await api('settings_save', { agent_activity_max_tokens: state.ui.agentActivityMaxTokens }); } catch(_){ /* ignore */ }
});

settingAgentCompactAboveTokens?.addEventListener('change', async ()=>{
  state.ui.agentCompactAboveTokens = normalizeAgentCompactAboveTokens(settingAgentCompactAboveTokens.value, 100000);
  settingAgentCompactAboveTokens.value = String(state.ui.agentCompactAboveTokens);
  try { await api('settings_save', { agent_compact_above_tokens: state.ui.agentCompactAboveTokens }); } catch(_){ /* ignore */ }
});

settingAgentCompactKeepToolRounds?.addEventListener('change', async ()=>{
  state.ui.agentCompactKeepToolRounds = normalizeAgentCompactKeepToolRounds(settingAgentCompactKeepToolRounds.value, 6);
  settingAgentCompactKeepToolRounds.value = String(state.ui.agentCompactKeepToolRounds);
  try { await api('settings_save', { agent_compact_keep_tool_rounds: state.ui.agentCompactKeepToolRounds }); } catch(_){ /* ignore */ }
});

settingAgentCompactEmergencyEnabled?.addEventListener('change', async ()=>{
  state.ui.agentCompactEmergencyEnabled = !!settingAgentCompactEmergencyEnabled.checked;
  try { await api('settings_save', { agent_compact_emergency_enabled: state.ui.agentCompactEmergencyEnabled ? 1 : 0 }); }
  catch(_){ if (settingAgentCompactEmergencyEnabled) settingAgentCompactEmergencyEnabled.checked = !!state.ui.agentCompactEmergencyEnabled; }
});

settingAgentCompactModel?.addEventListener('change', async ()=>{
  const value = String(settingAgentCompactModel.value || '__current__');
  state.ui.agentCompactModelKey = value || '__current__';
  try { await api('settings_save', { agent_compact_model_key: state.ui.agentCompactModelKey }); }
  catch(_){ renderAgentCompactModelOptions(); }
});

settingAgentCompactReasoningNone?.addEventListener('change', async ()=>{
  state.ui.agentCompactReasoningNone = !!settingAgentCompactReasoningNone.checked;
  try { await api('settings_save', { agent_compact_reasoning_none: state.ui.agentCompactReasoningNone ? 1 : 0 }); }
  catch(_){ if (settingAgentCompactReasoningNone) settingAgentCompactReasoningNone.checked = !!state.ui.agentCompactReasoningNone; }
});

settingAgentSupervisorEveryToolCalls?.addEventListener('change', async ()=>{
  state.ui.agentSupervisorEveryToolCalls = normalizeAgentSupervisorEveryToolCalls(settingAgentSupervisorEveryToolCalls.value, 0);
  settingAgentSupervisorEveryToolCalls.value = String(state.ui.agentSupervisorEveryToolCalls);
  try { await api('settings_save', { agent_supervisor_every_tool_calls: state.ui.agentSupervisorEveryToolCalls }); } catch(_){ /* ignore */ }
});

settingAgentSupervisorModel?.addEventListener('change', async ()=>{
  const value = String(settingAgentSupervisorModel.value || '__current__');
  state.ui.agentSupervisorModelKey = value || '__current__';
  try { await api('settings_save', { agent_supervisor_model_key: state.ui.agentSupervisorModelKey }); }
  catch(_){ renderAgentSupervisorModelOptions(); }
});

settingUploadHardLimitMb?.addEventListener('change', async ()=>{
  const isSuper = String(state.user?.role || 'user') === 'superadmin';
  if (!isSuper) { renderGeneralSettingsUI(); return; }
  state.ui.uploadHardLimitMb = normalizeMbLimit(settingUploadHardLimitMb.value, 50, 1, 1024);
  if (settingUploadHardLimitMb) settingUploadHardLimitMb.value = String(state.ui.uploadHardLimitMb);
  try { await api('settings_save', { upload_hard_limit_mb: state.ui.uploadHardLimitMb }); } catch(_){ /* ignore */ }
});

settingMediaImageInlineLimitMb?.addEventListener('change', async ()=>{
  const isSuper = String(state.user?.role || 'user') === 'superadmin';
  if (!isSuper) { renderGeneralSettingsUI(); return; }
  state.ui.mediaImageInlineLimitMb = normalizeMbLimit(settingMediaImageInlineLimitMb.value, 8, 0, 1024);
  if (settingMediaImageInlineLimitMb) settingMediaImageInlineLimitMb.value = String(state.ui.mediaImageInlineLimitMb);
  try { await api('settings_save', { media_image_inline_limit_mb: state.ui.mediaImageInlineLimitMb }); } catch(_){ /* ignore */ }
});

settingMediaAudioInlineLimitMb?.addEventListener('change', async ()=>{
  const isSuper = String(state.user?.role || 'user') === 'superadmin';
  if (!isSuper) { renderGeneralSettingsUI(); return; }
  state.ui.mediaAudioInlineLimitMb = normalizeMbLimit(settingMediaAudioInlineLimitMb.value, 15, 0, 1024);
  if (settingMediaAudioInlineLimitMb) settingMediaAudioInlineLimitMb.value = String(state.ui.mediaAudioInlineLimitMb);
  try { await api('settings_save', { media_audio_inline_limit_mb: state.ui.mediaAudioInlineLimitMb }); } catch(_){ /* ignore */ }
});

settingPdfMemorySaving?.addEventListener('change', async ()=>{
  const isSuper = String(state.user?.role || 'user') === 'superadmin';
  if (!isSuper) {
    if (settingPdfMemorySaving) settingPdfMemorySaving.checked = !!state.ui.pdfMemorySaving;
    renderGeneralSettingsUI();
    return;
  }
  const previous = !!state.ui.pdfMemorySaving;
  const next = !!settingPdfMemorySaving.checked;
  try {
    await api('settings_save', { pdf_memory_saving: next ? 1 : 0 });
    state.ui.pdfMemorySaving = next;
  } catch(_){
    if (settingPdfMemorySaving) settingPdfMemorySaving.checked = previous;
  }
});

const normalizeArchiveDays = (val, fallback=30)=>{
  const n = parseInt(String(val ?? ''), 10);
  if (!Number.isFinite(n)) return fallback;
  if (n < 1) return 1;
  if (n > 36500) return 36500;
  return n;
};

try{
  const savedArchiveDays = localStorage.getItem('archive_old_root_days');
  if (archiveOldRootDays && savedArchiveDays !== null) archiveOldRootDays.value = String(normalizeArchiveDays(savedArchiveDays, 30));
}catch(_){ }

archiveOldRootDays?.addEventListener('change', ()=>{
  const days = normalizeArchiveDays(archiveOldRootDays.value, 30);
  archiveOldRootDays.value = String(days);
  try{ localStorage.setItem('archive_old_root_days', String(days)); }catch(_){ }
});

archiveOldRootBtn?.addEventListener('click', async ()=>{
  const days = normalizeArchiveDays(archiveOldRootDays?.value, 30);
  if (archiveOldRootDays) archiveOldRootDays.value = String(days);
  try{ localStorage.setItem('archive_old_root_days', String(days)); }catch(_){ }

  const previousLabel = archiveOldRootBtn.textContent;
  archiveOldRootBtn.disabled = true;
  archiveOldRootBtn.textContent = 'Archiving…';
  if (archiveOldRootStatus) archiveOldRootStatus.textContent = '';
  try{
    const r = await api('archive_old_root_chats', {days});
    const moved = Math.max(0, Number(r?.moved || 0) || 0);
    await reloadSidebar();
    if (archiveOldRootStatus){
      archiveOldRootStatus.textContent = moved === 0
        ? `No folderless chats older than ${days} days. Archive is ready.`
        : `Moved ${moved} folderless chat${moved === 1 ? '' : 's'} to Archive.`;
    }
  }catch(err){
    if (archiveOldRootStatus) archiveOldRootStatus.textContent = 'Archive failed: ' + (err?.message || err);
  }finally{
    archiveOldRootBtn.disabled = false;
    archiveOldRootBtn.textContent = previousLabel || 'Move old folderless chats to archive';
  }
});

const renderWebSettingsUI = ()=>{
  const locked = !!(state.perms.inheritGlobalWeb && String(state.user?.role || 'user') === 'user');
  if (webInheritNote) webInheritNote.classList.toggle('hidden', !locked);
  const setDis = (el, dis)=>{ try{ if(el) el.disabled = !!dis; }catch(_){ } };
  // Only lock the global web tool settings; per-user toggles remain editable.
  [settingWebAllowPrivate, settingWebFetchMaxChars, settingWebToolMaxChars].forEach(el=> setDis(el, locked));
};

settingWebFetchMaxChars?.addEventListener('change', async ()=>{
  if (state.perms.inheritGlobalWeb && String(state.user?.role || 'user') === 'user') { renderWebSettingsUI(); return; }
  state.ui.webFetchMaxChars = normalizeWebLimit(settingWebFetchMaxChars.value, 50000);
  if (settingWebFetchMaxChars) settingWebFetchMaxChars.value = String(state.ui.webFetchMaxChars);
  try { await api('settings_save', { web_fetch_max_chars: state.ui.webFetchMaxChars }); } catch(_){ /* ignore */ }
});

settingWebToolMaxChars?.addEventListener('change', async ()=>{
  if (state.perms.inheritGlobalWeb && String(state.user?.role || 'user') === 'user') { renderWebSettingsUI(); return; }
  state.ui.webToolMaxChars = normalizeWebLimit(settingWebToolMaxChars.value, 60000);
  if (settingWebToolMaxChars) settingWebToolMaxChars.value = String(state.ui.webToolMaxChars);
  try { await api('settings_save', { web_tool_max_chars: state.ui.webToolMaxChars }); } catch(_){ /* ignore */ }
});

// Search settings
const isSearchConfigured = ()=>{
  const prov = String(state.ui.searchProvider || 'serper');
  if (prov === 'serper') return !!String(state.ui.serperApiKey || '').trim();
  if (prov === 'brave') return !!String(state.ui.braveApiKey || '').trim();
  if (prov === 'exa') return !!String(state.ui.exaApiKey || '').trim();
  if (prov === 'custom') return !!String(state.ui.searchCustomUrl || '').trim();
  if (prov === 'searchngx') return !!String(state.ui.searchNgxUrl || '').trim();
  return false;
};

const renderSearchSettingsUI = ()=>{
  const locked = !!(state.perms.inheritGlobalSearch && state.user && String(state.user.role||'user')==='user');
  const prov = String(state.ui.searchProvider || 'serper');
  if (settingSearchProvider) settingSearchProvider.value = prov;
  if (searchInheritNote) searchInheritNote.classList.toggle('hidden', !locked);

  // Lock down search configuration fields when inherited globally.
  const setDis = (el, dis)=>{ try{ if(el) el.disabled = !!dis; }catch(_){ } };
  [
    settingSearchProvider, settingSerperKey, settingBraveKey, settingExaKey, settingSearchCustomUrl, settingSearchCustomNewsUrl,
    settingSearchCustomAllowPrivate, settingSearchCustomKey, settingSearchNgxUrl, settingSearchNgxAllowPrivate,
    settingSearchNgxKey, settingSearchGl, settingSearchHl, settingSearchNum
  ].forEach(el=> setDis(el, locked));
  if (searchCustomHint) searchCustomHint.classList.toggle('hidden', prov !== 'custom');
  if (searchSerperFields) searchSerperFields.classList.toggle('hidden', prov !== 'serper');
  if (searchBraveFields) searchBraveFields.classList.toggle('hidden', prov !== 'brave');
  if (searchExaFields) searchExaFields.classList.toggle('hidden', prov !== 'exa');
  if (searchCustomFields) searchCustomFields.classList.toggle('hidden', prov !== 'custom');
  if (searchNgxFields) searchNgxFields.classList.toggle('hidden', prov !== 'searchngx');

  // Custom News URL override is optional, but should always be available for "custom".
  if (searchCustomNewsWrap) searchCustomNewsWrap.classList.toggle('hidden', prov !== 'custom');
  // Also reflect disable state in the composer popover.
  renderWebTools();
};

const saveSearchSettings = async (patch)=>{
  try { await api('settings_save', patch); } catch(_){ /* ignore */ }
};

settingSearchProvider?.addEventListener('change', async ()=>{
  state.ui.searchProvider = String(settingSearchProvider.value || 'serper');
  await saveSearchSettings({ search_provider: state.ui.searchProvider });
  renderSearchSettingsUI();
});

settingSerperKey?.addEventListener('change', async ()=>{
  state.ui.serperApiKey = String(settingSerperKey.value || '');
  await saveSearchSettings({ serper_api_key: state.ui.serperApiKey });
  renderSearchSettingsUI();
});

settingBraveKey?.addEventListener('change', async ()=>{
  state.ui.braveApiKey = String(settingBraveKey.value || '');
  await saveSearchSettings({ brave_api_key: state.ui.braveApiKey });
  renderSearchSettingsUI();
});

settingExaKey?.addEventListener('change', async ()=>{
  state.ui.exaApiKey = String(settingExaKey.value || '');
  await saveSearchSettings({ exa_api_key: state.ui.exaApiKey });
  renderSearchSettingsUI();
});

settingSearchCustomUrl?.addEventListener('change', async ()=>{
  state.ui.searchCustomUrl = String(settingSearchCustomUrl.value || '').trim();
  await saveSearchSettings({ search_custom_url: state.ui.searchCustomUrl });
  renderSearchSettingsUI();
});

settingSearchCustomNewsUrl?.addEventListener('change', async ()=>{
  state.ui.searchCustomNewsUrl = String(settingSearchCustomNewsUrl.value || '').trim();
  await saveSearchSettings({ search_custom_news_url: state.ui.searchCustomNewsUrl });
  renderSearchSettingsUI();
});

settingSearchCustomAllowPrivate?.addEventListener('change', async ()=>{
  state.ui.searchCustomAllowPrivate = !!settingSearchCustomAllowPrivate.checked;
  await saveSearchSettings({ search_custom_allow_private: state.ui.searchCustomAllowPrivate ? 1 : 0 });
  renderSearchSettingsUI();
});

settingSearchCustomKey?.addEventListener('change', async ()=>{
  state.ui.searchCustomApiKey = String(settingSearchCustomKey.value || '');
  await saveSearchSettings({ search_custom_api_key: state.ui.searchCustomApiKey });
  renderSearchSettingsUI();
});

settingSearchNgxUrl?.addEventListener('change', async ()=>{
  state.ui.searchNgxUrl = String(settingSearchNgxUrl.value || '').trim();
  await saveSearchSettings({ searchngx_url: state.ui.searchNgxUrl });
  renderSearchSettingsUI();
});

settingSearchNgxAllowPrivate?.addEventListener('change', async ()=>{
  state.ui.searchNgxAllowPrivate = !!settingSearchNgxAllowPrivate.checked;
  await saveSearchSettings({ searchngx_allow_private: state.ui.searchNgxAllowPrivate ? 1 : 0 });
  renderSearchSettingsUI();
});

settingSearchNgxKey?.addEventListener('change', async ()=>{
  state.ui.searchNgxApiKey = String(settingSearchNgxKey.value || '');
  await saveSearchSettings({ searchngx_api_key: state.ui.searchNgxApiKey });
  renderSearchSettingsUI();
});

const saveSearchLocale = async ()=>{
  state.ui.searchGl = String(settingSearchGl?.value || state.ui.searchGl || 'us').trim() || 'de';
  state.ui.searchHl = String(settingSearchHl?.value || state.ui.searchHl || 'us').trim() || 'us';
  const num = parseInt(String(settingSearchNum?.value || state.ui.searchNum || 10), 10);
  state.ui.searchNum = (Number.isFinite(num) && num>=1 && num<=20) ? num : 10;
  await saveSearchSettings({ search_gl: state.ui.searchGl, search_hl: state.ui.searchHl, search_num: state.ui.searchNum });
};

settingSearchGl?.addEventListener('change', saveSearchLocale);
settingSearchHl?.addEventListener('change', saveSearchLocale);
settingSearchNum?.addEventListener('change', saveSearchLocale);



// RAG settings
const normalizeRagTopK = (val)=>{
  const n = parseInt(String(val ?? ''), 10);
  if (!Number.isFinite(n)) return 8;
  return Math.max(1, Math.min(64, n));
};
const normalizeRagTimeout = (val)=>{
  const n = parseInt(String(val ?? ''), 10);
  if (!Number.isFinite(n)) return 180;
  return Math.max(5, Math.min(3600, n));
};
const normalizeRagMode = (val, fallback='hybrid')=>{
  const fb = ['dense','hybrid','precise'].includes(String(fallback || '').toLowerCase()) ? String(fallback).toLowerCase() : 'hybrid';
  const mode = String(val ?? '').toLowerCase().trim();
  return ['dense','hybrid','precise'].includes(mode) ? mode : fb;
};
const normalizeChatRagMode = (val)=>{
  const mode = String(val ?? 'default').toLowerCase().trim();
  return ['default','dense','hybrid','precise'].includes(mode) ? mode : 'default';
};
const effectiveRagMode = ()=>{
  const chatMode = normalizeChatRagMode(state.webtools?.rag_mode);
  return chatMode === 'default' ? normalizeRagMode(state.ui?.ragDefaultMode, 'hybrid') : normalizeRagMode(chatMode, 'hybrid');
};
const ragModeLabel = (mode)=>({dense:'Fast', hybrid:'Hybrid', precise:'Precise'}[normalizeRagMode(mode, 'hybrid')] || 'Hybrid');
const setRagSettingsStatus = (text, isError=false)=>{
  if (!settingRagStatus) return;
  settingRagStatus.textContent = String(text || '');
  settingRagStatus.style.color = isError ? 'var(--danger, #c33)' : '';
};

let ragCapabilityNotice = null;
const showRagCapabilityNotice = (title, detail='')=>{
  ragCapabilityNotice?.remove();
  const el = document.createElement('div');
  el.className = 'rag-capability-notice';
  el.setAttribute('role', 'status');
  el.innerHTML = `<div class="rag-capability-notice-copy"><b>${esc(String(title || 'RAG'))}</b><span>${esc(String(detail || ''))}</span></div><button type="button" class="rag-capability-notice-close" title="Dismiss" aria-label="Dismiss">×</button>`;
  document.body.appendChild(el);
  el.querySelector('.rag-capability-notice-close')?.addEventListener('click', ()=>{
    if (ragCapabilityNotice === el) ragCapabilityNotice = null;
    el.remove();
  });
  ragCapabilityNotice = el;
};
const ragCapabilityKey = (chat = state.currentChat)=> String(chat?.id || '__draft__');
const currentRagCapabilities = (chat = state.currentChat)=> state.ragCapabilities.get(ragCapabilityKey(chat)) || null;
const clearRagCapabilityCache = ()=>{
  state.ragCapabilities.clear();
  state.ragCapabilityPending.clear();
};
const ensureRagCapabilities = async (chat = state.currentChat)=>{
  if (!state.ui.ragAvailable) return null;
  const key = ragCapabilityKey(chat);
  if (state.ragCapabilities.has(key)) return state.ragCapabilities.get(key);
  if (state.ragCapabilityPending.has(key)) return state.ragCapabilityPending.get(key);

  const pending = (async()=>{
    try {
      const r = await api('rag_capabilities');
      const raw = (r && typeof r.capabilities === 'object' && r.capabilities) ? r.capabilities : {};
      const caps = {
        dense: raw.dense !== false,
        hybrid: raw.hybrid !== false,
        precise: raw.precise === true,
        checked: true,
        error: ''
      };
      state.ragCapabilities.set(key, caps);
      if (!caps.precise) {
        showRagCapabilityNotice('Precise RAG unavailable', 'The reranker is not configured in ragd. Fast and Hybrid remain available.');
      }
      return caps;
    } catch (err) {
      const caps = {dense:true, hybrid:true, precise:false, checked:false, error:String(err?.message || err || 'Capability check failed')};
      state.ragCapabilities.set(key, caps);
      showRagCapabilityNotice('Could not check RAG capabilities', 'ragd /v1/status could not be read. Precise is hidden until the server can be checked.');
      return caps;
    } finally {
      state.ragCapabilityPending.delete(key);
      renderWebTools();
    }
  })();
  state.ragCapabilityPending.set(key, pending);
  renderWebTools();
  return pending;
};
const renderRagSettingsUI = ()=>{
  const isSuper = String(state.user?.role || 'user') === 'superadmin';
  [settingRagUrl, settingRagTopK, settingRagTimeoutSec, settingRagTest].forEach(el=>{
    try { if (el) el.disabled = !isSuper; } catch(_) {}
  });
  if (settingRagAutoEnable) settingRagAutoEnable.disabled = false;
  if (settingRagDefaultMode) settingRagDefaultMode.disabled = false;
  if (ragSuperNote) {
    ragSuperNote.textContent = isSuper
      ? 'RAG infrastructure is global. A configured server URL makes it available; automatic activation and the retrieval default below are personal.'
      : 'RAG infrastructure is managed globally by a superadmin. Automatic activation and your retrieval default below are personal.';
  }
  if (!isSuper) setRagSettingsStatus(state.ui.ragAvailable ? 'RAG service available' : 'RAG service unavailable');
  renderWebTools();
};
const saveRagSettingsFromForm = async ()=>{
  const isSuper = String(state.user?.role || 'user') === 'superadmin';
  if (!isSuper) return false;
  state.ui.ragUrl = String(settingRagUrl?.value || '').trim().replace(/\/+$/, '');
  state.ui.ragTopK = normalizeRagTopK(settingRagTopK?.value);
  state.ui.ragTimeoutSec = normalizeRagTimeout(settingRagTimeoutSec?.value);
  if (settingRagTopK) settingRagTopK.value = String(state.ui.ragTopK);
  if (settingRagTimeoutSec) settingRagTimeoutSec.value = String(state.ui.ragTimeoutSec);
  try {
    await api('settings_save', {
      rag_url: state.ui.ragUrl,
      rag_top_k: state.ui.ragTopK,
      rag_timeout_sec: state.ui.ragTimeoutSec
    });
    state.ui.ragAvailable = !!state.ui.ragUrl;
    clearRagCapabilityCache();
    const hasOverride = !!(state.currentChat?.meta && state.currentChat.meta.webtools);
    if (!hasOverride) {
      state.webtools.rag = !!state.ui.ragAvailable && !!state.ui.ragAutoEnable;
      state.webtools.rag_mode = 'default';
    }
    if (!state.ui.ragAvailable && state.webtools.rag) {
      state.webtools.rag = false;
      persistCurrentWebTools();
    }
    setRagSettingsStatus('Saved');
    renderRagSettingsUI();
    return true;
  } catch (err) {
    setRagSettingsStatus(err?.message || String(err), true);
    return false;
  }
};

settingRagDefaultMode?.addEventListener('change', async ()=>{
  state.ui.ragDefaultMode = normalizeRagMode(settingRagDefaultMode?.value, 'hybrid');
  if (settingRagDefaultMode) settingRagDefaultMode.value = state.ui.ragDefaultMode;
  try {
    await api('settings_save', {rag_default_mode: state.ui.ragDefaultMode});
    setRagSettingsStatus('Saved');
    renderWebTools();
  } catch (err) {
    setRagSettingsStatus(err?.message || String(err), true);
  }
});

settingRagAutoEnable?.addEventListener('change', async ()=>{
  state.ui.ragAutoEnable = !!settingRagAutoEnable.checked;
  try {
    await api('settings_save', {rag_auto_enable: state.ui.ragAutoEnable ? 1 : 0});
    setRagSettingsStatus('Saved');
  } catch (err) {
    setRagSettingsStatus(err?.message || String(err), true);
    return;
  }
  const hasOverride = !!(state.currentChat?.meta && state.currentChat.meta.webtools);
  if (!hasOverride) {
    state.webtools.rag = !!state.ui.ragAvailable && !!state.ui.ragAutoEnable;
    state.webtools.rag_mode = 'default';
    renderWebTools();
  }
});
settingRagUrl?.addEventListener('change', saveRagSettingsFromForm);
settingRagTopK?.addEventListener('change', saveRagSettingsFromForm);
settingRagTimeoutSec?.addEventListener('change', saveRagSettingsFromForm);
settingRagTest?.addEventListener('click', async ()=>{
  setRagSettingsStatus('Testing…');
  const saved = await saveRagSettingsFromForm();
  if (!saved) return;
  try {
    const r = await api('rag_test');
    const st = r?.status || {};
    const chunks = Number(st.indexed_chunks || 0);
    const dim = Number(st.dimension || 0);
    setRagSettingsStatus(`Connected · ${String(st.index || 'ragd')} · ${chunks} chunks${dim ? ` · ${dim}D` : ''}`);
  } catch (err) {
    setRagSettingsStatus(err?.message || String(err), true);
  }
});

// Image settings
const comfyProfileId = ()=>{
  try {
    if (globalThis.crypto?.getRandomValues) {
      const a = new Uint32Array(2);
      globalThis.crypto.getRandomValues(a);
      return `comfy_${a[0].toString(16)}${a[1].toString(16)}`;
    }
  } catch(_){ }
  return `comfy_${Date.now().toString(36)}_${Math.random().toString(36).slice(2,10)}`;
};

const comfyNum = (v, fallback)=>{
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
};

const comfyNormalizeProfile = (p, fallbackId='')=>{
  const x = (p && typeof p === 'object') ? p : {};
  let id = String(x.id || fallbackId || '').trim().replace(/[^A-Za-z0-9_.:-]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 100);
  if (!id) id = comfyProfileId();
  let name = String(x.name || '').trim();
  if (!name) name = 'ComfyUI';
  return {
    id,
    name,
    url: String(x.url || ''),
    workflow_json: String(x.workflow_json || ''),
    bindings_json: String(x.bindings_json || ''),
    binding_plan_json: String(x.binding_plan_json || ''),
    seed: Math.trunc(comfyNum(x.seed, -1)),
    steps: Math.max(1, Math.min(250, Math.trunc(comfyNum(x.steps, 20)))),
    guidance: comfyNum(x.guidance, 3.5),
    width: Math.max(64, Math.min(4096, Math.trunc(comfyNum(x.width, 512)))),
    height: Math.max(64, Math.min(4096, Math.trunc(comfyNum(x.height, 512)))),
    batch: Math.max(1, Math.min(16, Math.trunc(comfyNum(x.batch, 1)))),
    timeout_sec: Math.max(30, Math.min(3600, Math.trunc(comfyNum(x.timeout_sec, 900)))),
    apply_defaults: x.apply_defaults === true || Number(x.apply_defaults) === 1
  };
};

const comfyLegacyProfileFromState = ()=> comfyNormalizeProfile({
  id: 'default',
  name: 'Default',
  url: state.ui.imageComfyUrl || '',
  workflow_json: state.ui.imageComfyWorkflow || '',
  bindings_json: state.ui.imageComfyBindings || '',
  seed: state.ui.imageComfySeed ?? -1,
  steps: state.ui.imageComfySteps ?? 20,
  guidance: state.ui.imageComfyGuidance ?? 3.5,
  width: state.ui.imageComfyWidth ?? 512,
  height: state.ui.imageComfyHeight ?? 512,
  batch: state.ui.imageComfyBatch ?? 1,
  timeout_sec: state.ui.imageComfyTimeout ?? 900,
  apply_defaults: !!state.ui.imageComfyApplyDefaults
}, 'default');

const ensureComfyProfiles = ()=>{
  let profiles = Array.isArray(state.ui.imageComfyProfiles) ? state.ui.imageComfyProfiles : [];
  profiles = profiles.filter(p=> p && typeof p === 'object').slice(0, 50).map((p,i)=> comfyNormalizeProfile(p, `comfy_${i+1}`));
  if (!profiles.length) profiles = [comfyLegacyProfileFromState()];

  // Keep IDs unique so the selected profile is deterministic even after hand-edited JSON/imports.
  const seen = new Set();
  for (const p of profiles) {
    if (!p.id || seen.has(p.id)) p.id = comfyProfileId();
    seen.add(p.id);
  }
  state.ui.imageComfyProfiles = profiles;

  let selected = String(state.ui.imageComfyProfileId || '').trim();
  if (!profiles.some(p=>p.id === selected)) selected = profiles[0].id;
  state.ui.imageComfyProfileId = selected;
  return profiles;
};

const activeComfyProfile = ()=>{
  const profiles = ensureComfyProfiles();
  return profiles.find(p=>p.id === state.ui.imageComfyProfileId) || profiles[0];
};

const syncComfyStateFromActiveProfile = ()=>{
  const p = activeComfyProfile();
  if (!p) return;
  state.ui.imageComfyUrl = String(p.url || '');
  state.ui.imageComfyWorkflow = String(p.workflow_json || '');
  state.ui.imageComfyBindings = String(p.bindings_json || '');
  state.ui.imageComfySeed = Math.trunc(comfyNum(p.seed, -1));
  state.ui.imageComfySteps = Math.max(1, Math.trunc(comfyNum(p.steps, 20)));
  state.ui.imageComfyGuidance = comfyNum(p.guidance, 3.5);
  state.ui.imageComfyWidth = Math.max(64, Math.trunc(comfyNum(p.width, 512)));
  state.ui.imageComfyHeight = Math.max(64, Math.trunc(comfyNum(p.height, 512)));
  state.ui.imageComfyBatch = Math.max(1, Math.trunc(comfyNum(p.batch, 1)));
  state.ui.imageComfyTimeout = Math.max(30, Math.trunc(comfyNum(p.timeout_sec, 900)));
  state.ui.imageComfyApplyDefaults = !!p.apply_defaults;
};

const captureComfyFormIntoActiveProfile = ()=>{
  const p = activeComfyProfile();
  if (!p) return null;
  p.url = String(settingImageComfyUrl?.value ?? state.ui.imageComfyUrl ?? '').trim();
  const nextWorkflow = String(settingImageComfyWorkflow?.value ?? state.ui.imageComfyWorkflow ?? '');
  const nextBindings = String(settingImageComfyBindings?.value ?? state.ui.imageComfyBindings ?? '');
  if (nextWorkflow !== String(p.workflow_json || '') || nextBindings !== String(p.bindings_json || '')) p.binding_plan_json = '';
  p.workflow_json = nextWorkflow;
  p.bindings_json = nextBindings;
  p.seed = Math.trunc(comfyNum(settingImageComfySeed?.value, state.ui.imageComfySeed ?? -1));
  p.steps = Math.max(1, Math.min(250, Math.trunc(comfyNum(settingImageComfySteps?.value, state.ui.imageComfySteps ?? 20))));
  p.guidance = comfyNum(settingImageComfyGuidance?.value, state.ui.imageComfyGuidance ?? 3.5);
  p.width = Math.max(64, Math.min(4096, Math.trunc(comfyNum(settingImageComfyWidth?.value, state.ui.imageComfyWidth ?? 512))));
  p.height = Math.max(64, Math.min(4096, Math.trunc(comfyNum(settingImageComfyHeight?.value, state.ui.imageComfyHeight ?? 512))));
  p.batch = Math.max(1, Math.min(16, Math.trunc(comfyNum(settingImageComfyBatch?.value, state.ui.imageComfyBatch ?? 1))));
  p.timeout_sec = Math.max(30, Math.min(3600, Math.trunc(comfyNum(settingImageComfyTimeout?.value, state.ui.imageComfyTimeout ?? 900))));
  p.apply_defaults = !!(settingImageComfyApplyDefaults?.checked ?? state.ui.imageComfyApplyDefaults);
  syncComfyStateFromActiveProfile();
  return p;
};

const comfyProfilesJson = ()=> JSON.stringify(ensureComfyProfiles());

const imageEditComfyProfileId = ()=>{
  try {
    if (window.crypto?.getRandomValues) {
      const a = new Uint32Array(2);
      window.crypto.getRandomValues(a);
      return `comfy_edit_${a[0].toString(16)}${a[1].toString(16)}`;
    }
  } catch(_){}
  return `comfy_edit_${Date.now().toString(36)}_${Math.random().toString(36).slice(2,10)}`;
};
const imageEditComfyNormalizeProfile = (p, fallbackId='')=>{
  const x = (p && typeof p === 'object') ? p : {};
  let id = String(x.id || fallbackId || '').trim();
  id = id.replace(/[^A-Za-z0-9_.:-]+/g, '_').replace(/^_+|_+$/g, '');
  if (!id) id = imageEditComfyProfileId();
  if (id.length > 100) id = id.slice(0,100);
  let name = String(x.name || '').trim();
  if (!name) name = 'ComfyUI Edit';
  if (name.length > 240) name = name.slice(0,240);
  const mp = parseFloatSafe(x.megapixels, 1);
  return {
    id,
    name,
    url: String(x.url || '').trim().slice(0,2048),
    workflow_json: String(x.workflow_json || ''),
    bindings_json: String(x.bindings_json || ''),
    binding_plan_json: String(x.binding_plan_json || ''),
    seed: Math.trunc(comfyNum(x.seed, -1)),
    steps: Math.max(1, Math.min(250, Math.trunc(comfyNum(x.steps, 20)))),
    guidance: comfyNum(x.guidance, 3.5),
    width: Math.max(64, Math.min(4096, Math.trunc(comfyNum(x.width, 1024)))),
    height: Math.max(64, Math.min(4096, Math.trunc(comfyNum(x.height, 1024)))),
    batch: Math.max(1, Math.min(16, Math.trunc(comfyNum(x.batch, 1)))),
    megapixels: Math.max(0.1, Math.min(64, Number.isFinite(mp) ? mp : 1)),
    timeout_sec: Math.max(30, Math.min(3600, Math.trunc(comfyNum(x.timeout_sec, 900)))),
    apply_defaults: !!x.apply_defaults,
  };
};
const imageEditComfyLegacyProfileFromState = ()=> imageEditComfyNormalizeProfile({
  id: state.ui.imageEditComfyProfileId || '',
  name: 'ComfyUI Edit',
  url: state.ui.imageEditComfyUrl || '',
  workflow_json: state.ui.imageEditComfyWorkflow || '',
  bindings_json: state.ui.imageEditComfyBindings || '',
  seed: state.ui.imageEditComfySeed ?? -1,
  steps: state.ui.imageEditComfySteps ?? 20,
  guidance: state.ui.imageEditComfyGuidance ?? 3.5,
  width: state.ui.imageEditComfyWidth ?? 1024,
  height: state.ui.imageEditComfyHeight ?? 1024,
  batch: state.ui.imageEditComfyBatch ?? 1,
  megapixels: state.ui.imageEditComfyMegapixels ?? 1,
  timeout_sec: state.ui.imageEditComfyTimeout ?? 900,
  apply_defaults: !!state.ui.imageEditComfyApplyDefaults,
});
const ensureImageEditComfyProfiles = ()=>{
  let profiles = Array.isArray(state.ui.imageEditComfyProfiles) ? state.ui.imageEditComfyProfiles : [];
  profiles = profiles.filter(p=> p && typeof p === 'object').slice(0,50).map((p,i)=> imageEditComfyNormalizeProfile(p, `comfy_edit_${i+1}`));
  if (!profiles.length) profiles = [imageEditComfyLegacyProfileFromState()];
  const seen = new Set();
  profiles.forEach(p=>{
    if (!p.id || seen.has(p.id)) p.id = imageEditComfyProfileId();
    seen.add(p.id);
  });
  state.ui.imageEditComfyProfiles = profiles;
  let selected = String(state.ui.imageEditComfyProfileId || '').trim();
  if (!profiles.some(p=>p.id === selected)) selected = profiles[0]?.id || '';
  state.ui.imageEditComfyProfileId = selected;
  return profiles;
};
const activeImageEditComfyProfile = ()=>{
  const profiles = ensureImageEditComfyProfiles();
  return profiles.find(p=>p.id === state.ui.imageEditComfyProfileId) || profiles[0];
};
const syncImageEditComfyStateFromActiveProfile = ()=>{
  const p = activeImageEditComfyProfile();
  if (!p) return;
  state.ui.imageEditComfyUrl = String(p.url || '');
  state.ui.imageEditComfyWorkflow = String(p.workflow_json || '');
  state.ui.imageEditComfyBindings = String(p.bindings_json || '');
  state.ui.imageEditComfySeed = Math.trunc(comfyNum(p.seed, -1));
  state.ui.imageEditComfySteps = Math.max(1, Math.trunc(comfyNum(p.steps, 20)));
  state.ui.imageEditComfyGuidance = comfyNum(p.guidance, 3.5);
  state.ui.imageEditComfyWidth = Math.max(64, Math.trunc(comfyNum(p.width, 1024)));
  state.ui.imageEditComfyHeight = Math.max(64, Math.trunc(comfyNum(p.height, 1024)));
  state.ui.imageEditComfyBatch = Math.max(1, Math.trunc(comfyNum(p.batch, 1)));
  state.ui.imageEditComfyMegapixels = Math.max(0.1, parseFloatSafe(p.megapixels, 1));
  state.ui.imageEditComfyTimeout = Math.max(30, Math.trunc(comfyNum(p.timeout_sec, 900)));
  state.ui.imageEditComfyApplyDefaults = !!p.apply_defaults;
};
const captureImageEditComfyFormIntoActiveProfile = ()=>{
  const p = activeImageEditComfyProfile();
  if (!p) return;
  p.url = String(settingImageEditComfyUrl?.value ?? state.ui.imageEditComfyUrl ?? '').trim();
  const nextWorkflow = String(settingImageEditComfyWorkflow?.value ?? state.ui.imageEditComfyWorkflow ?? '');
  const nextBindings = String(settingImageEditComfyBindings?.value ?? state.ui.imageEditComfyBindings ?? '');
  if (nextWorkflow !== String(p.workflow_json || '') || nextBindings !== String(p.bindings_json || '')) p.binding_plan_json = '';
  p.workflow_json = nextWorkflow;
  p.bindings_json = nextBindings;
  p.seed = Math.trunc(comfyNum(settingImageEditComfySeed?.value, state.ui.imageEditComfySeed ?? -1));
  p.steps = Math.max(1, Math.min(250, Math.trunc(comfyNum(settingImageEditComfySteps?.value, state.ui.imageEditComfySteps ?? 20))));
  p.guidance = comfyNum(settingImageEditComfyGuidance?.value, state.ui.imageEditComfyGuidance ?? 3.5);
  p.width = Math.max(64, Math.min(4096, Math.trunc(comfyNum(settingImageEditComfyWidth?.value, state.ui.imageEditComfyWidth ?? 1024))));
  p.height = Math.max(64, Math.min(4096, Math.trunc(comfyNum(settingImageEditComfyHeight?.value, state.ui.imageEditComfyHeight ?? 1024))));
  p.batch = Math.max(1, Math.min(16, Math.trunc(comfyNum(settingImageEditComfyBatch?.value, state.ui.imageEditComfyBatch ?? 1))));
  p.megapixels = Math.max(0.1, Math.min(64, parseFloatSafe(settingImageEditComfyMegapixels?.value, state.ui.imageEditComfyMegapixels ?? 1)));
  p.timeout_sec = Math.max(30, Math.min(3600, Math.trunc(comfyNum(settingImageEditComfyTimeout?.value, state.ui.imageEditComfyTimeout ?? 900))));
  p.apply_defaults = !!(settingImageEditComfyApplyDefaults?.checked ?? state.ui.imageEditComfyApplyDefaults);
  syncImageEditComfyStateFromActiveProfile();
};
const imageEditComfyProfilesJson = ()=> JSON.stringify(ensureImageEditComfyProfiles());
let imageEditComfyProfileSaveChain = Promise.resolve();
const persistImageEditComfyProfiles = (extra={})=>{
  const patch = {
    image_edit_comfyui_profiles_json: imageEditComfyProfilesJson(),
    image_edit_comfyui_profile_id: String(state.ui.imageEditComfyProfileId || ''),
    ...extra,
  };
  imageEditComfyProfileSaveChain = imageEditComfyProfileSaveChain.catch(()=>{}).then(()=> saveImageSettings(patch));
  return imageEditComfyProfileSaveChain;
};
const renderImageEditComfyProfileOptions = ()=>{
  if (!settingImageEditComfyProfile) return;
  const profiles = ensureImageEditComfyProfiles();
  const selected = String(state.ui.imageEditComfyProfileId || profiles[0]?.id || '');
  settingImageEditComfyProfile.innerHTML = profiles.map(p=>`<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('');
  settingImageEditComfyProfile.value = selected;
};

let comfyProfileSaveChain = Promise.resolve();

const persistComfyProfiles = (extra={})=>{
  // Snapshot now and serialize writes. A textarea blur followed immediately by a
  // profile switch must not let an older request overwrite the newer selection.
  const patch = {
    image_comfyui_profiles_json: comfyProfilesJson(),
    image_comfyui_profile_id: String(state.ui.imageComfyProfileId || ''),
    ...extra
  };
  comfyProfileSaveChain = comfyProfileSaveChain.catch(()=>{}).then(()=> saveImageSettings(patch));
  return comfyProfileSaveChain;
};

const renderComfyProfileOptions = ()=>{
  if (!settingImageComfyProfile) return;
  const profiles = ensureComfyProfiles();
  const selected = String(state.ui.imageComfyProfileId || profiles[0]?.id || '');
  settingImageComfyProfile.innerHTML = profiles.map(p=>`<option value="${esc(p.id)}">${esc(p.name)}</option>`).join('');
  settingImageComfyProfile.value = selected;
};

const isImageConfigured = ()=>{
  const prov = String(state.ui.imageProvider || 'openai');
  if (prov === 'openai') return !!String(state.ui.imageApiKey || '').trim();
  if (prov === 'openrouter') return !!String(state.ui.imageOpenrouterApiKey || '').trim() && !!String(state.ui.imageOpenrouterModel || '').trim();
  if (prov === 'sdcpp') return !!String(state.ui.imageSdCppBaseUrl || '').trim();
  if (prov === 'comfyui') {
    const url = String(state.ui.imageComfyUrl || '').trim();
    const wf = String(state.ui.imageComfyWorkflow || '').trim();
    return !!url && !!wf;
  }
  return false;
};


const renderOpenaiImageModelOptions = ()=>{
  if (!settingImageModel) return;
  const cur = String(state.ui.imageModel || 'gpt-image-2');
  const models = Array.isArray(state.ui.imageOpenaiModels) ? state.ui.imageOpenaiModels : [];
  const items = models.length ? models : [{ id: cur }];
  const seen = new Set();
  let html = '';
  for (const m of items){
    const id = String(m?.id || '').trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    html += `<option value="${esc(id)}">${esc(id)}</option>`;
  }
  // Preserve a previously configured/custom model even if /models does not return it
  // for the current key/project, or if OpenAI changes its image-model naming scheme.
  if (cur && !seen.has(cur)) html = `<option value="${esc(cur)}">${esc(cur)}</option>` + html;
  settingImageModel.innerHTML = html;
  settingImageModel.value = cur;
  if (settingImageModelsStatus) {
    if (state.ui.imageOpenaiModelsBusy) settingImageModelsStatus.textContent = 'Loading OpenAI image models…';
    else if (state.ui.imageOpenaiModelsError) settingImageModelsStatus.textContent = state.ui.imageOpenaiModelsError;
    else if (models.length) settingImageModelsStatus.textContent = `${models.length} image model${models.length === 1 ? '' : 's'} loaded from /models.`;
    else settingImageModelsStatus.textContent = 'OpenAI image models will be loaded from /models. The API exposes basic model metadata only, so image model IDs are filtered by naming pattern.';
  }
};

const maybeFetchOpenaiImageModels = async (force=false)=>{
  if (String(state.ui.imageProvider || 'openai') !== 'openai') return;
  if (state.ui.imageOpenaiModelsBusy) return;
  if (!force && Array.isArray(state.ui.imageOpenaiModels) && state.ui.imageOpenaiModels.length) return;
  if (!force && String(state.ui.imageOpenaiModelsError || '').trim()) return;
  // Without a key the server request cannot succeed. Keep the currently configured
  // model visible instead of producing an error on every settings render.
  if (!String(state.ui.imageApiKey || '').trim()) {
    renderOpenaiImageModelOptions();
    return;
  }
  state.ui.imageOpenaiModelsBusy = true;
  state.ui.imageOpenaiModelsError = '';
  renderOpenaiImageModelOptions();
  try{
    const r = await api('image_openai_models');
    state.ui.imageOpenaiModels = Array.isArray(r?.models) ? r.models : [];
  }catch(ex){
    state.ui.imageOpenaiModels = [];
    state.ui.imageOpenaiModelsError = ex?.message || 'Could not load OpenAI image models.';
  }finally{
    state.ui.imageOpenaiModelsBusy = false;
    renderOpenaiImageModelOptions();
  }
};

const renderOpenrouterImageModelOptions = ()=>{
  if (!settingImageOpenrouterModel) return;
  const cur = String(state.ui.imageOpenrouterModel || 'google/gemini-3-pro-image-preview');
  const models = Array.isArray(state.ui.imageOpenrouterModels) ? state.ui.imageOpenrouterModels : [];
  const items = models.length ? models : [{ id: cur, name: cur }];
  const seen = new Set();
  let html = '';
  for (const m of items){
    const id = String(m?.id || '').trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const name = String(m?.name || id);
    const label = name === id ? id : `${name} — ${id}`;
    html += `<option value="${esc(id)}">${esc(label)}</option>`;
  }
  if (cur && !seen.has(cur)) html = `<option value="${esc(cur)}">${esc(cur)}</option>` + html;
  settingImageOpenrouterModel.innerHTML = html;
  settingImageOpenrouterModel.value = cur;
  if (settingImageOpenrouterModelsStatus) {
    if (state.ui.imageOpenrouterModelsBusy) settingImageOpenrouterModelsStatus.textContent = 'Loading OpenRouter image models…';
    else if (models.length) settingImageOpenrouterModelsStatus.textContent = `${models.length} OpenRouter image models loaded from /models.`;
    else settingImageOpenrouterModelsStatus.textContent = 'OpenRouter image models will be loaded from /models?output_modalities=image.';
  }
};

const maybeFetchOpenrouterImageModels = async (force=false)=>{
  if (String(state.ui.imageProvider || 'openai') !== 'openrouter') return;
  if (state.ui.imageOpenrouterModelsBusy) return;
  if (!force && Array.isArray(state.ui.imageOpenrouterModels) && state.ui.imageOpenrouterModels.length) return;
  state.ui.imageOpenrouterModelsBusy = true;
  renderOpenrouterImageModelOptions();
  try{
    const r = await api('image_openrouter_models');
    state.ui.imageOpenrouterModels = Array.isArray(r?.models) ? r.models : [];
  }catch(ex){
    if (settingImageOpenrouterModelsStatus) settingImageOpenrouterModelsStatus.textContent = ex?.message || 'Could not load OpenRouter image models.';
  }finally{
    state.ui.imageOpenrouterModelsBusy = false;
    renderOpenrouterImageModelOptions();
  }
};

const renderImageGenerationProviderFields = ()=>{
  const prov = String(state.ui.imageProvider || 'openai');
  if (imageOpenaiFields) imageOpenaiFields.classList.toggle('hidden', prov !== 'openai');
  if (imageOpenrouterFields) imageOpenrouterFields.classList.toggle('hidden', prov !== 'openrouter');
  if (imageSdCppFields) imageSdCppFields.classList.toggle('hidden', prov !== 'sdcpp');
  if (imageComfyFields) imageComfyFields.classList.toggle('hidden', prov !== 'comfyui');
};

const renderImageSettingsUI = ()=>{
  const locked = !!(state.perms.inheritGlobalImage && String(state.user?.role || 'user') === 'user');
  if (imageInheritNote) imageInheritNote.classList.toggle('hidden', !locked);

  const setDisabled = (el, dis)=>{
    if (!el) return;
    try{ el.disabled = !!dis; }catch(_){ }
  };

  [
    // Per-user toggles must remain editable even when Image is inherited globally.
    settingImageProvider, settingImageBaseUrl, settingImageApiKey, settingImageModel, settingImageModelsRefresh,
    settingImageOpenrouterBaseUrl, settingImageOpenrouterApiKey, settingImageOpenrouterModel, settingImageOpenrouterModelsRefresh,
    settingImageSize, settingImageQuality, settingImageBackground, settingImageOutputFormat,
    settingImageComfyProfile, settingImageComfyProfileNew, settingImageComfyProfileDuplicate, settingImageComfyProfileRename, settingImageComfyProfileDelete,
    settingImageComfyUrl, settingImageComfyWorkflow, settingImageComfyBindings, settingImageComfyAutodetect,
    settingImageComfySeed, settingImageComfySteps, settingImageComfyGuidance, settingImageComfyWidth, settingImageComfyHeight,
    settingImageComfyBatch, settingImageComfyTimeout, settingImageComfyApplyDefaults,
    settingImageModeGeneration, settingImageModeEditing,
    settingImageEditComfyProfile, settingImageEditComfyProfileNew, settingImageEditComfyProfileDuplicate, settingImageEditComfyProfileRename, settingImageEditComfyProfileDelete,
    settingImageEditComfyUrl, settingImageEditComfyWorkflow, settingImageEditComfyBindings, settingImageEditComfyAutodetect,
    settingImageEditComfySeed, settingImageEditComfySteps, settingImageEditComfyGuidance, settingImageEditComfyWidth, settingImageEditComfyHeight,
    settingImageEditComfyBatch, settingImageEditComfyMegapixels, settingImageEditComfyTimeout, settingImageEditComfyApplyDefaults
  ].forEach(el=>setDisabled(el, locked));

  if (settingImageAutoEnable) settingImageAutoEnable.checked = !!state.ui.imageAutoEnable;
  if (settingVisionAutoAttachLastImage) settingVisionAutoAttachLastImage.checked = !!state.ui.visionAutoAttachLastImage;
  if (settingImageProvider) settingImageProvider.value = String(state.ui.imageProvider || 'openai');
  if (settingImageBaseUrl) settingImageBaseUrl.value = String(state.ui.imageBaseUrl || 'https://api.openai.com/v1');
  if (settingImageApiKey && settingImageApiKey !== document.activeElement) settingImageApiKey.value = String(state.ui.imageApiKey || '');
  renderOpenaiImageModelOptions();
  if (settingImageOpenrouterBaseUrl) settingImageOpenrouterBaseUrl.value = String(state.ui.imageOpenrouterBaseUrl || 'https://openrouter.ai/api/v1');
  if (settingImageOpenrouterApiKey && settingImageOpenrouterApiKey !== document.activeElement) settingImageOpenrouterApiKey.value = String(state.ui.imageOpenrouterApiKey || '');
  renderOpenrouterImageModelOptions();
  if (settingImageSize) settingImageSize.value = String(state.ui.imageSize || 'auto');
  if (settingImageQuality) settingImageQuality.value = String(state.ui.imageQuality || 'auto');
  if (settingImageBackground) settingImageBackground.value = String(state.ui.imageBackground || 'auto');
  if (settingImageOutputFormat) settingImageOutputFormat.value = String(state.ui.imageOutputFormat || 'png');

  const mode = String(state.ui.imageSettingsMode || 'generation');
  const generationActive = mode === 'generation';
  if (imageGenerationSettings) imageGenerationSettings.classList.toggle('hidden', !generationActive);
  if (imageEditingSettings) imageEditingSettings.classList.toggle('hidden', generationActive);
  if (settingImageModeGeneration) {
    settingImageModeGeneration.classList.toggle('active', generationActive);
    settingImageModeGeneration.setAttribute('aria-selected', generationActive ? 'true' : 'false');
    settingImageModeGeneration.tabIndex = generationActive ? 0 : -1;
  }
  if (settingImageModeEditing) {
    settingImageModeEditing.classList.toggle('active', !generationActive);
    settingImageModeEditing.setAttribute('aria-selected', generationActive ? 'false' : 'true');
    settingImageModeEditing.tabIndex = generationActive ? -1 : 0;
  }

  const prov = String(state.ui.imageProvider || 'openai');
  renderImageGenerationProviderFields();
  if (prov === 'openai') maybeFetchOpenaiImageModels(false);
  if (prov === 'openrouter') maybeFetchOpenrouterImageModels(false);

  if (settingImageSdCppBaseUrl) settingImageSdCppBaseUrl.value = String(state.ui.imageSdCppBaseUrl || 'http://127.0.0.1:1234/v1');
  if (settingImageSdCppApiKey && settingImageSdCppApiKey !== document.activeElement) settingImageSdCppApiKey.value = String(state.ui.imageSdCppApiKey || '');
  if (settingImageSdCppModel) settingImageSdCppModel.value = String(state.ui.imageSdCppModel || 'flux-2-klein-base-4b-Q8_0.gguf');
  if (settingImageSdCppNegativePrompt && settingImageSdCppNegativePrompt !== document.activeElement) settingImageSdCppNegativePrompt.value = String(state.ui.imageSdCppNegativePrompt || '');
  if (settingImageSdCppWidth) settingImageSdCppWidth.value = String(state.ui.imageSdCppWidth ?? 512);
  if (settingImageSdCppHeight) settingImageSdCppHeight.value = String(state.ui.imageSdCppHeight ?? 512);
  if (settingImageSdCppBatch) settingImageSdCppBatch.value = String(state.ui.imageSdCppBatch ?? 1);
  if (settingImageSdCppSeed) settingImageSdCppSeed.value = String(state.ui.imageSdCppSeed ?? -1);
  if (settingImageSdCppSteps) settingImageSdCppSteps.value = String(state.ui.imageSdCppSteps ?? 20);
  if (settingImageSdCppCfgScale) settingImageSdCppCfgScale.value = String(state.ui.imageSdCppCfgScale ?? 7);
  if (settingImageSdCppGuidance) settingImageSdCppGuidance.value = String(state.ui.imageSdCppGuidance ?? 3.5);
  if (settingImageSdCppSamplingMethod) settingImageSdCppSamplingMethod.value = String(state.ui.imageSdCppSamplingMethod || '');
  if (settingImageSdCppScheduler) settingImageSdCppScheduler.value = String(state.ui.imageSdCppScheduler || '');
  if (settingImageSdCppFlowShift) settingImageSdCppFlowShift.value = String(state.ui.imageSdCppFlowShift || '');
  if (settingImageSdCppExtraArgs) settingImageSdCppExtraArgs.value = String(state.ui.imageSdCppExtraArgs || '');
  if (settingImageSdCppTimeout) settingImageSdCppTimeout.value = String(state.ui.imageSdCppTimeout ?? 900);
  if (settingImageSdCppAutoVaeTiling768) settingImageSdCppAutoVaeTiling768.checked = !!state.ui.imageSdCppAutoVaeTiling768;

  renderComfyProfileOptions();
  if (settingImageComfyProfileDelete) settingImageComfyProfileDelete.disabled = locked || ensureComfyProfiles().length <= 1;
  if (settingImageComfyUrl) settingImageComfyUrl.value = String(state.ui.imageComfyUrl || '');
  if (settingImageComfyWorkflow && settingImageComfyWorkflow !== document.activeElement) settingImageComfyWorkflow.value = String(state.ui.imageComfyWorkflow || '');
  if (settingImageComfyBindings && settingImageComfyBindings !== document.activeElement) settingImageComfyBindings.value = String(state.ui.imageComfyBindings || '');
  if (settingImageComfySeed) settingImageComfySeed.value = String(state.ui.imageComfySeed ?? -1);
  if (settingImageComfySteps) settingImageComfySteps.value = String(state.ui.imageComfySteps ?? 20);
  if (settingImageComfyGuidance) settingImageComfyGuidance.value = String(state.ui.imageComfyGuidance ?? 3.5);
  if (settingImageComfyWidth) settingImageComfyWidth.value = String(state.ui.imageComfyWidth ?? 512);
  if (settingImageComfyHeight) settingImageComfyHeight.value = String(state.ui.imageComfyHeight ?? 512);
  if (settingImageComfyBatch) settingImageComfyBatch.value = String(state.ui.imageComfyBatch ?? 1);
  if (settingImageComfyTimeout) settingImageComfyTimeout.value = String(state.ui.imageComfyTimeout ?? 900);
  if (settingImageComfyApplyDefaults) settingImageComfyApplyDefaults.checked = !!state.ui.imageComfyApplyDefaults;

  renderImageEditComfyProfileOptions();
  if (settingImageEditComfyProfileDelete) settingImageEditComfyProfileDelete.disabled = locked || ensureImageEditComfyProfiles().length <= 1;
  if (settingImageEditComfyUrl) settingImageEditComfyUrl.value = String(state.ui.imageEditComfyUrl || '');
  if (settingImageEditComfyWorkflow && settingImageEditComfyWorkflow !== document.activeElement) settingImageEditComfyWorkflow.value = String(state.ui.imageEditComfyWorkflow || '');
  if (settingImageEditComfyBindings && settingImageEditComfyBindings !== document.activeElement) settingImageEditComfyBindings.value = String(state.ui.imageEditComfyBindings || '');
  if (settingImageEditComfySeed) settingImageEditComfySeed.value = String(state.ui.imageEditComfySeed ?? -1);
  if (settingImageEditComfySteps) settingImageEditComfySteps.value = String(state.ui.imageEditComfySteps ?? 20);
  if (settingImageEditComfyGuidance) settingImageEditComfyGuidance.value = String(state.ui.imageEditComfyGuidance ?? 3.5);
  if (settingImageEditComfyWidth) settingImageEditComfyWidth.value = String(state.ui.imageEditComfyWidth ?? 1024);
  if (settingImageEditComfyHeight) settingImageEditComfyHeight.value = String(state.ui.imageEditComfyHeight ?? 1024);
  if (settingImageEditComfyBatch) settingImageEditComfyBatch.value = String(state.ui.imageEditComfyBatch ?? 1);
  if (settingImageEditComfyMegapixels) settingImageEditComfyMegapixels.value = String(state.ui.imageEditComfyMegapixels ?? 1);
  if (settingImageEditComfyTimeout) settingImageEditComfyTimeout.value = String(state.ui.imageEditComfyTimeout ?? 900);
  if (settingImageEditComfyApplyDefaults) settingImageEditComfyApplyDefaults.checked = !!state.ui.imageEditComfyApplyDefaults;

  // Also reflect disable state in the composer popover.
  renderWebTools();
};


// Voice (record -> transcribe -> send)
state.voice = { enabled:false, recording:false, busy:false, mediaRecorder:null, chunks:[], stream:null };

// Browser TTS (read aloud per message)
state.tts = { speaking:false, msgIndex:-1, utterance:null, audio:null, objectUrl:null, queue:null, provider:'browser', pending:false, abort:null, mediaSource:null, sourceBuffer:null, userStopRequested:false };

function stopTts(){
  // Stop Browser TTS
  try{
    if ('speechSynthesis' in window) window.speechSynthesis.cancel();
  }catch(_){ }

  // Stop OpenAI-audio playback
  try{
    if (state.tts.audio){
      state.tts.audio.pause();
      state.tts.audio.currentTime = 0;
    }
  
  // Abort any in-flight OpenAI TTS fetch
  try{
    if (state.tts.abort){
      state.tts.abort.abort();
    }
  }catch(_){ }

}catch(_){ }

  try{
    if (state.tts.objectUrl) URL.revokeObjectURL(state.tts.objectUrl);
  }catch(_){ }

  state.tts.speaking = false;
  state.tts.msgIndex = -1;
  state.tts.utterance = null;
  state.tts.audio = null;
  state.tts.objectUrl = null;
  state.tts.queue = null;
  state.tts.pending = false;
  state.tts.abort = null;
  state.tts.mediaSource = null;
  state.tts.sourceBuffer = null;
  updateTtsButtons();
}

function updateTtsButtons(){
  // Highlight the active speak button (if any)
  try{
    document.querySelectorAll('.message .action-btn[data-action="speak"]').forEach(btn=>{
      const msgEl = btn.closest('.message');
      const idx = parseInt(msgEl?.dataset.msgIndex || '-1', 10);
      const on = state.tts.speaking && idx === state.tts.msgIndex;
      btn.classList.toggle('active', !!on);
      btn.title = on ? 'Stop reading' : 'Read aloud';
      btn.setAttribute('aria-label', on ? 'Stop reading' : 'Read aloud');
    });
  }catch(_){ }
}

function speakMessage(idx){
  const prov = String(state.ui.voiceTtsProvider || 'browser');
  if (prov === 'openai') {
    speakMessageOpenAI(idx);
  } else {
    speakMessageBrowser(idx);
  }
}

function speakMessageBrowser(idx){
  const txt = String(state.currentChat?.messages?.[idx]?.content || '').trim();
  if (!txt) return;
  if (!('speechSynthesis' in window) || typeof window.SpeechSynthesisUtterance !== 'function'){
    alert('Text-to-speech is not supported by this browser.');
    return;
  }
  // Toggle off if the same message is currently speaking.
  if (state.tts.speaking && state.tts.msgIndex === idx){
    stopTts();
    return;
  }

  // Stop anything currently playing.
  stopTts();

  const u = new SpeechSynthesisUtterance(txt);
  // Best-effort language: prefer German if UI is German; fallback to browser locale.
  const lang = (String(navigator.language||'').toLowerCase().startsWith('de')) ? 'de-DE' : String(navigator.language || 'en-US');
  u.lang = lang;
  u.rate = 1;
  u.pitch = 1;
  u.onend = ()=>{ stopTts(); };
  u.onerror = ()=>{ stopTts(); };

  state.tts.speaking = true;
  state.tts.msgIndex = idx;
  state.tts.utterance = u;
  state.tts.provider = 'browser';
  updateTtsButtons();
  try{ window.speechSynthesis.speak(u); }catch(_){ stopTts(); }
}

function splitTextForTts(text, maxLen){
  const out = [];
  let t = String(text||'').trim();
  if (!t) return out;
  const max = Math.max(800, Number(maxLen||3900));
  while (t.length > max){
    let cut = t.lastIndexOf('\n', max);
    if (cut < Math.floor(max*0.55)) cut = t.lastIndexOf('. ', max);
    if (cut < Math.floor(max*0.55)) cut = t.lastIndexOf('! ', max);
    if (cut < Math.floor(max*0.55)) cut = t.lastIndexOf('? ', max);
    if (cut < Math.floor(max*0.55)) cut = max;
    out.push(t.slice(0, cut).trim());
    t = t.slice(cut).trim();
  }
  if (t) out.push(t);
  return out;
}

async function fetchOpenAiSpeechBlob(inputText, voice, model){
  const res = await fetch('api.php?action=voice_speech', {
    method: 'POST',
    headers: { 'Content-Type':'application/json', 'Accept':'audio/mpeg, audio/*;q=0.9, application/json;q=0.8' },
    body: JSON.stringify({ input: inputText, voice, model })
  });

  const ct = (res.headers.get('content-type') || '').toLowerCase();
  if (!res.ok){
    // Try to read JSON error
    let msg = `${res.status} ${res.statusText}`;
    try{
      if (ct.includes('application/json')){
        const j = await res.json();
        if (j && j.error) msg = String(j.error);
      } else {
        msg = String(await res.text() || msg);
      }
    }catch(_){ }
    if (res.status === 401 && typeof window.llcShowLogin === 'function'){
      window.llcShowLogin(msg || 'Unauthorized');
    }
    throw new Error(msg);
  }

  if (ct.includes('application/json')){
    const j = await res.json();
    throw new Error(String(j?.error || 'Unexpected JSON response'));
  }
  return await res.blob();
}


async function playOpenAiSpeechStreamChunk(inputText, voice, model){
  // Progressive streaming playback via MediaSource.
  // Falls back to full buffering if the browser doesn't support MSE for audio/mpeg.
  const mime = 'audio/mpeg';

  const canStream = (typeof window.MediaSource !== 'undefined') &&
                    (typeof MediaSource.isTypeSupported === 'function') &&
                    MediaSource.isTypeSupported(mime);

  if (!canStream){
    // Fallback: buffer the whole blob
    const blob = await fetchOpenAiSpeechBlob(inputText, voice, model);
    const url = URL.createObjectURL(blob);
    state.tts.objectUrl = url;
    const a = new Audio(url);
    state.tts.audio = a;
    await a.play();
    return await new Promise((resolve, reject)=>{
      a.onended = ()=>resolve();
      a.onerror = ()=>reject(new Error('Audio playback failed'));
    });
  }

  // Clean up previous URL
  try{ if (state.tts.objectUrl) URL.revokeObjectURL(state.tts.objectUrl); }catch(_){ }
  const ms = new MediaSource();
  state.tts.mediaSource = ms;

  const url = URL.createObjectURL(ms);
  state.tts.objectUrl = url;

  const a = new Audio();
  state.tts.audio = a;
  a.preload = 'auto';
  a.src = url;

  const controller = new AbortController();
  state.tts.abort = controller;

  const sourceOpen = new Promise((resolve)=> ms.addEventListener('sourceopen', resolve, { once:true }));
  await sourceOpen;

  let sb;
  try{
    sb = ms.addSourceBuffer(mime);
    sb.mode = 'sequence';
    state.tts.sourceBuffer = sb;
  }catch(e){
    // If we can't create the SourceBuffer, fall back to blob mode.
    controller.abort();
    try{ if (state.tts.objectUrl) URL.revokeObjectURL(state.tts.objectUrl); }catch(_){ }
    state.tts.objectUrl = null;
    state.tts.mediaSource = null;
    state.tts.sourceBuffer = null;
    const blob = await fetchOpenAiSpeechBlob(inputText, voice, model);
    const u = URL.createObjectURL(blob);
    state.tts.objectUrl = u;
    const aa = new Audio(u);
    state.tts.audio = aa;
    await aa.play();
    return await new Promise((resolve, reject)=>{
      aa.onended = ()=>resolve();
      aa.onerror = ()=>reject(new Error('Audio playback failed'));
    });
  }

  const res = await fetch('api.php?action=voice_speech_stream', {
    method: 'POST',
    headers: { 'Content-Type':'application/json', 'Accept':'audio/mpeg, audio/*;q=0.9, application/json;q=0.8' },
    body: JSON.stringify({ input: inputText, voice, model }),
    signal: controller.signal,
  });

  const ct = (res.headers.get('content-type') || '').toLowerCase();
  if (!res.ok){
    let msg = `${res.status} ${res.statusText}`;
    try{
      if (ct.includes('application/json')){
        const j = await res.json();
        if (j && j.error) msg = String(j.error);
      }else{
        const t = await res.text();
        if (t) msg = t;
      }
    }catch(_){ }
    throw new Error(msg);
  }

  const reader = res.body?.getReader?.();
  if (!reader){
    // No streaming body; fall back to buffering
    const blob = await res.blob();
    const u = URL.createObjectURL(blob);
    try{ if (state.tts.objectUrl) URL.revokeObjectURL(state.tts.objectUrl); }catch(_){ }
    state.tts.objectUrl = u;
    a.src = u;
    await a.play();
    return await new Promise((resolve, reject)=>{
      a.onended = ()=>resolve();
      a.onerror = ()=>reject(new Error('Audio playback failed'));
    });
  }

  const append = (u8)=>{
    return new Promise((resolve, reject)=>{
      const doAppend = ()=>{
        try{
          sb.appendBuffer(u8);
          sb.addEventListener('updateend', ()=>resolve(), { once:true });
        }catch(e){
          reject(e);
        }
      };
      if (sb.updating){
        sb.addEventListener('updateend', doAppend, { once:true });
      }else{
        doAppend();
      }
    });
  };

  let started = false;

  try{
    while(true){
      const { done, value } = await reader.read();
      if (done) break;
      if (value && value.byteLength){
        await append(value);
        if (!started){
          started = true;
          try{ await a.play(); }catch(_){ /* user gesture required; ignore */ }
        }
      }
    }
    // Wait for last update to finish
    if (sb.updating){
      await new Promise(resolve=> sb.addEventListener('updateend', resolve, { once:true }));
    }
    try{ ms.endOfStream(); }catch(_){ }

    // Wait until playback ends (or is stopped)
    await new Promise((resolve, reject)=>{
      a.onended = ()=>resolve();
      a.onerror = ()=>reject(new Error('Audio playback failed'));
    });
  } catch(err){
    const msg = (err?.message || String(err));
    const aborted = (controller.signal.aborted || err?.name === 'AbortError' || /aborted/i.test(msg));
    if (aborted){
      // Expected when the user presses Stop.
      state.tts.userStopRequested = false;
      return;
    }
    throw err;
  } finally {
    try{ reader.releaseLock?.(); }catch(_){ }
  }
}



async function playNextOpenAiChunk(){
  if (!state.tts.queue || state.tts.queue.length === 0){
    stopTts();
    return;
  }
  if (state.tts.pending) return;
  state.tts.pending = true;

  const chunk = state.tts.queue.shift();
  try{
    const voice = String(state.ui.voiceTtsVoice || 'marin') || 'marin';
    const model = String(state.ui.voiceTtsModel || 'gpt-4o-mini-tts') || 'gpt-4o-mini-tts';

    await playOpenAiSpeechStreamChunk(chunk, voice, model);

    state.tts.pending = false;

    // Cleanup chunk URL after playback
    try{ if (state.tts.objectUrl) URL.revokeObjectURL(state.tts.objectUrl); }catch(_){ }
    state.tts.objectUrl = null;
    state.tts.audio = null;
    state.tts.mediaSource = null;
    state.tts.sourceBuffer = null;
    state.tts.abort = null;

    // next chunk
    playNextOpenAiChunk();
  }catch(err){
    state.tts.pending = false;
    const msg = (err?.message || String(err));
    const aborted = (state.tts.userStopRequested || err?.name === 'AbortError' || /aborted/i.test(msg));
    if (aborted){
      // User pressed stop (or the request was aborted). Don't show an error.
      stopTts();
      state.tts.userStopRequested = false;
      return;
    }
    console.error(err);
    alert('Vorlesen (OpenAI) fehlgeschlagen: ' + msg);
    stopTts();
  }
}

function speakMessageOpenAI(idx){
  const txt = String(state.currentChat?.messages?.[idx]?.content || '').trim();
  if (!txt) return;

  // Toggle off if the same message is currently speaking.
  if (state.tts.speaking && state.tts.msgIndex === idx){
    state.tts.userStopRequested = true;
    stopTts();
    return;
  }
  state.tts.userStopRequested = false;


  // Need key (we don't validate it client-side, but we can give a friendly hint)
  const hasKey = !!String(state.ui.voiceApiKey||'').trim();
  if (!hasKey){
    alert('Kein Voice API Key gesetzt (Settings → Voice).');
    return;
  }

  stopTts();

  state.tts.speaking = true;
  state.tts.msgIndex = idx;
  state.tts.provider = 'openai';
  state.tts.queue = splitTextForTts(txt, 3900); // OpenAI speech endpoint max input is 4096 chars
  updateTtsButtons();
  playNextOpenAiChunk();
}

function renderVoiceUI(){
  if (!voiceBtn) return;
  const hasKey = !!String(state.ui.voiceApiKey||'').trim();
  const show = !!state.ui.voiceAutoEnable;
  voiceBtn.classList.toggle('hidden', !show);
  voiceBtn.disabled = !show || !hasKey || isCurrentChatStreaming() || !!state.webFetchBusy || !!state.voice.busy;
  voiceBtn.classList.toggle('active', !!state.voice.recording);
  voiceBtn.title = !hasKey ? 'Set Voice API key in Settings → Voice' : (state.voice.recording ? 'Stop recording' : 'Voice');
}

async function startVoiceRecording(){
  if (!voiceBtn) return;
  const hasKey = !!String(state.ui.voiceApiKey||'').trim();
  if (!hasKey){ renderVoiceUI(); return; }
  if (state.voice.recording || state.voice.busy) return;
  try{
    const stream = await navigator.mediaDevices.getUserMedia({ audio:true });
    state.voice.stream = stream;
    const opts = {};
    const prefer = 'audio/webm;codecs=opus';
    if (window.MediaRecorder && MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported(prefer)) opts.mimeType = prefer;
    const rec = new MediaRecorder(stream, opts);
    state.voice.mediaRecorder = rec;
    state.voice.chunks = [];
    rec.ondataavailable = (e)=>{ if (e.data && e.data.size>0) state.voice.chunks.push(e.data); };
    rec.onstop = async ()=>{
      const chunks = state.voice.chunks || [];
      const blob = new Blob(chunks, { type: (chunks[0]?.type || 'audio/webm') });
      try{ state.voice.stream?.getTracks?.().forEach(t=>t.stop()); }catch(_){ }
      state.voice.stream = null;
      state.voice.mediaRecorder = null;
      state.voice.chunks = [];
      state.voice.recording = false;
      renderVoiceUI();
      if (blob.size < 1024) return;
      await transcribeAndSend(blob);
    };
    rec.start();
    state.voice.recording = true;
    renderVoiceUI();
  }catch(err){
    console.warn('Voice start failed', err);
    alert('Mic error: ' + (err?.message||String(err)));
    state.voice.recording = false;
    renderVoiceUI();
  }
}

function stopVoiceRecording(){
  const rec = state.voice.mediaRecorder;
  if (!rec) return;
  try{ rec.stop(); }catch(_){ }
  state.voice.recording = false;
  renderVoiceUI();
}

async function transcribeAndSend(blob){
  state.voice.busy = true;
  renderVoiceUI();
  try{
    const fd = new FormData();
    fd.append('audio', blob, 'voice.webm');
    const res = await fetch('api.php?action=voice_transcribe', { method:'POST', body: fd });
    const ct = res.headers.get('content-type') || '';
    if (!res.ok){
      let msg = `${res.status} ${res.statusText}`;
      try{ msg = ct.includes('application/json') ? (await res.json()).error : await res.text(); }catch(_){ }
      throw new Error(msg);
    }
    const j = ct.includes('application/json') ? await res.json() : { text: await res.text() };
    const text = String(j.text || '').trim();
    if (!text) return;
    textarea.value = text;
    textarea.dispatchEvent(new Event('input'));
    // Dictation behavior is configurable: either auto-send or just fill the composer.
    if (state.ui.voiceAutoSend) {
      await send();
    } else {
      try{ textarea.focus(); }catch(_){ }
      // move cursor to end
      try{ textarea.selectionStart = textarea.selectionEnd = textarea.value.length; }catch(_){ }
      syncSend();
    }
  }catch(err){
    console.warn('Transcribe failed', err);
    alert('Voice failed: ' + (err?.message||String(err)));
  }finally{
    state.voice.busy = false;
    renderVoiceUI();
    syncSend();
  }
}

voiceBtn?.addEventListener('click', (e)=>{
  e.preventDefault();
  if (state.voice.recording) stopVoiceRecording();
  else startVoiceRecording();
});

// Settings handlers
settingVoiceApiKey?.addEventListener('change', async ()=>{
  state.ui.voiceApiKey = String(settingVoiceApiKey.value || '');
  try{ await api('settings_save', { voice_api_key: state.ui.voiceApiKey }); }catch(_){ }
  renderVoiceUI();
  syncSend();
});
settingVoiceAutoEnable?.addEventListener('change', async ()=>{
  state.ui.voiceAutoEnable = !!settingVoiceAutoEnable.checked;
  try{ await api('settings_save', { voice_auto_enable: state.ui.voiceAutoEnable ? 1 : 0 }); }catch(_){ }
  renderVoiceUI();
  syncSend();
});

settingVoiceAutoSend?.addEventListener('change', async ()=>{
  state.ui.voiceAutoSend = !!settingVoiceAutoSend.checked;
  try{ await api('settings_save', { voice_auto_send: state.ui.voiceAutoSend ? 1 : 0 }); }catch(_){ }
  // no UI dependency beyond behavior
});


const renderVoiceSettingsUI = ()=>{
  const locked = !!(state.perms.inheritGlobalVoice && state.user && String(state.user.role||'user')==='user');
  if (voiceInheritNote) voiceInheritNote.classList.toggle('hidden', !locked);

  const setDisabled = (el, dis)=>{ try{ if(el) el.disabled = !!dis; }catch(_){ } };
  // Per-user toggles must remain editable even when Voice is inherited globally.
  [
    settingVoiceApiKey,
    settingVoiceTtsProvider, settingVoiceTtsModel, settingVoiceTtsVoice
  ].forEach(el=> setDisabled(el, locked));

  if (settingVoiceApiKey && settingVoiceApiKey !== document.activeElement) settingVoiceApiKey.value = String(state.ui.voiceApiKey || '');
  if (settingVoiceAutoEnable) settingVoiceAutoEnable.checked = !!state.ui.voiceAutoEnable;
  if (settingVoiceAutoSend) settingVoiceAutoSend.checked = !!state.ui.voiceAutoSend;

  // Keep read-aloud UI in sync.
  renderVoiceTtsSettingsUI();
};

const renderVoiceTtsSettingsUI = ()=>{
  const prov = String(state.ui.voiceTtsProvider || 'browser');
  if (settingVoiceTtsProvider) settingVoiceTtsProvider.value = prov;
  if (voiceTtsOpenaiFields) voiceTtsOpenaiFields.classList.toggle('hidden', prov !== 'openai');
  if (settingVoiceTtsModel) settingVoiceTtsModel.value = String(state.ui.voiceTtsModel || 'gpt-4o-mini-tts');
  if (settingVoiceTtsVoice) settingVoiceTtsVoice.value = String(state.ui.voiceTtsVoice || 'marin');
};

settingVoiceTtsProvider?.addEventListener('change', async ()=>{
  state.ui.voiceTtsProvider = String(settingVoiceTtsProvider.value || 'browser');
  try{ await api('settings_save', { voice_tts_provider: state.ui.voiceTtsProvider }); }catch(_){ }
  // If something is currently speaking, stop it (provider switch).
  stopTts();
  renderVoiceTtsSettingsUI();
});


settingVoiceTtsModel?.addEventListener('change', async ()=>{
  state.ui.voiceTtsModel = String(settingVoiceTtsModel.value || 'gpt-4o-mini-tts');
  try{ await api('settings_save', { voice_tts_model: state.ui.voiceTtsModel }); }catch(_){ }
  // If something is currently speaking, stop it (model switch).
  stopTts();
  renderVoiceTtsSettingsUI();
});

settingVoiceTtsVoice?.addEventListener('change', async ()=>{
  state.ui.voiceTtsVoice = String(settingVoiceTtsVoice.value || 'marin');
  try{ await api('settings_save', { voice_tts_voice: state.ui.voiceTtsVoice }); }catch(_){ }
});



const saveImageSettings = async (patch)=>{
  try { await api('settings_save', patch); } catch(_){ /* ignore */ }
};

settingImageAutoEnable?.addEventListener('change', async ()=>{
  state.ui.imageAutoEnable = !!settingImageAutoEnable.checked;
  await saveImageSettings({ image_auto_enable: state.ui.imageAutoEnable ? 1 : 0 });

  const hasOverride = !!(state.currentChat?.meta && state.currentChat.meta.webtools);
  if (!hasOverride) {
    state.webtools.image = !!state.ui.imageAutoEnable;
        state.webtools.document = false;
        state.webtools.custom_tools = defaultCustomToolNames();
        state.webtools.mcp_servers = defaultMcpServerIds();
    renderWebTools();
  }
});


settingVisionAutoAttachLastImage?.addEventListener('change', async ()=>{
  state.ui.visionAutoAttachLastImage = !!settingVisionAutoAttachLastImage.checked;
  await saveImageSettings({ vision_auto_attach_last_image: state.ui.visionAutoAttachLastImage ? 1 : 0 });
});

let imageProviderSaveChain = Promise.resolve();
settingImageProvider?.addEventListener('change', async ()=>{
  const provider = String(settingImageProvider.value || 'openai');
  state.ui.imageProvider = provider;
  if (provider === 'openai') {
    state.ui.imageBaseUrl = String(state.ui.imageBaseUrl || 'https://api.openai.com/v1');
  }
  if (provider === 'openrouter') {
    state.ui.imageOpenrouterBaseUrl = String(state.ui.imageOpenrouterBaseUrl || 'https://openrouter.ai/api/v1');
    state.ui.imageOpenrouterModel = String(state.ui.imageOpenrouterModel || 'google/gemini-3-pro-image-preview');
  }
  if (provider === 'sdcpp') {
    state.ui.imageSdCppBaseUrl = String(state.ui.imageSdCppBaseUrl || 'http://127.0.0.1:1234/v1');
    state.ui.imageSdCppModel = String(state.ui.imageSdCppModel || 'flux-2-klein-base-4b-Q8_0.gguf');
  }

  // Provider switching is a local UI operation first. Do not wait for the
  // settings request or rebuild the Generation/Editing tab before showing the
  // selected provider's fields.
  renderImageGenerationProviderFields();
  renderWebTools();
  if (provider === 'openai') maybeFetchOpenaiImageModels(true);
  if (provider === 'openrouter') maybeFetchOpenrouterImageModels(true);

  // Preserve user order when switching quickly (e.g. ComfyUI -> OpenRouter -> OpenAI).
  imageProviderSaveChain = imageProviderSaveChain
    .catch(()=>{})
    .then(()=> saveImageSettings({ image_provider: provider }));
  await imageProviderSaveChain;
});

settingImageBaseUrl?.addEventListener('change', async ()=>{
  state.ui.imageBaseUrl = String(settingImageBaseUrl.value || '').trim() || 'https://api.openai.com/v1';
  state.ui.imageOpenaiModels = [];
  state.ui.imageOpenaiModelsError = '';
  await saveImageSettings({ image_base_url: state.ui.imageBaseUrl });
  renderImageSettingsUI();
  maybeFetchOpenaiImageModels(true);
});

settingImageApiKey?.addEventListener('change', async ()=>{
  state.ui.imageApiKey = String(settingImageApiKey.value || '');
  state.ui.imageOpenaiModels = [];
  state.ui.imageOpenaiModelsError = '';
  await saveImageSettings({ image_api_key: state.ui.imageApiKey });
  renderImageSettingsUI();
  maybeFetchOpenaiImageModels(true);
});

settingImageModel?.addEventListener('change', async ()=>{
  state.ui.imageModel = String(settingImageModel.value || 'gpt-image-2');
  await saveImageSettings({ image_model: state.ui.imageModel });
  renderImageSettingsUI();
});

settingImageModelsRefresh?.addEventListener('click', async ()=>{
  state.ui.imageOpenaiModels = [];
  state.ui.imageOpenaiModelsError = '';
  await maybeFetchOpenaiImageModels(true);
});

settingImageOpenrouterBaseUrl?.addEventListener('change', async ()=>{
  state.ui.imageOpenrouterBaseUrl = String(settingImageOpenrouterBaseUrl.value || '').trim() || 'https://openrouter.ai/api/v1';
  state.ui.imageOpenrouterModels = [];
  await saveImageSettings({ image_openrouter_base_url: state.ui.imageOpenrouterBaseUrl });
  renderImageSettingsUI();
  maybeFetchOpenrouterImageModels(true);
});

settingImageOpenrouterApiKey?.addEventListener('change', async ()=>{
  state.ui.imageOpenrouterApiKey = String(settingImageOpenrouterApiKey.value || '');
  state.ui.imageOpenrouterModels = [];
  await saveImageSettings({ image_openrouter_api_key: state.ui.imageOpenrouterApiKey });
  renderImageSettingsUI();
  maybeFetchOpenrouterImageModels(true);
});

settingImageOpenrouterModel?.addEventListener('change', async ()=>{
  state.ui.imageOpenrouterModel = String(settingImageOpenrouterModel.value || 'google/gemini-3-pro-image-preview');
  await saveImageSettings({ image_openrouter_model: state.ui.imageOpenrouterModel });
  renderImageSettingsUI();
});

settingImageOpenrouterModelsRefresh?.addEventListener('click', async ()=>{
  state.ui.imageOpenrouterModels = [];
  await maybeFetchOpenrouterImageModels(true);
});


settingImageSdCppBaseUrl?.addEventListener('change', async ()=>{ state.ui.imageSdCppBaseUrl = String(settingImageSdCppBaseUrl.value || '').trim() || 'http://127.0.0.1:1234/v1'; await saveImageSettings({ image_sdcpp_base_url: state.ui.imageSdCppBaseUrl }); renderImageSettingsUI(); });
settingImageSdCppApiKey?.addEventListener('change', async ()=>{ state.ui.imageSdCppApiKey = String(settingImageSdCppApiKey.value || ''); await saveImageSettings({ image_sdcpp_api_key: state.ui.imageSdCppApiKey }); renderImageSettingsUI(); });
settingImageSdCppModel?.addEventListener('change', async ()=>{ state.ui.imageSdCppModel = String(settingImageSdCppModel.value || 'flux-2-klein-base-4b-Q8_0.gguf'); await saveImageSettings({ image_sdcpp_model: state.ui.imageSdCppModel }); renderImageSettingsUI(); });
settingImageSdCppNegativePrompt?.addEventListener('change', async ()=>{ state.ui.imageSdCppNegativePrompt = String(settingImageSdCppNegativePrompt.value || ''); await saveImageSettings({ image_sdcpp_negative_prompt: state.ui.imageSdCppNegativePrompt }); });
settingImageSdCppWidth?.addEventListener('change', async ()=>{ state.ui.imageSdCppWidth = Math.max(64, parseIntSafe(settingImageSdCppWidth.value, 512)); await saveImageSettings({ image_sdcpp_width: state.ui.imageSdCppWidth }); });
settingImageSdCppHeight?.addEventListener('change', async ()=>{ state.ui.imageSdCppHeight = Math.max(64, parseIntSafe(settingImageSdCppHeight.value, 512)); await saveImageSettings({ image_sdcpp_height: state.ui.imageSdCppHeight }); });
settingImageSdCppBatch?.addEventListener('change', async ()=>{ state.ui.imageSdCppBatch = Math.max(1, parseIntSafe(settingImageSdCppBatch.value, 1)); await saveImageSettings({ image_sdcpp_batch: state.ui.imageSdCppBatch }); });
settingImageSdCppSeed?.addEventListener('change', async ()=>{ state.ui.imageSdCppSeed = parseIntSafe(settingImageSdCppSeed.value, -1); await saveImageSettings({ image_sdcpp_seed: state.ui.imageSdCppSeed }); });
settingImageSdCppSteps?.addEventListener('change', async ()=>{ state.ui.imageSdCppSteps = Math.max(1, parseIntSafe(settingImageSdCppSteps.value, 20)); await saveImageSettings({ image_sdcpp_steps: state.ui.imageSdCppSteps }); });
settingImageSdCppCfgScale?.addEventListener('change', async ()=>{ state.ui.imageSdCppCfgScale = parseFloatSafe(settingImageSdCppCfgScale.value, 7); await saveImageSettings({ image_sdcpp_cfg_scale: state.ui.imageSdCppCfgScale }); });
settingImageSdCppGuidance?.addEventListener('change', async ()=>{ state.ui.imageSdCppGuidance = parseFloatSafe(settingImageSdCppGuidance.value, 3.5); await saveImageSettings({ image_sdcpp_guidance: state.ui.imageSdCppGuidance }); });
settingImageSdCppSamplingMethod?.addEventListener('change', async ()=>{ state.ui.imageSdCppSamplingMethod = String(settingImageSdCppSamplingMethod.value || '').trim(); await saveImageSettings({ image_sdcpp_sampling_method: state.ui.imageSdCppSamplingMethod }); });
settingImageSdCppScheduler?.addEventListener('change', async ()=>{ state.ui.imageSdCppScheduler = String(settingImageSdCppScheduler.value || '').trim(); await saveImageSettings({ image_sdcpp_scheduler: state.ui.imageSdCppScheduler }); });
settingImageSdCppFlowShift?.addEventListener('change', async ()=>{ state.ui.imageSdCppFlowShift = String(settingImageSdCppFlowShift.value || '').trim(); await saveImageSettings({ image_sdcpp_flow_shift: state.ui.imageSdCppFlowShift }); });
settingImageSdCppExtraArgs?.addEventListener('change', async ()=>{ state.ui.imageSdCppExtraArgs = String(settingImageSdCppExtraArgs.value || '').trim(); await saveImageSettings({ image_sdcpp_extra_args: state.ui.imageSdCppExtraArgs }); });
settingImageSdCppTimeout?.addEventListener('change', async ()=>{ state.ui.imageSdCppTimeout = Math.max(30, parseIntSafe(settingImageSdCppTimeout.value, 900)); await saveImageSettings({ image_sdcpp_timeout_sec: state.ui.imageSdCppTimeout }); });
settingImageSdCppAutoVaeTiling768?.addEventListener('change', async ()=>{ state.ui.imageSdCppAutoVaeTiling768 = !!settingImageSdCppAutoVaeTiling768.checked; await saveImageSettings({ image_sdcpp_auto_vae_tiling_768: state.ui.imageSdCppAutoVaeTiling768 ? 1 : 0 }); });

settingImageSize?.addEventListener('change', async ()=>{
  state.ui.imageSize = String(settingImageSize.value || 'auto');
  await saveImageSettings({ image_size: state.ui.imageSize });
  renderImageSettingsUI();
});

settingImageQuality?.addEventListener('change', async ()=>{
  state.ui.imageQuality = String(settingImageQuality.value || 'auto');
  await saveImageSettings({ image_quality: state.ui.imageQuality });
  renderImageSettingsUI();
});

settingImageBackground?.addEventListener('change', async ()=>{
  state.ui.imageBackground = String(settingImageBackground.value || 'auto');
  await saveImageSettings({ image_background: state.ui.imageBackground });
  renderImageSettingsUI();
});

settingImageOutputFormat?.addEventListener('change', async ()=>{
  state.ui.imageOutputFormat = String(settingImageOutputFormat.value || 'png');
  await saveImageSettings({ image_output_format: state.ui.imageOutputFormat });
  renderImageSettingsUI();
});


// ComfyUI image settings
const parseIntSafe = (v, fallback)=>{
  const n = parseInt(String(v ?? '').trim(), 10);
  return Number.isFinite(n) ? n : fallback;
};
const parseFloatSafe = (v, fallback)=>{
  const n = Number(String(v ?? '').trim());
  return Number.isFinite(n) ? n : fallback;
};

settingImageComfyProfile?.addEventListener('change', async ()=>{
  // Capture any field that may still have unsaved edits before switching away.
  captureComfyFormIntoActiveProfile();
  const wanted = String(settingImageComfyProfile.value || '');
  if (ensureComfyProfiles().some(p=>p.id === wanted)) state.ui.imageComfyProfileId = wanted;
  syncComfyStateFromActiveProfile();
  renderImageSettingsUI();
  await persistComfyProfiles();
});

settingImageComfyProfileNew?.addEventListener('click', async ()=>{
  captureComfyFormIntoActiveProfile();
  const profiles = ensureComfyProfiles();
  const suggested = `ComfyUI ${profiles.length + 1}`;
  const entered = window.prompt('Profile name', suggested);
  if (entered === null) return;
  const name = String(entered || '').trim() || suggested;
  // IMPORTANT: do not call activeComfyProfile() here. ensureComfyProfiles()
  // normalizes into a fresh array on each call; doing so would detach `profiles`
  // and make profiles.push(p) write into a stale array (the old New-button bug).
  const current = profiles.find(x=>x.id === state.ui.imageComfyProfileId) || profiles[0] || null;
  const p = comfyNormalizeProfile({
    id: comfyProfileId(),
    name,
    // Most installations use one ComfyUI server, so carry the URL over.
    url: current?.url || state.ui.imageComfyUrl || '',
    workflow_json: '',
    bindings_json: '',
    seed: -1,
    steps: 20,
    guidance: 3.5,
    width: 512,
    height: 512,
    batch: 1,
    timeout_sec: current?.timeout_sec ?? 900,
    apply_defaults: false
  });
  profiles.push(p);
  state.ui.imageComfyProfileId = p.id;
  syncComfyStateFromActiveProfile();
  renderImageSettingsUI();
  await persistComfyProfiles();
  settingImageComfyWorkflow?.focus();
});

settingImageComfyProfileDuplicate?.addEventListener('click', async ()=>{
  captureComfyFormIntoActiveProfile();
  const src = activeComfyProfile();
  if (!src) return;
  const profiles = ensureComfyProfiles();
  const copy = comfyNormalizeProfile({ ...src, id: comfyProfileId(), name: `${src.name} copy` });
  profiles.push(copy);
  state.ui.imageComfyProfileId = copy.id;
  syncComfyStateFromActiveProfile();
  renderImageSettingsUI();
  await persistComfyProfiles();
});

settingImageComfyProfileRename?.addEventListener('click', async ()=>{
  captureComfyFormIntoActiveProfile();
  const p = activeComfyProfile();
  if (!p) return;
  const entered = window.prompt('Profile name', p.name || 'ComfyUI');
  if (entered === null) return;
  const name = String(entered || '').trim();
  if (!name) return;
  p.name = name;
  renderImageSettingsUI();
  await persistComfyProfiles();
});

settingImageComfyProfileDelete?.addEventListener('click', async ()=>{
  captureComfyFormIntoActiveProfile();
  const profiles = ensureComfyProfiles();
  if (profiles.length <= 1) return;
  const currentId = String(state.ui.imageComfyProfileId || '');
  const idx = profiles.findIndex(p=>p.id === currentId);
  const p = idx >= 0 ? profiles[idx] : profiles[0];
  if (!window.confirm(`Delete ComfyUI profile "${p?.name || 'ComfyUI'}"?`)) return;
  const deleteAt = idx >= 0 ? idx : 0;
  profiles.splice(deleteAt, 1);
  const next = profiles[Math.min(deleteAt, profiles.length - 1)] || profiles[0];
  state.ui.imageComfyProfileId = next?.id || '';
  syncComfyStateFromActiveProfile();
  renderImageSettingsUI();
  await persistComfyProfiles();
});

const saveActiveComfyProfileFromForm = async ()=>{
  captureComfyFormIntoActiveProfile();
  await persistComfyProfiles();
  renderImageSettingsUI();
};

settingImageComfyUrl?.addEventListener('change', saveActiveComfyProfileFromForm);
settingImageComfyWorkflow?.addEventListener('change', saveActiveComfyProfileFromForm);
settingImageComfyBindings?.addEventListener('change', saveActiveComfyProfileFromForm);
settingImageComfySeed?.addEventListener('change', saveActiveComfyProfileFromForm);
settingImageComfySteps?.addEventListener('change', saveActiveComfyProfileFromForm);
settingImageComfyGuidance?.addEventListener('change', saveActiveComfyProfileFromForm);
settingImageComfyWidth?.addEventListener('change', saveActiveComfyProfileFromForm);
settingImageComfyHeight?.addEventListener('change', saveActiveComfyProfileFromForm);
settingImageComfyBatch?.addEventListener('change', saveActiveComfyProfileFromForm);
settingImageComfyTimeout?.addEventListener('change', saveActiveComfyProfileFromForm);
settingImageComfyApplyDefaults?.addEventListener('change', saveActiveComfyProfileFromForm);

async function analyzeComfyWorkflow(mode, workflowJson){
  const result = await api('comfyui_analyze', { mode, workflow_json: workflowJson });
  const bindings = Array.isArray(result?.bindings) ? result.bindings : [];
  const plan = (result?.plan && typeof result.plan === 'object') ? result.plan : null;
  return { bindings, plan };
}

settingImageComfyAutodetect?.addEventListener('click', async ()=>{
  const raw = String(settingImageComfyWorkflow?.value || '').trim();
  if (!raw) { alert('Paste a Workflow JSON first.'); return; }
  try {
    captureComfyFormIntoActiveProfile();
    const { bindings, plan } = await analyzeComfyWorkflow('generate', raw);
    const txt = JSON.stringify(bindings, null, 2);
    if (settingImageComfyBindings) settingImageComfyBindings.value = txt;
    const p = activeComfyProfile();
    if (p) {
      p.workflow_json = raw;
      p.bindings_json = txt;
      p.binding_plan_json = plan ? JSON.stringify(plan) : '';
    }
    state.ui.imageComfyBindings = txt;
    await persistComfyProfiles();
    renderImageSettingsUI();
  } catch(err) {
    alert('Auto-detect failed: ' + (err?.message || String(err)));
  }
});


const saveActiveImageEditComfyProfileFromForm = async ()=>{
  captureImageEditComfyFormIntoActiveProfile();
  await persistImageEditComfyProfiles();
  renderImageSettingsUI();
};

settingImageModeGeneration?.addEventListener('click', ()=>{
  state.ui.imageSettingsMode = 'generation';
  renderImageSettingsUI();
});
settingImageModeEditing?.addEventListener('click', ()=>{
  state.ui.imageSettingsMode = 'editing';
  renderImageSettingsUI();
});
const handleImageModeTabKey = (event)=>{
  if (!['ArrowLeft','ArrowRight','Home','End'].includes(event.key)) return;
  event.preventDefault();
  let next = String(state.ui.imageSettingsMode || 'generation');
  if (event.key === 'Home') next = 'generation';
  else if (event.key === 'End') next = 'editing';
  else next = next === 'generation' ? 'editing' : 'generation';
  state.ui.imageSettingsMode = next;
  renderImageSettingsUI();
  (next === 'generation' ? settingImageModeGeneration : settingImageModeEditing)?.focus();
};
settingImageModeGeneration?.addEventListener('keydown', handleImageModeTabKey);
settingImageModeEditing?.addEventListener('keydown', handleImageModeTabKey);

settingImageEditComfyProfile?.addEventListener('change', async ()=>{
  captureImageEditComfyFormIntoActiveProfile();
  const wanted = String(settingImageEditComfyProfile.value || '');
  if (ensureImageEditComfyProfiles().some(p=>p.id === wanted)) state.ui.imageEditComfyProfileId = wanted;
  syncImageEditComfyStateFromActiveProfile();
  renderImageSettingsUI();
  await persistImageEditComfyProfiles();
});

settingImageEditComfyProfileNew?.addEventListener('click', async ()=>{
  captureImageEditComfyFormIntoActiveProfile();
  const profiles = ensureImageEditComfyProfiles();
  const suggested = `ComfyUI Edit ${profiles.length + 1}`;
  const entered = window.prompt('New edit profile name', suggested);
  if (entered === null) return;
  const name = String(entered || '').trim() || suggested;
  const current = profiles.find(x=>x.id === state.ui.imageEditComfyProfileId) || profiles[0] || null;
  const p = imageEditComfyNormalizeProfile({
    id: imageEditComfyProfileId(),
    name,
    url: current?.url || state.ui.imageEditComfyUrl || '',
    workflow_json: '',
    bindings_json: '',
    seed: current?.seed ?? state.ui.imageEditComfySeed ?? -1,
    steps: current?.steps ?? state.ui.imageEditComfySteps ?? 20,
    guidance: current?.guidance ?? state.ui.imageEditComfyGuidance ?? 3.5,
    width: current?.width ?? state.ui.imageEditComfyWidth ?? 1024,
    height: current?.height ?? state.ui.imageEditComfyHeight ?? 1024,
    batch: current?.batch ?? state.ui.imageEditComfyBatch ?? 1,
    megapixels: current?.megapixels ?? state.ui.imageEditComfyMegapixels ?? 1,
    timeout_sec: current?.timeout_sec ?? state.ui.imageEditComfyTimeout ?? 900,
    apply_defaults: current?.apply_defaults ?? state.ui.imageEditComfyApplyDefaults ?? false,
  });
  profiles.push(p);
  state.ui.imageEditComfyProfileId = p.id;
  syncImageEditComfyStateFromActiveProfile();
  renderImageSettingsUI();
  await persistImageEditComfyProfiles();
  settingImageEditComfyWorkflow?.focus();
});

settingImageEditComfyProfileDuplicate?.addEventListener('click', async ()=>{
  captureImageEditComfyFormIntoActiveProfile();
  const src = activeImageEditComfyProfile();
  if (!src) return;
  const profiles = ensureImageEditComfyProfiles();
  const copy = imageEditComfyNormalizeProfile({ ...src, id: imageEditComfyProfileId(), name: `${src.name} copy` });
  profiles.push(copy);
  state.ui.imageEditComfyProfileId = copy.id;
  syncImageEditComfyStateFromActiveProfile();
  renderImageSettingsUI();
  await persistImageEditComfyProfiles();
});

settingImageEditComfyProfileRename?.addEventListener('click', async ()=>{
  captureImageEditComfyFormIntoActiveProfile();
  const p = activeImageEditComfyProfile();
  if (!p) return;
  const entered = window.prompt('Profile name', p.name || 'ComfyUI Edit');
  if (entered === null) return;
  const name = String(entered || '').trim();
  if (!name) return;
  p.name = name;
  renderImageSettingsUI();
  await persistImageEditComfyProfiles();
});

settingImageEditComfyProfileDelete?.addEventListener('click', async ()=>{
  captureImageEditComfyFormIntoActiveProfile();
  const profiles = ensureImageEditComfyProfiles();
  if (profiles.length <= 1) return;
  const currentId = String(state.ui.imageEditComfyProfileId || '');
  const idx = profiles.findIndex(p=>p.id === currentId);
  const p = idx >= 0 ? profiles[idx] : profiles[0];
  if (!window.confirm(`Delete ComfyUI edit profile "${p?.name || 'ComfyUI Edit'}"?`)) return;
  const deleteAt = idx >= 0 ? idx : 0;
  profiles.splice(deleteAt, 1);
  const next = profiles[Math.min(deleteAt, profiles.length - 1)] || profiles[0];
  state.ui.imageEditComfyProfileId = next?.id || '';
  syncImageEditComfyStateFromActiveProfile();
  renderImageSettingsUI();
  await persistImageEditComfyProfiles();
});

settingImageEditComfyUrl?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);
settingImageEditComfyWorkflow?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);
settingImageEditComfyBindings?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);
settingImageEditComfySeed?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);
settingImageEditComfySteps?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);
settingImageEditComfyGuidance?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);
settingImageEditComfyWidth?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);
settingImageEditComfyHeight?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);
settingImageEditComfyBatch?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);
settingImageEditComfyMegapixels?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);
settingImageEditComfyTimeout?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);
settingImageEditComfyApplyDefaults?.addEventListener('change', saveActiveImageEditComfyProfileFromForm);

settingImageEditComfyAutodetect?.addEventListener('click', async ()=>{
  const raw = String(settingImageEditComfyWorkflow?.value || '').trim();
  if (!raw) { alert('Paste an edit Workflow JSON first.'); return; }
  try {
    captureImageEditComfyFormIntoActiveProfile();
    const { bindings, plan } = await analyzeComfyWorkflow('edit', raw);
    const txt = JSON.stringify(bindings, null, 2);
    if (settingImageEditComfyBindings) settingImageEditComfyBindings.value = txt;
    const p = activeImageEditComfyProfile();
    if (p) {
      p.workflow_json = raw;
      p.bindings_json = txt;
      p.binding_plan_json = plan ? JSON.stringify(plan) : '';
    }
    state.ui.imageEditComfyBindings = txt;
    await persistImageEditComfyProfiles();
    renderImageSettingsUI();
  } catch(err) {
    alert('Auto-detect failed: ' + (err?.message || String(err)));
  }
});



  // Connections
  const maskKey = (k) => {
    if (!k) return '—';
    return k.length < 12 ? '•••• •••• ••••' : ('•••• •••• •••• ' + k.slice(-4));
  };

  const clearConnTest = ()=>{
    if (!connTestResult) return;
    connTestResult.classList.add('hidden');
    connTestResult.classList.remove('ok','err');
    connTestResult.textContent = '';
  };
  const showConnTest = (kind, lines)=>{
    if (!connTestResult) return;
    clearConnTest();
    connTestResult.classList.remove('hidden');
    connTestResult.classList.add(kind === 'ok' ? 'ok' : 'err');
    const txt = Array.isArray(lines) ? lines.filter(Boolean).join('\n') : String(lines||'');
    connTestResult.textContent = txt;
  };

  function resetConnForm(){
    connId.value=''; connLabel.value=''; if(connPrefix) connPrefix.value=''; connUrl.value=''; connKey.value=''; connHeaders.value=''; connNotes.value='';
    connForm.dataset.enabled = '1';
    clearConnTest();
  }
  connAddBtn?.addEventListener('click', ()=>{
    if (!state.perms.canCreateConnections) return;
    resetConnForm();
    connForm.classList.remove('hidden');
    connLabel.focus();
  });
  connCancel?.addEventListener('click', ()=>{ connForm.classList.add('hidden'); resetConnForm(); });

  connForm?.addEventListener('keydown', (e)=>{
    if (e.key === 'Enter' && e.target && e.target.tagName !== 'TEXTAREA') {
      e.preventDefault();
      connSaveBtn?.click();
    }
  });

  connTestBtn?.addEventListener('click', async ()=>{
    if (!state.perms.canCreateConnections) return;
    const base_url = String(connUrl.value || '').trim();
    if (!base_url){ showConnTest('err', ['Base-URL fehlt.']); return; }
    const payload = {
      id: String(connId.value || ''),
      base_url,
      api_key: String(connKey.value || ''),
      headers: String(connHeaders.value || '').trim(),
    };
    if (connTestBtn) connTestBtn.disabled = true;
    showConnTest('ok', ['Testing…']);
    try{
      const r = await api('conn_test', payload);
      if (r && r.ok){
        const lines = [];
        const hc = Number(r.http_code);
        lines.push(`✅ HTTP ${Number.isFinite(hc)?hc:'200'} · ${r.status || 'ok'}`);
        if (Number.isFinite(Number(r.models_count))) lines.push(`Models: ${r.models_count}`);
        if (Array.isArray(r.sample_models) && r.sample_models.length){
          lines.push(`Sample: ${r.sample_models.slice(0,6).join(', ')}`);
        }
        if (Array.isArray(r.warnings) && r.warnings.length){
          lines.push('');
          for (const w of r.warnings) lines.push(`⚠ ${w}`);
        }
        showConnTest('ok', lines);
      } else {
        const lines = [];
        const hc = Number(r?.http_code);
        const statusLine = `❌ HTTP ${Number.isFinite(hc)?hc:'?'}${r?.status ? ' · '+r.status : ''}`;
        lines.push(statusLine);
        if (r?.error) lines.push(String(r.error));
        if (Array.isArray(r?.hints) && r.hints.length){
          lines.push('');
          for (const h of r.hints) lines.push(`↳ ${h}`);
        }
        if (r?.body_snippet) {
          lines.push('');
          lines.push(String(r.body_snippet));
        }
        showConnTest('err', lines);
      }
    }catch(ex){
      showConnTest('err', [String(ex?.message || ex)]);
    }finally{
      if (connTestBtn) connTestBtn.disabled = false;
    }
  });

  connSaveBtn?.addEventListener('click', async ()=>{
    if (!state.perms.canCreateConnections) return;
    const payload = {
      id: connId.value || ('c_'+Math.random().toString(36).slice(2,10)),
      label: connLabel.value.trim(),
      prefix: (connPrefix?.value || '').trim(),
      base_url: connUrl.value.trim(),
      enabled: Number(connForm.dataset.enabled || '1') === 0 ? 0 : 1,
      api_key: connKey.value,
      headers: connHeaders.value.trim(),
      notes: connNotes.value.trim()
    };
    await api('conn_save', payload);
    connForm.classList.add('hidden');
    resetConnForm();
    await renderConnections();
    await refreshModels();
  });

  on('click', '.conn-card [data-cmd]', async (e, btn)=>{
    const cmd = btn.dataset.cmd;
    const id = btn.dataset.id;
    const it = state.connections.find(x=>x.id===id);
    if (!it) return;
    const readonly = !!it.readonly;
    if (readonly && (cmd==='toggle' || cmd==='edit' || cmd==='delete' || cmd==='reveal')) return;
    if (cmd==='toggle'){
      const enabled = (it.enabled==null ? 1 : Number(it.enabled)) === 1 ? 0 : 1;
      await api('conn_set_enabled', {id, enabled});
      await renderConnections();
      await refreshModels();
      // If current selection points to a disabled connection, try to fall back.
      if (state.ui.connectionId === id && enabled === 0) {
        state.ui.connectionId = (state.connections.find(c=>Number(c.enabled)===1)?.id) || '';
        await api('settings_save', { selected_model: state.ui.model || '', selected_connection_id: state.ui.connectionId || '', system_prompt: state.ui.systemPrompt || '' });
      }
    }
    if (cmd==='edit'){
      connForm.classList.remove('hidden');
      clearConnTest();
      connForm.dataset.enabled = (Number(it.enabled)===0 ? '0' : '1');
      connId.value=it.id; connLabel.value=it.label||''; if(connPrefix) connPrefix.value=it.prefix||''; connUrl.value=it.base_url||''; connKey.value=it.api_key||''; connHeaders.value=it.headers||''; connNotes.value=it.notes||'';
      connLabel.focus();
    }
    if (cmd==='delete'){
      if (!confirm('Delete this connection?')) return;
      await api('conn_delete', {id});
      await renderConnections();
      await refreshModels();
    }
    if (cmd==='reveal'){
      const span = btn.parentElement.querySelector('.key-text');
      const masked = span.dataset.masked === 'true';
      if (masked){
        span.textContent = it.api_key || '—';
        span.dataset.masked = 'false';
        btn.textContent = 'Hide';
      } else {
        span.textContent = maskKey(it.api_key);
        span.dataset.masked = 'true';
        btn.textContent = 'Show	';
      }
    }
  });

  async function renderConnections(){
    const res = await api('conn_list', {});
    state.connections = res.connections || [];
    state.ui.connectionId = res.selected_connection_id || state.ui.connectionId || '';

    state.perms.canCreateConnections = !!res.can_create_connections;
    state.perms.inheritGlobalConnections = !!res.inherit_global_connections;
    connAddBtn?.classList.toggle('hidden', !state.perms.canCreateConnections);
    if (!state.perms.canCreateConnections) connForm?.classList.add('hidden');

    connList.innerHTML='';
    if (!state.connections.length){
      connEmpty.classList.remove('hidden');
      return;
    }
    connEmpty.classList.add('hidden');
    for (const it of state.connections){
      const enabled = (it.enabled==null ? 1 : Number(it.enabled)) === 1;
      const scope = String(it.scope || '');
      const readonly = !!it.readonly;
      const scopeBadge = scope==='global' ? '<span class="model-badge">global</span>' : (scope==='private' ? '<span class="model-badge">privat</span>' : '');
      const card = document.createElement('div');
      card.className='conn-card';
      card.innerHTML = `
        <div class="conn-card-head">
          <div>
            <div class="conn-title">${esc(it.label||'(ohne Namen)')} ${scopeBadge} ${enabled?'<span class="model-badge">enabled</span>':'<span class="model-badge">disabled</span>'} ${readonly?'<span class="model-badge">readonly</span>':''}</div>
            <div class="conn-sub">${esc(it.base_url||'—')}</div>
            ${it.prefix?`<div class="muted" style="margin-top:4px;">Prefix: <span class="mono">${esc(it.prefix)}</span></div>`:''}
          </div>
          <div class="conn-actions">
            ${readonly ? '' : `
              <button class="btn ${enabled?'btn-ghost':'btn-primary'}" data-cmd="toggle" data-id="${it.id}">${enabled?'Disable':'Enable'}</button>
              <button class="btn btn-ghost" data-cmd="edit" data-id="${it.id}">Edit</button>
              <button class="btn btn-danger" data-cmd="delete" data-id="${it.id}">Delete</button>
            `}
          </div>
        </div>
        <div class="conn-card-body">
          <span class="key-pill">
            <span>Key:</span>
            <span class="key-text" data-id="${it.id}" data-masked="true">${readonly ? '—' : maskKey(it.api_key)}</span>
            ${readonly ? '' : `<button class="key-btn" data-cmd="reveal" data-id="${it.id}">Show</button>`}
          </span>
          ${it.notes?`<div class="muted" style="margin-top:6px">${esc(it.notes)}</div>`:''}
        </div>
      `;
      connList.appendChild(card);
    }
  }

// ---------- Users (Settings → Users) ----------
const isAdmin = ()=> ['admin','superadmin'].includes(String(state.user?.role || ''));
const isSuperAdmin = ()=> String(state.user?.role || '') === 'superadmin';

function setUserMsg(el, msg, ok=false){
  if (!el) return;
  el.textContent = msg || '';
  el.style.color = ok ? 'var(--ok, #2e7d32)' : 'var(--text-muted)';
}

async function renderUsers(){
  if (userSelfUsername) userSelfUsername.textContent = state.user?.username || '—';
  if (userSelfRole) userSelfRole.textContent = state.user?.role || 'user';
  if (userSelfEmail) userSelfEmail.value = state.user?.email || '';
  setUserMsg(userSelfMsg, '');

  usersAdminWrap?.classList.toggle('hidden', !isAdmin());

  if (!isAdmin()) return;

  try{
    const res = await api('user_list', {});
    state.users = res.users || [];
  }catch(err){
    state.users = [];
    console.warn('user_list failed', err);
  }

  if (!usersList) return;
  usersList.innerHTML = '';

  if (!state.users.length){
    usersEmpty?.classList.remove('hidden');
    return;
  }
  usersEmpty?.classList.add('hidden');

  // Compact list: show only a few users by default; actions are expandable per user.
  const MAX_PREVIEW = 3;
  const showAll = !!state.ui.usersShowAll;
  const list = showAll ? state.users : state.users.slice(0, MAX_PREVIEW);

  if (state.users.length > MAX_PREVIEW) {
    const ctrl = document.createElement('div');
    ctrl.className = 'users-list-controls';
    ctrl.innerHTML = `
      <button type="button" class="btn btn-ghost" id="users-toggle-more">${showAll ? 'Show less' : `Show all (${state.users.length})`}</button>
      <span class="muted">${showAll ? '' : `zeige ${list.length} von ${state.users.length}`}</span>
    `;
    usersList.appendChild(ctrl);
  }

  for (const u of list){
    const me = String(u.id) === String(state.user?.id || '');
    const role = String(u.role || 'user');
    const roleBadge = role === 'superadmin' ? 'superadmin' : (role === 'admin' ? 'admin' : 'user');
    const inherit = !!u.inherit_global_connections;
    const ownConns = !!u.allow_own_connections;
    const inheritSearch = !!u.inherit_global_search;
    const inheritWeb = !!u.inherit_global_web;
    const inheritImage = !!u.inherit_global_image;
    const inheritVoice = !!u.inherit_global_voice;

    const summarySub = `${esc(u.email || '—')}${role==='user' ? ` <span class="muted">· global connections: ${inherit ? 'on' : 'off'} · own connections: ${ownConns ? 'on' : 'off'} · Web: ${inheritWeb ? 'Global' : 'Own'} · Search: ${inheritSearch ? 'Global' : 'Own'} · Image: ${inheritImage ? 'Global' : 'Own'} · Voice: ${inheritVoice ? 'Global' : 'Own'}</span>` : ''}`;

    const actions = [];
    if (!me && role !== 'superadmin') actions.push(`<button type="button" class="btn btn-ghost" data-cmd="toggleRole" data-id="${esc(u.id)}">${role==='admin' ? 'Revoke admin' : 'Make admin'}</button>`);
    if (!me && isSuperAdmin()) actions.push(`<button type="button" class="btn btn-ghost" data-cmd="toggleSuper" data-id="${esc(u.id)}">${role==='superadmin' ? 'Revoke superadmin' : 'Make superadmin'}</button>`);
    if (!me && role==='user') actions.push(
      `<button type="button" class="btn btn-ghost" data-cmd="toggleInherit" data-id="${esc(u.id)}">Global connections: ${inherit ? 'off' : 'on'}</button>`,
      `<button type="button" class="btn btn-ghost" data-cmd="toggleWeb" data-id="${esc(u.id)}">Web: ${inheritWeb ? 'Global' : 'Own'}</button>`,
      `<button type="button" class="btn btn-ghost" data-cmd="toggleSearch" data-id="${esc(u.id)}">Search: ${inheritSearch ? 'Global' : 'Own'}</button>`,
      `<button type="button" class="btn btn-ghost" data-cmd="toggleImage" data-id="${esc(u.id)}">Image: ${inheritImage ? 'Global' : 'Own'}</button>`,
      `<button type="button" class="btn btn-ghost" data-cmd="toggleVoice" data-id="${esc(u.id)}">Voice: ${inheritVoice ? 'Global' : 'Own'}</button>`,
      `<button type="button" class="btn btn-ghost" data-cmd="toggleOwn" data-id="${esc(u.id)}">Own connections: ${ownConns ? 'off' : 'on'}</button>`
    );
    if (!me) actions.push(
      `<button type="button" class="btn btn-ghost" data-cmd="setEmail" data-id="${esc(u.id)}">Change email</button>`,
      `<button type="button" class="btn btn-danger" data-cmd="setPw" data-id="${esc(u.id)}">Set password</button>`,
      `<button type="button" class="btn btn-danger" data-cmd="deleteUser" data-id="${esc(u.id)}">Delete user</button>`
    );

    const headHtml = `
      <div>
        <div class="conn-title">${esc(u.username || '—')} <span class="model-badge">${roleBadge}</span> ${me ? '<span class="model-badge">me</span>' : ''}</div>
        <div class="conn-sub">${summarySub}</div>
      </div>
    `;

    if (!actions.length){
      const card = document.createElement('div');
      card.className = 'conn-card user-card user-compact';
      card.innerHTML = `<div class="conn-card-head user-summary">${headHtml}</div>`;
      usersList.appendChild(card);
      continue;
    }

    const card = document.createElement('details');
    card.className = 'conn-card user-card user-details';
    card.innerHTML = `
      <summary class="conn-card-head user-summary">
        ${headHtml}
        <div class="user-summary-right" aria-hidden="true"><span class="user-chevron">▾</span></div>
      </summary>
      <div class="user-details-body">
        <div class="conn-actions user-actions">
          ${actions.join('')}
        </div>
      </div>
    `;
    usersList.appendChild(card);
  }
}

// Toggle compact/full list view (admin only)
on('click', '#users-toggle-more', async ()=>{
  if (!isAdmin()) return;
  state.ui.usersShowAll = !state.ui.usersShowAll;
  try{ await renderUsers(); }catch(_){ }
});

// Self: save email
userSelfSaveEmail?.addEventListener('click', async ()=>{
  const email = String(userSelfEmail?.value || '').trim();
  try{
    const res = await api('user_self_update', { email });
    if (res?.user) state.user = { ...state.user, ...res.user };
    setUserMsg(userSelfMsg, 'Email saved.', true);

    // If an admin updates their own email, refresh the admin list so "me" shows the new value.
    if (isAdmin()) {
      try { await renderUsers(); } catch(_) {}
    }
  }catch(err){
    setUserMsg(userSelfMsg, err?.message || 'Error');
  }
});

// Self: change password
userSelfSavePw?.addEventListener('click', async ()=>{
  const curPw = String(userSelfCurPw?.value || '');
  const pw1 = String(userSelfNewPw?.value || '');
  const pw2 = String(userSelfNewPw2?.value || '');
  if (!pw1 || pw1.length < 4) { setUserMsg(userSelfMsg, 'Password too short (min. 4 characters).'); return; }
  if (pw1 !== pw2) { setUserMsg(userSelfMsg, 'Passwords do not match.'); return; }
  try{
    await api('user_self_update', { current_password: curPw, new_password: pw1 });
    if (userSelfCurPw) userSelfCurPw.value = '';
    if (userSelfNewPw) userSelfNewPw.value = '';
    if (userSelfNewPw2) userSelfNewPw2.value = '';
    setUserMsg(userSelfMsg, 'Password changed.', true);
  }catch(err){
    setUserMsg(userSelfMsg, err?.message || 'Error');
  }
});

// Admin: create user form
const resetUserCreateForm = ()=>{
  if (userCreateUsername) userCreateUsername.value = '';
  if (userCreateEmail) userCreateEmail.value = '';
  if (userCreatePassword) userCreatePassword.value = '';
  if (userCreateAdmin) userCreateAdmin.checked = false;
  if (userCreateInherit) userCreateInherit.checked = true;
  if (userCreateSearchInherit) userCreateSearchInherit.checked = true;
  if (userCreateWebInherit) userCreateWebInherit.checked = true;
  if (userCreateImageInherit) userCreateImageInherit.checked = true;
  if (userCreateVoiceInherit) userCreateVoiceInherit.checked = true;
  if (userCreateOwn) userCreateOwn.checked = false;
  setUserMsg(userCreateMsg, '');
};

userCreateBtn?.addEventListener('click', ()=>{
  if (!isAdmin()) return;
  resetUserCreateForm();
  userCreateForm?.classList.remove('hidden');
  userCreateUsername?.focus();
});
userCreateCancel?.addEventListener('click', ()=>{
  userCreateForm?.classList.add('hidden');
  resetUserCreateForm();
});

userCreateSave?.addEventListener('click', async ()=>{
  if (!isAdmin()) return;
  const username = String(userCreateUsername?.value || '').trim();
  const email = String(userCreateEmail?.value || '').trim();
  const password = String(userCreatePassword?.value || '');
  const role = userCreateAdmin?.checked ? 'admin' : 'user';
  const inherit_global_connections = !!userCreateInherit?.checked;
  const inherit_global_search = !!userCreateSearchInherit?.checked;
  const inherit_global_web = !!userCreateWebInherit?.checked;
  const inherit_global_image = !!userCreateImageInherit?.checked;
  const inherit_global_voice = !!userCreateVoiceInherit?.checked;
  const allow_own_connections = !!userCreateOwn?.checked;

  if (!username) { setUserMsg(userCreateMsg, 'Username fehlt.'); return; }
  if (!password || password.length < 4) { setUserMsg(userCreateMsg, 'Password too short (min. 4 characters).'); return; }

  try{
    await api('user_create', { username, email, password, role, inherit_global_connections, inherit_global_web, inherit_global_search, inherit_global_image, inherit_global_voice, allow_own_connections });
    userCreateForm?.classList.add('hidden');
    resetUserCreateForm();
    await renderUsers();
  }catch(err){
    setUserMsg(userCreateMsg, err?.message || 'Error');
  }
});

// Admin: actions on user cards
on('click', '.user-card [data-cmd]', async (e, btn)=>{
  // Safety: avoid any default button behaviour + keep clicks from triggering other delegated handlers.
  e.preventDefault();
  e.stopPropagation();
  if (!isAdmin()) return;
  const cmd = btn.dataset.cmd;
  const id = btn.dataset.id;
  const u = (state.users || []).find(x=>String(x.id)===String(id));
  if (!u) return;

  try{
    if (cmd === 'toggleRole'){
      const cur = String(u.role || 'user');
      if (cur === 'superadmin') return;
      const newRole = cur === 'admin' ? 'user' : 'admin';
      if (!confirm(`Really change role? ${u.username} → ${newRole}`)) return;
      await api('user_update', { id, role: newRole });
      await renderUsers();
      return;
    }

    if (cmd === 'toggleSuper'){
      if (!isSuperAdmin()) return;
      const cur = String(u.role || 'user');
      const newRole = cur === 'superadmin' ? 'admin' : 'superadmin';
      if (!confirm(`Really change role? ${u.username} → ${newRole}`)) return;
      await api('user_update', { id, role: newRole });
      await renderUsers();
      return;
    }

    if (cmd === 'toggleInherit'){
      const cur = !!u.inherit_global_connections;
      await api('user_update', { id, inherit_global_connections: cur ? 0 : 1 });
      await renderUsers();
      return;
    }

    if (cmd === 'toggleWeb'){
      const cur = !!u.inherit_global_web;
      await api('user_update', { id, inherit_global_web: cur ? 0 : 1 });
      await renderUsers();
      return;
    }

    if (cmd === 'toggleSearch'){
      const cur = !!u.inherit_global_search;
      await api('user_update', { id, inherit_global_search: cur ? 0 : 1 });
      await renderUsers();
      return;
    }

    if (cmd === 'toggleImage'){
      const cur = !!u.inherit_global_image;
      await api('user_update', { id, inherit_global_image: cur ? 0 : 1 });
      await renderUsers();
      return;
    }

    if (cmd === 'toggleVoice'){
      const cur = !!u.inherit_global_voice;
      await api('user_update', { id, inherit_global_voice: cur ? 0 : 1 });
      await renderUsers();
      return;
    }

    if (cmd === 'toggleOwn'){
      const cur = !!u.allow_own_connections;
      await api('user_update', { id, allow_own_connections: cur ? 0 : 1 });
      await renderUsers();
      return;
    }

    if (cmd === 'setEmail'){
      const current = String(u.email || '');
      const next = prompt(`New email for ${u.username} (blank = remove):`, current);
      if (next === null) return;
      await api('user_update', { id, email: String(next).trim() });
      await renderUsers();
      return;
    }

    if (cmd === 'setPw'){
      const p1 = prompt(`New password for ${u.username}:`);
      if (p1 === null) return;
      const p2 = prompt('Repeat password:');
      if (p2 === null) return;
      if (String(p1) !== String(p2)) { alert('Passwords do not match.'); return; }
      if (String(p1).length < 4) { alert('Password too short (min. 4 characters).'); return; }
      if (!confirm(`Password for ${u.username} — really set it?`)) return;
      await api('user_update', { id, password: String(p1) });
      await renderUsers();
      return;
    }

    if (cmd === 'deleteUser'){
      if (!confirm(`Really delete user? ${u.username}\n\nWarning: chats/files/settings for this user will also be deleted.`)) return;
      await api('user_delete', { id });
      await renderUsers();
      return;
    }
  }catch(err){
    alert(err?.message || 'Error');
  }
});


  // Param chips: simple "click chip => custom"
  function initParams(){
    $$('.param-row').forEach(row=>{
      const name = row.dataset.name;
      const chip = row.querySelector('.status-chip');
      const reset = row.querySelector('.reset-param-btn');
      const input = row.querySelector('input,textarea,select');
      if (!name || !chip || !reset || !input) return;

      const render = ()=>{
        const custom = row.classList.contains('is-custom');
        chip.textContent = custom ? 'Custom' : 'Default';
        chip.classList.toggle('custom', custom);
        chip.setAttribute('aria-pressed', custom?'true':'false');
        reset.disabled = !custom;
        reset.classList.toggle('invisible', !custom);
      };
      row._render = render;

      chip.addEventListener('click', ()=>{ row.classList.add('is-custom'); render(); input.focus(); input.select?.(); if(!state.loadingChat) scheduleMetaSave(); });
      chip.addEventListener('keydown', (e)=>{ if(e.key==='Enter'||e.key===' '){ e.preventDefault(); row.classList.add('is-custom'); render(); input.focus(); if(!state.loadingChat) scheduleMetaSave(); }});
      input.addEventListener('input', ()=>{ if(row.classList.contains('is-custom')) { render(); if(!state.loadingChat) scheduleMetaSave(); } });
      reset.addEventListener('click', ()=>{ row.classList.remove('is-custom'); input.value=''; render(); if(!state.loadingChat) scheduleMetaSave(); });

      render();
    });
  }

  // Reset all advanced params back to defaults
  const resetAllBtn = $('#reset-all');
  if (resetAllBtn){
    // Prevent toggling the <details> when clicking inside <summary>
    resetAllBtn.addEventListener('pointerdown', (e)=>{ e.stopPropagation(); });
    resetAllBtn.addEventListener('click', (e)=>{
      e.preventDefault();
      e.stopPropagation();
      applyParamsToUI({});
      if (!state.loadingChat) scheduleMetaSave();
    });
  }

  function collectParams(){
    const params = {};
    $$('.param-row.is-custom').forEach(row=>{
      const name = row.dataset.name;
      const input = row.querySelector('input,textarea,select');
      if (!name || !input) return;
      const raw = input.value;
      if (raw==='' || raw==null) return;

      const vstr = String(raw).trim();
      if (vstr === '') return;

      // JSON objects/arrays (for stop, logit_bias, schema, etc.)
      if ((vstr.startsWith('{') && vstr.endsWith('}')) || (vstr.startsWith('[') && vstr.endsWith(']'))) {
        try { params[name] = JSON.parse(vstr); return; } catch(_) {}
      }

      const low = vstr.toLowerCase();
      if (low === 'true') { params[name] = true; return; }
      if (low === 'false') { params[name] = false; return; }
      if (/^-?\d+(\.\d+)?$/.test(vstr)) { params[name] = Number(vstr); return; }

      params[name] = vstr;
    });
    return params;
  }

  function applyParamsToUI(params){
    const p = (params && typeof params === 'object') ? params : {};
    $$('.param-row').forEach(row=>{
      const name = row.dataset.name;
      const input = row.querySelector('input,textarea,select');
      if (!name || !input) return;

      if (Object.prototype.hasOwnProperty.call(p, name)) {
        row.classList.add('is-custom');
        const v = p[name];
        if (typeof v === 'string') input.value = v;
        else if (typeof v === 'number' || typeof v === 'boolean') input.value = String(v);
        else input.value = JSON.stringify(v);
      } else {
        row.classList.remove('is-custom');
        input.value = '';
      }
      if (typeof row._render === 'function') row._render();
    });
  }


  const debounce = (fn, ms=500)=>{
    let t = null;
    return (...args)=>{
      clearTimeout(t);
      t = setTimeout(()=>fn(...args), ms);
    };
  };

  const persistUiToChatMeta = ()=>{
    if (!state.currentChat) return;
    state.currentChat.meta = state.currentChat.meta || {};
    state.currentChat.meta.system_prompt = state.ui.systemPrompt || '';
    state.currentChat.meta.params = collectParams();
  };

  scheduleMetaSave = debounce(async ()=>{
    if (!state.currentChat || state.loadingChat) return;
    persistUiToChatMeta();

    try { await saveChat(); } catch(_) {}
    try { await reloadSidebar(); } catch(_) {}

    // Also keep global defaults in sync (new chats inherit)
    try {
      await api('settings_save', {
        selected_model: state.ui.model || '',
        selected_connection_id: state.ui.connectionId || ''
      });
    } catch(_) {}
  }, 600);

  let systemTouched = false;
  systemPromptEl?.addEventListener('input', ()=>{
    systemTouched = true;
    state.ui.systemPrompt = systemPromptEl.value;
    if (state.loadingChat) return;
    scheduleMetaSave();
  });
  // Attachments
  const human = (bytes)=>{
    if (!Number.isFinite(bytes)) return '';
    const u=['B','KB','MB','GB']; let i=0, v=bytes;
    while(v>=1024 && i<u.length-1){ v/=1024; i++; }
    return `${v.toFixed(v<10&&i>0?1:0)} ${u[i]}`;
  };
  function iconSvg(name){
    // Minimal inline SVG icons (monochrome via currentColor).
    const base = 'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"';
    const wrap = (inner)=>`<svg ${base}>${inner}</svg>`;
    switch(String(name||'')){
      case 'paperclip':
        return wrap('<path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66L9.4 17.18a2 2 0 1 1-2.83-2.83l8.49-8.48"/>');
      case 'file':
        return wrap('<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>');
      case 'fileText':
        return wrap('<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M16 13H8"/><path d="M16 17H8"/><path d="M10 9H8"/>');
      case 'image':
        return wrap('<rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/>');
      case 'link':
        return wrap('<path d="M10 13a5 5 0 0 0 7.54.54l1.73-1.73a5 5 0 0 0-7.07-7.07L11 5"/><path d="M14 11a5 5 0 0 0-7.54-.54L4.73 12.2a5 5 0 0 0 7.07 7.07L13 19"/>');
      case 'pencil':
        return wrap('<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z"/>');
      case 'eye':
        return wrap('<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>');
      case 'download':
        return wrap('<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5"/><path d="M12 15V3"/>');
      case 'upload':
        return wrap('<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M17 8l-5-5-5 5"/><path d="M12 3v12"/>');
      case 'plus':
        return wrap('<path d="M12 5v14"/><path d="M5 12h14"/>');
      case 'archive':
        return wrap('<path d="M21 8v13H3V8"/><path d="M1 3h22v5H1z"/><path d="M10 12h4"/>');
      case 'unlink':
        return wrap('<path d="M10 13a5 5 0 0 0 7.54.54l1.73-1.73a5 5 0 0 0-7.07-7.07L11 5"/><path d="M14 11a5 5 0 0 0-7.54-.54L4.73 12.2a5 5 0 0 0 7.07 7.07L13 19"/><path d="M4 4l16 16"/>');
      case 'trash':
        return wrap('<path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/>');
      case 'audio':
      case 'music':
        return wrap('<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>');
      case 'volume':
      case 'speaker':
        // Feather "volume-2" (simplified)
        return wrap('<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>');
      case 'search':
        return wrap('<circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/>');
      case 'x':
        return wrap('<path d="M18 6L6 18"/><path d="M6 6l12 12"/>');
      case 'maximize':
        return wrap('<path d="M8 3H5a2 2 0 0 0-2 2v3"/><path d="M16 3h3a2 2 0 0 1 2 2v3"/><path d="M8 21H5a2 2 0 0 1-2-2v-3"/><path d="M16 21h3a2 2 0 0 0 2-2v-3"/>');
      case 'minimize':
        return wrap('<path d="M8 3H5a2 2 0 0 0-2 2v3"/><path d="M16 3h3a2 2 0 0 1 2 2v3"/><path d="M8 21H5a2 2 0 0 1-2-2v-3"/><path d="M16 21h3a2 2 0 0 0 2-2v-3"/><path d="M9 9h6v6H9z"/>');
      default:
        return wrap('<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>');
    }
  }

  const iconForType = (t)=>{
    const map = { file: 'paperclip', document: 'fileText', image: 'image', audio: 'audio', url: 'link', note: 'pencil', text: 'fileText', rag: 'fileText' };
    return iconSvg(map[t] || 'fileText');
  };

  // New document-library attachments keep text semantics but only persist a
  // file_id. Extraction is fetched from PHP when the user opens the viewer or
  // when the backend builds a model request. This cache lives only in memory.
  const documentTextCache = new Map();

  function isTextDocumentAttachment(a){
    const t = String(a?.type || '');
    return ['text','textfile','file_text','document'].includes(t); // `document` = compatibility with first library build
  }

  function documentKindLabel(name, mime){
    const ext = extOf(name);
    const m = String(mime || '').toLowerCase();
    if (ext === 'pdf' || m === 'application/pdf') return 'PDF';
    if (ext === 'docx' || m.includes('wordprocessingml')) return 'DOCX';
    if (ext === 'odt' || m.includes('opendocument.text')) return 'ODT';
    if (ext === 'xlsx' || m.includes('spreadsheetml')) return 'XLSX';
    if (ext === 'ods' || m.includes('opendocument.spreadsheet')) return 'ODS';
    if (ext === 'csv' || m === 'text/csv') return 'CSV';
    return 'Text';
  }

  function documentTextMeta(a){
    const size = human(Number(a?.size || 0));
    const kind = documentKindLabel(a?.name || '', a?.mime || '');
    return `${size ? size + ' · ' : ''}${kind} → Text`;
  }

  async function attachmentTextForView(a){
    const inline = (typeof a?.text === 'string') ? a.text : '';
    if (inline.trim()) return inline;
    const fileId = String(a?.file_id || '').trim();
    if (!fileId) throw new Error('No text extraction is available for this attachment');
    if (documentTextCache.has(fileId)) return documentTextCache.get(fileId);
    const r = await api('file_text', {id:fileId});
    const text = String(r?.text || '');
    if (!text.trim()) throw new Error('Document contains no extractable text');
    documentTextCache.set(fileId, text);
    return text;
  }

  function ragRefsForChat(chat = state.currentChat, includeDraft = false){
    const refs = new Map();
    const add = (a, requireReady=false)=>{
      if (!a || a.type !== 'rag') return;
      const id = String(a.rag_document_id || '').trim();
      if (!id) return;
      // Historical message attachments are immutable snapshots. Their stored
      // rag_state can be stale after an interrupted automatic rebuild because
      // the canonical file row is updated independently. Once a message owns a
      // stable rag_document_id, keep sending that id and let the backend/ragd
      // recovery path decide whether the index must be rebuilt. Only draft
      // attachments are blocked on their live indexing state.
      if (requireReady) {
        const ragState = String(a.rag_state || '').trim().toLowerCase();
        if (ragState && ragState !== 'ready') return;
      }
      if (!refs.has(id)) refs.set(id, {
        id,
        name: String(a.name || 'document'),
        chunks: Number(a.rag_chunks || 0)
      });
    };
    for (const m of (chat?.messages || [])) {
      for (const a of (Array.isArray(m?.attachments) ? m.attachments : [])) add(a, false);
    }
    if (includeDraft) for (const a of (state.attachments || [])) add(a, true);
    return [...refs.values()];
  }

  function ragDocumentIdsForChat(chat = state.currentChat){
    return ragRefsForChat(chat, false).map(r=>r.id);
  }

  function renderAttachments(){
    attachmentsBar.innerHTML='';
    for (const a of state.attachments){
      const chip = document.createElement('div');
      chip.className='attach-chip';
      chip.innerHTML = `
        <span class="chip-icon">${iconForType(a.type)}</span>
        <span class="chip-name" title="${esc(a.name)}">${esc(a.name)}</span>
        ${a.meta?`<span class="chip-meta">· ${esc(a.meta)}</span>`:''}
        ${(isTextDocumentAttachment(a) && (a.text || a.file_id))?`<button class="chip-action chip-view" title="View extraction" aria-label="View">${iconSvg('eye')}</button>`:''}
        ${a.url?`<a class="chip-action chip-download" title="Download" aria-label="Download" href="${esc(a.url)}" target="_blank" rel="noopener noreferrer">${iconSvg('download')}</a>`:''}
        ${(a.file_id && a.url && a.type!=='rag')?`<button class="chip-action chip-delete" title="Delete on server" aria-label="Delete">${iconSvg('trash')}</button>`:''}
        <button class="chip-remove" title="Remove (local)" aria-label="Remove">${iconSvg('x')}</button>
      `;
      chip.querySelector('.chip-remove').addEventListener('click', ()=>{
        state.attachments = state.attachments.filter(x=>x.id!==a.id);
        renderAttachments(); renderWebTools(); syncSend();
      });

      const viewBtn = chip.querySelector('.chip-view');
      viewBtn?.addEventListener('click', async (e)=>{
        e.stopPropagation();
        const title = a.name ? `Extraction · ${a.name}` : 'Extraction';
        try {
          if (!a.text && a.file_id) extractModal.open(title, 'Extracting text from stored document…');
          const text = await attachmentTextForView(a);
          extractModal.open(title, text);
        } catch (err) {
          extractModal.close();
          alert(String(err?.message || err || 'Could not extract document text'));
        }
      });

      const delBtn = chip.querySelector('.chip-delete');
      delBtn?.addEventListener('click', async (e)=>{
        e.stopPropagation();
        const ok = confirm('Really delete this file from the server?');
        if(!ok) return;
        try{
          await deleteStoredFileWithForce(a.file_id);
        }catch(err){
          if (!err?.cancelled) alert(String(err?.message || err));
          return;
        }
        // Remove from local attachments after server delete
        state.attachments = state.attachments.filter(x=>x.id!==a.id);
        renderAttachments(); renderWebTools(); syncSend();
      });

      attachmentsBar.appendChild(chip);
    }
  }

  function toggleAttachMenu(){
    attachMenu.classList.toggle('show');
    attachBtn.setAttribute('aria-expanded', attachMenu.classList.contains('show')?'true':'false');
  }
  attachBtn?.addEventListener('click', (e)=>{ e.stopPropagation(); toggleAttachMenu(); });

  // ---------- Persistent document library ----------
  let documentLibraryModal = null;
  let documentLibraryRefreshTimer = null;

  function ensureDocumentLibraryModal(){
    if (documentLibraryModal) return documentLibraryModal;
    const modal = document.createElement('div');
    modal.className = 'modal document-library-modal';
    modal.setAttribute('role','dialog');
    modal.setAttribute('aria-modal','true');
    modal.setAttribute('aria-hidden','true');
    modal.innerHTML = `
      <div class="modal-backdrop" data-document-library-close="1"></div>
      <div class="modal-panel document-library-panel" role="document">
        <div class="modal-header">
          <div>
            <div>Documents</div>
            <div class="document-library-subtitle">New document uploads stored by LLC</div>
          </div>
          <button class="icon-btn" data-document-library-close="1" aria-label="Close">${iconSvg('x')}</button>
        </div>
        <div class="document-library-toolbar">
          <div class="document-library-hint">Files stay on disk; this list stores only metadata and RAG state.</div>
          <div class="document-library-toolbar-actions">
            <label class="document-library-search" aria-label="Search documents">
              ${iconSvg('search')}
              <input class="document-library-search-input" type="search" placeholder="Search documents…" autocomplete="off" spellcheck="false" />
            </label>
            <button class="btn tiny document-library-refresh" type="button">Refresh</button>
          </div>
        </div>
        <div class="document-library-list"></div>
      </div>`;
    document.body.appendChild(modal);

    const close = ()=>{
      if (documentLibraryRefreshTimer) {
        clearTimeout(documentLibraryRefreshTimer);
        documentLibraryRefreshTimer = null;
      }
      modal.classList.remove('open');
      modal.setAttribute('aria-hidden','true');
    };
    modal.querySelectorAll('[data-document-library-close="1"]').forEach(el=>el.addEventListener('click', close));
    modal.querySelector('.document-library-refresh')?.addEventListener('click', ()=>loadDocumentLibrary());
    modal.querySelector('.document-library-search-input')?.addEventListener('input', ()=>filterDocumentLibraryRows());
    document.addEventListener('keydown', (e)=>{ if (e.key==='Escape' && modal.classList.contains('open')) close(); });
    documentLibraryModal = { modal, close };
    return documentLibraryModal;
  }

  function filterDocumentLibraryRows(){
    const ref = documentLibraryModal;
    if (!ref?.modal) return;
    const list = ref.modal.querySelector('.document-library-list');
    const input = ref.modal.querySelector('.document-library-search-input');
    if (!list || !input) return;

    const query = String(input.value || '').trim().toLocaleLowerCase();
    const rows = Array.from(list.querySelectorAll('.document-library-row'));
    let visible = 0;
    for (const row of rows) {
      const haystack = String(row.dataset.search || '').toLocaleLowerCase();
      const show = !query || haystack.includes(query);
      row.hidden = !show;
      if (show) visible++;
    }

    let empty = list.querySelector('.document-library-filter-empty');
    if (query && rows.length && visible === 0) {
      if (!empty) {
        empty = document.createElement('div');
        empty.className = 'document-library-empty document-library-filter-empty';
        list.appendChild(empty);
      }
      empty.textContent = `No documents match “${input.value.trim()}”.`;
      empty.hidden = false;
    } else if (empty) {
      empty.hidden = true;
    }
  }

  function libraryRagLabel(file){
    const s = String(file?.rag_state || '').toLowerCase();
    const chunks = Math.max(0, Number(file?.rag_chunks || 0));
    const indexedAt = Number(file?.rag_indexed_at || 0);
    if (s === 'ready') return `RAG ready${chunks ? ` · ${chunks} chunks` : ''}${indexedAt ? ` · indexed ${fmt(indexedAt)}` : ''}`;
    if (s === 'failed') return `RAG failed${file?.rag_error ? ` · ${String(file.rag_error)}` : ''}`;
    if (['queued','chunking','embedding','storing'].includes(s)) return `RAG · ${ragPhaseLabel(s)}`;
    return 'Not indexed in RAG';
  }

  function attachLibraryDocument(file){
    const readyForRag = String(file?.rag_state || '').toLowerCase() === 'ready' && String(file?.rag_document_id || '').trim();
    const useRag = !!(state.webtools?.rag && readyForRag);
    const id = 'att_'+Math.random().toString(36).slice(2,9);
    if (useRag) {
      state.attachments.push({
        id,
        type:'rag',
        name:String(file.name || 'document'),
        meta:`RAG · ${Number(file.rag_chunks || 0)} chunks`,
        url:String(file.url || ''),
        mime:String(file.mime || 'application/octet-stream'),
        size:Number(file.size || 0),
        file_id:String(file.id || ''),
        rag_document_id:String(file.rag_document_id || ''),
        rag_job_id:String(file.rag_job_id || ''),
        rag_state:'ready',
        rag_chunks:Number(file.rag_chunks || 0),
        rag_embedding_model:String(file.rag_embedding_model || '')
      });
    } else {
      const normal = {
        id,
        type:'text',
        name:String(file.name || 'document'),
        url:String(file.url || ''),
        mime:String(file.mime || 'application/octet-stream'),
        size:Number(file.size || 0),
        file_id:String(file.id || '')
      };
      normal.meta = documentTextMeta(normal);
      state.attachments.push(normal);
    }
    renderAttachments();
    renderWebTools();
    syncSend();
  }

  async function indexLibraryDocument(file, button){
    if (!state.ui.ragAvailable) {
      alert('RAG is not available. Configure a server URL in Settings → RAG.');
      return;
    }
    if (button) { button.disabled = true; button.textContent = 'Starting…'; }
    try {
      const res = await api('file_rag_index', {id:String(file.id || '')});
      const jobId = String(res?.rag_job_id || res?.job_id || '');
      if (!jobId) {
        await loadDocumentLibrary();
        return;
      }
      setRagRuntimeActivity({title:'Indexing RAG document', detail:`${String(file.name || 'Document')} · ${ragPhaseLabel(res?.rag_state || 'queued')}`, percent:null});
      const shadow = {
        name:String(file.name || 'Document'),
        rag_chunks:Number(res?.rag_chunks || 0),
        rag_state:String(res?.rag_state || 'queued'),
        meta:''
      };
      await waitForRagJob(jobId, shadow);
      await loadDocumentLibrary();
    } catch (err) {
      alert(String(err?.message || err || 'RAG indexing failed'));
      await loadDocumentLibrary().catch(()=>{});
    } finally {
      if (button && button.isConnected) button.disabled = false;
    }
  }

  async function deleteLibraryDocument(file){
    const name = String(file?.name || 'document');
    if (!confirm(`Really delete ${name} from LLC?`)) return;
    try {
      await deleteStoredFileWithForce(file.id);
      // Remove unsent references to a file that no longer exists. Historic chat
      // references deliberately remain untouched and will report a missing file.
      state.attachments = (state.attachments || []).filter(a=>String(a?.file_id || '') !== String(file.id || ''));
      renderAttachments();
      syncSend();
      await loadDocumentLibrary();
    } catch (err) {
      if (!err?.cancelled) alert(String(err?.message || err || 'Delete failed'));
    }
  }

  async function loadDocumentLibrary(){
    const ref = ensureDocumentLibraryModal();
    const list = ref.modal.querySelector('.document-library-list');
    if (!list) return;
    if (documentLibraryRefreshTimer) {
      clearTimeout(documentLibraryRefreshTimer);
      documentLibraryRefreshTimer = null;
    }
    list.innerHTML = '<div class="document-library-empty">Loading…</div>';
    try {
      const res = await api('file_library_list');
      const files = Array.isArray(res?.files) ? res.files : [];

      // A ragd job can finish while this dialog/browser is closed. Reconcile
      // active jobs when the library is opened so DB status never becomes the
      // source of truth for ragd progress.
      if (state.ui.ragAvailable) {
        await Promise.all(files.map(async file=>{
          const s = String(file?.rag_state || '').toLowerCase();
          const jobId = String(file?.rag_job_id || '').trim();
          if (!jobId || !['queued','chunking','embedding','storing'].includes(s)) return;
          try {
            const job = await api('rag_job', {job_id:jobId});
            if (job && typeof job === 'object') {
              file.rag_state = String(job.state || file.rag_state || '');
              file.rag_chunks = Number(job.chunks || job.total || file.rag_chunks || 0);
              if (job.embedding_model) file.rag_embedding_model = String(job.embedding_model);
              file.rag_error = String(job.error || '');
            }
          } catch(_){ /* keep last known metadata; row remains usable */ }
        }));
      }

      list.innerHTML = '';
      if (!files.length) {
        list.innerHTML = '<div class="document-library-empty">No library documents yet. New PDF/TXT/Docs/Sheets uploads will appear here.</div>';
        return;
      }
      for (const file of files) {
        const row = document.createElement('div');
        row.className = 'document-library-row';
        row.dataset.search = `${String(file?.name || '')} ${String(file?.mime || '')} ${libraryRagLabel(file)}`;
        const ragState = String(file?.rag_state || '').toLowerCase();
        const indexing = ['queued','chunking','embedding','storing'].includes(ragState);
        const created = Number(file?.created_at || 0);
        const useLabel = (ragState === 'ready' && state.webtools?.rag) ? 'Use with RAG' : 'Use in chat';
        row.innerHTML = `
          <div class="document-library-file">
            <div class="document-library-name" title="${esc(file.name || '')}">${iconSvg('fileText')}<span>${esc(file.name || 'document')}</span></div>
            <div class="document-library-meta">${esc(human(Number(file.size || 0)))} · ${esc(file.mime || '')}${created ? ` · ${esc(fmt(created))}` : ''}</div>
            <div class="document-library-rag ${ragState === 'failed' ? 'failed' : (ragState === 'ready' ? 'ready' : '')}">${esc(libraryRagLabel(file))}</div>
          </div>
          <div class="document-library-actions">
            <button class="btn tiny library-use" type="button">${useLabel}</button>
            ${ragState !== 'ready' ? `<button class="btn tiny library-index" type="button" ${indexing ? 'disabled' : ''}>${indexing ? ragPhaseLabel(ragState) : (ragState === 'failed' ? 'Retry RAG' : 'Index in RAG')}</button>` : ''}
            <button class="icon-btn sm library-view" type="button" title="View extracted text" aria-label="View extracted text">${iconSvg('eye')}</button>
            ${file.url ? `<a class="icon-btn sm" href="${esc(file.url)}" target="_blank" rel="noopener noreferrer" title="Download" aria-label="Download">${iconSvg('download')}</a>` : ''}
            <button class="icon-btn sm danger library-delete" type="button" title="Delete" aria-label="Delete">${iconSvg('trash')}</button>
          </div>`;
        row.querySelector('.library-use')?.addEventListener('click', ()=>{
          attachLibraryDocument(file);
          ref.close();
        });
        row.querySelector('.library-view')?.addEventListener('click', async ()=>{
          const title = file?.name ? `Extraction · ${file.name}` : 'Extraction';
          try {
            extractModal.open(title, 'Extracting text from stored document…');
            const text = await attachmentTextForView({file_id:String(file?.id || ''), name:file?.name, mime:file?.mime, size:file?.size});
            extractModal.open(title, text);
          } catch (err) {
            extractModal.close();
            alert(String(err?.message || err || 'Could not extract document text'));
          }
        });
        row.querySelector('.library-index')?.addEventListener('click', (e)=>indexLibraryDocument(file, e.currentTarget));
        row.querySelector('.library-delete')?.addEventListener('click', ()=>deleteLibraryDocument(file));
        list.appendChild(row);
      }
      filterDocumentLibraryRows();

      const stillIndexing = files.some(file=>['queued','chunking','embedding','storing'].includes(String(file?.rag_state || '').toLowerCase()));
      if (stillIndexing && ref.modal.classList.contains('open')) {
        documentLibraryRefreshTimer = setTimeout(()=>loadDocumentLibrary(), 1200);
      }
    } catch (err) {
      list.innerHTML = `<div class="document-library-empty">${esc(String(err?.message || err || 'Could not load documents'))}</div>`;
    }
  }

  async function openDocumentLibrary(){
    const ref = ensureDocumentLibraryModal();
    const search = ref.modal.querySelector('.document-library-search-input');
    if (search) search.value = '';
    ref.modal.classList.add('open');
    ref.modal.setAttribute('aria-hidden','false');
    await loadDocumentLibrary();
  }


  // ---------- Document workspace UI ----------
  function ensureDocumentMeta(chat = state.currentChat){
    if (!chat) return null;
    chat.meta = chat.meta || {};
    if (!chat.meta.document || typeof chat.meta.document !== 'object') {
      chat.meta.document = { activeId: null, documents: {}, collapsed: false, maximized: false, viewMode: 'preview' };
    }
    const dm = chat.meta.document;
    if (!dm.documents || typeof dm.documents !== 'object' || Array.isArray(dm.documents)) dm.documents = {};
    if (!['preview','raw'].includes(String(dm.viewMode || ''))) dm.viewMode = 'preview';
    dm.maximized = !!dm.maximized;

    // Migration from the first single-document build.
    if (dm.active && typeof dm.active === 'object') {
      const migrated = normalizeDocumentUpdate(dm.active, null);
      dm.documents[migrated.id] = { ...(dm.documents[migrated.id] || {}), ...migrated };
      if (!dm.activeId) dm.activeId = migrated.id;
      delete dm.active;
    }

    if (!dm.activeId) {
      const firstId = Object.keys(dm.documents)[0] || null;
      dm.activeId = firstId;
    }
    return dm;
  }

  function documentList(chat = state.currentChat){
    const dm = ensureDocumentMeta(chat);
    if (!dm) return [];
    return Object.values(dm.documents || {}).filter(d => d && typeof d === 'object')
      .sort((a,b)=> Number(b.updated_at || 0) - Number(a.updated_at || 0));
  }

  function activeDocument(chat = state.currentChat){
    const dm = ensureDocumentMeta(chat);
    if (!dm) return null;
    const id = dm.activeId;
    return (id && dm.documents && dm.documents[id] && typeof dm.documents[id] === 'object') ? dm.documents[id] : null;
  }

  function documentVersionEntries(doc){
    if (!doc || typeof doc !== 'object') return [];
    const map = new Map();
    const add = (v)=>{
      if (!v || typeof v !== 'object') return;
      const ver = Number(v.version || 0);
      if (!Number.isFinite(ver) || ver <= 0) return;
      map.set(ver, {
        id: String(v.id || doc.id || ''),
        title: String(v.title || doc.title || 'Untitled document'),
        type: String(v.type || doc.type || 'markdown'),
        version: ver,
        content: String(v.content ?? ''),
        updated_at: Number(v.updated_at || 0)
      });
    };
    if (Array.isArray(doc.history)) doc.history.forEach(add);
    add(doc);
    return Array.from(map.values()).sort((a,b)=> Number(b.version||0) - Number(a.version||0));
  }

  function selectedDocumentVersion(doc = activeDocument()){
    if (!doc) return 0;
    const dm = ensureDocumentMeta();
    const wanted = Number(dm?.viewVersions?.[doc.id] || doc.version || 0);
    return Number.isFinite(wanted) && wanted > 0 ? wanted : Number(doc.version || 0);
  }

  function displayedDocumentSnapshot(){
    const doc = activeDocument();
    if (!doc) return null;
    const ver = selectedDocumentVersion(doc);
    return documentVersionEntries(doc).find(v => Number(v.version) === Number(ver)) || doc;
  }

  function normalizeDocumentUpdate(doc, prev = null){
    const out = (doc && typeof doc === 'object') ? { ...doc } : {};
    const old = (prev && typeof prev === 'object') ? prev : {};
    out.id = String(out.id || out.document_id || old.id || ('doc_' + now() + '_' + Math.random().toString(16).slice(2,8)));
    delete out.document_id;
    out.title = String(out.title || old.title || 'Untitled document');
    out.type = String(out.type || old.type || 'markdown');
    out.content = String(out.content ?? old.content ?? '');
    const oldVer = Number(old.version || 0);
    const newVer = Number(out.version || 0);
    out.version = Number.isFinite(newVer) && newVer > 0 ? newVer : (oldVer + 1);
    out.updated_at = Number(out.updated_at || now());
    if (!out.created_at) out.created_at = old.created_at || out.updated_at;

    const merged = new Map();
    const addHist = (v)=>{
      if (!v || typeof v !== 'object') return;
      const ver = Number(v.version || 0);
      if (!Number.isFinite(ver) || ver <= 0) return;
      merged.set(ver, {
        id: out.id,
        title: String(v.title || out.title),
        type: String(v.type || out.type),
        version: ver,
        content: String(v.content ?? ''),
        updated_at: Number(v.updated_at || 0)
      });
    };
    if (Array.isArray(old.history)) old.history.forEach(addHist);
    if (Array.isArray(out.history)) out.history.forEach(addHist);
    addHist({ id: out.id, title: out.title, type: out.type, version: out.version, content: out.content, updated_at: out.updated_at });
    out.history = Array.from(merged.values()).sort((a,b)=>Number(a.version||0)-Number(b.version||0)).slice(-50);
    return out;
  }

  function applyDocumentUpdate(doc, chat = state.currentChat){
    if (!chat) return;
    const dm = ensureDocumentMeta(chat);
    const incomingId = doc && (doc.id || doc.document_id);
    const prev = incomingId && dm.documents ? dm.documents[String(incomingId)] : activeDocument(chat);
    const next = normalizeDocumentUpdate(doc, prev);
    dm.documents[next.id] = next;
    dm.activeId = next.id;
    dm.viewVersions = dm.viewVersions || {};
    dm.viewVersions[next.id] = next.version;
    renderDocumentUI();
    saveChat(chat).catch(()=>{});
  }

  function isMarkdownPreviewable(doc){
    const type = String(doc?.type || '').toLowerCase();
    const title = String(doc?.title || '').toLowerCase();
    if (!doc) return false;
    if (type.includes('markdown') || type === 'md' || type === 'text' || type === 'txt' || type === 'prompt') return true;
    if (/\.(md|markdown|txt)$/i.test(title)) return true;
    return false;
  }

  function isHtmlPreviewable(doc){
    if (!doc) return false;
    const type = String(doc?.type || '').toLowerCase();
    const title = String(doc?.title || '').toLowerCase();
    const content = String(doc?.content || '').trim();
    if (type === 'html' || type === 'htm' || type.includes('html')) return true;
    if (/\.(html|htm)$/i.test(title)) return true;
    if (/^<!doctype\s+html/i.test(content) || /^<html[\s>]/i.test(content)) return true;
    return false;
  }

  function isCssDocument(doc){
    if (!doc) return false;
    const type = String(doc?.type || '').toLowerCase();
    const title = String(doc?.title || '').toLowerCase();
    if (type === 'css' || type.includes('css')) return true;
    if (/\.css$/i.test(title)) return true;
    return false;
  }

  function workspaceCssForDocument(activeDoc){
    const docs = documentList();
    const activeId = String(activeDoc?.id || '');
    return docs
      .filter(d => String(d?.id || '') !== activeId && isCssDocument(d))
      .map(d => `/* ${String(d.title || 'style.css').replace(/\*\//g, '* /')} */\n${String(d.content || '')}`)
      .filter(Boolean)
      .join('\n\n');
  }

  function openDocumentHtmlPreview(doc){
    if (!doc || !isHtmlPreviewable(doc)) return;
    const css = workspaceCssForDocument(doc);
    const title = doc.title ? `${doc.title} Preview` : 'HTML Document Preview';
    previewModal.open(title, buildHtmlPreviewDoc(doc.content || '', css));
  }

  // Document preview intentionally uses the exact same Markdown parser as chat.
  // Keeping a second reduced parser here caused feature drift (notably tables
  // and multi-line blockquotes). The shared md() renderer escapes raw input
  // before applying Markdown, so it is also the safe rendering path.


  function documentStateForPayload(chat = state.currentChat){
    const dm = ensureDocumentMeta(chat);
    if (!dm) return { mode: 'chat' };
    return {
      mode: 'document',
      active_id: dm.activeId || null,
      activeId: dm.activeId || null,
      collapsed: !!dm.collapsed,
      documents: dm.documents || {}
    };
  }

  function renderDocumentUI(){
    const dm = ensureDocumentMeta(state.currentChat);
    const docs = documentList();
    const doc = activeDocument();
    const on = !!state.webtools?.document;
    if (!documentPanel) return;
    documentPanel.classList.toggle('hidden', !on && !doc);
    documentPanel.classList.toggle('empty', !doc);
    documentPanel.classList.toggle('collapsed', !!dm?.collapsed);
    documentPanel.classList.toggle('maximized', !!dm?.maximized);
    if (documentRestoreBtn) {
      const showRestore = (!!on || !!doc) && !!dm?.collapsed;
      documentRestoreBtn.classList.toggle('hidden', !showRestore);
      documentRestoreBtn.classList.toggle('active', showRestore);
      const label = doc ? `Open documents: ${doc.title || 'Untitled document'}` : 'Open documents';
      documentRestoreBtn.title = label;
      documentRestoreBtn.setAttribute('aria-label', label);
    }
    if (documentMaximizeBtn) {
      documentMaximizeBtn.innerHTML = iconSvg(dm?.maximized ? 'minimize' : 'maximize');
      documentMaximizeBtn.title = dm?.maximized ? 'Restore document panel' : 'Maximize document panel';
      documentMaximizeBtn.setAttribute('aria-label', dm?.maximized ? 'Restore document panel' : 'Maximize document panel');
      documentMaximizeBtn.setAttribute('aria-pressed', dm?.maximized ? 'true' : 'false');
    }
    const shownDoc = displayedDocumentSnapshot();
    const shownVer = shownDoc ? Number(shownDoc.version || doc?.version || 1) : 0;
    const latestVer = doc ? Number(doc.version || 1) : 0;
    if (documentTitleEl) {
      documentTitleEl.textContent = '';
      documentTitleEl.classList.add('hidden');
    }
    if (documentVersionEl) {
      documentVersionEl.textContent = '';
      documentVersionEl.classList.add('hidden');
    }
    if (documentSelectEl) {
      const cur = dm?.activeId || '';
      documentSelectEl.innerHTML = '';
      const empty = document.createElement('option');
      empty.value = '';
      empty.textContent = docs.length ? 'Select document…' : 'No documents';
      documentSelectEl.appendChild(empty);
      docs.forEach(d => {
        const opt = document.createElement('option');
        opt.value = d.id;
        opt.textContent = `${d.title || 'Untitled'} · v${Number(d.version || 1)}`;
        documentSelectEl.appendChild(opt);
      });
      documentSelectEl.value = cur;
      documentSelectEl.disabled = docs.length === 0;
    }
    if (documentVersionSelectEl) {
      documentVersionSelectEl.innerHTML = '';
      const versions = documentVersionEntries(doc);
      versions.forEach(v => {
        const opt = document.createElement('option');
        opt.value = String(v.version);
        opt.textContent = `v${Number(v.version || 0)}${Number(v.version || 0) === latestVer ? ' · current' : ''}`;
        documentVersionSelectEl.appendChild(opt);
      });
      documentVersionSelectEl.value = shownDoc ? String(shownVer) : '';
      documentVersionSelectEl.disabled = !doc || versions.length <= 1;
      documentVersionSelectEl.classList.toggle('hidden', !doc || versions.length <= 1);
    }
    if (documentRestoreVersionBtn) {
      const canRestore = !!doc && !!shownDoc && Number(shownVer) !== Number(latestVer);
      documentRestoreVersionBtn.disabled = !canRestore;
      documentRestoreVersionBtn.classList.toggle('hidden', !doc || documentVersionEntries(doc).length <= 1);
      documentRestoreVersionBtn.title = canRestore ? `Restore v${shownVer} as new version` : 'Select an older version to restore';
    }
    if (documentCopyBtn) documentCopyBtn.disabled = !doc;
    if (documentDownloadBtn) documentDownloadBtn.disabled = !doc;
    if (documentDeleteBtn) documentDeleteBtn.disabled = !doc;
    const renderDoc = shownDoc || doc;
    const markdownPreviewable = isMarkdownPreviewable(renderDoc);
    const htmlPreviewable = isHtmlPreviewable(renderDoc);
    const previewable = markdownPreviewable || htmlPreviewable;
    const mode = markdownPreviewable ? String(dm?.viewMode || 'preview') : 'raw';
    if (documentViewPreviewBtn) {
      documentViewPreviewBtn.classList.toggle('active', markdownPreviewable && mode === 'preview');
      documentViewPreviewBtn.disabled = !doc || !previewable;
      documentViewPreviewBtn.title = htmlPreviewable ? 'Open HTML preview' : (markdownPreviewable ? 'Rendered preview' : 'Preview is available for Markdown/text/HTML documents');
    }
    if (documentViewRawBtn) {
      documentViewRawBtn.classList.toggle('active', mode === 'raw');
      documentViewRawBtn.disabled = !doc;
    }
    if (documentPreviewEl) {
      documentPreviewEl.classList.toggle('markdown-preview', mode === 'preview');
      documentPreviewEl.classList.toggle('raw-preview', mode !== 'preview');
      if (!doc) {
        documentPreviewEl.textContent = 'Document mode is on. Ask the model to create one or more documents, then pick the active file here.';
      } else if (mode === 'preview') {
        const renderedMarkdown = md(renderDoc.content || '');
        documentPreviewEl.innerHTML = renderedMarkdown || '<p class="muted">Empty document.</p>';
        // The shared chat renderer includes per-code-block controls. The document
        // panel already has document-level copy/download controls, so avoid a
        // second set of controls inside the preview itself.
        documentPreviewEl.querySelectorAll('.code-copy,.code-download,.code-preview').forEach(el=>el.remove());
        scheduleFitMermaid(documentPreviewEl);
      } else {
        documentPreviewEl.textContent = String(renderDoc.content || '');
      }
    }
  }

  function safeDocumentFilename(doc){
    const title = String(doc?.title || 'document').trim() || 'document';
    const cleaned = title.replace(/[\\/:*?"<>|]+/g, '-').replace(/\s+/g, ' ').trim().slice(0, 80) || 'document';
    if (/\.[a-z0-9]{1,8}$/i.test(cleaned)) return cleaned;
    const ext = extForLang(String(doc?.type || '').toLowerCase(), String(doc?.content || ''));
    return `${cleaned}.${ext || 'txt'}`;
  }

  async function copyActiveDocument(){
    const doc = displayedDocumentSnapshot();
    if (!doc) return;
    const txt = String(doc.content || '');
    try{ await navigator.clipboard.writeText(txt); }
    catch(_){
      const ta=document.createElement('textarea'); ta.value=txt; document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove();
    }
    const old = documentCopyBtn?.innerHTML;
    if (documentCopyBtn) {
      documentCopyBtn.textContent = '✓';
      setTimeout(()=>{ documentCopyBtn.innerHTML = old || iconSvg('fileText'); }, 800);
    }
  }

  function downloadActiveDocument(){
    const doc = displayedDocumentSnapshot();
    if (!doc) return;
    const content = String(doc.content || '');
    const filename = safeDocumentFilename(doc);
    const ext = (filename.match(/\.([a-z0-9]{1,8})$/i)?.[1] || 'txt').toLowerCase();
    const blob = new Blob([content], { type: mimeForExt(ext) });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(()=>{ try{ URL.revokeObjectURL(url); }catch(_){} }, 1500);
  }

  function restoreSelectedDocumentVersion(){
    const dm = ensureDocumentMeta();
    const doc = activeDocument();
    const snap = displayedDocumentSnapshot();
    if (!dm || !doc || !snap) return;
    const latestVer = Number(doc.version || 1);
    const restoreVer = Number(snap.version || latestVer);
    if (restoreVer === latestVer) return;
    const ok = confirm(`Restore “${doc.title || 'Untitled document'}” v${restoreVer} as a new version?`);
    if (!ok) return;
    const nowMs = now();
    const hist = documentVersionEntries(doc).sort((a,b)=>Number(a.version||0)-Number(b.version||0));
    const next = {
      ...doc,
      title: snap.title || doc.title,
      type: snap.type || doc.type,
      content: String(snap.content || ''),
      version: latestVer + 1,
      updated_at: nowMs,
      history: hist.slice(-49)
    };
    next.history.push({
      id: next.id,
      title: next.title,
      type: next.type,
      version: next.version,
      content: next.content,
      updated_at: next.updated_at
    });
    dm.documents[next.id] = next;
    dm.viewVersions = dm.viewVersions || {};
    dm.viewVersions[next.id] = next.version;
    renderDocumentUI();
    saveChat(state.currentChat).catch(()=>{});
  }

  function deleteActiveDocument(){
    const dm = ensureDocumentMeta();
    const doc = activeDocument();
    if (!dm || !doc) return;
    const ok = confirm(`Delete document “${doc.title || 'Untitled document'}”?`);
    if (!ok) return;
    delete dm.documents[doc.id];
    const next = documentList()[0] || null;
    dm.activeId = next ? next.id : null;
    dm.active_id = dm.activeId;
    renderDocumentUI();
    saveChat(state.currentChat).catch(()=>{});
  }

  documentCollapseBtn?.addEventListener('click', (e)=>{
    e.preventDefault(); e.stopPropagation();
    const dm = ensureDocumentMeta();
    if (!dm) return;
    dm.collapsed = !dm.collapsed;
    renderDocumentUI();
    saveChat(state.currentChat).catch(()=>{});
  });

  documentRestoreBtn?.addEventListener('click', (e)=>{
    e.preventDefault(); e.stopPropagation();
    const dm = ensureDocumentMeta();
    if (!dm) return;
    dm.collapsed = false;
    renderDocumentUI();
    saveChat(state.currentChat).catch(()=>{});
  });

  documentMaximizeBtn?.addEventListener('click', (e)=>{
    e.preventDefault(); e.stopPropagation();
    const dm = ensureDocumentMeta();
    if (!dm) return;
    dm.maximized = !dm.maximized;
    if (dm.maximized) dm.collapsed = false;
    renderDocumentUI();
    saveChat(state.currentChat).catch(()=>{});
  });

  document.addEventListener('keydown', (e)=>{
    if (e.key !== 'Escape') return;
    const dm = ensureDocumentMeta();
    if (!dm?.maximized) return;
    dm.maximized = false;
    renderDocumentUI();
    saveChat(state.currentChat).catch(()=>{});
  });

  documentSelectEl?.addEventListener('change', ()=>{
    const dm = ensureDocumentMeta();
    if (!dm) return;
    const id = documentSelectEl.value;
    if (id && dm.documents && dm.documents[id]) {
      dm.activeId = id;
      dm.active_id = id;
      dm.viewVersions = dm.viewVersions || {};
      delete dm.viewVersions[id];
      renderDocumentUI();
      saveChat(state.currentChat).catch(()=>{});
    }
  });

  documentVersionSelectEl?.addEventListener('change', ()=>{
    const dm = ensureDocumentMeta();
    const doc = activeDocument();
    if (!dm || !doc) return;
    dm.viewVersions = dm.viewVersions || {};
    const ver = Number(documentVersionSelectEl.value || doc.version || 1);
    if (Number.isFinite(ver) && ver > 0) dm.viewVersions[doc.id] = ver;
    renderDocumentUI();
    saveChat(state.currentChat).catch(()=>{});
  });

  documentRestoreVersionBtn?.addEventListener('click', (e)=>{
    e.preventDefault(); e.stopPropagation();
    restoreSelectedDocumentVersion();
  });

  documentViewPreviewBtn?.addEventListener('click', (e)=>{
    e.preventDefault(); e.stopPropagation();
    const dm = ensureDocumentMeta();
    const doc = activeDocument();
    const shownDoc = displayedDocumentSnapshot();
    const targetDoc = shownDoc || doc;
    if (!dm || !doc || !targetDoc) return;
    if (isHtmlPreviewable(targetDoc)) {
      openDocumentHtmlPreview(targetDoc);
      return;
    }
    if (!isMarkdownPreviewable(targetDoc)) return;
    dm.viewMode = 'preview';
    renderDocumentUI();
    saveChat(state.currentChat).catch(()=>{});
  });

  documentViewRawBtn?.addEventListener('click', (e)=>{
    e.preventDefault(); e.stopPropagation();
    const dm = ensureDocumentMeta();
    if (!dm) return;
    dm.viewMode = 'raw';
    renderDocumentUI();
    saveChat(state.currentChat).catch(()=>{});
  });

  documentCopyBtn?.addEventListener('click', (e)=>{
    e.preventDefault(); e.stopPropagation();
    copyActiveDocument();
  });

  documentDownloadBtn?.addEventListener('click', (e)=>{
    e.preventDefault(); e.stopPropagation();
    downloadActiveDocument();
  });

  documentDeleteBtn?.addEventListener('click', (e)=>{
    e.preventDefault(); e.stopPropagation();
    deleteActiveDocument();
  });

  function customToolKey(t){ return String(t?.id || t?.name || '').trim(); }
  function customToolName(t){ return String(t?.name || t?.id || '').trim(); }
  function customToolTitle(t){ return String(t?.title || t?.name || t?.id || 'Custom tool').trim(); }
  function customToolFunctionName(value){
    return String(value || '').trim().replace(/[^A-Za-z0-9_]+/g, '_').replace(/^[^A-Za-z_]+/, '').slice(0, 64);
  }
  function customToolNormalizeHeaders(raw){
    const out = {};
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return out;
    for (const [key,value] of Object.entries(raw)) {
      const name = String(key || '').trim();
      if (!name) continue;
      out[name] = String(value ?? '');
    }
    return out;
  }
  function customToolClone(value, fallback={}){
    try { return JSON.parse(JSON.stringify(value)); } catch(_) { return fallback; }
  }
  function customToolNormalizeParameters(raw){
    const schema = (raw && typeof raw === 'object' && !Array.isArray(raw)) ? customToolClone(raw,{}) : {};
    schema.type = 'object';
    if (!schema.properties || typeof schema.properties !== 'object' || Array.isArray(schema.properties)) schema.properties = {};
    if (!Array.isArray(schema.required)) schema.required = [];
    schema.required = schema.required.map(x=>String(x)).filter(Boolean);
    return schema;
  }
  function customToolNormalizeTimeout(value, fallback=30){
    const n = parseInt(String(value ?? ''),10);
    if (!Number.isFinite(n)) return fallback;
    return Math.max(1,Math.min(120,n));
  }
  function customToolNormalizeTool(tool, index=0){
    const rawName = String(tool?.name || tool?.id || `custom_tool_${index+1}`).trim();
    const name = rawName || `custom_tool_${index+1}`;
    const method = String(tool?.method || 'POST').toUpperCase() === 'GET' ? 'GET' : 'POST';
    return {
      id:String(tool?.id || name).trim() || name,
      name,
      title:String(tool?.title || name).trim() || name,
      description:String(tool?.description || '').trim(),
      endpoint:String(tool?.endpoint || tool?.url || '').trim(),
      method,
      headers:customToolNormalizeHeaders(tool?.headers),
      allow_private:!!tool?.allow_private,
      timeout_sec:customToolNormalizeTimeout(tool?.timeout_sec,30),
      parameters:customToolNormalizeParameters(tool?.parameters),
      body_template:typeof tool?.body_template === 'string' ? tool.body_template : ''
    };
  }
  function customToolsCurrent(){
    return (Array.isArray(state.ui.customTools) ? state.ui.customTools : []).map((tool,index)=>customToolNormalizeTool(tool,index));
  }
  function defaultCustomToolNames(){
    if (!state.ui.customToolsAutoEnable) return [];
    return customToolsCurrent().map(t=>customToolName(t)).filter(Boolean);
  }
  function enabledCustomTools(){
    const arr = Array.isArray(state.webtools?.custom_tools) ? state.webtools.custom_tools : [];
    return new Set(arr.map(x=>String(x)).filter(Boolean));
  }
  function setEnabledCustomTools(set){
    state.webtools.custom_tools = Array.from(set || []).filter(Boolean);
  }
  function customToolSetPageStatus(message, kind=''){
    if (!settingCustomToolsStatus) return;
    settingCustomToolsStatus.textContent = String(message || '');
    settingCustomToolsStatus.classList.toggle('ok', kind === 'ok');
    settingCustomToolsStatus.classList.toggle('err', kind === 'err');
  }
  function customToolSyncRawEditor(){
    const tools = customToolsCurrent();
    const pretty = JSON.stringify(tools,null,2);
    state.ui.customToolsJson = pretty;
    if (settingCustomToolsJson && settingCustomToolsJson !== document.activeElement) settingCustomToolsJson.value = pretty;
  }
  function customToolHostLabel(url){
    try { return new URL(String(url || '')).host || String(url || ''); }
    catch(_) { return String(url || ''); }
  }
  function customToolIsLocalUrl(url){
    try {
      const host = new URL(String(url || '')).hostname.toLowerCase();
      return host === 'localhost' || host === '127.0.0.1' || host === '::1' || /^10\./.test(host) || /^192\.168\./.test(host) || /^172\.(1[6-9]|2\d|3[01])\./.test(host);
    } catch(_) { return false; }
  }
  function customToolParameterCount(tool){
    const props = customToolNormalizeParameters(tool?.parameters).properties;
    return Object.keys(props).length;
  }
  function renderCustomToolsSettingsUI(){
    if (settingCustomToolsAutoEnable) settingCustomToolsAutoEnable.checked = !!state.ui.customToolsAutoEnable;
    const tools = customToolsCurrent();
    state.ui.customTools = tools;
    if (settingCustomToolsJson && settingCustomToolsJson !== document.activeElement) {
      settingCustomToolsJson.value = String(state.ui.customToolsJson || '[]');
    }
    if (customToolsList) {
      customToolsList.innerHTML = '';
      for (const [index,tool] of tools.entries()) {
        const card = document.createElement('div');
        card.className = 'conn-card custom-tool-card';
        const headers = Object.keys(customToolNormalizeHeaders(tool.headers)).length;
        const params = customToolParameterCount(tool);
        const local = customToolIsLocalUrl(tool.endpoint) || !!tool.allow_private;
        const host = customToolHostLabel(tool.endpoint);
        card.innerHTML = `
          <div class="conn-card-head">
            <div class="custom-tool-card-main">
              <div class="conn-title">${esc(customToolTitle(tool))}</div>
              <div class="conn-sub mono">${esc(tool.name)}${host ? ` · ${esc(host)}` : ''}</div>
            </div>
            <div class="conn-actions">
              <button class="btn btn-ghost" type="button" data-custom-tool-cmd="edit" data-index="${index}">Edit</button>
              <button class="btn btn-danger" type="button" data-custom-tool-cmd="delete" data-index="${index}">Delete</button>
            </div>
          </div>
          <div class="conn-card-body">
            <div class="custom-tool-card-badges">
              <span class="model-badge">${esc(tool.method)}</span>
              <span class="model-badge">${params} parameter${params===1?'':'s'}</span>
              ${headers ? `<span class="model-badge">${headers} header${headers===1?'':'s'}</span>` : ''}
              ${local ? `<span class="model-badge">private network allowed</span>` : ''}
              ${tool.body_template ? `<span class="model-badge">custom body</span>` : ''}
            </div>
            <div class="custom-tool-card-endpoint mono">${esc(tool.endpoint || 'No endpoint')}</div>
            ${tool.description ? `<div class="muted custom-tool-card-description">${esc(tool.description)}</div>` : ''}
          </div>`;
        customToolsList.appendChild(card);
      }
    }
    customToolsEmpty?.classList.toggle('hidden', tools.length > 0);
    if (!String(settingCustomToolsStatus?.textContent || '').trim()) {
      customToolSetPageStatus(tools.length ? `${tools.length} custom tool${tools.length===1?'':'s'} configured.` : 'No custom tools configured.');
    }
  }
  async function persistCustomTools(tools, message='Custom tools updated.'){
    const normalized = (Array.isArray(tools) ? tools : []).map((tool,index)=>customToolNormalizeTool(tool,index));
    const names = new Set();
    const ids = new Set();
    for (const tool of normalized) {
      if (!/^[A-Za-z_][A-Za-z0-9_]{0,63}$/.test(tool.name)) throw new Error(`${tool.title || tool.name}: Function name is invalid.`);
      if (!tool.description) throw new Error(`${tool.title || tool.name}: Description is required.`);
      if (!tool.endpoint) throw new Error(`${tool.title || tool.name}: Endpoint is required.`);
      if (names.has(tool.name)) throw new Error(`Duplicate function name: ${tool.name}`);
      names.add(tool.name);
      if (tool.id && ids.has(tool.id)) throw new Error(`Duplicate tool ID: ${tool.id}`);
      if (tool.id) ids.add(tool.id);
    }
    const pretty = JSON.stringify(normalized,null,2);
    await api('settings_save',{custom_tools_json:pretty});
    state.ui.customTools = normalized;
    state.ui.customToolsJson = pretty;
    if (settingCustomToolsJson) settingCustomToolsJson.value = pretty;

    const valid = new Set();
    for (const tool of normalized) { valid.add(tool.name); if (tool.id) valid.add(tool.id); }
    const hasOverride = !!(state.currentChat?.meta && state.currentChat.meta.webtools);
    if (hasOverride) {
      state.webtools.custom_tools = Array.from(enabledCustomTools()).filter(key=>valid.has(key));
      persistCurrentWebTools();
    } else {
      state.webtools.custom_tools = defaultCustomToolNames();
    }
    customToolSetPageStatus(message,'ok');
    renderCustomToolsSettingsUI();
    renderWebTools();
  }
  function parseCustomToolsEditor(){
    const parsed = JSON.parse(String(settingCustomToolsJson?.value || '[]').trim() || '[]');
    if (!Array.isArray(parsed)) throw new Error('Top-level JSON must be an array.');
    return parsed;
  }
  async function saveCustomToolsFromSettings(){
    try {
      const parsed = parseCustomToolsEditor();
      await persistCustomTools(parsed, `Applied ${parsed.length} custom tool${parsed.length===1?'':'s'} from raw configuration.`);
    } catch(ex) {
      customToolSetPageStatus(ex?.message || 'Could not apply raw custom tool configuration.','err');
    }
  }

  let customToolEditorIdWasEdited = false;
  let customToolEditorBaseParameters = customToolNormalizeParameters({});

  function customToolSetEditorResult(kind, message){
    if (!customToolEditorResult) return;
    customToolEditorResult.classList.remove('hidden','ok','err');
    customToolEditorResult.classList.add(kind === 'ok' ? 'ok' : 'err');
    customToolEditorResult.textContent = String(message || '');
  }
  function customToolClearEditorResult(){
    if (!customToolEditorResult) return;
    customToolEditorResult.classList.add('hidden');
    customToolEditorResult.classList.remove('ok','err');
    customToolEditorResult.textContent = '';
  }
  function customToolRefreshHeaderEmpty(){
    if (!customToolNoHeaders || !customToolHeaderList) return;
    customToolNoHeaders.classList.toggle('hidden', customToolHeaderList.querySelectorAll('.custom-tool-header-row').length > 0);
  }
  function customToolAddHeaderRow(name='',value=''){
    if (!customToolHeaderList) return;
    const row = document.createElement('div');
    row.className = 'mcp-header-row custom-tool-header-row';
    row.innerHTML = `
      <input class="mcp-header-name custom-tool-header-name" type="text" placeholder="Header name" spellcheck="false" value="${esc(name)}" />
      <input class="mcp-header-value custom-tool-header-value" type="text" placeholder="Value" spellcheck="false" value="${esc(value)}" />
      <button class="icon-btn mcp-header-remove custom-tool-header-remove" type="button" aria-label="Remove header">✕</button>`;
    customToolHeaderList.appendChild(row);
    customToolRefreshHeaderEmpty();
    row.querySelector('.custom-tool-header-name')?.focus();
  }
  function customToolRenderHeaders(headers){
    if (!customToolHeaderList) return;
    customToolHeaderList.innerHTML = '';
    for (const [name,value] of Object.entries(customToolNormalizeHeaders(headers))) customToolAddHeaderRow(name,value);
    customToolRefreshHeaderEmpty();
  }
  function customToolCollectHeaders(){
    const headers = {};
    for (const row of Array.from(customToolHeaderList?.querySelectorAll('.custom-tool-header-row') || [])) {
      const name = String(row.querySelector('.custom-tool-header-name')?.value || '').trim();
      if (!name) continue;
      headers[name] = String(row.querySelector('.custom-tool-header-value')?.value || '');
    }
    return headers;
  }
  function customToolRefreshParameterEmpty(){
    if (!customToolNoParameters || !customToolParameterList) return;
    customToolNoParameters.classList.toggle('hidden', customToolParameterList.querySelectorAll('.custom-tool-parameter-row').length > 0);
  }
  function customToolAddParameterRow(name='', schema={}, required=false, focus=true){
    if (!customToolParameterList) return;
    const original = (schema && typeof schema === 'object' && !Array.isArray(schema)) ? customToolClone(schema,{}) : {};
    const type = ['string','number','integer','boolean','object','array'].includes(String(original.type || '')) ? String(original.type) : '';
    const row = document.createElement('div');
    row.className = 'custom-tool-parameter-row';
    row._customToolSchema = original;
    row.innerHTML = `
      <input class="custom-tool-param-name" type="text" placeholder="email" spellcheck="false" value="${esc(name)}" />
      <select class="custom-tool-param-type">
        <option value=""${type===''?' selected':''}>Any</option>
        <option value="string"${type==='string'?' selected':''}>String</option>
        <option value="number"${type==='number'?' selected':''}>Number</option>
        <option value="integer"${type==='integer'?' selected':''}>Integer</option>
        <option value="boolean"${type==='boolean'?' selected':''}>Boolean</option>
        <option value="object"${type==='object'?' selected':''}>Object</option>
        <option value="array"${type==='array'?' selected':''}>Array</option>
      </select>
      <input class="custom-tool-param-description" type="text" placeholder="What this argument means" value="${esc(String(original.description || ''))}" />
      <label class="custom-tool-param-required"><input type="checkbox" ${required?'checked':''} /><span>Required</span></label>
      <button class="icon-btn custom-tool-param-remove" type="button" aria-label="Remove parameter">✕</button>`;
    customToolParameterList.appendChild(row);
    customToolRefreshParameterEmpty();
    if (focus) row.querySelector('.custom-tool-param-name')?.focus();
  }
  function customToolRenderParameters(parameters){
    if (!customToolParameterList) return;
    const schema = customToolNormalizeParameters(parameters);
    customToolEditorBaseParameters = customToolClone(schema,customToolNormalizeParameters({}));
    customToolParameterList.innerHTML = '';
    const required = new Set(schema.required || []);
    for (const [name,prop] of Object.entries(schema.properties || {})) customToolAddParameterRow(name,prop,required.has(name),false);
    customToolRefreshParameterEmpty();
  }
  function customToolCollectParameters(){
    const base = customToolClone(customToolEditorBaseParameters,customToolNormalizeParameters({}));
    base.type = 'object';
    base.properties = {};
    const required = [];
    const seen = new Set();
    for (const row of Array.from(customToolParameterList?.querySelectorAll('.custom-tool-parameter-row') || [])) {
      const name = String(row.querySelector('.custom-tool-param-name')?.value || '').trim();
      if (!name) continue;
      if (seen.has(name)) throw new Error(`Duplicate parameter name: ${name}`);
      seen.add(name);
      const schema = customToolClone(row._customToolSchema || {},{});
      const type = String(row.querySelector('.custom-tool-param-type')?.value || '');
      const description = String(row.querySelector('.custom-tool-param-description')?.value || '').trim();
      if (type) schema.type = type; else delete schema.type;
      if (description) schema.description = description; else delete schema.description;
      base.properties[name] = schema;
      if (row.querySelector('.custom-tool-param-required input')?.checked) required.push(name);
    }
    base.required = required;
    return base;
  }
  function customToolSyncBodyUI(){
    const isPost = String(customToolEditMethod?.value || 'POST') === 'POST';
    customToolBodyCard?.classList.toggle('hidden', !isPost);
    if (!isPost) return;
    const custom = String(customToolEditBodyMode?.value || 'default') === 'template';
    customToolBodyTemplateWrap?.classList.toggle('hidden', !custom);
    if (customToolBodyModeHint) customToolBodyModeHint.innerHTML = custom
      ? 'Build the POST body with <code>{{parameter}}</code> placeholders.'
      : 'Default sends <code>{"arguments": ...}</code> as JSON.';
  }
  function openCustomToolEditor(index=-1){
    const tools = customToolsCurrent();
    const editing = Number.isInteger(Number(index)) && Number(index) >= 0 && Number(index) < tools.length;
    let name = 'custom_tool';
    let suffix = 2;
    const used = new Set(tools.map(tool=>tool.name));
    while (used.has(name)) name = `custom_tool_${suffix++}`;
    const tool = editing ? tools[Number(index)] : customToolNormalizeTool({
      id:name,
      name,
      title:'New Custom Tool',
      description:'',
      endpoint:'',
      method:'POST',
      parameters:{type:'object',properties:{},required:[]},
      timeout_sec:30
    }, tools.length);
    if (customToolEditIndex) customToolEditIndex.value = editing ? String(index) : '-1';
    if (customToolEditTitle) customToolEditTitle.value = tool.title;
    if (customToolEditName) customToolEditName.value = tool.name;
    if (customToolEditDescription) customToolEditDescription.value = tool.description;
    if (customToolEditMethod) customToolEditMethod.value = tool.method;
    if (customToolEditEndpoint) customToolEditEndpoint.value = tool.endpoint;
    if (customToolEditAllowPrivate) customToolEditAllowPrivate.checked = !!tool.allow_private;
    if (customToolEditBodyMode) customToolEditBodyMode.value = tool.body_template ? 'template' : 'default';
    if (customToolEditBodyTemplate) customToolEditBodyTemplate.value = tool.body_template;
    if (customToolEditId) customToolEditId.value = tool.id;
    if (customToolEditTimeout) customToolEditTimeout.value = String(tool.timeout_sec);
    customToolEditorIdWasEdited = editing && tool.id !== tool.name;
    customToolRenderHeaders(tool.headers);
    customToolRenderParameters(tool.parameters);
    customToolSyncBodyUI();
    customToolClearEditorResult();
    const title = $('#custom-tool-editor-title');
    if (title) title.textContent = editing ? 'Edit Custom Tool' : 'Add Custom Tool';
    if (customToolEditorApply) customToolEditorApply.textContent = editing ? 'Update tool' : 'Add tool';
    customToolEditorModal?.classList.remove('hidden');
    requestAnimationFrame(()=>customToolEditTitle?.focus());
  }
  function closeCustomToolEditor(){ customToolEditorModal?.classList.add('hidden'); }
  function collectCustomToolEditorTool(){
    const name = String(customToolEditName?.value || '').trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]{0,63}$/.test(name)) throw new Error('Function name must start with a letter or underscore and contain only letters, numbers and underscores (max. 64 characters).');
    const title = String(customToolEditTitle?.value || '').trim() || name;
    const description = String(customToolEditDescription?.value || '').trim();
    if (!description) throw new Error('Description is required.');
    const endpoint = String(customToolEditEndpoint?.value || '').trim();
    if (!endpoint) throw new Error('Endpoint is required.');
    try {
      const parsed = new URL(endpoint);
      if (!/^https?:$/.test(parsed.protocol)) throw new Error('');
    } catch(_) { throw new Error('Endpoint must be a valid HTTP or HTTPS URL.'); }
    const method = String(customToolEditMethod?.value || 'POST') === 'GET' ? 'GET' : 'POST';
    const bodyTemplate = method === 'POST' && String(customToolEditBodyMode?.value || 'default') === 'template'
      ? String(customToolEditBodyTemplate?.value || '')
      : '';
    return customToolNormalizeTool({
      id:String(customToolEditId?.value || '').trim() || name,
      name,
      title,
      description,
      endpoint,
      method,
      headers:customToolCollectHeaders(),
      allow_private:!!customToolEditAllowPrivate?.checked,
      timeout_sec:customToolNormalizeTimeout(customToolEditTimeout?.value,30),
      parameters:customToolCollectParameters(),
      body_template:bodyTemplate
    });
  }


  const mcpTestState = new Map();
  let mcpEditorIdWasEdited = false;

  function mcpClamp(value, min, max, fallback){
    const n = Number(value);
    if (!Number.isFinite(n)) return fallback;
    return Math.max(min, Math.min(max, Math.round(n)));
  }
  function mcpNormalizeTimeoutSec(value, fallback=3600){
    const n = parseInt(String(value ?? ''), 10);
    if (!Number.isFinite(n)) return fallback;
    if (n < 0) return 0;
    if (n > 2592000) return 2592000;
    return n;
  }
  function mcpServerKey(server){
    const raw = String(server?.id || server?.name || '').trim();
    return raw.replace(/[^A-Za-z0-9_-]+/g, '_').replace(/^[_-]+|[_-]+$/g, '').slice(0, 40);
  }
  function mcpServerTitle(server){ return String(server?.name || server?.id || 'MCP server').trim(); }
  function mcpNormalizeHeaders(raw){
    const out = {};
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return out;
    for (const [key, value] of Object.entries(raw)) {
      const name = String(key || '').trim();
      if (!name) continue;
      out[name] = String(value ?? '');
    }
    return out;
  }
  function mcpNormalizeServer(server, index=0){
    const name = String(server?.name || server?.title || server?.id || `MCP Server ${index+1}`).trim() || `MCP Server ${index+1}`;
    const id = mcpServerKey({id:server?.id || name}) || `server_${index+1}`;
    return {
      id,
      name,
      description: String(server?.description || '').trim(),
      url: String(server?.url || server?.endpoint || '').trim(),
      token: String(server?.token || server?.bearer_token || ''),
      headers: mcpNormalizeHeaders(server?.headers),
      allow_private: !!server?.allow_private,
      timeout_sec: mcpNormalizeTimeoutSec(server?.timeout_sec, 3600),
      max_response_bytes: mcpClamp(server?.max_response_bytes, 65536, 64*1024*1024, 32*1024*1024),
      follow_exec_jobs: server?.follow_exec_jobs !== false,
      protocol_version: String(server?.protocol_version || '2025-11-25').trim() || '2025-11-25'
    };
  }
  function mcpCurrentServers(){
    return (Array.isArray(state.ui.mcpServers) ? state.ui.mcpServers : []).map((server,index)=>mcpNormalizeServer(server,index));
  }
  function defaultMcpServerIds(){
    if (!state.ui.mcpServersAutoEnable) return [];
    return mcpCurrentServers().map(mcpServerKey).filter(Boolean);
  }
  function enabledMcpServers(){
    return new Set((Array.isArray(state.webtools?.mcp_servers) ? state.webtools.mcp_servers : []).map(x=>String(x)).filter(Boolean));
  }
  function setEnabledMcpServers(set){ state.webtools.mcp_servers = Array.from(set || []).filter(Boolean); }
  function mcpSetPageStatus(message, kind=''){
    if (!settingMcpServersStatus) return;
    settingMcpServersStatus.textContent = String(message || '');
    settingMcpServersStatus.classList.toggle('ok', kind === 'ok');
    settingMcpServersStatus.classList.toggle('err', kind === 'err');
  }
  function renderMcpContextSettingsUI(){
    const mode = String(state.ui.mcpContextMode || 'externalize') === 'externalize' ? 'externalize' : 'full';
    if (settingMcpContextMode) settingMcpContextMode.value = mode;
    if (settingMcpExternalizeAbove) settingMcpExternalizeAbove.value = String(mcpClamp(state.ui.mcpExternalizeAboveTokens, 500, 200000, 6000));
    if (settingMcpPreviewMax) settingMcpPreviewMax.value = String(mcpClamp(state.ui.mcpPreviewMaxTokens, 200, 50000, 2500));
    if (settingMcpFullPassMax) settingMcpFullPassMax.value = String(mcpClamp(state.ui.mcpFullFirstPassMaxTokens, 0, 200000, 32000));
    mcpContextLimits?.classList.toggle('disabled', mode !== 'externalize');
    if (settingMcpContextStatus && !String(settingMcpContextStatus.textContent || '').trim()) {
      settingMcpContextStatus.textContent = mode === 'externalize'
        ? 'Changes are saved automatically. Large MCP results are stored as artifacts; very large results use the preview immediately.'
        : 'Changes are saved automatically. Full MCP results remain in every later agent request.';
    }
  }
  async function saveMcpContextSettings(){
    const mode = String(settingMcpContextMode?.value || 'externalize') === 'externalize' ? 'externalize' : 'full';
    const threshold = mcpClamp(settingMcpExternalizeAbove?.value, 500, 200000, 6000);
    const preview = mcpClamp(settingMcpPreviewMax?.value, 200, 50000, 2500);
    const fullFirstPassMax = mcpClamp(settingMcpFullPassMax?.value, 0, 200000, 32000);
    if (preview >= threshold && mode === 'externalize') {
      if (settingMcpContextStatus) settingMcpContextStatus.textContent = 'Maximum preview must be smaller than the externalization threshold.';
      return;
    }

    // Apply locally before the asynchronous persistence call. Every chat request
    // sends these exact values to the backend, so the visible UI mode is never
    // dependent on whether an earlier settings request has already completed.
    state.ui.mcpContextMode = mode;
    state.ui.mcpExternalizeAboveTokens = threshold;
    state.ui.mcpPreviewMaxTokens = preview;
    state.ui.mcpFullFirstPassMaxTokens = fullFirstPassMax;
    renderMcpContextSettingsUI();

    try {
      await api('settings_save', {
        mcp_context_mode: mode,
        mcp_externalize_above_tokens: threshold,
        mcp_preview_max_tokens: preview,
        mcp_full_first_pass_max_tokens: fullFirstPassMax
      });
      if (settingMcpContextStatus) settingMcpContextStatus.textContent = mode === 'externalize'
        ? `Saved automatically. MCP results above ${threshold} tokens become artifacts; results above ${fullFirstPassMax} tokens use the ${preview}-token preview immediately.`
        : 'Saved automatically. MCP results remain in full context.';
    } catch(ex) {
      if (settingMcpContextStatus) settingMcpContextStatus.textContent = (ex?.message || 'Could not persist MCP context handling.') + ' The current page still uses the selected mode for chat requests.';
    }
  }
  function mcpSyncRawEditor(){
    const servers = mcpCurrentServers();
    const pretty = JSON.stringify(servers, null, 2);
    state.ui.mcpServersJson = pretty;
    if (settingMcpServersJson && settingMcpServersJson !== document.activeElement) settingMcpServersJson.value = pretty;
  }
  function mcpHostLabel(url){
    try { return new URL(String(url || '')).host || String(url || ''); }
    catch(_) { return String(url || ''); }
  }
  function mcpIsLocalUrl(url){
    try {
      const host = new URL(String(url || '')).hostname.toLowerCase();
      return host === 'localhost' || host === '127.0.0.1' || host === '::1' || /^10\./.test(host) || /^192\.168\./.test(host) || /^172\.(1[6-9]|2\d|3[01])\./.test(host);
    } catch(_) { return false; }
  }
  function mcpRenderTestState(server){
    const stateItem = mcpTestState.get(mcpServerKey(server));
    if (!stateItem) return '';
    const cls = stateItem.ok ? 'ok' : 'err';
    return `<div class="mcp-card-test ${cls}">${esc(stateItem.text || '')}</div>`;
  }
  function renderMcpSettingsUI(){
    if (settingMcpServersAutoEnable) settingMcpServersAutoEnable.checked = !!state.ui.mcpServersAutoEnable;
    renderMcpContextSettingsUI();
    const servers = mcpCurrentServers();
    state.ui.mcpServers = servers;
    mcpSyncRawEditor();

    if (mcpList) {
      mcpList.innerHTML = '';
      for (const [index, server] of servers.entries()) {
        const card = document.createElement('div');
        card.className = 'conn-card mcp-card';
        const auth = String(server.token || '') !== '';
        const headerCount = Object.keys(mcpNormalizeHeaders(server.headers)).length;
        const local = mcpIsLocalUrl(server.url);
        card.innerHTML = `
          <div class="conn-card-head">
            <div class="mcp-card-main">
              <div class="conn-title">${esc(mcpServerTitle(server))}</div>
              <div class="conn-sub mono">${esc(server.url || 'No URL')}</div>
            </div>
            <div class="conn-actions">
              <button class="btn btn-ghost" type="button" data-mcp-cmd="test" data-index="${index}">Test</button>
              <button class="btn btn-ghost" type="button" data-mcp-cmd="edit" data-index="${index}">Edit</button>
              <button class="btn btn-danger" type="button" data-mcp-cmd="delete" data-index="${index}">Delete</button>
            </div>
          </div>
          <div class="conn-card-body">
            <div class="mcp-card-badges">
              <span class="model-badge">${esc(server.id)}</span>
              <span class="model-badge">${auth ? 'Bearer auth' : 'No auth'}</span>
              ${headerCount ? `<span class="model-badge">${headerCount} custom header${headerCount===1?'':'s'}</span>` : ''}
              ${local ? `<span class="model-badge">local/private</span>` : ''}
              <span class="model-badge">${server.follow_exec_jobs !== false ? 'exec jobs followed' : 'exec jobs detached'}</span>
              <span class="model-badge">${esc(server.protocol_version)}</span>
            </div>
            ${server.description ? `<div class="muted mcp-card-description">${esc(server.description)}</div>` : ''}
            ${mcpRenderTestState(server)}
          </div>`;
        mcpList.appendChild(card);
      }
    }
    mcpEmpty?.classList.toggle('hidden', servers.length > 0);
    if (!String(settingMcpServersStatus?.textContent || '').trim()) {
      mcpSetPageStatus(servers.length ? `${servers.length} MCP server${servers.length===1?'':'s'} configured.` : 'No MCP servers configured.');
    }
  }
  async function persistMcpServers(servers, message='MCP servers saved.'){
    const normalized = (Array.isArray(servers) ? servers : []).map((server,index)=>mcpNormalizeServer(server,index));
    const seen = new Set();
    for (const server of normalized) {
      if (!server.url) throw new Error(`${server.name}: Server URL is required.`);
      if (seen.has(server.id)) throw new Error(`Duplicate MCP server ID: ${server.id}`);
      seen.add(server.id);
    }
    const pretty = JSON.stringify(normalized, null, 2);
    await api('settings_save', {mcp_servers_json:pretty});
    state.ui.mcpServers = normalized;
    state.ui.mcpServersJson = pretty;
    if (settingMcpServersJson) settingMcpServersJson.value = pretty;

    const valid = new Set(normalized.map(mcpServerKey));
    const hasOverride = !!(state.currentChat?.meta && state.currentChat.meta.webtools);
    if (hasOverride) {
      state.webtools.mcp_servers = Array.from(enabledMcpServers()).filter(id=>valid.has(id));
      persistCurrentWebTools();
    } else {
      state.webtools.mcp_servers = defaultMcpServerIds();
    }
    for (const key of Array.from(mcpTestState.keys())) if (!valid.has(key)) mcpTestState.delete(key);
    mcpSetPageStatus(message, 'ok');
    renderMcpSettingsUI();
    renderWebTools();
  }
  function parseMcpServersEditor(){
    const parsed = JSON.parse(String(settingMcpServersJson?.value || '[]').trim() || '[]');
    if (!Array.isArray(parsed)) throw new Error('Top-level JSON must be an array.');
    return parsed;
  }
  async function saveMcpServersFromSettings(){
    try {
      const parsed = parseMcpServersEditor();
      await persistMcpServers(parsed, `Applied ${parsed.length} MCP server${parsed.length===1?'':'s'} from raw JSON.`);
    } catch(ex) {
      mcpSetPageStatus(ex?.message || 'Could not apply raw MCP configuration.', 'err');
    }
  }

  function mcpSetEditorResult(kind, lines){
    if (!mcpEditorResult) return;
    mcpEditorResult.classList.remove('hidden','ok','err');
    mcpEditorResult.classList.add(kind === 'ok' ? 'ok' : 'err');
    mcpEditorResult.textContent = Array.isArray(lines) ? lines.join('\n') : String(lines || '');
  }
  function mcpClearEditorResult(){
    if (!mcpEditorResult) return;
    mcpEditorResult.classList.add('hidden');
    mcpEditorResult.classList.remove('ok','err');
    mcpEditorResult.textContent = '';
  }
  function mcpRefreshHeaderEmpty(){
    if (!mcpNoHeaders || !mcpHeaderList) return;
    mcpNoHeaders.classList.toggle('hidden', mcpHeaderList.querySelectorAll('.mcp-header-row').length > 0);
  }
  function mcpAddHeaderRow(name='', value=''){
    if (!mcpHeaderList) return;
    const row = document.createElement('div');
    row.className = 'mcp-header-row';
    row.innerHTML = `
      <input class="mcp-header-name" type="text" placeholder="Header name" spellcheck="false" value="${esc(name)}" />
      <input class="mcp-header-value" type="text" placeholder="Value" spellcheck="false" value="${esc(value)}" />
      <button class="icon-btn mcp-header-remove" type="button" aria-label="Remove header">✕</button>`;
    mcpHeaderList.appendChild(row);
    mcpRefreshHeaderEmpty();
    row.querySelector('.mcp-header-name')?.focus();
  }
  function mcpRenderHeaders(headers){
    if (!mcpHeaderList) return;
    mcpHeaderList.innerHTML = '';
    for (const [name,value] of Object.entries(mcpNormalizeHeaders(headers))) mcpAddHeaderRow(name,value);
    mcpRefreshHeaderEmpty();
  }
  function mcpSetAuthEnabled(enabled){
    if (mcpEditAuthEnabled) mcpEditAuthEnabled.checked = !!enabled;
    mcpEditTokenWrap?.classList.toggle('hidden', !enabled);
    if (!enabled && mcpEditToken) {
      mcpEditToken.type = 'password';
      mcpEditToken.classList.remove('is-revealed');
    }
    if (mcpTokenReveal) mcpTokenReveal.textContent = 'Show';
  }
  function openMcpEditor(index=-1){
    const servers = mcpCurrentServers();
    const editing = Number.isInteger(Number(index)) && Number(index) >= 0 && Number(index) < servers.length;
    let newId = 'local';
    let suffix = 2;
    const usedIds = new Set(servers.map(mcpServerKey));
    while (usedIds.has(newId)) newId = `local_${suffix++}`;
    const server = editing ? servers[Number(index)] : mcpNormalizeServer({
      id:newId,
      name:newId === 'local' ? 'Local MCP Server' : `Local MCP Server ${suffix-1}`,
      url:'http://127.0.0.1:8765/mcp',
      token:'change-me',
      allow_private:true,
      timeout_sec:3600,
      max_response_bytes:32*1024*1024,
      follow_exec_jobs:true,
      protocol_version:'2025-11-25'
    }, servers.length);
    if (mcpEditIndex) mcpEditIndex.value = editing ? String(index) : '-1';
    if (mcpEditName) mcpEditName.value = server.name;
    if (mcpEditId) mcpEditId.value = server.id;
    if (mcpEditUrl) mcpEditUrl.value = server.url;
    if (mcpEditDescription) mcpEditDescription.value = server.description;
    if (mcpEditToken) { mcpEditToken.value = server.token; mcpEditToken.type = 'password'; }
    if (mcpEditAllowPrivate) mcpEditAllowPrivate.checked = !!server.allow_private;
    if (mcpEditProtocol) mcpEditProtocol.value = server.protocol_version;
    if (mcpEditTimeout) mcpEditTimeout.value = String(server.timeout_sec);
    if (mcpEditMaxResponse) mcpEditMaxResponse.value = String(Math.max(1,Math.round(server.max_response_bytes/(1024*1024))));
    if (mcpEditFollowExecJobs) mcpEditFollowExecJobs.checked = server.follow_exec_jobs !== false;
    mcpSetAuthEnabled(String(server.token || '') !== '');
    mcpRenderHeaders(server.headers);
    mcpClearEditorResult();
    mcpEditorIdWasEdited = editing;
    const title = $('#mcp-editor-title');
    if (title) title.textContent = editing ? 'Edit MCP Server' : 'Add MCP Server';
    mcpEditorModal?.classList.remove('hidden');
    mcpEditorModal?.setAttribute('aria-hidden','false');
    window.setTimeout(()=>mcpEditName?.focus(),0);
  }
  function closeMcpEditor(){
    mcpEditorModal?.classList.add('hidden');
    mcpEditorModal?.setAttribute('aria-hidden','true');
    mcpClearEditorResult();
  }
  function collectMcpEditorServer(){
    const name = String(mcpEditName?.value || '').trim();
    const id = mcpServerKey({id:String(mcpEditId?.value || '').trim()});
    const url = String(mcpEditUrl?.value || '').trim();
    if (!name) throw new Error('Name is required.');
    if (!id) throw new Error('Server ID is required.');
    if (!url) throw new Error('Server URL is required.');
    let parsedUrl;
    try { parsedUrl = new URL(url); } catch(_) { throw new Error('Server URL is invalid.'); }
    if (!['http:','https:'].includes(parsedUrl.protocol)) throw new Error('Server URL must use http:// or https://.');

    const headers = {};
    for (const row of Array.from(mcpHeaderList?.querySelectorAll('.mcp-header-row') || [])) {
      const headerName = String(row.querySelector('.mcp-header-name')?.value || '').trim();
      const headerValue = String(row.querySelector('.mcp-header-value')?.value || '');
      if (!headerName && !headerValue.trim()) continue;
      if (!headerName) throw new Error('Every custom header needs a name.');
      if (Object.prototype.hasOwnProperty.call(headers, headerName)) throw new Error(`Duplicate custom header: ${headerName}`);
      headers[headerName] = headerValue;
    }
    const maxMb = mcpClamp(mcpEditMaxResponse?.value, 1, 64, 32);
    return mcpNormalizeServer({
      id,
      name,
      description:String(mcpEditDescription?.value || '').trim(),
      url,
      token:mcpEditAuthEnabled?.checked ? String(mcpEditToken?.value || '') : '',
      headers,
      allow_private:!!mcpEditAllowPrivate?.checked,
      timeout_sec:mcpNormalizeTimeoutSec(mcpEditTimeout?.value,3600),
      max_response_bytes:maxMb*1024*1024,
      follow_exec_jobs:mcpEditFollowExecJobs ? !!mcpEditFollowExecJobs.checked : true,
      protocol_version:String(mcpEditProtocol?.value || '2025-11-25').trim() || '2025-11-25'
    });
  }
  async function testMcpServer(server, {editor=false}={}){
    const key = mcpServerKey(server);
    if (editor) {
      if (mcpEditorTest) mcpEditorTest.disabled = true;
      mcpSetEditorResult('ok',['Testing connection…']);
    } else {
      mcpTestState.set(key,{ok:true,text:'Testing connection…'});
      renderMcpSettingsUI();
    }
    try {
      const result = await api('mcp_test',{server});
      const tools = Array.isArray(result.tools) ? result.tools.map(tool=>String(tool?.name || '')).filter(Boolean) : [];
      const line = `${Number(result.tool_count || 0)} tools · ${Number(result.duration_ms || 0)} ms · protocol ${String(result.protocol_version || server.protocol_version)}`;
      mcpTestState.set(key,{ok:true,text:`Connected: ${line}`});
      if (editor) {
        const lines = [`Connected: ${line}`];
        if (tools.length) lines.push(`Tools: ${tools.slice(0,12).join(', ')}${tools.length>12?' …':''}`);
        mcpSetEditorResult('ok',lines);
      }
      mcpSetPageStatus(`${mcpServerTitle(server)} connected successfully.`, 'ok');
      renderMcpSettingsUI();
      return result;
    } catch(ex) {
      const message = String(ex?.message || ex || 'Connection failed.');
      mcpTestState.set(key,{ok:false,text:`Connection failed: ${message}`});
      if (editor) mcpSetEditorResult('err',[`Connection failed: ${message}`]);
      mcpSetPageStatus(`${mcpServerTitle(server)}: ${message}`, 'err');
      renderMcpSettingsUI();
      throw ex;
    } finally {
      if (editor && mcpEditorTest) mcpEditorTest.disabled = false;
    }
  }
  async function testMcpServersFromSettings(){
    const servers = mcpCurrentServers();
    if (!servers.length) { mcpSetPageStatus('No MCP servers to test.'); return; }
    if (settingMcpServersTest) settingMcpServersTest.disabled = true;
    let ok = 0;
    try {
      for (const server of servers) {
        try { await testMcpServer(server); ok++; } catch(_) { /* card already shows the failure */ }
      }
      mcpSetPageStatus(`${ok}/${servers.length} MCP server${servers.length===1?'':'s'} connected successfully.`, ok===servers.length?'ok':'err');
    } finally {
      if (settingMcpServersTest) settingMcpServersTest.disabled = false;
    }
  }

  // ---------- Code workspace UI ----------
  let workspaceModal = null;
  let workspaceFiles = [];

  function workspaceStatus(message){
    const el = workspaceModal?.modal?.querySelector('.workspace-status');
    if (el) el.textContent = message || '';
  }

  function workspaceUrl(action, params = {}){
    const q = new URLSearchParams({action, ...params});
    return `api.php?${q.toString()}`;
  }

  function activeWorkspace(){
    const id = String(state.webtools.workspace_id || '');
    return (Array.isArray(state.workspaces) ? state.workspaces : []).find(w=>String(w.id || '') === id) || null;
  }

  function formatWorkspaceBytes(bytes){
    const n = Math.max(0, Number(bytes || 0));
    if (n < 1024) return `${n} B`;
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(n < 10 * 1024 ? 1 : 0)} KB`;
    return `${(n / (1024 * 1024)).toFixed(n < 10 * 1024 * 1024 ? 1 : 0)} MB`;
  }

  function ensureWorkspaceModal(){
    if (workspaceModal) return workspaceModal;
    const modal = document.createElement('div');
    modal.className = 'modal workspace-modal';
    modal.id = 'workspace-modal';
    modal.setAttribute('role','dialog');
    modal.setAttribute('aria-modal','true');
    modal.setAttribute('aria-hidden','true');
    modal.innerHTML = `
      <div class="modal-backdrop" data-workspace-close="1"></div>
      <div class="modal-panel workspace-modal-panel" role="document">
        <div class="modal-header">
          <div>
            <div class="modal-title">Code workspace</div>
            <div class="muted workspace-modal-sub">Manage projects. Access below is a user-controlled permission for this chat; the agent cannot change it.</div>
          </div>
          <button class="icon-btn workspace-close-icon" type="button" data-workspace-close="1" title="Close" aria-label="Close">${iconSvg('x')}</button>
        </div>
        <div class="workspace-modal-body">
          <div class="workspace-create-row">
            <input class="input workspace-name-input" type="text" maxlength="120" placeholder="New workspace name">
            <button class="btn btn-primary workspace-create-btn" type="button">${iconSvg('plus')}<span>Create</span></button>
            <button class="btn btn-ghost workspace-import-btn" type="button">${iconSvg('archive')}<span>Import ZIP</span></button>
            <input class="visually-hidden workspace-import-input" type="file" accept=".zip,application/zip">
          </div>
          <div class="workspace-access-row">
            <label for="workspace-access-select">Agent access for this chat</label>
            <select id="workspace-access-select" class="input workspace-access-select">
              <option value="read">Read only</option>
              <option value="write">Read and edit</option>
            </select>
            <span class="muted workspace-access-note">Read and edit is the default. You can lock the active or next workspace to read only at any time.</span>
          </div>
          <div class="workspace-download-row">
            <label for="workspace-download-select">Offer download after changes</label>
            <select id="workspace-download-select" class="input workspace-download-select">
              <option value="yes" selected>Yes</option>
              <option value="no">No</option>
            </select>
            <span class="muted workspace-download-note">When enabled, the agent should attach one changed file directly, or a ZIP when several files were changed.</span>
          </div>
          <div class="workspace-status muted" aria-live="polite"></div>
          <div class="workspace-list"></div>

          <section class="workspace-files-panel hidden" aria-label="Workspace files">
            <div class="workspace-files-head">
              <div>
                <div class="workspace-files-title">Files in <span class="workspace-active-name"></span></div>
                <div class="muted workspace-files-summary"></div>
              </div>
              <button class="btn btn-ghost workspace-export-btn" type="button">${iconSvg('download')}<span>Download ZIP</span></button>
            </div>
            <div class="workspace-upload-row">
              <input class="input workspace-upload-dir" type="text" placeholder="Destination folder (optional), e.g. assets/img">
              <button class="btn btn-ghost workspace-upload-btn" type="button">${iconSvg('upload')}<span>Add files or ZIP</span></button>
              <label class="workspace-replace-label" title="Create a snapshot before replacing an existing file">
                <input class="workspace-upload-replace" type="checkbox"> Replace existing
              </label>
              <input class="visually-hidden workspace-files-input" type="file" multiple>
            </div>
            <div class="workspace-file-list"></div>
          </section>
        </div>
        <div class="modal-footer workspace-modal-footer">
          <button class="btn btn-ghost workspace-detach-btn" type="button">${iconSvg('unlink')}<span>Turn off for chat</span></button>
          <button class="btn btn-ghost" type="button" data-workspace-close="1">${iconSvg('x')}<span>Close</span></button>
        </div>
      </div>`;
    document.body.appendChild(modal);

    const close = ()=>{
      modal.classList.remove('open');
      modal.setAttribute('aria-hidden','true');
    };
    modal.querySelectorAll('[data-workspace-close="1"]').forEach(el=>el.addEventListener('click', close));
    document.addEventListener('keydown', (e)=>{ if (e.key === 'Escape' && modal.classList.contains('open')) close(); });

    const accessEl = modal.querySelector('.workspace-access-select');
    accessEl?.addEventListener('change', ()=>{
      if (!state.webtools.code_workspace) return;
      state.webtools.workspace_access = accessEl.value === 'read' ? 'read' : 'write';
      persistCurrentWebTools();
      renderWebTools();
      renderWorkspaceList();
      workspaceStatus(state.webtools.workspace_access === 'read' ? 'Agent access changed to read only.' : 'Agent access changed to read and edit.');
    });

    const downloadEl = modal.querySelector('.workspace-download-select');
    downloadEl?.addEventListener('change', ()=>{
      state.webtools.workspace_offer_download = downloadEl.value !== 'no';
      persistCurrentWebTools();
      renderWorkspaceList();
      workspaceStatus(state.webtools.workspace_offer_download
        ? 'Downloads after workspace changes are enabled.'
        : 'Downloads after workspace changes are disabled.');
    });

    modal.querySelector('.workspace-create-btn')?.addEventListener('click', async ()=>{
      const input = modal.querySelector('.workspace-name-input');
      const name = String(input?.value || '').trim();
      workspaceStatus('Creating workspace…');
      try {
        const res = await api('workspace_create', {name: name || 'Untitled workspace'});
        if (input) input.value = '';
        await refreshWorkspaceList();
        if (res?.workspace) await selectWorkspaceForChat(res.workspace, accessEl?.value || 'write');
        workspaceStatus('Workspace created.');
      } catch(ex) {
        workspaceStatus(ex?.message || 'Could not create workspace.');
      }
    });

    const importInput = modal.querySelector('.workspace-import-input');
    modal.querySelector('.workspace-import-btn')?.addEventListener('click', ()=>importInput?.click());
    importInput?.addEventListener('change', async ()=>{
      const file = importInput.files?.[0];
      if (!file) return;
      workspaceStatus(`Importing ${file.name}…`);
      try {
        const fd = new FormData();
        fd.append('file', file);
        const res = await fetch('api.php?action=workspace_import', {method:'POST', body:fd});
        const data = await res.json().catch(()=>({error:`${res.status} ${res.statusText}`}));
        if (res.status === 401 && typeof window.llcShowLogin === 'function') window.llcShowLogin(data?.error || 'Unauthorized');
        if (!res.ok) throw new Error(data?.error || 'Workspace import failed');
        await refreshWorkspaceList();
        if (data?.workspace) await selectWorkspaceForChat(data.workspace, accessEl?.value || 'write');
        workspaceStatus(`Imported ${file.name}.`);
      } catch(ex) {
        workspaceStatus(ex?.message || 'Workspace import failed.');
      } finally {
        importInput.value = '';
      }
    });

    const filesInput = modal.querySelector('.workspace-files-input');
    modal.querySelector('.workspace-upload-btn')?.addEventListener('click', ()=>filesInput?.click());
    filesInput?.addEventListener('change', async ()=>{
      const selected = Array.from(filesInput.files || []);
      const id = String(state.webtools.workspace_id || '');
      if (!id || !selected.length) return;
      const targetDir = String(modal.querySelector('.workspace-upload-dir')?.value || '').trim();
      const replace = !!modal.querySelector('.workspace-upload-replace')?.checked;
      workspaceStatus(`Adding ${selected.length} selected item${selected.length === 1 ? '' : 's'}…`);
      try {
        const fd = new FormData();
        fd.append('id', id);
        fd.append('target_dir', targetDir);
        if (replace) fd.append('replace', '1');
        selected.forEach(file=>fd.append('files[]', file, file.name));
        const res = await fetch('api.php?action=workspace_file_upload', {method:'POST', body:fd});
        const data = await res.json().catch(()=>({error:`${res.status} ${res.statusText}`}));
        if (res.status === 401 && typeof window.llcShowLogin === 'function') window.llcShowLogin(data?.error || 'Unauthorized');
        if (!res.ok) throw new Error(data?.error || 'File or ZIP upload failed');
        await Promise.all([refreshWorkspaceFiles(), refreshWorkspaceList()]);
        const added = Number(data?.count || 0);
        const archives = Number(data?.archives || 0);
        workspaceStatus(`Added ${added} file${added === 1 ? '' : 's'}${archives ? ` from ${archives} ZIP archive${archives === 1 ? '' : 's'}` : ''}.`);
      } catch(ex) {
        workspaceStatus(ex?.message || 'File or ZIP upload failed.');
      } finally {
        filesInput.value = '';
      }
    });

    modal.querySelector('.workspace-export-btn')?.addEventListener('click', ()=>{
      const id = String(state.webtools.workspace_id || '');
      if (!id) return workspaceStatus('Select a workspace first.');
      const a = document.createElement('a');
      a.href = workspaceUrl('workspace_export', {id});
      a.rel = 'noopener';
      document.body.appendChild(a);
      a.click();
      a.remove();
    });

    modal.querySelector('.workspace-detach-btn')?.addEventListener('click', ()=>{
      state.webtools.code_workspace = false;
      state.webtools.workspace_id = '';
      state.webtools.workspace_name = '';
      workspaceFiles = [];
      persistCurrentWebTools();
      renderWebTools();
      renderWorkspaceList();
      renderWorkspaceFiles();
      workspaceStatus('Code Workspace turned off for this chat.');
    });

    workspaceModal = {modal, close, accessEl, downloadEl};
    return workspaceModal;
  }

  async function selectWorkspaceForChat(ws, access = null, strategy = null){
    if (!ws?.id) return;
    state.webtools.code_workspace = true;
    state.webtools.workspace_id = String(ws.id);
    state.webtools.workspace_name = String(ws.name || 'Workspace');
    state.webtools.workspace_access = (access || state.webtools.workspace_access) === 'read' ? 'read' : 'write';
    state.webtools.workspace_strategy = 'efficient';
    persistCurrentWebTools();
    renderWebTools();
    renderWorkspaceList();
    await refreshWorkspaceFiles();
  }

  function applyAgentWorkspaceUpdate(ws, chat){
    if (!ws || !chat) return;
    const id = String(ws.id || '');
    if (!id) return;
    const name = String(ws.name || 'Workspace');
    const access = String(ws.access || 'write') === 'read' ? 'read' : 'write';
    const strategy = 'efficient';

    chat.meta = chat.meta || {};
    chat.meta.webtools = (chat.meta.webtools && typeof chat.meta.webtools === 'object') ? chat.meta.webtools : {};
    chat.meta.webtools.code_workspace = true;
    chat.meta.webtools.workspace_id = id;
    chat.meta.webtools.workspace_name = name;
    chat.meta.webtools.workspace_access = access;
    chat.meta.webtools.workspace_strategy = strategy;

    if (state.currentChat?.id === chat.id) {
      state.webtools.code_workspace = true;
      state.webtools.workspace_id = id;
      state.webtools.workspace_name = name;
      state.webtools.workspace_access = access;
      state.webtools.workspace_strategy = strategy;
      workspaceFiles = [];
      renderWebTools();
      refreshWorkspaceList().then(()=>refreshWorkspaceFiles()).catch(()=>{});
    }
  }

  function renderWorkspaceList(){
    const ref = ensureWorkspaceModal();
    const list = ref.modal.querySelector('.workspace-list');
    const accessEl = ref.accessEl;
    const downloadEl = ref.downloadEl;
    const selectedId = String(state.webtools.workspace_id || '');
    const capabilityOn = !!state.webtools.code_workspace;
    const selected = capabilityOn && !!selectedId;
    if (accessEl) {
      accessEl.value = state.webtools.workspace_access === 'read' ? 'read' : 'write';
      accessEl.disabled = !capabilityOn;
    }
    if (downloadEl) {
      downloadEl.value = state.webtools.workspace_offer_download === false ? 'no' : 'yes';
      downloadEl.disabled = !capabilityOn;
    }
    const note = ref.modal.querySelector('.workspace-access-note');
    if (note) note.textContent = selected
      ? `Current mode: ${state.webtools.workspace_access === 'read' ? 'read only' : 'read and edit'}. Changes apply immediately to this chat.`
      : (capabilityOn
          ? `Applies when the agent selects a workspace: ${state.webtools.workspace_access === 'read' ? 'read only' : 'read and edit'}.`
          : 'Code Workspace is off.');
    const downloadNote = ref.modal.querySelector('.workspace-download-note');
    if (downloadNote) downloadNote.textContent = capabilityOn
      ? (state.webtools.workspace_offer_download === false
          ? 'The agent will only attach workspace downloads when you explicitly ask for them.'
          : 'After file changes, the agent should attach one changed file directly or a ZIP when several files were changed.')
      : 'This preference applies when Code Workspace is enabled for this chat.';
    if (!list) return;
    list.innerHTML = '';
    const items = Array.isArray(state.workspaces) ? state.workspaces : [];
    if (!items.length) {
      const empty = document.createElement('div');
      empty.className = 'workspace-empty muted';
      empty.textContent = 'No workspaces yet. Create an empty workspace or import a ZIP project.';
      list.appendChild(empty);
      return;
    }
    for (const ws of items) {
      const row = document.createElement('div');
      const isSelected = selected && selectedId === String(ws.id || '');
      row.className = 'workspace-row' + (isSelected ? ' selected' : '');

      const info = document.createElement('button');
      info.type = 'button';
      info.className = 'workspace-row-main';
      const name = document.createElement('span');
      name.className = 'workspace-row-name';
      name.textContent = String(ws.name || 'Workspace');
      const meta = document.createElement('span');
      meta.className = 'workspace-row-meta';
      const files = Number(ws.file_count || 0);
      const access = isSelected ? ` · ${state.webtools.workspace_access === 'read' ? 'read only' : 'read and edit'}` : '';
      meta.textContent = `${files} file${files === 1 ? '' : 's'}${isSelected ? ' · active' : ''}${access}`;
      info.append(name, meta);
      info.addEventListener('click', ()=>selectWorkspaceForChat(ws, accessEl?.value || 'write'));

      const rename = document.createElement('button');
      rename.type = 'button';
      rename.className = 'icon-btn sm workspace-row-action';
      rename.title = 'Rename workspace';
      rename.setAttribute('aria-label','Rename workspace');
      rename.innerHTML = iconSvg('pencil');
      rename.addEventListener('click', async (e)=>{
        e.stopPropagation();
        const next = prompt('Workspace name', String(ws.name || 'Workspace'));
        if (next == null || !String(next).trim() || String(next).trim() === String(ws.name || '')) return;
        workspaceStatus('Renaming workspace…');
        try {
          const res = await api('workspace_rename', {id:String(ws.id || ''), name:String(next).trim()});
          if (isSelected && res?.workspace) {
            state.webtools.workspace_name = String(res.workspace.name || next).trim();
            persistCurrentWebTools();
          }
          await refreshWorkspaceList();
          workspaceStatus('Workspace renamed.');
        } catch(ex) {
          workspaceStatus(ex?.message || 'Could not rename workspace.');
        }
      });

      const download = document.createElement('button');
      download.type = 'button';
      download.className = 'icon-btn sm workspace-row-action';
      download.title = 'Download workspace ZIP';
      download.setAttribute('aria-label','Download workspace ZIP');
      download.innerHTML = iconSvg('download');
      download.addEventListener('click', (e)=>{
        e.stopPropagation();
        const a = document.createElement('a');
        a.href = workspaceUrl('workspace_export', {id:String(ws.id || '')});
        a.rel = 'noopener';
        document.body.appendChild(a);
        a.click();
        a.remove();
      });

      const del = document.createElement('button');
      del.type = 'button';
      del.className = 'icon-btn sm danger workspace-row-delete';
      del.title = 'Delete workspace';
      del.setAttribute('aria-label','Delete workspace');
      del.innerHTML = iconSvg('trash');
      del.addEventListener('click', async (e)=>{
        e.stopPropagation();
        if (!confirm(`Delete workspace “${String(ws.name || 'Workspace')}” and all its files?`)) return;
        workspaceStatus('Deleting workspace…');
        try {
          await api('workspace_delete', {id:String(ws.id || '')});
          if (isSelected) {
            state.webtools.workspace_id = '';
            state.webtools.workspace_name = '';
            workspaceFiles = [];
            persistCurrentWebTools();
          }
          await refreshWorkspaceList();
          renderWebTools();
          renderWorkspaceFiles();
          workspaceStatus('Workspace deleted.');
        } catch(ex) {
          workspaceStatus(ex?.message || 'Could not delete workspace.');
        }
      });
      row.append(info, rename, download, del);
      list.appendChild(row);
    }
  }

  function renderWorkspaceFiles(){
    const ref = ensureWorkspaceModal();
    const panel = ref.modal.querySelector('.workspace-files-panel');
    const list = ref.modal.querySelector('.workspace-file-list');
    const ws = activeWorkspace();
    const active = !!state.webtools.code_workspace && !!ws;
    panel?.classList.toggle('hidden', !active);
    if (!active || !list) {
      if (list) list.innerHTML = '';
      return;
    }
    const name = ref.modal.querySelector('.workspace-active-name');
    if (name) name.textContent = String(ws.name || 'Workspace');
    const summary = ref.modal.querySelector('.workspace-files-summary');
    const fileItems = workspaceFiles.filter(item=>item.type === 'file');
    const dirItems = workspaceFiles.filter(item=>item.type === 'directory');
    if (summary) summary.textContent = `${fileItems.length} file${fileItems.length === 1 ? '' : 's'} · ${dirItems.length} folder${dirItems.length === 1 ? '' : 's'}`;
    list.innerHTML = '';
    if (!workspaceFiles.length) {
      const empty = document.createElement('div');
      empty.className = 'workspace-empty muted';
      empty.textContent = 'This workspace is empty. Add files or a ZIP archive above.';
      list.appendChild(empty);
      return;
    }
    for (const item of workspaceFiles) {
      const row = document.createElement('div');
      row.className = `workspace-file-row ${item.type === 'directory' ? 'directory' : 'file'}`;
      const icon = document.createElement('span');
      icon.className = 'workspace-file-icon';
      icon.textContent = item.type === 'directory' ? '▸' : '·';
      const path = document.createElement('span');
      path.className = 'workspace-file-path';
      path.textContent = String(item.path || '');
      row.append(icon, path);
      if (item.type === 'file') {
        const size = document.createElement('span');
        size.className = 'workspace-file-size';
        size.textContent = formatWorkspaceBytes(item.size);
        const download = document.createElement('a');
        download.className = 'icon-btn sm workspace-file-download';
        download.title = 'Download file';
        download.setAttribute('aria-label', `Download ${String(item.path || 'file')}`);
        download.innerHTML = iconSvg('download');
        download.href = workspaceUrl('workspace_file_download', {id:String(ws.id || ''), path:String(item.path || '')});

        const remove = document.createElement('button');
        remove.type = 'button';
        remove.className = 'icon-btn sm danger workspace-file-delete';
        remove.title = 'Delete file';
        remove.setAttribute('aria-label', `Delete ${String(item.path || 'file')}`);
        remove.innerHTML = iconSvg('trash');
        remove.addEventListener('click', async ()=>{
          const rel = String(item.path || '');
          if (!rel || !confirm(`Delete file “${rel}”? A snapshot will be kept.`)) return;
          workspaceStatus(`Deleting ${rel}…`);
          remove.disabled = true;
          try {
            await api('workspace_file_delete', {id:String(ws.id || ''), path:rel});
            await Promise.all([refreshWorkspaceFiles(), refreshWorkspaceList()]);
            workspaceStatus(`Deleted ${rel}.`);
          } catch(ex) {
            workspaceStatus(ex?.message || 'Could not delete file.');
            remove.disabled = false;
          }
        });
        row.append(size, download, remove);
      }
      list.appendChild(row);
    }
  }

  async function refreshWorkspaceFiles(){
    const id = String(state.webtools.workspace_id || '');
    if (!state.webtools.code_workspace || !id) {
      workspaceFiles = [];
      renderWorkspaceFiles();
      return;
    }
    try {
      const res = await fetch(workspaceUrl('workspace_files', {id}));
      const data = await res.json().catch(()=>({error:`${res.status} ${res.statusText}`}));
      if (res.status === 401 && typeof window.llcShowLogin === 'function') window.llcShowLogin(data?.error || 'Unauthorized');
      if (!res.ok) throw new Error(data?.error || 'Could not load workspace files');
      workspaceFiles = Array.isArray(data?.items) ? data.items : [];
      renderWorkspaceFiles();
      if (data?.truncated) workspaceStatus('File list is truncated after 5000 entries.');
    } catch(ex) {
      workspaceFiles = [];
      renderWorkspaceFiles();
      workspaceStatus(ex?.message || 'Could not load workspace files.');
    }
  }

  async function refreshWorkspaceList(){
    const res = await api('workspace_list');
    state.workspaces = Array.isArray(res?.workspaces) ? res.workspaces : [];
    const activeId = String(state.webtools.workspace_id || '');
    if (activeId) {
      const active = state.workspaces.find(w=>String(w.id || '') === activeId);
      if (active) {
        state.webtools.workspace_name = String(active.name || state.webtools.workspace_name || 'Workspace');
      } else if (state.webtools.code_workspace) {
        state.webtools.workspace_id = '';
        state.webtools.workspace_name = '';
        workspaceFiles = [];
        persistCurrentWebTools();
      }
    }
    renderWorkspaceList();
    renderWorkspaceFiles();
    renderWebTools();
  }

  async function openWorkspaceModal(){
    const ref = ensureWorkspaceModal();
    ref.modal.classList.add('open');
    ref.modal.setAttribute('aria-hidden','false');
    workspaceStatus('Loading workspaces…');
    try {
      await refreshWorkspaceList();
      await refreshWorkspaceFiles();
      workspaceStatus('');
    } catch(ex) {
      workspaceStatus(ex?.message || 'Could not load workspaces.');
    }
  }

  // ---------- Web tools UI ----------
  function renderWebTools(){
  if (!webToolsBtn || !webToolsMenu) return;

  const webOn = !!state.webtools?.web;
  const searchOn = !!state.webtools?.search;
  const ragOn = !!state.webtools?.rag;
  const imageOn = !!state.webtools?.image;
  const documentOn = !!state.webtools?.document;
  const workspaceOn = !!state.webtools?.code_workspace;
  const customSet = enabledCustomTools();
  const customOn = customSet.size > 0;
  const mcpSet = enabledMcpServers();
  const mcpOn = mcpSet.size > 0;

  const prov = String(state.ui.searchProvider || 'serper');
  const searchConfigured = isSearchConfigured();
  const imageConfigured = isImageConfigured();

  webToolsBtn.classList.toggle('active', webOn || searchOn || ragOn || imageOn || documentOn || workspaceOn || customOn || mcpOn);
  webToolsBtn.classList.toggle('document-active', documentOn);

  const webItem = webToolsMenu.querySelector('.webtools-item[data-action="web"]');
  if (webItem) webItem.classList.toggle('active', webOn);

  const searchItem = webToolsMenu.querySelector('.webtools-item[data-action="search"]');
  if (searchItem) {
    searchItem.classList.toggle('active', searchOn);

    const canUse = !!searchConfigured;
    searchItem.toggleAttribute('disabled', !canUse);
    searchItem.classList.toggle('disabled', !canUse);

    const sub = searchItem.querySelector('.wt-sub');
    if (sub) {
      const label = (prov === 'serper') ? 'Serper'
        : (prov === 'brave') ? 'Brave'
        : (prov === 'exa') ? 'Exa'
        : (prov === 'searchngx') ? 'SearXNG'
        : (prov === 'custom') ? 'Custom'
        : 'Search';
      sub.textContent = canUse ? `Search (${label})` : 'Configure in Settings → Search';
    }
  }

  const ragItem = webToolsMenu.querySelector('.webtools-item[data-action="rag-toggle-menu"]');
  if (ragItem) {
    const canUse = !!state.ui.ragAvailable;
    const chatMode = normalizeChatRagMode(state.webtools?.rag_mode);
    const effective = effectiveRagMode();
    const caps = currentRagCapabilities();
    const capsPending = state.ragCapabilityPending.has(ragCapabilityKey());
    const preciseAvailable = caps ? !!caps.precise : null;
    const ragPanelOpen = !!(webToolsRagList && !webToolsRagList.classList.contains('hidden'));
    ragItem.classList.toggle('active', ragOn);
    ragItem.toggleAttribute('disabled', !canUse);
    ragItem.classList.toggle('disabled', !canUse);
    ragItem.setAttribute('aria-expanded', ragPanelOpen ? 'true' : 'false');
    const sub = ragItem.querySelector('.wt-sub');
    if (sub) {
      const effectiveLabel = (preciseAvailable === false && effective === 'precise') ? 'Precise unavailable' : ragModeLabel(effective);
      sub.textContent = canUse
        ? (ragOn ? effectiveLabel : `Off · ${ragModeLabel(state.ui.ragDefaultMode)}`)
        : 'Configure in Settings → RAG';
    }
    if (webToolsRagList) {
      webToolsRagList.querySelectorAll('[data-action="rag-mode"]').forEach(btn=>{
        const mode = String(btn.dataset.mode || '');
        const active = mode === 'off' ? !ragOn : (ragOn && mode === effective);
        btn.classList.toggle('active', active);
        if (mode === 'precise') {
          // Do not flash Precise before the lazy status check has completed.
          // A failed/negative capability check keeps it absent; there is no
          // background polling.
          btn.classList.toggle('hidden', capsPending || preciseAvailable !== true);
          btn.disabled = preciseAvailable !== true;
        }
      });
    }
  }

  const imageItem = webToolsMenu.querySelector('.webtools-item[data-action="image"]');
  if (imageItem) {
    imageItem.classList.toggle('active', imageOn);

    const canUse = !!imageConfigured;
    imageItem.toggleAttribute('disabled', !canUse);
    imageItem.classList.toggle('disabled', !canUse);

    const sub = imageItem.querySelector('.wt-sub');
    if (sub) {
      const ip = String(state.ui.imageProvider || 'openai');
      const label = (ip === 'comfyui') ? 'ComfyUI'
        : (ip === 'openrouter') ? 'OpenRouter Image Models'
        : (ip === 'sdcpp') ? 'stable-diffusion.cpp'
        : 'OpenAI Image API';
      sub.textContent = canUse ? label : 'Configure in Settings → Image';
    }
  }
  const workspaceItem = webToolsMenu.querySelector('.webtools-item[data-action="code-workspace-toggle-menu"]');
  if (workspaceItem) {
    const workspacePanelOpen = !!(webToolsWorkspaceList && !webToolsWorkspaceList.classList.contains('hidden'));
    workspaceItem.classList.toggle('active', workspaceOn);
    workspaceItem.setAttribute('aria-expanded', workspacePanelOpen ? 'true' : 'false');
    const sub = workspaceItem.querySelector('.wt-sub');
    if (sub) {
      const name = String(state.webtools?.workspace_name || '').trim();
      const access = String(state.webtools?.workspace_access || 'write') === 'read' ? 'read only' : 'edit';
      sub.textContent = workspaceOn
        ? (String(state.webtools?.workspace_id || '') ? `On · ${name || 'Workspace'} · ${access}` : `On · new or explicitly selected workspace · ${access}`)
        : 'Off';
    }
  }
  if (webToolsWorkspaceList) {
    const toggle = webToolsWorkspaceList.querySelector('[data-action="workspace-toggle"]');
    if (toggle) {
      toggle.classList.toggle('active', workspaceOn);
      const title = toggle.querySelector('.wt-title');
      const sub = toggle.querySelector('.wt-sub');
      if (title) title.textContent = workspaceOn ? 'On' : 'Off';
      if (sub) sub.textContent = workspaceOn ? 'Workspace tools enabled for this chat' : 'Workspace tools disabled for this chat';
    }
  }
  const documentItem = webToolsMenu.querySelector('.webtools-item[data-action="document"]');
  if (documentItem) {
    documentItem.classList.toggle('active', documentOn);
    const sub = documentItem.querySelector('.wt-sub');
    const doc = activeDocument();
    if (sub) sub.textContent = documentOn
      ? (doc ? `Editing ${doc.title || 'document'} · ${documentList().length} doc${documentList().length === 1 ? '' : 's'}` : 'Document mode is active')
      : 'Create/edit multiple documents';
  }
  const customToggle = webToolsMenu.querySelector('.webtools-item[data-action="custom-tools-toggle"]');
  const customTools = Array.isArray(state.ui.customTools) ? state.ui.customTools : [];
  const customPanelOpen = !!(webToolsCustomList && !webToolsCustomList.classList.contains('hidden'));
  if (customToggle) {
    customToggle.classList.toggle('active', customOn);
    customToggle.setAttribute('aria-expanded', customPanelOpen ? 'true' : 'false');
    const sub = customToggle.querySelector('.wt-sub');
    if (sub) sub.textContent = customTools.length ? `${customSet.size}/${customTools.length} active` : 'Configure in Settings → Custom Tools';
  }
  if (webToolsCustomList) {
    webToolsCustomList.innerHTML = '';
    if (!customTools.length) {
      const empty = document.createElement('div');
      empty.className = 'webtools-custom-empty';
      empty.textContent = 'No custom tools yet.';
      webToolsCustomList.appendChild(empty);
    } else {
      for (const t of customTools) {
        const key = customToolKey(t);
        const name = customToolName(t);
        if (!key || !name) continue;
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'webtools-custom-tool' + (customSet.has(key) || customSet.has(name) ? ' active' : '');
        btn.dataset.action = 'custom-tool';
        btn.dataset.tool = key;
        btn.dataset.toolName = name;
        const desc = String(t.description || '').trim();
        btn.innerHTML = `<span class="wt-check" aria-hidden="true"></span><div class="wt-text"><div class="wt-title">${esc(customToolTitle(t))}</div><div class="wt-sub">${esc(desc ? desc.slice(0, 80) : name)}</div></div>`;
        webToolsCustomList.appendChild(btn);
      }
    }
  }
  const mcpToggle = webToolsMenu.querySelector('.webtools-item[data-action="mcp-servers-toggle"]');
  const mcpServers = Array.isArray(state.ui.mcpServers) ? state.ui.mcpServers : [];
  const mcpPanelOpen = !!(webToolsMcpList && !webToolsMcpList.classList.contains('hidden'));
  if (mcpToggle) {
    mcpToggle.classList.toggle('active', mcpOn);
    mcpToggle.setAttribute('aria-expanded', mcpPanelOpen ? 'true' : 'false');
    const sub = mcpToggle.querySelector('.wt-sub');
    if (sub) sub.textContent = mcpServers.length ? `${mcpSet.size}/${mcpServers.length} active` : 'Configure in Settings → MCP';
  }
  if (webToolsMcpList) {
    webToolsMcpList.innerHTML = '';
    if (!mcpServers.length) {
      const empty=document.createElement('div'); empty.className='webtools-custom-empty'; empty.textContent='No MCP servers yet.'; webToolsMcpList.appendChild(empty);
    } else {
      for (const server of mcpServers) {
        const key=mcpServerKey(server); if (!key) continue;
        const btn=document.createElement('button'); btn.type='button'; btn.className='webtools-custom-tool'+(mcpSet.has(key)?' active':'');
        btn.dataset.action='mcp-server'; btn.dataset.server=key;
        const desc=String(server.description || server.url || '').trim();
        btn.innerHTML=`<span class="wt-check" aria-hidden="true"></span><div class="wt-text"><div class="wt-title">${esc(mcpServerTitle(server))}</div><div class="wt-sub">${esc(desc ? desc.slice(0,90) : key)}</div></div>`;
        webToolsMcpList.appendChild(btn);
      }
    }
  }
  renderDocumentUI();


  webToolsBtn.setAttribute('aria-expanded', webToolsMenu.classList.contains('show')?'true':'false');
}


  function persistCurrentWebTools(){
    if (!state.currentChat) return;
    state.currentChat.meta = state.currentChat.meta || {};
    state.currentChat.meta.webtools = {
      web: !!state.webtools.web,
      search: !!state.webtools.search,
      rag: !!state.webtools.rag,
      rag_mode: normalizeChatRagMode(state.webtools.rag_mode),
      image: !!state.webtools.image,
      document: !!state.webtools.document,
      code_workspace: !!state.webtools.code_workspace,
      workspace_id: String(state.webtools.workspace_id || ''),
      workspace_name: String(state.webtools.workspace_name || ''),
      workspace_access: String(state.webtools.workspace_access || 'write'),
      workspace_strategy: 'efficient',
      workspace_offer_download: state.webtools.workspace_offer_download !== false,
      custom_tools: Array.isArray(state.webtools.custom_tools) ? state.webtools.custom_tools : [],
      mcp_servers: Array.isArray(state.webtools.mcp_servers) ? state.webtools.mcp_servers : []
    };
    saveChat(state.currentChat).catch(()=>{});
  }

  function closeCustomToolsFlyout(){
    webToolsCustomList?.classList.add('hidden');
    webToolsMcpList?.classList.add('hidden');
    webToolsRagList?.classList.add('hidden');
    webToolsWorkspaceList?.classList.add('hidden');
    const ragToggle = webToolsMenu?.querySelector('.webtools-item[data-action="rag-toggle-menu"]');
    const workspaceToggle = webToolsMenu?.querySelector('.webtools-item[data-action="code-workspace-toggle-menu"]');
    const customToggle = webToolsMenu?.querySelector('.webtools-item[data-action="custom-tools-toggle"]');
    const mcpToggle = webToolsMenu?.querySelector('.webtools-item[data-action="mcp-servers-toggle"]');
    ragToggle?.setAttribute('aria-expanded', 'false');
    workspaceToggle?.setAttribute('aria-expanded', 'false');
    customToggle?.setAttribute('aria-expanded', 'false');
    mcpToggle?.setAttribute('aria-expanded', 'false');
  }

  function toggleWebToolsMenu(){
    if (!webToolsMenu) return;
    const willOpen = !webToolsMenu.classList.contains('show');
    webToolsMenu.classList.toggle('show', willOpen);
    if (!willOpen) closeCustomToolsFlyout();
    if (webToolsBtn) webToolsBtn.setAttribute('aria-expanded', willOpen ? 'true':'false');
    // close other popovers for sanity
    attachMenu?.classList.remove('show');
  }

  webToolsBtn?.addEventListener('click', (e)=>{ e.preventDefault(); e.stopPropagation(); toggleWebToolsMenu(); renderWebTools(); });
  webToolsMenu?.addEventListener('click', async (e)=>{
  e.preventDefault();
  e.stopPropagation();
  const item = e.target.closest('.webtools-item, .webtools-custom-tool');
  if (!item) return;
  const action = item.dataset.action;

  if (action === 'rag-toggle-menu') {
    if (item.hasAttribute('disabled')) return;
    webToolsCustomList?.classList.add('hidden');
    webToolsMcpList?.classList.add('hidden');
    webToolsWorkspaceList?.classList.add('hidden');
    const opening = !!(webToolsRagList && webToolsRagList.classList.contains('hidden'));
    if (webToolsRagList) webToolsRagList.classList.toggle('hidden');
    renderWebTools();
    if (opening) await ensureRagCapabilities(state.currentChat);
    renderWebTools();
    return;
  }
  if (action === 'rag-mode') {
    const mode = String(item.dataset.mode || '').toLowerCase();
    if (mode === 'precise' && currentRagCapabilities()?.precise !== true) return;
    if (mode === 'off') {
      state.webtools.rag = false;
    } else if (['dense','hybrid','precise'].includes(mode)) {
      state.webtools.rag = true;
      // Selecting the current personal default silently removes the chat
      // override, so future Settings changes can still flow through.
      state.webtools.rag_mode = mode === normalizeRagMode(state.ui.ragDefaultMode, 'hybrid') ? 'default' : mode;
    } else {
      return;
    }
    webToolsRagList?.classList.add('hidden');
    persistCurrentWebTools();
    renderWebTools();
    return;
  }

  if (action === 'custom-tools-toggle') {
    webToolsRagList?.classList.add('hidden');
    webToolsMcpList?.classList.add('hidden');
    webToolsWorkspaceList?.classList.add('hidden');
    if (webToolsCustomList) webToolsCustomList.classList.toggle('hidden');
    renderWebTools(); return;
  }
  if (action === 'mcp-servers-toggle') {
    webToolsRagList?.classList.add('hidden');
    webToolsCustomList?.classList.add('hidden');
    webToolsWorkspaceList?.classList.add('hidden');
    if (webToolsMcpList) webToolsMcpList.classList.toggle('hidden');
    renderWebTools(); return;
  }
  if (action === 'code-workspace-toggle-menu') {
    webToolsRagList?.classList.add('hidden');
    webToolsCustomList?.classList.add('hidden');
    webToolsMcpList?.classList.add('hidden');
    if (webToolsWorkspaceList) webToolsWorkspaceList.classList.toggle('hidden');
    renderWebTools();
    return;
  }
  if (action === 'workspace-toggle') {
    const next = !state.webtools.code_workspace;
    state.webtools.code_workspace = next;
    // Enabling the capability never silently reuses an old project. A workspace
    // becomes active only through an explicit manager selection or an agent action.
    state.webtools.workspace_id = '';
    state.webtools.workspace_name = '';
    workspaceFiles = [];
    persistCurrentWebTools();
    renderWebTools();
    renderWorkspaceList();
    renderWorkspaceFiles();
    return;
  }
  if (action === 'workspace-manager') {
    webToolsMenu.classList.remove('show');
    webToolsBtn?.setAttribute('aria-expanded','false');
    closeCustomToolsFlyout();
    openWorkspaceModal();
    return;
  }
  if (action === 'mcp-server') {
    const key=String(item.dataset.server || '').trim(); const set=enabledMcpServers();
    if (set.has(key)) set.delete(key); else if (key) set.add(key); setEnabledMcpServers(set);
  } else if (action === 'custom-tool') {
    const key = String(item.dataset.tool || item.dataset.toolName || '').trim();
    const name = String(item.dataset.toolName || key).trim();
    const set = enabledCustomTools();
    if (set.has(key) || set.has(name)) { set.delete(key); set.delete(name); }
    else set.add(name || key);
    setEnabledCustomTools(set);
  } else if (action === 'web') {
    state.webtools.web = !state.webtools.web;
  } else if (action === 'search') {
    if (item.hasAttribute('disabled')) return;
    state.webtools.search = !state.webtools.search;
  } else if (action === 'image') {
    if (item.hasAttribute('disabled')) return;
    state.webtools.image = !state.webtools.image;
  } else if (action === 'document') {
    state.webtools.document = !state.webtools.document;
  } else {
    return;
  }

  // Persist per-chat override, same behavior as Web/Search/Image/Document.
  persistCurrentWebTools();

  renderWebTools();
  // Keep the menu open after every toggle. It closes only when the globe button is clicked.
});



  settingCustomToolsAutoEnable?.addEventListener('change', async ()=>{
    state.ui.customToolsAutoEnable = !!settingCustomToolsAutoEnable.checked;
    try { await api('settings_save', { custom_tools_auto_enable: state.ui.customToolsAutoEnable ? 1 : 0 }); } catch(_){ /* ignore */ }

    // If the current chat has no explicit webtools override, apply the new default immediately.
    const hasOverride = !!(state.currentChat?.meta && state.currentChat.meta.webtools);
    if (!hasOverride) {
      state.webtools.custom_tools = defaultCustomToolNames();
      renderWebTools();
    }
  });

  settingCustomToolsJson?.addEventListener('change', saveCustomToolsFromSettings);
  settingCustomToolsFormat?.addEventListener('click', ()=>{
    if (!settingCustomToolsJson) return;
    try { settingCustomToolsJson.value = JSON.stringify(JSON.parse(String(settingCustomToolsJson.value || '[]')), null, 2); customToolSetPageStatus('Raw configuration formatted.'); }
    catch(ex){ customToolSetPageStatus('Invalid JSON: ' + (ex?.message || ex),'err'); }
  });
  customToolAddBtn?.addEventListener('click',()=>openCustomToolEditor(-1));
  customToolEditorClose?.addEventListener('click',closeCustomToolEditor);
  customToolEditorCancel?.addEventListener('click',closeCustomToolEditor);
  customToolEditorModal?.querySelector('[data-custom-tool-close]')?.addEventListener('click',closeCustomToolEditor);
  customToolHeaderAdd?.addEventListener('click',()=>customToolAddHeaderRow());
  customToolHeaderList?.addEventListener('click',(event)=>{
    const button=event.target.closest('.custom-tool-header-remove');
    if (!button) return;
    button.closest('.custom-tool-header-row')?.remove();
    customToolRefreshHeaderEmpty();
  });
  customToolParameterAdd?.addEventListener('click',()=>customToolAddParameterRow());
  customToolParameterList?.addEventListener('click',(event)=>{
    const button=event.target.closest('.custom-tool-param-remove');
    if (!button) return;
    button.closest('.custom-tool-parameter-row')?.remove();
    customToolRefreshParameterEmpty();
  });
  customToolEditMethod?.addEventListener('change',customToolSyncBodyUI);
  customToolEditBodyMode?.addEventListener('change',customToolSyncBodyUI);
  customToolEditId?.addEventListener('input',()=>{ customToolEditorIdWasEdited=true; });
  customToolEditName?.addEventListener('input',()=>{
    if (customToolEditorIdWasEdited || !customToolEditId) return;
    customToolEditId.value=customToolFunctionName(customToolEditName.value);
  });
  customToolEditorApply?.addEventListener('click',async()=>{
    if (customToolEditorApply) customToolEditorApply.disabled=true;
    try {
      const tool=collectCustomToolEditorTool();
      const tools=customToolsCurrent();
      const index=Number(customToolEditIndex?.value || -1);
      const duplicateName=tools.findIndex((item,i)=>item.name===tool.name && i!==index);
      if (duplicateName>=0) throw new Error(`Another custom tool already uses the function name “${tool.name}”.`);
      const duplicateId=tools.findIndex((item,i)=>customToolKey(item)===tool.id && i!==index);
      if (duplicateId>=0) throw new Error(`Another custom tool already uses the ID “${tool.id}”.`);
      if (index>=0 && index<tools.length) tools[index]=tool; else tools.push(tool);
      await persistCustomTools(tools,`${tool.title} updated.`);
      closeCustomToolEditor();
    } catch(ex) {
      customToolSetEditorResult('err',String(ex?.message || ex));
    } finally {
      if (customToolEditorApply) customToolEditorApply.disabled=false;
    }
  });
  customToolsList?.addEventListener('click',async(event)=>{
    const button=event.target.closest('[data-custom-tool-cmd]');
    if (!button) return;
    const index=Number(button.dataset.index);
    const tools=customToolsCurrent();
    const tool=tools[index];
    if (!tool) return;
    const command=String(button.dataset.customToolCmd || '');
    if (command==='edit') { openCustomToolEditor(index); return; }
    if (command==='delete') {
      if (!confirm(`Delete custom tool “${customToolTitle(tool)}”?`)) return;
      tools.splice(index,1);
      try { await persistCustomTools(tools,`${customToolTitle(tool)} deleted.`); }
      catch(ex){ customToolSetPageStatus(ex?.message || 'Could not delete custom tool.','err'); }
    }
  });
  settingMcpServersAutoEnable?.addEventListener('change', async ()=>{
    state.ui.mcpServersAutoEnable=!!settingMcpServersAutoEnable.checked;
    try { await api('settings_save',{mcp_servers_auto_enable:state.ui.mcpServersAutoEnable?1:0}); }
    catch(ex){ mcpSetPageStatus(ex?.message || 'Could not save MCP default.', 'err'); return; }
    const hasOverride=!!(state.currentChat?.meta && state.currentChat.meta.webtools);
    if (!hasOverride) { state.webtools.mcp_servers=defaultMcpServerIds(); renderWebTools(); }
    mcpSetPageStatus(state.ui.mcpServersAutoEnable ? 'Configured MCP servers will be active in new chats.' : 'New chats start without MCP servers.', 'ok');
  });
  settingMcpContextMode?.addEventListener('change',()=>{
    const externalize = String(settingMcpContextMode.value || 'full') === 'externalize';
    mcpContextLimits?.classList.toggle('disabled', !externalize);
    saveMcpContextSettings();
  });
  settingMcpExternalizeAbove?.addEventListener('change', saveMcpContextSettings);
  settingMcpPreviewMax?.addEventListener('change', saveMcpContextSettings);
  settingMcpFullPassMax?.addEventListener('change', saveMcpContextSettings);
  settingMcpServersJson?.addEventListener('change', saveMcpServersFromSettings);
  settingMcpServersTest?.addEventListener('click',testMcpServersFromSettings);
  settingMcpServersFormat?.addEventListener('click',()=>{
    if (!settingMcpServersJson) return;
    try { settingMcpServersJson.value=JSON.stringify(JSON.parse(String(settingMcpServersJson.value || '[]')),null,2); mcpSetPageStatus('Raw JSON formatted.'); }
    catch(ex){ mcpSetPageStatus('Invalid JSON: '+(ex?.message || ex), 'err'); }
  });

  mcpAddBtn?.addEventListener('click',()=>openMcpEditor(-1));
  mcpEditorClose?.addEventListener('click',closeMcpEditor);
  mcpEditorCancel?.addEventListener('click',closeMcpEditor);
  mcpEditorModal?.querySelector('[data-mcp-close]')?.addEventListener('click',closeMcpEditor);
  mcpEditAuthEnabled?.addEventListener('change',()=>mcpSetAuthEnabled(!!mcpEditAuthEnabled.checked));
  mcpHeaderAdd?.addEventListener('click',()=>mcpAddHeaderRow());
  mcpHeaderList?.addEventListener('click',(event)=>{
    const button=event.target.closest('.mcp-header-remove');
    if (!button) return;
    button.closest('.mcp-header-row')?.remove();
    mcpRefreshHeaderEmpty();
  });
  mcpTokenReveal?.addEventListener('click',()=>{
    if (!mcpEditToken) return;
    const reveal=mcpEditToken.type==='password';
    mcpEditToken.type=reveal?'text':'password';
    mcpEditToken.classList.toggle('is-revealed', reveal);
    mcpTokenReveal.textContent=reveal?'Hide':'Show';
  });
  mcpEditId?.addEventListener('input',()=>{ mcpEditorIdWasEdited=true; });
  mcpEditName?.addEventListener('input',()=>{
    if (mcpEditorIdWasEdited || !mcpEditId) return;
    mcpEditId.value=mcpServerKey({id:mcpEditName.value});
  });
  mcpEditorTest?.addEventListener('click',async()=>{
    try { await testMcpServer(collectMcpEditorServer(),{editor:true}); }
    catch(_) { /* rendered in editor */ }
  });
  mcpEditorSave?.addEventListener('click',async()=>{
    if (mcpEditorSave) mcpEditorSave.disabled=true;
    try {
      const server=collectMcpEditorServer();
      const servers=mcpCurrentServers();
      const index=Number(mcpEditIndex?.value || -1);
      const duplicate=servers.findIndex((item,i)=>mcpServerKey(item)===server.id && i!==index);
      if (duplicate>=0) throw new Error(`Another MCP server already uses the ID “${server.id}”.`);
      if (index>=0 && index<servers.length) servers[index]=server;
      else servers.push(server);
      await persistMcpServers(servers, `${server.name} saved.`);
      closeMcpEditor();
    } catch(ex) {
      mcpSetEditorResult('err',[String(ex?.message || ex)]);
    } finally {
      if (mcpEditorSave) mcpEditorSave.disabled=false;
    }
  });

  mcpList?.addEventListener('click',async(event)=>{
    const button=event.target.closest('[data-mcp-cmd]');
    if (!button) return;
    const index=Number(button.dataset.index);
    const servers=mcpCurrentServers();
    const server=servers[index];
    if (!server) return;
    const command=String(button.dataset.mcpCmd || '');
    if (command==='edit') { openMcpEditor(index); return; }
    if (command==='test') {
      button.disabled=true;
      try { await testMcpServer(server); } catch(_) { /* card shows error */ }
      finally { button.disabled=false; }
      return;
    }
    if (command==='delete') {
      if (!confirm(`Delete MCP server “${mcpServerTitle(server)}”?`)) return;
      servers.splice(index,1);
      try { await persistMcpServers(servers, `${mcpServerTitle(server)} deleted.`); }
      catch(ex){ mcpSetPageStatus(ex?.message || 'Could not delete MCP server.', 'err'); }
    }
  });
  document.addEventListener('keydown',(event)=>{
    if (event.key==='Escape' && customToolEditorModal && !customToolEditorModal.classList.contains('hidden')) { closeCustomToolEditor(); return; }
    if (event.key==='Escape' && mcpEditorModal && !mcpEditorModal.classList.contains('hidden')) closeMcpEditor();
  });

  // initial state
  renderWebTools();

  // ---------- URL/Web reader (readability.php) ----------
  const MAX_WEB_PAGES_PER_SEND = 3;
  const webFetchLimit = ()=>{
    // 0 = unlimited
    return normalizeWebLimit(state.ui.webFetchMaxChars ?? 50000, 50000);
  };
  const URL_RE = /https?:\/\/[\w\-._~:/?#\[\]@!$&'()*+,;=%]+/ig;

  function normalizeUrlCandidate(u){
    let s = String(u||'').trim();
    // strip typical trailing punctuation from chat text
    s = s.replace(/[)\],.;!?]+$/g, '');
    return s;
  }

  function extractUrlsFromText(t){
    const s = String(t||'');
    const m = s.match(URL_RE) || [];
    const out = [];
    for (const raw of m) {
      const u = normalizeUrlCandidate(raw);
      if (!u) continue;
      if (!out.includes(u)) out.push(u);
    }
    return out;
  }

  async function fetchReadability(url){
    const u = normalizeUrlCandidate(url);
    if (!u) throw new Error('Empty URL');
    const lim = webFetchLimit();
    const qs = new URLSearchParams({ url: u, max_chars: String(lim) });
    const res = await fetch(`readability.php?${qs.toString()}`, {
      method:'GET',
      headers: { 'Accept': 'application/json' }
    });
    const ct = res.headers.get('content-type') || '';
    if (!res.ok){
      const t = ct.includes('application/json') ? (await res.json()).error : await res.text();
      throw new Error(String(t||'Failed to fetch URL'));
    }
    if (ct.includes('application/json')) return res.json();
    return { ok:true, url:u, content_text: await res.text() };
  }

  function makeWebTextAttachment(url, r){
    const title = (r && typeof r.title === 'string') ? r.title.trim() : '';
    const author = (r && typeof r.author === 'string') ? r.author.trim() : '';
    const text = (r && typeof r.content_text === 'string') ? r.content_text : '';
    const truncated = !!(r && r.truncated);

    const head = [];
    if (title) head.push(`Title: ${title}`);
    if (author) head.push(`By: ${author}`);
    head.push(`URL: ${url}`);
    head.push('');

    const body = (text || '').trim();
    const full = head.join('\n') + body;
    const previewName = title ? `Web: ${title}` : `Web: ${url}`;
    const lim = webFetchLimit();
    const shown = (lim > 0) ? Math.min(full.length, lim) : full.length;
    const meta = `Web · ${shown} chars${truncated ? ' · truncated' : ''}`;

    return {
      id: 'att_' + Math.random().toString(36).slice(2,9),
      type: 'text',
      name: previewName.slice(0, 140),
      meta,
      url,
      mime: 'text/plain',
      text: (lim > 0 && full.length > lim) ? (full.slice(0, lim) + '\n\n[...truncated client-side...]') : full,
      truncated: (lim > 0 && full.length > lim) || truncated,
      not_sent: false
    };
  }

  async function addWebExtractionToState(url){
    state.webFetchBusy = true;
    webToolsBtn?.classList.add('loading');
    syncSend();
    try{
      const r = await fetchReadability(url);
      if (!r || r.ok === false) throw new Error(r?.error || 'Readability failed');
      const att = makeWebTextAttachment(normalizeUrlCandidate(url), r);
      state.attachments.push(att);
      renderAttachments();
      syncSend();
      return att;
    } finally {
      state.webFetchBusy = false;
      webToolsBtn?.classList.remove('loading');
      renderWebTools();
      syncSend();
    }
  }

  async function buildSendAttachments(text, atts, opts=null){
    const srcAtts = Array.isArray(atts) ? atts : [];
    const prefer = !!state.ui.webPreferAttachments;
    const forceUrlAttachments = !!(opts && opts.forceUrlAttachments);
    // If Web is off, pass through. If we don't prefer persisting sources, only convert explicit URL-attachments when forced.
    if (!state.webtools?.web) return srcAtts;
    if (!prefer && !forceUrlAttachments) return srcAtts;

    const out = [];
    const seen = new Set();
    let added = 0;

    // First: turn URL attachments into extracted text
    for (const a of srcAtts) {
      if (added >= MAX_WEB_PAGES_PER_SEND) { out.push(a); continue; }
      if (a && a.type === 'url' && a.url) {
        const u = normalizeUrlCandidate(a.url);
        if (!u) { out.push(a); continue; }
        if (seen.has(u)) continue;
        seen.add(u);
        try {
          const r = await fetchReadability(u);
          if (r && r.ok !== false) {
            out.push(makeWebTextAttachment(u, r));
            added++;
            continue;
          }
        } catch(_){ /* fallback below */ }
        out.push(a);
      } else {
        out.push(a);
        // mark already referenced sources to avoid double fetching
        if (a && typeof a.url === 'string' && a.url.startsWith('http')) seen.add(normalizeUrlCandidate(a.url));
      }
    }

    // Second: URLs inside the message text (only when preferAttachments is enabled)
    if (prefer) {
      for (const u0 of extractUrlsFromText(text)) {
        if (added >= MAX_WEB_PAGES_PER_SEND) break;
        const u = normalizeUrlCandidate(u0);
        if (!u || seen.has(u)) continue;
        seen.add(u);
        try {
          const r = await fetchReadability(u);
          if (r && r.ok !== false) {
            out.push(makeWebTextAttachment(u, r));
            added++;
          }
        } catch(_){ /* ignore */ }
      }
    }

    return out;
  }

  attachMenu?.addEventListener('click', async (e)=>{
    const item = e.target.closest('.attach-item');
    if (!item) return;
    const action = item.dataset.action;
    if (action==='files') fileInput.click();
    if (action==='documents') await openDocumentLibrary();
    if (action==='url'){
      const u = prompt('Add URL:');
      if (u && u.trim()) {
        const url = u.trim();
        // "Add link" is explicit intent to persist a source: always try to extract when Web is enabled,
        // independent of the "prefer attachments" toggle (which only controls automatic URL harvesting).
        if (state.webtools?.web) {
          try {
            await addWebExtractionToState(url);
          } catch (err) {
            alert('Web lesen fehlgeschlagen: ' + (err?.message || String(err)));
            state.attachments.push({id:'att_'+Math.random().toString(36).slice(2,9), type:'url', name:url, meta:'Link', url});
          }
        } else {
          state.attachments.push({id:'att_'+Math.random().toString(36).slice(2,9), type:'url', name:url, meta:'Link', url});
        }
      }
    }
    if (action==='note'){
      const t = prompt('Freitext:');
      if(t && t.trim()) state.attachments.push({id:'att_'+Math.random().toString(36).slice(2,9), type:'note', name:t.trim().slice(0,80), meta:`Text · ${t.trim().length} chars`, text:t.trim()});
    }
    attachMenu.classList.remove('show');
    renderAttachments(); syncSend();
  });

  async function uploadFile(file, options={}){
    const rag = !!options?.rag;
    const onUploadProgress = (typeof options?.onUploadProgress === 'function') ? options.onUploadProgress : null;

    // Fetch has no portable upload progress events. Use XHR only when the caller
    // actually needs byte-level progress (RAG indexing UI); keep the original
    // fetch path for all ordinary uploads.
    if (!onUploadProgress && !rag) {
      const fd = new FormData();
      fd.append('file', file, file.name);
      const res = await fetch('api.php?action=file_upload', {method:'POST', body: fd});
      const ct = res.headers.get('content-type')||'';
      if(!res.ok){
        const t = ct.includes('application/json') ? (await res.json()).error : await res.text();
        throw new Error(t);
      }
      return res.json();
    }

    return new Promise((resolve, reject)=>{
      const xhr = new XMLHttpRequest();
      xhr.open('POST', 'api.php?action=file_upload', true);
      xhr.responseType = 'text';
      xhr.upload.onprogress = (ev)=>{
        if (!onUploadProgress || !ev.lengthComputable) return;
        const loaded = Math.max(0, Number(ev.loaded)||0);
        const total = Math.max(0, Number(ev.total)||0);
        const percent = total > 0 ? Math.max(0, Math.min(100, (loaded / total) * 100)) : null;
        onUploadProgress({loaded,total,percent});
      };
      xhr.onerror = ()=>reject(new Error('Upload failed'));
      xhr.onabort = ()=>reject(new Error('Upload aborted'));
      xhr.onload = ()=>{
        let data = null;
        try { data = JSON.parse(String(xhr.responseText || '')); } catch(_){ data = null; }
        if (xhr.status < 200 || xhr.status >= 300) {
          const msg = data?.error || String(xhr.responseText || `${xhr.status} ${xhr.statusText}`);
          reject(new Error(msg));
          return;
        }
        if (!data || typeof data !== 'object') {
          reject(new Error('Upload returned invalid JSON'));
          return;
        }
        resolve(data);
      };
      const fd = new FormData();
      fd.append('file', file, file.name);
      if (rag) fd.append('rag', '1');
      xhr.send(fd);
    });
  }

  const sleep = (ms)=>new Promise(resolve=>setTimeout(resolve, Math.max(0, Number(ms)||0)));

  function ragPhaseLabel(stateName){
    const s = String(stateName || '').toLowerCase();
    if (s === 'queued') return 'Queued';
    if (s === 'chunking') return 'Chunking';
    if (s === 'embedding') return 'Embedding';
    if (s === 'storing') return 'Storing index';
    if (s === 'ready') return 'Ready';
    if (s === 'failed') return 'Failed';
    return s || 'Indexing';
  }

  async function waitForRagJob(jobId, attachment){
    const started = Date.now();
    const maxMs = 60 * 60 * 1000;
    let lastError = null;
    while ((Date.now() - started) < maxMs) {
      let job;
      try {
        job = await api('rag_job', {job_id:String(jobId || '')});
        lastError = null;
      } catch (err) {
        lastError = err;
        await sleep(1200);
        continue;
      }

      const stateName = String(job?.state || 'queued');
      const done = Math.max(0, Number(job?.done)||0);
      const total = Math.max(0, Number(job?.total)||0);
      const chunks = Math.max(0, Number(job?.chunks)||0);
      const pctRaw = Number(job?.percent);
      const pct = Number.isFinite(pctRaw) ? Math.max(0, Math.min(100, pctRaw)) : (total > 0 ? (done / total) * 100 : null);
      const phase = ragPhaseLabel(stateName);

      if (attachment) {
        attachment.rag_state = stateName;
        attachment.rag_done = done;
        attachment.rag_total = total;
        attachment.rag_chunks = chunks || attachment.rag_chunks || 0;
        attachment.meta = stateName === 'ready'
          ? `RAG · ${attachment.rag_chunks || total || 0} chunks`
          : `RAG · ${phase}${total > 0 ? ` ${Math.round(done)} / ${Math.round(total)}` : ''}`;
        renderAttachments();
        syncSend();
      }

      updateRagRuntimeActivity({
        title: stateName === 'ready' ? 'RAG document ready' : 'Indexing RAG document',
        detail: `${String(attachment?.name || 'Document')} · ${phase}${total > 0 ? ` · ${Math.round(done)} / ${Math.round(total)} chunks` : ''}${pct != null ? ` · ${Math.round(pct)}%` : ''}`,
        percent: stateName === 'ready' ? 100 : pct
      });

      if (stateName === 'ready') {
        if (attachment) {
          attachment.rag_chunks = chunks || total || attachment.rag_chunks || 0;
          attachment.meta = `RAG · ${attachment.rag_chunks} chunks`;
          renderAttachments();
          syncSend();
        }
        clearRagRuntimeActivity(1400);
        return job;
      }
      if (stateName === 'failed') {
        const msg = String(job?.error || 'RAG indexing failed');
        updateRagRuntimeActivity({title:'RAG indexing failed', detail:`${String(attachment?.name || 'Document')} · ${msg}`, percent:null});
        throw new Error(msg);
      }
      await sleep(700);
    }
    throw lastError || new Error('RAG indexing timed out');
  }

  async function addRagFileAttachment(file, id, kind){
    const name = String(file?.name || 'document');
    const provisional = {
      id,
      type:'rag',
      name,
      meta:'RAG · Uploading 0%',
      mime:String(file?.type || 'application/octet-stream'),
      size:Number(file?.size || 0),
      rag_state:'uploading',
      rag_document_id:'',
      rag_chunks:0,
      rag_embedding_model:''
    };
    state.attachments.push(provisional);
    renderAttachments();
    syncSend();

    setRagRuntimeActivity({
      title:'Preparing RAG document',
      detail:`${name} · Uploading · 0%`,
      percent:0
    });

    try {
      let saw100 = false;
      const up = await uploadFile(file, {
        rag:true,
        onUploadProgress:({loaded,total,percent})=>{
          const pct = percent == null ? null : Math.round(percent);
          provisional.rag_state = 'uploading';
          provisional.meta = `RAG · Uploading${pct == null ? '' : ` ${pct}%`}`;
          if (pct != null && pct >= 100) saw100 = true;
          renderAttachments();
          updateRagRuntimeActivity({
            title:'Preparing RAG document',
            detail: pct != null && pct >= 100
              ? `${name} · Extracting text…`
              : `${name} · Uploading${pct == null ? '' : ` · ${pct}%`}`,
            percent: pct != null && pct >= 100 ? null : pct
          });
        }
      });

      // The upload body may already be on the server while PHP is still
      // extracting PDF/DOCX text. Make that waiting phase explicit.
      if (saw100) updateRagRuntimeActivity({title:'Preparing RAG document', detail:`${name} · Extracting text…`, percent:null});

      const rr = up?.rag || {};
      const jobId = String(rr.job_id || '');
      const documentId = String(rr.document_id || '');
      if (!jobId || !documentId) throw new Error('RAG server did not return an indexing job');

      provisional.url = String(up.url || '');
      provisional.file_id = String(up.id || '');
      provisional.mime = String(up.mime || provisional.mime || 'application/octet-stream');
      provisional.size = Number(up.size || provisional.size || 0);
      provisional.rag_document_id = documentId;
      provisional.rag_job_id = jobId;
      provisional.rag_embedding_model = String(rr.embedding_model || '');
      provisional.rag_state = String(rr.state || 'queued');
      provisional.meta = `RAG · ${ragPhaseLabel(provisional.rag_state)}`;
      renderAttachments();

      await waitForRagJob(jobId, provisional);
      return provisional;
    } catch (err) {
      provisional.rag_state = 'failed';
      provisional.rag_error = String(err?.message || err);
      provisional.meta = 'RAG · Failed';
      renderAttachments();
      syncSend();
      updateRagRuntimeActivity({title:'RAG indexing failed', detail:`${name} · ${provisional.rag_error}`, percent:null});
      throw err;
    }
  }

  // ---- File readers (client-side inline attachments) ----
  const readAsDataURL = (file)=>new Promise((resolve, reject)=>{
    const r = new FileReader();
    r.onerror = ()=>reject(new Error('Failed to read file'));
    r.onload = ()=>resolve(String(r.result||''));
    r.readAsDataURL(file);
  });
  const TEXT_EXT = new Set([
    'txt','md','markdown','rst','csv','tsv','json','jsonl','xml','yaml','yml','toml','ini','conf','log',
    'html','htm','css','js','ts','jsx','tsx','py','php','java','c','h','cpp','hpp','rs','go','rb','sh','bash','zsh','sql'
  ]);

  const bytesFromMb = (mb)=>Math.max(0, normalizeMbLimit(mb, 0, 0, 1024) * 1024 * 1024);

  function extOf(name){
    const p = String(name||'').split('.');
    return (p.length>1 ? p[p.length-1] : '').toLowerCase();
  }

  function audioFormatFromFile(name, mime){
    const ext = extOf(name);
    if (['mp3','wav','m4a','aac','ogg','oga','opus','flac','webm'].includes(ext)) return ext === 'oga' ? 'ogg' : ext;
    const m = String(mime||'').toLowerCase();
    if (m.includes('mpeg') || m.includes('mp3')) return 'mp3';
    if (m.includes('wav')) return 'wav';
    if (m.includes('mp4') || m.includes('m4a')) return 'm4a';
    if (m.includes('aac')) return 'aac';
    if (m.includes('ogg')) return 'ogg';
    if (m.includes('opus')) return 'opus';
    if (m.includes('flac')) return 'flac';
    if (m.includes('webm')) return 'webm';
    return ext || 'audio';
  }

  async function addFileAttachment(f){
    const mime = String(f.type||'');
    const name = String(f.name||'file');
    const ext = extOf(name);
    const id = 'att_'+Math.random().toString(36).slice(2,9);

    const isImg = mime.startsWith('image/') || ['png','jpg','jpeg','webp','gif','bmp'].includes(ext);
    const isAudio = mime.startsWith('audio/') || ['mp3','wav','m4a','aac','ogg','oga','opus','flac','webm'].includes(ext);
    const isPdf = mime === 'application/pdf' || ext === 'pdf';
    const isDocx = mime === 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' || ext === 'docx';
    const isOdt = mime === 'application/vnd.oasis.opendocument.text' || ext === 'odt';
    const isXlsx = mime === 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' || ext === 'xlsx';
    const isOds = mime === 'application/vnd.oasis.opendocument.spreadsheet' || ext === 'ods';
    const isText = mime.startsWith('text/') || TEXT_EXT.has(ext);
    const isRagIndexable = isText || isPdf || isDocx || isOdt || isXlsx || isOds;

    // RAG is an explicit mode switch. When it is ON, document-like uploads are
    // sent once to PHP; PHP extracts and hands the text directly to ragd. The
    // browser receives only file/job metadata and polls real indexing progress.
    if (state.webtools?.rag && isRagIndexable) {
      const kind = isPdf ? 'PDF' : (isDocx ? 'DOCX' : (isOdt ? 'ODT' : (isXlsx ? 'XLSX' : (isOds ? 'ODS' : 'Text'))));
      await addRagFileAttachment(f, id, kind);
      return;
    }

    // Images: optionally inline as data URL (portable but DB-heavy), or store only in uploads.
    // When stored only as a file URL, the backend re-loads/encodes it for multimodal requests.
    if (isImg) {
      const inlineImages = !!state.ui.mediaImageInline;
      if (!inlineImages || Number(f.size||0) > bytesFromMb(state.ui.mediaImageInlineLimitMb ?? 8)) {
        const up = await uploadFile(f);
        state.attachments.push({
          id,
          type: 'image',
          name: up.name || name,
          meta: `${human(up.size || f.size)} · ${inlineImages ? 'image (too large inline)' : 'stored in uploads'}`,
          url: up.url,
          mime: up.mime || mime || 'image/*',
          size: up.size || Number(f.size||0),
          file_id: up.id,
          stored_only: !inlineImages,
          note: inlineImages ? 'Image not inlined (too large).' : 'Image stored in uploads; encoded again when sent to the model.'
        });
        return;
      }
      const dataUrl = await readAsDataURL(f);
      state.attachments.push({
        id,
        type: 'image',
        name,
        meta: `${human(f.size)} · inline`,
        data_url: dataUrl,
        mime: mime || 'image/*',
        size: Number(f.size||0),
      });
      return;
    }



    // Audio: optionally inline as data URL (portable but DB-heavy), or store only in uploads.
    // Stored-only audio is re-loaded/encoded by the backend when building multimodal input.
    if (isAudio) {
      const up = await uploadFile(f);
      const inlineAudio = !!state.ui.mediaAudioInline;
      if (!inlineAudio || Number(f.size||0) > bytesFromMb(state.ui.mediaAudioInlineLimitMb ?? 15)) {
        state.attachments.push({
          id,
          type: 'audio',
          name: up.name || name,
          meta: `${human(up.size || f.size)} · ${inlineAudio ? 'audio (too large inline)' : 'stored in uploads'}`,
          url: up.url,
          mime: up.mime || mime || 'audio/*',
          size: up.size || Number(f.size||0),
          file_id: up.id,
          stored_only: !inlineAudio,
          note: inlineAudio ? 'Audio not inlined (too large).' : 'Audio stored in uploads; encoded again when sent to the model.',
          format: audioFormatFromFile(name, mime)
        });
        return;
      }
      const dataUrl = await readAsDataURL(f);
      state.attachments.push({
        id,
        type: 'audio',
        name,
        meta: `${human(f.size)} · inline audio`,
        data_url: dataUrl,
        url: up.url,
        mime: up.mime || mime || 'audio/*',
        size: Number(f.size||0),
        file_id: up.id,
        format: audioFormatFromFile(name, mime)
      });
      return;
    }

    // Normal documents remain text attachments semantically, exactly like the
    // old UI/model path. The only change is storage: the chat keeps file_id and
    // metadata, while the full extraction is read from the one HDD copy on demand.
    if (isRagIndexable) {
      const up = await uploadFile(f);
      const att = {
        id,
        type: 'text',
        name: up.name || name,
        url: up.url,
        mime: up.mime || mime || 'application/octet-stream',
        size: Number(up.size || f.size || 0),
        file_id: up.id
      };
      att.meta = documentTextMeta(att);
      state.attachments.push(att);
      return;
    }

    // Fallback: upload for download.
    const up = await uploadFile(f);
    state.attachments.push({
      id,
      type: 'file',
      name: up.name,
      meta: `${human(up.size)} · stored`,
      url: up.url,
      mime: up.mime,
      size: up.size,
      file_id: up.id,
      not_sent: true
    });
  }

  fileInput?.addEventListener('change', async ()=>{
    const files = Array.from(fileInput.files||[]);
    if (!files.length) return;
    try {
      for (const f of files) await addFileAttachment(f);
    } catch (err) {
      alert(String(err?.message || err || 'File/RAG processing failed'));
    }
    fileInput.value='';
    renderAttachments(); renderWebTools(); syncSend();
  });

  // drag & drop
  ['dragenter','dragover'].forEach(ev=>{
    inputContainer?.addEventListener(ev, (e)=>{ e.preventDefault(); inputContainer.classList.add('dragover'); });
  });
  ['dragleave','dragend'].forEach(ev=>{
    inputContainer?.addEventListener(ev, ()=> inputContainer.classList.remove('dragover'));
  });
  inputContainer?.addEventListener('drop', async (e)=>{
    e.preventDefault(); inputContainer.classList.remove('dragover');
    const files = Array.from(e.dataTransfer?.files||[]);
    if (files.length){
      // Composer drops are always chat attachments. Enabling Code Workspace makes
      // workspace tools available to the agent; it must not silently reinterpret
      // every user upload as a project import. The agent can explicitly import a
      // relevant attachment later with workspace_import_attachment.
      try {
        for (const f of files) await addFileAttachment(f);
      } catch (err) {
        alert(String(err?.message || err || 'File/RAG processing failed'));
      }
      renderAttachments(); renderWebTools(); syncSend();
    }
  });


// paste (Ctrl/Cmd+V) images from clipboard into attachments
async function handlePasteToAttachments(e){
  const dt = e.clipboardData;
  if (!dt) return false;

  let files = [];
  const items = Array.from(dt.items || []);
  for (const it of items){
    if (it && it.kind === 'file'){
      const f = it.getAsFile && it.getAsFile();
      if (f && String(f.type||'').startsWith('image/')) files.push(f);
    }
  }

  // Fallback: some browsers expose clipboard files here
  if (!files.length){
    const ff = Array.from(dt.files || []);
    for (const f of ff){
      if (f && String(f.type||'').startsWith('image/')) files.push(f);
    }
  }

  // Fallback: copied <img src="data:image/..."> from the browser
  if (!files.length){
    const html = dt.getData && dt.getData('text/html');
    if (html && /<img/i.test(html)){
      const srcs = [];
      const re = /<img[^>]+src=["']([^"']+)["']/ig;
      let m;
      while ((m = re.exec(html))) {
        const src = String(m[1] || '');
        if (src.startsWith('data:image/')) srcs.push(src);
      }
      for (const src of srcs.slice(0, 5)){
        try{
          const blob = await (await fetch(src)).blob();
          if (!String(blob.type||'').startsWith('image/')) continue;
          const ext = (String(blob.type).split('/')[1] || 'png').replace('jpeg','jpg');
          files.push(new File([blob], `pasted.${ext}`, { type: blob.type }));
        }catch(_){ }
      }
    }
  }

  if (!files.length) return false;

  // Don't clobber normal pastes that include text
  const hasText = !!(dt.getData && (dt.getData('text/plain') || '').trim());
  if (!hasText) e.preventDefault();

  for (const f of files.slice(0, 5)) await addFileAttachment(f);
  renderAttachments();
  syncSend();
  return true;
}

// Only react to paste when the user is in the composer (avoid interfering with settings forms etc.)
document.addEventListener('paste', (e)=>{
  const t = e.target;
  const active = document.activeElement;
  const inComposer =
    (t && t.closest && t.closest('#input-container')) ||
    (active && active.closest && active.closest('#input-container'));
  if (!inComposer) return;
  // Fire and forget (async)
  handlePasteToAttachments(e);
});

  // Autoscroll. Throttle bookkeeping to one read per animation frame so rapid
  // keyboard/touch scrolling cannot flood the main thread on very long chats.
  let chatScrollRaf = 0;
  chatArea?.addEventListener('scroll', ()=>{
    if (chatScrollRaf) return;
    chatScrollRaf = requestAnimationFrame(()=>{
      chatScrollRaf = 0;
      const near = (chatArea.scrollHeight - chatArea.scrollTop - chatArea.clientHeight) < 120;
      state.autoscroll = near;
    });
  }, {passive:true});
  function scrollBottom(force=false){
    if (!chatArea) return;
    if (force || state.autoscroll) chatArea.scrollTop = chatArea.scrollHeight;
  }

  // Autoscroll inside the reasoning box (when expanded). If the user scrolls up,
  // we stop forcing it to the bottom until they scroll back down.
  function attachThinkingAutoscroll(el){
    if (!el || el.dataset.asBound === '1') return;
    el.dataset.asBound = '1';
    el.dataset.stickBottom = '1';
    el.addEventListener('scroll', ()=>{
      const near = (el.scrollHeight - el.scrollTop - el.clientHeight) < 24;
      el.dataset.stickBottom = near ? '1' : '0';
    }, {passive:true});
  }

  function maybeScrollThinking(el){
    if (!el) return;
    attachThinkingAutoscroll(el);
    if (!el.classList.contains('expanded')) return;
    if (el.dataset.stickBottom !== '0') el.scrollTop = el.scrollHeight;
  }

  // Reasoning is plain pre-wrapped text. Keep it as a single text node instead
  // of rebuilding escaped HTML (and thousands of <br> nodes) on every delta.
  const normalizeThinkingText = (text)=> String(text ?? '').replace(/\r\n?/g, '\n');

  function setThinkingText(el, text){
    if (!el) return;
    const raw = String(text ?? '');
    el.textContent = normalizeThinkingText(raw);
    el.dataset.reasoningChars = String(raw.length);
  }

  function appendThinkingText(el, delta, totalRawLength, previousRawEndsCr=false){
    if (!el || !delta) return;
    let raw = String(delta);
    // If CRLF was split across two stream events, the previous full render has
    // already normalized the CR. Avoid introducing a second newline for the LF.
    if (previousRawEndsCr && raw.startsWith('\n')) raw = raw.slice(1);
    const text = normalizeThinkingText(raw);
    const onlyChild = el.firstChild && el.firstChild === el.lastChild ? el.firstChild : null;
    if (onlyChild && onlyChild.nodeType === Node.TEXT_NODE) {
      onlyChild.appendData(text);
    } else if (!el.firstChild) {
      el.appendChild(document.createTextNode(text));
    } else {
      // Defensive fallback for old/mutated DOM. The next full sync will collapse
      // this back to one node if another renderer has inserted child elements.
      el.appendChild(document.createTextNode(text));
    }
    el.dataset.reasoningChars = String(totalRawLength);
  }

  function normalizeAgentActivityEvent(raw){
    if (!raw || typeof raw !== 'object') return null;
    const id = String(raw.id || '').trim();
    const title = String(raw.title || '').trim();
    if (!id || !title) return null;
    const allowedStatus = new Set(['running','done','error']);
    const allowedKind = new Set(['tool','commentary','finding','decision','warning']);
    const allowedDetailFormat = new Set(['text','code','json']);
    const livePreview = raw.live_preview === true;
    const detailRaw = String(raw.detail || '');
    const generatedBytesRaw = Number(raw.generated_bytes);
    const progressRaw = (raw.progress === null || raw.progress === undefined || raw.progress === '') ? NaN : Number(raw.progress);
    return {
      id,
      title,
      status: allowedStatus.has(String(raw.status||'')) ? String(raw.status) : 'done',
      kind: allowedKind.has(String(raw.kind||'')) ? String(raw.kind) : 'commentary',
      tool: String(raw.tool || ''),
      detail: livePreview ? detailRaw : detailRaw.trim(),
      detail_label: String(raw.detail_label || '').trim(),
      detail_summary: String(raw.detail_summary || '').trim(),
      detail_format: allowedDetailFormat.has(String(raw.detail_format||'')) ? String(raw.detail_format) : 'text',
      live_preview: livePreview,
      generated_bytes: Number.isFinite(generatedBytesRaw) ? Math.max(0, Math.round(generatedBytesRaw)) : 0,
      preview_target: String(raw.preview_target || '').trim(),
      preview_truncated: raw.preview_truncated === true,
      cancel_action: String(raw.cancel_action || '').trim(),
      cancel_server_id: String(raw.cancel_server_id || '').trim(),
      cancel_job_id: String(raw.cancel_job_id || '').trim(),
      artifact_id: String(raw.artifact_id || '').trim(),
      artifact_url: String(raw.artifact_url || '').trim(),
      progress: Number.isFinite(progressRaw) ? Math.max(0, Math.min(1, progressRaw)) : null,
      progress_label: String(raw.progress_label || '').trim(),
      ts: Number.isFinite(Number(raw.ts)) ? Number(raw.ts) : now()
    };
  }

  function agentActivityTotal(message, storedCount=null){
    const stored = storedCount == null
      ? (Array.isArray(message?.activity) ? message.activity.length : 0)
      : Math.max(0, Math.round(Number(storedCount) || 0));
    const raw = Number(message?.activity_total);
    return Number.isFinite(raw) ? Math.max(stored, Math.max(0, Math.round(raw))) : stored;
  }

  function agentActivitySeenIds(message){
    if (!message || typeof message !== 'object') return null;
    if (message.__agentActivitySeenIds instanceof Set) return message.__agentActivitySeenIds;
    const seen = new Set();
    for (const raw of (Array.isArray(message.activity) ? message.activity : [])) {
      const id = String(raw?.id || '').trim();
      if (id) seen.add(id);
    }
    try {
      // Runtime-only bookkeeping. Do not inflate chat JSON/export data with every
      // historical activity id just to keep an exact counter.
      Object.defineProperty(message, '__agentActivitySeenIds', {
        value: seen,
        writable: true,
        configurable: true,
        enumerable: false
      });
    } catch(_) {
      // A sealed legacy object can skip the cache; retained ids still prevent
      // duplicate counting in the normal update path.
    }
    return seen;
  }

  function upsertAgentActivity(message, rawEvent){
    const event = normalizeAgentActivityEvent(rawEvent);
    if (!message || !event) return false;
    if (!Array.isArray(message.activity)) message.activity = [];

    const beforeCount = message.activity.length;
    const seen = agentActivitySeenIds(message);
    const idx = message.activity.findIndex(x=>String(x?.id||'') === event.id);
    const alreadySeen = idx >= 0 || !!seen?.has(event.id);

    if (idx >= 0) {
      const previous = normalizeAgentActivityEvent(message.activity[idx]);
      const sameRunningStage = !!previous
        && previous.status === 'running'
        && event.status === 'running'
        && previous.kind === event.kind
        && previous.tool === event.tool
        && previous.title === event.title;

      // ComfyUI can interleave `executing` / progress_state updates without a
      // numeric value between sampler progress events. Those events describe the
      // same running node and must not erase the most recent 8/25-style progress.
      // A real node/title change still clears progress normally.
      if (sameRunningStage && event.progress == null && previous.progress != null) {
        event.progress = previous.progress;
        if (!event.progress_label) event.progress_label = previous.progress_label;
      }

      message.activity[idx] = {...message.activity[idx], ...event};
    } else {
      message.activity.push(event);
    }

    if (!alreadySeen) {
      message.activity_total = agentActivityTotal(message, beforeCount) + 1;
      seen?.add(event.id);
    } else if (message.activity_total != null) {
      // Keep malformed/old values from ever dropping below the retained history.
      message.activity_total = agentActivityTotal(message);
    }

    if (message.activity.length > 100) message.activity = message.activity.slice(-100);
    return true;
  }

  // A stream can end without its final SSE frame reaching the browser (proxy close,
  // network interruption, malformed final chunk). Never leave animated activity
  // rows in a permanent `running` state after the client has stopped streaming.
  function settleAgentActivity(message, status='done'){
    if (!message || !Array.isArray(message.activity)) return false;
    const terminalStatus = status === 'error' ? 'error' : 'done';
    let changed = false;
    message.activity = message.activity.map(raw=>{
      const event = normalizeAgentActivityEvent(raw);
      if (!event || event.status !== 'running') return raw;
      changed = true;
      return {...raw, status:terminalStatus, live_preview:false, ts:now()};
    });
    return changed;
  }

  function clearAgentArtifactLinks(message){
    if (!message) return false;
    let changed = false;
    if (Array.isArray(message.activity)) {
      message.activity = message.activity.map(raw=>{
        if (!raw || (!raw.artifact_url && !raw.artifact_id)) return raw;
        changed = true;
        return {...raw, artifact_url:'', artifact_id:''};
      });
    }
    if (message.metrics && Number(message.metrics.mcp_artifact_count || 0) !== 0) {
      message.metrics.mcp_artifact_count = 0;
      changed = true;
    }
    return changed;
  }

  function syncChatStreamingClass(){
    if (!chatMsgs) return;
    const chatId = String(state.currentChat?.id || '');
    chatMsgs.classList.toggle('is-streaming', !!chatId && state.streams.has(chatId));
  }

  function agentActivityRowHtml(rawEvent){
    const event = normalizeAgentActivityEvent(rawEvent);
    if (!event) return '';
    const status = event.status;
    const kind = event.kind;
    const icon = status === 'done' ? '✓' : (status === 'error' ? '!' : (kind === 'commentary' ? '→' : '•'));
    const tool = event.tool ? `<span class="agent-activity-tool">${esc(event.tool)}</span>` : '';
    let detail = '';

    if (event.live_preview && status === 'running') {
      const formatClass = ['code','json'].includes(event.detail_format) ? ` agent-activity-live-${event.detail_format}` : ' agent-activity-live-text';
      const target = event.preview_target ? `<span class="agent-activity-live-target">${esc(event.preview_target)}</span>` : '<span class="agent-activity-live-target">Output</span>';
      const size = `<span class="agent-activity-live-size">${esc(human(event.generated_bytes) || `${event.generated_bytes} B`)} generated</span>`;
      const tail = event.preview_truncated ? '<span class="agent-activity-live-tail-label">latest tail</span>' : '';
      const body = `${event.preview_truncated ? '<span class="agent-activity-live-ellipsis">…</span>' : ''}${esc(event.detail)}<span class="agent-activity-live-cursor" aria-hidden="true">▋</span>`;
      detail = `<div class="agent-activity-live-preview${formatClass}">
        <div class="agent-activity-live-meta">${target}<span class="agent-activity-live-sep">·</span>${size}${tail}</div>
        <div class="agent-activity-live-body">${body}</div>
      </div>`;
    } else if (event.detail) {
      const label = event.detail_label ? `<span class="agent-activity-detail-label">${esc(event.detail_label)}</span>` : '';
      const detailFormat = ['code','json'].includes(event.detail_format) ? event.detail_format : 'text';
      const formatClass = ` agent-activity-detail-${detailFormat}`;
      if (event.detail.length > 220 || event.detail.includes('\n')) {
        const firstLine = event.detail.split('\n', 1)[0];
        const previewSource = event.detail_summary || firstLine || event.detail;
        const preview = previewSource.length > 217 ? `${previewSource.slice(0, 217).trimEnd()}…` : previewSource;
        detail = `<details class="agent-activity-detail agent-activity-detail-expandable${formatClass}">
          <summary>${label}<span class="agent-activity-detail-text">${esc(preview)}</span></summary>
          <div class="agent-activity-detail-full">${esc(event.detail)}</div>
        </details>`;
      } else {
        detail = `<div class="agent-activity-detail${formatClass}">${label}<span class="agent-activity-detail-text">${esc(event.detail)}</span></div>`;
      }
    }

    const canCancel = status === 'running'
      && ['mcp_cancel','comfyui_cancel'].includes(event.cancel_action)
      && event.cancel_job_id
      && (event.cancel_action !== 'mcp_cancel' || event.cancel_server_id);
    const cancelTitle = event.cancel_action === 'comfyui_cancel'
      ? 'Stop this ComfyUI job; keep the agent running'
      : 'Stop only this process; keep the agent running';
    const cancelButton = canCancel
      ? `<button type="button" class="agent-activity-cancel" data-cancel-action="${esc(event.cancel_action)}" data-server-id="${esc(event.cancel_server_id)}" data-job-id="${esc(event.cancel_job_id)}" title="${esc(cancelTitle)}">Stop</button>`
      : '';
    const artifactButton = event.artifact_url
      ? `<a class="agent-activity-artifact" href="${esc(event.artifact_url)}" target="_blank" rel="noopener">Open full output</a>`
      : '';
    const progressValue = (event.progress === null || event.progress === undefined || event.progress === '') ? NaN : Number(event.progress);
    const progressPct = Number.isFinite(progressValue) ? Math.max(0, Math.min(100, Math.round(progressValue * 100))) : null;
    const progressLabel = event.progress_label || (progressPct != null ? `${progressPct}%` : '');
    const progress = progressPct == null ? '' : `<div class="agent-activity-progress-wrap">
      <div class="agent-activity-progress" aria-label="${esc(progressLabel)}"><span style="width:${progressPct}%"></span></div>
      <span class="agent-activity-progress-label">${esc(progressLabel)}</span>
    </div>`;
    return `<div class="agent-activity-item ${esc(status)} ${esc(kind)}${event.live_preview ? ' live-preview' : ''}" data-activity-id="${esc(event.id)}">
      <span class="agent-activity-icon" aria-hidden="true">${icon}</span>
      <div class="agent-activity-main">
        <span class="agent-activity-title">${esc(event.title)}</span>
        ${detail}
        ${progress}
      </div>
      <div class="agent-activity-side">${tool}${artifactButton}${cancelButton}</div>
    </div>`;
  }

  function agentActivityHtml(message){
    const allEvents = Array.isArray(message?.activity)
      ? message.activity.map(normalizeAgentActivityEvent).filter(Boolean)
      : [];
    const events = allEvents.slice(-60);
    if (!events.length) return '';
    const rows = events.map(agentActivityRowHtml).join('');
    const total = agentActivityTotal(message, allEvents.length);
    const countLabel = total > events.length ? `${events.length}/${total}` : `${events.length}`;
    const collapsed = message?.activity_collapsed === true;
    return `<div class="agent-activity-section${collapsed ? ' collapsed' : ''}">
      <button type="button" class="agent-activity-header" aria-expanded="${collapsed ? 'false' : 'true'}">
        <span class="agent-activity-heading">Agent activity</span>
        <span class="agent-activity-header-meta">
          <span class="agent-activity-count">${countLabel}</span>
          <span class="agent-activity-chevron" aria-hidden="true">${collapsed ? '▼' : '▲'}</span>
        </span>
      </button>
      <div class="agent-activity-list">${rows}</div>
    </div>`;
  }

  function scrollAgentLivePreviewToTail(root){
    if (!root) return;
    for (const body of root.querySelectorAll('.agent-activity-live-body')) {
      body.scrollTop = body.scrollHeight;
    }
  }

  // The activity list is its own scroll container. Replacing the section DOM used
  // to reset that container to scrollTop=0 whenever a new tool/action arrived.
  // Keep following the newest row while the user is already near the bottom, but
  // preserve their exact position when they intentionally scroll up to inspect
  // older activity.
  function captureAgentActivityScroll(section){
    const list = section?.querySelector('.agent-activity-list');
    if (!list) return null;
    const distanceFromBottom = list.scrollHeight - list.scrollTop - list.clientHeight;
    return {
      top: list.scrollTop,
      stickBottom: distanceFromBottom < 32
    };
  }

  function restoreAgentActivityScroll(section, snapshot, defaultToBottom=false){
    const list = section?.querySelector('.agent-activity-list');
    if (!list) return;
    if (!snapshot) {
      if (defaultToBottom) list.scrollTop = list.scrollHeight;
      return;
    }
    list.scrollTop = snapshot.stickBottom ? list.scrollHeight : snapshot.top;
  }

  function patchAgentActivityRunningDom(row, rawEvent){
    const event = normalizeAgentActivityEvent(rawEvent);
    if (!row || !event || event.live_preview) return false;

    // Keep a running row mounted while ComfyUI reports updates for the same node.
    // This prevents CSS/layout flicker and, importantly, keeps an existing
    // progress bar visible when ComfyUI interleaves a non-numeric `executing`
    // update between numeric sampler progress events.
    const title = row.querySelector('.agent-activity-title');
    if (!title || title.textContent !== event.title) return false;
    if (!row.classList.contains(event.status) || !row.classList.contains(event.kind)) return false;
    if (event.status !== 'running') return false;

    const main = row.querySelector('.agent-activity-main');
    if (!main) return false;

    const progressValue = (event.progress === null || event.progress === undefined || event.progress === '') ? NaN : Number(event.progress);
    if (Number.isFinite(progressValue)) {
      const progressPct = Math.max(0, Math.min(100, Math.round(progressValue * 100)));
      const progressLabel = event.progress_label || `${progressPct}%`;
      let wrap = main.querySelector('.agent-activity-progress-wrap');
      if (!wrap) {
        main.insertAdjacentHTML('beforeend', `<div class="agent-activity-progress-wrap">
          <div class="agent-activity-progress"><span></span></div>
          <span class="agent-activity-progress-label"></span>
        </div>`);
        wrap = main.querySelector('.agent-activity-progress-wrap');
      }
      const bar = wrap?.querySelector('.agent-activity-progress');
      const fill = bar?.querySelector('span');
      const label = wrap?.querySelector('.agent-activity-progress-label');
      if (!bar || !fill || !label) return false;
      bar.setAttribute('aria-label', progressLabel);
      fill.style.width = `${progressPct}%`;
      label.textContent = progressLabel;
    }

    // No numeric progress on this event is intentional: leave any existing bar
    // untouched. A different node/title falls through to the normal full render.
    return true;
  }

  function renderAgentActivityDom(msgEl, message, rawEvent=null){
    if (!msgEl) return;
    const wrapper = msgEl.querySelector('.message-wrapper');
    if (!wrapper) return;
    const current = wrapper.querySelector('.agent-activity-section');

    // The hot path updates the current row in place. New activity rows are also
    // appended in place so an active agent run does not recreate the scroll box.
    if (current && rawEvent) {
      const event = normalizeAgentActivityEvent(rawEvent);
      if (event) {
        const scrollSnapshot = captureAgentActivityScroll(current);
        let row = null;
        for (const candidate of current.querySelectorAll('.agent-activity-item')) {
          if (candidate.dataset.activityId === event.id) { row = candidate; break; }
        }
        if (row) {
          if (patchAgentActivityRunningDom(row, event)) {
            restoreAgentActivityScroll(current, scrollSnapshot);
            return;
          }

          row.outerHTML = agentActivityRowHtml(event);
          let replacement = null;
          for (const candidate of current.querySelectorAll('.agent-activity-item')) {
            if (candidate.dataset.activityId === event.id) { replacement = candidate; break; }
          }
          scrollAgentLivePreviewToTail(replacement);
          restoreAgentActivityScroll(current, scrollSnapshot);
          return;
        }

        const list = current.querySelector('.agent-activity-list');
        if (list) {
          list.insertAdjacentHTML('beforeend', agentActivityRowHtml(event));
          while (list.children.length > 60) list.firstElementChild?.remove();

          const allEvents = Array.isArray(message?.activity)
            ? message.activity.map(normalizeAgentActivityEvent).filter(Boolean)
            : [];
          const shown = Math.min(60, allEvents.length);
          const total = agentActivityTotal(message, allEvents.length);
          const count = current.querySelector('.agent-activity-count');
          if (count) count.textContent = total > shown ? `${shown}/${total}` : `${shown}`;

          const appended = list.lastElementChild;
          scrollAgentLivePreviewToTail(appended);
          restoreAgentActivityScroll(current, scrollSnapshot, true);
          return;
        }
      }
    }

    const html = agentActivityHtml(message);
    if (!html) {
      current?.remove();
      return;
    }
    if (current) {
      const scrollSnapshot = captureAgentActivityScroll(current);
      current.outerHTML = html;
      const replacement = wrapper.querySelector('.agent-activity-section');
      scrollAgentLivePreviewToTail(replacement);
      restoreAgentActivityScroll(replacement, scrollSnapshot);
      return;
    }
    const header = wrapper.querySelector('.message-header');
    if (header) header.insertAdjacentHTML('afterend', html);
    else wrapper.insertAdjacentHTML('afterbegin', html);
    const inserted = wrapper.querySelector('.agent-activity-section');
    scrollAgentLivePreviewToTail(inserted);
    restoreAgentActivityScroll(inserted, null, true);
  }

  // Textarea send
  function ragDraftBlocked(){
    if (!state.webtools?.rag) return false;
    return (state.attachments || []).some(a=>a?.type === 'rag' && String(a.rag_state || (a.rag_document_id ? 'ready' : '')) !== 'ready');
  }

  function syncSend(){
    const hasText = textarea.value.trim().length>0;
    const streaming = isCurrentChatStreaming();
    const ragBlocked = ragDraftBlocked();
    const busySend = streaming || !!state.webFetchBusy || ragBlocked;
    sendBtn.disabled = busySend || (!hasText && state.attachments.length===0);
    if (sendBtn) sendBtn.title = ragBlocked ? 'Wait until the RAG document is indexed, remove it, or switch RAG off' : 'Send';
    if (stopBtn) stopBtn.disabled = !streaming;
    // Voice button
    if (voiceBtn){
      const hasKey = !!String(state.ui.voiceApiKey||'').trim();
      const show = !!state.ui.voiceAutoEnable;
      voiceBtn.classList.toggle('hidden', !show);
      voiceBtn.disabled = !show || !hasKey || busySend || !!state.voice?.busy;
    }
  }
  textarea?.addEventListener('input', ()=>{
    textarea.style.height='auto';
    textarea.style.height=Math.min(textarea.scrollHeight,120)+'px';
    syncSend();
  });
  textarea?.addEventListener('keydown', (e)=>{
    if(e.key==='Enter' && !e.shiftKey){ e.preventDefault(); send(); }
  });
  sendBtn?.addEventListener('click', ()=>send());
  stopBtn?.addEventListener('click', ()=>stopCurrentStream());

  // ---------- Sidebar rendering ----------
  // Helpers for <details> folders
  const setFolderOpen = (details, open)=>{
    try{
      if (!(details instanceof HTMLDetailsElement)) return;
      details.open = !!open;
      const fid = details?.dataset?.folderId;
      if (fid) localStorage.setItem('folder_open_'+fid, details.open?'true':'false');
      const chev = details.querySelector(':scope > summary .folder-chevron');
      if (chev) chev.textContent = details.open ? '▾' : '▸';
    }catch(_){/* noop */}
  };

  const collapseFolderTree = (rootDetails)=>{
    if (!(rootDetails instanceof HTMLDetailsElement)) return;
    const all = [rootDetails].concat(Array.from(rootDetails.querySelectorAll('.folder')));
    all.forEach(d=> setFolderOpen(d, false));
  };

  function buildMaps(){
    const foldersByParent = new Map();
    state.folders.forEach(f=>{
      const p = f.parent_id || '__root__';
      if(!foldersByParent.has(p)) foldersByParent.set(p, []);
      foldersByParent.get(p).push(f);
    });
    foldersByParent.forEach(arr=>arr.sort((a,b)=>{
      const aa = Number(a?.is_archive || 0) === 1 ? 1 : 0;
      const bb = Number(b?.is_archive || 0) === 1 ? 1 : 0;
      if (aa !== bb) return bb - aa;
      return String(a?.name || '').localeCompare(String(b?.name || ''), undefined, {sensitivity:'base'});
    }));

    const chatsByFolder = new Map();
    state.chats.forEach(c=>{
      const k = c.folder_id || '__root__';
      if(!chatsByFolder.has(k)) chatsByFolder.set(k, []);
      chatsByFolder.get(k).push(c);
    });
    chatsByFolder.forEach(arr=>arr.sort((a,b)=>(b.updated_at||0)-(a.updated_at||0)));
    return {foldersByParent, chatsByFolder};
  }

  let archiveTreeCacheSource = null;
  let archiveTreeCache = new Set();
  function archivedFolderIds(){
    if (archiveTreeCacheSource === state.folders) return archiveTreeCache;
    archiveTreeCacheSource = state.folders;
    archiveTreeCache = new Set();

    const folders = state.folders || [];
    const archive = folders.find(f=>Number(f?.is_archive || 0) === 1);
    if (!archive?.id) return archiveTreeCache;

    const children = new Map();
    folders.forEach(f=>{
      const p = String(f?.parent_id || '');
      if (!children.has(p)) children.set(p, []);
      children.get(p).push(String(f?.id || ''));
    });
    const stack = [String(archive.id)];
    while (stack.length){
      const id = stack.pop();
      if (!id || archiveTreeCache.has(id)) continue;
      archiveTreeCache.add(id);
      (children.get(id) || []).forEach(cid=>stack.push(cid));
    }
    return archiveTreeCache;
  }

  function folderIsInsideArchive(folderId){
    const id = String(folderId || '').trim();
    return !!id && archivedFolderIds().has(id);
  }

  function chatIsArchived(c){
    return !!c && folderIsInsideArchive(c.folder_id);
  }

  function attachedParentId(c){
    const pid = String(c?.clone_parent_id || '').trim();
    const attached = String(c?.clone_attached || '') === '1' || c?.clone_attached === 1 || c?.clone_attached === true;
    return (attached && pid) ? pid : '';
  }

  function chatEl(c){
    const div = document.createElement('div');
    const streaming = isChatStreaming(c.id);
    const archived = chatIsArchived(c);
    const sid = String(c.id);
    const isSel = !!(state.sidebarSelection && state.sidebarSelection.ids && state.sidebarSelection.ids.has(sid));
    div.className = 'chat-item' + (isSel?' selected':'') + (state.currentChat?.id===c.id?' active':'') + (streaming?' streaming':'');
    div.dataset.chatId=c.id;
    div.draggable = true;
    const folderBadge = c._folderName ? `<span class="chat-folder-badge">${esc(c._folderName)}</span>` : '';
    const streamBadge = streaming ? `<span class="chat-streaming-dot" title="Generating">●</span>` : '';
    const isAttachedVariant = !!attachedParentId(c);
    const variantBadge = isAttachedVariant ? `<span class="chat-variant-badge" title="Attached clone variant">Variant</span>` : '';
    const detachMenu = isAttachedVariant ? `
        <button class="chat-dropdown-item" data-cmd="detach">Detach from tree</button>` : '';
    const versionBadge = Number(c._cloneChildrenCount || 0) > 0 ? `<span class="chat-variant-badge" title="Attached clone variants">${Number(c._cloneChildrenCount)} version${Number(c._cloneChildrenCount)===1?'':'s'}</span>` : '';
    div.innerHTML = `
      <div class="chat-title">${esc(c.title||'New chat')} ${folderBadge} ${variantBadge} ${versionBadge} ${streamBadge}</div>
      <div class="chat-preview">${esc(c.preview||'')}</div>
      <button class="chat-menu-btn" data-action="chat-dropdown" aria-haspopup="true" aria-expanded="false">…</button>
      <div class="chat-dropdown">
        <div class="submenu-wrap">
          <button class="chat-dropdown-item has-submenu" type="button" data-submenu="rename">Rename</button>
        </div>
        <div class="submenu-wrap">
          <button class="chat-dropdown-item has-submenu" type="button" data-submenu="clone">Clone</button>
        </div>
        <button class="chat-dropdown-item" data-cmd="save-template">Save as template</button>
        <div class="submenu-wrap">
          <button class="chat-dropdown-item has-submenu" type="button" data-submenu="compress">Compress &amp; Clone</button>
        </div>
        <div class="submenu-wrap">
          <button class="chat-dropdown-item has-submenu" type="button" data-submenu="export">Export</button>
        </div>
        <button class="chat-dropdown-item" data-cmd="move">Move to…</button>
        ${archived ? '' : '<button class="chat-dropdown-item" data-cmd="archive">Move to archive</button>'}
        ${detachMenu}
        <div class="dropdown-sep"></div>
        <button class="chat-dropdown-item" data-cmd="delete">Delete</button>
      </div>
    `;
    return div;
  }


  function renderChatBranch(c, childrenByParent, depth){
    const kids = (childrenByParent.get(String(c.id)) || []).slice();
    c._cloneChildrenCount = kids.length;
    if (!kids.length) return chatEl(c);

    const branch = document.createElement('div');
    branch.className = 'chat-branch';
    branch.dataset.chatId = c.id;
    if (depth > 0) branch.classList.add('nested');

    const openKey = 'clone_branch_open_' + String(c.id);
    const isOpen = (localStorage.getItem(openKey) ?? 'true') === 'true';
    branch.classList.toggle('collapsed', !isOpen);

    const head = document.createElement('div');
    head.className = 'chat-branch-head';
    const toggle = document.createElement('button');
    toggle.className = 'clone-branch-toggle';
    toggle.type = 'button';
    toggle.title = isOpen ? 'Collapse variants' : 'Expand variants';
    toggle.textContent = isOpen ? '▾' : '▸';
    toggle.addEventListener('click', (e)=>{
      e.preventDefault(); e.stopPropagation();
      const nextOpen = branch.classList.contains('collapsed');
      branch.classList.toggle('collapsed', !nextOpen);
      toggle.textContent = nextOpen ? '▾' : '▸';
      toggle.title = nextOpen ? 'Collapse variants' : 'Expand variants';
      try{ localStorage.setItem(openKey, nextOpen ? 'true' : 'false'); }catch(_){ }
    });
    head.appendChild(toggle);
    head.appendChild(chatEl(c));
    branch.appendChild(head);

    const childWrap = document.createElement('div');
    childWrap.className = 'chat-branch-children';
    kids.forEach(k=>childWrap.appendChild(renderChatBranch(k, childrenByParent, depth + 1)));
    branch.appendChild(childWrap);
    return branch;
  }

  function appendChatsWithAttachedBranches(container, chats){
    const arr = Array.isArray(chats) ? chats.slice() : [];
    const byId = new Map(arr.map(c=>[String(c.id), c]));
    const childrenByParent = new Map();
    arr.forEach(c=>{
      const pid = attachedParentId(c);
      if (!pid || !byId.has(pid)) return;
      if (!childrenByParent.has(pid)) childrenByParent.set(pid, []);
      childrenByParent.get(pid).push(c);
    });
    childrenByParent.forEach(list=>list.sort((a,b)=>(b.updated_at||0)-(a.updated_at||0)));
    arr.forEach(c=>{
      const pid = attachedParentId(c);
      if (pid && byId.has(pid)) return;
      container.appendChild(renderChatBranch(c, childrenByParent, 0));
    });
  }

  function folderEl(f, maps){
    const details = document.createElement('details');
    const isArchive = Number(f?.is_archive || 0) === 1;
    const insideArchive = folderIsInsideArchive(f?.id);
    details.className='folder' + (isArchive ? ' archive-folder' : '');
    details.dataset.folderId=f.id;
    details.dataset.archive = isArchive ? '1' : '0';
    details.open = (localStorage.getItem('folder_open_'+f.id) ?? 'true') === 'true';

    const subfolders = maps.foldersByParent.get(f.id) || [];
    const chats = maps.chatsByFolder.get(f.id) || [];

    const folderIcon = isArchive
      ? `<span class="folder-icon archive-folder-icon" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M4 7h16v13H4zM3 4h18v4H3zM9 11h6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg></span>`
      : `<span class="folder-icon">📁</span>`;
    const folderMenu = isArchive
      ? `
          <button class="folder-dropdown-item" data-cmd="export">Export…</button>
          <button class="folder-dropdown-item" data-cmd="collapse-all">Collapse All</button>`
      : `
          <button class="folder-dropdown-item" data-cmd="rename">Rename</button>
          <button class="folder-dropdown-item" data-cmd="new-subfolder">New Subfolder</button>
          <button class="folder-dropdown-item" data-cmd="move">Move to…</button>
          ${insideArchive ? '' : '<button class="folder-dropdown-item" data-cmd="archive">Move to archive</button>'}
          <button class="folder-dropdown-item" data-cmd="export">Export…</button>
          <button class="folder-dropdown-item" data-cmd="collapse-all">Collapse All</button>
          <div class="dropdown-sep"></div>
          <button class="folder-dropdown-item" data-cmd="delete">Delete</button>`;

    details.innerHTML = `
      <summary class="folder-header" draggable="${isArchive ? 'false' : 'true'}">
        <div class="folder-title">
          <span class="folder-chevron">${details.open?'▾':'▸'}</span>
          ${folderIcon}
          <span class="folder-name">${esc(f.name||'Folder')}</span>
          <span class="folder-count">(${chats.length})</span>
        </div>
        <button class="folder-menu-btn" data-action="folder-dropdown" aria-haspopup="true" aria-expanded="false">…</button>
        <div class="folder-dropdown">
          ${folderMenu}
        </div>
      </summary>
      <div class="folder-children"></div>
    `;
    const children = details.querySelector(':scope > .folder-children');
    subfolders.forEach(sf=>children.appendChild(folderEl(sf, maps)));
    appendChatsWithAttachedBranches(children, chats);

    details.addEventListener('toggle', ()=> setFolderOpen(details, details.open));
    return details;
  }

      submenuExport = document.createElement('div');
    submenuExport.className='submenu submenu-export';
    submenuExport.innerHTML = `
  <button class="chat-dropdown-item" data-export="openai">Export as OpenAI-JSON</button>
  <button class="chat-dropdown-item" data-export="json">Export as JSON</button>
  <button class="chat-dropdown-item" data-export="txt">Export as TXT</button>
`;
    document.body.appendChild(submenuExport);

    submenuCompress = document.createElement('div');
    submenuCompress.className='submenu submenu-compress';
    submenuCompress.innerHTML = `
      <button class="chat-dropdown-item" data-compress="1" data-first="0" data-keep="0">Just Compact</button>
      <button class="chat-dropdown-item" data-compress="1" data-first="1" data-keep="0">Compact + first message</button>
      <button class="chat-dropdown-item" data-compress="1" data-first="1" data-keep="2">Compact + first message + 2 last raw</button>
      <button class="chat-dropdown-item" data-compress="1" data-first="1" data-keep="4">Compact + first message + 4 last raw</button>
    `;
    document.body.appendChild(submenuCompress);

    submenuRename = document.createElement('div');
    submenuRename.className='submenu submenu-rename';
    submenuRename.innerHTML = `
      <button class="chat-dropdown-item" data-rename="manual">Rename</button>
      <button class="chat-dropdown-item" data-rename="auto">Auto Rename</button>
    `;
    document.body.appendChild(submenuRename);

    submenuClone = document.createElement('div');
    submenuClone.className='submenu submenu-clone';
    submenuClone.innerHTML = `
      <button class="chat-dropdown-item" data-clone="normal">Clone</button>
      <button class="chat-dropdown-item" data-clone="attached">Clone attached</button>
    `;
    document.body.appendChild(submenuClone);


    // Template submenu (for "New → Templates" menu)
    submenuTemplate = document.createElement('div');
    submenuTemplate.className='submenu submenu-template';
    submenuTemplate.innerHTML = `
      <button class="chat-dropdown-item" data-template-action="use">Use</button>
      <button class="chat-dropdown-item" data-template-action="rename">Rename</button>
      <div class="dropdown-sep"></div>
      <button class="chat-dropdown-item" data-template-action="delete">Delete</button>
    `;
    document.body.appendChild(submenuTemplate);

  function renderSidebar(){
    chatList.innerHTML='';

    // If search is active, render a flat result list.
    const q = String(state.sidebarSearch?.q || '').trim();
    if (q){
      const results = Array.isArray(state.sidebarSearch.results) ? state.sidebarSearch.results : [];
      const folderNameById = new Map(state.folders.map(f=>[f.id, f.name]));
      const head = document.createElement('div');
      head.className = 'sidebar-search-head';
      const count = results.length;
      head.innerHTML = `<div class="sidebar-search-head-title">Search: <span class="muted">${esc(q)}</span> <span class="muted">(${count})</span></div>`;
      chatList.appendChild(head);

      if (!count){
        const m = document.createElement('div');
        m.className = 'muted';
        m.style.padding='12px 8px';
        m.textContent = 'No matches.';
        chatList.appendChild(m);
        return;
      }

      for (const r of results){
        const c = {...r};
        const fid = c.folder_id || null;
        c._folderName = fid ? (folderNameById.get(fid) || 'Folder') : 'Root';
        chatList.appendChild(chatEl(c));
      }
      return;
    }

    const maps = buildMaps();
    const rootFolders = maps.foldersByParent.get('__root__') || [];
    const rootChats = maps.chatsByFolder.get('__root__') || [];
    rootFolders.forEach(f=>chatList.appendChild(folderEl(f, maps)));
    appendChatsWithAttachedBranches(chatList, rootChats);
    const empty = $('#chat-list-empty');
    if (empty){
      empty.classList.toggle('hidden', state.chats.length>0);
      if (!state.chats.length) chatList.appendChild(empty);
    }
  }

  async function reloadSidebar(){
    const b = await api('bootstrap');
    if (b && b.logged_in===false){
      if (typeof window.llcSetAuthState==='function') window.llcSetAuthState(b.auth || {});
      if (typeof window.llcShowLogin==='function') window.llcShowLogin(b?.auth?.initial_admin_setup_required ? '' : 'Please sign in');
      return;
    }
    state.folders = b.folders||[];
    state.chats = b.chats||[];
    // Keep the open chat's folder_id in sync with the sidebar snapshot.
    // Otherwise a later saveChat() (e.g. when switching model) can overwrite a recent move.
    if (state.currentChat && state.currentChat.id != null){
      const id = String(state.currentChat.id);
      const row = (state.chats || []).find(c=>String(c.id)===id);
      if (row){
        const fid = (row.folder_id == null || row.folder_id === '') ? null : row.folder_id;
        state.currentChat.folder_id = fid;
        const cached = state.chatCache?.get?.(id);
        if (cached) cached.folder_id = fid;
      }
    }
    renderSidebar();
  }

  // Keep a renamed chat title consistent across state objects.
  // Otherwise a later saveChat() (e.g. when switching the model) can write an old title back to the DB.
  function patchChatTitle(chatId, newTitle){
    const id = String(chatId || '').trim();
    if (!id) return;
    const t = String(newTitle || '').trim();
    if (!t) return;
    const row = (state.chats || []).find(c=>String(c.id)===id);
    if (row) row.title = t;
    if (state.currentChat && String(state.currentChat.id)===id) state.currentChat.title = t;
    const cached = state.chatCache?.get?.(id);
    if (cached) cached.title = t;
  }

  // Keep a moved chat's folder_id consistent across state objects.
  // Otherwise a later saveChat() (e.g. when switching the model) can write an old folder_id back to the DB.
  function patchChatFolder(chatId, folderId){
    const id = String(chatId || '').trim();
    if (!id) return;
    const fid = (folderId == null || folderId === '') ? null : String(folderId);
    const row = (state.chats || []).find(c=>String(c.id)===id);
    if (row) row.folder_id = fid;
    if (state.currentChat && String(state.currentChat.id)===id) state.currentChat.folder_id = fid;
    const cached = state.chatCache?.get?.(id);
    if (cached) cached.folder_id = fid;
  }

  // ---------- Sidebar search ----------
  let sidebarSearchTimer = null;
  const clearSidebarSearch = ()=>{
    state.sidebarSearch.q = '';
    state.sidebarSearch.results = null;
    state.sidebarSearch.loading = false;
    if (sidebarSearch) sidebarSearch.value = '';
    sidebarSearchClear?.classList.add('hidden');
    renderSidebar();
  };

  const runSidebarSearch = async (q)=>{
    const nonce = ++state.sidebarSearch.nonce;
    state.sidebarSearch.loading = true;
    try{
      const res = await api('chat_search', { q, limit: 100 });
      if (nonce !== state.sidebarSearch.nonce) return; // stale
      state.sidebarSearch.results = res.results || [];
    }catch(err){
      if (nonce !== state.sidebarSearch.nonce) return;
      // Don't silently swallow backend errors; otherwise the UI just shows "0 results" forever.
      console.warn('Sidebar search failed', err);
      state.sidebarSearch.results = [];
    }finally{
      if (nonce !== state.sidebarSearch.nonce) return;
      state.sidebarSearch.loading = false;
      renderSidebar();
    }
  };

  const setSidebarSearch = (q)=>{
    const qq = String(q||'').trim();
    state.sidebarSearch.q = qq;
    sidebarSearchClear?.classList.toggle('hidden', !qq);
    if (!qq){
      state.sidebarSearch.results = null;
      renderSidebar();
      return;
    }
    if (sidebarSearchTimer) clearTimeout(sidebarSearchTimer);
    sidebarSearchTimer = setTimeout(()=>runSidebarSearch(qq), 250);
  };

  sidebarSearch?.addEventListener('input', ()=> setSidebarSearch(sidebarSearch.value));
  sidebarSearch?.addEventListener('keydown', (e)=>{
    if (e.key === 'Escape'){ e.preventDefault(); clearSidebarSearch(); sidebarSearch.blur(); }
    if (e.key === 'Enter'){
      // open first result
      const r = Array.isArray(state.sidebarSearch.results) ? state.sidebarSearch.results[0] : null;
      if (r?.id){ openChat(r.id); sidebarSearch.blur(); }
    }
  });
  sidebarSearchClear?.addEventListener('click', (e)=>{ e.preventDefault(); clearSidebarSearch(); sidebarSearch?.focus(); });

  // Convenience: press / to focus search (like many apps)
  document.addEventListener('keydown', (e)=>{
    if (e.key !== '/') return;
    const tag = (document.activeElement?.tagName || '').toLowerCase();
    if (tag === 'textarea' || tag === 'input') return;
    e.preventDefault();
    sidebarSearch?.focus();
  });

  function getFolderPath(fid){
    const nameById = new Map((state.folders||[]).map(f=>[String(f.id), String(f.name || 'Folder')]));
    const parentById = new Map((state.folders||[]).map(f=>[String(f.id), f.parent_id == null ? null : String(f.parent_id)]));
    const parts = [];
    let walk = fid == null ? null : String(fid);
    const seen = new Set();
    while (walk && !seen.has(walk)){
      seen.add(walk);
      parts.push(nameById.get(walk) || 'Folder');
      walk = parentById.get(walk) || null;
    }
    return parts.reverse().join(' / ');
  }

  function folderPicker(title, options, currentId){
    return new Promise(resolve=>{
      const opts = Array.isArray(options) ? options.slice() : [];
      const cur = currentId == null ? null : String(currentId);
      let activeIndex = 0;
      let selectedId = currentId == null ? null : currentId;
      let selectedKey = selectedId == null ? '__root__' : String(selectedId);

      const overlay = document.createElement('div');
      overlay.className = 'folder-picker-overlay';
      overlay.innerHTML = `
        <div class="folder-picker-panel" role="dialog" aria-modal="true" aria-label="${esc(title || 'Choose folder')}">
          <div class="folder-picker-head">
            <div class="folder-picker-title">${esc(title || 'Choose folder')}</div>
            <button class="folder-picker-close" type="button" aria-label="Close">×</button>
          </div>
          <input class="folder-picker-search" type="search" placeholder="Search folders…" autocomplete="off">
          <div class="folder-picker-list" role="listbox" aria-label="Folders"></div>
          <div class="folder-picker-foot">
            <span class="muted">↑↓ navigate · Enter move · Esc closes</span>
            <div class="folder-picker-actions">
              <button class="folder-picker-cancel" type="button">Cancel</button>
              <button class="folder-picker-apply" type="button" aria-label="Move here"><span>Move here</span></button>
            </div>
          </div>
        </div>`;
      document.body.appendChild(overlay);

      const input = overlay.querySelector('.folder-picker-search');
      const list = overlay.querySelector('.folder-picker-list');
      const applyBtn = overlay.querySelector('.folder-picker-apply');
      const close = (val)=>{
        try{ overlay.remove(); }catch(_){ }
        resolve(val);
      };
      const keyOf = (id)=> id == null ? '__root__' : String(id);
      const filtered = ()=>{
        const q = String(input?.value || '').trim().toLowerCase();
        if (!q) return opts;
        return opts.filter(o=>String(o.name || '').toLowerCase().includes(q));
      };
      const setSelected = (o)=>{
        if (!o) return;
        selectedId = (o.id === undefined || o.id === '') ? null : o.id;
        selectedKey = keyOf(selectedId);
        if (applyBtn){
          applyBtn.disabled = false;
          applyBtn.removeAttribute('disabled');
        }
      };
      const submitSelected = (ev)=>{
        ev?.preventDefault?.();
        ev?.stopPropagation?.();
        close(selectedId === undefined ? null : selectedId);
      };
      const render = ()=>{
        const rows = filtered();
        if (activeIndex >= rows.length) activeIndex = Math.max(0, rows.length - 1);
        list.innerHTML = '';
        if (!rows.length){
          const empty = document.createElement('div');
          empty.className = 'folder-picker-empty';
          empty.textContent = 'No matching folders.';
          list.appendChild(empty);
          if (applyBtn) applyBtn.disabled = true;
          return;
        }
        if (!rows.some(o=>keyOf(o.id ?? null) === selectedKey)){
          const active = rows[activeIndex] || rows[0];
          setSelected(active);
        }
        rows.forEach((o, i)=>{
          const k = keyOf(o.id ?? null);
          const isCurrent = k === cur || (cur === null && k === '__root__');
          const isSelected = k === selectedKey;
          const btn = document.createElement('button');
          btn.type = 'button';
          btn.className = 'folder-picker-option' + (i===activeIndex ? ' active' : '') + (isSelected ? ' selected' : '') + (isCurrent ? ' current' : '');
          btn.dataset.index = String(i);
          btn.setAttribute('role', 'option');
          btn.setAttribute('aria-selected', isSelected ? 'true' : 'false');
          btn.innerHTML = `<span>${esc(o.name || '(root)')}</span><small>${isSelected ? 'selected' : ''}${isSelected && isCurrent ? ' · ' : ''}${isCurrent ? 'current' : ''}</small>`;
          btn.addEventListener('mouseenter', ()=>{
            const prev = list.querySelector('.folder-picker-option.active');
            if (prev) prev.classList.remove('active');
            activeIndex = i;
            btn.classList.add('active');
          });
          btn.addEventListener('click', (ev)=>{
            ev.preventDefault();
            ev.stopPropagation();
            activeIndex = i;
            setSelected(o);
            render();
          });
          btn.addEventListener('dblclick', (ev)=>{
            ev.preventDefault();
            ev.stopPropagation();
            setSelected(o);
            submitSelected(ev);
          });
          list.appendChild(btn);
        });
        list.querySelector('.folder-picker-option.active')?.scrollIntoView({block:'nearest'});
        if (applyBtn) applyBtn.disabled = false;
      };

      overlay.addEventListener('click', (e)=>{ if (e.target === overlay) close(undefined); });
      overlay.querySelector('.folder-picker-close')?.addEventListener('click', ()=>close(undefined));
      overlay.querySelector('.folder-picker-cancel')?.addEventListener('click', ()=>close(undefined));
      applyBtn?.addEventListener('click', (e)=>submitSelected(e));
      input?.addEventListener('input', ()=>{ activeIndex = 0; render(); });
      overlay.addEventListener('keydown', (e)=>{
        const rows = filtered();
        if (e.key === 'Escape'){ e.preventDefault(); close(undefined); return; }
        if (e.key === 'ArrowDown'){
          e.preventDefault();
          activeIndex = Math.min(rows.length - 1, activeIndex + 1);
          setSelected(rows[activeIndex]);
          render();
          return;
        }
        if (e.key === 'ArrowUp'){
          e.preventDefault();
          activeIndex = Math.max(0, activeIndex - 1);
          setSelected(rows[activeIndex]);
          render();
          return;
        }
        if (e.key === 'Enter'){
          e.preventDefault();
          if (rows.length) submitSelected(e);
        }
      });
      render();
      setTimeout(()=>input?.focus(), 0);
    });
  }

  // Sidebar interactions
  let sidebarDraggingChat = false;
  let sidebarDraggingFolder = false;

  // Multi-select (Ctrl/Cmd + click, Shift + click) for moving multiple chats via drag & drop.
  const cssEsc = (s)=>{
    const t = String(s ?? '');
    return (window.CSS && CSS.escape) ? CSS.escape(t) : t.replace(/[^a-zA-Z0-9_\-]/g, '\\$&');
  };

  const syncSidebarSelectionClasses = ()=>{
    if (!chatList) return;
    const ids = state.sidebarSelection?.ids;
    $$('.chat-item', chatList).forEach(el=>{
      const id = String(el.dataset.chatId || '');
      el.classList.toggle('selected', !!(ids && ids.has(id)));
    });
  };

  const clearSidebarSelection = ()=>{
    const ids = state.sidebarSelection?.ids;
    if (ids) ids.clear();
    if (state.sidebarSelection) state.sidebarSelection.anchorId = null;
    syncSidebarSelectionClasses();
  };

  const handleSidebarSelectClick = (e, item)=>{
    const id = String(item.dataset.chatId || '');
    if (!id || !chatList) return;
    const sel = state.sidebarSelection;
    const ids = sel?.ids;
    if (!ids) return;

    const isCtrl = !!(e.ctrlKey || e.metaKey);
    const isShift = !!e.shiftKey;

    const items = $$('.chat-item', chatList).filter(el=> el && el.offsetParent !== null);
    const idx = items.indexOf(item);
    if (idx < 0) return;

    if (isShift){
      let aId = String(sel.anchorId || '');
      let aEl = aId ? chatList.querySelector(`.chat-item[data-chat-id="${cssEsc(aId)}"]`) : null;
      let aIdx = aEl ? items.indexOf(aEl) : -1;
      if (aIdx < 0) aIdx = idx;
      const lo = Math.min(aIdx, idx);
      const hi = Math.max(aIdx, idx);
      if (!isCtrl) ids.clear();
      for (let i=lo; i<=hi; i++){
        const cid = String(items[i].dataset.chatId || '');
        if (cid) ids.add(cid);
      }
      if (!sel.anchorId) sel.anchorId = id;
      syncSidebarSelectionClasses();
      return;
    }

    if (isCtrl){
      if (ids.has(id)) ids.delete(id);
      else ids.add(id);
      sel.anchorId = id;
      syncSidebarSelectionClasses();
      return;
    }
  };

  on('click', '.chat-item', async (e, item)=>{
    if (sidebarDraggingChat || sidebarDraggingFolder) return;
    if (e.target.closest('.chat-menu-btn') || e.target.closest('.chat-dropdown')) return;

    const isMulti = e.shiftKey || e.ctrlKey || e.metaKey;
    if (isMulti){
      e.preventDefault();
      handleSidebarSelectClick(e, item);
      return;
    }

    clearSidebarSelection();
    await openChat(item.dataset.chatId);
  });

  // Escape clears selection (handy when you selected a bunch accidentally)
  document.addEventListener('keydown', (e)=>{
    if (e.key !== 'Escape') return;
    const tag = (document.activeElement?.tagName || '').toLowerCase();
    if (tag === 'textarea' || tag === 'input') return;
    if (state.sidebarSelection?.ids && state.sidebarSelection.ids.size){
      clearSidebarSelection();
    }
  });
  on('click', '[data-action="chat-dropdown"]', (e, btn)=>{
    e.preventDefault(); e.stopPropagation();
    $$('.chat-dropdown').forEach(d=>d.classList.remove('show'));
    $$('.folder-dropdown').forEach(d=>d.classList.remove('show'));
    document.querySelectorAll('.submenu.show').forEach(s=>s.classList.remove('show'));
    btn.nextElementSibling.classList.toggle('show');
  });
  on('click', '[data-action="folder-dropdown"]', (e, btn)=>{
    e.preventDefault(); e.stopPropagation();
    $$('.folder-dropdown').forEach(d=>d.classList.remove('show'));
    $$('.chat-dropdown').forEach(d=>d.classList.remove('show'));
    document.querySelectorAll('.submenu.show').forEach(s=>s.classList.remove('show'));
    btn.nextElementSibling.classList.toggle('show');
  });

  // Templates menu (split "New" button)
  on('click', '#template-menu-list .tpl-item', (e, btn)=>{
    e.preventDefault(); e.stopPropagation();
    const tplId = String(btn.dataset.tplId || '');
    if (!tplId || !submenuTemplate) return;
    // Position submenu to the right of the template item.
    const rect = btn.getBoundingClientRect();
    submenuTemplate.dataset.tplId = tplId;
    submenuTemplate.style.left = Math.min(rect.right + 8, window.innerWidth - 220) + 'px';
    submenuTemplate.style.top = Math.min(rect.top - 6, window.innerHeight - 160) + 'px';
    document.querySelectorAll('.submenu.show').forEach(s=>s.classList.remove('show'));
    submenuTemplate.classList.add('show');
  });

  on('click', '.submenu-template .chat-dropdown-item', async (e, el)=>{
    e.preventDefault(); e.stopPropagation();
    const action = String(el.dataset.templateAction || '');
    const tplId = String(submenuTemplate?.dataset?.tplId || '');
    if (!action || !tplId) return;

    const getTplName = ()=> (state.templates||[]).find(t=>String(t.id)===tplId)?.name || 'Template';

    try{
      if (action==='use'){
        closeMenus();
        const r = await api('template_get', {id: tplId});
        const tpl = r.template || {};
        const payload = (tpl.payload && typeof tpl.payload === 'object') ? tpl.payload : {};
        const res = await api('chat_create', {folder_id:null});
        const newId = res.id;
        const chat = {
          id: newId,
          title: String(payload.title || tpl.name || getTplName() || 'New chat'),
          folder_id: null,
          connection_id: payload.connection_id || payload.connectionId || null,
          model: payload.model || null,
          messages: Array.isArray(payload.messages) ? payload.messages : [],
          meta: (payload.meta && typeof payload.meta==='object') ? payload.meta : {}
        };
        if (!chat.meta || typeof chat.meta !== 'object') chat.meta = {};
        if (chat.meta.params == null) chat.meta.params = {};
        state.chatCache.set(String(newId), chat);
        await saveChat(chat);
        await reloadSidebar();
        await openChat(newId);
        textarea?.focus();
        return;
      }
      if (action==='rename'){
        const current = getTplName();
        const name = prompt('Template name:', current);
        if (!name || !name.trim()) return;
        await api('template_rename', {id: tplId, name: name.trim()});
        const t = (state.templates||[]).find(x=>String(x.id)===tplId);
        if (t) t.name = name.trim();
        renderTemplatesMenu();
        return;
      }
      if (action==='delete'){
        const name = getTplName();
        if (!confirm(`Delete template "${name}"?`)) return;
        await api('template_delete', {id: tplId});
        state.templates = (state.templates||[]).filter(x=>String(x.id)!==tplId);
        renderTemplatesMenu();
        closeMenus();
        return;
      }
    } finally {
      submenuTemplate?.classList.remove('show');
    }
  });

  on('click', '.chat-dropdown .has-submenu', (e, trigger)=>{
  e.stopPropagation();
  const kind = trigger.dataset.submenu || 'export';
  const menu = (kind === 'compress') ? submenuCompress : (kind === 'rename') ? submenuRename : (kind === 'clone') ? submenuClone : submenuExport;
  if (!menu) return;
  // remember which chat this submenu belongs to (submenu lives in <body>)
  menu.dataset.chatId = trigger.closest('.chat-item')?.dataset.chatId || '';
  // hide the other submenu
  document.querySelectorAll('.submenu.show').forEach(s=>s.classList.remove('show'));
  const rect = trigger.getBoundingClientRect();
  menu.style.left = (rect.right+6)+'px';
  menu.style.top  = (rect.top-6)+'px';
  menu.classList.add('show');
});

  on('click', '.submenu [data-clone]', async (e, btn)=>{
    e.preventDefault(); e.stopPropagation();
    const mode = String(btn.dataset.clone || 'normal');
    const openDD = $('.chat-dropdown.show');
    const id = ((btn.closest('.submenu')?.dataset.chatId || '') || '').trim() || openDD?.closest('.chat-item')?.dataset.chatId;
    document.querySelectorAll('.submenu.show').forEach(s=>s.classList.remove('show'));
    $$('.chat-dropdown').forEach(d=>d.classList.remove('show'));
    if (!id) return;
    const res = await api('chat_clone', {id, attached: mode === 'attached'});
    await reloadSidebar();
    if (mode === 'attached' && res?.id) {
      try{ await openChat(res.id); }catch(_){ }
    }
  });



  on('click', '.submenu [data-export]', (e, btn)=>{
    const fmt = btn.dataset.export;
    // Prefer the stored chat id; fallback to the open dropdown if still present.
    const openDD = $('.chat-dropdown.show');
    const id = ((btn.closest('.submenu')?.dataset.chatId || '') || '').trim() || openDD?.closest('.chat-item')?.dataset.chatId;
    document.querySelectorAll('.submenu.show').forEach(s=>s.classList.remove('show'));
    $$('.chat-dropdown').forEach(d=>d.classList.remove('show'));
    if (id) window.location = `api.php?action=chat_export&id=${encodeURIComponent(id)}&format=${encodeURIComponent(fmt)}`;
  });

  on('click', '.submenu [data-rename]', async (e, btn)=>{
    const kind = String(btn.dataset.rename || '');
    const menu = btn.closest('.submenu');
    const chatId = menu?.dataset.chatId || '';
    document.querySelectorAll('.submenu.show').forEach(s=>s.classList.remove('show'));
    $$('.chat-dropdown').forEach(d=>d.classList.remove('show'));
    if (!chatId) return;

    if (kind === 'manual'){
      const cur = state.chats.find(c=>c.id===chatId)?.title || '';
      const t = prompt('Chat title:', cur);
      if(t && t.trim()){
        const nt = t.trim();
        await api('chat_rename', {id:chatId, title:nt});
        patchChatTitle(chatId, nt);
        await reloadSidebar();
      }
      return;
    }

    if (kind === 'auto'){
      jobDismissed = false;
      showJob('Auto renaming…', 'Generating title…');
      try{
        const payload = { id: chatId };
        // If the chat is currently open, pass the live selection to avoid relying on stale DB fields.
        if (state.currentChat?.id === chatId) {
          payload.connection_id = state.ui.connectionId || state.currentChat.connection_id || '';
          payload.model = state.ui.model || state.currentChat.model || '';
        }
        const r = await api('chat_auto_rename', payload);
        const nt = (r && typeof r.title === 'string') ? r.title.trim() : '';
        if (nt) patchChatTitle(chatId, nt);
        await reloadSidebar();
        if (state.currentChat?.id === chatId){
          try{ await openChat(chatId); }catch(_){ }
        }
        hideJob();
      }catch(err){
        hideJob();
        alert(String(err?.message || err || 'Error'));
      }
      return;
    }
  });

  on('click', '.submenu [data-compress]', async (e, btn)=>{
    const keep = Number(btn.dataset.keep || 0) || 0;
    const includeFirst = String(btn.dataset.first ?? '1') !== '0';
    const menu = btn.closest('.submenu');
    const chatId = menu?.dataset.chatId || '';
    document.querySelectorAll('.submenu.show').forEach(s=>s.classList.remove('show'));
    $$('.chat-dropdown').forEach(d=>d.classList.remove('show'));
    if (!chatId) return;

    const choice = prompt(
      'Choose compression length:\n'
      + '1. 300 words\n'
      + '2. 500-1000 words\n'
      + '3. 1000-2000 words\n'
      + '4. 2000-3500 words\n\n'
      + 'Enter 1, 2, 3, or 4:',
      '1'
    );
    if (choice === null) return;
    const storyOptRaw = String(choice || '').trim();
    const storyOpt = (storyOptRaw==='1' || storyOptRaw==='2' || storyOptRaw==='3' || storyOptRaw==='4') ? storyOptRaw : '1';

    jobDismissed = false;
    showJob('Compressing & cloning…', 'Starting…');

    let qs = `api.php?action=chat_compress_clone_sse&id=${encodeURIComponent(chatId)}&keep=${encodeURIComponent(String(keep))}&include_first=${encodeURIComponent(includeFirst?'1':'0')}&story_words=${encodeURIComponent(storyOpt)}`;
    // If the chat is currently open, pass the live selection to avoid relying on stale DB fields.
    if (state.currentChat?.id === chatId) {
      const cid = state.ui.connectionId || state.currentChat.connection_id || '';
      const mid = state.ui.model || state.currentChat.model || '';
      if (cid) qs += `&connection_id=${encodeURIComponent(cid)}`;
      if (mid) qs += `&model=${encodeURIComponent(mid)}`;
    }
    let newChatId = null;
    let closed = false;
    const es = new EventSource(qs);

    const close = ()=>{
      if (closed) return;
      closed = true;
      try{ es.close(); }catch(_){ }
    };

    es.onmessage = (ev)=>{
      let obj = null;
      try{ obj = JSON.parse(ev.data); }catch(_){ return; }
      const t = obj?.type;
      if (!t || t==='ping') return;

      if (t==='status'){
        const msg = String(obj.message || obj.status || '');
        showJob('Compressing & cloning…', msg || 'Working…');
        return;
      }
      if (t==='result'){
        newChatId = String(obj.id || '');
        return;
      }
      if (t==='error'){
        close();
        hideJob();
        alert(String(obj.error || 'Error'));
        return;
      }
      if (t==='done'){
        close();
        (async()=>{
          try{ await reloadSidebar(); }catch(_){ }
          if (newChatId) {
            try{ await openChat(newChatId); }catch(_){ }
          }
          hideJob();
        })();
      }
    };

    es.onerror = ()=>{
      // Connection dropped (proxy timeout / network hiccup). The backend may still finish.
      close();
      hideJob();
      (async()=>{ try{ await reloadSidebar(); }catch(_){ } })();
      alert('Connection dropped while compressing. The clone may still have been created — check the sidebar for a new compact chat.');
    };
  });


  on('click', '.chat-dropdown .chat-dropdown-item', async (e, el)=>{
    const cmd = el.dataset.cmd;
    if(!cmd) return;
    const id = el.closest('.chat-item')?.dataset.chatId;
    el.closest('.chat-dropdown')?.classList.remove('show');
    document.querySelectorAll('.submenu.show').forEach(s=>s.classList.remove('show'));
    if (!id) return;

    if (cmd==='rename'){
      const cur = state.chats.find(c=>c.id===id)?.title || '';
      const t = prompt('Chat title:', cur);
      if(t && t.trim()){
        const nt = t.trim();
        await api('chat_rename', {id, title:nt});
        patchChatTitle(id, nt);
        await reloadSidebar();
      }
    }
    if (cmd==='clone'){ await api('chat_clone', {id, attached:false}); await reloadSidebar(); }
    if (cmd==='save-template'){
      // Build template payload from full chat (incl. system prompt & advanced params)
      let chat = null;
      if (state.currentChat?.id === id){
        persistUiToChatMeta();
        chat = state.currentChat;
      } else {
        const r = await api('chat_get', {id});
        chat = r.chat;
      }
      if (!chat) return;
      const defaultName = String(chat.title || 'Template').trim() || 'Template';
      const name = prompt('Template name:', defaultName);
      if (!name || !name.trim()) return;
      const payload = {
        title: String(chat.title || ''),
        connection_id: chat.connection_id || null,
        model: chat.model || null,
        messages: Array.isArray(chat.messages) ? chat.messages : [],
        meta: (chat.meta && typeof chat.meta === 'object') ? chat.meta : {}
      };
      await api('template_create', {name: name.trim(), payload});
      await reloadTemplates();
      closeMenus();
      return;
    }
    if (cmd==='delete'){
      if(!confirm('Delete chat?')) return;
      await api('chat_delete', {id});
      if (state.currentChat?.id===id) state.currentChat=null;
      await init(); // refresh everything
    }
    if (cmd==='move'){
      const curFolderId = state.chats.find(c=>String(c.id)===String(id))?.folder_id || null;
      const opts = [{id:null, name:'(root)'}]
        .concat((state.folders||[])
          .map(f=>({id:f.id, name:getFolderPath(f.id)}))
          .sort((a,b)=>String(a.name).localeCompare(String(b.name))));
      const newFolderId = await folderPicker('Move chat to…', opts, curFolderId);
      if (newFolderId === undefined) return;
      try {
        await api('chat_move', {id, folder_id: newFolderId});
        patchChatFolder(id, newFolderId);
        await reloadSidebar();
      } catch (err) {
        console.error('Move chat failed', err);
        alert('Move failed: ' + (err?.message || err));
      }
    }
    if (cmd==='archive'){
      try {
        const r = await api('chat_archive', {id});
        const archiveId = String(r?.archive_id || '').trim();
        if (archiveId) patchChatFolder(id, archiveId);
        await reloadSidebar();
      } catch (err) {
        console.error('Archive chat failed', err);
        alert('Archive failed: ' + (err?.message || err));
      }
    }
    if (cmd==='detach'){
      await api('chat_detach', {id});
      if (state.currentChat?.id === id && state.currentChat.meta && typeof state.currentChat.meta === 'object') {
        delete state.currentChat.meta.clone;
      }
      await reloadSidebar();
    }
  });

  on('click', '.folder-dropdown .folder-dropdown-item', async (e, el)=>{
    const cmd = el.dataset.cmd;
    const folderId = el.closest('.folder')?.dataset.folderId;
    el.closest('.folder-dropdown')?.classList.remove('show');
    if(!cmd || !folderId) return;

    if(cmd==='rename'){
      const cur = state.folders.find(f=>f.id===folderId)?.name || '';
      const name = prompt('Folder name:', cur);
      if(name && name.trim()){ await api('folder_rename', {id:folderId, name:name.trim()}); await reloadSidebar(); }
    }
    if(cmd==='new-subfolder'){
      const name = prompt('Subfolder name:','Subfolder');
      if(!name||!name.trim()) return;
      await api('folder_create', {name:name.trim(), parent_id:folderId});
      await reloadSidebar();
    }
    if (cmd==='move'){
      // Build a list of legal parent folders: root + all folders except self and its descendants.
      const childrenByParent = new Map();
      state.folders.forEach(ff=>{
        const p = ff.parent_id || '__root__';
        if (!childrenByParent.has(p)) childrenByParent.set(p, []);
        childrenByParent.get(p).push(ff);
      });
      const descendants = new Set();
      const stack = [folderId];
      while (stack.length){
        const cur = stack.pop();
        const kids = childrenByParent.get(cur) || [];
        for (const k of kids){
          if (!k || !k.id || descendants.has(k.id)) continue;
          descendants.add(k.id);
          stack.push(k.id);
        }
      }

      const curParentId = state.folders.find(ff=>String(ff.id)===String(folderId))?.parent_id || null;
      const opts = [{id:null, name:'(root)'}]
        .concat((state.folders||[])
          .filter(ff=>String(ff.id)!==String(folderId) && !descendants.has(ff.id))
          .map(ff=>({id:ff.id, name:getFolderPath(ff.id)}))
          .sort((a,b)=>String(a.name).localeCompare(String(b.name))));

      const parentId = await folderPicker('Move folder to parent…', opts, curParentId);
      if (parentId === undefined) return;
      try {
        await api('folder_move', {id:folderId, parent_id: parentId});
        await reloadSidebar();
      } catch (err) {
        console.error('Move folder failed', err);
        alert('Move failed: ' + (err?.message || err));
      }
    }
    if(cmd==='archive'){
      try {
        await api('folder_archive', {id:folderId});
        await reloadSidebar();
      } catch (err) {
        console.error('Archive folder failed', err);
        alert('Archive failed: ' + (err?.message || err));
      }
      return;
    }
    if(cmd==='export'){
      // Collect this folder + all descendant folder ids.
      const childrenByParent = new Map();
      (state.folders||[]).forEach(ff=>{
        const p = ff.parent_id || '__root__';
        if (!childrenByParent.has(p)) childrenByParent.set(p, []);
        childrenByParent.get(p).push(ff);
      });
      const folderIds = new Set([folderId]);
      const stack = [folderId];
      while (stack.length){
        const cur = stack.pop();
        const kids = childrenByParent.get(cur) || [];
        for (const k of kids){
          if (!k || !k.id || folderIds.has(k.id)) continue;
          folderIds.add(k.id);
          stack.push(k.id);
        }
      }

      const n = (state.chats||[]).filter(c=>folderIds.has(String(c.folder_id||''))).length;
      if (n <= 0){ alert('No chats to export.'); return; }

      const folderName = state.folders.find(f=>f.id===folderId)?.name || 'Folder';
      const ok = confirm(`Export ${n} Chats from Folder "${folderName}" as ZIP? (Can take a while depending on the amount)`);
      if (!ok) return;

      const choice = prompt('Export format?\n\n1. OpenAI-JSON\n2. JSON\n3. TXT', '2');
      const c = String(choice||'').trim();
      const fmt = (c==='1') ? 'openai' : (c==='3' ? 'txt' : 'json');
      closeMenus();
      window.location = `api.php?action=folder_export&id=${encodeURIComponent(folderId)}&format=${encodeURIComponent(fmt)}`;
      return;
    }
    if(cmd==='collapse-all'){
      const root = el.closest('.folder');
      if (root) collapseFolderTree(root);
    }
    if(cmd==='delete'){
      const folderName = state.folders.find(f=>f.id===folderId)?.name || 'Folder';
      const choice = prompt(
        `Delete folder: ${folderName}\n\n`+
        `1) Move chats to root\n`+
        `2) Delete all chats in the folder (incl. subfolders)\n\n`+
        `Type 1 or 2:`,
        '1'
      );
      const c = String(choice||'').trim();
      if (!c) return;
      if (c === '2'){
        if(!confirm('Really delete ALL chats in this folder (including subfolders)?')) return;
        await api('folder_delete', {id:folderId, mode:'delete_chats'});
      } else {
        if(!confirm('Delete the folder and move chats to root?')) return;
        await api('folder_delete', {id:folderId, mode:'move_to_root'});
      }
      await init();
    }
  });

  newFolderBtn?.addEventListener('click', async ()=>{
    const name = prompt('Folder name:','New Folder');
    if(!name||!name.trim()) return;
    await api('folder_create', {name:name.trim(), parent_id:null});
    await reloadSidebar();
  });

  newChatDdBtn?.addEventListener('click', (e)=>{
    e.preventDefault();
    e.stopPropagation();
    if (!newChatMenu) return;
    const willShow = !newChatMenu.classList.contains('show');
    closeMenus();
    if (willShow){
      renderTemplatesMenu();
      newChatMenu.classList.add('show');
      newChatDdBtn.setAttribute('aria-expanded','true');
    } else {
      newChatMenu.classList.remove('show');
      newChatDdBtn.setAttribute('aria-expanded','false');
    }
  });

  newChatBtn?.addEventListener('click', async ()=>{
    const res = await api('chat_create', {folder_id:null});
    await reloadSidebar();
    await openChat(res.id);
    textarea.focus();
  });

  // ---------- Drag & drop import into sidebar ----------
  // Also supports moving chats between folders (drag a chat onto a folder / empty root area).
  const CHAT_DRAG_TYPE = 'application/x-llc-chat-id';
  const CHAT_DRAG_MULTI_TYPE = 'application/x-llc-chat-ids';
  const FOLDER_DRAG_TYPE = 'application/x-llc-folder-id';

  on('dragstart', '.chat-item', (e, item)=>{
    try{
      const id = String(item.dataset.chatId || '').trim();
      if (!id || !e.dataTransfer) return;

      const sel = state.sidebarSelection?.ids;

      // Prefer DOM "selected" state (what the user sees) and union it with the stored selection.
      const domSelIds = (()=>{
        try{
          if (!chatList) return [];
          return $$(".chat-item.selected", chatList)
            .map(el=> String(el.dataset.chatId || '').trim())
            .filter(Boolean);
        }catch(_){ return []; }
      })();

      const draggedIsSelected = item.classList.contains('selected') || !!(sel && sel.has(id));

      // If the user drags an unselected chat while a selection exists, treat it as a new selection.
      if (!draggedIsSelected && sel && sel.size){
        sel.clear();
        sel.add(id);
        if (state.sidebarSelection) state.sidebarSelection.anchorId = id;
        try{ syncSidebarSelectionClasses(); }catch(_){/* noop */}
      }

      // Determine drag payload: if dragging a selected item, drag the full selection (including the active chat).
      let ids = [id];
      if (draggedIsSelected){
        const pool = domSelIds.concat(sel ? Array.from(sel) : []);
        const uniq = Array.from(new Set(pool.map(x=>String(x||'').trim()).filter(Boolean)));
        if (uniq.length > 1) ids = uniq;
      }

      sidebarDraggingChat = true;
      e.dataTransfer.effectAllowed = 'move';
      if (ids.length > 1){
        e.dataTransfer.setData(CHAT_DRAG_MULTI_TYPE, JSON.stringify(ids));
      }
      e.dataTransfer.setData(CHAT_DRAG_TYPE, id);
      // Fallback for some browsers.
      // Some engines don't reliably expose custom MIME types in `dataTransfer.types` on drop,
      // so we also encode multi-drag in text/plain.
      if (ids.length > 1){
        e.dataTransfer.setData('text/plain', `llc-chat-ids:${ids.join(',')}`);
      } else {
        e.dataTransfer.setData('text/plain', id);
      }

      // Visual: mark all dragged items
      try{
        for (const cid of ids){
          const el = chatList?.querySelector?.(`.chat-item[data-chat-id="${cssEsc(cid)}"]`);
          if (el) el.classList.add('dragging');
        }
      }catch(_){
        item.classList.add('dragging');
      }
    }catch(_){/* noop */}
  });

  // Move folders by drag & drop (drop onto another folder or the root list area).
  on('dragstart', '.folder-header', (e, header)=>{
    try{
      if (header.querySelector('.folder-menu-btn') && e.target && e.target.closest('.folder-menu-btn')) return;
      const folder = header.closest('.folder');
      if (folder?.dataset?.archive === '1') {
        e.preventDefault();
        return;
      }
      const id = folder?.dataset?.folderId || '';
      if (!id || !e.dataTransfer) return;
      sidebarDraggingFolder = true;
      e.dataTransfer.effectAllowed = 'move';
      e.dataTransfer.setData(FOLDER_DRAG_TYPE, id);
      e.dataTransfer.setData('text/plain', id);
      header.classList.add('dragging');
    }catch(_){/* noop */}
  });

  on('dragend', '.folder-header', (_e, header)=>{
    sidebarDraggingFolder = false;
    header.classList.remove('dragging');
    clearDropHighlight();
  });

  on('dragend', '.chat-item', (_e, _item)=>{
    sidebarDraggingChat = false;
    try{ $$('.chat-item.dragging', chatList || document).forEach(el=>el.classList.remove('dragging')); }catch(_){/* noop */}
    clearDropHighlight();
  });

  // Drop one or multiple exported chat JSON files onto the chat list (root)
  // or onto a folder to import directly into that folder.
  let dragHoverEl = null;
  const clearDropHighlight = ()=>{
    chatList?.classList?.remove('dragover');
    if (dragHoverEl) dragHoverEl.classList.remove('drop-target');
    dragHoverEl = null;
  };

  const folderFromEvent = (e)=>{
    const el = e.target?.closest?.('.folder');
    const fid = el?.dataset?.folderId || null;
    return fid;
  };

  chatList?.addEventListener('dragover', (e)=>{
    if (!e.dataTransfer) return;
    const types = Array.from(e.dataTransfer.types||[]);
    const isFiles = types.includes('Files');
    const isChatMove = sidebarDraggingChat || types.includes(CHAT_DRAG_TYPE) || types.includes(CHAT_DRAG_MULTI_TYPE);
    const isFolderMove = sidebarDraggingFolder || types.includes(FOLDER_DRAG_TYPE);
    if (!isFiles && !isChatMove && !isFolderMove) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = isFiles ? 'copy' : 'move';

    chatList.classList.add('dragover');
    const folderEl = e.target?.closest?.('.folder');
    if (dragHoverEl && dragHoverEl !== folderEl) dragHoverEl.classList.remove('drop-target');
    dragHoverEl = folderEl || null;
    if (dragHoverEl) dragHoverEl.classList.add('drop-target');
  });

  chatList?.addEventListener('dragleave', (e)=>{
    // Only clear if we actually leave the chat list region.
    if (e.relatedTarget && chatList.contains(e.relatedTarget)) return;
    clearDropHighlight();
  });

  chatList?.addEventListener('drop', async (e)=>{
    if (!e.dataTransfer) return;
    const types = Array.from(e.dataTransfer.types||[]);
    const isFiles = types.includes('Files');
    const isChatMove = sidebarDraggingChat || types.includes(CHAT_DRAG_TYPE) || types.includes(CHAT_DRAG_MULTI_TYPE);
    const isFolderMove = sidebarDraggingFolder || types.includes(FOLDER_DRAG_TYPE);
    if (!isFiles && !isChatMove && !isFolderMove) return;
    e.preventDefault();
    const folderId = folderFromEvent(e);
    clearDropHighlight();
    if (isFiles){
      const files = e.dataTransfer.files;
      if (!files || !files.length) return;
      await importJsonFiles(files, folderId);
      return;
    }

    // Move folder
    if (isFolderMove){
      const movingId = (e.dataTransfer.getData(FOLDER_DRAG_TYPE) || e.dataTransfer.getData('text/plain') || '').trim();
      if (!movingId) return;
      // Dropping onto itself should do nothing.
      if (folderId && String(folderId) === String(movingId)) return;
      try{
        await api('folder_move', { id: movingId, parent_id: folderId });
        await reloadSidebar();
      }catch(err){
        try{ await reloadSidebar(); }catch(_){/* noop */}
        alert(String(err?.message || err || 'Move failed'));
      }
      return;
    }

    // Move chat(s)
    let chatIds = [];
    // 1) Prefer explicit multi payload if present.
    try{
      const raw = (e.dataTransfer.getData(CHAT_DRAG_MULTI_TYPE) || '').trim();
      const arr = raw ? JSON.parse(raw) : [];
      if (Array.isArray(arr) && arr.length) chatIds = arr;
    }catch(_){ /* noop */ }

    // 2) Fallback: multi encoded in text/plain (some browsers hide custom types).
    if (!chatIds.length){
      const t = (e.dataTransfer.getData('text/plain') || '').trim();
      if (t.startsWith('llc-chat-ids:')){
        chatIds = t.slice('llc-chat-ids:'.length).split(',').map(s=>s.trim()).filter(Boolean);
      }
    }
    chatIds = (Array.isArray(chatIds) ? chatIds : []).map(x=>String(x||'').trim()).filter(Boolean);
    if (!chatIds.length){
      const one = (e.dataTransfer.getData(CHAT_DRAG_TYPE) || e.dataTransfer.getData('text/plain') || '').trim();
      if (one) chatIds = [one];
    }
    if (!chatIds.length) return;

    try{
      const failed = [];
      for (const cid of chatIds){
        try{
          await api('chat_move', { id: cid, folder_id: folderId });
          patchChatFolder(cid, folderId);
        }catch(_e){
          failed.push(cid);
        }
      }
      try{ clearSidebarSelection(); }catch(_){/* noop */}
      await reloadSidebar();
      if (failed.length){
        alert(`Move failed for ${failed.length} chat(s).`);
      }
    }catch(err){
      // If move fails, just refresh sidebar to avoid stale UI.
      try{ await reloadSidebar(); }catch(_){/* noop */}
      alert(String(err?.message || err || 'Move failed'));
    }
  });

  // ---------- Chat rendering ----------
  const approxTokens = (t)=>{
    const s = String(t ?? '');
    if (!s.trim()) return 0;
    return Math.max(1, Math.ceil(s.length / 4));
  };

// ---------- Minimal Mermaid (flowchart) -> inline SVG renderer (client-side, no deps) ----------
/*
  Goal: "good enough" flowchart subset that LLMs often output.
  Supported:
  - graph/flowchart TB/TD/LR/RL
  - edges: -->, -.->, ==>
  - optional edge labels: -->|label|
  - nodes: A[txt], B{txt}, C(txt), plus optional :::class suffix (ignored)
  - ignores directives: classDef/class/style/linkStyle/subgraph/end/click + init blocks
  Render: inline SVG (no external libs). Layout is a simple layered layout (DAG-ish) with back-edge routing.
*/

const __mmdTextMeasurer = (() => {
  const c = document.createElement('canvas');
  const ctx = c.getContext('2d');
  // Keep this in sync with CSS (svg.mmd .mmd-label)
  ctx.font = '600 14px system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif';
  const ctxSmall = c.getContext('2d'); // same canvas, different font set on demand
  return {
    measure: (s, font) => {
      try{
        if(font) ctx.font = font;
        const w = ctx.measureText(String(s||'')).width || 0;
        return w;
      }catch(_){
        return (String(s||'').length || 0) * 7;
      }
    }
  };
})();

function mermaidToSvg(src){
  const raw = String(src||'');
  // detect diagram type (minimal subset)
  const first = raw.replace(/\r\n/g,'\n')
    .split('\n')
    .map(l=>l.trim())
    .find(l=>l && !l.startsWith('%%')) || '';

  if(/^pie\b/i.test(first)){
    const pie = parseMermaidPie(raw);
    if(!pie || !pie.items || pie.items.length===0) throw new Error('empty');
    return renderPieSvg(pie);
  }

  const parsed = parseMermaidFlowchart(raw);
  if(!parsed || !parsed.nodes || parsed.nodes.size===0) throw new Error('empty');
  const laid = layoutFlowchart(parsed);
  return renderFlowchartSvg(laid);
}

function escSvg(s){
  return String(s ?? '')
    .replace(/&/g,'&amp;')
    .replace(/</g,'&lt;')
    .replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;')
    .replace(/'/g,'&#39;');
}

function splitStatements(line){
  const out = [];
  let cur = '';
  let q = null;
  for(let i=0;i<line.length;i++){
    const ch = line[i];
    if(q){
      cur += ch;
      if(ch === q && line[i-1] !== '\\') q = null;
      continue;
    }
    if(ch === '"' || ch === "'"){ q = ch; cur += ch; continue; }
    if(ch === ';'){
      if(cur.trim()) out.push(cur.trim());
      cur = '';
      continue;
    }
    cur += ch;
  }
  if(cur.trim()) out.push(cur.trim());
  return out;
}


// -------- Mermaid (minimal subset) PIE -> inline SVG (client-side, no deps) --------
function parseMermaidPie(src){
  const raw = String(src||'').replace(/\r\n/g,'\n');
  const lines = raw.split('\n');
  let headerIdx = -1;
  for(let i=0;i<lines.length;i++){
    const t = lines[i].trim();
    if(!t || t.startsWith('%%')) continue;
    headerIdx = i; break;
  }
  if(headerIdx < 0) return null;
  const head = lines[headerIdx].trim();
  if(!/^pie\b/i.test(head)) return null;

  let title = '';
  let showData = false;
  const toks = head.split(/\s+/).filter(Boolean);
  for(let i=1;i<toks.length;i++){
    const tk = toks[i].toLowerCase();
    if(tk === 'showdata') showData = true;
    if(tk === 'title'){
      title = toks.slice(i+1).join(' ');
      break;
    }
  }

  const items = [];
  for(let i=headerIdx+1;i<lines.length;i++){
    let t = lines[i].trim();
    if(!t || t.startsWith('%%')) continue;
    if(/^(?:classDef|class|style|linkStyle|subgraph|end|click)\b/i.test(t)) continue;
    if(t.endsWith(';')) t = t.slice(0,-1).trim();

    // "Label" : 45   OR  Label : 45
    let m = t.match(/^"([^"]+)"\s*:\s*([-+]?\d+(?:\.\d+)?)\s*$/);
    if(!m) m = t.match(/^([^":]+?)\s*:\s*([-+]?\d+(?:\.\d+)?)\s*$/);
    if(!m) continue;

    const label = String(m[1]).trim();
    const val = Number(m[2]);
    if(!Number.isFinite(val)) continue;
    items.push({ label, value: val });
  }

  return { type:'pie', title, showData, items };
}

function renderPieSvg(pie){
  const items = (pie?.items || []).filter(it => Number.isFinite(it.value) && it.value > 0);
  if(items.length === 0) throw new Error('empty');

  const sum = items.reduce((a,b)=>a + b.value, 0);
  const title = String(pie?.title || '').trim();

  // Dark-ish palette (works on dark background)
  const palette = [
    '#14090c', '#4a1233', '#2f4650', '#4b331e', '#203244', '#4a245c',
    '#1b4f72', '#7d6608', '#6e2c00', '#196f3d'
  ];

  const titleFont = '700 34px system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif';
  const legendFont = '600 18px system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif';
  const pctFont    = '700 20px system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif';

  const pad = 26;
  const r = 200;
  const box = 16;
  const gap = 10;
  const rowH = 26;
  const titleH = title ? 54 : 18;

  const normLabel = (s)=> String(s||'')
    .replace(/<br\s*\/?\s*>/gi,' ')
    .replace(/\s+/g,' ')
    .trim();

  let maxLegendW = 0;
  for(const it of items){
    const w = __mmdTextMeasurer.measure(normLabel(it.label), legendFont);
    maxLegendW = Math.max(maxLegendW, w);
  }

  const legendW = (maxLegendW > 0 ? (box + gap + maxLegendW) : 0);
  const legendSpace = legendW ? (40 + legendW) : 0;

  const vbW = Math.ceil(pad*2 + r*2 + legendSpace);
  const vbH = Math.ceil(pad*2 + titleH + r*2);

  const cx = pad + r;
  const cy = pad + titleH + r;
  const legendX = cx + r + 40;
  const legendY0 = cy - ((items.length-1) * rowH)/2;

  let ang = -Math.PI/2;
  const slices = items.map((it,i)=>{
    const frac = it.value / sum;
    const a0 = ang;
    const a1 = ang + frac * Math.PI * 2;
    ang = a1;

    const x0 = cx + r * Math.cos(a0);
    const y0 = cy + r * Math.sin(a0);
    const x1 = cx + r * Math.cos(a1);
    const y1 = cy + r * Math.sin(a1);
    const large = (a1 - a0) > Math.PI ? 1 : 0;
    const d = `M ${cx} ${cy} L ${x0} ${y0} A ${r} ${r} 0 ${large} 1 ${x1} ${y1} Z`;
    const col = palette[i % palette.length];

    // percentage label
    const mid = (a0 + a1) / 2;
    const tx = cx + (r * 0.67) * Math.cos(mid);
    const ty = cy + (r * 0.67) * Math.sin(mid);
    const pct = Math.round(frac * 100);
    const pctText = pct ? (pct + '%') : '';

    return (
      `<path class="mmd-pie-slice" d="${d}" fill="${col}" stroke="rgba(0,0,0,.65)" stroke-width="2"></path>` +
      (pctText ? `<text class="mmd-pie-percent" x="${tx}" y="${ty}" text-anchor="middle" dominant-baseline="central">${escSvg(pctText)}</text>` : '')
    );
  }).join('');

  const titleSvg = title
    ? `<text class="mmd-pie-title" x="${vbW/2}" y="${pad + 18}" text-anchor="middle" dominant-baseline="central">${escSvg(title)}</text>`
    : '';

  const legendSvg = legendW ? (
    '<g class="mmd-pie-legend">' +
    items.map((it,i)=>{
      const y = legendY0 + i*rowH;
      const col = palette[i % palette.length];
      const lab = normLabel(it.label);
      return (
        `<rect class="mmd-pie-legend-swatch" x="${legendX}" y="${y - box/2}" width="${box}" height="${box}" rx="2" ry="2" fill="${col}" stroke="rgba(0,0,0,.65)" stroke-width="1"></rect>` +
        `<text class="mmd-pie-legend-text" x="${legendX + box + gap}" y="${y}" dominant-baseline="central">${escSvg(lab)}</text>`
      );
    }).join('') +
    '</g>'
  ) : '';

  const svg =
`<svg class="mmd mmd-pie" xmlns="http://www.w3.org/2000/svg"
  width="${vbW}" height="${vbH}"
  data-vbw="${vbW}" data-vbh="${vbH}"
  viewBox="0 0 ${vbW} ${vbH}"
  preserveAspectRatio="xMidYMid meet" role="img" aria-label="Pie chart">
  <style>
    .mmd-pie-title{font: ${titleFont};}
    .mmd-pie-percent{font: ${pctFont};}
    .mmd-pie-legend-text{font: ${legendFont};}
  </style>
  ${titleSvg}
  ${slices}
  ${legendSvg}
</svg>`;

  return svg;
}

function parseMermaidFlowchart(src){
  const raw = String(src||'').replace(/\r\n/g,'\n');
  const lines0 = raw.split('\n');

  let dir = 'TB';
  const nodes = new Map(); // id -> {id,label,shape,_order}
  const edges = [];
  const order = [];

  const ops = ['-.->','-->','==>'];
  let lastId = null; // continuation lines like "--> B" use the previous endpoint

  const normId = (id)=> String(id||'').trim();

  const autoNodeIdFromLabel = (label)=>{
    const s = String(label||'').trim();
    // FNV-1a 32-bit hash (stable id for "loose" labels like: Nicht schwanger)
    let h = 2166136261;
    for(let i=0;i<s.length;i++){
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    const hex = (h >>> 0).toString(16);
    let slug = s.toLowerCase()
      .replace(/<br\s*\/?>/gi,' ')
      .replace(/[^a-z0-9]+/g,'_')
      .replace(/^_+|_+$/g,'')
      .slice(0,24);
    if(!slug) slug = 'n';
    return slug + '_' + hex;
  };


  const remember = (id)=>{
    if(!nodes.has(id)) order.push(id);
  };

  const cleanEndpoint = (s)=>{
    // remove class suffixes like :::foo
    return String(s||'').trim().replace(/:::\s*[A-Za-z0-9_\-:]+(\s+:::\s*[A-Za-z0-9_\-:]+)*\s*$/,'').trim();
  };

  const stripOuterParens = (s)=>{
    s = String(s||'').trim();
    if(s.startsWith('(') && s.endsWith(')') && !s.includes('[') && !s.includes('{')){
      return s.slice(1,-1).trim();
    }
    return s;
  };

  const upsertNode = (id, label, shape)=>{
    id = normId(id);
    if(!id) return null;
    remember(id);
    const prev = nodes.get(id) || { id, label:id, shape:'rect', _order: order.length-1 };
    const next = { ...prev };
    if(label != null){
      let t = String(label).trim();
      if((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))){
        t = t.slice(1,-1);
      }
      next.label = t;
    }
    if(shape) next.shape = shape;
    next._order = prev._order;
    nodes.set(id, next);
    return next;
  };

  const parseEndpoint = (s)=>{
    s = cleanEndpoint(stripOuterParens(s));
    if(!s) return null;

    const idm = s.match(/^([A-Za-z0-9_:\-]+)\s*(.*)$/);
    if(!idm) return null;
    const id = idm[1];
    let rest = (idm[2]||'').trim();
    if(!rest){
      return upsertNode(id, nodes.get(id)?.label ?? id, nodes.get(id)?.shape ?? 'rect');
    }

    const first = rest[0];
    let close = '';
    let shape = 'rect';
    if(first==='['){ close = ']'; shape='rect'; }
    else if(first==='{'){ close = '}'; shape='diamond'; }
    else if(first==='('){ close = ')'; shape='round'; }
    else{
      // Heuristic (LLM-friendly): treat multi-word bare endpoints like "Nicht schwanger" as a single node label.
      const fullLabel = (id + ' ' + rest).trim();
      const autoId = autoNodeIdFromLabel(fullLabel);
      return upsertNode(autoId, fullLabel, nodes.get(autoId)?.shape ?? 'rect');
    }

    let label = '';
    let q = null;
    for(let i=1;i<rest.length;i++){
      const ch = rest[i];
      if(q){
        label += ch;
        if(ch === q && rest[i-1] !== '\\') q = null;
        continue;
      }
      if(ch === '"' || ch === "'"){ q = ch; label += ch; continue; }
      if(ch === close){
        let full = label.trim();
        const tail = String(rest.slice(i+1) || '').trim();
        if(tail){
          // Common LLM mistake: E[Title]<br>More text (outside brackets). Treat as part of the label.
          if(/^<br\s*\/?>/i.test(tail)){
            const more = tail.replace(/<br\s*\/?>/gi, '\n').trim();
            if(more) full = (full ? (full + '\n' + more) : more);
          }
        }
        return upsertNode(id, full, shape);
      }
      label += ch;
    }

    return upsertNode(id, nodes.get(id)?.label ?? id, nodes.get(id)?.shape ?? 'rect');
  };

  const findEdgeOp = (line, startAt=0)=>{
    // find -->, -.->, ==> outside quotes/brackets
    let q=null;
    let depth=0;
    for(let i=startAt;i<line.length;i++){
      const ch=line[i];
      if(q){
        if(ch===q && line[i-1]!=='\\') q=null;
        continue;
      }
      if(ch==='"' || ch==="'"){ q=ch; continue; }
      if(ch==='['||ch==='{'||ch==='(') depth++;
      if(ch===']'||ch==='}'||ch===')') depth=Math.max(0,depth-1);
      if(depth) continue;
      for(const op of ops){
        if(line.startsWith(op,i)) return { i, op };
      }
    }
    return null;
  };

  const splitEndpointToken = (s)=>{
    // returns { token, rest } where rest begins with the next edge op (or empty)
    let q=null;
    let depth=0;
    for(let i=0;i<s.length;i++){
      const ch=s[i];
      if(q){
        if(ch===q && s[i-1]!=='\\') q=null;
        continue;
      }
      if(ch==='"' || ch==="'"){ q=ch; continue; }
      if(ch==='['||ch==='{'||ch==='(') depth++;
      if(ch===']'||ch==='}'||ch===')') depth=Math.max(0,depth-1);
      if(depth) continue;
      for(const op of ops){
        if(s.startsWith(op,i)){
          return { token: s.slice(0,i).trim(), rest: s.slice(i).trim() };
        }
      }
    }
    return { token: s.trim(), rest: '' };
  };

  const parseEdgeChain = (stmt)=>{
    const src = String(stmt||'');
    const hit0 = findEdgeOp(src, 0);
    if(!hit0) return false;

    let s = src.trim();
    let fromId = null;
    let chainPreLabel = null; // supports: A -- "label" --> B and continuation lines

    // Continuation line? (starts with an op)
    let startsWithOp = false;
    for(const op of ops){
      if(s.startsWith(op)) { startsWithOp = true; break; }
    }

    if(startsWithOp){
      if(!lastId) return true; // can't attach; treat as handled
      fromId = lastId;
    }else{
      const hit = findEdgeOp(s, 0);
      let leftTok = s.slice(0, hit.i).trim();

      // Support Mermaid-style edge labels before the arrow:
      //   A -- "label" --> B
      //   -- "label" --> B   (continuation from previous node)
      // We treat the label as the label for the following arrow op.
      let preLabel = null;
      let endpointTok = leftTok;

      const pre = leftTok.match(/^(.*?)(?:\s+|^)--\s*(?:(?:"([^"]*)")|(?:'([^']*)')|([^]*?))\s*$/);
      if(pre){
        endpointTok = String(pre[1]||'').trim();
        preLabel = String(pre[2]||pre[3]||pre[4]||'').trim();
      }

      if(endpointTok){
        const a = parseEndpoint(endpointTok);
        if(a) fromId = a.id;
      }else{
        if(lastId) fromId = lastId; // continuation
      }

      if(preLabel) chainPreLabel = preLabel;

      s = s.slice(hit.i).trim(); // now begins with op
      if(!fromId) return true;
    }

    while(s){
      // swallow leading whitespace
      s = s.trimStart();
      let op = null;
      for(const o of ops){
        if(s.startsWith(o)) { op = o; break; }
      }
      if(!op) break;
      s = s.slice(op.length).trim();

      // optional |label|
      let elabel = '';
      if(s.startsWith('|')){
        let q=null;
        let j=1;
        for(; j<s.length; j++){
          const ch = s[j];
          if(q){
            if(ch===q && s[j-1] !== '\\') q=null;
            continue;
          }
          if(ch==='"' || ch==="'"){ q=ch; continue; }
          if(ch==='|') break;
        }
        if(j<s.length && s[j]==='|'){
          elabel = s.slice(1,j).trim();
          s = s.slice(j+1).trim();
        }
      }

      // if no |label| was provided, fall back to a pre-arrow label (A -- label --> B)
      if(!elabel && chainPreLabel){
        elabel = chainPreLabel;
        chainPreLabel = null; // only applies to the next edge
      }

      const spl = splitEndpointToken(s);
      const rightTok = spl.token;
      s = spl.rest;

      const b = parseEndpoint(rightTok);
      if(!b){
        // even if we can't parse a node, stop the chain
        break;
      }

      edges.push({
        from: fromId,
        to: b.id,
        style: op === '-.->' ? 'dashed' : (op === '==>' ? 'thick' : 'solid'),
        label: elabel
      });

      fromId = b.id;
      lastId = b.id;
    }

    return true;
  };

  for(const rawLine of lines0){
    const line0 = String(rawLine||'');
    const line = line0.trim();
    if(!line){ lastId = null; continue; }

    // Comments + init
    if(line.startsWith('%%')) continue;

    for(const stmt0 of splitStatements(line0.trim())){
      let stmt = stmt0.replace(/;+\s*$/,'').trim();
      if(!stmt) continue;

      const header = stmt.match(/^(graph|flowchart)\s+([A-Za-z]{2})\b/i);
      if(header){
        dir = header[2].toUpperCase();
        continue;
      }

      // ignore common directives (LLMs love sprinkling these)
      if(/^(classDef|class|style|linkStyle|click|subgraph|end|direction)\b/i.test(stmt)){
        continue;
      }

      if(parseEdgeChain(stmt)) continue;

      const n = parseEndpoint(stmt);
      if(n) lastId = n.id;
    }
  }

  return { dir, nodes, edges, order };
}

function layoutFlowchart(g){
  const dir = (g.dir || 'TB').toUpperCase();
  const isLR = (dir === 'LR' || dir === 'RL');

  const nodesArr = Array.from(g.nodes.values()).sort((a,b)=> (a._order??0) - (b._order??0));

  const adj = new Map();
  const radj = new Map();
  for(const n of nodesArr){ adj.set(n.id, []); radj.set(n.id, []); }

  for(const e of g.edges){
    if(!adj.has(e.from)) adj.set(e.from, []);
    if(!radj.has(e.to)) radj.set(e.to, []);
    adj.get(e.from).push(e.to);
    radj.get(e.to).push(e.from);
  }

  // Back-edge detection (cycles) via DFS
  const state = new Map(); // 0=unseen,1=visiting,2=done
  const back = new Set();  // "from->to"
  const dfs = (u)=>{
    state.set(u,1);
    for(const v of (adj.get(u)||[])){
      const st = state.get(v)||0;
      if(st===0) dfs(v);
      else if(st===1) back.add(u+'->'+v);
    }
    state.set(u,2);
  };
  for(const n of nodesArr){
    if((state.get(n.id)||0)===0) dfs(n.id);
  }

  // ---- Node sizing (real-ish text measurement + wrapping)
  const FONT_MAIN = '600 14px system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif';
  const LINE_H = 18;
  const PAD_X = 22;
  const PAD_Y = 16;
  const MIN_W = 104;
  const MAX_W = 520;
  const MAX_TEXT_W = 240; // target wrap width
  const MIN_H_RECT = 44;
  const MIN_H_DIA  = 68;

  const measure = (s, font)=> __mmdTextMeasurer.measure(s, font || FONT_MAIN);

  const hardWrapWord = (word, maxW)=>{
    const chars = Array.from(String(word||''));
    const out = [];
    let cur='';
    for(const ch of chars){
      const t = cur + ch;
      if(cur && measure(t, FONT_MAIN) > maxW){
        out.push(cur);
        cur = ch;
      }else cur = t;
    }
    if(cur) out.push(cur);
    return out.length ? out : [''];
  };

  const wrapText = (label)=>{
    const raw = String(label ?? '').trim();
    if(!raw) return [''];
    const parts = raw.replace(/<br\s*\/?>/gi, '\n').split('\n');
    const lines = [];
    for(const part0 of parts){
      const part = String(part0||'').trim();
      if(!part){ lines.push(''); continue; }
      const words = part.split(/\s+/).filter(Boolean);
      let cur = '';
      for(const w of words){
        const cand = cur ? (cur + ' ' + w) : w;
        if(measure(cand, FONT_MAIN) <= MAX_TEXT_W){
          cur = cand;
        }else{
          if(cur) lines.push(cur);
          if(measure(w, FONT_MAIN) > MAX_TEXT_W){
            const chunks = hardWrapWord(w, MAX_TEXT_W);
            for(let i=0;i<chunks.length;i++){
              if(i===chunks.length-1) cur = chunks[i];
              else lines.push(chunks[i]);
            }
          }else{
            cur = w;
          }
        }
      }
      if(cur) lines.push(cur);
    }
    return lines.length ? lines : [''];
  };

  const measureNode = (label, shape)=>{
    const lines = wrapText(label);
    let maxLineW = 0;
    for(const l of lines) maxLineW = Math.max(maxLineW, measure(l, FONT_MAIN));

    let w = Math.max(MIN_W, Math.min(MAX_W, maxLineW + PAD_X));
    let h = Math.max(MIN_H_RECT, Math.min(280, (lines.length * LINE_H) + PAD_Y));

    if(shape === 'diamond'){
      h = Math.max(MIN_H_DIA, h);
      w = Math.max(w, Math.min(MAX_W, h * 1.55));
      w = Math.max(w, 160);
    }

    return { w, h, lines };
  };

  const nodeMeta = new Map();
  for(const n of nodesArr){
    nodeMeta.set(n.id, measureNode(n.label, n.shape));
  }

  // ---- Layering (ignore back-edges)
  const indeg = new Map(nodesArr.map(n=>[n.id,0]));
  for(const e of g.edges){
    if(back.has(e.from+'->'+e.to)) continue;
    indeg.set(e.to, (indeg.get(e.to)||0) + 1);
  }
  const q = [];
  for(const [id,d] of indeg.entries()) if(d===0) q.push(id);
  q.sort((a,b)=> (g.nodes.get(a)?._order??0) - (g.nodes.get(b)?._order??0));

  const topo = [];
  while(q.length){
    const u = q.shift();
    topo.push(u);
    for(const v of (adj.get(u)||[])){
      if(back.has(u+'->'+v)) continue;
      indeg.set(v, (indeg.get(v)||0) - 1);
      if(indeg.get(v)===0){
        q.push(v);
        q.sort((a,b)=> (g.nodes.get(a)?._order??0) - (g.nodes.get(b)?._order??0));
      }
    }
  }

  // Longest-path ranks (topo order)
  const layer = new Map(nodesArr.map(n=>[n.id,0]));
  for(const u of topo){
    const lu = layer.get(u)||0;
    for(const v of (adj.get(u)||[])){
      if(back.has(u+'->'+v)) continue;
      layer.set(v, Math.max(layer.get(v)||0, lu+1));
    }
  }

  let maxL = 0;
  for(const n of nodesArr) maxL = Math.max(maxL, layer.get(n.id)||0);
  const layers = Array.from({length:maxL+1}, ()=>[]);
  for(const n of nodesArr){
    const L = layer.get(n.id)||0;
    layers[L].push(n.id);
  }

  // ---- Placement
  const PAD = 28;

  if(isLR){
    const GAP_Y = 46;
    const GAP_X = 110;

    const colW = layers.map(ids=>{
      let mw = 0;
      for(const id of ids) mw = Math.max(mw, nodeMeta.get(id).w);
      return mw || MIN_W;
    });

    const colH = layers.map(ids=>{
      let h = 0;
      for(let i=0;i<ids.length;i++){
        h += nodeMeta.get(ids[i]).h;
        if(i) h += GAP_Y;
      }
      return h || MIN_H_RECT;
    });

    const totalH = Math.max(...colH, 160) + PAD*2;
    let x = PAD;
    const pos = new Map();

    for(let li=0; li<layers.length; li++){
      const ids = layers[li];
      const cw = colW[li];
      const ch = colH[li];
      const cx = x + cw/2;
      let y = (totalH - ch)/2;

      for(const id of ids){
        const m = nodeMeta.get(id);
        const cy = y + m.h/2;
        pos.set(id, { x:cx, y:cy, w:m.w, h:m.h, layer:li });
        y += m.h + GAP_Y;
      }

      x += cw + GAP_X;
    }

    const totalW = (x - GAP_X) + PAD;

    // Nicer look: single source in first column sits between its children.
    if(layers[0] && layers[0].length===1){
      const id = layers[0][0];
      const outs = (adj.get(id)||[]).filter(v=>!back.has(id+'->'+v));
      const ys = outs.map(v=>pos.get(v)?.y).filter(Number.isFinite);
      if(ys.length){
        pos.get(id).y = ys.reduce((a,b)=>a+b,0) / ys.length;
      }
    }

    // Mirror for RL
    if(dir === 'RL'){
      for(const [id,p] of pos.entries()){
        pos.set(id, { ...p, x: (totalW - p.x) });
      }
    }

    return { dir, nodes:g.nodes, edges:g.edges, meta:nodeMeta, pos, back, width:totalW, height:totalH };
  }

  // TB/BT-ish: vertical layers, nodes spread horizontally within a layer
  const GAP_X = 30;
  const GAP_Y = 62;

  const layerHeights = layers.map(ids=>{
    let mh = 0;
    for(const id of ids) mh = Math.max(mh, nodeMeta.get(id).h);
    return mh || MIN_H_RECT;
  });

  const layerWidths = layers.map(ids=>{
    let w = 0;
    for(let i=0;i<ids.length;i++){
      w += nodeMeta.get(ids[i]).w;
      if(i) w += GAP_X;
    }
    return w;
  });

  const innerW = Math.max(...layerWidths, 240);
  const totalW = innerW + PAD*2;

  const yByLayer = [];
  let y = PAD;
  for(let i=0;i<layers.length;i++){
    y += layerHeights[i]/2;
    yByLayer.push(y);
    y += layerHeights[i]/2 + GAP_Y;
  }
  const totalH = y - GAP_Y + PAD;

  const pos = new Map();
  for(let li=0; li<layers.length; li++){
    const ids = layers[li];
    const lw = layerWidths[li];
    let x = (totalW - lw)/2;
    for(let i=0;i<ids.length;i++){
      const id = ids[i];
      const m = nodeMeta.get(id);
      const cx = x + m.w/2;
      const cy = yByLayer[li];
      pos.set(id, { x:cx, y:cy, w:m.w, h:m.h, layer:li });
      x += m.w + GAP_X;
    }
  }

  return { dir, nodes:g.nodes, edges:g.edges, meta:nodeMeta, pos, back, width:totalW, height:totalH };
}

function renderFlowchartSvg(g){
  const arrowId = 'mmdArrow' + Math.random().toString(36).slice(2,7);

  // helper: anchor points
  const anchor = (p, which)=>{
    if(which==='top') return [p.x, p.y - p.h/2];
    if(which==='bot') return [p.x, p.y + p.h/2];
    if(which==='left') return [p.x - p.w/2, p.y];
    if(which==='right') return [p.x + p.w/2, p.y];
    return [p.x,p.y];
  };

  // compute routing extents
  let maxX = -Infinity, maxY = -Infinity, minX = Infinity, minY = Infinity;
  const bump = (x,y)=>{
    if(!Number.isFinite(x) || !Number.isFinite(y)) return;
    minX = Math.min(minX, x);
    minY = Math.min(minY, y);
    maxX = Math.max(maxX, x);
    maxY = Math.max(maxY, y);
  };

  for(const p of g.pos.values()){
    bump(p.x - p.w/2, p.y - p.h/2);
    bump(p.x + p.w/2, p.y + p.h/2);
  }

  // for back-edge routing
  let rightMost = -Infinity, bottomMost = -Infinity;
  for(const p of g.pos.values()){
    rightMost = Math.max(rightMost, p.x + p.w/2);
    bottomMost = Math.max(bottomMost, p.y + p.h/2);
  }

  const pathFor = (e)=>{
    const a = g.pos.get(e.from);
    const b = g.pos.get(e.to);
    if(!a || !b) return { d:'', labelPos:null, pts:[] };

    const isLR = (g.dir==='LR' || g.dir==='RL');
    const isBack = g.back.has(e.from+'->'+e.to) || (!isLR && (b.layer <= a.layer)) || (isLR && (b.x <= a.x));

    const pts = [];
    if(isBack){
      const loop = 44;
      if(!isLR){
        const [sx,sy] = anchor(a,'right');
        const [ex,ey] = anchor(b,'top');
        const outX = rightMost + loop;
        const y1 = sy;
        const y2 = Math.min(ey - 18, sy + 18);
        const d = `M ${sx} ${sy} L ${outX} ${y1} L ${outX} ${y2} L ${ex} ${y2} L ${ex} ${ey}`;
        pts.push([sx,sy],[outX,y1],[outX,y2],[ex,y2],[ex,ey]);
        return { d, labelPos: e.label? [outX-8, (y1+y2)/2] : null, pts };
      }else{
        const [sx,sy] = anchor(a,'bot');
        const [ex,ey] = anchor(b,'left');
        const outY = bottomMost + loop;
        const x2 = Math.min(ex - 18, sx + 18);
        const d = `M ${sx} ${sy} L ${sx} ${outY} L ${x2} ${outY} L ${x2} ${ey} L ${ex} ${ey}`;
        pts.push([sx,sy],[sx,outY],[x2,outY],[x2,ey],[ex,ey]);
        return { d, labelPos: e.label? [(sx+ex)/2, outY-8] : null, pts };
      }
    }

    if(!isLR){
      const [sx,sy] = anchor(a,'bot');
      const [ex,ey] = anchor(b,'top');
      const dy = Math.max(40, Math.abs(ey - sy) * 0.5);
      const c1x = sx, c1y = sy + dy;
      const c2x = ex, c2y = ey - dy;
      const d = `M ${sx} ${sy} C ${c1x} ${c1y} ${c2x} ${c2y} ${ex} ${ey}`;
      pts.push([sx,sy],[c1x,c1y],[c2x,c2y],[ex,ey]);
      return { d, labelPos: e.label? [(sx+ex)/2, (sy+ey)/2 - 8] : null, pts };
    }else{
      const [sx,sy] = anchor(a,'right');
      const [ex,ey] = anchor(b,'left');
      const dx = Math.max(52, Math.abs(ex - sx) * 0.5);
      const c1x = sx + dx, c1y = sy;
      const c2x = ex - dx, c2y = ey;
      const d = `M ${sx} ${sy} C ${c1x} ${c1y} ${c2x} ${c2y} ${ex} ${ey}`;
      pts.push([sx,sy],[c1x,c1y],[c2x,c2y],[ex,ey]);
      return { d, labelPos: e.label? [(sx+ex)/2, (sy+ey)/2 - 8] : null, pts };
    }
  };

  const edgePathSvg = (e)=>{
    const info = pathFor(e);
    if(!info.d) return '';
    for(const [x,y] of info.pts) bump(x,y);

    let cls = 'mmd-edge';
    if(e.style==='dashed') cls += ' mmd-edge-dashed';
    if(e.style==='thick') cls += ' mmd-edge-thick';

    // arrow on last segment
    const path = `<path class="${cls}" d="${info.d}" marker-end="url(#${arrowId})"></path>`;

    let lbl = '';
    if(e.label && info.labelPos){
      const [lx,ly] = info.labelPos;
      // bump a small label box
      const lw = __mmdTextMeasurer.measure(e.label, '600 12px system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif');
      bump(lx - lw/2, ly-10);
      bump(lx + lw/2, ly+10);
      lbl = `<text class="mmd-edge-label" x="${lx}" y="${ly}" text-anchor="middle" dominant-baseline="central">${escSvg(e.label)}</text>`;
    }
    return path + lbl;
  };

  const nodeSvg = (n)=>{
    const p = g.pos.get(n.id);
    const meta = g.meta.get(n.id);
    if(!p || !meta) return '';
    const x0 = p.x - p.w/2;
    const y0 = p.y - p.h/2;

    let shapeSvg = '';
    if(n.shape === 'diamond'){
      const cx = p.x, cy = p.y;
      const w = p.w, hh = p.h;
      const pts = [
        [cx, cy - hh/2],
        [cx + w/2, cy],
        [cx, cy + hh/2],
        [cx - w/2, cy]
      ];
      shapeSvg = `<polygon class="mmd-node" points="${pts.map(pt=>pt.join(',')).join(' ')}"></polygon>`;
    }else if(n.shape === 'round'){
      const r = 14;
      shapeSvg = `<rect class="mmd-node" x="${x0}" y="${y0}" width="${p.w}" height="${p.h}" rx="${r}" ry="${r}"></rect>`;
    }else{
      shapeSvg = `<rect class="mmd-node" x="${x0}" y="${y0}" width="${p.w}" height="${p.h}" rx="2" ry="2"></rect>`;
    }

    // Labels (centered, multiline)
    const lines = meta.lines || [n.label||''];
    const lineH = 18;
    const startY = p.y - ((lines.length-1) * lineH)/2;
    const text = lines.map((ln,i)=>{
      const yy = startY + i*lineH;
      return `<text class="mmd-label" x="${p.x}" y="${yy}" text-anchor="middle" dominant-baseline="central">${escSvg(ln)}</text>`;
    }).join('');

    return `<g class="mmd-n">${shapeSvg}${text}</g>`;
  };

  const edgesSvg = g.edges.map(edgePathSvg).join('');
  const nodesSvg = Array.from(g.nodes.values()).sort((a,b)=> (a._order??0)-(b._order??0)).map(nodeSvg).join('');

  const margin = 28;
  const vbX = Math.floor((Number.isFinite(minX)?minX:0) - margin);
  const vbY = Math.floor((Number.isFinite(minY)?minY:0) - margin);
  const vbW = Math.ceil(((Number.isFinite(maxX)?maxX:0) - (Number.isFinite(minX)?minX:0)) + margin*2);
  const vbH = Math.ceil(((Number.isFinite(maxY)?maxY:0) - (Number.isFinite(minY)?minY:0)) + margin*2);

  // Provide intrinsic pixel size; JS/CSS will downscale to fit (and cap upscaling).
  const svg =
`<svg class="mmd" xmlns="http://www.w3.org/2000/svg"
  width="${vbW}" height="${vbH}"
  data-vbw="${vbW}" data-vbh="${vbH}"
  viewBox="${vbX} ${vbY} ${vbW} ${vbH}"
  preserveAspectRatio="xMidYMid meet" role="img" aria-label="Diagram">
  <defs>
    <marker id="${arrowId}" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="6" markerHeight="6" orient="auto">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="currentColor"></path>
    </marker>
  </defs>
  ${edgesSvg}
  ${nodesSvg}
</svg>`;
  return svg;
}

// Fit diagrams to container without insane upscaling.
let __mmdFitRaf = 0;
function fitMermaidSvgs(root){
  const scope = root || document;
  const svgs = scope.querySelectorAll ? scope.querySelectorAll('svg.mmd[data-vbw]') : [];
  const MAX_UP_SMALL = 1.55; // allow small graphs to grow
  const MAX_UP_MED   = 1.25;
  const MAX_UP_LARGE = 1.10;
  svgs.forEach(svg=>{
    const vbw = Number(svg.dataset.vbw||0);
    if(!vbw) return;
    const wrap = svg.closest('.mmd-wrap');
    const w = wrap ? wrap.clientWidth : (svg.parentElement ? svg.parentElement.clientWidth : 0);
    if(!w) return;
    const maxUp = vbw < 520 ? MAX_UP_SMALL : (vbw < 820 ? MAX_UP_MED : MAX_UP_LARGE);
    const desired = Math.min(w, vbw * maxUp);
    svg.style.width = Math.max(60, Math.floor(desired)) + 'px';
    svg.style.height = 'auto';
  });
}
function scheduleFitMermaid(root){
  if(__mmdFitRaf) cancelAnimationFrame(__mmdFitRaf);
  __mmdFitRaf = requestAnimationFrame(()=>{ __mmdFitRaf=0; fitMermaidSvgs(root); });
}
window.addEventListener('resize', ()=>scheduleFitMermaid(document));
// ---------- /Minimal Mermaid renderer ----------

function md(md){
  const raw = String(md ?? '');

  // ---- Helpers: \boxed{...} -------------------------------------------------
  // MathML support for <menclose> (boxed) is inconsistent across browsers.
  // Instead of relying on MathML boxes, we strip \boxed{...} from TeX and draw a
  // stable HTML/CSS box around the rendered MathML.
  const stripAllBoxed = (tex)=>{
    const s = String(tex ?? '');
    let i = 0;
    let out = '';
    let changed = false;

    const startsWithBoxed = (idx)=> s.slice(idx, idx+6) === '\\boxed';
    const isWS = (ch)=> ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r';

    while (i < s.length){
      if (!startsWithBoxed(i)) { out += s[i++]; continue; }

      // Found "\\boxed". Skip it and any whitespace, then require an opening "{".
      let j = i + 6;
      while (j < s.length && isWS(s[j])) j++;
      if (s[j] !== '{'){ out += s[i++]; continue; } // not a real boxed command

      // Consume the {...} group with brace matching.
      j++; // after '{'
      let depth = 1;
      let inner = '';
      while (j < s.length){
        const ch = s[j];
        if (ch === '\\'){
          // Keep escapes intact
          inner += ch;
          j++;
          if (j < s.length){ inner += s[j]; j++; }
          continue;
        }
        if (ch === '{'){ depth++; inner += ch; j++; continue; }
        if (ch === '}'){
          depth--;
          if (depth === 0){ j++; break; }
          inner += ch; j++; continue;
        }
        inner += ch; j++;
      }
      if (depth !== 0){
        // Unbalanced braces: fall back to literal text.
        out += s[i++];
        continue;
      }

      // Replace the whole \boxed{...} with its content.
      out += inner;
      changed = true;
      i = j;
    }

    return { tex: out, boxed: changed };
  };

  const renderMathHTML = (tex, display)=>{
    const r = stripAllBoxed(tex);
    const mml = texToMathML(r.tex, !!display);
    if (!r.boxed) return mml;
    const boxCls = display ? 'tex-boxed tex-boxed-block' : 'tex-boxed';
    return `<span class="${boxCls}">${mml}</span>`;
  };

  // ---- 1) Extract fenced code blocks (closed) ----
  const blocks = [];
  // Fenced code blocks as people actually paste them:
  // - allow indentation (lists/quotes)
  // - allow Windows newlines
  // - allow trailing whitespace after the closing fence
  let tmp = raw.replace(/(^|\r?\n)[ \t]*```([^\r\n`]*)\r?\n([\s\S]*?)\r?\n[ \t]*```[ \t]*(?=\r?\n|$)/g, (_m, pre, lang, code)=>{
    const i = blocks.length;
    blocks.push({ lang: (lang||'').trim(), code, open:false });
    return `${pre}@@CODE_${i}@@`;
  });

  // ---- 1b) Treat an unfinished trailing fence as a code block (streaming-friendly) ----
  // If there's an opening ``` that never closes (common while streaming), render it as code until end.
  // We only ever convert the LAST unmatched fence to avoid eating earlier text.
  const fence = '```';
  const last = tmp.lastIndexOf(fence);
  if (last !== -1) {
    const after = tmp.slice(last + fence.length);
    const nl = after.indexOf('\n');
    if (nl !== -1) {
      const lang = after.slice(0, nl).trim();
      const rest = after.slice(nl + 1);
      if (rest.indexOf(fence) === -1) {
        const i = blocks.length;
        blocks.push({ lang, code: rest, open:true });
        tmp = tmp.slice(0, last) + `@@CODE_${i}@@`;
      }
    }
  }

  // ---- 2) Extract inline code spans BEFORE escaping/emphasis ----
  // This avoids double-escaping (e.g. `<` inside inline code) while staying safe.
  const inlines = [];
  tmp = tmp.replace(/`([^`\n]+)`/g, (_m, code)=>{
    const i = inlines.length;
    inlines.push(code);
    // Use a token that won't get mangled by emphasis rules.
    // (Older builds used @@IC_0@@; we accept both when restoring.)
    return `@@IC${i}@@`;
  });

  // ---- 2b) Extract LaTeX-style math BEFORE escaping/emphasis ----
  // Supported delimiters:
  // - inline: \( ... \)  or  $ ... $
  // - block:  \[ ... \]  or  $$ ... $$
  //
  // Notes:
  // - Parsing $...$ is intentionally conservative to avoid eating currency like "$10".
  // - For a literal dollar sign, use \\$ (markdown-style escape).
  const mathInline = [];
  const mathBlock = [];

  const isEscapedAt = (s, idx)=>{
    // idx is the position of the delimiter char (e.g. '$')
    let n = 0;
    for (let i = idx - 1; i >= 0 && s[i] === '\\'; i--) n++;
    return (n % 2) === 1;
  };

  const isWord = (c)=> !!c && /[A-Za-z0-9]/.test(c);
  const openOK = (prev)=> !isWord(prev);
  const closeOK = (next)=> !isWord(next);

  const looksLikeMath = (tex)=>{
    const t = String(tex ?? '').trim();
    if (!t) return false;

    // Pure numbers like "$10$" are far more likely currency than math.
    if (/^-?\d+(?:[.,]\d+)*$/.test(t)) return false;

    // TeX-ish signals
    if (/\\[A-Za-z]+/.test(t)) return true;      // commands like \frac, \sqrt, \theta
    if (/[\^_{}=<>]/.test(t)) return true;        // common TeX/math syntax
    if (/[A-Za-z0-9]\s*[\+\-\*\/]\s*[A-Za-z0-9]/.test(t)) return true; // binary op
    if (/^-?\d+[A-Za-z]+$/.test(t)) return true;  // 2x, 10n
    if (/^[A-Za-z]{1,3}$/.test(t)) return true;    // a, x, ab

    return false;
  };

  const extractDollarMath = (s)=>{
    let out = '';
    let i = 0;

    while (i < s.length) {
      const ch = s[i];

      // Backslash-escaped dollar: "\$" -> literal "$"
      if (ch === '\\' && s[i+1] === '$') {
        out += '@@LITDOLLAR@@';
        i += 2;
        continue;
      }

      if (ch !== '$' || isEscapedAt(s, i)) {
        out += ch;
        i++;
        continue;
      }

      // $$ ... $$ (block)
      if (s[i+1] === '$') {
        const start = i;
        i += 2;
        let j = i;
        while (j < s.length) {
          if (s[j] === '$' && s[j+1] === '$' && !isEscapedAt(s, j)) break;
          j++;
        }
        if (j < s.length) {
          const tex = s.slice(i, j);
          const idx = mathBlock.length;
          mathBlock.push(tex);
          out += `@@MB${idx}@@`;
          i = j + 2;
          continue;
        }
        // Unclosed: keep literal
        out += '$$';
        i = start + 2;
        continue;
      }

      // $ ... $ (inline)
      const start = i;
      const prev = s[start-1] || '';
        if (!openOK(prev)) {
        out += '$';
        i = start + 1;
        continue;
      }

      let j = start + 1;
      let crossedLine = false;
      while (j < s.length) {
        // Inline $...$ must stay on one physical line. Without this guard an
        // ordinary currency amount such as "$0.84" can accidentally pair with
        // a later dollar sign (for example "0.84$") several paragraphs away,
        // causing the whole intervening prose to be parsed as TeX/MathML.
        // Multiline math is still supported via $$...$$ and \[...\].
        if (s[j] === '\n' || s[j] === '\r') {
          crossedLine = true;
          break;
        }

        if (s[j] === '$' && !isEscapedAt(s, j)) {
          // Skip $$ (block markers) when looking for an inline close.
          if (s[j+1] === '$') { j += 2; continue; }
          // Also skip if this '$' is the 2nd of a '$$' pair (rare but safe).
          if (s[j-1] === '$') { j++; continue; }
          break;
        }
        j++;
      }

      if (crossedLine || j >= s.length) {
        out += '$';
        i = start + 1;
        continue;
      }

      const closeNext = s[j+1] || '';
      if (!closeOK(closeNext)) {
        out += '$';
        i = start + 1;
        continue;
      }

      const texRaw = s.slice(start + 1, j);

      if (!looksLikeMath(texRaw)) {
        // Not math (likely currency or normal text) -> keep literal '$'
        out += '$';
        i = start + 1;
        continue;
      }

      const idx = mathInline.length;
      mathInline.push(texRaw);
      out += `@@MI${idx}@@`;
      i = j + 1;
    }

    return out;
  };

  // Bracketed math first (can span newlines)
  tmp = tmp.replace(/\\\[([\s\S]*?)\\\]/g, (_m, tex)=>{
    const i = mathBlock.length;
    mathBlock.push(tex);
    return `@@MB${i}@@`;
  });

  tmp = tmp.replace(/\\\(([\s\S]*?)\\\)/g, (_m, tex)=>{
    const i = mathInline.length;
    mathInline.push(tex);
    return `@@MI${i}@@`;
  });

  // Dollar-delimited math ($...$ / $$...$$)
  tmp = extractDollarMath(tmp);
// ---- 3) Escape everything else ----
  tmp = esc(tmp).replace(/@@LITDOLLAR@@/g, ()=>'$');

  // CommonMark does not treat underscores inside words as emphasis delimiters.
  // Protect runs such as the underscores in `lazarus_whisper_input.mp3` before
  // applying the deliberately small emphasis regexes below, then restore them.
  // Without this, `_whisper_` is interpreted as italic and its underscores
  // disappear from filenames, identifiers and similar text.
  const intrawordUnderscores = [];
  tmp = tmp.replace(/([A-Za-z0-9])(_+)(?=[A-Za-z0-9])/g, (_m, left, underscores)=>{
    const i = intrawordUnderscores.length;
    intrawordUnderscores.push(underscores);
    return `${left}@@IWUS${i}@@`;
  });

  // ---- 4) Inline markdown (safe because we've escaped already) ----
  tmp = tmp
    // bold+italic (common forms)
    .replace(/\*\*\*([\s\S]+?)\*\*\*/g, '<strong><em>$1</em></strong>')
    .replace(/___([\s\S]+?)___/g, '<strong><em>$1</em></strong>')
    .replace(/\*\*_([^_\n]+)_\*\*/g, '<strong><em>$1</em></strong>')
    .replace(/__\*([^*\n]+)\*__/g, '<strong><em>$1</em></strong>')
    // bold
    .replace(/\*\*([\s\S]+?)\*\*/g, '<strong>$1</strong>')
    .replace(/__([\s\S]+?)__/g, '<strong>$1</strong>')
    // italic
    .replace(/\*([^\n*]+)\*/g, '<em>$1</em>')
    .replace(/_([^_\n]+)_/g, '<em>$1</em>')
    // strike
    .replace(/~~([^\n~]+)~~/g, '<del>$1</del>')
    // links
    .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');

  // Restore literal intraword underscores after emphasis parsing.
  tmp = tmp.replace(/@@IWUS(\d+)@@/g, (_m, n)=> intrawordUnderscores[Number(n)] ?? '');

  // ---- 4b) Restore inline code spans ----
  tmp = tmp.replace(/@@IC_?(\d+)@@/g, (_m, n)=>{
    const code = inlines[Number(n)] ?? '';
    return `<code>${esc(code)}</code>`;
  });

  // ---- 4c) Restore inline math ----
  tmp = tmp.replace(/@@(?:MI|MATHI_)(\d+)@@/g, (_m, n)=>{
    const tex = mathInline[Number(n)] ?? '';
    return `<span class="math math-inline">${renderMathHTML(tex, false)}</span>`;
  });

  // ---- 5) Block markdown (headings, lists, blockquotes, hr, tables, paragraphs, code placeholders) ----
  const lines = tmp.split('\n');
  const out = [];
  // Nested lists need a stack (indent-level aware).
  const listStack = []; // {type:'ul'|'ol', level:int, liOpen:bool}
  let inBQ = false;
  let para = [];

  const flushPara = ()=>{
    if (!para.length) return;
    out.push(`<p>${para.join('<br>')}</p>`);
    para = [];
  };

  const closeLists = ()=>{
    while(listStack.length){
      const top = listStack[listStack.length-1];
      if(top.liOpen){ out.push('</li>'); top.liOpen=false; }
      out.push(`</${top.type}>`);
      listStack.pop();
    }
  };

  const closeListsBQ = ()=>{
    closeLists();
    if (inBQ){ out.push('</blockquote>'); inBQ=false; }
  };

  const hardBreakBlock = ()=>{
    flushPara();
    closeListsBQ();
  };

  // Open/continue a nested list stack.
  //
  // For ordered lists we try to preserve explicit numbering (e.g. sectioned
  // reports like "2. ..." / "3. ..."). We only set an <ol start> when the
  // first marker isn't "1" so that classic Markdown style (all items written
  // as "1.") still auto-increments.
  const ensureList = (type, level, startNum)=>{
    const cur = listStack[listStack.length-1];

    const openTag = ()=>{
      if (type === 'ol'){
        const n = Number(startNum);
        if (Number.isFinite(n) && n > 1) return `<ol start="${n}">`;
      }
      return `<${type}>`;
    };

    // Start fresh
    if(!cur){
      out.push(openTag());
      listStack.push({type, level, liOpen:false});
      return;
    }

    // Go deeper: open a nested list inside the current <li>
    if(level > cur.level){
      if(!cur.liOpen){
        // Defensive: if we somehow don't have an open li, open one.
        out.push('<li>');
        cur.liOpen=true;
      }
      out.push(openTag());
      listStack.push({type, level, liOpen:false});
      return;
    }

    // Go up: close lists until we reach the target level
    while(listStack.length && listStack[listStack.length-1].level > level){
      const top = listStack[listStack.length-1];
      if(top.liOpen){ out.push('</li>'); top.liOpen=false; }
      out.push(`</${top.type}>`);
      listStack.pop();
    }

    // Now we're at the right level (or stack is empty)
    const nowTop = listStack[listStack.length-1];
    if(!nowTop){
      out.push(openTag());
      listStack.push({type, level, liOpen:false});
      return;
    }

    // Same level, but list type changes
    if(nowTop.type !== type){
      if(nowTop.liOpen){ out.push('</li>'); nowTop.liOpen=false; }
      out.push(`</${nowTop.type}>`);
      listStack.pop();
      out.push(openTag());
      listStack.push({type, level, liOpen:false});
      return;
    }

    // Same level, same type: close previous li
    if(nowTop.liOpen){ out.push('</li>'); nowTop.liOpen=false; }
  };

  const splitRow = (row)=>{
    let s = row.trim();
    if (s.startsWith('|')) s = s.slice(1);
    if (s.endsWith('|')) s = s.slice(0, -1);
    return s.split('|').map(c=>c.trim());
  };

  const alignFromSep = (cell)=>{
    const c = cell.trim();
    const left = c.startsWith(':');
    const right = c.endsWith(':');
    if (left && right) return 'center';
    if (right) return 'right';
    if (left) return 'left';
    return '';
  };

  // Treat literal <br> tags inside table cells as line breaks.
  // We only do this inside tables to avoid enabling raw HTML elsewhere.
  const fixBrInTableCell = (s)=>{
    const html = String(s ?? '');
    // Avoid converting inside inline code spans (<code>...</code>).
    const parts = html.split(/(<code>[\s\S]*?<\/code>)/g);
    for (let i=0;i<parts.length;i++){
      if (parts[i].startsWith('<code>')) continue;
      parts[i] = parts[i].replace(/&lt;br\s*\/?\s*&gt;/gi, '<br>');
    }
    return parts.join('');
  };

  const isTableSep = (row)=>{
    const r = row.trim();
    if (!r.includes('-') || !r.includes('|')) return false;
    return /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(r);
  };

  for (let i=0;i<lines.length;i++){
    const t = lines[i].trimEnd();

    // Code block placeholder (as a full line)
    // Allow leading/trailing whitespace so indented fences don't leak @@CODE_x@@.
    // Using \s* here is more robust than trim(), because some editors insert odd whitespace.
    const codeMatch = t.match(/^\s*@@CODE_(\d+)@@\s*$/);
    if (codeMatch){
      hardBreakBlock();
      const idx = Number(codeMatch[1]);
      const b = blocks[idx];
      const codeEsc = esc(b?.code ?? '');
      const cls = b?.lang ? ` class="language-${esc(b.lang)}"` : '';
      const open = b?.open ? ' data-open="1"' : '';
      const langNorm = String(b?.lang || '').trim().toLowerCase();

      // Mermaid (minimal subset) -> inline SVG
      if (langNorm === 'mermaid'){
        let svg = '';
        try{ svg = mermaidToSvg(String(b?.code ?? '')); }catch(_){ svg = ''; }
        if (svg){
          out.push(
            `<div class="codeblock mermaid-block"${open}>` +
              `<button class="code-download" title="Download" aria-label="Download">${iconSvg('download')}</button>` +
              `<button class="code-copy" title="Copy">⧉</button>` +
              `<div class="mmd-wrap">${svg}</div>` +
              `<pre class="mmd-src" hidden><code class="language-mermaid">${codeEsc}</code></pre>` +
            `</div>`
          );
          continue;
        }
      }

      // Preview support:
      // - html/htm: render as-is
      // - svg (or xml/no lang that looks like <svg>): wrap in a simple HTML document
      const rawCodeForPreview = String(b?.code ?? '');
      const stripped = rawCodeForPreview.replace(/^\s*<\?xml[^>]*>\s*/i, '').trim();
      const looksSvg = /^<svg[\s>]/i.test(stripped);

      const previewType =
        (langNorm === 'html' || langNorm === 'htm') ? 'html' :
        (langNorm === 'svg' || ((langNorm === 'xml' || !langNorm) && looksSvg)) ? 'svg' :
        '';

      const previewBtn = previewType
        ? `<button class="code-preview" data-preview-type="${previewType}" title="Preview" aria-label="Preview">${iconSvg('eye')}</button>`
        : '';

      const downloadBtn = `<button class="code-download" title="Download" aria-label="Download">${iconSvg('download')}</button>`;
      out.push(
        `<div class="codeblock"${open}>` +
          `${previewBtn}` +
          `${downloadBtn}` +
          `<button class="code-copy" title="Copy">⧉</button>` +
          `<pre><code${cls}>${codeEsc}</code></pre>` +
        `</div>`
      );
      continue;
    }

    // Block math placeholder (as a full line)
    const mathBlockMatch = t.match(/^\s*@@(?:MB|MATHB_)(\d+)@@\s*$/);
    if (mathBlockMatch){
      hardBreakBlock();
      const idx = Number(mathBlockMatch[1]);
      const tex = (mathBlock[idx] ?? '');
      out.push(`<div class="math math-block">${renderMathHTML(tex, true)}</div>`);
      continue;
    }

    // Blank lines: keep lists open if the next non-empty line continues the list.
    // (Otherwise ordered lists will restart at 1 after each blank line.)
    if (t.trim() === ''){
      if (listStack.length){
        // Look ahead to the next non-empty line
        let j = i + 1;
        while (j < lines.length && String(lines[j] ?? '').trim() === '') j++;
        const nxt = (j < lines.length) ? String(lines[j] ?? '').trimEnd() : '';

        const nextContinuesList =
          /^\s*[-*+]\s+/.test(nxt) ||          // ul
          /^\s*\d+\.\s+/.test(nxt) ||         // ol
          /^\s+\S/.test(nxt);                  // indented continuation

        if (nextContinuesList){
          // End any paragraph, but do NOT close the list.
          flushPara();
          continue;
        }
      }
      hardBreakBlock();
      continue;
    }

    // Table (header row + separator row)
    if (t.includes('|') && i+1 < lines.length && isTableSep(lines[i+1])) {
      hardBreakBlock();

      const headerCells = splitRow(t);
      const sepCells = splitRow(lines[i+1]);
      const aligns = sepCells.map(alignFromSep);

      const rows = [];
      i += 2; // consume header + separator
      for (; i < lines.length; i++) {
        const rowLine = lines[i].trimEnd();
        if (!rowLine.trim()) break;
        if (/^(#{1,6})\s+/.test(rowLine.trim())) break;
        if (/^(?:-{3,}|\*{3,}|_{3,})$/.test(rowLine.trim())) break;
        if (/^\s*@@CODE_(\d+)@@\s*$/.test(rowLine)) break;
        if (!rowLine.includes('|')) break;
        rows.push(splitRow(rowLine));
      }
      i -= 1; // compensate for loop increment

      const ths = headerCells.map((c, idx)=>{
        const a = aligns[idx] ? ` style="text-align:${aligns[idx]}"` : '';
        return `<th${a}>${fixBrInTableCell(c)}</th>`;
      }).join('');

      const trs = rows.map(r=>{
        const tds = headerCells.map((_c, idx)=>{
          const cell = (r[idx] ?? '');
          const a = aligns[idx] ? ` style="text-align:${aligns[idx]}"` : '';
          return `<td${a}>${fixBrInTableCell(cell)}</td>`;
        }).join('');
        return `<tr>${tds}</tr>`;
      }).join('');

      out.push(`<table><thead><tr>${ths}</tr></thead><tbody>${trs}</tbody></table>`);
      continue;
    }

    // Horizontal rule
    if (/^(?:-{3,}|\*{3,}|_{3,})$/.test(t.trim())){
      hardBreakBlock();
      out.push('<hr>');
      continue;
    }

    // Headings
    const h = t.match(/^(#{1,6})\s+(.+)$/);
    if (h){
      hardBreakBlock();
      const lv = h[1].length;
      out.push(`<h${lv}>${h[2].trim()}</h${lv}>`);
      continue;
    }

    // Blockquote
    const bq = t.match(/^&gt;\s?(.*)$/);
    if (bq){
      flushPara();
      if (!inBQ){ closeLists(); out.push('<blockquote>'); inBQ=true; }
      out.push(`<p>${bq[1]}</p>`);
      continue;
    }

    // Unordered list (supports nesting via indentation)
    const ul = t.match(/^(\s*)[-*+]\s+(.+)$/);
    if (ul){
      flushPara();
      if (inBQ){ out.push('</blockquote>'); inBQ=false; }
      const indent = (ul[1]||'').replace(/\t/g,'  ').length;
      const level = Math.floor(indent/2);
      ensureList('ul', level);
      const top = listStack[listStack.length-1];
      out.push(`<li>${ul[2]}`);
      top.liOpen = true;
      continue;
    }

    // Ordered list (supports nesting via indentation)
    const ol = t.match(/^(\s*)(\d+)\.\s+(.+)$/);
    if (ol){
      flushPara();
      if (inBQ){ out.push('</blockquote>'); inBQ=false; }
      const num = Number(ol[2]);
      const indent = (ol[1]||'').replace(/\t/g,'  ').length;
      const level = Math.floor(indent/2);
      ensureList('ol', level, num);
      const top = listStack[listStack.length-1];
      // Preserve explicit numbering when the marker isn't "1.".
      // This keeps report-style numbering intact (1., 2., 3. ...), while still
      // allowing classic Markdown lists written as all "1." to auto-increment.
      const valueAttr = (Number.isFinite(num) && num !== 1) ? ` value="${num}"` : '';
      out.push(`<li${valueAttr}>${ol[3]}`);
      top.liOpen = true;
      continue;
    }

    // Continuation line inside the current list item (keep it simple)
    if (listStack.length){
      const cur = listStack[listStack.length-1];
      if (cur.liOpen && /^\s+\S/.test(t) && !/^(#{1,6})\s+/.test(t.trim()) && !/^\s*@@CODE_(\d+)@@\s*$/.test(t)){
        out.push(`<div class="li-continue">${t.trim()}</div>`);
        continue;
      }
    }

    // Plain paragraph line (we join consecutive lines with <br>)
    if (listStack.length || inBQ) closeListsBQ();
    para.push(t);
  }

  flushPara();
  closeListsBQ();
  return out.join('\n');
}



  // --- Per-message speed stats (llama.cpp timings etc.) ---
  function msgMetricsHtml(metrics){
    metrics = (metrics && typeof metrics === 'object') ? metrics : {};
    const p = Number(metrics.prompt_tps);
    const g = Number(metrics.gen_tps);
    const pt = Number(metrics.prompt_tokens);
    const ct = Number(metrics.completion_tokens);
    const usd = Number(metrics.price);

    const fmtTps = (v)=> Number.isFinite(v) ? v.toFixed(1) : '—';
    const fmtTok = (v)=> Number.isFinite(v) ? String(Math.round(v)) : '—';
    const fmtMoney = (v)=> Number.isFinite(v) ? `$${fmtUsd(v)}` : '—';

    // Always show both rows; fill with placeholders until backend sends real stats.
    return `
      <div class="metrics-row"><span>P</span><span>${fmtTps(p)} tok/s · ${fmtTok(pt)} tok</span></div>
      <div class="metrics-row"><span>G</span><span>${fmtTps(g)} tok/s · ${fmtTok(ct)} tok</span></div>
      <div class="metrics-row"><span>$</span><span>${fmtMoney(usd)}</span></div>
    `;
  }

  function metricsReady(metrics){
    if (!metrics || typeof metrics !== 'object') return false;
    const vals = [metrics.prompt_tps, metrics.gen_tps, metrics.prompt_tokens, metrics.completion_tokens, metrics.total_tokens];
    return vals.some(v=>Number.isFinite(Number(v)));
  }

  function setMsgMetricsDom(msgEl, metrics){
    if (!msgEl) return;
    const box = msgEl.querySelector('.msg-metrics');
    if (!box) return;
    const pop = box.querySelector('.metrics-pop');
    if (!pop) return;
    const html = msgMetricsHtml(metrics);
    pop.innerHTML = html;
    if (metricsReady(metrics)) box.classList.add('ready'); else box.classList.remove('ready');
  }

  function renderMessages(){
    syncChatStreamingClass();
    chatMsgs.innerHTML='';
    if(!state.currentChat){ chatMsgs.appendChild(emptyChatMsg); updateTokenBarIdle(); return; }
    const msgs = state.currentChat.messages || [];
    if(!msgs.length){
      const div=document.createElement('div');
      div.className='muted'; div.style.padding='24px 0'; div.style.textAlign='center';
      div.textContent='Write something to get started.';
      chatMsgs.appendChild(div);
      updateTokenBarIdle();
      return;
    }
    msgs.forEach((m,i)=>chatMsgs.appendChild(messageNode(m,i)));
    scrollBottom(true);
    updateTokenBarIdle();
    updateTtsButtons();
    scheduleFitMermaid(chatMsgs);
  }

  function ragSourcesHtml(m){
    const sources = Array.isArray(m?.rag_sources) ? m.rag_sources : [];
    if (!sources.length) return '';

    const cited = new Set();
    const content = String(m?.content || '');
    for (const match of content.matchAll(/\[(\d+)\]/g)) cited.add(Number(match[1]));

    const cards = sources.map((src, i)=>{
      const n = Number(src?.n || (i + 1));
      const name = String(src?.name || src?.source || src?.document_id || 'Document');
      const section = String(src?.section || '').trim();
      const page = Number(src?.page);
      const score = Number(src?.score);
      const text = String(src?.text || '').trim();
      const isCited = cited.has(n);
      let url = String(src?.source || '').trim();
      if (url && Number.isFinite(page) && page > 0 && /^https?:\/\//i.test(url)) {
        url = url.replace(/#.*$/, '') + `#page=${Math.round(page)}`;
      }
      const loc = [];
      if (Number.isFinite(page) && page > 0) loc.push(`p. ${Math.round(page)}`);
      if (section) loc.push(section);
      if (Number.isFinite(score)) loc.push(Number(score).toFixed(3));
      const title = url && /^https?:\/\//i.test(url)
        ? `<a class="rag-source-link" href="${esc(url)}" target="_blank" rel="noopener noreferrer">${esc(name)}</a>`
        : `<span>${esc(name)}</span>`;
      return `<div class="rag-source-card${isCited ? ' cited' : ''}">
        <div class="rag-source-head">
          <span class="rag-source-num">[${n}]</span>
          <span class="rag-source-name">${title}</span>
          ${isCited ? '<span class="rag-source-cited">cited</span>' : ''}
        </div>
        ${loc.length ? `<div class="rag-source-meta">${loc.map(esc).join(' · ')}</div>` : ''}
        <div class="rag-source-passage">${esc(text)}</div>
      </div>`;
    }).join('');

    return `<details class="rag-sources-block">
      <summary><span>RAG sources</span><span class="rag-sources-count">${sources.length}${cited.size ? ` · ${cited.size} cited` : ''}</span></summary>
      <div class="rag-sources-list">${cards}</div>
    </details>`;
  }

  function messageNode(m, idx){
    const isUser = m.role==='user';
    const wrap=document.createElement('div');
    wrap.className=`message ${isUser?'user':'assistant'}`;
    wrap.dataset.msgIndex=String(idx);
    const avatar = isUser?'U':'AI';
    // IMPORTANT: show the model that produced *this* assistant message.
    // Chats can switch models over time; do not retroactively relabel older turns.
    const msgModel = (!isUser)
      ? (m.model || m.model_id || m?.meta?.model || m?.meta?.model_id || '')
      : '';
    const who = isUser ? 'You' : (msgModel || state.currentChat?.model || state.ui.model || 'AI');
    const isLast = (idx === ((state.currentChat?.messages||[]).length - 1));
    const isEmptyAssistant = (!isUser && !String(m.content||'').trim());
    const showTyping = (!isUser && isLast && (m.incomplete === true) && (m.stopped !== true) && isEmptyAssistant);

    const content = (showTyping)
      ? '<div class="typing-indicator" aria-label="Assistant is thinking"><span class="typing-dot" aria-hidden="true"></span></div>'
      : md(m.content||'');
    const atts = (m.attachments||[]).map((a,ai)=>{
      const rmBtn = `<button class="icon-btn sm att-remove" data-msg-index="${idx}" data-att-index="${ai}" title="Remove from message" aria-label="Remove">${iconSvg('x')}</button>`;
      const dlBtn = (a.url) ? `<a class="icon-btn sm" href="${esc(a.url)}" target="_blank" rel="noopener noreferrer" title="Download" aria-label="Download">${iconSvg('download')}</a>` : '';
      const delBtn = ((a.file_id && a.url) ? `<button class="icon-btn sm danger att-delete" data-msg-index="${idx}" data-att-index="${ai}" title="Delete on server" aria-label="Delete">${iconSvg('trash')}</button>` : '');

      if(a.type==='image' && (a.data_url || a.url)){
        const src = a.data_url || a.url;
        const actions = `<div class="att-actions">${dlBtn}${delBtn}${rmBtn}</div>`;
        return `<div class="muted" style="margin-top:10px;">
          <div class="att-row">
            <span class="att-label">${iconSvg('image')} <b>${esc(a.name||'image')}</b></span>
            ${actions}
          </div>
          <div style="margin-top:8px;"><img src="${esc(src)}" style="max-width:260px;border-radius:10px;border:1px solid var(--border);"></div>
        </div>`;
      }

      if(a.type==='audio' && (a.data_url || a.url)){
        const src = a.data_url || a.url;
        const actions = `<div class="att-actions">${dlBtn}${delBtn}${rmBtn}</div>`;
        return `<div class="muted" style="margin-top:10px;">
          <div class="att-row">
            <span class="att-label">${iconSvg('audio')} <b>${esc(a.name||'audio')}</b> <span class="muted">· ${esc(a.mime||'audio/*')} · ${esc(human(a.size||0))}</span></span>
            ${actions}
          </div>
          <div style="margin-top:8px;"><audio controls preload="metadata" src="${esc(src)}" style="width:min(360px,100%);"></audio></div>
        </div>`;
      }

      if(a.type==='url' && a.url){
        const actions = `<div class="att-actions">${rmBtn}</div>`;
        return `<div class="muted" style="margin-top:10px;">
          <div class="att-row">
            <span class="att-label">${iconSvg('link')} <a href="${esc(a.url)}" target="_blank" rel="noopener noreferrer">${esc(a.url)}</a></span>
            ${actions}
          </div>
        </div>`;
      }

      if(isTextDocumentAttachment(a) && (a.text || a.file_id)){
        const txt = String(a.text||'');
        const head = txt.slice(0, 800);
        const more = txt.length > head.length;
        const badge = a.truncated ? ' · truncated' : '';
        const fileBacked = !txt && !!a.file_id;
        const info = fileBacked ? ` <span class="muted">· ${esc(documentTextMeta(a))}</span>` : '';

        const actions = `
          <div class="att-actions">
            ${a.url ? `<a class="icon-btn sm" href="${esc(a.url)}" target="_blank" rel="noopener noreferrer" title="Download" aria-label="Download">${iconSvg('download')}</a>` : ''}
            <button class="icon-btn sm att-view" data-msg-index="${idx}" data-att-index="${ai}" title="View full extraction" aria-label="View">${iconSvg('eye')}</button>
            ${(a.file_id && a.url) ? `<button class="icon-btn sm danger att-delete" data-msg-index="${idx}" data-att-index="${ai}" title="Delete on server" aria-label="Delete">${iconSvg('trash')}</button>` : ''}
            ${rmBtn}
          </div>`;

        return `<div class="muted" style="margin-top:10px;">
          <div class="att-row">
            <span class="att-label">${iconSvg('fileText')} <b>${esc(a.name||'text')}</b>${badge}${info}</span>
            ${actions}
          </div>
          ${txt ? `<pre class="att-preview">${esc(head)}${more ? '…' : ''}</pre>` : ''}
        </div>`;
      }

      if(a.type==='rag' && a.rag_document_id){
        const actions = `<div class="att-actions">${dlBtn}${rmBtn}</div>`;
        const chunks = Number(a.rag_chunks || 0);
        return `<div class="muted" style="margin-top:10px;">
          <div class="att-row">
            <span class="att-label">${iconSvg('fileText')} <b>${esc(a.name||'RAG document')}</b> <span class="muted">· RAG${chunks ? ` · ${chunks} chunks` : ''}</span></span>
            ${actions}
          </div>
        </div>`;
      }

      if((a.type==='file'||a.type==='image') && a.url){
        const ns = a.not_sent ? ' · not sent to model' : '';
        const actions = `<div class="att-actions">${dlBtn}${delBtn}${rmBtn}</div>`;
        const fileSize = Number(a.size || 0);
        const sizeInfo = fileSize > 0 ? ` · ${esc(human(fileSize))}` : '';
        return `<div class="muted" style="margin-top:10px;">
          <div class="att-row">
            <span class="att-label">${iconSvg('paperclip')} <a href="${esc(a.url)}" target="_blank" rel="noopener noreferrer">${esc(a.name||'file')}</a> <span class="muted">· ${esc(a.mime||'')}${sizeInfo}${ns}</span></span>
            ${actions}
          </div>
        </div>`;
      }

      if(a.type==='note' && a.text){
        const actions = `<div class="att-actions">${rmBtn}</div>`;
        return `<div class="muted" style="margin-top:10px;">
          <div class="att-row">
            <span class="att-label">${iconSvg('pencil')} <span>${esc(a.text)}</span></span>
            ${actions}
          </div>
        </div>`;
      }

      return '';
    }).join('');
    const activity = (!isUser) ? agentActivityHtml(m) : '';
    const hasReasoning = (!isUser && m.reasoning && String(m.reasoning).trim());
    const thinking = (hasReasoning) ? `
      <div class="thinking-section">
        <div class="thinking-header">🧠 Reasoning <span>▼</span></div>
        <div class="thinking-content"></div>
      </div>` : '';

    const canResume = (!isUser && isLast && (m.stopped === true));

    const metricsInner = (!isUser) ? msgMetricsHtml(m.metrics || null) : '';
    const ragSources = (!isUser) ? ragSourcesHtml(m) : '';

    wrap.innerHTML = `
      <div class="message-avatar">${avatar}</div>
      <div class="message-wrapper">
        <div class="message-header"><span>${esc(who)}</span><span>${fmt(m.created_at)}</span></div>
        ${activity}
        ${thinking}
        <div class="message-content">${content}${atts}</div>
        ${ragSources}
        <div class="message-actions">
          <button class="action-btn" data-action="edit" title="Edit">✏</button>
          <button class="action-btn" data-action="copy" title="Copy">⧉</button>
          <button class="action-btn" data-action="speak" title="Read aloud" aria-label="Read aloud">${iconSvg('volume')}</button>
          ${!isUser?`<div class="msg-metrics${metricsReady(m.metrics||null)?' ready':''}"><button class="action-btn metric-btn" data-action="metrics" title="Stats">ⓘ</button><div class="metrics-pop">${metricsInner}</div></div>`:''}
          ${!isUser?'<button class="action-btn" data-action="regen" title="Regenerate">↻</button>':''}
          ${canResume?'<button class="action-btn" data-action="resume" title="Resume">▶</button>':''}
          <button class="action-btn danger" data-action="delete" title="Delete">${iconSvg('trash')}</button>
        </div>
      </div>
    `;
    if (hasReasoning) setThinkingText(wrap.querySelector('.thinking-content'), m.reasoning || '');
    return wrap;
  }

  const scheduleAgentActivityStateSave = debounce(()=>{
    if (!state.currentChat || state.loadingChat) return;
    saveChat(state.currentChat).catch(()=>{});
  }, 250);

  on('click', '.agent-activity-header', (e, header)=>{
    e.preventDefault();
    const section = header.closest('.agent-activity-section');
    if (!section) return;

    const collapsed = !section.classList.contains('collapsed');
    section.classList.toggle('collapsed', collapsed);
    header.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
    const arrow = header.querySelector('.agent-activity-chevron');
    if (arrow) arrow.textContent = collapsed ? '▼' : '▲';

    // Keep the user's choice stable while streaming replaces the activity DOM,
    // and persist it with the message so reopening the chat preserves the state.
    const msgEl = section.closest('.message');
    const idx = Number(msgEl?.dataset?.msgIndex);
    const message = Number.isInteger(idx) ? state.currentChat?.messages?.[idx] : null;
    if (message) {
      message.activity_collapsed = collapsed;
      scheduleAgentActivityStateSave();
    }
  });

  on('click', '.agent-activity-cancel', async (e, btn)=>{
    e.preventDefault();
    e.stopPropagation();
    const action = String(btn.dataset.cancelAction || '').trim();
    const serverId = String(btn.dataset.serverId || '').trim();
    const jobId = String(btn.dataset.jobId || '').trim();
    if (!jobId || btn.disabled) return;
    if (action === 'mcp_cancel' && !serverId) return;
    if (!['mcp_cancel','comfyui_cancel'].includes(action)) return;
    btn.disabled = true;
    const oldText = btn.textContent;
    btn.textContent = 'Stopping…';
    try {
      // Out-of-band job cancellation only. Keep the chat stream alive so the
      // tool call can observe the cancellation and the agent can recover/explain.
      if (action === 'comfyui_cancel') {
        const result = await api('comfyui_cancel', {chat_id:String(state.currentChat?.id || ''), job_id:jobId});
        btn.textContent = result?.cancelled === false ? 'Already stopped' : 'Stopping…';
      } else {
        const result = await api('mcp_cancel', {chat_id:String(state.currentChat?.id || ''), server_id:serverId, job_id:jobId});
        const cancelResult = result?.result || {};
        const found = cancelResult.found;
        const requested = cancelResult.cancellation_requested;
        const attempted = cancelResult.termination_attempted;
        const succeeded = cancelResult.termination_succeeded;

        if (found === false) {
          btn.textContent = 'Not running';
        } else if (requested !== true) {
          btn.disabled = false;
          btn.textContent = 'Stop rejected';
        } else if (attempted === true && succeeded === false) {
          btn.disabled = false;
          btn.textContent = 'Stop failed';
          btn.title = 'The MCP server found the job but could not terminate its process tree';
        } else {
          btn.textContent = attempted === true ? 'Stopping…' : 'Stop queued';
        }
      }
    } catch (ex) {
      btn.disabled = false;
      btn.textContent = oldText;
      console.error(`${action || 'Job'} cancellation request failed`, ex);
    }
  });

  on('click', '.thinking-header', (e, header)=>{
    const content = header.nextElementSibling;
    const arrow = header.querySelector('span:last-child');
    content.classList.toggle('expanded');
    arrow.textContent = content.classList.contains('expanded')?'▲':'▼';
    // When opening, auto-scroll the reasoning box to the bottom.
    maybeScrollThinking(content);
    scrollBottom();
  });

    on('click', '.code-copy', async (e, btn)=>{
    e.preventDefault();
    e.stopPropagation();
    const codeEl = btn.closest('.codeblock')?.querySelector('code');
    const txt = codeEl?.textContent || '';
    if(!txt) return;
    try{ await navigator.clipboard.writeText(txt); }
    catch(_){
      const ta=document.createElement('textarea'); ta.value=txt; document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove();
    }
    const old = btn.textContent;
    btn.textContent = '✓';
    setTimeout(()=>{ btn.textContent = old; }, 800);
  });

  const codeLang = (codeEl)=>{
    const cls = String(codeEl?.className || '');
    const m = cls.match(/\blanguage-([a-z0-9_+-]+)\b/i);
    return m ? String(m[1]).toLowerCase() : '';
  };
  const extForLang = (lang, txt)=>{
    const l = String(lang||'').toLowerCase();
    const map = {
      html:'html', htm:'html', css:'css', svg:'svg', xml:'xml',
      js:'js', javascript:'js', mjs:'js', ts:'ts', typescript:'ts',
      py:'py', python:'py',
      json:'json', yaml:'yml', yml:'yml',
      md:'md', markdown:'md',
      sh:'sh', bash:'sh', zsh:'sh', shell:'sh',
      sql:'sql', php:'php', go:'go', rust:'rs', java:'java',
      c:'c', cpp:'cpp', 'c++':'cpp', csharp:'cs', cs:'cs',
      mermaid:'mmd'
    };
    if (map[l]) return map[l];
    const s = String(txt||'').trim();
    if (/^<svg[\s>]/i.test(s)) return 'svg';
    if (/^<!doctype\s+html/i.test(s) || /^<html[\s>]/i.test(s)) return 'html';
    return 'txt';
  };
  const mimeForExt = (ext)=>{
    const e = String(ext||'').toLowerCase();
    const map = {
      html:'text/html;charset=utf-8',
      css:'text/css;charset=utf-8',
      js:'text/javascript;charset=utf-8',
      ts:'text/plain;charset=utf-8',
      json:'application/json;charset=utf-8',
      yml:'text/yaml;charset=utf-8',
      md:'text/markdown;charset=utf-8',
      svg:'image/svg+xml;charset=utf-8',
      xml:'application/xml;charset=utf-8'
    };
    return map[e] || 'text/plain;charset=utf-8';
  };

  on('click', '.code-download', (e, btn)=>{
    e.preventDefault();
    e.stopPropagation();
    const codeEl = btn.closest('.codeblock')?.querySelector('code');
    const txt = codeEl?.textContent || '';
    if (!String(txt).length) return;
    const lang = codeLang(codeEl);
    const ext = extForLang(lang, txt);
    const safeLang = (lang || 'code').replace(/[^a-z0-9_-]+/ig, '') || 'code';
    const stamp = new Date().toISOString().replace(/[:.]/g,'-');
    const filename = `${safeLang}-${stamp}.${ext}`;
    const blob = new Blob([txt], { type: mimeForExt(ext) });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(()=>{ try{ URL.revokeObjectURL(url); }catch(_){} }, 1500);
  });


  on('click', '.code-preview', (e, btn)=>{
    e.preventDefault();
    e.stopPropagation();

    const codeEl = btn.closest('.codeblock')?.querySelector('code');
    const html = codeEl?.textContent || '';
    if (!String(html).trim()) return;

    // Try to pick up CSS from the same message (common LLM pattern: separate ```html and ```css fences).
    const msgEl = btn.closest('.message');
    let css = '';
    if (msgEl){
      const cssBlocks = Array.from(msgEl.querySelectorAll('.codeblock code.language-css'));
      css = cssBlocks.map(el=>el.textContent || '').filter(Boolean).join('\n\n');
    }

    const type = String(btn.dataset.previewType || 'html').toLowerCase();

    if (type === 'svg'){
      const baseCss = 'html,body{margin:0;padding:0;height:100%;} body{display:flex;align-items:stretch;} svg{width:100%;height:100%;}';
      const doc = buildHtmlPreviewDoc(html, [baseCss, css].filter(Boolean).join('\n\n'));
      previewModal.open('SVG Preview', doc);
      return;
    }

    const doc = buildHtmlPreviewDoc(html, css);
    previewModal.open('HTML Preview', doc);
  });

on('click', '.message .action-btn', async (e, btn)=>{
    const action = btn.dataset.action;
    const idx = parseInt(btn.closest('.message')?.dataset.msgIndex||'-1',10);
    if(!state.currentChat || !Number.isFinite(idx) || idx<0) return;

    if(action==='speak'){
      e.preventDefault();
      e.stopPropagation();
      speakMessage(idx);
      return;
    }

    if(action==='metrics'){
      e.preventDefault();
      e.stopPropagation();
      const box = btn.closest('.msg-metrics');
      if (!box) return;
      // close other open popovers
      document.querySelectorAll('.msg-metrics.open').forEach(el=>{ if (el!==box) el.classList.remove('open'); });
      box.classList.toggle('open');
      return;
    }

    if(action==='copy'){
      const txt = state.currentChat.messages[idx]?.content || '';
      try{ await navigator.clipboard.writeText(txt); }catch(_){
        const ta=document.createElement('textarea'); ta.value=txt; document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove();
      }
    }
    if(action==='edit') startEdit(idx);
    if(action==='regen') await regenerate(idx);
    if(action==='resume') await resumeGeneration(idx);
    if(action==='delete') await deleteMessage(idx);
  });

  async function deleteMessage(idx){
    if(isCurrentChatStreaming()) return;
    if(!state.currentChat) return;
    const msgs = state.currentChat.messages || [];
    const m = msgs[idx];
    if(!m) return;

    const role = (m.role==='user') ? 'User' : 'Assistant';
    const preview = String(m.content||'').trim().slice(0, 120);
    const ok = confirm(`Delete message?\n\n${role}: ${preview}${preview.length===120?'…':''}`);
    if(!ok) return;

    msgs.splice(idx, 1);
    state.currentChat.messages = msgs;
    await saveChat();
    await reloadSidebar();
    renderMessages();
    updateTokenBarIdle();
  }


  on('click', '.att-view', async (e, btn)=>{
    e.preventDefault(); e.stopPropagation();
    const mi = Number(btn.dataset.msgIndex);
    const ai = Number(btn.dataset.attIndex);
    const m = state.currentChat?.messages?.[mi];
    const a = m?.attachments?.[ai];
    if (!a || (!a.text && !a.file_id)) return;
    const title = a.name ? `Extraction · ${a.name}` : 'Extraction';
    try {
      if (!a.text && a.file_id) extractModal.open(title, 'Extracting text from stored document…');
      const text = await attachmentTextForView(a);
      extractModal.open(title, text);
    } catch (err) {
      extractModal.close();
      alert(String(err?.message || err || 'Could not extract document text'));
    }
  });

  on('click', '.att-delete', async (e, btn)=>{
    e.preventDefault(); e.stopPropagation();
    const mi = Number(btn.dataset.msgIndex);
    const ai = Number(btn.dataset.attIndex);
    const m = state.currentChat?.messages?.[mi];
    const a = m?.attachments?.[ai];
    if (!a || !a.file_id) return;
    const ok = confirm('Really delete this file from the server?');
    if(!ok) return;
    try{
      await deleteStoredFileWithForce(a.file_id);
    }catch(err){
      if (!err?.cancelled) alert(String(err?.message || err));
      return;
    }
    // Keep attachment but remove server link so UI reflects deletion
    a.url = '';
    a.file_id = '';
    a.not_sent = true;
    a.note = 'Deleted from server';
    await saveChat();
    renderMessages();
  });

  on('click', '.att-remove', async (e, btn)=>{
    e.preventDefault(); e.stopPropagation();
    if (isCurrentChatStreaming()) return;
    const mi = Number(btn.dataset.msgIndex);
    const ai = Number(btn.dataset.attIndex);
    const m = state.currentChat?.messages?.[mi];
    if (!m || !Array.isArray(m.attachments)) return;
    const a = m.attachments[ai];
    if (!a) return;

    // If the attachment still exists on the server, we keep it there (use the trash button to delete server-side).
    const ok = confirm(`Remove attachment from message?

${String(a.name||a.url||a.type||'attachment').slice(0,120)}`);
    if(!ok) return;

    m.attachments.splice(ai, 1);
    if (m.attachments.length === 0) delete m.attachments;

    await saveChat();
    renderMessages();
    renderWebTools();
  });

  function startEdit(idx){
    const m = state.currentChat.messages[idx];
    const el = chatMsgs.querySelector(`.message[data-msg-index="${idx}"] .message-content`);
    if(!m||!el) return;
    const original = m.content||'';
    const ta=document.createElement('textarea');
    ta.value=original;
    ta.style.width='100%';
    ta.style.minHeight='120px';
    ta.style.background='var(--input-bg)';
    ta.style.border='1px solid var(--border)';
    ta.style.borderRadius='10px';
    ta.style.color='var(--text-primary)';
    ta.style.padding='10px';
    ta.style.resize='vertical';

    const row=document.createElement('div');
    row.style.display='flex'; row.style.gap='8px'; row.style.marginTop='10px';
    const save=document.createElement('button'); save.className='btn btn-primary'; save.textContent='Save';
    const cancel=document.createElement('button'); cancel.className='btn btn-ghost'; cancel.textContent='Cancel';
    row.append(save,cancel);

    el.innerHTML='';
    el.append(ta,row);
    ta.focus();

    const done = async (ok)=>{
      if(!ok){ renderMessages(); return; }
      m.content = ta.value;
      m.edited_at = now();
      await saveChat();
      await reloadSidebar();
      renderMessages();
    };
    save.addEventListener('click', ()=>done(true));
    cancel.addEventListener('click', ()=>done(false));
    ta.addEventListener('keydown', (e)=>{ if(e.key==='Escape'){ e.preventDefault(); done(false); }});
  }

  async function regenerate(idx){
    if(isCurrentChatStreaming()) return;
    const msgs = state.currentChat.messages || [];
    if(idx<=0 || idx>=msgs.length) return;
    if(msgs[idx].role!=='assistant') return;
    let userIdx=-1;
    for(let i=idx-1;i>=0;i--){ if(msgs[i].role==='user'){ userIdx=i; break; } }
    if(userIdx<0) return;

    // Regenerate truncates/replaces the assistant message. Make sure billed $ doesn't reset.
    // If this chat doesn't yet have a billed accumulator, seed it from the currently visible messages.
    if (!state.currentChat.meta || !state.currentChat.meta.billed) {
      const c = sumChatCost(state.currentChat);
      if (c && c.any) {
        const b = ensureChatBilled(state.currentChat);
        if (b) { b.usd = c.usd; b.any = true; }
      }
    }
    state.currentChat.messages = msgs.slice(0, userIdx+1);
    state.currentChat.messages.push({role:'assistant', content:'', reasoning:'', activity:[], activity_total:0, activity_collapsed:false, created_at: now(), model: state.ui.model, connection_id: state.ui.connectionId, incomplete:true, stopped:false});
    renderMessages();
    await streamAssistantForChat(state.currentChat, { mode:'new', assistantIdx: state.currentChat.messages.length-1 });
  }

  async function resumeGeneration(idx){
    if(isCurrentChatStreaming()) return;
    if(!state.currentChat) return;
    const msgs = state.currentChat.messages || [];
    if (idx < 0 || idx >= msgs.length) return;
    const m = msgs[idx];
    if (!m || m.role !== 'assistant') return;
    if (idx !== msgs.length - 1) return; // only resume the latest assistant turn
    if (!(m.stopped === true || m.incomplete === true)) return;

    await streamAssistantForChat(state.currentChat, { mode:'resume', assistantIdx: idx });
  }

  // ---------- Load / save ----------
  async function openChat(id){
    // Stop any active read-aloud when switching chats.
    stopTts();
    const chatId = String(id);
    // Keep the previous chat in memory (important if it is currently streaming).
    if (state.currentChat?.id != null) state.chatCache.set(String(state.currentChat.id), state.currentChat);

    localStorage.setItem('last_chat_id', chatId);

    // Prefer in-memory chat (keeps streaming tokens), otherwise fetch.
    let next = state.chatCache.get(chatId);
    if (!next){
      const res = await api('chat_get', {id: chatId});
      next = res.chat;
      state.chatCache.set(chatId, next);
    }
    state.currentChat = next;

    state.loadingChat = true;
    try {
      state.currentChat.meta = state.currentChat.meta || {};
      state.currentChat.messages = state.currentChat.messages || [];

      // Backward compatibility: if a stored assistant message contains inline <think>...</think>
      // but no separate reasoning field, extract and persist in-memory.
      for (const m of state.currentChat.messages) {
        if (!m || m.role !== 'assistant') continue;
        if (m.reasoning && String(m.reasoning).trim()) continue;
        if (typeof m.content !== 'string') continue;
        const match = m.content.match(/<think>([\s\S]*?)<\/think>/i);
        if (match && match[1] != null) {
          m.reasoning = (m.reasoning || '') + match[1];
          m.content = m.content.replace(/<think>[\s\S]*?<\/think>/ig, '').trim();
        }
      }

      // Prefer chat-specific selection, otherwise keep global selection.
      if (state.currentChat.connection_id) state.ui.connectionId = state.currentChat.connection_id;
      if (state.currentChat.model) state.ui.model = state.currentChat.model;

      // Per-chat system prompt + params
      const sp = (state.currentChat.meta.system_prompt ?? state.defaults.systemPrompt ?? '');
      state.ui.systemPrompt = sp;
      if (systemPromptEl) systemPromptEl.value = sp;
      applyParamsToUI(state.currentChat.meta.params || {});

      // Per-chat webtools toggle.
      // If the chat has an explicit override, use it; otherwise default to the global setting.
      const wt = state.currentChat.meta.webtools;
      if (wt && typeof wt === 'object') {
        state.webtools.web = !!wt.web;
        state.webtools.search = !!(wt.search ?? wt.webSearch);
        state.webtools.rag = !!wt.rag;
        state.webtools.rag_mode = normalizeChatRagMode(wt.rag_mode ?? wt.ragMode ?? 'default');
        state.webtools.image = !!(wt.image ?? wt.img ?? wt.image_generation);
        state.webtools.document = !!(wt.document ?? wt.doc ?? wt.workspace);
        state.webtools.code_workspace = !!wt.code_workspace;
        state.webtools.workspace_id = String(wt.workspace_id || '');
        state.webtools.workspace_name = String(wt.workspace_name || '');
        state.webtools.workspace_access = String(wt.workspace_access || 'write') === 'read' ? 'read' : 'write';
        state.webtools.workspace_strategy = 'efficient';
        state.webtools.workspace_offer_download = wt.workspace_offer_download !== false;
        state.webtools.custom_tools = Array.isArray(wt.custom_tools) ? wt.custom_tools : [];
        state.webtools.mcp_servers = Array.isArray(wt.mcp_servers) ? wt.mcp_servers : [];
      } else {
        state.webtools.web = !!state.ui.webAutoEnable;
        state.webtools.search = !!state.ui.webSearchAutoEnable;
        state.webtools.rag = !!state.ui.ragAvailable && !!state.ui.ragAutoEnable;
        state.webtools.rag_mode = 'default';
        state.webtools.image = !!state.ui.imageAutoEnable;
        state.webtools.document = false;
        state.webtools.code_workspace = false;
        state.webtools.workspace_id = '';
        state.webtools.workspace_name = '';
        state.webtools.workspace_access = 'write';
        state.webtools.workspace_strategy = 'efficient';
        state.webtools.workspace_offer_download = true;
        state.webtools.custom_tools = defaultCustomToolNames();
        state.webtools.mcp_servers = defaultMcpServerIds();
      }
      if (!state.ui.ragAvailable) state.webtools.rag = false;
      renderWebTools();
      renderDocumentUI();

      if (state.ui.model) modelBtn.firstChild.textContent = headerModelText() + ' ';
      syncRouterEventStream();
      syncCurrentModelContext();
    } finally {
      state.loadingChat = false;
    }

    renderSidebar();
    renderMessages();
    syncSend();
  }

  async function saveChat(chat = state.currentChat){
    if(!chat) return;
    // Keep an in-memory copy so streaming tokens don't get overwritten by a fresh chat_get.
    if (chat?.id != null) state.chatCache.set(String(chat.id), chat);
    // title from first user if default
    if(!chat.title || chat.title==='New chat'){
      const first = (chat.messages||[]).find(m=>m.role==='user' && (m.content||'').trim());
      if(first) {
        chat.title = first.content.trim().slice(0,60);
        // Keep sidebar + cache consistent so later actions (e.g. model switch) don't overwrite the DB title.
        if (chat?.id != null) patchChatTitle(chat.id, chat.title);
      }
    }
    const last = [...(chat.messages||[])].reverse().find(m=>m.role==='user' && (m.content||'').trim());
    const preview = last ? last.content.trim().slice(0,90) : '';
    await api('chat_save', {
      id: chat.id,
      title: chat.title || 'New chat',
      folder_id: chat.folder_id || null,
      connection_id: chat.connection_id || state.ui.connectionId || null,
      model: chat.model || state.ui.model || null,
      preview,
      messages: chat.messages || [],
      meta: chat.meta || {}
    });
  }

  function buildLlmMessages(chat, opts = {}){
    const uptoIdx = (opts.uptoIdx != null) ? opts.uptoIdx : ((chat.messages||[]).length - 1);
    const trimTrailingEmptyAssistant = (opts.trimTrailingEmptyAssistant !== false);

    const out = [];
    const msgs = chat.messages || [];
    for (let i = 0; i <= uptoIdx; i++){
      const m = msgs[i];
      if (!m || !m.role) continue;
      if (!['user','assistant','system'].includes(m.role)) continue;
      const mm = { role: m.role, content: m.content ?? '' };
      if (Array.isArray(m.attachments) && m.attachments.length) {
        if (m.role === 'user') {
          mm.attachments = m.attachments;
        } else if (state?.ui?.visionAutoAttachLastImage) {
          // Needed so the server can find the last generated image and attach it to the next user turn.
          // We only forward image attachments from non-user roles to avoid bloating the payload.
          const imgs = m.attachments.filter(a=>a && a.type==='image');
          if (imgs.length) mm.attachments = imgs;
        }
      }
      out.push(mm);
    }

    if (trimTrailingEmptyAssistant) {
      while (out.length) {
        const last = out[out.length-1];
        const empty = (last.role === 'assistant') && !String(last.content || '').trim() && !(last.attachments && last.attachments.length);
        if (empty) out.pop(); else break;
      }
    }
    return out;
  }

  function runningMcpCancelJobs(message){
    const jobs = [];
    const seen = new Set();
    for (const raw of (Array.isArray(message?.activity) ? message.activity : [])) {
      const event = normalizeAgentActivityEvent(raw);
      if (!event || event.status !== 'running' || event.cancel_action !== 'mcp_cancel') continue;
      if (!event.cancel_server_id || !event.cancel_job_id) continue;
      const key = `${event.cancel_server_id}\0${event.cancel_job_id}`;
      if (seen.has(key)) continue;
      seen.add(key);
      jobs.push({chat_id:String(state.currentChat?.id || ''), server_id:event.cancel_server_id, job_id:event.cancel_job_id});
    }
    return jobs;
  }

  function runningComfyUiCancelJobs(message){
    const jobs = [];
    const seen = new Set();
    for (const raw of (Array.isArray(message?.activity) ? message.activity : [])) {
      const event = normalizeAgentActivityEvent(raw);
      if (!event || event.status !== 'running' || event.cancel_action !== 'comfyui_cancel') continue;
      if (!event.cancel_job_id || seen.has(event.cancel_job_id)) continue;
      seen.add(event.cancel_job_id);
      jobs.push({chat_id:String(state.currentChat?.id || ''), job_id:event.cancel_job_id});
    }
    return jobs;
  }

  function stopCurrentStream(){
    const id = state.currentChat?.id;
    if (!id) return;
    const s = state.streams.get(String(id));
    if (!s) return;

    const messages = Array.isArray(state.currentChat?.messages) ? state.currentChat.messages : [];
    const activeMessage = [...messages].reverse().find(m=>m?.role === 'assistant' && (m?.incomplete === true || runningMcpCancelJobs(m).length || runningComfyUiCancelJobs(m).length));
    for (const job of runningMcpCancelJobs(activeMessage)) {
      // Separate requests are intentional: the chat stream may be blocked in a
      // long tool call while cancellation reaches the backend on another worker.
      api('mcp_cancel', job).catch(err=>console.error('MCP cancellation failed', err));
    }
    for (const job of runningComfyUiCancelJobs(activeMessage)) {
      api('comfyui_cancel', job).catch(err=>console.error('ComfyUI cancellation failed', err));
    }

    try{ s.controller?.abort(); }catch(_){/* noop */}
  }

  async function streamAssistantForChat(chat, opts = {}){
    if (!chat?.id) return;
    const chatId = String(chat.id);
    if (state.streams.has(chatId)) return;

    const assistantIdx = (opts.assistantIdx != null) ? opts.assistantIdx : ((chat.messages||[]).length - 1);
    const mode = opts.mode || 'new'; // 'new' | 'resume'

    // If this chat is currently open, sync per-chat config from UI before sending.
    const isActive = (state.currentChat?.id === chat.id);
    const params = isActive ? collectParams() : (chat.meta?.params || {});
    const systemPrompt = isActive ? (state.ui.systemPrompt || '') : (chat.meta?.system_prompt || '');
    const connectionId = isActive ? (state.ui.connectionId || chat.connection_id || null) : (chat.connection_id || null);
    const model = isActive ? (state.ui.model || chat.model || '') : (chat.model || '');

    // Persist the selection onto the chat so background streams keep their own settings.
    chat.connection_id = connectionId;
    chat.model = model;
    chat.meta = chat.meta || {};
    chat.meta.system_prompt = systemPrompt;
    chat.meta.params = params;

    // Mark message state for UI.
    const am = chat.messages?.[assistantIdx];
    if (am && am.role === 'assistant') {
      const wasIncomplete = !!am.incomplete;
      am.incomplete = true;
      am.stopped = false;

      // ---- Regenerate-friendly metrics handling ----
      // We keep a per-message run history so $ can accumulate across regenerates.
      // The visible (latest) tokens/stats still live at the top-level fields.
      const oldMet = (am.metrics && typeof am.metrics === 'object') ? am.metrics : {};
      const prevRuns = Array.isArray(oldMet.runs) ? oldMet.runs.slice() : [];

      // Migration: older chats stored only the latest run in metrics.*.
      // When we regenerate we would otherwise "forget" the prior billed price.
      const hasRuns = prevRuns.length > 0;
      const oldPt = Number(oldMet.prompt_tokens);
      const oldCt = Number(oldMet.completion_tokens);
      const oldTt = Number(oldMet.total_tokens);
      const oldPrice = Number(oldMet.price);
      const oldHasAny = Number.isFinite(oldPt) || Number.isFinite(oldCt) || Number.isFinite(oldTt) || Number.isFinite(oldPrice);
      if (!hasRuns && oldHasAny && !oldMet._active_run && !wasIncomplete) {
        prevRuns.push({
          id: `legacy-${now()}`,
          ts: now(),
          connection_id: String(am.connection_id || connectionId || ''),
          model: String(am.model || model || ''),
          prompt_tokens: Number.isFinite(oldPt) ? oldPt : null,
          completion_tokens: Number.isFinite(oldCt) ? oldCt : null,
          total_tokens: Number.isFinite(oldTt) ? oldTt : null,
          price: Number.isFinite(oldPrice) ? oldPrice : null
        });
      }

      // Reset visible per-message metrics so we don't show stale stats while regenerating,
      // but preserve the run history.
      am.metrics = { runs: prevRuns };

      // Snapshot the model used for THIS request.
      am.model = model;
      am.connection_id = connectionId;

      // Track the active run so we can finalize it exactly once on done.
      am.metrics._active_run = {
        id: `${now()}-${Math.random().toString(16).slice(2)}`,
        ts: now(),
        connection_id: String(connectionId || ''),
        model: String(model || '')
      };
    }

    // Build messages for the model.
    let llmMessages;
    if (mode === 'resume') {
      llmMessages = buildLlmMessages(chat, { uptoIdx: assistantIdx, trimTrailingEmptyAssistant: false });
      llmMessages.push({ role:'user', content: 'Continue exactly where you left off. Do not repeat. Do not restart the answer. If the interrupted work used an interactive terminal, first inspect existing terminal sessions and continue one if available; do not relaunch a long-running installation, VM, SSH session, or terminal command merely because the response stream was interrupted.' });
    } else {
      llmMessages = buildLlmMessages(chat, { trimTrailingEmptyAssistant: true });
    }

    // ---- Token metrics (rough /4 estimate while streaming; replaced by real stats once available) ----
    // IMPORTANT: include attachments too. buildLlmMessages keeps user attachments
    // in mm.attachments (PDF extractions, TXT, base64 images, URLs, notes, ...).
    // Images are ignored for estimation (varies wildly by backend and encoding).
    //
    // NOTE: While streaming we want P to never "jump backwards" just because our /4 estimator
    // undercounts a large existing context. So we anchor the estimate to the last finalized
    // request total (prompt+completion) and add only the new user turn (plus any synthetic
    // resume instruction) on top.
    const usageReset = !!chat?.meta?.usage_reset;
    const lastRun = usageReset ? { pt: 0, ct: 0 } : getLastRunTokens(chat);
    const prevTotalTok = usageReset ? 0 : (Number(lastRun.pt) + Number(lastRun.ct));

    let newUserTok = 0;
    if (mode === 'resume') {
      // Synthetic user nudge appended only for resume.
      newUserTok = estTok('Continue exactly where you left off. Do not repeat. Do not restart the answer. If the interrupted work used an interactive terminal, first inspect existing terminal sessions and continue one if available; do not relaunch a long-running installation, VM, SSH session, or terminal command merely because the response stream was interrupted.');
    } else {
      const um = chat.messages?.[assistantIdx - 1];
      if (um && um.role === 'user') {
        newUserTok = estTokFromContent(um.content) + estTokFromAttachments(um.attachments);
      }
    }

    const promptTokRaw = estTok(chat.meta?.system_prompt || '') + (llmMessages||[]).reduce((sum, mm)=> {
      return sum + estTokFromContent(mm.content) + estTokFromAttachments(mm.attachments);
    }, 0);

    // Stable prompt estimate used during streaming until backend stats arrive.
    const promptTok = Math.max(promptTokRaw, prevTotalTok + newUserTok);

    // Base = summed usage so far (exclude the assistant placeholder we're currently filling).
    // Keep P/T from metrics where available, but for C we recompute from the current message list
    // so deletes/older turns without metrics still behave intuitively.
    const baseUsage = sumChatUsage(chat, { excludeIdx: assistantIdx });
    const baseC = sumChatCompletionCurrent(chat, { excludeIdx: assistantIdx });
    // For cost we want *billed spend so far*, which includes previous runs of a regenerated message.
    // We reset visible metrics for the active assistant message, but keep its run history.
    const baseCost = getChatBilledCost(chat);

    // A tool/agent request may contain many distinct upstream model turns. The
    // backend reports real usage for each completed turn as agent_turn_stats.
    // Keep those turn records separate from the final message metrics while the
    // request is live so P/C/$ can advance at every tool boundary.
    const agentTurnUsage = new Map();
    // Current in-flight agent turn. Tool-call JSON is hidden from the normal
    // content stream, so the backend sends a rough live completion estimate
    // until real per-turn usage arrives.
    let agentLiveTurn = -1;
    let agentLiveCompletionTokens = 0;

    const agentUsageSummary = ()=>{
      if (!agentTurnUsage.size) return null;
      const turns = [...agentTurnUsage.values()].sort((a,b)=>a.turn-b.turn);
      const last = turns[turns.length - 1] || null;
      let completionTokens = 0;
      let totalTokens = 0;
      let price = 0;
      let allCompletionKnown = true;
      let allTotalKnown = true;
      let allPriceKnown = true;

      for (const rec of turns) {
        if (rec.ct == null) allCompletionKnown = false;
        else completionTokens += rec.ct;

        const turnTotal = rec.tt != null ? rec.tt : ((rec.pt != null && rec.ct != null) ? (rec.pt + rec.ct) : null);
        if (turnTotal == null) allTotalKnown = false;
        else totalTokens += turnTotal;

        if (rec.price == null) allPriceKnown = false;
        else price += rec.price;
      }

      return {
        turns,
        count: turns.length,
        last,
        completionTokens: allCompletionKnown ? completionTokens : null,
        totalTokens: allTotalKnown ? totalTokens : null,
        price: allPriceKnown ? price : null
      };
    };

    const rememberAgentTurnStats = (obj)=>{
      const rawTurn = Number(obj?.turn);
      const turn = Number.isFinite(rawTurn) ? Math.max(0, Math.trunc(rawTurn)) : agentTurnUsage.size;
      const numberOrNull = (v)=>{
        const n = Number(v);
        return Number.isFinite(n) ? n : null;
      };
      const pt = numberOrNull(obj?.prompt_tokens);
      const ct = numberOrNull(obj?.completion_tokens);
      const tt = numberOrNull(obj?.total_tokens);
      const promptTps = numberOrNull(obj?.prompt_tps);
      const genTps = numberOrNull(obj?.gen_tps);
      const turnPrice = (pt != null && ct != null) ? calcPrice(pt, ct, connectionId, model) : null;
      agentTurnUsage.set(turn, { turn, pt, ct, tt, promptTps, genTps, price: turnPrice });
      if (agentLiveTurn === turn) {
        agentLiveTurn = -1;
        agentLiveCompletionTokens = 0;
      }
      return agentUsageSummary();
    };

    const applyAgentUsageToMetrics = (m, summary)=>{
      if (!m || !summary?.last) return;
      m.metrics = m.metrics || {};
      const last = summary.last;
      if (last.promptTps != null) m.metrics.prompt_tps = last.promptTps;
      if (last.genTps != null) m.metrics.gen_tps = last.genTps;
      // prompt_tokens remains the latest model turn because that is the useful
      // context position. Completion/total usage spans every model turn in this
      // one agent run, which is what C/accounting need.
      if (last.pt != null) m.metrics.prompt_tokens = last.pt;
      if (summary.completionTokens != null) m.metrics.completion_tokens = summary.completionTokens;
      if (summary.totalTokens != null) m.metrics.total_tokens = summary.totalTokens;
      if (summary.price != null) m.metrics.price = summary.price;
      m.metrics.agent_turn_count = summary.count;
    };

    const statsT0 = performance.now();
    let statsLast = 0;

    const curUsage = ()=>{
      const m = chat.messages?.[assistantIdx];
      const met = (m && m.metrics && typeof m.metrics === 'object') ? m.metrics : {};
      const ptReal = Number.isFinite(Number(met.prompt_tokens)) ? Number(met.prompt_tokens) : null;
      const ctReal = Number.isFinite(Number(met.completion_tokens)) ? Number(met.completion_tokens) : null;
      const ttReal = Number.isFinite(Number(met.total_tokens)) ? Number(met.total_tokens) : null;

      const pt = (ptReal != null) ? ptReal : promptTok;

      // completion: estimate while streaming (content+reasoning), then replaced by backend completion_tokens
      const ctEst = estTok(m?.content) + estTok(m?.reasoning);
      const ct = (ctReal != null) ? ctReal : ctEst;

      const tt = (ttReal != null) ? ttReal : (pt + ct);

      const genTps = Number.isFinite(Number(met.gen_tps)) ? Number(met.gen_tps) : null;
      return { pt, ct, tt, genTps };
    };

    const updateStats = (force=false)=>{
      if (state.currentChat?.id !== chat.id) return;
      const now = performance.now();
      if (!force && (now - statsLast) < 120) return;
      statsLast = now;

      const cur = curUsage();
      const agentUsage = agentUsageSummary();
      const lastAgentTurn = agentUsage?.last || null;

      // For a normal response, P/C keep their existing live-estimate behavior.
      // Once an agent turn has finalized, prefer its real upstream usage and the
      // cumulative completion count across all completed turns in this run.
      const liveAgentCt = Math.max(0, Number(agentLiveCompletionTokens) || 0);
      const P = (lastAgentTurn?.pt != null && lastAgentTurn?.ct != null)
        ? (lastAgentTurn.pt + lastAgentTurn.ct + liveAgentCt)
        : (cur.pt + Math.max(cur.ct, liveAgentCt));
      const completedAgentCt = agentUsage?.completionTokens != null ? agentUsage.completionTokens : null;
      const C = baseC + (completedAgentCt != null ? (completedAgentCt + liveAgentCt) : Math.max(cur.ct, liveAgentCt));

      // Speed estimate: don't divide by the whole request time (which includes
      // initial network/model latency) or it will start low and creep upward.
      // Instead, start timing from the first produced tokens and use a short
      // rolling EMA over Δtokens/Δt. Agent turns can provide their own exact
      // generation speed; after each completed turn, prefer that value.
      const streamRec = state.streams.get(chatId);

      if (!agentUsage && streamRec && streamRec._firstTokAt == null && cur.ct > 0.2) {
        streamRec._firstTokAt = now;
        streamRec._lastSpeedAt = now;
        streamRec._lastSpeedCt = cur.ct;
      }

      let tpsRaw = 0;
      if (lastAgentTurn?.genTps != null) {
        tpsRaw = lastAgentTurn.genTps;
      } else if (cur.genTps != null) {
        tpsRaw = cur.genTps;
      } else if (!agentUsage && streamRec && streamRec._firstTokAt != null) {
        const baseAt = (streamRec._lastSpeedAt ?? streamRec._firstTokAt);
        const baseCt = (streamRec._lastSpeedCt ?? 0);
        const dt = (now - baseAt) / 1000;
        const dTok = cur.ct - baseCt;

        // Update EMA only when we actually received more tokens.
        if (dt >= 0.25 && dTok > 0.05) {
          const inst = dTok / dt;
          streamRec._tpsEma = (streamRec._tpsEma == null) ? inst : (streamRec._tpsEma * 0.75 + inst * 0.25);
          streamRec._lastSpeedAt = now;
          streamRec._lastSpeedCt = cur.ct;
        }

        const denom = Math.max(0.001, (now - streamRec._firstTokAt) / 1000);
        tpsRaw = streamRec._tpsEma ?? (cur.ct / denom);
      } else if (!agentUsage) {
        const elapsed = (now - statsT0) / 1000;
        tpsRaw = (elapsed > 0.3) ? (cur.ct / elapsed) : 0;
      }

      const tps = Number.isFinite(tpsRaw) ? (tpsRaw >= 10 ? Math.round(tpsRaw) : Number(tpsRaw.toFixed(1))) : 0;

      if (statusPromptTokEl) statusPromptTokEl.textContent = `P ${Math.round(P)}`;
      if (statusCompletionTokEl) statusCompletionTokEl.textContent = `C ${Math.round(C)}`;
      // CTX is model/runtime metadata, not per-turn usage. It is intentionally
      // left untouched during a running request.

      const curUsd = agentUsage?.price != null
        ? agentUsage.price
        : calcPrice(cur.pt, cur.ct, connectionId, model);
      const totalUsd = (baseCost.usd || 0) + (curUsd || 0);
      if (statusCostEl) {
        statusCostEl.textContent = (baseCost.any || (curUsd != null)) ? `~$${fmtUsd(totalUsd)}` : '';
      }
      const elapsedShown = (streamRec && streamRec._firstTokAt != null && !agentUsage)
        ? ((now - streamRec._firstTokAt) / 1000)
        : ((now - statsT0) / 1000);
      if (statusSpeedEl) statusSpeedEl.textContent = `${elapsedShown.toFixed(1)}s • ${tps} tok/s`;
    };

    const controller = new AbortController();
    state.streams.set(chatId, {
      controller,
      assistantIdx,
      startedAt: now(),
      promptTok,
      statsT0,
      mode,
      baseUsage,
      baseCost,
      // One request owns the complete temporary activity lifecycle: model load
      // -> prompt processing -> first generated output.
      runtimeActivityDismissed: false,
      promptProgress: null,
      // Streaming speed helpers
      _firstTokAt: null,
      _lastSpeedAt: null,
      _lastSpeedCt: 0,
      _tpsEma: null
    });
    syncChatStreamingClass();
    state.chatCache.set(chatId, chat);
    renderSidebar();
    if (state.currentChat?.id === chat.id) syncSend();
    updateStats(true);

    const payload = {
      chat_id: chat.id,
      connection_id: connectionId,
      model: model,
      system_prompt: chat.meta.system_prompt || '',
      params: chat.meta.params || {},
      messages: llmMessages,
      // Tool toggles from the composer (🌐 menu). Backend uses this to enable tool calling.
      webtools: {
        web: !!(state.webtools && state.webtools.web),
        search: !!(state.webtools && state.webtools.search),
        rag: !!(state.webtools && state.webtools.rag),
        rag_mode: normalizeChatRagMode(state.webtools?.rag_mode),
        image: !!(state.webtools && state.webtools.image),
        document: !!(state.webtools && state.webtools.document),
        code_workspace: !!(state.webtools && state.webtools.code_workspace),
        workspace_id: String(state.webtools?.workspace_id || ''),
        workspace_access: String(state.webtools?.workspace_access || 'write'),
        workspace_strategy: 'efficient',
        workspace_offer_download: state.webtools?.workspace_offer_download !== false,
        custom_tools: Array.isArray(state.webtools?.custom_tools) ? state.webtools.custom_tools : [],
        mcp_servers: Array.isArray(state.webtools?.mcp_servers) ? state.webtools.mcp_servers : []
      },
      rag: {
        documents: ragDocumentIdsForChat(chat),
        retrieval_mode: effectiveRagMode()
      },
      // Runtime truth for this exact request. The backend still persists defaults,
      // but it no longer guesses the active mode from a possibly stale DB value.
      mcp_context: {
        mode: String(state.ui?.mcpContextMode || 'externalize') === 'externalize' ? 'externalize' : 'full',
        externalize_above_tokens: mcpClamp(state.ui?.mcpExternalizeAboveTokens, 500, 200000, 6000),
        preview_max_tokens: mcpClamp(state.ui?.mcpPreviewMaxTokens, 200, 50000, 2500),
        full_first_pass_max_tokens: mcpClamp(state.ui?.mcpFullFirstPassMaxTokens, 0, 200000, 32000)
      },
      document: (state.webtools && state.webtools.document) ? documentStateForPayload(chat) : { mode: 'chat' },
      workspace: (state.webtools && state.webtools.code_workspace) ? {
        id: String(state.webtools.workspace_id || ''),
        access: String(state.webtools.workspace_access || 'write'),
        strategy: 'efficient',
        offer_download: state.webtools.workspace_offer_download !== false
      } : null
    };

    let res;
    try{
      // In router mode the normal chat request is allowed to autoload a cold
      // model. Arm the persistent status feed first so loading/progress events
      // cannot race past the UI.
      await ensureRouterEventStreamReady(connectionId);
      res = await fetch('api.php?action=chat_stream', {
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body: JSON.stringify(payload),
        signal: controller.signal
      });
    } catch(err){
      // Abort or network failure.
      if (controller.signal.aborted) {
        if (am) { am.stopped = true; am.incomplete = true; settleAgentActivity(am, 'error'); clearAgentArtifactLinks(am); }
      } else {
        if (am) { am.content = 'Error: ' + (err?.message||String(err)); am.incomplete = false; am.stopped = false; settleAgentActivity(am, 'error'); clearAgentArtifactLinks(am); }
      }
      state.streams.delete(chatId);
      syncChatStreamingClass();
      renderRuntimeActivity();
      renderSidebar();
      if (state.currentChat?.id === chat.id) { renderMessages(); syncSend(); updateTokenBarIdle(); }
      await saveChat(chat);
      await reloadSidebar();
      return;
    }

    if(!res.ok){
      const t = await res.text();
      if (am) { am.content = 'Error: ' + t; am.incomplete = false; am.stopped = false; settleAgentActivity(am, 'error'); }
      state.streams.delete(chatId);
      syncChatStreamingClass();
      renderRuntimeActivity();
      renderSidebar();
      if (state.currentChat?.id === chat.id) { renderMessages(); syncSend(); updateTokenBarIdle(); }
      await saveChat(chat);
      await reloadSidebar();
      return;
    }

    const reader = res.body.getReader();
    const dec = new TextDecoder('utf-8');
    let buf = '';

    // Reasoning deltas are often much finer-grained than answer deltas. Buffer only
    // their DOM writes until the next paint, then append the new text natively.
    // The full reasoning string still updates immediately in the chat state.
    let reasoningPending = '';
    let reasoningFrame = 0;

    const flushReasoningDom = ()=>{
      if (reasoningFrame) {
        cancelAnimationFrame(reasoningFrame);
        reasoningFrame = 0;
      }
      const pending = reasoningPending;
      reasoningPending = '';
      if (!pending || state.currentChat?.id !== chat.id) return;

      const m = chat.messages[assistantIdx];
      const msgEl = chatMsgs.querySelector(`.message[data-msg-index="${assistantIdx}"]`);
      if (!m || !msgEl) return;

      let section = msgEl.querySelector('.thinking-section');
      if(!section){
        const wrapper = msgEl.querySelector('.message-wrapper');
        const before = msgEl.querySelector('.message-content');
        if (!wrapper || !before) return;
        section = document.createElement('div');
        section.className='thinking-section';
        section.innerHTML = `<div class="thinking-header">🧠 Reasoning <span>▼</span></div><div class="thinking-content"></div>`;
        wrapper.insertBefore(section, before);
      }

      const contentEl = section.querySelector('.thinking-content');
      if (!contentEl) return;

      const full = String(m.reasoning || '');
      const renderedChars = Number(contentEl.dataset.reasoningChars);
      const expectedBeforeAppend = full.length - pending.length;

      if (Number.isFinite(renderedChars) && renderedChars === expectedBeforeAppend) {
        const previousRawEndsCr = expectedBeforeAppend > 0 && full.charCodeAt(expectedBeforeAppend - 1) === 13;
        appendThinkingText(contentEl, pending, full.length, previousRawEndsCr);
      } else {
        // A full message rerender may have replaced the node while a frame was queued.
        // Resynchronize once; normal streaming continues incrementally afterwards.
        setThinkingText(contentEl, full);
      }

      maybeScrollThinking(contentEl);
      scrollBottom();
      updateStats();
    };

    const scheduleReasoningDom = ()=>{
      if (reasoningFrame) return;
      reasoningFrame = requestAnimationFrame(()=>{
        reasoningFrame = 0;
        flushReasoningDom();
      });
    };

    const applyDelta = (type, delta)=>{
      const m = chat.messages[assistantIdx];
      if(!m) return;
      if(type==='content') m.content = (m.content||'') + delta;
      if(type==='reasoning') m.reasoning = (m.reasoning||'') + delta;

      // Only patch the DOM when this chat is the one currently displayed.
      if (state.currentChat?.id !== chat.id) return;

      if(type==='reasoning'){
        reasoningPending += delta;
        scheduleReasoningDom();
        return;
      }

      const msgEl = chatMsgs.querySelector(`.message[data-msg-index="${assistantIdx}"]`);
      if(!msgEl) return;
      if(type==='content'){
        const contentEl = msgEl.querySelector('.message-content');
        if(contentEl) contentEl.innerHTML = md(m.content||'');
          scheduleFitMermaid(msgEl);
      }
      scrollBottom();
      updateStats();
    };

    // Small UI signal from backend (e.g. web_read start/done)
    let statusEl = null;
    let statusRevision = 0;
    const setStreamStatus = (text, phase='')=>{
      if (!text) return 0;
      if (state.currentChat?.id !== chat.id) return 0;
      statusRevision++;
      if (!statusEl) {
        statusEl = document.createElement('div');
        statusEl.className = 'stream-status';
        statusEl.innerHTML = `<span class="pill"></span>`;
        chatMsgs.appendChild(statusEl);
      }
      statusEl.classList.toggle('done', phase === 'done');
      statusEl.classList.toggle('error', phase === 'error');
      const pill = statusEl.querySelector('.pill');
      if (pill) pill.textContent = text;
      scrollBottom();
      return statusRevision;
    };
    const clearStreamStatus = ()=>{
      statusRevision++;
      if (statusEl && statusEl.parentElement) statusEl.parentElement.removeChild(statusEl);
      statusEl = null;
    };

    let ended = false;
    try{
      while(true){
        const {done, value} = await reader.read();
        if(done) break;
        buf += dec.decode(value, {stream:true});
        let idx;
        while((idx = buf.indexOf('\n\n')) !== -1){
          const block = buf.slice(0, idx);
          buf = buf.slice(idx+2);
          const lines = block.split('\n').map(l=>l.trim()).filter(Boolean);
          for(const line of lines){
            if(!line.startsWith('data:')) continue;
            const data = line.slice(5).trim();
            if(!data) continue;
            let obj;
            try{ obj = JSON.parse(data); }catch(_){ continue; }
            if(obj.type==='status'){
              const msg = obj.message || '';
              const phase = obj.phase || '';
              const revision = msg ? setStreamStatus(msg, phase) : 0;
              if ((phase === 'done' || phase === 'error') && revision) {
                // Do not let an old completion timer erase the next tool's status.
                const delay = phase === 'error' ? 4000 : 2500;
                setTimeout(()=>{
                  if (statusRevision === revision) clearStreamStatus();
                }, delay);
              }
              continue;
            }

            if(obj.type==='activity'){
              const m = chat.messages[assistantIdx];
              if (m && upsertAgentActivity(m, obj.event)) {
                if (state.currentChat?.id === chat.id) {
                  const msgEl = chatMsgs.querySelector(`.message[data-msg-index="${assistantIdx}"]`);
                  const activityId = String(obj.event?.id || '').trim();
                  const mergedEvent = activityId
                    ? (m.activity || []).find(x=>String(x?.id || '') === activityId) || obj.event
                    : obj.event;
                  renderAgentActivityDom(msgEl, m, mergedEvent);
                  scrollBottom();
                }
              }
              continue;
            }

            if(obj.type==='mcp_artifacts_cleared'){
              const m = chat.messages[assistantIdx];
              if (m && clearAgentArtifactLinks(m) && state.currentChat?.id === chat.id) {
                const msgEl = chatMsgs.querySelector(`.message[data-msg-index="${assistantIdx}"]`);
                renderAgentActivityDom(msgEl, m);
                updateStats(true);
              }
              continue;
            }

            if(obj.type==='mcp_context_savings'){
              const m = chat.messages[assistantIdx];
              if (m){
                m.metrics = m.metrics || {};
                const saved = Number(obj.saved_tokens);
                const count = Number(obj.artifact_count);
                if (Number.isFinite(saved)) m.metrics.mcp_context_saved_tokens = Math.max(0, Math.round(saved));
                if (Number.isFinite(count)) m.metrics.mcp_artifact_count = Math.max(0, Math.round(count));
                m.metrics.mcp_context_mode = String(obj.mode || 'externalize');
                if (String(obj.mode || '') === 'externalize') state.ui.mcpContextMode = 'externalize';
                if (state.currentChat?.id === chat.id) updateStats(true);
              }
              continue;
            }

            if(obj.type==='rag_sources'){
              const m = chat.messages[assistantIdx];
              if (m) {
                // Keep provenance in state, but do not tear down/rebuild the
                // assistant DOM immediately before token streaming starts.
                // The normal final render shows the source cards after generation.
                m.rag_sources = Array.isArray(obj.sources) ? obj.sources : [];
              }
              continue;
            }

            if(obj.type==='rag_retrieval_progress'){
              setRagRetrievalProgressForChat(chatId, obj);
              continue;
            }

            if(obj.type==='rag_retrieval_progress_done'){
              clearRagRetrievalProgressForChat(chatId);
              continue;
            }

            if(obj.type==='prompt_progress'){
              setPromptProgressForChat(chatId, obj);
              continue;
            }

            if(obj.type==='prompt_progress_done'){
              clearPromptProgressForChat(chatId);
              continue;
            }

            if(obj.type==='agent_turn_progress'){
              const rawTurn = Number(obj.turn);
              const rawCt = Number(obj.completion_tokens_estimate);
              if (Number.isFinite(rawCt) && rawCt >= 0) {
                const turn = Number.isFinite(rawTurn) ? Math.max(0, Math.trunc(rawTurn)) : agentLiveTurn;
                if (turn !== agentLiveTurn) {
                  agentLiveTurn = turn;
                  agentLiveCompletionTokens = 0;
                }
                // Progress for one upstream turn must be monotonic. Real stats
                // arriving in agent_turn_stats reset this temporary estimate.
                agentLiveCompletionTokens = Math.max(agentLiveCompletionTokens, rawCt);
                if (state.currentChat?.id === chat.id) updateStats(true);
              }
              continue;
            }

            if(obj.type==='agent_turn_stats'){
              const summary = rememberAgentTurnStats(obj);
              const m = chat.messages[assistantIdx];
              if (m && summary) {
                applyAgentUsageToMetrics(m, summary);
                if (state.currentChat?.id === chat.id) {
                  const msgEl = chatMsgs.querySelector(`.message[data-msg-index="${assistantIdx}"]`);
                  if (msgEl) setMsgMetricsDom(msgEl, m.metrics);
                  updateStats(true);
                }
              }
              continue;
            }

            if(obj.type==='stats'){
              const m = chat.messages[assistantIdx];
              if (m){
                m.metrics = m.metrics || {};
                const p = Number(obj.prompt_tps);
                const g = Number(obj.gen_tps);
                if (Number.isFinite(p)) m.metrics.prompt_tps = p;
                if (Number.isFinite(g)) m.metrics.gen_tps = g;

                const pt = Number(obj.prompt_tokens);
                const ct = Number(obj.completion_tokens);
                const tt = Number(obj.total_tokens);
                if (Number.isFinite(pt)) m.metrics.prompt_tokens = pt;
                if (Number.isFinite(ct)) m.metrics.completion_tokens = ct;
                if (Number.isFinite(tt)) m.metrics.total_tokens = tt;

                // Compute per-request price (USD) if configured for this connection+model.
                const ptUse = Number.isFinite(Number(m.metrics.prompt_tokens)) ? Number(m.metrics.prompt_tokens) : null;
                const ctUse = Number.isFinite(Number(m.metrics.completion_tokens)) ? Number(m.metrics.completion_tokens) : null;
                if (ptUse != null || ctUse != null) {
                  const usd = calcPrice(ptUse || 0, ctUse || 0, (m.connection_id || connectionId), (m.model || model));
                  if (usd != null) m.metrics.price = usd;
                }

                if (state.currentChat?.id === chat.id) {
                  const msgEl = chatMsgs.querySelector(`.message[data-msg-index="${assistantIdx}"]`);
                  if (msgEl) setMsgMetricsDom(msgEl, m.metrics);
                  updateStats(true);
                }
              }
              continue;
            }

            if(obj.type==='document_update'){
              if (obj.document) applyDocumentUpdate(obj.document, chat);
              continue;
            }

            if(obj.type==='workspace_update'){
              if (obj.workspace) applyAgentWorkspaceUpdate(obj.workspace, chat);
              continue;
            }

            if(obj.type==='attachment'){
              const m = chat.messages[assistantIdx];
              if (m){
                m.attachments = m.attachments || [];
                if (obj.attachment) m.attachments.push(obj.attachment);
                if (state.currentChat?.id === chat.id) renderMessages();
              }
              continue;
            }
            if(obj.type==='done'){
              clearPromptProgressForChat(chatId);
              flushReasoningDom();
              const m = chat.messages[assistantIdx];
              const finalAgentUsage = agentUsageSummary();

              // Preserve aggregate usage across every internal model turn in an
              // agent run. The last turn's prompt remains the context anchor; C,
              // total usage and price cover the whole run.
              if (m && finalAgentUsage) applyAgentUsageToMetrics(m, finalAgentUsage);

              // If backend didn't send stats, fall back to our rough estimate so the UI isn't blank.
              if (m){
                m.metrics = m.metrics || {};
                if (!Array.isArray(m.metrics.runs)) m.metrics.runs = [];
                const ctEst = estTok(m?.content) + estTok(m?.reasoning);
                if (!Number.isFinite(Number(m.metrics.prompt_tokens))) m.metrics.prompt_tokens = promptTok;
                if (!Number.isFinite(Number(m.metrics.completion_tokens))) m.metrics.completion_tokens = ctEst;
                if (!Number.isFinite(Number(m.metrics.total_tokens))) m.metrics.total_tokens = Number(m.metrics.prompt_tokens||0) + Number(m.metrics.completion_tokens||0);

                // Also compute $ if a price is configured. For agent runs,
                // applyAgentUsageToMetrics already summed the price of every
                // internal model turn; do not overwrite it with last-prompt +
                // cumulative-completion arithmetic.
                if (finalAgentUsage?.price == null) {
                  const ptUse = Number(m.metrics.prompt_tokens) || 0;
                  const ctUse = Number(m.metrics.completion_tokens) || 0;
                  const usd = calcPrice(ptUse, ctUse, (m.connection_id || connectionId), (m.model || model));
                  if (usd != null) m.metrics.price = usd;
                }

                // Finalize this generation as a run (so Regenerate can accumulate $ across runs).
                const ar = (m.metrics && m.metrics._active_run && typeof m.metrics._active_run === 'object') ? m.metrics._active_run : null;
                const runId = String(ar?.id || `run-${now()}`);
                const already = m.metrics.runs.some(r => r && typeof r === 'object' && String(r.id||'') === runId);
                const hadEverGen = Number.isFinite(Number(chat?.meta?.total_gen_tok));
                const seedEverGen = hadEverGen ? null : (sumChatEverGen(chat, { excludeIdx: assistantIdx }).total || 0);
                if (!already) {
                  m.metrics.runs.push({
                    id: runId,
                    ts: Number(ar?.ts || now()),
                    connection_id: String(ar?.connection_id || m.connection_id || connectionId || ''),
                    model: String(ar?.model || m.model || model || ''),
                    prompt_tokens: Number.isFinite(Number(m.metrics.prompt_tokens)) ? Number(m.metrics.prompt_tokens) : null,
                    completion_tokens: Number.isFinite(Number(m.metrics.completion_tokens)) ? Number(m.metrics.completion_tokens) : null,
                    total_tokens: Number.isFinite(Number(m.metrics.total_tokens)) ? Number(m.metrics.total_tokens) : null,
                    price: Number.isFinite(Number(m.metrics.price)) ? Number(m.metrics.price) : null
                  });

                  // Add to chat-level billed spend so cost survives Regenerate (which replaces messages).
                  const runPrice = Number.isFinite(Number(m.metrics.price)) ? Number(m.metrics.price) : null;
                  if (runPrice != null) {
                    const hadBilled = !!(chat.meta && chat.meta.billed && typeof chat.meta.billed === 'object');
                    const b = ensureChatBilled(chat);
                    if (b) {
                      // If this is the first time we track billed spend for this chat, seed it from
                      // already-visible priced messages (excluding the current assistant idx), then add this run.
                      if (!hadBilled) {
                        const seed = sumChatCost(chat, { excludeIdx: assistantIdx });
                        if (seed && seed.any) { b.usd = seed.usd; b.any = true; }
                      }
                      b.usd += runPrice;
                      b.any = true;
                      b.runs += 1;
                    }
                  }
                  // Add to chat-level "ever generated" completion tokens (survives Regenerate).
                  const runCt = Number.isFinite(Number(m.metrics.completion_tokens)) ? Number(m.metrics.completion_tokens) : null;
                  if (runCt != null) {
                    chat.meta = chat.meta || {};
                    if (!Number.isFinite(Number(chat.meta.total_gen_tok))) chat.meta.total_gen_tok = (seedEverGen != null ? seedEverGen : 0);
                    chat.meta.total_gen_tok = (Number(chat.meta.total_gen_tok) || 0) + runCt;
                  }
                }
                // Clear active run marker.
                try{ delete m.metrics._active_run; }catch(_){ m.metrics._active_run = null; }
              }

              updateStats(true);

              const met = (m && m.metrics && typeof m.metrics === 'object') ? m.metrics : {};
              const lastAgentTurn = finalAgentUsage?.last || null;
              // These chat.meta fields seed P for the *next* request. Therefore
              // they must use only the last model turn, not cumulative agent
              // completion usage (which is already contained in that last prompt).
              const pt = lastAgentTurn?.pt != null
                ? lastAgentTurn.pt
                : (Number.isFinite(Number(met.prompt_tokens)) ? Number(met.prompt_tokens) : promptTok);
              const ct = lastAgentTurn?.ct != null
                ? lastAgentTurn.ct
                : (Number.isFinite(Number(met.completion_tokens)) ? Number(met.completion_tokens) : (estTok(m?.content) + estTok(m?.reasoning)));
              const tt = lastAgentTurn?.tt != null
                ? lastAgentTurn.tt
                : (pt + ct);

              const elapsed = (performance.now() - statsT0) / 1000;
              const tpsRaw = Number.isFinite(Number(met.gen_tps)) ? Number(met.gen_tps) : (elapsed > 0.15 ? (ct / elapsed) : 0);
              const tps = Number.isFinite(tpsRaw) ? (tpsRaw >= 10 ? Math.round(tpsRaw) : Number(tpsRaw.toFixed(1))) : 0;

              chat.meta = chat.meta || {};
              // If this chat was created via "compact & clone", we intentionally
              // started usage counters at zero. First real generation ends that.
              try{ delete chat.meta.usage_reset; }catch(_){ chat.meta.usage_reset = false; }
              chat.meta.last_prompt_tok = pt;
              chat.meta.last_completion_tok = ct;
              chat.meta.last_total_tok = tt;
              chat.meta.last_elapsed_s = Number(elapsed.toFixed(1));
              chat.meta.last_tps = tps;

              if (am) { am.incomplete = false; am.stopped = false; settleAgentActivity(am, 'done'); }
              clearStreamStatus();
              ended = true;
              break;
            }
            if(obj.type==='error'){
              clearPromptProgressForChat(chatId);
              flushReasoningDom();
              if (am) { am.content = 'Error: ' + (obj.error||'unknown'); am.incomplete = false; am.stopped = false; settleAgentActivity(am, 'error'); clearAgentArtifactLinks(am); }
              updateStats(true);
              clearStreamStatus();
              ended = true;
              break;
            }
            if(obj.type==='content' || obj.type==='reasoning') {
              clearPromptProgressForChat(chatId);
              applyDelta(obj.type, obj.delta||'');
            }
          }
          if (ended) break;
        }
        if (ended) break;
      }

      // A clean ReadableStream EOF is not the same as the protocol's terminal
      // `done` event. Treat a missing terminal frame as an interrupted response so
      // the UI cannot remain animated forever and Resume stays available.
      if (!ended && am) {
        am.stopped = true;
        am.incomplete = true;
        settleAgentActivity(am, 'error');
        clearAgentArtifactLinks(am);
      }
    } catch(err){
      if (controller.signal.aborted) {
        if (am) { am.stopped = true; am.incomplete = true; settleAgentActivity(am, 'error'); clearAgentArtifactLinks(am); }
      } else {
        if (am) { am.content = 'Error: ' + (err?.message||String(err)); am.incomplete = false; am.stopped = false; settleAgentActivity(am, 'error'); clearAgentArtifactLinks(am); }
      }
    } finally {
      flushReasoningDom();
      // Defensive final reconciliation for any backend/tool path that omitted its
      // terminal activity update.
      if (am) settleAgentActivity(am, (am.stopped || am.incomplete) ? 'error' : 'done');
      state.streams.delete(chatId);
      syncChatStreamingClass();
      renderRuntimeActivity();
      clearStreamStatus();
      renderSidebar();
      if (state.currentChat?.id === chat.id) { syncSend(); renderMessages(); updateTokenBarIdle(); }
      await saveChat(chat);
      await reloadSidebar();
    }
  }

  // ---------- Send / stream ----------
  async function send(){
    if(isCurrentChatStreaming() || state.webFetchBusy || ragDraftBlocked()) return;
    if (state.webtools?.rag && state.ui.ragAvailable) {
      const caps = await ensureRagCapabilities(state.currentChat);
      if (effectiveRagMode() === 'precise' && caps && caps.precise !== true) {
        showRagCapabilityNotice('Precise RAG unavailable', 'Choose Fast, Hybrid, or Default after configuring a reranker in ragd.');
        return;
      }
    }
    if(!state.currentChat){
      // A tool toggle can be selected before the first chat is persisted. Keep
      // that composer state across chat_create/openChat instead of resetting it.
      const draftWebtools = {
        web: !!state.webtools.web,
        search: !!state.webtools.search,
        rag: !!state.webtools.rag,
        rag_mode: normalizeChatRagMode(state.webtools.rag_mode),
        image: !!state.webtools.image,
        document: !!state.webtools.document,
        code_workspace: !!state.webtools.code_workspace,
        workspace_id: String(state.webtools.workspace_id || ''),
        workspace_name: String(state.webtools.workspace_name || ''),
        workspace_access: String(state.webtools.workspace_access || 'write'),
        workspace_strategy: 'efficient',
        workspace_offer_download: state.webtools.workspace_offer_download !== false,
        custom_tools: Array.isArray(state.webtools.custom_tools) ? [...state.webtools.custom_tools] : [],
        mcp_servers: Array.isArray(state.webtools.mcp_servers) ? [...state.webtools.mcp_servers] : []
      };
      const created = await api('chat_create', {folder_id:null});
      await reloadSidebar();
      await openChat(created.id);
      const draftCaps = state.ragCapabilities.get('__draft__');
      if (draftCaps) {
        state.ragCapabilities.set(String(created.id || ''), draftCaps);
        state.ragCapabilities.delete('__draft__');
      }
      Object.assign(state.webtools, draftWebtools);
      persistCurrentWebTools();
      renderWebTools();
    }
    const text = textarea.value.trim();
    if(!text && state.attachments.length===0) return;

    // If Web is enabled, we can either:
    // - persist sources as extracted text attachments (preferred when "webPreferAttachments" is on)
    // - or leave URLs in the prompt and let tool-calling handle it (ephemeral)
    let sendAtts = state.attachments;
    const hasUrlAtt = Array.isArray(state.attachments) && state.attachments.some(a=>a && a.type==='url' && a.url);
    if (state.webtools?.web && (state.ui.webPreferAttachments || hasUrlAtt)) {
      state.webFetchBusy = true;
      webToolsBtn?.classList.add('loading');
      syncSend();
      try {
        // When not preferring attachments, still convert explicit URL-attachments ("Add link") into text sources.
        const textForExtraction = state.ui.webPreferAttachments ? text : '';
        sendAtts = await buildSendAttachments(textForExtraction, state.attachments, {
          forceUrlAttachments: (!state.ui.webPreferAttachments && hasUrlAtt)
        });
      } finally {
        state.webFetchBusy = false;
        webToolsBtn?.classList.remove('loading');
        renderWebTools();
        syncSend();
      }
    }

    const userMsg = {
      role:'user',
      content:text,
      created_at: now(),
      attachments: (sendAtts || []).map(a=>({
        type:a.type,
        name:a.name,
        url:a.url,
        data_url:a.data_url,
        mime:a.mime,
        size:a.size,
        file_id:a.file_id,
        text:a.text,
        truncated: a.truncated,
        not_sent: a.not_sent,
        note: a.note,
        format: a.format,
        rag_document_id: a.rag_document_id,
        rag_chunks: a.rag_chunks,
        rag_embedding_model: a.rag_embedding_model,
        rag_state: a.rag_state,
        rag_job_id: a.rag_job_id,
        rag_error: a.rag_error
      }))
    };
    state.currentChat.messages = state.currentChat.messages || [];
    state.currentChat.messages.push(userMsg);
    state.currentChat.messages.push({role:'assistant', content:'', reasoning:'', activity:[], activity_total:0, activity_collapsed:false, created_at: now(), model: state.ui.model, connection_id: state.ui.connectionId, incomplete:true, stopped:false});

    textarea.value=''; textarea.style.height='auto';
    state.attachments=[]; renderAttachments(); renderWebTools(); syncSend();
    renderMessages();

    await streamAssistantForChat(state.currentChat, { mode:'new', assistantIdx: state.currentChat.messages.length-1 });
  }

  // Import
  async function importJsonFiles(files, targetFolderId=null){
    const list = Array.from(files || []).filter(f=>f && (f.name||'').toLowerCase().endsWith('.json'));
    if (!list.length) { alert('Please select .json files.'); return; }

    // ---- Flexible import formats ----
    // In addition to our own JSON export, we accept:
    // 1) OpenAI JSON
    //    - {"messages":[{"role":"user","content":"..."}, ...]}
    //    - [{"role":"user","content":"..."}, ...]  (common on the web)
    // 2) OpenWebUI JSON (we import only the currently selected branch and drop side branches)
    //    - [{ title, chat:{ history:{ messages:{...}, currentId:"..." } ... } }, ...]

    const isObj = (x)=>x && typeof x==='object' && !Array.isArray(x);
    const isStr = (x)=>typeof x==='string';

    const openAiContentToString = (content)=>{
      if (content == null) return '';
      if (typeof content === 'string') return content;
      // OpenAI can be an array of parts (text/image/etc.)
      if (Array.isArray(content)) {
        let out = '';
        for (const part of content){
          if (!part) continue;
          if (typeof part === 'string') { out += part; continue; }
          if (isObj(part)){
            if (part.type === 'text' && typeof part.text === 'string') { out += part.text; continue; }
            if (part.type === 'input_text' && typeof part.text === 'string') { out += part.text; continue; }
            if (part.type === 'image_url') {
              const url = part.image_url?.url || part.url || '';
              out += (out && !out.endsWith('\n') ? '\n' : '') + (url ? `[image] ${url}` : '[image]');
              continue;
            }
          }
          try{ out += (out && !out.endsWith('\n') ? '\n' : '') + JSON.stringify(part); }catch(_){ out += String(part); }
        }
        return out;
      }
      // Fallback
      try{ return JSON.stringify(content); }catch(_){ return String(content); }
    };

    // Decode HTML entities (OpenWebUI stores reasoning blocks with &gt; / &quot; etc.)
    const decodeHtml = (s)=>{
      if (s == null) return '';
      if (typeof s !== 'string') s = String(s);
      try{
        if (typeof document === 'undefined') return s;
        const ta = document.createElement('textarea');
        ta.innerHTML = s;
        return ta.value;
      }catch(_){
        return s;
      }
    };

    // OpenWebUI puts CoT into an HTML <details type="reasoning">...</details> block
    // and appends the final answer after it. Split that into {reasoning, content}.
    const splitOpenWebUiReasoning = (raw)=>{
      const s = (raw == null) ? '' : String(raw);
      const m = s.match(/<details\b[^>]*\btype=["']reasoning["'][^>]*>/i);
      if (!m || m.index == null) return { content: decodeHtml(s), reasoning: '' };

      const start = m.index;
      const closeIdx = s.toLowerCase().indexOf('</details>', start);
      if (closeIdx < 0) return { content: decodeHtml(s), reasoning: '' };

      const detailsHtml = s.slice(start, closeIdx + 10);
      const after = s.slice(closeIdx + 10);

      let reasoning = '';
      try{
        if (typeof document !== 'undefined'){
          const wrap = document.createElement('div');
          wrap.innerHTML = detailsHtml;
          const det = wrap.querySelector('details');
          if (det){
            const sum = det.querySelector('summary');
            if (sum) sum.remove();
            reasoning = (det.textContent || '').trim();
          } else {
            reasoning = (wrap.textContent || '').trim();
          }
        } else {
          reasoning = decodeHtml(detailsHtml)
            .replace(/<[^>]+>/g,'')
            .trim();
        }
      }catch(_){
        reasoning = decodeHtml(detailsHtml)
          .replace(/<[^>]+>/g,'')
          .trim();
      }

      const content = decodeHtml(after).replace(/^\s+/, '');
      return { content, reasoning };
    };

    const looksLikeMsg = (m)=>isObj(m) && isStr(m.role) && ('content' in m);
    const looksLikeOpenAiMessagesArray = (arr)=>Array.isArray(arr) && arr.length && arr.every(looksLikeMsg);

    const normalizeMessages = (msgs)=>{
      if (!Array.isArray(msgs)) return [];
      return msgs
        .filter(m=>isObj(m) && isStr(m.role))
        .map(m=>{
          const mm = {...m};
          mm.role = String(mm.role);
          // Our renderer expects a string. If it's structured, flatten it.
          mm.content = openAiContentToString(mm.content);
          // Try to align timestamps to our ms epoch convention.
          if (typeof mm.created_at === 'number') {
            // keep as-is
          } else if (typeof mm.timestamp === 'number') {
            mm.created_at = mm.timestamp > 2e12 ? mm.timestamp : Math.round(mm.timestamp * 1000);
          }
          return mm;
        });
    };

    const extractOpenWebUiChats = (obj, fallbackTitle)=>{
      const items = Array.isArray(obj) ? obj : [obj];
      const out = [];
      for (const it of items){
        if (!isObj(it)) continue;
        const chatRoot = it.chat || it;
        const hist = chatRoot?.history;
        const hmsgs = hist?.messages;
        const currentId = hist?.currentId;

        let branch = [];
        if (isObj(hmsgs) && currentId && hmsgs[currentId]) {
          // Walk parent pointers from currentId back to root.
          const seen = new Set();
          let cid = currentId;
          while (cid && hmsgs[cid] && !seen.has(cid)){
            seen.add(cid);
            branch.push(hmsgs[cid]);
            cid = hmsgs[cid].parentId;
          }
          branch.reverse();
        } else if (Array.isArray(chatRoot?.messages) && chatRoot.messages.length) {
          // Some OpenWebUI exports also include a flattened messages array. Use it as fallback.
          branch = chatRoot.messages;
        }

        const messages = branch
          .filter(m=>isObj(m) && isStr(m.role))
          .map(m=>{
            const role = String(m.role);

            // OpenWebUI can embed reasoning + final answer into `content`.
            // If a separate field exists, prefer it.
            let content = openAiContentToString(m.content);
            let reasoning = '';

            if (role === 'assistant'){
              if (isStr(m.reasoning) && m.reasoning.trim()){
                reasoning = decodeHtml(m.reasoning).trim();
                content = decodeHtml(content);
              } else {
                const split = splitOpenWebUiReasoning(content);
                content = split.content;
                reasoning = split.reasoning;
              }
            } else {
              content = decodeHtml(content);
            }

            return {
              role,
              content,
              reasoning,
              created_at: typeof m.timestamp === 'number' ? Math.round(m.timestamp*1000) : (typeof m.created_at==='number' ? m.created_at : now()),
              // Keep model info if present (optional)
              model: m.modelName || m.model || undefined
            };
          });

        if (!messages.length) continue;

        const title = String(it.title || chatRoot.title || fallbackTitle || 'Imported chat');
        const model = (Array.isArray(chatRoot.models) && chatRoot.models[0]) ? String(chatRoot.models[0]) : '';
        const params = isObj(chatRoot.params) ? chatRoot.params : {};

        out.push({
          title,
          model,
          messages,
          meta: { params }
        });
      }
      return out;
    };

    const normalizeToChats = (obj, filename)=>{
      const fallbackTitle = (filename||'Imported chat').replace(/\.json$/i,'');

      // Our own batch export: {chats:[...]}
      if (isObj(obj) && Array.isArray(obj.chats)) {
        return obj.chats
          .filter(c=>isObj(c) && Array.isArray(c.messages))
          .map(c=>({ ...c, title: String(c.title||fallbackTitle), messages: normalizeMessages(c.messages) }));
      }

      // Our own single wrapper: {chat:{...}}
      if (isObj(obj) && isObj(obj.chat)) {
        const c = obj.chat;
        if (Array.isArray(c.messages)) return [{ ...c, title: String(c.title||fallbackTitle), messages: normalizeMessages(c.messages) }];
      }

      // OpenWebUI (typically an array with chat/history)
      if (Array.isArray(obj) && obj.length && isObj(obj[0]) && (obj[0].chat || (obj[0].history && obj[0].history.messages))) {
        const chats = extractOpenWebUiChats(obj, fallbackTitle);
        if (chats.length) return chats;
      }
      if (isObj(obj) && (obj.chat || (obj.history && obj.history.messages))) {
        const chats = extractOpenWebUiChats(obj, fallbackTitle);
        if (chats.length) return chats;
      }

      // OpenAI JSON: array of messages
      if (looksLikeOpenAiMessagesArray(obj)) {
        return [{ title: fallbackTitle, messages: normalizeMessages(obj) }];
      }

      // OpenAI JSON: object with messages
      if (isObj(obj) && Array.isArray(obj.messages) && looksLikeOpenAiMessagesArray(obj.messages)) {
        return [{ title: String(obj.title||fallbackTitle), ...obj, messages: normalizeMessages(obj.messages) }];
      }

      // Our own direct chat object
      if (isObj(obj) && Array.isArray(obj.messages)) {
        return [{ ...obj, title: String(obj.title||fallbackTitle), messages: normalizeMessages(obj.messages) }];
      }

      // File might be an array of chat objects (rare)
      if (Array.isArray(obj) && obj.length && isObj(obj[0]) && Array.isArray(obj[0].messages)) {
        return obj
          .filter(c=>isObj(c) && Array.isArray(c.messages))
          .map(c=>({ ...c, title: String(c.title||fallbackTitle), messages: normalizeMessages(c.messages) }));
      }

      return [];
    };

    const chats = [];
    const failed = [];
    for (const f of list){
      let obj;
      try{ obj = JSON.parse(await f.text()); }catch(_){ failed.push(`${f.name}: invalid JSON`); continue; }

      const chatsFromFile = normalizeToChats(obj, f.name);
      if (!chatsFromFile.length) {
        failed.push(`${f.name}: no valid chat/format detected`);
        continue;
      }
      for (const chat of chatsFromFile){
        if (!chat || !isObj(chat) || !Array.isArray(chat.messages) || !chat.messages.length) {
          failed.push(`${f.name}: Chat ohne Messages`);
          continue;
        }
        if (!chat.title || !String(chat.title).trim()) chat.title = (f.name||'Imported chat').replace(/\.json$/i,'');
        chat.messages = normalizeMessages(chat.messages);
        chats.push(chat);
      }
    }

    if (!chats.length){
      alert(failed.length ? failed.join('\n') : 'Nichts zu importieren.');
      return;
    }

    // Batch import when possible.
    let res;
    try{
      res = await api('chat_import', chats.length===1
        ? {chat: chats[0], folder_id: targetFolderId}
        : {chats, folder_id: targetFolderId}
      );
    } catch(err){
      alert('Import fehlgeschlagen: ' + (err?.message||String(err)));
      return;
    }

    const ids = (res && Array.isArray(res.ids)) ? res.ids : (res && res.id ? [res.id] : []);
    await init();
    if (ids[0]) await openChat(ids[0]);

    if (failed.length){
      alert(`Importiert: ${ids.length}\n\nProbleme:\n` + failed.join('\n'));
    }
  }

  function openImport(){
    const inp=document.createElement('input');
    inp.type='file';
    inp.accept='.json,application/json';
    inp.multiple=true;
    inp.addEventListener('change', async ()=>{
      if(!inp.files?.length) return;
      await importJsonFiles(inp.files, null);
    });
    inp.click();
  }

  // Refresh models (aggregated across all enabled connections)
  async function refreshModels(){
    try{
      const r = await api('models');
      state.models = r.models || state.models;
      renderModels();
      renderAgentCompactModelOptions();
      renderAgentSupervisorModelOptions();
      renderModelCapabilityControl();
      syncRouterEventStream();
      syncCurrentModelContext();
      // If Pricing's picker is open, refresh its list too (without touching chat selection).
      try{ if (pricingModelModal && pricingModelModal.classList.contains('open')) renderPricingModelPickerList(); }catch(_){ }
    }catch(_){}
  }

  // ---------- Init ----------
  async function init(){
    try{
      const b = await api('bootstrap');
      if (b && b.logged_in===false){
        if (typeof window.llcSetAuthState==='function') window.llcSetAuthState(b.auth || {});
        if (typeof window.llcShowLogin==='function') window.llcShowLogin(b?.auth?.initial_admin_setup_required ? '' : 'Please sign in');
        return;
      }
      state.user = b.user || null;
      initLocalLightAI(b.locallightai || null);
      state.folders = b.folders || [];
      state.chats = b.chats || [];
      state.templates = b.templates || [];
      state.connections = b.connections || [];
      state.perms.canCreateConnections = !!b.can_create_connections;
      state.perms.inheritGlobalConnections = !!b.inherit_global_connections;
      state.perms.inheritGlobalWeb = !!b.inherit_global_web;
      state.perms.inheritGlobalSearch = !!b.inherit_global_search;
      state.perms.inheritGlobalImage = !!b.inherit_global_image;
      state.perms.inheritGlobalVoice = !!b.inherit_global_voice;
      state.ui.connectionId = b.selected_connection_id || state.ui.connectionId || '';
      state.models = b.models || [];
      state.ui.modelCapabilityOverrides = (b.model_capability_overrides && typeof b.model_capability_overrides === 'object') ? b.model_capability_overrides : {};
      state.ui.model = b.selected_model || state.ui.model || '';
      state.defaults.systemPrompt = b.system_prompt || '';
      state.ui.systemPrompt = state.defaults.systemPrompt;
      if(systemPromptEl) systemPromptEl.value = state.ui.systemPrompt || '';
      renderTemplatesMenu();
      
// General (global) settings
state.ui.toolSimpleMaxIters = normalizeToolRoundLimit(b.tool_simple_max_iters ?? state.ui.toolSimpleMaxIters ?? 20, 20);
state.ui.toolAgenticMaxIters = normalizeToolRoundLimit(b.tool_agentic_max_iters ?? state.ui.toolAgenticMaxIters ?? 200, 200);
state.ui.agentActivityMode = normalizeAgentActivityMode(b.agent_activity_mode ?? state.ui.agentActivityMode ?? 'tail');
state.ui.agentActivityMaxTokens = normalizeAgentActivityMaxTokens(b.agent_activity_max_tokens ?? state.ui.agentActivityMaxTokens ?? 1000, 1000);
state.ui.agentCompactAboveTokens = normalizeAgentCompactAboveTokens(b.agent_compact_above_tokens ?? state.ui.agentCompactAboveTokens ?? 100000, 100000);
state.ui.agentCompactKeepToolRounds = normalizeAgentCompactKeepToolRounds(b.agent_compact_keep_tool_rounds ?? state.ui.agentCompactKeepToolRounds ?? 6, 6);
state.ui.agentCompactEmergencyEnabled = (b.agent_compact_emergency_enabled == null) ? false : (Number(b.agent_compact_emergency_enabled) !== 0);
state.ui.agentCompactModelKey = String(b.agent_compact_model_key || state.ui.agentCompactModelKey || '__current__');
state.ui.agentCompactReasoningNone = (b.agent_compact_reasoning_none == null) ? true : (Number(b.agent_compact_reasoning_none) !== 0);
state.ui.agentSupervisorEveryToolCalls = normalizeAgentSupervisorEveryToolCalls(b.agent_supervisor_every_tool_calls ?? state.ui.agentSupervisorEveryToolCalls ?? 0, 0);
state.ui.agentSupervisorModelKey = String(b.agent_supervisor_model_key || state.ui.agentSupervisorModelKey || '__current__');
if (settingToolSimpleMaxIters) settingToolSimpleMaxIters.value = String(state.ui.toolSimpleMaxIters);
if (settingToolAgenticMaxIters) settingToolAgenticMaxIters.value = String(state.ui.toolAgenticMaxIters);
if (settingAgentActivityMode) settingAgentActivityMode.value = state.ui.agentActivityMode;
if (settingAgentActivityMaxTokens) settingAgentActivityMaxTokens.value = String(state.ui.agentActivityMaxTokens);
if (settingAgentCompactAboveTokens) settingAgentCompactAboveTokens.value = String(state.ui.agentCompactAboveTokens);
if (settingAgentCompactKeepToolRounds) settingAgentCompactKeepToolRounds.value = String(state.ui.agentCompactKeepToolRounds);
if (settingAgentCompactEmergencyEnabled) settingAgentCompactEmergencyEnabled.checked = !!state.ui.agentCompactEmergencyEnabled;
if (settingAgentCompactReasoningNone) settingAgentCompactReasoningNone.checked = !!state.ui.agentCompactReasoningNone;
if (settingAgentSupervisorEveryToolCalls) settingAgentSupervisorEveryToolCalls.value = String(state.ui.agentSupervisorEveryToolCalls);
renderAgentCompactModelOptions();
renderAgentSupervisorModelOptions();
state.ui.uploadHardLimitMb = normalizeMbLimit(b.upload_hard_limit_mb ?? state.ui.uploadHardLimitMb ?? 50, 50, 1, 1024);
state.ui.mediaImageInlineLimitMb = normalizeMbLimit(b.media_image_inline_limit_mb ?? state.ui.mediaImageInlineLimitMb ?? 8, 8, 0, 1024);
state.ui.mediaAudioInlineLimitMb = normalizeMbLimit(b.media_audio_inline_limit_mb ?? state.ui.mediaAudioInlineLimitMb ?? 15, 15, 0, 1024);
state.ui.pdfMemorySaving = (b.pdf_memory_saving == null) ? false : (Number(b.pdf_memory_saving) !== 0);
if (settingUploadHardLimitMb) settingUploadHardLimitMb.value = String(state.ui.uploadHardLimitMb);
if (settingMediaImageInlineLimitMb) settingMediaImageInlineLimitMb.value = String(state.ui.mediaImageInlineLimitMb);
if (settingMediaAudioInlineLimitMb) settingMediaAudioInlineLimitMb.value = String(state.ui.mediaAudioInlineLimitMb);
if (settingPdfMemorySaving) settingPdfMemorySaving.checked = !!state.ui.pdfMemorySaving;
renderGeneralSettingsUI();

// RAG settings (URL-driven infrastructure; activation/default are personal)
state.ui.ragAvailable = (b.rag_available == null) ? false : (Number(b.rag_available) !== 0);
state.ui.ragAutoEnable = (b.rag_auto_enable == null) ? false : (Number(b.rag_auto_enable) !== 0);
state.ui.ragUrl = String(b.rag_url || '');
state.ui.ragTopK = normalizeRagTopK(b.rag_top_k ?? state.ui.ragTopK ?? 8);
state.ui.ragTimeoutSec = normalizeRagTimeout(b.rag_timeout_sec ?? state.ui.ragTimeoutSec ?? 180);
state.ui.ragDefaultMode = normalizeRagMode(b.rag_default_mode ?? state.ui.ragDefaultMode ?? 'hybrid', 'hybrid');
if (settingRagAutoEnable) settingRagAutoEnable.checked = !!state.ui.ragAutoEnable;
if (settingRagUrl) settingRagUrl.value = state.ui.ragUrl;
if (settingRagTopK) settingRagTopK.value = String(state.ui.ragTopK);
if (settingRagTimeoutSec) settingRagTimeoutSec.value = String(state.ui.ragTimeoutSec);
if (settingRagDefaultMode) settingRagDefaultMode.value = state.ui.ragDefaultMode;
renderRagSettingsUI();

// Web settings
state.ui.webAutoEnable = (b.web_auto_enable == null) ? false : (Number(b.web_auto_enable) !== 0);
if (settingWebAutoEnable) settingWebAutoEnable.checked = !!state.ui.webAutoEnable;

state.ui.webSearchAutoEnable = (b.web_search_auto_enable == null) ? false : (Number(b.web_search_auto_enable) !== 0);
if (settingWebSearchAutoEnable) settingWebSearchAutoEnable.checked = !!state.ui.webSearchAutoEnable;

state.ui.webPreferAttachments = (b.web_prefer_attachments == null) ? false : (Number(b.web_prefer_attachments) !== 0);
if (settingWebPreferAtt) settingWebPreferAtt.checked = !!state.ui.webPreferAttachments;

state.ui.mediaImageInline = (b.media_image_inline == null) ? true : (Number(b.media_image_inline) !== 0);
if (settingMediaImageInline) settingMediaImageInline.checked = !!state.ui.mediaImageInline;

state.ui.mediaAudioInline = (b.media_audio_inline == null) ? false : (Number(b.media_audio_inline) !== 0);
if (settingMediaAudioInline) settingMediaAudioInline.checked = !!state.ui.mediaAudioInline;

state.ui.webAllowPrivate = (b.web_allow_private == null) ? false : (Number(b.web_allow_private) !== 0);
if (settingWebAllowPrivate) settingWebAllowPrivate.checked = !!state.ui.webAllowPrivate;

state.ui.webFetchMaxChars = normalizeWebLimit(b.web_fetch_max_chars ?? state.ui.webFetchMaxChars ?? 50000, 50000);
if (settingWebFetchMaxChars) settingWebFetchMaxChars.value = String(state.ui.webFetchMaxChars);

state.ui.webToolMaxChars = normalizeWebLimit(b.web_tool_max_chars ?? state.ui.webToolMaxChars ?? 60000, 60000);
if (settingWebToolMaxChars) settingWebToolMaxChars.value = String(state.ui.webToolMaxChars);

renderWebSettingsUI();

// Search settings
state.ui.searchProvider = String(b.search_provider || state.ui.searchProvider || 'serper');
state.ui.serperApiKey = String(b.serper_api_key || '');
state.ui.braveApiKey = String(b.brave_api_key || '');
state.ui.exaApiKey = String(b.exa_api_key || '');
state.ui.searchCustomUrl = String(b.search_custom_url || '');
state.ui.searchCustomNewsUrl = String(b.search_custom_news_url || '');
state.ui.searchCustomAllowPrivate = (b.search_custom_allow_private == null) ? false : (Number(b.search_custom_allow_private) !== 0);
state.ui.searchCustomApiKey = String(b.search_custom_api_key || '');
state.ui.searchNgxUrl = String(b.searchngx_url || '');
state.ui.searchNgxAllowPrivate = (b.searchngx_allow_private == null) ? false : (Number(b.searchngx_allow_private) !== 0);
state.ui.searchNgxApiKey = String(b.searchngx_api_key || '');
state.ui.searchGl = String(b.search_gl || 'us');
state.ui.searchHl = String(b.search_hl || 'en');
const sn = parseInt(String(b.search_num ?? state.ui.searchNum ?? 10), 10);
state.ui.searchNum = (Number.isFinite(sn) && sn>=1 && sn<=20) ? sn : 10;

if (settingSearchProvider) settingSearchProvider.value = state.ui.searchProvider;
if (settingSerperKey) settingSerperKey.value = state.ui.serperApiKey;
if (settingBraveKey) settingBraveKey.value = state.ui.braveApiKey;
if (settingExaKey) settingExaKey.value = state.ui.exaApiKey;
if (settingSearchCustomUrl) settingSearchCustomUrl.value = state.ui.searchCustomUrl;
if (settingSearchCustomNewsUrl) settingSearchCustomNewsUrl.value = state.ui.searchCustomNewsUrl;
if (settingSearchCustomAllowPrivate) settingSearchCustomAllowPrivate.checked = !!state.ui.searchCustomAllowPrivate;
if (settingSearchCustomKey) settingSearchCustomKey.value = state.ui.searchCustomApiKey;
if (settingSearchNgxUrl) settingSearchNgxUrl.value = state.ui.searchNgxUrl;
if (settingSearchNgxAllowPrivate) settingSearchNgxAllowPrivate.checked = !!state.ui.searchNgxAllowPrivate;
if (settingSearchNgxKey) settingSearchNgxKey.value = state.ui.searchNgxApiKey;
if (settingSearchGl) settingSearchGl.value = state.ui.searchGl;
if (settingSearchHl) settingSearchHl.value = state.ui.searchHl;
if (settingSearchNum) settingSearchNum.value = String(state.ui.searchNum);

renderSearchSettingsUI();


// Image settings
state.ui.imageProvider = String(b.image_provider || state.ui.imageProvider || 'openai');
state.ui.imageBaseUrl = String(b.image_base_url || state.ui.imageBaseUrl || 'https://api.openai.com/v1');
state.ui.imageApiKey = String(b.image_api_key || '');
state.ui.imageModel = String(b.image_model || state.ui.imageModel || 'gpt-image-2');
state.ui.imageOpenrouterBaseUrl = String(b.image_openrouter_base_url || state.ui.imageOpenrouterBaseUrl || 'https://openrouter.ai/api/v1');
state.ui.imageOpenrouterApiKey = String(b.image_openrouter_api_key || '');
state.ui.imageOpenrouterModel = String(b.image_openrouter_model || state.ui.imageOpenrouterModel || 'google/gemini-3-pro-image-preview');
state.ui.imageSdCppBaseUrl = String(b.image_sdcpp_base_url || state.ui.imageSdCppBaseUrl || 'http://127.0.0.1:1234/v1');
state.ui.imageSdCppApiKey = String(b.image_sdcpp_api_key || '');
state.ui.imageSdCppModel = String(b.image_sdcpp_model || state.ui.imageSdCppModel || 'flux-2-klein-base-4b-Q8_0.gguf');
state.ui.imageSdCppNegativePrompt = String(b.image_sdcpp_negative_prompt || state.ui.imageSdCppNegativePrompt || '');
state.ui.imageSdCppWidth = (b.image_sdcpp_width == null) ? (state.ui.imageSdCppWidth ?? 512) : Number(b.image_sdcpp_width);
state.ui.imageSdCppHeight = (b.image_sdcpp_height == null) ? (state.ui.imageSdCppHeight ?? 512) : Number(b.image_sdcpp_height);
state.ui.imageSdCppBatch = (b.image_sdcpp_batch == null) ? (state.ui.imageSdCppBatch ?? 1) : Number(b.image_sdcpp_batch);
state.ui.imageSdCppSeed = (b.image_sdcpp_seed == null) ? (state.ui.imageSdCppSeed ?? -1) : Number(b.image_sdcpp_seed);
state.ui.imageSdCppSteps = (b.image_sdcpp_steps == null) ? (state.ui.imageSdCppSteps ?? 20) : Number(b.image_sdcpp_steps);
state.ui.imageSdCppCfgScale = (b.image_sdcpp_cfg_scale == null) ? (state.ui.imageSdCppCfgScale ?? 7) : Number(b.image_sdcpp_cfg_scale);
state.ui.imageSdCppGuidance = (b.image_sdcpp_guidance == null) ? (state.ui.imageSdCppGuidance ?? 3.5) : Number(b.image_sdcpp_guidance);
state.ui.imageSdCppSamplingMethod = String(b.image_sdcpp_sampling_method || state.ui.imageSdCppSamplingMethod || '');
state.ui.imageSdCppScheduler = String(b.image_sdcpp_scheduler || state.ui.imageSdCppScheduler || '');
state.ui.imageSdCppFlowShift = String(b.image_sdcpp_flow_shift || state.ui.imageSdCppFlowShift || '');
state.ui.imageSdCppExtraArgs = String(b.image_sdcpp_extra_args || state.ui.imageSdCppExtraArgs || '');
state.ui.imageSdCppTimeout = (b.image_sdcpp_timeout_sec == null) ? (state.ui.imageSdCppTimeout ?? 900) : Number(b.image_sdcpp_timeout_sec);
state.ui.imageSdCppAutoVaeTiling768 = (b.image_sdcpp_auto_vae_tiling_768 == null) ? (state.ui.imageSdCppAutoVaeTiling768 ?? true) : (Number(b.image_sdcpp_auto_vae_tiling_768) !== 0);
state.ui.imageAutoEnable = (b.image_auto_enable == null) ? false : (Number(b.image_auto_enable) !== 0);
state.ui.imageSize = String(b.image_size || state.ui.imageSize || 'auto');
state.ui.imageQuality = String(b.image_quality || state.ui.imageQuality || 'auto');
state.ui.imageBackground = String(b.image_background || state.ui.imageBackground || 'auto');
state.ui.imageOutputFormat = String(b.image_output_format || state.ui.imageOutputFormat || 'png');

state.ui.visionAutoAttachLastImage = (b.vision_auto_attach_last_image == null) ? true : (Number(b.vision_auto_attach_last_image) !== 0);
state.ui.customToolsJson = String(b.custom_tools_json || '[]');
state.ui.customTools = Array.isArray(b.custom_tools) ? b.custom_tools : [];
state.ui.customToolsAutoEnable = (b.custom_tools_auto_enable == null) ? false : (Number(b.custom_tools_auto_enable) !== 0);
if (settingCustomToolsAutoEnable) settingCustomToolsAutoEnable.checked = !!state.ui.customToolsAutoEnable;
renderCustomToolsSettingsUI();
state.ui.mcpServersJson = String(b.mcp_servers_json || '[]');
state.ui.mcpServers = Array.isArray(b.mcp_servers) ? b.mcp_servers : [];
state.ui.mcpServersAutoEnable = (b.mcp_servers_auto_enable == null) ? false : (Number(b.mcp_servers_auto_enable) !== 0);
state.ui.mcpContextMode = String(b.mcp_context_mode || 'externalize') === 'externalize' ? 'externalize' : 'full';
state.ui.mcpExternalizeAboveTokens = mcpClamp(b.mcp_externalize_above_tokens, 500, 200000, 6000);
state.ui.mcpPreviewMaxTokens = mcpClamp(b.mcp_preview_max_tokens, 200, 50000, 2500);
state.ui.mcpFullFirstPassMaxTokens = mcpClamp(b.mcp_full_first_pass_max_tokens, 0, 200000, 32000);
if (settingMcpServersAutoEnable) settingMcpServersAutoEnable.checked = !!state.ui.mcpServersAutoEnable;
renderMcpSettingsUI();

// ComfyUI image settings
state.ui.imageComfyUrl = String(b.image_comfyui_url || state.ui.imageComfyUrl || '');
state.ui.imageComfyWorkflow = String(b.image_comfyui_workflow_json || state.ui.imageComfyWorkflow || '');
state.ui.imageComfyBindings = String(b.image_comfyui_bindings_json || state.ui.imageComfyBindings || '');
state.ui.imageComfySeed = (b.image_comfyui_seed == null) ? (state.ui.imageComfySeed ?? -1) : Number(b.image_comfyui_seed);
state.ui.imageComfySteps = (b.image_comfyui_steps == null) ? (state.ui.imageComfySteps ?? 20) : Number(b.image_comfyui_steps);
state.ui.imageComfyGuidance = (b.image_comfyui_guidance == null) ? (state.ui.imageComfyGuidance ?? 3.5) : Number(b.image_comfyui_guidance);
state.ui.imageComfyWidth = (b.image_comfyui_width == null) ? (state.ui.imageComfyWidth ?? 512) : Number(b.image_comfyui_width);
state.ui.imageComfyHeight = (b.image_comfyui_height == null) ? (state.ui.imageComfyHeight ?? 512) : Number(b.image_comfyui_height);
state.ui.imageComfyBatch = (b.image_comfyui_batch == null) ? (state.ui.imageComfyBatch ?? 1) : Number(b.image_comfyui_batch);
state.ui.imageComfyTimeout = (b.image_comfyui_timeout_sec == null) ? (state.ui.imageComfyTimeout ?? 900) : Number(b.image_comfyui_timeout_sec);
state.ui.imageComfyApplyDefaults = (b.image_comfyui_apply_defaults == null) ? (state.ui.imageComfyApplyDefaults ?? false) : (Number(b.image_comfyui_apply_defaults) !== 0);

let comfyProfilesLoaded = [];
try {
  const parsed = JSON.parse(String(b.image_comfyui_profiles_json || '[]'));
  if (Array.isArray(parsed)) comfyProfilesLoaded = parsed;
} catch(_){ }
state.ui.imageComfyProfiles = comfyProfilesLoaded;
state.ui.imageComfyProfileId = String(b.image_comfyui_profile_id || '');
ensureComfyProfiles();
syncComfyStateFromActiveProfile();

state.ui.imageEditComfyUrl = String(b.image_edit_comfyui_url || state.ui.imageEditComfyUrl || '');
state.ui.imageEditComfyWorkflow = String(b.image_edit_comfyui_workflow_json || state.ui.imageEditComfyWorkflow || '');
state.ui.imageEditComfyBindings = String(b.image_edit_comfyui_bindings_json || state.ui.imageEditComfyBindings || '');
state.ui.imageEditComfySeed = (b.image_edit_comfyui_seed == null) ? (state.ui.imageEditComfySeed ?? -1) : Number(b.image_edit_comfyui_seed);
state.ui.imageEditComfySteps = (b.image_edit_comfyui_steps == null) ? (state.ui.imageEditComfySteps ?? 20) : Number(b.image_edit_comfyui_steps);
state.ui.imageEditComfyGuidance = (b.image_edit_comfyui_guidance == null) ? (state.ui.imageEditComfyGuidance ?? 3.5) : Number(b.image_edit_comfyui_guidance);
state.ui.imageEditComfyWidth = (b.image_edit_comfyui_width == null) ? (state.ui.imageEditComfyWidth ?? 1024) : Number(b.image_edit_comfyui_width);
state.ui.imageEditComfyHeight = (b.image_edit_comfyui_height == null) ? (state.ui.imageEditComfyHeight ?? 1024) : Number(b.image_edit_comfyui_height);
state.ui.imageEditComfyBatch = (b.image_edit_comfyui_batch == null) ? (state.ui.imageEditComfyBatch ?? 1) : Number(b.image_edit_comfyui_batch);
state.ui.imageEditComfyMegapixels = (b.image_edit_comfyui_megapixels == null) ? (state.ui.imageEditComfyMegapixels ?? 1) : Number(b.image_edit_comfyui_megapixels);
state.ui.imageEditComfyTimeout = (b.image_edit_comfyui_timeout_sec == null) ? (state.ui.imageEditComfyTimeout ?? 900) : Number(b.image_edit_comfyui_timeout_sec);
state.ui.imageEditComfyApplyDefaults = (b.image_edit_comfyui_apply_defaults == null) ? (state.ui.imageEditComfyApplyDefaults ?? false) : (Number(b.image_edit_comfyui_apply_defaults) !== 0);
let imageEditComfyProfilesLoaded = [];
try {
  const parsed = JSON.parse(String(b.image_edit_comfyui_profiles_json || '[]'));
  if (Array.isArray(parsed)) imageEditComfyProfilesLoaded = parsed;
} catch(_) { }
state.ui.imageEditComfyProfiles = imageEditComfyProfilesLoaded;
state.ui.imageEditComfyProfileId = String(b.image_edit_comfyui_profile_id || '');
ensureImageEditComfyProfiles();
syncImageEditComfyStateFromActiveProfile();

renderImageSettingsUI();

      // Voice settings
      state.ui.voiceApiKey = String(b.voice_api_key || '');
      state.ui.voiceAutoEnable = (b.voice_auto_enable == null) ? false : (Number(b.voice_auto_enable) !== 0);
      state.ui.voiceAutoSend = (b.voice_auto_send == null) ? true : (Number(b.voice_auto_send) !== 0);

      // Read-aloud (TTS) settings
      state.ui.voiceTtsProvider = String(b.voice_tts_provider || state.ui.voiceTtsProvider || 'browser');
      state.ui.voiceTtsModel = String(b.voice_tts_model || state.ui.voiceTtsModel || 'gpt-4o-mini-tts');
      if (state.ui.voiceTtsModel !== 'gpt-4o-mini-tts') state.ui.voiceTtsModel = 'gpt-4o-mini-tts';
      state.ui.voiceTtsVoice = String(b.voice_tts_voice || state.ui.voiceTtsVoice || 'marin');

      if (settingVoiceApiKey) settingVoiceApiKey.value = state.ui.voiceApiKey;
      if (settingVoiceAutoEnable) settingVoiceAutoEnable.checked = !!state.ui.voiceAutoEnable;
      if (settingVoiceAutoSend) settingVoiceAutoSend.checked = !!state.ui.voiceAutoSend;
      if (settingVoiceTtsProvider) settingVoiceTtsProvider.value = state.ui.voiceTtsProvider;
      if (settingVoiceTtsModel) settingVoiceTtsModel.value = state.ui.voiceTtsModel;
      if (settingVoiceTtsVoice) settingVoiceTtsVoice.value = state.ui.voiceTtsVoice;

      renderVoiceSettingsUI();
      renderVoiceUI();

      // Pricing settings
      state.ui.pricing = Array.isArray(b.pricing) ? b.pricing : (state.ui.pricing || []);


// Default composer toggle (chat-specific override will be applied in openChat).
      state.webtools.web = !!state.ui.webAutoEnable;
      state.webtools.search = !!state.ui.webSearchAutoEnable;
      state.webtools.rag = !!state.ui.ragAvailable && !!state.ui.ragAutoEnable;
      state.webtools.rag_mode = 'default';
      state.webtools.image = !!state.ui.imageAutoEnable;
        state.webtools.document = false;
        state.webtools.code_workspace = false;
        state.webtools.workspace_id = '';
        state.webtools.workspace_name = '';
        state.webtools.workspace_access = 'write';
        state.webtools.workspace_strategy = 'efficient';
        state.webtools.workspace_offer_download = true;
        state.webtools.custom_tools = defaultCustomToolNames();
        state.webtools.mcp_servers = defaultMcpServerIds();
      renderWebTools();
      if(state.ui.model) modelBtn.firstChild.textContent = headerModelText() + ' ';
      renderModels();
      renderModelCapabilityControl();
      syncRouterEventStream();
      syncCurrentModelContext();
      renderSidebar();
      renderMessages();
      syncSend();

      // Refresh /models in the background (never block UI if a provider is offline)
      refreshModels();

      const last = localStorage.getItem('last_chat_id');
      const id = last && state.chats.find(c=>c.id===last) ? last : (state.chats[0]?.id || null);
      if(id) await openChat(id);
    }catch(err){
      chatMsgs.innerHTML = `<div class="muted" style="padding:24px 0; text-align:center;">Backend unreachable: ${esc(err.message)}</div>`;
    }
  }

  setupLogin();
  initParams();
  init();
});
