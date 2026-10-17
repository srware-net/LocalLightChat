# LocalLightChat

**Portable. Fast. Yours.**\
**The ultimate lightweight UI for AI chat, RAG and agents.**

Use local models, cloud APIs or both. Keep huge chats manageable, search your history, work with files and documents, add RAG, or give an agent a shell and workspace — without turning the frontend into a heavyweight stack.

`<1s` cold start · `500k+` context · `<60MB` download · `100%` portable

Website: https://www.locallightai.com/llc/

## What it does

### Chat that can get big

- Folder-based chat organization and management
- Full-text search across your chat history
- **Compress & Clone** for large conversations while preserving decision-critical context
- Documents and editable artifacts with version history
- Attachments including PDF, images, CSV, YAML, XML, logs and more
- URL sources and text notes
- Markdown, Mermaid, Math/TeX and syntax-highlighted code
- Templates, automatic chat naming, cloning, import and export

### Give the model tools

- MCP server management with per-chat activation and support for remote MCP servers
- Native MCP agent stack with workspace-scoped filesystem tools
- Process and shell execution
- Persistent interactive terminal sessions
- Persistent code workspaces
- Optional Windows desktop tools for window management, screen capture and keyboard input
- Configurable agentic tool-call rounds and context compaction
- Large MCP results can be externalized as artifacts and selectively inspected later with artifact info, search and read tools instead of repeatedly filling the model context

### RAG without the heavyweight stack

- Dedicated `ragd` service included in the project
- Reusable file library with RAG state
- Dense, hybrid and precise retrieval modes
- Hybrid retrieval combines vector search with BM25
- Configurable chunking, retrieval depth and optional reranking
- OpenAI-compatible embedding endpoint support
- RAG can be enabled globally or per chat

### Search, images, voice and model control

- Built-in web search and fetch tools with configurable search providers
- Image generation through OpenAI-compatible APIs, OpenRouter, stable-diffusion.cpp or ComfyUI bindings
- Image editing through supported ComfyUI workflows
- Voice transcription and text-to-speech
- Local and cloud model connections through OpenAI-compatible APIs
- Multiple connection profiles with custom headers and model prefixes
- Advanced generation controls including temperature, sampling, DRY and Mirostat
- Configurable model pricing and usage information
- Role-based users: superadmin, admin and user

## Download

Ready-to-use portable packages are available from GitHub Releases:

https://github.com/srware-net/LocalLightChat/releases

The repository contains packaging for:

- Windows
- Linux x64
- Linux ARM64
- macOS

## Docker

Prebuilt image:

```text
srwarenet/locallightchat:latest
```

Docker Hub:

https://hub.docker.com/r/srwarenet/locallightchat

Run locally:

```bash
docker run -d \
  --name locallightchat \
  -p 127.0.0.1:8181:80 \
  -p 127.0.0.1:8182:443 \
  -v locallightchat:/var/lib/locallightchat \
  --restart unless-stopped \
  srwarenet/locallightchat:latest
```

Open:

```text
http://127.0.0.1:8181
```

HTTPS is also available on:

```text
https://127.0.0.1:8182
```

The included certificate is self-signed, so a browser warning is expected.

Stop and remove the container:

```bash
docker stop locallightchat
docker rm locallightchat
```

## Docker Compose / source build

The Docker setup runs nginx, PHP-FPM, MCP/Agent and optional RAG services in a single container and persists application data, uploads, temporary files and agent workspaces in Docker volumes.

Before building from the repository, copy the application files into `docker/public/` and provide the matching `ragd` and `mcp_server` binaries in `docker/native/<arch>/` as indicated by the placeholder files.

Then:

```bash
cd docker
cp .env.example .env
docker compose up -d --build
```

Default URLs:

```text
http://127.0.0.1:8181/
https://127.0.0.1:8182/
```

By default Docker binds only to `127.0.0.1`. Change the `LLC_HTTP_BIND` and `LLC_HTTPS_BIND` values in `.env` if you intentionally want LAN access.

RAG is disabled in the default Docker configuration until an embedding endpoint is configured in `docker/config/ragd.conf`. The MCP server starts with the container and uses a persistent workspace volume.

More Docker details: [`docker/README_DOCKER.md`](docker/README_DOCKER.md)

## Self-hosted

Use this if you want to deploy LocalLightChat on your own web stack.

Requires:

- nginx or a similar web server
- PHP 8.x
- SQLite

Upload the contents of:

```text
www/
```

to your web server document root, for example:

```text
htdocs/
public_html/
www/
```

Usually you should upload the contents of `www/`, not the folder itself.

Agent and RAG features require their corresponding services in addition to the web application.

## Import from OpenWebUI

The included v4 converter can migrate an OpenWebUI SQLite database to the current LocalLightChat schema.

It supports chats, folders, messages, file metadata, image/audio attachments and optional alternate message branches as cloned chats. API keys, login credentials, sessions and provider secrets are deliberately not copied.

Basic usage:

```bash
python converter/convert_openwebui_to_locallightchat_v4.py openwebui.db
```

For media migration and advanced options, see:

[`converter/README_openwebui_to_locallightchat_v4.md`](converter/README_openwebui_to_locallightchat_v4.md)

## Project structure

```text
LocalLightChat/
├─ www/          Web application
├─ mcp/          MCP gateway, configurator and native tool server
├─ ragd/         RAG service
├─ docker/       Docker image and Compose setup
├─ packages/     Portable platform packages
├─ converter/    OpenWebUI migration tool
├─ LISENSE
└─ README.md
```

## License

Apache License 2.0. See [`LISENSE`](LISENSE).
