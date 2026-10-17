#!/usr/bin/env python3
"""Offline source-level assertions (not a substitute for macOS acceptance tests)."""
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
code = (ROOT / 'launcher' / 'LocalLightChat.swift').read_text()
config = (ROOT / 'web' / 'config.php').read_text()
script = (ROOT / 'build_app.sh').read_text()
assert 'Contents' in code and 'Helpers' in code and 'Resources' in code
assert 'Application Support' not in code or '.applicationSupportDirectory' in code
assert '.applicationSupportDirectory' in code
assert 'NSStatusBar' in code
assert 'applicationDockMenu' in code and 'applicationShouldHandleReopen' in code
assert 'NSWindow' not in code and 'showControlWindow' not in code
assert 'CFBundleIconFile' in script and 'LocalLightChat.icns' in script
assert (ROOT / 'assets' / 'LocalLightChat.icns').exists()
assert 'location ^~ /uploads/' in code and 'alias \\(uploads)' in code
assert 'LLC_DATA_DIR' in code and 'LLC_MCP_TOKEN' in code
assert 'NSWorkspace.shared.open' in code
assert 'pkill -' not in code
# Full RAG template is bundled; the launcher instantiates it under Application Support.
rag_template = (ROOT / 'resources' / 'config' / 'ragd.conf.template').read_text()
for key in ('listen', 'port', 'db', 'llama_url', 'embedding_model',
            'chunk_chars', 'chunk_max_chars', 'chunk_overlap',
            'embedding_batch', 'default_top_k', 'max_top_k',
            'hybrid_dense_k', 'hybrid_bm25_k', 'hybrid_rrf_k',
            'reranker_enabled', 'reranker_url', 'reranker_model',
            'reranker_max_bytes', 'max_request_bytes'):
    assert re.search(rf'^\s*{key}=', rag_template, re.MULTILINE), key
assert '__LLC_RAG_DB_PATH__' in rag_template
assert 'try ensureRAGConfig()' in code
assert 'ragd.conf.before-full-config.bak' in code
assert 'resources/config/ragd.conf.template' in script
assert 'mcp-server.json' in code and 'ragd.conf' in code
assert 'LLC_REQUIRE_INITIAL_ADMIN_PASSWORD' in config
assert 'LLC_PRECONFIGURED_MCP_TOKEN' in config
assert 'if [ "$IDENTITY" = \'-\' ]' in script
assert 'codesign --force --sign' in script
assert 'check_macho' in script and 'APP_ARCH=' in script and 'BUILD_ARCHS' in script
assert not (ROOT / 'web' / 'data' / 'locallightchat.sqlite').exists()
print('Source checks: OK')
